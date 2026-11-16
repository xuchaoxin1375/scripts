# WebUI v2（单工作台）

Vite + React + TypeScript，默认入口。旧四页前端保留在 `webui/v1/`，可用
`--v1` 或 `serve-webui.ps1 -V1` 切回。

## 启动

```bash
# 生产构建后用 FastAPI 托管（默认入口，推荐单独端口）
npm run build
python start_web_ui.py --port 8601 --config <cf_config.csv|json>

# 或由 PowerShell 管理后台服务
.\serve-webui.ps1 -Port 8601 -Config <cf_config.csv|json>

# 开发模式：Vite 8612，/api 代理到 8600
npm run dev

# 仅看设计稿时使用 mock 数据
VITE_USE_MOCK=true npm run dev
```

Windows PowerShell 设置 mock：`$env:VITE_USE_MOCK='true'; npm run dev`。
切回旧前端：`.\serve-webui.ps1 -Port 8601 -Restart -V1`。

## 加载策略

- 记录表按总量分档：首次请求 50 条；`total <= 50` 时第一页就是全部，直接本地；
  `51–500` 再请求一次 `all=true` 取回全量后本地处理；`>500` 保持服务端分页，
  排序/筛选/翻页走请求，并用旧数据占位避免闪骨架。
- 本地模式下搜索 150ms 防抖，类型/代理/两态排序/分页全部即时完成，不请求后端。
- 编辑保存、批量改内容成功后直接更新本地缓存，不重新拉整表；批量删除更新本地并在
  服务端分页模式下后台刷新当前页；导入可能批量新增/更新，后台重拉一次且保留旧数据。
- 表头列宽可拖动，方向键 8px（Shift 32px）、Home/End 最小/最大、Enter 或双击恢复默认，
  宽度写入 `localStorage`（`cfv2-records-cols`）；1023px 以下切记录卡片，不显示表头。
- 名称/类型/内容表头按钮两态排序：新列从升序开始，同列在升序/降序间切换，不再点回“未排序”；
  回到默认顺序用工具栏“重置排序”（排序激活时出现），1023px 以下用工具栏“排序”下拉的“默认顺序”。
- 预览面板读取任务的真实结果（`/api/v1/jobs/{id}/results`），不再用本地记录猜 Diff。
- 任务列表有运行中任务时 3 秒轮询，空闲时 20 秒；单任务详情仅在运行中 2 秒轮询，
  任务日志仅在运行中自动刷新。
- 批量抽屉关闭时，预览任务详情与任务日志停止轮询；重新打开后再拉取。
- 高级页按分区路由加载，只请求当前分区需要的数据；离开工作台后不再加载记录。
- 跨账号查找创建后台扫描后每 1 秒轮询进度；默认“找到第一个就停止”，可切换
  “扫描全部账号”，命中后也可“继续查询剩余账号”；离开页面扫描继续，返回时按
  `sessionStorage`（`cfv2-find-scan`）恢复。扫描结果只保留在服务端内存，重启后失效；
  页面会自动清理失效的扫描 ID，并提示重新查找。
- 记录、域名、账号分别显示加载/失败状态，失败可单独重试，不会互相遮住。

## 已接真实 API

- 账号、zone、DNS 记录（小 zone 全量本地、大 zone 服务端分页）、meta、任务列表与详情。
- 预览任务提交（`POST /api/v1/jobs`，`dry_run=true`）。
- 预览结果分页读取、预览转执行（`POST /api/v1/jobs/{id}/execute`）。
- 失败域重跑、取消任务、失败清单 CSV、请求异常 CSV。
- 任务详情：结构化执行时间线 + 折叠的原始日志；`/api/v1/jobs/{id}/logs`
  同时返回 `events` 与 `logs`。
- 单条记录编辑（`PATCH /api/v1/records`）与新增（`POST /api/v1/records`）都在弹窗内直接写入，不经过预览任务。
- 选中记录批量设置代理、按 ID 批量改内容、按 ID 批量删除
  （`POST /api/v1/records/bulk-update` / `bulk-delete`）。
- 记录 JSON 导出（`POST /api/v1/records/export`）与 zone CSV 导出。
- 高级页：跨账号查找（后台扫描、进度、部分结果、取消、命中即停/扫描全部/继续查询）、
  provision 预览/执行、JSON 导入预检/写入、服务器导出任务与文件下载、
  白名单/重跑清单上传、任务历史与审计分页、运行参数。
- 邮箱转发：账号级目标地址库（已验证默认选中、待验证折叠、添加与刷新）与域名级启用（域名、目标、状态、风险确认）双列分层；1024px 及以下堆叠。Provision 与 Inspector 的邮箱目标只从账号内已验证地址中选择。
- 出口代理：顶栏/侧栏打开设置，`GET/PUT /api/v1/proxy` 在当前进程保存代理列表；总开关与单项开关分离，总开关关闭时只保存不启用。URL 脱敏回显，已有条目按 id 切换不会丢凭据，不落盘。
- 白名单/重跑清单上传后附加到下一次任务，不写入账号配置。

## 尚未完成

