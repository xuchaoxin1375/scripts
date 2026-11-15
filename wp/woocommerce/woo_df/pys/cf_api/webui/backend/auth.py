# -*- coding: utf-8 -*-
"""鉴权依赖：口令走 X-Auth-Token；未配置口令时保持本机免认证。"""

from __future__ import annotations

from typing import Optional

from fastapi import Header, HTTPException

from . import deps


def check_auth(password: str, token: Optional[str]) -> None:
    """校验请求头；password 为空表示本机免认证。"""
    if not password:
        return
    if token != password:
        raise HTTPException(status_code=401, detail="未授权")


def require_auth(
    x_auth_token: Optional[str] = Header(default=None, alias="X-Auth-Token"),
) -> None:
    """FastAPI 依赖：按当前配置口令校验请求。"""
    check_auth(deps.get_password(), x_auth_token)
