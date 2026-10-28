# wp-functions 定时任务批量部署

## 用途

本目录提供一套轻量方案，用于在已有的多台 Linux 服务器上批量新增两条每天执行的 crontab 任务。核心约束是**不改动现有 crontab 条目，也不修改系统时区**，只在每台机器上维护一个独立文件 `/etc/cron.d/wp-functions`（下称受管文件）。

设计取舍与边界见 [方案.md](方案.md)，本文件只说明安装、下发、验证和维护操作。

## 目录文件

| 文件 | 用途 |
| --- | --- |
| `deploy.sh` | 批量下发、校验、删除受管文件（控制机执行） |
| `install-cron.sh` | 在目标机本地安装、校验、删除受管文件（服务器执行） |
| `wp-functions.cron.cst` | 系统时区为 `Asia/Shanghai` 时使用的模板 |
| `wp-functions.cron.utc` | 系统时区为 `UTC` 时使用的模板 |
| `hosts.example.txt` | 主机清单示例 |
| `hosts.txt` | 实际主机清单，由使用者创建，已被 `.gitignore` 忽略 |
| `方案.md` | 方案说明、取舍、验收标准与风险边界 |

## 前置条件

- 控制机安装 OpenSSH 客户端，能够以 root 身份免密登录全部目标机。`deploy.sh` 需要 Bash，应在 Linux、WSL 或 Git Bash 中运行；`install-cron.sh` 在目标机本地执行，Windows 侧只需 `scp` 与 `ssh`。
- 目标机已经安装并运行 cron，服务名可能是 `cron`、`crond` 或 `cronie`；cron 实现需要读取 `/etc/cron.d`，Debian、Ubuntu、RHEL 与 CentOS 的默认实现均满足该条件。
- 目标机已经存在 `/www/sh/wp-functions-update/update_wp_functions.sh`、`/www/functions4.php` 和 `/www/functions24.php`。
- 目标机的系统时区为 `Asia/Shanghai` 或 `UTC`，或其他固定 UTC+8 时区（后者用 `--template` 指定 CST 模板）；观察夏令时的时区不在本方案范围内。
- 目标机的 root crontab 中没有这两条任务的旧副本；如果已经存在，按下一节迁移，避免重复执行。

首次使用前，建议先手工验证 SSH：

```bash
ssh -o BatchMode=yes root@203.0.113.11 true
```

命令返回 0 表示免密登录可用。若提示 host key 校验失败，先将目标机加入 `known_hosts`，或在 `~/.ssh/config` 中单独配置该主机。

## 已有同名任务时的迁移

服务器上可能已经用 `crontab -e` 或宝塔面板创建过这两条任务。首次下发前**必须**先在每台目标机检查：

```bash
ssh root@203.0.113.11 "crontab -l | grep -nE 'functions4\.php|functions24\.php'"
ssh root@203.0.113.11 "grep -rnE --exclude=wp-functions 'functions4\.php|functions24\.php' /etc/crontab /etc/cron.d/"
```

如果发现旧条目，先备份再删除。root crontab 的备份与编辑命令如下：

```bash
ssh root@203.0.113.11 'crontab -l > ~/crontab.bak'
ssh root@203.0.113.11 'crontab -e'
```

删除引用 `functions4.php` 和 `functions24.php` 的旧行后，执行 `crontab -l` 确认条目已消失，再运行本方案。`deploy.sh` 与 `install-cron.sh` 都会检查 root crontab、`/etc/crontab` 和其他 `/etc/cron.d` 文件，发现同名条目时拒绝下发。只有在确认重复条目不会造成重复执行时，才使用 `--allow-existing` 跳过该检查。

宝塔面板中的任务需要在面板界面删除，不能只改文件。面板通常维护 root 的 crontab，删除后可以用上面的 `crontab -l` 命令复核。

## 快速开始

1. 复制主机清单并填写实际目标机。

   ```bash
   cd wp-functions-cron
   cp hosts.example.txt hosts.txt
   vi hosts.txt
   ```

2. 预演，确认时区识别、模板选择和预检结果。

   ```bash
   bash deploy.sh --dry-run
   ```

3. 正式下发。

   ```bash
   bash deploy.sh
   ```

4. 校验全部目标机。

   ```bash
   bash deploy.sh --check
   ```

5. 登录任意一台目标机，核对文件与现有 crontab。

   ```bash
   ssh root@203.0.113.11 'cat /etc/cron.d/wp-functions'
   ssh root@203.0.113.11 'stat -c "%a %U %G" /etc/cron.d/wp-functions'
   ssh root@203.0.113.11 'crontab -l'
   ```

   文件权限应为 `644 root root`，`crontab -l` 中不应出现这两条任务的旧副本，其余条目应与下发前一致。

