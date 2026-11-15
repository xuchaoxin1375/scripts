# -*- coding: utf-8 -*-
"""引擎适配层：按文件路径加载 cloudflare_dns_tool.py，提供 Web 所需原语。

设计原则：
- 引擎文件保持不动，本层只做转接；引擎内 sys.exit 路径全部转换为 EngineError。
- 密钥永不原文返回界面层，一律经引擎 mask_secret 脱敏。
"""

from __future__ import annotations

import importlib.util
import os
import sys
from threading import Event, Lock
from typing import Any, Optional

ENGINE_FILENAME = "cloudflare_dns_tool.py"


class EngineError(Exception):
    """引擎调用失败（配置无效、认证失败、网络异常等）。"""


_engine_module: Any = None


def engine_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(os.path.dirname(here)), ENGINE_FILENAME)


def default_config_path() -> str:
    """Web/CLI 共用的账号配置文件预设（与引擎 CF_CONFIG_PATH 同源）。"""
    try:
        mod = engine()
        preset = str(getattr(mod, "CF_CONFIG_PATH", "") or "").strip()
        if preset:
            return preset
    except Exception:
        pass
    return os.getenv("CF_CONFIG_PATH", "").strip()


def engine() -> Any:
    """加载并缓存引擎模块。"""
    global _engine_module
    if _engine_module is None:
        path = engine_path()
        if not os.path.exists(path):
            raise EngineError(f"引擎文件不存在: {path}")
        spec = importlib.util.spec_from_file_location("cf_engine", path)
        if spec is None or spec.loader is None:
            raise EngineError("引擎模块加载失败")
        module = importlib.util.module_from_spec(spec)
        sys.modules["cf_engine"] = module
        spec.loader.exec_module(module)
        _engine_module = module
    return _engine_module


def get_engine() -> Any:
    """供 start_web_ui 复用：直接返回引擎模块（含 ProxyPool/校验函数）。"""
    return engine()


def get_accounts(config_path: str) -> list[dict]:
    """读取账号列表，失败抛 EngineError（不直接退出进程）。"""
    mod = engine()
    try:
        accounts = mod.get_cf_accounts(config_path)
    except SystemExit as exc:
        raise EngineError(f"配置文件无效或无可用账号: {config_path}") from exc
    if not accounts:
        raise EngineError(f"配置文件中没有可用账号: {config_path}")
    return accounts


def masked_accounts(accounts: list[dict]) -> list[dict[str, Any]]:
    """返回脱敏后的账号摘要，供界面展示（含 has_secret，不含原文）。"""
    mod = engine()
    rows: list[dict[str, Any]] = []
    for account in accounts:
        auth = account.get("auth_method", "")
        secret = account.get("token") or account.get("key") or ""
        rows.append(
            {
                "name": account.get("name") or account.get("email") or "unknown",
                "auth": auth,
                "email": account.get("email") or "不可用",
                "secret": mod.mask_secret(secret, show=False),
                "has_secret": bool(secret),
            }
        )
    return rows


def build_updater(
    account: dict,
    workers: int = 2,
    interval: float = 0.5,
    scope: str = "account",  # noqa: ARG001 - 作用域由调用方限速器体现，保持签名兼容
    max_retries: int = 5,
    proxy_pool: Any = None,
    stop_event: Optional[Event] = None,
    print_lock: Optional[Lock] = None,
) -> Any:
    """为单个账号构造引擎 updater（限速器按传入间隔创建）。"""
    mod = engine()
    stop = stop_event or Event()
    limiter = None
    if interval and interval > 0:
        limiter = mod.ApiRateLimiter(min_interval=interval, stop_event=stop)
    return mod.CloudflareDNSUpdater(
        auth_method=account["auth_method"],
        api_token=account.get("token"),
        api_email=account.get("email"),
        api_key=account.get("key"),
        max_workers=max(1, workers),
        print_lock=print_lock or Lock(),
        stop_event=stop,
        account_name=account.get("name") or account.get("email") or "unknown",
        rate_limiter=limiter,
        api_max_retries=max_retries,
        proxy_pool=proxy_pool,
    )


def get_zones(account: dict, **updater_kwargs: Any) -> list[dict]:
    """读取账号下所有 zone，失败抛 EngineError。"""
    updater = build_updater(account, **updater_kwargs)
    try:
        return updater.get_all_zones()
    except Exception as exc:
        raise EngineError(f"读取域名列表失败: {exc}") from exc


def get_records(
    account: dict, zone_id: str, record_type: str = "ALL", **updater_kwargs: Any
) -> list[dict]:
    """读取单个 zone 的 DNS 记录，失败抛 EngineError。"""
    updater = build_updater(account, **updater_kwargs)
    try:
        return updater.get_dns_records(zone_id, record_type or "ALL")
    except Exception as exc:
        raise EngineError(f"读取 DNS 记录失败: {exc}") from exc


def load_whitelist_strict(path: str) -> list[str]:
    """读取白名单文件，失败抛 EngineError（不直接退出进程）。"""
    mod = engine()
    try:
        return mod.load_whitelist(path)
    except SystemExit as exc:
        raise EngineError(f"白名单文件无效: {path}") from exc


