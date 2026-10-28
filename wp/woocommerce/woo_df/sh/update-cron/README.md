# 多服务器定时任务批量下发（update-cron）

## 用途

本目录提供一套轻量方案，用于向多台 Linux 服务器批量下发一份**受管 cron 文件**，默认 `/etc/cron.d/update-cron`。任务内容由模板决定，不限于某一类站点脚本：可以是备份、清理、同步、站点更新等任意 cron 任务。

核心约束是**不改动现有 crontab 条目，也不修改系统时区**：新任务只写入一份独立文件，整份覆盖、整份删除，与 `crontab -l`、宝塔面板和其他 `/etc/cron.d` 文件互不影响。

仓库内的 `cron.cst` 与 `cron.utc` 只是示例，附带的两条任务用于演示（WP 函数更新）；实际使用请复制到仓库外，替换成自己的任务与路径。

此前若已按旧名称下发过 `/etc/cron.d/wp-functions`，重命名不会自动迁移：要继续沿用时给 `--target /etc/cron.d/wp-functions`，或先按“日常维护 · 删除任务”清理旧文件，再下发新的默认路径。

设计取舍与边界见 [方案.md](方案.md)，本文件只说明安装、下发、验证和维护操作。

## 目录文件

| 文件 | 用途 |
| --- | --- |
| `deploy.sh` | 批量下发、校验、删除受管文件（控制机执行） |
| `install-cron.sh` | 在目标机本地安装、校验、删除受管文件（服务器执行） |
| `cron.cst` | 示例模板：系统时区为 `Asia/Shanghai` 时使用 |
| `cron.utc` | 示例模板：系统时区为 `UTC` 时使用 |
| `hosts.example.txt` | 主机清单示例 |
| `hosts.txt` | 实际主机清单，由使用者创建，已被 `.gitignore` 忽略 |
| `方案.md` | 方案说明、取舍、验收标准与风险边界 |

`deploy.sh` 面向 Bash 控制机，`install-cron.sh` 在目标机本地执行。Windows 控制机另有模块命令 `Push-FileToServers`（仓库 `PS/WpOnline`）可一条命令完成并发下发，见“Windows 侧单文件下发”。

## 模板与主机清单不入库

仓库是公开的，本目录里的模板只作示例，不是可直接投产的配置：

- 模板中的任务、脚本路径、日志位置都按示例填写，实际环境不同就要改。
- 真实下发用的模板应复制到仓库外单独维护，例如 `~/wpfc/update-cron.cron` 或 `./work/update-cron.cron`，只改自己的副本；仓库内的两份保持通用示例，避免把真实路径提交进公开仓库。
- 下文命令里的模板参数一律指**你自己的副本**；`deploy.sh` 用 `--template`，`Push-FileToServers` 用 `-Path`。
- 不传 `--template` 时，`deploy.sh` 使用仓库目录内的两份示例，仅适合试跑或时区自动选择验证。

## 前置条件

- 控制机安装 OpenSSH 客户端，能够以 root 身份免密登录全部目标机。`deploy.sh` 需要 Bash，应在 Linux、WSL 或 Git Bash 中运行；`install-cron.sh` 在目标机本地执行，Windows 侧只需 `scp` 与 `ssh`。控制机若已加载仓库的 `PS/WpOnline` 模块，也可以直接用 `Push-FileToServers` 完成批量下发，不依赖 Bash。
- 目标机已经安装并运行 cron，服务名可能是 `cron`、`crond` 或 `cronie`；cron 实现需要读取 `/etc/cron.d`，Debian、Ubuntu、RHEL 与 CentOS 的默认实现均满足该条件。
- 目标机的系统时区为 `Asia/Shanghai` 或 `UTC`，或其他固定 UTC+8 时区（后者用 `--template` 指定 CST 模板）；观察夏令时的时区不在本方案范围内。
- 模板中的任务依赖的文件（更新脚本、数据源等）已经部署，必要时用 `--require` 声明，让 `deploy.sh` 在下发前检查。
- 目标机的 root crontab 与其他 cron 配置中没有相同任务的旧副本；如果已经存在，按下一节迁移，避免重复执行。

首次使用前，建议先手工验证 SSH：

```bash
ssh -o BatchMode=yes root@203.0.113.11 true
```

