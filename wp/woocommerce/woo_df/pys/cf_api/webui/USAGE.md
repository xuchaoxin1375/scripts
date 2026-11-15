# WebUI 使用说明

## 1 打开

```powershell
.\serve-webui.ps1              # 后台启动 8600，默认 v2 单工作台
.\serve-webui.ps1 -V1          # 需要旧四页前端时启动 v1
```

浏览器访问 `http://127.0.0.1:8600`。排障看 `.\serve-webui.ps1 -Logs`；前台调试才用 `python start_web_ui.py --port 8600`。

## 2 建议顺序（v2）

1. 顶栏切换账号与域名；左侧全局导航默认展开，页脚按钮可收起为 Rail。
2. 记录表按服务端分页加载；单条编辑点行末“编辑”在弹窗保存。
3. 勾选记录或点“批量操作”，在右侧批量抽屉填写参数并提交预览。
4. 预览抽屉读取任务真实结果；确认无误后执行变更。
5. 任务页签看进度、日志与失败清单；有失败域可重跑。
6. 删除类动作先限定范围；删域名必须填快照目录并输入 `DELETE`。

## 3 高风险动作

- 删除通配符 / 删 IP / 删域名必须先限定域名范围。
- 删域名必须填快照目录并输入 `DELETE`，否则 400 拒绝。
- 正式变更前建议填快照目录做自动备份；备份失败会中止变更。

## 4 全量能力对照（CLI → Web）

| CLI | Web |
|---|---|
| `-f` 查找域名 | 高级页“跨账号查找” → `GET /api/v1/find?domain=` |
| `--list-dns` | 工作台记录表 → `GET /api/v1/records`（服务端分页） |
| 单条增改 | 记录编辑器 → `PATCH /api/v1/records`；新增/导入 → `POST`；按 id 删 → `DELETE` |
| 批量更新/删除/添加/设属性/导出 | 动作面板/高级页 → `POST /api/v1/jobs`（`dry_run` 默认开） |
| `--provision` 全流程 | 动作面板或高级页 provision：服务器 IP/转发邮箱/SSL/步骤开关 → 同名模式任务 |
| 失败清单重跑 | 高级页上传清单 `POST /api/v1/resume-upload`；任务页签“重跑失败域” |
| 白名单文件 | 高级页上传 `POST /api/v1/whitelist-upload`，附加到下一次任务（等价 `-w`） |
| 域名列表导出 | 高级页“zone CSV” → `GET /api/v1/zones.csv`（UTF-8-SIG，5000 行上限） |
| 备份产物下载 | 任务页签“导出文件” → `GET /api/v1/jobs/{id}/exports[/{n}]`（仅限导出/快照目录内） |
| 显式调参 | 高级页“运行参数”：速度档位/限速范围/最大重试（账号并发越界 400） |
| 催激活 | 域名激活等待在 provision 内自动执行；也可调 `POST /api/v1/zones/activation-check` |

```mermaid
flowchart TD
    A[工作台确认账号/域名/记录范围] --> B[动作面板提交预览任务]
    B --> C{预览结果与 verdict 是否符合预期?}
    C -->|否| D[调整范围/参数/白名单]
    D --> B
    C -->|是| E[执行预览]
    E --> F[任务页签核对日志与失败清单]
    F --> G{有失败项?}
    G -->|是| H[下载清单→重跑失败域]
    G -->|否| I[完成]
```

## 5 导航与窄屏

- 旧前端 v1 的左侧账号/域名搜索框用于本地过滤，不触发额外请求。
- 390/768/1024/1440 宽度可用；v2 在 1023 以下记录表转卡片，页面无横向滚动。
- 移动端左侧导航通过顶栏菜单按钮展开，选择后自动收起。

## 6 新前端 v2（单工作台）

`webui/v2/` 是默认单工作台前端，不再分概览/浏览/操作/任务四页：

- 顶栏切换账号/域名；左侧全局导航默认展开，页脚按钮收起为 Rail；Rail 悬停或键盘进入会临时展开，主内容槽宽不变，`[` 可切换收起/展开；窄屏抽屉。
- 单条记录“编辑”在弹窗内走 `PATCH /api/v1/records`；新增记录弹窗提交后先生成预览任务。
- 批量操作与任务在右侧抽屉；选中记录可批量设置代理、按 ID 改内容或删除。
- 记录表按服务端分页加载（50 条/页），搜索、类型、代理与排序都传后端；选中记录跨页保留。
- 选中记录或直接点“批量操作”，填写参数后先提交预览任务；预览面板读取任务真实结果，确认后“执行变更”。
- 任务页签里可看进度、原始日志、失败清单、异常 CSV、失败域重跑、执行预览、导出文件。
- 1023px 以下记录表转卡片，1024px 及以上保留表格；页面无横向滚动。
- 高级页已接：跨账号查找、provision 预览/执行、邮箱转发、JSON 导入预检/写入、记录 JSON / zone CSV 导出、服务器导出任务、白名单/重跑清单上传、任务历史与审计、运行参数。

### 邮箱转发（Email Routing）

在高级页“邮箱转发（Email Routing）”面板：

1. 选择账号和域名，填写目标邮箱（例如 Gmail）。
2. 点“添加并发送验证”；Cloudflare 会向目标邮箱发验证邮件。目标地址是账号级的，验证一次可复用到同账号其他域名。
3. 到目标邮箱（含垃圾箱）点 “Verify email address”，回到面板点“刷新状态”。
4. 目标邮箱显示“已验证”后，点“验证后完成配置”；面板会启用路由并设置 catch-all。
5. 从另一个邮箱发到 `test@你的域名`，检查目标邮箱收件箱和垃圾箱；不要用同一个 Gmail 自发。

注意：

- 新账号的第一个域名同样要验证目标邮箱；新账号本身的邮箱验证是另一件事，不能替代目标地址验证。
- 域名必须使用 Cloudflare DNS 且已激活；已有其他 MX（Google Workspace、企业邮箱）会冲突，启用 Email Routing 会替换 MX，先确认原邮箱是否保留。
- 未验证前不要执行带“邮箱”步骤的 provision：MX 会先切换，但 catch-all 不生效，来信可能被拒（Address does not exist）。
- 本页只配置 catch-all；只想收指定前缀（如 `info@`）时到 Cloudflare 控制台建具体 routing rule。
- 验证邮件没收到，到 Cloudflare 控制台 `Email Service > Email Routing > Destination Addresses` 重发；WebUI 负责添加、刷新状态和验证后完成配置。
- API Token 需要 Email Routing Addresses / Rules / Settings 权限；权限不足会报 403。
- 限制：目标地址 200 个/账号、规则 200 条/域名、单封 25 MiB。

启动（与旧版对比，建议单独端口）：

```powershell
cd webui/v2
npm install
npm run build
cd ../..
python start_web_ui.py --port 8601 --config <cf_config.csv|json>
```

也可用 `.\serve-webui.ps1 -Port 8601 -Config <cf_config.csv|json>` 由后台服务管理；
`-Restart -V1` 切回旧前端，不传前端参数时 `-Restart` 保持现状。
改了后端代码（`webui/backend/`、`start_web_ui.py`、`cloudflare_dns_tool.py`）后必须 `-Restart`；
`-Status` 发现进程早于代码更新时会提示，否则浏览器可能加载新界面却调用到旧接口。

浏览器打开 `http://127.0.0.1:8601`。旧版用 `-V1` 启动；v2 已是默认入口。
