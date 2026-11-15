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

- 记录表使用服务端分页（每页 50 条），搜索 350ms 防抖，类型/代理/排序都走
  `/api/v1/records` 查询参数；不再一次性拉完整个域名。
- 选中记录跨页保留，批量改内容/删除按记录 ID 精确执行；按域名批量仍走预览任务。
- 预览面板读取任务的真实结果（`/api/v1/jobs/{id}/results`），不再用本地记录猜 Diff。
- 任务列表有运行中任务时 3 秒轮询，空闲时 20 秒；单任务详情仅在运行中 2 秒轮询，
  任务日志仅在运行中自动刷新。
- 批量抽屉关闭时，预览任务详情与任务日志停止轮询；重新打开后再拉取。
- 高级页的历史/审计、跨账号查找、上传与导入都在进入页面或触发动作后才请求；
  离开工作台后不再加载记录。
- 记录、域名、账号分别显示加载/失败状态，失败可单独重试，不会互相遮住。

## 已接真实 API

- 账号、zone、DNS 记录（服务端分页/过滤/排序）、meta、任务列表与详情。
- 预览任务提交（`POST /api/v1/jobs`，`dry_run=true`）。
- 预览结果分页读取、预览转执行（`POST /api/v1/jobs/{id}/execute`）。
- 失败域重跑、取消任务、失败清单 CSV、请求异常 CSV。
- 单条记录编辑（`PATCH /api/v1/records`）。
- 选中记录批量设置代理、按 ID 批量改内容、按 ID 批量删除
  （`POST /api/v1/records/bulk-update` / `bulk-delete`）。
- 记录 JSON 导出（`POST /api/v1/records/export`）与 zone CSV 导出。
- 高级页：跨账号查找、provision 预览/执行、JSON 导入预检/写入、服务器导出任务与
  文件下载、白名单/重跑清单上传、任务历史与审计分页、运行参数。
- 白名单/重跑清单上传后附加到下一次任务，不写入账号配置。

## 尚未完成

- 真实账号的完整写入验收已在授权测试 scope `cf00/goodpayway.shop` 完成，并清理了
  专用测试记录；`cftest` 当前没有 zone，账号级只读与任务链已验收。
- 运行参数只保存本机浏览器，不写回账号配置文件。
- 记录表筛选仍由后端先取全量记录再过滤；超大型 zone 的进一步上游分页需要引擎支持。

## 结构

- `src/App.tsx`：账号/域名范围、记录与任务状态、侧栏/抽屉/弹窗编排。
- `src/components/Sidebar.tsx`：全局导航（桌面默认展开 264，页脚按钮收起为 Rail 64；Rail 悬停/键盘进入临时展开，只覆盖不推挤主内容；窄屏抽屉）。
- `src/components/ResourceSwitcher.tsx`：顶栏账号/域名切换、搜索、加载与重试。
- `src/components/OperationsDrawer.tsx`：右侧批量抽屉、操作/任务页签、焦点与遮罩。
- `src/components/Inspector.tsx`：动作选择、参数、真实 Diff 预览、任务详情。
- `src/components/RecordDialogs.tsx`：单条编辑弹窗与新增记录预览弹窗。
- `src/components/ScopeBar.tsx`：页头、范围条、附件与刷新。
- `src/components/RecordsTable.tsx`：服务端分页表格与 1023px 以下记录卡片。
- `src/components/EmailRoutingPanel.tsx`：邮箱转发目标添加/验证状态、刷新、验证后启用路由并设置 catch-all。
- `src/components/EmailRoutingNotes.tsx`：展开式邮箱转发注意事项（验证、Gmail、MX 冲突、限制）。
- `src/pages/Advanced.tsx`：跨账号查找、provision、邮箱转发、导入导出、范围附件、历史审计。
- `src/api/`：`client.ts` 请求/取消/下载，`hooks.ts` TanStack Query hooks，`types.ts` API 形状。
- `src/shared/actions.ts`：动作任务 payload 组装。
- `src/shared/runtime.ts`：本机运行参数读取/保存。

## 验收

```bash
npm run build
python webui/v2/tests/browser_accept.py
```

测试启动真实 FastAPI 静态托管，用 Playwright 拦截 `/api/v1` 返回固定 JSON；
不访问 Cloudflare。覆盖记录分页、资源切换、侧栏默认展开/页脚收起/Rail 悬停与键盘临时展开/Esc/快捷键、
新增与编辑弹窗焦点、批量抽屉真实预览、任务详情与日志、批量内容/删除、高级页查找/历史/上传、
邮箱转发目标验证与完成 catch-all，1440/1024/768/390 无页面横滚、390 侧栏与抽屉、零 pageerror。

## 邮箱转发限制

- 本页只配置 catch-all（`*@domain` 全部转发到一个目标邮箱）；按前缀的 routing rule 仍在 Cloudflare 控制台配置。
- 目标邮箱验证由 Cloudflare 发送邮件，必须到收件箱点击；WebUI 只负责添加、刷新状态和验证后完成配置。
- 验证邮件重发、目标地址删除在 Cloudflare 控制台 `Email Service > Email Routing > Destination Addresses` 操作。
- API Token 需要 Email Routing Addresses / Rules / Settings 权限；权限不足时接口返回 403。
- 域名必须使用 Cloudflare DNS 且已激活；已有其他 MX 时先确认是否保留原邮箱，避免启用后中断收信。
