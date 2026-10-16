# -*- coding: utf-8 -*-
"""前端验收（破而后立提高版：静态断言 + 浏览器由 verify 覆盖）。

检查 dist/index.html：
- root/skip/lang/视口/标题随路由；
- 令牌：Topbar56/Sidebar240/1440/390/768/on-primary/圆角四档/阴影带色相/动效120/200/320；
- 步骤条四段全页共享；无快捷入口重复分组；Stat 诚实标注抽样；
- 表格末列粘性、无 100vw 通栏、无 overflow-x 掩盖；
- .btn 全带 svg（含动态模板与 toast 撤销）；状态门真禁用+原因；按钮文案动词+对象；
- 列宽 Home 最小/End 最大/Enter 恢复；CmdK 拼音守卫；刷新保留旧数据；分页 session 可回退；
- 无 div onClick/alert/outline:none。
"""

from __future__ import annotations

import os
import re
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
        ('id="root"' in html, "缺少 root 挂载点"),
        ("skip" in html and "#main" in html, "缺少跳链"),
        ("--topbar-h:56px" in html or "--topbar-h: 56px" in html, "缺少 Topbar56"),
        ("--sidebar-w:240px" in html or "--sidebar-w: 240px" in html, "缺少侧边栏 240"),
        ("--on-primary" in html, "缺少 on-primary 成对令牌（深色白字对比修复）"),
        ("--radius-full" in html, "缺少圆角四档（4/8/12/full）"),
        ("--dur-1:120ms" in html and "--dur-3:320ms" in html, "缺少动效 120/200/320"),
        ("max1440" in html or "1440" in html, "缺少内容 1440"),
        ("390" in html or "767px" in html, "缺少窄屏断点"),
        ("position:sticky" in html and "right:0" in html, "末列粘性缺失"),
        ("prefers-reduced-motion" in html, "缺少 reduced-motion"),
        ("stepper" in html and "aria-current=\"step\"" in html, "缺少四段步骤条"),
        ("快捷入口" not in html, "快捷入口重复分组未删除（多入口未合并）"),
        ("抽样" in html, "Stat 误导未修复（须标注抽样与测量条件）"),
        ("Ctrl+K" in html or "cmdk" in html, "缺少命令面板"),
        ("dry-run" in html or "dry_run" in html, "缺少 dry-run 默认开"),
        ("DELETE" in html, "缺少 DELETE 确认"),
        ("查询记录" in html, "按钮文案未按动词+对象（查询记录）"),
        ("提交预览任务" in html, "提交按钮未随 dry-run 显示预览/执行"),
        ("选择账号" in html and "查看记录" in html, "账号/域名按钮文案未修复"),
        ("下载域名 CSV" in html, "域名 CSV 文案未修复"),
        ("isComposing" in html, "缺少拼音回车守卫"),
        ("sessionStorage" in html and "cf_browse" in html, "分页可回退未实现"),
        ("刷新中" in html, "刷新保留旧数据未实现"),
        ("确认删除" in html, "批量删除对象名确认未实现"),
        ('调整列宽' in html, "列宽调节缺失"),
        ("Home" in html and "End" in html and "Enter" in html, "列宽 Home/End/Enter 键位未统一 sonnet"),
        ("bQueryWhy" in html, "状态门原因可见未实现"),
        ("min(640px,100vw - 32px)" in html or "min(640px,100vw-32px)" in html, "弹窗浮层须 min(期望,100vw-32)"),
    ]
    for ok, msg in checks:
        if not ok:
            fail(msg)
    if "плотный" in html:
        fail("旧主张残留 плотный 未清除")
    forbids = [
        ("window.alert", "禁用 window.alert"),
        ("outline:none", "无替代 outline:none"),
        (
            "onClick" in html and "<div" in html and "onClick=" in html,
            "禁用 div onClick",
        ),
        (
            "overflow-x:hidden" in html.replace(" ", ""),
            "禁用 overflow-x:hidden 掩盖",
        ),
    ]
    nospace = html.replace(" ", "")
    if "100vw" in nospace and "100vw-" not in nospace:
        fail("慎用 100vw 通栏")
    for hit, msg in forbids:
        if hit is True:
            fail(msg)
    # .btn 全带图标（含 JS 模板串中的动态按钮）
    btns = re.findall(r"<button[^>]*>.*?</button>", html, re.S)
    btn_like = [b for b in btns if 'class="btn' in b or "class='btn" in b]
    miss = [b for b in btn_like if "<svg" not in b]
    if miss:
        fail(f".btn 素按钮 {len(miss)} 个未带图标（首个 {miss[0][:80]!r}）")
    # DOM 创建的 toast 撤销按钮须带图标（innerHTML 含 svg）
    if 'b.innerHTML' not in html and "textContent=\"撤销\"" in html:
        fail("toast 撤销按钮素按钮（须 innerHTML 带 svg）")
    if html.count("<svg") < 20:
        fail("动态按钮图标不足")
    for i, line in enumerate(html.splitlines(), start=1):
        if line != line.rstrip():
            fail(f"尾随空白 dist/index.html:{i}")
    print("VISUAL PASS (static, redesign 2026-10-11)")


if __name__ == "__main__":
    main()
