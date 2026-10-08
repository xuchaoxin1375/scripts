# -*- coding: utf-8 -*-
"""后端依赖注入：配置路径/口令/代理池/任务管理器单例。

供 app.py 路由与测试复用；configure 幂等，可重复调用切换配置。
"""

from __future__ import annotations

from typing import Any, Optional

from . import db, engine_adapter
from .jobs import JobManager

_config_path: str = ""
_password: str = ""
_proxy_pool: Any = None
_manager: Optional[JobManager] = None


def configure(
    config_path: str,
    password: str = "",
    proxy_pool: Any = None,
) -> None:
    """设置全局依赖并初始化 sqlite（WAL，库文件在配置同目录 cf_web.db）。"""
    global _config_path, _password, _proxy_pool, _manager
    _config_path = config_path
    _password = password or ""
    _proxy_pool = proxy_pool
    if _manager is None:
        _manager = JobManager()
    if config_path:
        try:
            db.init_db(config_path)
        except Exception:
            pass


def get_config_path() -> str:
    return _config_path


def get_password() -> str:
    return _password


def get_proxy_pool() -> Any:
    return _proxy_pool


def get_manager() -> JobManager:
    global _manager
    if _manager is None:
        _manager = JobManager()
    return _manager


def get_accounts() -> list[dict]:
    if not _config_path:
        return []
    return engine_adapter.get_accounts(_config_path)


def default_dirs() -> dict[str, str]:
    """快照/导出默认目录：派生自配置文件所在目录。"""
    import os

    parent = os.path.dirname(os.path.abspath(_config_path)) if _config_path else ""
    if parent and os.path.isdir(parent):
        return {
            "backup_dir": os.path.join(parent, "cf_backup"),
            "export_dir": os.path.join(parent, "cf_export"),
        }
    return {"backup_dir": "./cf_backup", "export_dir": "./cf_export"}
