"""REST 接口：挂载于 NiceGUI 底层 FastAPI，供脚本与自动化调用。

认证：服务端设置口令时，请求头 X-Auth-Token 必须匹配；未设口令则开放
（此时服务应仅监听本机，由启动参数保证）。
"""

from __future__ import annotations

import os
import tempfile
from typing import Any, Callable, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Response, UploadFile
from pydantic import BaseModel, Field

from . import engine_adapter, jobs


class JobSubmit(BaseModel):
    """提交任务请求体（字段与操作表单同源）。"""

    mode: str = "update"
    accounts: list[str] = Field(default_factory=list)
    record_type: str = "auto"
    old_content: Optional[str] = None
    new_content: Optional[str] = None
    delete_ip: Optional[str] = None
    delete_zone_mode: str = "dns"
    set_proxied: Optional[str] = None
    set_ttl: Optional[int] = None
    include_subdomains: bool = True
    whitelist: list[str] = Field(default_factory=list)
    whitelist_file: Optional[str] = None
    domains: list[str] = Field(default_factory=list)
    resume_csv: Optional[str] = None
    backup_dir: Optional[str] = None
    export_fmt: str = "json"
    export_dir: str = "./cf_export"
    speed: str = "eco"
    scope: str = "account"
    max_retries: int = 5
    dry_run: bool = True
    label: Optional[str] = None


class Deps:
    """路由依赖：由宿主（页面或测试）注入。"""

    def __init__(
        self,
        get_config_path: Callable[[], str],
        get_accounts: Callable[[], list[dict]],
        get_manager: Callable[[], jobs.JobManager],
        get_password: Callable[[], str],
        get_proxy_pool: Callable[[], Any],
    ):
        self.get_config_path = get_config_path
        self.get_accounts = get_accounts
        self.get_manager = get_manager
        self.get_password = get_password
        self.get_proxy_pool = get_proxy_pool


def _check_auth(password: str, token: Optional[str]) -> None:
    if not password:
        return
    if token != password:
        raise HTTPException(status_code=401, detail="未授权")


def _lookup(accounts: list[dict], names: list[str]) -> list[dict]:
    by_name = {(a.get("name") or a.get("email") or "unknown"): a for a in accounts}
    missing = [name for name in names if name not in by_name]
    if missing:
        raise HTTPException(status_code=400, detail=f"未知账号: {missing}")
    return [by_name[name] for name in names]


def _assemble_params(body: JobSubmit) -> tuple[dict[str, Any], Optional[str]]:
    """组装引擎参数；返回 (params, 错误信息)。"""
    whitelist = list(body.whitelist or [])
    if body.whitelist_file:
        try:
            whitelist.extend(engine_adapter.load_whitelist_strict(body.whitelist_file))
        except engine_adapter.EngineError as exc:
            return {}, str(exc)
    resume_entries = None
    if body.resume_csv:
        try:
            resume_entries = engine_adapter.load_resume_entries_strict(body.resume_csv)
        except engine_adapter.EngineError as exc:
            return {}, str(exc)
    params: dict[str, Any] = {
        "mode": body.mode,
        "record_type": body.record_type,
        "old_content": body.old_content,
        "new_content": body.new_content,
        "delete_ip": body.delete_ip,
        "delete_zone_mode": body.delete_zone_mode,
        "set_proxied": body.set_proxied,
        "set_ttl": body.set_ttl,
        "include_subdomains": body.include_subdomains,
        "whitelist": whitelist,
        "domains": list(body.domains or []),
        "resume_entries": resume_entries,
        "backup_dir": body.backup_dir,
        "export_fmt": body.export_fmt,
        "export_dir": body.export_dir,
    }
    error = jobs.validate_job_params(params, body.accounts)
    if error:
        return {}, error
    engine = engine_adapter.engine()
    if body.speed not in engine.SPEED_PRESETS:
        return {}, f"不支持的速度档位: {body.speed}"
    if body.scope not in {"account", "global"}:
        return {}, f"不支持的限速范围: {body.scope}"
    return params, None


