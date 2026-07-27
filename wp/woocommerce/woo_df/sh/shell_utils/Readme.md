## abstract

- 这部分脚本(.sh)在sh/shell_utils.sh中配置引用(间接被shellrc_addition.sh引用)

## 关于homebrew的安装和管理

分两类情况:
- 国外linux服务器(网络好,但是可能用的root用户,为了让root用户可以(间接)安装和使用brew,这时候我们考虑创建一个普通用户(例如linuxbrew),然后root借用这个角色权限使用brew,也可以考虑编写一个函数brewr来包装一下)
- 国内linux或者macos上安装和使用brew,这里我们主要讨论前者.因为网络环境的问题,brew的自身的安装和brew下载包的过程中如果不借助于镜像,失败率高且几乎不可用.当然用户可以使用代理来加速也是可以的.

本仓库中的homebrew环境激活的注意事项:

- 如果使用本仓库提供的一键部署shell环境,那么在`$sh/shell_var.sh`这个文件中会尝试几种管理homebrew的环境变量和激活指令(如果没有安装homebrew,则不会执行相关代码,不会污染环境.)
- 典型命令示例:

```Shell
# >>> homebrew shellenv >>>
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
# <<< homebrew shellenv <<<
```

其中`/home/linuxbrew/.linuxbrew/bin/brew shellenv`命令会生成一系列的环境变量设置语句(如果相关环境变量在当前shell会话中尚未设置的话,才会输出,或者用`$()`接收输出).然后我们用`eval`执行这些语句.

- 如果直接将homebrew的激活指令添加到`.zshrc`或`.bashrc`中,也可以,重复配置不会有什么问题.

### 设计与函数入口

网络环境、操作系统和安装身份是三个独立维度。例如，Linux 既可能位于国内，
也可能位于海外；国内用户既可以使用镜像，也可以使用代理访问官方源。因此核心
入口统一为：

```bash
install_brew [options]
```

原有函数继续保留，作为场景包装器：

- `install_brew_cn`：只提供 USTC 镜像和安装脚本默认值，不创建或切换用户。
- `install_linuxbrew`：仅供 root 使用，默认从官方源创建或复用
  `linuxbrew` 专用用户；普通用户调用会直接报错。
- `brewr`：root 以专用用户身份执行 brew；普通用户直接执行 PATH 中的 brew。
- `cleanup_linuxbrew_dedicated_user`：从专用用户布局迁移回普通 sudo 用户布局；
  默认只预览，必须显式传入 `--execute` 才修改系统。

这些函数都在 `shell_utils/brew.sh` 中，不依赖本仓库的其他函数。运行时仍需要
操作系统提供 `bash`、`curl`、`git`、`awk`、`mktemp` 等基础命令；创建用户或
切换身份时需要 `sudo` 或 `runuser`。

安装身份必须显式且稳定：

| 当前身份 | 推荐入口 | 是否创建专用用户 |
| --- | --- | --- |
| 普通 sudo 用户 | `install_brew` 或 `install_brew_cn` | 否，Homebrew 归当前用户 |
| root | `install_linuxbrew` | 是，默认创建 `linuxbrew` |
| root + 国内镜像 | `install_brew --mirror ustc --user linuxbrew --create-user` | 是 |

普通用户传入 `--create-user`，或者调用 `install_linuxbrew`，都会得到明确错误，
不会静默创建账号，也不会悄悄切换成其他安装模式。

`new_user` 是底层系统用户管理工具，不是普通用户安装 Homebrew 的前置步骤。
只有明确维护服务器账号时才直接调用它；Homebrew 安装流程会在 root 且明确指定
`--create-user` 时调用它。

### Homebrew 安装目录和普通用户权限

Homebrew 官方安装器使用固定的受支持前缀：

| 平台 | 标准前缀 |
| --- | --- |
| Linux | `/home/linuxbrew/.linuxbrew` |
| Apple Silicon macOS | `/opt/homebrew` |
| Intel macOS | `/usr/local` |

Linux 普通用户运行 `install_brew` 或 `install_brew_cn` 时，不会默认安装到自己的
`~/.linuxbrew`。首次创建标准前缀通常需要 sudo；官方安装器会在交互模式下请求
密码。用户没有 sudo 权限且标准前缀尚未准备好时，安装会失败，这是预期行为。

不推荐通过手工 clone 将 Homebrew 强制放入 `~/.linuxbrew`。非标准前缀不属于
Homebrew 的主要支持路径，部分预编译 bottle 无法直接使用，可能退回源码编译，
增加安装时间、构建依赖和失败概率。确实需要无 sudo 的用户级包管理器时，应该
优先评估 Nix、mise 等原生支持用户目录的方案。

### 海外 Linux 服务器：root 间接使用 Homebrew

Homebrew 拒绝直接以 root 身份运行。推荐创建独立普通用户，让 root 通过该身份
安装和管理软件：

```bash
install_linuxbrew
brewr install jq
brewr update
```

默认用户为 `linuxbrew`，也可以显式指定：

```bash
install_linuxbrew --user linuxbrew
brewr --user linuxbrew install fd
```

即使指定其他用户名，Linux 的 Homebrew 标准前缀仍是
`/home/linuxbrew/.linuxbrew`。root 会在该目录尚不存在时创建它并交给目标用户；
如果目录已经存在但属于其他用户，函数会拒绝修改其属主，避免破坏已有安装。

`install_linuxbrew` 创建的专用用户默认没有登录密码，也不会被授予 sudo 权限。
这是刻意的最小权限设计。root 通过 `sudo -u` 或 `runuser` 切换身份，Homebrew
本身及其安装的软件仍归专用用户所有。

