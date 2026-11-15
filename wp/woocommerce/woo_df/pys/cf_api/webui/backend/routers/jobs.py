# -*- coding: utf-8 -*-
"""任务提交、进度、结果、失败清单、取消与导出路由。"""

from __future__ import annotations

import os
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse, Response

from .. import deps
from .. import jobs as job_runner
from ..auth import require_auth
from ..common import paginate
from ..schemas import JobSubmit
from ..services.accounts import lookup_accounts
from ..services.jobs import (
    execute_preview,
    rerun_job,
)
from ..services.jobs import (
    submit_job as submit_job_service,
)

router = APIRouter(dependencies=[Depends(require_auth)])


@router.post("/api/v1/jobs")
def submit_job(body: JobSubmit) -> dict[str, Any]:
    matched = lookup_accounts(list(body.accounts or []))
    job_id = submit_job_service(body, matched)
    return {"job_id": job_id}


@router.get("/api/v1/jobs")
def list_jobs() -> dict[str, Any]:
    return {"jobs": deps.get_manager().list()}


@router.get("/api/v1/jobs/{job_id}")
def get_job(job_id: str) -> dict[str, Any]:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    return job.snapshot()


@router.get("/api/v1/jobs/{job_id}/zones")
def job_zones(job_id: str, account: str) -> dict[str, Any]:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    return {"job_id": job_id, "account": account, **job.zone_detail(account)}


@router.get("/api/v1/jobs/{job_id}/results")
def job_results(job_id: str, page: int = 1, per_page: int = 50) -> dict[str, Any]:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    with job._lock:
        results = list(job.results)
    data = paginate(results, page, per_page)
    data.update({"job_id": job_id})
    return data


@router.get("/api/v1/jobs/{job_id}/logs")
def job_logs(job_id: str, offset: int = 0, limit: int = 500) -> dict[str, Any]:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    total, lines = job.read_logs(offset, limit)
    return {
        "job_id": job_id,
        "total": total,
        "offset": max(0, offset),
        "logs": lines,
    }


@router.get("/api/v1/jobs/{job_id}/failures")
def job_failures(job_id: str, page: int = 1, per_page: int = 50) -> dict[str, Any]:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    with job._lock:
        rows = list(job.failure_rows)
    data = paginate(rows, page, per_page)
    data.update({"job_id": job_id})
    return data


@router.get("/api/v1/jobs/{job_id}/failures.csv")
def job_failures_csv(job_id: str) -> Response:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    if not job.failure_rows:
        raise HTTPException(status_code=404, detail="该任务无失败清单")
    text = job_runner.failures_csv_text(job)
    return Response(
        content="\ufeff" + text,
        media_type="text/csv; charset=utf-8",
        headers={
            "Content-Disposition": f"attachment; filename=failures_{job_id}.csv"
        },
    )


@router.get("/api/v1/jobs/{job_id}/anomalies")
def job_anomalies(job_id: str, page: int = 1, per_page: int = 50) -> dict[str, Any]:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    with job._lock:
        rows = list(job.anomalies)
    data = paginate(rows, page, per_page)
    data.update({"job_id": job_id})
    return data


@router.get("/api/v1/jobs/{job_id}/anomalies.csv")
def job_anomalies_csv(job_id: str) -> Response:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    if not job.anomalies:
        raise HTTPException(status_code=404, detail="该任务无请求异常")
    text = job_runner.anomalies_csv_text(job)
    return Response(
        content="\ufeff" + text,
        media_type="text/csv; charset=utf-8",
        headers={
            "Content-Disposition": f"attachment; filename=anomalies_{job_id}.csv"
        },
    )


@router.post("/api/v1/jobs/{job_id}/rerun")
def job_rerun(
    job_id: str,
    failed_only: bool = False,
    dry_run: Optional[bool] = None,
) -> dict[str, Any]:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    return {"job_id": rerun_job(job, failed_only=failed_only, dry_run=dry_run)}


@router.post("/api/v1/jobs/{job_id}/execute")
def job_execute(job_id: str) -> dict[str, Any]:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    return {"job_id": execute_preview(job)}


@router.post("/api/v1/jobs/{job_id}/cancel")
def job_cancel(job_id: str) -> dict[str, Any]:
    ok = deps.get_manager().cancel(job_id)
    if not ok:
        raise HTTPException(status_code=409, detail="任务不可取消（不存在或已结束）")
    return {"job_id": job_id, "cancelled": True}


@router.get("/api/v1/jobs/{job_id}/exports")
def job_exports(job_id: str) -> dict[str, Any]:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    with job._lock:
        results = list(job.results)
    items = [
        {"index": n, "zone": r.get("zone", ""), "path": str(r.get("new") or "")}
        for n, r in enumerate(results)
        if r.get("status") == "exported" and r.get("new")
    ]
    return {"job_id": job_id, "total": len(items), "items": items}


@router.get("/api/v1/jobs/{job_id}/exports/{index}")
def job_export_file(job_id: str, index: int) -> FileResponse:
    job = deps.get_manager().get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
    with job._lock:
        results = list(job.results)
    exported = [r for r in results if r.get("status") == "exported" and r.get("new")]
    if index < 0 or index >= len(exported):
        raise HTTPException(status_code=404, detail="导出文件不存在")
    raw = str(exported[index].get("new") or "")
    candidate = os.path.realpath(raw)
    allowed = {
        os.path.realpath(d)
        for d in {
            deps.default_dirs()["export_dir"],
            deps.default_dirs()["backup_dir"],
            "./cf_export",
            "./cf_backup",
        }
    }
    if not any(
        candidate == base or candidate.startswith(base + os.sep) for base in allowed
    ):
        raise HTTPException(status_code=403, detail="导出路径不在允许目录内")
    if not os.path.isfile(candidate):
        raise HTTPException(status_code=404, detail="导出文件已不在磁盘上")
    return FileResponse(candidate)