命令返回 0 表示免密登录可用。若提示 host key 校验失败，先将目标机加入 `known_hosts`，或在 `~/.ssh/config` 中单独配置该主机。

## 已有相同任务时的迁移

任务可能已经用 `crontab -e` 或宝塔面板创建过。首次下发前**必须**先在每台目标机检查模板中引用的脚本（`.php`、`.sh`）是否已出现在其他 cron 配置里：

```bash
ssh root@203.0.113.11 "crontab -l | grep -nF -e update_wp_functions.sh"
ssh root@203.0.113.11 "grep -rnF -e update_wp_functions.sh /etc/crontab /etc/cron.d/"
```

检查用的名字换成你模板里的脚本基名，可以一次传多个 `-e`。`deploy.sh` 与 `install-cron.sh` 都会自动做同样的检查：从模板中提取 `.php` 与 `.sh` 的基名，比对 root crontab、`/etc/crontab` 和其他 `/etc/cron.d` 文件，命中即拒绝下发。

如果发现旧条目，先备份再删除。root crontab 的备份与编辑命令如下：

```bash
ssh root@203.0.113.11 'crontab -l > ~/crontab.bak'
ssh root@203.0.113.11 'crontab -e'
```

删除旧行后执行 `crontab -l` 确认条目已消失，再运行本方案。只有在确认重复条目不会造成重复执行时，才使用 `--allow-existing` 跳过该检查。

宝塔面板中的任务需要在面板界面删除，不能只改文件。面板通常维护 root 的 crontab，删除后可以用上面的 `crontab -l` 命令复核。

## 快速开始

### 控制机有 Bash

1. 准备主机清单与自己的模板副本。仓库里的模板只是示例，先复制到仓库外再改。

   ```bash
   cd update-cron
   cp hosts.example.txt hosts.txt
   vi hosts.txt
   mkdir -p ~/wpfc
   cp cron.cst ~/wpfc/update-cron.cron
   vi ~/wpfc/update-cron.cron
   ```

   模板里要按实际环境核对任务命令、依赖脚本与日志路径。

2. 预演，确认预检结果与将写入的内容。

   ```bash
   bash deploy.sh --template ~/wpfc/update-cron.cron --dry-run
   ```

   有依赖文件需要预检时追加 `--require`，可重复：

   ```bash
   bash deploy.sh --template ~/wpfc/update-cron.cron \
     --require /www/sh/wp-functions-update/update_wp_functions.sh \
     --require /www/functions4.php --dry-run
   ```

   指定 `--template` 后不再按机器自动选模板，所以这条命令适用于全部目标机同为 CST（或同为 UTC）的情况；时区混合时按“时区与模板”分两组，每组用一份副本。

3. 正式下发。

   ```bash
   bash deploy.sh --template ~/wpfc/update-cron.cron
   ```

4. 校验全部目标机。

   ```bash
   bash deploy.sh --template ~/wpfc/update-cron.cron --check
   ```

5. 登录任意一台目标机，核对文件与现有 crontab。

   ```bash
   ssh root@203.0.113.11 'cat /etc/cron.d/update-cron'
   ssh root@203.0.113.11 'stat -c "%a %U %G" /etc/cron.d/update-cron'
   ssh root@203.0.113.11 'crontab -l'
   ```

   文件权限应为 `644 root root`，`crontab -l` 中不应出现相同任务的旧副本，其余条目应与下发前一致。

### 控制机只有 Windows PowerShell

前提是全部目标机的系统时区一致（典型情况都是 `Asia/Shanghai`），且旧任务条目已按“已有相同任务时的迁移”清理完毕。先在控制机加载模块，并把示例模板复制成自己的副本：

```powershell
# 在仓库根目录执行
Import-Module ./PS/WpOnline/WpOnline.psd1
New-Item -ItemType Directory -Force ./work | Out-Null
Copy-Item ./wp/woocommerce/woo_df/sh/update-cron/cron.cst ./work/update-cron.cron
notepad ./work/update-cron.cron
```

`./work` 放在仓库外或已被忽略均可，关键是真实的任务、路径与日志按自己的环境改，仓库内的示例保持原样。

