#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""domain_fix.py — spaceship 正常域名与 Cloudflare 激活 zone 差集检测与修复工具

背景:
    Cloudflare 偶尔会误删仍然正常的域名(zone)。本工具把 spaceship 账号下的
    全部正常域名,与 Cloudflare 全部账号的 active zone 做差集,找出"在
    spaceship 正常、却不在 Cloudflare"的缺失域名,并可将它们重新添加
    (create_zone) 到指定的 Cloudflare 账号,并按需补齐 DNS 记录、等待激活、
    重建邮箱转发、设置 SSL 与基础安全/加速选项。

流程:
    [1] 导出 spaceship 正常域名      -> <输出目录>/spaceship_normal_domains.csv
    [2] 导出 Cloudflare active zone  -> <输出目录>/cf_active_domains.csv
    [3] 差集(spaceship 正常 - CF)    -> <输出目录>/missing_domains.csv
        如给出 --whitelist,再取差集与白名单的交集
                                     -> <输出目录>/missing_domains_whitelisted.csv
    [4] --apply 时重新添加最终域名并补齐配置 -> <输出目录>/fix_results.csv

默认输出目录: <spaceship 配置文件所在目录>/domain_fix
默认直接执行(--apply): 查询、导出、计算差集后真正修复;仅预览时显式加 --dry-run。
白名单: 纯文本文件,一行一个域名,自动去除多余空格/行内注释,支持 http(s):// 与 IDN。
过期过滤: 默认不过滤;加 --exclude-expired 可剔除已过期域名
         (expirationDate<=当前时间;缺失/无法解析则保留)。
数据来源: 默认联网计算最新结果;也可用 --ss-csv/--cf-csv 指定已有 CSV,
          或 --no-export 复用默认文件,或 --missing-csv 直接使用已算好的差集。

DNS 记录指定方式(优先级从高到低):
    1. --records-file 中该域名的行;
    2. --record 指定的全局记录;
    3. --zones-file(旧 domain,ip,forward,security,ssl)中的 ip,或 --server-ip;
       自动生成 A/AAAA @ 与 www 两条记录(典型场景)。
    若以上都缺,则跳过 DNS 步骤(不会写入错误记录)。

配置兼容:
    - cf 配置(JSON)顶层: default_forward_email / ssl_mode / security_mode
    - cf 账号(JSON)字段: default_server_ip
    - --zones-file 兼容旧 cf_domains 表格列: domain,ip,forward,security,ssl,Note
"""

from __future__ import annotations

import argparse
import atexit
import builtins
import csv
import ipaddress
import json
import logging
import os
import signal
import sys
import time
from concurrent.futures import (
    FIRST_COMPLETED,
    Future,
    ThreadPoolExecutor,
    wait,
)
from dataclasses import dataclass, field
from datetime import datetime, timezone
from threading import Event, Lock, current_thread, local as thread_local
from typing import Any, Optional

# 复用两个既有工具目录中的实现:它们是平铺脚本,直接加入 sys.path 后按模块导入。
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_PYS_DIR = os.path.dirname(_THIS_DIR)
for _tool_dir in (
    os.path.join(_PYS_DIR, "spaceship_api"),
    os.path.join(_PYS_DIR, "cf_api"),
):
    if _tool_dir not in sys.path:
        sys.path.insert(0, _tool_dir)

import cloudflare_dns_tool as cf  # noqa: E402
import spaceship_api as ss  # noqa: E402


def _script_version() -> str:
    """脚本版本取自身文件修改时间（YYYY.MM.DD-HHMM），每次运行自动带上。"""
    try:
        mtime = os.path.getmtime(__file__)
    except OSError:
        return "unknown"
    return datetime.fromtimestamp(mtime).strftime("%Y.%m.%d-%H%M")


VERSION = _script_version()

# 多线程下保证单行日志原子输出：log_print 由多个工作线程调用，若不串行化，
# 同一行的片段可能与其它线程的输出交错。
_PRINT_LOCK = Lock()

# Ctrl+C 计数：第一次优雅收尾，第二次强制退出（见 install_interrupt_handler）。
_INTERRUPT_COUNT = 0

# 日志落盘：给出 --log-file 后，把 stdout/stderr 全量 tee 到文件；log_print 的
# 结构化行（时间/级别/线程）直接写入同一文件。两者共用一个文件句柄与锁，因此
# 既不会漏掉底层库的裸 print / traceback，也不会把 log_print 重复记两次。
_LOG_SINK: Optional["_LogSink"] = None
_LOG_LEVEL_VALUE = logging.INFO
_ORIGINAL_STDOUT = sys.stdout
_ORIGINAL_STDERR = sys.stderr


class _LogSink:
    """线程安全的日志文件句柄：结构化行与裸输出共用，按行落盘。"""

    def __init__(self, path: str, overwrite: bool) -> None:
        parent = os.path.dirname(os.path.abspath(path))
        if parent:
            os.makedirs(parent, exist_ok=True)
        self._fh = open(path, "w" if overwrite else "a", encoding="utf-8", buffering=1)
        self._lock = Lock()
        self._closed = False

    def write_structured(
        self, stamp: str, level_name: str, thread_name: str, message: str
    ) -> None:
        with self._lock:
            if self._closed:
                return
            self._fh.write(f"{stamp}\t{level_name}\t{thread_name}\t{message}\n")
            self._fh.flush()

    def write_raw(self, text: str) -> None:
        with self._lock:
            if self._closed:
                return
            self._fh.write(text)
            if "\n" in text:
                self._fh.flush()

    def flush(self) -> None:
        with self._lock:
            if not self._closed:
                self._fh.flush()

    def close(self) -> None:
        with self._lock:
            if self._closed:
                return
            self._closed = True
            try:
                self._fh.flush()
            finally:
                self._fh.close()


class _TeeStream:
    """把写入同时转发给原始流与日志文件；未启用文件日志时不使用本类。"""

    def __init__(self, original: Any, sink: _LogSink) -> None:
        self._original = original
        self._sink = sink

    def write(self, text: str) -> int:
        written = self._original.write(text)
        self._sink.write_raw(text)
        return written if isinstance(written, int) else len(text)

    def writelines(self, lines: Any) -> None:
        for line in lines:
            self.write(line)

    def flush(self) -> None:
        self._original.flush()
        self._sink.flush()

    def close(self) -> None:
        # 不关闭原始流（进程退出时由解释器负责），只保证日志已落盘。
        self.flush()

    @property
    def encoding(self) -> str:
        return getattr(self._original, "encoding", "utf-8")

    @property
    def errors(self) -> Any:
        return getattr(self._original, "errors", None)

    def isatty(self) -> bool:
        try:
            return bool(self._original.isatty())
        except Exception:  # noqa: BLE001
            return False

    def fileno(self) -> int:
        return self._original.fileno()

    def __getattr__(self, name: str) -> Any:
        return getattr(self._original, name)


def _shutdown_logging() -> None:
    """进程退出：恢复原始流并关闭日志文件。"""
    global _LOG_SINK
    sink = _LOG_SINK
    if sink is None:
        return
    sys.stdout = _ORIGINAL_STDOUT
    sys.stderr = _ORIGINAL_STDERR
    sink.flush()
    sink.close()
    _LOG_SINK = None


def configure_logging(log_file: Optional[str], log_level: str, overwrite: bool) -> None:
    """配置日志：控制台照常打印；给出 --log-file 后同时写入文件（默认关闭）。

    启用文件后采取“全量捕获”：stdout/stderr 上的一切输出（含底层库的裸 print 与
    未捕获异常的 traceback）都会同步进文件；本工具经 log_print 发出的行另以
    时间/级别/线程名的结构化格式记录，两者共用同一文件、不会重复。默认追加写入，
    避免误删历史审计记录。
    """
    global _LOG_SINK, _LOG_LEVEL_VALUE, _ORIGINAL_STDOUT, _ORIGINAL_STDERR

    _LOG_LEVEL_VALUE = getattr(logging, (log_level or "INFO").upper(), logging.INFO)

    if not log_file:
        return

    _ORIGINAL_STDOUT = sys.stdout
    _ORIGINAL_STDERR = sys.stderr
    _LOG_SINK = _LogSink(log_file, overwrite)
    sys.stdout = _TeeStream(_ORIGINAL_STDOUT, _LOG_SINK)
    sys.stderr = _TeeStream(_ORIGINAL_STDERR, _LOG_SINK)
    atexit.register(_shutdown_logging)


def logging_enabled() -> bool:
    """判断是否已配置日志文件（即是否给出 --log-file）。"""
    return _LOG_SINK is not None


def log_print(*args, level: int = logging.INFO, **kwargs) -> None:
    """同时输出到控制台和日志文件（与 cf_api.log_print 同行为）。

    控制台行首带本地时间戳；调用方传 sep/end/file 等仍透传（sep 仅用于拼接）。
    启用文件日志时，控制台写入**绕过** tee，改由 _LogSink 记录结构化行，避免
    log_print 在文件里出现两次（tee 一次 + 结构化一次）。
    """
    sep = kwargs.pop("sep", " ")
    message = sep.join(str(arg) for arg in args)
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    requested = kwargs.pop("file", None)

    with _PRINT_LOCK:
        if _LOG_SINK is None:
            # 未启用文件日志：沿用原行为，写入调用时指定的流（默认当前 stdout）。
            if requested is None:
                builtins.print(f"{stamp} {message}", **kwargs)
            else:
                builtins.print(f"{stamp} {message}", file=requested, **kwargs)
            return

        if requested is None or requested is sys.stdout or requested is _ORIGINAL_STDOUT:
            console = _ORIGINAL_STDOUT
        elif requested is sys.stderr or requested is _ORIGINAL_STDERR:
            console = _ORIGINAL_STDERR
        else:
            console = requested
        builtins.print(f"{stamp} {message}", file=console, **kwargs)
        if level >= _LOG_LEVEL_VALUE:
            _LOG_SINK.write_structured(
                stamp, logging.getLevelName(level), current_thread().name, message
            )


def install_interrupt_handler(stop_event: Event) -> None:
    """安装 Ctrl+C 处理器：第一次优雅收尾，第二次强制退出。

    - 第一次 Ctrl+C：设置 stop_event，主线程抛出 KeyboardInterrupt，交给上层
      取消排队任务、等待进行中任务收尾并落盘（不产生 traceback）。
    - 第二次 Ctrl+C：说明用户不想再等。先刷新标准输出，再以退出码 130 立即结束，
      跳过收尾（当某个请求卡在网络等待中时提供逃生通道）。
    """

    def _handle_sigint(_signum: int, _frame: object) -> None:
        global _INTERRUPT_COUNT
        _INTERRUPT_COUNT += 1
        if _INTERRUPT_COUNT == 1:
            stop_event.set()
            raise KeyboardInterrupt
        # 第二次：强制退出，不再等待收尾。
        try:
            sys.stdout.flush()
            sys.stderr.flush()
        except Exception:  # noqa: BLE001 - 强制退出路径不因刷新失败而卡住
            pass
        sys.stderr.write("\n再次收到 Ctrl+C，强制退出。\n")
        os._exit(130)

    signal.signal(signal.SIGINT, _handle_sigint)


# 常见配置目录候选(与 spaceship_api_demo.py / cf 工具默认路径保持一致)。
CONFIG_DIR_CANDIDATES = [
    r"C:/repos/configs/deploy_configs",
    ss.DEPLOY_CONFIGS,
]

SS_CSV_NAME = "spaceship_normal_domains.csv"  # 默认(status=normal)时的文件名
CF_CSV_NAME = "cf_active_domains.csv"
MISSING_CSV_NAME = "missing_domains.csv"
WHITELIST_CSV_NAME = "missing_domains_whitelisted.csv"
FIX_CSV_NAME = "fix_results.csv"
UNFINISHED_CSV_NAME = "unfinished_domains.csv"  # 中断时未处理域名（供断点/人工核对）

FIX_CSV_FIELDNAMES = [
    "account",
    "domain",
    "zone_status",
    "zone_id",
    "nameservers",
    "activation",
    "record_status",
    "email_status",
    "ssl_status",
    "security_status",
    "error",
    "timestamp",
]

UNFINISHED_CSV_FIELDNAMES = ["tag", "domain", "account", "reason"]

# 记录文件列(供 load_records_config 参考;安全/加速设置已集中在 cf_api)
RECORD_FIELDS = ["domain", "name", "type", "content", "proxied", "ttl", "priority"]


def now_iso() -> str:
    """返回当前 UTC 时间的 ISO8601 字符串。"""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def normalize_domain(value: Any) -> str:
    """域名归一化:去空白、去尾点、转小写,便于跨来源比较。"""
    if value is None:
        return ""
    return str(value).strip().strip(".").lower()


def spaceship_csv_name(status: str) -> str:
    """spaceship 域名 CSV 文件名;normal 使用固定名,其余状态带状态名。"""
    return SS_CSV_NAME if status == "normal" else f"spaceship_{status}_domains.csv"


def _clean_whitelist_line(line: str) -> str:
    """清洗白名单中的一行:去空白/注释,兼容 http(s):// 与路径,返回归一化域名。"""
    text = (line or "").strip()
    if not text or text.startswith("#"):
        return ""
    text = text.split("#", 1)[0].strip()
    if "://" in text:
        text = text.split("://", 1)[1]
    text = text.split("/", 1)[0].strip()
    tokens = text.split()
    if not tokens:
        return ""
    return normalize_domain(tokens[0])


