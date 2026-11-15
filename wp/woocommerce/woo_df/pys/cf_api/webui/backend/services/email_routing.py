# -*- coding: utf-8 -*-
"""邮箱转发（Cloudflare Email Routing）编排。

目标地址是账号级资源：先添加并验证，验证通过后才允许对 zone 启用路由并
设置 catch-all。这里不复制引擎的 HTTP 细节，只组合适配层与引擎方法。
"""

from __future__ import annotations

import re
from typing import Any, Optional

from .. import engine_adapter

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def normalize_email(raw: str) -> str:
    """校验并归一化目标邮箱；空值或格式错误抛 ValueError。"""
    email = (raw or "").strip()
    if not email:
        raise ValueError("请输入目标邮箱")
    if len(email) > 254 or ".." in email or not _EMAIL_RE.match(email):
        raise ValueError("目标邮箱格式不正确")
    return email.lower()


def list_addresses(updater: Any) -> list[dict[str, Any]]:
    """读取账号下所有目标地址（已按适配层归一化）。"""
    return engine_adapter.list_email_routing_addresses(updater)


def find_address(items: list[dict[str, Any]], email: str) -> Optional[dict[str, Any]]:
    """在目标地址列表中按邮箱精确查找（忽略大小写）。"""
    target = (email or "").strip().lower()
    if not target:
        return None
    for item in items:
        if str(item.get("email", "")).strip().lower() == target:
            return item
    return None


def add_address(updater: Any, email: str) -> dict[str, Any]:
    """确保目标地址存在；新地址会触发 Cloudflare 验证邮件。"""
    target = normalize_email(email)
    items = list_addresses(updater)
    existing = find_address(items, target)
    if existing is not None:
        verified = bool(existing.get("verified"))
        return {
            "email": target,
            "found": True,
            "verified": verified,
            "created": False,
            "message": (
                "目标邮箱已验证，可以直接完成 catch-all 配置。"
                if verified
                else "目标邮箱已添加但尚未验证；请到收件箱（含垃圾箱）点击验证链接后刷新状态。"
            ),
        }
    try:
        updater.create_email_routing_address(target)
    except Exception as exc:  # noqa: BLE001
        # 并发创建时可能已被另一端添加；重读一次再判断，避免误报。
        try:
            items = list_addresses(updater)
            existing = find_address(items, target)
        except engine_adapter.EngineError:
            existing = None
        if existing is not None:
            return {
                "email": target,
                "found": True,
                "verified": bool(existing.get("verified")),
                "created": False,
                "message": "目标邮箱已存在；请检查验证状态。",
            }
        raise engine_adapter.EngineError(f"添加目标邮箱失败: {exc}") from exc
    try:
        items = list_addresses(updater)
        created = find_address(items, target)
    except engine_adapter.EngineError:
        created = None
    return {
        "email": target,
        "found": created is not None,
        "verified": bool(created.get("verified")) if created else False,
        "created": True,
        "message": (
            "已添加目标邮箱，Cloudflare 已发送验证邮件；"
            "请到收件箱（含垃圾箱）点击验证链接，然后刷新状态。"
        ),
    }


def _zone_data(updater: Any, zone_id: str) -> dict[str, Any]:
    raw = updater.get_zone(zone_id)
    if isinstance(raw, dict):
        result = raw.get("result", raw)
        if isinstance(result, dict):
            return result
    return {}


def _required_records(updater: Any, zone_id: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for record in updater.get_email_routing_required_records(zone_id):
        if not isinstance(record, dict):
            continue
        rows.append(
            {
                "type": str(record.get("type", "")),
                "name": str(record.get("name", "")),
                "content": str(record.get("content", "")),
                "priority": record.get("priority"),
            }
        )
    return rows


def zone_status(updater: Any, zone_id: str, zone_name: str) -> dict[str, Any]:
    """汇总 zone 的邮箱路由状态、catch-all 与现有 MX 冲突。"""
    try:
        zone = _zone_data(updater, zone_id)
    except Exception as exc:  # noqa: BLE001
        raise engine_adapter.EngineError(f"读取域名状态失败: {exc}") from exc
    settings = updater.get_email_routing_settings(zone_id)
    catch_all = engine_adapter.get_email_routing_catch_all(updater, zone_id)
    records_error = ""
    required: list[dict[str, Any]] = []
    try:
        required = _required_records(updater, zone_id)
    except Exception as exc:  # noqa: BLE001
        records_error = str(exc)
    mx_records: list[dict[str, Any]] = []
    try:
        for record in updater.get_dns_records(zone_id, "MX"):
            if not isinstance(record, dict):
                continue
            mx_records.append(
                {
                    "name": str(record.get("name", "")),
                    "content": str(record.get("content", "")),
                    "priority": record.get("priority"),
                }
            )
    except Exception as exc:  # noqa: BLE001
        records_error = records_error or str(exc)
    non_cloudflare_mx = [
        item["content"]
        for item in mx_records
        if "mx.cloudflare.net" not in str(item.get("content", "")).lower()
    ]
    return {
        "zone": zone_name,
        "zone_id": zone_id,
        "zone_status": str(zone.get("status", "")),
        "routing_enabled": bool(settings.get("enabled")),
        "catch_all": catch_all,
        "required_records": required,
        "mx_records": mx_records,
        "non_cloudflare_mx": non_cloudflare_mx,
        "records_error": records_error,
    }


def complete(updater: Any, zone_id: str, zone_name: str, email: str) -> dict[str, Any]:
    """验证通过后启用路由并设置 catch-all（幂等）。"""
    target = normalize_email(email)
    items = list_addresses(updater)
    address = find_address(items, target)
    if address is None:
        raise ValueError("目标邮箱尚未添加；请先添加并完成验证")
    if not bool(address.get("verified")):
        raise ValueError(
            "目标邮箱尚未验证；请到收件箱点击 Cloudflare 验证链接后刷新状态"
        )
    try:
        zone = _zone_data(updater, zone_id)
    except Exception as exc:  # noqa: BLE001
        raise engine_adapter.EngineError(f"读取域名状态失败: {exc}") from exc
    zone_state = str(zone.get("status", ""))
    if zone_state != "active":
        raise ValueError(
            f"域名状态为 {zone_state or '未知'}；Email Routing 要求 zone 为 active"
        )
    try:
        status, message, records = updater.configure_email_routing(
            zone_id, zone_name, target
        )
    except Exception as exc:  # noqa: BLE001
        raise engine_adapter.EngineError(f"配置邮箱路由失败: {exc}") from exc
    if status == "error":
        raise engine_adapter.EngineError(message or "配置邮箱路由失败")
    if status == "pending_verification":
        raise ValueError(message or "目标邮箱尚未验证")
    return {"email": target, "status": status, "message": message, "records": records}