1. 确认时区与依赖文件。

   ```powershell
   Update-Servers -cmd 'timedatectl show -p Timezone --value'
   Update-Servers -cmd 'ls -l /www/sh/wp-functions-update/update_wp_functions.sh /www/functions4.php /www/functions24.php'
   ```

   `Update-Servers` 对服务器清单中的全部机器执行同一条命令，默认在 `/www` 下运行；Windows PowerShell 5.1 需先安装 `ThreadJob` 模块，否则改用 `pwsh` 7。能力与限制见“Update-Servers 的适用边界”。

2. 预演、下发、校验都使用同一条 `Push-FileToServers` 命令：加 `-WhatIf` 预演，去掉即为下发，再跑一次即为校验（已一致的机器显示 `Skipped`）。完整命令与参数见“Windows 侧单文件下发 · 方式一”。

   下发后按上一节登录任意一台，核对 `stat` 与 `crontab -l`。时区混合时不要用这条路径，改用 `deploy.sh` 按机器选择模板。

## deploy.sh 命令说明

| 命令 | 作用 |
| --- | --- |
| `bash deploy.sh` | 按主机清单逐台下发，已是最新的目标机会跳过 |
| `bash deploy.sh --dry-run` | 只读取目标机状态并打印将执行的操作，不写入 |
| `bash deploy.sh --check` | 只校验受管文件的内容与权限，不写入 |
| `bash deploy.sh --remove` | 备份后删除受管文件，停止调度其中的任务 |
| `bash deploy.sh --allow-existing` | 跳过“已有相同任务”检查，仅在确认不会重复执行时使用 |
| `bash deploy.sh -f hosts-prod.txt` | 使用指定主机清单 |
| `bash deploy.sh --template ~/wpfc/update-cron.cron` | 强制使用指定模板，跳过时区自动识别 |
| `bash deploy.sh --target /etc/cron.d/my-tasks` | 改受管文件路径，默认 `/etc/cron.d/update-cron` |
| `bash deploy.sh --backup-dir /var/backups/my-tasks` | 改备份目录，默认 `/var/backups/<受管文件名>` |
| `bash deploy.sh --require /path/to/dep` | 下发前要求目标机存在该文件，可重复 |
| `bash deploy.sh --help` | 显示帮助 |

脚本按目标机顺序执行，单台失败不会中断整批任务。全部成功时退出码为 0，存在失败时为 1，参数或本地文件错误时为 2。`--hosts` 与 `--template` 的相对路径按脚本所在目录解析，绝对路径按原样使用。

受管文件名不能含点号：`/etc/cron.d` 中带点号的文件会被 `run-parts` 静默跳过，脚本会在本地直接拒绝。备份文件名由受管文件名加时间戳构成，例如 `update-cron.20261028-160000`。

SSH 端口、私钥等连接参数可以写入 `~/.ssh/config`，也可以通过环境变量传入：

```bash
SSH_EXTRA_OPTS="-p 2222 -i $HOME/.ssh/id_ed25519" bash deploy.sh --dry-run
```

## 时区与模板

cron 的触发时刻按目标机的系统时区解释。模板中的 `TZ=Asia/Shanghai` 只影响任务进程看到的时区，不改变触发时刻。脚本会根据 `timedatectl` 的结果自动选择模板：

| 示例模板 | 适用系统时区 | 示例任务的 16:00 / 00:00 |
| --- | --- | --- |
| `cron.cst` | `Asia/Shanghai` | `0 16` / `0 0` |
| `cron.utc` | `UTC` | `0 8` / `0 16` |

实际下发用自己在仓库外维护的副本，模板中的任务、依赖脚本和日志路径按真实环境填写。其他固定 UTC+8 时区（例如 `Asia/Singapore`、`Asia/Hong_Kong`、`Asia/Taipei`）可以显式指定 CST 模板：

```bash
bash deploy.sh --template ~/wpfc/update-cron.cron
```

使用 `--template` 下发后，后续执行 `--check` 也要带上相同的 `--template`，否则脚本会重新按系统时区识别并可能拒绝执行。

如果目标机使用观察夏令时的时区，固定小时无法在全年保持北京时间。此时应改用带 `OnCalendar=... Asia/Shanghai` 的 systemd timer，或在充分评估存量任务影响后统一系统时区。本方案不自动处理这类环境。

