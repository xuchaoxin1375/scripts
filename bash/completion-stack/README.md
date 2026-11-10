# bash 补全组合部署（argc + carapace）

把 bash 的参数补全接成「carapace 负责重叠命令（git、docker 等）、argc-completions 补 carapace 缺失的命令（如 nginx）」。本目录只做编排，安装与 rc 写入仍由两个子脚本完成：

- [../argc-completions/setup.sh](../argc-completions/setup.sh)
- [../carapace/setup.sh](../carapace/setup.sh)

两者都通过 bash 的 `complete -F` 注册，同一命令后加载者生效，所以组合顺序固定为 **argc 在前、carapace 在后**。

## 新设备

前提：bash 4+；已克隆本仓库；argc-completions 克隆在 `~/argc-completions`（或用 `--argc-dir` 指定）。

```bash
git clone https://github.com/sigoden/argc-completions.git ~/argc-completions

cd /path/to/scripts/bash/completion-stack
bash setup.sh --dry-run            # 看两个子脚本会写什么
bash setup.sh --install-carapace   # 装 carapace 二进制并写入两个 rc 块
bash setup.sh --check              # 只读验收
```

- 已有 carapace 二进制时去掉 `--install-carapace`，只写 rc。
- 只想用其中一个：`--skip-argc` 或 `--skip-carapace`。
- 登录 shell（macOS Terminal、Git Bash、ssh）加 `--login`；先在实际终端执行 `shopt -q login_shell` 判断。
- rc 中已有 carapace 块时，argc 块会插到它之前，不会把 git 抢回去。

## 选项

| 选项 | 作用 |
| --- | --- |
| `-n`, `--dry-run` | 只打印两个子脚本将执行的动作，不修改文件 |
| `-c`, `--check`、`--status` | 只读检查 carapace 状态、argc 片段与加载状态 |
| `-u`, `--uninstall` | 移除两个 rc 标记块，不删除二进制 |
| `-l`, `--login` | 写入登录 shell 实际读取的 rc |
| `-r`, `--rc <file>` | 指定 rc 文件，默认 `~/.bashrc`；与 `--login` 互斥 |
| `--argc-dir <dir>` | argc-completions 克隆目录；默认 `$ARGC_COMPLETIONS_DIR` 或自动探测 `~/argc-completions` 等 |
| `--install-carapace` | 顺带调用 `carapace/setup.sh --install` 安装二进制 |
| `--skip-argc` | 只接入 carapace |
| `--skip-carapace` | 只接入 argc |
| `-h`, `--help` | 显示帮助 |

## 生效与验收

```bash
bash -ic 'complete -p git; complete -p nginx'
bash -ic 'bind -p | grep C-i'
```

预期 `git` 为 `_carapace_completer_ble`、`nginx` 为 `_argc_completer`。Tab 的「列表/循环」模式来自 dotfiles 的 `shellrc_addition.sh`（见 [carapace README](../carapace/README.md) 的「Tab 列表与循环」）；只部署本目录不会改动 Tab 绑定。

## 卸载

```bash
bash setup.sh --uninstall           # 移除两个标记块
bash setup.sh --uninstall --login   # 登录 shell 安装时
```

二进制按安装渠道卸载（`scoop uninstall carapace-bin`、`brew uninstall carapace`，或删除 `~/.cxxu/bin/carapace.exe` / `~/.local/bin/carapace`）。

## 边界与已知行为

- 需要 bash 4 及以上；Windows 用 Git Bash，`--install-carapace` 走 windows zip。
- 启动成本：本机实测 argc 运行时约 135–145 ms、carapace 约 50 ms；只想覆盖部分命令时用 `ARGC_COMPLETIONS_ONLY` 缩小注册范围。
- 重跑单个子脚本会改变顺序：重跑 argc 会自动插到 carapace 前；重跑 carapace 会追加到末尾（仍在 argc 之后）。
- 只覆盖 bash；PowerShell 的 git 归属由 `PsGitCompletionSource` 决定（`Auto` 已优先 `git-completion`）。
- `--check` 会分别用 `bash -ic` / `bash -lic` 探测 argc 是否加载，登录 shell 会打印 job control 警告，可忽略。
