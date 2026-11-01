# uptime_checks — 反向代理节点与业务页面拨测

一组低依赖的主动拨测脚本，用于发现反向代理节点、经节点回源的业务页面和公网入口是否可用，并通过邮件发出故障、恢复与持续故障提醒。

脚本只做观察与通知：不重启服务、不切换线路、不修改代理配置，也不采集主机资源指标。

## 适用范围

| 纳入首期 | 明确不做 |
| --- | --- |
| 指定节点的代理自身健康检查 | 自动重启、切线路、改 DNS |
| 经指定节点回源的代表性业务页面 | 全站点、全业务流程遍历 |
| 公网域名入口检查 | 多地域、多运营商视角 |
| 连续失败防抖与恢复通知 | 秒级告警、电话级值守 |
| 邮件通知与失败重试 | 本地邮件服务器、多渠道机器人 |
| 事件记录与维护静默 | 网页面板、数据库、主机 Agent |

后端服务器直连检查属于后续扩展，当前版本不提供。

## 运行条件

| 依赖 | 说明 |
| --- | --- |
| Linux 主机 | 单台，长期运行；时间和时区应正确 |
| Bash 4 及以上 | 使用关联数组等 Bash 4 特性 |
| systemd 或 cron | 二选一，负责每分钟触发；不要求 systemd |
| curl | 发起 HTTP 探测与 SMTP 投递，需支持 HTTPS 与 SMTP 协议 |
| coreutils、grep、sed、awk | 系统自带即可 |
| util-linux 的 flock | 防止相邻两轮并发执行 |
| GNU date | 解析维护窗口时间 |
| 一个 SMTP 发信账号 | 复用既有邮箱服务，不自建邮件服务器 |

不依赖 Docker、数据库、jq、网页面板或目标机 Agent。

## 检查分层

| `kind` | 目标 | 判定方式 | 主要用途 |
| --- | --- | --- | --- |
| `node` | 指定节点的代理自身健康接口 | 锚定节点地址，断言状态码与可选正文 | 判断节点与代理是否在响应 |
| `biz` | 经指定节点回源的代表性页面 | 锚定节点地址，断言状态码与可选正文 | 判断该节点到源站的链路是否可用 |
| `public` | 用户实际访问的公网域名 | 走正常 DNS，断言状态码与可选正文 | 判断用户入口是否正常 |

三类结果的结论不能互相替代：

- 代理自身健康，不代表回源业务正常。
- 公网入口正常，在有 CDN 时也不代表某个指定节点正常。
- 指定节点正常，不能证明其他地区或运营商可访问。

**探测锚定方式**：`node` 与 `biz` 需要填写 `address`，脚本用 `--resolve` 把域名固定到该地址，同时保留 URL 中的域名作为 TLS SNI 与 `Host`。这样不会因 DNS 轮询或 CDN 调度而测到别的节点。

**协议按实际拓扑配置**：直接承接 HTTPS 的节点查 443；Cloudflare 回源 HTTP 的节点查 80。不要为了统一格式强制补 443，否则会把正常节点误判为故障。

**健康路径随模板不同**：常见路径为 `/__gateway_health`、`/__b_health`、`/__tenant_health`，对应固定响应分别包含 `gateway ok`、`b nginx ok`、`gateway ok`。按节点实际配置填写，正文断言只取稳定短串，不要整段复制响应，避免把地址映射带入邮件。`hostmap` 模式对未登记 `Host` 可能直接返回 444，此时必须填写 `host_header`。

**TLS 校验默认开启**，脚本不提供跳过证书校验的开关。私有 CA 通过 `ca_bundle` 指定证书文件。

**不跟随重定向**：`expect_status` 与服务器返回的首个状态码比较。确需接受 301 或 302 时，把 `expect_status` 改成对应值，不要依赖自动跳转。

**正文断言**：`expect_body` 使用固定字符串匹配响应正文。它适合确认页面确实由应用返回，而不是静态兜底页、缓存页或挑战页。不要填写随机内容或会随请求变化的文本。单次响应最多读取 1 MiB，超出时该检查按失败处理。

## 文件清单

