# -*- coding: utf-8 -*-
"""跨账号 zone 扫描：并发查询、进度快照、取消与部分结果。

设计要点：
- 只按 zone 名精确查询，不加 ``status=active``；pending/moved 也要能看到。
- 每个账号只查一次，不在扫描阶段拉取 DNS 记录；记录数交给工作台按需加载。
- 扫描结果按账号记录 hit/miss/error，前端可实时看到已检查数与当前账号。
- 扫描器是只读的，不复用写任务的 JobManager，避免扫描出现在任务历史里。
"""

from __future__ import annotations

import itertools
import re
import time
from concurrent.futures import FIRST_COMPLETED, Future, ThreadPoolExecutor, wait
from dataclasses import dataclass, field
from datetime import datetime, timezone
from threading import Event, Lock
from typing import Any, Callable, Optional

from .. import engine_adapter

MAX_SCANS = 20
MAX_EVENTS = 400
MAX_ERROR_CHARS = 500

# Cloudflare zone 名：至少一个点，标签只允许字母/数字/连字符，允许 punycode。
DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)"
    r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$",
    re.IGNORECASE,
)


def utc_now() -> str:
    """UTC ISO 时间（秒级），用于快照与事件。"""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def normalize_domain(value: str) -> str:
    """从域名/URL/白名单行提取 Cloudflare zone 名；无效返回空字符串。"""
    eng = engine_adapter.engine()
    target = (eng.get_main_domain_name_from_str(value) or str(value or "").strip()).lower()
    target = target.strip().strip(".")
    if not target or not DOMAIN_RE.fullmatch(target):
        return ""
    return target


def scan_speed(speed: str, max_retries: int) -> dict[str, Any]:
    """把速度档位解析成扫描并发、请求间隔与重试次数。

    Raises:
        engine_adapter.EngineError: 档位不存在。
    """
    eng = engine_adapter.engine()
    presets = getattr(eng, "SPEED_PRESETS", {})
    preset = presets.get(speed)
    if not isinstance(preset, dict):
        raise engine_adapter.EngineError(f"不支持的速度档位: {speed}")
    try:
        account_workers = int(preset.get("account_workers", 3))
    except (TypeError, ValueError):
        account_workers = 3
    try:
        interval = float(preset.get("request_interval", 0.0))
    except (TypeError, ValueError):
        interval = 0.0
    return {
        "speed": speed,
        "account_workers": max(1, min(20, account_workers)),
        "request_interval": max(0.0, interval),
        "max_retries": max(0, min(20, int(max_retries))),
    }


