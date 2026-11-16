# -*- coding: utf-8 -*-
"""运行时出口代理 API 回归：列表保留、总开关、单项开关、脱敏与审计。"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui.backend import deps  # noqa: E402
from webui.backend.app import create_app  # noqa: E402

CONFIG_JSON = '{"accounts":{"t1":{"cf_api_token":"secret-token-1234567890"}}}'


class ProxyApiTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.mkdtemp(prefix="cf_web_proxy_")
        self.cfg = os.path.join(tmp, "cf_config.json")
        with open(self.cfg, "w", encoding="utf-8") as fh:
            fh.write(CONFIG_JSON)
        deps.configure(self.cfg)
        from fastapi.testclient import TestClient

        self.c = TestClient(create_app(""))

    def tearDown(self):
        deps.configure(self.cfg)

    def save(self, enabled: bool, mode: str, proxies: list[dict]) -> dict:
        r = self.c.put(
            "/api/v1/proxy",
            json={"enabled": enabled, "mode": mode, "proxies": proxies},
        )
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def test_empty_proxy_shape(self):
        body = self.c.get("/api/v1/proxy").json()
        self.assertEqual(
            body,
            {
                "enabled": False,
                "mode": "round-robin",
                "proxies": [],
                "count": 0,
                "total": 0,
                "enabled_count": 0,
                "active": False,
                "persisted": False,
            },
        )
        meta = self.c.get("/api/v1/meta").json()
        self.assertEqual(meta["proxy"]["count"], 0)
        self.assertEqual(meta["proxy"]["total"], 0)
        self.assertFalse(meta["proxy"]["enabled"])

    def test_save_entries_masks_credentials_and_builds_active_pool(self):
        body = self.save(
            True,
            "failover",
            [
                {"url": "http://user:pass@127.0.0.1:7897", "enabled": True},
                {"url": "http://127.0.0.1:7898", "enabled": False},
            ],
        )
        self.assertTrue(body["enabled"])
        self.assertEqual(body["mode"], "failover")
        self.assertEqual(body["total"], 2)
        self.assertEqual(body["enabled_count"], 1)
        self.assertEqual(body["count"], 1)
        self.assertTrue(body["active"])
        self.assertEqual([item["enabled"] for item in body["proxies"]], [True, False])
        self.assertNotIn("user:pass", " ".join(item["url"] for item in body["proxies"]))
        self.assertIn("http://127.0.0.1:7897", body["proxies"][0]["url"])

        pool = deps.get_proxy_pool()
        self.assertIsNotNone(pool)
        self.assertEqual(pool.mode, "failover")
        self.assertEqual(pool.urls, ["http://user:pass@127.0.0.1:7897"])

        meta = self.c.get("/api/v1/meta").json()
        self.assertEqual(
            meta["proxy"],
            {
                "mode": "failover",
                "count": 1,
                "total": 2,
                "enabled": True,
                "enabled_count": 1,
            },
        )

    def test_toggle_existing_by_id_preserves_credentials(self):
        saved = self.save(
            True,
            "failover",
            [
                {"url": "http://user:pass@127.0.0.1:7897", "enabled": True},
                {"url": "http://127.0.0.1:7898", "enabled": False},
            ],
        )
        first_id = saved["proxies"][0]["id"]
        second_id = saved["proxies"][1]["id"]

        toggled = self.save(
            True,
            "failover",
            [
                {"id": first_id, "enabled": False},
                {"id": second_id, "enabled": True},
            ],
        )
        self.assertEqual(toggled["count"], 1)
        self.assertEqual(deps.get_proxy_pool().urls, ["http://127.0.0.1:7898"])
        # 只传 id 时服务端继续保留原凭据，界面无需回显或重填。
        stored = {entry.id: entry for entry in deps.get_proxy_config().entries}
        self.assertEqual(stored[first_id].url, "http://user:pass@127.0.0.1:7897")
        self.assertFalse(stored[first_id].enabled)

        restored = self.save(
            True,
            "failover",
            [
                {"id": first_id, "enabled": True},
                {"id": second_id, "enabled": False},
            ],
        )
        self.assertEqual(restored["count"], 1)
        self.assertEqual(
            deps.get_proxy_pool().urls, ["http://user:pass@127.0.0.1:7897"]
        )

    def test_master_switch_off_keeps_saved_entries(self):
        saved = self.save(
            True,
            "sticky",
            [{"url": "http://127.0.0.1:7897", "enabled": True}],
        )
        entry_id = saved["proxies"][0]["id"]
        body = self.save(
            False,
            "sticky",
            [{"id": entry_id, "enabled": True}],
        )
        self.assertFalse(body["enabled"])
        self.assertFalse(body["active"])
        self.assertEqual(body["count"], 0)
        self.assertEqual(body["total"], 1)
        self.assertEqual(body["enabled_count"], 1)
        self.assertIsNone(deps.get_proxy_pool())
        self.assertEqual(len(deps.get_proxy_config().entries), 1)

        reenabled = self.save(
            True,
            "sticky",
            [{"id": entry_id, "enabled": True}],
        )
        self.assertTrue(reenabled["active"])
        self.assertEqual(reenabled["count"], 1)

    def test_clear_list(self):
        self.save(
            True,
            "round-robin",
            [{"url": "http://127.0.0.1:7897", "enabled": True}],
        )
        body = self.save(False, "round-robin", [])
        self.assertEqual(body["total"], 0)
        self.assertEqual(body["count"], 0)
        self.assertEqual(body["proxies"], [])
        self.assertIsNone(deps.get_proxy_pool())

    def test_duplicate_url_merges_to_one_entry(self):
        body = self.save(
            True,
            "round-robin",
            [
                {"url": "http://127.0.0.1:7897", "enabled": False},
                {"url": "http://127.0.0.1:7897", "enabled": True},
            ],
        )
        self.assertEqual(body["total"], 1)
        self.assertEqual(body["enabled_count"], 1)
        self.assertEqual(deps.get_proxy_pool().urls, ["http://127.0.0.1:7897"])

    def test_invalid_mode_url_or_unknown_id_keeps_state(self):
        saved = self.save(
            True,
            "round-robin",
            [{"url": "http://127.0.0.1:7897", "enabled": True}],
        )
        entry_id = saved["proxies"][0]["id"]

        bad_mode = self.c.put(
            "/api/v1/proxy",
            json={
                "enabled": True,
                "mode": "random",
                "proxies": [{"id": entry_id, "enabled": True}],
            },
        )
        self.assertEqual(bad_mode.status_code, 400)
        bad_url = self.c.put(
            "/api/v1/proxy",
            json={
                "enabled": True,
                "mode": "round-robin",
                "proxies": [{"url": "socks5://127.0.0.1:1080", "enabled": True}],
            },
        )
        self.assertEqual(bad_url.status_code, 400)
        unknown = self.c.put(
            "/api/v1/proxy",
            json={
                "enabled": True,
                "mode": "round-robin",
                "proxies": [{"id": "missing", "enabled": True}],
            },
        )
        self.assertEqual(unknown.status_code, 400)

        current = self.c.get("/api/v1/proxy").json()
        self.assertEqual(current["total"], 1)
        self.assertEqual(current["count"], 1)
        self.assertEqual(current["proxies"][0]["id"], entry_id)

    def test_proxy_change_audits_counts_not_urls(self):
        self.save(
            True,
            "failover",
            [
                {"url": "http://user:pass@127.0.0.1:7897", "enabled": True},
                {"url": "http://127.0.0.1:7898", "enabled": False},
            ],
        )
        audit = self.c.get("/api/v1/audit", params={"limit": 10}).json()
        rows = [item for item in audit["items"] if item["kind"] == "proxy_config"]
        self.assertTrue(rows)
        detail = rows[0]["detail"]
        self.assertIn("1/2", detail)
        self.assertIn("failover", detail)
        self.assertNotIn("127.0.0.1", detail)
        self.assertNotIn("user:pass", detail)

    def test_proxy_requires_auth_when_password_set(self):
        from fastapi.testclient import TestClient

        deps.configure(self.cfg, password="secret")
        client = TestClient(create_app(""))
        self.assertEqual(client.get("/api/v1/proxy").status_code, 401)
        self.assertEqual(
            client.put(
                "/api/v1/proxy",
                json={
                    "enabled": True,
                    "mode": "round-robin",
                    "proxies": [{"url": "http://127.0.0.1:7897", "enabled": True}],
                },
            ).status_code,
            401,
        )
        allowed = client.put(
            "/api/v1/proxy",
            json={
                "enabled": True,
                "mode": "round-robin",
                "proxies": [{"url": "http://127.0.0.1:7897", "enabled": True}],
            },
            headers={"X-Auth-Token": "secret"},
        )
        self.assertEqual(allowed.status_code, 200)
        self.assertEqual(allowed.json()["count"], 1)


if __name__ == "__main__":
    unittest.main()
