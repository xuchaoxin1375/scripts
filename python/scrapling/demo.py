# save_boatid_source.py
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse


DEFAULT_URL = (
    "https://www.boatid.com/t-h-marine/"
    "48-l-snap-flex-all-round-stern-pole-led-light-mpn-led-navsfsl-48-dp.html"
)

BLOCK_HINTS = (
    "access denied",
    "attention required",
    "error 1020",
    "sorry, you have been blocked",
    "error 1015",
)


@dataclass
class FetchResult:
    engine: str
    url: str
    final_url: Optional[str]
    status: Optional[int]
    html: str
    elapsed_sec: float
    blocked_suspected: bool


class FetchError(RuntimeError):
    pass


def setup_logging(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="[%(asctime)s] %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def parse_proxy_endpoint(proxy: str) -> tuple[str, int]:
    parsed = urlparse(proxy)
    if not parsed.scheme or not parsed.hostname or not parsed.port:
        raise ValueError(
            f"代理格式不完整: {proxy!r}，建议使用 http://host:port 或 socks5://host:port"
        )
    return parsed.hostname, int(parsed.port)


def wait_for_proxy(proxy: Optional[str], attempts: int = 3, delay: float = 1.5) -> bool:
    if not proxy:
        return True

    host, port = parse_proxy_endpoint(proxy)
    for i in range(1, attempts + 1):
        try:
            with socket.create_connection((host, port), timeout=3):
                logging.info("代理端口可连通: %s:%s", host, port)
                return True
        except OSError as exc:
            logging.warning("代理连通性检查失败 %s/%s: %s", i, attempts, exc)
            if i < attempts:
                time.sleep(delay)

    return False


def looks_blocked(html: str) -> bool:
    text = html[:300_000].lower()
    if any(hint in text for hint in BLOCK_HINTS):
        return True

    # 正常页面可能内嵌 Cloudflare 相关 JS/CSS；只有挑战页的组合特征才判为拦截。
    return (
        "just a moment" in text
        and "cloudflare" in text
        and "/cdn-cgi/challenge-platform" in text
    )


def atomic_write_text(path: Path, content: str, encoding: str = "utf-8") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding=encoding,
        delete=False,
        dir=str(path.parent),
        suffix=".tmp",
    ) as f:
        f.write(content)
        tmp_name = f.name
    os.replace(tmp_name, path)


def extract_html_from_scrapling_response(resp) -> str:
    """
    Scrapling 版本变化较快，这里做宽松兼容：
    优先取 text/html/content/body；如果是 bytes 则解码；最后退化为 str(resp)。
    """
    for attr in ("html_content", "text", "html", "content", "body"):
        val = getattr(resp, attr, None)
        if val is None:
            continue
        if callable(val):
            try:
                val = val()
            except TypeError:
                continue

        if isinstance(val, bytes):
            return val.decode("utf-8", errors="replace")
        if isinstance(val, str):
            return val

    rendered = str(resp)
    if rendered:
        return rendered

    raise FetchError("无法从 Scrapling Response 对象中提取 HTML。")


def get_status_from_obj(obj) -> Optional[int]:
    for attr in ("status", "status_code"):
        val = getattr(obj, attr, None)
        if isinstance(val, int):
            return val
        if callable(val):
            try:
                ret = val()
                if isinstance(ret, int):
                    return ret
            except TypeError:
                pass
    return None


def fetch_with_scrapling_api(
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headful: bool,
) -> FetchResult:
    started = time.perf_counter()

    try:
        from scrapling.fetchers import StealthyFetcher
    except Exception as exc:
        raise FetchError(f"无法导入 scrapling.fetchers.StealthyFetcher: {exc}") from exc

    kwargs = {
        "headless": not headful,
        "network_idle": True,
        "load_dom": True,
        "timeout": timeout_ms,
        "real_chrome": True,
        "google_search": True,
        "solve_cloudflare": True,
        "block_webrtc": True,
        "hide_canvas": True,
        # 不默认禁用资源，避免部分站点 JS/CSS 依赖导致页面未完成。
        "disable_resources": False,
    }
    if proxy:
        kwargs["proxy"] = proxy

    logging.info("尝试 Scrapling Python API 获取页面。")
    resp = StealthyFetcher.fetch(url, **kwargs)

    html = extract_html_from_scrapling_response(resp)
    status = get_status_from_obj(resp)
    final_url = getattr(resp, "url", None)
    if callable(final_url):
        try:
            final_url = final_url()
        except TypeError:
            final_url = None

    return FetchResult(
        engine="scrapling_api",
        url=url,
        final_url=str(final_url) if final_url else None,
        status=status,
        html=html,
        elapsed_sec=round(time.perf_counter() - started, 3),
        blocked_suspected=looks_blocked(html),
    )


