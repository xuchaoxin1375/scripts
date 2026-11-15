# -*- coding: utf-8 -*-
"""文件上传：白名单、重跑清单预览与落盘。"""

from __future__ import annotations

import csv
import io
import os
import tempfile
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile

from .. import engine_adapter
from ..auth import require_auth

router = APIRouter(dependencies=[Depends(require_auth)])


@router.post("/api/v1/whitelist-upload")
async def whitelist_upload(file: UploadFile) -> dict[str, Any]:
    data = await file.read()
    if len(data) > 2 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="文件过大（上限 2MB）")
    handle = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        handle.write(data)
    finally:
        handle.close()
    try:
        domains = engine_adapter.load_whitelist_strict(handle.name)
    except engine_adapter.EngineError as exc:
        try:
            os.unlink(handle.name)
        except OSError:
            pass
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"path": handle.name, "count": len(domains), "domains": domains[:200]}


@router.post("/api/v1/resume-preview")
async def resume_preview(request: Request) -> dict[str, Any]:
    data = await request.body()
    if len(data) > 2 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="文件过大（上限 2MB）")
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise HTTPException(status_code=400, detail=f"清单解码失败: {exc}") from exc
    reader = csv.DictReader(io.StringIO(text))
    if reader.fieldnames is None:
        raise HTTPException(status_code=400, detail="清单为空")
    lowered = {str(n or "").strip().lower() for n in reader.fieldnames}
    if "zone" not in lowered:
        raise HTTPException(status_code=400, detail="重跑文件缺少 zone 列")
    rows = [r for r in reader if any(str(v or "").strip() for v in r.values())]
    preview = [
        {
            "account": str(r.get("account") or r.get("Account") or ""),
            "zone": str(r.get("zone") or r.get("Zone") or ""),
        }
        for r in rows[:50]
    ]
    return {"rows": len(rows), "preview": preview}


@router.post("/api/v1/resume-upload")
async def resume_upload(file: UploadFile) -> dict[str, Any]:
    data = await file.read()
    if len(data) > 2 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="文件过大（上限 2MB）")
    handle = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    try:
        handle.write(data)
    finally:
        handle.close()
    try:
        entries = engine_adapter.load_resume_entries_strict(handle.name)
    except engine_adapter.EngineError as exc:
        try:
            os.unlink(handle.name)
        except OSError:
            pass
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    zones = sorted({z for _a, z in entries if z})
    return {"path": handle.name, "rows": len(entries), "zones": zones[:100]}
