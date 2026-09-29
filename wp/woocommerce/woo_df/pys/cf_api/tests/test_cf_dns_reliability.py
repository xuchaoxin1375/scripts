"""cloudflare_dns_tool 可靠性回归测试（标准库 unittest，无第三方依赖）。

覆盖本次改造的核心防丢点：
- 520/限流载荷重试，403 不重试；
- 全量替换同名多记录逐 id 处理；
- 内容归一化比对；
- 失败清单 CSV 写读与重跑过滤（含整账号哨兵与空集合语义）；
- fan-out 对账（expected == completed + cancelled）；
- 最终 verdict（完美/未完美/中断与重跑提示）。
"""

import importlib.util
import os
import sys
import tempfile
import unittest
from concurrent.futures import Future
from threading import Event, Lock

TOOL_PATH = os.path.join(os.path.dirname(__file__), "..", "cloudflare_dns_tool.py")


def load_tool():
    spec = importlib.util.spec_from_file_location("cf_dns_tool", TOOL_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["cf_dns_tool"] = module
    spec.loader.exec_module(module)
    return module


tool = load_tool()


class FakeResponse:
    def __init__(self, status=200, payload=None, headers=None, text=""):
        self.status_code = status
        self.headers = headers or {}
        self._payload = payload
        self.text = text or ""
        self.ok = 200 <= status < 300

    def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload


class FakeSession:
    def __init__(self, responses):
        self._responses = list(responses)
        self.calls = 0
        self.last_kwargs: dict = {}

    def request(self, method, url, timeout=30, **kwargs):
        self.calls += 1
        self.last_kwargs = kwargs
        resp = self._responses[min(self.calls - 1, len(self._responses) - 1)]
        if isinstance(resp, Exception):
            raise resp
        return resp


def make_updater(**kwargs):
    defaults = {
        "auth_method": "token",
        "api_token": "test",
        "max_workers": 1,
        "print_lock": Lock(),
        "stop_event": Event(),
        "account_name": "acct-test",
        "rate_limiter": None,
        "api_max_retries": 3,
        "api_retry_base_delay": 0.01,
        "api_retry_max_sleep": 0.05,
    }
    defaults.update(kwargs)
    updater = tool.CloudflareDNSUpdater(**defaults)
    updater._safe_print = lambda *a, **k: None
    return updater


def ok_payload():
    return {"success": True, "result": {"id": "x"}, "errors": []}


class RequestRetryTest(unittest.TestCase):
    def test_retries_cloudflare_520_then_succeeds(self):
        updater = make_updater()
        session = FakeSession(
            [
                FakeResponse(520, text="origin error"),
                FakeResponse(522, text="origin error"),
                FakeResponse(200, ok_payload()),
            ]
        )
        updater._get_session = lambda: session
        data = updater._request("GET", "/zones")
        self.assertTrue(data["success"])
        self.assertEqual(session.calls, 3)

    def test_retries_success_false_rate_limit_payload(self):
        updater = make_updater()
        session = FakeSession(
            [
                FakeResponse(
                    200,
                    {
                        "success": False,
                        "errors": [{"code": 8000000, "message": "Rate limit"}],
                    },
                ),
                FakeResponse(200, ok_payload()),
            ]
        )
        updater._get_session = lambda: session
        data = updater._request("GET", "/zones")
        self.assertTrue(data["success"])
        self.assertEqual(session.calls, 2)

    def test_no_retry_on_forbidden(self):
        updater = make_updater()
        session = FakeSession(
            [
                FakeResponse(
                    403,
                    {
                        "success": False,
                        "errors": [{"code": 9109, "message": "forbidden"}],
                    },
                )
            ]
        )
        updater._get_session = lambda: session
        with self.assertRaises(Exception):
            updater._request("GET", "/zones")
        self.assertEqual(session.calls, 1)


class FullReplaceTest(unittest.TestCase):
    def test_same_name_multi_records_all_processed(self):
        updater = make_updater()
        zone = {"name": "example.com", "id": "z1"}
        opposite = [
            {
                "id": "a1",
                "name": "example.com",
                "content": "1.1.1.1",
                "type": "A",
                "proxied": False,
                "ttl": 1,
            },
            {
                "id": "a2",
                "name": "example.com",
                "content": "1.1.1.2",
                "type": "A",
                "proxied": False,
                "ttl": 1,
            },
        ]
        updater.get_dns_records = lambda zid, rtype=None: (
            [] if rtype == "AAAA" else list(opposite)
        )
        created, deleted = [], []
        updater.create_dns_record = lambda **kw: created.append(kw) or {}
        updater.delete_dns_record = lambda zid, rid: deleted.append(rid) or {}
        stats = tool.OperationStats()
        results = updater._process_zone_full_replace(
            zone, 1, 1, 1, "2001:db8::1", "AAAA", "A", False, True, False, stats
        )
        # 同名两条旧 A：创建一次 AAAA，逐 id 删除两次。
        self.assertEqual(len(created), 1)
        self.assertEqual(sorted(deleted), ["a1", "a2"])
        self.assertEqual(stats.created, 1)
        self.assertEqual(stats.deleted, 2)
        self.assertTrue(any(r.status == "deleted_old_full_migrate" for r in results))


class NormalizeTest(unittest.TestCase):
    def test_contents_equal(self):
        self.assertTrue(tool.contents_equal("2001:0db8::1", "2001:db8::1"))
        self.assertTrue(tool.contents_equal("Old.Example.COM.", "old.example.com"))
        self.assertFalse(tool.contents_equal("1.1.1.1", "2.2.2.2"))

    def test_parse_add_record_ipv6(self):
        self.assertEqual(
            tool.parse_add_record_spec("www:AAAA:2001:db8::1"),
            ("www", "AAAA", "2001:db8::1"),
        )
        self.assertEqual(
            tool.parse_add_record_spec("www-AAAA-2001:db8::1"),
            ("www", "AAAA", "2001:db8::1"),
        )
        self.assertEqual(
            tool.parse_add_record_spec("www A 1.2.3.4"),
            ("www", "A", "1.2.3.4"),
        )


class FailureCsvTest(unittest.TestCase):
    def test_rows_and_resume_roundtrip(self):
        results = [
            tool.DNSOperationResult(
                zone="example.com",
                name="www",
                record_type="A",
                old_content="1.1.1.1",
                new_content="2.2.2.2",
                status="error",
                message="boom",
            ),
            tool.DNSOperationResult(
                zone="example.com",
                name="www",
                record_type="A",
                old_content="1.1.1.1",
                new_content="2.2.2.2",
                status="updated",
            ),
            tool.DNSOperationResult(
                zone="other.com",
                name="",
                record_type="ZONE",
                old_content=None,
                new_content=None,
                status="cancelled",
                message="stop",
            ),
        ]
        rows = tool.failure_rows_for_results("acct-a", results)
        self.assertEqual(len(rows), 2)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "中文失败.csv")
            tool.write_failure_csv(path, rows)
            with open(path, "rb") as fh:
                self.assertTrue(fh.read(3) == b"\xef\xbb\xbf")
            entries = tool.load_resume_entries(path)
            self.assertIn(("acct-a", "example.com"), entries)
            zones = tool.resume_zones_for_account(entries, "acct-a")
            self.assertEqual(zones, {"example.com", "other.com"})
            self.assertEqual(
                tool.resume_zones_for_account(entries, "other-acct"), set()
            )


