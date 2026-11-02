## 概述

个人电脑与 Linux 服务器共用的一套 shell 脚本库，兼容 bash 与 zsh；与 [PowerShell 模块集](../../../../PS/) 相互独立，可单独部署。

- `$sh` 约定指向本目录：部署脚本会把仓库落到 `$HOME/repos/scripts`，再建立 `~/sh` 链接并写入 shellrc。
- 服务器专用的 nginx、fail2ban 等配置只在本目录的对应子目录中维护；shell 部署不触碰服务器软件配置。
- 单个脚本的原始链接可从仓库页面的 raw 处获取，github 与 gitee 均可。

## 一键部署

未部署过则完整克隆，已部署则更新代码。

### 个人电脑端

具备 bash 的设备都可以使用(会跳过服务器软件相关配置的处理阶段)。

```bash
bash <(curl -sSfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/update_shell_config.sh)
```

### Linux 服务器端

参数语义以脚本内 `print_usage` 为准：`-U` 更新 shellrc，`-F` 强制更新配置文件(含覆盖 `nginx.conf`，酌情使用)，`-R` 使用非默认的客户 IP 解析。

```bash
## github
bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh) -U # -F -R
## gitee(国内)
bash <(curl -SfL https://raw.giteeusercontent.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/update_repos.sh) -U # -F -R
```

### Linux 虚拟机或模拟层

WSL 或 Lima 等轻量虚拟平台可以按普通 Linux 系统的方式部署。

考虑到维护与一致性，也可以与宿主机共用仓库(前置：先定义 `_REPO_BASE="repos/scripts"` 与 `_SH_RELATIVE="wp/woocommerce/woo_df/sh"`；WSL 连接 Windows 侧仓库，Lima 连接 macOS 宿主仓库)：

```bash
# wsl
ln -snfv /mnt/c/repos ~/repos
ln -snfv /mnt/c/$_REPO_BASE/$_SH_RELATIVE ~/sh
bash ~/sh/shellrc_addition.sh && exec bash
# lima(mac)
ln -snfv $HOME/repos ~/repos
ln -snfv $HOME/$_REPO_BASE/$_SH_RELATIVE ~/sh
bash ~/sh/shellrc_addition.sh && exec bash
```

## 修复与自救

更新脚本自身损坏(尤其是早期仓库)时，绕过 `$sh` 直接获取并执行：首次使用时 `$sh` 未定义，脚本会尝试下载到根目录。

```bash
curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh -o $HOME/update_repos.sh && bash $HOME/update_repos.sh
```

## 交互式 shell 增强

适用于 Linux/macOS，提供交互式补全与提示增强。

### zsh / Oh My Zsh

需要动态补全、历史建议与语法高亮时，先补齐系统依赖，再部署 omz 与插件。以下操作只改当前用户的家目录，不影响 bash 配置。

```bash
# 如果了解系统包管理器，直接安装依赖，例如：
apt install zsh # 适用于 Debian/Ubuntu
```

通用依赖检查/安装(对不同系统包管理器的一层薄包装)：

```bash
curl -SfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/install_shell_deps.sh -o ~/install_shell_deps.sh

# 依赖检查(只读，缺失时返回非零状态)
bash ~/install_shell_deps.sh --check
# 安装缺失依赖(Linux 走发行版包管理器，macOS 走 Homebrew)
bash ~/install_shell_deps.sh -y
```

- [install_shell_deps.sh](install_shell_deps.sh)：检查并安装 `zsh`、`git`、`curl`、`tar`(macOS 另需 `gnu-sed`)；支持 apt-get、dnf、yum、apk、pacman、zypper、xbps-install、emerge、eopkg 与 Homebrew。参数：`--check` 只检查，`-n` 空跑，`-y` 非交互安装。Windows 的 git-bash / MSYS2 / Cygwin 没有可安装的 zsh，脚本只做检查并给出 WSL 指引。

```bash
# 部署 oh-my-zsh 与插件；首次安装 omz 后脚本会中断，重跑一次即可
bash <(curl -sSfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/deploy_omz.sh) -s github
```

- [deploy_omz.sh](deploy_omz.sh)：安装 omz、补全/建议/高亮插件及 `zasync` 依赖；`-U` 更新已装插件，`-zac-ref` 钉扎 `zsh-autocomplete` 版本，`-o false` 跳过 omz 安装。
- 插件清单、版本钉扎、更新与故障排查见 [Readme@deploy_omz.md](Readme@deploy_omz.md)。

### fish

开箱即用的交互式友好 shell，可通过系统包管理器安装。

## 手动克隆

不使用一键脚本时，按普通 git 仓库克隆，再建立 `~/sh` 链接并加载 shellrc：

```bash
repos="$HOME/repos"
scripts="$repos/scripts"
repo_source="github.com"
mkdir -p "$repos"
git clone --recursive --depth 1 --shallow-submodules https://"$repo_source"/xuchaoxin1375/scripts.git "$scripts"
# 配置 shell 脚本库(兼容 bash/zsh)
sh_script_dir="$scripts/wp/woocommerce/woo_df/sh"
sh_sym="$HOME/sh" sh="$sh_sym"
ln -snfv "$sh_script_dir" "$sh_sym"
bash $sh/shellrc_addition.sh # 部署 prompt 主题与补全
exec bash # 使配置生效
```

`repo_source` 在国内直连不通时更换代理或镜像；gitee 备选可能要求登录。Windows 上克隆前先关闭 `core.autocrlf`，否则 `.sh` 的换行会被改写为 CRLF 而无法执行：

```bash
git config --global core.autocrlf false
```

精简系统(如 alpine linux)需先安装 bash 与 git：`sudo apk add bash git`。

## 文档入口

| 文档 | 说明 |
|---|---|
| [Readme@服务器环境配置流程和迁移指南.md](Readme@服务器环境配置流程和迁移指南.md) | 服务器环境配置流程与迁移 |
| [Readme@deploy_omz.md](Readme@deploy_omz.md) | omz 与插件清单、版本钉扎、更新与排障 |
| [Readme@deploy_wp_full.md](Readme@deploy_wp_full.md) | WordPress 站点完整部署设计 |
| [Readme@qps.md](Readme@qps.md) | `qps.sh`：nginx 聚合日志实时 QPS 监控 |
| [nginx_conf/Readme.md](nginx_conf/Readme.md) | nginx 配置总入口 |
| [tool_installer/README.installers-best-practices.md](tool_installer/README.installers-best-practices.md) | GitHub Release 安装脚本的编写规范 |
| [update-cron/README.md](update-cron/README.md) | 多服务器定时任务批量下发 |
| [uptime_checks/README.md](uptime_checks/README.md) | 反向代理节点与业务页面拨测 |
| [wp-functions-update/README.md](wp-functions-update/README.md) | 批量更新站点主题 `functions.php` |
