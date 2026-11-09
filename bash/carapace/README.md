# carapace 在 bash / Git Bash 中的接入

[carapace](https://carapace.sh/) 的 bash 接入本身只有一行 `source <(carapace _carapace bash)`，但直接放进 Git Bash 的 `~/.bashrc` 会遇到一个 PATH 细节：carapace 会追加 Windows 风格的目录（`C:/...;...`），而 MSYS 的 PATH 用 `:` 分隔，`;` 会把后面的第一个目录粘进同一个 PATH 项。本目录提供一个可重复 source 的运行时脚本和一个写入/卸载 `~/.bashrc` 标记块的小工具。

> PowerShell 侧的 carapace 由 `init` 按 `PsCarapace` 配置加载，启停用 `Enable-CxxuComponent` / `Disable-CxxuComponent`；本目录只覆盖 bash。两边互不影响，安装与 PowerShell 侧配置见 [Deploy-Guide](../../PS/docs/Deploy-Guide.md) 的「可选：carapace」。

## 目录内容

- [carapace.sh](carapace.sh)：运行时初始化，被 `~/.bashrc` source；检查 carapace、加载补全、修正 Git Bash 的 PATH，可重复 source。
- [setup.sh](setup.sh)：在 rc 文件中写入或移除带标记的接入片段，支持试运行与卸载。
- [README.md](README.md)：本文档。

## 安装

Git Bash 中执行：

```sh
bash /c/repos/scripts/bash/carapace/setup.sh --dry-run
bash /c/repos/scripts/bash/carapace/setup.sh
```

WSL 中使用 Windows 侧仓库副本时，路径改为 `/mnt/c/repos/scripts/bash/carapace/setup.sh`；脚本写入的是当前环境的 `~/.bashrc`。Linux/WSL 使用各自的 carapace 二进制。

安装动作只有一处：在 `~/.bashrc` 末尾写入 `# >>> carapace >>>` 标记块，内容为 source 运行时脚本。重新打开终端或执行 `source ~/.bashrc` 后生效。

卸载：

```sh
bash /c/repos/scripts/bash/carapace/setup.sh --uninstall
```

`setup.sh` 的选项：

| 选项 | 作用 |
| --- | --- |
| `--dry-run` | 只打印将要写入或移除的内容，不修改文件 |
| `--uninstall` | 从 rc 文件移除 `# >>> carapace >>>` 标记块 |
| `--rc <file>` | 指定 rc 文件，默认 `~/.bashrc` |

标记块里记录的是 `carapace.sh` 的绝对路径；仓库移动后重新运行 `setup.sh` 即可刷新。

## 手工接入

不运行 `setup.sh` 时，把下面内容加入 `~/.bashrc`：

```bash
# 可选：桥接其他补全框架
export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
source <(carapace _carapace bash)
# Git Bash/MSYS：去掉 carapace 追加的 Windows 风格 PATH 项
case "$PATH" in *';'*) PATH="${PATH#*;}" ;; esac
```

`source <(carapace _carapace bash)` 会注册全部 completer。只想加载单个命令时，可把 `_carapace` 换成命令名，例如 `source <(carapace chmod bash)`。

## 环境变量

| 变量 | 作用 |
| --- | --- |
| `CARAPACE_BIN` | 可选；把 carapace 所在目录前置到 bash PATH，例如 `~/.cxxu/bin` |
| `CARAPACE_BRIDGES` | 可选；启用其他补全框架桥接，值如 `zsh,fish,bash,inshellisense` |
| `CARAPACE_EXCLUDES` | 可选；不注册补全的命令，逗号分隔。本机 1.8.2 实测 `git,gitk` 可同时排除两者，空格分隔不生效 |

`CARAPACE_EXCLUDES` 在 source 前导出即可，例如让 argc-completions 继续负责 git：

```bash
export CARAPACE_EXCLUDES='git,gitk'
source <(carapace _carapace bash)
```

## 与 argc-completions 共存

两个工具都用 bash 的 `complete -F` 注册补全，同一个命令以后注册的为准。`~/.bashrc` 中的 source 顺序决定优先级：

- 需要 carapace 接管 git：把 carapace 的片段放在 argc-completions 之后。
- 需要 argc-completions 保留 git：在 carapace 前设置 `CARAPACE_EXCLUDES='git,gitk'`，或把 carapace 片段放在 argc 之前。
- 只想各管一部分命令时，用 `CARAPACE_EXCLUDES` 把 git 留给 argc，其余命令交给 carapace。

PowerShell 侧的 `PsGitCompletionSource` 只影响 PowerShell 的 git/gitk 归属，不改变 bash 的注册顺序。

## 验收

```sh
command -v carapace
carapace --version
carapace --list
```

在交互式 Git Bash 中：

- 多个候选时按两次 `<Tab>`：第一次只补公共前缀（没有公共前缀时响铃），第二次显示候选列表；候选很多时 Bash 会询问 `Display all ...? (y or n)`，输入 `y` 显示。
- `git checkout <Tab><Tab>` 应出现分支、标签与 `HEAD`，可带提交说明。
- `git add <Tab><Tab>` 应出现未暂存或未跟踪文件。
- `gh pr <Tab><Tab>` 即使未安装 `gh` 也应出现静态子命令；需要读取仓库、PR 编号或登录状态的动态候选才依赖 `gh` 本身。
- `carapace <Tab><Tab>` 应出现 completer 列表。

本机交互式验证环境为 Git Bash 5.2.37（MSYS）+ carapace 1.8.2：`source` 约 44 ms；`git checkout <Tab><Tab>` 返回 17 个标签/分支/引用候选（含提交说明），`gh pr <Tab><Tab>` 返回 21 个子命令（本机未安装 `gh`）。`source` 的成本随版本与主机变化。

## 已知限制

- 需要 bash 4 及以上；Git Bash 5.x 满足，bash 3 会被 carapace 拒绝。
- bash 补全函数调用 `xargs`；极简环境缺少 coreutils 时，运行时脚本会警告并跳过，不注册半可用的补全。
- 每次打开 shell 都会执行一次 carapace 生成补全，本机约 44 ms；需要更快启动时减少注册命令或仅在需要的终端加载。
- carapace 会为大量命令注册补全，可能覆盖已有的 bash-completion；用 `CARAPACE_EXCLUDES` 排除不需要的命令。
- 仅 Git Bash（MSYS）完成实机验证；Cygwin 走同一脚本与兼容层 PATH 分支，Linux/WSL 走同一脚本但不需要 PATH 修正，均未逐项实机确认。
- PATH 修正是针对 Git Bash/Cygwin 的兼容处理；Linux 下 carapace 追加的是 POSIX 路径，不需要该行。
