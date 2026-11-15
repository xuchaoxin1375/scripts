# -*- coding: utf-8 -*-
"""任务提交编排：参数组装、速度解析、JobManager 提交。

HTTP 路由只负责鉴权与响应；本模块保留原有校验顺序与错误文案。
"""

from __future__ import annotations

from typing import Any, Optional

from fastapi import HTTPException

from .. import db, deps, engine_adapter
from .. import jobs as job_runner
from ..jobs import Job
from ..schemas import JobSubmit
from ..validate import validate_job_params
from .accounts import lookup_accounts


def build_job_params(body: JobSubmit, matched: list[dict]) -> dict[str, Any]:
    """把请求体转换为引擎任务参数，保留旧接口的默认值与校验顺序。"""
    resume_entries = None
    if body.resume_csv:
        try:
            resume_entries = engine_adapter.load_resume_entries_strict(body.resume_csv)
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

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
        "whitelist": list(body.whitelist or []),
        "domains": list(body.domains or []),
        "resume_entries": resume_entries,
        "backup_dir": body.backup_dir,
        "confirm": body.confirm,
        "add_domain": body.add_domain,
        "add_records": list(body.add_records or []),
        "proxied": body.proxied,
        "ttl": body.ttl,
        "allow_multi_value": body.allow_multi_value,
        "export_fmt": body.export_fmt,
        "export_dir": body.export_dir or deps.default_dirs()["export_dir"],
        "server_ip": body.server_ip,
        "forward_email": body.forward_email,
        "ssl_mode": body.ssl_mode,
        "do_dns": body.do_dns,
        "do_activation": body.do_activation,
        "do_email": body.do_email,
        "do_ssl": body.do_ssl,
        "do_security": body.do_security,
        "do_optimize": body.do_optimize,
    }
    if body.whitelist_file:
        try:
            params["whitelist"] = list(params["whitelist"]) + (
                engine_adapter.load_whitelist_strict(body.whitelist_file)
            )
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
    params["create_zone"] = body.create_zone
    params["activation_timeout"] = body.activation_timeout
    params["activation_interval"] = body.activation_interval

    # add_records 服务端预检，避免整任务跑起来才报错
    if params.get("add_records"):
        eng = engine_adapter.engine()
        for spec in params["add_records"]:
            try:
                eng.parse_add_record_spec(spec)
            except ValueError as exc:
                raise HTTPException(status_code=400, detail=str(exc)) from exc

    err = validate_job_params(params, list(body.accounts or []))
    if err:
        raise HTTPException(status_code=400, detail=err)
    return params


def build_speed(body: JobSubmit) -> dict[str, Any]:
    """解析速度档位与显式覆盖参数，范围与旧实现一致。"""
    eng = engine_adapter.engine()
    if body.speed not in getattr(eng, "SPEED_PRESETS", {}):
        raise HTTPException(status_code=400, detail=f"不支持的速度档位: {body.speed}")
    if body.scope not in {"account", "global"}:
        raise HTTPException(status_code=400, detail=f"不支持的限速范围: {body.scope}")
    preset = eng.SPEED_PRESETS[body.speed]
    workers = (
        int(preset["workers"])
        if body.workers is None
        else max(1, min(20, int(body.workers)))
    )
    interval = (
        float(preset["request_interval"])
        if body.request_interval is None
        else max(0.0, float(body.request_interval))
    )
    if body.account_workers is not None and (
        int(body.account_workers) < 1 or int(body.account_workers) > 20
    ):
        raise HTTPException(status_code=400, detail="账号并发数需为 1~20")
    if body.max_retries is not None and int(body.max_retries) < 0:
        raise HTTPException(status_code=400, detail="重试次数不能为负")
    for name, val in (("retry_base", body.retry_base), ("retry_max", body.retry_max)):
        if val is not None and float(val) <= 0:
            raise HTTPException(status_code=400, detail=f"{name} 必须大于 0")
    return {
        "workers": workers,
        "interval": interval,
        "scope": body.scope,
        "max_retries": int(body.max_retries),
        "retry_base": float(body.retry_base) if body.retry_base is not None else None,
        "retry_max": float(body.retry_max) if body.retry_max is not None else None,
        "account_workers": int(body.account_workers)
        if body.account_workers is not None
        else None,
    }


