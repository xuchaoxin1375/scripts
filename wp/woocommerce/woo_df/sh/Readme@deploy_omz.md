# zsh / Oh My Zsh 与 `deploy_omz.sh`

本文说明本仓库用 `deploy_omz.sh` 部署的 zsh 环境：Oh My Zsh（omz）框架、一组补全/提示插件，以及更新时必须处理的 `zasync` 依赖。

脚本路径：`deploy_omz.sh`  
脚本版本：以文件内 `version=` 为准（当前文档对应 `20260911.1`）。

脚本只改 **zsh**（主要写 `~/.zshrc` 和 `$ZSH_CUSTOM/plugins`）。可以用 bash 执行部署，但对 bash 本身没有增强效果。

---

## 这套环境做什么

目标是让 zsh 的交互接近 fish：输入时自动出补全列表、灰色建议、语法高亮。

组成：

| 层 | 作用 | 本脚本如何处理 |
| --- | --- | --- |
| zsh | shell 本体 | **不安装**，需系统已有 `zsh` |
| Oh My Zsh | 插件/主题框架，默认 `~/.oh-my-zsh` | `-o` 控制是否安装 |
| 自定义插件 | 补全、建议、高亮等 | clone 到 `$ZSH_CUSTOM/plugins`，并改 `~/.zshrc` |
| `zasync` | `zsh-autocomplete` 的运行时依赖 | 安装/`-U` 时写入 cache、`fpath` 和 `vendor/zasync` |

未安装 zsh 时请先装好，并保证有 `git`、`curl`。精简系统常缺这两者。

---

## 插件说明

默认安装（可用命令行关掉）：

| 插件 | 默认 | 作用 | 脚本选项 |
| --- | --- | --- | --- |
| `zsh-completions` | 开 | 额外补全定义，加入 `fpath` | `-zc true\|false` |
| `zsh-autocomplete` | `omz` | **边输入边出补全菜单**（动态补全） | `-zac omz\|std\|false`；版本钉扎 `-zac-ref` |
| `zsh-autosuggestions` | 开 | 灰色历史建议 | `-zasp true\|false` |
| `zsh-syntax-highlighting` | 开 | 命令语法高亮，须靠近 `plugins` 列表末尾 | `-zshp true\|false` |
| `you-should-use` | 关 | 提醒已有 alias；个别环境会异常 | `-zysu true\|false` |
| `zsh-history-substring-search` | 关 | 按已输入前缀搜历史 | `-zhssp true\|false` |

另外会把 omz 自带的 `git`、`z` 写进 `plugins=(...)`。

### `zsh-autocomplete` 与 `zasync`

`zsh-autocomplete` 在 2026-08 的 `7633bc7` 之后不再内置异步实现，启动时会：

```text
git clone https://github.com/marlonrichert/zasync.git ~/.cache/zsh/zasync
```

国内访问 GitHub 经常卡在 `Cloning into '/home/.../.cache/zsh/zasync'...`，表现为 zsh「卡住」或动态补全不工作。

因此脚本会：

1. 优先复制脚本旁的 `vendor/zasync/`（不依赖 GitHub）
2. 失败再试 ghproxy tarball / jsDelivr
3. 安装到：
   - `~/.cache/zsh/zasync`（插件默认查找位置，并写好 `.git/FETCH_HEAD`，避免启动再 clone）
   - `$ZSH_CUSTOM/plugins/zasync`
4. 在 `~/.zshrc` 加入 `fpath`，让插件直接 `autoload zasync`

同步脚本到另一台机器时，请带上 `vendor/zasync/`，不要只拷 `deploy_omz.sh`。

`zsh-autocomplete` 加载模式：

- `omz`：放进 omz 的 `plugins=(...)`（默认）
- `std`：按上游建议在 `~/.zshrc` 靠前 `source` 插件文件
- `false`：不装

### 钉扎 `zsh-autocomplete` 版本

上游从 2026-08 起改动很大：异步实现换成 `zasync`，随后又把 `zasync` 移出仓库，启动时 `git clone` GitHub。同一套 `deploy_omz.sh` 不能假设「永远跟 main」。用 `-zac-ref` 钉在已经验证过的提交，`.zshrc` 片段会跟着切：

