# -*- coding: utf-8 -*-
"""任务管理：线程池执行引擎批量操作，界面轮询进度。

- 长耗时批量在线程池中执行，界面轮询 Job 状态（线程安全读取）。
- 引擎的 log_print 打补丁分流一份到任务日志，同时保留控制台输出。
- 取消走 stop_event，与 CLI 语义一致；结果集上限 2000，日志 deque 2000。
"""

from __future__ import annotations

import csv
import io
import itertools
import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from threading import Event, Lock
from typing import Any, Callable, Optional

from . import db, engine_adapter
from .validate import validate_job_params as _validate_params

MAX_RESULTS = 2000
MAX_LOGS = 2000

_job_local = threading.local()
_orig_log_print: Optional[Callable[..., None]] = None
_patch_lock = Lock()
_counter = itertools.count(1)


def validate_job_params(params: dict[str, Any], accounts: list[str]) -> Optional[str]:
    """兼容旧导入路径的校验入口。"""
    return _validate_params(params, accounts)


@dataclass
class Job:
    """单个批量任务（含预览任务）。"""

    id: str
    label: str
    kind: str  # preview / execute / export
    mode: str = "update"
    account_names: list[str] = field(default_factory=list)
    status: str = "pending"  # pending/running/done/failed/cancelled
    accounts_done: int = 0
    current_account: str = ""
    results: list[dict[str, Any]] = field(default_factory=list)
    failure_rows: list[dict[str, Any]] = field(default_factory=list)
    verdict_lines: list[str] = field(default_factory=list)
    exit_code: Optional[int] = None
    error: str = ""
    created_at: str = ""
    finished_at: str = ""
    stop_event: Event = field(default_factory=Event)
    account_status: dict[str, str] = field(default_factory=dict)
    zone_order: dict[str, list[str]] = field(default_factory=dict)
    zone_states: dict[str, dict[str, str]] = field(default_factory=dict)
    _lock: Lock = field(default_factory=Lock, repr=False)
    _logs: Any = field(default_factory=lambda: deque(maxlen=MAX_LOGS), repr=False)

    def append_log(self, text: str) -> None:
        with self._lock:
            self._logs.append(text)

    def read_logs(self, offset: int = 0, limit: int = 500) -> tuple[int, list[str]]:
        with self._lock:
            lines = list(self._logs)
        total = len(lines)
        start = max(0, offset)
        return total, lines[start : start + max(1, limit)]

    def set_account_status(self, account: str, status: str) -> None:
        with self._lock:
            self.account_status[account] = status

    def record_zone(self, account: str, zone: str, state: str) -> None:
        with self._lock:
            states = self.zone_states.setdefault(account, {})
            states[zone] = state
            order = self.zone_order.setdefault(account, [])
            if zone not in order:
                order.append(zone)

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            total = len(self.account_names)
            zone_summary = {
                account: {
                    "total": len(self.zone_order.get(account, [])),
                    "done": sum(
                        1
                        for zone in self.zone_order.get(account, [])
                        if self.zone_states.get(account, {}).get(zone)
                        in {"done", "error", "cancelled"}
                    ),
                }
                for account in self.account_names
            }
            return {
                "job_id": self.id,
                "id": self.id,
                "label": self.label,
                "kind": self.kind,
                "mode": self.mode,
                "status": self.status,
                "accounts_done": self.accounts_done,
                "accounts_total": total,
                "current_account": self.current_account,
                "account_status": dict(self.account_status),
                "zone_summary": zone_summary,
                "result_count": len(self.results),
                "failure_count": len(self.failure_rows),
                "exit_code": self.exit_code,
                "error": self.error,
                "created_at": self.created_at,
                "finished_at": self.finished_at,
                "verdict": list(self.verdict_lines),
            }

    def zone_detail(self, account: str, limit: int = 500) -> dict[str, Any]:
        with self._lock:
            order = list(self.zone_order.get(account, []))
            states = dict(self.zone_states.get(account, {}))
        rows = [{"zone": zone, "state": states.get(zone, "pending")} for zone in order]
        truncated = len(rows) > limit
        return {"rows": rows[:limit], "truncated": truncated, "total": len(rows)}


