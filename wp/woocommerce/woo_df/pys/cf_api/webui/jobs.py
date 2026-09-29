"""任务管理：后台线程执行引擎批量操作，界面轮询进度。

- 长耗时批量在线程池中执行，UI 通过 ui.timer 轮询 Job 状态（线程安全读取）。
- 引擎的 log_print 被转接到当前任务日志，同时保留服务器控制台输出。
- 取消通过 stop_event 协作完成，与 CLI 语义一致。
"""

from __future__ import annotations

import itertools
import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from threading import Event, Lock
from typing import Any, Callable, Optional

from . import engine_adapter


@dataclass
class Job:
    """单个批量任务（含预览任务）。"""

    id: str
    label: str
    kind: str  # preview / execute / export
    account_names: list[str]
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
    _logs: Any = field(default_factory=lambda: deque(maxlen=2000), repr=False)

    def append_log(self, text: str) -> None:
        with self._lock:
            self._logs.append(text)

    def read_logs(self) -> list[str]:
        with self._lock:
            return list(self._logs)

    def set_account_status(self, account: str, status: str) -> None:
        """设置账号级状态：pending/running/done/failed/interrupted。"""
        with self._lock:
            self.account_status[account] = status

    def record_zone(self, account: str, zone: str, state: str) -> None:
        """记录域名级进度，state 为 done/error/cancelled。"""
        with self._lock:
            states = self.zone_states.setdefault(account, {})
            states[zone] = state
            order = self.zone_order.setdefault(account, [])
            if zone not in order:
                order.append(zone)

    def zone_progress(self, account: str) -> dict[str, Any]:
        with self._lock:
            order = list(self.zone_order.get(account, []))
            states = dict(self.zone_states.get(account, {}))
        done = sum(1 for zone in order if states.get(zone) in {"done", "error"})
        return {"total": len(order), "done": done, "states": states}

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
                        in {"done", "error"}
                    ),
                }
                for account in self.account_names
            }
            return {
                "id": self.id,
                "label": self.label,
                "kind": self.kind,
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
            }

    def zone_detail(self, account: str, limit: int = 500) -> dict[str, Any]:
        """返回某账号的域名明细（状态表），超限截断。"""
        with self._lock:
            order = list(self.zone_order.get(account, []))
            states = dict(self.zone_states.get(account, {}))
        rows = [{"zone": zone, "state": states.get(zone, "pending")} for zone in order]
        truncated = len(rows) > limit
        return {"rows": rows[:limit], "truncated": truncated, "total": len(rows)}


_job_local = threading.local()
_log_sink_installed = False
_log_sink_lock = Lock()
_original_log_print: Any = None


def _now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def current_job() -> Optional[Job]:
    return getattr(_job_local, "job", None)


def install_log_sink() -> None:
    """将引擎 log_print 转接一份到当前任务日志（幂等）。"""
    global _log_sink_installed, _original_log_print
    with _log_sink_lock:
        if _log_sink_installed:
            return
        mod = engine_adapter.engine()
        _original_log_print = mod.log_print

        def _web_log_print(*args: Any, **kwargs: Any) -> None:
            _original_log_print(*args, **kwargs)
            job = current_job()
            if job is not None:
                sep = kwargs.get("sep", " ") if isinstance(kwargs, dict) else " "
                try:
                    job.append_log(sep.join(str(arg) for arg in args))
                except Exception:
                    pass

        mod.log_print = _web_log_print
        _log_sink_installed = True


class JobManager:
    """任务管理器：提交、查询、取消，后台线程池执行。"""

    def __init__(self, max_workers: int = 2):
        self._executor = ThreadPoolExecutor(
            max_workers=max(1, max_workers), thread_name_prefix="webjob"
        )
        self._jobs: dict[str, Job] = {}
        self._lock = Lock()
        self._counter = itertools.count(1)
        install_log_sink()

    def submit(
        self,
        label: str,
        kind: str,
        func: Callable[..., None],
        account_names: list[str],
        **kwargs: Any,
    ) -> str:
        with self._lock:
            job_id = f"job-{next(self._counter):04d}"
            job = Job(
                id=job_id,
                label=label,
                kind=kind,
                account_names=list(account_names),
                created_at=_now_iso(),
            )
            self._jobs[job_id] = job
        self._executor.submit(self._run, job, func, kwargs)
        return job_id

    def _run(self, job: Job, func: Callable[..., None], kwargs: Any) -> None:
        _job_local.job = job
        job.status = "running"
        try:
            func(job, **kwargs)
            if job.stop_event.is_set():
                job.status = "cancelled"
            elif job.exit_code == 0:
                job.status = "done"
            else:
                job.status = "failed"
        except Exception as exc:  # noqa: BLE001 - 任务异常必须落盘为状态
            job.error = str(exc)
            job.status = "failed"
            job.append_log(f"[JOB-ERROR] {exc}")
        finally:
            job.finished_at = _now_iso()
            _job_local.job = None

    def get(self, job_id: str) -> Optional[Job]:
        with self._lock:
            return self._jobs.get(job_id)

    def list(self) -> list[dict[str, Any]]:
        with self._lock:
            jobs = list(self._jobs.values())
        return [job.snapshot() for job in sorted(jobs, key=lambda j: j.id)]

    def cancel(self, job_id: str) -> bool:
        job = self.get(job_id)
        if job is None or job.status != "running":
            return False
        job.stop_event.set()
        job.append_log("[CANCEL] 已请求取消，等待工作线程退出...")
        return True


