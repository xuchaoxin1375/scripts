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
   - 支持 IPv4 <-> IPv6 跨类型迁移：例如 A(IPv4) -> AAAA(IPv6) 时创建新 AAAA 并删除旧 A。

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
   - 查询日志包含账号序号、账号名、可用邮箱、认证方式、目标域名和耗时，便于定位失败账号。
   - 不会在查询日志中输出 API Token 或 Global API Key。

5. 处理进度输出
   - 处理账号内域名时输出：[i/n] 正在处理域名 xxx。
   - 若白名单只匹配部分域名，同时输出“账号共 N 个域名，本次待处理 M 个”。

6. Cloudflare API 限流与速度档位
   - Cloudflare 官方 REST API 全局限额通常为 1200 次 / 5 分钟 / 用户或账号 Token。
   - 默认 --speed eco 保守执行，尽量不触碰限流；着急时用 balanced/fast/turbo 提速。
   - 使用 --request-interval 可自定义本进程内相邻两次 Cloudflare API 请求的最小间隔。
   - 收到 HTTP 429 时会读取 retry-after / Ratelimit 响应头并自动退避重试。
   - 可重试状态码覆盖 408/409/425/5xx 与 Cloudflare 520~527/530；触发限流后
     限速器临时叠加等待（自适应），成功后逐步衰减，小账号快速场景不受影响。

7. 中断处理
   - 支持 Ctrl+C 通知所有账号/域名工作线程停止。
   - 尚未开始的 future 会被取消并记为 cancelled；已经运行中的线程会在下一次检查 stop_event 或当前 HTTP 请求返回后退出。
   - 每次批量结束输出对账行（expected/completed/cancelled），保证 expected == completed + cancelled。

8. 失败清单与重跑（CSV）
   - 使用 --failed-output failures.csv 将失败/取消行导出（UTF-8-SIG）。
   - 使用 --resume-from failures.csv 仅重跑清单中的域名；已完成项因内容一致自动跳过，天然幂等。

9. 出口代理（可选）
   - 使用 -P/--proxy（可多次）或 --proxy-file 配置 1 到多个 HTTP/HTTPS 代理。
   - 调度模式 --proxy-mode：round-robin / sticky / failover；网络错误自动冷却切换。
   - 代理改变出口 IP 与链路，可缓解 IP 级限流/封禁并提高重试成功率；
     Cloudflare 配额按 credential 计算，配额侧仍需 --conservative/--request-interval。

维护约定：
- 每次修改本文件后，都应执行项目文档“代码质量检查”章节推荐的完整检查。
- 至少包括 Ruff 格式化与静态检查、Pyright 类型检查、Python 语法编译检查，
  以及 git diff 空白错误检查；所有检查通过后再提交或交付修改。

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
from collections import Counter
from collections.abc import Iterable, Mapping
from concurrent.futures import (
    FIRST_COMPLETED,
    Future,
    ThreadPoolExecutor,
    as_completed,
    wait,
)
from dataclasses import dataclass, field
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from threading import Event, Lock, local as thread_local
from typing import Any, Callable, Optional, Union
from urllib.parse import urlparse

import requests

VERSION = "20260929"

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
CF_CONFIG_PATH = os.getenv(
    "CF_CONFIG_PATH", f"{DEPLOY_CONFIGS}/cf_config.csv"
)  # cf_config.json

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
DEFAULT_SPEED = "eco"
# 速度档位：默认 eco 保守（尽量不触碰限流），着急时用更高档位。
# 各档含义（account_workers / workers / request_interval 秒）：
# - eco：多账号各 3 并发、单账号内 2 并发、每账号约 2 请求/秒；
# - balanced：略微偏快，适合账号多、每账号域名少的日常批量；
# - fast：快速档，429 风险明显上升，失败项进清单需重跑；
# - turbo：不额外限速，仅保留自适应退避，限流几乎必然发生，只建议配合清单重跑使用。
SPEED_PRESETS: dict[str, dict[str, float]] = {
    "eco": {
        "account_workers": 3,
        "workers": 2,
        "request_interval": 0.5,
    },
    "balanced": {
        "account_workers": 5,
        "workers": 4,
        "request_interval": 0.2,
    },
    "fast": {
        "account_workers": 8,
        "workers": 6,
        "request_interval": 0.1,
    },
    "turbo": {
        "account_workers": 20,
        "workers": 20,
        "request_interval": 0.0,
    },
}
HARD_MAX_WORKERS = 20
DEFAULT_API_MAX_RETRIES = 5
DEFAULT_API_RETRY_BASE_DELAY = 2.0
DEFAULT_API_RETRY_MAX_SLEEP = 300.0

# 可重试的 HTTP 状态码。除 429 与常见 5xx 外，还覆盖 Cloudflare 源站错误
# 520~527/530（缓存/源站异常，常为临时性）以及 408/409/425 等临时性错误。
# 401/403/404 等语义性错误不在其中，失败即记账等待重跑，不做无意义重试。
RETRYABLE_HTTP_STATUS = frozenset(
    {
        408,
        409,
        425,
        429,
        500,
        502,
        503,
        504,
        520,
        521,
        522,
        523,
        524,
        525,
        526,
        527,
        530,
    }
)

# 自适应限速上限：连续触发限流时，限速器在用户配置间隔之上最多再叠加的秒数。
# 无 429/可重试错误时不叠加，小账号快速场景不受影响。
ADAPTIVE_MAX_EXTRA_INTERVAL = 5.0

# 失败清单 CSV 列。默认只写入 failed/cancelled 行，保持文件简洁；
# dry_run 预览行不写入失败清单。
FAILURE_CSV_FIELDNAMES = [
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

# 视为“未完成、需要重跑”的结果状态。done/skipped/dry_run_* 不在此列。
FAILURE_STATUSES = frozenset(
    {
        "error",
        "error_delete_old_after_migrate",
        "cancelled",
    }
)

# --list-zones 导出 CSV 列。active 表示 Cloudflare 侧处于激活状态的 zone。
ZONES_CSV_FIELDNAMES = [
    "account",
    "name",
    "status",
    "zone_id",
    "nameservers",
]

# --provision 导出 CSV 列：域名配置结果（DNS/激活/邮箱/SSL/安全）。
PROVISION_CSV_FIELDNAMES = [
    "account",
    "domain",
    "zone_id",
    "zone_status",
    "activation",
    "record_status",
    "email_status",
    "ssl_status",
    "security_status",
    "error",
    "timestamp",
]

# 基础安全设置：反机器人 / RUM 等默认不开启，只启用低风险基础项。
PROVISION_BASIC_SECURITY: dict[str, Any] = {
    "always_use_https": "on",
    "browser_check": "on",
    "security_level": "medium",
}
# 免费加速增益（与旧 cf_config_api.py 一致），默认开启。
PROVISION_SPEED: dict[str, Any] = {
    "speed_brain": "on",
    "0rtt": "on",
    "early_hints": "on",
}

# zone 级读取失败时最多尝试次数（初次 + 1 次补偿重试）。
ZONE_FETCH_MAX_ATTEMPTS = 2

LOGGER = logging.getLogger("cloudflare_dns_tool")
SENSITIVE_ARG_NAMES = {"-t", "--token", "-k", "--key", "--api-key", "-P", "--proxy"}
PROXY_DEFAULT_MODE = "round-robin"
PROXY_FAILURE_COOLDOWN = 60.0

# --quiet: 把人类可读日志改道到 stderr，保持 stdout 只含机器可解析输出(JSON/CSV 行)。
QUIET = False


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
    """同时输出到控制台和日志文件。--quiet 时改道 stderr。"""
    if QUIET:
        kwargs.setdefault("file", sys.stderr)
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
        if old_content and old_version not in {4, 6}:
            raise ValueError(
                "A 记录的 --old-ip/--old-content 必须是合法 IPv4/IPv6 地址；"
                "如需更新 CNAME 请指定 --record-type CNAME"
            )

    if final_type == "AAAA":
        if new_version != 6:
            raise ValueError("AAAA 记录的新内容必须是合法 IPv6 地址")
        if old_content and old_version not in {4, 6}:
            raise ValueError(
                "AAAA 记录的 --old-ip/--old-content 必须是合法 IPv4/IPv6 地址；"
                "如需更新 CNAME 请指定 --record-type CNAME"
            )

    return final_type


def record_type_for_ip_version(ip_version: int) -> str:
    """根据 IP 版本返回对应 DNS 记录类型。"""
    if ip_version == 4:
        return "A"
    if ip_version == 6:
        return "AAAA"
    raise ValueError(f"不支持的 IP 版本: {ip_version}")


def is_ip_family_migration(
    old_content: Optional[str], new_content: Optional[str]
) -> bool:
    """判断是否为 IPv4 <-> IPv6 跨记录类型迁移。"""
    if not old_content or not new_content:
        return False
    old_version = get_ip_version(old_content)
    new_version = get_ip_version(new_content)
    return (
        old_version in {4, 6} and new_version in {4, 6} and old_version != new_version
    )


def resolve_delete_ip_record_type(delete_ip: str, record_type: str) -> str:
    """
    解析“删除指向指定 IP 的记录”最终要读取的记录类型。

    删除 IPv4 时只需要扫描 A 记录；删除 IPv6 时只需要扫描 AAAA 记录。
    如果用户显式指定了不匹配的 --record-type，则提前报错，避免误解。
    """
    ip_version = get_ip_version(delete_ip)
    if ip_version not in {4, 6}:
        raise ValueError("--delete-ip 必须是合法 IPv4 或 IPv6 地址")

    inferred_type = record_type_for_ip_version(ip_version)
    if record_type in {"auto", "ALL", inferred_type}:
        return inferred_type

    raise ValueError(
        f"--delete-ip {delete_ip} 对应记录类型为 {inferred_type}，"
        f"但当前 --record-type={record_type} 不匹配"
    )


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


def normalize_content_for_compare(value: Optional[str]) -> str:
    """归一化 DNS 内容用于相等比对，不改变实际下发的原始值。

    - 去首尾空白；CNAME 忽略大小写与尾点；
    - IP 地址用 ipaddress 压缩表示，避免 IPv6 多种写法被误判为不同。
    """
    if value is None:
        return ""
    text = str(value).strip()
    if not text:
        return ""
    lowered = text.lower().rstrip(".")
    try:
        return ipaddress.ip_address(text).compressed.lower()
    except ValueError:
        return lowered


def contents_equal(first: Optional[str], second: Optional[str]) -> bool:
    """比对两条 DNS 内容是否等价（归一化后）。"""
    return normalize_content_for_compare(first) == normalize_content_for_compare(second)


def is_rate_limit_api_payload(data: object) -> bool:
    """判断 success:false 的响应体是否实质为限流（值得重试）。

    Cloudflare 有时以 HTTP 200 + success:false 返回限流错误，
    此时不能按普通失败直接记账，应走 429 退避重试。
    """
    if not isinstance(data, dict):
        return False
    errors = data.get("errors")
    if not isinstance(errors, list):
        return False
    for item in errors:
        if not isinstance(item, dict):
            continue
        try:
            code = int(item.get("code", 0) or 0)
        except (TypeError, ValueError):
            code = 0
        message = str(item.get("message", "") or "").lower()
        if code in {10000, 8000000, 8000001}:
            return True
        if "rate limit" in message or "too many requests" in message:
            return True
    return False


def utc_now_iso() -> str:
    """返回当前 UTC 时间的 ISO8601 字符串，用于失败清单。"""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def write_failure_csv(path: str, rows: list[dict[str, Any]]) -> None:
    """写入失败清单 CSV（UTF-8-SIG，兼容 Excel 中文）。

    只写入 failed/cancelled 行；调用方负责过滤。父目录自动创建。
    """
    import csv

    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8-sig") as file_obj:
        writer = csv.DictWriter(file_obj, fieldnames=FAILURE_CSV_FIELDNAMES)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in FAILURE_CSV_FIELDNAMES})


def write_zones_csv(path: str, rows: list[dict[str, Any]]) -> None:
    """写入 zone 列表 CSV（UTF-8-SIG，兼容 Excel 中文）。父目录自动创建。"""
    import csv

    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8-sig") as file_obj:
        writer = csv.DictWriter(file_obj, fieldnames=ZONES_CSV_FIELDNAMES)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in ZONES_CSV_FIELDNAMES})


def write_provision_csv(path: str, rows: list[dict[str, Any]]) -> None:
    """写入域名配置结果 CSV（UTF-8-SIG）。父目录自动创建。"""
    import csv

    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8-sig") as file_obj:
        writer = csv.DictWriter(file_obj, fieldnames=PROVISION_CSV_FIELDNAMES)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in PROVISION_CSV_FIELDNAMES})


def load_resume_entries(path: str) -> list[tuple[str, str]]:
    """读取 --resume-from CSV，返回 (account, zone) 小写元组列表。

    account 为空表示适用于所有账号；zone 为空表示整个账号（账号级失败哨兵行），
    重跑时该账号不过滤、全量执行。
    """
    import csv

    entries: list[tuple[str, str]] = []
    with open(path, "r", newline="", encoding="utf-8-sig") as file_obj:
        reader = csv.DictReader(file_obj)
        if reader.fieldnames is None:
            return entries
        lowered = {str(name or "").strip().lower() for name in reader.fieldnames}
        if "zone" not in lowered:
            raise ValueError(f"重跑文件缺少 zone 列: {path}")
        for row in reader:
            account = (
                str(row.get("account") or row.get("Account") or "").strip().lower()
            )
            zone = str(row.get("zone") or row.get("Zone") or "").strip().lower()
            entries.append((account, zone))
    return entries


def resume_filter_for_account(
    entries: Optional[list[tuple[str, str]]], account_name: str
) -> Optional[set[str]]:
    """计算当前账号的重跑过滤集合。

    返回 None 表示不过滤（无重跑文件，或清单含本账号整账号哨兵行）；
    返回集合（含空集合）表示仅处理其中 zone，空集合即本账号无待重跑域名。
    """
    if entries is None:
        return None
    current = (account_name or "").strip().lower()
    for account, zone in entries:
        if not zone and account in {"", current}:
            return None
    return {zone for account, zone in entries if zone and account in {"", current}}


def resume_zones_for_account(
    entries: list[tuple[str, str]], account_name: str
) -> set[str]:
    """兼容旧语义：返回属于当前账号的 zone 集合（小写）。"""
    result = resume_filter_for_account(entries, account_name)
    return set() if result is None else result


def infer_action_from_status(status: str) -> str:
    """从结果状态推断失败清单的 action 列。"""
    mapping = {
        "updated": "update",
        "updated_full": "full_replace",
        "created": "migrate",
        "deleted": "delete",
        "deleted_ip": "delete_ip",
        "deleted_old_after_migrate": "migrate",
        "deleted_old_full_migrate": "full_replace",
        "deleted_zone": "delete_zone",
        "cleared_dns": "delete_zone",
        "added_domain": "add",
        "added_record": "add",
        "updated_attrs": "set_attrs",
        "exported": "export",
        "error": "batch",
        "error_delete_old_after_migrate": "migrate",
        "cancelled": "batch",
    }
    return mapping.get(status, "batch")


def failure_rows_for_results(
    account_name: str, results: list["DNSOperationResult"]
) -> list[dict[str, Any]]:
    """提取失败/取消行并补齐账号，供失败清单 CSV 使用。"""
    rows: list[dict[str, Any]] = []
    for item in results:
        if item.status not in FAILURE_STATUSES:
            continue
        if not item.account:
            item.account = account_name
        rows.append(item.to_failure_row(infer_action_from_status(item.status)))
    return rows


def serialize_zone_backup(
    account_name: str, zone: dict, records: list[dict]
) -> dict[str, Any]:
    """序列化单个 zone 的备份载荷（JSON 全量，可读可审计）。"""
    slim_records = [
        {
            "id": record.get("id", ""),
            "type": record.get("type", ""),
            "name": record.get("name", ""),
            "content": record.get("content", ""),
            "ttl": record.get("ttl", 1),
            "proxied": bool(record.get("proxied", False)),
        }
        for record in records
    ]
    return {
        "tool": "cloudflare_dns_tool",
        "version": VERSION,
        "account": account_name,
        "zone": zone.get("name", ""),
        "zone_id": zone.get("id", ""),
        "exported_at": utc_now_iso(),
        "record_count": len(slim_records),
        "records": slim_records,
    }


def format_bind_zone(zone_name: str, records: list[dict]) -> str:
    """生成简化 BIND 区域文件（仅记录行，供人阅读与外部工具消费）。

    注意：不含 SOA/NS 权威记录，不可直接灌入权威服务，仅作备份参考。
    """
    lines = [
        f"; cloudflare_dns_tool export, zone={zone_name}, at={utc_now_iso()}",
        f"$ORIGIN {zone_name}.",
    ]
    for record in records:
        r_type = str(record.get("type", ""))
        r_name = str(record.get("name", ""))
        short = "@" if r_name.lower() == zone_name.lower() else r_name
        content = str(record.get("content", ""))
        ttl = record.get("ttl", 1)
        proxied = "yes" if record.get("proxied") else "no"
        lines.append(f"{short}\t{ttl}\tIN\t{r_type}\t{content} ; proxied={proxied}")
    return "\n".join(lines) + "\n"


def write_zone_backup_file(
    base_dir: str, account_name: str, zone_name: str, payload: dict[str, Any], fmt: str
) -> str:
    """写入单个 zone 备份文件，返回写入路径。"""
    safe_account = re.sub(r"[^\w\-.]+", "_", account_name or "unknown")
    safe_zone = re.sub(r"[^\w\-.]+", "_", zone_name or "unknown")
    account_dir = os.path.join(os.path.abspath(base_dir), safe_account)
    os.makedirs(account_dir, exist_ok=True)
    if fmt == "bind":
        path = os.path.join(account_dir, f"{safe_zone}.bind")
        with open(path, "w", encoding="utf-8") as file_obj:
            file_obj.write(format_bind_zone(zone_name, payload.get("records", [])))
    else:
        path = os.path.join(account_dir, f"{safe_zone}.json")
        with open(path, "w", encoding="utf-8") as file_obj:
            json.dump(payload, file_obj, ensure_ascii=False, indent=2)
    return path


def parse_add_record_spec(spec: str) -> tuple[str, str, str]:
    """解析 --add-record 参数，兼容 IPv6 内容中的冒号。

    支持 name:type:content、name-type-content、空格分隔。中间的 type
    通过已知类型 token 定位，避免 IPv6 的冒号破坏切分。
    """
    text = (spec or "").strip()
    if not text:
        raise ValueError("记录格式为空")
    match = re.match(
        r"^(?P<name>.+?)[\s:\-]+(?P<rtype>[A-Za-z]+)[\s:\-]+(?P<content>.+)$",
        text,
    )
    if not match:
        raise ValueError(
            "格式错误，支持 name:type:content / name-type-content / name type content，"
            f"收到: {spec}"
        )
    name = match.group("name").strip()
    rtype = match.group("rtype").strip().upper()
    content = match.group("content").strip()
    if not name or not rtype or not content:
        raise ValueError(
            "格式错误，支持 name:type:content / name-type-content / name type content，"
            f"收到: {spec}"
        )
    return name, rtype, content


def mask_secret(value: Optional[str], show: bool = False) -> str:
    """列表展示账号时默认隐藏 token/key，避免误泄露。"""
    if not value:
        return ""
    if show:
        return value
    if len(value) <= 8:
        return "*" * len(value)
    return f"{value[:4]}...{value[-4:]}"


def normalize_config_text(value: Any) -> str:
    """将配置值规范化为文本，并把常见表格空值统一转换为空字符串。"""
    if value is None:
        return ""

    text = str(value).strip()
    if text.lower() in {"", "nan", "none", "null", "<na>"}:
        return ""
    return text


def format_account_identity(
    account: Mapping[str, Any],
    account_index: Optional[int] = None,
    account_total: Optional[int] = None,
) -> str:
    """构建不包含密钥的账号标识，供并发查询日志定位具体账号。"""
    name = normalize_config_text(account.get("name")) or "unknown"
    email = normalize_config_text(account.get("email")) or "不可用"
    auth_method = normalize_config_text(account.get("auth_method")) or "unknown"
    progress = ""
    if account_index is not None and account_total is not None:
        progress = f"[账号 {account_index}/{account_total}] "
    return f"{progress}name={name}, email={email}, auth={auth_method}"


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
    本进程内共享的 Cloudflare API 调用限速器（ floor + 自适应叠加 ）。

    设计要点：
    - 账号多、zone 多时，即使每个账号/zone 线程并发，实际 API 请求仍会被统一限速。
    - 限速器只影响本脚本进程内的请求，无法感知其他脚本或 Cloudflare Dashboard。
      因此保守模式默认使用 0.5 秒/请求，为外部调用留出余量。
    - 该限速器是“最小请求间隔”模型，简单、可维护，不依赖第三方包。
    - 自适应部分只在触发 429/可重试错误后临时叠加等待；无错误时保持用户配置
      的 floor 不变，小账号快速场景不受影响（不漏优先、速度其次）。
    """

    def __init__(self, min_interval: float = 0.0, stop_event: Optional[Event] = None):
        self.min_interval = max(0.0, float(min_interval or 0.0))
        self._stop_event = stop_event or Event()
        self._lock = Lock()
        self._next_allowed_at = 0.0
        self._adaptive_extra = 0.0

    @property
    def enabled(self) -> bool:
        return self.min_interval > 0 or self._adaptive_extra > 0

    @property
    def adaptive_extra(self) -> float:
        with self._lock:
            return self._adaptive_extra

    def note_rate_limited(self) -> None:
        """记录一次限流/可重试错误，临时放大后续等待间隔。"""
        with self._lock:
            if self._adaptive_extra <= 0:
                self._adaptive_extra = 0.5
            else:
                self._adaptive_extra = min(
                    ADAPTIVE_MAX_EXTRA_INTERVAL, self._adaptive_extra * 2.0
                )

    def note_success(self) -> None:
        """记录一次成功，逐步衰减自适应叠加。"""
        with self._lock:
            if self._adaptive_extra > 0:
                self._adaptive_extra = max(0.0, self._adaptive_extra * 0.9)
                if self._adaptive_extra < 0.05:
                    self._adaptive_extra = 0.0

    def wait(self) -> None:
        """在发起 API 请求前调用，确保相邻请求至少间隔 floor + 自适应秒数。"""
        while True:
            if self._stop_event.is_set():
                raise KeyboardInterrupt

            with self._lock:
                interval = self.min_interval + self._adaptive_extra
                if interval <= 0:
                    return
                now = time.monotonic()
                wait_seconds = self._next_allowed_at - now
                if wait_seconds <= 0:
                    self._next_allowed_at = now + interval
                    return

            interruptible_sleep(min(wait_seconds, 0.5), self._stop_event)


def sanitize_proxy_url(url: str) -> str:
    """脱敏代理 URL：去掉 userinfo，仅保留 scheme://host:port，用于日志展示。"""
    try:
        parsed = urlparse(str(url).strip())
        host = parsed.hostname or ""
        port = f":{parsed.port}" if parsed.port else ""
        scheme = (parsed.scheme or "http").lower()
        return f"{scheme}://{host}{port}" if host else "***"
    except (ValueError, TypeError):
        return "***"


