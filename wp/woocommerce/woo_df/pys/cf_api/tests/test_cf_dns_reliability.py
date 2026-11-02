"""cloudflare_dns_tool 可靠性回归测试（标准库 unittest，无第三方依赖）。

覆盖本次改造的核心防丢点：
- 520/限流载荷重试，403 不重试；
- 全量替换同名多记录逐 id 处理；
- 内容归一化比对；
- 失败清单 CSV 写读与重跑过滤（含整账号哨兵与空集合语义）；
- fan-out 对账（expected == completed + cancelled）；
- 最终 verdict（完美/未完美/中断与重跑提示）。
"""

import argparse
import importlib.util
import os
import sys
import tempfile
import unittest
from concurrent.futures import Future
from threading import Event, Lock
from unittest import mock

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


class FakeApiError(Exception):
    """测试用 API 错误（避免裸 Exception 触发 lint）。"""


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


class RequestAnomalyTest(unittest.TestCase):
    """请求异常历史：重试后成功也要留痕。"""

    def test_retry_then_success_records_resolved_anomaly(self):
        updater = make_updater()
        session = FakeSession(
            [
                FakeResponse(520, text="origin error"),
                FakeResponse(200, ok_payload()),
            ]
        )
        updater._get_session = lambda: session
        updater._request(
            "PUT", "/zones/" + "a" * 32 + "/dns_records/r1", json={"content": "x"}
        )
        rows = updater.request_anomalies()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["resolved"], "yes")
        self.assertEqual(rows[0]["attempts"], 2)
        self.assertEqual(rows[0]["zone_id"], "a" * 32)
        self.assertEqual(rows[0]["http_status"], "520")
        self.assertIn("520", rows[0]["error"])

    def test_zone_name_is_resolved_from_cache(self):
        updater = make_updater()
        zone_id = "b" * 32
        updater._zone_names[zone_id] = "example.com"
        session = FakeSession(
            [
                FakeResponse(429, headers={"retry-after": "0"}, text="rate"),
                FakeResponse(200, ok_payload()),
            ]
        )
        updater._get_session = lambda: session
        updater._request("GET", f"/zones/{zone_id}/dns_records")
        rows = updater.request_anomalies()
        self.assertEqual(rows[0]["zone"], "example.com")
        self.assertEqual(rows[0]["http_status"], "429")
        self.assertIn("限流", rows[0]["kind"])

    def test_final_failure_records_unresolved_anomaly(self):
        updater = make_updater(api_max_retries=0)
        session = FakeSession(
            [
                FakeResponse(
                    403,
                    {"success": False, "errors": [{"code": 9109, "message": "no"}]},
                )
            ]
        )
        updater._get_session = lambda: session
        with self.assertRaisesRegex(Exception, "403"):
            updater._request("GET", "/zones")
        rows = updater.request_anomalies()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["resolved"], "no")
        self.assertEqual(rows[0]["http_status"], "403")
        self.assertIn("请求被拒绝", rows[0]["kind"])

    def test_retry_summary_and_csv(self):
        rows = [
            {
                "account": "acct-a",
                "zone": "example.com",
                "zone_id": "z1",
                "method": "PUT",
                "endpoint": "/zones/z1/dns_records/r1",
                "kind": "触发 Cloudflare 限流",
                "http_status": "429",
                "attempts": 3,
                "resolved": "yes",
                "error": "HTTP 429",
                "timestamp": "2026-01-01T00:00:00Z",
            },
            {
                "account": "acct-b",
                "zone": "example.com",
                "zone_id": "z2",
                "method": "GET",
                "endpoint": "/zones/z2/dns_records",
                "kind": "服务端临时错误 520",
                "http_status": "520",
                "attempts": 2,
                "resolved": "no",
                "error": "HTTP 520",
                "timestamp": "2026-01-01T00:00:01Z",
            },
        ]
        lines = tool.retry_summary_lines(rows)
        text = "\n".join(lines)
        self.assertIn("异常请求 2 次", text)
        self.assertIn("已恢复 1，未恢复 1", text)
        self.assertIn("异常涉及账号 2 个、域名 1 个", text)
        self.assertIn("- 按错误码: HTTP 429 — 触发 Cloudflare 限流 1", text)
        self.assertIn("[1] HTTP 429 — 触发 Cloudflare 限流", text)
        self.assertIn("[2] HTTP 520 — 服务端临时错误 520", text)
        self.assertIn("账号", text)
        self.assertIn("异常请求", text)

        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "retry.csv")
            tool.write_retry_csv(path, rows)
            with open(path, encoding="utf-8-sig") as file_obj:
                content = file_obj.read()
        self.assertIn("account,zone,zone_id,method,endpoint", content)
        self.assertIn("http_status", content)
        self.assertIn("acct-a", content)
        self.assertIn("resolved", content)

    def test_same_code_groups_account_zone_and_truncates(self):
        rows = [
            {
                "account": f"acct-{index}",
                "zone": f"zone{index}.example.com",
                "zone_id": f"z{index}",
                "method": "PUT",
                "endpoint": f"/zones/z{index}/dns_records/r{index}",
                "kind": "触发 Cloudflare 限流",
                "http_status": "429",
                "attempts": 2,
                "resolved": "yes",
                "error": "HTTP 429",
                "timestamp": "2026-01-01T00:00:00Z",
            }
            for index in range(12)
        ]
        text = "\n".join(tool.retry_summary_lines(rows))
        self.assertIn("[1] HTTP 429 — 触发 Cloudflare 限流（12 次", text)
        # 每段最多 10 行，剩余 2 个组合提示导出。
        self.assertIn("另有 2 个账号/域名组合未显示", text)
        self.assertNotIn("acct-9", text)

    def test_scope_summary_reports_final_success_and_failure(self):
        scope = tool.RunScopeStats(
            accounts_total=2,
            accounts_ok=1,
            accounts_failed=1,
            zones_attempted=10,
            zones_succeeded=9,
            zones_failed=1,
        )
        text = "\n".join(tool.scope_summary_lines(scope))
        self.assertIn("尝试 2 个，成功 1 个，失败 1 个", text)
        self.assertIn("尝试 10 个", text)
        self.assertIn("最终成功 9 个（含重试后成功）", text)
        self.assertIn("最终失败 1 个", text)

    def test_summarize_zone_outcomes_uses_final_state(self):
        results = [
            tool.DNSOperationResult(
                zone="ok.example.com",
                name="a",
                record_type="A",
                old_content="1.1.1.1",
                new_content="2.2.2.2",
                status="updated",
            ),
            tool.DNSOperationResult(
                zone="bad.example.com",
                name="b",
                record_type="A",
                old_content="1.1.1.1",
                new_content="2.2.2.2",
                status="error",
            ),
            tool.DNSOperationResult(
                zone="skip.example.com",
                name="c",
                record_type="A",
                old_content="1.1.1.1",
                new_content="2.2.2.2",
                status="skipped",
            ),
        ]
        batch_result = tool.BatchRunResult(
            results=results,
            stats=tool.OperationStats(),
            expected_zones=3,
        )
        attempted, succeeded, failed, cancelled = tool.summarize_zone_outcomes(
            batch_result
        )
        self.assertEqual((attempted, succeeded, failed, cancelled), (3, 2, 1, 0))


