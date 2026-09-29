#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Web UI 启动入口：python start_web_ui.py [--host 127.0.0.1] [--port 8080]。

安全说明：
- 默认仅监听 127.0.0.1；对外监听必须设置访问口令。
- 口令来源：--password，或环境变量 CF_WEB_PASSWORD。
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from webui.server import PASSWORD_ENV, create_app  # noqa: E402


def parse_args() -> argparse.Namespace:
    # 默认值与 CLI -C 同源（引擎 CF_CONFIG_PATH），避免 Web 端每次手填。
    try:
        from webui.engine_adapter import default_config_path

        _preset = default_config_path()
    except Exception:  # noqa: BLE001 - 引擎加载失败时保持空预设
        _preset = os.getenv("CF_CONFIG_PATH", "")
    parser = argparse.ArgumentParser(description="Cloudflare DNS Web 操作台")
    parser.add_argument("--host", default="127.0.0.1", help="监听地址（默认仅本机）。")
    parser.add_argument(
        "--port", type=int, default=8080, help="监听端口（默认 8080）。"
    )
    parser.add_argument(
        "-C",
        "--config",
        default=_preset,
        help=f"账号配置文件路径（默认预设 {_preset or '（空）'}，可在页面内修改）。",
    )
    parser.add_argument(
        "--password",
        default=None,
        help="访问口令（也可用环境变量 CF_WEB_PASSWORD）。",
    )
    parser.add_argument(
        "-P",
        "--proxy",
        action="append",
        default=None,
        metavar="URL",
        help="出口代理，可多次使用。",
    )
    parser.add_argument(
        "--proxy-mode",
        default="round-robin",
        choices=["round-robin", "sticky", "failover"],
        help="多代理调度模式。",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    password = args.password or os.getenv(PASSWORD_ENV, "")
    print(f"Cloudflare DNS Web 操作台: http://{args.host}:{args.port}")
    if not password:
        print("警告: 未设置访问口令，仅允许本机访问。")
    create_app(
        config_path=args.config or "",
        password=password,
        proxy_urls=args.proxy or [],
        proxy_mode=args.proxy_mode,
        host=args.host,
        port=args.port,
    )


if __name__ in {"__main__", "__mp_main__"}:
    main()
