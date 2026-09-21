# AGENTS.md — PS 模块集（CxxuPsModules）agent 入口

## 先读文档，再碰代码
本目录 `docs/` 是唯一真相源（若代码注释与文档矛盾，以文档为准，顺手修注释）：
1. `docs/Agent-Handoff.md` —— 踩坑清单（必读，尤其 §3；能省至少一次返工）
2. `docs/Module-Conventions.md` —— 命名/编码铁律（§1 单横线、§8 换行）+ 文档语言（§11 术语、§12 行文）
3. `docs/Module-Map.md` —— 54 模块画像（找功能先查表，别 grep 大海捞针）
4. `docs/Feature-Guide.md` —— 用户手册 + FAQ（动用户可见行为先看）
5. `docs/Startup-Optimization.md` —— 性能基线 + 搬迁史（动热路径先看基线表）
6. `docs/Deploy-Guide.md` —— 新机部署（仅部署相关）
7. `docs/Live-Versions.md` —— 并排版本活件设计专章（动 dll/同步/加载先看）

改完代码必看 `Agent-Handoff.md §5` 要不要同步文档。

## 红线
- 只动 `PS/` 与仓库根；`wp/` 是用户领地不动；`PS/Pwsh/demo.ps1` 的删除不是你干的，别碰。
- 换行：存量不动，新文件 CRLF；提交前必跑 `git diff` vs `git diff --ignore-cr-at-eol` 对照。
- 中文用户：中文回复；行内 `pwsh -Command` 引号必炸，复杂命令写 `.ps1` 再 `-File` 执行。
- 提交/推送/PR：用户明确说才做；提交后必验 HEAD（`git show HEAD:<关键文件>` + 状态干净）。

## 根目录旧文档
`../PwshModuleByCxxu.md` 描述的是旧结构，仅考古用；现状以本目录 `docs/` 为准。
