# ripgrep 通用安装脚本

[`install_ripgrep.sh`](./install_ripgrep.sh) 根据 [ripgrep 官方安装指南](https://github.com/BurntSushi/ripgrep#installation) 编写。默认解析最新 GitHub Release，只安装官方预编译的 `rg` 主程序，避免 Debian/Ubuntu 等发行版仓库版本滞后，也不需要 Rust 编译工具链。

通用的设计、安全和测试原则见 [`README.installers-best-practices.md`](./README.installers-best-practices.md)。

## 默认行为

```bash
chmod +x install_ripgrep.sh
./install_ripgrep.sh
```

脚本会：

1. 解析最新 Release 版本。
2. 识别 CPU 与 libc，选择官方 Linux 归档。
3. 使用 [`net_is_cn.sh`](../shell_utils/net_is_cn.sh) 判断出口地区并排序 GitHub 文件下载通道。
4. 下载上游提供的 `.sha256` 并校验归档。
5. 只从归档提取唯一的 `rg` 常规文件。
6. 核对 `rg --version`，再原子写入目标位置。

普通用户默认安装到 `~/.local/bin/rg`，root 默认安装到 `/usr/local/bin/rg`。

使用 verbose 查看 auto 的完整决策结果：

```bash
./install_ripgrep.sh --mirror auto --verbose
```

日志会列出国家代码、实际请求 URL、失败与选中的通道、latest 版本来源、CPU/libc 资产映射、checksum 来源、本地/远程版本比较和安装目标。版本解析会明确区分 `github.com/.../releases/latest` 重定向、`api.github.com` 和传输通道；显示“文件镜像”仅表示镜像转发前者，并非 GitHub API 经过镜像。日志不会启用可能泄露认证请求头的 `curl -v`；代理用户信息和 URL 查询参数会脱敏。

## 安装方式

| 方式 | 用途 |
| --- | --- |
| `binary` | 默认；最新、依赖最少，不受系统仓库版本影响 |
| `package` | 显式使用发行版仓库，交由系统包管理器维护 |
| `auto` | `binary` 的兼容别名 |

固定版本：

```bash
./install_ripgrep.sh --version 15.2.0
```

指定安装目录：

```bash
./install_ripgrep.sh --install-dir "$HOME/bin"
```

系统包模式：

```bash
sudo ./install_ripgrep.sh --method package
```

支持 apt、dnf/yum、apk、pacman、zypper、xbps、emerge 和 eopkg。脚本不会自动启用 EPEL 或其他第三方系统仓库；若当前仓库没有 ripgrep，请使用默认 binary 模式。

## 国内网络

自动回退：

```bash
./install_ripgrep.sh --mirror auto
```

auto 首次需要下载通道时加载 [`net_is_cn.sh`](../shell_utils/net_is_cn.sh)，本次运行只检测一次。CN 出口按 `ghfast.top`、`gh-proxy.com`、`ghproxy.net`、GitHub 直连排序；非 CN 或 UNKNOWN 按 GitHub 直连、三个镜像排序。辅助脚本缺失时按 UNKNOWN 处理。显式选择某个通道时不会检测地区。

强制指定通道：

```bash
./install_ripgrep.sh --mirror direct
./install_ripgrep.sh --mirror ghfast
./install_ripgrep.sh --mirror ghproxy
./install_ripgrep.sh --mirror ghproxynet
```

使用自定义、内网或人工审核过的镜像：

```bash
./install_ripgrep.sh --mirror https://mirror.example.com
```

自定义镜像必须支持以下形式：

```text
https://mirror.example.com/https://github.com/OWNER/REPO/...
```

使用代理：

```bash
./install_ripgrep.sh --proxy http://127.0.0.1:7890
./install_ripgrep.sh --proxy socks5h://127.0.0.1:7890
```

`--proxy` 只传给 curl，不改写系统配置；auto 的地区检测也会经该代理观察实际出口。节点发现可参考 [gh-proxy issue #116](https://github.com/hunshcn/gh-proxy/issues/116) 与 [GitHub 文件加速聚合页](https://yishijie.gitlab.io/ziyuan/)，但公益节点的运营者、内容安全和可用性会变化，因此脚本不会自动导入聚合页的全部节点。

脚本当前不调用 `api.github.com`，而是通过 `github.com/BurntSushi/ripgrep/releases/latest` 重定向解析版本。`--mirror` 只用于 Release 页面、归档和 checksum；镜像 URL 构造函数明确拒绝 `api.github.com`。若以后需要 GitHub API，只能直连或使用 `--proxy`。

## 校验策略

ripgrep Release 为归档发布配套的 `.sha256` 文件。默认 `--checksum require`：无法取得或校验失败都会停止安装。

```bash
# 默认严格模式
./install_ripgrep.sh --checksum require

# 旧版本没有校验文件时，警告后继续做归档与版本检查
./install_ripgrep.sh --checksum auto

# 明确跳过，不推荐
./install_ripgrep.sh --checksum skip
```

从独立可信渠道取得 SHA-256 后，可以建立更强的信任锚：

```bash
./install_ripgrep.sh --version 15.2.0 --sha256 <64位十六进制摘要>
```

用户提供的 `--sha256` 优先于在线校验文件。同一第三方镜像提供的归档和 checksum 能发现传输损坏，但不能抵抗镜像同时篡改两者；checksum 不是数字签名。

## 架构

脚本映射上游常见 Linux 资产：

| 系统架构 | Release target |
| --- | --- |
| x86_64 | `x86_64-unknown-linux-musl`，静态构建，减少 glibc 依赖 |
| aarch64 | `aarch64-unknown-linux-gnu` 或 `musl` |
| armv7 hard-float | `armv7-unknown-linux-gnueabihf` 或 `musleabihf` |
| i686 | `i686-unknown-linux-gnu` |
| s390x | `s390x-unknown-linux-gnu` |

上游不保证每个版本都发布所有 target。资产不存在时脚本会在所有下载通道失败后停止，可显式改用发行版 package 模式。

## 更新与卸载

再次执行默认命令即可检查最新版。本地版本相同时跳过归档下载；目标版本更高时会在下载前询问，默认回答为 No：

```bash
./install_ripgrep.sh

# 无人值守升级
./install_ripgrep.sh --yes
```

脚本不实现降级功能：目标版本低于现有版本时直接失败，`--force` 和 `--yes` 都不会绕过。`--yes` 只跳过升级确认；`--force` 只负责重装同版本或覆盖无法识别的冲突目标。

卸载当前用户默认 binary 目标：

```bash
./install_ripgrep.sh --uninstall
```

卸载其他模式：

```bash
sudo ./install_ripgrep.sh --method package --uninstall
```

自定义目录必须在卸载时再次给出：

```bash
./install_ripgrep.sh --install-dir "$HOME/bin" --uninstall
```

脚本只删除精确目标，不搜索或删除其他位置的 `rg`。

## Dry-run 与依赖

```bash
./install_ripgrep.sh --dry-run
sudo ./install_ripgrep.sh --method package --dry-run
```

binary dry-run 仍会联网、下载到临时目录并完成 checksum、归档和版本验证，但不会写入安装目录。package dry-run 只打印持久化命令。

版本方向策略适用于默认 binary。package 模式不指定版本，由包管理器处理升级事务；默认保留原生确认提示，传入 `--yes` 才启用非交互确认。Cargo 等外部生态安装器未实现，避免引入 Rust 工具链、索引配置和另一套更新语义。

运行依赖：

- 所有模式：Bash 4 或更新版本和常见基础命令。
- binary：curl、tar，以及 `sha256sum` 或 `shasum`。
- package：受支持的包管理器；非 root 用户还需要 sudo。

脚本支持 `NO_COLOR=1`，退出时自动清理临时文件。安装后若提示目录不在 PATH，可将普通用户默认目录加入 shell 配置：

```bash
export PATH="$HOME/.local/bin:$PATH"
```
