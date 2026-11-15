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


def make_legacy_jobs_db() -> str:
    tmp = tempfile.mkdtemp(prefix="cf_oldjobs_test_")
    cfg = os.path.join(tmp, "cf_config.json")
    with open(cfg, "w", encoding="utf-8") as fh:
        fh.write('{"accounts":{"u":{"cf_api_token":"dummy"}}}')
    c = sqlite3.connect(os.path.join(tmp, "cf_web.db"))
    c.execute(
        "CREATE TABLE jobs_history("
        "job_id TEXT PRIMARY KEY, label TEXT, kind TEXT, status TEXT,"
        " exit_code INTEGER, created_at TEXT, finished_at TEXT,"
        " id TEXT, mode TEXT, accounts TEXT)"
    )
    c.execute(
        "INSERT INTO jobs_history(job_id, label, kind, status, exit_code, created_at, finished_at)"
        " VALUES('job-old', 'legacy', 'preview', 'done', 0, 't0', 't1')"
    )
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

    def test_legacy_job_id_primary_key_migrated(self):
        db.init_db(make_legacy_jobs_db())
        rows = db.list_history(10)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], "job-old")
        self.assertEqual(rows[0]["mode"], "preview")
        db.upsert_history(
            {
                "id": "job-new",
                "mode": "execute",
                "status": "done",
                "label": "new",
                "accounts": "u",
                "exit_code": 0,
                "created_at": "t2",
                "finished_at": "t3",
            }
        )
        db.upsert_history(
            {
                "id": "job-new",
                "mode": "execute",
                "status": "failed",
                "label": "new",
                "accounts": "u",
                "exit_code": 1,
                "created_at": "t2",
                "finished_at": "t4",
            }
        )
        rows = db.list_history(10)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["id"], "job-new")
        self.assertEqual(rows[0]["status"], "failed")


if __name__ == "__main__":
    unittest.main()
