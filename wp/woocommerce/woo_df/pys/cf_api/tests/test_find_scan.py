# -*- coding: utf-8 -*-
"""跨账号查找扫描：进度、取消、失败语义与旧接口兼容。"""

from __future__ import annotations

import os
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui.backend import deps  # noqa: E402
from webui.backend.app import create_app  # noqa: E402
from webui.backend.services import find as find_service  # noqa: E402

SPEED = {
    "speed": "test",
    "account_workers": 2,
    "request_interval": 0.0,
    "max_retries": 1,
}


def fake_query(account, domain, **kwargs):
    """按账号名返回 hit/miss/error；pending 用于验证不按 active 过滤。"""
    name = account.get("name")
    if name == "hit":
        return {
            "account": name,
            "kind": "hit",
            "zone": domain,
            "zone_id": "z1",
            "status": "active",
            "elapsed_ms": 1,
        }
    if name == "pending":
        return {
            "account": name,
            "kind": "hit",
            "zone": domain,
            "zone_id": "z2",
            "status": "pending",
            "elapsed_ms": 2,
        }
    if name.startswith("error"):
        return {
            "account": name,
            "kind": "error",
            "error": "token 无 Zone:Read 权限",
            "elapsed_ms": 1,
        }
    return {"account": name, "kind": "miss", "elapsed_ms": 1}


def make_manager():
    return find_service.FindScanManager(query_fn=fake_query)