| `-zac-ref` | 实际提交 | 异步 | `.zshrc` |
| --- | --- | --- | --- |
| `latest`（默认） | `origin/main` | 外置 `zasync` | 写入 `# >>> zasync`，删 `# >>> zac pin` |
| `classic` | `20f6c34`（2026-03-26） | 旧 fd，无 zasync | **删除** zasync 片段；写入 `# >>> zac pin` |
| `bundled` | tag `26.08.04` / `52ce817` | zasync 仍在仓库内 | **删除** zasync 片段；写入 `# >>> zac pin` |
| 任意 git ref | 该 commit/tag | 按检出树检测 | `external` 才写 zasync 片段 |

别名：`classic` = `stable` / `pre-zasync` / `20f6c34`；`bundled` = `in-tree` / `52ce817` / `26.08.04`。

```bash
# 回到「zasync 移出之前」那套已验证的 classic
bash deploy_omz.sh -o false -zac-ref classic -s github

# 仍用内置 zasync，但不跟 main 盲升
bash deploy_omz.sh -o false -zac-ref bundled -s github

# 明确回到滚动更新
bash deploy_omz.sh -U -zac-ref latest -s origin -y
```

钉扎后仓库是 detached HEAD，标记在：

- `$ZSH_CUSTOM/plugins/zsh-autocomplete/.deploy_omz_ref`
- `~/.zshrc` 的 `# >>> zac pin`

之后只跑 `-U`（不带 `-zac-ref`）会**沿用钉扎**，不会快进到 main。其它插件仍按原规则更新。

Gitee 浅克隆有时按 SHA 取不到 `classic`，脚本会回退到 GitHub 拉那一个 commit。

### zsh 5.8 与 `unhandled ZLE widget`

同一套 `plugins` 在 zsh ≥ 5.9 上启动安静，在 **Ubuntu 22 / zsh 5.8.1** 上会报：

```text
zsh-syntax-highlighting: unhandled ZLE widget 'menu-search'
zsh-syntax-highlighting: unhandled ZLE widget 'recent-paths'
```

原因：`zsh-syntax-highlighting` 在 5.9 以下会在加载时 wrap 全部 ZLE widget；`zsh-autocomplete` 却先 `bindkey` 这两个名字，真正 `zle -N` / `zle -C` 要到 precmd。5.9+ 走 `add-zle-hook-widget`，不会去 wrap，所以其它设备上看不到这条。

功能一般没坏，只是噪音。脚本在 `source $ZSH/oh-my-zsh.sh` 前写入 `# >>> zac zsyh widgets`，给这两个名字占位；precmd 仍会覆盖成正式 widget。关掉 autocomplete 时脚本会删掉该片段。

有 `zsh-autocomplete` 时不要再手动 `compinit`（脚本会注释掉 `zsh-completions` 那段里的 `compinit`）。

### `zsh-autocomplete` 关键节点

本环境今天 `-U` 之前钉在 **`20f6c34`（2026-03-26，Fix fd handling）**。Gitee 镜像随后快进到 **`bf8db6b`（2026-08-27）**，中间几个月的提交一次拉齐，所以体感是「突然大变」。

显著变化从 **2026-08-03** 开始集中出现：

| 日期 | 提交 | 变化 | 对本环境的影响 |
| --- | --- | --- | --- |
| 2026-03-26 | `20f6c34` | Fix fd handling | **更新前版本**。↑ = `up-line-or-search`，弹出历史命令列表；异步仍是旧 fd 实现 |
| 2026-08-03 | `50a99a6` | 用 `marlonrichert/z-async` 子模块替换 fd 异步 | 实时补全的后台调度换掉；旧的 fd-widget 补丁失效 |
| 2026-08-03 | `d3a08ee` | 把 `Completions` 的 `fpath` 挪到 `plugin.zsh` | omz 仍在 source 插件前 `compinit`，`_autocomplete__history_lines` 等进不了 dump |
| 2026-08-04 | `52ce817` | 把 `z-async` 做成 subtree 内置 | 启动不必访问 GitHub |
| 2026-08-05 | `027cdab` | `unambiguous` 展示兼容 zsh &lt; 5.9 | Ubuntu 22 / zsh 5.8.1 相关 |
| 2026-08-26 | **`7633bc7`** | **不再内置 zasync，init 时 `git clone` GitHub** | **启动卡在 `Cloning into ~/.cache/zsh/zasync`** |
| 2026-08-27 | `bf8db6b` | Remove unused images | **当前 main**，今日更新落到这里 |