def load_resume_entries_strict(path: str) -> list[tuple[str, str]]:
    """读取重跑清单，失败抛 EngineError（不直接退出进程）。"""
    mod = engine()
    try:
        return mod.load_resume_entries(path)
    except (FileNotFoundError, ValueError) as exc:
        raise EngineError(f"重跑清单无效: {exc}") from exc


def slim_record(record: dict) -> dict[str, Any]:
    """记录精简视图，供表格展示（含备注与 MX 优先级透传）。"""
    prio = record.get("priority", None)
    try:
        prio = int(prio) if prio is not None else None
    except (TypeError, ValueError):
        prio = None
    return {
        "id": record.get("id", ""),
        "type": record.get("type", ""),
        "name": record.get("name", ""),
        "content": record.get("content", ""),
        "ttl": record.get("ttl", 1),
        "proxied": bool(record.get("proxied", False)),
        "comment": str(record.get("comment") or ""),
        "priority": prio,
    }


def write_record_full(
    updater: Any, zone_id: str, record_id: str, payload: dict[str, Any]
) -> dict[str, Any]:
    """全量改写单条记录（含 comment/priority）。

    引擎 `update_dns_record` 的 payload 固定，不含 Cloudflare 新增字段；
    本函数经引擎传输层直发 PUT，引擎文件本身零改动。调用方须先完成校验。
    """
    allowed = {"type", "name", "content", "proxied", "ttl", "comment", "priority"}
    body = {k: v for k, v in payload.items() if k in allowed}
    if body.get("priority") is None:
        body.pop("priority", None)
    return updater._request(  # noqa: SLF001 - 适配层复用引擎传输能力
        "PUT", f"/zones/{zone_id}/dns_records/{record_id}", json=body
    )


def create_record_full(
    updater: Any, zone_id: str, payload: dict[str, Any]
) -> dict[str, Any]:
    """直建单条记录（含 comment/priority），返回 Cloudflare 原始结果。"""
    allowed = {"type", "name", "content", "proxied", "ttl", "comment", "priority"}
    body = {k: v for k, v in payload.items() if k in allowed}
    if body.get("priority") is None:
        body.pop("priority", None)
    if not str(body.get("comment") or ""):
        body.pop("comment", None)
    return updater._request(  # noqa: SLF001 - 适配层复用引擎传输能力
        "POST", f"/zones/{zone_id}/dns_records", json=body
    )


def list_email_routing_addresses(updater: Any) -> list[dict[str, Any]]:
    """读取账号级邮箱转发目标，分页取回并归一化验证状态。"""
    try:
        account_id = updater.get_account_id()
    except Exception as exc:  # noqa: BLE001 - 统一转成 Web 可展示错误
        raise EngineError(f"无法获取账号 ID: {exc}") from exc
    if not account_id:
        raise EngineError("无法获取账号 ID，不能读取邮箱转发目标")
    try:
        raw_items: list[Any] = []
        page = 1
        while True:
            data = updater._request(  # noqa: SLF001 - 适配层复用引擎传输能力
                "GET",
                f"/accounts/{account_id}/email/routing/addresses",
                params={"page": page, "per_page": 50},
            )
            batch = data.get("result", []) if isinstance(data, dict) else []
            if not isinstance(batch, list) or not batch:
                break
            raw_items.extend(batch)
            info = data.get("result_info", {}) if isinstance(data, dict) else {}
            if not isinstance(info, dict):
                info = {}
            total_pages = int(info.get("total_pages", 1) or 1)
            if page >= total_pages or page >= 4:
                break
            page += 1
    except Exception as exc:  # noqa: BLE001
        raise EngineError(f"读取邮箱转发目标失败: {exc}") from exc
    rows: list[dict[str, Any]] = []
    for item in raw_items:
        if isinstance(item, str):
            rows.append(
                {
                    "id": "",
                    "email": item,
                    "verified": False,
                    "created": "",
                    "modified": "",
                }
            )
            continue
        if not isinstance(item, dict):
            continue
        email = str(item.get("email") or "").strip()
        if not email:
            continue
        rows.append(
            {
                "id": str(item.get("id") or item.get("tag") or ""),
                "email": email,
                "verified": bool(item.get("verified")),
                "created": str(item.get("created") or ""),
                "modified": str(item.get("modified") or ""),
            }
        )
    return rows


def get_email_routing_catch_all(updater: Any, zone_id: str) -> dict[str, Any]:
    """读取 zone 的 catch-all 规则；未配置或无权读取时返回空状态。"""
    try:
        data = updater._request(  # noqa: SLF001 - 适配层复用引擎传输能力
            "GET", f"/zones/{zone_id}/email/routing/rules/catch_all"
        )
    except Exception:  # noqa: BLE001 - 未配置时 Cloudflare 可能返回 404
        return {"enabled": False, "forward_to": [], "name": ""}
    result = data.get("result", {}) if isinstance(data, dict) else {}
    if not isinstance(result, dict):
        return {"enabled": False, "forward_to": [], "name": ""}
    forward_to: list[str] = []
    for action in result.get("actions") or []:
        if not isinstance(action, dict) or action.get("type") != "forward":
            continue
        value = action.get("value")
        if isinstance(value, list):
            forward_to.extend(str(item) for item in value if item)
        elif isinstance(value, str) and value:
            forward_to.append(value)
    return {
        "enabled": bool(result.get("enabled")),
        "forward_to": forward_to,
        "name": str(result.get("name") or ""),
    }
