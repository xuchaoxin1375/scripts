# scripts

> A collection of practical scripts for daily use: PowerShell modules (`PS/`, 67 modules, pwsh-first) and shell scripts (bash/zsh).
> 实用脚本集合：PowerShell 模块集（`PS/`，67 模块）与 shell 脚本库（bash/zsh）；下文以中文为主。
>
> 仓库：[github.com/xuchaoxin1375/scripts](https://github.com/xuchaoxin1375/scripts) · [gitee.com/xuchaoxin1375/scripts](https://gitee.com/xuchaoxin1375/scripts)

## 你是谁？先看这里

| 你要做什么 | 看哪里 |
|---|---|
| 新机装 PowerShell 环境 | 本文“快速开始”→ [部署指南](./PS/docs/Deploy-Guide.md) |
| 日常用（查命令、配补全） | [用户手册](./PS/docs/Feature-Guide.md)（§2 命令表；§7/§8/§10 补全；§9 dll 管理） |
| 出问题 | 先跑 `doctor`，再按 [文档入口地图](./PS/docs/README.md) 分流 |
| 机器只有 Windows PowerShell 5.1 | 本文 `-Light` → [Feature-Guide §13](./PS/docs/Feature-Guide.md) |
| 找功能在哪个模块 | [模块地图](./PS/docs/Module-Map.md)（67 模块画像表） |
| 改模块/加函数、写自动化 | [PS/AGENTS.md](./PS/AGENTS.md) → [踩坑编年史](./PS/docs/Agent-Handoff.md)（§3 必读） |

## 快速开始：PowerShell 模块集

### 一键部署（完整版，适合长期使用）

默认走 github + 加速镜像（gitee 对 `irm|iex` 常误报拦截，只留兼容，不再作为默认源）：

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex
```

已经装好 PowerShell 7 和 git 的机器会跳过软件安装、直接 clone，速度更快更稳；没装则尝试自动安装（可靠性不保证，失败看“GitHub 加速与部署故障”一节）。想先审查脚本或指定参数，分步执行：

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1' > ~/dcp.ps1
~/dcp.ps1 -RepoSource github
# 已有仓库想强制覆盖：Deploy-CxxuPsModules -Verbose -Confirm
```

细节见 [部署说明](./PS/Deploy/readme.md)。

### 落仓库后第二步：补全栈

上一条只落仓库加环境；关掉重开终端（自动 `init`），再装补全栈（[部署指南](./PS/docs/Deploy-Guide.md)极简版，共 2 条命令）：

```powershell
Deploy-CompletionStack
# 再重开一次，缓存就绪。版本不够 7.5 会警告（自研 predictor 用不上，其它照常）。
```

### 轻量部署（仅 Windows PowerShell 5.1，免 git 免 pwsh）

新机器只有 v5 时，在 `powershell.exe` 里存下脚本再加 `-Light` 跑：无 git 不提示安装、直走离线包下载（codeload + 中央镜像静默，不弹窗选源），落 `PSModulePath`（追加不覆盖），结尾不装 pwsh、改写 5.1 专属 profile，重开 `powershell.exe` 跑 `init` 即用（B 档可用范围与禁区见 [Feature-Guide §13](./PS/docs/Feature-Guide.md)）：

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1' > ~/dcp.ps1
~/dcp.ps1 -Light
```

### 临时使用（不取全仓）

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy.psm1'|iex   # Deploy 系列（含镜像测速、scoop、smb 等）
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Tools/Tools.psm1'|iex     # Tools 系列小工具
```

### 本地开发（未推送时用本地代码测部署）

仓库内直接运行一键脚本并加 `-Dev`（仓库根从脚本位置自动推导，4 个一键脚本通用：`Deploy-CxxuPsModules`、`Deploy-GitForWindows`、`Deploy-Pwsh7Portable`、`Register-GithubHostsAutoUpdater`；marker 缺失则警告并回退远端）：

```powershell
C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Dev # 可叠 -Light -WhatIf（注意脚本尾部有真实调用）
```

## 兼容与版本要求

- 强烈建议 PowerShell 7+（完整功能与最佳性能；联想应用商店可下，版本可能非最新，不影响使用）。
- 67 模块中 62 个兼容 Windows PowerShell 5.1（B 档：`init` + 提示符 + Tab 补全 + 历史可用；预测视图与 dll 链留 7 不降）；查数用 `Get-CxxuModuleCompatibility`（真相源是各模块自己的 `.psd1`），清单与加码禁区见 [Feature-Guide §13](./PS/docs/Feature-Guide.md)。
- 5.1 下读 UTF-8 文档（含中文）用 `Get-ContentUTF8`（裸 `Get-Content` 按 GBK 解码必乱码）；5.1 专属 profile 可跑 `Install-Ps51Profile` 一键写入（与 7 互不干扰）。

## GitHub 加速与部署故障

- 中央变量 `$env:PsGithubMirror`（不设默认 `gh-proxy.com`，模块内静默测速、会话缓存一次）；内置镜像过期就先测速再换：`Get-AvailableGithubMirrors`，挑最快的持久化（`Add-EnvVar -EnvVar PsGithubMirror -NewValue 'https://xxx'`）；可用列表与实测日期见 `PS/TestLinks/TestLinks.psm1` 头部。
- 不要再硬编码旧域名（`github.moeyy.xyz` 已停服，`ghproxy.cc`/`mirror.ghproxy.com` 已不可用）；自找镜像对照搜集页（注意甄别，很多已停服）：[GitHub文件加速|列表集合](https://yishijie.gitlab.io/ziyuan/)（聚合页，非下载前缀）、[镜像站点搜集 Issue #116](https://github.com/hunshcn/gh-proxy/issues/116#issuecomment-2339526975)。
- 会过期的外部资源（镜像站/上游版本/第三方域）统一登记在 [部署指南 §14](./PS/docs/Deploy-Guide.md)，部署失败先查该表再换链接。
- 执行策略报错先跑 `Set-ExecutionPolicy Bypass -Scope CurrentUser -Force`；git 读配置报错则移除或备份 `~/.gitconfig`（`rm ~/.gitconfig` 或 `mv ~/.gitconfig ~/.gitconfig.bak`）。

## 直接 clone（不走一键脚本时）

先关 `autocrlf` 再 clone（Windows 必做，否则 bash 脚本换行被改成 CRLF，在 git-bash 里跑出错）：

```bash
git config --global core.autocrlf false
```

已经 clone 坏的两种补救：删仓重 clone；或配好模块后跑 `cd $sh;ls -Recurse *.sh,.inputrc.conf|Convert-CRLF -Replace -To LF;cd -` 把换行改回 LF。精简系统（如 alpine）先装 bash 与 git：`sudo apk add bash git`。

Windows（用 powershell 运行；目录建议固定 `C:/repos/scripts`，profile 与 conda 缓存里写的是这个路径）：

```powershell
New-Item -itemtype directory C:/repos -Verbose -ErrorAction SilentlyContinue
git clone --recursive --depth 1 --shallow-submodules https://github.com/xuchaoxin1375/scripts.git C:/repos/scripts
setx PsModulePath C:/repos/scripts/PS
```

国内从 gitee clone 可能要求登录；github 免登录但直连不一定通，不通走代理：

```powershell
$proxy = "http://127.0.0.1:8800" # 代理 url
New-Item -itemtype directory C:/repos -Verbose -ErrorAction SilentlyContinue
git -c http.proxy="$Proxy" -c https.proxy="$Proxy" clone --recursive --depth 1 --shallow-submodules https://github.com/xuchaoxin1375/scripts.git C:/repos/scripts
setx PsModulePath C:/repos/scripts/PS
```

`*nix`（`repo_source` 国内直连不通可换代理/镜像，备选 gitee 可能要求登录）：

```bash
repos="$HOME/repos"
scripts="$repos/scripts"
repo_source="github.com"
mkdir -p "$repos"
git clone --recursive --depth 1 --shallow-submodules https://"$repo_source"/xuchaoxin1375/scripts.git "$scripts"
# 配 shell 脚本库（兼容 bash/zsh）
sh_script_dir="$scripts/wp/woocommerce/woo_df/sh"
sh_sym="$HOME/sh" sh="$sh_sym"
ln -snfv "$sh_script_dir" "$sh_sym"
bash $sh/shellrc_addition.sh # 部署 prompt 主题与补全
exec bash # 让配置生效
```

clone 参数：`--depth 1` 只取最近一次提交（最省空间）；`--recursive` 顺带子模块（`ble.sh` 建议带）；`--shallow-submodules` 让子模块同样只取最新；`--single-branch` 只取主分支。

## shell（bash/zsh）与服务器

个人电脑与服务器共用一套 shell 库（`wp/woocommerce/woo_df/sh`，`$sh` 指向它），服务器另有 nginx/fail2ban 等专用配置（下面方案不碰服务器软件配置）。

一键部署 shell 环境（没部署过则完整 clone，否则更新代码）：

```bash
bash <( curl -sSfL https://gitee.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/update_shell_config.sh)
```

服务器仅取代码（`-F` 会覆盖 nginx 主配置，酌情加；反向代理后的后端机加 `-R`）：

```bash
## github
bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh) -U # -F -R
## gitee（国内）
bash <(curl -SfL https://raw.giteeusercontent.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/update_repos.sh) -U # -F -R
```

某次更新把更新脚本本身搞坏时，绕过 `$sh`（首次使用 `$sh` 未定义会下到根目录）直取直跑：`curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh -o $HOME/update_repos.sh && bash $HOME/update_repos.sh`（raw 链接去仓库页“原始数据”处取，github 与 gitee 均可）。

虚拟机/模拟层与宿主机共用（先定义 `_REPO_BASE="repos/scripts"` 与 `_SH_RELATIVE="wp/woocommerce/woo_df/sh"`；wsl 连 windows 仓，lima 连 mac 宿主仓）：

```bash
# wsl
ln -snfv /mnt/c/repos ~/repos
ln -snfv /mnt/c/$_REPO_BASE/$_SH_RELATIVE ~/sh
bash ~/sh/shellrc_addition.sh && exec bash
# lima（mac）
ln -snfv $HOME/repos ~/repos
ln -snfv $HOME/$_REPO_BASE/$_SH_RELATIVE ~/sh
bash ~/sh/shellrc_addition.sh && exec bash
```

## 日常使用与更新

- 开新终端跑 `init`（完整环境）或 `p`（轻量常用）；`init -Timing` 看分步耗时，启动慢对照 [性能基线](./PS/docs/Startup-Optimization.md)。
- 查命令：`Get-ModuleByCxxu`（5.1 可用）→ `Get-Command -Module <名>` → `Get-Command <命令>` 反查归属；补全、开机任务、手动启用清单见 [用户手册 §4/§7/§8/§10/§11](./PS/docs/Feature-Guide.md)。
- 更新：`Update-ReposesConfiged`（批量拉取；带 dll 变更则同步活件后**重开终端**再 `init`，纯 psm1 变更跑 `ipmox` 即可，会话变量不丢）；收尾跑 `Test-PsEnvReadiness`（加 `-CheckRemote` 可顺便看远端有无更新，只读不写本地）。
- dll/活件机制（并排版本 + 指针）见 [设计专章](./PS/docs/Live-Versions.md)；`git pull` 只写仓库目录、纯文本永不锁，随便拉；仓库源 dll 点不亮时本地重编（macOS/新版 pwsh），流程见设计专章 §10。

## 文档地图

`PS/docs/` 是唯一真相源（代码注释与文档矛盾时以文档为准）：

| 文档 | 一句话 |
|---|---|
| [用户手册](./PS/docs/Feature-Guide.md) | 命令表、补全、dll 管理、FAQ、手动启用清单（§11） |
| [部署指南](./PS/docs/Deploy-Guide.md) | 新机部署：极简 2 条命令、分步详解、多设备差异、更新（§13）、时效性清单（§14） |
| [设计专章](./PS/docs/Live-Versions.md) | 并排版本活件：结构、指针协议、流程、故障、命令分工 |
| [模块地图](./PS/docs/Module-Map.md) | 67 模块画像表：找功能先查表 |
| [性能基线](./PS/docs/Startup-Optimization.md) | 基线表 + 搬迁史：动热路径先看 |
| [踩坑编年史](./PS/docs/Agent-Handoff.md) | 每个决策的起因、实测、教训（agent 必读 §3） |
| [规范](./PS/docs/Module-Conventions.md) | 命名/编码铁律 + 文档语言 |
| [入口地图](./PS/docs/README.md) | 按任务分流（新用户从这张表进） |
| [agent 入口](./PS/AGENTS.md) | 红线、换行、提交规范 |

找命令按“日常使用与更新”三段式，找故障先跑 `doctor`（它会点名文档章节），找决策理由按 Handoff 编号查。`PwshModuleByCxxu.md` 描述旧结构，仅供考古（另有三站镜像：[GitCode](https://gitcode.com/xuchaoxin1375/Scripts/blob/main/PwshModuleByCxxu.md) · [Gitee](https://gitee.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md) · [GitHub](https://github.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)）。
