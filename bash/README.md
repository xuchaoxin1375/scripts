# bash 补全：归属、顺序与排查入口

`bash/` 下三份接入说明各有细节；补全框架（argc-completions、carapace、ble.sh）都通过 `complete -F` 注册，**同一命令后注册者生效**。先在这里确定归属与生效边界，再进对应目录。

## 归属约定

- git / gitk 归 carapace：argc 的 git 补全由 `git <cmd> --help` 的 OPTIONS 段生成，缺 `--cached`、`--staged`、`--merge-base`、`--no-index` 等只写在 SYNOPSIS 的选项。
- 其余命令可分工：按「argc 先、carapace 后」source，重叠命令交 carapace，argc 独有命令（如 `nginx`）保留。
- 想让 argc 接管某个两边都有的命令：把它写进 `CARAPACE_EXCLUDES`；argc 侧只能正向列举（`ARGC_COMPLETIONS_ONLY`）。
- 取舍详情与 PowerShell 侧差异见 [carapace README](carapace/README.md#与-argc-completions-共存)；组合部署顺序见 [completion-stack README](completion-stack/README.md)。

## 症状分流

| 现象 | 先查 | 结论与去处 |
| --- | --- | --- |
| Tab 候选仍来自旧框架（如装了 carapace，git 仍是 argc） | `complete -p git` | 看注册函数是 `_carapace_completer*` 还是 `_argc_completer`；归属见上，reload 见下 |
| `setup.sh --status` 显示已接入，实际终端没变 | 终端启动时间与 rc 修改时间 | 状态只读 rc 与子 shell；当前会话需 `source` rc 或新开终端 |
| 已打开的会话想当场撤销某个命令 | `complete -r <命令>` | 只影响当前会话；持久停用用 `setup.sh --disable` |
| 第一次 Tab 只补前缀 / 候选被插进命令行 | `bind -q complete`、`bind -q menu-complete` | Tab 的列表/循环模式由 dotfiles 助手决定，见 [completion-stack](completion-stack/README.md#临时停用-tab-模式) |
| git 缺 `--cached`、`--staged` | `complete -p git` | git 归了 argc；换回 carapace，或明确接受该缺口时保留 |

## 诊断

当前会话的注册状态用 source 型诊断脚本查看——`complete -p` 在子进程里看不到父会话的注册，必须让脚本跑在当前 shell 里：

```bash
source <仓库路径>/bash/completion-diagnose.sh
```

它只读，输出 bash 版本、rc 块顺序、`git`/`gitk`/`nginx` 的注册函数、rc 是否在本次 shell 启动后修改、排除项变量与 Tab 绑定，并对 git 归属和 reload 给出结论。优先复用这个入口，不手写一次性探测。

## 生效边界

- 安装、卸载、改排除项都**只影响之后的 shell**；当前会话里 `complete -F` 已注册、函数仍在内存。
- 改完执行一次 `source <rc>`（或新开终端），再用 `complete -p <命令>` 确认来源；非交互自查用 `bash -ic 'complete -p git'`。
- 运行时脚本的 `_CARAPACE_SHELL_LOADED`、`_ARGC_COMPLETIONS_LOADED` 只防重复 source，不能当开关。

## 目录

- [carapace](carapace/README.md)：安装、rc 接入、共存与排障
- [argc-completions](argc-completions/README.md)：安装、平台适配与 git 选项缺口
- [completion-stack](completion-stack/README.md)：一键组合、顺序规则、分层停用与验收
- [completion-diagnose.sh](completion-diagnose.sh)：当前会话的来源、rc 新鲜度、排除项与 Tab 绑定诊断（source 运行）
- [shell-completion-descriptions.md](shell-completion-descriptions.md)：zsh 侧 `_git` 描述缺失（与 bash 无关）