`TZ=Asia/Shanghai` 同时保证脚本内的 `date` 使用北京时间。北京时间 00:00 在 UTC 机器上对应前一天 16:00，若进程没有设置 `TZ`，按日期生成的文件名或判断会落到前一天。

Windows PowerShell 在传递远程命令时对引号、`$` 与反斜杠敏感。本方案把复杂逻辑收敛到服务端脚本，远程命令只剩一条带固定参数的 `bash ...`，可以避开转义问题。

`Push-FileToServers` 的远端命令按同样的原则构造：只用单引号，不含双引号，并且以 LF 下发。远端登录 shell 不把 CR 当作空白字符，命令带 CRLF 会让 `then`、`fi`、`}` 等标记失效；Windows PowerShell 5.1 传参时还会吃掉双引号。命令内容只使用 POSIX 语法，root 登录 shell 是 bash、zsh 或 sh 都能执行。

## Windows 侧单文件下发

如果全部目标机的系统时区一致（例如都是 `Asia/Shanghai`），可以只维护一份 cron 文件，从 Windows 侧下发。这种形态不依赖 WSL 或 Git Bash。

先批量确认时区，命令在每台目标机本地执行：

```powershell
Update-Servers -cmd 'timedatectl show -p Timezone --value'
```

Bash 侧直接跑 `bash deploy.sh --dry-run`，它会同时打印识别到的时区与将选用的模板。全部为 `Asia/Shanghai` 时一份模板通吃；存在 `UTC` 机器时按“时区与模板”一节分组，不要用同一份文件覆盖全部机器。

Windows 侧有三种落地方式，区别在于上传由谁完成，以及是否在目标机本地做预检：

| 方式 | 上传 | 逐台操作 | 适用 |
| --- | --- | --- | --- |
| 方式一：直接落到受管路径 | `Push-FileToServers` 内部执行 `scp` | 否，一条命令处理清单内全部机器 | 旧条目已清理，不需要额外预检 |
| 方式一（预检变体）：上传到 `/tmp` 再安装 | 同上，两条命令都是批量 | 否，两条命令处理全部机器 | 需要重复条目与 cron 服务检查 |
| 方式二：手工 `scp` + `install-cron.sh` | 自己写 `scp`，每台一条 | 是 | 未加载 `PS/WpOnline` 模块 |

### 方式一：一条命令下发（推荐）

已加载模块时不需要手写 `scp`：一条命令内完成上传、比对、备份、原子替换与写后校验，重复执行幂等。

```powershell
Import-Module ./PS/WpOnline/WpOnline.psd1
Push-FileToServers -Path /path/to/update-cron-file.cron -RemotePath /etc/cron.d/update-cron -Linuxify -Backup -BackupDirectory /var/backups/update-cron
```

- 目标机默认取服务器清单的 `ip` 字段（跳过开头 1 条），也可以用 `-Server 203.0.113.11,root@203.0.113.12` 直接指定。
- `-Linuxify` 去 BOM、CRLF 转 LF，模板必须带；`-BackupDirectory` 与 `install-cron.sh` 一致时，“回滚”一节的命令可直接通用。
- 默认 10 台并发，`-ThrottleLimit` 取 1 到 64；目标目录不存在时加 `-CreateDirectory`；`-WhatIf` 只打印不连接。运行中逐台打印状态与耗时，末尾给汇总行。

`-RemotePath` 就是最终受管路径，落地时用 `install -m 0644 -o root -g root` 加同目录改名，cron 下一分钟读取，**推送即安装**：不需要再执行 `install-cron.sh`，也不需要重启 cron。

需要 `install-cron.sh` 的重复条目与 cron 服务预检时，先批量上传到 `/tmp`，再批量安装：

```powershell
Push-FileToServers -Path /path/to/update-cron-file.cron -RemotePath /tmp/update-cron.cron -Linuxify
Update-Servers -cmd 'bash /www/sh/update-cron/install-cron.sh -f /tmp/update-cron.cron'
```

`/tmp` 下带点号的文件名不受 `/etc/cron.d` 命名限制，安装、预检与写后校验都由服务器端脚本完成，其中的脚本路径按实际部署位置调整；把第二条换成 `--check` 或 `--remove` 即为校验与删除。