| 文件 | 作用 |
| --- | --- |
| `probe.sh` | 检查调度、状态判定、事件记录、通知入队与重试 |
| `notify-email.sh` | 读取消息并通过 SMTP 投递 |
| `checks.tsv.example` | 检查项配置示例 |
| `maintenance.tsv.example` | 维护窗口示例 |
| `notify.env.example` | 邮件配置示例 |
| `systemd/uptime-probe.service` | 单轮执行单元 |
| `systemd/uptime-probe.timer` | 每分钟触发 |

运行数据默认写入 `/var/lib/uptime-checks`；使用 systemd 时由 `StateDirectory` 创建并授权，使用 cron 时需按安装步骤提前创建并授权。

## 安装

以下步骤以 `/opt/uptime_checks` 为安装目录、`uptime` 为运行用户。目录和用户可按实际情况调整，调整后同步修改 systemd 单元。

```sh
sudo useradd --system --home /var/lib/uptime-checks --shell /usr/sbin/nologin uptime
sudo install -d -m 755 /opt/uptime_checks
sudo cp probe.sh notify-email.sh checks.tsv.example maintenance.tsv.example notify.env.example README.md /opt/uptime_checks/
sudo cp -r systemd /opt/uptime_checks/
cd /opt/uptime_checks
sudo cp checks.tsv.example checks.tsv
sudo cp maintenance.tsv.example maintenance.tsv
sudo cp notify.env.example notify.env
sudo chmod 755 probe.sh notify-email.sh
sudo chown -R root:root /opt/uptime_checks
sudo chown uptime:uptime notify.env
sudo chmod 600 notify.env
sudo install -d -m 700 -o uptime -g uptime /var/lib/uptime-checks
sudo cp systemd/uptime-probe.service systemd/uptime-probe.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable uptime-probe.timer
```

这里只启用开机自启，不立即开始探测。先完成配置校验与测试邮件，再按“启用定时器”一节启动。使用 cron 时跳过本节最后的两个 `systemctl` 命令，改按“使用 cron 代替 systemd”配置，并确认定时器未启用。

`checks.tsv`、`maintenance.tsv` 与 `notify.env` 已在 `.gitignore` 中排除，避免把真实节点和凭据提交到仓库。

脚本文件必须保持 LF 换行。在 Windows 上编辑后，如出现 `$'\r': command not found`，先转换换行再部署。

## 配置检查项

`checks.tsv` 使用制表符分隔，共 11 列，空字段必须保留制表符占位。以 `#` 开头的行和空行会被忽略。

| 列 | 字段 | 说明 |
| --- | --- | --- |
| 1 | `id` | 检查项唯一标识，只允许字母、数字、点、下划线和连字符 |
| 2 | `kind` | `node`、`biz` 或 `public` |
| 3 | `group` | 告警分组名；同一节点的检查使用同一分组，便于合并通知 |
| 4 | `url` | 完整 HTTP 或 HTTPS 地址，可含路径与查询串 |
| 5 | `address` | 节点地址；`node` 与 `biz` 必填，`public` 必须留空 |
| 6 | `host_header` | 可选，覆盖请求的 `Host`；为空时使用 URL 中的域名 |
| 7 | `expect_status` | 期望的三位状态码，例如 `200` |
| 8 | `expect_body` | 可选，响应正文中必须出现的固定字符串 |
| 9 | `timeout` | 单次请求超时秒数，1 到 120 |
| 10 | `ca_bundle` | 可选，自定义 CA 证书路径 |
| 11 | `enabled` | `1` 启用，`0` 停用 |

示例：

```text
node-a-health	node	group-a	http://www.example.com/__gateway_health	192.0.2.10	www.example.com	200	gateway ok	8		1
node-a-biz	biz	group-a	http://www.example.com/	192.0.2.10	www.example.com	200	示例商品	8		1
public-entry	public	public-entry	https://www.example.com/			200	示例商品	8		1
```

字段含义与取舍：

- **`group` 决定告警粒度**。同一节点的健康检查与回源检查放同一分组，故障时合并为一封邮件；公网入口单独分组，避免和节点结论混在一起。
- **`expect_body` 是业务判据的关键**。只断言 200 时，静态兜底页、缓存页和挑战页都可能通过；代表性页面应填写稳定标记。
- **`address` 只支持 IPv4 或普通域名**，当前版本不支持 IPv6 字面量。
- **`ca_bundle` 用于私有 CA**。公共证书无需填写。