class FanoutScopeTest(unittest.TestCase):
    """账号级 fan-out 汇总账号成功/失败与 zone 最终状态。"""

    def test_scope_aggregates_account_and_zone_outcomes(self):
        outcomes = {
            "ok": tool.AccountOutcome(
                name="ok",
                ok=True,
                error="",
                failure_rows=[],
                anomaly_rows=[],
                zones_attempted=2,
                zones_succeeded=2,
            ),
            "bad": tool.AccountOutcome(
                name="bad",
                ok=False,
                error="账号内存在 1 个错误、0 个取消",
                failure_rows=[{"account": "bad"}],
                anomaly_rows=[{"account": "bad", "http_status": "429"}],
                zones_attempted=2,
                zones_succeeded=1,
                zones_failed=1,
            ),
        }

        def fake_run(account, *_args, **_kwargs):
            return outcomes[account["name"]]

        with mock.patch.object(tool, "run_operation_for_account", fake_run):
            (
                success,
                failed,
                failure_rows,
                cancelled_accounts,
                anomaly_rows,
                scope,
            ) = tool.run_accounts_fanout(
                [{"name": "ok"}, {"name": "bad"}],
                argparse.Namespace(account_workers=2),
                None,
                Lock(),
                Event(),
                None,
            )

        self.assertEqual((success, failed, cancelled_accounts), (1, 1, 0))
        self.assertEqual(len(failure_rows), 1)
        self.assertEqual(len(anomaly_rows), 1)
        self.assertEqual(scope.accounts_total, 2)
        self.assertEqual(scope.accounts_ok, 1)
        self.assertEqual(scope.accounts_failed, 1)
        self.assertEqual(scope.zones_attempted, 4)
        self.assertEqual(scope.zones_succeeded, 3)
        self.assertEqual(scope.zones_failed, 1)


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