要恢复「↑ 弹出历史列表」：autoload Completions 后保留插件默认按键，不要把 ↑ **一律**绑成 `.up-line-or-history`。脚本已按此生成 `~/zsh_bindkey_config.sh`。当前词含 glob（如 `ls *md`）时例外，见下文故障排查。


新版和 omz 的冲突点：omz 在 `source` 插件**之前**就 `compinit`，`Completions/_autocomplete__*` 进不了 dump。上箭头默认走 `up-line-or-search` → `_autocomplete__history_lines`，就会 `command not found`。

修复：插件加载后 `autoload` 这些函数，**不要**把 ↑ 改成 `.up-line-or-history`，才能保留更新前的「弹出历史命令列表」。

---

## 和 `deploy_omz.sh` 的对应关系

脚本尽量幂等：反复运行不应把 `~/.zshrc` 搅乱。它改过的片段都带 conda 风格标记，便于识别和卸载：

```zsh
# >>> zsh-completions
...
# <<< zsh-completions

# >>> zasync
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zasync
# <<< zasync

# >>> zac zsyh widgets   # 必须在 source $ZSH/oh-my-zsh.sh 之前
if autoload -Uz is-at-least 2>/dev/null && ! is-at-least 5.9; then
  zle -N menu-search
  zle -N recent-paths
fi
# <<< zac zsyh widgets
```

其它标记包括：`disable_compfix`、`zac_compinit`、`zac bindkey config`、`zac zsyh widgets`、`zac pin`、`zhss bindkey config`。

绑定键配置会生成独立文件再 source：

- `~/zsh_bindkey_config.sh`（autocomplete / Tab 菜单）
- `~/zsh_bindkey_hss_config.sh`（可选 history-substring-search）

插件代码目录：

```text
${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/
  zsh-completions/
  zsh-autocomplete/
  zsh-autosuggestions/
  zsh-syntax-highlighting/
  zasync/                  # 运行时依赖，不是 omz plugins 列表项
  ...
```

仓库源（`-s` / `--repo-source`）：

| 值 | 安装 | `-U` 更新 |
| --- | --- | --- |
| `github` | 从 GitHub clone | 把 origin 改到 GitHub 再 pull |
| `gitee` | 从 Gitee 镜像 clone | 把 origin 改到 Gitee 再 pull |
| `origin`（别名 `keep` / `current` / `existing`） | **不允许** | **不改 remote**，各插件沿用当前 origin 做 `git pull --ff-only` |

国外机器优先 GitHub；国内 Gitee 镜像可能限流或要登录。

---

## 安装

依赖：已安装的 `zsh`，以及 `git`、`curl`。macOS 全量部署还需要 GNU sed（`gsed`）。

第一次若尚未安装 omz：脚本会装 omz、可能把默认 shell 改成 zsh 并 `exec zsh`，**当前这次部署中断**。再跑一次才会装插件、改 `~/.zshrc`。

```bash
# 查看帮助
bash deploy_omz.sh -h

# 本机已有脚本
bash deploy_omz.sh -s github
bash deploy_omz.sh -s gitee

# 远程一键（可能要跑两次）
bash <(curl -sSfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/deploy_omz.sh) -s github

# 已自行装过 omz，跳过安装框架
bash deploy_omz.sh -o false -s gitee

# 只装 omz，不装插件
bash deploy_omz.sh -O

# 关掉 you-should-use
bash deploy_omz.sh -o false -zysu false

# 钉扎 classic（20f6c34，旧 fd 异步）
bash deploy_omz.sh -o false -zac-ref classic -s github
```

`-o` / `--install-omz`：`default` | `github` | `gitee` | `false`。自定义 omz 路径时用 `--zsh-custom`，并与环境变量 `ZSH_CUSTOM` 一致。

---

## 更新（`-U`）

