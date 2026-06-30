#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Cloudflare DNS 批量修改 / 查询 / 清理工具

主要功能：
1. 批量更新账号下 DNS 记录
   - 支持 A(IPv4)、AAAA(IPv6)、CNAME。
   - 默认使用 --record-type auto：
     * --new-ip/--new-content 是 IPv4 时自动处理 A 记录；
     * --new-ip/--new-content 是 IPv6 时自动处理 AAAA 记录；
     * CNAME 无法通过 IP 自动判断，需显式指定 --record-type CNAME。
   - 支持白名单、old-ip/old-content 过滤、dry-run 预览。

2. 删除以星号开头的通配符 DNS 记录
   - 使用 --delete-wildcard 启用删除模式。
   - 典型记录名：*.example.com、*.sub.example.com。
   - 删除模式下 --record-type auto 等同 ALL，即匹配所有类型；也可指定 A/AAAA/CNAME/ALL。
   - 强烈建议先配合 --dry-run 预览。

3. 多账号并发处理
   - --account-workers 控制账号级并发。
   - --workers 控制单账号内 zone/域名级并发。

4. 快速查询某个域名存在于哪些账号
   - 使用 -f/--find-domain。

5. 处理进度输出
   - 处理账号内域名时输出：[i/n] 正在处理域名 xxx。
   - 若白名单只匹配部分域名，同时输出“账号共 N 个域名，本次待处理 M 个”。

6. Cloudflare API 保守限流模式
   - Cloudflare 官方 REST API 全局限额通常为 1200 次 / 5 分钟 / 用户或账号 Token。
   - 使用 --conservative 可启用保守模式：降低账号/域名并发，并对本进程内所有 API 请求串行限速。
   - 使用 --request-interval 可自定义本进程内相邻两次 Cloudflare API 请求的最小间隔。
   - 收到 HTTP 429 时会读取 retry-after / Ratelimit 响应头并自动退避重试。

7. 中断处理
   - 支持 Ctrl+C 通知所有账号/域名工作线程停止。
   - 尚未开始的 future 会被取消；已经运行中的线程会在下一次检查 stop_event 或当前 HTTP 请求返回后退出。

配置文件示例：
{
  "accounts": {
    "account-a": {
      "cf_api_token": "token_xxx"
    },
    "account-b": {
      "cf_api_email": "name@example.com",
      "cf_api_key": "global_api_key_xxx"
    }
  }
}

常用示例：
  # IPv4：自动选择 A 记录
  python cf_dns_tool.py --new-ip 1.2.3.4 --dry-run

  # IPv6：自动选择 AAAA 记录
  python cf_dns_tool.py --new-ip 2001:db8::1 --dry-run

  # 只更新旧 IPv6 为指定新 IPv6
  python cf_dns_tool.py --old-ip 2001:db8::10 --new-ip 2001:db8::20

  # 更新 CNAME
  python cf_dns_tool.py --record-type CNAME --old-content old.example.com --new-content new.example.com

  # 预览删除所有以 * 开头的通配符记录
  python cf_dns_tool.py --delete-wildcard --dry-run

  # 只删除通配符 AAAA 记录
  python cf_dns_tool.py --delete-wildcard --record-type AAAA

  # 保守模式：适合账号多、域名多或已有其他 Cloudflare API 任务同时运行的场景
  python cf_dns_tool.py --new-ip 1.2.3.4 --conservative --dry-run

  # 自定义全局 API 调用间隔：本脚本进程内所有账号共享，0.5 表示最多约 2 次/秒
  python cf_dns_tool.py --new-ip 1.2.3.4 --request-interval 0.5

  # 短选项等价写法
  python cf_dns_tool.py -n 1.2.3.4 -c -d
  python cf_dns_tool.py -D -c -d
