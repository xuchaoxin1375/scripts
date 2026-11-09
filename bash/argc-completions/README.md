# argc-completions 在 Git Bash 与 WSL bash 中的适配

[argc-completions](https://github.com/sigoden/argc-completions) 上游只提供“把片段写入 `~/.bashrc`”的通用做法，直接照搬到 Git Bash 与 WSL 会遇到二进制冲突、bash 探测失败、ble.sh 候选串污染等问题。本目录在**不修改上游仓库**的前提下补齐这些差异，两个环境共用同一份运行时脚本。

## 目录内容

- [argc-completions.sh](argc-completions.sh)：运行时初始化，被 `~/.bashrc` source；自动区分 MSYS 与 Linux/WSL，可重复 source。
- [setup.sh](setup.sh)：在 `~/.bashrc` 中写入或移除带标记的接入片段，支持试运行与卸载。
- [README.md](README.md)：本文档。

## 安装

Git Bash 中执行：

```sh
bash /c/repos/scripts/bash/argc-completions/setup.sh --dry-run
bash /c/repos/scripts/bash/argc-completions/setup.sh
```

WSL 中执行：

```sh
bash /mnt/c/repos/scripts/bash/argc-completions/setup.sh --dry-run
bash /mnt/c/repos/scripts/bash/argc-completions/setup.sh
```

安装动作只有一处：在 `~/.bashrc` 末尾写入 `# >>> argc-completions >>>` 标记块，内容为 source 运行时脚本。重新打开终端或 `source ~/.bashrc` 后生效。

卸载：

```sh
bash /c/repos/scripts/bash/argc-completions/setup.sh --uninstall          # Git Bash
bash /mnt/c/repos/scripts/bash/argc-completions/setup.sh --uninstall      # WSL
```

## 手工接入

不运行 `setup.sh` 时，把下面一行加入 `~/.bashrc` 即可，路径按当前平台替换：

```sh
source /c/repos/scripts/bash/argc-completions/argc-completions.sh          # Git Bash
source /mnt/c/repos/scripts/bash/argc-completions/argc-completions.sh      # WSL
```

可用环境变量覆盖默认行为：

| 变量 | 作用 |
| --- | --- |
| `ARGC_COMPLETIONS_DIR` | 上游仓库位置，默认 Git Bash 为 `/c/repos/argc-completions`，WSL 为 `/mnt/c/repos/argc-completions` |
| `ARGC_COMPLETIONS_ONLY` | 只注册指定命令，如 `ARGC_COMPLETIONS_ONLY="git docker cargo"` |
| `ARGC_COMPGEN_DESCRIPTION` | 是否输出候选描述，默认 `0`。只有 Tab 仍绑定普通 `complete` 且未加载 ble.sh 时，设为 `1` 才安全 |

## 为什么不能直接照搬上游步骤

上游 README 要求 Windows 在 Git Bash 中执行 `setup-shell.sh bash`，本机实测该片段本身可用，但会在若干具体环节失败。

### git bash：目录里的 Linux `argc` 遮蔽了 `argc.exe`

上游 `bin/` 由 `download-tools.sh` 按平台下载，本机同时存在 Linux 版 `argc` 与 Windows 版 `argc.exe`，而 `setup-shell.sh` 会把 `bin` 前置到 `PATH`。Git Bash 查找命令时先命中无扩展名的 Linux ELF，直接报 `cannot execute binary file: Exec format error`。更隐蔽的是，argc 在生成候选时会再启动一次 bash 执行补全脚本，脚本末尾的 `argc --argc-eval` 同样命中该 ELF，于是**静态选项正常、动态候选全部为空**（例如 `git checkout` 分支、`git add` 未暂存文件）。

适配方式：在 `~/.local/bin` 放一份 `argc.exe` 副本并置于 `PATH` 最前，上游 `bin` 只追加到末尾。这样 `argc`、`argc.exe`、`yq.exe` 都能正常解析，上游目录保持不变。

### git bash：argc 猜不到 bash 的位置

argc 在 Windows 上按“`C:\Program Files\Git\bin\bash.exe` → `git` 所在目录的 `..\bin\bash.exe`”推断 bash。本机 Git 由 Scoop 安装，实际路径是 `apps/git/current/mingw64/bin/git.exe`，与推断规则不匹配，`argc --argc-shell-path` 直接返回 `Shell not found`。这会让所有需要执行 shell 函数的动态补全失效。

适配方式：设置 `ARGC_SHELL_PATH` 为当前 bash 的 Windows 路径，运行时脚本用 `cygpath -w "$BASH"` 自动生成。

### ble.sh：描述会写进命令行

argc 的 bash 输出没有独立的描述列，默认把“候选 (说明)”拼成一个完整字符串。普通 readline 下只是列表里多了括号文字；ble.sh 的补全菜单会把选中的整串作为预览写入命令行，实际得到：

```text
git checkout\ \(Switch\ branches\ or\ restore\ working\ tree\ files\)
```

适配方式：默认导出 `ARGC_COMPGEN_DESCRIPTION=0`，候选只剩命令名，ble.sh 菜单与预览均正常。该开关在每次补全时读取，无需改上游脚本。

Git Bash 也有同样的取舍：本机 `~/.inputrc` 把 Tab 绑定为 `menu-complete`，若保留说明，列表能看到解释，但再次按 Tab 选中候选时 readline 会把整串说明插入命令行。因此默认关闭说明。若确认 Tab 使用普通 `complete` 且未加载 ble.sh，可显式设置 `ARGC_COMPGEN_DESCRIPTION=1`，此时列表显示说明，而 Tab 只补全公共前缀，不会插入说明。把 `"\C-i"` 改回 `complete` 会失去菜单循环，需要自行权衡。

### WSL：缺少 `yq`

部分补全（cargo 的 features/dependencies、ansible 的 inventory、bun 的 scripts、bws、ant 等）会调用 `yq`。WSL 默认未安装时这些候选静默为空，其余补全不受影响。可安装官方仓库中的 mikefarah 版本：

```sh
sudo pacman -S go-yq        # Arch
```

没有 `yq` 时，`argc --argc-compgen bash "" git che` 这类不依赖 yq 的补全仍能正常工作。

## 平台差异

| 项目 | Git Bash（MSYS） | WSL / Linux |
| --- | --- | --- |
| `argc` 入口 | `~/.local/bin/argc.exe` 副本 | 上游 `bin/argc` |
| `ARGC_COMPLETIONS_ROOT` | POSIX 路径，供 bash `source` 使用 | 仓库绝对路径 |
| `ARGC_COMPLETIONS_PATH` | Windows 路径、`;` 分隔，含 `windows` 子目录 | POSIX 路径、`:` 分隔，含 `linux` 子目录 |
| `ARGC_SHELL_PATH` | 必须显式指定 | 不需要 |
| `PATH` 处理 | shim 在前，上游 `bin` 在末尾 | 上游 `bin` 前置 |
| 描述输出 | 默认关闭（避免说明被插入） | 默认关闭（兼容 ble.sh） |

## 已知问题与限制

- `set -u` 会破坏补全：上游生成的 `_argc_completer_parse_line` 使用了未初始化的 `unbalance` 变量，`set -u` 下触发 `unbalance: unbound variable`。交互式 shell 不要启用 `set -u`，或在 source 前 `set +u`。
- 会覆盖同名命令的原生补全：argc 通过 `complete -F` 注册，`git`、`docker` 等原有 bash-completion 会被替换。只想保留部分命令时用 `ARGC_COMPLETIONS_ONLY` 或在运行时脚本中裁掉列表。
- WSL 的补全延迟高于 Git Bash：本机实测 `git che` 一次补全约 160 ms（Git Bash 约 40–90 ms），主要耗在启动 bash 与执行补全脚本。把上游复制到 WSL 文件系统实测无明显改善，因此默认继续复用 `/mnt/c` 的单一副本。ble.sh 的自动补全会放大该延迟，可关闭自动补全或缩小注册命令范围。
- 启动开销：本机实测 source 全部补全时 Git Bash 约 110 ms，WSL 约 25 ms。需要更快启动时用 `ARGC_COMPLETIONS_ONLY`。
- `-o nosort` 需要 bash 4.4 及以上；本机 Git Bash 为 5.2，WSL 为 5.3，均满足。
- 上游 `bin/` 内两个 argc 版本可能不一致（本机实测 Linux 版 1.23.0、Windows 版 1.24.0）。升级时运行上游 `scripts/download-tools.sh`，运行时脚本会按修改时间自动刷新 `~/.local/bin/argc.exe` 副本。
- 路径形态需注意：`ARGC_COMPLETIONS_ROOT` 必须是 bash 可读的 POSIX 路径，`ARGC_COMPLETIONS_PATH` 必须是 argc 可解析的 Windows 路径，两者不能互换。

### git diff 缺少 --cached 与 --staged 补全

现象：在 argc-completions 接管 `git` 补全后，`git diff --sta` 只给出 `--stat`，不会出现 `--staged`；`git diff --ca` 也没有 `--cached`。同组缺失的还有 `--merge-base`、`--no-index` 等。`git restore --sta` 能正常补出 `--staged`，说明 argc 的 flag 补全与本地接入均正常，问题只在 `git diff` 的选项表。

原因：上游 `completions/git.sh` 是自动生成的（文件头标注 `Automatic generated, DON'T MODIFY IT.`），生成源 `src/git.sh` 通过解析 `git <cmd> --help` 的 OPTIONS 段构造选项。`git diff` 支持多种调用形态，`--cached` / `--staged` 只写在 SYNOPSIS 与描述文字中，不进入 OPTIONS 段，生成器因此收不到。git 自带的 bash 补全把这组选项单独维护在 `__git_diff_difftool_options` 中，可侧面说明它们容易被帮助文本驱动的生成器漏掉。

可直接调用 argc 的补全入口复现，无需进入交互式补全：

```sh
argc --argc-compgen bash /c/repos/argc-completions/completions/git.sh git diff --sta
```

输出只有 `--stat`；把末尾参数换成 `--ca` 则没有输出。

临时处理：在上游仓库的 `completions/git.sh`（默认 `/c/repos/argc-completions/completions/git.sh`）的 `git diff` 段、`# @arg` 参数定义行之前补两行，重新打开终端即可生效：

```bash
# @flag --cached                          View staged changes; synonym --staged.
# @flag --staged                          Synonym for --cached.
```

该文件是生成产物，上游更新或重新生成时补丁会丢失；这与本文档其余部分“不修改上游仓库”的做法不同，仅建议用于确认问题或短期过渡。

长期处理：把补丁放到上游生成源 `src/git.sh` 的 `_patch_table` 中 `git diff` 分支，用 `_patch_table_edit_options` 的 `;;` 追加语法补充选项，再在上游仓库根执行 `./Argcfile.sh generate git` 重新生成，并向 argc-completions 提交 PR：

```bash
elif [[ "$*" == "git diff" ]]; then
    _patch_table_edit_arguments ';;' '[commit-path]...;[`_choice_diff`]' | \
    _patch_table_edit_options ';;' \
        '--cached;;View changes staged in the index' \
        '--staged;;Synonym for --cached' \
        '--merge-base;;Use the merge base of two commits' \
        '--no-index;;Compare two paths outside a Git repository'
```

本机 `git config help.format` 为 `html`，`git diff --help` 会打开浏览器并阻塞生成流程；Git Bash 中也没有 `man` 与 `col`。重新生成应在 WSL/Linux 或具备 man 查看器的环境进行，或先把 `help.format` 调整为可用方式。

该缺口基于上游 `main` 的 `completions/git.sh`（提交 `19b7038`）核对；更新上游后应先确认是否已被修复。

## 验证

安装后可在对应 shell 中检查：

```sh
command -v argc
argc --argc-version
argc --argc-shell-path
complete -p git
```

预期 `argc` 指向 shim 或上游二进制，`argc --argc-shell-path` 返回可执行的 bash 路径，`complete -p git` 显示 `_argc_completer`。动态补全可用临时仓库验证：创建未跟踪文件与分支后，`git add <Tab>`、`git checkout <Tab>` 应分别列出文件与分支。

以上结论基于本机 Git Bash（bash 5.2.37、MSYS）与 WSL Arch Linux（bash 5.3.9、ble.sh）实测；其他发行版或 Git for Windows 官方安装包的目录布局不同，`ARGC_SHELL_PATH` 可能无需设置，但不影响本方案。
