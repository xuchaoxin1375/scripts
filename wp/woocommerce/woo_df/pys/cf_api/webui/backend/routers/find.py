# -*- coding: utf-8 -*-
"""跨账号查找域名（对应 CLI -f）。

v2 使用可轮询的后台扫描（进度/部分结果/取消）；旧 `/api/v1/find`
保留同步响应，供外部调用兼容。
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from .. import deps, engine_adapter
from ..auth import require_auth
from ..schemas import FindScanRequest
from ..services import find as find_service

router = APIRouter(dependencies=[Depends(require_auth)])


def _accounts_or_502() -> list[dict]:
    try:
        return deps.get_accounts()
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


def _target_or_400(domain: str) -> str:
    try:
        target = find_service.normalize_domain(domain)
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if not target:
        raise HTTPException(
            status_code=400,
            detail="域名无效：请填 Cloudflare zone 名（根域名），例如 example.com",
        )
    return target


def _speed_or_400(speed: str, max_retries: int) -> dict[str, Any]:
    try:
        return find_service.scan_speed(speed, max_retries)
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/api/v1/find/scans")
def start_find_scan(body: FindScanRequest) -> dict[str, Any]:
    """创建跨账号扫描，立即返回可轮询快照。"""
    target = _target_or_400(body.domain)
    accounts = _accounts_or_502()
    speed = _speed_or_400(body.speed, body.max_retries)
    scan = deps.get_find_manager().start(
        target,
        accounts,
        speed,
        deps.get_proxy_pool(),
        stop_on_first=body.stop_on_first,
    )
    return scan.snapshot()


@router.get("/api/v1/find/scans/{scan_id}")
def get_find_scan(scan_id: str) -> dict[str, Any]:
    """读取扫描进度与部分结果。"""
    scan = deps.get_find_manager().get(scan_id)
    if scan is None:
        raise HTTPException(status_code=404, detail=f"扫描不存在: {scan_id}")
    return scan.snapshot()


@router.post("/api/v1/find/scans/{scan_id}/cancel")
def cancel_find_scan(scan_id: str) -> dict[str, Any]:
    """请求取消扫描；已结束时返回 409。"""
    manager = deps.get_find_manager()
    scan = manager.get(scan_id)
    if scan is None:
        raise HTTPException(status_code=404, detail=f"扫描不存在: {scan_id}")
    if not scan.cancel():
        raise HTTPException(status_code=409, detail="扫描已结束，不能取消")
    return scan.snapshot()


@router.post("/api/v1/find/scans/{scan_id}/continue")
def continue_find_scan(scan_id: str) -> dict[str, Any]:
    """在命中即停或取消后，继续检查剩余未检查账号。"""
    accounts = _accounts_or_502()
    try:
        scan = deps.get_find_manager().continue_scan(
            scan_id,
            accounts,
            deps.get_proxy_pool(),
        )
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=f"扫描不存在: {scan_id}") from exc
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return scan.snapshot()


@router.get("/api/v1/find")
def find_domain(domain: str) -> dict[str, Any]:
    """旧同步接口：兼容保留，返回命中与覆盖统计。"""
    try:
        target = find_service.normalize_domain(domain)
    except engine_adapter.EngineError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if not target:
        return {
            "domain": str(domain or "").strip(),
            "found": 0,
            "checked": 0,
            "missed": 0,
            "failed": 0,
            "complete": False,
            "results": [],
            "errors": [
                {
                    "account": "",
                    "error": "域名无效：请填 Cloudflare zone 名（根域名），例如 example.com",
                }
            ],
        }
    accounts = _accounts_or_502()
    speed = _speed_or_400("eco", 5)
    return find_service.find_sync(
        target,
        accounts,
        speed,
        deps.get_proxy_pool(),
    )
