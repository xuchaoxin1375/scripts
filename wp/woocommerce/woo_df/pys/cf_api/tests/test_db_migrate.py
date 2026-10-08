# -*- coding: utf-8 -*-
"""旧库 schema 迁移回归测试：audit_log 缺 kind 列的旧 cf_web.db 不得挂接口。

回归用户报障：sqlite3.OperationalError: no such column: kind。
"""

from __future__ import annotations

import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui.backend import db  # noqa: E402


def make_old_db() -> str:
    tmp = tempfile.mkdtemp(prefix="cf_oldb_test_")
    cfg = os.path.join(tmp, "cf_config.json")
    with open(cfg, "w", encoding="utf-8") as fh:
        fh.write('{"accounts":{"u":{"cf_api_token":"dummy"}}}')
    c = sqlite3.connect(os.path.join(tmp, "cf_web.db"))
    c.execute(
        "CREATE TABLE audit_log(id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, account TEXT)"
    )
    c.execute("INSERT INTO audit_log(ts, account) VALUES('t0', 'u')")
    c.execute("CREATE TABLE jobs_history(id TEXT PRIMARY KEY, mode TEXT, status TEXT)")
    c.commit()
    c.close()
    return cfg


class OldDbMigrateTest(unittest.TestCase):
    def test_missing_columns_migrated_and_data_kept(self):
        db.init_db(make_old_db())
        rows = db.list_audit(10)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["account"], "u")
        self.assertIn("kind", rows[0])
        self.assertEqual(db.list_history(10), [])
        db.audit("execute", account="u")
        self.assertEqual(len(db.list_audit(10)), 2)


if __name__ == "__main__":
    unittest.main()
