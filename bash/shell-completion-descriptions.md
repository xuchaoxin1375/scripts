# zsh 的 git 补全选项描述缺失

macOS 上 zsh 补全 `git` 时只出现选项名、不显示说明，原因通常在 `fpath` 里 `_git` 的来源，而不是 zsh 或 git 版本。修复片段由 [`deploy_omz.sh`](../wp/woocommerce/woo_df/sh/deploy_omz.sh) 的 `ensure_git_completion_fpath_zshrc` 维护。

## 现象

在 `~/.zshrc` 加载完成后，按 Tab 只看到选项名：

```text
git commit --am<TAB>
--amend
```

正常应当带描述：

```text
--amend  -- amend the tip of the current branch
```

## 原因

zsh 从 `fpath` 中第一个名为 `_git` 的文件加载补全函数。同一台机器上可能有两份：

| 来源 | 典型路径 | 是否带描述 |
| --- | --- | --- |
| zsh 自带 | `/usr/share/zsh/<版本>/functions/_git` | 带，函数内写作 `--amend[amend the tip of the current branch]` |
| git / Homebrew 附带 | `$(brew --prefix)/share/zsh/site-functions/_git` | 不带，是 bash 补全的 zsh wrapper，文件头为 `# zsh completion wrapper for git` |

Homebrew 的 `brew shellenv` 会把 `site-functions` 插到 `fpath` 最前面：

```zsh
fpath[1,0]="/opt/homebrew/share/zsh/site-functions";
export FPATH;
```

wrapper 因此遮住 zsh 自带实现，选项描述随之消失。Linux 上如果 git 由源码或第三方包装安装，也可能出现同类目录。

## 判断当前生效的 `_git`

```zsh
autoload -Uz +X _git
print -r -- ${functions_source[_git]}
```

指向 `.../functions/_git` 说明已用原生实现；指向 `.../share/zsh/site-functions/_git` 说明仍是 wrapper，需要修复。

列出所有 wrapper 目录：

```zsh
for d in $fpath; do
  [[ -f $d/_git ]] && grep -q 'zsh completion wrapper for git' "$d/_git" && print -r -- "$d"
done
```

## 修复

把这类目录降到 `fpath` 末尾，让 zsh 自带 `_git` 重新排到前面。片段必须放在 `~/.zshrc` 末尾，确保它看到的是 oh-my-zsh 和各插件追加完的完整 `fpath`：

```zsh
# >>> git completion fpath
# 部分 git 安装（如 Homebrew）附带 bash 兼容层 _git，并经 shellenv 前置到 fpath，
# 会遮住 zsh 自带、带选项描述的 _git。把这类目录移到 fpath 末尾；无可移动项时不做改动。
() {
  emulate -L zsh
  local d
  local -a demote keep
  for d in $fpath; do
    [[ -f $d/_git ]] || continue
    if grep -q 'zsh completion wrapper for git' "$d/_git" 2>/dev/null; then
      demote+=("$d")
    fi
  done
  (( ${#demote} )) || return 0
  for d in $fpath; do
    (( ${demote[(Ie)$d]} )) || keep+=("$d")
  done
  fpath=($keep $demote)
}
# <<< git completion fpath
```

片段只改 `fpath` 顺序，不删除任何文件，也不依赖特定 zsh 版本路径；没有 wrapper 时直接返回。`deploy_omz.sh` 会先删除旧片段再追加到末尾，重复执行不会产生多个副本。

## 部署与验收

完整部署（不带 `-U`）时由脚本自动写入：

```bash
bash wp/woocommerce/woo_df/sh/deploy_omz.sh
```

已经配置过 `~/.zshrc` 的机器可以只检查标记块和实际加载来源：

```zsh
grep -n 'git completion fpath' ~/.zshrc
autoload -Uz +X _git
print -r -- ${functions_source[_git]}
```

再新开终端（或 `exec zsh`）验证描述：

```text
git commit --am<TAB>
--amend  -- amend the tip of the current branch

git --no-pag<TAB>
--no-pager  -- don't pipe git output into a pager
```

## 边界与回退

- 片段降级的是整个含 wrapper 的目录。本机 Homebrew `site-functions` 与系统 zsh 函数目录唯一重名项是 `_git`，因此不影响其他补全；若将来出现其他重名，可改为只把系统 `_git` 插到 `fpath` 前面。
- 只影响新启动的交互式 shell；当前会话执行 `exec zsh` 后生效。
- 与 bash 补全无关。bash 侧的 carapace/argc 接入见 [`completion-stack/README.md`](completion-stack/README.md)。
- 回退：删除 `~/.zshrc` 中 `# >>> git completion fpath` 到 `# <<< git completion fpath` 之间的内容，再 `exec zsh`；重跑 `deploy_omz.sh` 会重新写入。

验证范围：macOS 27.2，`/bin/zsh` 5.9 与 Homebrew zsh 5.9.1，Homebrew git 2.54.0。
