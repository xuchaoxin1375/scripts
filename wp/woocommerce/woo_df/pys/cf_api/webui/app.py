"""Web UI 入口兼容层：NiceGUI 实现已替换为 FastAPI + 静态前端。

保留本模块仅为兼容旧导入（测试与外部脚本仍可 from webui.app import create_app）。
新实现见 webui/server.py。
"""

from __future__ import annotations

from .server import PASSWORD_ENV, ServerState, build_fastapi, create_app  # noqa: F401

try:
    from . import engine_adapter as _adapter

    CONFIG_DEFAULT = _adapter.default_config_path()
except Exception:  # noqa: BLE001 - 引擎加载失败时保持空预设
    CONFIG_DEFAULT = ""