def load_whitelist(path: str) -> list[str]:
    """读取白名单文本文件:一行一个域名,自动去除多余空格与行内注释。"""
    if not os.path.exists(path):
        raise FileNotFoundError(f"白名单文件不存在: {path}")
    entries: list[str] = []
    seen: set[str] = set()
    with open(path, "r", encoding="utf-8-sig") as file_obj:
        for raw in file_obj:
            domain = _clean_whitelist_line(raw)
            if domain and domain not in seen:
                seen.add(domain)
                entries.append(domain)
    return entries


def _whitelist_aliases(whitelist: list[str]) -> set[str]:
    """把白名单域名扩展为匹配集合,附加 punycode 写法以兼容 IDN。"""
    allowed: set[str] = set()
    for domain in whitelist:
        allowed.add(domain)
        try:
            allowed.add(domain.encode("idna").decode("ascii").lower())
        except Exception:  # noqa: BLE001 - 非法 IDN 忽略别名即可
            continue
    return allowed


def intersect_with_whitelist(
    missing_rows: list[dict[str, str]], whitelist: list[str]
) -> list[dict[str, str]]:
    """取差集与白名单的交集(白名单为空时返回原差集)。"""
    if not whitelist:
        return list(missing_rows)
    allowed = _whitelist_aliases(whitelist)
    result: list[dict[str, str]] = []
    for row in missing_rows:
        candidates = {
            normalize_domain(row.get("name")),
            normalize_domain(row.get("unicodeName")),
        }
        candidates.discard("")
        if candidates & allowed:
            result.append(row)
    return result


def pick_first_existing(candidates: list[str]) -> str:
    """返回候选路径中第一个存在的;若都不存在则返回第一个。"""
    for path in candidates:
        if path and os.path.exists(path):
            return path
    return candidates[0] if candidates else ""


def resolve_default_configs() -> tuple[str, str]:
    """解析默认的 spaceship / cloudflare 配置文件路径。"""
    ss_config = pick_first_existing(
        [os.path.join(d, "spaceship_config.json") for d in CONFIG_DIR_CANDIDATES]
        + [ss.DEFAULT_CONFIG_PATH]
    )
    cf_config = pick_first_existing(
        [os.path.join(d, "cf_config.csv") for d in CONFIG_DIR_CANDIDATES]
        + [os.path.join(d, "cf_config.json") for d in CONFIG_DIR_CANDIDATES]
        + [cf.CF_CONFIG_PATH]
    )
    return ss_config, cf_config


def read_csv_rows(path: str) -> list[dict[str, str]]:
    """读取 CSV(兼容 Excel 的 UTF-8-SIG 编码),返回字典行列表。"""
    if not os.path.exists(path):
        raise FileNotFoundError(f"CSV 不存在: {path}")
    with open(path, "r", newline="", encoding="utf-8-sig") as file_obj:
        reader = csv.DictReader(file_obj)
        return [dict(row) for row in reader]


