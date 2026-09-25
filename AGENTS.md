# AGENTS.md — 仓库工作入口（全仓红线）

## 作用范围

- 本仓库活跃区为 `PS/`（PowerShell 模块集）与仓库根文档；`wp/` 为用户领地，一律不碰（不读无关文件、不暂存、不提交）。
- `PS/` 内工作细则见 `PS/AGENTS.md`（进入 `PS/` 工作前必读）；`PS/docs/` 为唯一真相源（代码注释与文档矛盾时以文档为准）。

## 红线（全仓适用）

- 提交/推送/PR：用户明确说才做；提交信息用 `fix:`/`feat:`/`chore:` + 中文简述；提交后必验 HEAD（`git show HEAD:<关键文件>` + 状态干净）。
- 换行：存量文件不动，新文件 CRLF；提交前必跑 `git diff` vs `git diff --ignore-cr-at-eol` 对照。
- 用户可见文本遵循 `PS/docs/Module-Conventions.md §11` 用词与 `§12` 行文（正式、规范、严谨）。
- 中文用户：中文回复；复杂命令写 `.ps1` 再 `-File` 执行，不拼行内 `pwsh -Command` 引号。
