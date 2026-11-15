# -*- coding: utf-8 -*-
"""zone 列表、CSV 与激活检查路由。"""

from __future__ import annotations

import csv
import io
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response

from .. import engine_adapter
from ..auth import require_auth
from ..common import paginate
from ..services.accounts import lookup_accounts
from ..services.zones import get_zones, resolve_zone

router = APIRouter(dependencies=[Depends(require_auth)])


@router.get("/api/v1/zones")
def zones(
    account: str,
    filter: str = "",  # noqa: A002 - 与历史查询参数名保持兼容
    status: str = "all",
    page: int = 1,
    per_page: int = 50,
) -> dict[str, Any]:
    matched = lookup_accounts([account])
    try:
        all_zones = get_zones(matched[0])
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    keyword = (filter or "").strip().lower()
    want_status = (status or "all").strip().lower()
    rows = [
        {
            "name": z.get("name", ""),
            "status": z.get("status", ""),
            "id": z.get("id", ""),
        }
        for z in all_zones
        if keyword in str(z.get("name", "")).lower()
        and (want_status == "all" or str(z.get("status", "")) == want_status)
    ]
    data = paginate(rows, page, per_page)
    data.update({"account": account})
    return data


@router.get("/api/v1/zones.csv")
def zones_csv(
    account: str,
    filter: str = "",  # noqa: A002 - 与 zones 查询同名保持一致
    status: str = "all",
) -> Response:
    matched = lookup_accounts([account])
    try:
        all_zones = get_zones(matched[0])
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    keyword = (filter or "").strip().lower()
    want_status = (status or "all").strip().lower()
    eng = engine_adapter.engine()
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=list(eng.ZONES_CSV_FIELDNAMES))
    writer.writeheader()
    count = 0
    for z in all_zones:
        if keyword and keyword not in str(z.get("name", "")).lower():
            continue
        if want_status != "all" and str(z.get("status", "")) != want_status:
            continue
        writer.writerow(
            {
                "account": account,
                "name": z.get("name", ""),
                "status": z.get("status", ""),
                "zone_id": z.get("id", ""),
                "nameservers": ";".join(z.get("name_servers") or []),
            }
        )
        count += 1
        if count >= 5000:
            break
    return Response(
        content="\ufeff" + buf.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f"attachment; filename=zones_{account}.csv"},
    )


@router.post("/api/v1/zones/activation-check")
def activation_check(payload: dict[str, Any]) -> dict[str, Any]:
    account = str(payload.get("account", ""))
    zone = str(payload.get("zone", ""))
    matched = lookup_accounts([account])
    zone_id, zone_name = resolve_zone(matched[0], zone)
    try:
        updater = engine_adapter.build_updater(matched[0])
        updater.trigger_activation_check(zone_id)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"催激活失败: {exc}") from exc
    return {"account": account, "zone": zone_name, "triggered": True}
