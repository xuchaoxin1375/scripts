# AGENTS.md — 反代网关（reverse_proxy）agent 入口

> 全仓红线见仓库根 `AGENTS.md`；`PS/` 细则见 `PS/AGENTS.md`，与本目录无关时不读。本文件只界定本目录的工作边界与入口指引，细节以 `docs/` 为准，不在此复制。

## 作用范围

- 本目录：`scripts/`（`base.sh`、`multi.sh`、`tenants.sh`、`clean.sh`、`check_ports.sh`）、`docs/`（五份说明）、`gateway/`、`gateway.conf`、`reverse_multi_ip_demo.conf`、`reverse_to_a.conf`。
- 不碰目录外文件；现有文档只读不改，除非任务明确要求。

## 红线（本目录适用）

- 换行：存量文件不动；`.sh` 文件必须 `LF`（`CRLF` 在 Linux 报 `$'\r': command not found`）；`.md` 新文件 `CRLF`。提交前必跑 `git diff` 与 `git diff --ignore-cr-at-eol` 对照。
- 三部署脚本中的端口检查代码块（起止标记内）必须字节一致，改一处即改三处，校验见维护指南 §5。
- `shellcheck` 只允许两处存量告警（`base.sh` 的 `SC2016`、`tenants.sh` 的 `SC1111`）；不整文件重排存量脚本格式。
- 暂存只点名本次文件，禁止 `git add -A`（工作区常有无关文件）。
- 提交信息 `feat:/fix:/chore:` 加中文简述；提交后验 `HEAD`（`--stat`、抽查关键文件、状态干净）；推送与 `PR` 须用户明确指示。

## 文档入口（只放指引）

| 文档 | 说明 |
| --- | --- |
| `docs/check_ports@端口检查维护指南.md` | 端口检查契约、接入点、交互语义、验证协议（先读） |
| `docs/clean@清理说明.md` | 四脚本产物与冲突、清理用法 |
| `docs/multi@配置生成脚本说明.md` | `multi.sh` 设计说明 |
| `docs/tenants@配置生成脚本说明.md` | `tenants.sh` 设计说明 |
| `docs/不同反代模式下(hostmap)nginx目录结构参考.md` | `hostmap` 目录结构参考 |

## 验证入口

- 语法：各脚本 `bash -n`；帮助：`--help` 必须可运行并含新选项。
- 逻辑：本机临时目录 `harness_ports_check.sh`（不入库，丢失后按维护指南 §7 的思路重建）。
- 交互式 `y/n` 分支无法离线覆盖，上目标机后人工确认一次。