def failures_csv_text(job: Job) -> str:
    """失败清单 CSV 文本（无 BOM，调用方按需加 BOM 下发）。"""
    mod = engine_adapter.engine()
    fieldnames: list[str] = list(getattr(mod, "FAILURE_CSV_FIELDNAMES", []))
    if not fieldnames:
        fieldnames = [
            "account",
            "zone",
            "record_id",
            "name",
            "type",
            "old_content",
            "new_content",
            "action",
            "status",
            "attempts",
            "error",
            "timestamp",
        ]
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=fieldnames)
    writer.writeheader()
    with job._lock:
        rows = list(job.failure_rows)
    for row in rows:
        writer.writerow({k: row.get(k, "") for k in fieldnames})
    return buf.getvalue()


def _ensure_log_patch() -> None:
    global _orig_log_print
    with _patch_lock:
        if _orig_log_print is not None:
            return
        mod = engine_adapter.engine()
        _orig_log_print = mod.log_print

        def _patched(*args: Any, **kwargs: Any) -> None:
            sep = kwargs.get("sep", " ")
            text = sep.join(str(a) for a in args)
            current = getattr(_job_local, "current", None)
            if current is not None:
                try:
                    current.append_log(text)
                except Exception:
                    pass
            assert _orig_log_print is not None
            _orig_log_print(*args, **kwargs)

        mod.log_print = _patched  # type: ignore[method-assign]


def _now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime())


class JobManager:
    """任务管理器：提交/查询/取消/历史。"""

    def __init__(self, max_workers: int = 4) -> None:
        self._pool = ThreadPoolExecutor(max_workers=max_workers)
        self._jobs: dict[str, Job] = {}
        self._lock = Lock()
        _ensure_log_patch()

    def submit(
        self,
        label: str,
        kind: str,
        func: Callable[..., None],
        account_names: list[str],
        **kwargs: Any,
    ) -> str:
        job_id = f"job-{next(_counter):04d}"
        job = Job(
            id=job_id,
            label=label,
            kind=kind,
            mode=str(kwargs.get("params", {}).get("mode", "update")),
            account_names=list(account_names),
            status="pending",
            created_at=_now_iso(),
        )
        for name in account_names:
            job.account_status[name] = "pending"
        with self._lock:
            self._jobs[job_id] = job
        self._pool.submit(self._run, job, func, kwargs)
        return job_id

    def _run(self, job: Job, func: Callable[..., None], kwargs: Any) -> None:
        _job_local.current = job
        job.status = "running"
        try:
            func(job, **kwargs)
        except Exception as exc:  # noqa: BLE001 - 任务异常转失败态，不抛给线程池
            job.status = "failed"
            job.error = str(exc)
            job.append_log(f"[JOB-ERR] {exc}")
        finally:
            if job.status == "running":
                job.status = "done"
            job.finished_at = _now_iso()
            try:
                db.upsert_history(
                    {
                        "id": job.id,
                        "mode": job.mode,
                        "status": job.status,
                        "label": job.label,
                        "accounts": ",".join(job.account_names),
                        "exit_code": job.exit_code,
                        "created_at": job.created_at,
                        "finished_at": job.finished_at,
                    }
                )
            except Exception:
                pass
            _job_local.current = None

    def get(self, job_id: str) -> Optional[Job]:
        with self._lock:
            return self._jobs.get(job_id)

    def list(self, limit: int = 50) -> list[dict[str, Any]]:
        with self._lock:
            jobs = list(self._jobs.values())[-limit:]
        return [j.snapshot() for j in reversed(jobs)]

    def cancel(self, job_id: str) -> bool:
        job = self.get(job_id)
        if job is None or job.status not in {"pending", "running"}:
            return False
        job.stop_event.set()
        job.append_log("[JOB] 已请求取消，等待工作线程退出")
        return True


def _bind_progress(updater: Any, job: Job, account_name: str) -> None:
    def _cb(zone_name: str, state: str) -> None:
        job.record_zone(account_name, zone_name, state)

    updater.progress_cb = _cb