class DrainReconcileTest(unittest.TestCase):
    def test_expected_equals_completed_plus_cancelled(self):
        updater = make_updater()
        done_future: Future = Future()
        done_future.set_result([])
        pending_future: Future = Future()
        future_to_zone = {
            done_future: {"name": "a.com"},
            pending_future: {"name": "b.com"},
        }
        updater._stop_event.set()
        stats = tool.OperationStats()
        results: list = []
        completed, cancelled = updater._drain_zone_futures(
            future_to_zone, stats, results, action="单测"
        )
        self.assertEqual(completed + cancelled, 2)
        self.assertEqual(cancelled, 1)
        self.assertTrue(any(r.status == "cancelled" for r in results))


class ResumeFilterTest(unittest.TestCase):
    def test_no_file_means_no_filter(self):
        self.assertIsNone(tool.resume_filter_for_account(None, "acct-a"))

    def test_whole_account_sentinel_means_no_filter(self):
        entries = [("acct-a", ""), ("acct-a", "z.com")]
        self.assertIsNone(tool.resume_filter_for_account(entries, "acct-a"))
        # 空 account 哨兵适用于所有账号。
        self.assertIsNone(tool.resume_filter_for_account([("", "")], "any-acct"))

    def test_unrelated_account_gets_empty_set(self):
        entries = [("acct-a", "z.com")]
        self.assertEqual(tool.resume_filter_for_account(entries, "other-acct"), set())
        self.assertEqual(tool.resume_filter_for_account(entries, "acct-a"), {"z.com"})

    def test_apply_filter_none_vs_empty(self):
        updater = make_updater()
        zones = [{"name": "a.com"}, {"name": "b.com"}]
        self.assertEqual(len(updater._apply_resume_filter(zones, None)), 2)
        self.assertEqual(updater._apply_resume_filter(zones, set()), [])


