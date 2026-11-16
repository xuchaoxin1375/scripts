# -*- coding: utf-8 -*-
"""运行时出口代理配置（仅内存，不落盘）。"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from .. import db
from ..auth import require_auth
from ..schemas import ProxySettings
from ..services.proxy import apply_proxy_settings, proxy_payload

router = APIRouter(dependencies=[Depends(require_auth)])


@router.get("/api/v1/proxy")
def get_proxy() -> dict[str, Any]:
    """读取当前代理状态；URL 只返回脱敏后的 scheme://host:port。"""
    return proxy_payload()


@router.put("/api/v1/proxy")
def update_proxy(body: ProxySettings) -> dict[str, Any]:
    """保存代理列表、总开关与单项开关；proxies 为空时清空列表。"""
    try:
        payload = apply_proxy_settings(
            body.enabled,
            body.mode,
            [item.model_dump() for item in body.proxies],
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    try:
        if payload["total"] == 0:
            detail = "清空代理配置"
        elif payload["enabled"]:
            detail = (
                f"保存代理配置：总开关开，启用 "
                f"{payload['enabled_count']}/{payload['total']}，"
                f"模式 {payload['mode']}"
            )
        else:
            detail = (
                f"保存代理配置：总开关关，保存 {payload['total']} 个（未启用）"
            )
        db.audit("proxy_config", detail=detail)
    except Exception:
        pass
    return payload
