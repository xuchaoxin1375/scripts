# btop 通用安装脚本

[`install_btop.sh`](./install_btop.sh) 是面向国内外 Linux 环境的 [btop](https://github.com/aristocratos/btop) 安装、更新与卸载脚本。默认安装最新官方预编译二进制，避免 Debian stable 等系统仓库版本偏旧；系统包仍可显式选择。

> 规格层级：本脚本属于工具安装器的「完整层」参考实现，口径见 [README.installers-best-practices.md](./README.installers-best-practices.md)。新建工具安装脚本默认按「基础层」编写，不需要复制这里的主题、桌面入口、卸载清单与全架构矩阵。

## 功能

- 支持 Debian/Ubuntu、Fedora/RHEL 系、Alpine、Arch、openSUSE、Void、Gentoo 和 Solus 的系统包管理器。
- `binary`、`package` 两种安装方式；`auto` 是 `binary` 的兼容别名。
- 使用 [`net_is_cn.sh`](../shell_utils/net_is_cn.sh) 优化 GitHub 直连与文件镜像顺序，也可显式指定通道。
- curl 支持 HTTP、HTTPS、SOCKS4/5 代理。
- Release 模式按上游资产清单映射 CPU 架构，覆盖 x86_64、aarch64、armv7、arm、i686、i586、riscv64、s390x、mips64、powerpc64、m68k。
- 同时部署 Release 自带主题与 `btop.desktop` 桌面入口，可用 `--no-themes`、`--no-desktop` 跳过。
- 支持指定版本、自定义目录、强制覆盖、卸载、dry-run 和可选 SHA-256 校验。
- 下载到独立临时目录，检查压缩包路径、运行下载程序核对版本，再原子替换目标。
- 卸载只删除本脚本安装的主题文件与桌面入口，不扫描目录删除其他内容。

## 快速开始

脚本要求 Bash，不要用 `sh` 执行：

```bash
chmod +x install_btop.sh
./install_btop.sh
```

默认解析 GitHub 最新 Release，下载与当前 CPU 匹配的压缩包。普通用户安装到 `~/.local/bin/btop`，主题与桌面入口落在 `~/.local/share`；root 执行时对应 `/usr/local/bin/btop` 与 `/usr/local/share`。这条路径只依赖 Bash、curl、tar 和常见基础命令，不需要 C++ 工具链或系统开发包。

查看所有选项：

```bash
./install_btop.sh --help
```

查看 auto 检测到的国家、候选通道、每个实际请求 URL、latest 版本来源以及架构与安装决策：

```bash
./install_btop.sh --mirror auto --verbose
```

verbose 是结构化决策日志，不会启用可能泄露请求头的 `curl -v`。代理 URL 的用户信息和 URL 查询参数会脱敏；如果设置了标准 curl 代理环境变量，日志会显示变量名和脱敏后的地址。

## 安装方式

| 方式 | 适用场景 | 特点 |
| --- | --- | --- |
| `auto` | 兼容别名 | 与 `binary` 相同，保留给旧调用方式 |
| `package` | 服务器、长期维护 | 使用发行版仓库，自动获得发行版安全更新 |
| `binary` | 要求新版或固定版本 | 下载官方预编译 Release，不依赖编译环境 |

系统包安装：

```bash
sudo ./install_btop.sh --method package
```

当前用户安装最新官方 Release：

```bash
./install_btop.sh --method binary
```

安装固定版本：

```bash
./install_btop.sh --method binary --version 1.4.8
```

指定目录：

```bash
./install_btop.sh --method binary --install-dir "$HOME/bin"
```

## 平台与资产

上游只为 Linux 发布静态链接的 musl 包，文件名形如 `btop-<target>.tar.gz`，不区分 glibc 与 musl；因此同一个资产可以运行在 Debian、Alpine 等发行版上。脚本按 `uname -m` 选择资产，未知架构直接失败，不会猜测文件名。

| 本机架构 | 使用的资产目标 |
| --- | --- |
| x86_64、amd64 | `x86_64-unknown-linux-musl` |
| aarch64、arm64 | `aarch64-unknown-linux-musl` |
| i686 | `i686-unknown-linux-musl` |
| i386、i486、i586 | `i586-unknown-linux-musl` |
| armv7l、armv7、armv8l | `armv7-unknown-linux-musleabi` |
| armv6l、arm | `arm-unknown-linux-musleabi` |
| riscv64 | `riscv64-unknown-linux-musl` |
| s390x | `s390x-ibm-linux-musl` |
| mips64 | `mips64-unknown-linux-musl` |
| powerpc64 | `powerpc64-unknown-linux-musl` |
| m68k | `m68k-unknown-linux-musl` |

上游只提供大端 `mips64` 与 `powerpc64` 资产，小端 `mips64el`、`ppc64le` 会明确报错并建议改用 `package` 模式。macOS 没有 Release 资产，脚本会提示使用 `brew install btop`；Windows 请在 WSL 中运行。

资产命名随上游发布策略变化。脚本按 v1.4 系列的资产结构实现，固定更早或更晚的版本时请先核对[上游 Release](https://github.com/aristocratos/btop/releases)。

## 国内网络

### GitHub 镜像

`--mirror auto` 首次需要下载通道时会加载 [`net_is_cn.sh`](../shell_utils/net_is_cn.sh)，且本次运行只检测一次。CN 出口依次尝试 `ghfast.top`、`gh-proxy.com`、`ghproxy.net`，最后以 GitHub 直连兜底；非 CN 或无法判断时先尝试 GitHub 直连，再回退到这些镜像。辅助脚本缺失时按 UNKNOWN 处理并优先直连。

如果显式使用 `--proxy`，地区检测也经该代理判断实际出口。显式指定 `direct`、内置镜像或自定义镜像时不会执行地区检测。镜像属于第三方服务，可用性和可信边界可能变化；敏感环境建议使用可信代理、自建镜像并通过 `--sha256` 固定校验值。

```bash
# 强制使用内置镜像
./install_btop.sh -m binary --mirror ghfast

# 使用 ghproxy.net
./install_btop.sh -m binary --mirror ghproxynet

# GitHub 直连，不回退
./install_btop.sh -m binary --mirror direct

# 自定义“前缀/原始 GitHub URL”形式的镜像
./install_btop.sh -m binary --mirror https://mirror.example.com
```

### 代理

```bash
./install_btop.sh -m binary --proxy http://127.0.0.1:7890
./install_btop.sh -m binary --proxy socks5h://127.0.0.1:7890
```

`--proxy` 只作用于脚本发起的 curl 请求，不修改系统配置。系统包管理器应使用其自身配置；也可以按环境需要预先导出 `http_proxy` 和 `https_proxy`。

脚本当前不调用 `api.github.com`，而是从 `github.com/aristocratos/btop/releases/latest` 的重定向解析版本。`--mirror` 仅应用于 GitHub Release 页面和文件；代码会拒绝为 `api.github.com` 拼接文件镜像前缀。

## 主题与桌面入口

Release 压缩包除可执行文件外，还带有官方主题目录与 `btop.desktop`。binary 模式默认安装这两项：

- 可执行文件：`<安装目录>/btop`。
- 主题文件：`<share 根目录>/btop/themes/`，并在同目录写入 `.install_btop.manifest` 清单。
- 桌面入口：`<share 根目录>/applications/btop.desktop`，`Exec` 改写为可执行文件绝对路径，避免桌面环境不继承自定义 `PATH`。

`share 根目录` 默认为安装目录的同级 `share`：`/usr/local/bin` 对应 `/usr/local/share`，`~/.local/bin` 对应 `~/.local/share`。需要集中部署时用 `--share-dir` 指定绝对路径：

```bash
sudo ./install_btop.sh -m binary --install-dir /opt/btop/bin --share-dir /opt/btop/share
```

跳过共享资源：

```bash
./install_btop.sh --no-themes --no-desktop
```

主题目录内的同名文件会被覆盖，清单只记录本次安装的文件，因此卸载不会删除目录中的其他主题。桌面入口若已存在且不是本脚本生成，默认拒绝覆盖；确认后使用 `--force`。

btop 首次运行会在 `~/.config/btop/` 生成个人配置，卸载不会删除该目录。

## 更新、卸载与演练

再次运行相同命令即可检查更新。目标版本（包括解析出的远程最新版）已安装时会跳过归档下载；目标版本更高时会在下载前询问是否升级，默认回答为 No。

```bash
# 交互确认升级
./install_btop.sh

# 定时任务或其他非交互环境
./install_btop.sh --yes
```

脚本不实现降级功能：目标版本低于现有版本时直接失败，`--force` 和 `--yes` 都不会绕过。`--yes` 只跳过升级确认；`--force` 用于重装同版本或替换无法识别的冲突目标。

```bash
# 先查看将执行的持久化变更命令
sudo ./install_btop.sh -m package --dry-run

# 卸载发行版包
sudo ./install_btop.sh -m package --uninstall

# 删除当前用户默认目标及其主题、桌面入口
./install_btop.sh -m binary --uninstall

# 删除自定义目录
./install_btop.sh -m binary --install-dir "$HOME/bin" --share-dir "$HOME/share" --uninstall
```

卸载严格按所选方式和目录工作，不会搜索并删除其他位置的同名程序。已知版本已安装但共享资源缺失时，可用 `--force` 重新安装一次以补齐主题与桌面入口。

`binary --dry-run` 不会写入安装目录，但仍会联网下载到临时目录，并完成归档与版本验证；退出时清理临时文件。`package --dry-run` 只打印命令。

package 模式不指定版本，由系统包管理器决定升级事务；默认保留包管理器确认提示，传入 `--yes` 才使用其非交互确认参数。该模式的主题与桌面入口由发行版包提供，`--no-themes`、`--no-desktop` 会被忽略并提示。

## 运行依赖

- 所有模式需要 Bash 4 或更新版本和常见基础命令。
- `package` 需要一个受支持的系统包管理器；非 root 用户还需要 `sudo`。
- `binary` 需要 `curl`、`tar`、`grep`、`awk` 和常见 coreutils 工具。

脚本会明确报告缺失命令，但不会擅自安装构建工具或改写软件源。

## 完整性与安全

GitHub Release 下载始终使用 HTTPS。还可从可信渠道取得对应压缩包的 SHA-256 后显式校验：

```bash
./install_btop.sh -m binary -v 1.4.8 --sha256 <64位十六进制摘要>
```

未指定摘要时，脚本仍会：

- 让 tar 验证 gzip/tar 格式。
- 拒绝绝对路径和包含 `..` 的成员路径。
- 只提取唯一的 `bin/btop`、`themes/*.theme` 与 `btop.desktop`，并要求主题与程序都是常规文件。
- 执行 `btop -v`，要求版本与请求版本一致。
- 在目标目录暂存并原子替换，避免半写入文件。

第三方镜像并不等同于官方信任源。需要强供应链保证时，请提供 SHA-256，或在组织内托管经过验证的 Release 文件。上游未发布独立 checksum 文件，脚本不会编造校验值。

btop 官方源码提供可选的 setuid 安装方式，用于让普通用户读取部分受限信息。本脚本不修改 setuid 位；确有需要时请按组织安全策略单独评估。

## 常见问题

`btop: command not found`：确认安装目录在 `PATH` 中。普通用户默认目录可这样加入 Bash/Zsh：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

RHEL/Alma/Rocky 的仓库找不到 `btop`：该包位于 EPEL。脚本不会擅自启用第三方系统仓库；可先按组织策略启用仓库，或直接使用：

```bash
./install_btop.sh --method binary
```

旧系统运行 Release 报错：musl 静态包对内核版本的要求低于 glibc 动态链接包；若仍失败，请升级系统或改用发行版 package 模式。

桌面菜单看不到 btop，但命令行可用：说明 `btop.desktop` 未被桌面环境识别。确认 `--share-dir` 指向 `$XDG_DATA_HOME` 或 `~/.local/share`，必要时重新登录桌面会话。

## 环境与退出状态

- 支持 `NO_COLOR=1` 禁用彩色日志。
- 尊重 curl 支持的标准代理和证书环境变量。
- 成功返回 `0`；参数、网络、校验、安装或验证失败返回非零值。
- 临时文件在正常退出、失败或中断时自动清理。
