# -*- coding: utf-8 -*-
"""前端 API 路径与后端路由一致性。

浏览器验收会拦截全部 `/api/v1/**` 并返回固定 JSON，前端路径写错、后端路由漏挂
也会通过；这里直接比对 v2 源码里写出的路径与 FastAPI 路由表，补上这一层。

只校验路径，不校验方法、参数与响应形状；这些由 `test_webui*.py` 的契约测试覆盖。
"""

from __future__ import annotations

import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from webui.backend.app import create_app  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI_SRC = os.path.join(ROOT, "webui", "v2", "src")

# 源码里的调用写法：双引号、单引号或模板字符串；遇到 ? 即截断查询串。
PATH_RE = re.compile(r"""["'`](/api/v1/[^"'`?\s]*)""")
# 前端模板参数 ${jobId} 与 FastAPI 的 {job_id} 归一成同一个占位符。
FRONT_TEMPLATE_RE = re.compile(r"\$\{[^/{}]+\}")
BACKEND_PARAM_RE = re.compile(r"\{[^/{}]+\}")


def normalize(path: str) -> str:
    """去掉查询串和末尾斜杠，把两边不同的参数名归一成 `{}`。"""
    path = path.split("?", 1)[0].rstrip("/")
    path = FRONT_TEMPLATE_RE.sub("{}", path)
    path = BACKEND_PARAM_RE.sub("{}", path)
    return path or "/"


def frontend_paths() -> set[str]:
    paths: set[str] = set()
    for dirpath, dirnames, filenames in os.walk(UI_SRC):
        dirnames[:] = [name for name in dirnames if name != "node_modules"]
        for name in sorted(filenames):
            if not name.endswith((".ts", ".tsx")):
                continue
            with open(os.path.join(dirpath, name), encoding="utf-8") as handle:
                text = handle.read()
            for match in PATH_RE.finditer(text):
                paths.add(normalize(match.group(1)))
    return paths


def backend_paths() -> set[str]:
    # 新版 FastAPI 的 include_router 是惰性的，app.routes 里只有 _IncludedRouter；
    # OpenAPI 路径表会展开到具体路由，且不受内部实现变化影响。
    paths = create_app("").openapi()["paths"]
    return {normalize(path) for path in paths if path.startswith("/api/v1/")}


class FrontendApiPathTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.front = frontend_paths()
        cls.back = backend_paths()

    def test_frontend_paths_were_found(self):
        # 防止正则或目录变化导致空集合静默通过。
        self.assertGreaterEqual(len(self.front), 20)
        self.assertIn("/api/v1/email-routing/addresses", self.front)
        self.assertIn("/api/v1/email-routing/status", self.front)
        self.assertIn("/api/v1/email-routing/complete", self.front)

    def test_every_frontend_path_has_backend_route(self):
        missing = sorted(self.front - self.back)
        self.assertEqual(
            missing,
            [],
            "前端调用了后端未注册的接口: " + ", ".join(missing),
        )


if __name__ == "__main__":
    unittest.main()
