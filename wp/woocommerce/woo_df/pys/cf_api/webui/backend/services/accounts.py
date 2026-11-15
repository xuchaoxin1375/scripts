# -*- coding: utf-8 -*-
"""账号查找与界面摘要。"""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException

from .. import deps, engine_adapter


def lookup_accounts(names: list[str]) -> list[dict]:
    """按名称查找账号；缺失账号返回 400，保持旧接口行为。"""
    accounts = deps.get_accounts()
    by_name = {(a.get("name") or a.get("email") or "unknown"): a for a in accounts}
    missing = [n for n in names if n not in by_name]
    if missing:
        raise HTTPException(status_code=400, detail=f"未知账号: {missing}")
    return [by_name[n] for n in names]


def accounts_payload() -> dict[str, Any]:
    """返回脱敏账号列表；配置读取失败映射为 502。"""
    try:
        accounts = deps.get_accounts()
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {"items": engine_adapter.masked_accounts(accounts)}
