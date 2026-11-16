# -*- coding: utf-8 -*-
"""结构化任务日志解析：常见引擎前缀、参数合并与噪声过滤。"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui.backend.jobs import Job  # noqa: E402
from webui.backend.log_events import parse_log_entries  # noqa: E402


def entry(text: str, ts: str = "2026-11-16T10:00:00+00:00") -> dict:
    return {"ts": ts, "text": text}


class LogEventsTest(unittest.TestCase):
    def test_banner_params_and_dry_run_grouping(self):
        entries = [
            entry("=" * 70),
            entry("Cloudflare DNS 添加域名/记录 | 账号: acct-demo"),
            entry(
                "add_domain=None, target_zone=example.com, records=1, "
                "proxied=True, ttl=1, dry_run=True"
            ),
            entry("=" * 70),
            entry("账号 acct-demo 下共 5 个域名"),
            entry("[命令行指定域名] 目标域名数: 1, 匹配到账号内域名: 1"),
            entry("  [INFO] 使用已有域名: example.com (zone_id=abc123)"),
            entry("  [DRY-ADD-RECORD] A 3 -> 1.2.3.4"),
            entry("    A 3 -> 1.2.3.4 (proxied)"),
            entry("账号 acct-demo 完成: updated=0, created=1, errors=0"),
            entry("对账: zones expected=1, completed=1, cancelled=0"),
            entry("[VERDICT] 完美执行：1 个账号全部成功，无失败。"),
        ]
        events = parse_log_entries(entries)
        self.assertEqual(
            [event["title"] for event in events],
            [
                "任务开始",
                "账号域名",
                "命令行指定域名",
                "使用已有域名",
                "预演：添加记录",
                "账号完成",
                "对账",
                "结论",
            ],
        )
        start = events[0]
        self.assertEqual(start["account"], "acct-demo")
        self.assertEqual(start["zone"], "example.com")
        self.assertEqual(start["meta"]["target_zone"], "example.com")
        self.assertEqual(start["meta"]["records"], "1")

        domains = events[1]
        self.assertEqual(domains["account"], "acct-demo")
        self.assertEqual(domains["meta"]["domains"], "5")

        command = events[2]
        self.assertIn("目标域名数", command["detail"])

        info = events[3]
        self.assertIn("example.com", info["detail"])
        self.assertEqual(info["meta"]["zone_id"], "abc123")

        dry = events[4]
        self.assertEqual(dry["detail"], "A 3 -> 1.2.3.4\nA 3 -> 1.2.3.4 (proxied)")

        done = events[5]
        self.assertEqual(done["level"], "success")
        self.assertEqual(done["account"], "acct-demo")
        self.assertEqual(done["meta"]["created"], "1")
        self.assertEqual(done["detail"], "")

        reconciliation = events[6]
        self.assertEqual(reconciliation["meta"]["completed"], "1")

        self.assertEqual(events[7]["level"], "success")
        self.assertIn("完美执行", events[7]["detail"])

    def test_found_and_account_error(self):
        entries = [
            entry(
                "[FOUND] name=acct-found, domain=example.net, "
                "records=8, elapsed=1.2s"
            ),
            entry("[ACCOUNT-ERR] acct-fail: token 无 Zone:Read 权限"),
            entry("[WARN] 白名单第 1 行未解析到有效域名: not a domain !!!"),
            entry("some random noise line"),
        ]
        events = parse_log_entries(entries)
        self.assertEqual(len(events), 3)
        found = events[0]
        self.assertEqual(found["level"], "success")
        self.assertEqual(found["account"], "acct-found")
        self.assertEqual(found["zone"], "example.net")
        self.assertEqual(found["meta"]["records"], "8")
        self.assertEqual(found["detail"], "")

        failed = events[1]
        self.assertEqual(failed["level"], "error")
        self.assertEqual(failed["account"], "acct-fail")
        self.assertIn("Zone:Read", failed["detail"])

        warn = events[2]
        self.assertEqual(warn["level"], "warning")
        self.assertIn("白名单", warn["title"])

    def test_generic_error_line_is_kept_as_warning(self):
        events = parse_log_entries([entry("操作失败: 网络不可达")])
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["level"], "warning")
        self.assertEqual(events[0]["title"], "操作失败")
        self.assertIn("网络不可达", events[0]["detail"])

    def test_job_captures_timestamped_entries(self):
        job = Job(id="job-test", label="测试", kind="preview")
        job.append_log("[INFO] 使用已有域名: example.com")
        job.append_log("[VERDICT] 完美执行：无失败。")
        total, entries = job.read_log_entries()
        self.assertEqual(total, 2)
        self.assertTrue(all(entry["ts"] for entry in entries))
        events = parse_log_entries(entries)
        self.assertEqual([event["title"] for event in events], ["使用已有域名", "结论"])
        self.assertEqual(events[1]["level"], "success")

    def test_empty_input(self):
        self.assertEqual(parse_log_entries([]), [])


if __name__ == "__main__":
    unittest.main()
