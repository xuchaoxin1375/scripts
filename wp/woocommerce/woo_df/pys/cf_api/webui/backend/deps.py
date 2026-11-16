# -*- coding: utf-8 -*-
"""后端依赖注入：配置路径/口令/代理池/任务管理器单例。

供 app.py 路由与测试复用；configure 幂等，可重复调用切换配置。
"""

from __future__ import annotations

from dataclasses import dataclass, field
from secrets import token_hex
from threading import Lock
from typing import Any, Optional

from . import db, engine_adapter
from .jobs import JobManager


@dataclass
class ProxyEntry:
    """一条已保存的代理；url 含凭据，只在服务端保存。"""

    id: str
    url: str
    enabled: bool = True


@dataclass
class ProxyConfig:
    """当前进程的代理配置；总开关关闭时仍保留 entries。"""

    enabled: bool = False
    mode: str = "round-robin"
    entries: list[ProxyEntry] = field(default_factory=list)
    lock: Lock = field(default_factory=Lock, repr=False, compare=False)


def new_proxy_id() -> str:
    return token_hex(6)


_config_path: str = ""
_password: str = ""
_proxy_pool: Any = None
_proxy_config: ProxyConfig = ProxyConfig()
_manager: Optional[JobManager] = None
_find_manager: Any = None


def configure(
    config_path: str,
    password: str = "",
    proxy_pool: Any = None,
) -> None:
    """设置全局依赖并初始化 sqlite（WAL，库文件在配置同目录 cf_web.db）。"""
    global _config_path, _password, _proxy_pool, _proxy_config, _manager
    _config_path = config_path
    _password = password or ""
    _proxy_pool = proxy_pool
    _proxy_config = ProxyConfig()
    if proxy_pool is not None:
        urls = list(getattr(proxy_pool, "urls", []) or [])
        _proxy_config.enabled = bool(urls)
        _proxy_config.mode = str(getattr(proxy_pool, "mode", "") or "round-robin")
        _proxy_config.entries = [
            ProxyEntry(id=new_proxy_id(), url=url, enabled=True) for url in urls
        ]
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


def get_proxy_config() -> ProxyConfig:
    return _proxy_config


def set_proxy_pool(proxy_pool: Any) -> None:
    """替换全局代理池；新发起的请求生效，进行中的任务保留原池。"""
    global _proxy_pool
    _proxy_pool = proxy_pool


def get_manager() -> JobManager:
    global _manager
    if _manager is None:
        _manager = JobManager()
    return _manager


def get_find_manager() -> Any:
    """跨账号扫描注册表单例；延迟导入避免与 services.find 循环依赖。"""
    global _find_manager
    if _find_manager is None:
        from .services.find import FindScanManager

        _find_manager = FindScanManager()
    return _find_manager


def reset_find_manager() -> None:
    """测试或重新配置时释放扫描线程池。"""
    global _find_manager
    if _find_manager is not None:
        try:
            _find_manager.shutdown()
        except Exception:
            pass
        _find_manager = None


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