def write_csv_rows(
    path: str,
    rows: list[dict[str, Any]],
    fieldnames: Optional[list[str]] = None,
) -> None:
    """写入 CSV(UTF-8-SIG,Excel 可直接打开);父目录自动创建。"""
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    if fieldnames is None:
        ordered: list[str] = []
        for row in rows:
            for key in row:
                if key not in ordered:
                    ordered.append(key)
        fieldnames = ordered or ["name"]
    with open(path, "w", newline="", encoding="utf-8-sig") as file_obj:
        writer = csv.DictWriter(file_obj, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def export_spaceship_domains(
    ss_config: str, path: str, status: str, exclude_expired: bool = False
) -> tuple[int, str]:
    """导出 spaceship 所有账号中指定状态的域名到 CSV。"""
    log_print(f"[1/4] 读取 spaceship 域名: 配置={ss_config}, 状态={status}")
    auth = ss.get_auth(ss_config)
    client = ss.APIClient(auth["api_key"], auth["api_secret"], auth=auth)
    grouped = client.list_domains_from_all_accounts(auth, output="", names_only=False)
    filtered: list[dict[str, Any]] = []
    total = 0
    for entry in grouped or []:
        account = entry.get("account", "")
        doms = entry.get("domains", {})
        items = doms.get("items", []) if isinstance(doms, dict) else (doms or [])
        kept = ss.filter_domains_by_status(
            items, status=status, exclude_expired=exclude_expired
        )
        filtered.append(
            {
                "account": account,
                "domains": {"items": kept, "total": len(kept)},
                "total": len(kept),
            }
        )
        total += len(kept)
    ss.export_domains_to_csv(filtered, path)
    log_print(f"      -> 已导出 {total} 个域名(状态={status})到 {path}")
    return total, path


def build_cf_args(
    zone_status: str,
    workers: int,
    account_workers: int,
    request_interval: float,
    zones_output: str,
) -> argparse.Namespace:
    """构造 cf_api 命令行工具所需的参数命名空间,复用其 zone 导出逻辑。"""
    return argparse.Namespace(
        zone_status=zone_status,
        zones_output=zones_output,
        workers=workers,
        account_workers=account_workers,
        request_interval=request_interval,
        rate_limit_scope="global",
        api_max_retries=cf.DEFAULT_API_MAX_RETRIES,
        api_retry_base_delay=cf.DEFAULT_API_RETRY_BASE_DELAY,
        api_retry_max_sleep=cf.DEFAULT_API_RETRY_MAX_SLEEP,
        proxy=None,
        proxy_file=None,
        proxy_mode=cf.PROXY_DEFAULT_MODE,
    )


def export_cf_active_zones(
    cf_config: str,
    path: str,
    zone_status: str,
    workers: int,
    account_workers: int,
    request_interval: float,
    stop_event: Optional[Event] = None,
) -> tuple[int, str]:
    """调用 cf_api 逻辑导出所有账号的 zone(默认只保留 active)到 CSV。

    stop_event 由调用方传入并复用（与主流程共享），Ctrl+C 时各账号的读取线程
    能立即收到停止信号，无需等分页请求全部跑完。
    """
    log_print(f"[2/4] 读取 Cloudflare zone: 配置={cf_config}, 状态={zone_status}")
    accounts = cf.get_cf_accounts(cf_config)
    if not accounts:
        raise RuntimeError(f"Cloudflare 配置中没有可用账号: {cf_config}")
    stop_event = stop_event or Event()
    rate_limiter: Optional[cf.ApiRateLimiter] = (
        cf.ApiRateLimiter(request_interval, stop_event)
        if request_interval and request_interval > 0
        else None
    )
    args = build_cf_args(
        zone_status=zone_status,
        workers=workers,
        account_workers=account_workers,
        request_interval=request_interval,
        zones_output=path,
    )
    code = cf.run_list_zones_mode(
        accounts=accounts,
        args=args,
        stop_event=stop_event,
        rate_limiter=rate_limiter,
        proxy_pool=None,
    )
    if code != 0:
        log_print(
            "      注意: 有部分 Cloudflare 账号读取失败,差集可能不完整!",
            file=sys.stderr,
        )
    rows = read_csv_rows(path)
    log_print(f"      -> 已导出 {len(rows)} 个 zone 到 {path}")
    return len(rows), path


def compute_missing(
    ss_rows: list[dict[str, str]], cf_rows: list[dict[str, str]]
) -> tuple[list[dict[str, str]], set[str]]:
    """计算差集:在 spaceship(正常)中、但不在 Cloudflare(active)中的域名。"""
    cf_names: set[str] = set()
    for row in cf_rows:
        name = normalize_domain(row.get("name") or row.get("zone"))
        if name:
            cf_names.add(name)

    missing: list[dict[str, str]] = []
    for row in ss_rows:
        candidates = {
            normalize_domain(row.get("name")),
            normalize_domain(row.get("unicodeName")),
        }
        candidates.discard("")
        if not candidates:
            continue
        if candidates & cf_names:
            continue
        missing.append(row)
    return missing, cf_names


def select_target_account(accounts: list[dict], selector: str) -> dict:
    """按账号名 / 邮箱 / 数字索引选择目标账号;selector 为空时取最后一个。"""
    if not selector:
        return accounts[-1]
    selector = selector.strip()
    if selector.isdigit():
        idx = int(selector)
        if 1 <= idx <= len(accounts):
            return accounts[idx - 1]
        raise ValueError(f"账号索引超出范围: {selector}(共 {len(accounts)} 个账号)")
    target = selector.lower()
    for account in accounts:
        name = str(account.get("name") or "").strip().lower()
        email = str(account.get("email") or "").strip().lower()
        if target in {name, email}:
            return account
    raise ValueError(f"未找到匹配的 Cloudflare 账号: {selector}")


def _parse_bool(value: Any, default: bool) -> bool:
    """把表格里的布尔值解析为 bool;空值返回默认值。"""
    if value is None:
        return default
    text = str(value).strip().lower()
    if text == "":
        return default
    return text in {"1", "true", "yes", "y", "on", "是"}


def _read_json_file(path: str) -> dict:
    """安全读取 JSON 文件,失败返回空 dict。"""
    try:
        with open(path, "r", encoding="utf-8") as file_obj:
            data = json.load(file_obj)
    except Exception:  # noqa: BLE001 - 配置缺失/损坏按无配置处理
        return {}
    return data if isinstance(data, dict) else {}


def load_cf_legacy_defaults(cf_config: str, account_name: str) -> tuple[dict, str]:
    """读取 cf 旧配置的全局默认值与指定账号的 default_server_ip。

    兼容旧 cf_config.json 的顶层字段 default_forward_email/ssl_mode/security_mode
    与账号字段 default_server_ip。若传入的是 csv,但同目录存在 cf_config.json,
    则回退到该 json 读取这些旧字段(账号来源仍以 --cf-config 为准)。

    Returns:
        (globals, server_ip)
    """
    candidate_paths = [cf_config]
    if os.path.splitext(cf_config)[1].lower() != ".json":
        sibling = os.path.join(
            os.path.dirname(os.path.abspath(cf_config)), "cf_config.json"
        )
        if os.path.exists(sibling):
            candidate_paths.append(sibling)

    globals_: dict = {}
    server_ip = ""
    target = (account_name or "").strip().lower()
    for path in candidate_paths:
        if not path.lower().endswith(".json"):
            continue
        data = _read_json_file(path)
        if not data:
            continue
        if not globals_:
            for key in ("default_forward_email", "ssl_mode", "security_mode"):
                value = data.get(key)
                if value not in (None, ""):
                    globals_[key] = value
        accounts = data.get("accounts")
        if isinstance(accounts, dict) and target:
            for name, acc in accounts.items():
                if not isinstance(acc, dict):
                    continue
                identities = {
                    str(name).strip().lower(),
                    str(acc.get("account") or "").strip().lower(),
                    str(acc.get("cf_api_email") or "").strip().lower(),
                }
                if target in identities:
                    server_ip = server_ip or str(acc.get("default_server_ip") or "")
    return globals_, server_ip


def load_zones_config(path: str) -> dict[str, dict[str, str]]:
    """读取旧格式域名配置(domain,ip,forward,security,ssl,Note)。

    兼容 csv/xlsx 表格与简单 conf/txt(每行第一个 token 视为域名)。
    返回 domain -> {ip, forward, security, ssl}。
    """
    result: dict[str, dict[str, str]] = {}
    if not path or not os.path.exists(path):
        return result
    ext = os.path.splitext(path)[1].lower()
    if ext in {".csv", ".xlsx", ".xls"}:
        if ext == ".csv":
            rows = read_csv_rows(path)
        else:
            import pandas as pd  # 延迟导入,仅 Excel 需要

            frame = pd.read_excel(path, keep_default_na=False)
            rows = [
                {str(k).strip().lower(): v for k, v in row.items()}
                for row in frame.to_dict(orient="records")
            ]
        for row in rows:
            lowered = {
                str(k).strip().lower(): ("" if v is None else str(v).strip())
                for k, v in row.items()
            }
            domain = normalize_domain(lowered.get("domain"))
            if not domain:
                continue
            result[domain] = {
                "ip": lowered.get("ip", ""),
                "forward": lowered.get("forward", ""),
                "security": lowered.get("security", ""),
                "ssl": lowered.get("ssl", ""),
            }
        return result
    # conf/txt:每行第一个 token 为域名,忽略其余
    with open(path, "r", encoding="utf-8-sig") as file_obj:
        for raw in file_obj:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            domain = normalize_domain(line.split()[0])
            if domain:
                result.setdefault(
                    domain, {"ip": "", "forward": "", "security": "", "ssl": ""}
                )
    return result


def load_records_config(path: str) -> dict[str, list[dict[str, Any]]]:
    """读取 DNS 记录配置文件。

    CSV 列: domain,name,type,content,proxied,ttl,priority。
    domain 为空的行作为全局默认(应用到所有域名)。
    返回 domain -> [record,...]。
    """
    result: dict[str, list[dict[str, Any]]] = {}
    if not path or not os.path.exists(path):
        return result
    rows = read_csv_rows(path)
    for row in rows:
        lowered = {
            str(k).strip().lower(): ("" if v is None else str(v).strip())
            for k, v in row.items()
        }
        name = lowered.get("name", "") or "@"
        record_type = (lowered.get("type", "") or "A").upper()
        content = lowered.get("content", "")
        if not content:
            continue
        priority_raw = lowered.get("priority", "")
        record = {
            "name": name,
            "type": record_type,
            "content": content,
            "proxied": _parse_bool(lowered.get("proxied"), True),
            "ttl": int(lowered.get("ttl") or 1),
            "priority": int(priority_raw) if priority_raw else None,
        }
        key = normalize_domain(lowered.get("domain", ""))
        result.setdefault(key, []).append(record)
    return result


def _default_records_for_ip(ip: str, proxied: bool, ttl: int) -> list[dict[str, Any]]:
    """根据服务器 IP 生成典型的 @ 与 www 两条记录(A/AAAA 自动判断)。"""
    record_type = "A"
    try:
        if isinstance(ipaddress.ip_address(ip), ipaddress.IPv6Address):
            record_type = "AAAA"
    except ValueError:
        record_type = "A"
    return [
        {
            "name": "@",
            "type": record_type,
            "content": ip,
            "proxied": proxied,
            "ttl": ttl,
            "priority": None,
        },
        {
            "name": "www",
            "type": record_type,
            "content": ip,
            "proxied": proxied,
            "ttl": ttl,
            "priority": None,
        },
    ]


def resolve_records_for_domain(
    domain: str,
    zones_config: dict[str, dict[str, str]],
    records_by_domain: dict[str, list[dict[str, Any]]],
    global_records: list[dict[str, Any]],
    server_ip: str,
    proxied_default: bool,
    ttl_default: int,
) -> list[dict[str, Any]]:
    """按优先级解析某域名应写入的 DNS 记录。"""
    if records_by_domain.get(domain):
        return records_by_domain[domain]
    if records_by_domain.get(""):
        return records_by_domain[""]
    if global_records:
        return global_records
    ip = (zones_config.get(domain, {}) or {}).get("ip") or server_ip
    if ip:
        return _default_records_for_ip(ip, proxied_default, ttl_default)
    return []


def parse_global_records(
    specs: list[str], proxied: bool, ttl: int
) -> list[dict[str, Any]]:
    """把 --record 参数解析为记录字典列表(复用 cf 工具的解析规则)。"""
    records: list[dict[str, Any]] = []
    for spec in specs or []:
        name, record_type, content = cf.parse_add_record_spec(spec)
        records.append(
            {
                "name": name,
                "type": record_type,
                "content": content,
                "proxied": proxied,
                "ttl": ttl,
                "priority": None,
            }
        )
    return records


@dataclass
class ProvisionOptions:
    """域名修复/配置流程的解析后选项。"""

    account: dict
    output_dir: str
    add_workers: int
    request_interval: float
    server_ip: str
    forward_email: str
    ssl_mode: str
    do_dns: bool
    do_activation: bool
    do_email: bool
    do_ssl: bool
    do_security: bool
    do_optimize: bool
    set_nameservers: bool
    activation_timeout: float
    activation_interval: float
    proxied_default: bool
    ttl_default: int
    allow_multi_value: bool
    records_by_domain: dict[str, list[dict[str, Any]]]
    global_records: list[dict[str, Any]]
    zones_config: dict[str, dict[str, str]]
    revisit_timeout: float = 1800.0
    ss_auth: dict = field(default_factory=dict)
    # 第一遍是否在单域内等待激活。默认 False：第一遍只建站/NS/DNS（快），
    # 激活与补邮箱统一交给批量回访（_revisit_until_done），避免工作线程被
    # 单个域名的激活轮询占满。仅当关闭回访（--revisit-timeout 0）时才回退为
    # 单域内等待，保持旧行为。
    first_pass_wait: bool = False
    # 详情日志：逐条打印 DNS 记录（名/类型/内容/状态）与邮箱各步骤。默认开启。
    detail: bool = True
    # 每线程一个 spaceship 客户端：update_nameservers 会改写客户端账号凭证，
    # 共享实例在跨账号并发时会串号，故按线程隔离；同时避免每域名重建客户端。
    _ss_local: Any = field(default_factory=thread_local, repr=False, compare=False)


def _ss_client_for_thread(opt: ProvisionOptions) -> Optional[ss.APIClient]:
    """返回当前线程复用的 spaceship 客户端（无认证配置时返回 None）。"""
    if not opt.ss_auth:
        return None
    client = getattr(opt._ss_local, "client", None)
    if client is None:
        client = ss.APIClient(
            opt.ss_auth.get("api_key", ""),
            opt.ss_auth.get("api_secret", ""),
            auth=opt.ss_auth,
        )
        opt._ss_local.client = client
    return client


def _ss_select_account(client: Any, opt: ProvisionOptions, account_name: str) -> bool:
    """把线程内 spaceship 客户端切到指定账号，避免 update_nameservers 全账号扫描。

    spaceship 的 ``update_nameservers`` 会先调 ``get_domain_from_all_accounts``：若客户端
    当前凭证不对，就会遍历所有账号逐个探测（每个域名 ~20 次请求，日志噪音极大）。而差集
    CSV 的 ``account`` 列已经告诉我们域名属于哪个账号，先切好凭证即可首次命中，直接省掉
    整轮扫描。account_name 为空或不在配置中时返回 False（回退到原有查找逻辑）。
    """
    target = (account_name or "").strip().lower()
    if not target:
        return False
    accounts = opt.ss_auth.get("accounts") if opt.ss_auth else None
    if not isinstance(accounts, list):
        return False
    for acc in accounts:
        if not isinstance(acc, dict):
            continue
        if str(acc.get("account", "")).strip().lower() != target:
            continue
        client.account = str(acc.get("account", ""))
        client.api_key = str(acc.get("api_key", ""))
        client.api_secret = str(acc.get("api_secret", ""))
        return True
    return False


def _ns_host_set(value: Any) -> set[str]:
    """从 spaceship 返回的 nameservers 结构中提取主机集合(小写、去尾点)。

    兼容 dict（含 hosts/hostnames/nameservers 键）、list[str/dict]、纯字符串；
    不可识别返回空集合（调用方视为“查不到”，走原更新逻辑）。
    """
    hosts: set[str] = set()

    def add(item: Any) -> None:
        if isinstance(item, str) and item.strip():
            hosts.add(item.strip().rstrip(".").lower())

    items: Any = []
    if isinstance(value, dict):
        for key in ("hosts", "hostnames", "nameservers", "nameServers"):
            if isinstance(value.get(key), list):
                items = value[key]
                break
    elif isinstance(value, list):
        items = value
    elif isinstance(value, str):
        items = [value]
    for item in items:
        if isinstance(item, str):
            add(item)
        elif isinstance(item, dict):
            for key in ("host", "hostname", "name", "nameserver"):
                if item.get(key):
                    add(str(item[key]))
                    break
    return hosts


def _ns_current_hosts(ss_client: Any, domain: str) -> tuple[set[str], str]:
    """查询 spaceship 侧当前 NS 主机集合，返回 (hosts, error)。

    查询失败时 hosts 为空、error 非空；调用方据此直接走更新逻辑，并在详情日志里
    说明“当前 NS 未知”的原因。
    """
    try:
        current = ss_client.get_nameservers(domain)
    except Exception as exc:  # noqa: BLE001 - 查询失败不阻断，按需更新
        return set(), str(exc)
    return _ns_host_set(current), ""


def provision_one(
    updater: cf.CloudflareDNSUpdater,
    domain: str,
    opt: ProvisionOptions,
    ss_account: str = "",
) -> dict[str, str]:
    """对单个域名执行:创建 zone + DNS + 激活 + 邮箱 + SSL + 安全/加速。

    ss_account 为该域名在 spaceship 的所属账号（差集 CSV 的 account 列），用于预选
    凭证、避免改 NS 时全账号扫描；为空则沿用原有查找逻辑。
    """
    account_name = updater.account_name
    row: dict[str, str] = {
        "account": account_name,
        "domain": domain,
        "zone_status": "",
        "zone_id": "",
        "nameservers": "",
        "activation": "skipped",
        "record_status": "skipped",
        "email_status": "skipped",
        "ssl_status": "skipped",
        "security_status": "skipped",
        "error": "",
        "timestamp": now_iso(),
    }

    zone_id: Optional[str] = None
    zone_info: dict = {}
    try:
        data = updater.create_zone(domain)
        zone_info = data.get("result", {}) or {}
        zone_id = zone_info.get("id")
        row["zone_status"] = str(zone_info.get("status", "created"))
        if zone_id:
            # 供收尾统计区分“本次新建”与“已存在复用”；不写入 CSV 列。
            row["_created"] = True
    except Exception as exc:  # noqa: BLE001 - 已存在时回查,其它错误记账
        message = str(exc)
        lowered = message.lower()
        if "already exists" in lowered and "another user" in lowered:
            row["error"] = f"zone 已被其它 Cloudflare 用户占用: {message}"
            return row
        if "already exists" in lowered:
            try:
                existing = updater.get_zone_by_name(domain)
                if existing:
                    zone_info = existing
                    zone_id = existing.get("id")
                    row["zone_status"] = str(existing.get("status", "exists"))
                else:
                    row["zone_status"] = "exists"
                    row["error"] = "zone 已存在但未能在当前账号回查到"
            except Exception as exc2:  # noqa: BLE001
                row["error"] = f"zone 已存在但查询失败: {exc2}"
                return row
        else:
            row["error"] = f"创建 zone 失败: {message}"
            return row

    if zone_id:
        row["zone_id"] = str(zone_id)
    nameservers = ";".join(zone_info.get("name_servers") or [])
    row["nameservers"] = nameservers
    zone_name = str(zone_info.get("name") or domain)

    # NS 指向新 zone 分配的 nameservers(默认开启,安排在 DNS/激活之前,及时生效)；
    # 先查 spaceship 侧现状，已一致则跳过（nameservers-unchanged），避免每次重写。
    if opt.set_nameservers and nameservers and opt.ss_auth:
        hosts = [h for h in nameservers.split(";") if h]
        try:
            ss_client = _ss_client_for_thread(opt)
            if ss_client is None:
                raise RuntimeError("spaceship 客户端不可用")
            _ss_select_account(ss_client, opt, ss_account)
            wanted = {h.strip().rstrip(".").lower() for h in hosts if h.strip()}
            current_hosts, ns_err = _ns_current_hosts(ss_client, domain)
            if current_hosts and current_hosts == wanted:
                row["activation"] = "nameservers-unchanged"
                if opt.detail:
                    log_print(
                        f"      [NS] {domain} 当前NS={'; '.join(sorted(current_hosts))}"
                        " 与目标一致，跳过"
                    )
            else:
                if opt.detail:
                    old = (
                        "; ".join(sorted(current_hosts))
                        if current_hosts
                        else (ns_err or "未知")
                    )
                    log_print(
                        f"      [NS] {domain} 目标NS={'; '.join(hosts)}"
                        f"（当前: {old}）→ 更新"
                    )
                ss_client.update_nameservers(domain, "custom", hosts, auth=opt.ss_auth)
                row["activation"] = "nameservers-set"
                if opt.detail:
                    log_print(f"      [NS] {domain} spaceship 侧 NS 已更新")
        except Exception as exc:  # noqa: BLE001
            row["activation"] = f"nameservers-error:{exc}"
            if opt.detail:
                log_print(
                    f"      [NS] {domain} 更新失败: {exc}", level=logging.WARNING
                )

    if zone_id:
        zone_cfg = opt.zones_config.get(domain, {}) or {}
        records = resolve_records_for_domain(
            domain,
            opt.zones_config,
            opt.records_by_domain,
            opt.global_records,
            opt.server_ip,
            opt.proxied_default,
            opt.ttl_default,
        )
        cf_options = cf.ZoneProvisionOptions(
            records=records,
            forward_email=zone_cfg.get("forward") or opt.forward_email,
            ssl_mode=zone_cfg.get("ssl") or opt.ssl_mode,
            do_dns=opt.do_dns,
            do_activation=opt.first_pass_wait,
            do_email=opt.do_email,
            do_ssl=opt.do_ssl,
            do_security=opt.do_security,
            do_optimize=opt.do_optimize,
            activation_timeout=opt.activation_timeout,
            activation_interval=opt.activation_interval,
            allow_multi_value=opt.allow_multi_value,
            verbose=opt.detail,
            on_tick=lambda st, remain: log_print(
                f"      {domain} 状态={st},剩余 {remain:.0f}s"
            ),
        )
        statuses = cf.provision_zone(updater, zone_id, zone_name, domain, cf_options)
        ns_note = row["activation"]
        row["activation"] = (
            f"{ns_note}|{statuses['activation']}"
            if ns_note != "skipped"
            else statuses["activation"]
        )
        row["record_status"] = statuses["record_status"]
        row["email_status"] = statuses["email_status"]
        row["ssl_status"] = statuses["ssl_status"]
        row["security_status"] = statuses["security_status"]
        if statuses["error"]:
            row["error"] = statuses["error"]

    # 统一为“完成时间”：第一遍收尾时覆盖初始时间；此后回访刷新会再更新为最终时间。
    row["timestamp"] = now_iso()
    return row


def _needs_revisit(row: dict[str, str]) -> bool:
    """判断结果行是否需要回访：zone 已建好、无致命错误，但激活未完成或邮箱被延期。"""
    if not row.get("zone_id") or row.get("error"):
        return False
    if row.get("email_status", "").startswith("deferred"):
        return True
    activation = row.get("activation", "")
    return activation != "active" and not activation.endswith("|active")


def _revisit_row(
    updater: cf.CloudflareDNSUpdater,
    row: dict[str, str],
    opt: ProvisionOptions,
) -> None:
    """回访单行：刷新激活状态；若已 active 且邮箱被延期，则只补邮箱（幂等）。"""
    domain = row.get("domain", "")
    zone_id = row.get("zone_id", "")
    try:
        zone = updater.get_zone(zone_id) if zone_id else None
        status = str(((zone or {}).get("result") or {}).get("status") or "")
    except Exception as exc:  # noqa: BLE001
        row["activation"] = f"error:{exc}"
        return
    new_status = "active" if status == "active" else f"pending:{status or 'unknown'}"
    old_activation = row.get("activation", "")
    # 对 pending/moved 等未激活状态，主动触发一次激活检查（催激活）；每个域名每次运行
    # 只催一次，避免频繁调用。成功仅进入优先重查队列，不代表立即激活。
    if status and status != "active" and not row.get("_activation_nudged"):
        row["_activation_nudged"] = True
        try:
            updater.trigger_activation_check(zone_id)
            if opt.detail:
                log_print(f"      [激活] {domain} 已触发一次激活检查（当前 {status}）")
        except Exception as exc:  # noqa: BLE001
            log_print(
                f"      [激活] {domain} 触发激活检查失败: {exc}",
                level=logging.WARNING,
            )
    if "|" in old_activation:
        prefix = old_activation.split("|", 1)[0]
        row["activation"] = f"{prefix}|{new_status}"
    else:
        row["activation"] = new_status
    if status:
        # 刷新 zone_status，避免新建 zone 在激活后仍显示 pending，与 activation 矛盾。
        row["zone_status"] = status
    if status == "active" and row.get("email_status", "").startswith("deferred"):
        zone_cfg = opt.zones_config.get(domain, {}) or {}
        email_opt = cf.ZoneProvisionOptions(
            records=[],
            forward_email=zone_cfg.get("forward") or opt.forward_email,
            ssl_mode="",
            do_dns=False,
            do_activation=False,
            do_email=True,
            do_ssl=False,
            do_security=False,
            do_optimize=False,
            verbose=opt.detail,
        )
        try:
            statuses = cf.provision_zone(updater, zone_id, domain, domain, email_opt)
            row["email_status"] = statuses["email_status"]
            if statuses.get("error"):
                row["error"] = statuses["error"]
        except Exception as exc:  # noqa: BLE001
            row["error"] = f"回访补邮箱失败: {exc}"
    row["timestamp"] = now_iso()


def _row_partial_failure(row: dict[str, str]) -> bool:
    """判断行是否“部分失败”（非致命）：NS/记录/邮箱/SSL/安全任一步出错。

    这些错误只落在各自的列里，不写 error 列；单独统计，避免“失败 0”被误读为全绿。
    """
    if row.get("error"):
        return False  # 致命错误单独计入 failed
    if "error:" in str(row.get("activation", "")):
        return True
    if ":error" in str(row.get("record_status", "")):
        return True
    for key in ("email_status", "ssl_status"):
        if str(row.get(key, "")).startswith("error"):
            return True
    if "errors=" in str(row.get("security_status", "")):
        return True
    return False


def _revisit_until_done(
    updater: cf.CloudflareDNSUpdater,
    results: list[dict[str, str]],
    opt: ProvisionOptions,
    path: str,
    stop_event: Optional[Event] = None,
) -> None:
    """批量回访：等激活、激活一个补一个邮箱，直到全完成或总预算耗尽。

    按域名指数退避：每个未完成域名独立计时，间隔从 --activation-interval 起逐次翻倍
    （上限 60s），只有到期的域名才会被探测，避免每轮全量重扫、大幅削减无效轮询。每轮
    落盘一次，Ctrl+C 不丢数；预算耗尽则剩余行保持 deferred，下次重跑（zone 已 exists）
    继续补。
    """
    stop_event = stop_event or Event()
    budget = max(0.0, float(opt.revisit_timeout or 0.0))
    if budget <= 0:
        return
    base = max(1.0, float(opt.activation_interval or 5.0))
    max_interval = max(base, 60.0)
    start = time.monotonic()
    deadline = start + budget

    tracked: list[dict[str, str]] = [row for row in results if _needs_revisit(row)]
    if not tracked:
        log_print("      回访: 全部已完成，无需等待。")
        return
    # 首查在一个（至多 5s 的）窗口内错开，避免同一瞬间全部到期。
    for i, row in enumerate(tracked):
        row["_probe_interval"] = base
        row["_next_probe"] = start + (i / max(1, len(tracked))) * min(base, 5.0)

    round_no = 0
    while tracked and not stop_event.is_set():
        now = time.monotonic()
        if now >= deadline:
            log_print(
                f"      回访: 预算耗尽({budget:.0f}s)，剩余 {len(tracked)} 个"
                "待激活后重跑补齐。",
                level=logging.WARNING,
            )
            return
        due = [row for row in tracked if float(row.get("_next_probe", 0.0)) <= now]
        if not due:
            earliest = min(float(row.get("_next_probe", now)) for row in tracked)
            wait_secs = min(max(1.0, earliest - now), deadline - now)
            if wait_secs <= 0:
                continue
            cf.interruptible_sleep(wait_secs, stop_event)
            continue

        round_no += 1
        log_print(
            f"      回访[{round_no}]: {len(due)} 个到期（待访 {len(tracked)} 个，"
            f"退避 {base:.0f}~{max_interval:.0f}s）"
        )
        for row in due:
            if stop_event.is_set():
                break
            _revisit_row(updater, row, opt)
            log_print(
                f"        {row.get('domain')}: activation={row.get('activation')}, "
                f"email={row.get('email_status')}"
            )
            if _needs_revisit(row):
                interval = min(
                    max_interval,
                    max(base, float(row.get("_probe_interval", base)) * 2.0),
                )
                row["_probe_interval"] = interval
                row["_next_probe"] = time.monotonic() + interval
        tracked = [row for row in tracked if _needs_revisit(row)]
        write_csv_rows(path, results, FIX_CSV_FIELDNAMES)
    if stop_event.is_set():
        log_print("      回访被中断，未完成的行下次重跑补齐。", level=logging.WARNING)


def provision_domains(
    missing_rows: list[dict[str, str]],
    opt: ProvisionOptions,
    stop_event: Optional[Event] = None,
) -> list[dict[str, str]]:
    """对差集(或白名单交集)逐个域名执行修复与配置。

    第一遍用有界窗口并发执行（同时最多 opt.add_workers 个），完成一个补一个、
    每完成一个即落盘；不做逐域激活等待，激活与补邮箱交给随后的批量回访。

    Ctrl+C 时：第一次中断取消排队任务、进行中任务借助 stop_event 尽快收尾
    （cf 侧的等待与请求均可中断），已完成部分落盘后返回，不抛 traceback；
    调用方按 stop_event 决定退出码。再按一次 Ctrl+C 走强制退出。
    """
    account_name = opt.account.get("name") or opt.account.get("email") or "unknown"
    account_email = opt.account.get("email") or ""
    if account_email and account_email != account_name:
        account_name = f"{account_name} <{account_email}>"
    mode = (
        "串行" if max(1, int(opt.add_workers or 1)) == 1 else f"并行x{opt.add_workers}"
    )
    log_print(f"[4/4] 修复并配置域名 -> Cloudflare 账号: {account_name}（{mode}）")
    stop_event = stop_event or Event()
    rate_limiter: Optional[cf.ApiRateLimiter] = (
        cf.ApiRateLimiter(opt.request_interval, stop_event)
        if opt.request_interval and opt.request_interval > 0
        else None
    )
    updater = cf.CloudflareDNSUpdater(
        auth_method=opt.account["auth_method"],
        api_token=opt.account.get("token"),
        api_email=opt.account.get("email"),
        api_key=opt.account.get("key"),
        account_name=account_name,
        rate_limiter=rate_limiter,
        stop_event=stop_event,
    )

    tasks: list[tuple[str, str]] = []
    for row in missing_rows:
        name = (row.get("name") or "").strip()
        if name:
            tasks.append((name, (row.get("account") or "").strip()))

    results: list[dict[str, str]] = []
    max_workers = max(1, int(opt.add_workers or 1))
    total = len(tasks)
    path = os.path.join(opt.output_dir, FIX_CSV_NAME)
    unfinished_path = os.path.join(opt.output_dir, UNFINISHED_CSV_NAME)
    collected: set[int] = set()
    next_idx = 0

    def _format_result(tag: str, domain: str, result: dict[str, str]) -> str:
        return (
            f"      {tag} {domain}: zone={result['zone_status']}, "
            f"activation={result['activation']}, "
            f"dns={result['record_status']}, email={result['email_status']}, "
            f"ssl={result['ssl_status']}"
        )

    def _run_one(tag: str, domain: str, ss_account: str) -> dict[str, str]:
        # 开始行由干活的线程打印，提交时不预打，并行进度才真实。
        log_print(f"      {tag} 开始 {domain}…")
        return provision_one(updater, domain, opt, ss_account)

    def _flush() -> None:
        write_csv_rows(path, results, FIX_CSV_FIELDNAMES)

    def _run_pass() -> None:
        """有界窗口并发执行第一遍：同时最多 max_workers 个在跑，完成一个补一个。

        相比一次性提交全部任务，排队任务不占用 future/内存，中断时（stop_event）
        只需取消在途窗口；每完成一个即落盘，Ctrl+C 或强制退出尽量不丢结果。
        """
        nonlocal next_idx
        if total == 0:
            return
        executor = ThreadPoolExecutor(
            max_workers=max_workers, thread_name_prefix="domain-fix"
        )
        pending: dict[Future, tuple[str, str, int]] = {}
        try:
            # 条件必须同时考虑 pending：全部任务提交完（next_idx==total）后仍需把
            # 在途的最后一窗（最多 max_workers 个）排空，否则它们的结果会被丢弃。
            while not stop_event.is_set() and (pending or next_idx < total):
                while len(pending) < max_workers and next_idx < total:
                    domain, ss_account = tasks[next_idx]
                    tag = f"[{next_idx + 1}/{total}]"
                    idx = next_idx
                    next_idx += 1
                    pending[executor.submit(_run_one, tag, domain, ss_account)] = (
                        tag,
                        domain,
                        idx,
                    )
                if not pending:
                    break
                done, _ = wait(
                    set(pending), timeout=0.5, return_when=FIRST_COMPLETED
                )
                for future in done:
                    tag, domain, idx = pending.pop(future)
                    try:
                        result = future.result()
                    except KeyboardInterrupt:
                        stop_event.set()
                        continue
                    except Exception as exc:  # noqa: BLE001 - 兜底，避免漏记一个域名
                        result = {
                            "account": account_name,
                            "domain": domain,
                            "zone_status": "",
                            "zone_id": "",
                            "nameservers": "",
                            "activation": "skipped",
                            "record_status": "skipped",
                            "email_status": "skipped",
                            "ssl_status": "skipped",
                            "security_status": "skipped",
                            "error": f"任务异常: {exc}",
                            "timestamp": now_iso(),
                        }
                    else:
                        log_print(_format_result(tag, domain, result))
                    results.append(result)
                    collected.add(idx)
                    _flush()
        finally:
            # 取消未开始的任务；已在跑的线程借助 stop_event 协作文收尾。
            for future in list(pending):
                future.cancel()
            unstarted = total - next_idx
            if unstarted > 0:
                log_print(
                    f"      {unstarted} 个域名未开始（已中断），队列已取消",
                    level=logging.WARNING,
                )
            executor.shutdown(wait=True, cancel_futures=True)

    interrupted = False
    try:
        _run_pass()
        _flush()
        if opt.do_activation and not stop_event.is_set():
            # 第二遍：批量回访，统一等激活、激活一个补一个邮箱，一次运行内尽量配完。
            # 第一遍不再逐域等待激活，工作线程得以持续处理新域名（见 README 并发说明）。
            _revisit_until_done(updater, results, opt, path, stop_event)
            _flush()
    except KeyboardInterrupt:
        stop_event.set()
        interrupted = True
        log_print(
            "      收到 Ctrl+C，取消排队任务，等待进行中任务收尾并保存进度…",
            level=logging.WARNING,
        )
    finally:
        _flush()

    # stop_event 只在收到中断时置位；据此补回中断标记（避免内层捕获把 Ctrl+C 吞掉）。
    interrupted = interrupted or stop_event.is_set()

    # 未处理域名落盘（独立 CSV）：中断时把未开始/未完成的行写出来，便于断点与人工核对。
    unfinished_rows: list[dict[str, str]] = []
    for idx in range(total):
        if idx in collected:
            continue
        domain, src_account = tasks[idx]
        unfinished_rows.append(
            {
                "tag": f"[{idx + 1}/{total}]",
                "domain": domain,
                "account": src_account or account_name,
                "reason": "未开始（中断）" if idx >= next_idx else "已开始未完成（中断）",
            }
        )
    if os.path.exists(unfinished_path):
        try:
            os.remove(unfinished_path)
        except OSError:
            pass
    if unfinished_rows:
        write_csv_rows(unfinished_path, unfinished_rows, UNFINISHED_CSV_FIELDNAMES)

    added = sum(1 for r in results if r.get("_created"))
    reused = sum(1 for r in results if r.get("zone_id") and not r.get("_created"))
    failed = sum(1 for r in results if r["error"])
    partial = sum(1 for r in results if _row_partial_failure(r))
    extra = f", 未处理 {len(unfinished_rows)}" if unfinished_rows else ""
    done_mark = "（已中断，未完成的可重跑补齐）" if interrupted else ""
    log_print(
        f"      修复完成: 新建 {added}, 复用 {reused}, 失败 {failed}, "
        f"部分失败 {partial}, 完成 {len(results)}/{total}{extra}; 明细见 {path}{done_mark}"
    )
    if unfinished_rows:
        log_print(
            f"      未处理清单: {unfinished_path}（可据此重跑或续跑）",
            level=logging.WARNING,
        )
    return results


def parse_args() -> argparse.Namespace:
    ss_config, cf_config = resolve_default_configs()
    default_output_dir = os.path.join(os.path.dirname(ss_config), "domain_fix")
    parser = argparse.ArgumentParser(
        description="spaceship 正常域名与 Cloudflare 激活 zone 差集检测与修复",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  # 默认: 导出两个 CSV 并计算差集(不修改任何东西)\n"
            "  python domain_fix.py\n\n"
            "  # 确认缺失清单后,重新添加并补齐 DNS/邮箱/SSL(默认最后一个账号)\n"
            "  python domain_fix.py --apply --server-ip 1.2.3.4\n\n"
            "  # 指定目标账号、记录文件,并仅修复白名单交集\n"
            "  python domain_fix.py --apply --add-account cf00 --whitelist fix.txt ^\n"
            "                       --records-file records.csv\n"
        ),
    )
    parser.add_argument(
        "-V", "--version", action="version", version=f"%(prog)s {VERSION}"
    )
    parser.add_argument("--ss-config", default=ss_config, help="spaceship 配置文件路径")
    parser.add_argument(
        "--cf-config", default=cf_config, help="Cloudflare 配置文件路径"
    )
    parser.add_argument(
        "--output-dir",
        default=default_output_dir,
        help=f"CSV 输出目录(默认: {default_output_dir})",
    )
    parser.add_argument(
        "--ss-status",
        default="normal",
        choices=["normal", "suspended", "all"],
        help="spaceship 域名状态过滤,默认 normal(无 suspensions)",
    )
    parser.add_argument(
        "--exclude-expired",
        action="store_true",
        help="额外剔除已过期域名(expirationDate<=当前时间);缺失/无法解析则保留",
    )
    parser.add_argument(
        "--zone-status",
        default="active",
        choices=["active", "all"],
        help="Cloudflare zone 状态过滤,默认 active(正常/激活)",
    )
    parser.add_argument(
        "--no-export",
        action="store_true",
        help="跳过导出,直接使用输出目录中已存在(默认文件名)的两个 CSV 计算差集",
    )
    parser.add_argument(
        "--ss-csv",
        default="",
        metavar="PATH",
        help="使用指定路径的已有 spaceship 域名 CSV(指定后跳过 spaceship 联网导出)",
    )
    parser.add_argument(
        "--cf-csv",
        default="",
        metavar="PATH",
        help="使用指定路径的已有 Cloudflare zone CSV(指定后跳过 Cloudflare 查询)",
    )
    parser.add_argument(
        "--missing-csv",
        default="",
        metavar="PATH",
        help="直接使用已计算好的差集 CSV,跳过两个来源的导出与差集计算",
    )
    parser.add_argument(
        "--whitelist",
        default="",
        metavar="PATH",
        help="白名单文本文件(一行一个域名,自动去空格/注释);给出后只对差集与该白名单的交集进行修复",
    )
    parser.add_argument(
        "--add-account",
        default="",
        help="重新添加时的目标 Cloudflare 账号(账号名/邮箱/序号),默认最后一个账号",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="本次最多修复多少个域名,0 表示不限制",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        dest="apply",
        default=True,
        help="确认执行:真正把域名添加到 Cloudflare 并补齐配置(默认执行)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_false",
        dest="apply",
        help="仅预览:只导出与计算差集,不做任何改动",
    )
    parser.add_argument(
        "--add-workers",
        type=int,
        default=4,
        help="修复并发线程数,默认 4(共享限速器兜底,总量不超配额)",
    )
    parser.add_argument(
        "--detail",
        action="store_true",
        dest="detail",
        default=True,
        help="逐条打印 DNS 记录(名/类型/内容/状态)与邮箱各步骤(默认开启)",
    )
    parser.add_argument(
        "--no-detail",
        action="store_false",
        dest="detail",
        help="不打印 DNS/邮箱的逐条详情,只保留逐域汇总行",
    )
    parser.add_argument(
        "--workers", type=int, default=2, help="单账号读取 zone 的并发数"
    )
    parser.add_argument(
        "--account-workers",
        type=int,
        default=3,
        help="读取 Cloudflare zone 时账号级并发数",
    )
    parser.add_argument(
        "--request-interval",
        type=float,
        default=0.3,
        help="Cloudflare API 相邻请求最小间隔秒数,默认 0.3",
    )
    # DNS 记录相关
    parser.add_argument(
        "--server-ip",
        default="",
        help="默认服务器 IP:无其它记录配置时,为该域名添加 A/AAAA 的 @ 与 www 记录",
    )
    parser.add_argument(
        "--records-file",
        default="",
        metavar="PATH",
        help="DNS 记录 CSV: domain,name,type,content,proxied,ttl,priority(domain 为空表示全局)",
    )
    parser.add_argument(
        "--record",
        action="append",
        default=None,
        metavar="NAME:TYPE:CONTENT",
        help="全局 DNS 记录(可多次),如 --record @:A:1.2.3.4 --record www:A:1.2.3.4",
    )
    parser.add_argument(
        "--proxied",
        action="store_true",
        dest="proxied",
        default=None,
        help="新增记录默认开启 Cloudflare 代理(默认开启)",
    )
    parser.add_argument(
        "--no-proxied",
        action="store_false",
        dest="proxied",
        help="新增记录默认关闭 Cloudflare 代理",
    )
    parser.add_argument("--ttl", type=int, default=1, help="新增记录默认 TTL(1=自动)")
    parser.add_argument(
        "--allow-multi-value",
        action="store_true",
        help="允许同名 A/AAAA 多值(同一主机名多个 IP);默认关闭,同名只保留一条",
    )
    parser.add_argument(
        "--zones-file",
        default="",
        metavar="PATH",
        help="旧格式域名配置: domain,ip,forward,security,ssl,Note(兼容 conf/txt 每行一个域名)",
    )
    # 邮箱 / SSL / 安全相关
    parser.add_argument(
        "--forward-email",
        default="",
        help="邮箱转发目标地址(默认取 cf 配置 default_forward_email)",
    )
    parser.add_argument(
        "--ssl-mode",
        default="",
        choices=["", "flexible", "full", "strict", "off"],
        help="SSL 模式(默认取 cf 配置 ssl_mode);置空则不改",
    )
    parser.add_argument(
        "--security",
        action="store_true",
        dest="security",
        default=None,
        help="启用基础安全设置(always_use_https/browser_check/security_level)",
    )
    parser.add_argument(
        "--no-security",
        action="store_false",
        dest="security",
        help="不修改基础安全设置",
    )
    parser.add_argument(
        "--optimize",
        action="store_true",
        dest="optimize",
        default=None,
        help="启用免费加速增益(speed_brain/0rtt/early_hints,默认开启)",
    )
    parser.add_argument(
        "--no-optimize", action="store_false", dest="optimize", help="不修改加速设置"
    )
    parser.add_argument("--no-dns", action="store_true", help="不添加 DNS 记录")
    parser.add_argument(
        "--activation",
        action="store_true",
        dest="activation",
        default=True,
        help="等待 zone 激活(轮询直到 active 或超时;默认等待,以完成配置)",
    )
    parser.add_argument(
        "--no-activation",
        action="store_false",
        dest="activation",
        help="不等待 zone 激活(建站配完即返回)",
    )
    parser.add_argument("--no-email", action="store_true", help="不配置邮箱转发")
    parser.add_argument("--no-ssl", action="store_true", help="不设置 SSL 模式")
    parser.add_argument(
        "--set-nameservers",
        action="store_true",
        dest="set_nameservers",
        default=True,
        help="通过 spaceship API 把域名 NS 指向新 zone 分配的 nameservers(默认开启)",
    )
    parser.add_argument(
        "--no-set-nameservers",
        action="store_false",
        dest="set_nameservers",
        help="不自动改 spaceship 侧 NS",
    )
    parser.add_argument(
        "--activation-timeout", type=float, default=300.0, help="等待激活的最长秒数"
    )
    parser.add_argument(
        "--activation-interval", type=float, default=5.0, help="激活轮询间隔秒数"
    )
    parser.add_argument(
        "--revisit-timeout",
        type=float,
        default=1800.0,
        help="批量回访总预算秒数(0=关闭)；--activation 开启时，第一遍后对未激活/邮箱延期的域名循环回访补配",
    )
    parser.add_argument(
        "-L",
        "--log-file",
        default=None,
        help="保存运行日志到指定文件：全量捕获屏幕输出（含底层库的 print 与 traceback），"
        "并以带级别/线程名的结构化格式记录本工具日志。默认不写日志文件。",
    )
    parser.add_argument(
        "-G",
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="结构化日志行(log_print)的记录级别（默认 INFO）；裸输出不受此过滤。",
    )
    parser.add_argument(
        "--log-overwrite",
        action="store_true",
        help="覆盖已有日志文件。默认追加写入，避免误删历史审计记录。",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    configure_logging(args.log_file, args.log_level, args.log_overwrite)
    stop_event = Event()
    install_interrupt_handler(stop_event)
    output_dir = os.path.abspath(args.output_dir)
    os.makedirs(output_dir, exist_ok=True)
    ss_csv = os.path.join(output_dir, spaceship_csv_name(args.ss_status))
    cf_csv = os.path.join(output_dir, CF_CSV_NAME)
    missing_csv = os.path.join(output_dir, MISSING_CSV_NAME)
    whitelist_csv = os.path.join(output_dir, WHITELIST_CSV_NAME)

    log_print(f"domain_fix version: {VERSION}")
    log_print(f"输出目录: {output_dir}")
    log_print(f"spaceship 配置: {args.ss_config}")
    log_print(f"Cloudflare 配置: {args.cf_config}")
    log_print(f"模式: {'APPLY(实际修复)' if args.apply else 'DRY-RUN(仅导出/预览)'}")

    def load_spaceship_rows() -> list[dict[str, str]]:
        if args.ss_csv:
            log_print(f"[1/4] 使用已有 spaceship CSV: {args.ss_csv}")
            return read_csv_rows(args.ss_csv)
        if args.no_export:
            log_print(f"[1/4] 复用默认 spaceship CSV: {ss_csv}")
            return read_csv_rows(ss_csv)
        export_spaceship_domains(
            args.ss_config,
            ss_csv,
            status=args.ss_status,
            exclude_expired=args.exclude_expired,
        )
        return read_csv_rows(ss_csv)

    def load_cf_rows() -> list[dict[str, str]]:
        if args.cf_csv:
            log_print(f"[2/4] 使用已有 Cloudflare CSV: {args.cf_csv}")
            return read_csv_rows(args.cf_csv)
        if args.no_export:
            log_print(f"[2/4] 复用默认 Cloudflare CSV: {cf_csv}")
            return read_csv_rows(cf_csv)
        export_cf_active_zones(
            args.cf_config,
            cf_csv,
            zone_status=args.zone_status,
            workers=args.workers,
            account_workers=args.account_workers,
            request_interval=args.request_interval,
            stop_event=stop_event,
        )
        return read_csv_rows(cf_csv)

    if args.missing_csv:
        log_print(f"[1-3/4] 使用已有差集 CSV: {args.missing_csv}")
        missing = read_csv_rows(args.missing_csv)
        cf_names: set[str] = set()
        log_print(f"      差集 {len(missing)} 行(未重新计算,状态过滤参数被忽略)")
        if args.exclude_expired:
            missing, dropped = ss.filter_out_expired(missing)
            log_print(
                f"      已剔除已过期域名 {len(dropped)} 个,剩余 {len(missing)} 个"
            )
    else:
        ss_rows = load_spaceship_rows()
        if args.exclude_expired and (args.ss_csv or args.no_export):
            # 已有 CSV 可能含过期域名,统一按 expirationDate 再剔除一次(新鲜导出已过滤)
            ss_rows, dropped = ss.filter_out_expired(ss_rows)
            log_print(
                f"      已剔除已过期域名 {len(dropped)} 个,剩余 {len(ss_rows)} 个"
            )
        cf_rows = load_cf_rows()
        log_print(
            f"[3/4] 计算差集(spaceship {args.ss_status} - Cloudflare {args.zone_status})"
        )
        missing, cf_names = compute_missing(ss_rows, cf_rows)
        write_csv_rows(missing_csv, missing)
        log_print(
            f"      spaceship({args.ss_status}) {len(ss_rows)} 个,"
            f"Cloudflare({args.zone_status}) {len(cf_names)} 个,缺失 {len(missing)} 个"
        )
        log_print(f"      -> 缺失域名清单: {missing_csv}")

    targets = missing
    if args.whitelist:
        whitelist = load_whitelist(args.whitelist)
        targets = intersect_with_whitelist(missing, whitelist)
        write_csv_rows(whitelist_csv, targets)
        missing_names: set[str] = set()
        for row in missing:
            missing_names.add(normalize_domain(row.get("name")))
            missing_names.add(normalize_domain(row.get("unicodeName")))
        missing_names.discard("")
        target_ids = {id(row) for row in targets}
        excluded = [row for row in missing if id(row) not in target_ids]
        not_in_diff = [d for d in whitelist if d not in missing_names]
        log_print(
            f"      白名单 {len(whitelist)} 个,与差集交集 {len(targets)} 个"
            f"(被白名单排除 {len(excluded)} 个)"
        )
        log_print(f"      -> 白名单交集清单: {whitelist_csv}")
        if not_in_diff:
            preview_names = ", ".join(not_in_diff[:10])
            more = " ..." if len(not_in_diff) > 10 else ""
            log_print(
                f"      提示: 白名单中有 {len(not_in_diff)} 个域名不在差集中"
                f"(无需修复或不在 spaceship 正常集合): {preview_names}{more}"
            )

    if not targets:
        log_print(
            "      没有需要修复的域名(差集或与白名单的交集为空)。",
            level=logging.WARNING,
        )
        return

    if not args.apply:
        preview = targets[:20]
        log_print("      预览(前 20 个):")
        for row in preview:
            log_print(
                f"        - {row.get('name', '')} (账号: {row.get('account', '')})"
            )
        log_print("      这是 DRY-RUN 预览;去掉 --dry-run 即真正执行。")
        return

    if args.limit and args.limit > 0:
        targets = targets[: args.limit]
        log_print(f"      --limit {args.limit}: 本次仅修复前 {len(targets)} 个")

    # 组装修复选项(读取旧配置全局默认值与每域名覆盖)
    accounts = cf.get_cf_accounts(args.cf_config)
    if not accounts:
        raise RuntimeError(f"Cloudflare 配置中没有可用账号: {args.cf_config}")
    account = select_target_account(accounts, args.add_account)
    account_name = account.get("name") or account.get("email") or ""
    cf_globals, legacy_server_ip = load_cf_legacy_defaults(
        args.cf_config, str(account_name)
    )
    server_ip = (
        args.server_ip
        or str(account.get("default_server_ip") or "")
        or legacy_server_ip
    )
    forward_email = args.forward_email or str(
        cf_globals.get("default_forward_email") or ""
    )
    ssl_mode = args.ssl_mode or str(cf_globals.get("ssl_mode") or "")
    do_security = (
        bool(cf_globals.get("security_mode", 0))
        if args.security is None
        else args.security
    )
    do_optimize = True if args.optimize is None else args.optimize

    zones_config = load_zones_config(args.zones_file) if args.zones_file else {}
    records_by_domain = (
        load_records_config(args.records_file) if args.records_file else {}
    )
    proxied_default = True if args.proxied is None else args.proxied
    global_records = parse_global_records(args.record, proxied_default, args.ttl)

    ss_auth: dict = {}
    set_nameservers = bool(args.set_nameservers)
    if set_nameservers:
        try:
            ss_auth = ss.get_auth(args.ss_config)
        except (OSError, ValueError) as exc:
            log_print(
                f"      警告: spaceship 配置不可用({exc}),已跳过自动改 NS",
                level=logging.WARNING,
            )
            set_nameservers = False

    # 第一遍是否逐域等待激活：仅当关闭了批量回访（--revisit-timeout 0）时才回退，
    # 否则把激活等待统一交给回访循环，避免工作线程被单个域名占住。
    revisit_enabled = args.activation and float(args.revisit_timeout or 0.0) > 0
    first_pass_wait = args.activation and not revisit_enabled

    log_print(
        "      修复步骤: "
        f"dns={'on' if not args.no_dns else 'off'}, "
        f"nameservers={'on' if set_nameservers else 'off'}, "
        f"activation={'on' if args.activation else 'off'}, "
        f"email={'on' if not args.no_email else 'off'}, "
        f"ssl={'on' if (ssl_mode and not args.no_ssl) else 'off'}, "
        f"security={'on' if do_security else 'off'}, "
        f"optimize={'on' if do_optimize else 'off'}, "
        f"server-ip={server_ip or '-'}, "
        f"forward-email={forward_email or '-'}"
    )

    opt = ProvisionOptions(
        account=account,
        output_dir=output_dir,
        add_workers=args.add_workers,
        request_interval=args.request_interval,
        server_ip=server_ip,
        forward_email=forward_email,
        ssl_mode=ssl_mode,
        do_dns=not args.no_dns,
        do_activation=args.activation,
        do_email=not args.no_email,
        do_ssl=bool(ssl_mode) and not args.no_ssl,
        do_security=do_security,
        do_optimize=do_optimize,
        set_nameservers=set_nameservers,
        activation_timeout=args.activation_timeout,
        activation_interval=args.activation_interval,
        revisit_timeout=args.revisit_timeout,
        proxied_default=proxied_default,
        ttl_default=args.ttl,
        allow_multi_value=args.allow_multi_value,
        records_by_domain=records_by_domain,
        global_records=global_records,
        zones_config=zones_config,
        ss_auth=ss_auth,
        first_pass_wait=first_pass_wait,
        detail=args.detail,
    )
    provision_domains(targets, opt, stop_event)
    if stop_event.is_set():
        sys.exit(130)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log_print("已中断退出，未完成的可重跑补齐。", level=logging.WARNING)
        sys.exit(130)
