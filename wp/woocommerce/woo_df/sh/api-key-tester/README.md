# KeyLens · API Key 体检站

一站式检测 OpenAI / Anthropic / Gemini 及所有 OpenAI 兼容中转站的 API Key 是否可用。纯本地运行，零依赖，无任何第三方服务器参与。

## 快速开始

**macOS / Linux：**

```bash
./start.sh        # 启动本地后端并自动打开浏览器
./start.sh stop   # 停止
./start.sh status # 查看状态
```

**Windows：**

```bat
start.bat        :: 启动本地后端并自动打开浏览器
start.bat stop   :: 停止
start.bat status :: 查看状态
```

> 未使用脚本时也可手动启动：`node server.js` 后访问 `http://localhost:8899`。

浏览器打开 `http://localhost:8899` 后：

1. 选择服务商（或直接粘贴 API 地址，左侧下拉自动匹配）
2. 粘贴 Key，模型留空会自动选用第一个可用模型
3. 点击「开始体检」，查看报告

> 直接双击 `index.html` 也可以使用（浏览器直连模式），但部分 API 会因 CORS 被浏览器拦截；推荐用脚本启动后端。

## 文件结构

| 文件 | 说明 |
|---|---|
| `server.js` | 本地后端：静态托管 + `/api/test` 服务器通道测试（零依赖，仅内置模块） |
| `index.html` | 前端页面（可直接双击打开，也可由后端托管） |
| `start.sh` | macOS / Linux 一键启动 / 停止 / 查看状态 |
| `start.bat` | Windows 一键启动 / 停止 / 查看状态（cmd 或双击运行） |

## 双测试通道

页面提供「测试通道」切换，自动检测后端并默认使用服务器通道：

| 通道 | 说明 | CORS 影响 |
|---|---|---|
| **服务器测试（推荐）** | 请求由本地后端发出，行为与 curl 完全一致 | 无 |
| **浏览器直连** | 请求直接从浏览器发出 | 服务商未开启 CORS 时会被拦截 |

## 支持的服务商与协议

| 服务商 | 鉴权方式 | 模型列表 | 对话接口 |
|---|---|---|---|
| OpenAI / DeepSeek / Moonshot / 硅基流动 / Groq / OpenRouter / 中转站 | `Authorization: Bearer` | `/models` | `/chat/completions` |
| Anthropic | `x-api-key` 头 + `anthropic-version` | `/models` | `/messages` |
| Google Gemini | URL 参数 `?key=` | `/models` | `/models/{模型}:generateContent` |

## 功能

- **体检报告**：验证 Key → 获取模型列表 → 对话测试三步流程，含响应耗时、可用模型数
- **智能错误解析**：401 / 403 / 404 / 429 / 网络错误自动翻译为可读原因，并提取服务商结构化错误信息
- **curl 等价复现**：每次请求都在报告中给出等价 curl 命令，可复制到终端验证
- **批量测试**：模型框用英文逗号分隔，一次测多个模型
- **导出代码**：curl / Python (requests) / Python (官方 SDK) / JavaScript (fetch)，按所选服务商协议生成，带语法高亮、行号，支持复制与下载
- **从 curl 导入**：粘贴任意 curl 命令，自动识别地址 / Key / 模型并回填表单
- **历史记录**：自动保存测试记录（本机 localStorage），点击回填，未保存 Key 时自动提示
- **主题系统**：6 套主题（浅色/极光紫/深海蓝/樱粉/翡翠绿/熔岩橙），切换带涟漪动画，自动记忆

## 关于 CORS

浏览器出于同源策略，只允许网页读取"同源"服务器的响应。若 API 服务商未返回 CORS 授权头，浏览器会丢弃响应——这就是"curl 能用、网页不行"的原因，与 Key 是否正确无关。

解决办法（按推荐顺序）：

1. **使用本工具自带后端**（`./start.sh`，服务器通道，彻底解决）
2. **换用支持 CORS 的服务商**（OpenAI / Anthropic / Google 等官方接口普遍支持）
3. **终端 / 后端调用**（页面「导出代码」生成 curl / Python / JS）
4. **本地 CORS 代理**（如 `npx local-cors-proxy --proxyUrl 你的域名 --port 8010`）
5. **浏览器插件**（仅调试用，勿依赖处理敏感数据）

## 隐私说明

- Key 只保存在本机浏览器的 `localStorage` 中，仅点击体检时才发送到对应 API 地址（服务器通道下发送给本地后端，由后端原样转发）
- 无任何第三方服务器、无统计、无追踪
- 可随时取消「记住 Key」并清空历史记录

## 环境要求

- Node.js ≥ 12（`server.js` 仅用内置 `http` / `https` / `fs` 模块，无需 `npm install`）
- macOS / Linux：`start.sh`
- Windows：`start.bat`（cmd 或资源管理器双击，通过 PowerShell 在后台拉起 Node 进程）