本节只适用于当前 shell 的有效 UID 是 0 的情况。普通用户即使拥有 sudo 权限，
也应直接运行 `install_brew`，让官方安装器在准备标准前缀时按需请求 sudo 密码；
不要先调用用户创建函数，也不要运行 `sudo install_linuxbrew`，除非明确决定采用
“root 管理、专用用户持有 Homebrew”的服务器布局。

### 国内普通用户：使用镜像

默认兼容入口使用 USTC：

```bash
install_brew_cn
```

也可以使用统一入口明确选择镜像：

```bash
install_brew --mirror ustc
install_brew --mirror tuna
install_brew --mirror aliyun
```

`--mirror` 同时影响 brew 仓库、API 和 bottle 下载地址。未指定
`--installer-source` 时，安装脚本来源默认跟随镜像；需要混合使用时可以分别
指定：

```bash
install_brew --mirror ustc --installer-source official
```

只切换已经安装好的 Homebrew，不重新安装：

```bash
install_brew --mirror tuna --update-mirror-only
brew update
```

恢复官方源并清理脚本管理的镜像环境变量：

```bash
install_brew --reset-mirror
```

镜像配置使用带起止标记的管理块写入当前 shell 的 rc 文件，重复执行不会追加
重复内容，并会自动迁移旧版本 `brew.sh` 写入的镜像块。可以用 `--rc FILE`
指定文件，或用 `--no-write-env` 只影响当前 shell。

### 国内用户：使用代理和官方源

如果代理稳定，使用官方源通常比依赖某个镜像更及时：

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5://127.0.0.1:7890

install_brew --mirror official
```

只需要设置实际可用的代理变量。安装器和 `brewr` 会显式传递 Homebrew 镜像变量
以及大小写形式的代理变量，避免它们在 sudo 切换用户时被默认过滤。

### 常用选项

```text
--mirror NAME              official、ustc、tuna 或 aliyun
--installer-source NAME    单独指定安装脚本来源
--user USER                root 指定非 root 安装用户
--create-user              指定用户不存在时创建
--update-mirror-only       仅更新镜像配置
--reset-mirror             恢复官方源
--rc FILE                  指定持久化配置文件
--no-write-env             不写入 shell rc
--non-interactive          禁止交互；需要输入 sudo 密码时不要使用
--force                    即使检测到 brew 也重新安装
--uninstall                运行官方卸载脚本
```

运行 `install_brew --help`、`install_brew_cn --help`、
`install_linuxbrew --help` 或 `brewr --help` 可以查看内置帮助。

### 系统依赖

Homebrew 不负责安装最初的编译工具。Linux 上可先执行：

```bash
# Debian / Ubuntu
sudo apt-get install build-essential procps curl file git

# Fedora / RHEL
sudo dnf group install 'Development Tools'
sudo dnf install procps-ng curl file git

# Arch Linux
sudo pacman -S base-devel procps-ng curl file git
```

### 权限冲突排查

如果普通用户安装时看到类似错误：

```text
cd: /home/linuxbrew/.linuxbrew/Homebrew: Permission denied
/usr/.git: Permission denied
Failed during: /usr/bin/git ... init
```

真正的首个错误是无法进入 `/home/linuxbrew/.linuxbrew/Homebrew`。后面的
`/usr/.git` 通常是镜像安装脚本在 `cd` 失败后没有及时退出而产生的连锁错误，
不是 Homebrew 计划安装到 `/usr`。

先检查目录和账号：

```bash
ls -ld /home/linuxbrew /home/linuxbrew/.linuxbrew
getent passwd linuxbrew
```

如果 `/home/linuxbrew` 属于专用的 `linuxbrew` 用户，应继续使用专用用户方案，
不要让当前普通用户接管目录：

```bash
# 在 root shell 中完成安装并使用
install_linuxbrew
brewr install jq
```

国内网络下，root 可以为专用用户选择镜像：

```bash
install_brew --mirror ustc --user linuxbrew --create-user --no-write-env
brewr install jq
```

如果确定不再使用专用用户，而是要让当前普通用户拥有 Homebrew，需要先备份并
显式删除旧安装，或者由管理员确认后转移整个标准前缀的属主。脚本不会自动执行
`chown -R`，因为这会破坏另一个用户正在使用的 Homebrew。不要只为绕过报错而
把 `/home/linuxbrew` 改成全局可写。

#### 从专用用户迁移到官方普通用户方案

对于个人工作站，如果希望安装效果尽可能接近官方命令，推荐清理专用账号后，
由日常普通 sudo 用户重新安装。不要只删除 `.linuxbrew`：专用账号的家目录本身
就是 `/home/linuxbrew`，只删内部目录仍会留下属主和 `750` 权限冲突。

脚本提供一个范围严格、默认只预览的迁移函数：

```bash
source /home/cxxu/sh/shell_utils/brew.sh

# 只读预览，不修改系统
cleanup_linuxbrew_dedicated_user

# 确认预览后执行；这里会交互请求 sudo 密码
cleanup_linuxbrew_dedicated_user --execute
```

执行模式会拒绝终止正在运行的进程，不直接删除家目录，而是将其移动到类似下面
的 root 私有备份：

```text
/home/linuxbrew.dedicated-backup-20260724-153000
```

随后删除 `linuxbrew` 账号、空的同名私有组、本脚本创建的
`/etc/sudoers.d/linuxbrew_nopasswd`，并列出其他仍引用该用户名的 sudoers 文件。
备份不会自动删除；确认新 Homebrew 和所需数据均正常后，再由管理员手工处理。

清理完成后回到普通用户 shell，使用官方安装器配合代理最接近官方效果：

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
install_brew --mirror official --installer-source official
```

无法访问 GitHub 安装脚本时，可以使用 USTC 安装器和镜像：

```bash
install_brew --mirror ustc --installer-source ustc
```
