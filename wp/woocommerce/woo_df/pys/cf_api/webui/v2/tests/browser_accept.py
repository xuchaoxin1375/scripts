# -*- coding: utf-8 -*-
"""WebUI v2 浏览器验收：真实 FastAPI 静态托管 + Playwright 拦截 API 契约。

不访问 Cloudflare：所有 /api/v1 请求由 Playwright 用固定 JSON 响应。
覆盖：记录服务端分页、搜索、预览真实结果、任务详情、单条编辑、批量内容/删除、
高级页查找/历史/上传、390 窄屏无横滚与零 pageerror。
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
from urllib.parse import parse_qs, urlparse

ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)
START_PY = os.path.join(ROOT, "start_web_ui.py")
DIST = os.path.join(ROOT, "webui", "v2", "dist", "index.html")

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
    "per_page": 50,
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
PREVIEW_JOB = {
    **JOB,
    "job_id": "job-9002",
    "id": "job-9002",
    "status": "done",
    "accounts_done": 1,
    "zone_summary": {"t1": {"total": 1, "done": 1}},
    "failure_count": 0,
    "result_count": 3,
    "finished_at": "2026-11-15T17:00:10+08:00",
    "verdict": ["预览完成：将更新 3 条记录"],
}
PREVIEW_RESULTS = [
    {
        "account": "t1",
        "zone": "example.com",
        "name": "example.com",
        "type": "A",
        "old": "203.0.113.10",
        "new": "198.51.100.77",
        "status": "dry_run_update",
        "message": "预览",
    },
    {
        "account": "t1",
        "zone": "example.com",
        "name": "www.example.com",
        "type": "A",
        "old": "203.0.113.10",
        "new": "198.51.100.77",
        "status": "dry_run_update",
        "message": "预览",
    },
    {
        "account": "t1",
        "zone": "example.com",
        "name": "api.example.com",
        "type": "CNAME",
        "old": "origin.example.net",
        "new": "198.51.100.77",
        "status": "dry_run_update",
        "message": "预览",
    },
]
HISTORY = [
    {
        "id": "job-9002",
        "mode": "update",
        "status": "done",
        "label": "预览 update x1账号",
        "accounts": "t1",
        "exit_code": 0,
        "created_at": "2026-11-15T17:00:00+08:00",
        "finished_at": "2026-11-15T17:00:10+08:00",
    },
    {
        "id": "job-9001",
        "mode": "update",
        "status": "failed",
        "label": "执行 update x1账号",
        "accounts": "t1",
        "exit_code": 1,
        "created_at": "2026-11-15T16:00:00+08:00",
        "finished_at": "2026-11-15T16:01:00+08:00",
    },
]
AUDIT = [
    {
        "id": 1,
        "ts": "2026-11-15T17:00:10+08:00",
        "kind": "bulk_update",
        "account": "t1",
        "detail": "example.com 更新 2 条，失败 0 条",
    }
]
META = {
    "version": "20260929",
    "speed_presets": {
        "eco": {"account_workers": 3, "workers": 2, "request_interval": 0.5}
    },
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
            "缺少 dist/index.html：先执行 cd webui/v2 && npm run build"
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
    data_requests: list[tuple[str, str]] = []

    def api(route) -> None:
        request = route.request
        parsed = urlparse(request.url)
        path = parsed.path
        method = request.method
        query = parse_qs(parsed.query)
        data_requests.append((method, path))
        if path.endswith("/api/v1/meta"):
            body = META
        elif path.endswith("/api/v1/accounts"):
            body = ACCOUNTS
        elif path.endswith("/api/v1/zones"):
            body = ZONES
        elif path.endswith("/api/v1/records") and method == "GET":
            records = RECORDS
            wanted = query.get("type", ["ALL"])[0]
            if wanted != "ALL":
                records = {
                    **RECORDS,
                    "items": [r for r in RECORDS["items"] if r["type"] == wanted],
                }
            body = records
        elif path.endswith("/api/v1/records") and method == "PATCH":
            body = {"status": "updated", "message": "已更新"}
        elif path.endswith("/api/v1/records/bulk-update"):
            body = {"updated": ["r1", "r2"], "failed": [], "total": 2}
        elif path.endswith("/api/v1/records/bulk-delete"):
            body = {"deleted": [{"id": "r1"}], "failed": [], "total": 1}
        elif path.endswith("/api/v1/records/import"):
            payload = json.loads(request.post_data or "{}")
            body = (
                {"checked": len(payload.get("records", [])), "errors": [], "failed": [], "total": 0}
                if payload.get("dry_run")
                else {
                    "added": 1,
                    "updated": 0,
                    "unchanged": 0,
                    "failed": [],
                    "errors": [],
                    "total": 1,
                }
            )
        elif path.endswith("/api/v1/jobs") and method == "GET":
            body = {"jobs": [JOB, PREVIEW_JOB]}
        elif path.endswith("/api/v1/jobs") and method == "POST":
            body = {"job_id": "job-9002"}
        elif path.endswith("/api/v1/jobs/job-9002/results"):
            body = {
                "total": len(PREVIEW_RESULTS),
                "page": int(query.get("page", ["1"])[0]),
                "per_page": int(query.get("per_page", ["50"])[0]),
                "items": PREVIEW_RESULTS,
            }
        elif path.endswith("/api/v1/jobs/job-9002/logs"):
            body = {
                "job_id": "job-9002",
                "total": 2,
                "offset": 0,
                "logs": ["[job] job-9002 已创建", "[progress] 3/3"],
            }
        elif path.endswith("/api/v1/jobs/job-9002/exports"):
            body = {"job_id": "job-9002", "total": 0, "items": []}
        elif path.endswith("/api/v1/jobs/job-9002"):
            body = PREVIEW_JOB
        elif path.endswith("/api/v1/jobs/job-9001/logs"):
            body = {"job_id": "job-9001", "total": 1, "offset": 0, "logs": ["[job] running"]}
        elif path.endswith("/api/v1/jobs/job-9001"):
            body = JOB
        elif path.endswith("/api/v1/jobs/job-9001/execute"):
            body = {"job_id": "job-9003"}
        elif path.endswith("/api/v1/jobs/job-9001/rerun"):
            body = {"job_id": "job-9004"}
        elif path.endswith("/api/v1/history"):
            body = {"items": HISTORY, "total": len(HISTORY), "limit": 50, "offset": 0}
        elif path.endswith("/api/v1/audit"):
            body = {"items": AUDIT, "total": len(AUDIT), "limit": 50, "offset": 0}
        elif path.endswith("/api/v1/find"):
            body = {
                "domain": query.get("domain", [""])[0],
                "found": 1,
                "results": [
                    {
                        "account": "t1",
                        "zone": "example.com",
                        "zone_id": "z1",
                        "status": "active",
                        "record_count": 3,
                    }
                ],
            }
        elif path.endswith("/api/v1/whitelist-upload"):
            body = {
                "path": "/tmp/w.txt",
                "count": 2,
                "domains": ["example.com", "shop.example.net"],
            }
        elif path.endswith("/api/v1/resume-upload"):
            body = {"path": "/tmp/r.csv", "rows": 1, "zones": ["example.com"]}
        else:
            errors.append(f"not mocked: {method} {path}")
            route.fulfill(
                status=404,
                content_type="application/json",
                body=json.dumps({"detail": f"not mocked: {method} {path}"}),
            )
            return
        route.fulfill(
            status=200, content_type="application/json", body=json.dumps(body)
        )

    try:
        wait_ready(base)
        with sync_playwright() as pw:
            browser = pw.chromium.launch()
            page = browser.new_page(viewport={"width": 1440, "height": 1000})
            page.on("pageerror", lambda exc: errors.append(f"pageerror: {exc}"))
            page.on(
                "console",
                lambda msg: errors.append(f"console-{msg.type}: {msg.text}")
                if msg.type == "error"
                else None,
            )
            page.route("**/api/v1/**", api)
            page.goto(base, wait_until="networkidle")
            page.wait_for_selector(".account-item", timeout=10_000)
            page.wait_for_function(
                "document.querySelectorAll('.records-table tbody tr').length === 3",
                timeout=10_000,
            )
            if page.locator(".account-item").count() != 1:
                raise AssertionError("账号数量不符合预期")
            if "共 3 条" not in page.locator(".records-footer span").first.inner_text():
                raise AssertionError("记录总数未按服务端分页显示")
            page.screenshot(path=os.path.join(shots, "workspace_1440.png"))

            boxes = page.locator(".records-table tbody input[type=checkbox]")
            boxes.nth(0).check()
            boxes.nth(1).check()
            page.get_by_role("button", name="改选中内容").click()
            page.get_by_placeholder("198.51.100.10 或 target.example.net").fill(
                "198.51.100.88"
            )
            page.get_by_role("button", name="确认写入").click()
            page.wait_for_selector("text=已更新 2 条记录内容", timeout=10_000)
            page.screenshot(path=os.path.join(shots, "bulk_content_1440.png"))

            boxes.nth(0).check()
            page.locator(".bulk-bar").get_by_role("button", name="删除", exact=True).click()
            page.get_by_text("我已核对范围，确认删除").click()
            page.get_by_role("button", name="删除 1 条").click()
            page.wait_for_selector("text=已删除 1 条记录", timeout=10_000)

            page.get_by_role("button", name="批量操作").click()
            page.get_by_placeholder("198.51.100.10 或 target.example.net").fill(
                "198.51.100.77"
            )
            page.get_by_role("button", name="预览变更").click()
            page.wait_for_selector("text=预览 · 尚未执行", timeout=10_000)
            page.wait_for_selector("text=预览任务返回 3 条变更", timeout=10_000)
            if "job-9002" not in page.locator(".preview-job").inner_text():
                raise AssertionError("预览任务 ID 未显示")
            page.screenshot(path=os.path.join(shots, "preview_1440.png"))

            page.get_by_role("tab", name="任务").click()
            page.locator(".task-row", has_text="job-9002").click()
            page.wait_for_selector("text=TASK DETAIL", timeout=10_000)
            page.wait_for_selector("text=[job] job-9002 已创建", timeout=10_000)
            page.screenshot(path=os.path.join(shots, "task_1440.png"))

            page.get_by_role("tab", name="操作").click()
            page.locator(".records-table tbody .row-action").first.click()
            page.wait_for_selector("text=编辑记录", timeout=10_000)
            page.get_by_role("button", name="保存记录").click()
            page.wait_for_selector("text=记录已保存", timeout=10_000)

            page.get_by_role("button", name="高级页").click()
            page.wait_for_selector("text=历史与审计", timeout=10_000)
            page.wait_for_selector("text=job-9002", timeout=10_000)
            page.get_by_role("button", name="审计日志").click()
            page.wait_for_selector("text=bulk_update", timeout=10_000)
            page.get_by_placeholder("example.com").first.fill("example.com")
            page.get_by_role("button", name="查找", exact=True).click()
            page.wait_for_selector("text=命中 1 个账号", timeout=10_000)
            page.screenshot(path=os.path.join(shots, "advanced_1440.png"), full_page=True)

            file_input = page.locator(".drop-zone input[type=file]").first
            with tempfile.NamedTemporaryFile(
                "w", suffix=".txt", delete=False, encoding="utf-8"
            ) as handle:
                handle.write("example.com\nshop.example.net\n")
                whitelist_file = handle.name
            file_input.set_input_files(whitelist_file)
            page.wait_for_selector("text=已附加 2 个域名", timeout=10_000)
            os.unlink(whitelist_file)

            page.get_by_role("button", name="回到工作台").click()
            page.wait_for_selector("text=白名单 2 域", timeout=10_000)
            page.screenshot(path=os.path.join(shots, "attachment_1440.png"))

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
            mobile.goto(base + "/#/advanced", wait_until="networkidle")
            mobile.wait_for_selector("text=历史与审计", timeout=10_000)
            mobile_overflow = mobile.evaluate(
                "document.documentElement.scrollWidth - window.innerWidth"
            )
            if mobile_overflow > 1:
                raise AssertionError(f"390 高级页横滚 {mobile_overflow}px")
            mobile.screenshot(path=os.path.join(shots, "advanced_390.png"), full_page=True)
            browser.close()
        if errors:
            raise AssertionError("; ".join(errors[:6]))
        if not any(path.endswith("/api/v1/records") for _m, path in data_requests):
            raise AssertionError("没有请求记录接口")
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
