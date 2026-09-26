[toc]

## 关于端口检查的设计说明

`check_ports.sh` 是反代服务器的端口与防火墙巡检工具：确认检查列表端口的本地监听状态与防火墙放行状态，定位阻断点；可选修复模式尝试放行。`base.sh / multi.sh / tenants.sh` 在 `nginx` 重载成功后调用它做部署后验证；未通过时先询问是否放行（默认对象 `80,443`），失败则告警并询问是否继续部署。

路径记号：`R=reverse_proxy` 目录；`S=R/scripts`（`base.sh`、`multi.sh`、`tenants.sh`、`clean.sh`、`check_ports.sh`）；`C/D/L` 沿用 `clean@清理说明.md` 的记号（`C=$NGINX_CONF_HOME`，`D=$NGINX_CONFD`，`L=$NGINX_LOG_DIR`）。

---

## 1. 文件清单

| 文件 | 职责 | 说明 |
| --- | --- | --- |
| `S/check_ports.sh` | 端口监听与防火墙检查，可选修复 | 独立执行或被 `source` 引用；行为契约见 §2 |
| `S/base.sh` | `simple/hostmap` 单入口部署 | 重载后调用端口检查；无 `set -euo pipefail`，新增代码须防御式编写 |
| `S/multi.sh` | 多出口 `B_IP->A_IP` 部署 | 仅重载成功后调用检查；`--no-reload` 时跳过并打印复查命令 |
| `S/tenants.sh` | 多租户网关部署 | 与 `multi.sh` 相同 |
| `S/clean.sh` | 统一清理 | 未接入端口检查（清理后的端口状态含义不定，不做断言） |
| 本文件 | agent 维护指南 | 与 `S/*.sh` 同步更新 |

验证脚本（`verify_check_ports.ps1`、`verify_ports_integration.ps1`、`harness_ports_check.sh`）存放于本机临时目录，不入库。

---

## 2. `check_ports.sh` 行为契约

| 项目 | 约定 |
| --- | --- |
| 默认检查 | `80,443`，协议 `tcp`；仅 `HTTP` 入口（如 Cloudflare Flexible）请用 `--ports 80` |
| 防火墙后端 | 自动检测，优先级 `firewalld → ufw → nft → iptables`；未知记 `none`，状态未知计为未通过 |
| 退出码 | `0` 全部通过；`1` 存在未监听、未放行或未知；`2` 用法错误 |
| 输出形态 | 常规日志；`-q/--quiet` 一行汇总；`--json` 纯 `JSON` 走 `stdout`、日志走 `stderr` |
| 修复模式 | `--fix` 按后端放行，需 `root`；`iptables/nft` 仅运行时生效并提示持久化命令；`--dry-run` 只预览 |

被引用稳定接口（`source` 后仅加载函数，不执行检查）：`is_port_listening`（`0` 已监听/`1` 未监听/`2` 未知）、`is_firewall_open`（`0` 已放行/`1` 未放行/`2` 未知）、`ensure_firewall_port`（需 `FIX_MODE=true`）、`detect_firewall_backend`、`check_single_port`。入口卫哨使用 `return 0` 探测是否被 `source`，以同时兼容 `bash <(curl …)` 直接执行。

---

## 3. 三部署脚本的接入点

| 脚本 | 全局变量 | 调用点 | 跳过条件 |
| --- | --- | --- | --- |
| `base.sh` | 顶部 `PORTS_CHECK_LIST` 等四变量 | `nginx -t && nginx -s reload` 成功后、`exec bash` 之前，`run_ports_check \|\| exit 1` | `--skip-ports-check`；找不到 `check_ports.sh` 时告警跳过 |
| `multi.sh` | 同上 | 重载成功分支内、最终 `完成` 之前 | 同上；另 `--no-reload/--dev/--dry-run` 到达不了调用点，改为打印复查命令 |
| `tenants.sh` | 同上 | 同 `multi.sh` | 同 `multi.sh` |

新增参数（三个脚本一致）：`--ports-check <list>`（默认 `80`）、`--fix-ports <list>`（默认 `80,443`）、`--skip-ports-check`、`--yes`（交互询问一律按确认处理，适用于自动化）。

