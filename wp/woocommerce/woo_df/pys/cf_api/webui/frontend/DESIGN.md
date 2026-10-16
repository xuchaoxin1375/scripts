# 前端设计（清单式控制台，单文件）

> 状态：2026-10-11 破而后立重做。旧主张“像 Cloudflare 控制台一样 плотный”含俄语残留且未落 token，已废止。本版从任务重做，外壳沿 fable 基底，记忆点唯一为四段步骤条。

## 步骤1——任务与渐进披露

一句话：本机单用户为多账号 Cloudflare DNS 做批量变更，主任务是圈定范围→dry-run 预览→执行→凭 verdict 与失败清单闭环，下一步永远可回退。

假设：仅 127.0.0.1 本机使用；无配额查询接口；59 账号现网；高风险操作必须二次确认；后端 `/api/v1` 契约冻结，前端只改表现层。

旧设计为什么是现在这样：单文件原生无 Node 依赖、FastAPI 直接复用引擎校验与失败清单，为求全量 CLI 能力最快落地。代价是浏览页三表堆叠首屏多焦点、概览 Stat 用首账号抽样冒充总数、侧栏快捷入口与管理重复、查询等按钮伪装可用、列宽键位混写 fable/sonnet、CmdK 回车无拼音守卫、刷新清表闪骨架、批量删除无对象名确认。

分层：L1 首屏只做一件事（浏览=查记录，操作=提交预览，任务=看 verdict）；L2 次要进弹窗（账号库/域名库/历史/审计/筛选草稿）；L3 高级收折叠（速度与限流）。危险操作（删通配符/删 IP/删域名）远离首屏：操作页独立危险分组 + 快照必填 + DELETE 确认。空状态只给一件事加一个主按钮。同一动作多入口合并为一个：侧栏只留概览/浏览/操作/任务四项，删除快捷入口重复分组。

## 步骤2——主张与线框

情绪目标：踏实、可回退、不怕点错。不要感受到：花哨、误导、点后才知不可用。

灵感转译：飞机检查单 + 实验室记录本。每步留痕、可撤销、结论标测量条件。

候选三方向：A 清单式向导（范围→动作→参数→确认四步强引导，老用户多一步）；B 密排控制台（保持四页只修细节，信息过载依旧）；C 搜索优先指挥台（CmdK 为核心，发现性弱）。选定 A+C 融合：保留四页外壳降迁移成本，每页顶部统一四段步骤条，浏览收纳双表进弹窗，操作按分组非强制分步。只换配色不算新方向，故三者布局/信息组织均不同。

核心主张：清单式控制台——范围→预览→证据。

记忆点（一处）：全页共享四段步骤条（范围→预览→执行→核对，当前高亮可回跳）。任务进度头保留为功能，不抢视觉焦点。

不做什么：不虚构配额上限数；不做满屏毛玻璃/渐变大字/标题 emoji/卡片套卡片；不做双前端；不做配置切换与任务级代理；装饰只许步骤条一处。

线框（每块：是什么+多宽+装什么）：

```text
Topbar56（高56，全宽）：[菜单36][Logo+操作台][配置路径摘要ellipsis max60vw][spacer][代理徽标][主题36][命令Ctrl+K]
Shell（文档滚动）：SidebarSlot240/Rail56/抽屉<768 + main max1440 padding16
Sidebar（ top56 sticky 高calc)：[快速搜索→CmdK][返回概览][分组管理：概览/浏览/操作/任务 双行标题+副标题][底部收起[ ]]
概览 main：PageHeader（标题+一句话任务+规模摘要）+ alert首屏一件事 + 步骤条 + 主操作≤3（查记录primary/批量改IP/看任务）+ 配置摘要卡（真实数+抽样声明）
浏览 main：PageHeader + 步骤条 + 上下文栏L1（账号select 240 + 域名input flex + 状态select 140 + 查询记录primary，真禁用+原因）+ 次要行L2（账号库/域名库/全账号查找/域名CSV）+ 工具栏（搜索左伸缩+筛选+显示+导入+导出+新增记录primary最右，窄屏搜索独占行）+ chips生效条件 + 表卡（计数+分页20/50/100/200）+ 选中才出现批量条
操作 main：PageHeader + 步骤条 + 表单max720单列分组（1范围：账号chips+域名+白名单+上传 / 2动作：日常/危险radio卡 / 3参数：按动作动态，危险区红区独立 / 4确认：dry-run默认开+摘要+提交预览/执行任务）+ 高级details + 草稿+脏保护
任务 main：PageHeader + 步骤条 + 上下文（刷新/历史/审计）+ 进度头sticky（进度+取消/下载清单/重跑/导出）+ verdict + 结果表分页50 + 日志框限高内滚220
弹窗（一次一个，min640,100vw-32）：账号库/域名库/历史/审计/导入/命令；移动底板全宽；焦点进首字段关回焦Esc遮罩关
```

