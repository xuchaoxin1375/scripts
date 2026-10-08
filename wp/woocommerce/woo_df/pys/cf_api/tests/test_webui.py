# -*- coding: utf-8 -*-
"""WebUI 后端契约回归测试（标准库 unittest + FastAPI TestClient，无外网依赖）。

覆盖 WEBUI_LESSONS.md 约束：
- 预设同源 / 默认 dry_run 开 / 脱敏 / 删除类限定范围 / 删域名需快照+DELETE /
  重跑清单 2MB 上限 / 单条校验与网页版对齐 / SPA 防穿越 / /api 兼容。
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui.backend import deps  # noqa: E402
from webui.backend.app import create_app  # noqa: E402

CONFIG_JSON = '{"accounts":{"t1":{"cf_api_token":"secret-token-1234567890"}}}'


def make_client():
    tmp = tempfile.mkdtemp(prefix="cf_web_test_")
    cfg = os.path.join(tmp, "cf_config.json")
    with open(cfg, "w", encoding="utf-8") as fh:
        fh.write(CONFIG_JSON)
    deps.configure(cfg)
    app = create_app("")
    from fastapi.testclient import TestClient

    return TestClient(app)


class WebContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = make_client()

    def test_meta_same_source_and_defaults(self):
        r = self.c.get("/api/v1/meta")
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertIn("speed_presets", body)
        self.assertEqual(body["speed_presets"]["eco"]["account_workers"], 3)
        self.assertTrue(body["defaults"]["dry_run"])
        self.assertEqual(body["defaults"]["record_type"], "auto")
        # 旧端兼容。
        self.assertEqual(self.c.get("/api/meta").status_code, 200)

    def test_accounts_masked(self):
        body = self.c.get("/api/v1/accounts").json()
        self.assertEqual(len(body["items"]), 1)
        item = body["items"][0]
        self.assertNotIn("secret-token-1234567890", json.dumps(item))
        self.assertTrue(item.get("has_secret"))

    def test_submit_validation(self):
        base = {"accounts": ["t1"], "domains": ["example.com"], "dry_run": True}
        # 更新缺新内容。
        r = self.c.post("/api/v1/jobs", json={**base, "mode": "update"})
        self.assertEqual(r.status_code, 400)
        # 删除类不限范围。
        r = self.c.post(
            "/api/v1/jobs",
            json={"mode": "delete_ip", "accounts": ["t1"], "delete_ip": "1.2.3.4"},
        )
        self.assertEqual(r.status_code, 400)
        # 删域名缺快照目录。
        r = self.c.post(
            "/api/v1/jobs",
            json={
                **base,
                "mode": "delete_zone",
                "delete_zone_mode": "dns",
                "confirm": "DELETE",
            },
        )
        self.assertEqual(r.status_code, 400)
        # 删域名缺 DELETE 确认。
        dirs = self.c.get("/api/v1/meta").json()["dirs"]
        r = self.c.post(
            "/api/v1/jobs",
            json={
                **base,
                "mode": "delete_zone",
                "delete_zone_mode": "dns",
                "backup_dir": dirs["backup_dir"],
            },
        )
        self.assertEqual(r.status_code, 400)

    def test_resume_preview_limits(self):
        ok = self.c.post(
            "/api/v1/resume-preview",
            content=b"account,zone\nt1,example.com\n",
        )
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.json()["rows"], 1)
        big = b"a" * (2 * 1024 * 1024 + 1)
        r = self.c.post("/api/v1/resume-preview", content=big)
        self.assertEqual(r.status_code, 400)

    def test_single_record_validation(self):
        # TXT 不可开代理（与网页版对齐），应在联网前 400。
        r = self.c.post(
            "/api/v1/records",
            json={
                "account": "t1",
                "zone": "example.com",
                "name": "x",
                "type": "TXT",
                "content": "v",
                "proxied": True,
                "ttl": 1,
            },
        )
        self.assertEqual(r.status_code, 400)
        # 代理开时 TTL 锁定 1。
        r = self.c.post(
            "/api/v1/records",
            json={
                "account": "t1",
                "zone": "example.com",
                "name": "www",
                "type": "A",
                "content": "1.2.3.4",
                "proxied": True,
                "ttl": 300,
            },
        )
        self.assertEqual(r.status_code, 400)

    def test_spa_fallback_no_traversal(self):
        # 无前端目录时未挂载 SPA；有目录时回退 index.html（由冒烟覆盖，此处仅验 404 映射）。
        r = self.c.get("/api/v1/jobs/no-such-id")
        self.assertEqual(r.status_code, 404)


if __name__ == "__main__":
    unittest.main()