- 邮箱转发的真实 Cloudflare 写入（添加目标地址、邮箱验证、启用路由与 catch-all）尚未在真实账号验收；
  当前通过后端契约测试、假 updater 与浏览器 mock 验收，首次真实使用需按 `USAGE.md` 走一遍。
- 真实账号的完整写入验收已在授权测试 scope `cf00/goodpayway.shop` 完成，并清理了
  专用测试记录；`cftest` 当前没有 zone，账号级只读与任务链已验收。
- 运行参数只保存本机浏览器，不写回账号配置文件。
- 超过 500 条的 zone 仍走服务端分页；超大 zone 的上游分页/分段加载需要引擎支持。

## 结构

- `src/main.tsx`：BrowserRouter 路径路由；旧 `#/` 链接在启动时自动迁移到对应路径。
- `src/App.tsx`：账号/域名范围、记录与任务状态、侧栏/抽屉/弹窗编排。
- `src/components/Sidebar.tsx`：全局导航（桌面默认展开 264，页脚按钮收起为 Rail 64；Rail 悬停/键盘进入临时展开，只覆盖不推挤主内容；第一段无标题、后续分组标题槽固定高度，折叠态用分隔线；折叠态点击导航保持到指针离开，固定展开时不收起；高级工具按分区列出；窄屏抽屉）。
- `src/components/ResourceSwitcher.tsx`：顶栏账号/域名切换、搜索、加载与重试。
- `src/components/OperationsDrawer.tsx`：右侧批量抽屉、操作/任务页签、焦点与遮罩。
- `src/components/Inspector.tsx`：动作选择、参数、真实 Diff 预览、任务详情。
- `src/components/RecordDialogs.tsx`：单条编辑与新增记录弹窗，都在弹窗内直接写入。
- `src/components/ProxySettingsDialog.tsx`：出口代理设置弹窗（代理列表、总开关、单项开关、脱敏状态与未保存修改提示）。
- `src/components/ScopeBar.tsx`：页头、范围条、附件与刷新。
- `src/components/RecordsTable.tsx`：按总量分档的记录表、两态排序与工具栏重置、可调列宽与 1023px 以下记录卡片。
- `src/components/ColumnResize.tsx`：列宽拖动/键盘/持久化单元，`<colgroup>` 与填充列配合。
- `src/components/EmailRoutingPanel.tsx`：邮箱转发面板；账号级目标地址库与域名级启用双列分层，已验证地址默认选中，待验证地址折叠，风险确认内联，技术详情折叠。
- `src/components/FindPanel.tsx`：跨账号扫描的创建、进度轮询、取消、命中表、未找到账号与结构化扫描记录。
- `src/components/EmailRoutingNotes.tsx`：展开式邮箱转发注意事项（验证、Gmail、MX 冲突、限制）。
- `src/pages/Advanced.tsx`：高级页各分区、跨账号查找、provision、邮箱转发、导入导出、范围附件、历史审计、运行参数。
- `src/shared/advancedSections.ts`：侧栏与高级页共用的分区名称、说明与图标。
- `src/api/`：`client.ts` 请求/取消/下载，`hooks.ts` TanStack Query hooks，`types.ts` API 形状。
- `src/shared/actions.ts`：动作任务 payload 组装。
- `src/shared/runtime.ts`：本机运行参数读取/保存。

## 验收

```bash
npm run build
python webui/v2/tests/browser_accept.py
python tests/test_webui_email_routing.py
python tests/test_webui_api_paths.py
```

浏览器验收启动新的 FastAPI 进程托管真实 `dist`，但用 Playwright 拦截 `/api/v1` 返回固定 JSON；
它验证界面状态与交互，不验证运行中的后端是否存在这些路由，也不访问 Cloudflare。
`test_webui_api_paths.py` 比对前端源码里的 `/api/v1` 路径与后端 OpenAPI 路由表，补上路径漂移；
`serve-webui.ps1 -Status` 会提示后端进程早于代码更新的情况。

覆盖记录分页、资源切换、侧栏默认展开/页脚收起/Rail 悬停与键盘临时展开/Esc/快捷键、
新增与编辑弹窗焦点、批量抽屉真实预览、任务详情与日志、批量内容/删除、侧栏高级工具分区与查找/历史/上传、
邮箱转发目标验证与完成 catch-all（账号级/域名级双列在 1024/768/390 下堆叠）、Provision/Inspector 只选已验证目标，1440/1024/768/390 无页面横滚、390 侧栏与抽屉、零 pageerror。

## 邮箱转发限制

- 本页只配置 catch-all（`*@domain` 全部转发到一个目标邮箱）；按前缀的 routing rule 仍在 Cloudflare 控制台配置。
- 目标邮箱验证由 Cloudflare 发送邮件，必须到收件箱点击；WebUI 只负责添加、刷新状态和验证后完成配置。未验证时引擎不修改 DNS/MX/路由，Provision 与 Inspector 也不会提交未验证目标。
- 验证邮件重发、目标地址删除在 Cloudflare 控制台 `Email Service > Email Routing > Destination Addresses` 操作。
- API Token 需要 Email Routing Addresses / Rules / Settings 权限；权限不足时接口返回 403。
- 域名必须使用 Cloudflare DNS 且已激活；已有其他 MX 时先确认是否保留原邮箱，避免启用后中断收信。