失败不中断整批，也不抛异常，只体现在返回对象的 `Status` 与警告里，脚本化时要显式检查：

```powershell
$r = Push-FileToServers -Path /path/to/update-cron-file.cron -RemotePath /etc/cron.d/update-cron -Linuxify
if (@($r | Where-Object Status -eq 'Failed').Count -gt 0) { throw '下发存在失败机器' }
```

直接落到 `/etc/cron.d/update-cron` 时只负责文件落地，不检查重复任务条目、模板依赖文件与 cron 服务；需要这些检查就用上面的 `/tmp` + `install-cron.sh` 组合，或改用 `deploy.sh --require`。完整参数见 `Get-Help Push-FileToServers -Full`。

### 方式二：手工 `scp` + `install-cron.sh`

没有加载模块时用这条路径。它需要手写命令，并且每台目标机各执行一次：

1. 在本地编辑自己的模板副本 `./work/update-cron.cron`（从仓库示例复制而来）。
2. 上传到目标机的 `/tmp`。
3. 在目标机执行 `install-cron.sh`，由它完成去 BOM、去 CR、备份、原子替换、写后校验与重复条目检查。

```powershell
scp ./work/update-cron.cron root@${h}:/tmp/update-cron.cron
ssh root@${h} 'bash /www/sh/update-cron/install-cron.sh -f /tmp/update-cron.cron'
```

`${h}` 替换为目标机地址。`scp` 每台一条，需要自己循环；`ssh` 这一步不含按主机变化的参数，可以交给 `Update-Servers` 批量执行：

```powershell
Update-Servers -cmd 'bash /www/sh/update-cron/install-cron.sh -f /tmp/update-cron.cron'
```

`Update-Servers` 只负责执行命令、不做上传，前提是每台的 `scp` 都已经执行。如果仓库已经整体部署到目标机，可以省掉 `scp`，让安装器直接读仓库内的模板：

```powershell
Update-Servers -cmd 'bash /www/sh/update-cron/install-cron.sh -f /www/sh/update-cron/cron.cst'
```

`/www/sh` 按实际部署路径调整。这种形态下模板随仓库走 Git，换行由 `.gitattributes` 保证，`install-cron.sh` 再去一次 BOM 与 CR 作为兜底。

### Update-Servers 的适用边界

本文多处用 `Update-Servers` 做批量只读检查与批量执行，它适合的场景很窄：

- 对服务器清单内**全部**机器执行同一条命令：查时区、查文件是否存在、批量执行 `install-cron.sh --check`、批量备份并删除受管文件。
- 只做执行，不做上传：文件下发用 `Push-FileToServers` 或手工 `scp`。
- 固定以 `root` 登录，并先切到 `-WorkingDirectory`（默认 `/www`）；目标机没有该目录时命令直接失败。
- 没有 `-Server` 参数，不能只处理一台；单台操作用 `ssh root@<host> '...'`。
- 输出不区分主机，多台结果混在一起；需要逐台状态时看 `Push-FileToServers` 的结果对象，或自己循环单台 `ssh`。
- 不返回失败汇总与退出码，只回显远端 stdout 与 stderr。
- 依赖 `Start-ThreadJob`：PowerShell 7 自带；Windows PowerShell 5.1 需先安装 `ThreadJob` 模块，否则整条命令直接报 `CommandNotFoundException`，一台都不会执行。

### 校验与删除

用 `install-cron.sh` 落地时按单台或经 `Update-Servers` 批量执行：

```powershell
ssh root@${h} 'bash /www/sh/update-cron/install-cron.sh --check -f /tmp/update-cron.cron'
Update-Servers -cmd 'bash /www/sh/update-cron/install-cron.sh --check -f /tmp/update-cron.cron'
ssh root@${h} 'bash /www/sh/update-cron/install-cron.sh --remove'
```

用 `Push-FileToServers` 落地时，重跑同一条命令即为校验：内容与权限一致的机器显示 `Skipped`，缺失或不一致的显示 `Updated`。需要停止调度时先备份再删除：

```powershell
ssh root@${h} 'mkdir -p /var/backups/update-cron && cp -p /etc/cron.d/update-cron /var/backups/update-cron/update-cron.removed.$(date +%Y%m%d-%H%M%S) && rm -f /etc/cron.d/update-cron'
```

