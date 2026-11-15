# -*- coding: utf-8 -*-
"""历史与审计查询路由。"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from .. import db
from ..auth import require_auth

router = APIRouter(dependencies=[Depends(require_auth)])


@router.get("/api/v1/history")
def history(limit: int = 50, offset: int = 0) -> dict[str, Any]:
    limit = max(1, min(200, limit))
    offset = max(0, offset)
    try:
        return {
            "items": db.list_history(limit, offset),
            "total": db.count_history(),
            "limit": limit,
            "offset": offset,
        }
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.get("/api/v1/audit")
def audit(limit: int = 50, offset: int = 0) -> dict[str, Any]:
    limit = max(1, min(200, limit))
    offset = max(0, offset)
    try:
        return {
            "items": db.list_audit(limit, offset),
            "total": db.count_audit(),
            "limit": limit,
            "offset": offset,
        }
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=str(exc)) from exc