"""

from __future__ import annotations

import argparse
import builtins
import ipaddress
import json
import logging
import os
import re
import signal
import sys
import time
from collections.abc import Iterable, Mapping
from concurrent.futures import FIRST_COMPLETED, Future, ThreadPoolExecutor, wait
from dataclasses import dataclass, field
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from threading import Event, Lock, local as thread_local
from typing import Any, Optional, Union
from urllib.parse import urlparse

import requests

VERSION = "20260630"

# ============ 默认配置区 ============
# 说明：
# - 优先推荐通过命令行参数或配置文件传入认证信息，避免把密钥硬编码到脚本里。
# - 下方变量保留是为了兼容旧脚本结构；如果你确实想写死 token，可把占位符替换掉，
#   并在没有命令行/配置文件认证时自行扩展 build_accounts() 的 fallback 逻辑。
CF_API_TOKEN = "your_api_token_here"
AUTH_METHOD = "token"  # 可选：'token' 或 'key'
# ===================================

# 默认沿用原脚本的 Windows 路径；也可以通过环境变量 CF_CONFIG_PATH 覆盖。
DESKTOP = r"C:/Users/Administrator/Desktop"
DEPLOY_CONFIGS = f"{DESKTOP}/deploy_configs"
CF_CONFIG_PATH = os.getenv("CF_CONFIG_PATH", f"{DEPLOY_CONFIGS}/cf_config.json")

# Cloudflare 常见 DNS 记录类型。本脚本更新模式只处理这三类：
# - A    -> IPv4
# - AAAA -> IPv6
# - CNAME-> 域名别名
UPDATABLE_RECORD_TYPES = {"A", "AAAA", "CNAME"}

# 删除通配符记录时允许 ALL，因为通配符记录可能是 TXT/MX/SRV 等其他类型。
# 指定 ALL 时请求 Cloudflare 不带 type 过滤，由本地只筛选“名称以 * 开头”的记录。
DELETE_RECORD_TYPES = {"A", "AAAA", "CNAME", "ALL"}

# -s/--select-account 不带值时使用该哨兵值表示“进入交互式选择”。
SELECT_ACCOUNT_INTERACTIVE = "__interactive__"

# Cloudflare 官方 REST API 全局限额参考：1200 请求 / 5 分钟 ≈ 4 请求 / 秒。
# 保守模式默认只使用约一半额度：0.5 秒 / 请求 ≈ 2 请求 / 秒，给 Dashboard、
# 其他脚本、多个账号共享同一用户额度等情况留余量。
CF_GLOBAL_RATE_LIMIT_PER_5_MIN = 1200
CONSERVATIVE_REQUEST_INTERVAL = 0.5
CONSERVATIVE_ACCOUNT_WORKERS = 3
CONSERVATIVE_ZONE_WORKERS = 2
DEFAULT_RATE_LIMIT_SCOPE = "account"
DEFAULT_API_MAX_RETRIES = 10 # 间隔最多不超过5分钟(300s)
DEFAULT_API_RETRY_BASE_DELAY = 2.0
DEFAULT_API_RETRY_MAX_SLEEP = 300.0

LOGGER = logging.getLogger("cloudflare_dns_tool")
SENSITIVE_ARG_NAMES = {"-t", "--token", "-k", "--key", "--api-key"}

# 统计哪些账号处理成功/失败
SUCCESS_ACCOUNTS = []
FAILED_ACCOUNTS = []


def configure_logging(log_file: Optional[str], log_level: str, overwrite: bool) -> None:
    """
    配置文件日志，用于后续审计。

    默认不启用文件日志，避免无意生成敏感运行记录。用户传入 --log-file 后，
    控制台仍由原有 print 输出，日志文件由 logging 模块写入，避免控制台重复输出。
    """
    LOGGER.handlers.clear()
    LOGGER.propagate = False
    LOGGER.setLevel(logging.DEBUG)

    if not log_file:
        return

    level = getattr(logging, log_level.upper(), logging.INFO)
    log_dir = os.path.dirname(os.path.abspath(log_file))
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)

    file_handler = logging.FileHandler(
        log_file,
        mode="w" if overwrite else "a",
        encoding="utf-8",
    )
    file_handler.setLevel(level)
    file_handler.setFormatter(
        logging.Formatter(
            "%(asctime)s\t%(levelname)s\t%(threadName)s\t%(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )
    LOGGER.addHandler(file_handler)


def logging_enabled() -> bool:
    """判断是否已配置真实日志 handler。"""
    return bool(LOGGER.handlers)


def log_print(*args, level: int = logging.INFO, **kwargs) -> None:
    """同时输出到控制台和日志文件。"""
    builtins.print(*args, **kwargs)
    if not logging_enabled():
        return

    sep = kwargs.get("sep", " ")
    message = sep.join(str(arg) for arg in args)
    LOGGER.log(level, message)


def mask_sensitive_argv(argv: list[str]) -> list[str]:
    """隐藏命令行中的 token/key，避免写入审计日志。"""
    masked: list[str] = []
    mask_next = False

    for arg in argv:
        if mask_next:
            masked.append("***")
            mask_next = False
            continue

        if arg in SENSITIVE_ARG_NAMES:
            masked.append(arg)
            mask_next = True
            continue

        matched_inline_secret = False
        for sensitive_name in SENSITIVE_ARG_NAMES:
            prefix = f"{sensitive_name}="
            if arg.startswith(prefix):
                masked.append(f"{prefix}***")
                matched_inline_secret = True
                break

        if not matched_inline_secret:
            masked.append(arg)

    return masked


def log_startup(args: argparse.Namespace) -> None:
    """记录脚本启动信息，方便审计定位一次运行。"""
    if not logging_enabled():
        return

    LOGGER.info("=" * 80)
    LOGGER.info("Cloudflare DNS tool started, version=%s", VERSION)
    LOGGER.info("argv=%s", " ".join(mask_sensitive_argv(sys.argv)))
    LOGGER.info(
        "log_file=%s, log_level=%s, log_overwrite=%s",
        args.log_file,
        args.log_level,
        args.log_overwrite,
    )
    LOGGER.info(
        "rate_limit_scope=%s, request_interval=%s",
        args.rate_limit_scope,
        args.request_interval,
    )


def get_main_domain_name_from_str(value: str, normalize: bool = True) -> str:
    """
    从一行文本、URL 或 Markdown 链接中尽量提取 hostname/domain。

    注意：
    - 该函数不依赖公共后缀列表，因此不会严格判断“主域/根域”。
    - 用于白名单时，建议白名单里直接写 Cloudflare zone 名，例如 example.com。
    - 若输入为 https://www.example.com/path，会返回 example.com。
    - 若输入为 *.example.com，会返回 example.com，便于和 zone 名匹配。

    Args:
        value: 待解析字符串，可以是域名、URL、Markdown 链接等。
        normalize: 是否小写化并去除首尾空白。

    Returns:
        解析到的域名/hostname；失败返回空字符串。
    """
    if value is None:
        return ""

    text = str(value).strip()
    if not text:
        return ""

    # 兼容 Markdown 链接，例如：[example](https://www.example.com/path)
    md_link = re.search(r"\((https?://[^)]+)\)", text, flags=re.IGNORECASE)
    if md_link:
        text = md_link.group(1)

    # 去掉常见包裹符号，避免 "[example.com]" 这类格式影响解析。
    text = text.strip().strip("[]()<>\"'")

    # urlparse 需要 scheme 才能可靠识别 netloc；没有 scheme 时补 //。
    parse_target = (
        text if re.match(r"^[a-z][a-z0-9+.-]*://", text, re.I) else f"//{text}"
    )
    parsed = urlparse(parse_target)
    host = parsed.hostname or ""

    # 如果 urlparse 没解析出 hostname，再用正则兜底提取域名片段。
    if not host:
        fallback = re.search(
            r"(?:https?://)?(?:www\.)?((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61})",
            text,
            flags=re.IGNORECASE,
        )
        host = fallback.group(1) if fallback else ""

    host = host.strip().strip(".")
    if normalize:
        host = re.sub(r"\s+", "", host).lower()

    # 白名单匹配 Cloudflare zone 时，www. 和 *. 通常不是 zone 名本身。
    if host.startswith("www."):
        host = host[4:]
    if host.startswith("*."):
        host = host[2:]

    # 简单域名格式校验；不支持下划线，符合 DNS hostname 常见约束。
    if not re.fullmatch(
        r"(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?",
        host,
        flags=re.IGNORECASE,
    ):
        return ""

    return host


def normalize_record_type_arg(value: str) -> str:
    """argparse 用：规范化 --record-type 输入。"""
    v = (value or "").strip().upper()
    if v == "AUTO":
        return "auto"
    if v in {"A", "AAAA", "CNAME", "ALL"}:
        return v
    raise argparse.ArgumentTypeError("--record-type 仅支持 auto/A/AAAA/CNAME/ALL")


def get_ip_version(value: str) -> Optional[int]:
    """返回 IP 版本：IPv4 -> 4，IPv6 -> 6；不是合法 IP 返回 None。"""
    try:
        return ipaddress.ip_address(str(value).strip()).version
    except ValueError:
        return None


def infer_record_type_from_content(content: str) -> str:
    """
    根据新内容自动推断记录类型。

    - IPv4 -> A
    - IPv6 -> AAAA
    - 其他内容无法自动推断，若要更新 CNAME 请显式指定 --record-type CNAME。
    """
    version = get_ip_version(content)
    if version == 4:
        return "A"
    if version == 6:
        return "AAAA"
    raise ValueError(
        "--record-type auto 只能根据合法 IPv4/IPv6 自动判断；"
        "如需更新 CNAME，请指定 --record-type CNAME --new-content <目标域名>"
    )


def resolve_update_record_type(
    record_type: str, new_content: str, old_content: Optional[str]
) -> str:
    """
    解析更新模式最终要处理的记录类型，并对 IP 类型做基础校验。

    设计原则：
    - 默认 auto，降低 IPv4/IPv6 使用门槛。
    - A 必须对应 IPv4，AAAA 必须对应 IPv6，避免误把 IPv6 写入 A 记录。
    - CNAME 内容不是 IP，不强制用 ipaddress 校验。
    """
    if not new_content:
        raise ValueError("更新模式必须提供 --new-ip 或 --new-content")

    if record_type == "ALL":
        raise ValueError("更新模式不支持 --record-type ALL；请使用 auto/A/AAAA/CNAME")

    final_type = (
        infer_record_type_from_content(new_content)
        if record_type == "auto"
        else record_type
    )
    if final_type not in UPDATABLE_RECORD_TYPES:
        raise ValueError(f"更新模式不支持记录类型: {record_type}")

    new_version = get_ip_version(new_content)
    old_version = get_ip_version(old_content) if old_content else None

    if final_type == "A":
        if new_version != 4:
            raise ValueError("A 记录的新内容必须是合法 IPv4 地址")
        if old_content and old_version != 4:
            raise ValueError("A 记录的 --old-ip/--old-content 必须是合法 IPv4 地址")

    if final_type == "AAAA":
        if new_version != 6:
            raise ValueError("AAAA 记录的新内容必须是合法 IPv6 地址")
        if old_content and old_version != 6:
            raise ValueError("AAAA 记录的 --old-ip/--old-content 必须是合法 IPv6 地址")

    return final_type


def resolve_delete_record_type(record_type: str) -> str:
    """
    解析删除通配符模式最终使用的记录类型。

    删除模式没有 new_content，无法按 IP 自动判断，因此：
    - auto -> ALL
    - A/AAAA/CNAME -> 只删除对应类型的通配符记录
    - ALL -> 删除所有类型的通配符记录
    """
    if record_type == "auto":
        return "ALL"
    if record_type not in DELETE_RECORD_TYPES:
        raise ValueError("删除模式仅支持 --record-type auto/A/AAAA/CNAME/ALL")
    return record_type


def is_wildcard_record_name(record_name: str) -> bool:
    """判断 Cloudflare 返回的记录名是否以星号开头，例如 *.example.com。"""
    return str(record_name or "").strip().startswith("*")


def mask_secret(value: Optional[str], show: bool = False) -> str:
    """列表展示账号时默认隐藏 token/key，避免误泄露。"""
    if not value:
        return ""
    if show:
        return value
    if len(value) <= 8:
        return "*" * len(value)
    return f"{value[:4]}...{value[-4:]}"


def interruptible_sleep(seconds: float, stop_event: Optional[Event] = None) -> None:
    """
    可被 Ctrl+C / stop_event 中断的 sleep。

    普通 time.sleep(300) 在收到 429 后可能长时间卡住。这里把长 sleep 切成短片，
    便于用户中断任务，也便于多线程任务尽快响应 stop_event。
    """
    if seconds <= 0:
        return

    deadline = time.monotonic() + seconds
    while True:
        if stop_event and stop_event.is_set():
            raise KeyboardInterrupt
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return
        time.sleep(min(remaining, 0.5))


def parse_retry_after_seconds(value: Optional[str]) -> Optional[float]:
    """
    解析 Retry-After 响应头。

    RFC 允许 Retry-After 为秒数或 HTTP-date；Cloudflare 文档说明 REST API
    的 retry-after 为秒数，但这里兼容两种格式。
    """
    if not value:
        return None

    raw_value = value.strip()
    try:
        return max(0.0, float(raw_value))
    except ValueError:
        pass

    try:
        retry_at = parsedate_to_datetime(raw_value)
    except (TypeError, ValueError, IndexError, OverflowError):
        return None

    if retry_at.tzinfo is None:
        retry_at = retry_at.replace(tzinfo=timezone.utc)
    return max(0.0, (retry_at - datetime.now(timezone.utc)).total_seconds())


def parse_ratelimit_reset_seconds(value: Optional[str]) -> Optional[float]:
    """
    从 Cloudflare Ratelimit 头中提取需要等待的 reset 时间。

    Cloudflare 示例：
        Ratelimit: "default";r=50;t=30
    其中 r 是剩余额度，t 是窗口重置秒数。若发现 r=0，则返回需要等待的 t。
    """
    if not value:
        return None

    waits: list[float] = []
    for remaining, reset_after in re.findall(r"r=(\d+)\s*;\s*t=(\d+)", value):
        try:
            if int(remaining) <= 0:
                waits.append(float(reset_after))
        except ValueError:
            continue

    if not waits:
        return None
    return max(waits)


def calc_retry_delay(
    headers: Mapping[str, str],
    attempt_index: int,
    base_delay: float,
    max_sleep: float,
) -> float:
    """
    计算限流/临时错误后的退避时间。

    优先级：
    1. retry-after：Cloudflare 明确告诉客户端等待多久。
    2. Ratelimit 中 r=0 的 t：等待当前窗口重置。
    3. 指数退避：兜底处理响应头缺失或网络错误。
    """
    delay = parse_retry_after_seconds(headers.get("retry-after"))
    if delay is None:
        delay = parse_ratelimit_reset_seconds(headers.get("Ratelimit"))
    if delay is None:
        delay = base_delay * (2**attempt_index)
    return min(max(0.0, delay), max_sleep)


class ApiRateLimiter:
    """
    本进程内共享的 Cloudflare API 调用限速器。

    设计要点：
    - 账号多、zone 多时，即使每个账号/zone 线程并发，实际 API 请求仍会被统一限速。
    - 限速器只影响本脚本进程内的请求，无法感知其他脚本或 Cloudflare Dashboard。
      因此保守模式默认使用 0.5 秒/请求，为外部调用留出余量。
    - 该限速器是“最小请求间隔”模型，简单、可维护，不依赖第三方包。
    """

    def __init__(self, min_interval: float = 0.0, stop_event: Optional[Event] = None):
        self.min_interval = max(0.0, float(min_interval or 0.0))
        self._stop_event = stop_event or Event()
        self._lock = Lock()
        self._next_allowed_at = 0.0

    @property
    def enabled(self) -> bool:
        return self.min_interval > 0

    def wait(self) -> None:
        """在发起 API 请求前调用，确保相邻请求至少间隔 min_interval 秒。"""
        if not self.enabled:
            return

        while True:
            if self._stop_event.is_set():
                raise KeyboardInterrupt

            with self._lock:
                now = time.monotonic()
                wait_seconds = self._next_allowed_at - now
                if wait_seconds <= 0:
                    self._next_allowed_at = now + self.min_interval
                    return

            interruptible_sleep(min(wait_seconds, 0.5), self._stop_event)


def install_ctrl_c_handler(stop_event: Event) -> None:
    """
    安装 Ctrl+C 处理器，让多线程任务共享同一个停止信号。

    Python 只能在主线程接收 KeyboardInterrupt。这里在收到 SIGINT 时先设置
    stop_event，再抛出 KeyboardInterrupt 交给外层逻辑取消尚未开始的 future。
    已经在执行中的线程会在下一次检查 stop_event、下一次 API 请求前或当前
    requests 超时返回后尽快停止。
    """

    def _handle_sigint(_signum: int, _frame: object) -> None:
        stop_event.set()
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, _handle_sigint)


def cancel_pending_futures(futures: Iterable[Future[Any]]) -> None:
    """取消尚未开始执行的 future；已经运行中的线程会通过 stop_event 协作退出。"""
    for future in futures:
        future.cancel()


@dataclass
class DNSOperationResult:
    """单条 DNS 记录操作结果，便于后续扩展为 CSV/JSON 输出。"""

    zone: str
    name: str
    record_type: str
    old_content: str
    new_content: Optional[str]
    status: str  # updated / deleted / dry_run_update / dry_run_delete / skipped / error
    message: str = ""


@dataclass
class OperationStats:
    """线程安全统计信息。多个 zone 并发处理时统一累加。"""

    updated: int = 0
    deleted: int = 0
    dry_run: int = 0
    skipped: int = 0
    errors: int = 0
    _lock: Lock = field(default_factory=Lock, repr=False)

    def inc_updated(self) -> None:
        with self._lock:
            self.updated += 1

    def inc_deleted(self) -> None:
        with self._lock:
            self.deleted += 1

    def inc_dry_run(self) -> None:
        with self._lock:
            self.dry_run += 1

    def inc_skipped(self) -> None:
        with self._lock:
            self.skipped += 1

    def inc_errors(self) -> None:
        with self._lock:
            self.errors += 1


@dataclass
class BatchRunResult:
    """单账号批处理结果。"""

    results: list[DNSOperationResult]
    stats: OperationStats


class CloudflareDNSUpdater:
    """
    Cloudflare DNS 操作封装。

    线程模型：
    - 每个账号会创建一个 CloudflareDNSUpdater。
    - 单账号内多个 zone 可以并发处理。
    - requests.Session 不是严格线程安全对象，所以这里使用 thread_local，
      确保每个工作线程独立持有一个 Session。
    - 多账号场景下可传入同一个 ApiRateLimiter，使所有账号/zone 线程共享
      一个本进程级别的 Cloudflare API 调用节流器。
    """

    BASE_URL = "https://api.cloudflare.com/client/v4"

    def __init__(
        self,
        auth_method: str,
        api_token: Optional[str] = None,
        api_email: Optional[str] = None,
        api_key: Optional[str] = None,
        max_workers: int = 5,
        print_lock: Optional[Lock] = None,
        stop_event: Optional[Event] = None,
        account_name: str = "unknown",
        rate_limiter: Optional[ApiRateLimiter] = None,
        api_max_retries: int = DEFAULT_API_MAX_RETRIES,
        api_retry_base_delay: float = DEFAULT_API_RETRY_BASE_DELAY,
        api_retry_max_sleep: float = DEFAULT_API_RETRY_MAX_SLEEP,
    ):
        self.max_workers = max_workers
        self.account_name = account_name
        self._print_lock = print_lock or Lock()
        self._stop_event = stop_event or Event()
        self._thread_local = thread_local()
        self._rate_limiter = rate_limiter
        self._api_max_retries = max(0, int(api_max_retries))
        self._api_retry_base_delay = max(0.1, float(api_retry_base_delay))
        self._api_retry_max_sleep = max(1.0, float(api_retry_max_sleep))

        if auth_method == "token":
            if not api_token:
                raise ValueError("API Token 不能为空")
            self._headers = {
                "Authorization": f"Bearer {api_token}",
                "Content-Type": "application/json",
            }
        elif auth_method == "key":
            if not api_email or not api_key:
                raise ValueError("API Email 和 API Key 不能为空")
            self._headers = {
                "X-Auth-Email": api_email,
                "X-Auth-Key": api_key,
                "Content-Type": "application/json",
            }
        else:
            raise ValueError("auth_method 仅支持 token 或 key")

    def _get_session(self) -> requests.Session:
        """为当前线程获取/创建 requests.Session。"""
        session = getattr(self._thread_local, "session", None)
        if session is None:
            session = requests.Session()
            session.headers.update(self._headers)
            self._thread_local.session = session
        return session

    def _safe_print(self, *args, **kwargs) -> None:
        """多线程环境下串行打印，避免多线程输出交错。"""
        with self._print_lock:
            log_print(*args, **kwargs)

    def _should_stop(self) -> bool:
        return self._stop_event.is_set()

    def _check_stop(self) -> None:
        if self._should_stop():
            raise KeyboardInterrupt

    def _request(self, method: str, endpoint: str, **kwargs) -> dict:
        """
        统一处理 Cloudflare API 请求、限速和重试。

        限流处理策略：
        - 请求前先经过 ApiRateLimiter，控制本脚本进程内的总体请求间隔。
        - 收到 HTTP 429 时，优先使用 retry-after，其次使用 Ratelimit 头中的 t。
        - 对 5xx 和短暂网络错误做有限次数指数退避重试。
        """
        url = f"{self.BASE_URL}{endpoint}"
        last_error = ""

        for attempt in range(self._api_max_retries + 1):
            self._check_stop()
            if self._rate_limiter:
                self._rate_limiter.wait()

            LOGGER.debug(
                "API request account=%s method=%s endpoint=%s attempt=%s params=%s",
                self.account_name,
                method,
                endpoint,
                attempt + 1,
                kwargs.get("params"),
            )
            try:
                resp = self._get_session().request(method, url, timeout=30, **kwargs)
                LOGGER.debug(
                    "API response account=%s method=%s endpoint=%s status=%s",
                    self.account_name,
                    method,
                    endpoint,
                    resp.status_code,
                )
            except requests.RequestException as exc:
                last_error = f"网络请求失败: {exc}"
                if attempt >= self._api_max_retries:
                    raise Exception(last_error) from exc

                delay = min(
                    self._api_retry_base_delay * (2**attempt),
                    self._api_retry_max_sleep,
                )
                self._safe_print(
                    f"[RETRY] {method} {endpoint} 网络错误，{delay:.1f}s 后重试 "
                    f"({attempt + 1}/{self._api_max_retries})"
                )
                interruptible_sleep(delay, self._stop_event)
                continue

            if resp.status_code == 429:
                last_error = f"HTTP 429 Too Many Requests: {resp.text[:300]}"
                if attempt >= self._api_max_retries:
                    raise Exception(last_error)

                delay = calc_retry_delay(
                    resp.headers,
                    attempt_index=attempt,
                    base_delay=self._api_retry_base_delay,
                    max_sleep=self._api_retry_max_sleep,
                )
                self._safe_print(
                    f"[RATE-LIMIT] {method} {endpoint} 触发 Cloudflare 限流，"
                    f"{delay:.1f}s 后重试 ({attempt + 1}/{self._api_max_retries})"
                )
                interruptible_sleep(delay, self._stop_event)
                continue

            if (
                resp.status_code in {500, 502, 503, 504}
                and attempt < self._api_max_retries
            ):
                last_error = f"HTTP {resp.status_code}: {resp.text[:300]}"
                delay = min(
                    self._api_retry_base_delay * (2**attempt),
                    self._api_retry_max_sleep,
                )
                self._safe_print(
                    f"[RETRY] {method} {endpoint} 服务端临时错误 {resp.status_code}，"
                    f"{delay:.1f}s 后重试 ({attempt + 1}/{self._api_max_retries})"
                )
                interruptible_sleep(delay, self._stop_event)
                continue

            try:
                data = resp.json()
            except ValueError as exc:
                raise Exception(
                    f"HTTP {resp.status_code}: 返回非 JSON 内容: {resp.text[:300]}"
                ) from exc

            if not resp.ok or not data.get("success"):
                raise Exception(
                    f"HTTP {resp.status_code}, API 请求失败: {data.get('errors', [])}"
                )

            return data

        raise Exception(last_error or f"API 请求失败: {method} {endpoint}")

    def zone_exists(self, domain: str) -> bool:
        """快速检查某域名/zone 是否存在于当前账号。"""
        target = (get_main_domain_name_from_str(domain) or domain.strip()).lower()
        data = self._request(
            "GET",
            "/zones",
            params={"name": target, "page": 1, "per_page": 1, "status": "active"},
        )
        for zone in data.get("result", []):
            if zone.get("name", "").lower() == target:
                return True
        return False

    def get_all_zones(self) -> list[dict]:
        """分页读取当前账号下所有 zone。"""
        zones: list[dict] = []
        page = 1
        while True:
            self._check_stop()
            data = self._request("GET", "/zones", params={"page": page, "per_page": 50})
            zones.extend(data.get("result", []))

            result_info = data.get("result_info", {})
            total_pages = int(result_info.get("total_pages", 1) or 1)
            if page >= total_pages:
                break
            page += 1
            time.sleep(0.2)  # 轻微限速，减少触发 Cloudflare API rate limit 的概率。
        return zones

    def get_dns_records(
        self, zone_id: str, record_type: Optional[str] = "A"
    ) -> list[dict]:
        """
        分页读取某个 zone 下的 DNS 记录。

        Args:
            zone_id: Cloudflare zone id。
            record_type: A/AAAA/CNAME 等；为 None 或 ALL 时不按类型过滤。
        """
        records: list[dict] = []
        page = 1
        while True:
            self._check_stop()
            # 显式声明 value 可为 int 或 str，避免 Pylance/pyright 将该字典
            # 从初始值错误推断为 dict[str, int]，从而在后续写入 "type" 字符串时报错。
            params: dict[str, Union[int, str]] = {"page": page, "per_page": 100}
            if record_type and record_type != "ALL":
                params["type"] = record_type

            data = self._request("GET", f"/zones/{zone_id}/dns_records", params=params)
            records.extend(data.get("result", []))

            result_info = data.get("result_info", {})
            total_pages = int(result_info.get("total_pages", 1) or 1)
            if page >= total_pages:
                break
            page += 1
            time.sleep(0.1)
        return records

    def update_dns_record(
        self,
        zone_id: str,
        record_id: str,
        record_name: str,
        new_content: str,
        proxied: bool,
        ttl: int,
        record_type: str,
    ) -> dict:
        """
        更新单条 DNS 记录。

        这里沿用 PUT 全量更新方式，保留原记录的 name/proxied/ttl/type，只替换 content。
        若后续需要保留更多 Cloudflare 新字段（comment/tags/settings），可扩展 payload。
        """
        payload = {
            "type": record_type,
            "name": record_name,
            "content": new_content,
            "proxied": proxied,
            "ttl": ttl,
        }
        return self._request(
            "PUT", f"/zones/{zone_id}/dns_records/{record_id}", json=payload
        )

    def delete_dns_record(self, zone_id: str, record_id: str) -> dict:
        """删除单条 DNS 记录。调用前应确保已完成过滤与 dry-run 判断。"""
        return self._request("DELETE", f"/zones/{zone_id}/dns_records/{record_id}")

    def _progress_prefix(
        self,
        zone_name: str,
        zone_index: int,
        selected_zone_total: int,
        account_zone_total: int,
        action_name: str,
    ) -> str:
        """生成账号内 zone 处理进度文案。"""
        if selected_zone_total == account_zone_total:
            scope_text = f"账号共 {account_zone_total} 个域名"
        else:
            scope_text = f"账号共 {account_zone_total} 个域名，本次待处理 {selected_zone_total} 个"
        return (
            f"\n[账号:{self.account_name}] [{zone_index}/{selected_zone_total}] "
            f"正在处理域名: {zone_name} ({scope_text}, 操作: {action_name})"
        )

    def _process_zone_update(
        self,
        zone: dict,
        zone_index: int,
        selected_zone_total: int,
        account_zone_total: int,
        new_content: str,
        old_content: Optional[str],
        record_type: str,
        dry_run: bool,
        include_subdomains: bool,
        whitelist_active: bool,
        stats: OperationStats,
    ) -> list[DNSOperationResult]:
        """处理单个 zone 的更新逻辑。"""
        zone_name = zone["name"]
        zone_id = zone["id"]
        results: list[DNSOperationResult] = []

        self._safe_print(
            self._progress_prefix(
                zone_name,
                zone_index,
                selected_zone_total,
                account_zone_total,
                action_name=f"更新 {record_type}",
            )
        )

        try:
            records = self.get_dns_records(zone_id, record_type)
        except KeyboardInterrupt:
            return results
        except Exception as exc:
            self._safe_print(f"  [zone] 获取记录失败: {exc}")
            stats.inc_errors()
            return results

        if not records:
            self._safe_print(f"  [zone] 未找到 {record_type} 记录")
            return results

        for record in records:
            if self._should_stop():
                return results

            r_name = record.get("name", "")
            r_content = record.get("content", "")
            r_id = record.get("id", "")
            r_proxied = bool(record.get("proxied", False))
            r_ttl = int(record.get("ttl", 1) or 1)
            r_type = record.get("type", record_type)

            # 白名单模式下，--no-subdomains 表示只处理 zone 根记录，不处理子域名记录。
            if (
                whitelist_active
                and not include_subdomains
                and r_name.lower() != zone_name.lower()
            ):
                continue

            # 如果指定了 old-content/old-ip，则只更新内容完全匹配的记录。
            if old_content and r_content != old_content:
                stats.inc_skipped()
                continue

            # 新旧内容一致，无需重复更新。
            if r_content == new_content:
                stats.inc_skipped()
                continue

            if dry_run:
                self._safe_print(
                    f"  [DRY-UPDATE] {r_type} {r_name}: {r_content} -> {new_content}"
                )
                stats.inc_dry_run()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=new_content,
                        status="dry_run_update",
                    )
                )
                continue

            try:
                self.update_dns_record(
                    zone_id=zone_id,
                    record_id=r_id,
                    record_name=r_name,
                    new_content=new_content,
                    proxied=r_proxied,
                    ttl=r_ttl,
                    record_type=record_type,
                )
                self._safe_print(
                    f"  [OK] {r_type} {r_name}: {r_content} -> {new_content}"
                )
                stats.inc_updated()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=new_content,
                        status="updated",
                    )
                )
                time.sleep(0.1)
            except Exception as exc:
                self._safe_print(f"  [ERR] {r_type} {r_name}: {exc}")
                stats.inc_errors()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=new_content,
                        status="error",
                        message=str(exc),
                    )
                )

        return results

    def _process_zone_delete_wildcard(
        self,
        zone: dict,
        zone_index: int,
        selected_zone_total: int,
        account_zone_total: int,
        record_type: str,
        old_content: Optional[str],
        dry_run: bool,
        stats: OperationStats,
    ) -> list[DNSOperationResult]:
        """处理单个 zone 的“删除以 * 开头的 DNS 记录”逻辑。"""
        zone_name = zone["name"]
        zone_id = zone["id"]
        results: list[DNSOperationResult] = []

        self._safe_print(
            self._progress_prefix(
                zone_name,
                zone_index,
                selected_zone_total,
                account_zone_total,
                action_name=f"删除通配符记录(type={record_type})",
            )
        )

        try:
            records = self.get_dns_records(
                zone_id, None if record_type == "ALL" else record_type
            )
        except KeyboardInterrupt:
            return results
        except Exception as exc:
            self._safe_print(f"  [zone] 获取记录失败: {exc}")
            stats.inc_errors()
            return results

        matched = 0
        for record in records:
            if self._should_stop():
                return results

            r_name = record.get("name", "")
            if not is_wildcard_record_name(r_name):
                continue

            r_content = record.get("content", "")
            r_id = record.get("id", "")
            r_type = record.get("type", "")
            matched += 1

            # 删除模式下也复用 --old-content/--old-ip 作为内容过滤器，便于只删除指向旧地址的通配符记录。
            if old_content and r_content != old_content:
                stats.inc_skipped()
                continue

            if dry_run:
                self._safe_print(f"  [DRY-DELETE] {r_type} {r_name}: {r_content}")
                stats.inc_dry_run()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=None,
                        status="dry_run_delete",
                    )
                )
                continue

            try:
                self.delete_dns_record(zone_id, r_id)
                self._safe_print(f"  [DEL] {r_type} {r_name}: {r_content}")
                stats.inc_deleted()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=None,
                        status="deleted",
                    )
                )
                time.sleep(0.1)
            except Exception as exc:
                self._safe_print(f"  [ERR] 删除失败 {r_type} {r_name}: {exc}")
                stats.inc_errors()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=None,
                        status="error",
                        message=str(exc),
                    )
                )

        if matched == 0:
            self._safe_print("  [zone] 未发现以 * 开头的记录")

        return results

    def _filter_zones_by_whitelist(
        self,
        all_zones: list[dict],
        whitelist: Optional[list[str]],
    ) -> tuple[list[dict], Optional[set[str]]]:
        """按白名单过滤 zone，返回待处理 zone 与白名单集合。"""
        if not whitelist:
            return all_zones, None

        whitelist_set = {d.lower().strip() for d in whitelist if d and d.strip()}
        zones = [z for z in all_zones if z.get("name", "").lower() in whitelist_set]
        self._safe_print(
            f"白名单域名数: {len(whitelist_set)}, 匹配到账号内域名: {len(zones)}"
        )
        return zones, whitelist_set

    def batch_update(
        self,
        new_content: str,
        old_content: Optional[str] = None,
        whitelist: Optional[list[str]] = None,
        record_type: str = "auto",
        dry_run: bool = False,
        include_subdomains: bool = True,
    ) -> BatchRunResult:
        """当前账号下批量更新 DNS 记录。"""
        self._check_stop()
        final_record_type = resolve_update_record_type(
            record_type, new_content, old_content
        )

        self._safe_print("=" * 70)
        self._safe_print(f"Cloudflare DNS 批量更新 | 账号: {self.account_name}")
        self._safe_print(
            f"new_content={new_content}, old_content={old_content}, "
            f"type={final_record_type}, workers={self.max_workers}, dry_run={dry_run}"
        )
        self._safe_print("=" * 70)

        all_zones = self.get_all_zones()
        account_zone_total = len(all_zones)
        self._safe_print(f"账号 {self.account_name} 下共 {account_zone_total} 个域名")

        zones, whitelist_set = self._filter_zones_by_whitelist(all_zones, whitelist)
        if not zones:
            self._safe_print("没有需要处理的域名")
            return BatchRunResult(results=[], stats=OperationStats())

        stats = OperationStats()
        all_results: list[DNSOperationResult] = []
        selected_zone_total = len(zones)

        executor = ThreadPoolExecutor(max_workers=self.max_workers)
        pending: set[Future[Any]] = set()
        try:
            future_to_zone = {
                executor.submit(
                    self._process_zone_update,
                    zone,
                    zone_index,
                    selected_zone_total,
                    account_zone_total,
                    new_content,
                    old_content,
                    final_record_type,
                    dry_run,
                    include_subdomains,
                    whitelist_active=whitelist_set is not None,
                    stats=stats,
                ): zone
                for zone_index, zone in enumerate(zones, start=1)
            }
            pending = set(future_to_zone)

            while pending and not self._should_stop():
                done, pending = wait(
                    pending,
                    timeout=0.5,
                    return_when=FIRST_COMPLETED,
                )
                if not done:
                    continue

                for future in done:
                    zone = future_to_zone[future]
                    try:
                        all_results.extend(future.result())
                    except KeyboardInterrupt:
                        self._stop_event.set()
                        break
                    except Exception as exc:
                        self._safe_print(f"[zone-error] {zone.get('name')}: {exc}")
                        stats.inc_errors()
        except KeyboardInterrupt:
            self._stop_event.set()
            self._safe_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止当前账号任务...")
        finally:
            if self._should_stop():
                cancel_pending_futures(pending)
            executor.shutdown(wait=False, cancel_futures=True)

        self._safe_print("\n" + "=" * 70)
        self._safe_print(
            f"账号 {self.account_name} 完成: "
            f"updated={stats.updated}, deleted={stats.deleted}, dry_run={stats.dry_run}, "
            f"skipped={stats.skipped}, errors={stats.errors}"
        )
        self._safe_print("=" * 70)
        return BatchRunResult(results=all_results, stats=stats)

    def batch_delete_wildcard(
        self,
        whitelist: Optional[list[str]] = None,
        record_type: str = "auto",
        old_content: Optional[str] = None,
        dry_run: bool = False,
    ) -> BatchRunResult:
        """当前账号下批量删除所有名称以 * 开头的 DNS 记录。"""
        self._check_stop()
        final_record_type = resolve_delete_record_type(record_type)

        self._safe_print("=" * 70)
        self._safe_print(f"Cloudflare DNS 通配符记录删除 | 账号: {self.account_name}")
        self._safe_print(
            f"record_type={final_record_type}, old_content_filter={old_content}, "
            f"workers={self.max_workers}, dry_run={dry_run}"
        )
        self._safe_print("=" * 70)

        all_zones = self.get_all_zones()
        account_zone_total = len(all_zones)
        self._safe_print(f"账号 {self.account_name} 下共 {account_zone_total} 个域名")

        zones, _ = self._filter_zones_by_whitelist(all_zones, whitelist)
        if not zones:
            self._safe_print("没有需要处理的域名")
            return BatchRunResult(results=[], stats=OperationStats())

        stats = OperationStats()
        all_results: list[DNSOperationResult] = []
        selected_zone_total = len(zones)

        executor = ThreadPoolExecutor(max_workers=self.max_workers)
        pending: set[Future[Any]] = set()
        try:
            future_to_zone = {
                executor.submit(
                    self._process_zone_delete_wildcard,
                    zone,
                    zone_index,
                    selected_zone_total,
                    account_zone_total,
                    final_record_type,
                    old_content,
                    dry_run,
                    stats,
                ): zone
                for zone_index, zone in enumerate(zones, start=1)
            }
            pending = set(future_to_zone)

            while pending and not self._should_stop():
                done, pending = wait(
                    pending,
                    timeout=0.5,
                    return_when=FIRST_COMPLETED,
                )
                if not done:
                    continue

                for future in done:
                    zone = future_to_zone[future]
                    try:
                        all_results.extend(future.result())
                    except KeyboardInterrupt:
                        self._stop_event.set()
                        break
                    except Exception as exc:
                        self._safe_print(f"[zone-error] {zone.get('name')}: {exc}")
                        stats.inc_errors()
        except KeyboardInterrupt:
            self._stop_event.set()
            self._safe_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止当前账号任务...")
        finally:
            if self._should_stop():
                cancel_pending_futures(pending)
            executor.shutdown(wait=False, cancel_futures=True)

        self._safe_print("\n" + "=" * 70)
        self._safe_print(
            f"账号 {self.account_name} 完成: "
            f"updated={stats.updated}, deleted={stats.deleted}, dry_run={stats.dry_run}, "
            f"skipped={stats.skipped}, errors={stats.errors}"
        )
        self._safe_print("=" * 70)
        return BatchRunResult(results=all_results, stats=stats)


def load_whitelist(filepath: str) -> list[str]:
    """
    加载白名单文件中的域名。

    文件规则：
    - 每行一个域名或 URL。
    - 空行忽略。
    - 以 # 开头的行视为注释。
    - URL 会尽量提取 hostname；www. 和 *. 会被去掉。
    """
    domains: list[str] = []
    seen: set[str] = set()

    try:
        with open(filepath, "r", encoding="utf-8") as file_obj:
            for line_no, raw_line in enumerate(file_obj, start=1):
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue

                domain = get_main_domain_name_from_str(line)
                if not domain:
                    log_print(f"[WARN] 白名单第 {line_no} 行未解析到有效域名: {line}")
                    continue

                if domain not in seen:
                    seen.add(domain)
                    domains.append(domain)
                    log_print(f"解析到白名单域名: {domain}")
    except FileNotFoundError:
        log_print(f"白名单文件不存在: {filepath}")
        sys.exit(1)

    return domains


def load_config(config_path: str) -> dict:
    """读取 JSON 配置文件。"""
    if not os.path.exists(config_path):
        log_print(f"配置文件不存在: {config_path}")
        sys.exit(1)
    with open(config_path, "r", encoding="utf-8") as file_obj:
        return json.load(file_obj) or {}


def get_cf_accounts(config_path: str) -> list[dict]:
    """
    从配置文件读取 Cloudflare 账号。

    支持字段：
      - cf_api_token
      - cf_api_email + cf_api_key

    返回的账号对象统一为：
      {
        "name": "account-name",
        "auth_method": "token" 或 "key",
        "token": "..." 或 None,
        "email": "..." 或 None,
        "key": "..." 或 None
      }
    """
    cf_config = load_config(config_path)
    raw_accounts = cf_config.get("accounts", {})

    # 原脚本使用 dict；这里额外兼容 list，便于未来迁移配置格式。
    if isinstance(raw_accounts, list):
        iterable_accounts = [
            (acc.get("name") or acc.get("cf_api_email") or f"account-{idx}", acc)
            for idx, acc in enumerate(raw_accounts, start=1)
            if isinstance(acc, dict)
        ]
    elif isinstance(raw_accounts, dict):
        iterable_accounts = list(raw_accounts.items())
    else:
        iterable_accounts = []

    accounts: list[dict] = []
    for name, acc_obj in iterable_accounts:
        token = acc_obj.get("cf_api_token")
        email = acc_obj.get("cf_api_email")
        key = acc_obj.get("cf_api_key")

        if token:
            accounts.append(
                {
                    "name": name,
                    "auth_method": "token",
                    "token": token,
                    "email": None,
                    "key": None,
                }
            )
        elif email and key:
            accounts.append(
                {
                    "name": name,
                    "auth_method": "key",
                    "token": None,
                    "email": email,
                    "key": key,
                }
            )
        else:
            log_print(f"[WARN] 账号 {name} 缺少有效认证字段，已跳过")

    return accounts


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Cloudflare DNS 批量修改/查询/清理工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-V", "--version", action="version", version=f"%(prog)s {VERSION}"
    )

    # 更新模式参数。保留 --new-ip/--old-ip 是为了兼容旧用法；
    # 新增 --new-content/--old-content 使 CNAME 场景语义更准确。
    parser.add_argument(
        "-n",
        "--new-ip",
        "--new-content",
        dest="new_content",
        default=None,
        help="新的 DNS 内容。IPv4/IPv6 可自动判断记录类型；CNAME 请配合 --record-type CNAME。",
    )
    parser.add_argument(
        "-o",
        "--old-ip",
        "--old-content",
        dest="old_content",
        default=None,
        help="旧 DNS 内容过滤器；只修改/删除内容完全匹配的记录。",
    )

    parser.add_argument(
        "-w",
        "--whitelist",
        default=None,
        help="域名/URL 白名单文件路径（每行一个）；只处理白名单匹配到的 zone。",
    )
    parser.add_argument(
        "-r",
        "--record-type",
        default="auto",
        type=normalize_record_type_arg,
        help="DNS 记录类型：auto/A/AAAA/CNAME/ALL。更新模式不支持 ALL；删除模式 auto 等同 ALL。默认 auto。",
    )
    parser.add_argument(
        "-d",
        "--dry-run",
        action="store_true",
        help="预览模式：只打印将执行的操作，不实际修改/删除。",
    )
    parser.add_argument(
        "-N",
        "--no-subdomains",
        action="store_true",
        help="白名单 + 更新模式下只修改 zone 根记录，不修改子域名记录。",
    )

    # 删除模式参数。
    parser.add_argument(
        "-D",
        "--delete-wildcard",
        "--delete-star-records",
        action="store_true",
        help="删除名称以 * 开头的 DNS 记录，例如 *.example.com；建议先加 --dry-run 预览。",
    )

    # 并发控制。
    parser.add_argument(
        "-W",
        "--workers",
        type=int,
        default=5,
        metavar="N",
        help="单账号内 zone/域名并发数（默认 5，最大自动限制为 20）。",
    )
    parser.add_argument(
        "-A",
        "--account-workers",
        type=int,
        default=3,
        metavar="N",
        help="多账号并发数（默认 3，最大自动限制为 20）。",
    )
    parser.add_argument(
        "-c",
        "--conservative",
        action="store_true",
        help=(
            f"保守限流模式：自动将 --account-workers 限制为 {CONSERVATIVE_ACCOUNT_WORKERS}、"
            f"--workers 限制为 {CONSERVATIVE_ZONE_WORKERS}，"
            f"并设置 API 调用间隔为 {CONSERVATIVE_REQUEST_INTERVAL}s。"
        ),
    )
    parser.add_argument(
        "-i",
        "--request-interval",
        type=float,
        default=None,
        metavar="SECONDS",
        help=(
            "相邻两次 Cloudflare API 请求的最小间隔；具体作用范围由 "
            "--rate-limit-scope 控制；0 表示不额外限速。"
        ),
    )
    parser.add_argument(
        "-q",
        "--rate-limit-scope",
        default=DEFAULT_RATE_LIMIT_SCOPE,
        choices=["account", "global"],
        help=(
            "--request-interval 的限速范围：account=每个账号独立限速；"
            "global=整个脚本进程共享一个限速器。默认 account。"
        ),
    )
    parser.add_argument(
        "-R",
        "--api-max-retries",
        type=int,
        default=DEFAULT_API_MAX_RETRIES,
        metavar="N",
        help="Cloudflare API 429/5xx/网络临时错误的最大重试次数（默认 10）。",
    )
    parser.add_argument(
        "-B",
        "--api-retry-base-delay",
        type=float,
        default=DEFAULT_API_RETRY_BASE_DELAY,
        metavar="SECONDS",
        help="指数退避的初始等待秒数（默认 2.0）。",
    )
    parser.add_argument(
        "-M",
        "--api-retry-max-sleep",
        type=float,
        default=DEFAULT_API_RETRY_MAX_SLEEP,
        metavar="SECONDS",
        help="单次重试等待上限秒数（默认 300，匹配 Cloudflare 5 分钟限流窗口）。",
    )

    # 日志 / 审计相关。
    parser.add_argument(
        "-L",
        "--log-file",
        default=None,
        help="保存运行日志到指定文件，便于后期审计。默认不写日志文件。",
    )
    parser.add_argument(
        "-G",
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="日志文件记录级别（默认 INFO）。",
    )
    parser.add_argument(
        "--log-overwrite",
        action="store_true",
        help="覆盖已有日志文件。默认追加写入，避免误删历史审计记录。",
    )

    # 认证相关。
    parser.add_argument("-t", "--token", default=None, help="Cloudflare API Token。")
    parser.add_argument(
        "-e", "--email", default=None, help="Cloudflare 账号邮箱（配合 --api-key）。"
    )
    parser.add_argument(
        "-k",
        "--key",
        "--api-key",
        dest="api_key",
        default=None,
        help="Cloudflare Global API Key。",
    )
    parser.add_argument(
        "-C",
        "--config",
        default=CF_CONFIG_PATH,
        help="账号配置文件路径（多账号）。命令行显式认证优先级高于配置文件。",
    )

    # 查询/辅助模式。
    parser.add_argument(
        "-f", "--find-domain", default=None, help="快速查找某个域名是否存在于账号中。"
    )
    parser.add_argument(
        "-l", "--list-accounts", action="store_true", help="列出所有可用账号。"
    )
    parser.add_argument(
        "-s",
        "--select-account",
        nargs="?",
        const=SELECT_ACCOUNT_INTERACTIVE,
        default=None,
        metavar="ACCOUNT",
        help=(
            "选择配置文件中的一个账号进行操作。"
            "不带 ACCOUNT 时进入交互式选择；带 ACCOUNT 时按账号名/邮箱匹配，也支持数字索引。"
        ),
    )
    parser.add_argument(
        "-S",
        "--show-secrets",
        action="store_true",
        help="列出账号时显示完整 token/key。默认隐藏敏感字段。",
    )

    return parser.parse_args()


def list_accounts(accounts: list[dict], show_secrets: bool = False) -> None:
    """打印账号列表。默认脱敏显示密钥。"""
    for i, account in enumerate(accounts, start=1):
        name = account.get("name") or ""
        email = account.get("email") or ""
        token = mask_secret(account.get("token"), show=show_secrets)
        key = mask_secret(account.get("key"), show=show_secrets)
        auth_method = account.get("auth_method")
        secret_text = f"token={token}" if auth_method == "token" else f"key={key}"
        log_print(f"[{i}] {name}\t auth={auth_method}\t email={email}\t {secret_text}")


def account_matches_selector(account: dict, selector: str) -> bool:
    """判断账号是否匹配 -s/--select-account 给出的账号名或邮箱。"""
    target = selector.strip().lower()
    name = str(account.get("name") or "").strip().lower()
    email = str(account.get("email") or "").strip().lower()
    return target in {name, email}


def select_account_by_selector(
    accounts: list[dict], selector: str, show_secrets: bool = False
) -> dict:
    """
    根据命令行传入的 selector 选择账号。

    支持：
    - 账号名：配置文件 accounts 下的 key。
    - 邮箱：使用 cf_api_email 的账号可按邮箱匹配。
    - 数字索引：与 list_accounts() 展示的序号一致，从 1 开始。
    """
    selector = selector.strip()
    if not selector:
        log_print("账号选择参数不能为空")
        sys.exit(1)

    matched_accounts = [
        account for account in accounts if account_matches_selector(account, selector)
    ]
    if len(matched_accounts) == 1:
        return matched_accounts[0]

    if len(matched_accounts) > 1:
        log_print(f"账号选择 {selector!r} 匹配到多个账号，请使用更精确的账号名或索引:")
        list_accounts(matched_accounts, show_secrets=show_secrets)
        sys.exit(1)

    if selector.isdigit():
        account_idx = int(selector)
        if 1 <= account_idx <= len(accounts):
            return accounts[account_idx - 1]

    log_print(f"未找到账号: {selector}")
    log_print("可用账号如下:")
    list_accounts(accounts, show_secrets=show_secrets)
    sys.exit(1)


def choose_account_interactively(
    accounts: list[dict], show_secrets: bool = False
) -> dict:
    """交互式选择账号，兼容旧的 -s 用法。"""
    log_print("请选择一个账号:")
    list_accounts(accounts, show_secrets=show_secrets)
    try:
        account_idx = int(input("请输入选择的账号索引: ").strip())
        if account_idx < 1 or account_idx > len(accounts):
            raise ValueError
    except ValueError:
        log_print("账号索引无效")
        sys.exit(1)

    return accounts[account_idx - 1]


def build_accounts(args: argparse.Namespace) -> list[dict]:
    """
    根据优先级构建账号列表。

    优先级：
    1. 命令行 --token
    2. 命令行 --email + --api-key
    3. 配置文件 --config
    """
    if args.token:
        return [
            {
                "name": "cli-token-account",
                "auth_method": "token",
                "token": args.token,
                "email": None,
                "key": None,
            }
        ]

    if args.email and args.api_key:
        return [
            {
                "name": args.email,
                "auth_method": "key",
                "token": None,
                "email": args.email,
                "key": args.api_key,
            }
        ]

    # 配置文件模式。args.config 有默认值，因此没有显式认证时默认走配置文件。
    accounts = get_cf_accounts(args.config)
    if not accounts:
        log_print("配置文件中没有可用账号")
        sys.exit(1)

    log_print(f"从配置文件中读取账号: {args.config}")

    if args.select_account is not None:
        if args.select_account == SELECT_ACCOUNT_INTERACTIVE:
            account = choose_account_interactively(
                accounts, show_secrets=args.show_secrets
            )
        else:
            account = select_account_by_selector(
                accounts,
                str(args.select_account),
                show_secrets=args.show_secrets,
            )

        log_print(f"已选择账号: {account.get('name')}")
        return [account]

    return accounts


def run_find_mode(
    accounts: list[dict],
    domain: str,
    account_workers: int,
    zone_workers: int,
    stop_event: Event,
    rate_limiter: Optional[ApiRateLimiter],
    args: argparse.Namespace,
) -> int:
    """并发检查某个域名/zone 是否存在于多个账号中。"""
    print_lock = Lock()
    target_domain = get_main_domain_name_from_str(domain) or domain.strip().lower()

    def _find_one(account: dict) -> tuple[str, bool, str]:
        name = account.get("name") or account.get("email") or "unknown"
        try:
            account_rate_limiter = get_account_rate_limiter(
                args,
                stop_event,
                rate_limiter,
            )
            updater = CloudflareDNSUpdater(
                auth_method=account["auth_method"],
                api_token=account.get("token"),
                api_email=account.get("email"),
                api_key=account.get("key"),
                max_workers=zone_workers,
                print_lock=print_lock,
                stop_event=stop_event,
                account_name=name,
                rate_limiter=account_rate_limiter,
                api_max_retries=args.api_max_retries,
                api_retry_base_delay=args.api_retry_base_delay,
                api_retry_max_sleep=args.api_retry_max_sleep,
            )
            exists = updater.zone_exists(target_domain)
            return name, exists, ""
        except KeyboardInterrupt:
            return name, False, "interrupted"
        except Exception as exc:
            return name, False, str(exc)

    log_print(f"快速查找域名: {target_domain}，账号数: {len(accounts)}")
    found_accounts: list[str] = []

    executor = ThreadPoolExecutor(max_workers=max(1, account_workers))
    pending: set[Future[Any]] = set()
    try:
        pending = {executor.submit(_find_one, account) for account in accounts}
        while pending and not stop_event.is_set():
            done, pending = wait(
                pending,
                timeout=0.5,
                return_when=FIRST_COMPLETED,
            )
            if not done:
                continue

            for future in done:
                name, exists, err = future.result()
                if err:
                    if err == "interrupted":
                        continue
                    log_print(f"[ERR] {name}: {err}")
                    continue
                if exists:
                    found_accounts.append(name)
                    log_print(f"[FOUND] {name}")
                else:
                    log_print(f"[MISS]  {name}")
    except KeyboardInterrupt:
        stop_event.set()
        log_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止查询...")
    finally:
        if stop_event.is_set():
            cancel_pending_futures(pending)
        executor.shutdown(wait=False, cancel_futures=True)

    if stop_event.is_set():
        return 130

    log_print("\n查询结果:")
    if found_accounts:
        for name in found_accounts:
            log_print(f"- {name}")
        return 0

    log_print("- 未在任何账号中找到")
    return 2


def run_operation_for_account(
    account: dict,
    account_index: int,
    account_total: int,
    args: argparse.Namespace,
    whitelist: Optional[list[str]],
    print_lock: Lock,
    stop_event: Event,
    rate_limiter: Optional[ApiRateLimiter],
) -> tuple[str, bool, str]:
    """在单个账号中执行更新或删除操作。"""
    name = account.get("name") or account.get("email") or "unknown"
    try:
        account_rate_limiter = get_account_rate_limiter(
            args,
            stop_event,
            rate_limiter,
        )
        updater = CloudflareDNSUpdater(
            auth_method=account["auth_method"],
            api_token=account.get("token"),
            api_email=account.get("email"),
            api_key=account.get("key"),
            max_workers=args.workers,
            print_lock=print_lock,
            stop_event=stop_event,
            account_name=name,
            rate_limiter=account_rate_limiter,
            api_max_retries=args.api_max_retries,
            api_retry_base_delay=args.api_retry_base_delay,
            api_retry_max_sleep=args.api_retry_max_sleep,
        )
        updater._safe_print(
            f"\n=== [账号 {account_index}/{account_total}] 开始处理账号: {name} ==="
        )

        if args.delete_wildcard:
            batch_result = updater.batch_delete_wildcard(
                whitelist=whitelist,
                record_type=args.record_type,
                old_content=args.old_content,
                dry_run=args.dry_run,
            )
        else:
            batch_result = updater.batch_update(
                new_content=args.new_content,
                old_content=args.old_content,
                whitelist=whitelist,
                record_type=args.record_type,
                dry_run=args.dry_run,
                include_subdomains=not args.no_subdomains,
            )

        if stop_event.is_set():
            return name, False, "interrupted"

        if batch_result.stats.errors > 0:
            return name, False, f"账号内存在 {batch_result.stats.errors} 个错误"

        return name, True, ""
    except KeyboardInterrupt:
        return name, False, "interrupted"
    except Exception as exc:
        return name, False, str(exc)


def configure_rate_limit_args(args: argparse.Namespace) -> None:
    """
    配置保守限流模式与 API 重试参数。

    Cloudflare REST API 常规全局限额为 1200 请求 / 5 分钟，折算约 4 请求 / 秒。
    考虑到：
    - 同一用户的 Dashboard、API key、API token 调用会累计；
    - 用户可能同时运行多个脚本；
    - 多账号/多域名并发会放大瞬时请求；
    保守模式默认采用每账号约 2 请求 / 秒，并降低单账号内 zone 并发。
    """
    if args.request_interval is not None and args.request_interval < 0:
        log_print("--request-interval 不能为负数")
        sys.exit(1)

    if args.conservative:
        if args.request_interval is None:
            args.request_interval = CONSERVATIVE_REQUEST_INTERVAL
        if args.account_workers > CONSERVATIVE_ACCOUNT_WORKERS:
            log_print(
                "保守模式: 已将 --account-workers "
                f"从 {args.account_workers} 调整为 {CONSERVATIVE_ACCOUNT_WORKERS}"
            )
            args.account_workers = CONSERVATIVE_ACCOUNT_WORKERS
        if args.workers > CONSERVATIVE_ZONE_WORKERS:
            log_print(
                "保守模式: 已将 --workers "
                f"从 {args.workers} 调整为 {CONSERVATIVE_ZONE_WORKERS}"
            )
            args.workers = CONSERVATIVE_ZONE_WORKERS
    elif args.request_interval is None:
        args.request_interval = 0.0

    if args.api_max_retries < 0:
        log_print("--api-max-retries 不能为负数")
        sys.exit(1)
    if args.api_retry_base_delay <= 0:
        log_print("--api-retry-base-delay 必须大于 0")
        sys.exit(1)
    if args.api_retry_max_sleep <= 0:
        log_print("--api-retry-max-sleep 必须大于 0")
        sys.exit(1)


def build_rate_limiter(
    args: argparse.Namespace, stop_event: Event
) -> Optional[ApiRateLimiter]:
    """根据命令行参数构建 API 限速器。"""
    if not args.request_interval or args.request_interval <= 0:
        return None
    return ApiRateLimiter(min_interval=args.request_interval, stop_event=stop_event)


def build_shared_rate_limiter(
    args: argparse.Namespace, stop_event: Event
) -> Optional[ApiRateLimiter]:
    """仅在 global 作用域下构建全进程共享限速器。"""
    if args.rate_limit_scope != "global":
        return None
    return build_rate_limiter(args, stop_event)


def get_account_rate_limiter(
    args: argparse.Namespace,
    stop_event: Event,
    shared_rate_limiter: Optional[ApiRateLimiter],
) -> Optional[ApiRateLimiter]:
    """
    为一个账号选择实际使用的限速器。

    - global: 所有账号共享同一个限速器，最保守。
    - account: 每个账号独立一个限速器，适合多个独立 Cloudflare 账号并行处理。
    """
    if not args.request_interval or args.request_interval <= 0:
        return None
    if args.rate_limit_scope == "global":
        return shared_rate_limiter
    return build_rate_limiter(args, stop_event)


def validate_worker_args(args: argparse.Namespace) -> None:
    """限制并发参数，避免误设过高导致 API 限流或本机资源耗尽。"""
    if args.workers < 1:
        log_print("--workers 至少为 1")
        sys.exit(1)
    if args.workers > 20:
        log_print("线程数过高，已自动调整为 20")
        args.workers = 20

    if args.account_workers < 1:
        log_print("--account-workers 至少为 1")
        sys.exit(1)
    if args.account_workers > 20:
        log_print("账号并发数过高，已自动调整为 20")
        args.account_workers = 20


def validate_action_args(args: argparse.Namespace) -> None:
    """校验运行模式参数，避免更新和删除模式同时触发。"""
    if args.find_domain and (args.new_content or args.delete_wildcard):
        log_print("--find-domain 查询模式不能与更新/删除模式同时使用")
        sys.exit(1)

    if args.delete_wildcard and args.new_content:
        log_print(
            "--delete-wildcard 删除模式不能与 --new-ip/--new-content 更新模式同时使用"
        )
        sys.exit(1)

    if args.new_content:
        try:
            # 提前校验一次，失败时无需启动线程。
            final_type = resolve_update_record_type(
                args.record_type, args.new_content, args.old_content
            )
            log_print(f"更新模式记录类型: {final_type}")
        except ValueError as exc:
            log_print(f"参数错误: {exc}")
            sys.exit(1)

    if args.delete_wildcard:
        try:
            final_type = resolve_delete_record_type(args.record_type)
            log_print(f"删除通配符记录模式，记录类型: {final_type}")
        except ValueError as exc:
            log_print(f"参数错误: {exc}")
            sys.exit(1)


def main() -> None:
    args = parse_args()
    configure_logging(args.log_file, args.log_level, args.log_overwrite)
    configure_rate_limit_args(args)
    log_startup(args)
    validate_worker_args(args)
    validate_action_args(args)

    stop_event = Event()
    install_ctrl_c_handler(stop_event)
    rate_limiter = build_shared_rate_limiter(args, stop_event)
    if args.request_interval and args.request_interval > 0:
        scope_text = "全进程共享" if args.rate_limit_scope == "global" else "每账号独立"
        log_print(
            f"API 限速已启用: scope={args.rate_limit_scope}({scope_text}), "
            f"相邻 Cloudflare API 请求至少间隔 {args.request_interval:.3f}s；"
            f"官方常规限额参考 {CF_GLOBAL_RATE_LIMIT_PER_5_MIN}/5min。"
        )

    accounts = build_accounts(args)

    # 模式 0：列出可用账号。
    if args.list_accounts:
        list_accounts(accounts, show_secrets=args.show_secrets)
        sys.exit(0)

    # 模式 1：快速查域名。
    if args.find_domain:
        code = run_find_mode(
            accounts=accounts,
            domain=args.find_domain,
            account_workers=args.account_workers,
            zone_workers=args.workers,
            stop_event=stop_event,
            rate_limiter=rate_limiter,
            args=args,
        )
        sys.exit(code)

    # 模式 2：批量更新或删除通配符记录。
    if args.new_content or args.delete_wildcard:
        whitelist: Optional[list[str]] = None
        if args.whitelist:
            whitelist = load_whitelist(args.whitelist)
            if not whitelist:
                log_print("白名单文件为空或未解析到有效域名")
                sys.exit(1)
            log_print(f"已加载白名单: {len(whitelist)}")

        print_lock = Lock()
        success = 0
        failed = 0
        account_total = len(accounts)

        executor = ThreadPoolExecutor(max_workers=args.account_workers)
        pending: set[Future[Any]] = set()
        try:
            pending = {
                executor.submit(
                    run_operation_for_account,
                    account,
                    account_index,
                    account_total,
                    args,
                    whitelist,
                    print_lock,
                    stop_event,
                    rate_limiter,
                )
                for account_index, account in enumerate(accounts, start=1)
            }

            while pending and not stop_event.is_set():
                done, pending = wait(
                    pending,
                    timeout=0.5,
                    return_when=FIRST_COMPLETED,
                )
                if not done:
                    continue

                for future in done:
                    name, ok, err = future.result()
                    if ok:
                        success += 1
                        SUCCESS_ACCOUNTS.append(name)
                        log_print(f"[ACCOUNT-OK] {name}")
                    else:
                        if err == "interrupted":
                            continue
                        failed += 1
                        FAILED_ACCOUNTS.append(name)
                        log_print(f"[ACCOUNT-ERR] {name}: {err}")
        except KeyboardInterrupt:
            stop_event.set()
            log_print("\n[INTERRUPT] 收到 Ctrl+C，正在终止所有线程...")
        finally:
            if stop_event.is_set():
                cancel_pending_futures(pending)
            executor.shutdown(wait=False, cancel_futures=True)

        if stop_event.is_set():
            log_print("任务已被用户中断")
            sys.exit(130)

        log_print("\n账号汇总:")
        log_print(f"- 成功: {success}")
        log_print(f"- 失败: {failed}")
        # 打印失败的账号
        if failed > 0:
            log_print("\n失败的账号列表:")
            for name in FAILED_ACCOUNTS:
                log_print(name)
        sys.exit(1 if failed > 0 else 0)

    # 默认模式：没有指定动作时列出账号，给用户操作提示。
    list_accounts(accounts, show_secrets=args.show_secrets)
    log_print("\n提示:")
    log_print("- 使用 -s/--select-account 可交互选择账号；-s <账号名> 可直接指定账号。")
    log_print("- 使用 --new-ip/--new-content 进入更新模式。")
    log_print("- 使用 --delete-wildcard 进入删除通配符记录模式。")
    log_print("- 使用 -f/--find-domain 查询域名所在账号。")
    sys.exit(0)


if __name__ == "__main__":
    main()
