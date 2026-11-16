# -*- coding: utf-8 -*-
"""WebUI v2 浏览器验收：真实 FastAPI 静态托管 + Playwright 拦截 API 契约。

不访问 Cloudflare：所有 /api/v1 请求由 Playwright 用固定 JSON 响应。
覆盖：记录按总量分档（小 zone 本地、大 zone 服务端分页）、两态排序与工具栏重置、列宽键盘调整/还原/刷新持久化、复选框单元格无省略号、
搜索、预览真实结果、任务详情、单条编辑、批量内容/删除、侧栏高级工具分区与查找/历史/上传、
邮箱转发目标验证/完成 catch-all、Provision/Inspector 仅选已验证目标、侧栏默认展开/页脚收起/Rail 悬停与键盘临时展开/Esc/快捷键、
390 窄屏无横滚与零 pageerror。
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
    "proxy": {
        "mode": "round-robin",
        "count": 0,
        "total": 0,
        "enabled": False,
        "enabled_count": 0,
    },
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
            "缺少 dist/index.html：先执行 npm ci --prefix webui/v2 与 "
            "npm --prefix webui/v2 run build"
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
    expected_resource_errors = {"remaining": 0}
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
    record_posts: list[dict] = []
    find_scan_posts: list[dict] = []
    find_continue_posts: list[int] = []
    find_scan_polls = {"count": 0}
    meta_state = json.loads(json.dumps(META))
    proxy_state = {
        "enabled": False,
        "mode": "round-robin",
        "proxies": [],
        "count": 0,
        "total": 0,
        "enabled_count": 0,
        "active": False,
        "persisted": False,
    }
    proxy_seq = {"n": 0}

    def find_scan_body(
        status: str,
        checked: int,
        hits: int,
        misses: int,
        stopped_early: bool = False,
    ) -> dict:
        """固定扫描快照：先 running 再 done，覆盖进度、命中与提前停止。"""
        missed = [f"t{n}" for n in range(2, 2 + misses)]
        results = (
            [
                {
                    "account": "t1",
                    "zone": "example.com",
                    "zone_id": "z1",
                    "status": "active",
                    "elapsed_ms": 1400,
                }
            ]
            if hits
            else []
        )
        return {
            "scan_id": "scan-9001",
            "domain": "example.com",
            "status": status,
            "stop_on_first": True,
            "stopped_early": stopped_early,
            "stop_reason": "first_hit" if stopped_early else "",
            "total": 59,
            "checked": checked,
            "unchecked": max(0, 59 - checked),
            "hits": hits,
            "misses": misses,
            "failed": 0,
            "results": results,
            "errors": [],
            "missed_accounts": missed,
            "unchecked_accounts": [
                f"u{n}" for n in range(checked + 1, 60)
            ],
            "events": [
                {
                    "ts": "2026-11-16T10:00:00+00:00",
                    "level": "info",
                    "account": "",
                    "message": "开始扫描 59 个账号",
                },
                {
                    "ts": "2026-11-16T10:00:01+00:00",
                    "level": "success",
                    "account": "t1",
                    "message": "找到 example.com（active）",
                },
            ],
            "in_flight": ["t2", "t3"]
            if status in {"running", "cancelling"}
            else [],
            "started_at": "2026-11-16T10:00:00+00:00",
            "finished_at": ""
            if status in {"running", "cancelling"}
            else "2026-11-16T10:00:02+00:00",
            "elapsed_ms": 2000,
            "complete": status in {"done", "partial", "failed"}
            and not stopped_early,
        }

    def api(route) -> None:
        request = route.request
        parsed = urlparse(request.url)
        path = parsed.path
        method = request.method
        query = parse_qs(parsed.query)
        data_requests.append((method, path))
        if path.endswith("/api/v1/proxy") and method == "GET":
            body = proxy_state
        elif path.endswith("/api/v1/proxy") and method == "PUT":
            payload = json.loads(request.post_data or "{}")
            enabled = bool(payload.get("enabled"))
            mode = str(payload.get("mode") or "round-robin")
            existing = {item["id"]: item for item in proxy_state["proxies"]}
            proxies: list[dict] = []
            for item in payload.get("proxies") or []:
                item_id = str(item.get("id") or "").strip()
                item_enabled = bool(item.get("enabled", True))
                raw_url = item.get("url")
                if item_id:
                    current = existing.get(item_id)
                    if current is None:
                        errors.append(f"unknown proxy id: {item_id}")
                        route.fulfill(
                            status=400,
                            content_type="application/json",
                            body=json.dumps(
                                {"detail": f"代理条目不存在: {item_id}"}
                            ),
                        )
                        return
                    url = (
                        str(raw_url).strip()
                        if raw_url and str(raw_url).strip()
                        else str(current["url"])
                    )
                else:
                    proxy_seq["n"] += 1
                    item_id = f"p{proxy_seq['n']}"
                    url = str(raw_url or "").strip()
                proxies.append(
                    {"id": item_id, "url": url, "enabled": item_enabled}
                )
            total = len(proxies)
            enabled_count = sum(1 for item in proxies if item["enabled"])
            count = enabled_count if enabled else 0
            proxy_state.update(
                {
                    "enabled": enabled,
                    "mode": mode,
                    "proxies": proxies,
                    "count": count,
                    "total": total,
                    "enabled_count": enabled_count,
                    "active": count > 0,
                    "persisted": False,
                }
            )
            meta_state["proxy"] = {
                "mode": proxy_state["mode"],
                "count": proxy_state["count"],
                "total": proxy_state["total"],
                "enabled": proxy_state["enabled"],
                "enabled_count": proxy_state["enabled_count"],
            }
            body = proxy_state
        elif path.endswith("/api/v1/meta"):
            body = meta_state
        elif path.endswith("/api/v1/accounts"):
            body = ACCOUNTS
        elif path.endswith("/api/v1/zones"):
            body = ZONES
        elif path.endswith("/api/v1/records/refresh") and method == "POST":
            body = {"account": "t1", "zone": "example.com", "refreshed": True}
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
        elif path.endswith("/api/v1/records") and method == "POST":
            record_posts.append(json.loads(request.post_data or "{}"))
            body = {"status": "added", "message": "已添加"}
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
                "events": [
                    {
                        "ts": "2026-11-16T10:00:00+00:00",
                        "level": "info",
                        "title": "任务开始",
                        "detail": "Cloudflare DNS 预览任务",
                        "account": "t1",
                        "zone": "example.com",
                        "meta": {"dry_run": "True"},
                    },
                    {
                        "ts": "2026-11-16T10:00:02+00:00",
                        "level": "success",
                        "title": "账号完成",
                        "detail": "",
                        "account": "t1",
                        "zone": "example.com",
                        "meta": {"updated": "3", "errors": "0"},
                    },
                ],
            }
        elif path.endswith("/api/v1/jobs/job-9002/exports"):
            body = {"job_id": "job-9002", "total": 0, "items": []}
        elif path.endswith("/api/v1/jobs/job-9002"):
            body = PREVIEW_JOB
        elif path.endswith("/api/v1/jobs/job-9001/logs"):
            body = {
                "job_id": "job-9001",
                "total": 1,
                "offset": 0,
                "logs": ["[job] running"],
                "events": [
                    {
                        "ts": "2026-11-16T10:00:00+00:00",
                        "level": "info",
                        "title": "任务开始",
                        "detail": "执行任务运行中",
                        "account": "t1",
                        "zone": "example.com",
                        "meta": {},
                    }
                ],
            }
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
        elif path.endswith("/api/v1/find/scans") and method == "POST":
            find_scan_posts.append(json.loads(request.post_data or "{}"))
            body = find_scan_body("running", checked=5, hits=0, misses=5)
        elif path.endswith("/api/v1/find/scans/scan-9001"):
            find_scan_polls["count"] += 1
            if find_scan_polls["count"] == 1:
                body = find_scan_body("running", checked=5, hits=0, misses=5)
            else:
                body = find_scan_body(
                    "done",
                    checked=6,
                    hits=1,
                    misses=5,
                    stopped_early=True,
                )
        elif path.endswith("/api/v1/find/scans/scan-9001/continue"):
            find_continue_posts.append(1)
            body = find_scan_body(
                "done",
                checked=59,
                hits=1,
                misses=58,
            )
        elif path.endswith("/api/v1/find/scans/scan-9001/cancel"):
            body = find_scan_body("cancelled", checked=5, hits=0, misses=5)
        elif path.endswith("/api/v1/find/scans/scan-expired"):
            route.fulfill(
                status=404,
                content_type="application/json",
                body=json.dumps({"detail": "扫描不存在: scan-expired"}),
            )
            return
        elif path.endswith("/api/v1/find/scans/scan-offline"):
            route.abort()
            return
        elif path.endswith("/api/v1/find"):
            body = {
                "domain": query.get("domain", [""])[0],
                "found": 1,
                "checked": 1,
                "missed": 0,
                "failed": 0,
                "complete": True,
                "results": [
                    {
                        "account": "t1",
                        "zone": "example.com",
                        "zone_id": "z1",
                        "status": "active",
                        "elapsed_ms": 1400,
                    }
                ],
                "errors": [],
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

            def on_console(msg) -> None:
                if msg.type != "error":
                    return
                if (
                    expected_resource_errors["remaining"] > 0
                    and "Failed to load resource" in msg.text
                ):
                    expected_resource_errors["remaining"] -= 1
                    return
                errors.append(f"console-{msg.type}: {msg.text}")

            page.on("console", on_console)
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
            sidebar_gaps = page.evaluate(
                """() => {
                  const groups = [...document.querySelectorAll('.sidebar .nav-group')];
                  const link = groups[0]?.querySelector('.nav-link.active');
                  const title = groups[1]?.querySelector('.nav-group-title');
                  const first = groups[1]?.querySelector('.nav-link');
                  if (!link || !title || !first) return null;
                  const lr = link.getBoundingClientRect();
                  const tr = title.getBoundingClientRect();
                  const fr = first.getBoundingClientRect();
                  const ts = getComputedStyle(title);
                  return {
                    above: Math.round(tr.top + parseFloat(ts.paddingTop) - lr.bottom),
                    below: Math.round(fr.top - (tr.bottom - parseFloat(ts.paddingBottom))),
                  };
                }"""
            )
            if not sidebar_gaps or sidebar_gaps["above"] < 8 or sidebar_gaps["below"] < 6:
                raise AssertionError(f"侧栏分组标题与相邻项间距不足: {sidebar_gaps}")
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
                raise AssertionError("记录总数未正确显示")

            proxy_trigger = page.locator('[data-proxy-trigger="topbar"]')
            proxy_trigger.click()
            page.wait_for_selector("#proxy-settings-title", timeout=10_000)
            page.wait_for_function(
                'document.activeElement?.id === "proxy-add-url"',
                timeout=5_000,
            )
            page.keyboard.press("Escape")
            page.wait_for_selector(
                "#proxy-settings-title", state="detached", timeout=5_000
            )
            if not page.evaluate(
                'document.activeElement === document.querySelector(\'[data-proxy-trigger="topbar"]\')'
            ):
                raise AssertionError("代理设置弹窗关闭后焦点未回到顶栏徽标")

            # 新增但未保存：关闭应提示丢弃，且不影响当前生效配置。
            proxy_trigger.click()
            page.wait_for_selector("#proxy-settings-title", timeout=10_000)
            if page.locator(".proxy-edit-item").count() != 0:
                raise AssertionError("初始代理列表应为空")
            page.locator("#proxy-add-url").fill("http://127.0.0.1:7897")
            page.locator(".proxy-add-row").get_by_role("button", name="添加").click()
            if page.locator(".proxy-edit-item").count() != 1:
                raise AssertionError("添加代理后列表未更新")
            page.keyboard.press("Escape")
            if not page.get_by_text("再次关闭或按 Esc 将丢弃").is_visible():
                raise AssertionError("有未保存修改时关闭未提示")
            if "代理 0" not in proxy_trigger.inner_text():
                raise AssertionError("未保存的代理不应影响当前生效配置")
            page.keyboard.press("Escape")
            page.wait_for_selector(
                "#proxy-settings-title", state="detached", timeout=5_000
            )

            proxy_trigger.click()
            page.wait_for_selector("#proxy-settings-title", timeout=10_000)
            if page.locator(".proxy-edit-item").count() != 0:
                raise AssertionError("放弃修改后代理列表不应保留草稿")
            page.locator("#proxy-add-url").fill("socks5://127.0.0.1:1080")
            page.locator(".proxy-add-row").get_by_role("button", name="添加").click()
            if not page.get_by_text(
                "仅支持 http:// 或 https:// 代理"
            ).is_visible():
                raise AssertionError("非 http(s) 代理未在添加时拦截")

            for proxy_url in (
                "http://127.0.0.1:7897",
                "http://127.0.0.1:7898",
            ):
                page.locator("#proxy-add-url").fill(proxy_url)
                page.locator(".proxy-add-row").get_by_role(
                    "button", name="添加"
                ).click()
            if page.locator(".proxy-edit-item").count() != 2:
                raise AssertionError("批量添加代理后列表数量不符")
            page.locator(".proxy-edit-item .switch").nth(1).click()
            page.locator(".proxy-master .switch").click()
            page.locator("#proxy-mode").select_option("failover")
            page.wait_for_timeout(100)
            if not page.locator(".proxy-master input[type=checkbox]").is_checked():
                raise AssertionError("总开关未打开")
            if page.locator(".proxy-edit-item input[type=checkbox]").nth(1).is_checked():
                raise AssertionError("第二项单项开关未关闭")
            if not page.get_by_role("button", name="保存配置").is_enabled():
                raise AssertionError("有未保存修改时保存按钮应可用")
            page.screenshot(path=os.path.join(shots, "proxy_dialog_1440.png"))
            page.get_by_role("button", name="保存配置").click()
            page.wait_for_selector(
                "text=代理已启用：1/2 个（故障切换）", timeout=10_000
            )
            page.wait_for_selector(
                "#proxy-settings-title", state="detached", timeout=5_000
            )
            if "代理 1/2" not in proxy_trigger.inner_text():
                raise AssertionError("代理保存后顶栏数量未更新")

            proxy_trigger.click()
            page.wait_for_selector("#proxy-settings-title", timeout=10_000)
            if (
                "当前启用 1/2 · 故障切换"
                not in page.locator(".proxy-state").inner_text()
            ):
                raise AssertionError("代理弹窗当前状态未显示")
            if page.locator(".proxy-edit-item").count() != 2:
                raise AssertionError("已保存代理未在列表中保留")
            if not page.locator(".proxy-master input[type=checkbox]").is_checked():
                raise AssertionError("总开关状态未保留")
            if page.locator(".proxy-edit-item input[type=checkbox]").nth(1).is_checked():
                raise AssertionError("单项关闭状态未保留")
            if page.locator("#proxy-add-url").input_value() != "":
                raise AssertionError("新增输入框不应回填已保存地址")
            page.screenshot(path=os.path.join(shots, "proxy_active_1440.png"))

            # 关闭总开关：列表与单项开关保留，但当前不生效。
            page.locator(".proxy-master .switch").click()
            page.get_by_role("button", name="保存配置").click()
            page.wait_for_selector(
                "text=代理配置已保存：2 个（未启用）", timeout=10_000
            )
            page.wait_for_selector(
                "#proxy-settings-title", state="detached", timeout=5_000
            )
            if "代理 关" not in proxy_trigger.inner_text():
                raise AssertionError("总开关关闭后顶栏未显示关闭")

            proxy_trigger.click()
            page.wait_for_selector("#proxy-settings-title", timeout=10_000)
            if (
                "当前关闭（已保存 2 个）"
                not in page.locator(".proxy-state").inner_text()
            ):
                raise AssertionError("总开关关闭后已保存代理未保留")
            if page.locator(".proxy-edit-item").count() != 2:
                raise AssertionError("总开关关闭后代理列表丢失")
            if page.locator(".proxy-master input[type=checkbox]").is_checked():
                raise AssertionError("总开关关闭状态未保留")
            page.screenshot(path=os.path.join(shots, "proxy_saved_off_1440.png"))

            page.locator(".proxy-master .switch").click()
            page.locator(".proxy-edit-item .switch").nth(1).click()
            page.get_by_role("button", name="保存配置").click()
            page.wait_for_selector(
                "text=代理已启用：2/2 个（故障切换）", timeout=10_000
            )
            page.wait_for_selector(
                "#proxy-settings-title", state="detached", timeout=5_000
            )
            if "代理 2/2" not in proxy_trigger.inner_text():
                raise AssertionError("重新启用后顶栏数量未更新")

            proxy_trigger.click()
            page.wait_for_selector("#proxy-settings-title", timeout=10_000)
            page.get_by_role("button", name="清空列表").click()
            if page.locator(".proxy-edit-item").count() != 0:
                raise AssertionError("清空列表未清空草稿")
            page.get_by_role("button", name="保存配置").click()
            page.wait_for_selector("text=代理配置已清空", timeout=10_000)
            page.wait_for_selector(
                "#proxy-settings-title", state="detached", timeout=5_000
            )
            if "代理 0" not in proxy_trigger.inner_text():
                raise AssertionError("清空代理后顶栏数量未更新")
            if not any(
                method == "PUT" and path.endswith("/api/v1/proxy")
                for method, path in data_requests
            ):
                raise AssertionError("代理设置未提交 PUT 请求")

            check_cell = page.locator(".records-table tbody .check-cell").first
            if check_cell.evaluate("el => getComputedStyle(el).textOverflow") != "clip":
                raise AssertionError("复选框单元格仍在用省略号，会在右侧显示小点")

            records_before_sort = sum(
                1
                for method, path in data_requests
                if method == "GET" and path.endswith("/api/v1/records")
            )
            name_header = page.locator(".records-table thead th").filter(
                has=page.get_by_role("button", name="名称", exact=True)
            ).first
            name_button = name_header.get_by_role("button", name="名称", exact=True)
            if name_header.get_attribute("aria-sort") != "none":
                raise AssertionError("初始未排序时 aria-sort 应为 none")
            if page.locator(".sort-select").is_visible():
                raise AssertionError("桌面表头存在时不应重复显示工具栏排序下拉")
            name_button.click()
            page.wait_for_timeout(80)
            if name_header.get_attribute("aria-sort") != "ascending":
                raise AssertionError("第一次点击排序应为升序")
            page.screenshot(path=os.path.join(shots, "records_sorted_asc_1440.png"))
            name_button.click()
            page.wait_for_timeout(80)
            if name_header.get_attribute("aria-sort") != "descending":
                raise AssertionError("第二次点击排序应为降序")
            name_button.click()
            page.wait_for_timeout(80)
            if name_header.get_attribute("aria-sort") != "ascending":
                raise AssertionError("第三次点击排序应切回升序（两态，不回未排序）")
            page.get_by_role("button", name="重置排序").click()
            page.wait_for_timeout(80)
            if name_header.get_attribute("aria-sort") != "none":
                raise AssertionError("重置排序后 aria-sort 应回到 none")
            records_after_sort = sum(
                1
                for method, path in data_requests
                if method == "GET" and path.endswith("/api/v1/records")
            )
            if records_after_sort != records_before_sort:
                raise AssertionError(
                    "排序触发了记录接口请求，未使用本地数据"
                )

            resize_handle = page.locator('.col-resizer[data-column="name"]')
            name_th = page.locator(".records-table thead th").nth(1)
            width_before = name_th.bounding_box()["width"]
            resize_handle.focus()
            page.keyboard.press("ArrowRight")
            page.wait_for_timeout(80)
            width_after = name_th.bounding_box()["width"]
            if width_after < width_before + 7:
                raise AssertionError(
                    f"方向键未增加列宽: {width_before} -> {width_after}"
                )
            saved_width = json.loads(
                page.evaluate("localStorage.getItem('cfv2-records-cols')")
            )["name"]
            if saved_width != round(width_after):
                raise AssertionError(
                    f"列宽未持久化: 实际 {width_after}，存储 {saved_width}"
                )
            resize_handle.focus()
            page.keyboard.press("Enter")
            page.wait_for_timeout(80)
            if abs(name_th.bounding_box()["width"] - 220) > 1:
                raise AssertionError("Enter 未把列宽恢复默认")

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
            rail_top = page.locator(".sidebar").bounding_box()["y"]
            first_link_top = page.locator(".sidebar .nav-link").first.bounding_box()["y"]
            if first_link_top - rail_top > 22:
                raise AssertionError(
                    f"Rail 首项顶部空白过大: {first_link_top - rail_top}px"
                )
            rail_groups = page.evaluate(
                """() => {
                  const groups = Array.from(document.querySelectorAll('.sidebar .nav-group'));
                  if (groups.length < 2) return null;
                  const leftLinks = groups[0].querySelectorAll('.nav-link');
                  const rightLink = groups[1].querySelector('.nav-link');
                  if (!leftLinks.length || !rightLink) return null;
                  const a = leftLinks[leftLinks.length - 1].getBoundingClientRect();
                  const b = rightLink.getBoundingClientRect();
                  const line = getComputedStyle(groups[1], '::before');
                  return {
                    gap: Math.round(b.top - a.bottom),
                    lineHeight: line.height,
                    lineColor: line.backgroundColor,
                    lineContent: line.content,
                  };
                }"""
            )
            if not rail_groups:
                raise AssertionError("Rail 分组结构缺失")
            # 焦点环需要 6px 项间距和 32px 标题槽；组间空白上限按当前结构放宽到 36px。
            if rail_groups["gap"] > 36:
                raise AssertionError(f"Rail 组间空白过大: {rail_groups['gap']}px")
            if (
                rail_groups["lineContent"] == "none"
                or rail_groups["lineHeight"] != "1px"
                or rail_groups["lineColor"] == "rgba(0, 0, 0, 0)"
            ):
                raise AssertionError(f"Rail 组间缺少可见分隔线: {rail_groups}")

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
            page.get_by_role("link", name="跨账号查找", exact=True).click()
            page.wait_for_selector("text=查找域名", timeout=10_000)
            if page.locator(".sidebar").get_attribute("data-state") != "peek":
                raise AssertionError("点击导航后不应立即收起，应在鼠标离开后再收起")
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
            page.get_by_role("link", name="跨账号查找", exact=True).click()
            page.wait_for_selector("text=查找域名", timeout=10_000)
            if page.locator(".sidebar").get_attribute("data-state") != "pinned":
                raise AssertionError("固定展开时点击导航不应收起侧栏")
            page.get_by_role("link", name="DNS 记录", exact=True).click()
            page.wait_for_selector(".records-table tbody tr", timeout=10_000)
            if page.locator(".sidebar").get_attribute("data-state") != "pinned":
                raise AssertionError("固定展开时点击导航不应收起侧栏")

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
            page.wait_for_selector("text=执行时间线", timeout=10_000)
            page.wait_for_selector("text=任务开始", timeout=10_000)
            page.wait_for_selector("text=账号完成", timeout=10_000)
            page.wait_for_selector("text=原始日志", timeout=10_000)
            page.screenshot(path=os.path.join(shots, "task_1440.png"))

            page.get_by_role("tab", name="操作").click()
            records_before_edit = sum(
                1
                for method, path in data_requests
                if method == "GET" and path.endswith("/api/v1/records")
            )
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
            records_after_edit = sum(
                1
                for method, path in data_requests
                if method == "GET" and path.endswith("/api/v1/records")
            )
            if records_after_edit != records_before_edit:
                raise AssertionError("编辑保存后重新拉取了整表记录")
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
            jobs_before_add = len(job_posts)
            page.get_by_role("button", name="保存记录").click()
            page.wait_for_selector("text=记录已创建", timeout=10_000)
            page.wait_for_selector("#add-record-title", state="detached", timeout=5_000)
            if len(job_posts) != jobs_before_add:
                raise AssertionError("新增记录仍然提交了预览任务")
            if not record_posts:
                raise AssertionError("新增记录未直接写入 /api/v1/records")
            add_payload = record_posts[-1]
            if add_payload.get("zone") != "example.com":
                raise AssertionError("新增记录写入范围不是当前域名")
            if add_payload.get("name") != "_webui-accept-add":
                raise AssertionError("新增记录名称未提交")
            if add_payload.get("type") != "A":
                raise AssertionError("新增记录类型未提交")
            if add_payload.get("content") != "198.51.100.99":
                raise AssertionError("新增记录内容未提交")
            if add_payload.get("proxied") is not True:
                raise AssertionError("新增记录未提交代理状态")
            page.screenshot(path=os.path.join(shots, "add_record_1440.png"))

            page.screenshot(path=os.path.join(shots, "drawer_1440.png"))
            page.get_by_role("link", name="跨账号查找", exact=True).click()
            page.wait_for_function(
                "window.location.pathname === '/advanced/find'", timeout=10_000
            )
            page.wait_for_function(
                "document.querySelector('.sidebar .nav-link[aria-current=\"page\"]')?.textContent?.includes('跨账号查找')",
                timeout=10_000,
            )
            if (
                page.get_by_role("link", name="跨账号查找", exact=True).get_attribute(
                    "aria-current"
                )
                != "page"
            ):
                raise AssertionError("侧栏高级工具默认项不是跨账号查找")
            page.screenshot(path=os.path.join(shots, "advanced_1440.png"), full_page=True)

            page.get_by_role("link", name="历史与审计", exact=True).click()
            page.wait_for_function(
                "window.location.pathname === '/advanced/history'", timeout=10_000
            )
            page.wait_for_selector("text=job-9002", timeout=10_000)
            page.get_by_role("button", name="审计日志").click()
            page.wait_for_selector("text=bulk_update", timeout=10_000)
            page.screenshot(
                path=os.path.join(shots, "advanced_history_1440.png"), full_page=True
            )

            page.get_by_role("link", name="跨账号查找", exact=True).click()
            page.get_by_placeholder("example.com").first.fill("example.com")
            page.get_by_role("button", name="查找", exact=True).click()
            page.wait_for_selector("text=命中 1 个账号", timeout=10_000)
            page.wait_for_selector("text=提前停止", timeout=10_000)
            if (
                not find_scan_posts
                or find_scan_posts[-1].get("stop_on_first") is not True
            ):
                raise AssertionError("跨账号查找默认未启用命中即停")
            page.locator("button", has_text="继续查询剩余").click()
            page.wait_for_selector("text=已检查 59/59 个账号", timeout=10_000)
            if not find_continue_posts:
                raise AssertionError("继续查询未调用后端")

            # 服务重启后旧扫描记录失效：自动清理并提示重新查找。
            expected_resource_errors["remaining"] = 1
            page.evaluate(
                "sessionStorage.setItem('cfv2-find-scan', 'scan-expired')"
            )
            page.reload(wait_until="networkidle")
            page.wait_for_selector("text=上次扫描记录已失效", timeout=10_000)
            if page.evaluate("sessionStorage.getItem('cfv2-find-scan')") is not None:
                raise AssertionError("失效扫描 ID 未从 sessionStorage 清理")
            if page.locator(".error-inline").count():
                raise AssertionError("失效扫描仍显示红色错误")
            if not page.get_by_placeholder("example.com").first.is_visible():
                raise AssertionError("失效扫描后查找表单不可用")
            page.screenshot(
                path=os.path.join(shots, "find_expired_1440.png"),
                full_page=True,
            )
            expected_resource_errors["remaining"] = 0

            # 后端离线：显示中文连接提示，而不是原始 Failed to fetch。
            expected_resource_errors["remaining"] = 4
            page.evaluate(
                "sessionStorage.setItem('cfv2-find-scan', 'scan-offline')"
            )
            page.reload(wait_until="networkidle")
            page.wait_for_selector("text=无法连接后端", timeout=10_000)
            if page.get_by_text("Failed to fetch").count():
                raise AssertionError("仍显示原始 Failed to fetch")
            if not page.get_by_placeholder("example.com").first.is_visible():
                raise AssertionError("后端离线时查找表单不可用")
            page.screenshot(
                path=os.path.join(shots, "find_offline_1440.png"),
                full_page=True,
            )
            expected_resource_errors["remaining"] = 0

            page.get_by_role("link", name="邮箱转发", exact=True).click()
            page.wait_for_selector("text=邮箱转发（Email Routing）", timeout=10_000)
            email_panel = page.locator("section.panel").filter(
                has_text="邮箱转发（Email Routing）"
            )
            email_panel.get_by_text("邮箱转发注意事项（首次配置必看）").click()
            if not email_panel.get_by_text("目标邮箱必须先验证").is_visible():
                raise AssertionError("邮箱转发注意事项未展开")
            if not email_panel.get_by_text(
                "owner@gmail.com", exact=True
            ).first.is_visible():
                raise AssertionError("账号级目标地址未显示")
            if not email_panel.get_by_text(
                "已验证 · 本账号域名可直接复用", exact=True
            ).first.is_visible():
                raise AssertionError("已验证目标地址未标记可复用")
            email_panel.get_by_role("button", name="添加新目标邮箱").click()
            email_panel.get_by_placeholder("you@gmail.com").fill("new@gmail.com")
            email_panel.get_by_role("button", name="添加并发送验证").click()
            page.wait_for_selector("text=已添加目标邮箱，Cloudflare 已发送验证邮件", timeout=10_000)
            email_panel.get_by_text("new@gmail.com", exact=True).first.wait_for(
                timeout=10_000
            )
            if not email_panel.get_by_text(
                "待验证 · 请检查收件箱和垃圾箱", exact=True
            ).first.is_visible():
                raise AssertionError("新目标邮箱未显示待验证状态")
            if not email_panel.get_by_text(
                "验证完成前不能完成 catch-all 配置；请不要先切换 MX。"
            ).is_visible():
                raise AssertionError("未启用的域名未阻止待验证目标")
            email_panel.get_by_text("owner@gmail.com", exact=True).first.click()
            page.wait_for_timeout(120)
            if not email_panel.get_by_role(
                "radio", name="选择 owner@gmail.com"
            ).is_checked():
                raise AssertionError("点击目标地址条目未选中对应单选")
            if not email_panel.get_by_role(
                "button", name="启用转发并设置 catch-all"
            ).is_visible():
                raise AssertionError("切回已验证地址后未恢复完成入口")
            email_panel.get_by_role(
                "button", name="启用转发并设置 catch-all"
            ).click()
            page.wait_for_selector("text=邮箱转发已配置到 owner@gmail.com", timeout=10_000)
            if not email_panel.get_by_text(
                "已启用", exact=True
            ).first.is_visible():
                raise AssertionError("完成配置后未显示已启用状态")
            pending_details = email_panel.locator("details.email-routing-more")
            if not pending_details.evaluate("el => el.open"):
                email_panel.get_by_text("账号内待验证地址（2）").click()
                page.wait_for_timeout(100)
            email_panel.get_by_role(
                "radio", name="选择 new@gmail.com"
            ).check()
            page.wait_for_timeout(120)
            if not email_panel.get_by_text(
                "尚未验证；验证完成前不会改动当前 catch-all。"
            ).is_visible():
                raise AssertionError("待验证目标邮箱未说明当前路由保持不变")
            if not email_panel.get_by_text(
                "catch-all → owner@gmail.com", exact=True
            ).is_visible():
                raise AssertionError("待验证目标邮箱未保留当前 catch-all 状态")
            for width in (1024, 768):
                page.set_viewport_size({"width": width, "height": 900})
                page.wait_for_timeout(140)
                panel_overflow = page.evaluate(
                    "document.documentElement.scrollWidth - window.innerWidth"
                )
                if panel_overflow > 1:
                    raise AssertionError(
                        f"{width} 邮箱转发面板横滚 {panel_overflow}px"
                    )
                account_scope = email_panel.locator(
                    ".email-routing-scope"
                ).first.bounding_box()
                domain_scope = email_panel.locator(
                    ".email-routing-scope"
                ).nth(1).bounding_box()
                if (
                    not account_scope
                    or not domain_scope
                    or domain_scope["y"] < account_scope["y"] + account_scope["height"]
                ):
                    raise AssertionError(f"{width} 邮箱转发面板未按单列堆叠")
                page.screenshot(
                    path=os.path.join(shots, f"email_routing_{width}.png"),
                    full_page=True,
                )
            page.set_viewport_size({"width": 1440, "height": 900})
            page.wait_for_timeout(140)
            email_panel.scroll_into_view_if_needed()
            page.wait_for_timeout(120)
            page.screenshot(path=os.path.join(shots, "email_routing_view_1440.png"))
            page.screenshot(
                path=os.path.join(shots, "email_routing_1440.png"), full_page=True
            )
            page.get_by_role("button", name="切换到深色主题").click()
            page.wait_for_timeout(160)
            if page.locator("html").get_attribute("data-theme") != "dark":
                raise AssertionError("邮箱转发面板深色主题未生效")
            page.screenshot(
                path=os.path.join(shots, "email_routing_dark_1440.png"),
                full_page=True,
            )
            page.get_by_role("button", name="切换到浅色主题").click()
            page.wait_for_timeout(160)
            if page.locator("html").get_attribute("data-theme") != "light":
                raise AssertionError("邮箱转发面板浅色主题未恢复")

            page.get_by_role("link", name="配置向导", exact=True).click()
            page.wait_for_selector("text=域名配置向导", timeout=10_000)
            provision_panel = page.locator("section.panel").filter(
                has_text="域名配置向导"
            )
            provision_target = provision_panel.get_by_label("邮箱转发目标")
            provision_target.wait_for(timeout=10_000)
            provision_target.locator(
                'option[value="owner@gmail.com"]'
            ).wait_for(state="attached", timeout=10_000)
            option_texts = provision_target.locator("option").all_inner_texts()
            if "owner@gmail.com" not in option_texts:
                raise AssertionError("provision 未列出已验证目标地址")
            if "new@gmail.com" in option_texts:
                raise AssertionError("provision 列出了待验证目标地址")
            preview_button = provision_panel.get_by_role(
                "button", name="预览配置"
            )
            if not preview_button.is_disabled():
                raise AssertionError("provision 缺少已验证目标时仍可预览")
            if not provision_panel.get_by_text(
                "邮箱步骤已开启，请选择一个已验证目标地址"
            ).is_visible():
                raise AssertionError("provision 未说明需要选择已验证目标")
            if not provision_panel.get_by_role(
                "button", name="使用 owner@gmail.com"
            ).is_visible():
                raise AssertionError("provision 未提供使用已验证目标的快捷操作")
            page.screenshot(
                path=os.path.join(shots, "provision_email_blocked_1440.png")
            )
            provision_panel.get_by_role(
                "button", name="使用 owner@gmail.com"
            ).click()
            if provision_target.input_value() != "owner@gmail.com":
                raise AssertionError("provision 快捷选择未写入目标地址")
            if preview_button.is_disabled():
                raise AssertionError("provision 选择已验证目标后仍不可预览")
            provision_target.select_option("")
            provision_panel.get_by_role(
                "checkbox", name="邮箱", exact=True
            ).uncheck()
            if preview_button.is_disabled():
                raise AssertionError("provision 关闭邮箱步骤后仍不可预览")
            provision_panel.get_by_role(
                "checkbox", name="邮箱", exact=True
            ).check()
            if not preview_button.is_disabled():
                raise AssertionError("provision 重新开启邮箱步骤后未阻断")
            provision_target.select_option("owner@gmail.com")
            page.screenshot(
                path=os.path.join(shots, "provision_email_target_1440.png")
            )
            preview_button.click()
            page.wait_for_selector("text=provision 预览已提交", timeout=10_000)
            if not job_posts or job_posts[-1].get("forward_email") != "owner@gmail.com":
                raise AssertionError("provision 预览未携带已验证目标地址")
            if not job_posts[-1].get("do_email"):
                raise AssertionError("provision 预览未标记邮箱步骤")
            if not any(
                path.endswith("/api/v1/email-routing/complete")
                for _method, path in data_requests
            ):
                raise AssertionError("未提交邮箱转发完成请求")

            page.get_by_role("button", name="回到工作台").click()
            page.wait_for_selector(".records-table tbody tr", timeout=10_000)
            page.reload(wait_until="networkidle")
            page.wait_for_selector(".records-table tbody tr", timeout=10_000)
            page.get_by_role("button", name="批量操作", exact=True).click()
            page.wait_for_selector(".drawer.open", timeout=10_000)
            drawer = page.locator(".drawer.open")
            drawer.locator(".action-card", has_text="域名配置向导").click()
            inspector_target = drawer.get_by_label("邮箱转发目标")
            inspector_target.wait_for(timeout=10_000)
            inspector_target.locator(
                'option[value="owner@gmail.com"]'
            ).wait_for(state="attached", timeout=10_000)
            inspector_options = inspector_target.locator("option").all_inner_texts()
            if "owner@gmail.com" not in inspector_options:
                raise AssertionError("Inspector 未列出已验证目标地址")
            if "new@gmail.com" in inspector_options:
                raise AssertionError("Inspector 列出了待验证目标地址")
            if drawer.get_by_placeholder("admin@example.com").count():
                raise AssertionError("Inspector 仍保留目标邮箱自由输入")
            inspector_target.select_option("owner@gmail.com")
            if drawer.get_by_role("button", name="预览变更").is_disabled():
                raise AssertionError("Inspector 选择已验证目标后不可预览")
            page.screenshot(path=os.path.join(shots, "inspector_provision_1440.png"))
            drawer.get_by_role("button", name="关闭面板", exact=True).click()
            page.wait_for_timeout(200)

            page.get_by_role("link", name="范围附件", exact=True).click()
            page.wait_for_selector("text=白名单 / 重跑清单", timeout=10_000)
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

            page.wait_for_selector(".records-table tbody tr", timeout=10_000)
            resize_handle = page.locator('.col-resizer[data-column="name"]')
            resize_handle.focus()
            page.keyboard.press("ArrowRight")
            page.keyboard.press("ArrowRight")
            page.wait_for_timeout(80)
            resized_width = round(
                page.locator(".records-table thead th").nth(1).bounding_box()["width"]
            )
            page.reload(wait_until="networkidle")
            page.wait_for_selector(".records-table tbody tr", timeout=10_000)
            reloaded_width = round(
                page.locator(".records-table thead th").nth(1).bounding_box()["width"]
            )
            if reloaded_width != resized_width:
                raise AssertionError(
                    f"刷新后列宽未保持: {resized_width} -> {reloaded_width}"
                )
            page.locator('.col-resizer[data-column="name"]').focus()
            page.keyboard.press("Enter")
            page.wait_for_timeout(80)

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
            if not tablet.locator(".sort-select").is_visible():
                raise AssertionError("768 卡片视图缺少工具栏排序入口")
            tablet.locator(".sort-select select").select_option("-name")
            tablet.wait_for_timeout(120)
            first_card = tablet.locator(".record-card .record-name").first.inner_text()
            if first_card != "www":
                raise AssertionError(f"卡片视图按名称降序后首条应为 www，实际 {first_card}")
            if not tablet.get_by_role("button", name="重置排序").is_visible():
                raise AssertionError("卡片视图排序激活后缺少重置排序入口")
            tablet.screenshot(path=os.path.join(shots, "records_sorted_768.png"))
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

            mobile.get_by_role("button", name="打开导航", exact=True).click()
            mobile.wait_for_timeout(220)
            mobile.locator('[data-proxy-trigger="sidebar"]').click()
            mobile.wait_for_selector("#proxy-settings-title", timeout=10_000)
            mobile.screenshot(path=os.path.join(shots, "proxy_dialog_390.png"))
            proxy_box = mobile.locator(".proxy-modal").bounding_box()
            if (
                not proxy_box
                or proxy_box["x"] < 0
                or proxy_box["x"] + proxy_box["width"] > 391
            ):
                raise AssertionError(f"390 代理弹窗超出视口: {proxy_box}")
            mobile_proxy_overflow = mobile.evaluate(
                "document.documentElement.scrollWidth - window.innerWidth"
            )
            if mobile_proxy_overflow > 1:
                raise AssertionError(
                    f"390 代理弹窗横滚 {mobile_proxy_overflow}px"
                )
            mobile.get_by_role("button", name="关闭代理设置").click()
            mobile.wait_for_selector(
                "#proxy-settings-title", state="detached", timeout=5_000
            )
            mobile.get_by_role("button", name="关闭导航", exact=True).click()
            mobile.wait_for_timeout(220)
            if mobile.locator(".app.nav-open").count() != 0:
                raise AssertionError("390 代理弹窗关闭后侧栏未关闭")

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

            mobile.goto(base + "/advanced", wait_until="networkidle")
            mobile.wait_for_function(
                "window.location.pathname === '/advanced/find'", timeout=10_000
            )
            mobile.wait_for_selector("text=查找域名", timeout=10_000)
            active_nav = (
                mobile.locator('.sidebar .nav-link[aria-current="page"]').text_content()
                or ""
            )
            if "跨账号查找" not in active_nav:
                raise AssertionError("390 侧栏高级工具默认项不是跨账号查找")
            mobile_overflow = mobile.evaluate(
                "document.documentElement.scrollWidth - window.innerWidth"
            )
            if mobile_overflow > 1:
                raise AssertionError(f"390 高级页横滚 {mobile_overflow}px")
            mobile.get_by_role("button", name="打开导航", exact=True).click()
            mobile.wait_for_timeout(220)
            mobile.get_by_role("link", name="运行参数", exact=True).click()
            mobile.wait_for_function(
                "window.location.pathname === '/advanced/runtime'", timeout=10_000
            )
            mobile.wait_for_selector("text=速度档位", timeout=10_000)
            mobile.wait_for_function(
                "document.querySelector('.sidebar .nav-link[aria-current=\"page\"]')?.textContent?.includes('运行参数')",
                timeout=10_000,
            )
            mobile.wait_for_timeout(220)
            if mobile.locator(".app.nav-open").count() != 0:
                raise AssertionError("390 选择高级工具后侧栏未收起")
            active_nav = (
                mobile.locator('.sidebar .nav-link[aria-current="page"]').text_content()
                or ""
            )
            if "运行参数" not in active_nav:
                raise AssertionError("390 高级工具路由切换未生效")
            mobile.screenshot(
                path=os.path.join(shots, "advanced_390.png"), full_page=True
            )

            mobile.get_by_role("button", name="打开导航", exact=True).click()
            mobile.wait_for_timeout(220)
            mobile.get_by_role("link", name="邮箱转发", exact=True).click()
            mobile.wait_for_function(
                "window.location.pathname === '/advanced/email-routing'", timeout=10_000
            )
            mobile.wait_for_selector("text=邮箱转发（Email Routing）", timeout=10_000)
            mobile.wait_for_timeout(220)
            mobile_email_overflow = mobile.evaluate(
                "document.documentElement.scrollWidth - window.innerWidth"
            )
            if mobile_email_overflow > 1:
                raise AssertionError(
                    f"390 邮箱转发面板横滚 {mobile_email_overflow}px"
                )
            mobile_email_panel = mobile.locator("section.panel").filter(
                has_text="邮箱转发（Email Routing）"
            )
            account_box = mobile_email_panel.locator(
                ".email-routing-scope"
            ).first.bounding_box()
            domain_box = mobile_email_panel.locator(
                ".email-routing-scope"
            ).nth(1).bounding_box()
            if (
                not account_box
                or not domain_box
                or domain_box["y"] < account_box["y"] + account_box["height"]
            ):
                raise AssertionError("390 邮箱转发面板未按单列堆叠")
            mobile.screenshot(
                path=os.path.join(shots, "email_routing_390.png"), full_page=True
            )

            legacy = browser.new_page(viewport={"width": 390, "height": 900})
            legacy.on("pageerror", lambda exc: errors.append(f"legacy pageerror: {exc}"))
            legacy.route("**/api/v1/**", api)
            legacy.goto(
                base + "/advanced/history#/advanced/transfer",
                wait_until="networkidle",
            )
            legacy.wait_for_function(
                "window.location.pathname === '/advanced/transfer'", timeout=10_000
            )
            legacy.wait_for_selector(".advanced-page h1", timeout=10_000)
            if legacy.locator(".advanced-page h1").inner_text() != "导入 / 导出":
                raise AssertionError("旧 hash 链接未迁移到对应分区")
            legacy.close()

            large_items = [
                {
                    "id": f"L{i}",
                    "type": "A",
                    "name": f"host{i}.example.com",
                    "content": f"203.0.113.{i % 250}",
                    "ttl": 1,
                    "proxied": False,
                    "comment": "",
                    "priority": None,
                }
                for i in range(620)
            ]

            def large_records(route) -> None:
                request = route.request
                parsed = urlparse(request.url)
                if not (
                    request.method == "GET"
                    and parsed.path.endswith("/api/v1/records")
                ):
                    route.fallback()
                    return
                data_requests.append((request.method, parsed.path))
                query = parse_qs(parsed.query)
                page_no = int(query.get("page", ["1"])[0])
                per_page = int(query.get("per_page", ["50"])[0])
                if "all" in query:
                    items = large_items
                else:
                    start = (page_no - 1) * per_page
                    items = large_items[start : start + per_page]
                route.fulfill(
                    status=200,
                    content_type="application/json",
                    body=json.dumps(
                        {
                            "total": len(large_items),
                            "page": page_no,
                            "per_page": per_page,
                            "items": items,
                        }
                    ),
                )

            large = browser.new_page(viewport={"width": 1440, "height": 900})
            large.on("pageerror", lambda exc: errors.append(f"large pageerror: {exc}"))
            large.route("**/api/v1/**", api)
            large.route("**/api/v1/**", large_records)
            large.goto(base, wait_until="networkidle")
            large.wait_for_function(
                "document.querySelectorAll('.records-table tbody tr:not(.skeleton-row)').length === 50",
                timeout=10_000,
            )
            if "共 620 条" not in large.locator(".records-footer span").first.inner_text():
                raise AssertionError("大 zone 未进入服务端分页模式")
            before_large_sort = sum(
                1
                for method, path in data_requests
                if method == "GET" and path.endswith("/api/v1/records")
            )
            large.get_by_role("button", name="名称", exact=True).click()
            large.wait_for_timeout(300)
            after_large_sort = sum(
                1
                for method, path in data_requests
                if method == "GET" and path.endswith("/api/v1/records")
            )
            if after_large_sort <= before_large_sort:
                raise AssertionError("大 zone 排序未走服务端分页请求")
            large.screenshot(
                path=os.path.join(shots, "workspace_large_server_1440.png")
            )
            large.close()
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
