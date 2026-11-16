# -*- coding: utf-8 -*-
"""把引擎 CLI 日志行转换为 Web 可展示的结构化事件。

原则：
- 只解析已知前缀与关键汇总行；分隔线、空行、重复汇总等噪声直接丢弃。
- 未识别的行只有在明显是错误/警告时才进入时间线；其余保留在原始日志。
- 缩进行并入上一条事件详情，保留 dry-run 记录预览等上下文。
"""

from __future__ import annotations

import re
from typing import Any

SEPARATOR_RE = re.compile(r"^[=\-]{8,}$")
TAG_RE = re.compile(
    r"^\s*\[(?P<tag>[A-Z][A-Z0-9_-]*|zone|[\u4e00-\u9fff][^\]\s]*)\]\s*(?P<msg>.*)$"
)
KV_RE = re.compile(r"([A-Za-z_][\w-]*)=([^\s,，]+)")
KV_PART_RE = re.compile(r"^[A-Za-z_][\w-]*=\S+$")
ACCOUNT_RE = re.compile(r"(?:账号[：:]\s*|account=)([^\s,，]+)")
NAME_RE = re.compile(r"(?:^|[\s,，])name=([^\s,，]+)")
ZONE_RE = re.compile(r"(?:target_zone|zone|domain)=([^\s,，]+)")
ACCOUNT_DONE_RE = re.compile(r"^账号\s+(?P<account>[^\s,，]+)\s+完成[：:]\s*(?P<rest>.*)$")
ACCOUNT_DOMAINS_RE = re.compile(
    r"^账号\s+(?P<account>[^\s,，]+)\s+下共\s+(?P<count>\d+)\s+个域名"
)
BANNER_RE = re.compile(r"^Cloudflare DNS .+\|\s*账号[：:]\s*(?P<account>[^\s,，]+)")
VERDICT_RE = re.compile(r"^\[VERDICT\]\s*(?P<msg>.*)$")

DRY_TITLES = {
    "DRY-ADD-DOMAIN": "预演：添加域名",
    "DRY-ADD-RECORD": "预演：添加记录",
    "DRY-ATTRS": "预演：设置属性",
    "DRY-DEDUPE": "预演：同名收敛",
    "DRY-DELETE": "预演：删除记录",
    "DRY-DELETE-IP": "预演：删除指定 IP",
    "DRY-DELETE-ZONE": "预演：删除域名",
    "DRY-FULL": "预演：整域更新",
    "DRY-FULL-MIGRATE": "预演：整域迁移",
    "DRY-MIGRATE": "预演：记录迁移",
    "DRY-UPDATE": "预演：更新记录",
}

TAG_TITLES = {
    "CHECK": "检查账号",
    "FOUND": "找到域名",
    "MISS": "未找到",
    "INFO": "提示",
    "WARN": "警告",
    "ERR": "错误",
    "ERROR": "错误",
    "ACCOUNT-OK": "账号完成",
    "ACCOUNT-ERR": "账号失败",
    "ACCOUNT-CANCELLED": "账号取消",
    "JOB-ERR": "任务错误",
    "PROVISION": "配置向导",
    "BACKUP": "备份",
    "AUTO": "自动判断",
    "CREATE": "创建",
    "CREATE-FULL": "创建域名",
    "DNS": "DNS 操作",
    "MERGE": "同名收敛",
    "RETRY": "重试",
    "INTERRUPT": "中断",
    "zone": "域名处理",
    "SKIP-ADD": "跳过添加",
    "SKIP-CREATE": "跳过创建",
    "SKIP-FULL": "跳过整域",
    "OK-ADD": "添加完成",
    "OK-ATTRS": "属性设置完成",
    "OK-EXPORT": "导出完成",
    "OK-FULL": "整域更新完成",
    "OK-UPDATE": "更新完成",
    "ERR-ADD": "添加失败",
    "ERR-ATTRS": "属性设置失败",
    "ERR-EXPORT": "导出失败",
    "ERR-FULL": "整域更新失败",
    "ERR-FULL-CREATE": "整域创建失败",
    "ERR-FULL-DEDUPE": "整域收敛失败",
    "ERR-FULL-DEL": "整域删除失败",
}

