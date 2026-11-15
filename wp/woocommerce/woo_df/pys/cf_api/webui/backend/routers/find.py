# -*- coding: utf-8 -*-
"""跨账号查找域名（对应 CLI -f）。"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from .. import deps, engine_adapter
from ..auth import require_auth

router = APIRouter(dependencies=[Depends(require_auth)])


@router.get("/api/v1/find")
def find_domain(domain: str) -> dict[str, Any]:
    eng = engine_adapter.engine()
    target = (eng.get_main_domain_name_from_str(domain) or domain.strip()).lower()
    if not target:
        raise HTTPException(status_code=400, detail="域名无效")
    try:
        accounts = deps.get_accounts()
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    found: list[dict[str, Any]] = []
    for account in accounts:
        name = account.get("name") or account.get("email") or "unknown"
        try:
            updater = engine_adapter.build_updater(account)
            if not updater.zone_exists(target):
                continue
            zone = updater.get_zone_by_name(target) or {}
            info: dict[str, Any] = {
                "account": name,
                "zone": zone.get("name", target),
                "zone_id": zone.get("id", ""),
                "status": zone.get("status", ""),
            }
            zid = zone.get("id", "")
            if zid:
                try:
                    info["record_count"] = len(updater.get_dns_records(zid, "ALL"))
                except Exception:
                    info["record_count"] = "?"
            found.append(info)
        except Exception as exc:  # noqa: BLE001 - 单账号失败不中断全账号查找
            found.append({"account": name, "error": str(exc)})
    return {
        "domain": target,
        "found": len([f for f in found if "error" not in f]),
        "results": found,
    }