def run_operation_job(
    job: Job,
    accounts: list[dict],
    params: dict[str, Any],
    speed: dict[str, Any],
    proxy_pool: Any = None,
    dry_run: bool = True,
) -> None:
    """在工作线程中执行批量操作（供 JobManager.submit 回调）。"""
    mod = engine_adapter.engine()
    mode = str(params.get("mode", "update"))
    workers = int(speed.get("workers", 2))
    interval = float(speed.get("interval", 0.5))
    max_retries = int(speed.get("max_retries", 5))
    retry_base = speed.get("retry_base")
    retry_max = speed.get("retry_max")
    by_name = {(a.get("name") or a.get("email") or "unknown"): a for a in accounts}

    resume_entries = params.get("resume_entries")
    domains = list(params.get("domains") or [])
    whitelist = list(params.get("whitelist") or [])

    success = 0
    failed = 0
    cancelled_accounts = 0
    all_failures: list[dict[str, Any]] = []

    for account in accounts:
        if job.stop_event.is_set():
            name = account.get("name") or "unknown"
            job.set_account_status(name, "interrupted")
            cancelled_accounts += 1
            continue
        name = account.get("name") or account.get("email") or "unknown"
        job.current_account = name
        job.set_account_status(name, "running")
        try:
            updater = mod.CloudflareDNSUpdater(
                auth_method=account["auth_method"],
                api_token=account.get("token"),
                api_email=account.get("email"),
                api_key=account.get("key"),
                max_workers=max(1, workers),
                stop_event=job.stop_event,
                account_name=name,
                rate_limiter=mod.ApiRateLimiter(
                    min_interval=interval, stop_event=job.stop_event
                )
                if interval > 0
                else None,
                api_max_retries=max_retries,
                api_retry_base_delay=float(retry_base)
                if retry_base is not None
                else mod.DEFAULT_API_RETRY_BASE_DELAY,
                api_retry_max_sleep=float(retry_max)
                if retry_max is not None
                else mod.DEFAULT_API_RETRY_MAX_SLEEP,
                explicit_domains=domains or None,
                proxy_pool=proxy_pool,
            )
            _bind_progress(updater, job, name)
            batch = _run_single_account(
                updater,
                mod,
                mode,
                params,
                whitelist,
                domains,
                resume_entries,
                dry_run,
                name,
            )
            for item in batch.results:
                if len(job.results) < MAX_RESULTS:
                    job.results.append(
                        {
                            "account": item.account or name,
                            "zone": item.zone,
                            "name": item.name,
                            "type": item.record_type,
                            "old": item.old_content,
                            "new": item.new_content,
                            "status": item.status,
                            "message": item.message,
                        }
                    )
            rows = mod.failure_rows_for_results(name, batch.results)
            all_failures.extend(rows)
            pending = batch.stats.errors + batch.stats.cancelled
            if job.stop_event.is_set():
                job.set_account_status(name, "interrupted")
                cancelled_accounts += 1
            elif pending > 0:
                job.set_account_status(name, "failed")
                failed += 1
            else:
                job.set_account_status(name, "done")
                success += 1
        except Exception as exc:  # noqa: BLE001 - 单账号失败不影响其它账号
            job.set_account_status(name, "failed")
            job.append_log(f"[ACCOUNT-ERR] {name}: {exc}")
            failed += 1
            all_failures.append(
                {
                    "account": name,
                    "zone": "",
                    "record_id": "",
                    "name": "",
                    "type": "ZONE",
                    "old_content": "",
                    "new_content": "",
                    "action": "fetch_zones",
                    "status": "error",
                    "attempts": 1,
                    "error": f"账号级失败: {exc}",
                    "timestamp": mod.utc_now_iso(),
                }
            )
        finally:
            job.accounts_done += 1
            _ = by_name  # 保持账号映射可审计

    with job._lock:
        job.failure_rows = all_failures[:MAX_RESULTS]
    interrupted = bool(job.stop_event.is_set())
    code, lines = mod.build_final_verdict(
        success, failed, cancelled_accounts, all_failures, interrupted, None, "webui"
    )
    with job._lock:
        job.verdict_lines = list(lines)
        job.exit_code = code
    if interrupted:
        job.status = "cancelled"
    elif failed > 0 or cancelled_accounts > 0 or all_failures:
        job.status = "failed" if failed > 0 else "done"
    else:
        job.status = "done"
    try:
        db.audit(
            "execute",
            account=",".join(job.account_names),
            detail=f"{mode} dry={dry_run} code={code}",
        )
    except Exception:
        pass


