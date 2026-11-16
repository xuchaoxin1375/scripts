# -*- coding: utf-8 -*-
"""邮箱路由引擎安全边界：未验证目标地址不得改动 DNS/MX/路由。"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from cloudflare_dns_tool import CloudflareDNSUpdater  # noqa: E402


class EmailRoutingEngineSafetyTest(unittest.TestCase):
    def make_updater(self, verified: bool):
        updater = object.__new__(CloudflareDNSUpdater)
        calls: list[str] = []

        def ensure(email: str) -> tuple[bool, str]:
            calls.append("ensure")
            return verified, "verified" if verified else "unverified"

        def records(zone_id: str) -> list[dict]:
            calls.append("records")
            return [
                {
                    "type": "MX",
                    "name": "example.com",
                    "content": "route1.mx.cloudflare.net",
                    "priority": 10,
                }
            ]

        def ensure_dns(*args, **kwargs) -> tuple[str, str]:
            calls.append("dns")
            return "added", ""

        def settings(zone_id: str) -> dict:
            calls.append("settings")
            return {"enabled": False}

        def enable(zone_id: str) -> dict:
            calls.append("enable")
            return {}

        def catch_all(zone_id: str, email: str) -> dict:
            calls.append("catch_all")
            return {}

        updater.ensure_email_routing_address = ensure  # type: ignore[method-assign]
        updater.get_email_routing_required_records = records  # type: ignore[method-assign]
        updater.ensure_dns_record = ensure_dns  # type: ignore[method-assign]
        updater.get_email_routing_settings = settings  # type: ignore[method-assign]
        updater.enable_email_routing = enable  # type: ignore[method-assign]
        updater.update_email_routing_catch_all = catch_all  # type: ignore[method-assign]
        return updater, calls

    def test_unverified_target_returns_before_any_dns_or_route_change(self):
        updater, calls = self.make_updater(verified=False)

        status, message, records = CloudflareDNSUpdater.configure_email_routing(
            updater, "z1", "example.com", "new@example.com"
        )

        self.assertEqual(status, "pending_verification")
        self.assertIn("未修改 DNS、MX 或路由", message)
        self.assertEqual(records, [])
        self.assertEqual(calls, ["ensure"])

    def test_verified_target_still_configures_dns_routing_and_catch_all(self):
        updater, calls = self.make_updater(verified=True)

        status, message, records = CloudflareDNSUpdater.configure_email_routing(
            updater, "z1", "example.com", "owner@example.com"
        )

        self.assertEqual(status, "ok")
        self.assertIn("owner@example.com", message)
        self.assertEqual(records, ["MX example.com: added"])
        self.assertEqual(
            calls,
            ["ensure", "records", "dns", "settings", "enable", "catch_all"],
        )

    def test_empty_target_is_rejected_without_touching_network(self):
        updater, calls = self.make_updater(verified=False)

        status, message, records = CloudflareDNSUpdater.configure_email_routing(
            updater, "z1", "example.com", "   "
        )

        self.assertEqual(status, "error")
        self.assertEqual(message, "邮箱转发目标为空")
        self.assertEqual(records, [])
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
