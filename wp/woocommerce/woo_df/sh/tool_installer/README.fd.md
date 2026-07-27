# fd 通用安装脚本

[`install_fd.sh`](./install_fd.sh) 是面向国内外 Linux 环境的 fd 安装、更新与卸载脚本。设计依据 [fd 官方安装指南](https://github.com/sharkdp/fd#installation)。默认安装最新官方预编译二进制，避免 Debian stable 等系统仓库版本偏旧；系统包仍可显式选择。

## 功能

- 支持 Debian/Ubuntu、Fedora/RHEL 系、Alpine、Arch、openSUSE、Void、Gentoo 和 Solus 的系统包管理器。
- `binary`、`package` 两种安装方式；`auto` 是 `binary` 的兼容别名。
- 使用 [`net_is_cn.sh`](../shell_utils/net_is_cn.sh) 优化 GitHub 直连与文件镜像顺序，也可显式指定通道。
- curl 支持 HTTP、HTTPS、SOCKS4/5 代理。
- Release 模式支持 x86_64、aarch64、armv7 hard-float、i686，并自动区分 glibc 与 musl。
- 支持指定版本、自定义目录、强制覆盖、卸载、dry-run 和可选 SHA-256 校验。
- 下载到独立临时目录，检查压缩包路径、运行下载程序核对版本，再原子替换目标。
- Debian 系安装后自动创建 `fd` 兼容链接；已有冲突文件时默认拒绝覆盖。

## 快速开始

脚本要求 Bash，不要用 `sh` 执行：

```bash
chmod +x install_fd.sh
./install_fd.sh
```

默认解析 GitHub 最新 Release，下载与当前 CPU/libc 匹配的压缩包。普通用户安装到 `~/.local/bin/fd`；root 执行时安装到 `/usr/local/bin/fd`。这条路径只依赖 Bash、curl、tar 和常见基础命令，不需要 Rust 工具链或系统开发包。

查看所有选项：

```bash
./install_fd.sh --help
```

查看 auto 检测到的国家、候选通道、每个实际请求 URL、latest 版本来源以及架构/安装决策：

```bash
./install_fd.sh --mirror auto --verbose
```

verbose 是结构化决策日志，不会启用可能泄露请求头的 `curl -v`。版本解析日志会分别标明机制（`github.com/.../releases/latest` 重定向）、是否使用 GitHub API，以及实际传输通道（直连或文件镜像）；“经文件镜像解析重定向”不表示 `api.github.com` 经过镜像。代理 URL 的用户信息和 URL 查询参数会脱敏；如果设置了标准 curl 代理环境变量，日志会显示变量名和脱敏后的地址。

## 安装方式

| 方式 | 适用场景 | 特点 |
| --- | --- | --- |
| `auto` | 兼容别名 | 与 `binary` 相同，保留给旧调用方式 |
| `package` | 服务器、长期维护 | 使用发行版仓库，自动获得发行版安全更新 |
| `binary` | 要求新版或固定版本 | 下载官方预编译 Release，不依赖 Rust 工具链 |

系统包安装：

```bash
sudo ./install_fd.sh --method package
```

当前用户安装最新官方 Release：

```bash
./install_fd.sh --method binary
```

安装固定版本：

```bash
./install_fd.sh --method binary --version 10.4.2
```

指定目录：

```bash
./install_fd.sh --method binary --install-dir "$HOME/bin"
```

## 国内网络

### GitHub 镜像

`--mirror auto` 首次需要下载通道时会加载 [`net_is_cn.sh`](../shell_utils/net_is_cn.sh)，且本次运行只检测一次。CN 出口依次尝试 `ghfast.top`、`gh-proxy.com`、`ghproxy.net`，最后以 GitHub 直连兜底；非 CN 或无法判断时先尝试 GitHub 直连，再回退到这些镜像。辅助脚本缺失时按 UNKNOWN 处理并优先直连。

如果显式使用 `--proxy`，地区检测也经该代理判断实际出口。显式指定 `direct`、内置镜像或自定义镜像时不会执行地区检测。镜像属于第三方服务，可用性和可信边界可能变化；敏感环境建议使用可信代理、自建镜像并通过 `--sha256` 固定校验值。

```bash
# 强制使用内置镜像
./install_fd.sh -m binary --mirror ghfast

# 使用 ghproxy.net
./install_fd.sh -m binary --mirror ghproxynet

# GitHub 直连，不回退
./install_fd.sh -m binary --mirror direct

# 自定义“前缀/原始 GitHub URL”形式的镜像
./install_fd.sh -m binary --mirror https://mirror.example.com
```

### 代理

```bash
./install_fd.sh -m binary --proxy http://127.0.0.1:7890
./install_fd.sh -m binary --proxy socks5h://127.0.0.1:7890
```

`--proxy` 只作用于脚本发起的 curl 请求，不修改系统配置。系统包管理器应使用其自身配置；也可以按环境需要预先导出 `http_proxy` 和 `https_proxy`。

脚本当前不调用 `api.github.com`，而是从 `github.com/sharkdp/fd/releases/latest` 的重定向解析版本。`--mirror` 仅应用于 GitHub Release 页面和文件；代码会拒绝为 `api.github.com` 拼接文件镜像前缀。未来若增加 API 请求，也只能直连或通过 `--proxy` 访问。

## Debian/Ubuntu 的 fd 与 fdfind

官方仓库中的包名为 `fd-find`。为避免和另一个历史软件包冲突，其可执行文件名为 `fdfind`。脚本默认创建兼容链接：

```text
~/.local/bin/fd -> /usr/bin/fdfind
```

跳过链接：

```bash
sudo ./install_fd.sh -m package --no-alias
```

如果链接位置已有其他文件，脚本会停止。确认可覆盖后使用 `--force`。Release 包中的程序本来就叫 `fd`，无需链接。

## 更新、卸载与演练

再次运行相同命令即可检查更新。目标版本（包括解析出的远程最新版）已安装时会跳过归档下载；目标版本更高时会在下载前询问是否升级，默认回答为 No。

```bash
# 交互确认升级
./install_fd.sh

# 定时任务或其他非交互环境
./install_fd.sh --yes
```

脚本不实现降级功能：目标版本低于现有版本时直接失败，`--force` 和 `--yes` 都不会绕过。`--yes` 只跳过升级确认；`--force` 用于重装同版本或替换无法识别的冲突目标。

```bash
# 先查看将执行的持久化变更命令
sudo ./install_fd.sh -m package --dry-run

# 卸载发行版包，并仅删除指向 fdfind 的兼容链接
sudo ./install_fd.sh -m package --uninstall

# 删除当前用户默认 Release 目标 ~/.local/bin/fd
./install_fd.sh -m binary --uninstall

# 删除自定义目标
./install_fd.sh -m binary --install-dir "$HOME/bin" --uninstall

```

卸载严格按所选方式工作，不会搜索并删除其他目录中的同名程序。

`binary --dry-run` 不会写入安装目录，但仍会联网下载到临时目录，并完成归档与版本验证；退出时会清理这些临时文件。`package --dry-run` 只打印命令。

版本更新策略适用于默认 binary 模式。package 模式不指定版本，由系统包管理器决定升级事务；默认保留包管理器确认提示，传入 `--yes` 才使用其非交互确认参数。Cargo 等外部生态安装器未实现，避免引入 Rust 工具链、索引配置和另一套更新语义。

## 运行依赖

- 所有模式需要 Bash 4 或更新版本和常见基础命令。
- `package` 需要一个受支持的系统包管理器；非 root 用户还需要 `sudo`。
- `binary` 需要 `curl`、`tar`、`find` 和常见 coreutils 工具。

脚本会明确报告缺失命令，但不会擅自安装构建工具或改写软件源。这样在服务器和受管环境中不会引入未审核的系统级变更。

## 完整性与安全

GitHub Release 下载始终使用 HTTPS。还可从可信渠道取得对应压缩包的 SHA-256 后显式校验：

```bash
./install_fd.sh -m binary -v 10.4.2 --sha256 <64位十六进制摘要>
```

未指定摘要时，脚本仍会：

1. 让 tar 验证 gzip/tar 格式。
2. 拒绝绝对路径和包含 `..` 的成员路径。
3. 只选择名为 `fd` 的可执行文件。
4. 执行 `fd --version`，要求与请求版本完全一致。
5. 在目标目录暂存并原子替换，避免半写入文件。

第三方镜像并不等同于官方信任源。需要强供应链保证时，请提供 SHA-256，或在组织内托管经过验证的 Release 文件。

节点发现可参考 [gh-proxy issue #116](https://github.com/hunshcn/gh-proxy/issues/116) 和 [GitHub 文件加速聚合页](https://yishijie.gitlab.io/ziyuan/)。这些列表具有时效性，且部分为未知第三方运营；脚本不会远程加载后自动信任全部节点。选定并审核节点后，可通过 `--mirror https://节点地址` 使用。

## 常见问题

`fd: command not found`：确认安装目录在 `PATH` 中。普通用户默认目录可这样加入 Bash/Zsh：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

RHEL/Alma/Rocky 的仓库找不到 `fd-find`：官方指南建议启用 EPEL，或使用 Fedora Copr 的 `tkbcopr/fd`。脚本不会擅自启用第三方系统仓库；可先按组织策略启用仓库，或直接使用：

```bash
./install_fd.sh --method binary
```

旧系统运行 Release 报 glibc 版本错误：优先升级系统；也可在支持架构上使用 Alpine/musl 环境对应包，或显式改用发行版 package 模式。

## 环境与退出状态

- 支持 `NO_COLOR=1` 禁用彩色日志。
- 尊重 curl 支持的标准代理和证书环境变量。
- 成功返回 `0`；参数、网络、校验、安装或验证失败返回非零值。
- 临时文件在正常退出、失败或中断时自动清理。
