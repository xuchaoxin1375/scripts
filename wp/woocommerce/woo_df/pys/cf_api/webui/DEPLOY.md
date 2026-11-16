# WebUI 依赖与部署

本文说明 Cloudflare DNS WebUI 的依赖、首次部署、升级与排障。日常操作见 [USAGE.md](USAGE.md)，接口与架构见 [README.md](README.md)。

适用范围：Windows 本机单用户；后台管理脚本 `serve-webui.ps1` 依赖 PowerShell 5.1+。其他平台可直接前台运行 `python start_web_ui.py`，但未做验收，也不适用 `serve-webui.ps1` 的进程管理。

## 1 版本与依赖

| 组件 | 要求 | 说明 |
|---|---|---|
| Python | `>= 3.10`（已在 3.13.15 验证） | 当前 fastapi/uvicorn 等依赖要求 3.10+ |
| Node.js | `^20.19.0` 或 `>= 22.12.0`（已在 24.21.0 验证） | 仅构建前端，运行时不启动 Node |
| npm | 随 Node 安装（已在 11.19.0 验证） | 按 `package-lock.json` 安装 |
| PowerShell | `5.1+` | `serve-webui.ps1` 的进程管理与 `-Lan` 等参数 |

Python 运行时依赖固定在 [requirements.txt](requirements.txt)：`fastapi`、`uvicorn`、`python-multipart`（上传接口需要）、`requests`（引擎调用 Cloudflare API 需要）。

前端依赖与锁文件在 [v2/package.json](v2/package.json)、[v2/package-lock.json](v2/package-lock.json)。`webui/v2/dist/` 是构建产物，已被 Git 忽略；干净检出后必须构建，不能只装 Python 依赖。

验证与测试依赖见 [requirements-dev.txt](requirements-dev.txt)：`httpx`（TestClient）、`playwright`（浏览器验收）、`ruff`。`pyright` 可选，未固定版本。

首次安装需要能访问 PyPI 与 npm registry；受限网络按实际环境配置镜像或代理，本文不固定地址。

## 2 首次部署

以下命令在仓库的 `wp/woocommerce/woo_df/pys/cf_api` 目录执行。把 `<repo>` 换成仓库实际路径。

1. 进入目录并创建虚拟环境（推荐，避免污染全局 Python）：

   ```powershell
   cd <repo>\wp\woocommerce\woo_df\pys\cf_api
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install --upgrade pip
   ```

   若 `Activate.ps1` 被执行策略拦截，可在当前窗口临时放行：

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\.venv\Scripts\Activate.ps1
   ```

2. 安装 Python 运行时依赖：

   ```powershell
   pip install -r webui\requirements.txt
   ```

   成功判据：`python -c "import fastapi, uvicorn, multipart, requests"` 无输出、退出码为 `0`。

3. 安装前端依赖并构建：

   ```powershell
   npm ci --prefix webui/v2
   npm --prefix webui/v2 run build
   ```

   `npm ci` 按锁文件重装，适合部署；只在有意升级依赖时用 `npm install`。
   成功判据：生成 `webui/v2/dist/index.html`。

4. 准备账号配置。可从模板复制一份，放在仓库外，例如 `<config-dir>\cf_config.csv`：

   ```powershell
   Copy-Item examples\cf_config.template.readonly.csv <config-dir>\cf_config.csv
   ```

   配置文件格式、API Token 与 Email + Global API Key 两种认证方式见 [ReadMe.md 的“配置文件格式”](../ReadMe.md#配置文件格式)。真实 Token、Key 与账号信息不要提交到 Git。

5. 启动服务。显式指定配置路径，避免依赖默认桌面路径：

   ```powershell
   .\serve-webui.ps1 -Config <config-dir>\cf_config.csv
   .\serve-webui.ps1 -Status
   ```

   默认监听 `127.0.0.1:8600`。需要局域网访问时：

   ```powershell
   .\serve-webui.ps1 -Restart -Lan -Password <password>
   ```

   无口令拒绝绑定 `0.0.0.0`；口令也可通过 `CF_WEB_PASSWORD` 环境变量提供，避免留在命令行历史里。

6. 验证：

   ```powershell
   Invoke-RestMethod http://127.0.0.1:8600/api/v1/meta
   ```

   浏览器打开 `http://127.0.0.1:8600/`，能加载账号列表与域名即可。测试依赖安装后，可再跑：

   ```powershell
   .\tools\web_smoke.ps1 -Port 8601
   ```

   它使用临时假配置启动独立实例，不访问真实 Cloudflare 账号；成功输出 `SMOKE PASS`。

## 3 配置与运行时文件

| 路径 | 作用 | 是否入库 |
|---|---|---|
| `webui/v2/dist/` | 前端构建产物，FastAPI 静态托管 | 否，必须构建 |
| `webui/v2/node_modules/` | 前端构建依赖，仅构建时需要 | 否 |
| `webui.log`、`webui.log.1` | 服务日志，超过 512KB 轮转一份 | 否 |
| `<config-dir>/cf_web.db` | 任务历史与审计 sqlite（WAL） | 否，运行时生成 |
| `<config-dir>/cf_backup/` | 变更前快照默认目录 | 否，运行时生成 |
| `<config-dir>/cf_export/` | 导出文件默认目录 | 否，运行时生成 |
| `<config-dir>/cf_config.csv` 或 `.json` | 账号与默认配置 | 否，含凭据 |

- 配置路径默认取 `CF_CONFIG_PATH`，未设置时用 `C:/Users/<用户名>/Desktop/deploy_configs/cf_config.csv`；`-Config` 与 `--config` 可覆盖。
- 数据库、快照与导出目录都跟随配置文件所在目录，迁移配置时这些运行数据不会自动跟随。
- 页面内设置的出口代理只驻内存，重启后恢复启动参数或直连，不写入配置文件。
- 日志查看：`.\serve-webui.ps1 -Logs -Lines 100`。

