"""正经 Web 方案：FastAPI + 纯静态前端（无构建，替代 NiceGUI）。

- 后端：复用 engine_adapter / jobs / rest（/api 全保留，行为不变）。
- 前端：webui/static 下的原生 HTML/CSS/JS，无 Node 构建，直接由 FastAPI 托管。
- 长列表统一分页 + 滚动容器 + 粘性表头，单页最多渲染 100 行。
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Any, Optional

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import engine_adapter, jobs, rest

PASSWORD_ENV = "CF_WEB_PASSWORD"
STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
LOOPBACK = {"127.0.0.1", "localhost", "::1"}


@dataclass
class ServerState:
    """服务端可变状态（配置路径可在页面内切换，任务管理器常驻）。"""

    config_path: str = ""
    preset_path: str = ""
    password: str = ""
    proxy_urls: list[str] = field(default_factory=list)
    proxy_mode: str = "round-robin"
    proxy_pool: Any = None
    manager: jobs.JobManager = field(default_factory=lambda: jobs.JobManager())

    def ensure_proxy_pool(self) -> Any:
        if self.proxy_pool is None and self.proxy_urls:
            engine = engine_adapter.engine()
            self.proxy_pool = engine.ProxyPool(self.proxy_urls, mode=self.proxy_mode)
        return self.proxy_pool


class ConfigSwitch(BaseModel):
    path: str = ""


def _check(password: str, token: Optional[str]) -> None:
    if not password:
        return
    if token != password:
        raise HTTPException(status_code=401, detail="未授权")


def _default_dirs(config_path: str) -> dict[str, str]:
    parent = os.path.dirname(os.path.abspath(config_path)) if config_path else ""
    if parent and os.path.isdir(parent):
        return {
            "backup_dir": os.path.join(parent, "cf_backup"),
            "export_dir": os.path.join(parent, "cf_export"),
        }
    return {"backup_dir": "./cf_backup", "export_dir": "./cf_export"}


def build_fastapi(state: ServerState) -> FastAPI:
    """构建 FastAPI 应用（页面 + /api），供启动与测试复用。"""
    server = FastAPI(title="Cloudflare DNS 操作台")

    deps = rest.Deps(
        get_config_path=lambda: state.config_path,
        get_accounts=lambda: engine_adapter.get_accounts(state.config_path),
        get_manager=lambda: state.manager,
        get_password=lambda: state.password,
        get_proxy_pool=lambda: state.ensure_proxy_pool(),
    )
    server.include_router(rest.build_router(deps))

    @server.get("/api/meta")
    def meta() -> dict[str, Any]:
        engine = engine_adapter.engine()
        dirs = _default_dirs(state.config_path)
        return {
            "requires_auth": bool(state.password),
            "config_path": state.config_path,
            "preset_path": state.preset_path,
            "speeds": dict(engine.SPEED_PRESETS),
            "defaults": {
                "speed": "eco",
                "scope": "account",
                "max_retries": int(engine.DEFAULT_API_MAX_RETRIES),
                "record_type": "auto",
                "export_fmt": "json",
                "backup_dir": dirs["backup_dir"],
                "export_dir": dirs["export_dir"],
            },
        }

    @server.post("/api/config")
    def switch_config(
        body: ConfigSwitch, x_auth_token: Optional[str] = Header(default=None)
    ) -> dict[str, Any]:
        _check(state.password, x_auth_token)
        path = (body.path or "").strip() or state.preset_path
        if not path:
            raise HTTPException(status_code=400, detail="配置文件路径为空")
        try:
            accounts = engine_adapter.get_accounts(path)
        except engine_adapter.EngineError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        state.config_path = path
        return {
            "config_path": path,
            "count": len(accounts),
            "accounts": engine_adapter.masked_accounts(accounts),
            **_default_dirs(path),
        }

    @server.get("/api/default-dirs")
    def default_dirs(
        x_auth_token: Optional[str] = Header(default=None),
    ) -> dict[str, Any]:
        _check(state.password, x_auth_token)
        return {"config_path": state.config_path, **_default_dirs(state.config_path)}

    if os.path.isdir(STATIC_DIR):
        server.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @server.get("/")
    def index() -> FileResponse:
        page = os.path.join(STATIC_DIR, "index.html")
        if not os.path.exists(page):
            raise HTTPException(status_code=500, detail="前端页面缺失")
        return FileResponse(page, media_type="text/html; charset=utf-8")

    return server


def create_app(
    config_path: str = "",
    password: str = "",
    proxy_urls: Optional[list[str]] = None,
    proxy_mode: str = "round-robin",
    host: str = "127.0.0.1",
    port: int = 8080,
    show: bool = False,  # noqa: ARG001 - 保持与旧入口签名兼容
) -> None:
    """创建并启动 Web 服务（阻塞）。"""
    import uvicorn

    if host not in LOOPBACK and not password:
        raise SystemExit(
            "对外监听必须设置访问口令（--password 或 CF_WEB_PASSWORD），已拒绝启动"
        )
    preset = engine_adapter.default_config_path()
    effective = (config_path or "").strip() or preset
    state = ServerState(
        config_path=effective,
        preset_path=preset,
        password=password,
        proxy_urls=list(proxy_urls or []),
        proxy_mode=proxy_mode,
    )
    server = build_fastapi(state)
    uvicorn.run(server, host=host, port=port, log_level="info")
