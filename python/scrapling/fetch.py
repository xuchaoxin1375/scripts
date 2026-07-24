from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import logging
import multiprocessing as mp
import os
import shutil
import socket
import subprocess
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from queue import Empty
from typing import Optional
from urllib.parse import urlparse
from urllib.request import ProxyHandler, build_opener


TARGET_URL = "https://www.greentradingxxl.com/"
DEFAULT_PROXY = "http://localhost:7897"

# Avoid treating a normal page's embedded Cloudflare assets as a block page.
HARD_BLOCK_MARKERS = (
    "error 1020",
    "error 1015",
    "access denied",
    "attention required",
    "sorry, you have been blocked",
    "captcha delivery",
)


@dataclass
class FetchResult:
    engine: str
    status: Optional[int]
    final_url: str
    html: str
    elapsed_sec: float
    challenge_suspected: bool


class FetchError(RuntimeError):
    pass


def resolve_performance_profile(profile: str, settle_override: Optional[int]) -> tuple[bool, bool, int]:
    """Return load_dom, disable_resources, and post-verification wait settings.

    Do not alter Scrapling's Cloudflare solver timing here: verification clicks and
    stability waits are anti-bot critical. These profiles only tune work after it passes.
    """
    defaults = {
        "reliable": (True, False, 5_000),
        "balanced": (True, False, 1_500),
        "fast": (False, True, 0),
    }
    load_dom, disable_resources, settle_ms = defaults[profile]
    if settle_override is not None:
        settle_ms = settle_override
    return load_dom, disable_resources, settle_ms


def configure_logging(verbose: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="[%(asctime)s] %(levelname)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def validate_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError(f"URL 不合法: {url!r}")
    return url


def proxy_is_reachable(proxy: Optional[str]) -> bool:
    if not proxy:
        return True

    parsed = urlparse(proxy)
    if not parsed.scheme or not parsed.hostname or not parsed.port:
        raise ValueError("代理格式应为 http://host:port 或 socks5://host:port")

    for attempt in range(1, 4):
        try:
            with socket.create_connection((parsed.hostname, parsed.port), timeout=3):
                logging.info("代理端口可连通: %s:%s", parsed.hostname, parsed.port)
                return True
        except OSError as exc:
            logging.warning("代理连通性检查失败 %s/3: %s", attempt, exc)
            if attempt < 3:
                time.sleep(1.5)
    return False


def looks_like_challenge(html: str) -> bool:
    text = html[:300_000].lower()
    if any(marker in text for marker in HARD_BLOCK_MARKERS):
        return True
    return (
        "just a moment" in text
        and "cloudflare" in text
        and "/cdn-cgi/challenge-platform" in text
    )


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", delete=False, dir=path.parent, suffix=".tmp"
    ) as handle:
        handle.write(content)
        temp_path = handle.name
    os.replace(temp_path, path)


def fetch_with_cloakbrowser(
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headless: bool,
    settle_ms: int,
    close_browser: bool = True,
) -> FetchResult:
    try:
        from cloakbrowser import launch
    except ImportError as exc:
        raise FetchError("未安装 cloakbrowser；请在当前环境运行 python -m pip install cloakbrowser") from exc

    started = time.perf_counter()
    browser = None
    try:
        logging.info("启动 CloakBrowser（%s模式）。", "无头" if headless else "有头")
        browser = launch(
            headless=headless,
            proxy=proxy,
            locale="en-US",
            timezone="America/New_York",
            humanize=True,
            human_preset="careful",
        )
        page = browser.new_page(viewport={"width": 1440, "height": 960})
        response = page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)

        try:
            page.wait_for_load_state("networkidle", timeout=min(timeout_ms, 25_000))
        except Exception:
            logging.info("页面未达到 networkidle，保存当前已渲染 DOM。")

        if settle_ms:
            page.wait_for_timeout(settle_ms)

        html = page.content()
        return FetchResult(
            engine="cloakbrowser",
            status=response.status if response else None,
            final_url=page.url,
            html=html,
            elapsed_sec=round(time.perf_counter() - started, 3),
            challenge_suspected=looks_like_challenge(html),
        )
    finally:
        if browser and close_browser:
            browser.close()