## 4 端口与访问

| 端口 | 用途 |
|---|---|
| `8600` | WebUI 默认端口 |
| `8612` | Vite 开发服务器（`npm run dev`，仅开发） |
| `8613` | Vite 预览服务器（`npm run preview`，仅开发） |

- 默认仅监听 `127.0.0.1`，不对外暴露。
- `-Lan` 绑定 `0.0.0.0`，必须设置口令；服务为 HTTP，明文传输，只应在可信局域网使用。对方首次访问可能触发 Windows 防火墙提示，需要放行对应 TCP 端口。
- 同一端口只跑一个实例；多实例可用 `-Port` 指定不同端口，用 `-Ports` 查看。

## 5 升级与回滚

升级前先停服务并备份配置目录中的运行数据：

```powershell
.\serve-webui.ps1 -Stop
Copy-Item <config-dir>\cf_web.db <config-dir>\cf_web.db.bak
```

如目录中存在 `cf_web.db-wal`、`cf_web.db-shm`，一并复制。配置文件和快照目录按同样方式备份。

升级步骤：

```powershell
git pull --ff-only
.\.venv\Scripts\Activate.ps1
pip install -r webui\requirements.txt
npm ci --prefix webui/v2
npm --prefix webui/v2 run build
.\serve-webui.ps1 -Restart
.\serve-webui.ps1 -Status
```

- 后端代码（`webui/backend/`、`start_web_ui.py`、`cloudflare_dns_tool.py`）在进程启动时加载，升级后必须 `-Restart`。
- 前端 `dist` 每次请求从磁盘读取，只改前端时重新构建后刷新页面即可；升级流程统一重启更省判断。
- `cf_web.db` 的缺列由后端启动时自动补齐；仍建议升级前备份。旧库结构升级后不保证能被更旧代码直接读取，回滚时如遇数据库错误，恢复备份的 `cf_web.db` 后再启动。

回滚到上一个提交：

```powershell
git checkout <previous-commit>
.\.venv\Scripts\Activate.ps1
pip install -r webui\requirements.txt
npm ci --prefix webui/v2
npm --prefix webui/v2 run build
.\serve-webui.ps1 -Restart
```

## 6 验证与测试

| 目的 | 命令 | 前置 |
|---|---|---|
| 服务状态与接口 | `.\serve-webui.ps1 -Status` | 服务已启动 |
| API 冒烟（假配置） | `.\tools\web_smoke.ps1 -Port 8601` | Python 运行时依赖；端口空闲 |
| 后端契约测试 | `python -m unittest cf_api.tests.test_webui cf_api.tests.test_webui_extra` | 在 `pys` 目录执行 |
| 浏览器验收 | `python webui\v2\tests\browser_accept.py` | 已构建 `dist`；安装 `requirements-dev.txt` 与 Chromium |
| 全量门禁 | `.\tools\verify.ps1` | 开发依赖、Playwright Chromium、已执行 `npm ci` |

`tools\verify.ps1 -SkipVisual` 可跳过浏览器验收，只跑单测、编译、lint、构建与 API 冒烟。

安装 Playwright 浏览器：

```powershell
pip install -r webui\requirements-dev.txt
python -m playwright install chromium
```

## 7 常见问题

| 现象 | 先查 | 处理 |
|---|---|---|
| `ModuleNotFoundError: No module named 'fastapi'` | 当前窗口是否激活虚拟环境 | 激活 `.venv` 后重跑 `pip install -r webui\requirements.txt` |
| `Python 版本过低` 或依赖预检失败 | `python --version` | 安装 Python 3.10+，在正确环境中安装依赖 |
| `前端未构建：... npm run build` | `webui/v2/dist/index.html` 是否存在 | 执行 `npm ci --prefix webui/v2` 与 `npm --prefix webui/v2 run build` |
| `npm ci` 报 Node 版本不满足 `engines` | `node --version` | 升级到 Node `^20.19.0` 或 `>=22.12.0` |
| 启动 5 秒未就绪 | `.\serve-webui.ps1 -Logs -Lines 100` | 按日志处理；常见为依赖缺失、配置路径错误或端口冲突 |
| 端口被占用 | `.\serve-webui.ps1 -Port 8600 -Status`、`-Ports` | 停旧实例、换 `-Port`，或按提示选择空闲端口 |
| 页面能开但接口 404 | 进程启动时间是否早于代码修改 | `.\serve-webui.ps1 -Restart` |
| 返回 401 | 是否设置了口令 | 在页面输入口令，或通过 `CF_WEB_PASSWORD` 启动 |
| 上传文件返回 500 | `python-multipart` 是否安装 | 重装 `webui\requirements.txt` |
| 局域网无法访问 | 是否使用 `-Lan` 且设置了口令 | 检查绑定地址、口令和防火墙端口放行 |

## 8 平台边界

- Windows 是当前验证平台；`serve-webui.ps1` 的 `-Status`、`-Logs`、`-Restart`、`-Lan` 等管理能力都依赖 PowerShell。
- Linux/macOS 可尝试 `python start_web_ui.py --config <config> --port 8600` 前台运行，但未在本仓库验收；不要假定 `serve-webui.ps1` 或 Windows 路径默认值可用，启动时必须显式传 `--config`。
- 对外长期运行、开机自启、反向代理与 HTTPS 不在当前部署范围；需要时先补相应 Runbook 与验证，不直接套用本机 Hidden 进程方式。