@dataclass
class FindScan:
    """一次跨账号扫描的可轮询快照。"""

    id: str
    domain: str
    account_names: list[str]
    stop_on_first: bool = True
    speed: dict[str, Any] = field(default_factory=dict)
    status: str = "pending"  # pending/running/cancelling/done/partial/failed/cancelled
    checked: int = 0
    hits: int = 0
    misses: int = 0
    failed: int = 0
    results: list[dict[str, Any]] = field(default_factory=list)
    errors: list[dict[str, Any]] = field(default_factory=list)
    missed_accounts: list[str] = field(default_factory=list)
    events: list[dict[str, Any]] = field(default_factory=list)
    in_flight: list[str] = field(default_factory=list)
    started_at: str = ""
    finished_at: str = ""
    stopped_early: bool = False
    _started_mono: float = 0.0
    _finished_mono: float = 0.0
    _stop_event: Event = field(default_factory=Event)
    _hit_event: Event = field(default_factory=Event)
    _start_note: str = ""
    _lock: Lock = field(default_factory=Lock)

    @property
    def total(self) -> int:
        return len(self.account_names)

    def start(self) -> None:
        """进入运行态并写开始事件；启动前已取消则保持取消态。"""
        with self._lock:
            self.status = "cancelling" if self._stop_event.is_set() else "running"
            self.started_at = utc_now()
            self._started_mono = time.monotonic()
            mode = "找到第一个就停止" if self.stop_on_first else "扫描全部账号"
            message = self._start_note or f"开始扫描 {self.total} 个账号（{mode}）"
            self._start_note = ""
            self._event_unlocked("info", "", message)

    def mark_in_flight(self, account: str) -> None:
        """记录一个已提交、尚未返回的账号。"""
        with self._lock:
            if account and account not in self.in_flight:
                self.in_flight.append(account)

    def record(self, result: dict[str, Any]) -> None:
        """并入单个账号结果；扫描已结束时忽略迟到的结果。"""
        with self._lock:
            if self.status not in {"running", "cancelling"}:
                return
            account = str(result.get("account") or "unknown")
            if account in self.in_flight:
                self.in_flight.remove(account)
            kind = str(result.get("kind") or "error")
            if kind == "cancelled":
                return
            self.checked += 1
            if kind == "hit":
                self.hits += 1
                row = {
                    "account": account,
                    "zone": str(result.get("zone") or self.domain),
                    "zone_id": str(result.get("zone_id") or ""),
                    "status": str(result.get("status") or ""),
                    "elapsed_ms": int(result.get("elapsed_ms") or 0),
                }
                self.results.append(row)
                if self.stop_on_first:
                    self._hit_event.set()
                self._event_unlocked(
                    "success",
                    account,
                    f"找到 {row['zone']}（{row['status'] or '状态未知'}）",
                )
            elif kind == "miss":
                self.misses += 1
                self.missed_accounts.append(account)
                self._event_unlocked("info", account, "未找到")
            else:
                self.failed += 1
                error = str(result.get("error") or "未知错误")[:MAX_ERROR_CHARS]
                self.errors.append(
                    {
                        "account": account,
                        "error": error,
                        "elapsed_ms": int(result.get("elapsed_ms") or 0),
                    }
                )
                self._event_unlocked("error", account, f"读取失败：{error}")

    def should_stop_after_hit(self) -> bool:
        """命中且配置为找到第一个就停止时，通知调度器收口。"""
        return self.stop_on_first and self._hit_event.is_set()

    def _unchecked_accounts_unlocked(self) -> list[str]:
        """未返回结果的账号；调用方必须持有锁。"""
        checked_names = {row["account"] for row in self.results}
        checked_names.update(self.missed_accounts)
        checked_names.update(row["account"] for row in self.errors)
        return [
            name for name in self.account_names if name not in checked_names
        ]

    def unchecked_names(self) -> list[str]:
        """线程安全地读取未检查账号列表。"""
        with self._lock:
            return self._unchecked_accounts_unlocked()

    def begin_continuation(self) -> bool:
        """把已结束但仍有未检查账号的扫描重新打开为待运行态。"""
        with self._lock:
            if self.status not in {"done", "partial", "failed", "cancelled"}:
                return False
            unchecked = self._unchecked_accounts_unlocked()
            if not unchecked:
                return False
            self.status = "pending"
            self.stopped_early = False
            self.finished_at = ""
            self._finished_mono = 0.0
            self._stop_event = Event()
            self._hit_event = Event()
            self.stop_on_first = False
            self.in_flight = []
            self._start_note = f"继续扫描剩余 {len(unchecked)} 个账号"
            return True

    def cancel(self) -> bool:
        """请求取消；已结束返回 False。"""
        with self._lock:
            if self.status not in {"pending", "running", "cancelling"}:
                return False
            self.status = "cancelling"
            self._stop_event.set()
            self._event_unlocked("warning", "", "已请求取消，等待正在执行的账号返回")
            return True

    def finish(self, cancelled: bool, stopped_early: bool = False) -> None:
        """收敛终态；取消、提前命中与失败分开表达。"""
        with self._lock:
            if self.status in {"done", "partial", "failed", "cancelled"}:
                return
            self.stopped_early = bool(
                stopped_early and self.hits > 0 and not cancelled
            )
            if cancelled:
                self.status = "cancelled"
            elif self.stopped_early:
                self.status = "done"
            elif self.total == 0 or self.failed >= self.total:
                self.status = "failed"
            elif self.failed:
                self.status = "partial"
            else:
                self.status = "done"
            self.finished_at = utc_now()
            self._finished_mono = time.monotonic()
            self.in_flight.clear()
            unchecked = max(0, self.total - self.checked)
            if cancelled:
                level = "warning"
                summary = (
                    f"扫描已取消：{self.checked}/{self.total} 已检查，"
                    f"{self.hits} 命中，{self.misses} 未找到，{self.failed} 失败，"
                    f"{unchecked} 未检查"
                )
            elif self.stopped_early:
                level = "success"
                summary = (
                    f"提前停止：已找到命中，{self.checked}/{self.total} 已检查，"
                    f"{self.hits} 命中，{self.misses} 未找到，{self.failed} 失败，"
                    f"{unchecked} 未检查"
                )
            else:
                level = {
                    "done": "success",
                    "partial": "warning",
                    "failed": "error",
                }.get(self.status, "info")
                summary = (
                    f"扫描结束：{self.checked}/{self.total} 已检查，"
                    f"{self.hits} 命中，{self.misses} 未找到，{self.failed} 失败"
                )
            self._event_unlocked(level, "", summary)

    def wait(self, timeout: float = 0.0) -> bool:
        """等待扫描进入终态；timeout<=0 表示一直等到结束。"""
        deadline = time.monotonic() + max(0.0, timeout) if timeout > 0 else 0.0
        while True:
            with self._lock:
                if self.status in {"done", "partial", "failed", "cancelled"}:
                    return True
            if deadline and time.monotonic() >= deadline:
                return False
            time.sleep(0.05)

    def snapshot(self) -> dict[str, Any]:
        """线程安全快照，供 HTTP 轮询与旧接口复用。"""
        with self._lock:
            end = self._finished_mono or time.monotonic()
            elapsed_ms = (
                int((end - self._started_mono) * 1000)
                if self._started_mono
                else 0
            )
            status = self.status
            if status == "running" and self._stop_event.is_set():
                status = "cancelling"
            unchecked_accounts = self._unchecked_accounts_unlocked()
            stop_reason = ""
            if status == "cancelled":
                stop_reason = "cancelled"
            elif self.stopped_early:
                stop_reason = "first_hit"
            return {
                "scan_id": self.id,
                "domain": self.domain,
                "status": status,
                "stop_on_first": self.stop_on_first,
                "stopped_early": self.stopped_early,
                "stop_reason": stop_reason,
                "total": self.total,
                "checked": self.checked,
                "unchecked": max(0, self.total - self.checked),
                "hits": self.hits,
                "misses": self.misses,
                "failed": self.failed,
                "results": [dict(row) for row in self.results],
                "errors": [dict(row) for row in self.errors],
                "missed_accounts": list(self.missed_accounts),
                "unchecked_accounts": unchecked_accounts,
                "events": [dict(row) for row in self.events[-MAX_EVENTS:]],
                "in_flight": list(self.in_flight),
                "started_at": self.started_at,
                "finished_at": self.finished_at,
                "elapsed_ms": elapsed_ms,
                "complete": (
                    self.total > 0
                    and self.checked >= self.total
                    and not self.stopped_early
                    and self.status in {"done", "partial", "failed"}
                ),
            }

    def _event_unlocked(self, level: str, account: str, message: str) -> None:
        """写事件；调用方必须持有锁。"""
        self.events.append(
            {
                "ts": utc_now(),
                "level": level,
                "account": account,
                "message": message,
            }
        )
        if len(self.events) > MAX_EVENTS:
            del self.events[: len(self.events) - MAX_EVENTS]