def validate_proxy_url(url: str) -> str:
    """校验代理 URL，返回规范化后的原始串（保留凭证供 requests 使用）。

    仅支持 http/https（requests 原生支持，无需额外依赖）。
    """
    text = str(url or "").strip()
    parsed = urlparse(text)
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
        raise ValueError(
            f"代理地址格式错误，需为 http(s)://[user:pass@]host:port，收到: {url}"
        )
    return text


def load_proxy_file(path: str) -> list[str]:
    """读取代理文件，每行一个 URL，空行与 # 注释忽略。"""
    proxies: list[str] = []
    try:
        with open(path, "r", encoding="utf-8") as file_obj:
            for line_no, raw_line in enumerate(file_obj, start=1):
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                try:
                    proxies.append(validate_proxy_url(line))
                except ValueError as exc:
                    log_print(f"[WARN] 代理文件第 {line_no} 行无效，已跳过: {exc}")
    except FileNotFoundError:
        log_print(f"代理文件不存在: {path}")
        sys.exit(1)
    return proxies


class ProxyPool:
    """线程安全的出口代理池（HTTP/HTTPS）。

    作用与边界（诚实说明）：
    - 代理切换改变的是出口 IP 与链路，可缓解 egress-IP 级限流/封禁、
      本地链路故障，并在网络错误时自动切换，提高重试成功率；
    - Cloudflare REST 配额按 credential 计算（1200/5min），换代理
      不能提高该配额，配额侧仍需 --conservative/--request-interval。
    - 模式：round-robin（逐请求轮转，默认）、sticky（每线程固定一个）、
      failover（首个健康代理，仅故障时切换）。
    - 网络错误（RequestException）触发故障标记与冷却；429/5xx 属于
      服务端语义，不标记代理故障（round-robin 下次自然换出口）。
    """

    def __init__(
        self,
        urls: list[str],
        mode: str = PROXY_DEFAULT_MODE,
        failure_cooldown: float = PROXY_FAILURE_COOLDOWN,
    ):
        if mode not in {"round-robin", "sticky", "failover"}:
            raise ValueError(f"不支持的代理模式: {mode}")
        unique = list(dict.fromkeys(urls))
        if not unique:
            raise ValueError("代理池为空")
        self._urls = unique
        self._mode = mode
        self._cooldown = max(1.0, float(failure_cooldown))
        self._lock = Lock()
        self._counter = 0
        self._current = 0
        self._unhealthy: dict[str, float] = {}
        self._local = thread_local()

    @property
    def urls(self) -> list[str]:
        return list(self._urls)

    @property
    def mode(self) -> str:
        return self._mode

    def sanitized_list(self) -> str:
        return ", ".join(sanitize_proxy_url(url) for url in self._urls)

    def _healthy(self, url: str, now: float) -> bool:
        return self._unhealthy.get(url, 0.0) <= now

    def _pick_fallback(self) -> str:
        """全部不健康时仍选最早过期的，保证请求不被饿死。"""
        return min(self._urls, key=lambda url: self._unhealthy.get(url, 0.0))

    def next_proxy(self) -> str:
        """取下一个出口代理（必定返回一个，不断流）。"""
        now = time.monotonic()
        with self._lock:
            if self._mode == "sticky":
                idx = getattr(self._local, "proxy_index", None)
                if idx is None or not self._healthy(self._urls[idx], now):
                    idx = self._counter % len(self._urls)
                    self._counter += 1
                    self._local.proxy_index = idx
                url = self._urls[idx]
                return url if self._healthy(url, now) else self._pick_fallback()
            if self._mode == "failover":
                url = self._urls[self._current % len(self._urls)]
                if self._healthy(url, now):
                    return url
                for step in range(1, len(self._urls) + 1):
                    candidate = self._urls[(self._current + step) % len(self._urls)]
                    if self._healthy(candidate, now):
                        self._current += step
                        return candidate
                return self._pick_fallback()
            # round-robin
            for _ in range(len(self._urls)):
                url = self._urls[self._counter % len(self._urls)]
                self._counter += 1
                if self._healthy(url, now):
                    return url
            return self._pick_fallback()

    def report_success(self, url: str) -> None:
        with self._lock:
            self._unhealthy.pop(url, None)

    def report_failure(self, url: str) -> None:
        with self._lock:
            self._unhealthy[url] = time.monotonic() + self._cooldown


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
    """单条 DNS 记录操作结果，可直接导出为失败清单 CSV。"""

    zone: str
    name: str
    record_type: str
    old_content: Optional[str]
    new_content: Optional[str]
    # updated / created / deleted / dry_run_* / skipped / error /
    # error_delete_old_after_migrate / cancelled
    status: str
    message: str = ""
    account: str = ""
    attempts: int = 1
    record_id: str = ""

    def to_failure_row(self, action: str) -> dict[str, Any]:
        """转换为失败清单 CSV 行；调用方保证 status 已属于失败集合。"""
        return {
            "account": self.account,
            "zone": self.zone,
            "record_id": self.record_id,
            "name": self.name,
            "type": self.record_type,
            "old_content": self.old_content or "",
            "new_content": self.new_content or "",
            "action": action or infer_action_from_status(self.status),
            "status": self.status,
            "attempts": self.attempts,
            "error": self.message,
            "timestamp": utc_now_iso(),
        }


@dataclass
class OperationStats:
    """线程安全统计信息。多个 zone 并发处理时统一累加。

    cancelled 统计因中断/取消而未执行的条目，与 errors 并列为
    “需要重跑”信号；skipped 仅表示本次按规则跳过，无需重跑。
    """

    updated: int = 0
    created: int = 0
    deleted: int = 0
    dry_run: int = 0
    skipped: int = 0
    errors: int = 0
    cancelled: int = 0
    _lock: Lock = field(default_factory=Lock, repr=False)

    def inc_updated(self) -> None:
        with self._lock:
            self.updated += 1

    def inc_created(self) -> None:
        with self._lock:
            self.created += 1

    def inc_deleted(self, count: int = 1) -> None:
        with self._lock:
            self.deleted += count

    def inc_dry_run(self) -> None:
        with self._lock:
            self.dry_run += 1

    def inc_skipped(self) -> None:
        with self._lock:
            self.skipped += 1

    def inc_errors(self) -> None:
        with self._lock:
            self.errors += 1

    def inc_cancelled(self, count: int = 1) -> None:
        with self._lock:
            self.cancelled += count

    def summary(self) -> str:
        with self._lock:
            return (
                f"updated={self.updated}, created={self.created}, "
                f"deleted={self.deleted}, dry_run={self.dry_run}, "
                f"skipped={self.skipped}, errors={self.errors}, "
                f"cancelled={self.cancelled}"
            )