def fetch_with_scrapling_cli(
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    out_hint: Path,
) -> FetchResult:
    started = time.perf_counter()

    scrapling_bin = shutil.which("scrapling")
    if not scrapling_bin:
        raise FetchError("未找到 scrapling CLI；请确认当前 venv 已激活，或 scrapling 在 PATH 中。")

    tmp_out = out_hint.with_suffix(out_hint.suffix + ".scrapling_cli.tmp.html")
    if tmp_out.exists():
        tmp_out.unlink()

    cmd = [
        scrapling_bin,
        "extract",
        "stealthy-fetch",
        "--solve-cloudflare",
        url,
        str(tmp_out),
        "--real-chrome",
        "--timeout",
        str(timeout_ms),
    ]
    if proxy:
        cmd.extend(["--proxy", proxy])

    logging.info("尝试 Scrapling CLI 获取页面: %s", " ".join(cmd))
    proc = subprocess.run(
        cmd,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        # CLI 的 --timeout 是浏览器导航超时；这里额外给进程清理浏览器的缓冲。
        timeout=max(45, int(timeout_ms / 1000) + 45),
    )

    if proc.returncode != 0:
        raise FetchError(f"Scrapling CLI 失败，exit={proc.returncode}\n{proc.stdout}")

    if not tmp_out.exists() or tmp_out.stat().st_size == 0:
        raise FetchError(f"Scrapling CLI 未生成有效文件: {tmp_out}")

    html = tmp_out.read_text(encoding="utf-8", errors="replace")
    tmp_out.unlink(missing_ok=True)

    status = None
    for line in proc.stdout.splitlines():
        if "Fetched (" in line:
            try:
                status = int(line.split("Fetched (", 1)[1].split(")", 1)[0])
            except (IndexError, ValueError):
                pass

    return FetchResult(
        engine="scrapling_cli",
        url=url,
        final_url=None,
        status=status,
        html=html,
        elapsed_sec=round(time.perf_counter() - started, 3),
        blocked_suspected=looks_blocked(html),
    )


def fetch_with_cloakbrowser(
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headful: bool,
) -> FetchResult:
    started = time.perf_counter()

    try:
        from cloakbrowser import launch
    except ImportError as exc:
        raise FetchError(
            "无法导入 cloakbrowser；可安装后启用回退: pip install cloakbrowser"
        ) from exc

    launch_kwargs = {
        "headless": not headful,
        "locale": "en-US",
        "timezone": "America/New_York",
    }
    if proxy:
        launch_kwargs["proxy"] = proxy

    logging.info("尝试 CloakBrowser 获取页面。")
    browser = None

    try:
        browser = launch(**launch_kwargs)
        page = browser.new_page()

        response = page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)

        try:
            page.wait_for_load_state("networkidle", timeout=min(timeout_ms, 20_000))
        except Exception:
            logging.warning("等待 networkidle 超时，继续保存当前 DOM。")

        html = page.content()
        status = response.status if response else None
        final_url = page.url

        return FetchResult(
            engine="cloakbrowser",
            url=url,
            final_url=final_url,
            status=status,
            html=html,
            elapsed_sec=round(time.perf_counter() - started, 3),
            blocked_suspected=looks_blocked(html),
        )
    finally:
        if browser:
            try:
                browser.close()
            except Exception:
                pass