`install-cron.sh` 以 root 身份运行，检查 root crontab、`/etc/crontab` 与其他 `/etc/cron.d` 文件中的重复条目，备份到 `/var/backups/<受管文件名>/`，并在写后复核 SHA-256 与 `644 root root`。重复执行是安全的：内容与权限已一致时直接跳过，不产生额外备份。上传到 `/tmp` 的临时文件不会被删除，便于重复执行 `--check`。

### 与 deploy.sh 的分工

| 场景 | 建议 |
| --- | --- |
| 目标机同一时区，控制机已加载 `PS/WpOnline` 模块 | `Push-FileToServers`，一条命令并发下发并逐台输出结果 |
| 目标机同一时区，需要预检又不想逐台 `scp` | `Push-FileToServers` 上传到 `/tmp`，再用 `Update-Servers` 调 `install-cron.sh` |
| 目标机同一时区，控制机未加载模块 | 手工 `scp` + `install-cron.sh`，`scp` 每台一条 |
| 目标机时区混合（部分 CST、部分 UTC） | `deploy.sh`，按机器自动选择模板 |
| 需要预检依赖文件、cron 服务与重复条目 | `deploy.sh` 全部覆盖（依赖由 `--require` 声明）；`install-cron.sh` 查 cron 服务与重复条目；`Push-FileToServers` 都不查 |
| 需要在一台机器上反复执行并跳过无变化写入 | 各方式都支持；`deploy.sh` 在控制机比对，`Push-FileToServers` 与 `install-cron.sh` 在目标机比对，都不产生多余写入与备份 |

### 三个容易错的地方

- 受管文件名不能带点号。`/etc/cron.d` 中带点号的文件会被 `run-parts` 静默跳过，两个脚本都会直接拒绝这类目标名，`Push-FileToServers` 在调用时就会抛错。
- `scp` 直接覆盖目标路径不是原子写，cron 可能读到半截文件。各方式都先写同目录临时文件再改名。
- `scp` 落地后的属主与权限取决于源文件和登录用户。各方式都用 `install -m 0644 -o root -g root` 固定，并在写后复核。

## 下发后的验证

`deploy.sh --check` 通过只说明文件和权限正确，任务是否被 cron 调度还需要查看系统日志。用 `Push-FileToServers` 下发时，`Skipped` 同样只证明内容与权限一致。这两种检查都不覆盖 root crontab 或其他 cron 文件中的重复条目，首次迁移时仍需按“已有相同任务时的迁移”一节手工核对。cron 每分钟扫描一次配置，新文件通常在下一分钟生效；如果超过两分钟仍未生效，重启对应 cron 服务并查看系统日志。

Debian 与 Ubuntu：

```bash
ssh root@203.0.113.11 'grep CRON /var/log/syslog | tail -n 20'
ssh root@203.0.113.11 'journalctl -u cron --since "5 min ago" --no-pager'
```

RHEL、CentOS 与 Fedora：

```bash
ssh root@203.0.113.11 'tail -n 20 /var/log/cron'
ssh root@203.0.113.11 'journalctl -u crond --since "5 min ago" --no-pager'
```

到达任务预定时间后，检查任务输出。示例模板写入 `/var/log/wp-functions-update.log`，换成你自己的日志路径：

```bash
ssh root@203.0.113.11 'tail -n 50 /var/log/wp-functions-update.log'
```

如果需要立即验证命令本身，可以手工执行一次模板中的任务命令。示例任务会立即修改站点主题目录下的 `functions.php`，执行前应确认目标机允许这样操作：

```bash
ssh root@203.0.113.11 '/bin/bash /www/sh/wp-functions-update/update_wp_functions.sh --src /www/functions4.php'
```

## 日常维护

### 修改任务时间或命令

修改自己的模板副本（例如 `~/wpfc/update-cron.cron`），不要在仓库内的示例里写真实路径。随后先预演，再全量下发：

```bash
bash deploy.sh --template ~/wpfc/update-cron.cron --dry-run
bash deploy.sh --template ~/wpfc/update-cron.cron
bash deploy.sh --template ~/wpfc/update-cron.cron --check
```

模板中已经包含完整的命令、环境变量和日志重定向，不需要修改 `deploy.sh`。如果依赖文件路径有变化，要同时更新模板与 `--require` 参数。