@dataclass
class BatchRunResult:
    """单账号批处理结果（含对账字段）。"""

    results: list[DNSOperationResult]
    stats: OperationStats
    expected_zones: int = 0
    completed_zones: int = 0
    cancelled_zones: int = 0

    def reconcile_text(self) -> str:
        return (
            f"zones expected={self.expected_zones}, "
            f"completed={self.completed_zones}, "
            f"cancelled={self.cancelled_zones}"
        )


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
        explicit_domains: Optional[list[str]] = None,
        proxy_pool: Optional[ProxyPool] = None,
    ):
        self.max_workers = max_workers
        self.account_name = account_name
        self._explicit_domains = explicit_domains
        self._print_lock = print_lock or Lock()
        self._stop_event = stop_event or Event()
        self._thread_local = thread_local()
        self._rate_limiter = rate_limiter
        self._proxy_pool = proxy_pool
        # 可选进度回调 progress_cb(zone_name, state)，state 为 done/error/cancelled。
        # CLI 不设置；Web 任务层可设置以接收 zone 级进度，回调异常不影响引擎。
        self.progress_cb: Optional[Callable[[str, str], None]] = None
        self._api_max_retries = max(0, int(api_max_retries))
        self._api_retry_base_delay = max(0.1, float(api_retry_base_delay))
        self._api_retry_max_sleep = max(1.0, float(api_retry_max_sleep))
        # 账号 ID 缓存:zone 创建、邮箱转发等接口需要,按凭证解析一次即可。
        self._account_id: Optional[str] = None
        self._account_id_loaded = False

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
        - 对 RETRYABLE_HTTP_STATUS（含 Cloudflare 520~527/530）与短暂网络错误
          做有限次数指数退避重试；401/403/404 等语义错误直接失败记账。
        - HTTP 200 + success:false 若为限流载荷，同样走 429 退避重试。
        - 每次限流/可重试错误会通知限速器临时叠加等待；成功则逐步衰减，
          因此小账号快速场景不受影响，大批量限流场景自动变慢但不丢。
        """
        url = f"{self.BASE_URL}{endpoint}"
        last_error = ""

        for attempt in range(self._api_max_retries + 1):
            self._check_stop()
            if self._rate_limiter:
                self._rate_limiter.wait()
            proxy_url = self._proxy_pool.next_proxy() if self._proxy_pool else None
            proxies = {"http": proxy_url, "https": proxy_url} if proxy_url else None

            LOGGER.debug(
                "API request account=%s method=%s endpoint=%s attempt=%s params=%s proxy=%s",
                self.account_name,
                method,
                endpoint,
                attempt + 1,
                kwargs.get("params"),
                sanitize_proxy_url(proxy_url) if proxy_url else "-",
            )
            try:
                resp = self._get_session().request(
                    method, url, timeout=30, proxies=proxies, **kwargs
                )
                LOGGER.debug(
                    "API response account=%s method=%s endpoint=%s status=%s",
                    self.account_name,
                    method,
                    endpoint,
                    resp.status_code,
                )
            except requests.RequestException as exc:
                if self._proxy_pool and proxy_url:
                    self._proxy_pool.report_failure(proxy_url)
                if self._rate_limiter:
                    self._rate_limiter.note_rate_limited()
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

            status = resp.status_code
            if status in RETRYABLE_HTTP_STATUS:
                if self._rate_limiter:
                    self._rate_limiter.note_rate_limited()
                last_error = f"HTTP {status}: {resp.text[:300]}"
                if attempt >= self._api_max_retries:
                    raise Exception(last_error)

                delay = calc_retry_delay(
                    resp.headers,
                    attempt_index=attempt,
                    base_delay=self._api_retry_base_delay,
                    max_sleep=self._api_retry_max_sleep,
                )
                label = "触发 Cloudflare 限流" if status == 429 else "服务端临时错误"
                self._safe_print(
                    f"[RETRY] {method} {endpoint} {label} {status}，"
                    f"{delay:.1f}s 后重试 ({attempt + 1}/{self._api_max_retries})"
                )
                interruptible_sleep(delay, self._stop_event)
                continue

            try:
                data = resp.json()
            except ValueError as exc:
                # 可重试状态已在上一步处理；此处非 JSON 视为硬失败。
                raise Exception(
                    f"HTTP {status}: 返回非 JSON 内容: {resp.text[:300]}"
                ) from exc

            if not resp.ok or not data.get("success"):
                if is_rate_limit_api_payload(data):
                    if self._rate_limiter:
                        self._rate_limiter.note_rate_limited()
                    last_error = (
                        f"HTTP {status}, API 限流载荷: {data.get('errors', [])}"
                    )
                    if attempt >= self._api_max_retries:
                        raise Exception(last_error)
                    delay = calc_retry_delay(
                        resp.headers,
                        attempt_index=attempt,
                        base_delay=self._api_retry_base_delay,
                        max_sleep=self._api_retry_max_sleep,
                    )
                    self._safe_print(
                        f"[RETRY] {method} {endpoint} 限流载荷，"
                        f"{delay:.1f}s 后重试 ({attempt + 1}/{self._api_max_retries})"
                    )
                    interruptible_sleep(delay, self._stop_event)
                    continue
                raise Exception(
                    f"HTTP {status}, API 请求失败: {data.get('errors', [])}"
                )

            if self._rate_limiter:
                self._rate_limiter.note_success()
            if self._proxy_pool and proxy_url:
                self._proxy_pool.report_success(proxy_url)
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
            # 分页间隔走可中断 sleep；真正的请求节流由 ApiRateLimiter 承担。
            interruptible_sleep(0.2, self._stop_event)
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
            interruptible_sleep(0.1, self._stop_event)
        return records

    def _fetch_records_with_retry(
        self,
        zone_id: str,
        zone_name: str,
        record_type: Optional[str],
        stats: OperationStats,
        results: list[DNSOperationResult],
        action: str,
    ) -> Optional[list[dict]]:
        """读取单个 zone 的记录，失败时做一次补偿重试，仍失败则记账返回 None。

        避免“读失败 = 整个 zone 本次静默跳过”：最终失败会产生一条
        record_type=ZONE、status=error 的记账，供失败清单与重跑使用。
        """
        last_error = ""
        for attempt in range(1, ZONE_FETCH_MAX_ATTEMPTS + 1):
            try:
                return self.get_dns_records(zone_id, record_type)
            except KeyboardInterrupt:
                raise
            except Exception as exc:
                last_error = str(exc)
                if attempt < ZONE_FETCH_MAX_ATTEMPTS:
                    self._safe_print(
                        f"  [zone] {zone_name} 读取记录失败，第 {attempt} 次重试: {exc}"
                    )
                    interruptible_sleep(float(attempt), self._stop_event)
        self._safe_print(f"  [zone] {zone_name} 获取记录失败: {last_error}")
        stats.inc_errors()
        results.append(
            DNSOperationResult(
                zone=zone_name,
                name="",
                record_type="ZONE",
                old_content=None,
                new_content=None,
                status="error",
                message=f"{action} 读取记录失败: {last_error}",
                account=self.account_name,
                attempts=ZONE_FETCH_MAX_ATTEMPTS,
            )
        )
        return None

    def _mark_remaining_cancelled(
        self,
        results: list[DNSOperationResult],
        stats: OperationStats,
        zone_name: str,
        record_type_label: str,
        remaining: list[dict],
        action: str,
    ) -> None:
        """中断时把未处理的记录记为 cancelled，避免静默丢失。

        剩余条数较多时记一条聚合行，避免失败清单膨胀。
        """
        if not remaining:
            return
        stats.inc_cancelled(len(remaining))
        if len(remaining) > 50:
            results.append(
                DNSOperationResult(
                    zone=zone_name,
                    name=f"(剩余 {len(remaining)} 条记录未执行)",
                    record_type=record_type_label,
                    old_content=None,
                    new_content=None,
                    status="cancelled",
                    message=f"{action} 被中断",
                    account=self.account_name,
                )
            )
            return
        for record in remaining:
            results.append(
                DNSOperationResult(
                    zone=zone_name,
                    name=str(record.get("name", "")),
                    record_type=str(record.get("type", record_type_label)),
                    old_content=str(record.get("content", "")),
                    new_content=None,
                    status="cancelled",
                    message=f"{action} 被中断",
                    account=self.account_name,
                    record_id=str(record.get("id", "")),
                )
            )

    def _drain_zone_futures(
        self,
        future_to_zone: dict[Future[Any], dict],
        stats: OperationStats,
        all_results: list[DNSOperationResult],
        action: str,
    ) -> tuple[int, int]:
        """回收 zone fan-out 的 future，返回 (completed_zones, cancelled_zones)。

        - future 自身抛异常时记一条 zone 级 error，不吞掉整个 zone；
        - 中断时取消未开始的 future 并为每个未完成 zone 记 cancelled，
          保证 expected == completed + cancelled 可对账。
        - 进度回调：若实例属性 progress_cb 可调用，则以上报
          progress_cb(zone_name, state) 通知外部，state 为
          done/error/cancelled 之一；回调异常会被吞掉，不影响引擎。
        """
        notify = getattr(self, "progress_cb", None)
        if not callable(notify):
            notify = None

        def _report(zone_name: str, state: str) -> None:
            if notify is None:
                return
            try:
                notify(zone_name, state)
            except Exception:
                pass

        pending: set[Future[Any]] = set(future_to_zone)
        completed = 0
        cancelled = 0
        try:
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
                    zone_name = str(zone.get("name", "unknown"))
                    try:
                        all_results.extend(future.result())
                        completed += 1
                        _report(zone_name, "done")
                    except KeyboardInterrupt:
                        self._stop_event.set()
                        pending.add(future)
                        break
                    except Exception as exc:
                        completed += 1
                        self._safe_print(f"[zone-error] {zone_name}: {exc}")
                        stats.inc_errors()
                        all_results.append(
                            DNSOperationResult(
                                zone=zone_name,
                                name="",
                                record_type="ZONE",
                                old_content=None,
                                new_content=None,
                                status="error",
                                message=f"{action} zone 任务异常: {exc}",
                                account=self.account_name,
                            )
                        )
                        _report(zone_name, "error")
        except KeyboardInterrupt:
            self._stop_event.set()
            self._safe_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止当前账号任务...")
        if self._should_stop() and pending:
            cancel_pending_futures(pending)
            for future in pending:
                zone = future_to_zone.get(future, {})
                zone_name = str(zone.get("name", "unknown"))
                if not future.done() or future.cancelled():
                    cancelled += 1
                    stats.inc_cancelled()
                    all_results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name="",
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="cancelled",
                            message=f"{action} 未执行（任务被取消）",
                            account=self.account_name,
                        )
                    )
                    _report(zone_name, "cancelled")
                else:
                    try:
                        all_results.extend(future.result())
                        completed += 1
                        _report(zone_name, "done")
                    except Exception as exc:
                        completed += 1
                        stats.inc_errors()
                        all_results.append(
                            DNSOperationResult(
                                zone=zone_name,
                                name="",
                                record_type="ZONE",
                                old_content=None,
                                new_content=None,
                                status="error",
                                message=f"{action} zone 任务异常: {exc}",
                                account=self.account_name,
                            )
                        )
                        _report(zone_name, "error")
        return completed, cancelled

    def _report_zone(self, zone_name: str, state: str) -> None:
        """串行批量循环用的进度上报（与 _drain 内 _report 语义一致）。"""
        notify = getattr(self, "progress_cb", None)
        if not callable(notify):
            return
        try:
            notify(zone_name, state)
        except Exception:
            pass

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

    def create_dns_record(
        self,
        zone_id: str,
        record_name: str,
        content: str,
        proxied: bool,
        ttl: int,
        record_type: str,
    ) -> dict:
        """
        创建单条 DNS 记录。

        主要用于 IPv4 <-> IPv6 迁移：先创建目标类型记录，再删除旧类型记录，
        尽量降低迁移过程中的解析中断风险。
        """
        payload = {
            "type": record_type,
            "name": record_name,
            "content": content,
            "proxied": proxied,
            "ttl": ttl,
        }
        return self._request("POST", f"/zones/{zone_id}/dns_records", json=payload)

    def delete_dns_record(self, zone_id: str, record_id: str) -> dict:
        """删除单条 DNS 记录。调用前应确保已完成过滤与 dry-run 判断。"""
        return self._request("DELETE", f"/zones/{zone_id}/dns_records/{record_id}")

    def delete_zone(self, zone_id: str) -> dict:
        """删除整个 zone（域名）。此操作不可逆，请谨慎使用。"""
        return self._request("DELETE", f"/zones/{zone_id}")

    def get_account_id(self) -> Optional[str]:
        """解析当前凭证可访问的账号 ID(取第一个),结果缓存。

        部分接口(创建 zone、邮箱转发)需要 account id。若凭证无权访问
        /accounts(例如仅 zone 级权限),返回 None 而不是抛错,由调用方决定降级行为。
        """
        if self._account_id_loaded:
            return self._account_id
        self._account_id_loaded = True
        try:
            data = self._request("GET", "/accounts", params={"page": 1, "per_page": 50})
        except Exception as exc:  # noqa: BLE001 - 无权限时降级为 None
            self._safe_print(f"  [WARN] 获取账号 ID 失败,将不带 account 继续: {exc}")
            self._account_id = None
            return None
        for account in data.get("result", []):
            if not isinstance(account, dict):
                continue
            account_id = account.get("id")
            if account_id:
                self._account_id = account_id
                return account_id
        self._account_id = None
        return None

    def create_zone(
        self, domain: str, account_id: Optional[str] = None, zone_type: str = "full"
    ) -> dict:
        """在当前账号下添加新域名(zone)。

        优先带上 account id(创建 zone 的推荐写法);拿不到 account id 时保持旧行为。
        """
        payload: dict[str, Any] = {"name": domain, "type": zone_type}
        resolved_account = account_id or self.get_account_id()
        if resolved_account:
            payload["account"] = {"id": resolved_account}
        return self._request("POST", "/zones", json=payload)

    def get_zone_by_name(self, domain: str) -> Optional[dict]:
        """按域名查询 zone 详情;不存在返回 None。"""
        target = (get_main_domain_name_from_str(domain) or domain.strip()).lower()
        data = self._request(
            "GET", "/zones", params={"name": target, "page": 1, "per_page": 1}
        )
        for zone in data.get("result", []):
            if zone.get("name", "").lower() == target:
                return zone
        return None

    def get_zone(self, zone_id: str) -> dict:
        """读取单个 zone 详情。"""
        return self._request("GET", f"/zones/{zone_id}")

    def trigger_activation_check(self, zone_id: str) -> dict:
        """触发一次 zone 激活检查（催激活），仅对 pending/moved zone 有意义。

        对应 `PUT /zones/{zone_id}/activation_check`。成功仅表示已进入 Cloudflare
        的优先重查队列，**不等于立即激活**（通常数分钟到数小时，取决于 NS 是否已生效）。
        """
        return self._request("PUT", f"/zones/{zone_id}/activation_check")

    def wait_zone_active(
        self,
        zone_id: str,
        timeout: float = 300.0,
        interval: float = 5.0,
        on_tick: Optional[Callable[[str, float], None]] = None,
    ) -> tuple[bool, str]:
        """轮询 zone 状态直到 active 或超时。

        Returns:
            (是否已激活, 最后一次观察到的状态)
        """
        deadline = time.monotonic() + max(0.0, timeout)
        last_status = ""
        while True:
            self._check_stop()
            try:
                zone = self.get_zone(zone_id)
                last_status = str((zone.get("result") or {}).get("status") or "")
            except Exception as exc:  # noqa: BLE001 - 轮询期间的临时错误继续重试
                last_status = f"error: {exc}"
            if last_status == "active":
                return True, last_status
            remaining = deadline - time.monotonic()
            if on_tick:
                on_tick(last_status, max(0.0, remaining))
            if remaining <= 0:
                return False, last_status
            interruptible_sleep(min(interval, remaining), self._stop_event)

    def add_dns_record(
        self,
        zone_id: str,
        record_name: str,
        content: str,
        record_type: str,
        proxied: bool = False,
        ttl: int = 1,
        priority: Optional[int] = None,
    ) -> dict:
        """添加单条 DNS 记录。"""
        payload: dict[str, Any] = {
            "type": record_type,
            "name": record_name,
            "content": content,
            "proxied": proxied,
            "ttl": ttl,
        }
        if priority is not None:
            payload["priority"] = priority
        return self._request("POST", f"/zones/{zone_id}/dns_records", json=payload)

    def ensure_dns_record(
        self,
        zone_id: str,
        zone_name: str,
        record_name: str,
        record_type: str,
        content: str,
        proxied: bool = False,
        ttl: int = 1,
        priority: Optional[int] = None,
        allow_multi: bool = False,
        _records_cache: Optional[dict] = None,
    ) -> tuple[str, str]:
        """幂等地确保某条 DNS 记录存在，并避免同名劈叉。

        语义：

        - A/AAAA/CNAME 默认视为「同名单值」：同名同类型已有记录时，内容一致则跳过，
          不一致则覆盖（PUT）；并删除同名同类型的多余记录。
        - 指定 allow_multi=True 时，A/AAAA 改为允许多值（同名可指向多个 IP）：
          存在完全相同的记录则跳过，否则追加，不覆盖、不去重。
        - CNAME 与其它类型互斥：新增 CNAME 会清理同名其它记录；新增 A/AAAA 会清理同名 CNAME。
          CNAME 始终为单值（DNS 规则不允许同名多 CNAME）。
        - 其它类型（TXT/MX 等）本就走多值逻辑：仅当存在完全相同的记录时跳过，否则新增。
        - _records_cache：可选的同 zone 记录缓存（调用方每 zone 一个 dict），命中则跳过
          LIST 查询；函数内在增/删后同步维护缓存（改走失效重查）。跨 zone/跨线程不得共用。

        Returns:
            (状态, 说明)；状态取值 added/updated/unchanged/error。
        """
        normalized_type = (record_type or "").upper()
        # allow_multi 仅放宽 A/AAAA；CNAME 因 DNS 规则始终单值。
        if allow_multi and normalized_type in {"A", "AAAA"}:
            single_value = False
        else:
            single_value = normalized_type in {"A", "AAAA", "CNAME"}
        if record_name in ("", "@"):
            fqdn = zone_name.lower()
        elif record_name.endswith(zone_name.lower()):
            fqdn = record_name.lower()
        else:
            fqdn = f"{record_name}.{zone_name}".lower()

        cache = _records_cache

        def _fetch(rtype):
            key = rtype or "ALL"
            if cache is not None and key in cache:
                return cache[key]
            records = self.get_dns_records(zone_id, record_type=rtype)
            if cache is not None:
                cache[key] = records
            return records

        def _cache_forget(record_id):
            """删除成功后把该记录从缓存各表中摘除（精确，剩余条目依然有效）。"""
            if cache is None or not record_id:
                return
            rid = str(record_id)
            for records in cache.values():
                if isinstance(records, list):
                    records[:] = [r for r in records if str(r.get("id", "")) != rid]

        def _cache_invalidate():
            """覆盖成功后使相关表失效，下次重查（改是低频路径，简单且正确）。"""
            if cache is None:
                return
            cache.pop(normalized_type, None)
            cache.pop("ALL", None)

        def _cache_append(record):
            """新增成功后把返回的记录并入缓存（服务端已规范化为 FQDN，可直接用于后继比对）。"""
            if cache is None or not isinstance(record, dict):
                return
            rid = str(record.get("id", ""))
            for key in {normalized_type, "ALL"}:
                records = cache.get(key)
                if isinstance(records, list):
                    cache[key] = [r for r in records if str(r.get("id", "")) != rid]
                    cache[key].append(record)

        try:
            same_type = _fetch(normalized_type)
            conflicts: list[dict] = []
            if normalized_type == "CNAME":
                all_records = _fetch(None)
                conflicts = [
                    r
                    for r in all_records
                    if str(r.get("name", "")).lower() == fqdn
                    and str(r.get("type", "")).upper() != "CNAME"
                ]
            elif normalized_type in {"A", "AAAA"}:
                cname_records = _fetch("CNAME")
                conflicts = [
                    r for r in cname_records if str(r.get("name", "")).lower() == fqdn
                ]
        except Exception as exc:  # noqa: BLE001
            return "error", f"读取现有记录失败: {exc}"

        matches = [
            r
            for r in same_type
            if str(r.get("name", "")).lower() == fqdn
            and str(r.get("type", "")).upper() == normalized_type
        ]

        payload: dict[str, Any] = {
            "type": normalized_type,
            "name": record_name,
            "content": content,
            "proxied": proxied,
            "ttl": ttl,
        }
        if priority is not None:
            payload["priority"] = priority

        def _identical(record: dict) -> bool:
            return (
                str(record.get("content", "")) == str(content)
                and bool(record.get("proxied", False)) == bool(proxied)
                and int(record.get("ttl", 1) or 1) == int(ttl)
                and (
                    priority is None
                    or int(record.get("priority", 0) or 0) == int(priority)
                )
            )

        # 1) 清理冲突记录（CNAME 与其它类型互斥）
        cleaned = 0
        for conflict in conflicts:
            conflict_id = conflict.get("id")
            if not conflict_id:
                continue
            try:
                self.delete_dns_record(zone_id, str(conflict_id))
                _cache_forget(conflict_id)
                cleaned += 1
            except Exception as exc:  # noqa: BLE001
                return "error", f"清理冲突记录失败: {exc}"

        # 2) 多值记录（TXT/MX，或 allow_multi 的 A/AAAA）：存在完全相同则跳过，否则新增
        if not single_value:
            if any(_identical(record) for record in matches):
                return "unchanged", "记录已存在且一致"
            try:
                created = self.add_dns_record(
                    zone_id,
                    record_name,
                    content,
                    normalized_type,
                    proxied=proxied,
                    ttl=ttl,
                    priority=priority,
                )
                _cache_append((created or {}).get("result"))
            except Exception as exc:  # noqa: BLE001
                return "error", f"新增记录失败: {exc}"
            if cleaned:
                return "added", f"已新增记录；清理冲突 {cleaned} 条"
            return "added", "已新增记录"

        # 3) 同名单值类型：覆盖 + 去重
        if matches:
            primary = matches[0]
            identical = _identical(primary)
            if not identical:
                try:
                    self._request(
                        "PUT",
                        f"/zones/{zone_id}/dns_records/{primary.get('id')}",
                        json=payload,
                    )
                    _cache_invalidate()
                except Exception as exc:  # noqa: BLE001
                    return "error", f"更新记录失败: {exc}"
            removed = 0
            for extra in matches[1:]:
                extra_id = extra.get("id")
                if not extra_id:
                    continue
                try:
                    self.delete_dns_record(zone_id, str(extra_id))
                    _cache_forget(extra_id)
                    removed += 1
                except Exception as exc:  # noqa: BLE001
                    return "error", f"删除重复记录失败: {exc}"
            if identical and cleaned == 0 and removed == 0:
                return "unchanged", "记录已存在且一致"
            notes: list[str] = []
            if not identical:
                notes.append("已覆盖为指定内容")
            if removed:
                notes.append(f"删除重复 {removed} 条")
            if cleaned:
                notes.append(f"清理冲突 {cleaned} 条")
            return "updated", "；".join(notes) or "已更新"

        try:
            created = self.add_dns_record(
                zone_id,
                record_name,
                content,
                normalized_type,
                proxied=proxied,
                ttl=ttl,
                priority=priority,
            )
            _cache_append((created or {}).get("result"))
        except Exception as exc:  # noqa: BLE001
            return "error", f"新增记录失败: {exc}"
        if cleaned:
            return "added", f"已新增记录；清理冲突 {cleaned} 条"
        return "added", "已新增记录"

    def update_zone_setting(self, zone_id: str, setting_id: str, value: Any) -> dict:
        """更新单个 zone 设置(如 ssl、speed_brain、always_use_https)。"""
        return self._request(
            "PATCH", f"/zones/{zone_id}/settings/{setting_id}", json={"value": value}
        )

    def list_email_routing_addresses(
        self, account_id: Optional[str] = None
    ) -> list[dict]:
        """列出账号下已配置的邮箱转发目标地址。"""
        aid = account_id or self.get_account_id()
        if not aid:
            raise Exception("无法获取账号 ID,不能管理邮箱转发地址")
        data = self._request(
            "GET",
            f"/accounts/{aid}/email/routing/addresses",
            params={"page": 1, "per_page": 50},
        )
        return data.get("result", [])

    def create_email_routing_address(
        self, email: str, account_id: Optional[str] = None
    ) -> dict:
        """创建邮箱转发目标地址(需要收件人点击验证邮件后才会 verified)。"""
        aid = account_id or self.get_account_id()
        if not aid:
            raise Exception("无法获取账号 ID,不能创建邮箱转发地址")
        return self._request(
            "POST",
            f"/accounts/{aid}/email/routing/addresses",
            json={"email": email},
        )

    def ensure_email_routing_address(
        self, email: str, account_id: Optional[str] = None
    ) -> tuple[bool, str]:
        """确保目标邮箱存在,返回 (是否已验证, 状态)。

        状态: verified / unverified / created_pending_verification。
        """
        target = (email or "").strip().lower()
        if not target:
            return False, "empty"
        for address in self.list_email_routing_addresses(account_id):
            # API 在不同账号/版本下可能返回字符串列表或对象列表，二者均兼容；
            # 字符串元素无法确认验证状态，一律按未验证处理（只配路由、不设 catch-all）。
            if isinstance(address, str):
                addr_email, addr_verified = address, False
            elif isinstance(address, dict):
                addr_email = str(address.get("email", ""))
                addr_verified = bool(address.get("verified"))
            else:
                continue
            if addr_email.strip().lower() == target:
                return addr_verified, "verified" if addr_verified else "unverified"
        self.create_email_routing_address(target, account_id)
        return False, "created_pending_verification"

    def get_email_routing_settings(self, zone_id: str) -> dict:
        """读取 zone 的邮箱路由设置（是否已启用等）。

        对应 `GET /zones/{zone_id}/email/routing`，返回 settings 对象；
        形状异常时返回空 dict（调用方按“未启用”继续走启用流程）。
        """
        try:
            data = self._request("GET", f"/zones/{zone_id}/email/routing")
        except Exception:
            return {}
        result = (data or {}).get("result", {})
        return result if isinstance(result, dict) else {}

    def get_email_routing_required_records(self, zone_id: str) -> list[dict]:
        """获取启用邮箱路由所需的 DNS 记录(MX/SPF/DKIM)。

        对应 `GET /zones/{zone_id}/email/routing/dns`，返回 DNSRecord 数组
        （`{type, name, content, priority, ttl}`）。注意：`POST` 同路径是
        “启用路由”端点（返回 settings 对象），不可用于取记录。
        """
        data = self._request("GET", f"/zones/{zone_id}/email/routing/dns")
        return data.get("result", [])

    def enable_email_routing(self, zone_id: str) -> dict:
        """启用 zone 的邮箱路由（新版规范端点；旧 `POST .../enable` 已废弃）。

        对应 `POST /zones/{zone_id}/email/routing/dns`，返回 settings 对象。
        同 pending zone 会 403（Active zone required），调用前须确认已激活。
        """
        return self._request("POST", f"/zones/{zone_id}/email/routing/dns")

    def update_email_routing_catch_all(self, zone_id: str, forward_email: str) -> dict:
        """设置 catch-all 规则,把所有收件转发到指定邮箱。"""
        payload = {
            "name": f"catch-all-{zone_id}",
            "enabled": True,
            "matchers": [{"type": "all"}],
            "actions": [{"type": "forward", "value": [forward_email]}],
        }
        return self._request(
            "PUT", f"/zones/{zone_id}/email/routing/rules/catch_all", json=payload
        )

    def apply_zone_settings(
        self, zone_id: str, settings: Mapping[str, Any]
    ) -> list[tuple[str, str, str]]:
        """批量应用 zone 设置,逐项容错。

        Returns:
            [(setting_id, status, message)];status 为 ok/error。
        """
        results: list[tuple[str, str, str]] = []
        for setting_id, value in settings.items():
            try:
                self.update_zone_setting(zone_id, setting_id, value)
                results.append((setting_id, "ok", ""))
            except Exception as exc:  # noqa: BLE001 - 单项失败不影响其它设置
                results.append((setting_id, "error", str(exc)))
        return results

    def configure_email_routing(
        self,
        zone_id: str,
        zone_name: str,
        forward_email: str,
        catch_all: bool = True,
    ) -> tuple[str, str, list[str]]:
        """完整配置邮箱路由:补齐所需 DNS、启用路由、设置 catch-all。

        Returns:
            (status, message, records_status)
            status: ok / pending_verification / error
        """
        verified, addr_status = self.ensure_email_routing_address(forward_email)
        records_status: list[str] = []
        try:
            required = self.get_email_routing_required_records(zone_id)
        except Exception as exc:  # noqa: BLE001
            return "error", f"获取邮箱路由所需记录失败: {exc}", records_status

        # 不同账号/版本下 result 可能是对象数组，也可能包一层 dict；
        # 先归一化，归一化失败则报明错（带实际形状），不再以 AttributeError 裸崩。
        normalized: Optional[list] = None
        if isinstance(required, list):
            normalized = required
        elif isinstance(required, dict):
            for key in ("records", "result", "items", "data"):
                if isinstance(required.get(key), list):
                    normalized = required[key]
                    break
        if normalized is None or any(
            not isinstance(record, dict) for record in normalized
        ):
            preview = str(required)[:200]
            return (
                "error",
                f"邮箱路由所需记录格式异常: {type(required).__name__}:{preview}",
                records_status,
            )
        required = normalized

        for record in required:
            name = str(record.get("name", ""))
            record_type = str(record.get("type", ""))
            content = str(record.get("content", ""))
            priority = record.get("priority")
            status, msg = self.ensure_dns_record(
                zone_id,
                zone_name,
                name,
                record_type,
                content,
                proxied=bool(record.get("proxied", False)),
                ttl=int(record.get("ttl", 1) or 1),
                priority=int(priority) if priority is not None else None,
            )
            detail = f"（{msg}）" if msg else ""
            records_status.append(f"{record_type} {name}: {status}{detail}")

        # 已启用则跳过启用调用（幂等）；settings 查不到时按未启用继续走启用流程。
        if not self.get_email_routing_settings(zone_id).get("enabled"):
            try:
                self.enable_email_routing(zone_id)
            except Exception as exc:  # noqa: BLE001
                return "error", f"启用邮箱路由失败: {exc}", records_status

        if not catch_all:
            return "ok", "邮箱路由已启用(未设置 catch-all)", records_status
        if not verified:
            return (
                "pending_verification",
                f"目标邮箱 {forward_email} 未验证({addr_status}),"
                "已启用路由但暂不设置 catch-all,请先完成邮箱验证",
                records_status,
            )
        try:
            self.update_email_routing_catch_all(zone_id, forward_email)
        except Exception as exc:  # noqa: BLE001
            return "error", f"设置 catch-all 失败: {exc}", records_status
        return "ok", f"邮箱转发已配置到 {forward_email}", records_status

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
            records = self._fetch_records_with_retry(
                zone_id, zone_name, record_type, stats, results, action="更新"
            )
        except KeyboardInterrupt:
            return results
        if records is None:
            return results

        if not records:
            self._safe_print(f"  [zone] {zone_name} 未找到 {record_type} 记录,跳过处理")
            return results

        for index, record in enumerate(records):
            if self._should_stop():
                self._mark_remaining_cancelled(
                    results,
                    stats,
                    zone_name,
                    record_type,
                    records[index:],
                    action="更新",
                )
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

            # 如果指定了 old-content/old-ip，则只更新内容归一化后匹配的记录
            # （兼容 IPv6 多种写法与 CNAME 尾点/大小写差异）。
            if old_content and not contents_equal(r_content, old_content):
                stats.inc_skipped()
                continue

            # 新旧内容一致，无需重复更新（幂等：重跑已完成项自动跳过）。
            if contents_equal(r_content, new_content):
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
                        account=self.account_name,
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
                        account=self.account_name,
                    )
                )
                interruptible_sleep(0.1, self._stop_event)
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
                        account=self.account_name,
                    )
                )

        return results

    def _process_zone_full_replace(
        self,
        zone: dict,
        zone_index: int,
        selected_zone_total: int,
        account_zone_total: int,
        new_content: str,
        record_type: str,
        opposite_record_type: str | None,
        dry_run: bool,
        include_subdomains: bool,
        whitelist_active: bool,
        stats: "OperationStats",
    ) -> list["DNSOperationResult"]:
        """未指定 --old-ip 时的全量替换处理：处理当前类型 + 对立类型记录。

        以 record id 为单位处理，同一主机名下多条同类型记录都会被处理；
        创建去重依靠 existing_targets（同名同内容），删除按 id 逐条执行。
        """
        zone_name = zone["name"]
        zone_id = zone["id"]
        results: list["DNSOperationResult"] = []

        action_desc = f"全量替换->{record_type}"
        if opposite_record_type:
            action_desc += f"/{opposite_record_type}"

        self._safe_print(
            self._progress_prefix(
                zone_name,
                zone_index,
                selected_zone_total,
                account_zone_total,
                action_name=action_desc,
            )
        )

        try:
            target_records = self._fetch_records_with_retry(
                zone_id, zone_name, record_type, stats, results, action="全量替换"
            )
            if target_records is None:
                return results
            opposite_records: list[dict] = []
            if opposite_record_type:
                fetched = self._fetch_records_with_retry(
                    zone_id,
                    zone_name,
                    opposite_record_type,
                    stats,
                    results,
                    action="全量替换",
                )
                if fetched is None:
                    return results
                opposite_records = fetched
        except KeyboardInterrupt:
            return results

        # 已存在的目标（同名 + 归一化内容），用于避免重复创建。
        existing_targets = {
            (
                str(record.get("name", "")).lower(),
                normalize_content_for_compare(record.get("content", "")),
            )
            for record in target_records
        }
        normalized_new = normalize_content_for_compare(new_content)
        handled = 0

        # ========== 1. 处理当前类型记录（同类型更新，逐 id） ==========
        for index, record in enumerate(target_records):
            if self._should_stop():
                self._mark_remaining_cancelled(
                    results,
                    stats,
                    zone_name,
                    record_type,
                    target_records[index:],
                    action="全量替换",
                )
                return results

            r_name = record.get("name", "")
            r_content = record.get("content", "")
            r_id = record.get("id", "")
            r_proxied = bool(record.get("proxied", False))
            r_ttl = int(record.get("ttl", 1) or 1)
            r_type = record.get("type", record_type)

            if (
                whitelist_active
                and not include_subdomains
                and r_name.lower() != zone_name.lower()
            ):
                continue

            handled += 1
            if contents_equal(r_content, new_content):
                stats.inc_skipped()
                continue

            if dry_run:
                self._safe_print(
                    f"  [DRY-FULL] {r_type} {r_name}: {r_content} -> {new_content}"
                )
                stats.inc_dry_run()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=new_content,
                        status="dry_run_full_update",
                        account=self.account_name,
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
                existing_targets.add((r_name.lower(), normalized_new))
                self._safe_print(
                    f"  [OK-FULL] {r_type} {r_name}: {r_content} -> {new_content}"
                )
                stats.inc_updated()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=new_content,
                        status="updated_full",
                        account=self.account_name,
                    )
                )
                interruptible_sleep(0.08, self._stop_event)
            except Exception as exc:
                self._safe_print(f"  [ERR-FULL] {r_type} {r_name}: {exc}")
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
                        account=self.account_name,
                    )
                )

        # ========== 2. 处理对立类型记录（跨类型迁移，逐 id 删除） ==========
        if opposite_record_type and opposite_records:
            self._safe_print(
                f"  [INFO] 检测到 {len(opposite_records)} 条 {opposite_record_type} 记录，执行跨类型迁移..."
            )

            for index, record in enumerate(opposite_records):
                if self._should_stop():
                    self._mark_remaining_cancelled(
                        results,
                        stats,
                        zone_name,
                        opposite_record_type,
                        opposite_records[index:],
                        action="全量替换迁移",
                    )
                    return results

                r_name = record.get("name", "")
                r_content = record.get("content", "")
                r_id = record.get("id", "")
                r_proxied = bool(record.get("proxied", False))
                r_ttl = int(record.get("ttl", 1) or 1)

                if (
                    whitelist_active
                    and not include_subdomains
                    and r_name.lower() != zone_name.lower()
                ):
                    continue

                handled += 1
                target_exists = (r_name.lower(), normalized_new) in existing_targets

                if dry_run:
                    self._safe_print(
                        f"  [DRY-FULL-MIGRATE] {opposite_record_type} {r_name}: {r_content} -> "
                        f"{record_type} {new_content} ({'已存在' if target_exists else '创建+删除旧记录'})"
                    )
                    stats.inc_dry_run()
                    results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name=r_name,
                            record_type=f"{opposite_record_type}->{record_type}",
                            old_content=r_content,
                            new_content=new_content,
                            status="dry_run_full_migrate",
                            account=self.account_name,
                        )
                    )
                    continue

                if not target_exists:
                    try:
                        self.create_dns_record(
                            zone_id=zone_id,
                            record_name=r_name,
                            content=new_content,
                            proxied=r_proxied,
                            ttl=r_ttl,
                            record_type=record_type,
                        )
                        existing_targets.add((r_name.lower(), normalized_new))
                        stats.inc_created()
                        self._safe_print(
                            f"  [CREATE-FULL] {record_type} {r_name}: {new_content}"
                        )
                        interruptible_sleep(0.08, self._stop_event)
                    except Exception as exc:
                        self._safe_print(
                            f"  [ERR-FULL-CREATE] {record_type} {r_name}: {exc}"
                        )
                        stats.inc_errors()
                        results.append(
                            DNSOperationResult(
                                zone=zone_name,
                                name=r_name,
                                record_type=record_type,
                                old_content=r_content,
                                new_content=new_content,
                                status="error",
                                message=str(exc),
                                account=self.account_name,
                            )
                        )
                        continue

                # 删除旧记录（逐 id；失败记半迁移状态，便于重跑清理）。
                try:
                    self.delete_dns_record(zone_id, r_id)
                    stats.inc_deleted()
                    self._safe_print(
                        f"  [DEL-OLD-FULL] {opposite_record_type} {r_name}: {r_content}"
                    )
                    results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name=r_name,
                            record_type=opposite_record_type,
                            old_content=r_content,
                            new_content=None,
                            status="deleted_old_full_migrate",
                            account=self.account_name,
                        )
                    )
                    interruptible_sleep(0.08, self._stop_event)
                except Exception as exc:
                    self._safe_print(
                        f"  [ERR-FULL-DEL] 删除旧 {opposite_record_type} {r_name}: {exc}"
                    )
                    stats.inc_errors()
                    results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name=r_name,
                            record_type=opposite_record_type,
                            old_content=r_content,
                            new_content=None,
                            status="error_delete_old_after_migrate",
                            message=str(exc),
                            account=self.account_name,
                        )
                    )

        if handled == 0:
            self._safe_print(f"  [zone] {zone_name} 未找到任何 A/AAAA 记录需要处理")

        return results

    def _process_zone_migrate_ip_family(
        self,
        zone: dict,
        zone_index: int,
        selected_zone_total: int,
        account_zone_total: int,
        old_content: str,
        new_content: str,
        old_record_type: str,
        new_record_type: str,
        dry_run: bool,
        include_subdomains: bool,
        whitelist_active: bool,
        stats: OperationStats,
    ) -> list[DNSOperationResult]:
        """处理单个 zone 的 IPv4 <-> IPv6 跨类型迁移。"""
        zone_name = zone["name"]
        zone_id = zone["id"]
        results: list[DNSOperationResult] = []

        self._safe_print(
            self._progress_prefix(
                zone_name,
                zone_index,
                selected_zone_total,
                account_zone_total,
                action_name=f"迁移 {old_record_type}->{new_record_type}",
            )
        )

        try:
            old_records = self._fetch_records_with_retry(
                zone_id, zone_name, old_record_type, stats, results, action="迁移"
            )
            if old_records is None:
                return results
            target_records = self._fetch_records_with_retry(
                zone_id, zone_name, new_record_type, stats, results, action="迁移"
            )
            if target_records is None:
                return results
        except KeyboardInterrupt:
            return results

        existing_targets = {
            (
                str(record.get("name", "")).lower(),
                normalize_content_for_compare(record.get("content", "")),
            )
            for record in target_records
        }
        normalized_new = normalize_content_for_compare(new_content)
        matched = 0

        for index, record in enumerate(old_records):
            if self._should_stop():
                self._mark_remaining_cancelled(
                    results,
                    stats,
                    zone_name,
                    old_record_type,
                    old_records[index:],
                    action="迁移",
                )
                return results

            r_name = record.get("name", "")
            r_content = record.get("content", "")
            r_id = record.get("id", "")
            r_proxied = bool(record.get("proxied", False))
            r_ttl = int(record.get("ttl", 1) or 1)

            if (
                whitelist_active
                and not include_subdomains
                and r_name.lower() != zone_name.lower()
            ):
                continue

            if not contents_equal(r_content, old_content):
                stats.inc_skipped()
                continue

            matched += 1
            target_exists = (r_name.lower(), normalized_new) in existing_targets
            create_text = "目标记录已存在" if target_exists else "创建目标记录"

            if dry_run:
                self._safe_print(
                    f"  [DRY-MIGRATE] {old_record_type} {r_name}: {old_content} -> "
                    f"{new_record_type} {new_content} ({create_text}; 删除旧记录)"
                )
                stats.inc_dry_run()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=f"{old_record_type}->{new_record_type}",
                        old_content=old_content,
                        new_content=new_content,
                        status="dry_run_migrate",
                        account=self.account_name,
                    )
                )
                continue

            if not target_exists:
                try:
                    self.create_dns_record(
                        zone_id=zone_id,
                        record_name=r_name,
                        content=new_content,
                        proxied=r_proxied,
                        ttl=r_ttl,
                        record_type=new_record_type,
                    )
                    existing_targets.add((r_name.lower(), normalized_new))
                    stats.inc_created()
                    self._safe_print(
                        f"  [CREATE] {new_record_type} {r_name}: {new_content}"
                    )
                    results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name=r_name,
                            record_type=new_record_type,
                            old_content="",
                            new_content=new_content,
                            status="created",
                            account=self.account_name,
                        )
                    )
                    interruptible_sleep(0.1, self._stop_event)
                except Exception as exc:
                    self._safe_print(
                        f"  [ERR] 创建 {new_record_type} {r_name}: {exc}; 已保留旧记录"
                    )
                    stats.inc_errors()
                    results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name=r_name,
                            record_type=new_record_type,
                            old_content=old_content,
                            new_content=new_content,
                            status="error",
                            message=str(exc),
                            account=self.account_name,
                        )
                    )
                    continue
            else:
                stats.inc_skipped()
                self._safe_print(
                    f"  [SKIP-CREATE] {new_record_type} {r_name}: {new_content} 已存在"
                )

            try:
                self.delete_dns_record(zone_id, r_id)
                stats.inc_deleted()
                self._safe_print(
                    f"  [DEL-OLD] {old_record_type} {r_name}: {old_content}"
                )
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=old_record_type,
                        old_content=old_content,
                        new_content=None,
                        status="deleted_old_after_migrate",
                        account=self.account_name,
                    )
                )
                interruptible_sleep(0.1, self._stop_event)
            except Exception as exc:
                self._safe_print(
                    f"  [ERR] 删除旧记录失败 {old_record_type} {r_name}: {exc}"
                )
                stats.inc_errors()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=old_record_type,
                        old_content=old_content,
                        new_content=None,
                        status="error_delete_old_after_migrate",
                        message=str(exc),
                        account=self.account_name,
                    )
                )

        if matched == 0:
            self._safe_print(f"  [zone] 未找到 {old_record_type} {old_content} 记录")

        return results

    def _process_zone_delete_ip(
        self,
        zone: dict,
        zone_index: int,
        selected_zone_total: int,
        account_zone_total: int,
        delete_ip: str,
        record_type: str,
        dry_run: bool,
        include_subdomains: bool,
        whitelist_active: bool,
        stats: OperationStats,
    ) -> list[DNSOperationResult]:
        """处理单个 zone 中所有指向指定 IP 的 A/AAAA 记录删除。"""
        zone_name = zone["name"]
        zone_id = zone["id"]
        results: list[DNSOperationResult] = []

        self._safe_print(
            self._progress_prefix(
                zone_name,
                zone_index,
                selected_zone_total,
                account_zone_total,
                action_name=f"删除指向 IP 的记录(type={record_type})",
            )
        )

        try:
            records = self._fetch_records_with_retry(
                zone_id, zone_name, record_type, stats, results, action="删除指定 IP"
            )
        except KeyboardInterrupt:
            return results
        if records is None:
            return results

        matched = 0
        for index, record in enumerate(records):
            if self._should_stop():
                self._mark_remaining_cancelled(
                    results,
                    stats,
                    zone_name,
                    record_type,
                    records[index:],
                    action="删除指定 IP",
                )
                return results

            r_name = record.get("name", "")
            r_content = record.get("content", "")
            r_id = record.get("id", "")
            r_type = record.get("type", record_type)

            if (
                whitelist_active
                and not include_subdomains
                and r_name.lower() != zone_name.lower()
            ):
                continue

            if not contents_equal(r_content, delete_ip):
                stats.inc_skipped()
                continue

            matched += 1
            if dry_run:
                self._safe_print(f"  [DRY-DELETE-IP] {r_type} {r_name}: {r_content}")
                stats.inc_dry_run()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=None,
                        status="dry_run_delete_ip",
                        account=self.account_name,
                    )
                )
                continue

            try:
                self.delete_dns_record(zone_id, r_id)
                self._safe_print(f"  [DEL-IP] {r_type} {r_name}: {r_content}")
                stats.inc_deleted()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=None,
                        status="deleted_ip",
                        account=self.account_name,
                    )
                )
                interruptible_sleep(0.1, self._stop_event)
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
                        account=self.account_name,
                    )
                )

        if matched == 0:
            self._safe_print(f"  [zone] 未找到指向 {delete_ip} 的 {record_type} 记录")

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
            records = self._fetch_records_with_retry(
                zone_id,
                zone_name,
                None if record_type == "ALL" else record_type,
                stats,
                results,
                action="删除通配符",
            )
        except KeyboardInterrupt:
            return results
        if records is None:
            return results

        matched = 0
        for index, record in enumerate(records):
            if self._should_stop():
                self._mark_remaining_cancelled(
                    results,
                    stats,
                    zone_name,
                    record_type,
                    records[index:],
                    action="删除通配符",
                )
                return results

            r_name = record.get("name", "")
            if not is_wildcard_record_name(r_name):
                continue

            r_content = record.get("content", "")
            r_id = record.get("id", "")
            r_type = record.get("type", "")
            matched += 1

            # 删除模式下也复用 --old-content/--old-ip 作为内容过滤器，便于只删除指向旧地址的通配符记录。
            if old_content and not contents_equal(r_content, old_content):
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
                        account=self.account_name,
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
                        account=self.account_name,
                    )
                )
                interruptible_sleep(0.1, self._stop_event)
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
                        account=self.account_name,
                    )
                )

        if matched == 0:
            self._safe_print("  [zone] 未发现以 * 开头的记录")

        return results

    def _filter_zones(
        self,
        all_zones: list[dict],
        whitelist: Optional[list[str]] = None,
        explicit_domains: Optional[list[str]] = None,
    ) -> tuple[list[dict], Optional[set[str]]]:
        """
        按白名单或显式域名过滤 zone。

        支持两种模式：
        - whitelist：文件白名单模式
        - explicit_domains：命令行直接指定的域名（--domain）

        同时提供两者时取交集。
        """
        if not whitelist and not explicit_domains:
            return all_zones, None

        whitelist_set = set()
        if whitelist:
            whitelist_set = {d.lower().strip() for d in whitelist if d and d.strip()}

        explicit_set = set()
        if explicit_domains:
            explicit_set = {
                d.lower().strip() for d in explicit_domains if d and d.strip()
            }

        # 同时指定时取交集，否则使用任一集合
        if whitelist_set and explicit_set:
            target_set = whitelist_set & explicit_set
            mode_desc = "白名单+指定域名交集"
        elif whitelist_set:
            target_set = whitelist_set
            mode_desc = "白名单"
        else:
            target_set = explicit_set
            mode_desc = "命令行指定域名"

        if not target_set:
            self._safe_print(f"[{mode_desc}] 没有匹配的域名")
            return [], None

        zones = [z for z in all_zones if z.get("name", "").lower() in target_set]
        self._safe_print(
            f"[{mode_desc}] 目标域名数: {len(target_set)}, "
            f"匹配到账号内域名: {len(zones)}"
        )
        return zones, target_set if target_set else None

    def _apply_resume_filter(
        self, zones: list[dict], resume_zones: Optional[set[str]]
    ) -> list[dict]:
        """按 --resume-from 失败清单过滤 zone（zone 级重跑）。

        已完成的记录天然幂等（内容一致自动跳过），因此重跑整个失败 zone
        即可补齐失败/取消项，无需记录级精确定位。

        resume_zones 为 None 表示无重跑文件（不过滤）；空集合表示本账号
        在清单中无待重跑域名（全部跳过）。
        """
        if resume_zones is None:
            return zones
        kept = [
            zone for zone in zones if str(zone.get("name", "")).lower() in resume_zones
        ]
        self._safe_print(
            f"[resume] 失败清单涉及 {len(resume_zones)} 个域名，"
            f"本账号匹配 {len(kept)} 个"
        )
        return kept

    def batch_update(
        self,
        new_content: str,
        old_content: Optional[str] = None,
        whitelist: Optional[list[str]] = None,
        record_type: str = "auto",
        dry_run: bool = False,
        include_subdomains: bool = True,
        explicit_domains: Optional[list[str]] = None,
        resume_zones: Optional[set[str]] = None,
    ) -> BatchRunResult:
        """当前账号下批量更新 DNS 记录。"""
        self._check_stop()
        final_record_type = resolve_update_record_type(
            record_type, new_content, old_content
        )
        new_version = get_ip_version(new_content)
        old_version = get_ip_version(old_content) if old_content else None
        migrate_ip_family = bool(
            old_content
            and old_version in {4, 6}
            and new_version in {4, 6}
            and old_version != new_version
        )
        old_record_type = None
        if migrate_ip_family and old_content and old_version is not None:
            old_record_type = record_type_for_ip_version(old_version)

        # full_replace 模式：未指定 --old-ip 时，自动处理域名下所有 A/AAAA 记录
        # 包括同类型更新 和 跨类型迁移（自动检测并迁移旧记录）
        full_replace = old_content is None
        opposite_record_type = None
        if full_replace and new_version in {4, 6}:
            opposite_version = 6 if new_version == 4 else 4
            opposite_record_type = record_type_for_ip_version(opposite_version)

        self._safe_print("=" * 70)
        self._safe_print(f"Cloudflare DNS 批量更新 | 账号: {self.account_name}")
        self._safe_print(
            f"new_content={new_content}, old_content={old_content}, "
            f"type={final_record_type}, migrate_ip_family={migrate_ip_family}, "
            f"full_replace={full_replace}, workers={self.max_workers}, dry_run={dry_run}"
        )
        self._safe_print("=" * 70)

        all_zones = self.get_all_zones()
        account_zone_total = len(all_zones)
        self._safe_print(f"账号 {self.account_name} 下共 {account_zone_total} 个域名")

        # 合并实例级 explicit_domains 和方法参数
        final_explicit = explicit_domains or getattr(self, "_explicit_domains", None)
        zones, whitelist_set = self._filter_zones(
            all_zones, whitelist=whitelist, explicit_domains=final_explicit
        )
        zones = self._apply_resume_filter(zones, resume_zones)
        if not zones:
            self._safe_print("没有需要处理的域名")
            return BatchRunResult(results=[], stats=OperationStats())

        stats = OperationStats()
        all_results: list[DNSOperationResult] = []
        selected_zone_total = len(zones)

        executor = ThreadPoolExecutor(max_workers=self.max_workers)
        future_to_zone: dict[Future[Any], dict] = {}
        try:
            future_to_zone: dict[Future[Any], dict] = {}
            for zone_index, zone in enumerate(zones, start=1):
                if migrate_ip_family:
                    if old_record_type is None or old_content is None:
                        raise ValueError("跨 IP 类型迁移必须提供合法 --old-ip")
                    future = executor.submit(
                        self._process_zone_migrate_ip_family,
                        zone,
                        zone_index,
                        selected_zone_total,
                        account_zone_total,
                        old_content,
                        new_content,
                        old_record_type,
                        final_record_type,
                        dry_run,
                        include_subdomains,
                        whitelist_active=whitelist_set is not None,
                        stats=stats,
                    )
                elif full_replace:
                    future = executor.submit(
                        self._process_zone_full_replace,
                        zone,
                        zone_index,
                        selected_zone_total,
                        account_zone_total,
                        new_content,
                        final_record_type,
                        opposite_record_type,
                        dry_run,
                        include_subdomains,
                        whitelist_active=whitelist_set is not None,
                        stats=stats,
                    )
                else:
                    future = executor.submit(
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
                    )
                future_to_zone[future] = zone

            completed, cancelled = self._drain_zone_futures(
                future_to_zone, stats, all_results, action="批量更新"
            )
        except KeyboardInterrupt:
            self._stop_event.set()
            self._safe_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止当前账号任务...")
            completed, cancelled = self._drain_zone_futures(
                future_to_zone, stats, all_results, action="批量更新"
            )
        finally:
            # 正常路径排空等待，保证不丢任务；中断路径才立即取消。
            executor.shutdown(
                wait=not self._should_stop(), cancel_futures=bool(self._should_stop())
            )

        self._safe_print("\n" + "=" * 70)
        self._safe_print(f"账号 {self.account_name} 完成: {stats.summary()}")
        result = BatchRunResult(
            results=all_results,
            stats=stats,
            expected_zones=selected_zone_total,
            completed_zones=completed,
            cancelled_zones=cancelled,
        )
        self._safe_print(f"对账: {result.reconcile_text()}")
        self._safe_print("=" * 70)
        return result

    def batch_delete_wildcard(
        self,
        whitelist: Optional[list[str]] = None,
        record_type: str = "auto",
        old_content: Optional[str] = None,
        dry_run: bool = False,
        explicit_domains: Optional[list[str]] = None,
        resume_zones: Optional[set[str]] = None,
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

        final_explicit = explicit_domains or getattr(self, "_explicit_domains", None)
        zones, _ = self._filter_zones(
            all_zones, whitelist=whitelist, explicit_domains=final_explicit
        )
        zones = self._apply_resume_filter(zones, resume_zones)
        if not zones:
            self._safe_print("没有需要处理的域名")
            return BatchRunResult(results=[], stats=OperationStats())

        stats = OperationStats()
        all_results: list[DNSOperationResult] = []
        selected_zone_total = len(zones)

        executor = ThreadPoolExecutor(max_workers=self.max_workers)
        future_to_zone: dict[Future[Any], dict] = {}
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

            completed, cancelled = self._drain_zone_futures(
                future_to_zone, stats, all_results, action="删除通配符"
            )
        except KeyboardInterrupt:
            self._stop_event.set()
            self._safe_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止当前账号任务...")
            completed, cancelled = self._drain_zone_futures(
                future_to_zone, stats, all_results, action="删除通配符"
            )
        finally:
            executor.shutdown(
                wait=not self._should_stop(), cancel_futures=bool(self._should_stop())
            )

        self._safe_print("\n" + "=" * 70)
        self._safe_print(f"账号 {self.account_name} 完成: {stats.summary()}")
        result = BatchRunResult(
            results=all_results,
            stats=stats,
            expected_zones=selected_zone_total,
            completed_zones=completed,
            cancelled_zones=cancelled,
        )
        self._safe_print(f"对账: {result.reconcile_text()}")
        self._safe_print("=" * 70)
        return result

    def batch_add_domain_and_records(
        self,
        add_domain: Optional[str] = None,
        add_records: Optional[list[str]] = None,
        proxied: bool = True,  # 默认启用代理
        ttl: int = 1,
        dry_run: bool = False,
        existing_zone_id: Optional[str] = None,
        existing_zone_name: Optional[str] = None,
        explicit_domains: Optional[list[str]] = None,
        resume_zones: Optional[set[str]] = None,
        allow_multi_value: bool = False,
    ) -> BatchRunResult:
        """添加域名（可选）并批量添加 DNS 记录。"""
        self._check_stop()

        # 如果用户通过 -z 指定了域名但没有 --add-domain，则视为向已有域名添加记录
        target_zone_name = existing_zone_name or (
            explicit_domains[0] if explicit_domains else None
        )

        self._safe_print("=" * 70)
        self._safe_print(f"Cloudflare DNS 添加域名/记录 | 账号: {self.account_name}")
        self._safe_print(
            f"add_domain={add_domain}, target_zone={target_zone_name}, records={len(add_records) if add_records else 0}, "
            f"proxied={proxied}, ttl={ttl}, dry_run={dry_run}"
        )
        self._safe_print("=" * 70)

        stats = OperationStats()
        results: list[DNSOperationResult] = []

        if resume_zones is not None and target_zone_name:
            if target_zone_name.strip().lower() not in resume_zones:
                self._safe_print(
                    f"[resume] 目标域名 {target_zone_name} 不在失败清单中，跳过"
                )
                return BatchRunResult(results=[], stats=OperationStats())

        # 1. 处理 zone（优先使用已有 zone，其次添加新域名）
        zone_id = existing_zone_id
        zone_name = target_zone_name

        if add_domain and not zone_id:
            # 只有在没有已有 zone 时才添加新域名
            domain = add_domain.strip().lower()
            if dry_run:
                self._safe_print(f"  [DRY-ADD-DOMAIN] 将添加域名: {domain}")
                stats.inc_dry_run()
                results.append(
                    DNSOperationResult(
                        zone=domain,
                        name=domain,
                        record_type="ZONE",
                        old_content=None,
                        new_content=None,
                        status="dry_run_add_domain",
                        account=self.account_name,
                    )
                )
            else:
                try:
                    resp = self.create_zone(domain)
                    zone_id = resp.get("result", {}).get("id")
                    zone_name = resp.get("result", {}).get("name", domain)
                    self._safe_print(
                        f"  [OK] 已添加域名: {zone_name} (zone_id={zone_id})"
                    )
                    stats.inc_created()
                    results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name=zone_name,
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="added_domain",
                            account=self.account_name,
                        )
                    )
                except Exception as exc:
                    self._safe_print(f"  [ERR] 添加域名失败 {domain}: {exc}")
                    stats.inc_errors()
                    results.append(
                        DNSOperationResult(
                            zone=domain,
                            name=domain,
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="error",
                            message=str(exc),
                            account=self.account_name,
                        )
                    )
                    return BatchRunResult(results=results, stats=stats)

        # 如果用户指定了 -z 但没有 --add-domain，尝试获取 zone_id
        if not zone_id and zone_name:
            try:
                all_zones = self.get_all_zones()
                for z in all_zones:
                    if z.get("name", "").lower() == zone_name.lower():
                        zone_id = z["id"]
                        zone_name = z["name"]
                        self._safe_print(
                            f"  [INFO] 使用已有域名: {zone_name} (zone_id={zone_id})"
                        )
                        break
                if not zone_id:
                    self._safe_print(f"  [ERR] 未在账号中找到域名: {zone_name}")
                    stats.inc_errors()
                    results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name="",
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="error",
                            message="账号中未找到该域名",
                            account=self.account_name,
                        )
                    )
                    return BatchRunResult(results=results, stats=stats)
            except Exception as exc:
                self._safe_print(f"  [ERR] 获取域名列表失败: {exc}")
                stats.inc_errors()
                return BatchRunResult(results=results, stats=stats)

        # 2. 添加 DNS 记录
        if add_records:
            if zone_id and not zone_name:
                try:
                    zone_data = self.get_zone(zone_id)
                    zone_name = (zone_data.get("result") or {}).get("name") or zone_name
                except Exception:  # noqa: BLE001 - 仅用于补全 zone 名,失败不阻塞
                    pass
            if not zone_id:
                self._safe_print(
                    "  [ERR] 没有可用的 zone_id，请使用 --add-domain 添加域名，或使用 -z 指定已有域名"
                )
                stats.inc_errors()
                results.append(
                    DNSOperationResult(
                        zone=zone_name or "unknown",
                        name="",
                        record_type="ZONE",
                        old_content=None,
                        new_content=None,
                        status="error",
                        message="没有可用的 zone_id",
                        account=self.account_name,
                    )
                )

            if zone_id:
                for record_index, rec_str in enumerate(add_records):
                    if self._should_stop():
                        for pending_spec in add_records[record_index:]:
                            stats.inc_cancelled()
                            results.append(
                                DNSOperationResult(
                                    zone=zone_name or "unknown",
                                    name=pending_spec,
                                    record_type="RECORD",
                                    old_content=None,
                                    new_content=None,
                                    status="cancelled",
                                    message="添加任务被中断",
                                    account=self.account_name,
                                )
                            )
                        break
                    try:
                        rec_name, rec_type, rec_content = parse_add_record_spec(rec_str)

                        # auto 自动判断记录类型（最常用场景）
                        if rec_type in ("AUTO", "auto", ""):
                            rec_type = infer_record_type_from_content(rec_content)
                            self._safe_print(
                                f"  [AUTO] 自动判断记录类型: {rec_content} -> {rec_type}"
                            )

                        if dry_run:
                            self._safe_print(
                                f"  [DRY-ADD-RECORD] {rec_type} {rec_name} -> {rec_content}"
                            )
                            stats.inc_dry_run()
                            results.append(
                                DNSOperationResult(
                                    zone=zone_name or "unknown",
                                    name=rec_name,
                                    record_type=rec_type,
                                    old_content=None,
                                    new_content=rec_content,
                                    status="dry_run_add_record",
                                    account=self.account_name,
                                )
                            )
                            continue

                        status, message = self.ensure_dns_record(
                            zone_id=zone_id,
                            zone_name=zone_name or "",
                            record_name=rec_name,
                            record_type=rec_type,
                            content=rec_content,
                            proxied=proxied,
                            ttl=ttl,
                            allow_multi=allow_multi_value,
                        )
                        if status == "error":
                            self._safe_print(
                                f"  [ERR-ADD] {rec_type} {rec_name} -> {rec_content}: {message}"
                            )
                            stats.inc_errors()
                            results.append(
                                DNSOperationResult(
                                    zone=zone_name or "unknown",
                                    name=rec_name,
                                    record_type=rec_type,
                                    old_content=None,
                                    new_content=rec_content,
                                    status="error",
                                    message=message,
                                    account=self.account_name,
                                )
                            )
                            continue
                        if status == "unchanged":
                            self._safe_print(
                                f"  [SKIP-ADD] {rec_type} {rec_name} -> {rec_content}（已存在且一致）"
                            )
                            stats.inc_skipped()
                            result_status = "skipped"
                        elif status == "updated":
                            self._safe_print(
                                f"  [OK-UPDATE] {rec_type} {rec_name} -> {rec_content}（已覆盖旧记录）"
                            )
                            stats.inc_updated()
                            result_status = "updated_record"
                        else:
                            self._safe_print(
                                f"  [OK-ADD] {rec_type} {rec_name} -> {rec_content}"
                            )
                            stats.inc_created()
                            result_status = "added_record"
                        results.append(
                            DNSOperationResult(
                                zone=zone_name or "unknown",
                                name=rec_name,
                                record_type=rec_type,
                                old_content=None,
                                new_content=rec_content,
                                status=result_status,
                                message=message,
                                account=self.account_name,
                            )
                        )
                        interruptible_sleep(0.08, self._stop_event)

                    except Exception as exc:
                        self._safe_print(f"  [ERR-ADD] 添加记录失败 {rec_str}: {exc}")
                        stats.inc_errors()
                        results.append(
                            DNSOperationResult(
                                zone=zone_name or "unknown",
                                name=rec_str,
                                record_type="RECORD",
                                old_content=None,
                                new_content=None,
                                status="error",
                                message=str(exc),
                                account=self.account_name,
                            )
                        )

        self._safe_print("\n" + "=" * 70)
        self._safe_print(f"账号 {self.account_name} 完成: {stats.summary()}")
        self._safe_print("=" * 70)
        return BatchRunResult(results=results, stats=stats)

    def batch_delete_zone(
        self,
        whitelist: Optional[list[str]] = None,
        dry_run: bool = False,
        delete_zone_completely: bool = False,
        explicit_domains: Optional[list[str]] = None,
        resume_zones: Optional[set[str]] = None,
    ) -> BatchRunResult:
        """清空域名所有 DNS 记录（dns 模式），或彻底删除域名（full 模式）。

        参数：
            delete_zone_completely: True 表示彻底删除域名（full），False 仅清空 DNS 记录（dns）
        """
        self._check_stop()

        mode = "full（删除域名）" if delete_zone_completely else "dns（仅清空解析）"
        self._safe_print("=" * 70)
        self._safe_print(f"Cloudflare DNS 域名删除 | 账号: {self.account_name}")
        self._safe_print(f"mode={mode}, workers={self.max_workers}, dry_run={dry_run}")
        self._safe_print("=" * 70)

        all_zones = self.get_all_zones()
        account_zone_total = len(all_zones)
        self._safe_print(f"账号 {self.account_name} 下共 {account_zone_total} 个域名")

        zones, target_set = self._filter_zones(
            all_zones, whitelist=whitelist, explicit_domains=explicit_domains
        )
        zones = self._apply_resume_filter(zones, resume_zones)
        if not zones:
            self._safe_print("没有需要处理的域名")
            return BatchRunResult(results=[], stats=OperationStats())

        stats = OperationStats()
        all_results: list[DNSOperationResult] = []
        selected_zone_total = len(zones)
        completed_zones = 0

        for zone_index, zone in enumerate(zones, start=1):
            if self._should_stop():
                for pending_zone in zones[zone_index - 1 :]:
                    pending_name = str(pending_zone.get("name", "unknown"))
                    stats.inc_cancelled()
                    all_results.append(
                        DNSOperationResult(
                            zone=pending_name,
                            name="",
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="cancelled",
                            message="删除域名任务被中断",
                            account=self.account_name,
                        )
                    )
                    self._report_zone(pending_name, "cancelled")
                break

            zone_name = zone["name"]
            zone_id = zone["id"]

            self._safe_print(
                self._progress_prefix(
                    zone_name,
                    zone_index,
                    selected_zone_total,
                    account_zone_total,
                    action_name="删除域名"
                    if delete_zone_completely
                    else "清空 DNS 记录",
                )
            )

            try:
                # 1. 获取该 zone 下的所有 DNS 记录
                records = self._fetch_records_with_retry(
                    zone_id, zone_name, "ALL", stats, all_results, action="删除域名"
                )
                if records is None:
                    continue
                record_count = len(records)
                self._safe_print(f"  [zone] 发现 {record_count} 条 DNS 记录")

                if dry_run:
                    self._safe_print(
                        f"  [DRY-DELETE-ZONE] 将删除 {record_count} 条记录"
                    )
                    if delete_zone_completely:
                        self._safe_print(
                            f"  [DRY-DELETE-ZONE] 将彻底删除域名 {zone_name}"
                        )
                    stats.inc_dry_run()
                    all_results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name=zone_name,
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="dry_run_delete_zone"
                            if delete_zone_completely
                            else "dry_run_clear_dns",
                            account=self.account_name,
                        )
                    )
                    self._report_zone(zone_name, "done")
                    completed_zones += 1
                    continue

                # 2. 删除所有 DNS 记录
                deleted_count = 0
                for record in records:
                    if self._should_stop():
                        break
                    try:
                        self.delete_dns_record(zone_id, record["id"])
                        deleted_count += 1
                        interruptible_sleep(0.05, self._stop_event)
                    except Exception as exc:
                        self._safe_print(
                            f"  [ERR] 删除记录失败 {record.get('name')}: {exc}"
                        )
                        stats.inc_errors()
                        all_results.append(
                            DNSOperationResult(
                                zone=zone_name,
                                name=str(record.get("name", "")),
                                record_type=str(record.get("type", "")),
                                old_content=str(record.get("content", "")),
                                new_content=None,
                                status="error",
                                message=str(exc),
                                account=self.account_name,
                            )
                        )

                stats.inc_deleted(deleted_count)
                self._safe_print(
                    f"  [OK] 已删除 {deleted_count}/{record_count} 条 DNS 记录"
                )

                # 3. 如果是 full 模式，删除整个 zone
                if delete_zone_completely:
                    try:
                        self.delete_zone(zone_id)
                        stats.inc_deleted(1)  # 计入域名删除
                        self._safe_print(f"  [OK-FULL] 已彻底删除域名 {zone_name}")
                        all_results.append(
                            DNSOperationResult(
                                zone=zone_name,
                                name=zone_name,
                                record_type="ZONE",
                                old_content=None,
                                new_content=None,
                                status="deleted_zone",
                                account=self.account_name,
                            )
                        )
                        self._report_zone(zone_name, "done")
                    except Exception as exc:
                        self._safe_print(f"  [ERR-FULL] 删除域名失败: {exc}")
                        stats.inc_errors()
                        all_results.append(
                            DNSOperationResult(
                                zone=zone_name,
                                name=zone_name,
                                record_type="ZONE",
                                old_content=None,
                                new_content=None,
                                status="error",
                                message=str(exc),
                                account=self.account_name,
                            )
                        )
                        self._report_zone(zone_name, "error")
                else:
                    all_results.append(
                        DNSOperationResult(
                            zone=zone_name,
                            name=zone_name,
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="cleared_dns",
                            account=self.account_name,
                        )
                    )
                    self._report_zone(zone_name, "done")
                completed_zones += 1

            except KeyboardInterrupt:
                self._stop_event.set()
                for pending_zone in zones[zone_index:]:
                    pending_name = str(pending_zone.get("name", "unknown"))
                    stats.inc_cancelled()
                    all_results.append(
                        DNSOperationResult(
                            zone=pending_name,
                            name="",
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="cancelled",
                            message="删除域名任务被中断",
                            account=self.account_name,
                        )
                    )
                    self._report_zone(pending_name, "cancelled")
                break
            except Exception as exc:
                self._safe_print(f"  [zone] 处理失败: {exc}")
                stats.inc_errors()
                all_results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name="",
                        record_type="ZONE",
                        old_content=None,
                        new_content=None,
                        status="error",
                        message=str(exc),
                        account=self.account_name,
                    )
                )
                self._report_zone(zone_name, "error")

        self._safe_print("\n" + "=" * 70)
        self._safe_print(f"账号 {self.account_name} 完成: {stats.summary()}")
        result = BatchRunResult(
            results=all_results,
            stats=stats,
            expected_zones=selected_zone_total,
            completed_zones=completed_zones,
            cancelled_zones=stats.cancelled,
        )
        self._safe_print(f"对账: {result.reconcile_text()}")
        self._safe_print("=" * 70)
        return result

    def _process_zone_set_attrs(
        self,
        zone: dict,
        zone_index: int,
        selected_zone_total: int,
        account_zone_total: int,
        fetch_types: list[str],
        set_proxied: Optional[bool],
        set_ttl: Optional[int],
        old_content: Optional[str],
        dry_run: bool,
        include_subdomains: bool,
        whitelist_active: bool,
        stats: OperationStats,
    ) -> list[DNSOperationResult]:
        """处理单个 zone 的代理状态/TTL 批量设置（内容保持不变）。"""
        zone_name = zone["name"]
        zone_id = zone["id"]
        results: list[DNSOperationResult] = []

        self._safe_print(
            self._progress_prefix(
                zone_name,
                zone_index,
                selected_zone_total,
                account_zone_total,
                action_name=f"设置属性(proxied={set_proxied}, ttl={set_ttl})",
            )
        )

        all_records: list[dict] = []
        try:
            for fetch_type in fetch_types:
                fetched = self._fetch_records_with_retry(
                    zone_id, zone_name, fetch_type, stats, results, action="设置属性"
                )
                if fetched is None:
                    return results
                all_records.extend(fetched)
        except KeyboardInterrupt:
            return results

        for index, record in enumerate(all_records):
            if self._should_stop():
                self._mark_remaining_cancelled(
                    results,
                    stats,
                    zone_name,
                    "RECORD",
                    all_records[index:],
                    action="设置属性",
                )
                return results

            r_name = record.get("name", "")
            r_content = record.get("content", "")
            r_id = record.get("id", "")
            r_type = record.get("type", "")
            r_proxied = bool(record.get("proxied", False))
            r_ttl = int(record.get("ttl", 1) or 1)

            if (
                whitelist_active
                and not include_subdomains
                and r_name.lower() != zone_name.lower()
            ):
                continue
            if old_content and not contents_equal(r_content, old_content):
                stats.inc_skipped()
                continue

            new_proxied = r_proxied if set_proxied is None else set_proxied
            new_ttl = r_ttl if set_ttl is None else set_ttl
            if new_proxied == r_proxied and new_ttl == r_ttl:
                stats.inc_skipped()
                continue

            if dry_run:
                self._safe_print(
                    f"  [DRY-ATTRS] {r_type} {r_name}: "
                    f"proxied {r_proxied}->{new_proxied}, ttl {r_ttl}->{new_ttl}"
                )
                stats.inc_dry_run()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=r_content,
                        status="dry_run_set_attrs",
                        account=self.account_name,
                    )
                )
                continue

            try:
                self.update_dns_record(
                    zone_id=zone_id,
                    record_id=r_id,
                    record_name=r_name,
                    new_content=r_content,
                    proxied=new_proxied,
                    ttl=new_ttl,
                    record_type=r_type,
                )
                self._safe_print(
                    f"  [OK-ATTRS] {r_type} {r_name}: "
                    f"proxied {r_proxied}->{new_proxied}, ttl {r_ttl}->{new_ttl}"
                )
                stats.inc_updated()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=r_content,
                        status="updated_attrs",
                        account=self.account_name,
                    )
                )
                interruptible_sleep(0.1, self._stop_event)
            except Exception as exc:
                self._safe_print(f"  [ERR-ATTRS] {r_type} {r_name}: {exc}")
                stats.inc_errors()
                results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=r_name,
                        record_type=r_type,
                        old_content=r_content,
                        new_content=r_content,
                        status="error",
                        message=str(exc),
                        account=self.account_name,
                    )
                )

        return results

    def batch_set_attrs(
        self,
        set_proxied: Optional[bool] = None,
        set_ttl: Optional[int] = None,
        whitelist: Optional[list[str]] = None,
        record_type: str = "auto",
        old_content: Optional[str] = None,
        dry_run: bool = False,
        include_subdomains: bool = True,
        explicit_domains: Optional[list[str]] = None,
        resume_zones: Optional[set[str]] = None,
    ) -> BatchRunResult:
        """当前账号下批量设置 DNS 记录的代理状态/TTL（内容不变）。"""
        self._check_stop()
        if set_proxied is None and set_ttl is None:
            raise ValueError("至少指定 --set-proxied 或 --set-ttl 之一")
        if set_ttl is not None and set_ttl < 1:
            raise ValueError("--set-ttl 必须为正整数（1 表示自动）")

        normalized = (record_type or "auto").strip().upper()
        if normalized in {"AUTO", "ALL"}:
            fetch_types = ["A", "AAAA", "CNAME"]
        elif normalized in UPDATABLE_RECORD_TYPES:
            fetch_types = [normalized]
        else:
            raise ValueError(f"属性设置不支持记录类型: {record_type}")

        self._safe_print("=" * 70)
        self._safe_print(f"Cloudflare DNS 属性批量设置 | 账号: {self.account_name}")
        self._safe_print(
            f"set_proxied={set_proxied}, set_ttl={set_ttl}, types={fetch_types}, "
            f"workers={self.max_workers}, dry_run={dry_run}"
        )
        self._safe_print("=" * 70)

        all_zones = self.get_all_zones()
        account_zone_total = len(all_zones)
        self._safe_print(f"账号 {self.account_name} 下共 {account_zone_total} 个域名")

        final_explicit = explicit_domains or getattr(self, "_explicit_domains", None)
        zones, whitelist_set = self._filter_zones(
            all_zones, whitelist=whitelist, explicit_domains=final_explicit
        )
        zones = self._apply_resume_filter(zones, resume_zones)
        if not zones:
            self._safe_print("没有需要处理的域名")
            return BatchRunResult(results=[], stats=OperationStats())

        stats = OperationStats()
        all_results: list[DNSOperationResult] = []
        selected_zone_total = len(zones)

        executor = ThreadPoolExecutor(max_workers=self.max_workers)
        future_to_zone: dict[Future[Any], dict] = {}
        try:
            for zone_index, zone in enumerate(zones, start=1):
                future = executor.submit(
                    self._process_zone_set_attrs,
                    zone,
                    zone_index,
                    selected_zone_total,
                    account_zone_total,
                    fetch_types,
                    set_proxied,
                    set_ttl,
                    old_content,
                    dry_run,
                    include_subdomains,
                    whitelist_set is not None,
                    stats,
                )
                future_to_zone[future] = zone

            completed, cancelled = self._drain_zone_futures(
                future_to_zone, stats, all_results, action="设置属性"
            )
        except KeyboardInterrupt:
            self._stop_event.set()
            self._safe_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止当前账号任务...")
            completed, cancelled = self._drain_zone_futures(
                future_to_zone, stats, all_results, action="设置属性"
            )
        finally:
            executor.shutdown(
                wait=not self._should_stop(), cancel_futures=bool(self._should_stop())
            )

        self._safe_print("\n" + "=" * 70)
        self._safe_print(f"账号 {self.account_name} 完成: {stats.summary()}")
        result = BatchRunResult(
            results=all_results,
            stats=stats,
            expected_zones=selected_zone_total,
            completed_zones=completed,
            cancelled_zones=cancelled,
        )
        self._safe_print(f"对账: {result.reconcile_text()}")
        self._safe_print("=" * 70)
        return result

    def batch_export(
        self,
        export_dir: str,
        fmt: str = "json",
        whitelist: Optional[list[str]] = None,
        explicit_domains: Optional[list[str]] = None,
        resume_zones: Optional[set[str]] = None,
    ) -> BatchRunResult:
        """导出当前账号下 zone 的 DNS 记录（变更前备份/审计用）。"""
        self._check_stop()
        if fmt not in {"json", "bind"}:
            raise ValueError("--export 仅支持 json/bind")

        self._safe_print("=" * 70)
        self._safe_print(f"Cloudflare DNS 导出 | 账号: {self.account_name}")
        self._safe_print(f"format={fmt}, dir={export_dir}")
        self._safe_print("=" * 70)

        all_zones = self.get_all_zones()
        account_zone_total = len(all_zones)
        self._safe_print(f"账号 {self.account_name} 下共 {account_zone_total} 个域名")

        final_explicit = explicit_domains or getattr(self, "_explicit_domains", None)
        zones, _ = self._filter_zones(
            all_zones, whitelist=whitelist, explicit_domains=final_explicit
        )
        zones = self._apply_resume_filter(zones, resume_zones)
        if not zones:
            self._safe_print("没有需要处理的域名")
            return BatchRunResult(results=[], stats=OperationStats())

        stats = OperationStats()
        all_results: list[DNSOperationResult] = []
        selected_zone_total = len(zones)
        completed = 0

        for zone_index, zone in enumerate(zones, start=1):
            if self._should_stop():
                for pending_zone in zones[zone_index - 1 :]:
                    stats.inc_cancelled()
                    pending_name = str(pending_zone.get("name", "unknown"))
                    all_results.append(
                        DNSOperationResult(
                            zone=pending_name,
                            name="",
                            record_type="ZONE",
                            old_content=None,
                            new_content=None,
                            status="cancelled",
                            message="导出任务被中断",
                            account=self.account_name,
                        )
                    )
                    self._report_zone(pending_name, "cancelled")
                break
            zone_name = zone.get("name", "unknown")
            zone_id = zone.get("id", "")
            self._safe_print(
                f"[{zone_index}/{selected_zone_total}] 导出域名: {zone_name}"
            )
            try:
                records = self._fetch_records_with_retry(
                    zone_id, zone_name, "ALL", stats, all_results, action="导出"
                )
                if records is None:
                    self._report_zone(zone_name, "error")
                    continue
                payload = serialize_zone_backup(self.account_name, zone, records)
                path = write_zone_backup_file(
                    export_dir, self.account_name, zone_name, payload, fmt
                )
                self._safe_print(f"  [OK-EXPORT] {zone_name} -> {path}")
                stats.inc_updated()
                all_results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name=zone_name,
                        record_type="ZONE",
                        old_content=None,
                        new_content=path,
                        status="exported",
                        account=self.account_name,
                    )
                )
                self._report_zone(zone_name, "done")
                completed += 1
            except KeyboardInterrupt:
                self._stop_event.set()
                self._report_zone(zone_name, "cancelled")
                break
            except Exception as exc:
                self._safe_print(f"  [ERR-EXPORT] {zone_name}: {exc}")
                stats.inc_errors()
                all_results.append(
                    DNSOperationResult(
                        zone=zone_name,
                        name="",
                        record_type="ZONE",
                        old_content=None,
                        new_content=None,
                        status="error",
                        message=str(exc),
                        account=self.account_name,
                    )
                )
                self._report_zone(zone_name, "error")

        self._safe_print("\n" + "=" * 70)
        self._safe_print(f"账号 {self.account_name} 完成: {stats.summary()}")
        result = BatchRunResult(
            results=all_results,
            stats=stats,
            expected_zones=selected_zone_total,
            completed_zones=completed,
            cancelled_zones=stats.cancelled,
        )
        self._safe_print(f"对账: {result.reconcile_text()}")
        self._safe_print("=" * 70)
        return result

    def batch_backup(
        self,
        backup_dir: str,
        whitelist: Optional[list[str]] = None,
        explicit_domains: Optional[list[str]] = None,
        resume_zones: Optional[set[str]] = None,
    ) -> tuple[bool, str]:
        """变更前自动快照：将待处理 zone 全量导出为 JSON。

        任一 zone 快照失败即返回 False，调用方应中止变更，保证“无备份不变更”。
        """
        self._check_stop()
        all_zones = self.get_all_zones()
        final_explicit = explicit_domains or getattr(self, "_explicit_domains", None)
        zones, _ = self._filter_zones(
            all_zones, whitelist=whitelist, explicit_domains=final_explicit
        )
        zones = self._apply_resume_filter(zones, resume_zones)
        if not zones:
            return True, "无待处理域名，无需备份"

        stats = OperationStats()
        ledger: list[DNSOperationResult] = []
        for zone in zones:
            self._check_stop()
            zone_name = zone.get("name", "unknown")
            records = self._fetch_records_with_retry(
                zone.get("id", ""), zone_name, "ALL", stats, ledger, action="备份"
            )
            if records is None:
                return False, f"备份失败：{zone_name} 记录读取失败，已中止变更"
            try:
                payload = serialize_zone_backup(self.account_name, zone, records)
                write_zone_backup_file(
                    backup_dir, self.account_name, zone_name, payload, "json"
                )
            except (OSError, ValueError) as exc:
                return False, f"备份失败：{zone_name} 写入失败({exc})，已中止变更"
        self._safe_print(
            f"[BACKUP] 账号 {self.account_name} 已快照 {len(zones)} 个域名到 {backup_dir}"
        )
        return True, f"已备份 {len(zones)} 个域名"

    def batch_delete_ip(
        self,
        delete_ip: str,
        whitelist: Optional[list[str]] = None,
        record_type: str = "auto",
        dry_run: bool = False,
        include_subdomains: bool = True,
        explicit_domains: Optional[list[str]] = None,
        resume_zones: Optional[set[str]] = None,
    ) -> BatchRunResult:
        """当前账号下批量删除所有指向指定 IP 的 A/AAAA 记录。"""
        self._check_stop()
        final_record_type = resolve_delete_ip_record_type(delete_ip, record_type)

        self._safe_print("=" * 70)
        self._safe_print(f"Cloudflare DNS 指定 IP 记录删除 | 账号: {self.account_name}")
        self._safe_print(
            f"delete_ip={delete_ip}, record_type={final_record_type}, "
            f"workers={self.max_workers}, dry_run={dry_run}"
        )
        self._safe_print("=" * 70)

        all_zones = self.get_all_zones()
        account_zone_total = len(all_zones)
        self._safe_print(f"账号 {self.account_name} 下共 {account_zone_total} 个域名")

        # 合并实例级 explicit_domains 和方法参数
        final_explicit = explicit_domains or getattr(self, "_explicit_domains", None)
        zones, whitelist_set = self._filter_zones(
            all_zones, whitelist=whitelist, explicit_domains=final_explicit
        )
        zones = self._apply_resume_filter(zones, resume_zones)
        if not zones:
            self._safe_print("没有需要处理的域名")
            return BatchRunResult(results=[], stats=OperationStats())

        stats = OperationStats()
        all_results: list[DNSOperationResult] = []
        selected_zone_total = len(zones)

        executor = ThreadPoolExecutor(max_workers=self.max_workers)
        future_to_zone: dict[Future[Any], dict] = {}
        try:
            future_to_zone = {
                executor.submit(
                    self._process_zone_delete_ip,
                    zone,
                    zone_index,
                    selected_zone_total,
                    account_zone_total,
                    delete_ip,
                    final_record_type,
                    dry_run,
                    include_subdomains,
                    whitelist_active=whitelist_set is not None,
                    stats=stats,
                ): zone
                for zone_index, zone in enumerate(zones, start=1)
            }

            completed, cancelled = self._drain_zone_futures(
                future_to_zone, stats, all_results, action="删除指定 IP"
            )
        except KeyboardInterrupt:
            self._stop_event.set()
            self._safe_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止当前账号任务...")
            completed, cancelled = self._drain_zone_futures(
                future_to_zone, stats, all_results, action="删除指定 IP"
            )
        finally:
            executor.shutdown(
                wait=not self._should_stop(), cancel_futures=bool(self._should_stop())
            )

        self._safe_print("\n" + "=" * 70)
        self._safe_print(f"账号 {self.account_name} 完成: {stats.summary()}")
        result = BatchRunResult(
            results=all_results,
            stats=stats,
            expected_zones=selected_zone_total,
            completed_zones=completed,
            cancelled_zones=cancelled,
        )
        self._safe_print(f"对账: {result.reconcile_text()}")
        self._safe_print("=" * 70)
        return result


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
    """读取配置文件，支持 JSON、CSV、Excel（.xlsx/.xls）格式。

    表格格式要求（表头）：
        account, cf_api_email, password, cf_api_key, email_routing_verified

    返回统一结构：
        {
          "accounts": {
            "account-name": {
              "cf_api_email": "...",
              "cf_api_key": "...",
              ...
            }
          }
        }
    """
    if not os.path.exists(config_path):
        log_print(f"配置文件不存在: {config_path}")
        sys.exit(1)

    ext = os.path.splitext(config_path)[1].lower()

    # JSON 格式
    if ext == ".json":
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f) or {}
            # 兼容旧格式：如果已经是 {"accounts": {...}} 则直接返回
            if isinstance(data, dict) and "accounts" in data:
                return data
            # 否则假定它是 accounts 列表/字典
            return {"accounts": data}

    # 表格格式（CSV / Excel）
    elif ext in {".csv", ".xlsx", ".xls"}:
        try:
            import pandas as pd
        except ImportError:
            log_print("读取表格格式需要安装 pandas：pip install pandas openpyxl")
            sys.exit(1)

        if ext == ".csv":
            df = pd.read_csv(config_path)
        else:
            df = pd.read_excel(config_path)

        # 标准化列名（去除空格、大小写）
        df.columns = [str(c).strip().lower() for c in df.columns]

        required = {"cf_api_email", "cf_api_key"}
        if not required.issubset(set(df.columns)):
            log_print(f"表格缺少必要列 {required}，当前列: {list(df.columns)}")
            sys.exit(1)

        accounts_dict: dict[str, dict[str, Any]] = {}
        for row_number, (_, row) in enumerate(df.iterrows(), start=2):
            email = normalize_config_text(row.get("cf_api_email"))
            key = normalize_config_text(row.get("cf_api_key"))
            if not email or not key:
                account_name = normalize_config_text(row.get("account")) or "未命名账号"
                log_print(
                    f"[WARN] 配置文件第 {row_number} 行 {account_name} "
                    f"缺少有效的 cf_api_email 或 cf_api_key，已跳过"
                )
                continue

            name = normalize_config_text(row.get("account")) or email.split("@")[0]
            acc: dict[str, Any] = {
                "cf_api_email": email,
                "cf_api_key": key,
            }
            if "password" in df.columns:
                pwd = row.get("password")
                if bool(pd.notna(pwd)):
                    pwd_str = normalize_config_text(pwd)
                    if pwd_str:
                        acc["password"] = pwd_str
            if "email_routing_verified" in df.columns:
                val = row.get("email_routing_verified")
                if bool(pd.notna(val)):
                    acc["email_routing_verified"] = bool(val)

            accounts_dict[name] = acc

        return {"accounts": accounts_dict}

    else:
        log_print(f"不支持的配置文件格式: {ext}")
        sys.exit(1)


def get_cf_accounts(config_path: str) -> list[dict]:
    """
    从配置文件读取 Cloudflare 账号。

    支持格式：
      - JSON（旧格式）
      - CSV / Excel 表格（新格式）

    表格表头（必需）：
        cf_api_email, cf_api_key
    可选列：
        account, password, email_routing_verified

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
        token = normalize_config_text(acc_obj.get("cf_api_token"))
        email = normalize_config_text(acc_obj.get("cf_api_email"))
        key = normalize_config_text(acc_obj.get("cf_api_key"))
        account_name = normalize_config_text(name) or email or "unknown"
        # 透传旧配置里的可选字段(默认服务器 IP、邮箱路由验证状态),供上层编排使用。
        extras: dict = {}
        server_ip = normalize_config_text(acc_obj.get("default_server_ip"))
        if server_ip:
            extras["default_server_ip"] = server_ip
        if "email_routing_verified" in acc_obj:
            extras["email_routing_verified"] = bool(
                acc_obj.get("email_routing_verified")
            )

        if token:
            accounts.append(
                {
                    "name": account_name,
                    "auth_method": "token",
                    "token": token,
                    "email": None,
                    "key": None,
                    **extras,
                }
            )
        elif email and key:
            accounts.append(
                {
                    "name": account_name,
                    "auth_method": "key",
                    "token": None,
                    "email": email,
                    "key": key,
                    **extras,
                }
            )
        else:
            log_print(
                f"[WARN] 账号 {account_name}"
                + (f" <{email}>" if email else "")
                + " 缺少有效认证字段，已跳过"
            )

    return accounts