def _run_single_account(
    updater: Any,
    mod: Any,
    mode: str,
    params: dict[str, Any],
    whitelist: list[str],
    domains: list[str],
    resume_entries: Any,
    dry_run: bool,
    account_name: str,
) -> Any:
    """按模式分发到引擎 batch_*；重跑过滤按账号计算。"""
    resume_zones = mod.resume_filter_for_account(resume_entries, account_name)
    include_sub = bool(params.get("include_subdomains", True))
    record_type = str(params.get("record_type", "auto"))
    old_content = params.get("old_content")
    new_content = params.get("new_content")
    backup_dir = params.get("backup_dir")

    mutating = mode in {
        "update",
        "delete_wildcard",
        "delete_ip",
        "delete_zone",
        "add",
        "set_attrs",
    }
    if backup_dir and mutating and not dry_run:
        ok, msg = updater.batch_backup(
            backup_dir,
            whitelist=whitelist or None,
            explicit_domains=domains or None,
            resume_zones=resume_zones,
        )
        if not ok:
            raise RuntimeError(msg)

    if mode == "update":
        return updater.batch_update(
            new_content=new_content,
            old_content=old_content,
            whitelist=whitelist or None,
            record_type=record_type,
            dry_run=dry_run,
            include_subdomains=include_sub,
            explicit_domains=domains or None,
            resume_zones=resume_zones,
        )
    if mode == "delete_wildcard":
        return updater.batch_delete_wildcard(
            whitelist=whitelist or None,
            record_type=record_type,
            old_content=old_content,
            dry_run=dry_run,
            explicit_domains=domains or None,
            resume_zones=resume_zones,
        )
    if mode == "delete_ip":
        return updater.batch_delete_ip(
            delete_ip=params.get("delete_ip"),
            whitelist=whitelist or None,
            record_type=record_type,
            dry_run=dry_run,
            include_subdomains=include_sub,
            explicit_domains=domains or None,
            resume_zones=resume_zones,
        )
    if mode == "delete_zone":
        return updater.batch_delete_zone(
            whitelist=whitelist or None,
            dry_run=dry_run,
            delete_zone_completely=str(params.get("delete_zone_mode", "dns")) == "full",
            explicit_domains=domains or None,
            resume_zones=resume_zones,
        )
    if mode == "add":
        return updater.batch_add_domain_and_records(
            add_domain=params.get("add_domain"),
            add_records=params.get("add_records"),
            proxied=bool(params.get("proxied", True)),
            ttl=int(params.get("ttl", 1) or 1),
            dry_run=dry_run,
            explicit_domains=domains or None,
            resume_zones=resume_zones,
            allow_multi_value=bool(params.get("allow_multi_value", False)),
        )
    if mode == "set_attrs":
        raw = params.get("set_proxied")
        set_proxied = None if raw is None else (str(raw) == "on")
        return updater.batch_set_attrs(
            set_proxied=set_proxied,
            set_ttl=params.get("set_ttl"),
            whitelist=whitelist or None,
            record_type=record_type,
            old_content=old_content,
            dry_run=dry_run,
            include_subdomains=include_sub,
            explicit_domains=domains or None,
            resume_zones=resume_zones,
        )
    if mode == "export":
        return updater.batch_export(
            export_dir=params.get("export_dir") or "./cf_export",
            fmt=params.get("export_fmt") or "json",
            whitelist=whitelist or None,
            explicit_domains=domains or None,
            resume_zones=resume_zones,
        )
    if mode == "provision":
        return _run_provision(updater, params, domains, dry_run)
    raise ValueError(f"不支持的模式: {mode}")