def build_router(deps: Deps) -> APIRouter:
    """构建 /api 路由。"""
    router = APIRouter(prefix="/api")

    def _auth(x_auth_token: Optional[str] = Header(default=None)) -> None:
        _check_auth(deps.get_password(), x_auth_token)

    @router.get("/accounts")
    def list_accounts(_: None = Depends(_auth)) -> dict[str, Any]:
        try:
            accounts = deps.get_accounts()
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        return {"accounts": engine_adapter.masked_accounts(accounts)}

    @router.get("/zones")
    def list_zones(
        account: str, filter: str = "", _: None = Depends(_auth)
    ) -> dict[str, Any]:
        accounts = _lookup(deps.get_accounts(), [account])
        try:
            zones = engine_adapter.get_zones(accounts[0])
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        keyword = (filter or "").strip().lower()
        rows = [
            {"name": z.get("name", ""), "status": z.get("status", "")}
            for z in zones
            if keyword in str(z.get("name", "")).lower()
        ]
        return {"account": account, "total": len(zones), "zones": rows}

    @router.get("/records")
    def list_records(
        account: str, zone: str, _: None = Depends(_auth)
    ) -> dict[str, Any]:
        accounts = _lookup(deps.get_accounts(), [account])
        try:
            zones = engine_adapter.get_zones(accounts[0])
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        zone_id = ""
        for item in zones:
            if str(item.get("name", "")).lower() == zone.strip().lower():
                zone_id = item.get("id", "")
                break
        if not zone_id:
            raise HTTPException(status_code=404, detail=f"域名不在该账号中: {zone}")
        try:
            records = engine_adapter.get_records(accounts[0], zone_id)
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        return {
            "account": account,
            "zone": zone,
            "total": len(records),
            "records": [engine_adapter.slim_record(r) for r in records[:2000]],
            "truncated": len(records) > 2000,
        }

    @router.post("/jobs")
    def submit_job(body: JobSubmit, _: None = Depends(_auth)) -> dict[str, Any]:
        accounts = _lookup(deps.get_accounts(), body.accounts)
        params, error = _assemble_params(body)
        if error:
            raise HTTPException(status_code=400, detail=error)
        engine = engine_adapter.engine()
        preset = engine.SPEED_PRESETS[body.speed]
        speed = {
            "workers": int(preset["workers"]),
            "interval": float(preset["request_interval"]),
            "scope": body.scope,
            "max_retries": body.max_retries,
        }
        manager = deps.get_manager()
        label = body.label or (
            f"{'预览' if body.dry_run else '执行'} {body.mode} x{len(accounts)}账号"
        )
        job_id = manager.submit(
            label,
            "preview" if body.dry_run else "execute",
            jobs.run_operation_job,
            [a.get("name") or "" for a in accounts],
            accounts=accounts,
            params=params,
            speed=speed,
            proxy_pool=deps.get_proxy_pool(),
            dry_run=body.dry_run,
        )
        return {"job_id": job_id}

    @router.get("/jobs")
    def list_jobs(_: None = Depends(_auth)) -> dict[str, Any]:
        return {"jobs": deps.get_manager().list()}

    @router.get("/jobs/{job_id}")
    def get_job(job_id: str, _: None = Depends(_auth)) -> dict[str, Any]:
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        data = job.snapshot()
        data["verdict"] = list(job.verdict_lines)
        return data

    @router.get("/jobs/{job_id}/zones")
    def get_job_zones(
        job_id: str, account: str, _: None = Depends(_auth)
    ) -> dict[str, Any]:
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        return {"job_id": job_id, "account": account, **job.zone_detail(account)}

    @router.get("/jobs/{job_id}/results")
    def get_job_results(
        job_id: str, limit: int = 500, _: None = Depends(_auth)
    ) -> dict[str, Any]:
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        results = list(job.results)
        return {
            "job_id": job_id,
            "total": len(results),
            "results": results[: max(1, limit)],
            "truncated": len(results) > limit,
        }

    @router.get("/jobs/{job_id}/logs")
    def get_job_logs(
        job_id: str, offset: int = 0, _: None = Depends(_auth)
    ) -> dict[str, Any]:
        """增量拉取任务日志（前端轮询用，避免一次全量）。"""
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        lines = job.read_logs()
        start = max(0, offset)
        return {"job_id": job_id, "total": len(lines), "logs": lines[start:]}

    @router.post("/jobs/{job_id}/cancel")
    def cancel_job(job_id: str, _: None = Depends(_auth)) -> dict[str, Any]:
        ok = deps.get_manager().cancel(job_id)
        if not ok:
            raise HTTPException(
                status_code=409, detail="任务不可取消（不存在或已结束）"
            )
        return {"job_id": job_id, "cancelled": True}

    @router.get("/jobs/{job_id}/failures.csv")
    def download_failures(job_id: str, _: None = Depends(_auth)) -> Response:
        job = deps.get_manager().get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail=f"任务不存在: {job_id}")
        if not job.failure_rows:
            raise HTTPException(status_code=404, detail="该任务无失败清单")
        text = jobs.failures_csv_text(job)
        return Response(
            content="\ufeff" + text,
            media_type="text/csv; charset=utf-8",
            headers={
                "Content-Disposition": f"attachment; filename=failures_{job_id}.csv"
            },
        )

    @router.post("/resume-upload")
    async def resume_upload(
        file: UploadFile, _: None = Depends(_auth)
    ) -> dict[str, Any]:
        """上传重跑清单 CSV，返回服务端临时路径（供 jobs 提交体 resume_csv 使用）。"""
        data = await file.read()
        if len(data) > 2 * 1024 * 1024:
            raise HTTPException(status_code=400, detail="文件过大（上限 2MB）")
        path = save_upload_to_temp(data)
        try:
            entries = engine_adapter.load_resume_entries_strict(path)
        except engine_adapter.EngineError as exc:
            try:
                os.unlink(path)
            except OSError:
                pass
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        return {"path": path, "rows": len(entries)}

    return router


def save_upload_to_temp(data: bytes, suffix: str = ".csv") -> str:
    """保存上传文件到临时目录，返回路径（调用方负责清理）。"""
    handle = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    try:
        handle.write(data)
    finally:
        handle.close()
    return handle.name
