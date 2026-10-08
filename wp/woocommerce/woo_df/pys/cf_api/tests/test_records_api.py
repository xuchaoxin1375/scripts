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
        from tests.test_webui import make_client

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


if __name__ == "__main__":
    unittest.main()
