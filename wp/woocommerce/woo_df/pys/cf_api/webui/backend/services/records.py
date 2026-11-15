# -*- coding: utf-8 -*-
"""记录写入相关的纯逻辑：名称归一化、导入预检。"""

from __future__ import annotations

from typing import Any, Optional

from ..validate import validate_single_record


def canon_name(name: str, zone_name: str) -> str:
    """写路径名称归一化为完整域名。

    编辑器按参考稿使用短名（`@` 表根域名）；接口写入统一转完整域名，
    与读取路径的原始格式一致，避免改名语义漂移。
    """
    short = (name or "").strip()
    zone = (zone_name or "").strip()
    if not short or short == "@":
        return zone
    if not zone:
        return short
    low, zlow = short.lower(), zone.lower()
    if low == zlow or low.endswith("." + zlow):
        return short
    if "." not in short:
        return f"{short}.{zone}"
    return short


def import_item_error(index: int, item: Any) -> Optional[str]:
    """导入/恢复条目的单条校验；返回错误文本或 None。"""
    name = (item.name or "").strip()
    if not name:
        return f"第{index}条：名称必填"
    err = validate_single_record(
        {
            "type": (item.type or "").upper().strip(),
            "content": item.content,
            "proxied": bool(item.proxied),
            "ttl": int(item.ttl or 1),
            "comment": item.comment or "",
            "priority": item.priority,
        }
    )
    return f"第{index}条：{err}" if err else None
