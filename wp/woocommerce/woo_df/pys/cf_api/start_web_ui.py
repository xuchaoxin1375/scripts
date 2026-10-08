# -*- coding: utf-8 -*-
"""WebUI 启动入口（FastAPI + 单一前端）。

- 默认仅监听 127.0.0.1；对外监听无口令拒绝启动；
- 口令走 X-Auth-Token；代理仅全局（任务级代理不落盘、不进审计）。
"""

from __future__ import annotations

import argparse
import os
import sys

DESKTOP = r"C:/Users/Administrator/Desktop"
DEFAULT_CONFIG = os.getenv("CF_CONFIG_PATH", f"{DESKTOP}/deploy_configs/cf_config.csv")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Cloudflare DNS WebUI")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8600)
    p.add_argument("--config", default=DEFAULT_CONFIG)
    p.add_argument("--password", default=os.getenv("CF_WEB_PASSWORD", ""))
    p.add_argument("-P", "--proxy", action="append", default=None)
    p.add_argument("--proxy-file", default=None)
    p.add_argument(
        "--proxy-mode",
        default="round-robin",
        choices=["round-robin", "sticky", "failover"],
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    if args.host not in {"127.0.0.1", "localhost", "::1"} and not args.password:
        print("对外监听必须设置 --password（或 CF_WEB_PASSWORD），已拒绝启动")
        sys.exit(2)
    if not os.path.exists(args.config):
        print(f"配置文件不存在: {args.config}")
        sys.exit(2)

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from webui.backend import deps
    from webui.backend.app import create_app
    from webui.backend.engine_adapter import get_engine

    eng = get_engine()
    # 全局代理池（任务级代理已移除，仅驻内存全局池；审计只记数量与模式）。
    proxy_pool = None
    urls: list[str] = []
    if args.proxy:
        for raw in args.proxy:
            try:
                urls.append(eng.validate_proxy_url(raw))
            except ValueError as exc:
                print(f"代理参数错误: {exc}")
                sys.exit(2)
    if args.proxy_file:
        urls.extend(eng.load_proxy_file(args.proxy_file))
    if urls:
        proxy_pool = eng.ProxyPool(urls, mode=args.proxy_mode)
        print(f"出口代理: 模式={proxy_pool.mode} 数量={len(proxy_pool.urls)}")

    deps.configure(args.config, password=args.password, proxy_pool=proxy_pool)
    frontend = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "webui", "frontend", "dist"
    )
    app = create_app(frontend if os.path.isdir(frontend) else "")

    import uvicorn

    print(f"WebUI: http://{args.host}:{args.port} config={args.config}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