窄屏与容器：视口 1440/768/390 + 320 回流 + 300 压力；容器 recWrap 640 切表/卡；表单 720 单列；工具栏窄屏换行不删功能；表容器内横滚 + 末列 sticky 不透明 + 滚动阴影；页面无横滚；弹窗 `min(640px,100vw-32px)`；批量条底部浮层预留末行 padding。滚动归属：页面随文档滚，弹窗体与日志框限高内滚，表框限高 560 内滚表头 sticky。

无障碍底线：WCAG 2.2 AA，全键盘可达，`:focus-visible` 2px，目标≥24（触屏≥44），正文≥4.5:1，大字/图标/边界≥3:1，320 回流，`lang=zh-CN`，中文行高 1.6，CJK 不用斜体与两端对齐。

## 步骤3——令牌（三层，组件只用语义层）

```css
:root{
--bg:#ffffff; --subtle:#f4f6fa; --hover:#eef2f8; --surface:#ffffff; --canvas:#f7f9fc;
--text1:#1a2233; --text2:#4b5568; --text3:#626872; --border:#dde0e4;
--primary:#0051c3; --primary-hover:#003f99; --on-primary:#ffffff; --primary-soft:#e8f0fc; --link:#0051c3;
--success:#0f7a3d; --success-soft:#e0f3e7; --warning:#9a6700; --warning-soft:#fdf0d5; --danger:#c62828; --danger-soft:#fde7e9;
--brand:#f6821f; --focus:#0051c3;
--radius-s:4px; --radius-m:8px; --radius-l:12px; --radius-full:9999px;
--shadow-1:0 1px 2px rgba(0,81,195,.08); --shadow-2:0 4px 12px rgba(0,81,195,.10); --shadow-3:0 12px 32px rgba(0,81,195,.16);
--topbar-h:56px; --sidebar-w:240px; --rail-w:56px; --content-w:1440px;
--ease:cubic-bezier(.2,0,0,1); --dur-1:120ms; --dur-2:200ms; --dur-3:320ms;
color-scheme:light;
}
[data-theme="dark"]{
--bg:#0f1114; --subtle:#1e2126; --hover:#23272e; --surface:#17191d; --canvas:#0f1114;
--text1:#e8eaed; --text2:#b4b9c1; --text3:#a0a6af; --border:#2c3037;
--primary:#6ea8ff; --primary-hover:#8dbaff; --on-primary:#0f1114; --primary-soft:#16233a; --link:#8dbaff;
--success:#4cc275; --success-soft:#12362a; --warning:#e3b341; --warning-soft:#3a2c12; --danger:#ff7b72; --danger-soft:#3d1a20;
--focus:#7fb0ff; color-scheme:dark;
}
```

差异说明：删 6px 圆角档（4/8/12/full 四档）；阴影带主色相；`--text3 #7b8499→#626872` 使白底≥4.5:1；深色主按钮文字改 `--on-primary #0f1114`（旧白字对 `#6ea8ff` 仅约 2.4:1）；字号 12/13/14/16/20/24/28 七档内；间距 4/8/12/16/24/32/48；动效 120/200/320 只过渡 transform/opacity/width，跟随 reduced-motion；图标只用 Lucide 内联 stroke2 round。

对比度配对（前景→背景→用途→阈值）：正文 text1→surface≥4.5；次要 text2→surface≥4.5；辅助 text3→surface≥4.5（含 placeholder/只读）；主按钮 on-primary→primary/hover≥4.5（含 hover 复测）；链接 link→surface≥4.5 且正文链接常显下划线；pill/soft 文字对 soft 底≥4.5，图标对 soft 底≥3:1；代理/警告图标对行底≥3:1；焦点环 focus 对相邻底≥3:1 且不被 sticky 遮挡。

## 步骤4——交互、动效、文案

异步同一视觉语言：加载骨架预留尺寸防跳位，刷新保留旧数据 + 小指示“刷新中…”，空态给原因 + 主操作（暂无记录→新增记录，无匹配→清除过滤），错态给原因 + 重试，不只一行红字。测量条件标注：概览域名数明确“首账号抽样，非总数”，全账号查找显示“走 find 接口相对全部账号基线”。

显示与操作分离：Stat 只读不做成可点。配置收设置入口（主题/偏好），操作留独立入口（查询/提交）。

状态门二选一：查询记录无账号/域名时真禁用 + 原因可见（旁边文字 + title），禁伪装可用；表单填错不禁用提交，点了定位首错。有改动/无权限/提交中可禁用并说明原因与恢复路径。