ERROR_TAGS = {"ERR", "ERROR", "ACCOUNT-ERR", "JOB-ERR"}
WARNING_TAGS = {"WARN", "RETRY", "INTERRUPT", "ACCOUNT-CANCELLED"}
SUCCESS_TAGS = {"FOUND", "OK", "ACCOUNT-OK"}


def _level_for_tag(tag: str) -> str:
    if tag in ERROR_TAGS or tag.startswith("ERR-"):
        return "error"
    if tag in WARNING_TAGS or tag.startswith("SKIP-"):
        return "warning"
    if tag in SUCCESS_TAGS or tag.startswith("OK-"):
        return "success"
    return "info"


def _title_for_tag(tag: str) -> str:
    if tag in DRY_TITLES:
        return DRY_TITLES[tag]
    if tag.startswith("DRY-"):
        return "预演"
    if tag in TAG_TITLES:
        return TAG_TITLES[tag]
    if tag.startswith("ERR-"):
        return "失败"
    if tag.startswith("OK-"):
        return "完成"
    if tag.startswith("SKIP-"):
        return "跳过"
    return tag


def _split_message(message: str) -> tuple[str, str]:
    """把“标题: 详情”拆成两段；无冒号时整段作为标题。"""
    text = (message or "").strip()
    if not text:
        return "", ""
    for sep in ("：", ":"):
        if sep in text:
            title, detail = text.split(sep, 1)
            return title.strip(), detail.strip()
    return text, ""


def _extract_meta(text: str) -> dict[str, str]:
    meta: dict[str, str] = {}
    for key, value in KV_RE.findall(text or ""):
        if len(meta) >= 12:
            break
        meta[key] = value.rstrip(").,，;；")
    return meta


def _extract_account(text: str, tag: str = "") -> str:
    match = ACCOUNT_RE.search(text or "")
    if match:
        return match.group(1).strip()
    if tag in {"FOUND", "MISS", "CHECK"}:
        match = NAME_RE.search(f" {text}")
        if match:
            return match.group(1).strip()
    return ""


def _extract_zone(text: str) -> str:
    match = ZONE_RE.search(text or "")
    return match.group(1).strip() if match else ""


def _is_only_meta(text: str) -> bool:
    parts = [part.strip() for part in re.split(r"[,，]", text or "") if part.strip()]
    return bool(parts) and all(KV_PART_RE.match(part) for part in parts)


def _verdict_level(message: str) -> str:
    if "完美" in message or "全部成功" in message:
        return "success"
    if re.search(r"失败[：:]\s*[1-9]", message) or "存在失败" in message:
        return "error"
    if "部分" in message or "取消" in message:
        return "warning"
    return "info"


def _event(
    ts: str,
    level: str,
    title: str,
    detail: str = "",
    account: str = "",
    zone: str = "",
    meta: dict[str, str] | None = None,
) -> dict[str, Any]:
    return {
        "ts": ts,
        "level": level,
        "title": title[:200],
        "detail": detail[:800],
        "account": account,
        "zone": zone,
        "meta": meta or {},
    }