def _run_provision(
    updater: Any, params: dict[str, Any], domains: list[str], dry_run: bool
) -> Any:
    """Web 侧 provision：与 CLI --provision 同语义（DNS/激活/邮箱/SSL/安全/加速）。

    dry_run 只预览待写记录与待配步骤，不调用任何写接口。
    """
    mod = engine_adapter.engine()
    stats = mod.OperationStats()
    results: list[Any] = []
    server_ip = str(params.get("server_ip", "") or "")
    forward = str(params.get("forward_email", "") or "")
    ssl_mode = str(params.get("ssl_mode", "") or "")
    if ssl_mode and ssl_mode not in {"flexible", "full", "strict", "off"}:
        raise ValueError(f"不支持的 SSL 模式: {ssl_mode}")
    try:
        act_timeout = float(params.get("activation_timeout") or 300.0)
        act_interval = float(params.get("activation_interval") or 5.0)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"激活等待参数无效: {exc}") from exc
    if act_timeout <= 0 or act_interval <= 0:
        raise ValueError("激活等待参数必须大于 0")
    create_zone = bool(params.get("create_zone", False))
    for domain in domains:
        if updater._stop_event.is_set():
            stats.inc_cancelled()
            results.append(
                mod.DNSOperationResult(
                    zone=domain,
                    name="",
                    record_type="ZONE",
                    old_content=None,
                    new_content=None,
                    status="cancelled",
                    message="任务被取消",
                    account=updater.account_name,
                )
            )
            continue
        try:
            zone = updater.get_zone_by_name(domain)
            if zone is None and create_zone:
                if dry_run:
                    stats.inc_dry_run()
                    results.append(
                        mod.DNSOperationResult(
                            zone=domain,
                            name=domain,
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="dry_run_add_domain",
                            message="provision 预览：将创建 zone",
                            account=updater.account_name,
                        )
                    )
                    continue
                created = updater.create_zone(domain)
                zone = created.get("result", {}) or {}
                stats.inc_created()
                results.append(
                    mod.DNSOperationResult(
                        zone=str(zone.get("name", domain)),
                        name=str(zone.get("name", domain)),
                        record_type="ZONE",
                        old_content=None,
                        new_content=None,
                        status="added_domain",
                        message="provision 已创建 zone",
                        account=updater.account_name,
                    )
                )
            if zone is None:
                stats.inc_errors()
                results.append(
                    mod.DNSOperationResult(
                        zone=domain,
                        name="",
                        record_type="ZONE",
                        old_content=None,
                        new_content=None,
                        status="error",
                        message="账号中未找到该 zone（可开启建域后重跑）",
                        account=updater.account_name,
                    )
                )
                continue
            zone_id = zone.get("id", "")
            zone_name = zone.get("name", domain)
            specs = list(params.get("add_records") or [])
            records: list[dict[str, Any]] = []
            if specs:
                for spec in specs:
                    name, rtype, content = mod.parse_add_record_spec(spec)
                    records.append(
                        {
                            "name": name,
                            "type": rtype,
                            "content": content,
                            "proxied": bool(params.get("proxied", True)),
                            "ttl": int(params.get("ttl", 1) or 1),
                            "priority": None,
                        }
                    )
            elif server_ip:
                records = mod.build_records_for_domain(
                    domain,
                    {},
                    server_ip,
                    bool(params.get("proxied", True)),
                    int(params.get("ttl", 1) or 1),
                )
            if dry_run:
                if records:
                    for record in records:
                        stats.inc_dry_run()
                        results.append(
                            mod.DNSOperationResult(
                                zone=zone_name,
                                name=str(record.get("name", "")),
                                record_type=str(record.get("type", "")),
                                old_content=None,
                                new_content=str(record.get("content", "")),
                                status="dry_run_add_record",
                                message="provision 预览",
                                account=updater.account_name,
                            )
                        )
                else:
                    stats.inc_dry_run()
                    results.append(
                        mod.DNSOperationResult(
                            zone=zone_name,
                            name=zone_name,
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="dry_run_add_record",
                            message=(
                                f"provision 预览: dns={params.get('do_dns')} "
                                f"activation={params.get('do_activation')} "
                                f"email={bool(forward)} ssl={ssl_mode or '-'}"
                            ),
                            account=updater.account_name,
                        )
                    )
                continue
            options = mod.ZoneProvisionOptions(
                records=records,
                forward_email=forward,
                ssl_mode=ssl_mode,
                do_dns=bool(params.get("do_dns", True)),
                do_activation=bool(params.get("do_activation", True)),
                do_email=bool(params.get("do_email", True)),
                do_ssl=bool(ssl_mode) and bool(params.get("do_ssl", True)),
                do_security=bool(params.get("do_security", True)),
                do_optimize=bool(params.get("do_optimize", True)),
                activation_timeout=act_timeout,
                activation_interval=act_interval,
                verbose=False,
            )
            statuses = mod.provision_zone(updater, zone_id, zone_name, domain, options)
            summary = (
                f"dns={statuses.get('record_status')} act={statuses.get('activation')} "
                f"mail={statuses.get('email_status')} ssl={statuses.get('ssl_status')} "
                f"sec={statuses.get('security_status')}"
            )
            if statuses.get("error"):
                summary += f" err={statuses['error']}"
            bad = any(
                str(v).startswith("error:")
                or str(v).startswith("pending_verification:")
                for v in [
                    statuses.get("email_status", ""),
                    statuses.get("ssl_status", ""),
                ]
            )
            if bad:
                stats.inc_errors()
            else:
                stats.inc_updated()
            results.append(
                mod.DNSOperationResult(
                    zone=zone_name,
                    name=zone_name,
                    record_type="ZONE",
                    old_content=None,
                    new_content=summary,
                    status="error" if bad else "updated",
                    message=summary,
                    account=updater.account_name,
                )
            )
        except Exception as exc:  # noqa: BLE001
            stats.inc_errors()
            results.append(
                mod.DNSOperationResult(
                    zone=domain,
                    name="",
                    record_type="ZONE",
                    old_content=None,
                    new_content=None,
                    status="error",
                    message=str(exc),
                    account=updater.account_name,
                )
            )
    return mod.BatchRunResult(results=results, stats=stats)