`check_ports.sh` 定位顺序：`CHECK_PORTS_SCRIPT` 环境变量 → 脚本同目录（`BASH_SOURCE` 解析，进程替换时自动降级）→ `~/sh/nginx_conf/reverse_proxy/scripts/` → `/www/sh/nginx_conf/reverse_proxy/scripts/`。

---

## 4. 交互语义（重点）

`ask_yes_no` 返回三态：`0` 确认、`1` 拒绝（中止部署）、`2` 无法询问。`run_ports_check` 对 `2` 的处理一律是告警并继续，不中断部署；仅 `1` 中止。

- 无法询问的判定必须用真实打开探测（`: < /dev/tty`）。仅 `test -r` 不可靠：无控终端时 `test` 可通过但 `open` 报 `ENXIO`，会把“无人可问”误判为“用户拒绝”，导致非交互部署被错误中止（桩测试曾捕获此缺陷）。
- 交互式 `Ctrl-D`（读取失败）视为拒绝（返回 `1`），不视为无法询问。
- `--yes` 下两次询问均自动确认：自动尝试放行，失败则告警并继续。

---

## 5. 三份 helper 一致性铁律

`base.sh / multi.sh / tenants.sh` 中的端口检查代码块（起止标记 `# ---- 端口与防火墙检查` … `# ---- 端口与防火墙检查结束 ----`）必须字节一致。改一处即改三处，改完运行：

```bash
for f in base multi tenants; do
  sed -n '/# ---- 端口与防火墙检查(复用同目录/,/# ---- 端口与防火墙检查结束/p' "$f.sh" > "/tmp/helper_$f.inc"
done
cmp helper_base.inc helper_multi.inc && cmp helper_multi.inc helper_tenants.inc
```

---

## 6. 防火墙后端速查

| 后端 | 检查方式 | 放行命令 |
| --- | --- | --- |
| `firewalld` | `firewall-cmd --zone=$ZONE --query-port=$port/$proto` | `--permanent --add-port` 后 `--reload` |
| `ufw` | `ufw status` 含 `$port/$proto ALLOW` 且状态 `active` | `ufw allow $port/$proto` |
| `iptables` | `iptables -C INPUT … -j ACCEPT`；无权限或缺规则时按 `-S` 与 `INPUT` 默认策略判定 | `iptables -I INPUT …`（另写 `ip6tables`）；持久化按发行版另行保存 |
| `nft` | `nft list ruleset` 含 `$proto dport $port … accept` | `nft add rule inet filter input …`（表链不符则提示手工处理） |

---

## 7. 验证协议（改完必跑）

1. `bash -n` 三脚本；`shellcheck` 对照基线：只允许存量 `base.sh` 的 `SC2016` 与 `tenants.sh` 的 `SC1111`，新增告警必须清零。
2. `--help` 含新选项；新参数可解析，缺参数时 `multi/tenants` 非零退出。
3. 复跑本机临时目录的 `harness_ports_check.sh`（桩测试：跳过、通过、放行恢复、放行失败继续、缺失检查器、非交互探测）。
4. 换行检查：四个 `.sh` 文件零 `CR`；本指南等 `.md` 新文件为 `CRLF`。
5. 交互式 `y/n` 分支无法离线覆盖，上目标机后人工确认一次。

---

## 8. 换行与提交红线

- 存量文件不动换行；`.sh` 文件必须 `LF`（`CRLF` 在 Linux 报 `$'\r': command not found`）；`.md` 新文件 `CRLF`。不给 `.gitattributes` 加 `text` 声明（会触发全仓归一化假 diff）。
- 提交前跑 `git diff` 与 `git diff --ignore-cr-at-eol` 对照，确认无换行噪音。
- `git add` 只加本次文件，禁止 `-A`（工作区常有无关文件，如仓库根的 `routes.map.txt`）。
- 提交信息 `feat:/fix:/chore:` 加中文简述；提交后验 `HEAD`（`git show HEAD --stat`、抽查关键文件、状态干净）。推送与 `PR` 须用户明确指示。

---

## 9. 已知限制

1. 检查默认只覆盖 `80`：现网各网关配置只监听 `HTTP 80`，`443` 未监听属正常；放行对象默认含 `443`，为后续启用 `TLS` 预留。
2. 放行需要目标机 `root`；无防火墙工具的环境状态记未知，计未通过，需人工确认。
3. `clean.sh` 未接入：清理后的端口状态含义不定（可能被其他配置占用），不做断言。