修改配置后先执行校验，再交给定时器：

```sh
sudo -u uptime /opt/uptime_checks/probe.sh --check-config
```

校验会报告字段数、类型、重复 `id`、地址与时间格式问题。

## 维护窗口

`maintenance.tsv` 每行三个字段：作用域、开始时间、结束时间。作用域可以是检查项 `id`、分组名或 `*`。时间为本机时区，格式为 `YYYY-MM-DD HH:MM`。

```text
group-a	2026-11-02 02:00	2026-11-02 03:00
```

窗口内的行为：

- 检查照常执行，失败会写入事件记录，同一检查项在一个窗口内只记录首次失败和恢复。
- 连续失败与连续成功计数被重置，避免窗口结束瞬间补发旧故障。
- 不发送故障、恢复或提醒邮件。
- 窗口结束后重新累计，至少需要再次达到失败阈值才会告警。

维护窗口不会自动识别变更，也不会因为窗口结束而补发历史故障。

## 邮件通知

默认读取脚本目录下的 `notify.env`。使用 `--config-dir` 时，如果配置目录内存在 `notify.env`，会优先使用该文件；也可以用 `NOTIFY_ENV` 显式指定路径。

`notify.env` 字段：

| 字段 | 必需 | 说明 |
| --- | --- | --- |
| `SMTP_URL` | 是 | 例如 `smtps://smtp.example.com:465` |
| `SMTP_USER` | 否 | 用户名；与 `SMTP_PASS` 成对出现 |
| `SMTP_PASS` | 否 | 密码或授权码；不要使用邮箱登录密码 |
| `SMTP_STARTTLS` | 否 | 值为 `1` 时要求 STARTTLS，适用于 `smtp://` 入口 |
| `SMTP_CA_BUNDLE` | 否 | 私有 CA 证书路径 |
| `MAIL_FROM` | 是 | 发件人地址 |
| `MAIL_TO` | 是 | 收件人地址，多个用逗号分隔 |
| `MAIL_TIMEOUT` | 否 | 投递超时秒数，默认 30 |

先在目标主机实际发送一封测试邮件：

```sh
sudo -u uptime /opt/uptime_checks/notify-email.sh --test
```

测试成功前，不要认为邮件通道可用。常见限制包括服务商要求授权码、限制发信频率、只允许指定端口，或把自动邮件投入垃圾箱。

通知策略：

- 分组由正常转为故障时发送一封故障邮件。
- 分组恢复时发送一封恢复邮件，包含故障持续时间。
- 持续故障每 60 分钟提醒一次，间隔可通过 `UPTIME_REMIND_SECONDS` 调整。
- 同一分组内的关联失败合并，不按检查项逐封发送。
- 邮件正文只包含分组、检查项标识、检查类型、状态码、耗时和结果代码，不回显节点地址、完整 URL 或健康接口原始响应。

投递可靠性：

- 通知先写入状态目录下的 `queue/`，再调用发送程序。
- 发送成功才删除队列文件；失败会保留并增加尝试次数。
- 重试间隔从 1 分钟开始翻倍，最长 30 分钟；达到 20 次后移入 `queue/failed/` 并记录事件。
- 这避免了“先更新状态、发送失败后不再补发”的缺口。

### 启用定时器

配置校验和测试邮件都通过后，再启动定时器：

```sh
sudo systemctl start uptime-probe.timer
sudo systemctl list-timers uptime-probe.timer
```

## 使用 cron 代替 systemd

脚本只要求能每分钟执行一次 `probe.sh --once`，不依赖 systemd。没有 systemd、或希望复用现有 cron 时使用本节。**systemd 定时器与 cron 只能启用一种**，同时启用会让检查频率翻倍，更容易提前达到失败阈值。

以 `uptime` 用户安装 crontab：

```sh
sudo crontab -u uptime -e
```

写入以下内容：

```cron
PATH=/usr/local/bin:/usr/bin:/bin
MAILTO=""
* * * * * /opt/uptime_checks/probe.sh --once --quiet >> /var/log/uptime-checks.log 2>&1
```

各部分的含义：