def _cloak_worker(
    result_queue,
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headless: bool,
    settle_ms: int,
) -> None:
    """Run CloakBrowser outside the main process so a stuck launch is recoverable."""
    try:
        result = fetch_with_cloakbrowser(
            url, proxy, timeout_ms, headless, settle_ms, close_browser=False
        )
        result_queue.put((True, asdict(result)))
    except Exception as exc:
        result_queue.put((False, f"{type(exc).__name__}: {exc}"))


def terminate_worker_tree(worker: mp.Process) -> None:
    if not worker.is_alive():
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(worker.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        worker.terminate()
    worker.join(10)
    if worker.is_alive():
        worker.kill()
        worker.join(5)


def receive_worker_result(
    worker: mp.Process, result_queue, deadline_sec: int, engine_name: str
) -> dict:
    deadline = time.monotonic() + deadline_sec
    try:
        while time.monotonic() < deadline:
            try:
                success, payload = result_queue.get(timeout=min(1, deadline - time.monotonic()))
            except Empty:
                if not worker.is_alive():
                    raise FetchError(f"{engine_name} 子进程异常退出，exit={worker.exitcode}")
                continue

            # The DOM has arrived. Kill the worker tree instead of waiting for browser cleanup.
            terminate_worker_tree(worker)
            if not success:
                raise FetchError(f"{engine_name} 失败: {payload}")
            return payload

        terminate_worker_tree(worker)
        raise FetchError(f"{engine_name} 超过总时限 {deadline_sec}s，已终止该尝试。")
    finally:
        result_queue.close()
        result_queue.join_thread()


def fetch_with_cloakbrowser_deadline(
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headless: bool,
    settle_ms: int,
    deadline_sec: int,
) -> FetchResult:
    context = mp.get_context("spawn")
    result_queue = context.Queue(maxsize=1)
    worker = context.Process(
        target=_cloak_worker,
        args=(result_queue, url, proxy, timeout_ms, headless, settle_ms),
        name="cloakbrowser-fetch",
    )
    worker.start()
    return FetchResult(**receive_worker_result(worker, result_queue, deadline_sec, "CloakBrowser"))


def reserve_local_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def read_cdp_websocket_url(port: int, timeout_sec: int = 30) -> str:
    opener = build_opener(ProxyHandler({}))  # CDP is always local; never send it through SCRAPE_PROXY.
    endpoint = f"http://127.0.0.1:{port}/json/version"
    deadline = time.monotonic() + timeout_sec
    last_error: Optional[Exception] = None
    while time.monotonic() < deadline:
        try:
            with opener.open(endpoint, timeout=3) as response:
                payload = json.load(response)
            websocket_url = payload.get("webSocketDebuggerUrl")
            if websocket_url:
                return str(websocket_url)
        except Exception as exc:
            last_error = exc
            time.sleep(0.5)
    raise FetchError(f"CloakBrowser CDP 端点未就绪: {last_error}")


async def fetch_with_cloak_scrapling_cdp_async(
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headless: bool,
    settle_ms: int,
    load_dom: bool,
    disable_resources: bool,
) -> FetchResult:
    try:
        from cloakbrowser import launch_async
        from scrapling.fetchers import StealthyFetcher
    except ImportError as exc:
        raise FetchError("集成模式需要 cloakbrowser 和 scrapling。") from exc

    started = time.perf_counter()
    cdp_port = reserve_local_port()
    logging.info("启动 CloakBrowser + Scrapling CDP 集成（%s模式）。", "无头" if headless else "有头")
    # Keep the browser open after a response. The parent process owns process-tree cleanup.
    await launch_async(
        headless=headless,
        proxy=proxy,
        locale="en-US",
        timezone="America/New_York",
        humanize=True,
        human_preset="careful",
        args=[
            f"--remote-debugging-port={cdp_port}",
            "--remote-debugging-address=127.0.0.1",
        ],
    )
    cdp_url = read_cdp_websocket_url(cdp_port)
    response = await StealthyFetcher.async_fetch(
        url,
        cdp_url=cdp_url,
        solve_cloudflare=True,
        timeout=timeout_ms,
        wait=settle_ms,
        load_dom=load_dom,
        network_idle=False,
        disable_resources=disable_resources,
        block_webrtc=True,
        hide_canvas=True,
        retries=1,
    )
    html = extract_response_html(response)
    status = getattr(response, "status", getattr(response, "status_code", None))
    final_url = getattr(response, "url", url)
    return FetchResult(
        engine="cloakbrowser_scrapling_cdp",
        status=status if isinstance(status, int) else None,
        final_url=str(final_url),
        html=html,
        elapsed_sec=round(time.perf_counter() - started, 3),
        challenge_suspected=looks_like_challenge(html),
    )


def _integrated_worker(
    result_queue,
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headless: bool,
    settle_ms: int,
    load_dom: bool,
    disable_resources: bool,
) -> None:
    try:
        result = asyncio.run(
            fetch_with_cloak_scrapling_cdp_async(
                url, proxy, timeout_ms, headless, settle_ms, load_dom, disable_resources
            )
        )
        result_queue.put((True, asdict(result)))
    except Exception as exc:
        result_queue.put((False, f"{type(exc).__name__}: {exc}"))


def fetch_with_cloak_scrapling_cdp_deadline(
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headless: bool,
    settle_ms: int,
    load_dom: bool,
    disable_resources: bool,
    deadline_sec: int,
) -> FetchResult:
    context = mp.get_context("spawn")
    result_queue = context.Queue(maxsize=1)
    worker = context.Process(
        target=_integrated_worker,
        args=(
            result_queue,
            url,
            proxy,
            timeout_ms,
            headless,
            settle_ms,
            load_dom,
            disable_resources,
        ),
        name="cloakbrowser-scrapling-cdp",
    )
    worker.start()
    return FetchResult(
        **receive_worker_result(worker, result_queue, deadline_sec, "CloakBrowser + Scrapling CDP")
    )


def extract_response_html(response) -> str:
    for attribute in ("html_content", "content", "body", "text", "html"):
        value = getattr(response, attribute, None)
        if callable(value):
            value = value()
        if isinstance(value, bytes):
            return value.decode("utf-8", errors="replace")
        if isinstance(value, str):
            return value
    raise FetchError("无法从 Scrapling Response 提取 HTML。")


def fetch_with_scrapling_api(
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headless: bool,
    settle_ms: int,
    load_dom: bool,
    disable_resources: bool,
) -> FetchResult:
    try:
        from scrapling.fetchers import StealthySession
    except ImportError as exc:
        raise FetchError("未安装 scrapling；请在当前环境运行 python -m pip install scrapling") from exc

    started = time.perf_counter()
    logging.info("调用 Scrapling StealthySession Python API（%s模式）。", "无头" if headless else "有头")
    session = StealthySession(
        headless=headless,
        real_chrome=True,
        solve_cloudflare=True,
        proxy=proxy,
        timeout=timeout_ms,
        wait=settle_ms,
        load_dom=load_dom,
        # Avoid waiting forever on analytics/WebSocket traffic on storefront pages.
        network_idle=False,
        disable_resources=disable_resources,
        block_webrtc=True,
        hide_canvas=True,
        locale="en-US",
        timezone_id="America/New_York",
        retries=1,
    )
    session.start()
    # Do not close here. The worker sends the completed DOM first; its parent then
    # ends the browser process tree. This avoids a stuck browser teardown losing data.
    response = session.fetch(url)
    html = extract_response_html(response)
    status = getattr(response, "status", getattr(response, "status_code", None))
    final_url = getattr(response, "url", url)
    return FetchResult(
        engine="scrapling_api",
        status=status if isinstance(status, int) else None,
        final_url=str(final_url),
        html=html,
        elapsed_sec=round(time.perf_counter() - started, 3),
        challenge_suspected=looks_like_challenge(html),
    )


def _scrapling_api_worker(
    result_queue,
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headless: bool,
    settle_ms: int,
    load_dom: bool,
    disable_resources: bool,
) -> None:
    try:
        result = fetch_with_scrapling_api(
            url, proxy, timeout_ms, headless, settle_ms, load_dom, disable_resources
        )
        result_queue.put((True, asdict(result)))
    except Exception as exc:
        result_queue.put((False, f"{type(exc).__name__}: {exc}"))


def fetch_with_scrapling_api_deadline(
    url: str,
    proxy: Optional[str],
    timeout_ms: int,
    headless: bool,
    settle_ms: int,
    load_dom: bool,
    disable_resources: bool,
    deadline_sec: int,
) -> FetchResult:
    context = mp.get_context("spawn")
    result_queue = context.Queue(maxsize=1)
    worker = context.Process(
        target=_scrapling_api_worker,
        args=(
            result_queue,
            url,
            proxy,
            timeout_ms,
            headless,
            settle_ms,
            load_dom,
            disable_resources,
        ),
        name="scrapling-api-fetch",
    )
    worker.start()
    return FetchResult(**receive_worker_result(worker, result_queue, deadline_sec, "Scrapling API"))


def fetch_with_scrapling_cli(
    url: str, proxy: Optional[str], timeout_ms: int, headless: bool, output: Path
) -> FetchResult:
    executable = shutil.which("scrapling")
    if not executable:
        raise FetchError("找不到 scrapling CLI；请确认当前虚拟环境已激活。")

    started = time.perf_counter()
    temporary = output.with_suffix(output.suffix + ".scrapling.tmp.html")
    temporary.unlink(missing_ok=True)
    command = [
        executable,
        "extract",
        "stealthy-fetch",
        "--solve-cloudflare",
        url,
        str(temporary),
        "--real-chrome",
        "--timeout",
        str(timeout_ms),
        "--network-idle",
    ]
    command.append("--headless" if headless else "--no-headless")
    if proxy:
        command.extend(("--proxy", proxy))

    logging.info("尝试 Scrapling CLI 回退（%s模式）。", "无头" if headless else "有头")
    try:
        completed = subprocess.run(
            command,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=max(60, timeout_ms // 1000 + 45),
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise FetchError(f"Scrapling CLI 超时: {exc}") from exc

    if completed.returncode != 0:
        raise FetchError(f"Scrapling CLI 失败，exit={completed.returncode}:\n{completed.stdout}")
    if not temporary.exists() or not temporary.stat().st_size:
        raise FetchError("Scrapling CLI 未生成有效 HTML。")

    html = temporary.read_text(encoding="utf-8", errors="replace")
    temporary.unlink(missing_ok=True)
    status = None
    for line in completed.stdout.splitlines():
        if "Fetched (" in line:
            try:
                status = int(line.split("Fetched (", 1)[1].split(")", 1)[0])
            except (IndexError, ValueError):
                pass
    return FetchResult(
        engine="scrapling_cli",
        status=status,
        final_url=url,
        html=html,
        elapsed_sec=round(time.perf_counter() - started, 3),
        challenge_suspected=looks_like_challenge(html),
    )


def save(result: FetchResult, url: str, output: Path) -> None:
    atomic_write(output, result.html)
    metadata = asdict(result)
    metadata.update(
        requested_url=url,
        saved_to=str(output.resolve()),
        bytes_utf8=len(result.html.encode("utf-8", errors="replace")),
        sha256=hashlib.sha256(result.html.encode("utf-8", errors="replace")).hexdigest(),
    )
    atomic_write(
        output.with_suffix(output.suffix + ".meta.json"),
        json.dumps(metadata, ensure_ascii=False, indent=2),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="保存 GreenTradingXXL 的渲染后页面源码。")
    parser.add_argument("--url", default=TARGET_URL)
    parser.add_argument("--out", default="greentradingxxl.html")
    parser.add_argument("--proxy", default=os.getenv("SCRAPE_PROXY", DEFAULT_PROXY))
    parser.add_argument("--timeout-ms", type=int, default=270_000)
    parser.add_argument(
        "--performance",
        choices=("reliable", "balanced", "fast"),
        default="balanced",
        help="可靠: 完整渲染后等 5 秒；均衡: 等 1.5 秒；快速: 不等 DOM 稳定且禁用非必要资源。",
    )
    parser.add_argument(
        "--settle-ms",
        type=int,
        help="覆盖性能档位的验证通过后等待时间；不改变 Cloudflare 内部验证节奏。",
    )
    parser.add_argument(
        "--cloak-deadline-sec",
        type=int,
        default=300,
        help="CloakBrowser 单次尝试的进程总时限，默认 300 秒。",
    )
    parser.add_argument(
        "--api-deadline-sec",
        type=int,
        default=300,
        help="Scrapling API 单次尝试的进程总时限，默认 300 秒。",
    )
    parser.add_argument("--headless", action="store_true", help="默认有头；此选项改为无头。")
    parser.add_argument("--allow-direct", action="store_true")
    parser.add_argument(
        "--engine",
        choices=("auto", "integrated", "api", "cloak", "cli"),
        default="auto",
        help="默认 auto: CloakBrowser+Scrapling CDP 后再尝试 Scrapling API；CLI 仅供显式诊断。",
    )
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    configure_logging(args.verbose)
    try:
        url = validate_url(args.url.strip())
    except ValueError as exc:
        parser.error(str(exc))
    if (
        args.timeout_ms < 5_000
        or (args.settle_ms is not None and args.settle_ms < 0)
        or args.cloak_deadline_sec < 15
        or args.api_deadline_sec < 15
    ):
        parser.error("超时参数不合法：--timeout-ms 至少为 5000，两个 deadline 至少为 15，--settle-ms 不能小于 0。")

    output = Path(args.out).expanduser().resolve()
    load_dom, disable_resources, settle_ms = resolve_performance_profile(
        args.performance, args.settle_ms
    )
    proxy = args.proxy.strip() if args.proxy else None
    try:
        available = proxy_is_reachable(proxy)
    except ValueError as exc:
        parser.error(str(exc))

    if not available:
        if not args.allow_direct:
            logging.error("代理不可用，且未启用 --allow-direct；拒绝意外直连。")
            return 2
        logging.warning("代理不可用，按 --allow-direct 使用直连。")
        proxy = None

    engines = {
        "auto": ("integrated", "api"),
        "integrated": ("integrated",),
        "api": ("api",),
        "cloak": ("cloak",),
        "cli": ("cli",),
    }[args.engine]
    last_error: Optional[Exception] = None
    for engine in engines:
        try:
            if engine == "integrated":
                result = fetch_with_cloak_scrapling_cdp_deadline(
                    url,
                    proxy,
                    args.timeout_ms,
                    args.headless,
                    settle_ms,
                    load_dom,
                    disable_resources,
                    args.cloak_deadline_sec,
                )
            elif engine == "api":
                result = fetch_with_scrapling_api_deadline(
                    url,
                    proxy,
                    args.timeout_ms,
                    args.headless,
                    settle_ms,
                    load_dom,
                    disable_resources,
                    args.api_deadline_sec,
                )
            elif engine == "cloak":
                result = fetch_with_cloakbrowser_deadline(
                    url,
                    proxy,
                    args.timeout_ms,
                    args.headless,
                    args.settle_ms,
                    args.cloak_deadline_sec,
                )
            else:
                result = fetch_with_scrapling_cli(
                    url, proxy, args.timeout_ms, args.headless, output
                )

            if len(result.html) < 1_000:
                raise FetchError(f"{engine} 返回内容过短: {len(result.html)} chars")
            if result.status and result.status >= 400:
                raise FetchError(f"{engine} 返回 HTTP {result.status}")
            if result.challenge_suspected:
                diagnostic = output.with_suffix(output.suffix + f".{engine}.challenge.html")
                atomic_write(diagnostic, result.html)
                raise FetchError(f"{engine} 返回疑似验证页，已保存诊断文件: {diagnostic}")

            save(result, url, output)
            logging.info(
                "成功保存: %s | engine=%s | status=%s | bytes=%s | elapsed=%ss",
                output,
                result.engine,
                result.status,
                len(result.html.encode("utf-8", errors="replace")),
                result.elapsed_sec,
            )
            return 0
        except Exception as exc:
            last_error = exc
            logging.warning("%s 失败: %s", engine, exc)

    logging.error("所有引擎均失败。最后错误: %s", last_error)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
