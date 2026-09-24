# 文档入口地图

> 本目录 8 份文档。**不要按顺序全读**——先看"你是谁"，走对应路径；其余按需检索。
> 全程正式语言，术语以 `Module-Conventions.md §11` 为准。

## 按任务分流

| 你要做什么 | 读什么（按顺序） | 解决什么 |
|---|---|---|
| 新机部署 | `Deploy-Guide.md`（极简版 2 条命令先行）→ `Feature-Guide.md §1/§11` | 从零到可用 + 手动项查漏 |
| 日常使用 | `Feature-Guide.md §2`（命令表）→ §7/§8/§10（补全）→ §9（dll 四件套） | 查命令、配补全、管更新 |
| 出问题先看 | `doctor`（命令）→ `Feature-Guide.md §6/§8`（FAQ）→ `Agent-Handoff.md`（踩坑） | 定位→自助→避坑 |
| 加模块/加函数 | `Feature-Guide.md §3` → `Module-Conventions.md`（§1 目录、§2 命名、§7 manifest）→ `Module-Map.md`（找位置） | 一次做对，不返工 |
| 搞懂 dll/同步 | `Live-Versions.md`（设计专章，9 节 + 4 图）→ `Deploy-Guide.md §13` | 结构、流程、命令分工 |
| 非 Windows 系统 | `Feature-Guide.md §12`（`doctor` 会标平台行） | 哪些可用、哪些是 Windows 专属 |
| 5.1 兼容 | `Feature-Guide.md §13`（B 档 62 模块，`init` 零失败） | 降级清单、加码禁区 |
| 启动太慢 | `Startup-Optimization.md`（基线表 + 搬迁史）→ `init -Timing` | 基线对比，定位慢项 |
| 写 agent/自动化 | `AGENTS.md`（仓库根入口）→ `Agent-Handoff.md §3`（必读） | 红线、换行、提交规范 |

## 全表（一句话版）

| 文档 | 一句话 | 篇幅 |
|---|---|---|
| `Feature-Guide.md` | 用户手册：命令表、补全、dll 管理、FAQ、手动启用清单（§11） | 约 230 行 |
| `Deploy-Guide.md` | 新机部署：一键脚本、分步详解、多设备差异、更新到新版本（§13） | 约 140 行 |
| `Live-Versions.md` | 并排版本活件设计专章：结构、指针协议、流程、故障、命令分工 | 约 130 行 + 4 图 |
| `Agent-Handoff.md` | 踩坑编年史：每个决策的起因、实测、教训（#24 起为现行区，之前多为历史） | 约 190 行 |
| `Module-Conventions.md` | 规范：命名/编码铁律 + 文档语言（§11 术语表、§12 行文风格） | 约 130 行 |
| `Module-Map.md` | 67 模块画像表：找功能先查表，别 grep 大海捞针 | 约 120 行 |
| `Startup-Optimization.md` | 性能基线 + 搬迁史：动热路径先看基线表 | 约 430 行 |
| `AGENTS.md`（仓库 `PS/` 根） | agent 入口：红线、换行、提交规范 | 约 20 行 |

## 检索方法

- 找命令：`Module-Map.md` 按模块查，或会话里 `Get-Command <片段>` + `Get-Help <命令>`（帮助与文档同源）。
- 找故障：先跑 `doctor`（它会点名文档章节），再 `rg` 关键字搜 `docs/`。
- 找决策理由：`Agent-Handoff.md` 按号查；现行口径以 `Live-Versions.md` + §11 + §9 为准（见 Handoff #30）。
- 名词不懂：`Module-Conventions.md §11` 术语表。