- `PATH`：cron 的环境变量很少，显式包含 curl、flock 所在目录。
- `MAILTO=""`：不让 cron 把脚本输出再发一封邮件；故障邮件由脚本自己的 SMTP 通道发送。
- `--quiet`：抑制每分钟的逐项 INFO 输出，只保留警告与错误。事件记录和邮件不受影响。
- `>> /var/log/uptime-checks.log`：保存少量运行告警，便于排查；若不需要，可改为 `>/dev/null 2>&1`。
- 默认状态目录仍是 `/var/lib/uptime-checks`。自定义目录时在 crontab 顶部加 `UPTIME_STATE_DIR=/path`，或给命令加 `--state-dir`。

日志会随 cron 每分钟追加。建议配置 logrotate，避免长期增长：

```text
/var/log/uptime-checks.log {
  weekly
  rotate 8
  compress
  missingok
  notifempty
  create 0640 uptime adm
}
```

把这段保存为 `/etc/logrotate.d/uptime-checks`，并按实际用户组调整 `create`。

确认 cron 已生效：

```sh
sudo crontab -u uptime -l
sudo tail -n 20 /var/log/uptime-checks.log
sudo tail -n 20 /var/lib/uptime-checks/events.log
```

cron 的调度精度是分钟级，与默认阈值配合仍是连续 3 轮、约 3 分钟判定故障。相邻两轮重叠时，`probe.sh` 会用 `flock` 跳过本轮，不会并发探测。

如果之前启用过 systemd 定时器，先停用：

```sh
sudo systemctl disable --now uptime-probe.timer
```

## 判定与调度

| 项目 | 默认值 | 调整方式 |
| --- | --- | --- |
| 执行间隔 | 每分钟 | systemd 定时器或 cron |
| 故障阈值 | 连续失败 3 轮 | `UPTIME_FAIL_THRESHOLD` |
| 恢复阈值 | 连续成功 2 轮 | `UPTIME_RECOVER_THRESHOLD` |
| 单次请求超时 | 每项配置 | `checks.tsv` 第 9 列 |
| 持续故障提醒 | 60 分钟 | `UPTIME_REMIND_SECONDS` |
| 事件保留 | 90 天、最多 20000 行 | `UPTIME_RETENTION_DAYS`、`UPTIME_EVENT_MAX_LINES` |

正常调度且邮件通道可用时，故障告警通常在 3 到 5 分钟内发出。这是目标，不是投递时限保证；单轮超时、系统负载和邮件服务都会影响实际时间。

同一时刻只允许一轮运行。上一轮未结束时，下一轮直接跳过并记录警告，不会并发探测。

## 状态与事件

状态目录结构：

| 路径 | 内容 |
| --- | --- |
| `check.<id>.*` | 单个检查项的连续计数、状态、结果代码与耗时 |
| `group.<group>.*` | 分组状态、故障开始时间与最近提醒时间 |
| `events.log` | 追加写入的事件记录，字段为 UTC 时间、事件、分组、详情 |
| `queue/` | 待发送通知 |
| `queue/failed/` | 重试耗尽的通知 |
| `lock` | 防止并发执行的锁文件 |

主要事件包括 `group_down`、`group_up`、`reminder`、`notify_ok`、`notify_fail`、`notify_dead`、`maintenance_fail`、`maintenance_recovered` 和 `maintenance_suppressed`。

事件记录每天裁剪一次，删除超过保留期或超出最大行数的旧记录；当前状态不受裁剪影响。

查看方式：

```sh
sudo tail -n 50 /var/lib/uptime-checks/events.log
sudo journalctl -u uptime-probe.service -n 100 --no-pager
sudo ls -l /var/lib/uptime-checks/queue
```

## 手动执行

```sh
# 只校验配置，不发起探测
sudo -u uptime /opt/uptime_checks/probe.sh --check-config

# 执行一轮探测并输出结果，不写状态、不发通知
sudo -u uptime /opt/uptime_checks/probe.sh --dry-run

# 执行一轮正式检查，效果与定时器一致
sudo -u uptime /opt/uptime_checks/probe.sh --once
```

手动执行时不要用 root 写入生产状态目录，否则 `uptime` 用户后续可能无法更新状态。需要临时试验时，用 `--state-dir` 指向临时目录：