def _query_account_zone(
    account: dict[str, Any],
    domain: str,
    *,
    request_interval: float,
    max_retries: int,
    proxy_pool: Any,
    stop_event: Event,
) -> dict[str, Any]:
    """单账号查询：命中/未找到/失败三态，不抛异常给扫描器。"""
    name = account.get("name") or account.get("email") or "unknown"
    started = time.monotonic()
    try:
        updater = engine_adapter.build_updater(
            account,
            interval=request_interval,
            max_retries=max_retries,
            proxy_pool=proxy_pool,
            stop_event=stop_event,
        )
        zone = updater.get_zone_by_name(domain)
        elapsed_ms = int((time.monotonic() - started) * 1000)
        if zone:
            return {
                "account": name,
                "kind": "hit",
                "zone": zone.get("name") or domain,
                "zone_id": zone.get("id") or "",
                "status": zone.get("status") or "",
                "elapsed_ms": elapsed_ms,
            }
        return {"account": name, "kind": "miss", "elapsed_ms": elapsed_ms}
    except KeyboardInterrupt:
        return {
            "account": name,
            "kind": "cancelled",
            "elapsed_ms": int((time.monotonic() - started) * 1000),
        }
    except Exception as exc:  # noqa: BLE001 - 单账号失败不中断全账号扫描
        return {
            "account": name,
            "kind": "error",
            "error": str(exc)[:MAX_ERROR_CHARS] or "未知错误",
            "elapsed_ms": int((time.monotonic() - started) * 1000),
        }