def load_cf_globals(config_path: str) -> dict:
    """读取 Cloudflare 配置中的全局默认值(仅 JSON 格式支持)。

    兼容旧 cf_config.json 的顶层字段,供域名修复流程复用:
        default_forward_email / ssl_mode / security_mode

    表格(csv/xlsx)没有顶层全局字段,返回空 dict。
    """
    ext = os.path.splitext(config_path)[1].lower()
    if ext != ".json" or not os.path.exists(config_path):
        return {}
    try:
        with open(config_path, "r", encoding="utf-8") as file_obj:
            data = json.load(file_obj) or {}
    except Exception:  # noqa: BLE001 - 读取失败按无全局配置处理
        return {}
    if not isinstance(data, dict):
        return {}
    result: dict = {}
    for key in ("default_forward_email", "ssl_mode", "security_mode"):
        value = data.get(key)
        if value not in (None, ""):
            result[key] = value
    return result


def load_provision_table(path: str) -> dict[str, dict[str, str]]:
    """读取 --provision 的域名表格(兼容旧 cf_domains 格式)。

    支持 csv/xlsx(列: domain,ip,forward,security,ssl,Note)与 conf/txt
    (每行第一个 token 视为域名)。返回 domain -> {ip,forward,security,ssl}。
    """
    result: dict[str, dict[str, str]] = {}
    if not path or not os.path.exists(path):
        return result
    ext = os.path.splitext(path)[1].lower()
    rows: list[dict] = []
    if ext == ".csv":
        import csv

        with open(path, "r", newline="", encoding="utf-8-sig") as file_obj:
            rows = [dict(row) for row in csv.DictReader(file_obj)]
    elif ext in {".xlsx", ".xls"}:
        try:
            import pandas as pd
        except ImportError:
            log_print("读取 Excel 表格需要安装 pandas：pip install pandas openpyxl")
            sys.exit(1)
        frame = pd.read_excel(path, keep_default_na=False)
        rows = [
            {str(k).strip().lower(): v for k, v in row.items()}
            for row in frame.to_dict(orient="records")
        ]
    else:
        with open(path, "r", encoding="utf-8-sig") as file_obj:
            for raw in file_obj:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                domain = (
                    (get_main_domain_name_from_str(line.split()[0]) or line.split()[0])
                    .strip()
                    .lower()
                )
                if domain:
                    result.setdefault(
                        domain,
                        {"ip": "", "forward": "", "security": "", "ssl": ""},
                    )
        return result

    for row in rows:
        lowered = {
            str(k).strip().lower(): ("" if v is None else str(v).strip())
            for k, v in row.items()
        }
        domain = (
            (
                get_main_domain_name_from_str(lowered.get("domain", ""))
                or lowered.get("domain", "")
            )
            .strip()
            .lower()
        )
        if not domain:
            continue
        result[domain] = {
            "ip": lowered.get("ip", ""),
            "forward": lowered.get("forward", ""),
            "security": lowered.get("security", ""),
            "ssl": lowered.get("ssl", ""),
        }
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Cloudflare DNS 批量修改/查询/清理工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
        Note: 更多示例查看Readme.md文档,这里仅列出简单用法.
        Examples:

        # 查询某个域名
        python cloudflare_dns_tool.py  --find-domain domain.com  --json # -s选项默认可以指定账户名(缩写),不使用-s则全部账号中查找.

        # 为cf00这个cf账号中的domain.com域名添加dns记录,@表示主域名domain.com本身
        python cloudflare_dns_tool.py -s cf00  -z domain.com  --add-record  "@:auto:23.23.23.23" # -z选项指定域名,record参数指定三级域名段即可

        # 指定cf账号配置文件
        python cloudflare_dns_tool.py -C $deploy_configs/cf_config.csv # ....其他参数

        # IPv4：自动选择 A 记录
        python cloudflare_dns_tool.py --new-ip 1.2.3.4 --dry-run

        # IPv6：自动选择 AAAA 记录
        python cloudflare_dns_tool.py --new-ip 2001:db8::1 --dry-run

        # 只更新旧 IPv6 为指定新 IPv6
        python cloudflare_dns_tool.py --old-ip 2001:db8::10 --new-ip 2001:db8::20

        # IPv4 -> IPv6 迁移：为匹配旧 IPv4 的记录创建 AAAA，并删除旧 A
        python cloudflare_dns_tool.py --old-ip 1.2.3.4 --new-ip 2001:db8::1 --dry-run

        # 从指定账号中删除域名,域名及其dns记录都移除
        python cloudflare_dns_tool.py  --delete-zone full -z domain.com -s cf00

        # 删除域名下的所有dns记录,但保留域名在cf账号中.
        python cloudflare_dns_tool.py  --delete-zone dns -z domain.com -s cf00

        # 删除所有指向指定 IP 的 A/AAAA 记录
        python cloudflare_dns_tool.py --delete-ip 1.2.3.4 --dry-run

        # 失败清单与重跑：先导出失败/取消行，再仅重跑清单中的域名
        python cloudflare_dns_tool.py --new-ip 1.2.3.4 --failed-output failures.csv
        python cloudflare_dns_tool.py --new-ip 1.2.3.4 --resume-from failures.csv

        # 经本地代理出口（mihomo 等），多代理轮转并故障切换
        python cloudflare_dns_tool.py --new-ip 1.2.3.4 -P http://127.0.0.1:7897 --dry-run

        # 更新 CNAME
        python cloudflare_dns_tool.py --record-type CNAME --old-content old.example.com --new-content new.example.com

        # 预览删除所有以 * 开头的通配符记录
        python cloudflare_dns_tool.py --delete-wildcard --dry-run

        # 只删除通配符 AAAA 记录
        python cloudflare_dns_tool.py --delete-wildcard --record-type AAAA

        # 保守模式：适合账号多、域名多或已有其他 Cloudflare API 任务同时运行的场景
        python cloudflare_dns_tool.py --new-ip 1.2.3.4 --conservative --dry-run

        # 自定义全局 API 调用间隔：本脚本进程内所有账号共享，0.5 表示最多约 2 次/秒
        python cloudflare_dns_tool.py --new-ip 1.2.3.4 --request-interval 0.5

        # 短选项等价写法
        python cloudflare_dns_tool.py -n 1.2.3.4 -c -d
        python cloudflare_dns_tool.py -D -c -d
        
        """,
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
        "-z",
        "--domain",
        action="append",
        default=None,
        metavar="DOMAIN",
        help="直接指定要处理的域名（可多次使用，例如 -z example.com -z www.example.com）。与 --whitelist 同时使用时取交集。",
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
    parser.add_argument(
        "-x",
        "--delete-ip",
        default=None,
        metavar="IP",
        help="删除所有指向指定 IPv4/IPv6 的 A/AAAA 记录；建议先加 --dry-run 预览。",
    )
    parser.add_argument(
        "--delete-zone",
        choices=["dns", "full"],
        default=None,
        help="删除域名模式：dns=仅清空所有 DNS 记录（保留域名），full=清空记录后彻底删除域名。需配合 -z/--domain 或 -w 使用。",
    )

    # 新增：添加域名和 DNS 记录
    parser.add_argument(
        "--add-domain",
        metavar="DOMAIN",
        default=None,
        help="在当前账号下添加新域名（zone）。例如：--add-domain example.com",
    )
    parser.add_argument(
        "--add-record",
        action="append",
        default=None,
        metavar="NAME:TYPE:CONTENT",
        help="添加 DNS 记录（可多次使用）。格式支持 name:type:content、name-type-content、name space content。支持 auto 自动判断类型，例如 www:auto:1.2.3.4。默认启用 Cloudflare 代理。同名同类型记录幂等：内容一致则跳过，不一致则覆盖（A/AAAA/CNAME），不会产生重复或分叉。",
    )
    parser.add_argument(
        "--no-proxied",
        action="store_true",
        help="添加记录时禁用 Cloudflare 代理（默认启用）。",
    )
    parser.add_argument(
        "--ttl",
        type=int,
        default=1,
        help="添加记录的 TTL（默认 1 = 自动）。",
    )
    parser.add_argument(
        "--allow-multi-value",
        action="store_true",
        help="允许同名 A/AAAA 多值（同一主机名指向多个 IP）；默认关闭，同名只保留一条。CNAME 始终单值。",
    )

    # P0：备份导出与属性批量设置。
    parser.add_argument(
        "--export",
        choices=["json", "bind"],
        default=None,
        metavar="FORMAT",
        help="导出模式：将待处理 zone 的 DNS 记录导出为 json 或简化 bind 文件。需配合 --export-dir。",
    )
    parser.add_argument(
        "--export-dir",
        default=None,
        metavar="DIR",
        help="导出目录（默认 ./cf_export），按 <账号>/<域名>.json|bind 存放。",
    )
    parser.add_argument(
        "--backup-dir",
        default=None,
        metavar="DIR",
        help="变更前自动快照目录：正式执行（非 dry-run）前先全量备份待处理 zone，备份失败则中止变更。",
    )
    parser.add_argument(
        "--set-proxied",
        choices=["on", "off"],
        default=None,
        help="批量设置记录代理状态：on=启用橙云，off=关闭。内容保持不变，可与 --set-ttl 同用。",
    )
    parser.add_argument(
        "--set-ttl",
        type=int,
        default=None,
        metavar="N",
        help="批量设置记录 TTL（1=自动）。内容保持不变，可与 --set-proxied 同用。",
    )

    # 并发与速度档位。-W/-A/-i 默认 None 表示“未显式指定”，由 --speed 档位填充；
    # 显式指定的值优先（仍钳制在 1~20），档位只填未指定的项。
    parser.add_argument(
        "-W",
        "--workers",
        type=int,
        default=None,
        metavar="N",
        help="单账号内 zone/域名并发数。不指定时按 --speed 取值（eco:2，最大 20）。",
    )
    parser.add_argument(
        "-A",
        "--account-workers",
        type=int,
        default=None,
        metavar="N",
        help="多账号并发数。不指定时按 --speed 取值（eco:3，最大 20）。",
    )
    parser.add_argument(
        "--speed",
        default=DEFAULT_SPEED,
        choices=["eco", "balanced", "fast", "turbo"],
        help=(
            "速度档位（默认 eco 保守，尽量不触碰限流）:"
            "eco=保守，balanced=略微偏快，fast=快速档，turbo=不额外限速。"
            "显式指定的 -W/-A/-i 优先于档位。"
        ),
    )
    parser.add_argument(
        "-c",
        "--conservative",
        action="store_true",
        help="保守限流模式（等价于 --speed eco，兼容旧用法）。",
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
        help="Cloudflare API 429/可重试状态码/网络临时错误的最大重试次数（默认 5）。",
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
    parser.add_argument(
        "-P",
        "--proxy",
        action="append",
        default=None,
        metavar="URL",
        help="出口代理，可多次使用（例如 -P http://127.0.0.1:7897）。仅支持 http/https；URL 中的账号口令只用于连接，不会写入日志。",
    )
    parser.add_argument(
        "--proxy-file",
        default=None,
        metavar="PATH",
        help="代理文件路径，每行一个代理 URL（# 注释忽略），与 -P 合并使用。",
    )
    parser.add_argument(
        "--proxy-mode",
        default=PROXY_DEFAULT_MODE,
        choices=["round-robin", "sticky", "failover"],
        help="多代理调度：round-robin 逐请求轮转（默认），sticky 每线程固定，failover 仅故障切换。",
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
        "--list-zones",
        action="store_true",
        help="列出所有账号下的 zone（域名），默认只看 active 状态；可用 --zones-output 导出 CSV。",
    )
    parser.add_argument(
        "--zones-output",
        default=None,
        metavar="PATH",
        help="--list-zones 的 CSV 输出路径（UTF-8-SIG，Excel 可直接打开）。缺省时打印到屏幕。",
    )
    parser.add_argument(
        "--zone-status",
        default="active",
        choices=["active", "all"],
        help="--list-zones 的 zone 状态过滤：active（默认，即正常/激活）或 all（全部）。",
    )
    parser.add_argument(
        "--list-dns",
        default=None,
        metavar="ZONE",
        help="列出指定 zone 的 DNS 记录（配合 --json 输出 JSON，否则打印表格）。",
    )
    parser.add_argument(
        "--provision",
        action="store_true",
        help="域名配置模式：按表格对域名配置 DNS/邮箱转发/SSL/基础安全/加速。",
    )
    parser.add_argument(
        "--provision-table",
        default=None,
        metavar="PATH",
        help="--provision 的域名表格（domain,ip,forward,security,ssl,Note 或每行一个域名）。",
    )
    parser.add_argument(
        "--provision-output",
        default=None,
        metavar="PATH",
        help="--provision 结果 CSV 输出路径（UTF-8-SIG）。缺省打印到屏幕。",
    )
    parser.add_argument(
        "--server-ip",
        default="",
        metavar="IP",
        help="--provision 默认服务器 IP；无记录配置时生成 @ 与 www 两条 A/AAAA 记录。",
    )
    parser.add_argument(
        "--forward-email",
        default="",
        help="--provision 默认邮箱转发目标地址（缺省取配置 default_forward_email）。",
    )
    parser.add_argument(
        "--ssl-mode",
        default=None,
        choices=["flexible", "full", "strict", "off"],
        help="--provision 的 SSL 模式（缺省取配置 ssl_mode）。",
    )
    parser.add_argument(
        "--security",
        action="store_true",
        dest="security",
        default=None,
        help="--provision 启用基础安全设置（always_use_https/browser_check/security_level）。",
    )
    parser.add_argument(
        "--no-security",
        action="store_false",
        dest="security",
        help="--provision 不修改基础安全设置。",
    )
    parser.add_argument(
        "--optimize",
        action="store_true",
        dest="optimize",
        default=None,
        help="--provision 启用免费加速增益（默认开启）。",
    )
    parser.add_argument(
        "--no-optimize",
        action="store_false",
        dest="optimize",
        help="--provision 不修改加速设置。",
    )
    parser.add_argument(
        "--no-dns", action="store_true", help="--provision 不添加 DNS 记录。"
    )
    parser.add_argument(
        "--no-email", action="store_true", help="--provision 不配置邮箱转发。"
    )
    parser.add_argument(
        "--no-ssl", action="store_true", help="--provision 不设置 SSL 模式。"
    )
    parser.add_argument(
        "--no-activation", action="store_true", help="--provision 不等待 zone 激活。"
    )
    parser.add_argument(
        "--create-zone",
        action="store_true",
        help="--provision 时若账号中不存在该 zone 则在首个账号创建。",
    )
    parser.add_argument(
        "--activation-timeout",
        type=float,
        default=300.0,
        help="--provision 等待 zone 激活的最长秒数（默认 300）。",
    )
    parser.add_argument(
        "--activation-interval",
        type=float,
        default=5.0,
        help="--provision 激活轮询间隔秒数（默认 5）。",
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
    parser.add_argument(
        "--json",
        action="store_true",
        help="以 JSON 格式输出结果（目前主要用于 -f/--find-domain 与 --list-dns）。",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="把日志改道到 stderr，stdout 只保留 JSON/CSV 等机器可解析输出。",
    )
    parser.add_argument(
        "--failed-output",
        default=None,
        metavar="PATH",
        help="将失败/取消清单写入 CSV（UTF-8-SIG，含 account/zone/record/name/type/action/status/error 列），便于重跑补齐。默认不写文件。",
    )
    parser.add_argument(
        "--resume-from",
        default=None,
        metavar="PATH",
        help="从失败清单 CSV 重跑：仅处理清单中列出的域名；已完成项因内容一致会自动跳过，天然幂等。",
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


def collect_account_zones(
    account: dict,
    args: argparse.Namespace,
    stop_event: Event,
    rate_limiter: Optional[ApiRateLimiter],
    proxy_pool: Optional[ProxyPool] = None,
) -> tuple[str, list[dict], str]:
    """读取单个账号的 zone 列表并转换为 CSV 行。

    Returns:
        (account_name, rows, error_message)；error_message 为空表示读取成功。
    """
    name = account.get("name") or account.get("email") or "unknown"
    try:
        updater = CloudflareDNSUpdater(
            auth_method=account["auth_method"],
            api_token=account.get("token"),
            api_email=account.get("email"),
            api_key=account.get("key"),
            max_workers=args.workers,
            account_name=name,
            stop_event=stop_event,
            rate_limiter=get_account_rate_limiter(args, stop_event, rate_limiter),
            api_max_retries=args.api_max_retries,
            api_retry_base_delay=args.api_retry_base_delay,
            api_retry_max_sleep=args.api_retry_max_sleep,
            proxy_pool=proxy_pool,
        )
        zones = updater.get_all_zones()
    except KeyboardInterrupt:
        raise
    except Exception as exc:
        return name, [], str(exc)

    rows: list[dict] = []
    for zone in zones:
        status = str(zone.get("status") or "")
        if args.zone_status != "all" and status != args.zone_status:
            continue
        rows.append(
            {
                "account": name,
                "name": zone.get("name", ""),
                "status": status,
                "zone_id": zone.get("id", ""),
                "nameservers": ";".join(zone.get("name_servers") or []),
            }
        )
    return name, rows, ""


def run_list_zones_mode(
    accounts: list[dict],
    args: argparse.Namespace,
    stop_event: Event,
    rate_limiter: Optional[ApiRateLimiter],
    proxy_pool: Optional[ProxyPool] = None,
) -> int:
    """并发读取所有账号的 zone 列表，按状态过滤，可导出 CSV。

    退出码：0=全部账号读取成功，1=存在读取失败的账号。
    """
    account_total = len(accounts)
    all_rows: list[dict] = []
    errors: list[tuple[str, str]] = []
    print_lock = Lock()

    def _one(index: int, account: dict) -> tuple[str, list[dict], str]:
        name = account.get("name") or account.get("email") or "unknown"
        with print_lock:
            log_print(
                f"[ZONES] [{index}/{account_total}] 读取账号 {name} 的 zone 列表 ..."
            )
        return collect_account_zones(
            account, args, stop_event, rate_limiter, proxy_pool
        )

    max_workers = max(1, int(args.account_workers or 1))
    executor = ThreadPoolExecutor(max_workers=max_workers)
    futures = {
        executor.submit(_one, idx, account): account
        for idx, account in enumerate(accounts, start=1)
    }
    try:
        for future in as_completed(futures):
            name, rows, err = future.result()
            if err:
                errors.append((name, err))
                with print_lock:
                    log_print(f"[ZONES] 账号 {name} 读取失败: {err}")
            else:
                all_rows.extend(rows)
                with print_lock:
                    log_print(
                        f"[ZONES] 账号 {name}: {len(rows)} 个 zone（状态={args.zone_status}）"
                    )
    except KeyboardInterrupt:
        # 中断时先广播停止信号，再取消排队任务；已开始的账号读取线程会在
        # 下一次 stop_event 检查处尽快退出，随后向上抛出由主流程统一收尾。
        stop_event.set()
        cancel_pending_futures(futures)
        executor.shutdown(wait=True, cancel_futures=True)
        log_print("[ZONES] 已中断，停止读取 zone。", level=logging.WARNING)
        raise
    finally:
        executor.shutdown(wait=True)

    if args.zones_output and not stop_event.is_set():
        write_zones_csv(args.zones_output, all_rows)
        log_print(f"[ZONES] 已写入 CSV: {args.zones_output}（{len(all_rows)} 行）")
    else:
        log_print("account\tname\tstatus\tzone_id\tnameservers")
        for row in all_rows:
            log_print(
                f"{row['account']}\t{row['name']}\t{row['status']}\t"
                f"{row['zone_id']}\t{row['nameservers']}"
            )

    log_print(
        f"[ZONES] 汇总: 账号 {account_total} 个，成功 "
        f"{account_total - len(errors)}，失败 {len(errors)}，"
        f"zone {len(all_rows)} 个（状态={args.zone_status}）。"
    )
    return 1 if errors else 0


@dataclass
class ZoneProvisionOptions:
    """单个 zone 的配置选项（供 --provision 与外部编排复用）。"""

    records: list[dict] = field(default_factory=list)
    forward_email: str = ""
    ssl_mode: str = ""
    do_dns: bool = True
    do_activation: bool = True
    do_email: bool = True
    do_ssl: bool = True
    do_security: bool = True
    do_optimize: bool = True
    activation_timeout: float = 300.0
    activation_interval: float = 5.0
    on_tick: Optional[Callable[[str, float], None]] = None
    allow_multi_value: bool = False
    # 详情日志：逐条打印 DNS 记录（名/类型/内容/状态）与邮箱各步骤/所需记录。
    verbose: bool = False


def _zone_is_active(updater: CloudflareDNSUpdater, zone_id: str) -> bool:
    """查询 zone 是否已激活。

    查询失败或无状态字段时返回 True（走原逻辑，由各步骤 API 报错为准），
    避免一次查询抖动导致整站跳过。
    """
    try:
        zone = updater.get_zone(zone_id) or {}
    except Exception:  # noqa: BLE001
        return True
    status = str((zone.get("result") or {}).get("status") or "").lower()
    return status in ("", "active")


def provision_zone(
    updater: CloudflareDNSUpdater,
    zone_id: str,
    zone_name: str,
    domain: str,
    options: ZoneProvisionOptions,
) -> dict[str, str]:
    """对一个已存在的 zone 执行 DNS/激活/邮箱/SSL/安全/加速配置。

    返回状态字典(activation/record_status/email_status/ssl_status/security_status/error)。
    所有步骤均容错，单项失败不影响其它步骤。邮箱步骤要求 zone 为 active，
    未激活时记 `deferred:requires-active-zone`（待激活后重跑补配），不记 error。
    """
    result: dict[str, str] = {
        "activation": "skipped",
        "record_status": "skipped",
        "email_status": "skipped",
        "ssl_status": "skipped",
        "security_status": "skipped",
        "error": "",
    }

    if options.do_dns:
        if options.records:
            statuses: list[str] = []
            records_cache: dict = {}
            for record in options.records:
                name = str(record.get("name", "@"))
                record_type = str(record.get("type", "A"))
                content = str(record.get("content", ""))
                status, msg = updater.ensure_dns_record(
                    zone_id,
                    zone_name,
                    name,
                    record_type,
                    content,
                    proxied=bool(record.get("proxied", False)),
                    ttl=int(record.get("ttl", 1) or 1),
                    priority=record.get("priority"),
                    allow_multi=options.allow_multi_value,
                    _records_cache=records_cache,
                )
                statuses.append(f"{name}:{status}")
                if options.verbose:
                    detail = f"（{msg}）" if msg else ""
                    log_print(
                        f"      [DNS] {zone_name} {record_type} {name} -> {content} "
                        f"[{status}]{detail}"
                    )
            result["record_status"] = ";".join(statuses)
        else:
            result["record_status"] = "no-records"

    if options.do_activation:
        try:
            activated, status = updater.wait_zone_active(
                zone_id,
                timeout=options.activation_timeout,
                interval=options.activation_interval,
                on_tick=options.on_tick,
            )
            result["activation"] = "active" if activated else f"pending:{status}"
        except Exception as exc:  # noqa: BLE001
            result["activation"] = f"error:{exc}"

    if options.do_email:
        if options.forward_email:
            # Email Routing 要求 zone 为 active；pending 时硬调只会吃 403
            # (code 2009)，故先查状态，未激活则延期，待激活后重跑补配。
            if _zone_is_active(updater, zone_id):
                try:
                    status, message, records = updater.configure_email_routing(
                        zone_id, zone_name, options.forward_email
                    )
                    result["email_status"] = (
                        status if status == "ok" else f"{status}:{message}"
                    )
                    if options.verbose:
                        for item in records:
                            log_print(f"      [邮箱] {zone_name} {item}")
                        log_print(
                            f"      [邮箱] {zone_name} 结果: {status}"
                            + (f"（{message}）" if message else "")
                        )
                except Exception as exc:  # noqa: BLE001
                    result["email_status"] = f"error:{exc}"
            else:
                result["email_status"] = "deferred:requires-active-zone"
                if options.verbose:
                    log_print(
                        f"      [邮箱] {zone_name} 暂缓: zone 未激活，"
                        "待激活后由回访补配"
                    )
        else:
            result["email_status"] = "no-forward-email"

    if options.do_ssl:
        if options.ssl_mode:
            try:
                updater.update_zone_setting(zone_id, "ssl", options.ssl_mode)
                result["ssl_status"] = options.ssl_mode
            except Exception as exc:  # noqa: BLE001
                result["ssl_status"] = f"error:{exc}"
        else:
            result["ssl_status"] = "no-ssl-mode"

    if options.do_security or options.do_optimize:
        settings: dict[str, Any] = {}
        if options.do_security:
            settings.update(PROVISION_BASIC_SECURITY)
        if options.do_optimize:
            settings.update(PROVISION_SPEED)
        setting_results = updater.apply_zone_settings(zone_id, settings)
        ok = sum(1 for _s, status, _m in setting_results if status == "ok")
        errs = [f"{s}:{m}" for s, status, m in setting_results if status != "ok"]
        result["security_status"] = f"ok={ok}/{len(setting_results)}" + (
            ";errors=" + "|".join(errs) if errs else ""
        )

    return result


def build_records_for_domain(
    domain: str,
    table: dict[str, dict[str, str]],
    server_ip: str,
    proxied: bool,
    ttl: int,
) -> list[dict]:
    """按旧表格/默认 IP 生成典型记录：@ 与 www 的 A/AAAA。"""
    ip = (table.get(domain, {}) or {}).get("ip") or server_ip
    if not ip:
        return []
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


def run_provision_mode(
    accounts: list[dict],
    args: argparse.Namespace,
    stop_event: Event,
    rate_limiter: Optional[ApiRateLimiter],
    proxy_pool: Optional[ProxyPool] = None,
) -> int:
    """域名配置模式:对表格中的域名配置 DNS/邮箱/SSL/安全/加速。

    先在各账号中定位 zone(未找到且 --create-zone 时在首个账号创建),再逐项配置。
    退出码:0=全部成功,1=存在失败或未找到的域名。
    """
    table = load_provision_table(args.provision_table)
    if not table:
        log_print(f"--provision 表格为空或不存在: {args.provision_table}")
        return 1

    globals_ = load_cf_globals(args.config)
    forward_default = args.forward_email or str(
        globals_.get("default_forward_email") or ""
    )
    ssl_default = args.ssl_mode or str(globals_.get("ssl_mode") or "")
    security_default = bool(globals_.get("security_mode", 0))
    do_security = security_default if args.security is None else bool(args.security)
    do_optimize = True if args.optimize is None else bool(args.optimize)

    print_lock = Lock()

    def _make_updater(account: dict) -> CloudflareDNSUpdater:
        name = account.get("name") or account.get("email") or "unknown"
        return CloudflareDNSUpdater(
            auth_method=account["auth_method"],
            api_token=account.get("token"),
            api_email=account.get("email"),
            api_key=account.get("key"),
            max_workers=args.workers,
            account_name=name,
            rate_limiter=get_account_rate_limiter(args, stop_event, rate_limiter),
            api_max_retries=args.api_max_retries,
            api_retry_base_delay=args.api_retry_base_delay,
            api_retry_max_sleep=args.api_retry_max_sleep,
            proxy_pool=proxy_pool,
        )

    # 建立 zone -> 账号 映射(每账号只拉一次 zone 列表)
    updaters: dict[str, CloudflareDNSUpdater] = {}
    zone_owner: dict[str, tuple[dict, dict]] = {}
    for account in accounts:
        updater = _make_updater(account)
        name = updater.account_name
        updaters[name] = updater
        try:
            zones = updater.get_all_zones()
        except Exception as exc:  # noqa: BLE001
            with print_lock:
                log_print(f"[PROVISION] 账号 {name} 读取 zone 失败: {exc}")
            continue
        for zone in zones:
            zone_name = str(zone.get("name", "")).lower()
            if zone_name and zone_name not in zone_owner:
                zone_owner[zone_name] = (account, zone)

    results: list[dict[str, str]] = []
    for domain, row_cfg in table.items():
        owner = zone_owner.get(domain)
        zone_status = ""
        if owner is None:
            if not args.create_zone:
                results.append(
                    {
                        "account": "",
                        "domain": domain,
                        "zone_id": "",
                        "zone_status": "not-found",
                        "activation": "skipped",
                        "record_status": "skipped",
                        "email_status": "skipped",
                        "ssl_status": "skipped",
                        "security_status": "skipped",
                        "error": "账号中未找到该 zone（可用 --create-zone 新建）",
                        "timestamp": utc_now_iso(),
                    }
                )
                continue
            first = accounts[0]
            updater = updaters.get(
                first.get("name") or first.get("email") or "unknown"
            ) or _make_updater(first)
            try:
                created = updater.create_zone(domain)
                zone = created.get("result", {}) or {}
                owner = (first, zone)
                zone_status = str(zone.get("status", "created"))
            except Exception as exc:  # noqa: BLE001
                results.append(
                    {
                        "account": updater.account_name,
                        "domain": domain,
                        "zone_id": "",
                        "zone_status": "create-failed",
                        "activation": "skipped",
                        "record_status": "skipped",
                        "email_status": "skipped",
                        "ssl_status": "skipped",
                        "security_status": "skipped",
                        "error": f"创建 zone 失败: {exc}",
                        "timestamp": utc_now_iso(),
                    }
                )
                continue

        owner_account, zone = owner
        account_name = (
            owner_account.get("name") or owner_account.get("email") or "unknown"
        )
        updater = updaters.get(account_name) or _make_updater(owner_account)
        zone_id = str(zone.get("id", ""))
        zone_name = str(zone.get("name") or domain)
        if not zone_status:
            zone_status = str(zone.get("status", ""))

        effective_ip = args.server_ip or str(
            owner_account.get("default_server_ip") or ""
        )
        records = build_records_for_domain(
            domain,
            table,
            effective_ip,
            not args.no_proxied,
            args.ttl,
        )
        options = ZoneProvisionOptions(
            records=records,
            forward_email=row_cfg.get("forward") or forward_default,
            ssl_mode=row_cfg.get("ssl") or ssl_default,
            do_dns=not args.no_dns,
            do_activation=not args.no_activation,
            do_email=not args.no_email,
            do_ssl=bool(row_cfg.get("ssl") or ssl_default) and not args.no_ssl,
            do_security=do_security,
            do_optimize=do_optimize,
            activation_timeout=args.activation_timeout,
            activation_interval=args.activation_interval,
            allow_multi_value=args.allow_multi_value,
        )
        statuses = provision_zone(updater, zone_id, zone_name, domain, options)
        record = {
            "account": account_name,
            "domain": domain,
            "zone_id": zone_id,
            "zone_status": zone_status,
            "timestamp": utc_now_iso(),
        }
        record.update(statuses)
        results.append(record)
        with print_lock:
            log_print(
                f"[PROVISION] {domain}: zone={zone_status}, "
                f"dns={record['record_status']}, email={record['email_status']}, "
                f"ssl={record['ssl_status']}"
            )

    if args.provision_output:
        write_provision_csv(args.provision_output, results)
        log_print(
            f"[PROVISION] 已写入 CSV: {args.provision_output}（{len(results)} 行）"
        )
    failed = sum(
        1
        for r in results
        if r.get("error") or r.get("zone_status") in {"not-found", "create-failed"}
    )
    log_print(f"[PROVISION] 汇总: 域名 {len(results)} 个，失败/未找到 {failed} 个。")
    return 1 if failed else 0


def run_list_dns_mode(
    accounts: list[dict],
    args: argparse.Namespace,
    stop_event: Event,
    rate_limiter: Optional[ApiRateLimiter],
    proxy_pool: Optional[ProxyPool] = None,
) -> int:
    """列出指定 zone 的 DNS 记录；支持 --json。退出码 0=成功，1=未找到或失败。"""
    zone = (args.list_dns or "").strip()
    target = (get_main_domain_name_from_str(zone) or zone).lower()
    for account in accounts:
        name = account.get("name") or account.get("email") or "unknown"
        try:
            updater = CloudflareDNSUpdater(
                auth_method=account["auth_method"],
                api_token=account.get("token"),
                api_email=account.get("email"),
                api_key=account.get("key"),
                max_workers=args.workers,
                account_name=name,
                rate_limiter=get_account_rate_limiter(args, stop_event, rate_limiter),
                api_max_retries=args.api_max_retries,
                api_retry_base_delay=args.api_retry_base_delay,
                api_retry_max_sleep=args.api_retry_max_sleep,
                proxy_pool=proxy_pool,
            )
            found = updater.get_zone_by_name(target)
            if not found:
                continue
            zone_id = found.get("id")
            if not isinstance(zone_id, str) or not zone_id:
                log_print(f"[DNS] 账号 {name} 的 zone {target} 缺少有效 zone_id")
                continue
            records = updater.get_dns_records(zone_id, record_type=None)
        except Exception as exc:  # noqa: BLE001
            log_print(f"[DNS] 账号 {name} 查询 {target} 失败: {exc}")
            continue
        if args.json:
            import json

            print(
                json.dumps(
                    {
                        "account": name,
                        "zone": target,
                        "zone_id": zone_id,
                        "records": records,
                    },
                    ensure_ascii=False,
                    indent=2,
                )
            )
        else:
            log_print(f"[DNS] 账号 {name}, zone={target}, 记录数={len(records)}")
            for record in records:
                prox = " (proxied)" if record.get("proxied") else ""
                log_print(
                    f"  {str(record.get('type', '')):6} "
                    f"{str(record.get('name', '')):<32} -> "
                    f"{record.get('content', '')}{prox}"
                )
        return 0
    log_print(f"[DNS] 未在账号中找到 zone: {target}")
    return 1


def run_find_mode(
    accounts: list[dict],
    domain: str,
    account_workers: int,
    zone_workers: int,
    stop_event: Event,
    rate_limiter: Optional[ApiRateLimiter],
    args: argparse.Namespace,
    proxy_pool: Optional[ProxyPool] = None,
) -> int:
    """并发检查某个域名/zone 是否存在于多个账号中。"""
    print_lock = Lock()
    target_domain = get_main_domain_name_from_str(domain) or domain.strip().lower()
    account_total = len(accounts)

    def _find_one(account: dict, account_index: int) -> tuple[str, bool, str, dict]:
        """返回账号名、是否存在、错误信息和含账号上下文的查询详情。"""
        name = account.get("name") or account.get("email") or "unknown"
        email = account.get("email") or ""
        identity = format_account_identity(account, account_index, account_total)
        started_at = time.monotonic()
        with print_lock:
            log_print(f"[CHECK] {identity}, domain={target_domain}")
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
                proxy_pool=proxy_pool,
            )
            exists = updater.zone_exists(target_domain)
            zone_info = {}
            detail_warnings: list[str] = []
            if exists:
                # 尝试获取 zone 详细信息（记录数等）
                try:
                    all_zones = updater.get_all_zones()
                    for z in all_zones:
                        if z.get("name", "").lower() == target_domain:
                            zone_id = z.get("id")
                            if not isinstance(zone_id, str) or not zone_id:
                                continue
                            zone_info = {
                                "zone_id": zone_id,
                                "name": z.get("name"),
                                "status": z.get("status"),
                                "name_servers": z.get("name_servers", []),
                            }
                            try:
                                records = updater.get_dns_records(
                                    zone_id, record_type="ALL"
                                )
                                zone_info["record_count"] = len(records)
                                # 收集记录摘要（前 10 条）
                                record_list = []
                                for r in records[:10]:
                                    record_list.append(
                                        {
                                            "type": r.get("type"),
                                            "name": r.get("name"),
                                            "content": r.get("content"),
                                            "proxied": r.get("proxied", False),
                                        }
                                    )
                                zone_info["records"] = record_list
                                if len(records) > 10:
                                    zone_info["records_truncated"] = True
                            except Exception as exc:
                                zone_info["record_count"] = "?"
                                detail_warnings.append(f"读取 DNS 记录详情失败: {exc}")
                            break
                except Exception as exc:
                    detail_warnings.append(f"读取 zone 详情失败: {exc}")
            return (
                name,
                exists,
                "",
                {
                    "email": email,
                    "identity": identity,
                    "elapsed": time.monotonic() - started_at,
                    "detail_warnings": detail_warnings,
                    "zone_info": zone_info,
                },
            )
        except KeyboardInterrupt:
            return (
                name,
                False,
                "interrupted",
                {
                    "email": email,
                    "identity": identity,
                    "elapsed": time.monotonic() - started_at,
                },
            )
        except Exception as exc:
            return (
                name,
                False,
                str(exc),
                {
                    "email": email,
                    "identity": identity,
                    "elapsed": time.monotonic() - started_at,
                },
            )

    log_print(f"快速查找域名: {target_domain}，账号数: {len(accounts)}")
    found_results: list[dict] = []

    executor = ThreadPoolExecutor(max_workers=max(1, account_workers))
    pending: set[Future[Any]] = set()
    try:
        pending = {
            executor.submit(_find_one, account, account_index)
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
                name, exists, err, extra = future.result()
                identity = extra.get("identity") or f"name={name}"
                elapsed = float(extra.get("elapsed", 0.0))
                if err:
                    if err == "interrupted":
                        continue
                    log_print(
                        f"[ERR] {identity}, domain={target_domain}, "
                        f"elapsed={elapsed:.2f}s: {err}"
                    )
                    continue
                for warning in extra.get("detail_warnings", []):
                    log_print(
                        f"[WARN] {identity}, domain={target_domain}, "
                        f"elapsed={elapsed:.2f}s: {warning}"
                    )
                if exists:
                    zone_info = extra.get("zone_info", {})
                    email = extra.get("email", "")
                    result = {
                        "name": name,
                        "email": email,
                        "zone_info": zone_info,
                    }
                    found_results.append(result)

                    # 打印详细信息
                    rec_count = zone_info.get("record_count", "?")
                    ns_preview = ""
                    if zone_info.get("name_servers"):
                        ns_preview = f" NS={zone_info['name_servers'][0]}"
                    log_print(
                        f"[FOUND] {identity}, domain={target_domain}, "
                        f"records={rec_count}{ns_preview}, elapsed={elapsed:.2f}s"
                    )
                else:
                    log_print(
                        f"[MISS] {identity}, domain={target_domain}, "
                        f"elapsed={elapsed:.2f}s"
                    )
    except KeyboardInterrupt:
        stop_event.set()
        log_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止查询...")
    finally:
        if stop_event.is_set():
            cancel_pending_futures(pending)
        executor.shutdown(
            wait=not stop_event.is_set(), cancel_futures=bool(stop_event.is_set())
        )

    if stop_event.is_set():
        return 130

    log_print("\n查询结果:")
    if found_results:
        if args.json:
            import json

            output = {
                "domain": target_domain,
                "found": len(found_results),
                "results": [],
            }
            for r in found_results:
                item = {
                    "account": r["name"],
                    "email": r.get("email") or None,
                    "zone": r.get("zone_info", {}),
                }
                output["results"].append(item)
            print(json.dumps(output, ensure_ascii=False, indent=2))
        else:
            for r in found_results:
                name = r["name"]
                email = r.get("email", "")
                z = r.get("zone_info", {})
                line = f"- {name}"
                if email:
                    line += f"  email={email}"
                if z.get("zone_id"):
                    line += f"  zone_id={z['zone_id']}"
                if z.get("record_count") is not None:
                    line += f"  records={z['record_count']}"
                if z.get("status"):
                    line += f"  status={z['status']}"
                log_print(line)
                # 打印记录摘要
                recs = z.get("records", [])
                if recs:
                    for rec in recs[:5]:
                        prox = " (proxied)" if rec.get("proxied") else ""
                        log_print(
                            f"    {rec['type']:5} {rec['name']:<30} -> {rec['content']}{prox}"
                        )
                    if len(recs) > 5 or z.get("records_truncated"):
                        log_print(f"    ... ({z.get('record_count', '?')} total)")
        return 0

    if args.json:
        import json

        print(
            json.dumps(
                {"domain": target_domain, "found": 0, "results": []}, ensure_ascii=False
            )
        )
    else:
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
    proxy_pool: Optional[ProxyPool] = None,
) -> tuple[str, bool, str, list[dict[str, Any]]]:
    """在单个账号中执行更新或删除操作。

    返回 (账号名, 是否成功, 错误信息, 失败清单行)。
    成功判定：无 errors 且无 cancelled；中断返回 interrupted，由主循环汇总。
    """
    name = account.get("name") or account.get("email") or "unknown"
    try:
        account_rate_limiter = get_account_rate_limiter(
            args,
            stop_event,
            rate_limiter,
        )
        resume_entries = getattr(args, "_resume_entries", None)
        resume_zones = resume_filter_for_account(resume_entries, name)
        # 传递命令行直接指定的域名（--domain）
        explicit_domains = getattr(args, "domain", None)
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
            explicit_domains=explicit_domains,
            proxy_pool=proxy_pool,
        )
        updater._safe_print(
            f"\n=== [账号 {account_index}/{account_total}] 开始处理账号: {name} ==="
        )

        # 传递 --domain 指定的域名列表
        explicit_domains = getattr(args, "domain", None)
        backup_dir = getattr(args, "backup_dir", None)
        mutating = bool(
            args.delete_wildcard
            or args.delete_ip
            or args.delete_zone
            or args.add_domain
            or args.add_record
            or args.new_content
            or args.set_proxied is not None
            or args.set_ttl is not None
        )
        if backup_dir and mutating and not args.dry_run:
            backup_ok, backup_msg = updater.batch_backup(
                backup_dir,
                whitelist=whitelist,
                explicit_domains=explicit_domains,
                resume_zones=resume_zones,
            )
            if not backup_ok:
                return (
                    name,
                    False,
                    backup_msg,
                    [
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
                            "error": backup_msg,
                            "timestamp": utc_now_iso(),
                        }
                    ],
                )
        if args.delete_wildcard:
            batch_result = updater.batch_delete_wildcard(
                whitelist=whitelist,
                record_type=args.record_type,
                old_content=args.old_content,
                dry_run=args.dry_run,
                explicit_domains=explicit_domains,
                resume_zones=resume_zones,
            )
        elif args.delete_ip:
            batch_result = updater.batch_delete_ip(
                delete_ip=args.delete_ip,
                whitelist=whitelist,
                record_type=args.record_type,
                dry_run=args.dry_run,
                include_subdomains=not args.no_subdomains,
                explicit_domains=explicit_domains,
                resume_zones=resume_zones,
            )
        elif args.delete_zone:
            delete_completely = args.delete_zone == "full"
            batch_result = updater.batch_delete_zone(
                whitelist=whitelist,
                dry_run=args.dry_run,
                delete_zone_completely=delete_completely,
                explicit_domains=explicit_domains,
                resume_zones=resume_zones,
            )
        elif args.add_domain or args.add_record:
            # 默认启用代理，除非用户显式使用 --no-proxied
            use_proxied = not getattr(args, "no_proxied", False)

            batch_result = updater.batch_add_domain_and_records(
                add_domain=args.add_domain,
                add_records=args.add_record,
                proxied=use_proxied,
                ttl=args.ttl,
                dry_run=args.dry_run,
                explicit_domains=explicit_domains,
                resume_zones=resume_zones,
                allow_multi_value=args.allow_multi_value,
            )
        elif args.export:
            batch_result = updater.batch_export(
                export_dir=args.export_dir or "./cf_export",
                fmt=args.export,
                whitelist=whitelist,
                explicit_domains=explicit_domains,
                resume_zones=resume_zones,
            )
        elif args.set_proxied is not None or args.set_ttl is not None:
            batch_result = updater.batch_set_attrs(
                set_proxied=(args.set_proxied == "on")
                if args.set_proxied is not None
                else None,
                set_ttl=args.set_ttl,
                whitelist=whitelist,
                record_type=args.record_type,
                old_content=args.old_content,
                dry_run=args.dry_run,
                include_subdomains=not args.no_subdomains,
                explicit_domains=explicit_domains,
                resume_zones=resume_zones,
            )
        else:
            batch_result = updater.batch_update(
                new_content=args.new_content,
                old_content=args.old_content,
                whitelist=whitelist,
                record_type=args.record_type,
                dry_run=args.dry_run,
                include_subdomains=not args.no_subdomains,
                explicit_domains=explicit_domains,
                resume_zones=resume_zones,
            )

        failure_rows = failure_rows_for_results(name, batch_result.results)

        if stop_event.is_set():
            return name, False, "interrupted", failure_rows

        pending_count = batch_result.stats.errors + batch_result.stats.cancelled
        if pending_count > 0:
            return (
                name,
                False,
                f"账号内存在 {batch_result.stats.errors} 个错误、"
                f"{batch_result.stats.cancelled} 个取消",
                failure_rows,
            )

        return name, True, "", failure_rows
    except KeyboardInterrupt:
        return (
            name,
            False,
            "interrupted",
            [
                {
                    "account": name,
                    "zone": "",
                    "record_id": "",
                    "name": "",
                    "type": "ZONE",
                    "old_content": "",
                    "new_content": "",
                    "action": "batch",
                    "status": "cancelled",
                    "attempts": 1,
                    "error": "账号任务被中断（zone 列表未知，需整账号重跑）",
                    "timestamp": utc_now_iso(),
                }
            ],
        )
    except Exception as exc:
        # 账号级硬失败（如 zone 列表拉取失败）：zone 未知，记整账号哨兵行，
        # 重跑时该账号全量执行，保证不遗漏。
        return (
            name,
            False,
            str(exc),
            [
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
                    "error": f"账号级失败（需整账号重跑）: {exc}",
                    "timestamp": utc_now_iso(),
                }
            ],
        )


def resolve_speed_values(
    speed: str,
    workers: Optional[int],
    account_workers: Optional[int],
    request_interval: Optional[float],
) -> tuple[int, int, float]:
    """纯函数：按档位填充未显式指定的并发/间隔，返回 (workers, account_workers, interval)。

    显式指定的值优先（仅做合法性校验，不按档位下调）。
    """
    preset = SPEED_PRESETS[speed]
    resolved_workers = int(preset["workers"]) if workers is None else int(workers)
    resolved_accounts = (
        int(preset["account_workers"])
        if account_workers is None
        else int(account_workers)
    )
    resolved_interval = (
        float(preset["request_interval"])
        if request_interval is None
        else float(request_interval)
    )
    return resolved_workers, resolved_accounts, resolved_interval


def configure_rate_limit_args(args: argparse.Namespace) -> None:
    """
    配置速度档位、限流与 API 重试参数。

    默认 --speed eco：尽量不触碰 Cloudflare 限流（每账号约 2 请求/秒）。
    着急时用 --speed balanced/fast/turbo 提速；显式指定的 -W/-A/-i
    优先于档位。fast/turbo 会明确提示 429 风险，失败项进清单重跑。
    """
    speed = args.speed
    if args.conservative:
        if speed != "eco":
            log_print("--conservative 与 --speed 冲突，已按保守（eco）执行")
        speed = "eco"
        args.speed = "eco"
    if speed not in SPEED_PRESETS:
        log_print(f"--speed 仅支持 {sorted(SPEED_PRESETS)}")
        sys.exit(1)

    if args.request_interval is not None and args.request_interval < 0:
        log_print("--request-interval 不能为负数")
        sys.exit(1)
    if args.workers is not None and args.workers < 1:
        log_print("--workers 至少为 1")
        sys.exit(1)
    if args.account_workers is not None and args.account_workers < 1:
        log_print("--account-workers 至少为 1")
        sys.exit(1)

    args.workers, args.account_workers, args.request_interval = resolve_speed_values(
        speed, args.workers, args.account_workers, args.request_interval
    )

    if args.workers > HARD_MAX_WORKERS:
        log_print(f"线程数过高，已自动调整为 {HARD_MAX_WORKERS}")
        args.workers = HARD_MAX_WORKERS
    if args.account_workers > HARD_MAX_WORKERS:
        log_print(f"账号并发数过高，已自动调整为 {HARD_MAX_WORKERS}")
        args.account_workers = HARD_MAX_WORKERS

    if speed in {"fast", "turbo"}:
        log_print(
            f"速度档位 {speed}：请求密度高，触发 429/限流的概率明显上升；"
            "失败与取消项会记入失败清单，请配合 --failed-output/--resume-from 重跑补齐。"
        )
    log_print(
        f"速度档位: {speed}，account-workers={args.account_workers}，"
        f"workers={args.workers}，request-interval={args.request_interval}s"
    )

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


def build_proxy_pool(args: argparse.Namespace) -> Optional[ProxyPool]:
    """根据 -P/--proxy 与 --proxy-file 构建全进程共享代理池，无配置返回 None。"""
    urls: list[str] = []
    if getattr(args, "proxy", None):
        for raw in args.proxy:
            try:
                urls.append(validate_proxy_url(raw))
            except ValueError as exc:
                log_print(f"参数错误: {exc}")
                sys.exit(1)
    if getattr(args, "proxy_file", None):
        urls.extend(load_proxy_file(args.proxy_file))
    if not urls:
        return None
    try:
        pool = ProxyPool(urls, mode=args.proxy_mode)
    except ValueError as exc:
        log_print(f"参数错误: {exc}")
        sys.exit(1)
    log_print(
        f"出口代理已启用: 模式={pool.mode}，数量={len(pool.urls)}，"
        f"列表={pool.sanitized_list()}"
    )
    return pool


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
    if args.list_dns and (
        args.find_domain
        or args.new_content
        or args.delete_wildcard
        or args.delete_ip
        or args.delete_zone
        or args.export
        or args.set_proxied is not None
        or args.set_ttl is not None
        or args.add_domain
        or args.add_record
        or args.list_zones
        or args.provision
    ):
        log_print("--list-dns 不能与其他模式同时使用")
        sys.exit(1)

    if args.provision and not args.provision_table:
        log_print("--provision 需要配合 --provision-table 指定域名表格")
        sys.exit(1)
    if args.provision and (
        args.find_domain
        or args.new_content
        or args.delete_wildcard
        or args.delete_ip
        or args.delete_zone
        or args.export
        or args.set_proxied is not None
        or args.set_ttl is not None
        or args.add_domain
        or args.add_record
        or args.list_zones
    ):
        log_print("--provision 不能与其他更新/删除/添加/导出/查询模式同时使用")
        sys.exit(1)

    if args.list_zones and (
        args.find_domain
        or args.new_content
        or args.delete_wildcard
        or args.delete_ip
        or args.delete_zone
        or args.export
        or args.set_proxied is not None
        or args.set_ttl is not None
        or args.add_domain
        or args.add_record
    ):
        log_print("--list-zones 不能与其他更新/删除/添加/导出/设置模式同时使用")
        sys.exit(1)

    if args.find_domain and (
        args.new_content
        or args.delete_wildcard
        or args.delete_ip
        or args.delete_zone
        or args.export
        or args.set_proxied is not None
        or args.set_ttl is not None
    ):
        log_print("--find-domain 查询模式不能与更新/删除/导出/设置模式同时使用")
        sys.exit(1)

    destructive_modes = [
        bool(args.delete_wildcard),
        bool(args.delete_ip),
        bool(args.delete_zone),
    ]
    add_modes = [bool(args.add_domain), bool(args.add_record)]
    new_modes = [
        bool(args.new_content),
        bool(args.export),
        bool(args.set_proxied is not None or args.set_ttl is not None),
    ]

    if args.new_content and any(destructive_modes):
        log_print("更新模式不能与删除模式同时使用")
        sys.exit(1)

    if any(destructive_modes) and any(add_modes):
        log_print("删除模式不能与添加域名/记录模式同时使用")
        sys.exit(1)

    if sum(destructive_modes) > 1:
        log_print("--delete-wildcard、--delete-ip 和 --delete-zone 不能同时使用")
        sys.exit(1)

    if sum(new_modes) > 1 or (
        any(new_modes) and (any(destructive_modes) or any(add_modes))
    ):
        log_print(
            "更新、导出、属性设置、删除、添加模式之间不能同时使用，"
            "请分次执行（建议先 --export 备份）"
        )
        sys.exit(1)

    if sum(add_modes) == 1 and not (args.add_domain or args.add_record):
        log_print("--add-domain 和 --add-record 建议同时使用或至少提供一个")
        # 不强制退出，允许单独使用

    if args.delete_ip and args.old_content:
        log_print(
            "--delete-ip 已经指定要删除的 IP，不能再同时使用 --old-ip/--old-content"
        )
        sys.exit(1)

    if args.set_ttl is not None and args.set_ttl < 1:
        log_print("--set-ttl 必须为正整数（1=自动）")
        sys.exit(1)

    if args.export and not args.export_dir:
        args.export_dir = "./cf_export"
        log_print(f"未指定 --export-dir，默认使用 {args.export_dir}")

    if args.new_content:
        try:
            # 提前校验一次，失败时无需启动线程。
            final_type = resolve_update_record_type(
                args.record_type, args.new_content, args.old_content
            )
            if is_ip_family_migration(args.old_content, args.new_content):
                old_type = record_type_for_ip_version(
                    get_ip_version(args.old_content) or 0
                )
                log_print(
                    f"更新模式记录类型: {old_type}->{final_type} (跨 IP 类型迁移)"
                )
            else:
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

    if args.delete_ip:
        try:
            final_type = resolve_delete_ip_record_type(args.delete_ip, args.record_type)
            log_print(
                f"删除指定 IP 记录模式，记录类型: {final_type}, delete_ip={args.delete_ip}"
            )
        except ValueError as exc:
            log_print(f"参数错误: {exc}")
            sys.exit(1)


def build_final_verdict(
    success: int,
    failed: int,
    cancelled_accounts: int,
    failure_rows: list[dict[str, Any]],
    interrupted: bool,
    failed_output: Optional[str],
    prog: str,
) -> tuple[int, list[str]]:
    """构建本次运行的最终结论（是否完美执行）。

    返回 (exit_code, 输出行)。判定标准：
    - 完美执行：无失败账号、无取消账号、无失败清单行、未被中断；
    - 否则明确给出失败/取消统计、主要原因 Top5 与重跑命令。
    """
    error_rows = [
        row for row in failure_rows if str(row.get("status", "")) != "cancelled"
    ]
    cancelled_rows = [
        row for row in failure_rows if str(row.get("status", "")) == "cancelled"
    ]
    lines = ["", "账号汇总:", f"- 成功: {success}", f"- 失败: {failed}"]
    if cancelled_accounts:
        lines.append(f"- 取消账号: {cancelled_accounts}")
    if failure_rows:
        lines.append(
            f"- 未完成条目: {len(failure_rows)}"
            f"（失败 {len(error_rows)}，取消 {len(cancelled_rows)}）"
        )

    causes = Counter()
    for row in failure_rows:
        action = str(row.get("action", "batch"))
        error = str(row.get("error", ""))[:100]
        causes[(action, error)] += 1

    rerun_hint: list[str] = []
    if failure_rows:
        if failed_output:
            rerun_hint = [
                f"失败清单: {failed_output}（共 {len(failure_rows)} 行）",
                "建议重跑（其余参数保持本次不变）:",
                f"{prog} --resume-from {failed_output}",
            ]
        else:
            rerun_hint = [
                "建议下次加 --failed-output <path> 生成清单后用 --resume-from 重跑。"
            ]

    if interrupted:
        lines.append(
            "[VERDICT] 任务被中断：未能完美执行，"
            f"成功 {success}，失败 {failed}，取消账号 {cancelled_accounts}，"
            f"未完成条目 {len(failure_rows)}。"
        )
        lines.extend(verdict_cause_lines(causes))
        lines.extend(rerun_hint)
        return 130, lines

    if failed == 0 and cancelled_accounts == 0 and not failure_rows:
        lines.append(
            "[VERDICT] 完美执行："
            f"{success} 个账号全部成功，无失败、无取消、无未完成条目。"
        )
        return 0, lines

    lines.append(
        "[VERDICT] 未完美执行："
        f"成功 {success}，失败 {failed}，取消账号 {cancelled_accounts}，"
        f"未完成条目 {len(failure_rows)}"
        f"（失败 {len(error_rows)}，取消 {len(cancelled_rows)}）。"
        "重试未能挽救的条目见失败清单。"
    )
    lines.extend(verdict_cause_lines(causes))
    lines.extend(rerun_hint)
    return 1, lines


def verdict_cause_lines(causes: Counter[tuple[str, str]]) -> list[str]:
    """将原因计数器转为 Top5 输出行。"""
    if not causes:
        return []
    lines = ["主要原因 Top:"]
    for (action, error), count in causes.most_common(5):
        lines.append(f"- [{action}] x{count}: {error}")
    return lines


def run_accounts_fanout(
    accounts: list[dict],
    args: argparse.Namespace,
    whitelist: Optional[list[str]],
    print_lock: Lock,
    stop_event: Event,
    rate_limiter: Optional[ApiRateLimiter],
    proxy_pool: Optional[ProxyPool] = None,
) -> tuple[int, int, list[dict[str, Any]], int]:
    """账号级 fan-out：返回 (成功数, 失败数, 失败清单行, 取消账号数)。

    中断时未开始的账号 future 会被取消并计数为取消，不计入失败；
    已返回 failure_rows 的账号（即使中断）仍会保留其清单行，保证可重跑。
    """
    success = 0
    failed = 0
    cancelled_accounts = 0
    failure_rows: list[dict[str, Any]] = []
    account_total = len(accounts)

    executor = ThreadPoolExecutor(max_workers=args.account_workers)
    future_to_account: dict[Future[Any], dict] = {}
    pending: set[Future[Any]] = set()
    try:
        for account_index, account in enumerate(accounts, start=1):
            future = executor.submit(
                run_operation_for_account,
                account,
                account_index,
                account_total,
                args,
                whitelist,
                print_lock,
                stop_event,
                rate_limiter,
                proxy_pool,
            )
            future_to_account[future] = account
        pending = set(future_to_account)

        while pending and not stop_event.is_set():
            done, pending = wait(
                pending,
                timeout=0.5,
                return_when=FIRST_COMPLETED,
            )
            if not done:
                continue

            for future in done:
                name, ok, err, rows = future.result()
                failure_rows.extend(rows)
                if ok:
                    success += 1
                    log_print(f"[ACCOUNT-OK] {name}")
                else:
                    if err == "interrupted":
                        continue
                    failed += 1
                    log_print(f"[ACCOUNT-ERR] {name}: {err}")
    except KeyboardInterrupt:
        stop_event.set()
        log_print("\n[INTERRUPT] 收到 Ctrl+C，正在终止所有线程...")
    finally:
        if stop_event.is_set():
            cancel_pending_futures(pending)
            for future in pending:
                account = future_to_account.get(future, {})
                name = account.get("name") or account.get("email") or "unknown"
                if not future.done() or future.cancelled():
                    cancelled_accounts += 1
                    log_print(f"[ACCOUNT-CANCELLED] {name} 未执行（任务被取消）")
                else:
                    try:
                        res_name, ok, err, rows = future.result()
                        failure_rows.extend(rows)
                        if ok:
                            success += 1
                            log_print(f"[ACCOUNT-OK] {res_name}")
                        elif err != "interrupted":
                            failed += 1
                            log_print(f"[ACCOUNT-ERR] {res_name}: {err}")
                    except Exception as exc:
                        failed += 1
                        log_print(f"[ACCOUNT-ERR] {name}: {exc}")
        executor.shutdown(
            wait=not stop_event.is_set(), cancel_futures=bool(stop_event.is_set())
        )

    return success, failed, failure_rows, cancelled_accounts


def write_failure_report(
    args: argparse.Namespace, failure_rows: list[dict[str, Any]]
) -> None:
    """按 --failed-output 写失败清单；无清单时给出重跑提示。"""
    if not failure_rows:
        return
    if args.failed_output:
        write_failure_csv(args.failed_output, failure_rows)
        log_print(
            f"\n失败清单已写入: {args.failed_output}（共 {len(failure_rows)} 行），"
            "可用 --resume-from 重跑补齐。"
        )
    else:
        log_print(
            f"\n本次有 {len(failure_rows)} 条未完成（失败/取消），"
            "建议下次加 --failed-output <path> 生成清单后用 --resume-from 重跑。"
        )


def main() -> None:
    args = parse_args()
    global QUIET
    QUIET = bool(getattr(args, "quiet", False))
    configure_logging(args.log_file, args.log_level, args.log_overwrite)
    configure_rate_limit_args(args)
    log_startup(args)
    validate_worker_args(args)
    validate_action_args(args)

    stop_event = Event()
    install_ctrl_c_handler(stop_event)
    rate_limiter = build_shared_rate_limiter(args, stop_event)
    proxy_pool = build_proxy_pool(args)
    if args.request_interval and args.request_interval > 0:
        scope_text = "全进程共享" if args.rate_limit_scope == "global" else "每账号独立"
        log_print(
            f"API 限速已启用: scope={args.rate_limit_scope}({scope_text}), "
            f"相邻 Cloudflare API 请求至少间隔 {args.request_interval:.3f}s；"
            f"官方常规限额参考 {CF_GLOBAL_RATE_LIMIT_PER_5_MIN}/5min。"
        )

    accounts = build_accounts(args)

    # 重跑清单：提前加载，账号/zone 过滤在 run_operation_for_account 内完成。
    if getattr(args, "resume_from", None):
        try:
            args._resume_entries = load_resume_entries(args.resume_from)
        except FileNotFoundError:
            log_print(f"重跑文件不存在: {args.resume_from}")
            sys.exit(1)
        except ValueError as exc:
            log_print(f"重跑文件错误: {exc}")
            sys.exit(1)
        log_print(
            f"已加载重跑清单: {args.resume_from}（{len(args._resume_entries)} 行），"
            "仅处理清单中的域名"
        )

    # 模式 0：列出可用账号。
    if args.list_accounts:
        list_accounts(accounts, show_secrets=args.show_secrets)
        sys.exit(0)

    # 模式 0.5：列出所有账号的 zone（域名），可导出 CSV。
    if args.list_zones:
        code = run_list_zones_mode(
            accounts=accounts,
            args=args,
            stop_event=stop_event,
            rate_limiter=rate_limiter,
            proxy_pool=proxy_pool,
        )
        sys.exit(code)

    # 模式 0.6：按表格配置域名（DNS/邮箱/SSL/安全/加速）。
    if args.provision:
        code = run_provision_mode(
            accounts=accounts,
            args=args,
            stop_event=stop_event,
            rate_limiter=rate_limiter,
            proxy_pool=proxy_pool,
        )
        sys.exit(code)

    # 模式 0.7：列出指定 zone 的 DNS 记录。
    if args.list_dns:
        code = run_list_dns_mode(
            accounts=accounts,
            args=args,
            stop_event=stop_event,
            rate_limiter=rate_limiter,
            proxy_pool=proxy_pool,
        )
        sys.exit(code)

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
            proxy_pool=proxy_pool,
        )
        sys.exit(code)

    # 模式 2：批量更新 / 删除 / 属性设置 / 导出记录。
    if (
        args.new_content
        or args.delete_wildcard
        or args.delete_ip
        or args.delete_zone
        or args.export
        or args.set_proxied is not None
        or args.set_ttl is not None
    ):
        whitelist: Optional[list[str]] = None
        if args.whitelist:
            whitelist = load_whitelist(args.whitelist)
            if not whitelist:
                log_print("白名单文件为空或未解析到有效域名")
                sys.exit(1)
            log_print(f"已加载白名单: {len(whitelist)}")

        print_lock = Lock()
        success, failed, failure_rows, cancelled_accounts = run_accounts_fanout(
            accounts, args, whitelist, print_lock, stop_event, rate_limiter, proxy_pool
        )
        write_failure_report(args, failure_rows)

        exit_code, verdict_lines = build_final_verdict(
            success,
            failed,
            cancelled_accounts,
            failure_rows,
            interrupted=bool(stop_event.is_set()),
            failed_output=args.failed_output,
            prog=os.path.basename(sys.argv[0]) or "cloudflare_dns_tool.py",
        )
        for line in verdict_lines:
            log_print(line)
        sys.exit(exit_code)

    # 模式 3：添加域名或 DNS 记录
    if args.add_domain or args.add_record:
        whitelist = None  # 添加模式通常不需要白名单
        print_lock = Lock()
        success, failed, failure_rows, cancelled_accounts = run_accounts_fanout(
            accounts, args, whitelist, print_lock, stop_event, rate_limiter, proxy_pool
        )
        write_failure_report(args, failure_rows)

        exit_code, verdict_lines = build_final_verdict(
            success,
            failed,
            cancelled_accounts,
            failure_rows,
            interrupted=bool(stop_event.is_set()),
            failed_output=args.failed_output,
            prog=os.path.basename(sys.argv[0]) or "cloudflare_dns_tool.py",
        )
        for line in verdict_lines:
            log_print(line)
        sys.exit(exit_code)

    # 默认模式：没有指定动作时列出账号，给用户操作提示。
    list_accounts(accounts, show_secrets=args.show_secrets)
    log_print("\n提示:")
    log_print("- 使用 -s/--select-account 可交互选择账号；-s <账号名> 可直接指定账号。")
    log_print(
        "- 使用 --new-ip/--new-content 进入更新模式；old/new IP 版本不同会自动迁移 A/AAAA。"
    )
    log_print("- 使用 --delete-wildcard 进入删除通配符记录模式。")
    log_print("- 使用 --delete-ip 删除所有指向指定 IP 的 A/AAAA 记录。")
    log_print("- 使用 --add-domain / --add-record 添加域名或 DNS 记录。")
    log_print("- 使用 -f/--find-domain 查询域名所在账号。")
    log_print("- 使用 --list-zones [--zones-output out.csv] 导出所有账号的 zone。")
    log_print("- 使用 --list-dns <zone> [--json] 查看某域名的 DNS 记录。")
    log_print("- 使用 --provision --provision-table table.csv 批量配置域名。")
    sys.exit(0)


if __name__ == "__main__":
    main()
