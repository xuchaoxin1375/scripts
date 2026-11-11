# 文档入口地图

> 本目录文档按用途分工。**不要按顺序全读**——先看"你是谁"，走对应路径；其余按需检索。
> 全程正式语言，术语以 `Module-Conventions.md §11` 为准。

## 按任务分流

| 你要做什么 | 读什么（按顺序） | 解决什么 |
|---|---|---|
| 新机部署 | `Deploy-Guide.md`（保存脚本后按参数运行）→ `Feature-Guide.md §1/§11` | 从零到可用 + 手动项查漏 |
| 日常使用 | `Feature-Guide.md §2`（命令表）→ §7/§8/§10（补全）→ §9（dll 四件套 + Tab 自查） | 查命令、配补全、管更新 |
| 只启用补全（新机或已有环境） | `Deploy-Guide.md §5`（`Deploy-CompletionStack`）→ `Feature-Guide.md §7/§9`（开关/自查） | 默认只装核心活件；argc、PSFzf、fzf/zoxide 等按需加 `-Include*` |
| 统一管理组件启停与选项 | `Feature-Guide.md §7`（`Get/Enable/Disable-CxxuComponent`、`Set-CxxuComponentOption`）→ `PS/Init/components.psd1` | SchemaVersion=2 配置、组件清单、旧版平坦键兼容 |
| 比较或接入 carapace 补全 | [Feature-Guide](Feature-Guide.md) 的「carapace（可选，非默认）」→ [Deploy-Guide](Deploy-Guide.md) 的「可选：carapace」；bash 侧见 [bash/carapace/README.md](../../bash/carapace/README.md) | git/argc/git-completion 对比、`Deploy-Carapace`、`PsCarapace` 配置、`Set-GitCompletionSource`、GitHub Release/scoop 安装渠道、5.1 适配（零宽字符、环境变量截断、UTF-8/空参数、去 ANSI）与 pwsh 7.6 空结果补丁；Git Bash/Linux/macOS bash 的 rc 选择、登录 shell 与未验证项 |
| 启停或检查 argc 参数补全 | [Argc-Completions-Deploy](Argc-Completions-Deploy.md#4-启停与状态) → `Feature-Guide.md` 的补全章节 | 本会话/持久启停、停止自动提示、查看注册状态 |
| 查功能依赖与安装状态 | `Feature-Dependencies.md` → `Get-CxxuDependencyReport` | 哪些功能需要外部组件、缺什么、怎么补 |
| 出问题先看 | `doctor`（命令）→ `Feature-Guide.md §9`（dll/活件/Tab 补全排查）/§6/§8（FAQ）→ `Dev-Notes.md`（常见坑） | 定位→自助→避坑 |
| macOS 上 pwsh 假死或残留进程烧 CPU | [macOS-Pwsh-Runtime.md](macOS-Pwsh-Runtime.md) | 现场判据、清理步骤与防复发 |
| macOS 上 shell 配置接线、恢复 mamba/conda | [macOS-Shell-Setup.md](macOS-Shell-Setup.md) | profile 链路、停用范围、实测变化与恢复命令 |
| 补全不工作/变慢 | `doctor`（单层用 `doctor -Feature Tab` 或 `doctor -Feature Argc`）→ `Feature-Guide.md §9`「加载失败排查」+「Tab 补全自查」→ §8（ListView 候选）/§10（全景） | 先分清 Tab/ListView/参数层，再查开关/缓存/活件 |
| 复验 Tab 补全的实际界面 | [Interactive-Console-Verification.md](Interactive-Console-Verification.md) | 启动真实窗口、注入按键、读屏与截图取证；含 Git Bash 的启动差异 |
| 加模块/加函数 | `Feature-Guide.md §3` → `Module-Conventions.md`（§1 目录、§2 命名、§7 manifest）→ `Module-Map.md`（找位置） | 一次做对，不返工 |
| 搞懂 dll/同步 | `Live-Versions.md`（设计专章）→ `Deploy-Guide.md §13` | 结构、流程、命令分工、5.1 Tab 产物 |
| 非 Windows 系统 | `Feature-Guide.md §12`（`doctor`/readiness 按平台过滤并汇总已跳过项） | 哪些可用、哪些是 Windows 专属 |
| 5.1 兼容 | `Feature-Guide.md §13`（B 档兼容集，`init` 零失败；Tab 补全走 5.1 专用活件） | 降级清单、加码禁区 |
| 启动太慢 | `Startup-Optimization.md`（基线表 + 搬迁史）→ `init -Timing` | 基线对比，定位慢项 |
| 写 agent/自动化 | `AGENTS.md`（仓库根入口）→ `Dev-Notes.md`（决策要点，必读） | 红线、换行、提交规范 |

## 全表（一句话版）

| 文档 | 一句话 | 规模 |
|---|---|---|
| `Feature-Guide.md` | 用户手册：命令表、补全、dll 管理、FAQ、手动启用清单（§11） | 长（手册主体） |
| `Feature-Dependencies.md` | 功能依赖清单：按功能列外部组件、生成物、状态与安装建议 | 中 |
| `Deploy-Guide.md` | 新机部署：一键脚本、分步详解、多设备差异、更新到新版本（§13） | 中 |
| [Argc-Completions-Deploy.md](Argc-Completions-Deploy.md) | argc-completions 部署、更新、启停与排障 | 中 |
| [Interactive-Console-Verification.md](Interactive-Console-Verification.md) | 模拟用户按键复验 Tab 补全（pwsh 与 Git Bash）：真实窗口、按键注入、读屏与截图 | 中 |
| `Live-Versions.md` | 并排版本活件设计专章：结构、指针协议、流程、故障、命令分工、5.1 Tab 产物 | 中，含结构图与流程图 |
| `Dev-Notes.md` | agent 决策要点：编码/部署/文档/提交的硬规则与常见坑，日期无关 | 短 |
| `Module-Conventions.md` | 规范：命名/编码铁律 + 文档语言（§11 术语表、§12 行文风格） | 中 |
| `Module-Map.md` | 模块画像表：找功能先查表，别 grep 大海捞针 | 中 |
| `Startup-Optimization.md` | 性能基线 + 搬迁史：动热路径先看基线表 | 长（历史日志） |
| [macOS-Pwsh-Runtime.md](macOS-Pwsh-Runtime.md) | macOS 运行层故障：假死与残留 pwsh 空转的判据、清理与防复发 | 短 |
| [macOS-Shell-Setup.md](macOS-Shell-Setup.md) | macOS shell 配置现状：profile 接线、mamba/conda 停用记录、实测变化与恢复方式 | 短 |
| `AGENTS.md`（仓库 `PS/` 根） | agent 入口：红线、换行、提交规范 | 短 |

## 检索方法

- 找命令：`Module-Map.md` 按模块查，或会话里 `Get-Command <片段>` + `Get-Help <命令>`（帮助与文档同源）。
- 找故障：先跑 `doctor`（它会点名文档章节），再 `rg` 关键字搜 `docs/`。
- 找决策理由：先查本目录对应主题文档；跨主题的硬规则与坑看 `Dev-Notes.md`。不按日期或编号检索。
- 文档自检：改完检查本地链接可解析、示例命令与当前源码/参数一致。
- 名词不懂：`Module-Conventions.md §11` 术语表。
