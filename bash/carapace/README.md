# carapace 在 bash / Git Bash 中的接入

[carapace](https://carapace.sh/) 的 bash 接入本体只有一行 `source <(carapace _carapace bash)`，但直接把它放进 rc 文件会在部分环境失效或留下副作用：

- Git Bash/MSYS：carapace 会在 PATH 最前面追加 Windows 风格目录（`C:/...;...`），而 MSYS 的 PATH 用 `:` 分隔，`;` 会把后面的第一个目录粘进同一项。
- macOS 与 Git Bash：终端常以登录 shell 启动，读 `~/.bash_profile`、`~/.bash_login` 或 `~/.profile`，不读 `~/.bashrc`。
- macOS 自带 `/bin/bash` 是 3.2，carapace 会拒绝加载，需要 bash 4 及以上。

本目录提供一个可重复 source 的运行时脚本，以及一个安装二进制、写入/卸载 rc 标记块、可做只读状态检查的小工具，覆盖 Git Bash、Cygwin、Linux、WSL 与 macOS 的 bash。PowerShell 侧的 carapace 由 `init` 按 `PsCarapace` 配置加载，启停用 `Enable-CxxuComponent` / `Disable-CxxuComponent`；本目录只覆盖 bash，两边互不影响。安装与 PowerShell 侧配置见 [Deploy-Guide](../../PS/docs/Deploy-Guide.md) 的「可选：carapace」。

## 适用范围

| 项目 | 说明 |
| --- | --- |
| 覆盖的 shell | Git Bash（MSYS）、Cygwin、Linux、WSL、macOS 的 bash 4 及以上 |
| 不覆盖 | zsh（macOS 默认 shell）、fish、cmd.exe、PowerShell；这些环境不在本目录的接入范围 |
| 前置条件 | `carapace` 位于 PATH（或由 `setup.sh --install` 安装）；bash 4+；`xargs`（coreutils）；`--install` 另需 curl 或 wget、sha256sum（或 shasum），Linux/macOS 还需 tar，Git Bash/Cygwin 还需 unzip、bsdtar 或 powershell.exe 之一（用于解压 zip） |
| 修改范围 | 只在 rc 文件写入 `# >>> carapace >>>` 标记块；不修改 carapace 本体，不修改 profile |
| 生效方式 | 新开终端，或 `source` 对应 rc；运行时脚本可重复 source |
| 效果 | 注册 carapace 的全部 completer；Tab 补全命令参数值，不补命令名，也不补 PowerShell cmdlet |

## 平台差异

登录/非登录不是按操作系统划分，而是按终端启动方式。先在实际使用的终端里执行：

```bash
shopt -q login_shell && echo "login shell" || echo "non-login shell"
```

| 平台 | carapace 安装 | 实际读取的 rc | PATH 修正 | 验证状态 |
| --- | --- | --- | --- | --- |
| Git Bash（MSYS） | `setup.sh --install`（官方 Release 的 windows zip + SHA-256，装到 `~/.cxxu/bin`）、`scoop install carapace-bin`，或 PowerShell 里 `Deploy-Carapace -Bash`（装二进制并写 rc） | 非登录 `.bashrc`；登录 `.bash_profile`/`.bash_login`/`.profile` | 需要 | `--install` 已实测；Cygwin 未实测 |
| Cygwin | 同 Git Bash，或 Cygwin 包管理器 | 同 bash 规则 | 需要（兼容层） | 未实测 |
| Linux | `setup.sh --install`（官方 Release + SHA-256 + 镜像/代理），或发行版仓库，或手工装到 `~/.local/bin` | 非登录 `.bashrc`；登录 `.bash_profile`/`.bash_login`/`.profile` | 不需要 | `--install` 在 WSL Ubuntu 24.04 已实测；实际补全未在 Linux 桌面验证 |
| WSL | 在 WSL 内用 `setup.sh --install` 装 Linux 版；不要复用 Windows 的 `carapace.exe` | 通常为非登录 `.bashrc` | 不需要 | `--install` 与 `--check` 已实测；ble.sh 菜单未验证 |
| macOS bash | `brew install bash carapace`；系统 bash 3.2 不可用 | 非登录 `.bashrc`；登录 `.bash_profile`/`.bash_login`/`.profile` | 不需要 | 未实测 |
| macOS zsh | 不在本目录范围 | — | — | — |

## 最短路径（新设备复用）

把 `/path/to/scripts` 换成仓库的克隆目录，不要照抄某台机器的绝对路径。所有平台都先确认 carapace 可用：

```bash
command -v carapace
carapace --version
```

接入前可以先看整体状态（只读，不改文件）：

```bash
bash /path/to/scripts/bash/carapace/setup.sh --check
```

依赖不全时，先看会执行什么再安装：

```bash
bash /path/to/scripts/bash/carapace/setup.sh --install-deps --dry-run
bash /path/to/scripts/bash/carapace/setup.sh --install-deps
```

`--install-deps` 只在显式给出时执行：Linux 用 sudo 调包管理器，macOS 用 brew，Git Bash 只打印 scoop/pacman 命令。

在 PowerShell 中也可以用一条命令同时装二进制并写 rc（内部调用本目录的 `setup.sh`，写入内容与手工执行一致）：

```powershell
Deploy-Carapace -Bash            # 非登录 shell：写 ~/.bashrc
Deploy-Carapace -Bash -BashLogin # 登录 shell：写 ~/.bash_profile/~/.bash_login/~/.profile
```

下面仍按平台分开写，便于只处理二进制或只处理 rc 的情况。

接入命令按终端类型二选一：

| 终端类型 | 接入命令 |
| --- | --- |
| 非登录 shell（默认写 `~/.bashrc`） | `bash /path/to/scripts/bash/carapace/setup.sh` |
| 登录 shell（macOS Terminal、Git Bash、ssh 登录常见） | `bash /path/to/scripts/bash/carapace/setup.sh --login` |

先加 `--dry-run` 看目标文件与将写入的内容：

```bash
bash /path/to/scripts/bash/carapace/setup.sh --dry-run
bash /path/to/scripts/bash/carapace/setup.sh --dry-run --login
```

### Git Bash / MSYS

三种方式选一，都会得到可用的二进制：

```bash
# 1. 只用 bash：官方 Release 的 windows zip + SHA-256，装到 ~/.cxxu/bin 并写 rc
cd /path/to/scripts/bash/carapace
bash setup.sh --install --dry-run
bash setup.sh --install
```

```powershell
# 2. 在 PowerShell 里一条命令：装二进制 + 写 bash rc（需要 pwsh 7）
Deploy-Carapace -Bash
Deploy-Carapace -Bash -BashLogin   # 当前终端是登录 shell 时

# 3. 已有 scoop 渠道
scoop install carapace-bin
```

用 `setup.sh --install` 或 `Deploy-Carapace -Bash` 时 rc 已写好，可直接验收；用 `scoop` 装二进制时再补写 rc：

```bash
cd /path/to/scripts/bash/carapace
bash setup.sh --dry-run
bash setup.sh
```

回到 Git Bash 验收：

```bash
command -v carapace
carapace --version
```

如果 `command -v carapace` 没有输出，把安装目录加入 PATH（常见为 `~/.cxxu/bin` 或 `/c/scoop/shims`），再重开终端；用 `setup.sh --install` 时 rc 片段会通过 `CARAPACE_BIN` 自动前置该目录。Git Bash 使用登录 shell 时改加 `--login`。

### Linux

一键安装（官方 Release，SHA-256 校验，默认镜像优先）：

```bash
cd /path/to/scripts/bash/carapace
bash setup.sh --install --dry-run   # 先看平台、版本、通道与安装目录
bash setup.sh --install             # 下载 → 校验 → 装到 ~/.local/bin → 写入 rc
bash setup.sh --check               # 复核依赖、rc 片段与加载结果
```

- 下载通道默认 `auto`：先试 `gh-proxy.com`，失败换 `ghproxy.net`，最后直连 GitHub；`--mirror direct` 强制直连，`--mirror ghproxy|ghproxynet|ghfast` 固定节点，`--mirror https://...` 用自建或内网前缀。
- 需要代理时加 `--proxy http://127.0.0.1:7897`，或先导出 `HTTPS_PROXY`。
- 版本查询（`releases/latest` 重定向、API 兜底）不走文件镜像，只走直连或 `--proxy`；想省掉这次查询用 `--version 1.8.2`。
- 安装目录不在 PATH 时，rc 片段会写入 `CARAPACE_BIN` 让运行时脚本前置该目录；已有 carapace 时默认跳过，`--force` 覆盖。

没有网络或想用包管理器时，从发行版仓库安装；没有时从官方 Release 手工下载：

```bash
# 版本与架构以 https://github.com/carapace-sh/carapace-bin/releases 为准
tar -xzf carapace-bin_<版本>_linux_amd64.tar.gz carapace
mkdir -p ~/.local/bin
cp carapace ~/.local/bin/carapace
chmod +x ~/.local/bin/carapace

# 新终端要能找到 ~/.local/bin，按所用 shell 写进对应的 profile 或 rc
export PATH="$HOME/.local/bin:$PATH"

cd /path/to/scripts/bash/carapace
bash setup.sh --dry-run
bash setup.sh
```

`.deb`/`.rpm`/`.apk` 渠道与 PowerShell 侧的 `Deploy-Carapace` 见 [Deploy-Guide](../../PS/docs/Deploy-Guide.md) 的「可选：carapace」。Linux 桌面终端通常是非登录 shell；ssh 登录或显式 `bash -l` 时用 `--login`。

### WSL

在 WSL 内装 Linux 版 carapace，不要复用 Windows 侧的 `carapace.exe`。安装与检查都在 WSL 内执行：

```bash
# 如果仓库在 Windows 盘，路径形如 /mnt/c/path/to/scripts
cd /mnt/c/path/to/scripts/bash/carapace
bash setup.sh --install --dry-run
bash setup.sh --install
bash setup.sh --check
```

WSL 内跑 PowerShell 需要单独安装 pwsh，因此 `Deploy-Carapace` 不是默认路径；`setup.sh --install` 只依赖 curl/wget、tar 与 sha256sum。

`setup.sh` 写入的是 WSL 自己的 `~/.bashrc`，不会改动 Windows 侧 Git Bash 的配置。WSL 默认终端通常是非登录 shell。

### macOS bash

macOS 自带 `/bin/bash` 是 3.2，carapace 会直接拒绝。先安装新版 bash 并切换登录 shell：

```bash
brew install bash carapace
"$(brew --prefix)/bin/bash" --version

# 如果 chsh 报 non-standard shell，先把 brew bash 加入 /etc/shells
if ! grep -qxF "$(brew --prefix)/bin/bash" /etc/shells; then
	echo "$(brew --prefix)/bin/bash" | sudo tee -a /etc/shells
fi
chsh -s "$(brew --prefix)/bin/bash"
```

重新登录后确认，再接入：

```bash
echo "$BASH_VERSION"          # 应为 4.x 或 5.x
shopt -q login_shell && echo "login shell"

cd /path/to/scripts/bash/carapace
bash setup.sh --dry-run --login
bash setup.sh --login
```

macOS Terminal 默认是登录 shell；VS Code 等集成终端可能是非登录 shell，仍按上面的 `shopt` 结果选择。macOS 默认 shell 是 zsh，本目录不配置 zsh；如果要用默认终端，需要按 carapace 的 zsh 接入方式另行配置。macOS 的官方 carapace 产物未签名，优先用 `brew install carapace`。

## setup.sh 的选项与行为

| 选项 | 作用 |
| --- | --- |
| `-n`, `--dry-run` | 只打印将要写入或移除的内容，不修改文件 |
| `-l`, `--login` | 写入登录 shell 实际读取的 rc 文件 |
| `-r`, `--rc <file>` | 指定 rc 文件，默认 `~/.bashrc` |
| `-u`, `--uninstall` | 从 rc 文件移除 `# >>> carapace >>>` 标记块 |
| `-c`, `--check`、`--status` | 只读检查依赖、rc 片段与端到端加载状态；不修改任何文件 |
| `-i`, `--install` | 下载并安装 carapace（Linux/macOS/Git Bash/Cygwin），随后写入 rc |
| `--install-deps` | 安装缺失依赖：缺 curl/wget、coreutils、tar 时调用包管理器；Linux 用 sudo、macOS 用 brew，Git Bash 只给出命令 |
| `--version <v>` | `--install` 固定版本，默认查询最新 release |
| `--bin-dir <dir>` | `--install` 安装目录，默认 `$CARAPACE_BIN`；Windows 为 `~/.cxxu/bin`，其他平台为 `~/.local/bin` |
| `--mirror <m>` | 下载通道：`auto`（默认）、`direct`、`ghproxy`、`ghproxynet`、`ghfast` 或 https 前缀 |
| `--proxy <url>` | `--install` 时经 HTTP/HTTPS/SOCKS 代理下载 |
| `--force` | `--install` 覆盖已存在的二进制 |
| `-h`, `--help` | 显示帮助 |

行为与边界：

- 安装动作只有一处：在目标 rc 写入带标记的块，块内用绝对路径加载 `carapace.sh`。重复运行会先移除旧块再追加，不会产生多个副本。
- `setup.sh` 本身作为非登录 bash 子进程运行，无法替你判断终端是登录还是非登录；`--login` 必须由使用者先在实际终端执行 `shopt -q login_shell` 后选择。
- `--login` 按 bash 的读取顺序选择目标：已有 `~/.bash_profile` 用它，其次 `~/.bash_login`，再次 `~/.profile`；三个都不存在时创建 `~/.bash_profile`。`--login` 与 `--rc` 互斥。
- 创建 `~/.bash_profile` 后，登录 shell 不再读取 `~/.profile`；如果之后新增 `~/.profile`，需要在 `~/.bash_profile` 中显式 source 它。
- 目标 rc 不存在时会创建（包括父目录）。脚本不备份原文件；重要配置先自行备份或用版本控制，改动前可先跑 `--dry-run`。
- 目标 rc 是符号链接时脚本拒绝执行，避免把链接替换成普通文件；请用 `--rc` 指向真实文件，或手工编辑目标文件。
- 安装与卸载通过同目录临时文件加 `mv` 替换，并用 `cp -p` 保留原 rc 的权限；Git Bash/MSYS 的 `awk`/`grep` 以文本模式处理文件，重写 rc 时可能把该文件的行尾统一为 LF。bash 不受影响；要保持 CRLF 请手工编辑，或用版本控制对比后决定。
- 标记块中的路径是当前仓库副本的绝对路径；仓库移动后重新运行 `setup.sh` 刷新，或手工删除旧块。
- 找不到 carapace 时只提示，不阻止写入；新开 shell 后由运行时脚本再次提示并跳过初始化。装好 carapace 后新开终端，或重新 `source` 对应 rc。
- `--check`（`--status` 同义）只读：依次报告 bash 版本、`carapace` 与 `xargs` 是否可用、运行时脚本是否存在、平台、目标 rc、四个候选 rc 的标记块状态（含块内路径是否仍然存在），再用 `bash -ic` / `bash -lic` 各起一个子 shell 验证实际是否加载；不改写任何文件，且不能与 `--dry-run`、`--uninstall` 同时使用。
- `--check` 退出码：全部正常为 0；缺依赖、rc 片段有问题或尚未接入为 1；参数错误为 2。结论行会给出对应的修复命令。
- `--install` 支持 Linux/macOS 与 Git Bash/Cygwin：Windows 下载 `carapace-bin_<版本>_windows_<架构>.zip`，解压出 `carapace.exe` 装到 `~/.cxxu/bin`；其他平台下载 `tar.gz` 装到 `~/.local/bin`。解压顺序为 `unzip` → `bsdtar` → `powershell.exe`（Expand-Archive），三者都没有时报错并给出安装命令。安装目录不在 PATH 时，rc 片段额外写 `export CARAPACE_BIN`，运行时脚本会前置该目录。
- `--mirror` 只作用于 Release 文件（`tar.gz`/`zip` 与 `checksums.txt`）；版本查询始终直连或经 `--proxy`，不经过文件镜像。`auto` 顺序为 `gh-proxy.com` → `ghproxy.net` → 直连，单个候选失败才换下一个。
- 依赖缺失（curl/wget、tar、sha256sum）时默认只报告并给出对应包管理器命令，不自动 `sudo` 安装；显式加 `--install-deps` 才会调用包管理器（Linux 缺 sudo 时提示手工执行，Git Bash 只给出 scoop/pacman 命令）。`--install-deps` 与 `--dry-run` 组合时只打印将执行的安装命令。
- 升级与降级都只按 `--version` 指定的版本下载；已存在的二进制默认跳过，`--force` 才覆盖。
- 下载与解压都在 `mktemp -d` 的临时目录完成，脚本退出时清理；下载、校验或解压失败都以非零码退出，不写半成品二进制。
- 镜像与 `checksums.txt` 来自同一通道，恶意镜像可以同时替换两者；需要更强保证时用 `--mirror direct`（或 `--proxy` + 官方源）并核对 Release 页面的校验值。
- `--install --dry-run` 不联网，只打印平台、版本、通道、安装目录与依赖可用性。
- `--login` 安装后，默认的 `--uninstall` 不会去登录 rc 找块；用 `--uninstall --login`，或用 `--rc` 指向同一个文件。
- 标记块带 `[ -n "${BASH_VERSION:-}" ]` 保护，写进 `.profile` 这类可能被 sh/dash 读取的文件时，非 bash shell 会跳过，不会因加载 bash 脚本报错。

## 手工接入

不运行 `setup.sh` 时，把下面内容加入非登录 shell 的 `~/.bashrc`：

```bash
if [ -n "${BASH_VERSION:-}" ]; then
	# 可选：桥接其他补全框架
	export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
	# bash-ble：加载了 ble.sh 时走 ble 专用补全，否则自动回退普通 bash 补全
	source <(carapace _carapace bash-ble)

	# Git Bash/MSYS：去掉 carapace 追加的 Windows 风格 PATH 项
	case "${OSTYPE:-}" in
	msys* | cygwin*)
		case "$PATH" in
		[A-Za-z]:/*';'*) PATH="${PATH#*;}" ;;
		esac
		;;
	esac
fi
```

写入登录 rc（如 `~/.bash_profile`）时保留外层的 `BASH_VERSION` 判断；Linux/macOS 不需要 PATH 修正，其中的 `msys* | cygwin*` 分支可以省略。

`source <(carapace _carapace bash-ble)` 会注册全部 completer。只想加载单个命令时，可把 `_carapace` 换成命令名，例如 `source <(carapace chmod bash-ble)`。

## 环境变量

| 变量 | 作用 |
| --- | --- |
| `CARAPACE_BIN` | 可选；把 carapace 所在目录前置到 bash PATH，例如 `~/.cxxu/bin`。目录不存在时忽略 |
| `CARAPACE_BRIDGES` | 可选；启用其他补全框架桥接，值如 `zsh,fish,bash,inshellisense` |
| `CARAPACE_EXCLUDES` | 可选；不注册补全的命令，逗号分隔。本机 1.8.2 实测 `git,gitk` 可同时排除两者，空格分隔不生效 |

`CARAPACE_EXCLUDES` 在 source 前导出即可，例如让 argc-completions 继续负责 git：

```bash
export CARAPACE_EXCLUDES='git,gitk'
source <(carapace _carapace bash)
```

## 效果与验收

基础检查：

```bash
command -v carapace
carapace --version
carapace --list
echo "$BASH_VERSION"
shopt -q login_shell && echo "login shell" || echo "non-login shell"
type _carapace_completer
```

`type _carapace_completer` 应输出函数定义；没有输出说明当前 shell 没有加载运行时脚本。

不打开交互式终端时，可以用下面的命令按 rc 类型检查（登录 shell 会打印 job control 警告，可忽略）：

```bash
bash -ic 'type _carapace_completer'    # 非登录 shell 读取 ~/.bashrc
bash -lic 'type _carapace_completer'   # 登录 shell 读取 ~/.bash_profile/~/.bash_login/~/.profile
```

在交互式 bash 中：

- 多个候选时按两次 `<Tab>`：第一次只补公共前缀（没有公共前缀时响铃），第二次显示候选列表；候选很多时 Bash 会询问 `Display all ...? (y or n)`，输入 `y` 显示。
- `git checkout <Tab><Tab>` 应出现分支、标签与 `HEAD`，可带提交说明。
- `git add <Tab><Tab>` 应出现未暂存或未跟踪文件。
- `gh pr <Tab><Tab>` 即使未安装 `gh` 也应出现静态子命令；需要读取仓库、PR 编号或登录状态的动态候选才依赖 `gh` 本身。
- `carapace <Tab><Tab>` 应出现 completer 列表。

效果范围：

- carapace 注册的是参数值补全，不替代 bash 的命令名补全，也不补 PowerShell cmdlet。
- 候选数量随 carapace 版本、已安装命令与仓库状态变化；`carapace --list` 的数字不要写死。
- 未安装外部命令时，静态子命令仍可补全；需要命令自身返回上下文的候选会为空或变慢。
- 加载成本只在每次打开 shell 时发生，随注册命令数和主机变化；需要更快启动时用 `CARAPACE_EXCLUDES` 缩小范围。

## ble.sh 用户

carapace 提供专门的 `bash-ble` 生成模式，本目录的运行时脚本固定使用它：`bash-ble` 只在 ble.sh 已加载时接管，未加载时回退到普通补全，所以同一段 rc 可以同时服务 ble.sh 与普通 bash。

- 已加载 ble.sh（`BLE_ATTACHED`）时：自动补全直接返回，避免候选污染 ble.sh 的自动建议；菜单用 `bleopt complete_menu_style=desc`，候选通过 `ble/complete/cand/yield` 交给 ble.sh，并设置 `compopt -o ble/no-default`。
- 未加载 ble.sh 时：回退到 `_carapace_completer`，行为与普通 bash 模式一致。
- 不要用 `carapace _carapace bash` 配 ble.sh：普通 bash 生成器依赖 `IFS=$'\001' read`，ble.sh 的 `read` 包装会破坏它，表现为原始输出被写进命令行（ble.sh issue #735 的复现场景）。
- 需要 ble.sh 0.4 及以上（`ble/no-default` 与 `ble/complete/cand/yield`）；更旧的版本可能在补全时报 `compopt` 错误。
- 片段顺序：carapace 通过 `complete -F` 注册，ble.sh 在补全时读取这些定义，因此 ble.sh 常用的「顶部 `--attach=none`、末尾 `ble-attach`」写法也能取到；若遇到个别命令没有候选，把 carapace 片段放到 ble.sh 之后重试。

`setup.sh --check` 会单独报告 rc 中是否检测到 ble.sh，用来确认当前用的是哪种模式。

## 与 argc-completions 共存

两个工具都用 bash 的 `complete -F` 注册补全，同一个命令以后注册的为准。`~/.bashrc` 中的 source 顺序决定优先级：

- 需要 carapace 接管 git：把 carapace 的片段放在 argc-completions 之后。
- 需要 argc-completions 保留 git：在 carapace 前设置 `CARAPACE_EXCLUDES='git,gitk'`，或把 carapace 片段放在 argc 之前。
- 只想各管一部分命令时，用 `CARAPACE_EXCLUDES` 把 git 留给 argc，其余命令交给 carapace。

PowerShell 侧的 `PsGitCompletionSource` 只影响 PowerShell 的 git/gitk 归属，不改变 bash 的注册顺序。

## 重复安装与停用

重复执行是幂等的：

| 操作 | 重复执行的结果 |
| --- | --- |
| `setup.sh` / `setup.sh --login` | 先移除旧标记块再追加，始终只有一份，不会重复 source |
| `Deploy-Carapace -Bash`（及 `-BashLogin`） | 内部调用同一脚本，效果同上；二进制已存在时跳过下载，但仍刷新 rc |
| `setup.sh --install` | PATH 中已有 carapace 时跳过并提示，`--force` 才重新下载覆盖 |
| `setup.sh --install-deps` | 只处理缺失项；包管理器自身幂等，重复执行无副作用 |

- 「已安装」按 `command -v carapace` 判定：PATH 中命中其他渠道（如 `scoop` 的 shims）时同样跳过，不会写到 `--bin-dir`；要把副本装到指定目录加 `--force`。
- `--force` 只覆盖目标目录的二进制，不清理其他渠道的副本；多个副本并存时以 PATH 顺序为准，用 `command -v carapace` 确认实际命中哪一个。
- 目标目录没有副本时，rc 片段不写 `CARAPACE_BIN`，避免导出不存在的目录。

停用与卸载分开处理：

| 目标 | 操作 | 删除二进制 |
| --- | --- | --- |
| 停用 bash 补全 | `setup.sh --uninstall`（登录 shell 加 `--login`），或手工删除/注释标记块 | 否 |
| 只停用部分命令 | `CARAPACE_EXCLUDES='git,gitk'` | 否 |
| 停用 PowerShell 侧 | `Disable-PsPlugin Carapace -Persist`（`Disable-CxxuComponent Carapace -Persist` 等价），重开终端后不再加载 | 否 |
| 彻底卸载 bash 接入 | 见下节「卸载」 | 否 |
| 删除二进制 | `scoop uninstall carapace-bin`、`brew uninstall carapace`，或删除 `~/.cxxu/bin/carapace.exe` / `~/.local/bin/carapace` 并从 PATH 移除 | 是 |

两侧独立：停用 PowerShell 组件不影响 bash 的 rc 片段，`--uninstall` 也不修改 `PsCarapace` 配置。

## 卸载

```bash
# 非登录 shell 安装
bash /path/to/scripts/bash/carapace/setup.sh --uninstall

# 登录 shell 安装
bash /path/to/scripts/bash/carapace/setup.sh --uninstall --login

# 自定义 rc
bash /path/to/scripts/bash/carapace/setup.sh --uninstall --rc ~/.bash_profile
```

卸载只移除标记块，不删除 carapace 二进制。二进制按安装渠道卸载（`scoop uninstall carapace-bin`、`brew uninstall carapace`，或删除 `~/.local/bin/carapace`）并从 PATH 移除。

## 故障排查

| 现象 | 检查 | 处理 |
| --- | --- | --- |
| 打开终端提示未找到 carapace | `command -v carapace` | 安装 carapace，或把安装目录加入 PATH 后重开终端 |
| `carapace --version` 失败 | `carapace --version` 的实际报错 | 重新安装与平台/架构匹配的二进制 |
| 提示需要 bash 4 及以上 | `echo "$BASH_VERSION"` | macOS 用 `brew install bash` 并切换登录 shell；其他平台安装 bash 4+ |
| 补全完全没反应 | `type _carapace_completer` | 没有函数说明 rc 没加载：确认登录/非登录类型，重新运行 `setup.sh` 或 `setup.sh --login` |
| 只有部分命令没有候选 | `carapace --list`、`CARAPACE_EXCLUDES` | 确认命令是否被排除、是否需要该命令自身提供上下文 |
| `PATH` 出现带分号的异常项 | `printf '%s\n' "$PATH"` | Git Bash/MSYS 的 PATH 修正未生效；确认 `OSTYPE` 与运行时脚本版本 |
| 按 Tab 只补前缀不显示列表 | 候选数量 | 再按一次 `<Tab>`；候选很多时输入 `y` 确认 `Display all` |
| git 补全被 argc 或 bash-completion 覆盖 | rc 中的 source 顺序 | 调整顺序，或用 `CARAPACE_EXCLUDES` 排除 |
| 提示 rc 是符号链接 | `ls -l ~/.bashrc` | 用 `--rc` 指向真实文件，或手工编辑目标文件 |
| Git Bash 下 rc 行尾被改为 LF | `git diff` 或 `od -c ~/.bashrc` | 手工改回，或先把配置纳入版本控制在重写后对比 |
| `--install` 报缺 curl/wget、tar、sha256sum | 报错行给出的包管理器命令 | 加 `--install-deps` 让脚本调用包管理器，或按提示手工安装 |
| Windows 下 `--install` 解压失败 | `command -v unzip bsdtar powershell.exe` | 安装 unzip（`scoop install unzip`），或确认 `powershell.exe` 可用；三者有其一即可 |
| 想一次确认依赖与接入状态 | `bash /path/to/scripts/bash/carapace/setup.sh --check` | 按输出标出的问题逐项处理；退出码 1 表示仍需处理 |

## 验证记录与未验证项

已完成的实测：

- Git Bash 5.2.37（MSYS）+ carapace 1.8.2：运行时脚本 `source` 约 40–55 ms（含一次 `carapace _carapace bash` 生成；单独执行该生成命令约 35–40 ms）；`git checkout <Tab><Tab>` 返回带说明的标签/分支/引用候选，`gh pr <Tab><Tab>` 在未安装 `gh` 时返回静态子命令。
- `setup.sh` 在隔离 `HOME` 下验证了试运行不建文件、首次安装、重复安装幂等、卸载、标记块损坏报错、`--login` 目标选择与 `--uninstall --login`；还验证了权限保持、CRLF 文件在 Linux/WSL 下保留行尾、符号链接拒绝改写。
- `setup.sh --check` 在隔离 `HOME` 下验证了未接入、已接入（非登录与登录两类 shell 均加载）、块内路径失效、缺结束标记四种状态与对应退出码；`--check --dry-run` 按参数错误拒绝。
- `setup.sh --install` 用假 release 与假 curl 在隔离 `HOME` 下验证：dry-run 不联网、auto 从 gh-proxy 回退 ghproxy.net、`--mirror` 各模式的前缀、`--proxy` 传入 curl、SHA-256 不符拒绝写入、已装跳过与 `--force` 覆盖、`--check` 能识别 rc 片段里的 `CARAPACE_BIN`。
- WSL Ubuntu 24.04 实机经 `gh-proxy.com` 完成 `--install`（1.8.2，20.1MB，约 5.4MB/s，下载到写 rc 约 19s），`--check` 通过并在非登录 shell 中加载。
- Git Bash 实机 `--install --version 1.8.2`（windows zip）：经 `gh-proxy.com` 下载 19.4MB，SHA-256 通过，`unzip` 解压出 `carapace.exe` 并装到临时目录，`carapace.exe --version` 返回 1.8.2，rc 片段写入 `CARAPACE_BIN`。
- WSL Ubuntu 实机 `--install --version 1.8.2`（tar.gz）：安装到临时目录成功，`carapace --version` 返回 1.8.2。
- `--install-deps` 在隔离 PATH（只有 bash 与少量 coreutils）下识别出缺少 `curl coreutils tar`；无包管理器时给出手工安装命令并返回 1，PATH 中加入假 `apt-get` 后 `--dry-run` 打印 `sudo apt-get install -y curl coreutils tar`，未实际执行。
- `bash-ble`：Git Bash 上验证生成脚本、`_carapace_completer_ble` 注册，以及未加载 ble.sh 时回退到普通补全并返回正常候选；真实 ble.sh 菜单未验证（本机 WSL 的 ble.sh 在非 tty 子 shell 中不加载）。
- 运行时脚本在未安装 carapace 时给出平台提示并跳过；`BASH_VERSION`、`xargs`、`source` 失败都有对应提示。
- `shellcheck 0.9.0` 与 `shfmt 3.8.0` 对 `setup.sh`、`carapace.sh` 无报错，`bash -n` 通过。
- WSL Ubuntu 24.04：`setup.sh` 的安装、重复安装、卸载、符号链接保护与 CRLF 保留通过；WSL 内未安装 carapace，因此 Linux 的实际补全效果未验证。

未验证或未覆盖：

- macOS 的 bash 4+ 安装、`chsh`、登录 rc 与 carapace 实际补全未在 macOS 实机验证；本文按 bash 的通用读取规则给出步骤。
- Cygwin 未实测：`--install` 的 zip 解压回退（unzip/bsdtar/powershell）只在 Git Bash（MSYS）验证；PATH 修正分支按 MSYS 的行为编写。
- Linux 桌面发行版、ssh 登录 shell、`.deb`/`.rpm`/`.apk` 渠道未逐项验证。
- macOS 默认 zsh 不在本目录范围；zsh 的接入需要按 carapace 官方方式单独配置。
- carapace 生成脚本随版本变化；本文的 PATH 修正与候选行为基于 1.8.2，升级后如遇差异以实际输出为准。

## 已知限制

- 需要 bash 4 及以上；bash 3（macOS 自带 3.2）会被 carapace 拒绝。
- bash 补全函数调用 `xargs`；极简环境缺少 coreutils 时，运行时脚本会警告并跳过，不注册半可用的补全。
- 每次打开 shell 都会执行一次 carapace 生成补全，本机约 40–55 ms；需要更快启动时减少注册命令或仅在需要的终端加载。
- carapace 会为大量命令注册补全，可能覆盖已有的 bash-completion；用 `CARAPACE_EXCLUDES` 排除不需要的命令。
- PATH 修正只处理 Git Bash/MSYS 中 carapace 追加的、以盘符开头的 `C:/...;...` 项；如果 PATH 里其他位置也有分号，修正不会主动清理。
- 慢命令（如需要网络或扫描大目录的 completer）会阻塞 Tab；按需排除。
- Windows 下 `--install` 默认装到 `~/.cxxu/bin`，只通过 rc 片段的 `CARAPACE_BIN` 对 bash 生效；要在 PowerShell/cmd 直接调用 `carapace`，需另把该目录加入 Windows 用户 PATH（`Deploy-Carapace` 会做这一步）。
- 本目录只覆盖 bash；PowerShell、zsh、fish、cmd.exe 的接入各自独立。
- `bash-ble` 的补全菜单、自动建议与 `bleopt` 副作用未在真实 ble.sh 会话中验证；本机 WSL 的 ble.sh 在非 tty 子 shell 内不加载，`--check` 只能按 rc 内容判断。
- 文件镜像只保证传输完整性（同一通道的 `checksums.txt`），不构成对镜像运营者的信任；敏感环境请用 `--mirror direct` 或走代理访问官方源。