def run_find_scan(
    scan: FindScan,
    accounts: list[dict[str, Any]],
    speed: dict[str, Any],
    proxy_pool: Any = None,
    query_fn: Callable[..., dict[str, Any]] = _query_account_zone,
) -> None:
    """在工作线程中执行一次扫描（也供旧同步接口直接调用）。"""
    scan.start()
    workers = max(1, min(20, int(speed.get("account_workers", 3))))
    interval = max(0.0, float(speed.get("request_interval", 0.0)))
    max_retries = max(0, min(20, int(speed.get("max_retries", 5))))
    executor = ThreadPoolExecutor(max_workers=workers)
    futures: dict[Future[dict[str, Any]], dict[str, Any]] = {}

    def _run_one(account: dict[str, Any]) -> dict[str, Any]:
        """线程入口：真正开始查询时才标记 in-flight。"""
        name = account.get("name") or account.get("email") or "unknown"
        if scan._stop_event.is_set():
            return {"account": name, "kind": "cancelled", "elapsed_ms": 0}
        scan.mark_in_flight(name)
        try:
            return query_fn(
                account,
                scan.domain,
                request_interval=interval,
                max_retries=max_retries,
                proxy_pool=proxy_pool,
                stop_event=scan._stop_event,
            )
        except KeyboardInterrupt:
            return {"account": name, "kind": "cancelled", "elapsed_ms": 0}
        except Exception as exc:  # noqa: BLE001 - 线程内异常转单账号失败
            return {
                "account": name,
                "kind": "error",
                "error": str(exc)[:MAX_ERROR_CHARS] or "未知错误",
                "elapsed_ms": 0,
            }

    try:
        for account in accounts:
            if scan._stop_event.is_set():
                break
            futures[executor.submit(_run_one, account)] = account
        while futures:
            if scan._stop_event.is_set() or scan.should_stop_after_hit():
                break
            done, _ = wait(
                futures,
                timeout=0.5,
                return_when=FIRST_COMPLETED,
            )
            for future in done:
                futures.pop(future, None)
                try:
                    result = future.result()
                except KeyboardInterrupt:
                    if scan._stop_event.is_set():
                        continue
                    result = {
                        "account": "unknown",
                        "kind": "error",
                        "error": "查询被中断",
                        "elapsed_ms": 0,
                    }
                except Exception as exc:  # noqa: BLE001 - 线程内异常转单账号失败
                    if scan._stop_event.is_set():
                        continue
                    result = {
                        "account": "unknown",
                        "kind": "error",
                        "error": str(exc)[:MAX_ERROR_CHARS] or "未知错误",
                        "elapsed_ms": 0,
                    }
                scan.record(result)
            if scan.should_stop_after_hit():
                break
    finally:
        cancelled = scan._stop_event.is_set() or scan.status == "cancelling"
        stopped_early = scan.should_stop_after_hit() and not cancelled
        for future in futures:
            future.cancel()
        executor.shutdown(
            wait=not (cancelled or stopped_early),
            cancel_futures=True,
        )
        scan.finish(cancelled=cancelled, stopped_early=stopped_early)


def find_sync(
    domain: str,
    accounts: list[dict[str, Any]],
    speed: dict[str, Any],
    proxy_pool: Any = None,
    query_fn: Callable[..., dict[str, Any]] = _query_account_zone,
    stop_on_first: bool = False,
) -> dict[str, Any]:
    """旧 `/api/v1/find` 的同步实现，返回兼容字段 + 覆盖统计。

    旧接口保持原来的“扫描全部账号”语义，避免 v1 只拿到第一个命中。
    """
    names = [a.get("name") or a.get("email") or "unknown" for a in accounts]
    scan = FindScan(
        id="sync",
        domain=domain,
        account_names=names,
        stop_on_first=stop_on_first,
    )
    run_find_scan(scan, accounts, speed, proxy_pool, query_fn)
    snap = scan.snapshot()
    return {
        "domain": snap["domain"],
        "found": snap["hits"],
        "checked": snap["checked"],
        "missed": snap["misses"],
        "failed": snap["failed"],
        "complete": snap["complete"],
        "stop_on_first": snap["stop_on_first"],
        "stopped_early": snap["stopped_early"],
        "unchecked": snap["unchecked"],
        "results": [
            {
                "account": row["account"],
                "zone": row["zone"],
                "zone_id": row["zone_id"],
                "status": row["status"],
                "elapsed_ms": row["elapsed_ms"],
            }
            for row in snap["results"]
        ],
        "errors": snap["errors"],
    }