## deploy.sh 命令说明

| 命令 | 作用 |
| --- | --- |
| `bash deploy.sh` | 按主机清单逐台下发，已是最新的目标机会跳过 |
| `bash deploy.sh --dry-run` | 只读取目标机状态并打印将执行的操作，不写入 |
| `bash deploy.sh --check` | 只校验受管文件的内容与权限，不写入 |
| `bash deploy.sh --remove` | 备份后删除受管文件，停止调度这两条任务 |
| `bash deploy.sh --allow-existing` | 跳过“已有同名任务”检查，仅在确认不会重复执行时使用 |
| `bash deploy.sh -f hosts-prod.txt` | 使用指定主机清单 |
| `bash deploy.sh --template wp-functions.cron.cst` | 强制使用指定模板，跳过时区自动识别 |
| `bash deploy.sh --help` | 显示帮助 |

脚本按目标机顺序执行，单台失败不会中断整批任务。全部成功时退出码为 0，存在失败时为 1，参数或本地文件错误时为 2。`--hosts` 与 `--template` 的相对路径按脚本所在目录解析。

SSH 端口、私钥等连接参数可以写入 `~/.ssh/config`，也可以通过环境变量传入：

```bash
SSH_EXTRA_OPTS="-p 2222 -i $HOME/.ssh/id_ed25519" bash deploy.sh --dry-run
```

## 时区与模板

cron 的触发时刻按目标机的系统时区解释。受管文件中的 `TZ=Asia/Shanghai` 只影响任务进程看到的时区，不改变触发时刻。脚本会根据 `timedatectl` 的结果自动选择模板：

| 系统时区 | 使用模板 | 16:00 任务 | 00:00 任务 |
| --- | --- | --- | --- |
| `Asia/Shanghai` | `wp-functions.cron.cst` | `0 16` | `0 0` |
| `UTC` | `wp-functions.cron.utc` | `0 8` | `0 16` |

其他固定 UTC+8 时区（例如 `Asia/Singapore`、`Asia/Hong_Kong`、`Asia/Taipei`）可以显式指定 CST 模板：

```bash
bash deploy.sh --template wp-functions.cron.cst
```

使用 `--template` 下发后，后续执行 `--check` 也要带上相同的 `--template`，否则脚本会重新按系统时区识别并可能拒绝执行。

如果目标机使用观察夏令时的时区，固定小时无法在全年保持北京时间。此时应改用带 `OnCalendar=... Asia/Shanghai` 的 systemd timer，或在充分评估存量任务影响后统一系统时区。本方案不自动处理这类环境。

`TZ=Asia/Shanghai` 同时保证脚本内的 `date` 使用北京时间。北京时间 00:00 在 UTC 机器上对应前一天 16:00，若进程没有设置 `TZ`，按日期生成的文件名或判断会落到前一天。

Windows PowerShell 在传递远程命令时对引号、`$` 与反斜杠敏感。本方案把复杂逻辑收敛到服务端脚本，远程命令只剩一条带固定参数的 `bash ...`，可以避开转义问题。

## Windows 侧单文件下发

如果全部目标机的系统时区一致（例如都是 `Asia/Shanghai`），可以只维护一份 cron 文件，从 Windows 侧用 `scp` 下发。这种形态不依赖 WSL 或 Git Bash，控制机也不需要安装 Bash。

先批量确认时区：

```bash
ssh root@203.0.113.11 'timedatectl show -p Timezone --value'
```

全部为 `Asia/Shanghai` 时，只需使用 `wp-functions.cron.cst`，`0 16` 与 `0 0` 在所有机器上语义一致。存在 `UTC` 机器时按“时区与模板”一节分组，不要用同一份文件覆盖全部机器。

下发流程：

1. 在本地编辑 `wp-functions.cron.cst`，它就是最终落地内容。
2. 上传到目标机的临时路径。
3. 在目标机执行 `install-cron.sh`，由它完成剩余处理。

```powershell
scp .\wp-functions-cron\wp-functions.cron.cst root@${h}:/tmp/wp-functions.cron
ssh root@${h} 'bash /www/sh/wp-functions-cron/install-cron.sh -f /tmp/wp-functions.cron'
```

`${h}` 替换为 `Get-ServerList` 返回的主机名或地址；通过 `Update-Servers` 批量执行时，第二条命令可直接复用，不需要按主机改参数。