class VerdictTest(unittest.TestCase):
    def test_perfect_run(self):
        code, lines = tool.build_final_verdict(2, 0, 0, [], False, None, "prog")
        self.assertEqual(code, 0)
        self.assertTrue(any("完美执行" in line for line in lines))

    def test_failed_run_reports_causes_and_rerun(self):
        rows = [
            {"status": "error", "action": "batch", "error": "HTTP 429 boom"},
            {"status": "cancelled", "action": "batch", "error": "stop"},
        ]
        code, lines = tool.build_final_verdict(1, 1, 0, rows, False, "f.csv", "prog")
        self.assertEqual(code, 1)
        text = "\n".join(lines)
        self.assertIn("未完美执行", text)
        self.assertIn("--resume-from f.csv", text)
        self.assertIn("Top", text)

    def test_interrupted_exit_code(self):
        code, lines = tool.build_final_verdict(1, 0, 1, [], True, None, "prog")
        self.assertEqual(code, 130)
        self.assertTrue(any("中断" in line for line in lines))


class SpeedPresetTest(unittest.TestCase):
    def test_eco_defaults(self):
        self.assertEqual(
            tool.resolve_speed_values("eco", None, None, None), (2, 3, 0.5)
        )

    def test_each_preset_fills_blanks(self):
        self.assertEqual(
            tool.resolve_speed_values("balanced", None, None, None), (4, 5, 0.2)
        )
        self.assertEqual(
            tool.resolve_speed_values("fast", None, None, None), (6, 8, 0.1)
        )
        self.assertEqual(
            tool.resolve_speed_values("turbo", None, None, None), (20, 20, 0.0)
        )

    def test_explicit_values_win(self):
        self.assertEqual(tool.resolve_speed_values("eco", 10, 7, 0.1), (10, 7, 0.1))

    def test_configure_applies_preset_and_clamps(self):
        from types import SimpleNamespace

        args = SimpleNamespace(
            speed="balanced",
            conservative=False,
            workers=None,
            account_workers=None,
            request_interval=None,
            api_max_retries=5,
            api_retry_base_delay=2.0,
            api_retry_max_sleep=300.0,
        )
        tool.configure_rate_limit_args(args)
        self.assertEqual((args.workers, args.account_workers), (4, 5))
        self.assertAlmostEqual(args.request_interval, 0.2)

    def test_conservative_forces_eco(self):
        from types import SimpleNamespace

        args = SimpleNamespace(
            speed="fast",
            conservative=True,
            workers=None,
            account_workers=None,
            request_interval=None,
            api_max_retries=5,
            api_retry_base_delay=2.0,
            api_retry_max_sleep=300.0,
        )
        tool.configure_rate_limit_args(args)
        self.assertEqual(args.speed, "eco")
        self.assertEqual((args.workers, args.account_workers), (2, 3))

    def test_invalid_explicit_exits(self):
        from types import SimpleNamespace

        args = SimpleNamespace(
            speed="eco",
            conservative=False,
            workers=0,
            account_workers=None,
            request_interval=None,
            api_max_retries=5,
            api_retry_base_delay=2.0,
            api_retry_max_sleep=300.0,
        )
        with self.assertRaises(SystemExit):
            tool.configure_rate_limit_args(args)


