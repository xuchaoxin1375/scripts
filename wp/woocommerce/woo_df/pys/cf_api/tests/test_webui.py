"""Web UI 回归测试（标准库 unittest，页面启动冒烟见 web_smoke.ps1）。

覆盖：适配层错误转换、脱敏、任务执行（dry-run，桩 updater）、失败清单 CSV、
对外监听无口令拒绝启动、新静态前端（meta/日志/静态资源）。
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui import engine_adapter, jobs  # noqa: E402


def _account():
    return {
        "name": "acct-test",
        "auth_method": "token",
        "token": "secret-token",
        "email": None,
        "key": None,
    }


class FakeStats:
    errors = 0
    cancelled = 0


class FakeBatchResult:
    def __init__(self, results):
        self.results = results
        self.stats = FakeStats()


class FakeUpdater:
    def __init__(self, engine):
        self._engine = engine
        self.calls = []

    def batch_update(self, **kwargs):
        self.calls.append(kwargs)
        return FakeBatchResult(
            [
                self._engine.DNSOperationResult(
                    zone="example.com",
                    name="www",
                    record_type="A",
                    old_content="1.1.1.1",
                    new_content="2.2.2.2",
                    status="dry_run_update",
                    account="acct-test",
                )
            ]
        )


class AdapterTest(unittest.TestCase):
    def test_missing_config_raises_not_exit(self):
        with self.assertRaises(engine_adapter.EngineError):
            engine_adapter.get_accounts("不存在的路径.json")

    def test_secrets_masked(self):
        rows = engine_adapter.masked_accounts([_account()])
        self.assertEqual(rows[0]["name"], "acct-test")
        self.assertNotIn("secret-token", rows[0]["secret"])
        self.assertTrue(rows[0]["secret"])


class JobRunTest(unittest.TestCase):
    def test_preview_job_collects_results(self):
        engine = engine_adapter.engine()
        fake = FakeUpdater(engine)
        original = engine_adapter.build_updater
        engine_adapter.build_updater = lambda *a, **k: fake
        try:
            manager = jobs.JobManager(max_workers=1)
            job_id = manager.submit(
                "preview",
                "preview",
                jobs.run_operation_job,
                ["acct-test"],
                accounts=[_account()],
                params={"mode": "update", "new_content": "2.2.2.2"},
                speed={
                    "workers": 1,
                    "interval": 0,
                    "scope": "account",
                    "max_retries": 0,
                },
                dry_run=True,
            )
            job = manager.get(job_id)
            self.assertIsNotNone(job)
            assert job is not None
            self.assertTrue(jobs.wait_until(job, timeout=30))
            self.assertIn(job.status, {"done", "failed"})
            self.assertTrue(fake.calls)
            self.assertEqual(len(job.results), 1)
            self.assertEqual(job.results[0]["status"], "dry_run_update")
            self.assertEqual(job.exit_code, 0)
        finally:
            engine_adapter.build_updater = original

    def test_failures_csv_header(self):
        manager = jobs.JobManager(max_workers=1)
        job_id = manager.submit("x", "preview", lambda job: None, [])
        job = manager.get(job_id)
        assert job is not None
        job.failure_rows = [
            {
                "account": "a",
                "zone": "z",
                "record_id": "",
                "name": "n",
                "type": "A",
                "old_content": "1",
                "new_content": "2",
                "action": "update",
                "status": "error",
                "attempts": 1,
                "error": "boom",
                "timestamp": "t",
            }
        ]
        text = jobs.failures_csv_text(job)
        self.assertTrue(text.startswith("account,zone,record_id"))
        self.assertIn("boom", text)


class SecurityTest(unittest.TestCase):
    def test_non_loopback_without_password_refused(self):
        from webui.server import create_app

        with self.assertRaises(SystemExit):
            create_app(host="0.0.0.0", port=18099, password="")

    def test_compat_shim_still_exports_create_app(self):
        from webui import app

        self.assertTrue(callable(app.create_app))


class FrontendServerTest(unittest.TestCase):
    def _client(self, password="pw"):
        from fastapi.testclient import TestClient

        from webui.server import ServerState, build_fastapi

        state = ServerState(
            config_path="cfg-preset",
            preset_path="cfg-preset",
            password=password,
        )
        return TestClient(build_fastapi(state)), state

    def test_static_files_exist(self):
        import os

        base = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "webui",
            "static",
        )
        for name in ("index.html", "app.js", "styles.css"):
            path = os.path.join(base, name)
            self.assertTrue(os.path.exists(path), f"缺失前端文件: {name}")
            self.assertGreater(os.path.getsize(path), 500)

    def test_index_and_meta(self):
        client, _ = self._client()
        resp = client.get("/")
        self.assertEqual(resp.status_code, 200)
        self.assertIn("Cloudflare DNS", resp.text)
        meta = client.get("/api/meta").json()
        self.assertEqual(meta["config_path"], "cfg-preset")
        self.assertIn("eco", meta["speeds"])
        self.assertIn("backup_dir", meta["defaults"])

    def test_meta_auth_gate(self):
        client, _ = self._client(password="pw")
        resp = client.get("/api/jobs")
        self.assertEqual(resp.status_code, 401)

    def test_job_logs_incremental(self):
        from fastapi.testclient import TestClient

        from webui import jobs
        from webui.server import ServerState, build_fastapi

        manager = jobs.JobManager(max_workers=1)
        job_id = manager.submit("x", "preview", lambda job: None, [])
        job = manager.get(job_id)
        assert job is not None
        job.append_log("line-1")
        job.append_log("line-2")
        state = ServerState(config_path="cfg", preset_path="cfg", password="")
        state.manager = manager
        client = TestClient(build_fastapi(state))
        full = client.get(f"/api/jobs/{job_id}/logs").json()
        self.assertEqual(full["total"], 2)
        part = client.get(f"/api/jobs/{job_id}/logs?offset=1").json()
        self.assertEqual(part["logs"], ["line-2"])


class RestApiTest(unittest.TestCase):
    def _server(self, password="pw"):
        from fastapi import FastAPI
        from fastapi.testclient import TestClient

        from webui import rest

        manager = jobs.JobManager(max_workers=1)
        deps = rest.Deps(
            get_config_path=lambda: "cfg",
            get_accounts=lambda: [
                {
                    "name": "acct-test",
                    "auth_method": "token",
                    "token": "secret-token",
                    "email": None,
                    "key": None,
                }
            ],
            get_manager=lambda: manager,
            get_password=lambda: password,
            get_proxy_pool=lambda: None,
        )
        server = FastAPI()
        server.include_router(rest.build_router(deps))
        return TestClient(server), manager

    def test_auth_required(self):
        client, _ = self._server(password="pw")
        resp = client.get("/api/jobs")
        self.assertEqual(resp.status_code, 401)
        resp = client.get("/api/jobs", headers={"X-Auth-Token": "pw"})
        self.assertEqual(resp.status_code, 200)

    def test_accounts_masked(self):
        client, _ = self._server()
        resp = client.get("/api/accounts", headers={"X-Auth-Token": "pw"})
        self.assertEqual(resp.status_code, 200)
        rows = resp.json()["accounts"]
        self.assertEqual(rows[0]["name"], "acct-test")
        self.assertNotIn("secret-token", rows[0]["secret"])

    def test_submit_validation(self):
        client, _ = self._server()
        resp = client.post(
            "/api/jobs",
            json={"mode": "update", "accounts": ["acct-test"], "dry_run": True},
            headers={"X-Auth-Token": "pw"},
        )
        self.assertEqual(resp.status_code, 400)
        self.assertIn("新内容", resp.json()["detail"])

    def test_submit_unknown_account(self):
        client, _ = self._server()
        resp = client.post(
            "/api/jobs",
            json={
                "mode": "export",
                "accounts": ["nope"],
                "dry_run": True,
            },
            headers={"X-Auth-Token": "pw"},
        )
        self.assertEqual(resp.status_code, 400)

    def test_job_lifecycle(self):
        import time

        client, manager = self._server()

        def _instant(job, **kwargs):
            job.exit_code = 0
            job.verdict_lines = ["[VERDICT] 完美执行。"]

        original = jobs.run_operation_job
        jobs.run_operation_job = _instant
        try:
            resp = client.post(
                "/api/jobs",
                json={"mode": "export", "accounts": ["acct-test"], "dry_run": True},
                headers={"X-Auth-Token": "pw"},
            )
            self.assertEqual(resp.status_code, 200)
            job_id = resp.json()["job_id"]
            deadline = time.monotonic() + 10
            status = ""
            while time.monotonic() < deadline:
                detail = client.get(
                    f"/api/jobs/{job_id}", headers={"X-Auth-Token": "pw"}
                ).json()
                status = detail["status"]
                if status in {"done", "failed", "cancelled"}:
                    break
                time.sleep(0.05)
            self.assertEqual(status, "done")
            zones = client.get(
                f"/api/jobs/{job_id}/zones",
                params={"account": "acct-test"},
                headers={"X-Auth-Token": "pw"},
            )
            self.assertEqual(zones.status_code, 200)
        finally:
            jobs.run_operation_job = original


if __name__ == "__main__":
    unittest.main()
