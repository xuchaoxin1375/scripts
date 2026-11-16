# -*- coding: utf-8 -*-
"""记录读取缓存、名称归一化与导入预检。"""

from __future__ import annotations

import time
from threading import Lock
from typing import Any, Optional

from .. import engine_adapter
from ..validate import validate_single_record

# 排序/筛选/翻页不应反复向 Cloudflare 拉取同一 zone 的全量记录。
# 缓存只驻内存，写入与任务结束由调用方失效；显式刷新可绕过。
_CACHE_TTL = 30.0
_cache: dict[tuple[str, str, str], tuple[float, list[dict[str, Any]]]] = {}
_lock = Lock()


def _account_key(account: dict[str, Any]) -> str:
    return str(account.get("name") or account.get("email") or "unknown")


def load_records(
    account: dict[str, Any],
    zone_id: str,
    record_type: str = "ALL",
    *,
    refresh: bool = False,
) -> list[dict[str, Any]]:
    """读取 zone 记录；30 秒内命中缓存，失败不缓存。"""
    key = (_account_key(account), str(zone_id), (record_type or "ALL").upper())
    if not refresh:
        with _lock:
            hit = _cache.get(key)
            if hit is not None and time.monotonic() - hit[0] < _CACHE_TTL:
                return [dict(item) for item in hit[1]]
    records = engine_adapter.get_records(account, zone_id, record_type)
    with _lock:
        _cache[key] = (time.monotonic(), [dict(item) for item in records])
    return records


def invalidate(
    account: Optional[dict[str, Any]] = None,
    zone_id: Optional[str] = None,
) -> None:
    """失效指定账号/域名的缓存；不传账号时清空全部。"""
    if account is None:
        with _lock:
            _cache.clear()
        return
    account_key = _account_key(account)
    wanted_zone = str(zone_id) if zone_id is not None else None
    with _lock:
        for key in list(_cache):
            if key[0] != account_key:
                continue
            if wanted_zone is not None and key[1] != wanted_zone:
                continue
            _cache.pop(key, None)


def canon_name(name: str, zone_name: str) -> str:
    """写路径名称归一化为完整域名。

    编辑器按参考稿使用短名（`@` 表根域名）；接口写入统一转完整域名，
    与读取路径的原始格式一致，避免改名语义漂移。
    """
    short = (name or "").strip()
    zone = (zone_name or "").strip()
    if not short or short == "@":
        return zone
    if not zone:
        return short
    low, zlow = short.lower(), zone.lower()
    if low == zlow or low.endswith("." + zlow):
        return short
    if "." not in short:
        return f"{short}.{zone}"
    return short


def import_item_error(index: int, item: Any) -> Optional[str]:
    """导入/恢复条目的单条校验；返回错误文本或 None。"""
    name = (item.name or "").strip()
    if not name:
        return f"第{index}条：名称必填"
    err = validate_single_record(
        {
            "type": (item.type or "").upper().strip(),
            "content": item.content,
            "proxied": bool(item.proxied),
            "ttl": int(item.ttl or 1),
            "comment": item.comment or "",
            "priority": item.priority,
        }
    )
    return f"第{index}条：{err}" if err else None