class ProxyPoolTest(unittest.TestCase):
    URLS = ["http://127.0.0.1:7897", "http://127.0.0.1:7898"]

    def test_round_robin_cycles(self):
        pool = tool.ProxyPool(self.URLS, mode="round-robin")
        seen = [pool.next_proxy() for _ in range(4)]
        self.assertEqual(seen, self.URLS * 2)

    def test_failover_switches_on_failure_and_recovers(self):
        pool = tool.ProxyPool(self.URLS, mode="failover")
        self.assertEqual(pool.next_proxy(), self.URLS[0])
        pool.report_failure(self.URLS[0])
        self.assertEqual(pool.next_proxy(), self.URLS[1])
        # 恢复后仍保持当前健康项，直到它再次故障才切回。
        pool.report_success(self.URLS[0])
        self.assertEqual(pool.next_proxy(), self.URLS[1])
        pool.report_failure(self.URLS[1])
        self.assertEqual(pool.next_proxy(), self.URLS[0])

    def test_unhealthy_proxy_skipped_then_cooled_down(self):
        import time

        pool = tool.ProxyPool(self.URLS, mode="round-robin", failure_cooldown=0.05)
        pool.report_failure(self.URLS[0])
        self.assertEqual(pool.next_proxy(), self.URLS[1])
        time.sleep(0.06)
        self.assertIn(pool.next_proxy(), self.URLS)

    def test_all_unhealthy_still_returns_one(self):
        pool = tool.ProxyPool(self.URLS, mode="round-robin")
        pool.report_failure(self.URLS[0])
        pool.report_failure(self.URLS[1])
        self.assertIn(pool.next_proxy(), self.URLS)

    def test_sticky_consistent_within_thread(self):
        pool = tool.ProxyPool(self.URLS, mode="sticky")
        first = pool.next_proxy()
        for _ in range(5):
            self.assertEqual(pool.next_proxy(), first)

    def test_sanitize_and_validate(self):
        self.assertEqual(
            tool.sanitize_proxy_url("http://user:pass@127.0.0.1:7897"),
            "http://127.0.0.1:7897",
        )
        self.assertEqual(
            tool.validate_proxy_url("http://127.0.0.1:7897"),
            "http://127.0.0.1:7897",
        )
        with self.assertRaises(ValueError):
            tool.validate_proxy_url("ftp://127.0.0.1:21")
        with self.assertRaises(ValueError):
            tool.validate_proxy_url("not-a-url")

    def test_request_sends_proxies_and_reports(self):
        pool = tool.ProxyPool(self.URLS, mode="round-robin")
        updater = make_updater(proxy_pool=pool)
        session = FakeSession([FakeResponse(200, ok_payload())])
        updater._get_session = lambda: session
        updater._request("GET", "/zones")
        proxies = session.last_kwargs.get("proxies")
        self.assertEqual(proxies, {"http": self.URLS[0], "https": self.URLS[0]})

    def test_request_failure_marks_proxy_bad(self):
        import requests

        pool = tool.ProxyPool(self.URLS, mode="failover", failure_cooldown=60.0)
        updater = make_updater(proxy_pool=pool)
        session = FakeSession(
            [requests.ConnectionError("down"), FakeResponse(200, ok_payload())]
        )
        updater._get_session = lambda: session
        updater._request("GET", "/zones")
        # failover：第一次失败后切换到第二个代理并成功。
        self.assertEqual(
            session.last_kwargs.get("proxies"),
            {"http": self.URLS[1], "https": self.URLS[1]},
        )
        self.assertEqual(session.calls, 2)

    def test_build_proxy_pool(self):
        from types import SimpleNamespace

        args = SimpleNamespace(
            proxy=["http://127.0.0.1:7897"], proxy_file=None, proxy_mode="round-robin"
        )
        pool = tool.build_proxy_pool(args)
        self.assertIsNotNone(pool)
        assert pool is not None
        self.assertEqual(pool.urls, ["http://127.0.0.1:7897"])
        empty = SimpleNamespace(proxy=None, proxy_file=None, proxy_mode="round-robin")
        self.assertIsNone(tool.build_proxy_pool(empty))