def save_result(result: FetchResult, out: Path) -> None:
    atomic_write_text(out, result.html)

    meta = asdict(result)
    meta.pop("html", None)
    meta.update(
        {
            "saved_to": str(out.resolve()),
            "bytes_utf8": len(result.html.encode("utf-8", errors="replace")),
            "sha256": hashlib.sha256(
                result.html.encode("utf-8", errors="replace")
            ).hexdigest(),
        }
    )

    atomic_write_text(
        out.with_suffix(out.suffix + ".meta.json"),
        json.dumps(meta, ensure_ascii=False, indent=2),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--out", default="bbb.html")
    parser.add_argument(
        "--proxy",
        default=os.getenv("SCRAPE_PROXY", "http://localhost:7897"),
        help="例如 http://localhost:7897；也可通过 SCRAPE_PROXY 环境变量设置。",
    )
    parser.add_argument(
        "--engine",
        choices=("auto", "scrapling", "cloak"),
        default="auto",
        help="auto: Scrapling CLI -> CloakBrowser；scrapling: 仅 CLI。",
    )
    parser.add_argument("--timeout-ms", type=int, default=90_000)
    parser.add_argument("--headful", action="store_true", help="显示浏览器窗口，便于排查。")
    parser.add_argument(
        "--allow-direct",
        action="store_true",
        help="代理不可用时允许直连。默认不直连，避免国内 IP 直接触发 403。",
    )
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    setup_logging(args.verbose)

    url = args.url.strip()
    out = Path(args.out).expanduser().resolve()
    proxy = args.proxy.strip() if args.proxy else None

    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise SystemExit(f"URL scheme 不合法: {url}")

    if proxy and not wait_for_proxy(proxy):
        if args.allow_direct:
            logging.warning("代理不可用，按 --allow-direct 切换为直连。")
            proxy = None
        else:
            logging.error(
                "代理不可用，且未启用 --allow-direct；为避免国内 IP 直连被禁，已停止。"
            )
            return 2

    engines = []
    if args.timeout_ms < 5_000:
        raise SystemExit("--timeout-ms 必须至少为 5000。")

    if args.engine == "auto":
        # CLI 已由实际命令验证，优先使用；Scrapling Python API 在某些版本下可能
        # 无视导航超时并使解释器悬挂，因此仅作为用户自行选择的实现方式。
        engines = ["scrapling_cli", "cloakbrowser"]
    elif args.engine == "scrapling":
        engines = ["scrapling_cli"]
    elif args.engine == "cloak":
        engines = ["cloakbrowser"]

    last_error: Optional[Exception] = None

    for engine in engines:
        try:
            if engine == "scrapling_api":
                result = fetch_with_scrapling_api(
                    url=url,
                    proxy=proxy,
                    timeout_ms=args.timeout_ms,
                    headful=args.headful,
                )
            elif engine == "scrapling_cli":
                result = fetch_with_scrapling_cli(
                    url=url,
                    proxy=proxy,
                    timeout_ms=args.timeout_ms,
                    out_hint=out,
                )
            elif engine == "cloakbrowser":
                result = fetch_with_cloakbrowser(
                    url=url,
                    proxy=proxy,
                    timeout_ms=args.timeout_ms,
                    headful=args.headful,
                )
            else:
                raise FetchError(f"未知 engine: {engine}")

            if len(result.html) < 500:
                raise FetchError(f"{engine} 返回内容过短: {len(result.html)} chars")

            if result.status and result.status >= 400:
                logging.warning("%s 返回 HTTP %s。", engine, result.status)

            if result.blocked_suspected:
                diagnostic = out.with_suffix(out.suffix + f".{engine}.blocked.html")
                atomic_write_text(diagnostic, result.html)
                logging.warning(
                    "%s 返回内容疑似被拦截，诊断 HTML 已保存: %s",
                    engine,
                    diagnostic,
                )
                last_error = FetchError(f"{engine} 返回内容疑似被拦截")
                continue

            save_result(result, out)
            logging.info(
                "成功保存: %s | engine=%s | status=%s | bytes=%s | elapsed=%ss",
                out,
                result.engine,
                result.status,
                len(result.html.encode("utf-8", errors="replace")),
                result.elapsed_sec,
            )
            return 0

        except Exception as exc:
            last_error = exc
            logging.warning("%s 失败: %s", engine, exc)

    logging.error("所有方式均失败。最后错误: %s", last_error)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