### 新增机器

在 `hosts.txt` 中增加一行，执行 `bash deploy.sh --template ~/wpfc/update-cron.cron`。已经是最新的目标机会被跳过，只有新机器和内容不一致的机器会发生写入。

### 移除机器

从 `hosts.txt` 删除对应行只能阻止后续下发，不会清理该机器上的文件。需要清理时，用只包含该机器的主机清单执行删除：

```bash
printf 'root@203.0.113.11\n' > /tmp/hosts-remove.txt
bash deploy.sh -f /tmp/hosts-remove.txt --remove
```

### 回滚

每次覆盖前，脚本会把旧文件备份到 `/var/backups/<受管文件名>/`（可用 `--backup-dir` 改），文件名带时间戳。回滚时选择对应备份复制回受管路径：

```bash
ssh root@203.0.113.11 'ls -lt /var/backups/update-cron/'
ssh root@203.0.113.11 'cp -p /var/backups/update-cron/update-cron.20261028-160000 /etc/cron.d/update-cron'
```

复制后不需要重启 cron，下一分钟会按恢复后的内容调度。启用 SELinux 的系统需要再执行一次 `restorecon -F /etc/cron.d/update-cron`。

### 删除任务

```bash
bash deploy.sh --remove
```

`--remove` 会先备份为 `<受管文件名>.removed.<时间戳>`，再删除受管文件。删除后 `--check` 应当失败并提示目标文件不存在，这是预期结果。删除只影响本方案管理的这一份文件，不会修改 `crontab -l` 中的任何条目。受管路径由 `--target` 指定过时，`--remove` 也要带上同一个 `--target`。

### PowerShell 路径的等价操作

控制机没有 Bash 时，上文的日常操作对应关系如下。三条路径写的是同一份模板、同一个受管路径。

| 操作 | Bash 控制机 | Windows 控制机 |
| --- | --- | --- |
| 预演 | `bash deploy.sh --template <模板> --dry-run` | `Push-FileToServers … -WhatIf` |
| 下发或修改后重发 | `bash deploy.sh --template <模板>` | 重跑 `Push-FileToServers` |
| 校验 | `bash deploy.sh --template <模板> --check` | 重跑 `Push-FileToServers`，应全部 `Skipped` |
| 新增机器 | `hosts.txt` 增加一行后 `bash deploy.sh --template <模板>` | 服务器清单增加一行后重跑；或用 `-Server` 只指定新增机器 |
| 移除单台机器 | `bash deploy.sh -f hosts-remove.txt --remove` | 登录该机备份并删除受管文件，见“Windows 侧单文件下发 · 校验与删除” |
| 回滚 | `cp -p` 备份回受管路径 | 同左；也可把备份文件作为 `-Path`，用 `Push-FileToServers` 推回 |
| 删除全部任务 | `bash deploy.sh --remove` | 先用 `Update-Servers -cmd` 批量备份并删除受管文件 |

`Update-Servers` 只处理服务器清单内的全部机器，单台操作直接 `ssh root@<host> '...'`，能力与限制见“Update-Servers 的适用边界”。PowerShell 路径不预检重复条目与 cron 服务，模板改动后仍应人工核对一次 `crontab -l` 与 `/etc/cron.d`。

批量停止调度时，先备份再删除受管文件：

```powershell
Update-Servers -cmd 'mkdir -p /var/backups/update-cron && cp -p /etc/cron.d/update-cron /var/backups/update-cron/update-cron.removed.$(date +%Y%m%d-%H%M%S) && rm -f /etc/cron.d/update-cron'
```

## 故障排查

