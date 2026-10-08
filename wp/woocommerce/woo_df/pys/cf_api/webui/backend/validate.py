# -*- coding: utf-8 -*-
"""提交校验（与 CLI 对齐）与单条记录校验（与 Cloudflare 网页版对齐）。

删除类必须限定范围（白名单或指定域名）；删域名必须填快照目录且 confirm=DELETE；
添加模式必须有目标；add_records 服务端预检 parse_add_record_spec。
"""

from __future__ import annotations

from typing import Any, Optional

RECORD_TYPES = {
    "A",
    "AAAA",
    "CNAME",
    "TXT",
    "MX",
    "NS",
    "CAA",
    "SRV",
    "PTR",
    "HTTPS",
    "SVCB",
}

PROXIABLE_TYPES = {"A", "AAAA", "CNAME"}


def _non_empty_str(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_job_params(params: dict[str, Any], accounts: list[str]) -> Optional[str]:
    """返回错误信息，无错误返回 None。params 与 jobs.run_operation_job 同源。"""
    if not accounts:
        return "至少选择一个账号"
    mode = str(params.get("mode", "update"))
    domains = list(params.get("domains") or [])
    whitelist = list(params.get("whitelist") or [])
    resume_entries = params.get("resume_entries")
    has_scope = bool(domains or whitelist or resume_entries)

    if mode == "update":
        if not _non_empty_str(params.get("new_content")):
            return "更新模式必须提供 new_content"
    elif mode == "delete_wildcard":
        if not has_scope:
            return "删除类必须限定范围：请指定域名或白名单"
    elif mode == "delete_ip":
        if not _non_empty_str(params.get("delete_ip")):
            return "删除指定 IP 模式必须提供 delete_ip"
        if not has_scope:
            return "删除类必须限定范围：请指定域名或白名单"
    elif mode == "delete_zone":
        if not has_scope:
            return "删除类必须限定范围：请指定域名或白名单"
        if not _non_empty_str(params.get("backup_dir")):
            return "删域名必须填写快照目录（backup_dir）"
        if str(params.get("confirm", "")) != "DELETE":
            return "删域名二次确认须输入 DELETE"
    elif mode == "add":
        if not _non_empty_str(params.get("add_domain")) and not domains:
            return "添加模式必须有目标：新域名或指定域名首个"
        records = list(params.get("add_records") or [])
        if not _non_empty_str(params.get("add_domain")) and not records:
            return "添加模式必须提供 add_domain 或 add_records"
    elif mode == "set_attrs":
        if params.get("set_proxied") is None and params.get("set_ttl") is None:
            return "属性设置必须指定 set_proxied 或 set_ttl"
    elif mode == "export":
        if not _non_empty_str(params.get("export_dir")):
            return "导出模式必须提供 export_dir"
    elif mode == "provision":
        if not domains:
            return "配置模式必须指定域名（domains）"
        ssl_mode = str(params.get("ssl_mode", "") or "")
        if ssl_mode and ssl_mode not in {"flexible", "full", "strict", "off"}:
            return f"不支持的 SSL 模式: {ssl_mode}"
        for key in ("activation_timeout", "activation_interval"):
            val = params.get(key)
            if val is not None:
                try:
                    if float(val) <= 0:
                        return f"{key} 必须大于 0"
                except (TypeError, ValueError):
                    return f"{key} 无效"
    else:
        return f"不支持的模式: {mode}"
    return None


def validate_single_record(payload: dict[str, Any]) -> Optional[str]:
    """单条记录校验，返回错误信息；与 Cloudflare 网页版对齐。"""
    rtype = str(payload.get("type", "")).upper().strip()
    if rtype not in RECORD_TYPES:
        return f"不支持的记录类型: {rtype or '(空)'}"
    content = str(payload.get("content", "") or "").strip()
    if not content:
        return "记录内容不能为空"
    try:
        proxied = bool(payload.get("proxied", False))
    except Exception:
        return "proxied 必须为布尔值"
    if proxied and rtype not in PROXIABLE_TYPES:
        return f"{rtype} 不可开代理，仅 A/AAAA/CNAME 可开"
    try:
        ttl = int(payload.get("ttl", 1) or 1)
    except (TypeError, ValueError):
        return "TTL 必须为整数"
    if proxied and ttl != 1:
        return "代理开时 TTL 锁定为 1（自动）"
    if ttl != 1 and not 60 <= ttl <= 86400:
        return "TTL 仅允许 1（自动）或 60~86400"
    comment = payload.get("comment", "")
    if comment is None:
        comment = ""
    if not isinstance(comment, str):
        return "备注必须为文本"
    if len(comment) > 100:
        return f"备注至多 100 字（当前 {len(comment)} 字）：请删减后重试"
    prio = payload.get("priority", None)
    if prio is not None:
        try:
            prio = int(prio)
        except (TypeError, ValueError):
            return "优先级必须为整数"
        if not 0 <= prio <= 65535:
            return f"优先级须为 0~65535（当前 {prio}）"
        if rtype != "MX":
            return f"优先级仅 MX 记录可用，{rtype} 记录请勿填写"
    return None
