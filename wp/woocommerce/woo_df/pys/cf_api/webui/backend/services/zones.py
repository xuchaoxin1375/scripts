# -*- coding: utf-8 -*-
"""zone 解析与短 TTL 缓存。

Cloudflare 的 zone 列表在首屏会被账号切换、域名过滤、统计多处读取；
缓存 30 秒可减少重复 API 调用，创建/删除 zone 后由调用方失效。
"""

from __future__ import annotations

import time
from threading import Lock
from typing import Optional

from fastapi import HTTPException

from .. import engine_adapter

_CACHE_TTL = 30.0
_cache: dict[str, tuple[float, list[dict]]] = {}
_lock = Lock()


def _cache_key(account: dict) -> str:
    return str(account.get("name") or account.get("email") or "unknown")


def get_zones(account: dict) -> list[dict]:
    """读取账号 zone 列表；30 秒内命中缓存，失败不缓存。"""
    key = _cache_key(account)
    now = time.monotonic()
    with _lock:
        hit = _cache.get(key)
        if hit is not None and now - hit[0] < _CACHE_TTL:
            return list(hit[1])
    zones = engine_adapter.get_zones(account)
    with _lock:
        _cache[key] = (time.monotonic(), list(zones))
    return list(zones)


def invalidate(account: Optional[str] = None) -> None:
    """失效单个账号或全部 zone 缓存。"""
    with _lock:
        if account is None:
            _cache.clear()
        else:
            _cache.pop(account, None)


def resolve_zone(account: dict, zone: str) -> tuple[str, str]:
    """在账号内按域名精确匹配 zone；不存在返回 404。"""
    try:
        all_zones = get_zones(account)
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    for item in all_zones:
        if str(item.get("name", "")).lower() == zone.strip().lower():
            return str(item.get("id", "")), str(item.get("name", zone))
    raise HTTPException(status_code=404, detail=f"域名不在该账号中: {zone}")
