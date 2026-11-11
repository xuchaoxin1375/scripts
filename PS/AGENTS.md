# AGENTS.md — PS 模块集（CxxuPsModules）agent 入口

> 全仓入口见根 `../AGENTS.md`（作用范围与全仓红线）；本文件为 `PS/` 工作细则。

## 先读文档，再碰代码
本目录 `docs/` 是唯一真相源（若代码注释与文档矛盾，以文档为准，顺手修注释）：
0. `docs/README.md` —— 文档入口地图（新用户按任务分流，别全读）
1. `docs/Dev-Notes.md` —— agent 决策要点（编码/部署/文档/提交的硬规则与常见坑，日期无关）
2. `docs/Module-Conventions.md` —— 命名/编码铁律（§1 单横线、§8 换行）+ 文档语言（§11 术语、§12 行文、§13 用户文档结构）
3. `docs/Module-Map.md` —— 模块画像（找功能先查表，别 grep 大海捞针）
4. `docs/Feature-Guide.md` —— 用户手册 + FAQ（动用户可见行为先看）
5. `docs/Startup-Optimization.md` —— 性能基线 + 搬迁史（动热路径先看基线表）
6. `docs/Deploy-Guide.md` —— 新机部署（仅部署相关）
7. `docs/Live-Versions.md` —— 并排版本活件设计专章（动 dll/同步/加载先看）

改完代码看 `docs/Dev-Notes.md`「文档与提交」与 `docs/Module-Conventions.md §13`，决定是否同步文档。

## 红线
- 本文件约束 `PS/` 内的改动，跨区工作按根 `AGENTS.md` 执行；`PS/Pwsh/demo.ps1` 的删除不是你干的，别碰。
- 换行：默认忽略 CRLF/LF 差异，不做提交前对照与整文件转换（`.psm1`/`.psd1` 跟随文件原状）；仅 `.sh` 用 LF、`.cmd`/`.bat` 用 CRLF。
- 回复语言与 Windows 命令调用（复杂命令写 `.ps1` 再 `-File`）按 `user-profile` 与 skill `shell-pitfalls` 执行，本文件不重复。
- 用户可见文本（根 `readme.md`、指南、帮助、警告）：遵循 `docs/Module-Conventions.md §11` 用词、`§12` 行文与 `§13` 用户文档结构（正式、规范、严谨）；改用户可见行为先看 `Feature-Guide.md`，改完自查动作三要素（前置条件、执行者、善后）与术语一致；入口文档只放指引不复制正文。
- 提交：默认直接提交全部改动（用户手动改动可询问是否单独提交，分多次提交亦可）；推送/PR 须用户明确指示；提交后必验 HEAD（`git show HEAD:<关键文件>` + 状态干净）。

## 根目录旧文档
`../PwshModuleByCxxu.md` 描述的是旧结构，仅考古用；现状以本目录 `docs/` 为准。