def validate_job_params(
    params: dict[str, Any], account_names: list[str]
) -> Optional[str]:
    """校验任务参数（UI 与 REST 共用，与 CLI 校验语义对齐）。"""
    if not account_names:
        return "请先加载账号并选择执行账号"
    mode = params.get("mode", "update")
    if mode not in {
        "update",
        "delete_ip",
        "delete_wildcard",
        "delete_zone",
        "set_attrs",
        "export",
    }:
        return f"不支持的操作模式: {mode}"
    if mode == "update" and not params.get("new_content"):
        return "更新模式必须填写新内容"
    if mode == "delete_ip" and not params.get("delete_ip"):
        return "删除 IP 模式必须填写目标 IP"
    if (
        mode == "set_attrs"
        and not params.get("set_proxied")
        and params.get("set_ttl") is None
    ):
        return "属性设置至少选择代理状态或填写 TTL"
    ttl = params.get("set_ttl")
    if ttl is not None and (not isinstance(ttl, int) or ttl < 1):
        return "TTL 必须为正整数（1=自动）"
    if mode == "delete_zone" and not params.get("backup_dir"):
        return "删域名模式必须填写变更前快照目录"
    if not params.get("whitelist") and not params.get("domains"):
        if mode in {"delete_zone", "delete_wildcard", "delete_ip"}:
            return "删除类操作必须限定范围：填写白名单或指定域名"
    return None


def _dispatch_batch(
    engine: Any,
    updater: Any,
    params: dict[str, Any],
    whitelist: Optional[list[str]],
    explicit_domains: Optional[list[str]],
    resume_zones: Optional[set[str]],
    dry_run: bool,
) -> Any:
    """按操作模式分发到引擎 batch_*（与 CLI run_operation_for_account 对齐）。"""
    mode = params.get("mode", "update")
    if mode == "delete_wildcard":
        return updater.batch_delete_wildcard(
            whitelist=whitelist,
            record_type=params.get("record_type", "auto"),
            old_content=params.get("old_content"),
            dry_run=dry_run,
            explicit_domains=explicit_domains,
            resume_zones=resume_zones,
        )
    if mode == "delete_ip":
        return updater.batch_delete_ip(
            delete_ip=params["delete_ip"],
            whitelist=whitelist,
            record_type=params.get("record_type", "auto"),
            dry_run=dry_run,
            include_subdomains=params.get("include_subdomains", True),
            explicit_domains=explicit_domains,
            resume_zones=resume_zones,
        )
    if mode == "delete_zone":
        return updater.batch_delete_zone(
            whitelist=whitelist,
            dry_run=dry_run,
            delete_zone_completely=params.get("delete_zone_mode", "dns") == "full",
            explicit_domains=explicit_domains,
            resume_zones=resume_zones,
        )
    if mode == "set_attrs":
        proxied = params.get("set_proxied")
        return updater.batch_set_attrs(
            set_proxied=(proxied == "on") if proxied else None,
            set_ttl=params.get("set_ttl"),
            whitelist=whitelist,
            record_type=params.get("record_type", "auto"),
            old_content=params.get("old_content"),
            dry_run=dry_run,
            include_subdomains=params.get("include_subdomains", True),
            explicit_domains=explicit_domains,
            resume_zones=resume_zones,
        )
    if mode == "export":
        return updater.batch_export(
            export_dir=params.get("export_dir", "./cf_export"),
            fmt=params.get("export_fmt", "json"),
            whitelist=whitelist,
            explicit_domains=explicit_domains,
            resume_zones=resume_zones,
        )
    return updater.batch_update(
        new_content=params["new_content"],
        old_content=params.get("old_content"),
        whitelist=whitelist,
        record_type=params.get("record_type", "auto"),
        dry_run=dry_run,
        include_subdomains=params.get("include_subdomains", True),
        explicit_domains=explicit_domains,
        resume_zones=resume_zones,
    )


def _backup_if_needed(
    engine: Any,
    updater: Any,
    params: dict[str, Any],
    whitelist: Optional[list[str]],
    explicit_domains: Optional[list[str]],
    resume_zones: Optional[set[str]],
    dry_run: bool,
    job: Job,
) -> Optional[str]:
    """需要时执行变更前快照；失败返回错误信息（调用方中止账号）。"""
    backup_dir = params.get("backup_dir")
    if not backup_dir or dry_run or params.get("mode") == "export":
        return None
    ok, message = updater.batch_backup(
        backup_dir,
        whitelist=whitelist,
        explicit_domains=explicit_domains,
        resume_zones=resume_zones,
    )
    job.append_log(f"[BACKUP] {message}")
    return None if ok else message


