# -*- coding: utf-8 -*-
"""记录表重建支撑接口的契约测试（标准库 unittest，无外网依赖）。

覆盖：备注与优先级校验、精简视图透传、批量空载荷、导入预检门
（超量/重复/非法类型/超大备注，均在联网前拒绝）。
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui.backend import engine_adapter  # noqa: E402
from webui.backend.services import records as records_service  # noqa: E402
from webui.backend.validate import validate_single_record  # noqa: E402


class RecordValidateTest(unittest.TestCase):
    def test_comment_too_long(self):
        err = validate_single_record(
            {"type": "A", "content": "1.2.3.4", "proxied": False, "ttl": 1,
             "comment": "x" * 101}
        )
        self.assertIsNotNone(err)
        self.assertIn("100", err)

    def test_comment_ok(self):
        err = validate_single_record(
            {"type": "TXT", "content": "v", "proxied": False, "ttl": 1,
             "comment": "Strict DMA"}
        )
        self.assertIsNone(err)

    def test_priority_only_mx(self):
        err = validate_single_record(
            {"type": "A", "content": "1.2.3.4", "proxied": False, "ttl": 1,
             "priority": 10}
        )
        self.assertIsNotNone(err)
        self.assertIn("MX", err)

    def test_priority_range(self):
        bad = validate_single_record(
            {"type": "MX", "content": "m.example.com", "proxied": False,
             "ttl": 300, "priority": 99999}
        )
        self.assertIsNotNone(bad)
        ok = validate_single_record(
            {"type": "MX", "content": "m.example.com", "proxied": False,
             "ttl": 300, "priority": 10}
        )
        self.assertIsNone(ok)

    def test_slim_passthrough(self):
        slim = engine_adapter.slim_record(
            {"id": "1", "type": "MX", "name": "x", "content": "m",
             "ttl": 300, "proxied": False, "comment": "note", "priority": 10}
        )
        self.assertEqual(slim["comment"], "note")
        self.assertEqual(slim["priority"], 10)
        slim2 = engine_adapter.slim_record(
            {"id": "2", "type": "A", "name": "@", "content": "1.2.3.4"}
        )
        self.assertEqual(slim2["comment"], "")
        self.assertIsNone(slim2["priority"])


class RecordApiGateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from .test_webui import make_client

        cls.c = make_client()

    def test_bulk_empty_ids_no_network(self):
        r = self.c.post(
            "/api/v1/records/bulk-delete",
            json={"account": "t1", "zone": "example.com", "ids": []},
        )
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["total"], 0)

    def test_bulk_unknown_account(self):
        r = self.c.post(
            "/api/v1/records/bulk-delete",
            json={"account": "nobody", "zone": "example.com", "ids": ["x"]},
        )
        self.assertEqual(r.status_code, 400)

    def test_bulk_update_requires_patch(self):
        r = self.c.post(
            "/api/v1/records/bulk-update",
            json={"account": "t1", "zone": "example.com", "ids": ["x"]},
        )
        self.assertEqual(r.status_code, 400)

    def test_bulk_content_empty_ids_no_network(self):
        r = self.c.post(
            "/api/v1/records/bulk-update",
            json={
                "account": "t1",
                "zone": "example.com",
                "ids": [],
                "content": "198.51.100.10",
            },
        )
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["total"], 0)

    def test_bulk_update_content_writes_selected_ids(self):
        from unittest import mock

        from webui.backend.routers import records as records_router

        class FakeUpdater:
            def get_dns_records(self, zone_id, record_type):
                return [
                    {
                        "id": "r1",
                        "type": "A",
                        "name": "www.example.com",
                        "content": "203.0.113.10",
                        "ttl": 1,
                        "proxied": False,
                        "comment": "",
                        "priority": None,
                    }
                ]

        updater = FakeUpdater()
        with mock.patch.object(
            records_router, "lookup_accounts", return_value=[{"name": "t1"}]
        ):
            with mock.patch.object(
                records_router,
                "resolve_zone",
                return_value=("z1", "example.com"),
            ):
                with mock.patch.object(
                    records_router.engine_adapter,
                    "build_updater",
                    return_value=updater,
                ):
                    with mock.patch.object(
                        records_router.engine_adapter, "write_record_full"
                    ) as write:
                        r = self.c.post(
                            "/api/v1/records/bulk-update",
                            json={
                                "account": "t1",
                                "zone": "example.com",
                                "ids": ["r1"],
                                "content": "198.51.100.88",
                            },
                        )
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["updated"], ["r1"])
        self.assertFalse(r.json()["failed"])
        self.assertEqual(write.call_args.args[3]["content"], "198.51.100.88")

    def test_export_unknown_account_400(self):
        r = self.c.post(
            "/api/v1/records/export",
            json={"account": "nobody", "zone": "example.com", "ids": []},
        )
        self.assertEqual(r.status_code, 400)

    def test_import_over_cap(self):
        recs = [
            {"name": f"h{i}", "type": "A", "content": "1.2.3.4"}
            for i in range(201)
        ]
        r = self.c.post(
            "/api/v1/records/import",
            json={"account": "t1", "zone": "example.com", "records": recs},
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("200", r.json()["detail"])

    def test_import_duplicate_rejected(self):
        rec = {"name": "www", "type": "A", "content": "1.2.3.4"}
        r = self.c.post(
            "/api/v1/records/import",
            json={"account": "t1", "zone": "example.com",
                  "records": [rec, dict(rec)]},
        )
        self.assertEqual(r.status_code, 400)
        self.assertIn("重复", r.json()["detail"])

    def test_import_bad_type_rejected(self):
        r = self.c.post(
            "/api/v1/records/import",
            json={"account": "t1", "zone": "example.com",
                  "records": [{"name": "www", "type": "NOPE",
                               "content": "1.2.3.4"}]},
        )
        self.assertEqual(r.status_code, 400)

    def test_import_comment_too_long_rejected(self):
        r = self.c.post(
            "/api/v1/records/import",
            json={"account": "t1", "zone": "example.com",
                  "records": [{"name": "www", "type": "A",
                               "content": "1.2.3.4", "comment": "y" * 101}]},
        )
        self.assertEqual(r.status_code, 400)

    def test_restore_validates_before_write(self):
        r = self.c.post(
            "/api/v1/records/bulk-restore",
            json={"account": "t1", "zone": "example.com",
                  "records": [{"name": "", "type": "A", "content": "x"}]},
        )
        self.assertEqual(r.status_code, 400)


class RecordCacheTest(unittest.TestCase):
    """记录读取缓存：排序/筛选/翻页不重复打 Cloudflare，写入后失效。"""

    def setUp(self):
        records_service.invalidate()

    def tearDown(self):
        records_service.invalidate()

    def test_cache_hit_and_invalidate(self):
        from unittest import mock

        calls = []

        def fake_get_records(account, zone_id, record_type):
            calls.append((account.get("name"), zone_id, record_type))
            return [{"id": "r1", "type": "A", "name": "www.example.com"}]

        with mock.patch.object(
            records_service.engine_adapter, "get_records", side_effect=fake_get_records
        ):
            first = records_service.load_records({"name": "t1"}, "z1")
            first[0]["name"] = "mutated"
            second = records_service.load_records({"name": "t1"}, "z1")
            self.assertEqual(len(calls), 1)
            self.assertEqual(second[0]["name"], "www.example.com")
            records_service.invalidate({"name": "t1"}, "z1")
            records_service.load_records({"name": "t1"}, "z1")
            self.assertEqual(len(calls), 2)

    def test_refresh_bypasses_cache(self):
        from unittest import mock

        calls = []

        def fake_get_records(account, zone_id, record_type):
            calls.append(zone_id)
            return []

        with mock.patch.object(
            records_service.engine_adapter, "get_records", side_effect=fake_get_records
        ):
            records_service.load_records({"name": "t1"}, "z1")
            records_service.load_records({"name": "t1"}, "z1")
            records_service.load_records({"name": "t1"}, "z1", refresh=True)
            self.assertEqual(len(calls), 2)

    def test_records_route_reuses_cache_for_sort(self):
        from unittest import mock

        from webui.backend.routers import records as records_router

        c = self._client()
        calls = []
        rows = [
            {"id": "r2", "type": "A", "name": "www.example.com", "content": "203.0.113.2"},
            {"id": "r1", "type": "A", "name": "api.example.com", "content": "203.0.113.1"},
            {"id": "r3", "type": "A", "name": "example.com", "content": "203.0.113.3"},
        ]

        def fake_get_records(account, zone_id, record_type):
            calls.append(zone_id)
            return [dict(item) for item in rows]

        with mock.patch.object(
            records_router, "lookup_accounts", return_value=[{"name": "t1"}]
        ):
            with mock.patch.object(
                records_router,
                "get_zones",
                return_value=[{"name": "example.com", "id": "z1", "status": "active"}],
            ):
                with mock.patch.object(
                    records_service.engine_adapter,
                    "get_records",
                    side_effect=fake_get_records,
                ):
                    first = c.get(
                        "/api/v1/records",
                        params={"account": "t1", "zone": "example.com"},
                    )
                    second = c.get(
                        "/api/v1/records",
                        params={
                            "account": "t1",
                            "zone": "example.com",
                            "sort": "name",
                        },
                    )
        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(len(calls), 1)
        self.assertEqual(
            [item["name"] for item in second.json()["items"]],
            ["api.example.com", "example.com", "www.example.com"],
        )

    def test_records_all_returns_full_collection(self):
        from unittest import mock

        from webui.backend.routers import records as records_router

        c = self._client()
        rows = [
            {"id": "r1", "type": "A", "name": "example.com", "content": "203.0.113.1"},
            {"id": "r2", "type": "A", "name": "www.example.com", "content": "203.0.113.2"},
        ]
        with mock.patch.object(
            records_router, "lookup_accounts", return_value=[{"name": "t1"}]
        ):
            with mock.patch.object(
                records_router,
                "get_zones",
                return_value=[{"name": "example.com", "id": "z1", "status": "active"}],
            ):
                with mock.patch.object(
                    records_service.engine_adapter,
                    "get_records",
                    return_value=[dict(item) for item in rows],
                ):
                    r = c.get(
                        "/api/v1/records",
                        params={
                            "account": "t1",
                            "zone": "example.com",
                            "all": "true",
                        },
                    )
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body["total"], 2)
        self.assertEqual(len(body["items"]), 2)
        self.assertFalse(body["truncated"])
        self.assertEqual(body["page"], 1)

    def test_refresh_route_invalidates_cache(self):
        from unittest import mock

        from webui.backend.routers import records as records_router

        c = self._client()
        with mock.patch.object(
            records_router, "lookup_accounts", return_value=[{"name": "t1"}]
        ):
            with mock.patch.object(
                records_router, "resolve_zone", return_value=("z1", "example.com")
            ):
                with mock.patch.object(
                    records_router, "invalidate_records"
                ) as invalidate:
                    r = c.post(
                        "/api/v1/records/refresh",
                        json={"account": "t1", "zone": "example.com"},
                    )
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["refreshed"])
        invalidate.assert_called_once_with({"name": "t1"}, "z1")

    @staticmethod
    def _client():
        from .test_webui import make_client

        return make_client()


if __name__ == "__main__":
    unittest.main()