def parse_log_entries(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """把带时间戳的原始行转换为时间线事件。"""
    events: list[dict[str, Any]] = []
    for entry in entries:
        ts = str(entry.get("ts") or "")
        text = str(entry.get("text") or "")
        stripped = text.strip()
        if not stripped or SEPARATOR_RE.match(stripped):
            continue

        # 结论优先于普通标签解析。
        verdict = VERDICT_RE.match(stripped)
        if verdict:
            message = verdict.group("msg").strip()
            events.append(
                _event(
                    ts,
                    _verdict_level(message),
                    "结论",
                    message,
                )
            )
            continue

        # 账号完成汇总。
        done = ACCOUNT_DONE_RE.match(stripped)
        if done:
            account = done.group("account")
            rest = done.group("rest")
            meta = _extract_meta(rest)
            events.append(
                _event(
                    ts,
                    "success",
                    "账号完成",
                    "" if _is_only_meta(rest) else rest,
                    account=account,
                    meta=meta,
                )
            )
            continue

        # 任务横幅。
        banner = BANNER_RE.match(stripped)
        if banner:
            events.append(
                _event(
                    ts,
                    "info",
                    "任务开始",
                    stripped,
                    account=banner.group("account"),
                )
            )
            continue

        # 账号下域名数量。
        domains = ACCOUNT_DOMAINS_RE.match(stripped)
        if domains:
            count = domains.group("count")
            events.append(
                _event(
                    ts,
                    "info",
                    "账号域名",
                    f"共 {count} 个域名",
                    account=domains.group("account"),
                    meta={"domains": count},
                )
            )
            continue

        # 参数行并入上一条“任务开始”；没有上一条时单独成事件。
        if "," in stripped and _is_only_meta(stripped):
            meta = _extract_meta(stripped)
            if events and events[-1]["title"] == "任务开始":
                events[-1]["meta"].update(meta)
                if meta.get("target_zone"):
                    events[-1]["zone"] = meta["target_zone"]
            else:
                events.append(
                    _event(
                        ts,
                        "info",
                        "任务参数",
                        meta=meta,
                        zone=meta.get("target_zone", ""),
                    )
                )
            continue

        # 已知 [TAG] 行。
        tagged = TAG_RE.match(text)
        if tagged:
            tag = tagged.group("tag")
            message = tagged.group("msg").strip()
            level = _level_for_tag(tag)
            title = _title_for_tag(tag)
            detail = message
            if tag in {"INFO", "WARN", "ERR", "ERROR", "RETRY", "INTERRUPT"}:
                parsed_title, parsed_detail = _split_message(message)
                if parsed_title:
                    title = parsed_title
                    detail = parsed_detail
            if tag == "zone" and any(
                word in message for word in ("失败", "错误", "异常")
            ):
                level = "warning"
            meta = _extract_meta(message)
            if _is_only_meta(message):
                detail = ""
            account = _extract_account(message, tag)
            if not account and tag.startswith("ACCOUNT-"):
                account = re.split(r"[:：\s]", message, maxsplit=1)[0]
            zone = _extract_zone(message)
            if not zone and tag == "zone":
                zone = re.split(r"[\s,，]", message, maxsplit=1)[0]
            events.append(
                _event(
                    ts,
                    level,
                    title,
                    detail,
                    account=account,
                    zone=zone,
                    meta=meta,
                )
            )
            continue

        # 无标签的“标题: 详情”行，例如“对账: zones expected=1”。
        generic = re.match(
            r"^(?P<title>[^:=：]{2,60})[：:]\s*(?P<detail>.+)$", stripped
        )
        if generic and not stripped.lower().startswith(("http://", "https://")):
            title = generic.group("title").strip()
            detail = generic.group("detail").strip()
            level = (
                "warning"
                if any(word in stripped for word in ("失败", "错误", "异常"))
                else "info"
            )
            events.append(
                _event(
                    ts,
                    level,
                    title,
                    detail,
                    meta=_extract_meta(detail),
                )
            )
            continue

        # 缩进行/记录预览并入上一条事件详情。
        if text[:1].isspace() and events:
            previous = events[-1]
            previous["detail"] = (
                f"{previous['detail']}\n{stripped}"
                if previous["detail"]
                else stripped
            )[:800]
            continue

        # 未识别但明显异常的行。
        if any(word in stripped for word in ("失败", "错误", "异常")):
            events.append(_event(ts, "warning", "异常", stripped))
            continue

        # 其余噪声行留在原始日志，不进入时间线。
    return events
