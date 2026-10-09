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
    p.add_argument("--log-file", default=os.getenv("CF_WEB_LOG", ""))
    p.add_argument("-P", "--proxy", action="append", default=None)
    p.add_argument("--proxy-file", default=None)
    p.add_argument(
        "--proxy-mode",
        default="round-robin",
        choices=["round-robin", "sticky", "failover"],
    )
    return p.parse_args()


def _setup_file_log(path: str) -> None:
    """Hidden 后台运行时全靠文件排障：追加写入，超 512KB 转一个 .1 备份。"""
    import datetime

    try:
        if os.path.getsize(path) > 512 * 1024:
            try:
                os.replace(path, path + ".1")
            except OSError:
                pass
    except OSError:
        pass
    try:
        parent = os.path.dirname(os.path.abspath(path))
        if parent:
            os.makedirs(parent, exist_ok=True)
    except OSError:
        pass

    class _Tee:
        def __init__(self, stream, fp):  # type: ignore[no-untyped-def]
            self._stream = stream
            self._fp = fp

        def write(self, s):  # type: ignore[no-untyped-def]
            try:
                self._fp.write(s)
                self._fp.flush()
            except OSError:
                pass
            try:
                return self._stream.write(s)
            except OSError:
                return 0

        def flush(self):  # type: ignore[no-untyped-def]
            try:
                self._fp.flush()
            except OSError:
                pass
            try:
                self._stream.flush()
            except OSError:
                pass

        def isatty(self):  # type: ignore[no-untyped-def]
            try:
                return self._stream.isatty()
            except Exception:
                return False

    try:
        fp = open(path, "a", encoding="utf-8", errors="replace")
        fp.write(f"[{datetime.datetime.now():%Y-%m-%d %H:%M:%S}] WebUI 日志开始\n")
        fp.flush()
        sys.stdout = _Tee(sys.stdout, fp)  # type: ignore[assignment]
        sys.stderr = _Tee(sys.stderr, fp)  # type: ignore[assignment]
    except OSError as exc:
        print(f"日志文件不可写: {exc}")


def main() -> None:
    args = parse_args()
    if getattr(args, "log_file", ""):
        _setup_file_log(args.log_file)
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
    # Hidden 后台日志落盘：关掉着色（否则 webui.log 满是 ANSI 转义，与 serve-preview 的 stripAnsi 同理）。
    uvicorn.run(app, host=args.host, port=args.port, log_level="info", use_colors=False)


if __name__ == "__main__":
    main()
