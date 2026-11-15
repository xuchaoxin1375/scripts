# -*- coding: utf-8 -*-
"""WebUI v2 浏览器验收：真实 FastAPI 静态托管 + Playwright 拦截 API 契约。

不访问 Cloudflare：所有 /api/v1 请求由 Playwright 用固定 JSON 响应。
覆盖：账号/域名/记录加载、选中、预览提交、任务详情、单条编辑、批量代理、
390 窄屏卡片与页面无横滚、零 pageerror。
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from urllib.parse import urlparse

ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)
START_PY = os.path.join(ROOT, "start_web_ui.py")
DIST = os.path.join(ROOT, "webui", "frontend-v2", "dist", "index.html")

ACCOUNTS = {
    "items": [
        {
            "name": "t1",
            "auth": "token",
            "email": "不可用",
            "secret": "secr...",
            "has_secret": True,
        }
    ]
}
ZONES = {
    "total": 2,
    "page": 1,
    "per_page": 200,
    "items": [
        {"name": "example.com", "status": "active", "id": "z1"},
        {"name": "shop.example.net", "status": "active", "id": "z2"},
    ],
    "account": "t1",
}
RECORDS = {
    "total": 3,
    "page": 1,
    "per_page": 200,
    "items": [
        {
            "id": "r1",
            "type": "A",
            "name": "example.com",
            "content": "203.0.113.10",
            "ttl": 1,
            "proxied": True,
            "comment": "",
            "priority": None,
        },
        {
            "id": "r2",
            "type": "A",
            "name": "www.example.com",
            "content": "203.0.113.10",
            "ttl": 1,
            "proxied": True,
            "comment": "",
            "priority": None,
        },
        {
            "id": "r3",
            "type": "CNAME",
            "name": "api.example.com",
            "content": "origin.example.net",
            "ttl": 300,
            "proxied": False,
            "comment": "api",
            "priority": None,
        },
    ],
    "account": "t1",
    "zone": "example.com",
}
JOB = {
    "job_id": "job-9001",
    "id": "job-9001",
    "label": "预览 update",
    "kind": "preview",
    "mode": "update",
    "status": "running",
    "accounts_done": 0,
    "accounts_total": 1,
    "current_account": "t1",
    "account_status": {"t1": "running"},
    "zone_summary": {"t1": {"total": 1, "done": 0}},
    "result_count": 0,
    "failure_count": 0,
    "anomaly_count": 0,
    "dry_run": True,
    "scope": {
        "accounts": ["t1"],
        "domains": ["example.com"],
        "whitelist_count": 0,
        "add_domain": None,
        "delete_ip": None,
    },
    "exit_code": None,
    "error": "",
    "created_at": "2026-11-15T17:00:00+08:00",
    "finished_at": "",
    "verdict": [],
}
META = {
    "version": "20260929",
    "speed_presets": {},
    "defaults": {},
    "dirs": {"backup_dir": "./cf_backup", "export_dir": "./cf_export"},
    "requires_auth": False,
    "config_path": "C:/Users/Administrator/Desktop/deploy_configs/cf_config.csv",
    "proxy": {"mode": "", "count": 0},
}


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_ready(base: str, timeout: float = 30.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{base}/api/v1/meta", timeout=2) as resp:
                if resp.status == 200:
                    return
        except Exception:
            time.sleep(0.4)
    raise RuntimeError("server not ready")


def main() -> None:
    if not os.path.exists(DIST):
        raise SystemExit(
            "缺少 dist/index.html：先执行 cd webui/frontend-v2 && npm run build"
        )
    from playwright.sync_api import sync_playwright

    shots = tempfile.mkdtemp(prefix="cf_v2_accept_")
    tmp = tempfile.mkdtemp(prefix="cf_v2_cfg_")
    cfg = os.path.join(tmp, "cf_config.json")
    with open(cfg, "w", encoding="utf-8") as handle:
        handle.write('{"accounts":{"smoke":{"cf_api_token":"dummy"}}}')
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    proc = subprocess.Popen(
        [
            sys.executable,
            "start_web_ui.py",
            "--frontend-v2",
            "--port",
            str(port),
            "--config",
            cfg,
        ],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    errors: list[str] = []

    def api(route) -> None:
        request = route.request
        path = urlparse(request.url).path
        method = request.method
        if path.endswith("/api/v1/meta"):
            route.fulfill(status=200, content_type="application/json", body=json.dumps(META))
        elif path.endswith("/api/v1/accounts"):
            route.fulfill(status=200, content_type="application/json", body=json.dumps(ACCOUNTS))
        elif path.endswith("/api/v1/zones"):
            route.fulfill(status=200, content_type="application/json", body=json.dumps(ZONES))
        elif path.endswith("/api/v1/records") and method == "GET":
            route.fulfill(status=200, content_type="application/json", body=json.dumps(RECORDS))
        elif path.endswith("/api/v1/records") and method == "PATCH":
            route.fulfill(
                status=200,
                content_type="application/json",
                body=json.dumps({"status": "updated", "message": "已更新"}),
            )
        elif path.endswith("/api/v1/records/bulk-update"):
            route.fulfill(
                status=200,
                content_type="application/json",
                body=json.dumps({"updated": ["r1", "r2"], "failed": [], "total": 2}),
            )
        elif path.endswith("/api/v1/jobs") and method == "GET":
            route.fulfill(
                status=200,
                content_type="application/json",
                body=json.dumps({"jobs": [JOB]}),
            )
        elif path.endswith("/api/v1/jobs") and method == "POST":
            route.fulfill(
                status=200,
                content_type="application/json",
                body=json.dumps({"job_id": "job-9002"}),
            )
        elif path.endswith("/api/v1/jobs/job-9001") and method == "GET":
            route.fulfill(status=200, content_type="application/json", body=json.dumps(JOB))
        elif path.endswith("/api/v1/jobs/job-9002") and method == "GET":
            preview = {
                **JOB,
                "job_id": "job-9002",
                "id": "job-9002",
                "status": "done",
                "accounts_done": 1,
                "zone_summary": {"t1": {"total": 1, "done": 1}},
                "failure_count": 0,
                "result_count": 3,
                "finished_at": "2026-11-15T17:00:10+08:00",
            }
            route.fulfill(
                status=200, content_type="application/json", body=json.dumps(preview)
            )
        elif path.endswith("/api/v1/jobs/job-9001/execute"):
            route.fulfill(
                status=200,
                content_type="application/json",
                body=json.dumps({"job_id": "job-9003"}),
            )
        elif path.endswith("/api/v1/jobs/job-9001/rerun"):
            route.fulfill(
                status=200,
                content_type="application/json",
                body=json.dumps({"job_id": "job-9004"}),
            )
        else:
            route.fulfill(
                status=404,
                content_type="application/json",
                body=json.dumps({"detail": f"not mocked: {method} {path}"}),
            )

    try:
        wait_ready(base)
        with sync_playwright() as pw:
            browser = pw.chromium.launch()
            page = browser.new_page(viewport={"width": 1440, "height": 1000})
            page.on("pageerror", lambda exc: errors.append(f"pageerror: {exc}"))
            page.route("**/api/v1/**", api)
            page.goto(base, wait_until="networkidle")
            page.wait_for_selector(".account-item", timeout=10_000)
            page.wait_for_function(
                "document.querySelectorAll('.records-table tbody tr').length === 3",
                timeout=10_000,
            )
            if page.locator(".account-item").count() != 1:
                raise AssertionError("账号数量不符合预期")
            page.screenshot(path=os.path.join(shots, "workspace_1440.png"))

            boxes = page.locator(".records-table tbody input[type=checkbox]")
            boxes.nth(0).check()
            boxes.nth(1).check()
            page.get_by_role("button", name="批量操作").click()
            page.get_by_placeholder("198.51.100.10 或 target.example.net").fill(
                "198.51.100.77"
            )
            page.get_by_role("button", name="预览变更").click()
            page.wait_for_selector("text=预览 · 尚未执行", timeout=10_000)
            if "job-9002" not in page.locator(".preview-job").inner_text():
                raise AssertionError("预览任务 ID 未显示")
            page.screenshot(path=os.path.join(shots, "preview_1440.png"))

            page.get_by_role("tab", name="任务").click()
            page.locator(".task-row").first.click()
            page.wait_for_selector("text=TASK DETAIL", timeout=10_000)
            page.screenshot(path=os.path.join(shots, "task_1440.png"))

            page.get_by_role("tab", name="操作").click()
            page.locator(".records-table tbody .row-action").first.click()
            page.wait_for_selector("text=编辑记录", timeout=10_000)
            page.get_by_role("button", name="保存记录").click()
            page.wait_for_selector("text=记录已保存", timeout=10_000)

            boxes.nth(0).check()
            boxes.nth(1).check()
            page.get_by_role("button", name="设为已代理").click()
            page.wait_for_selector("text=已设置 2 条记录为已代理", timeout=10_000)

            mobile = browser.new_page(viewport={"width": 390, "height": 900})
            mobile.on("pageerror", lambda exc: errors.append(f"mobile pageerror: {exc}"))
            mobile.route("**/api/v1/**", api)
            mobile.goto(base, wait_until="networkidle")
            mobile.wait_for_selector(".record-card", timeout=10_000)
            overflow = mobile.evaluate(
                "document.documentElement.scrollWidth - window.innerWidth"
            )
            if overflow > 1:
                raise AssertionError(f"390 页面横滚 {overflow}px")
            mobile.screenshot(path=os.path.join(shots, "workspace_390.png"))
            browser.close()
        if errors:
            raise AssertionError("; ".join(errors[:5]))
        print(f"BROWSER PASS v2 shots={shots}")
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()


if __name__ == "__main__":
    main()