弹窗/抽屉/菜单双向过渡 200/120ms，减弱偏好瞬时切换；列表载入 200ms 不逐行拖延；页面切换 200-320ms。耗时操作同步忙态防重入（提交中禁用 + aria-busy + 文字“提交中…”），完成/失败恢复；动效不阻塞焦点。

按钮文案=动词+对象+后果：查询记录、选择账号、查看记录、新增记录、提交预览任务/提交执行任务、下载失败清单、一键重跑失败域、确认导入、确认删除。一次只开一个弹窗；破坏性确认写清对象名与数量（删除 N 条含首条名 + 撤销说明新 ID）。

表单：可见 label、正确 type/inputmode/autocomplete、失焦+提交两级校验、内联可修复错误 aria-describedby、首错聚焦、保留已填、允许粘贴。记录弹窗与行内共用同一校验；MX/TXT 联动关代理；开焦首字段关回焦Esc；脏保护（站内提示 + beforeunload 补充）；保存防重。

## 步骤5——响应式与状态（路由到 adaptive-responsive-guide）

阈值：视口 1440/768/390，容器 recWrap 640，表单 720。不断点名推定布局，以内容实测为准。实现只读命中场景：page-patterns（滚动归属与浮层形态）、patterns（操作收纳）、container-queries（640 切卡）、overflow-squeeze、extreme-narrow（300 压力）。

内容区 `flex:1+min-width:0` 保收缩；长行 `overflow-wrap:anywhere` 断行不断窗；单行省略加 title，正文至多 2 行。

## 步骤6——审查与交付（本轮提高项）

`scripts/scan.py` + `tests/accept.py` 静态门（新增：步骤条存在、on-primary 成对、列宽 Home/End/Enter、isComposing 守卫、真禁用原因、按钮全带图标、无 div onClick/alert/outline:none/100vw 通栏/overflow-x 掩盖）；浏览器门禁 `tests/browser_accept.py` 真机渲染 1440/768/390/320/300（开闭抽屉双态无横滚、路由切换、填表提交→verdict→日志非空、零 pageerror、视口截图 TEMP）；axe 零违例；LCP≤2.5s、INP≤200ms、CLS≤0.1；人工 Tab 走查 + NVDA/VoiceOver + 200% 缩放 + 深色。

结论三级：阻断（MUST/NEVER）/建议（SHOULD）/细节，注明文件与规则。交付：线框、令牌差异、视口/容器验证记录与截图、清单打勾、已知问题、保留清单。未执行项明确记录，不称通过。

## 保留清单（举证倒置，无论证保留=阻断）

1. fable 外壳 Topbar56+Sidebar（240/Rail56/抽屉）+ main max1440：已达独特级（遮 logo 可认的 Cloudflare 式密排 + 步骤条记忆点融合）？是，步骤条+密排组合非品类默认；为何不更好：换 264 将全量重测列宽与截图，ROI 低，240 已有 59 账号现网验证；对照 taste 第2/5条走过，以截图对标 fable/sonnet/gpt，方向仍无辨识度时无需转 distinctive（后台工具以可扫为先）。
2. 记录表工具栏九层骨架（搜索+筛选草稿应用+显示+导入+导出+新增 primary 最右）与计数条/复选列/三态排序 aria-sort/代理 TTL 备注详情警告列/短名/行内展开与新增共用校验/悬浮批量条+删除撤销/导入预检门：已达非凡级？是，现网建改删撤销全链通过且零残留；为何不更好：改任一将丢 9/9 verify 证据；对照过三工程截图，fable DNS 页整体 + sonnet 列宽 Undo + gpt 导入验收各取所长。
3. 任务三级进度 + verdict 复用引擎 + 失败清单 CSV 含 BOM + 一键重跑：已达独特级（引擎零侵入 + 测量条件标注）？是；为何不更好：改 verdict 将与 CLI 对账行分叉；对照过引擎 `build_final_verdict`，保持同源。
4. CmdK Ctrl+K + 双击填入 + 行内填入按钮（键盘/触屏等价）：已达非凡级？是，拼音守卫修复后无误触；为何不更好：删后老用户效率回退；对照过 fable 命令面板实现。
5. 单文件无依赖构建（复制即发布）：已达独特级（断网可用 + 秒开）？是；为何不更好：上 Vite/React 将引入工具链与审计负担；对照过 DECISIONS 放弃项，维持。

## 验收

- 390/768/1440 + 320 回流 + 300 压力：`scrollWidth<=innerWidth`，浮层 `min(期望,100vw-16)`。
- 按钮必带图标；无 `div onClick`；焦点可见不被 sticky 遮挡；正文对比 4.5:1，图标/边界 3:1。
- 视口/容器截图先全景定结构再特写验细节；浮层用视口截图；大改加开/关/空/满/错交互态截图并人眼确认。