def submit_job(body: JobSubmit, matched: list[dict]) -> str:
    """组装参数并提交任务，返回 job_id。"""
    params = build_job_params(body, matched)
    speed = build_speed(body)
    manager = deps.get_manager()
    label = body.label or (
        f"{'预览' if body.dry_run else '执行'} {body.mode} x{len(matched)}账号"
    )
    job_id = manager.submit(
        label,
        "preview" if body.dry_run else "execute",
        job_runner.run_operation_job,
        [a.get("name") or "" for a in matched],
        accounts=matched,
        params=params,
        speed=speed,
        proxy_pool=deps.get_proxy_pool(),
        dry_run=body.dry_run,
    )
    try:
        db.audit(
            "execute",
            account=",".join(a.get("name") or "" for a in matched),
            detail=label,
        )
    except Exception:
        pass
    return job_id


def rerun_job(
    job: Job,
    *,
    failed_only: bool = False,
    dry_run: Optional[bool] = None,
) -> str:
    """按原参数重跑任务；failed_only 只保留失败涉及的账号/域名。

    - 预览任务可传 dry_run=False 走“执行此预览”。
    - 失败域重跑优先用失败行里的 account/zone；账号级失败（zone 为空）
      退回整账号重跑，避免把失败当成“无待处理域名”。
    """
    if job.status in {"pending", "running"}:
        raise HTTPException(status_code=409, detail="任务仍在运行，不能重跑")

    params = dict(job.params or {})
    account_names = list(job.account_names)
    if failed_only:
        failures = list(job.failure_rows or [])
        if not failures:
            raise HTTPException(status_code=400, detail="该任务没有可重跑的失败项")
        failed_zones = sorted(
            {str(row.get("zone") or "") for row in failures if row.get("zone")}
        )
        failed_accounts = sorted(
            {str(row.get("account") or "") for row in failures if row.get("account")}
        )
        if failed_accounts:
            kept = [name for name in account_names if name in failed_accounts]
            account_names = kept or account_names
        params["domains"] = failed_zones
        params["whitelist"] = []
        params["resume_entries"] = None

    if dry_run is None:
        dry_run = job.dry_run
    speed = dict(job.speed or {})
    if not speed:
        speed = {"workers": 2, "interval": 0.5, "max_retries": 5, "scope": "account"}
    matched = lookup_accounts(account_names)
    action = "重跑失败域" if failed_only else "重跑"
    if job.kind == "preview" and not dry_run:
        action = "执行预览"
    label = f"{action} {job.id} · {job.mode} x{len(matched)}账号"
    new_id = deps.get_manager().submit(
        label,
        "preview" if dry_run else "execute",
        job_runner.run_operation_job,
        [a.get("name") or "" for a in matched],
        accounts=matched,
        params=params,
        speed=speed,
        proxy_pool=deps.get_proxy_pool(),
        dry_run=dry_run,
    )
    try:
        db.audit(
            "rerun",
            account=",".join(a.get("name") or "" for a in matched),
            detail=f"{label} from={job.id} failed_only={failed_only}",
        )
    except Exception:
        pass
    return new_id


def execute_preview(job: Job) -> str:
    """把预览任务按原参数转成执行任务。"""
    if job.kind != "preview":
        raise HTTPException(status_code=400, detail="只有预览任务可以执行")
    if job.status != "done":
        raise HTTPException(status_code=409, detail="预览尚未成功完成，不能执行")
    if job.failure_rows:
        raise HTTPException(
            status_code=409,
            detail="预览存在失败项，请先处理失败或重新预览",
        )
    return rerun_job(job, failed_only=False, dry_run=False)