`-U` / `--update-zsh-plugins` 更新**已经存在**的插件仓库。`zsh-autocomplete` 若已钉扎则保持该 commit；其它插件 fast-forward。统一切到 GitHub/Gitee 时会改 origin；选 `origin` 则不改。

### 交互

```bash
bash deploy_omz.sh -U
```

菜单：

1. 沿用各插件当前 origin（默认，不改 remote）
2. GitHub
3. Gitee
4. `q` 取消

确认后才会更新。

### 非交互（必须同时给 `-s` 和 `-y`）

```bash
# 沿用原来的 origin（插件有的来自 GitHub、有的来自 Gitee 时用这个）
bash deploy_omz.sh -U -s origin -y

# 统一改到 GitHub 再更新
bash deploy_omz.sh -U -s github -y

# 统一改到 Gitee 再更新
bash deploy_omz.sh -U -s gitee -y
```

只有 `-y` 没有 `-s` 会报错，避免在非交互环境里误切源。

`-U` 现在会：

- pull 已安装插件
- 安装/更新 `zasync`
- 重写 `~/zsh_bindkey_config.sh`：autoload Completions，保留插件默认 ↑ 历史列表；含 glob 的当前词改走普通历史翻页
- 写入/更新 `~/.zshrc` 的 `# >>> zac zsyh widgets`（zsh < 5.9 消除 syntax-highlighting 的 unhandled widget 警告）
- 按当前 `zsh-autocomplete` 树决定是否保留 `# >>> zasync` / `# >>> zac pin`

另一台机器更新前先同步新版脚本再跑 `-U`。

---

## 启动后如何确认

新开一个终端（不要复用卡在 clone 的会话）。

```zsh
# 插件目录
ls "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"

# zasync 可 autoload
whence -v zasync
ls "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zasync/Functions"

# 不应再指向 GitHub origin（cache 里若有残留 github remote，脚本会拆掉以免启动时 git pull 卡住）
git -C "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zasync" remote -v
```

输入命令时：

- 下方应出现 `zsh-autocomplete` 的补全列表
- 右侧/灰色建议来自 `zsh-autosuggestions`
- 命令词着色来自 `zsh-syntax-highlighting`
- 启动不应再出现 `unhandled ZLE widget 'menu-search'` / `'recent-paths'`（zsh 5.8 上靠 `# >>> zac zsyh widgets`）

---

## 故障排查

### zsh 停在 `Cloning into '.../zasync'`

原因：新版 `zsh-autocomplete` 在 prompt 前 clone GitHub。

处理：用当前脚本再跑一次安装或 `-U`（带 `vendor/zasync`）。不要干等 GitHub。

若曾 Ctrl-C 留下半截目录，脚本会用完整文件覆盖 cache，并刷新 `FETCH_HEAD`。

### 上箭头报 `_autocomplete__history_lines` / `_autocomplete__unambiguous`

这不是「新版取消了历史列表」，而是 Completions 函数没 autoload。更新前 ↑ 弹出历史列表，正是插件默认的 `up-line-or-search`。

`~/zsh_bindkey_config.sh` 会 autoload `Completions/_autocomplete__*`，并且**不覆盖** ↑/↓。`exec zsh` 后应恢复列表。若仍没有列表，检查 bindkey：

```zsh
bindkey '^[[A'   # 应为 up-line-or-search
bindkey '^[OA'
```

### `-U` 之后动态补全没了

常见原因：

1. 另一台机器还在用旧脚本，只更新了 `zsh-autocomplete`
2. 没带 `vendor/zasync`，网络回退也失败
3. `~/.zshrc` 没有 `# >>> zasync` 那段 `fpath`

用新脚本执行：

```bash
bash deploy_omz.sh -U -s origin -y
```

然后新开终端。

### `ls *md` 再按上下箭头卡死

