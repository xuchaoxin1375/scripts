# -*- coding: utf-8 -*-
"""FastAPI 组装：挂载 /api/v1 路由组 + SPA 回退。

路由按资源拆到 `routers/`，业务编排在 `services/`；本文件只保留应用级组装，
URL、JSON 字段与旧实现保持一致。
"""

from __future__ import annotations

import os

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse

from .routers import find, history, jobs, meta, records, uploads, zones


def create_app(frontend: str = "") -> FastAPI:
    """构建 FastAPI 应用（测试与启动共用）。"""
    app = FastAPI(title="Cloudflare DNS WebUI")

    app.include_router(meta.router)
    app.include_router(zones.router)
    app.include_router(records.router)
    app.include_router(find.router)
    app.include_router(jobs.router)
    app.include_router(uploads.router)
    app.include_router(history.router)

    # ---- SPA ----
    base = os.path.abspath(frontend) if frontend else ""
    if base and os.path.isdir(base):

        @app.get("/")
        def index() -> FileResponse:
            page = os.path.join(base, "index.html")
            if not os.path.exists(page):
                raise HTTPException(status_code=500, detail="前端页面缺失")
            return FileResponse(page, media_type="text/html; charset=utf-8")

        @app.get("/{path:path}")
        def spa(path: str) -> FileResponse:
            if path.startswith("api/"):
                raise HTTPException(status_code=404, detail="接口不存在")
            candidate = os.path.abspath(os.path.join(base, path))
            if candidate.startswith(base + os.sep) and os.path.isfile(candidate):
                return FileResponse(candidate)
            return FileResponse(
                os.path.join(base, "index.html"), media_type="text/html; charset=utf-8"
            )

    return app
