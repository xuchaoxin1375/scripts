# -*- coding: utf-8 -*-
"""邮箱转发路由契约测试：目标地址验证、zone 状态与完成配置。"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from typing import Any, Optional
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui.backend import deps  # noqa: E402
from webui.backend.app import create_app  # noqa: E402

CONFIG_JSON = '{"accounts":{"t1":{"cf_api_token":"secret-token-1234567890"}}}'


def make_client():
    tmp = tempfile.mkdtemp(prefix="cf_web_email_")
    cfg = os.path.join(tmp, "cf_config.json")
    with open(cfg, "w", encoding="utf-8") as fh:
        fh.write(CONFIG_JSON)
    deps.configure(cfg)
    app = create_app("")
    from fastapi.testclient import TestClient

    return TestClient(app)


class FakeUpdater:
    """只实现邮箱转发服务用到的引擎方法。"""

    account_name = "t1"

    def __init__(self) -> None:
        self.addresses: list[dict[str, Any]] = [
            {
                "id": "a1",
                "email": "owner@gmail.com",
                "verified": "2026-11-16T00:00:00Z",
                "created": "",
                "modified": "",
            },
            {
                "id": "a2",
                "email": "pending@example.net",
                "verified": None,
                "created": "",
                "modified": "",
            },
        ]
        self.zone_state = "active"
        self.mx_records: list[dict[str, Any]] = [
            {
                "name": "example.com",
                "content": "route1.mx.cloudflare.net",
                "priority": 10,
            }
        ]
        self.created: list[str] = []
        self.configured: list[tuple[str, str, str]] = []

    def get_account_id(self) -> str:
        return "acc1"

    def _request(
        self,
        method: str,
        path: str,
        params: Optional[dict[str, Any]] = None,
        json: Any = None,
    ) -> dict[str, Any]:
        if method == "GET" and path.endswith("/email/routing/addresses"):
            return {"result": self.addresses}
        if method == "GET" and path.endswith("/email/routing"):
            return {"result": {"enabled": True}}
        if method == "GET" and path.endswith("/email/routing/rules/catch_all"):
            return {
                "result": {
                    "enabled": True,
                    "name": "catch-all",
                    "actions": [{"type": "forward", "value": ["owner@gmail.com"]}],
                }
            }
        raise AssertionError(f"未模拟: {method} {path}")

    def create_email_routing_address(self, email: str) -> dict[str, Any]:
        self.created.append(email)
        self.addresses.append(
            {
                "id": "a3",
                "email": email,
                "verified": None,
                "created": "",
                "modified": "",
            }
        )
        return {}

    def get_zone(self, zone_id: str) -> dict[str, Any]:
        return {
            "result": {
                "id": zone_id,
                "name": "example.com",
                "status": self.zone_state,
            }
        }

    def get_email_routing_settings(self, zone_id: str) -> dict[str, Any]:
        return {"enabled": True}

    def get_email_routing_required_records(self, zone_id: str) -> list[dict[str, Any]]:
        return [
            {
                "type": "MX",
                "name": "example.com",
                "content": "route1.mx.cloudflare.net",
                "priority": 10,
            }
        ]

    def get_dns_records(self, zone_id: str, record_type: str) -> list[dict[str, Any]]:
        return self.mx_records

    def configure_email_routing(
        self, zone_id: str, zone_name: str, email: str
    ) -> tuple[str, str, list[str]]:
        self.configured.append((zone_id, zone_name, email))
        return "ok", f"邮箱转发已配置到 {email}", ["MX example.com: ok"]


class EmailRoutingContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = make_client()

    def setUp(self):
        self.updater = FakeUpdater()
        self.patches = [
            patch(
                "webui.backend.engine_adapter.build_updater",
                return_value=self.updater,
            ),
            patch(
                "webui.backend.services.zones.get_zones",
                return_value=[{"id": "z1", "name": "example.com", "status": "active"}],
            ),
        ]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()

    def test_addresses_and_target(self):
        body = self.c.get(
            "/api/v1/email-routing/addresses",
            params={"account": "t1", "email": "OWNER@gmail.com"},
        ).json()
        self.assertEqual(body["total"], 2)
        self.assertTrue(body["target"]["verified"])
        self.assertEqual(body["target"]["email"], "owner@gmail.com")

    def test_unknown_account_400(self):
        r = self.c.get("/api/v1/email-routing/addresses", params={"account": "no-such"})
        self.assertEqual(r.status_code, 400)

    def test_status_reports_catch_all_and_mx(self):
        body = self.c.get(
            "/api/v1/email-routing/status",
            params={"account": "t1", "zone": "example.com"},
        ).json()
        self.assertEqual(body["zone_status"], "active")
        self.assertTrue(body["routing_enabled"])
        self.assertTrue(body["catch_all"]["enabled"])
        self.assertEqual(body["catch_all"]["forward_to"], ["owner@gmail.com"])
        self.assertEqual(body["non_cloudflare_mx"], [])
        self.assertEqual(body["required_records"][0]["type"], "MX")

    def test_status_flags_non_cloudflare_mx(self):
        self.updater.mx_records = [
            {"name": "example.com", "content": "mx.google.com", "priority": 1}
        ]
        body = self.c.get(
            "/api/v1/email-routing/status",
            params={"account": "t1", "zone": "example.com"},
        ).json()
        self.assertEqual(body["non_cloudflare_mx"], ["mx.google.com"])

    def test_status_unknown_zone_404(self):
        r = self.c.get(
            "/api/v1/email-routing/status",
            params={"account": "t1", "zone": "missing.example"},
        )
        self.assertEqual(r.status_code, 404)

    def test_add_existing_verified_address(self):
        body = self.c.post(
            "/api/v1/email-routing/addresses",
            json={"account": "t1", "email": "owner@gmail.com"},
        ).json()
        self.assertTrue(body["found"])
        self.assertTrue(body["verified"])
        self.assertFalse(body["created"])
        self.assertEqual(self.updater.created, [])

    def test_add_new_address_triggers_verification(self):
        body = self.c.post(
            "/api/v1/email-routing/addresses",
            json={"account": "t1", "email": "new@gmail.com"},
        ).json()
        self.assertTrue(body["found"])
        self.assertFalse(body["verified"])
        self.assertTrue(body["created"])
        self.assertIn("new@gmail.com", self.updater.created)

    def test_add_invalid_email_400(self):
        r = self.c.post(
            "/api/v1/email-routing/addresses",
            json={"account": "t1", "email": "not-an-email"},
        )
        self.assertEqual(r.status_code, 400)

    def test_complete_requires_verified_address(self):
        r = self.c.post(
            "/api/v1/email-routing/complete",
            json={
                "account": "t1",
                "zone": "example.com",
                "email": "pending@example.net",
            },
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("尚未验证", r.json()["detail"])

    def test_complete_requires_active_zone(self):
        self.updater.zone_state = "pending"
        r = self.c.post(
            "/api/v1/email-routing/complete",
            json={
                "account": "t1",
                "zone": "example.com",
                "email": "owner@gmail.com",
            },
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("active", r.json()["detail"])

    def test_complete_sets_catch_all(self):
        body = self.c.post(
            "/api/v1/email-routing/complete",
            json={
                "account": "t1",
                "zone": "example.com",
                "email": "owner@gmail.com",
            },
        ).json()
        self.assertEqual(body["status"], "ok")
        self.assertEqual(body["zone"], "example.com")
        self.assertEqual(
            self.updater.configured,
            [("z1", "example.com", "owner@gmail.com")],
        )


if __name__ == "__main__":
    unittest.main()