class BackupExportTest(unittest.TestCase):
    ZONE = {"name": "example.com", "id": "z1"}
    RECORDS = [
        {
            "id": "r1",
            "type": "A",
            "name": "example.com",
            "content": "1.2.3.4",
            "ttl": 1,
            "proxied": False,
        },
        {
            "id": "r2",
            "type": "AAAA",
            "name": "www.example.com",
            "content": "2001:db8::1",
            "ttl": 300,
            "proxied": True,
        },
    ]

    def test_serialize_structure(self):
        payload = tool.serialize_zone_backup("acct-a", self.ZONE, self.RECORDS)
        self.assertEqual(payload["account"], "acct-a")
        self.assertEqual(payload["zone"], "example.com")
        self.assertEqual(payload["record_count"], 2)
        self.assertEqual(payload["records"][0]["content"], "1.2.3.4")

    def test_bind_format(self):
        text = tool.format_bind_zone("example.com", self.RECORDS)
        self.assertIn("$ORIGIN example.com.", text)
        self.assertIn("@\t1\tIN\tA\t1.2.3.4", text)
        self.assertIn("proxied=yes", text)

    def test_write_roundtrip(self):
        import json

        with tempfile.TemporaryDirectory() as tmp:
            payload = tool.serialize_zone_backup("acct-a", self.ZONE, self.RECORDS)
            json_path = tool.write_zone_backup_file(
                tmp, "acct-a", "example.com", payload, "json"
            )
            with open(json_path, encoding="utf-8") as fh:
                loaded = json.load(fh)
            self.assertEqual(loaded["record_count"], 2)
            bind_path = tool.write_zone_backup_file(
                tmp, "acct-a", "example.com", payload, "bind"
            )
            with open(bind_path, encoding="utf-8") as fh:
                self.assertIn("$ORIGIN", fh.read())

    def test_backup_aborts_on_fetch_failure(self):
        updater = make_updater()
        updater.get_all_zones = lambda: [dict(self.ZONE)]
        updater.get_dns_records = lambda zid, rtype=None: (_ for _ in ()).throw(
            Exception("boom")
        )
        with tempfile.TemporaryDirectory() as tmp:
            ok, msg = updater.batch_backup(tmp)
            self.assertFalse(ok)
            self.assertIn("中止", msg)


class SetAttrsTest(unittest.TestCase):
    def test_proxied_flip_and_skip(self):
        updater = make_updater()
        zone = {"name": "example.com", "id": "z1"}
        records = [
            {
                "id": "r1",
                "type": "A",
                "name": "example.com",
                "content": "1.2.3.4",
                "ttl": 1,
                "proxied": False,
            },
            {
                "id": "r2",
                "type": "A",
                "name": "www.example.com",
                "content": "1.2.3.4",
                "ttl": 1,
                "proxied": True,
            },
        ]
        updater.get_dns_records = lambda zid, rtype=None: list(records)
        updated = []
        updater.update_dns_record = lambda **kw: updated.append(kw) or {}
        stats = tool.OperationStats()
        results = updater._process_zone_set_attrs(
            zone, 1, 1, 1, ["A"], True, None, None, False, True, False, stats
        )
        self.assertEqual(len(updated), 1)
        self.assertEqual(updated[0]["record_id"], "r1")
        self.assertTrue(updated[0]["proxied"])
        self.assertEqual(stats.updated, 1)
        self.assertEqual(stats.skipped, 1)
        self.assertTrue(any(r.status == "updated_attrs" for r in results))

    def test_ttl_validation(self):
        updater = make_updater()
        with self.assertRaises(ValueError):
            updater.batch_set_attrs(set_ttl=0)
        with self.assertRaises(ValueError):
            updater.batch_set_attrs()


class ProgressCallbackTest(unittest.TestCase):
    def test_drain_reports_done_and_error(self):
        from concurrent.futures import Future

        updater = make_updater()
        seen = []
        updater.progress_cb = lambda zone, state: seen.append((zone, state))
        ok_future: Future = Future()
        ok_future.set_result([])
        bad_future: Future = Future()
        bad_future.set_exception(RuntimeError("boom"))
        stats = tool.OperationStats()
        results: list = []
        completed, cancelled = updater._drain_zone_futures(
            {ok_future: {"name": "a.com"}, bad_future: {"name": "b.com"}},
            stats,
            results,
            action="单测",
        )
        self.assertEqual((completed, cancelled), (2, 0))
        self.assertIn(("a.com", "done"), seen)
        self.assertIn(("b.com", "error"), seen)

    def test_no_callback_by_default(self):
        from concurrent.futures import Future

        updater = make_updater()
        self.assertIsNone(updater.progress_cb)
        done_future: Future = Future()
        done_future.set_result([])
        stats = tool.OperationStats()
        completed, _ = updater._drain_zone_futures(
            {done_future: {"name": "a.com"}}, stats, [], action="单测"
        )
        self.assertEqual(completed, 1)

    def test_callback_exception_does_not_break_engine(self):
        from concurrent.futures import Future

        updater = make_updater()

        def _bad(zone, state):
            raise RuntimeError("cb boom")

        updater.progress_cb = _bad
        done_future: Future = Future()
        done_future.set_result([])
        stats = tool.OperationStats()
        completed, _ = updater._drain_zone_futures(
            {done_future: {"name": "a.com"}}, stats, [], action="单测"
        )
        self.assertEqual(completed, 1)


if __name__ == "__main__":
    unittest.main()