| 现象 | 可能原因 | 处理 |
| --- | --- | --- |
| `Host key verification failed` | 目标机未加入 `known_hosts` | 先手工 `ssh` 一次，或按组织规范预置 host key |
| `Permission denied (publickey)` | 控制机密钥未获授权 | 将公钥加入目标机 root 的 `authorized_keys` |
| `需要 root 权限` | 登录用户不是 root | 使用 `root@host`，或按实际环境改造远程执行部分 |
| `不支持的时区` | 系统时区不在自动识别范围 | 用 `--template` 指向自己的模板显式指定 |
| `缺少文件` | `--require` 声明的依赖未部署 | 先部署依赖，或去掉对应的 `--require` |
| `cron 服务未运行` | cron、crond 或 cronie 未启动 | 启动对应服务并设置开机自启 |
| 预检提示已有相同任务 | root crontab 或其他 cron 配置中存在旧条目 | 按“已有相同任务时的迁移”备份并删除旧条目，确认后再下发 |
| `--check` 失败但文件内容看起来正确 | 权限、属主或换行符不符 | 用 `stat` 检查 `644 root root`，并确认模板保持 LF 换行 |
| `目标目录不存在` | `--target` 指向的目录未创建 | 先创建目录，或改用已存在的目录 |
| 任务没有按预期执行 | cron 未加载、时间语义不符或系统时区不是预期值 | 查看 cron 日志，并用 `systemctl status cron` 或 `systemctl status crond` 与 `timedatectl` 交叉确认 |
| 同一任务执行了两次 | 宝塔面板或用户 crontab 中存在相同任务 | 执行 `crontab -l` 与 `grep -r <脚本名> /etc/cron.d`，只保留一套 |
| 日志文件没有内容 | 命令路径错误、脚本无执行权限或 cron 未运行 | 手工执行一次命令，检查 cron 日志与日志文件权限 |
| `restorecon` 报错 | 目标机未启用 SELinux，或文件上下文无法修正 | 未启用 SELinux 时可以忽略；已启用时手工执行 `restorecon -v <受管文件>` 检查上下文 |
| 全部目标机显示 `Skipped` | 内容与权限已一致，未发生写入 | 预期结果；需要强制重写时先删除受管文件再下发 |
| `Failed 上传失败` | `scp` 无法连通、host key 未接受或密钥未授权 | 按本表前两行排查；失败时 `/tmp` 可能残留 `push-file-*`，用 `rm -f /tmp/push-file-*` 清理 |
| `Failed 写入失败: install: cannot create regular file` | 目标目录不存在 | 首次下发加 `-CreateDirectory` |
| `Failed 作业异常` | 后台作业未正常返回结果 | 改用 `-ThrottleLimit 1` 顺序执行，绕开并发层后复现 |
| 远端报 `unexpected end of file` 或 `parse error near` | 下发的命令换行或引号被破坏 | 确认调用的是最新版 `Push-FileToServers`；清理 `/tmp/push-file-*` 后重试 |
| `Update-Servers` 报 `Start-ThreadJob is not recognized` | 当前是 Windows PowerShell 5.1 且未安装 `ThreadJob` 模块 | 改用 `pwsh` 7 执行，或先安装 `ThreadJob` 模块 |
| `Update-Servers` 输出没有对应主机名，无法定位 | 该命令只回显远端输出，不标注主机 | 单台改用 `ssh root@<host> '...'` 逐个确认 |

## 与现有 crontab 和宝塔面板的关系

受管文件与 root 用户的 crontab 是两套独立配置。`crontab -l` 不会显示受管文件中的任务，查看全部任务需要同时检查两个位置：

```bash
crontab -l
cat /etc/cron.d/update-cron
```

宝塔面板通常只维护 root 用户的 crontab，不会读取或改写 `/etc/cron.d`。部署后仍应确认面板中没有重复创建同样的任务，否则同一时间会执行两次。

## 安全说明

- `hosts.txt` 可能包含真实服务器地址，已通过本目录的 `.gitignore` 排除，不应提交到仓库。
- 仓库内的模板只是示例；真实模板与 `hosts.txt` 都应放在仓库外，避免把服务器地址、依赖脚本路径与日志路径提交到公开仓库。
- 脚本以 root 身份写入 `/etc/cron.d`，控制机上的私钥应按最小权限保管。
- 模板执行的是你自己填写的命令，不接受来自目标机的任意输入；下发前应核对模板内容。
- 受管文件权限固定为 `644 root root`，避免被普通用户改写。

## 可选：日志轮转

示例任务把输出写入 `/var/log/wp-functions-update.log`，脚本不做轮转。长期运行时可以在目标机新增对应的 `/etc/logrotate.d/` 配置：

```conf
/var/log/wp-functions-update.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
```

该配置需要由使用者按目标机的日志策略调整，本方案不自动下发。
