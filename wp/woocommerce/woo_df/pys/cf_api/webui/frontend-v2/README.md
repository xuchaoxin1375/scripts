# WebUI v2（单工作台）

Vite + React + TypeScript。目标是替换旧四页壳，先完成核心闭环；旧前端
`webui/frontend/` 仍是默认入口，本目录可通过 `--frontend-v2` 单独启动。

## 启动

```bash
# 生产构建后用 FastAPI 托管（推荐先开 8601 与旧版对比）
npm run build
python start_web_ui.py --frontend-v2 --port 8601 --config <cf_config.csv|json>

# 开发模式：Vite 8612，/api 代理到 8600
npm run dev

# 仅看设计稿时使用 mock 数据
VITE_USE_MOCK=true npm run dev
```

Windows PowerShell 设置 mock：`$env:VITE_USE_MOCK='true'; npm run dev`。

## 已接真实 API

- 账号、zone、DNS 记录、meta、任务列表与任务详情。
- 预览任务提交（`POST /api/v1/jobs`，`dry_run=true`）。
- 预览转执行（`POST /api/v1/jobs/{id}/execute`）。
- 失败域重跑（`POST /api/v1/jobs/{id}/rerun?failed_only=true`）。
- 取消任务、失败清单 CSV、请求异常 CSV。
- 单条记录编辑（`PATCH /api/v1/records`）。
- 选中记录批量设置代理（`POST /api/v1/records/bulk-update`）。

## 尚未完成

- 高级页的 provision / 导入导出 / 全账号查找 / 历史审计仍是结构占位。
- 选中记录批量删除、按 ID 批量改内容、导入预检。
- 旧入口切换与 `serve-webui.ps1` 的 v2 参数；当前用 `start_web_ui.py --frontend-v2`。

## 结构

- `src/pages/Workspace.tsx`：账号/域名导航 + 范围条 + 记录表 + 批量条 + 检查器。
- `src/components/Inspector.tsx`：动作选择、参数、Diff 预览、单条编辑、任务详情。
- `src/components/RecordsTable.tsx`：桌面表格与 640px 以下记录卡片。
- `src/pages/Advanced.tsx`：低频能力入口（待接线）。
- `src/api/`：`client.ts` 请求与下载，`hooks.ts` TanStack Query hooks，`types.ts` API 形状。
- `src/lib/actions.ts`：动作预览行与任务 payload 组装。

## 验收

```bash
npm run build
python webui/frontend-v2/tests/browser_accept.py
```

测试启动真实 FastAPI 静态托管，用 Playwright 拦截 `/api/v1` 返回固定 JSON；
不访问 Cloudflare。覆盖 1440/390、预览提交、任务详情、单条编辑、批量代理与
零 pageerror。