`zsh-autocomplete` 的实时补全会把 `*md` 当成 glob，先画出 **globbed files / expansion**。此时再按 ↑（`up-line-or-search` / `history-search-backward`）会停在 `Loading...`，随后响铃或假死（上游 [#843](https://github.com/marlonrichert/zsh-autocomplete/issues/843)，zsh 5.8 上更明显）。↓ 的 `menu-select` 同样会走进这份展开列表。

`~/zsh_bindkey_config.sh` 的处理：

1. `zstyle ':autocomplete:*' ignored-input '*[\*\?\[]*'`：当前词含 `*` `?` `[` 时不实时列文件
2. 这些词上 ↑/↓/`^P`/`^N` 改走 `.up-line-or-history` / `.down-line-or-history`，不进历史菜单、不进补全菜单

不含 glob 的词（如 `ls`）仍然弹出历史命令列表。需要展开 glob 时用 Shift-Tab（`expand-word`）。

手改后 `exec zsh`。或：

```bash
bash deploy_omz.sh -U -s origin -y
```

### `zsh-syntax-highlighting: unhandled ZLE widget 'menu-search'`

当前机是 **zsh 5.8.1**（Ubuntu 22）。`zsh-syntax-highlighting` 在 5.9 以下会在加载时 wrap 全部 widget；`zsh-autocomplete` 却把 `menu-search` / `recent-paths` 先 bindkey，真正 `zle -N`/`zle -C` 要到 precmd。于是启动时报：

```text
zsh-syntax-highlighting: unhandled ZLE widget 'menu-search'
zsh-syntax-highlighting: unhandled ZLE widget 'recent-paths'
```

其它机器若是 zsh ≥ 5.9，走 `add-zle-hook-widget`，不会出现这条。功能本身通常没坏，只是噪音。

处理：完整部署或 `-U` 都会在 `source $ZSH/oh-my-zsh.sh` **之前**写入：

```zsh
# >>> zac zsyh widgets
if autoload -Uz is-at-least 2>/dev/null && ! is-at-least 5.9; then
  zle -N menu-search
  zle -N recent-paths
fi
# <<< zac zsyh widgets
```

占位只为挡住 wrap；第一次 prompt 前 autocomplete 的 precmd 仍会 `zle -C menu-search` / `zle -N recent-paths`。不要把这段放到 `oh-my-zsh.sh` 之后，警告已经打印过了。

手改 `~/.zshrc` 后 `exec zsh`。或：

```bash
bash deploy_omz.sh -U -s origin -y
```

`-zac false` 时脚本会删除该片段。

### `compinit: insecure directories`

常见于 linuxbrew 目录属主不是当前用户。脚本会写：

```zsh
ZSH_DISABLE_COMPFIX=true
zstyle '*:compinit' arguments -i -u
```

一般可忽略；不要随便对系统目录 `chmod`。

### 插件更新被跳过

`-U` 遇到下列情况会跳过该仓库并报 warn：

- 不是 git 仓库
- 有未提交改动
- detached HEAD
- 选了 `origin` 但该插件没有 `origin`

### 补全行为在 GNU / BSD 工具上不一致

`ls`、`grep` 等选项不同。测补全时注意当前是 GNU 还是 BSD。

---

## 卸载或减插件

1. 删目录：`$ZSH_CUSTOM/plugins/<插件名>`（以及不需要时的 `zasync`）
2. 从 `~/.zshrc` 的 `plugins=(...)` 去掉对应名字
3. 删掉成对的 `# >>> ...` / `# <<< ...` 片段
4. 可选：删 `~/zsh_bindkey_config.sh`、`~/.cache/zsh/zasync`

重装 omz：

```bash
rm -rf ~/.oh-my-zsh
bash deploy_omz.sh -O
# 再跑一次完整部署以安装插件
bash deploy_omz.sh -o false -s gitee
```

---

## 相关文件

| 路径 | 说明 |
| --- | --- |
| `deploy_omz.sh` | 部署/更新入口 |
| `vendor/zasync/` | 内置 `zasync`，避免启动时访问 GitHub |
| `~/.zshrc` | omz、`plugins`、`fpath`、标记片段（含 `zac zsyh widgets`、`zac pin`） |
| `~/zsh_bindkey_config.sh` | Tab/菜单键位；glob 词绕开历史上拉卡死 |
| `$ZSH_CUSTOM/plugins/zsh-autocomplete/.deploy_omz_ref` | `-zac-ref` 钉扎记录 |
| `~/.oh-my-zsh/` | omz 框架 |
| `~/.cache/zsh/zasync` | autocomplete 运行时 cache |
