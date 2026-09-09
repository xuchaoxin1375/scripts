# zsh / Oh My Zsh 与 `deploy_omz.sh`

本文说明本仓库用 `deploy_omz.sh` 部署的 zsh 环境：Oh My Zsh（omz）框架、一组补全/提示插件，以及更新时必须处理的 `zasync` 依赖。

脚本路径：`deploy_omz.sh`  
脚本版本：以文件内 `version=` 为准（当前文档对应 `20260909.2`）。

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
| `zsh-autocomplete` | `omz` | **边输入边出补全菜单**（动态补全） | `-zac omz\|std\|false` |
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

有 `zsh-autocomplete` 时不要再手动 `compinit`（脚本会注释掉 `zsh-completions` 那段里的 `compinit`）。

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
```

其它标记包括：`disable_compfix`、`zac_compinit`、`zac bindkey config`、`zhss bindkey config`。

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
```

`-o` / `--install-omz`：`default` | `github` | `gitee` | `false`。自定义 omz 路径时用 `--zsh-custom`，并与环境变量 `ZSH_CUSTOM` 一致。

---

## 更新（`-U`）

`-U` / `--update-zsh-plugins` 只更新**已经存在**的插件仓库（fast-forward），并处理 `zasync`。  
统一切到 GitHub/Gitee 时会改 origin；选 `origin` 则不改。

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
- 安装/更新 `zasync`（vendor 优先）
- 确保 `~/.zshrc` 能 `autoload zasync`

另一台机器更新前，先同步**新版脚本 + `vendor/zasync`**，再执行 `-U`。只跑旧脚本会把 `zsh-autocomplete` 升到需要 `zasync` 的版本，但装不好依赖，动态补全就会坏。

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

---

## 故障排查

### zsh 停在 `Cloning into '.../zasync'`

原因：新版 `zsh-autocomplete` 在 prompt 前 clone GitHub。

处理：用当前脚本再跑一次安装或 `-U`（带 `vendor/zasync`）。不要干等 GitHub。

若曾 Ctrl-C 留下半截目录，脚本会用完整文件覆盖 cache，并刷新 `FETCH_HEAD`。

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
| `~/.zshrc` | omz、`plugins`、`fpath`、标记片段 |
| `~/zsh_bindkey_config.sh` | Tab/菜单键位 |
| `~/.oh-my-zsh/` | omz 框架 |
| `~/.cache/zsh/zasync` | autocomplete 运行时 cache |
