# -*- coding: utf-8 -*-
"""WebUI 增量端点回归（全部功能补齐部分，不碰黄金 test_webui）。

覆盖：resume-upload、find 参数校验、单条 PATCH/DELETE 参数校验、
provision SSL 校验、zones 未知账号 400、meta 含 version/proxy。
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui.backend import deps  # noqa: E402
from webui.backend.app import create_app  # noqa: E402

CONFIG_JSON = '{"accounts":{"t1":{"cf_api_token":"secret-token-1234567890"}}}'


def make_client():
    tmp = tempfile.mkdtemp(prefix="cf_web_extra_")
    cfg = os.path.join(tmp, "cf_config.json")
    with open(cfg, "w", encoding="utf-8") as fh:
        fh.write(CONFIG_JSON)
    deps.configure(cfg)
    app = create_app("")
    from fastapi.testclient import TestClient

    return TestClient(app)


class ExtraContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = make_client()

    def test_meta_has_version_and_proxy(self):
        body = self.c.get("/api/v1/meta").json()
        self.assertIn("version", body)
        self.assertIn("proxy", body)
        self.assertIn("count", body["proxy"])

    def test_zones_unknown_account_400(self):
        r = self.c.get("/api/v1/zones", params={"account": "no-such"})
        self.assertEqual(r.status_code, 400)

    def test_find_garbage_domain_graceful(self):
        r = self.c.get("/api/v1/find", params={"domain": "not a domain !!!"})
        self.assertEqual(r.status_code, 200)
        self.assertIn("results", r.json())

    def test_patch_missing_id_400(self):
        r = self.c.post(
            "/api/v1/jobs",
            json={
                "mode": "provision",
                "accounts": ["t1"],
                "domains": ["example.com"],
                "ssl_mode": "bogus",
            },
        )
        self.assertEqual(r.status_code, 400)
        r = self.c.request(
            "PATCH",
            "/api/v1/records",
            json={"account": "t1", "zone": "example.com", "id": ""},
        )
        self.assertEqual(r.status_code, 400)

    def test_delete_missing_id_400(self):
        r = self.c.delete(
            "/api/v1/records",
            params={"account": "t1", "zone": "example.com", "id": " "},
        )
        self.assertEqual(r.status_code, 400)

    def test_resume_upload_roundtrip_and_limit(self):
        ok = self.c.post(
            "/api/v1/resume-upload",
            files={"file": ("f.csv", b"account,zone\nt1,example.com\n")},
        )
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.json()["rows"], 1)
        try:
            os.unlink(ok.json()["path"])
        except OSError:
            pass
        big = b"a" * (2 * 1024 * 1024 + 1)
        r = self.c.post("/api/v1/resume-upload", files={"file": ("big.csv", big)})
        self.assertEqual(r.status_code, 400)

    def test_whitelist_upload_roundtrip(self):
        ok = self.c.post(
            "/api/v1/whitelist-upload",
            files={"file": ("w.txt", b"example.com\nhttps://www.example.net/x\n")},
        )
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.json()["count"], 2)
        try:
            os.unlink(ok.json()["path"])
        except OSError:
            pass
        bad = self.c.post(
            "/api/v1/whitelist-upload", files={"file": ("w.txt", b"not a domain !!!\n")}
        )
        self.assertEqual(bad.status_code, 200)
        self.assertEqual(bad.json()["count"], 0)
        try:
            os.unlink(bad.json()["path"])
        except OSError:
            pass

    def test_zones_csv_unknown_account_400(self):
        r = self.c.get("/api/v1/zones.csv", params={"account": "no-such"})
        self.assertEqual(r.status_code, 400)

    def test_history_and_audit_page_shape(self):
        hist = self.c.get("/api/v1/history", params={"limit": 10, "offset": 0})
        self.assertEqual(hist.status_code, 200)
        self.assertIn("items", hist.json())
        self.assertIn("total", hist.json())
        audit = self.c.get("/api/v1/audit", params={"limit": 10})
        self.assertEqual(audit.status_code, 200)
        self.assertIn("items", audit.json())
        self.assertIn("total", audit.json())

    def test_explicit_workers_validation(self):
        base = {"accounts": ["t1"], "domains": ["example.com"], "dry_run": True}
        r = self.c.post(
            "/api/v1/jobs",
            json={
                **base,
                "mode": "update",
                "new_content": "1.2.3.4",
                "account_workers": 99,
            },
        )
        self.assertEqual(r.status_code, 400)
        r = self.c.post(
            "/api/v1/jobs",
            json={**base, "mode": "update", "new_content": "1.2.3.4", "retry_base": -1},
        )
        self.assertEqual(r.status_code, 400)

    def test_job_rerun_and_anomalies_missing_job(self):
        self.assertEqual(self.c.post("/api/v1/jobs/no-such/rerun").status_code, 404)
        self.assertEqual(self.c.post("/api/v1/jobs/no-such/execute").status_code, 404)
        self.assertEqual(
            self.c.get("/api/v1/jobs/no-such/anomalies").status_code, 404
        )
        self.assertEqual(
            self.c.get("/api/v1/jobs/no-such/anomalies.csv").status_code, 404
        )

    def test_job_snapshot_scope(self):
        from webui.backend.jobs import Job

        job = Job(
            id="job-test",
            label="preview",
            kind="preview",
            mode="update",
            account_names=["t1"],
            params={
                "mode": "update",
                "domains": ["example.com"],
                "whitelist": ["a.example", "b.example"],
            },
            dry_run=True,
        )
        snapshot = job.snapshot()
        self.assertTrue(snapshot["dry_run"])
        self.assertEqual(snapshot["scope"]["domains"], ["example.com"])
        self.assertEqual(snapshot["scope"]["whitelist_count"], 2)
        self.assertEqual(snapshot["anomaly_count"], 0)

    def test_rerun_job_reuses_params_and_overrides_dry_run(self):
        from unittest import mock

        from webui.backend.jobs import Job
        from webui.backend.services import jobs as svc

        class FakeManager:
            def __init__(self):
                self.call = None

            def submit(self, *args, **kwargs):
                self.call = (args, kwargs)
                return "job-new"

        manager = FakeManager()
        job = Job(
            id="job-old",
            label="preview",
            kind="preview",
            mode="update",
            account_names=["t1"],
            params={
                "mode": "update",
                "domains": ["example.com"],
                "new_content": "198.51.100.10",
            },
            speed={"workers": 2, "interval": 0.5, "max_retries": 5},
            dry_run=True,
            status="done",
        )
        with mock.patch.object(svc, "lookup_accounts", return_value=[{"name": "t1"}]):
            with mock.patch.object(svc.deps, "get_manager", return_value=manager):
                with mock.patch.object(svc.deps, "get_proxy_pool", return_value=None):
                    new_id = svc.rerun_job(job, failed_only=False, dry_run=False)
        self.assertEqual(new_id, "job-new")
        args, kwargs = manager.call
        self.assertEqual(args[1], "execute")
        self.assertFalse(kwargs["dry_run"])
        self.assertEqual(kwargs["params"]["domains"], ["example.com"])
        self.assertEqual(kwargs["params"]["new_content"], "198.51.100.10")

    def test_rerun_failed_only_keeps_failed_scope(self):
        from unittest import mock

        from webui.backend.jobs import Job
        from webui.backend.services import jobs as svc

        class FakeManager:
            def __init__(self):
                self.call = None

            def submit(self, *args, **kwargs):
                self.call = (args, kwargs)
                return "job-rerun"

        manager = FakeManager()
        job = Job(
            id="job-failed",
            label="execute",
            kind="execute",
            mode="update",
            account_names=["t1", "t2"],
            params={"mode": "update", "domains": ["all.example"]},
            speed={"workers": 2, "interval": 0.5, "max_retries": 5},
            dry_run=False,
            status="failed",
            failure_rows=[
                {"account": "t2", "zone": "failed.example", "status": "error"},
            ],
        )
        with mock.patch.object(
            svc, "lookup_accounts", return_value=[{"name": "t2"}]
        ) as lookup:
            with mock.patch.object(svc.deps, "get_manager", return_value=manager):
                with mock.patch.object(svc.deps, "get_proxy_pool", return_value=None):
                    new_id = svc.rerun_job(job, failed_only=True)
        self.assertEqual(new_id, "job-rerun")
        lookup.assert_called_once_with(["t2"])
        _args, kwargs = manager.call
        self.assertEqual(kwargs["params"]["domains"], ["failed.example"])
        self.assertFalse(kwargs["dry_run"])

    def test_job_exports_empty_404(self):
        body = {
            "accounts": ["t1"],
            "domains": ["example.com"],
            "dry_run": True,
            "mode": "update",
            "new_content": "1.2.3.4",
        }
        job = self.c.post("/api/v1/jobs", json=body).json()["job_id"]
        self.assertEqual(self.c.get(f"/api/v1/jobs/{job}/exports").json()["total"], 0)
        self.assertEqual(self.c.get(f"/api/v1/jobs/{job}/exports/0").status_code, 404)


if __name__ == "__main__":
    unittest.main()
