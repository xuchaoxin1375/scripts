# -*- coding: utf-8 -*-
"""邮箱转发目标与 zone 路由状态路由。"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from .. import deps, engine_adapter
from ..auth import require_auth
from ..schemas import EmailRoutingAddressBody, EmailRoutingCompleteBody
from ..services import email_routing
from ..services.accounts import lookup_accounts
from ..services.zones import resolve_zone

router = APIRouter(dependencies=[Depends(require_auth)])


def _updater(account: dict[str, Any]) -> Any:
    return engine_adapter.build_updater(
        account,
        proxy_pool=deps.get_proxy_pool(),
    )


@router.get("/api/v1/email-routing/addresses")
def addresses(account: str, email: str = "") -> dict[str, Any]:
    """账号级目标地址；email 可选，用于返回单条目标的验证状态。"""
    matched = lookup_accounts([account])
    try:
        updater = _updater(matched[0])
        items = email_routing.list_addresses(updater)
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    target = email_routing.find_address(items, email) if email else None
    return {
        "account": account,
        "total": len(items),
        "items": items,
        "target": target,
    }


@router.get("/api/v1/email-routing/status")
def status(account: str, zone: str) -> dict[str, Any]:
    """zone 的路由开关、catch-all、所需记录与 MX 冲突。"""
    matched = lookup_accounts([account])
    zone_id, zone_name = resolve_zone(matched[0], zone)
    try:
        updater = _updater(matched[0])
        data = email_routing.zone_status(updater, zone_id, zone_name)
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    data["account"] = account
    return data


@router.post("/api/v1/email-routing/addresses")
def add_address(payload: EmailRoutingAddressBody) -> dict[str, Any]:
    """添加目标地址；新地址会触发 Cloudflare 验证邮件。"""
    matched = lookup_accounts([payload.account])
    try:
        updater = _updater(matched[0])
        result = email_routing.add_address(updater, payload.email)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    result["account"] = payload.account
    return result


@router.post("/api/v1/email-routing/complete")
def complete(payload: EmailRoutingCompleteBody) -> dict[str, Any]:
    """目标邮箱验证通过后，启用路由并设置 catch-all。"""
    matched = lookup_accounts([payload.account])
    zone_id, zone_name = resolve_zone(matched[0], payload.zone)
    try:
        updater = _updater(matched[0])
        result = email_routing.complete(updater, zone_id, zone_name, payload.email)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    result["account"] = payload.account
    result["zone"] = zone_name
    return result