class FullReplaceDedupeTest(unittest.TestCase):
    """全量替换的同名收敛：每个主机名最终只保留一条记录。"""

    def _run(self, records, new_content="9.9.9.9", update=None, dry_run=False):
        updater = make_updater()
        zone = {"name": "example.com", "id": "z1"}
        updater.get_dns_records = lambda zid, rtype=None: (
            [] if rtype == "AAAA" else [dict(item) for item in records]
        )
        updated, deleted = [], []
        updater.update_dns_record = update or (
            lambda **kw: updated.append(kw) or {"success": True}
        )
        updater.delete_dns_record = lambda zid, rid: deleted.append(rid) or {}
        stats = tool.OperationStats()
        results = updater._process_zone_full_replace(
            zone, 1, 1, 1, new_content, "A", None, dry_run, True, False, stats
        )
        return stats, results, updated, deleted

    @staticmethod
    def _record(record_id, content, name="example.com"):
        return {
            "id": record_id,
            "name": name,
            "content": content,
            "type": "A",
            "proxied": False,
            "ttl": 1,
        }

    def test_same_name_duplicates_collapse_to_single_record(self):
        stats, results, updated, deleted = self._run(
            [self._record("a1", "1.1.1.1"), self._record("a2", "1.1.1.2")]
        )
        self.assertEqual([call["record_id"] for call in updated], ["a1"])
        self.assertEqual(deleted, ["a2"])
        self.assertEqual(stats.updated, 1)
        self.assertEqual(stats.deleted, 1)
        self.assertEqual(stats.errors, 0)
        self.assertTrue(any(r.status == "deleted_duplicate_full" for r in results))

    def test_existing_target_record_is_kept_and_others_removed(self):
        stats, _, updated, deleted = self._run(
            [self._record("a1", "9.9.9.9"), self._record("a2", "1.1.1.2")]
        )
        self.assertEqual(updated, [])
        self.assertEqual(deleted, ["a2"])
        self.assertEqual(stats.skipped, 1)
        self.assertEqual(stats.deleted, 1)
        self.assertEqual(stats.errors, 0)

    def test_identical_record_error_treated_as_converged(self):
        def raise_identical(**kwargs):
            raise FakeApiError(
                "HTTP 400, API 请求失败: [{'code': 81058, "
                "'message': 'An identical record already exists.'}]"
            )

        stats, results, _, deleted = self._run(
            [self._record("a1", "1.1.1.1"), self._record("a2", "1.1.1.2")],
            update=raise_identical,
        )
        # 撞 81058 说明目标内容已存在：记为跳过，但仍清理同名多余记录。
        self.assertEqual(stats.errors, 0)
        self.assertEqual(stats.skipped, 1)
        self.assertEqual(deleted, ["a2"])
        self.assertFalse(any(r.status == "error" for r in results))

    def test_update_failure_keeps_duplicates_for_manual_cleanup(self):
        def raise_forbidden(**kwargs):
            raise FakeApiError("HTTP 403, API 请求失败: [{'code': 9109}]")

        stats, results, _, deleted = self._run(
            [self._record("a1", "1.1.1.1"), self._record("a2", "1.1.1.2")],
            update=raise_forbidden,
        )
        self.assertEqual(deleted, [])
        self.assertEqual(stats.errors, 1)
        error = next(r for r in results if r.status == "error")
        self.assertEqual(error.action, "full_replace")
        self.assertIn("保留现场", error.message)

    def test_dry_run_previews_update_and_dedupe(self):
        stats, results, updated, deleted = self._run(
            [self._record("a1", "1.1.1.1"), self._record("a2", "1.1.1.2")],
            dry_run=True,
        )
        self.assertEqual(updated, [])
        self.assertEqual(deleted, [])
        self.assertEqual(stats.dry_run, 2)
        self.assertTrue(any(r.status == "dry_run_full_dedupe" for r in results))


