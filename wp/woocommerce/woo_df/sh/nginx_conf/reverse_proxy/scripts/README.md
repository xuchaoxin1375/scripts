# scripts/ 脚本说明

> 指引页：细节以各脚本 `--help` 和上级 `docs/` 为准，不在此复制。

## 脚本一览

| 脚本 | 用途 | 主要产物 / 动作 |
| --- | --- | --- |
| `base.sh` | 部署单机反代网关，两种模式：`-G simple`（全机单入口转同一上游 `-i`）；`-G hostmap`（全局 Host→Backend 映射表） | `reverse_to_a.conf` / `gateway.conf` + `gateway/` |
| `multi.sh` | 多出口 IP 反代（`B_IP->A_IP`），upstream 与日志按 `B+A` 双 IP 命名；`--dev` 只预览不写文件 | `reverse_multi_ip.conf`（`--conf-name` 可改名） |
| `tenants.sh` | 多租户：每租户独立 listen IP + 自有 `routes.map`，未知 Host 回 444 | `tenant-common/hostmap/server.conf` + `tenants/<id>/routes.map` |
| `clean.sh` | 清理 / 巡检各模式残留配置，防止 `listen` 抢口与 include 冲突；先 `--status` 只看不动 | 默认只删被 include 目录中的冲突源 |
| `check_ports.sh` | 端口监听与防火墙放行检查（`--ports`）/ 放行（`--fix`）；部署脚本重载后自动调用，也可单独跑或 `source` 复用函数 | 退出码 0 通过、1 阻断、2 用法错误 |

## 模式路由

- 单 IP、所有域名到同一后端 → `base.sh -G simple`
- 单 IP、多域名各到不同后端 → `base.sh -G hostmap`
- 多出口 IP、与后端一一对应 → `multi.sh -m 'B_IP->A_IP'`
- 多 IP、按租户隔离路由 → `tenants.sh`
- 切换模式 / 下线前 → 先跑 `clean.sh --status`

## 仓库模板（上一级目录）

- `gateway.simple.template.conf` → 部署为 `reverse_to_a.conf`（simple）
- `gateway.hostmap.template.conf` + `gateway/` → 部署为 `gateway.conf` + `gateway/`（hostmap）

## 文档指引（`../docs/`）

| 文档 | 说明 |
| --- | --- |
| [check_ports@端口检查维护指南.md](../docs/check_ports@端口检查维护指南.md) | 端口检查契约、接入点、交互语义、验证协议（先读） |
| [clean@清理说明.md](../docs/clean@清理说明.md) | 四脚本产物与冲突、清理用法 |
| [multi@配置生成脚本说明.md](../docs/multi@配置生成脚本说明.md) | `multi.sh` 设计说明 |
| [tenants@配置生成脚本说明.md](../docs/tenants@配置生成脚本说明.md) | `tenants.sh` 设计说明 |
| [不同反代模式下(hostmap)nginx目录结构参考.md](../docs/不同反代模式下(hostmap)nginx目录结构参考.md) | `hostmap` 目录结构参考 |

## 验证入口

- 语法：各脚本 `bash -n`；帮助：`--help` 必须可运行。
- 预览：`multi.sh --dev`（不写文件、不 reload）；换模式前 `clean.sh --status`。
