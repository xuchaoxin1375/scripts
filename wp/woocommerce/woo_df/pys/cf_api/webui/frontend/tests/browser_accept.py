# -*- coding: utf-8 -*-
"""浏览器模拟验收：真服务 + 合成实例 + 用户路径 + 视口截图。

合成实例声明（只证代码路径，不证现网）：
- 临时 dummy 配置、临时端口、本机回环；唯一写操作是 dry_run 预览任务
  （dummy token 在读 zone 阶段即失败，不产生任何 Cloudflare 写操作）。
- 需要真实写入/现网证据时另走审批，不在本脚本内做。

覆盖：
- 三宽 390/768/1440 首屏渲染（标题/导航可见）+ 无页面级横滚；
- 路由切换（概览/浏览/操作/任务）；
- 端到端提交链：操作页填表 → 提交 → 任务终态 → 日志非空 → verdict 可见；
- 零 pageerror / 零 JS console error（资源 404 另记噪音）；
- 视口截图留证 TEMP（full-page 不判定 sticky）。
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

PORT = 8603
BASE = f"http://127.0.0.1:{PORT}"
WIDTHS = (390, 768, 1440)
JOB_TIMEOUT = 120


def fail(msg: str) -> None:
    print(f"BROWSER FAIL: {msg}")
    sys.exit(1)


def wait_ready(timeout: float = 30.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{BASE}/api/v1/meta", timeout=3) as resp:
                if json.load(resp).get("version"):
                    return
        except Exception:
            time.sleep(1)
    fail("server not ready")


def main() -> None:
    from playwright.sync_api import sync_playwright

    tmp = tempfile.mkdtemp(prefix="cf_bacc_")
    fixed = os.getenv("CF_SHOTS_DIR", "")
    shots = fixed if fixed else tmp
    if fixed:
        os.makedirs(shots, exist_ok=True)
    cfg = os.path.join(tmp, "cf_config.json")
    with open(cfg, "w", encoding="utf-8") as fh:
        fh.write('{"accounts":{"smoke":{"cf_api_token":"dummy"}}}')
    root = os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    )
    proc = subprocess.Popen(
        [sys.executable, "start_web_ui.py", "--port", str(PORT), "--config", cfg],
        cwd=root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    errors: list[str] = []
    noise: list[str] = []

    def on_console(msg) -> None:
        text = f"console-{msg.type}: {msg.text}"
        if msg.type == "error" and "Failed to load resource" in msg.text:
            noise.append(text)
        elif msg.type == "error":
            errors.append(text)

    def on_console_tagged(msg, tag: str) -> None:
        text = f"console-{msg.type}{tag}: {msg.text}"
        if msg.type == "error" and "Failed to load resource" in msg.text:
            noise.append(text)
        elif msg.type == "error":
            errors.append(text)

    try:
        wait_ready()
        with sync_playwright() as pw:
            browser = pw.chromium.launch()
            try:
                for width in WIDTHS:
                    page = browser.new_page(viewport={"width": width, "height": 900})
                    tag = f"@{width}"
                    page.on(
                        "pageerror",
                        lambda exc, t=tag: errors.append(f"pageerror{t}: {exc}"),
                    )
                    page.on("console", lambda msg, t=tag: on_console_tagged(msg, t))
                    page.goto(BASE, wait_until="networkidle")
                    if "Cloudflare" not in page.title():
                        fail(f"width={width} 标题异常: {page.title()!r}")
                    for route in ("overview", "browse", "operate", "jobs"):
                        if width < 768:
                            page.click("#btnMenu")
                            page.wait_for_function(
                                "document.body.dataset.drawer === '1'", timeout=5000
                            )
                        page.click(f"#sidebar nav a[data-route='{route}']")
                        page.wait_for_selector(f"#page-{route}.active", timeout=5000)
                    # 关抽屉等过渡走完再量（closed 态不得有横滚）
                    page.evaluate("document.body.dataset.drawer = '0'")
                    page.wait_for_timeout(400)
                    # 移开鼠标等 peek 消退，截 rail 真态（退出延迟 220ms）
                    page.mouse.move(width - 20, 450)
                    page.wait_for_timeout(500)
                    overflow = page.evaluate(
                        "document.documentElement.scrollWidth - window.innerWidth"
                    )
                    if overflow > 1:
                        fail(f"width={width} 页面横滚 {overflow}px")
                    if width < 768:
                        # 开抽屉覆盖态同样不得有横滚（fixed 覆盖层）
                        page.click("#btnMenu")
                        page.wait_for_function(
                            "document.body.dataset.drawer === '1'", timeout=5000
                        )
                        page.wait_for_timeout(300)
                        overflow = page.evaluate(
                            "document.documentElement.scrollWidth - window.innerWidth"
                        )
                        if overflow > 1:
                            fail(f"width={width} 抽屉开态横滚 {overflow}px")
                        page.evaluate("document.body.dataset.drawer = '0'")
                        page.wait_for_timeout(400)
                    page.screenshot(path=os.path.join(shots, f"shot_{width}.png"))
                    page.close()
                # 端到端提交链（填表→提交→任务→日志非空→verdict）
                page = browser.new_page(viewport={"width": 1440, "height": 900})
                page.on(
                    "pageerror", lambda exc: errors.append(f"pageerror@flow: {exc}")
                )
                page.goto(f"{BASE}#/operate", wait_until="networkidle")
                page.wait_for_selector("#oSubmit", timeout=10000)
                page.fill("#oDomains", "example.com")
                page.fill("#oNew", "1.2.3.4")
                page.click("#oSubmit")
                page.wait_for_url("**#/jobs", timeout=10000)
                page.wait_for_selector(
                    "#jVerdict:not([hidden])", timeout=JOB_TIMEOUT * 1000
                )
                logs = page.inner_text("#jLogs")
                if len(logs.strip()) < 5:
                    fail("任务日志为空")
                verdict = page.inner_text("#jVerdict")
                if (
                    "失败" not in verdict
                    and "未完美执行" not in verdict
                    and "完美执行" not in verdict
                ):
                    fail(f"verdict 不可见: {verdict[:80]!r}")
                page.screenshot(path=os.path.join(shots, "shot_flow.png"))
                page.close()
            finally:
                browser.close()
    finally:
        if proc.poll() is None:
            proc.terminate()
    if errors:
        fail("; ".join(errors[:5]))
    if noise:
        print(f"BROWSER noise(资源 502，合成 dummy 实例预期): {len(noise)} 条")
    print(f"BROWSER PASS shots={tmp}")


if __name__ == "__main__":
    main()
