# -*- coding: utf-8 -*-
"""meta / accounts 路由。"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends

from .. import deps, engine_adapter
from ..auth import require_auth
from ..services.accounts import accounts_payload
from ..services.proxy import proxy_payload

router = APIRouter(dependencies=[Depends(require_auth)])


def _meta() -> dict[str, Any]:
    eng = engine_adapter.engine()
    dirs = deps.default_dirs()
    proxy = proxy_payload()
    return {
        "version": str(getattr(eng, "VERSION", "")),
        "speed_presets": dict(getattr(eng, "SPEED_PRESETS", {})),
        "defaults": {
            "dry_run": True,
            "record_type": "auto",
            "speed": "eco",
            "scope": "account",
            "max_retries": int(getattr(eng, "DEFAULT_API_MAX_RETRIES", 5)),
            "export_fmt": "json",
        },
        "dirs": dirs,
        "requires_auth": bool(deps.get_password()),
        "config_path": deps.get_config_path(),
        "proxy": {
            "mode": proxy["mode"],
            "count": proxy["count"],
            "total": proxy["total"],
            "enabled": proxy["enabled"],
            "enabled_count": proxy["enabled_count"],
        },
    }


@router.get("/api/v1/meta")
def meta_v1() -> dict[str, Any]:
    return _meta()


@router.get("/api/meta")
def meta_compat() -> dict[str, Any]:
    return _meta()


@router.get("/api/v1/accounts")
def accounts_v1() -> dict[str, Any]:
    return accounts_payload()


@router.get("/api/accounts")
def accounts_compat() -> dict[str, Any]:
    return {"accounts": accounts_payload()["items"]}