def run_operation_job(
    job: Job,
    accounts: list[dict],
    params: dict[str, Any],
    speed: dict[str, Any],
    proxy_pool: Any = None,
    dry_run: bool = False,
    max_results: int = 2000,
) -> None:
    """任务执行体：多账号顺序执行，实时更新进度与日志。"""
    engine = engine_adapter.engine()
    whitelist = params.get("whitelist") or None
    explicit_domains = params.get("domains") or None
    resume_entries = params.get("resume_entries")
    workers = int(speed.get("workers", 2))
    interval = float(speed.get("interval", 0.5))
    max_retries = int(speed.get("max_retries", 5))
    print_lock = Lock()

    success = 0
    failed = 0
    cancelled_accounts = 0
    all_failure_rows: list[dict[str, Any]] = []
    all_results: list[dict[str, Any]] = []

    for account in accounts:
        if job.stop_event.is_set():
            break
        name = account.get("name") or account.get("email") or "unknown"
        job.current_account = name
        job.set_account_status(name, "running")
        job.append_log(f"=== 开始处理账号: {name} ===")
        try:
            updater = engine_adapter.build_updater(
                account,
                workers=workers,
                interval=interval,
                scope=speed.get("scope", "account"),
                max_retries=max_retries,
                proxy_pool=proxy_pool,
                stop_event=job.stop_event,
                print_lock=print_lock,
            )
            updater.progress_cb = lambda zone, state, _acc=name: job.record_zone(
                _acc, zone, state
            )
            resume_zones = engine.resume_filter_for_account(resume_entries, name)
            backup_error = _backup_if_needed(
                engine,
                updater,
                params,
                whitelist,
                explicit_domains,
                resume_zones,
                dry_run,
                job,
            )
            if backup_error:
                failed += 1
                all_failure_rows.append(
                    {
                        "account": name,
                        "zone": "",
                        "record_id": "",
                        "name": "",
                        "type": "ZONE",
                        "old_content": "",
                        "new_content": "",
                        "action": "backup",
                        "status": "error",
                        "attempts": 1,
                        "error": backup_error,
                        "timestamp": _now_iso(),
                    }
                )
                continue
            batch_result = _dispatch_batch(
                engine,
                updater,
                params,
                whitelist,
                explicit_domains,
                resume_zones,
                dry_run,
            )
            for item in batch_result.results:
                if len(all_results) < max_results:
                    all_results.append(
                        {
                            "account": getattr(item, "account", "") or name,
                            "zone": item.zone,
                            "name": item.name,
                            "type": item.record_type,
                            "old": item.old_content or "",
                            "new": item.new_content or "",
                            "status": item.status,
                            "message": item.message,
                        }
                    )
            all_failure_rows.extend(
                engine.failure_rows_for_results(name, batch_result.results)
            )
            pending = batch_result.stats.errors + batch_result.stats.cancelled
            if job.stop_event.is_set():
                job.append_log(f"[账号中断] {name}")
                job.set_account_status(name, "interrupted")
                continue
            if pending > 0:
                failed += 1
                job.set_account_status(name, "failed")
            else:
                success += 1
                job.set_account_status(name, "done")
        except Exception as exc:  # noqa: BLE001 - 单账号异常不影响其他账号
            failed += 1
            job.set_account_status(name, "failed")
            job.append_log(f"[ACCOUNT-ERR] {name}: {exc}")
        finally:
            job.accounts_done += 1

    job.results = all_results
    job.failure_rows = all_failure_rows
    if job.stop_event.is_set() and not all_failure_rows and failed == 0:
        job.exit_code = 130
        job.verdict_lines = ["[VERDICT] 任务被中断。"]
        return
    code, lines = engine.build_final_verdict(
        success,
        failed,
        cancelled_accounts,
        all_failure_rows,
        interrupted=bool(job.stop_event.is_set()),
        failed_output=None,
        prog="web-ui",
    )
    job.exit_code = code
    job.verdict_lines = lines
    for line in lines:
        job.append_log(line)


def failures_csv_text(job: Job) -> str:
    """生成失败清单 CSV 文本（UTF-8 BOM 由下载端处理）。"""
    import csv
    import io

    engine = engine_adapter.engine()
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=engine.FAILURE_CSV_FIELDNAMES)
    writer.writeheader()
    for row in job.failure_rows:
        writer.writerow(
            {key: row.get(key, "") for key in engine.FAILURE_CSV_FIELDNAMES}
        )
    return output.getvalue()


def wait_until(job: Job, timeout: float = 300.0) -> bool:
    """测试辅助：等待任务结束。"""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if job.status in {"done", "failed", "cancelled"}:
            return True
        time.sleep(0.05)
    return False