如果仓库已经整体部署到目标机，可以省掉 `scp`，让安装器读取仓库内的模板：

```powershell
ssh root@${h} 'bash /www/sh/wp-functions-cron/install-cron.sh -f /www/sh/wp-functions-cron/wp-functions.cron.cst'
```

`/www/sh` 按实际部署路径调整。这种形态下模板随仓库走 Git，换行由 `.gitattributes` 保证，`install-cron.sh` 再去一次 BOM 与 CR 作为兜底。

本机若已加载仓库的 `PS` 模块，可以直接用 `Push-FileToServers` 完成同样的落地动作，它同样做去 BOM、去 CR、原子替换、备份与写后校验：

```powershell
Push-FileToServers -Path .\wp-functions-cron\wp-functions.cron.cst -RemotePath /etc/cron.d/wp-functions -Linuxify -Backup
```

该命令不检查重复任务条目，首次迁移仍需按“已有同名任务时的迁移”手工核对，或改用 `install-cron.sh`。

校验与删除：

```powershell
ssh root@${h} 'bash /www/sh/wp-functions-cron/install-cron.sh --check -f /tmp/wp-functions.cron'
ssh root@${h} 'bash /www/sh/wp-functions-cron/install-cron.sh --remove'
```

`install-cron.sh` 以 root 身份运行，检查 root crontab、`/etc/crontab` 与其他 `/etc/cron.d` 文件中的重复条目，备份到 `/var/backups/wp-functions-cron/`，并在写后复核 SHA-256 与 `644 root root`。重复执行是安全的：内容与权限已一致时直接跳过，不产生额外备份。上传到 `/tmp` 的临时文件不会被删除，便于重复执行 `--check`。

### 与 deploy.sh 的分工

| 场景 | 建议 |
| --- | --- |
| 目标机同一时区，控制机已有批量 SSH 与 `scp` 能力 | `scp` + `install-cron.sh`，Windows 侧无需 Bash |
| 目标机时区混合（部分 CST、部分 UTC） | `deploy.sh`，按机器自动选择模板 |
| 需要在一台机器上反复执行并跳过无变化写入 | 两者都支持；`deploy.sh` 在控制机比对，减少一次写入和备份 |

### 三个容易错的地方

- 落地文件名必须是 `wp-functions`，不能带点号。`/etc/cron.d` 中带点号的文件会被 `run-parts` 静默跳过，`install-cron.sh` 会直接拒绝这类目标名。
- `scp` 直接覆盖目标路径不是原子写，cron 可能读到半截文件。`install-cron.sh` 先写同目录临时文件再改名。
- `scp` 落地后的属主与权限取决于源文件和登录用户。`install-cron.sh` 用 `install -m 0644 -o root -g root` 固定，并在写后复核。

## 下发后的验证

`deploy.sh --check` 通过只说明文件和权限正确，任务是否被 cron 调度还需要查看系统日志。该检查不覆盖 root crontab 或其他 cron 文件中的重复条目，首次迁移时仍需按“已有同名任务时的迁移”一节手工核对。cron 每分钟扫描一次配置，新文件通常在下一分钟生效；如果超过两分钟仍未生效，重启对应 cron 服务并查看系统日志。

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

到达北京时间 16:00 或 00:00 后，检查任务输出：

```bash
ssh root@203.0.113.11 'tail -n 50 /var/log/wp-functions-update.log'
```

如果需要立即验证命令本身，可以手工执行一次。该命令会立即修改站点主题目录下的 `functions.php`，执行前应确认目标机允许这样操作：

```bash
ssh root@203.0.113.11 '/bin/bash /www/sh/wp-functions-update/update_wp_functions.sh --src /www/functions4.php'
```

## 日常维护

### 修改任务时间或命令

修改 `wp-functions.cron.cst` 和 `wp-functions.cron.utc` 两个模板，保持两份内容的时间语义一致。随后先预演，再全量下发：

```bash
bash deploy.sh --dry-run
bash deploy.sh
bash deploy.sh --check
```

模板中已经包含完整的命令、环境变量和日志重定向，不需要修改 `deploy.sh`。如果 `update_wp_functions.sh` 或两个源文件的路径与默认值不同，需要同时修改两个模板，并同步修改 `deploy.sh` 中 `remote_precheck` 的预检路径；预检路径目前按 `/www/...` 硬编码。

### 新增机器

在 `hosts.txt` 中增加一行，执行 `bash deploy.sh`。已经是最新的目标机会被跳过，只有新机器和内容不一致的机器会发生写入。

