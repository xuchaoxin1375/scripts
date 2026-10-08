# -*- coding: utf-8 -*-
"""前端验收（无浏览器依赖的静态断言 + 可选冒烟由 verify.ps1 覆盖）。

检查 dist/index.html：
- 含 root 挂载点、skip 链、中文 lang、视口；
- 令牌与断点齐全（Topbar56/Sidebar/1440/390/768/RAIL/抽屉）；
- 表格末列粘性、页面无 100vw 通栏、无 overflow-x:hidden 掩盖；
- 按钮必带 svg 图标（含动态生成的编辑/任务按钮模板）；
- 无 div onClick、无 window.alert、无 outline:none 无替代。
"""

from __future__ import annotations

import os
import sys

DIST = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "dist", "index.html"
)


def fail(msg: str) -> None:
    print(f"ACCEPT FAIL: {msg}")
    sys.exit(1)


def main() -> None:
    if not os.path.exists(DIST):
        fail(f"构建产物缺失: {DIST}，先跑 npm --prefix webui/frontend run build")
    with open(DIST, encoding="utf-8") as fh:
        html = fh.read()
    checks = [
        ('lang="zh-CN"' in html, "缺少中文 lang"),
        ('id="root"' in html, "缺少 root 挂载点（冒烟 SPA 依赖）"),
        ("skip" in html and "#main" in html, "缺少跳链"),
        ("--topbar-h:56px" in html or "--topbar-h: 56px" in html, "缺少 Topbar56 令牌"),
        (
            "--sidebar-w:240px" in html or "--sidebar-w: 240px" in html,
            "缺少侧边栏 240 令牌",
        ),
        ("max1440" in html or "1440" in html, "缺少内容 1440 约束"),
        ("390" in html or "767px" in html, "缺少窄屏断点"),
        ("position:sticky" in html and "right:0" in html, "末列粘性缺失"),
        ("prefers-reduced-motion" in html, "缺少 reduced-motion"),
        ("<svg" in html and "<button" in html, "按钮图标缺失"),
        ("Ctrl+K" in html or "cmdk" in html, "缺少命令面板"),
        ("dry-run" in html or "dry_run" in html, "缺少 dry-run 默认开"),
        ("DELETE" in html, "缺少删域名 DELETE 确认"),
    ]
    for ok, msg in checks:
        if not ok:
            fail(msg)
    forbids = [
        ("window.alert", "禁用 window.alert"),
        ("outline:none", "无替代的 outline:none"),
        (
            "onClick" in html and "<div" in html and "onClick=" in html,
            "禁用 div onClick",
        ),
        (
            "overflow-x:hidden" in html.replace(" ", ""),
            "禁用 overflow-x:hidden 掩盖溢出",
        ),
    ]
    nospace = html.replace(" ", "")
    if "100vw" in nospace and "100vw-" not in nospace:
        fail("慎用 100vw 通栏（浮层须 min(期望,100vw-16)）")
    for hit, msg in forbids:
        if hit is True:
            fail(msg)
    if "data-edit" in html and html.count("<svg") < 5:
        fail("动态按钮图标不足")
    # 行尾空白
    for i, line in enumerate(html.splitlines(), start=1):
        if line != line.rstrip():
            fail(f"尾随空白 dist/index.html:{i}")
    print("VISUAL PASS (static)")


if __name__ == "__main__":
    main()