class FindScanManager:
    """内存中的扫描注册表：限制并发扫描数，保留最近结果。"""

    def __init__(
        self,
        max_parallel_scans: int = 2,
        query_fn: Callable[..., dict[str, Any]] = _query_account_zone,
    ) -> None:
        self._pool = ThreadPoolExecutor(max_workers=max(1, max_parallel_scans))
        self._scans: dict[str, FindScan] = {}
        self._lock = Lock()
        self._counter = itertools.count(1)
        self._query_fn = query_fn

    def start(
        self,
        domain: str,
        accounts: list[dict[str, Any]],
        speed: dict[str, Any],
        proxy_pool: Any = None,
        stop_on_first: bool = True,
    ) -> FindScan:
        """创建扫描并立即返回快照对象。"""
        scan_id = f"scan-{next(self._counter):04d}"
        names = [a.get("name") or a.get("email") or "unknown" for a in accounts]
        scan = FindScan(
            id=scan_id,
            domain=domain,
            account_names=names,
            stop_on_first=stop_on_first,
            speed=dict(speed),
        )
        with self._lock:
            self._scans[scan_id] = scan
            self._prune_unlocked()
        self._pool.submit(
            run_find_scan,
            scan,
            accounts,
            speed,
            proxy_pool,
            self._query_fn,
        )
        return scan

    def get(self, scan_id: str) -> Optional[FindScan]:
        with self._lock:
            return self._scans.get(scan_id)

    def cancel(self, scan_id: str) -> bool:
        scan = self.get(scan_id)
        return bool(scan and scan.cancel())

    def continue_scan(
        self,
        scan_id: str,
        accounts: list[dict[str, Any]],
        proxy_pool: Any = None,
    ) -> FindScan:
        """在已结束的扫描上继续检查未检查账号。

        Raises:
            KeyError: 扫描不存在。
            ValueError: 仍在运行、没有未检查账号或配置中找不到对应账号。
        """
        scan = self.get(scan_id)
        if scan is None:
            raise KeyError(scan_id)
        unchecked = scan.unchecked_names()
        if not unchecked:
            raise ValueError("没有未检查的账号")
        by_name = {
            account.get("name") or account.get("email") or "unknown": account
            for account in accounts
        }
        remaining = [by_name[name] for name in unchecked if name in by_name]
        if not remaining:
            raise ValueError("未找到可继续的账号配置")
        if not scan.begin_continuation():
            raise ValueError("扫描仍在进行，不能继续")
        scan._start_note = f"继续扫描剩余 {len(remaining)} 个账号"
        speed = dict(scan.speed or {})
        if not speed:
            speed = {
                "speed": "eco",
                "account_workers": 3,
                "request_interval": 0.5,
                "max_retries": 5,
            }
        self._pool.submit(
            run_find_scan,
            scan,
            remaining,
            speed,
            proxy_pool,
            self._query_fn,
        )
        return scan

    def shutdown(self) -> None:
        """停止接受新扫描并取消正在运行的扫描（测试/退出用）。"""
        with self._lock:
            scans = list(self._scans.values())
            self._scans.clear()
        for scan in scans:
            scan.cancel()
        self._pool.shutdown(wait=False, cancel_futures=True)

    def _prune_unlocked(self) -> None:
        if len(self._scans) <= MAX_SCANS:
            return
        for key in list(self._scans):
            scan = self._scans[key]
            if scan.status not in {"pending", "running", "cancelling"}:
                del self._scans[key]
                if len(self._scans) <= MAX_SCANS:
                    return