### 移除机器

从 `hosts.txt` 删除对应行只能阻止后续下发，不会清理该机器上的文件。需要清理时，用只包含该机器的主机清单执行删除：

```bash
printf 'root@203.0.113.11\n' > /tmp/hosts-remove.txt
bash deploy.sh -f /tmp/hosts-remove.txt --remove
```

### 回滚

每次覆盖前，脚本会把旧文件备份到 `/var/backups/wp-functions-cron/`，文件名带时间戳。回滚时选择对应备份复制回受管路径：

```bash
ssh root@203.0.113.11 'ls -lt /var/backups/wp-functions-cron/'
ssh root@203.0.113.11 'cp -p /var/backups/wp-functions-cron/wp-functions.20261028-160000 /etc/cron.d/wp-functions'
```

复制后不需要重启 cron，下一分钟会按恢复后的内容调度。启用 SELinux 的系统需要再执行一次 `restorecon -F /etc/cron.d/wp-functions`。

### 删除任务

```bash
bash deploy.sh --remove
bash deploy.sh --check
```

`--remove` 会先备份为 `wp-functions.removed.<时间戳>`，再删除受管文件。`--check` 在删除后应当失败并提示目标文件不存在，这是预期结果。删除只影响本方案管理的两条任务，不会修改 `crontab -l` 中的任何条目。

## 故障排查

| 现象 | 可能原因 | 处理 |
| --- | --- | --- |
| `Host key verification failed` | 目标机未加入 `known_hosts` | 先手工 `ssh` 一次，或按组织规范预置 host key |
| `Permission denied (publickey)` | 控制机密钥未获授权 | 将公钥加入目标机 root 的 `authorized_keys` |
| `需要 root 权限` | 登录用户不是 root | 使用 `root@host`，或按实际环境改造远程执行部分 |
| `不支持的时区` | 系统时区不在自动识别范围 | 用 `--template wp-functions.cron.cst` 或 `.utc` 显式指定 |
| `缺少文件` | 更新脚本或源文件未部署 | 先完成 `wp-functions-update` 的部署 |
| `cron 服务未运行` | cron、crond 或 cronie 未启动 | 启动对应服务并设置开机自启 |
| 预检提示 root crontab 或 cron.d 中已有同名条目 | 服务器上存在旧任务副本 | 按“已有同名任务时的迁移”备份并删除旧条目，确认后再下发 |
| `--check` 失败但文件内容看起来正确 | 权限、属主或换行符不符 | 用 `stat` 检查 `644 root root`，并确认模板保持 LF 换行 |
| 任务没有按预期执行 | cron 未加载、时间语义不符或系统时区不是预期值 | 查看 cron 日志，并用 `systemctl status cron` 或 `systemctl status crond` 与 `timedatectl` 交叉确认 |
| 同一任务执行了两次 | 宝塔面板或用户 crontab 中存在同名任务 | 执行 `crontab -l` 与 `grep -r wp-functions /etc/cron.d`，只保留一套 |
| 日志文件没有内容 | 命令路径错误、脚本无执行权限或 cron 未运行 | 手工执行一次命令，检查 cron 日志与 `/var/log/wp-functions-update.log` 权限 |
| `restorecon` 报错 | 目标机未启用 SELinux，或文件上下文无法修正 | 未启用 SELinux 时可以忽略；已启用时手工执行 `restorecon -v /etc/cron.d/wp-functions` 检查上下文 |

## 与现有 crontab 和宝塔面板的关系

`/etc/cron.d/wp-functions` 与 root 用户的 crontab 是两套独立配置。`crontab -l` 不会显示受管文件中的两条任务，查看全部任务需要同时检查两个位置：

```bash
crontab -l
cat /etc/cron.d/wp-functions
```

宝塔面板通常只维护 root 用户的 crontab，不会读取或改写 `/etc/cron.d`。部署后仍应确认面板中没有重复创建同样的两条任务，否则同一时间会执行两次。

## 安全说明

- `hosts.txt` 可能包含真实服务器地址，已通过本目录的 `.gitignore` 排除，不应提交到仓库。
- 脚本以 root 身份写入 `/etc/cron.d`，控制机上的私钥应按最小权限保管。
- 模板只包含固定路径和命令，不接受来自目标机的任意输入。
- 受管文件权限固定为 `644 root root`，避免被普通用户改写。

## 可选：日志轮转

任务日志默认写入 `/var/log/wp-functions-update.log`，脚本不做轮转。长期运行时可以在目标机新增 `/etc/logrotate.d/wp-functions-update`：

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