```sh
sudo -u uptime /opt/uptime_checks/probe.sh --once --state-dir /tmp/uptime-test
```

`--notify-cmd` 可指定替代通知程序，便于验证队列与重试逻辑；该程序从标准输入读取“首行主题、其余正文”的消息。

退出码：

| 码 | 含义 |
| --- | --- |
| 0 | 本轮执行完成，或配置检查通过 |
| 1 | 配置、通知程序或运行环境错误 |
| 2 | 参数用法错误 |

检查目标不可用不会让进程返回非零；故障通过状态、事件和邮件表达，避免定时器把“目标故障”误报为“任务失败”。

## 验收

在正式启用定时器前，至少完成以下核对：

- `--check-config` 通过，错误配置能被拒绝。
- `--dry-run` 输出中包含 `node`、`biz`、`public` 三类结果，且都使用实际拓扑的协议与端口。
- 至少一个节点健康检查与一个经节点回源检查通过，正文断言使用真实标记。
- 测试邮件实际到达收件箱，且未被投入垃圾箱。
- 用一个非生产目标验证故障与恢复通知，不向生产节点注入故障。
- 维护窗口内的失败不发送邮件，窗口结束后不会立即补发。
- `events.log` 能读出一轮完整的故障开始与结束。
- 人为让通知命令失败时，消息保留在 `queue/` 并重试；恢复后能补发。

## 已知限制与风险

- **单点观察**：结果只代表监控机所在网络，不能证明其他地区或运营商不可访问。
- **没有外部心跳**：主拨测机失电、断网或任务卡死时，可能没有任何告警。本机日志不能替代外部发现。
- **邮件不是即时通道**：可能延迟、被过滤或进入垃圾箱，不适合作为夜间叫醒手段。
- **CDN 与缓存**：公网入口可能命中缓存、挑战页或限流页；正文断言应选择能反映真实业务的标记，并按需调整入口策略。
- **代表性覆盖**：一个业务页面通过，不代表全部站点、下单或其他流程正常。
- **无自动修复**：脚本不改变线上状态，恢复仍需人工处理。
- **后端直连未纳入**：当前不能区分“后端故障”和“节点到后端链路故障”，这一层留待后续扩展。
- **SMTP 凭据暴露面**：`curl --user` 在投递瞬间可能出现在本机进程列表中。使用专用授权码、限制文件权限和收件范围，不要使用主邮箱密码。

## 故障排查

| 现象 | 优先核对 |
| --- | --- |
| `curl_exit_6` | 域名解析失败；`public` 检查依赖本机 DNS |
| `curl_exit_7` | 连接被拒绝；端口、监听地址、防火墙或节点地址是否正确 |
| `curl_exit_28` | 请求超时；目标负载、网络质量或 `timeout` 是否过短 |
| `curl_exit_35` 或 `curl_exit_60` | TLS 握手或证书校验失败；协议、SNI、证书链或 `ca_bundle` |
| `unexpected_status_403` | 可能触发 CDN 挑战或访问控制；检查 `Host`、路径与入口策略 |
| `unexpected_status_444` | 通常为未知 `Host`；补 `host_header` 或修正域名 |
| `curl_exit_63` | 响应超过 1 MiB 上限；换更小的业务标记或检查入口 |
| `body_mismatch` | 标记不稳定、命中缓存或返回了兜底页；重新选择业务标记 |
| 邮件未到达 | 先跑 `--test`；检查 `notify.env` 权限、SMTP 端口、授权码和垃圾箱 |
| 状态无法写入 | 检查 `/var/lib/uptime-checks` 属主与权限，以及是否误用 root 执行 |
| `上一轮仍在运行` | 目标过多或超时过长；减少检查项、并发或单轮耗时 |

## 与参考方案的关系

本实现采纳参考材料中的分层探测、防抖、恢复通知、维护窗口与不泄漏真实地址等原则，并规避了示例脚本中的几处缺口：

- 通知失败不再被静默忽略，改为入队重试。
- 临时响应文件统一清理，不残留。
- 配置在探测前校验，字段缺失不会悄悄跳过。
- 状态更新与通知投递解耦，发送成功才确认完成。
- 健康检查与业务检查分别配置，不以本地健康接口代替回源结论。
