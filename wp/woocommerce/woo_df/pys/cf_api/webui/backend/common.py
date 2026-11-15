# -*- coding: utf-8 -*-
"""路由层通用小工具。"""

from __future__ import annotations

from typing import Any


def paginate(items: list[Any], page: int, per_page: int) -> dict[str, Any]:
    """服务端分页：每页 1~200 条，页码从 1 开始。"""
    per_page = max(1, min(200, per_page))
    page = max(1, page)
    total = len(items)
    start = (page - 1) * per_page
    return {
        "total": total,
        "page": page,
        "per_page": per_page,
        "items": items[start : start + per_page],
    }