class UpdateMergeTest(unittest.TestCase):
    """指定 --old-ip 时撞 81058：删除旧记录完成收敛，而不是记失败。"""

    def test_identical_target_removes_old_record(self):
        updater = make_updater()
        zone = {"name": "example.com", "id": "z1"}
        records = [
            {
                "id": "a1",
                "name": "example.com",
                "content": "1.1.1.1",
                "type": "A",
                "proxied": False,
                "ttl": 1,
            }
        ]
        updater.get_dns_records = lambda zid, rtype=None: [dict(r) for r in records]

        def raise_identical(**kwargs):
            raise FakeApiError(
                "HTTP 400, API 请求失败: [{'code': 81058, "
                "'message': 'An identical record already exists.'}]"
            )

        deleted = []
        updater.update_dns_record = raise_identical
        updater.delete_dns_record = lambda zid, rid: deleted.append(rid) or {}
        stats = tool.OperationStats()
        results = updater._process_zone_update(
            zone, 1, 1, 1, "9.9.9.9", "1.1.1.1", "A", False, True, False, stats
        )
        self.assertEqual(deleted, ["a1"])
        self.assertEqual(stats.errors, 0)
        self.assertEqual(stats.deleted, 1)
        self.assertTrue(any(r.status == "merged_duplicate" for r in results))


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

    def test_deterministic_failure_does_not_suggest_resume(self):
        rows = [
            {
                "status": "error",
                "action": "full_replace",
                "error": "HTTP 400, API 请求失败: [{'code': 81058, "
                "'message': 'An identical record already exists.'}]",
                "account": "acct-a",
                "zone": "example.com",
                "type": "A",
                "name": "www.example.com",
            }
        ]
        code, lines = tool.build_final_verdict(1, 1, 0, rows, False, "f.csv", "prog")
        text = "\n".join(lines)
        self.assertEqual(code, 1)
        self.assertIn("重跑无效", text)
        self.assertIn("确定性错误", text)
        self.assertIn("example.com", text)
        self.assertNotIn("--resume-from f.csv", text)

    def test_mixed_failures_warn_about_deterministic_rows(self):
        rows = [
            {"status": "error", "action": "full_replace", "error": "HTTP 429 boom"},
            {"status": "error", "action": "full_replace", "error": "HTTP 403 denied"},
        ]
        code, lines = tool.build_final_verdict(1, 1, 0, rows, False, "f.csv", "prog")
        text = "\n".join(lines)
        self.assertEqual(code, 1)
        self.assertIn("--resume-from f.csv", text)
        self.assertIn("另有 1 条为确定性错误", text)


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
