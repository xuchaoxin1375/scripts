# -*- coding: utf-8 -*-
"""WebUI v2 浏览器验收：真实 FastAPI 静态托管 + Playwright 拦截 API 契约。

不访问 Cloudflare：所有 /api/v1 请求由 Playwright 用固定 JSON 响应。
覆盖：记录服务端分页、搜索、预览真实结果、任务详情、单条编辑、批量内容/删除、
高级页查找/历史/上传、邮箱转发目标验证/完成 catch-all、侧栏默认展开/页脚收起/Rail
悬停与键盘临时展开/Esc/快捷键、390 窄屏无横滚与零 pageerror。
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
EMAIL_ADDRESSES = [
    {
        "id": "a1",
        "email": "owner@gmail.com",
        "verified": True,
        "created": "",
        "modified": "",
    },
    {
        "id": "a2",
        "email": "pending@example.net",
        "verified": False,
        "created": "",
        "modified": "",
    },
]
EMAIL_STATUS = {
    "zone": "example.com",
    "zone_id": "z1",
    "zone_status": "active",
    "routing_enabled": True,
    "catch_all": {
        "enabled": False,
        "forward_to": [],
        "name": "catch-all",
    },
    "required_records": [
        {
            "type": "MX",
            "name": "example.com",
            "content": "route1.mx.cloudflare.net",
            "priority": 10,
        }
    ],
    "mx_records": [
        {
            "name": "example.com",
            "content": "route1.mx.cloudflare.net",
            "priority": 10,
        }
    ],
    "non_cloudflare_mx": [],
    "records_error": "",
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
    email_addresses = [dict(item) for item in EMAIL_ADDRESSES]
    email_status = {
        **EMAIL_STATUS,
        "catch_all": {
            **EMAIL_STATUS["catch_all"],
            "forward_to": list(EMAIL_STATUS["catch_all"]["forward_to"]),
        },
    }
    data_requests: list[tuple[str, str]] = []
    job_posts: list[dict] = []

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
        elif path.endswith("/api/v1/email-routing/addresses") and method == "GET":
            account_name = query.get("account", [""])[0]
            wanted = query.get("email", [""])[0].strip().lower()
            target = next(
                (
                    item
                    for item in email_addresses
                    if item["email"].lower() == wanted
                ),
                None,
            )
            body = {
                "account": account_name,
                "total": len(email_addresses),
                "items": email_addresses,
                "target": target,
            }
        elif path.endswith("/api/v1/email-routing/status"):
            body = {
                **email_status,
                "account": query.get("account", [""])[0],
                "zone": query.get("zone", ["example.com"])[0],
            }
        elif path.endswith("/api/v1/email-routing/addresses") and method == "POST":
            payload = json.loads(request.post_data or "{}")
            account_name = str(payload.get("account", ""))
            wanted = str(payload.get("email", "")).strip().lower()
            existing = next(
                (
                    item
                    for item in email_addresses
                    if item["email"].lower() == wanted
                ),
                None,
            )
            if existing is not None:
                body = {
                    "account": account_name,
                    "email": wanted,
                    "found": True,
                    "verified": bool(existing["verified"]),
                    "created": False,
                    "message": "目标邮箱已存在；请检查验证状态。",
                }
            else:
                item = {
                    "id": f"a{len(email_addresses) + 1}",
                    "email": wanted,
                    "verified": False,
                    "created": "",
                    "modified": "",
                }
                email_addresses.append(item)
                body = {
                    "account": account_name,
                    "email": wanted,
                    "found": True,
                    "verified": False,
                    "created": True,
                    "message": "已添加目标邮箱，Cloudflare 已发送验证邮件。",
                }
        elif path.endswith("/api/v1/email-routing/complete"):
            payload = json.loads(request.post_data or "{}")
            target_email = str(payload.get("email", ""))
            email_status["catch_all"] = {
                "enabled": True,
                "forward_to": [target_email],
                "name": "catch-all",
            }
            body = {
                "account": str(payload.get("account", "")),
                "zone": str(payload.get("zone", "")),
                "email": target_email,
                "status": "ok",
                "message": f"邮箱转发已配置到 {target_email}",
                "records": ["MX example.com: ok"],
            }
        elif path.endswith("/api/v1/jobs") and method == "GET":
            body = {"jobs": [JOB, PREVIEW_JOB]}
        elif path.endswith("/api/v1/jobs") and method == "POST":
            job_posts.append(json.loads(request.post_data or "{}"))
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
            page.wait_for_selector(".resource-trigger", timeout=10_000)
            page.wait_for_function(
                "document.querySelectorAll('.records-table tbody tr').length === 3",
                timeout=10_000,
            )
            if page.locator(".sidebar .nav-link").count() < 3:
                raise AssertionError("全局侧栏导航项数量不符合预期")
            if page.locator(".app.rail").count() != 0:
                raise AssertionError("桌面首次访问侧栏应默认展开")
            if page.get_by_role("button", name="展开侧栏").count() != 0:
                raise AssertionError("顶栏不应保留重复的侧栏折叠按钮")
            expanded_width = page.locator(".sidebar").evaluate(
                "el => Math.round(el.getBoundingClientRect().width)"
            )
            if expanded_width < 240:
                raise AssertionError(f"桌面展开侧栏宽度异常: {expanded_width}")
            page.screenshot(path=os.path.join(shots, "sidebar_expanded_1440.png"))
            page.keyboard.press("Tab")
            if not page.evaluate(
                "document.activeElement?.classList.contains('skip-link')"
            ):
                raise AssertionError("首个 Tab 未聚焦跳到主要内容")
            page.keyboard.press("Enter")
            page.wait_for_timeout(50)
            if not page.evaluate("document.activeElement?.id === 'main'"):
                raise AssertionError("跳到主要内容未把焦点移到 main")
            page.locator(".resource-trigger").click()
            page.wait_for_selector(".resource-menu", timeout=10_000)
            if page.locator('[data-resource-kind="account"]').count() != 1:
                raise AssertionError("账号数量不符合预期")
            if page.locator('[data-resource-kind="zone"]').count() != 2:
                raise AssertionError("域名数量不符合预期")
            page.keyboard.press("Escape")
            page.wait_for_selector(".resource-menu", state="detached", timeout=5_000)
            if not page.evaluate(
                "document.activeElement === document.querySelector('.resource-trigger')"
            ):
                raise AssertionError("资源切换器关闭后焦点未回到触发器")
            if "共 3 条" not in page.locator(".records-footer span").first.inner_text():
                raise AssertionError("记录总数未按服务端分页显示")
            page.screenshot(path=os.path.join(shots, "workspace_1440.png"))
            page.get_by_role("button", name="切换到深色主题").click()
            page.wait_for_timeout(160)
            page.screenshot(path=os.path.join(shots, "workspace_dark_1440.png"))
            page.get_by_role("button", name="切换到浅色主题").click()

            page.get_by_role("button", name="收起侧栏").click(
                position={"x": 18, "y": 19}
            )
            page.wait_for_timeout(320)
            if page.locator(".app.rail").count() != 1:
                raise AssertionError("页脚收起侧栏失败")
            if page.locator(".sidebar").get_attribute("data-state") != "rail":
                raise AssertionError("手动收起后指针仍在 Rail 上，却立即弹回")
            rail_main_left = page.locator(".main").bounding_box()["x"]
            rail_width = page.locator(".sidebar").evaluate(
                "el => Math.round(el.getBoundingClientRect().width)"
            )
            if rail_width > 80:
                raise AssertionError(f"Rail 宽度异常: {rail_width}")
            page.screenshot(path=os.path.join(shots, "sidebar_rail_1440.png"))
            collapse_metrics = page.locator(".sidebar-collapse").evaluate(
                """el => ({
                  h: Math.round(el.getBoundingClientRect().height),
                  icon: Math.round(el.querySelector('svg').getBoundingClientRect().width),
                })"""
            )
            if collapse_metrics["h"] > 42 or collapse_metrics["icon"] < 16:
                raise AssertionError(f"Rail 页脚折叠按钮尺寸异常: {collapse_metrics}")
            rail_icon_y = page.locator(".sidebar .nav-link .nav-icon").first.evaluate(
                "el => el.getBoundingClientRect().y"
            )

            page.mouse.move(900, 700)
            page.wait_for_timeout(80)
            page.locator(".sidebar").hover()
            page.wait_for_timeout(480)
            if page.locator(".sidebar").get_attribute("data-state") != "peek":
                raise AssertionError("Rail 悬停未进入临时展开")
            peek_width = page.locator(".sidebar").evaluate(
                "el => Math.round(el.getBoundingClientRect().width)"
            )
            if peek_width < 240:
                raise AssertionError(f"悬停展开宽度异常: {peek_width}")
            if abs(page.locator(".main").bounding_box()["x"] - rail_main_left) > 1:
                raise AssertionError("悬停展开推挤了主内容槽宽")
            peek_icon_y = page.locator(".sidebar .nav-link .nav-icon").first.evaluate(
                "el => el.getBoundingClientRect().y"
            )
            if abs(peek_icon_y - rail_icon_y) > 1:
                raise AssertionError(
                    f"悬停展开使导航图标位移: {rail_icon_y} -> {peek_icon_y}"
                )
            page.screenshot(path=os.path.join(shots, "sidebar_peek_1440.png"))
            page.get_by_role("link", name="高级工具", exact=True).click()
            page.wait_for_selector("text=历史与审计", timeout=10_000)
            page.get_by_role("link", name="DNS 记录", exact=True).click()
            page.wait_for_selector(".records-table tbody tr", timeout=10_000)
            page.locator("#main").focus()

            page.mouse.move(900, 700)
            page.wait_for_timeout(320)
            if page.locator(".sidebar").get_attribute("data-state") != "rail":
                raise AssertionError("指针离开后侧栏未回到 Rail")

            page.get_by_role("button", name="保持展开").click()
            page.wait_for_timeout(320)
            if page.locator(".app.rail").count() != 0:
                raise AssertionError("页脚保持展开失败")

            page.keyboard.press("[")
            page.wait_for_timeout(320)
            if page.locator(".app.rail").count() != 1:
                raise AssertionError("快捷键 [ 未收起侧栏")

            page.evaluate("document.activeElement?.blur()")
            page.locator(".sidebar-collapse").focus()
            page.wait_for_timeout(100)
            if page.locator(".sidebar").get_attribute("data-state") != "peek":
                raise AssertionError("键盘进入 Rail 未临时展开")

            page.keyboard.press("Escape")
            page.wait_for_timeout(120)
            if page.locator(".sidebar").get_attribute("data-state") != "rail":
                raise AssertionError("Esc 未收起临时展开")
            if not page.evaluate(
                "document.activeElement?.classList.contains('sidebar-collapse')"
            ):
                raise AssertionError("Esc 收起后焦点未回到侧栏折叠按钮")

            page.get_by_role("button", name="保持展开").click()
            page.wait_for_timeout(320)
            if page.locator(".app.rail").count() != 0:
                raise AssertionError("恢复展开侧栏失败")

            page.get_by_role("button", name="新增记录").click()
            page.wait_for_selector("#add-record-title", timeout=10_000)
            page.wait_for_timeout(80)
            if not page.evaluate(
                'document.activeElement?.id === "add-record-name"'
            ):
                raise AssertionError("新增记录弹窗首焦不在名称输入框")
            page.keyboard.press("Escape")
            page.wait_for_selector("#add-record-title", state="detached", timeout=5_000)
            page.wait_for_timeout(80)
            if not page.evaluate(
                'document.activeElement?.hasAttribute("data-add-record")'
            ):
                raise AssertionError("新增记录弹窗关闭后焦点未回到触发器")

            boxes = page.locator(".records-table tbody input[type=checkbox]")
            boxes.nth(0).check()
            boxes.nth(1).check()
            page.locator(".bulk-bar").get_by_role(
                "button", name="改选中内容"
            ).click()
            page.locator("#bulk-content-input").fill("198.51.100.88")
            page.get_by_role("button", name="确认写入").click()
            page.wait_for_selector("text=已更新 2 条记录内容", timeout=10_000)
            page.screenshot(path=os.path.join(shots, "bulk_content_1440.png"))

            boxes.nth(0).check()
            page.locator(".bulk-bar").get_by_role("button", name="删除", exact=True).click()
            page.get_by_text("我已核对范围，确认删除").click()
            page.get_by_role("button", name="删除 1 条").click()
            page.wait_for_selector("text=已删除 1 条记录", timeout=10_000)

            page.get_by_role("button", name="批量操作").click()
            page.wait_for_selector(".drawer.open", timeout=10_000)
            page.wait_for_timeout(80)
            if page.locator(".drawer").get_attribute("aria-modal") is not None:
                raise AssertionError("宽屏批量抽屉不应按模态打开")
            if not page.evaluate(
                'document.activeElement?.getAttribute("aria-label") === "关闭面板"'
            ):
                raise AssertionError("批量抽屉打开后首焦不在关闭按钮")
            page.get_by_role("button", name="关闭面板", exact=True).click()
            page.wait_for_timeout(240)
            if page.locator(".drawer.open").count() != 0:
                raise AssertionError("批量抽屉未关闭")
            if not page.evaluate(
                "document.activeElement?.textContent?.includes('批量操作')"
            ):
                raise AssertionError("批量抽屉关闭后焦点未回到触发器")
            page.get_by_role("button", name="批量操作").click()
            page.wait_for_selector(".drawer.open", timeout=10_000)
            page.wait_for_timeout(240)
            page.locator(".action-card", has_text="更新记录内容").click()
            page.locator(".drawer .inspector-body").get_by_placeholder(
                "198.51.100.10 或 target.example.net"
            ).fill("198.51.100.77")
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
            page.wait_for_selector("#edit-record-title", timeout=10_000)
            page.wait_for_timeout(80)
            if not page.evaluate(
                'document.activeElement?.id === "edit-record-name"'
            ):
                raise AssertionError("编辑记录弹窗首焦不在名称输入框")
            page.get_by_role("button", name="保存记录").click()
            page.wait_for_selector("text=记录已保存", timeout=10_000)
            page.wait_for_selector("#edit-record-title", state="detached", timeout=5_000)
            page.wait_for_timeout(80)
            active_class = page.evaluate(
                "document.activeElement?.className || ''"
            )
            if "row-action" not in active_class and "records-panel" not in active_class:
                raise AssertionError("编辑记录弹窗关闭后焦点未回到行操作或记录区")

            row = page.locator(".records-table tbody tr").first
            row.locator(".row-action", has_text="删除").click()
            page.wait_for_selector("#bulk-delete-title", timeout=10_000)
            if page.locator("#bulk-delete-title").inner_text() != "删除记录":
                raise AssertionError("单条删除确认标题不正确")
            page.get_by_text("我已核对范围，确认删除").click()
            page.get_by_role("button", name="删除 1 条").click()
            page.wait_for_selector("text=已删除 1 条记录", timeout=10_000)
            page.wait_for_selector("#bulk-delete-title", state="detached", timeout=5_000)

            page.get_by_role("button", name="新增记录").click()
            page.wait_for_selector("#add-record-title", timeout=10_000)
            page.locator("#add-record-name").fill("_webui-accept-add")
            page.locator("#add-record-content").fill("198.51.100.99")
            page.get_by_role("button", name="提交预览").click()
            page.wait_for_selector("text=预览 · 尚未执行", timeout=10_000)
            page.wait_for_selector("text=预览任务返回 3 条变更", timeout=10_000)
            page.wait_for_selector("#add-record-title", state="detached", timeout=5_000)
            if not job_posts or job_posts[-1].get("mode") != "add":
                raise AssertionError("新增记录未提交 add 预览任务")
            add_payload = job_posts[-1]
            if add_payload.get("dry_run") is not True:
                raise AssertionError("新增记录预览未使用 dry_run")
            if add_payload.get("domains") != ["example.com"]:
                raise AssertionError("新增记录预览范围不是当前域名")
            if not any(
                "_webui-accept-add:A:198.51.100.99" in item
                for item in (add_payload.get("add_records") or [])
            ):
                raise AssertionError("新增记录预览缺少 add_records 规格")
            page.screenshot(path=os.path.join(shots, "add_preview_1440.png"))

            page.screenshot(path=os.path.join(shots, "drawer_1440.png"))
            page.get_by_role("link", name="高级工具").click()
            page.wait_for_selector("text=历史与审计", timeout=10_000)
            page.wait_for_selector("text=job-9002", timeout=10_000)
            page.get_by_role("button", name="审计日志").click()
            page.wait_for_selector("text=bulk_update", timeout=10_000)
            page.get_by_placeholder("example.com").first.fill("example.com")
            page.get_by_role("button", name="查找", exact=True).click()
            page.wait_for_selector("text=命中 1 个账号", timeout=10_000)
            page.screenshot(path=os.path.join(shots, "advanced_1440.png"), full_page=True)

            email_panel = page.locator("section.panel").filter(
                has_text="邮箱转发（Email Routing）"
            )
            email_panel.get_by_text("邮箱转发注意事项（首次配置必看）").click()
            if not email_panel.get_by_text("目标邮箱必须先验证").is_visible():
                raise AssertionError("邮箱转发注意事项未展开")
            email_panel.get_by_placeholder("you@gmail.com").fill("owner@gmail.com")
            if not email_panel.get_by_text(
                "目标邮箱已验证，可以完成 catch-all 配置。"
            ).is_visible():
                raise AssertionError("已验证目标邮箱未显示可完成状态")
            email_panel.get_by_role("button", name="验证后完成配置").click()
            page.wait_for_selector("text=邮箱转发已配置到 owner@gmail.com", timeout=10_000)
            email_panel.get_by_placeholder("you@gmail.com").fill("new@gmail.com")
            email_panel.get_by_role("button", name="添加并发送验证").click()
            page.wait_for_selector("text=已添加目标邮箱，Cloudflare 已发送验证邮件", timeout=10_000)
            if not email_panel.get_by_text(
                "目标邮箱已添加，等待验证；请检查收件箱和垃圾箱。"
            ).is_visible():
                raise AssertionError("新目标邮箱未显示待验证状态")
            provision_panel = page.locator("section.panel").filter(
                has_text="域名配置向导"
            )
            provision_panel.get_by_placeholder("admin@example.com").fill("new@gmail.com")
            if not provision_panel.get_by_text("目标邮箱尚未验证").is_visible():
                raise AssertionError("provision 未提示目标邮箱未验证")
            if not any(
                path.endswith("/api/v1/email-routing/complete")
                for _method, path in data_requests
            ):
                raise AssertionError("未提交邮箱转发完成请求")
            email_panel.scroll_into_view_if_needed()
            page.wait_for_timeout(120)
            page.screenshot(path=os.path.join(shots, "email_routing_view_1440.png"))
            page.screenshot(
                path=os.path.join(shots, "email_routing_1440.png"), full_page=True
            )

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

            tablet = browser.new_page(viewport={"width": 768, "height": 900})
            tablet.on("pageerror", lambda exc: errors.append(f"tablet pageerror: {exc}"))
            tablet.route("**/api/v1/**", api)
            tablet.goto(base, wait_until="networkidle")
            tablet.wait_for_selector(".record-card", state="visible", timeout=10_000)
            tablet_overflow = tablet.evaluate(
                "document.documentElement.scrollWidth - window.innerWidth"
            )
            if tablet_overflow > 1:
                raise AssertionError(f"768 页面横滚 {tablet_overflow}px")
            tablet.screenshot(path=os.path.join(shots, "workspace_768.png"))
            tablet.close()

            compact = browser.new_page(viewport={"width": 1024, "height": 900})
            compact.on("pageerror", lambda exc: errors.append(f"1024 pageerror: {exc}"))
            compact.route("**/api/v1/**", api)
            compact.goto(base, wait_until="networkidle")
            compact.wait_for_selector(".records-table tbody tr", timeout=10_000)
            if not compact.locator(".table-wrap").is_visible():
                raise AssertionError("1024 记录表未显示")
            compact_overflow = compact.evaluate(
                "document.documentElement.scrollWidth - window.innerWidth"
            )
            if compact_overflow > 1:
                raise AssertionError(f"1024 页面横滚 {compact_overflow}px")
            compact.screenshot(path=os.path.join(shots, "workspace_1024.png"))
            compact.close()

            mobile = browser.new_page(viewport={"width": 390, "height": 900})
            mobile.on("pageerror", lambda exc: errors.append(f"mobile pageerror: {exc}"))
            mobile.route("**/api/v1/**", api)
            mobile.goto(base, wait_until="networkidle")
            mobile.wait_for_selector(".record-card", state="visible", timeout=10_000)
            overflow = mobile.evaluate(
                "document.documentElement.scrollWidth - window.innerWidth"
            )
            if overflow > 1:
                raise AssertionError(f"390 页面横滚 {overflow}px")
            mobile.screenshot(path=os.path.join(shots, "workspace_390.png"))

            mobile.get_by_role("button", name="打开导航", exact=True).click()
            mobile.wait_for_timeout(220)
            if mobile.locator(".app.nav-open").count() != 1:
                raise AssertionError("390 侧栏未打开")
            if not mobile.get_by_role(
                "link", name="DNS 记录", exact=True
            ).is_visible():
                raise AssertionError("390 侧栏展开后导航链接不可见")
            mobile.screenshot(path=os.path.join(shots, "nav_390.png"))
            mobile.get_by_role("button", name="关闭导航", exact=True).click()
            mobile.wait_for_timeout(220)
            if mobile.locator(".app.nav-open").count() != 0:
                raise AssertionError("390 侧栏未关闭")
            if (
                mobile.locator(".sidebar").evaluate(
                    "el => getComputedStyle(el).visibility"
                )
                != "hidden"
            ):
                raise AssertionError("390 侧栏关闭后仍可见")

            mobile.get_by_role("button", name="批量操作", exact=True).click()
            mobile.wait_for_selector(".drawer.open", timeout=10_000)
            mobile.wait_for_timeout(240)
            if mobile.locator(".drawer").get_attribute("aria-modal") != "true":
                raise AssertionError("390 批量抽屉未按模态打开")
            drawer_box = mobile.locator(".drawer").bounding_box()
            if not drawer_box or drawer_box["width"] < 380:
                raise AssertionError(f"390 批量抽屉宽度异常: {drawer_box}")
            if drawer_box["x"] > 1:
                raise AssertionError(f"390 批量抽屉未贴边: {drawer_box}")
            mobile.screenshot(path=os.path.join(shots, "drawer_390.png"))
            mobile.get_by_role("button", name="关闭面板", exact=True).click()
            mobile.wait_for_timeout(220)
            if mobile.locator(".drawer.open").count() != 0:
                raise AssertionError("390 批量抽屉未关闭")

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