class FindScanServiceTest(unittest.TestCase):
    def test_mixed_results_and_progress(self):
        manager = make_manager()
        self.addCleanup(manager.shutdown)
        accounts = [
            {"name": "hit"},
            {"name": "pending"},
            {"name": "miss"},
            {"name": "error"},
        ]
        scan = manager.start(
            "example.com",
            accounts,
            SPEED,
            stop_on_first=False,
        )
        self.assertTrue(scan.wait(5))
        data = scan.snapshot()
        self.assertEqual(data["status"], "partial")
        self.assertEqual(data["checked"], 4)
        self.assertEqual(data["hits"], 2)
        self.assertEqual(data["misses"], 1)
        self.assertEqual(data["failed"], 1)
        self.assertTrue(data["complete"])
        self.assertEqual(
            sorted(item["status"] for item in data["results"]),
            ["active", "pending"],
        )
        self.assertEqual(data["missed_accounts"], ["miss"])
        self.assertEqual(data["errors"][0]["account"], "error")
        self.assertTrue(data["events"])

    def test_stop_on_first_stops_after_hit(self):
        manager = make_manager()
        self.addCleanup(manager.shutdown)
        scan = manager.start(
            "example.com",
            [
                {"name": "hit"},
                {"name": "miss1"},
                {"name": "miss2"},
                {"name": "miss3"},
            ],
            {**SPEED, "account_workers": 1},
            stop_on_first=True,
        )
        self.assertTrue(scan.wait(5))
        data = scan.snapshot()
        self.assertEqual(data["status"], "done")
        self.assertTrue(data["stopped_early"])
        self.assertEqual(data["stop_reason"], "first_hit")
        self.assertEqual(data["hits"], 1)
        self.assertLess(data["checked"], data["total"])
        self.assertGreater(data["unchecked"], 0)
        self.assertFalse(data["complete"])
        self.assertEqual(len(data["unchecked_accounts"]), data["unchecked"])

    def test_continue_scan_checks_remaining_accounts(self):
        manager = make_manager()
        self.addCleanup(manager.shutdown)
        accounts = [
            {"name": "hit"},
            {"name": "miss1"},
            {"name": "miss2"},
            {"name": "miss3"},
        ]
        scan = manager.start(
            "example.com",
            accounts,
            {**SPEED, "account_workers": 1},
            stop_on_first=True,
        )
        self.assertTrue(scan.wait(5))
        early = scan.snapshot()
        self.assertTrue(early["stopped_early"])
        self.assertGreater(early["unchecked"], 0)

        continued = manager.continue_scan(scan.id, accounts)
        self.assertIs(continued, scan)
        self.assertTrue(scan.wait(5))
        data = scan.snapshot()
        self.assertFalse(data["stopped_early"])
        self.assertEqual(data["status"], "done")
        self.assertEqual(data["checked"], 4)
        self.assertEqual(data["unchecked"], 0)
        self.assertEqual(data["hits"], 1)
        self.assertEqual(data["misses"], 3)
        self.assertTrue(data["complete"])
        self.assertTrue(
            any("继续扫描" in event["message"] for event in data["events"])
        )

    def test_continue_rejects_fully_checked_scan(self):
        manager = make_manager()
        self.addCleanup(manager.shutdown)
        accounts = [{"name": "hit"}, {"name": "miss1"}]
        scan = manager.start(
            "example.com",
            accounts,
            {**SPEED, "account_workers": 2},
            stop_on_first=False,
        )
        self.assertTrue(scan.wait(5))
        with self.assertRaises(ValueError):
            manager.continue_scan(scan.id, accounts)

    def test_scan_all_when_stop_on_first_disabled(self):
        manager = make_manager()
        self.addCleanup(manager.shutdown)
        scan = manager.start(
            "example.com",
            [
                {"name": "hit"},
                {"name": "miss1"},
                {"name": "miss2"},
                {"name": "miss3"},
            ],
            {**SPEED, "account_workers": 2},
            stop_on_first=False,
        )
        self.assertTrue(scan.wait(5))
        data = scan.snapshot()
        self.assertEqual(data["status"], "done")
        self.assertFalse(data["stopped_early"])
        self.assertEqual(data["checked"], 4)
        self.assertEqual(data["hits"], 1)
        self.assertEqual(data["misses"], 3)
        self.assertEqual(data["unchecked"], 0)
        self.assertTrue(data["complete"])

    def test_all_failed_is_not_reported_as_missing(self):
        manager = make_manager()
        self.addCleanup(manager.shutdown)
        scan = manager.start(
            "example.com",
            [{"name": "error"}, {"name": "error2"}],
            SPEED,
            stop_on_first=False,
        )
        self.assertTrue(scan.wait(5))
        data = scan.snapshot()
        self.assertEqual(data["status"], "failed")
        self.assertEqual(data["checked"], 2)
        self.assertEqual(data["hits"], 0)
        self.assertEqual(data["misses"], 0)
        self.assertEqual(data["failed"], 2)
        self.assertTrue(data["complete"])

    def test_cancel_scan(self):
        started = {"value": False}

        def blocking_query(account, domain, **kwargs):
            started["value"] = True
            kwargs["stop_event"].wait(2)
            return {"account": account.get("name"), "kind": "miss", "elapsed_ms": 1}

        manager = find_service.FindScanManager(query_fn=blocking_query)
        self.addCleanup(manager.shutdown)
        scan = manager.start(
            "example.com",
            [{"name": "a"}, {"name": "b"}],
            {**SPEED, "account_workers": 1},
        )
        deadline = time.monotonic() + 2
        while not started["value"] and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(manager.cancel(scan.id))
        self.assertTrue(scan.wait(5))
        data = scan.snapshot()
        self.assertEqual(data["status"], "cancelled")
        self.assertFalse(data["complete"])

    def test_cancel_before_worker_start_is_honoured(self):
        scan = find_service.FindScan(
            id="scan-early",
            domain="example.com",
            account_names=["a"],
        )
        self.assertTrue(scan.cancel())
        scan.start()
        scan.finish(cancelled=scan._stop_event.is_set())
        data = scan.snapshot()
        self.assertEqual(data["status"], "cancelled")
        self.assertFalse(data["complete"])

    def test_find_sync_legacy_shape(self):
        data = find_service.find_sync(
            "example.com",
            [{"name": "hit"}, {"name": "miss"}, {"name": "error"}],
            SPEED,
            query_fn=fake_query,
        )
        self.assertEqual(data["domain"], "example.com")
        self.assertEqual(data["found"], 1)
        self.assertEqual(data["checked"], 3)
        self.assertEqual(data["missed"], 1)
        self.assertEqual(data["failed"], 1)
        self.assertEqual(data["results"][0]["zone"], "example.com")
        self.assertIn("errors", data)

    def test_normalize_domain(self):
        self.assertEqual(find_service.normalize_domain("example.com"), "example.com")
        self.assertEqual(
            find_service.normalize_domain("https://www.example.com/path"),
            "example.com",
        )
        self.assertEqual(
            find_service.normalize_domain("*.example.com"),
            "example.com",
        )
        self.assertEqual(find_service.normalize_domain("not a domain !!!"), "")


class FindScanRouterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="cf_web_find_")
        cls.cfg = os.path.join(cls.tmp, "cf_config.json")
        with open(cls.cfg, "w", encoding="utf-8") as handle:
            handle.write(
                '{"accounts":{"hit":{"cf_api_token":"token-1234567890"},'
                '"miss":{"cf_api_token":"token-2234567890"}}}'
            )
        deps.configure(cls.cfg)
        deps.reset_find_manager()
        cls.app = create_app("")

    def setUp(self):
        self.manager = find_service.FindScanManager(query_fn=fake_query)
        self.patcher = patch(
            "webui.backend.deps.get_find_manager",
            return_value=self.manager,
        )
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()
        self.manager.shutdown()

    def test_scan_route_progress_and_result(self):
        from fastapi.testclient import TestClient

        client = TestClient(self.app)
        response = client.post(
            "/api/v1/find/scans",
            json={
                "domain": "example.com",
                "speed": "eco",
                "max_retries": 1,
                "stop_on_first": False,
            },
        )
        self.assertEqual(response.status_code, 200)
        first = response.json()
        self.assertEqual(first["domain"], "example.com")
        scan_id = first["scan_id"]
        deadline = time.monotonic() + 5
        data = first
        while data["status"] in {"pending", "running", "cancelling"}:
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.05)
            data = client.get(f"/api/v1/find/scans/{scan_id}").json()
        self.assertEqual(data["status"], "done")
        self.assertEqual(data["hits"], 1)
        self.assertEqual(data["misses"], 1)
        self.assertEqual(data["results"][0]["account"], "hit")

    def test_continue_route_resumes_unchecked_accounts(self):
        from fastapi.testclient import TestClient

        scan = self.manager.start(
            "example.com",
            [{"name": "hit"}, {"name": "miss"}],
            {**SPEED, "account_workers": 1},
            stop_on_first=True,
        )
        self.assertTrue(scan.wait(5))
        self.assertTrue(scan.snapshot()["stopped_early"])

        client = TestClient(self.app)
        response = client.post(
            f"/api/v1/find/scans/{scan.id}/continue",
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(scan.wait(5))
        data = scan.snapshot()
        self.assertEqual(data["checked"], 2)
        self.assertEqual(data["unchecked"], 0)
        self.assertFalse(data["stopped_early"])
        self.assertTrue(data["complete"])

    def test_invalid_domain_is_400(self):
        from fastapi.testclient import TestClient

        client = TestClient(self.app)
        response = client.post(
            "/api/v1/find/scans",
            json={"domain": "not a domain !!!"},
        )
        self.assertEqual(response.status_code, 400)

    def test_legacy_find_still_works(self):
        from fastapi.testclient import TestClient

        original = find_service.find_sync

        def legacy(domain, accounts, speed, proxy_pool=None):
            return original(
                domain,
                accounts,
                speed,
                proxy_pool,
                query_fn=fake_query,
            )

        client = TestClient(self.app)
        with patch(
            "webui.backend.services.find.find_sync",
            side_effect=legacy,
        ):
            response = client.get(
                "/api/v1/find", params={"domain": "example.com"}
            )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["found"], 1)
        self.assertEqual(data["checked"], 2)


if __name__ == "__main__":
    unittest.main()
