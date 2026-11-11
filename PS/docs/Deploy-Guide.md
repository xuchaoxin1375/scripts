# 新机部署指南（Deploy Guide）

> 目标：把模块集搬到另一台机器。先跑 `Test-PsEnvReadiness` 查缺口，再按需补；下面的极简版覆盖大多数新机器。
> 新机器还没有模块路径时，可直接导入脚本目录的清单：`Import-Module C:\repos\scripts\PS\Deploy\Deploy.psd1`。

## 极简版

### 前置：执行策略

与 Scoop 安装前置相同，先允许当前用户运行本地脚本：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

- 只改当前用户，不需要管理员；若报错，说明由 `MachinePolicy`/`UserPolicy` 组策略管控，需要管理员处理后再继续。
- 下载的脚本或 zip 带 Mark-of-the-Web 时，保存后执行 `Unblock-File`；`irm -OutFile` 保存的通常没有这个标记。

### 保存部署脚本

部署脚本就是仓库里的 `PS/Deploy/Deploy-CxxuPsModules.ps1`。先保存到本地，再按参数运行；保存一次可反复使用，也便于查看内容和修改参数。

```powershell
# 后文用 $deployScript 指这份副本；目录和文件名可以自定
$deployScript = "$HOME\Downloads\Deploy-CxxuPsModules.ps1"
# 镜像单独设置：换源只改这一行
$mirror = if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }
irm "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1" -OutFile $deployScript
```

- 保存下来的是同一个部署脚本，不是另一个版本；改名不影响运行。
- `$deployScript` 只在当前窗口有效；新开窗口后重新执行上面的赋值。
- 必须用 `-OutFile` 保存原始字节；Windows PowerShell 5.1 用 `>` 会写成 UTF-16，脚本解析失败。

### 运行部署

```powershell
& $deployScript
# 关闭并重开终端，profile 自动执行 init
Deploy-CompletionStack
# 再次重开终端，补全缓存就绪
```

- 只使用 Windows PowerShell 5.1 时直接运行即可；若同时没有 git，改用 `& $deployScript -Light`（见下）。
- 需要 PowerShell 7 时用 `& $deployScript -InstallPwsh7`；默认不安装。
- 默认下载前缀为 `https://gh-proxy.com`，用于 git 克隆、raw 脚本与离线包；可用 `-GithubMirror '<镜像>'` 或持久化 `$env:PsGithubMirror` 覆盖。
- 核心 `CxxuCommand` 的内联预测要求 PowerShell 7.5 及以上（7.5/7.6 均可，7.6 基于 .NET 10 可直接加载）；版本不足时只有警告，其余功能照常。仅用 Windows PowerShell 5.1 时另有 Tab 补全（`ps51` netstandard2.0 活件），没有内联预测。
- 参数的完整说明、离线安装、开发模式与沙箱调试见 [PS/Deploy/readme.md](../Deploy/readme.md)。
- 若 `& $deployScript` 仍报“禁止运行脚本”，回到“前置：执行策略”；重开后找不到 `Deploy-CompletionStack`，说明 profile 的 `init` 未执行，同样先处理策略。

### 按需修改参数

参数较多时，一长串命令既难读也难改。把参数写进哈希表，需要哪项就取消哪行的注释：

```powershell
$deployParams = @{
    # 只有 Windows PowerShell 5.1 且不装 git 时启用
    # Light        = $true
    # 部署完成后安装 PowerShell 7
    # InstallPwsh7 = $true
    # 部署到其他目录
    # RepoPath     = 'D:\repos\scripts'
    # 使用已下载的 zip，完全离线
    # Mode         = 'Default'
    # PackagePath  = 'D:\downloads\scripts-main.zip'
}
& $deployScript @deployParams
```

- 全部注释掉时等同于不带参数运行；只改一项也可以直接写 `& $deployScript -Light`。
- 不建议用 `irm ... | iex` 直接执行：不能传参数、不方便先检查内容，5.1 下还要额外裁剪 BOM。

### 典型参数组合

- 只有 Windows PowerShell 5.1、免 git：`& $deployScript -Light`
- 标准部署（有 git，镜像克隆）：`& $deployScript`
- 同时安装 PowerShell 7：`& $deployScript -InstallPwsh7`
- 已下载 zip、完全离线：`& $deployScript -Mode Default -PackagePath D:\downloads\scripts-main.zip`
- 默认目录已存在、重新部署：`& $deployScript -Force`
- 部署到其他目录：`& $deployScript -RepoPath D:\repos\scripts`

## 0. 先查缺口

```powershell
Test-PsEnvReadiness   # 必备/可选/首跑生成物三档表格，备注列直接给补法/对比结论
Get-CxxuDependencyReport -Missing   # 按功能看外部依赖与安装建议，只读、零网络
```

- `Test-PsEnvReadiness` 看整体安装态；`Get-CxxuDependencyReport` 按功能列出外部命令、PS 模块、argc 组件与活件，缺什么、怎么补见 [Feature-Dependencies.md](Feature-Dependencies.md)。

## 1. pwsh 7

```powershell
Update-PowerShell          # 自带升级；或 winget/scoop 重装
$PSVersionTable.PSVersion  # 完整功能需要 Major >= 7；5.1 的可用范围见 Feature-Guide 的 5.1 章节
```

## 2. git + 拉仓库

> 只有 Windows PowerShell 5.1 且不安装 git 时，跳过本节，直接运行 `& $deployScript -Light`，脚本会下载离线包并写 5.1 专属 profile。

```powershell
Confirm-GitCommand         # 查 git，没有就装
git clone https://github.com/xuchaoxin1375/scripts C:/repos/scripts
# 国内先定镜像：Get-SelectedMirror（gitee/github 按需）；hosts 拉胯用 Update-GithubHosts
```

目录建议固定 `C:/repos/scripts`（profile/conda 缓存里的路径写的是这个，换地方要同步修改）。

- Windows 手动克隆前先关闭 `core.autocrlf`（`git config --global core.autocrlf false`），否则 `.sh` 的换行会被改写为 CRLF，在 git-bash 中执行失败；已在开启状态下克隆的仓库，可用 `Convert-CRLF` 批量改回 LF。
- 克隆参数 `--recursive --depth 1 --shallow-submodules` 可减少体积；需要 `ble.sh` 等子模块时保留 `--recursive`。
- 直连不通时经代理克隆：`git -c http.proxy=http://127.0.0.1:7897 -c https.proxy=http://127.0.0.1:7897 clone ...`（端口按本机代理替换）；gitee 克隆可能要求登录。
- `PSModulePath` 用下一节的 `Add-EnvVar` 追加，不要直接 `setx` 覆盖既有值。
- git 读取配置报错（`~/.gitconfig` 损坏）时，备份或移除后重试：`mv ~/.gitconfig ~/.gitconfig.bak`。

## 3. PSModulePath

```powershell
Add-EnvVar -EnvVar PSModulePath -NewValue 'C:\repos\scripts\PS'   # User 级，当前会话立即生效
Get-Module -ListAvailable Test   # 能列出来即成功
```

## 4. profile（只留 `init`）

```powershell
Add-CxxuPsModuleToProfile  # 往 $profile（CurrentUserCurrentHost）写推荐块；或手抄 Config/core_ps_profile.ps1
```

conda 用户：跑 `conda init powershell` 后**重贴缓存块**（它会覆盖，贴法见 `Feature-Guide.md §5`）；
profile 里只保留 `init`；`argc` 由 Init 接管（部署见 [Argc-Completions-Deploy](Argc-Completions-Deploy.md)），`PSCompletions`/`fnm`/`scoop-search` 已迁到组件清单（默认关，装好后用 `Enable-CxxuComponent <Id> -Persist` 启用）。`git-completion` 不需要 profile 配置：装好模块后由 `init` 自动挂载（首次补全才导入）；`carapace` 由 `init` 按 `PsCarapace` 配置注册首个 Tab 懒加载桩，默认关闭，需要时按「可选：carapace」启用。

## 5. 补全栈与第三方 PS 模块

### 分层、来源与能力

`Deploy-CompletionStack` 按“默认层 + 可选层”组织。三个概念互不替代，不要混用：

- **部署层**：默认层不联网、不装仓库外组件；可选层用 `-Include*` 显式选择。
- **依赖级别**：必需、推荐、可选、生成物，由 `Get-CxxuDependencyReport` 判定，清单见 [Feature-Dependencies](Feature-Dependencies.md)。
- **交互层**：Tab 全量索引、ListView 预测、PSFzf、参数位，见 [Feature-Guide](Feature-Guide.md) 的「补全全景速查」。

| 部署层 | 组件 | 级别 | 下载来源 | pwsh 7.5+ | Windows PowerShell 5.1 |
|---|---|---|---|---|---|
| 默认层 | `CxxuPredictor` net9 活件、`CxxuTab`、配置模板 | 生成物/必需 | 仓库内文件同步到 `~/.cxxu/bin`，零网络 | ListView 命令名预测 + Tab 模糊增补 | 仅 Tab 模糊增补（`ps51` 活件） |
| 可选层 `-IncludeArgc` | argc-completions 仓库、`argc.exe`、`yq.exe` | 推荐 | `scripts-deps` 固定版本 → 上游 GitHub（同样套镜像前缀） | Tab 参数补全 + 首参数位静态 flag | Tab 参数补全，无自动 flag 提示 |
| 可选层 `-IncludeFuzzy` | `PSFzf`、`fzf`、`zoxide` | 推荐/可选 | `PSFzf` 走 PSGallery；`fzf`/`zoxide` 走 scoop → winget/brew → `scripts-deps` → 上游 | `Ctrl+T`/`Ctrl+R`、`z`；检测到代理时不走包管理器 | 同左 |
| 可选层 `-IncludePredictor` | `CompletionPredictor` | 推荐 | PSGallery | 参数/路径内联预测 | 以模块自身要求为准 |
| 可选层 `-IncludePSCompletions` | `PSCompletions` | 可选 | PSGallery | Tab 参数补全（装后 `Enable-CxxuComponent PSCompletions -Persist`） | 同左 |
| 可选层 `-IncludeGitCompletion` | `git-completion` | 推荐 | PSGallery | `git`/`gitk` 的 Tab 补全（分支、提交、按状态过滤的文件；首次补全才导入模块） | 可用；模块须在 5.1 可见的目录中（默认安装位置与 7 不同），选项补全受 5.1 引擎限制，见 [Feature-Guide](Feature-Guide.md) 的「Windows PowerShell 5.1 兼容」 |

- 二进制优先取 [`scripts-deps`](https://github.com/xuchaoxin1375/scripts-deps) 的固定版本，地址失效自动回退上游；`-NoMirror` 跳过转存仓库，`$env:PsDepsMirror` 可整体换前缀。版本钉子维护见 [PS/Deploy/readme.md](../Deploy/readme.md) 的转存章节。
- 表内组件装好后是否默认加载由组件清单决定；默认关闭的（如 `PSCompletions`、`carapace`）或曾手动停用的，再用 `Enable-CxxuComponent <Id> -Persist` 启用。`Get-CxxuComponent -Id <Id>` 会同时给出 `Install` 与 `Enable`，`Test-CxxuComponent` 的依赖警告也会带安装与启用命令。
- PSGallery 三件套由 PowerShellGet 安装，代理继承规则与 GitHub 直链不同；5.1 下环境变量可能不生效，网络受限时优先在 pwsh 7 执行，或先配系统代理。
- `git-completion` 的用户模块目录按宿主版本区分：`Install-Module git-completion -Scope CurrentUser` 在 pwsh 7 写入 `~\Documents\PowerShell\Modules`，在 5.1 写入 `~\Documents\WindowsPowerShell\Modules`。5.1 的 `PSModulePath` 默认不含 7 的用户目录，只在 7 上装过时，5.1 的 `init` 会判定模块缺失并跳过，`git`/`gitk` 回落到 argc 或原生补全；从 pwsh 7 启动的子进程继承 7 的 `PSModulePath` 时例外，但那条路径同时带模块顺序问题，不宜依赖。需要 5.1 也启用时，在 5.1 中执行 `Install-Module git-completion -Scope CurrentUser -Force`，或装入两个版本都扫描的 `Program Files\WindowsPowerShell\Modules`（需管理员权限）。5.1 下 `Deploy` 模块不可用，`Deploy-CompletionStack -IncludeGitCompletion` 只能从 pwsh 7 执行。装好后重开终端，再用 `Get-GitCompletionSource` 确认当前归属。
- `carapace-bin` 不纳入上述部署层；需要跨 shell 的外部 CLI 补全时，用下面的 `Deploy-Carapace` 安装，再按「可选：carapace」启用。

### 只启用补全（仓库、`PSModulePath`、profile 已就绪）

```powershell
Deploy-CompletionStack -WhatIf   # 空跑：看会同步什么
Deploy-CompletionStack           # 默认层：仅仓库内 CxxuCommand + CxxuTab，无网络、无仓库外依赖
# 重开终端；profile 的 init 按默认开关加载
```

- 默认层只同步 net9 predictor 与 5.1 Tab 两套活件，并补建用户配置模板；Tab 补全默认开启（`$env:PsTab` 未显式关闭时首个 Tab 自动加载）。
- 可选层按需追加（默认不装，避免新机拉一堆仓库外依赖）：

```powershell
Deploy-CompletionStack -IncludeArgc            # argc-completions 仓库 + argc.exe/yq.exe（并发下载）
Deploy-CompletionStack -IncludeFuzzy           # PSFzf 模块 + fzf/zoxide 二进制
Deploy-CompletionStack -IncludePredictor       # CompletionPredictor 模块
Deploy-CompletionStack -IncludePSCompletions   # PSCompletions 模块
Deploy-CompletionStack -IncludeGitCompletion   # git-completion 模块（git/gitk Tab 补全，init 自动挂载）
Deploy-CompletionStack -All                    # 以上全部
Deploy-CompletionStack -All -SkipBinaries      # 全部但跳过 fzf/zoxide 二进制
```

- 内联预测要 pwsh 7.5+；Windows PowerShell 5.1 只有 Tab 菜单，命令会自动发布 `ps51` 活件（新机也会顺带准备 net9 活件）。
- 开关默认全开（组件未安装时对应开关不产生实际效果；`PsCarapace` 默认关闭）；单关用 `Disable-PsPlugin Predictor|Tab|Fzf|Zoxide|Argc|GitCompletion|Carapace -Persist`，完整开关与优先级见 `Feature-Guide.md §7`。停用 `GitCompletion`/`Carapace` 后，当前会话已注册的 `git`/`gitk` completer 不会撤销，需重开终端才由剩余来源接管。
- 可选层需要网络。国内下载不稳定时，先 `Set-Proxy On`（或设置 `HTTPS_PROXY`/`HTTP_PROXY`）再执行；下载会自动识别代理，也可用 `-Proxy <地址>` / `-NoProxy` 单次覆盖。`Set-Proxy` 只影响当前会话（默认端口 7897，`-Port` 可改），新终端需重设或持久化 `HTTPS_PROXY`。缺少可选组件只提示，不影响默认层。
- `-IncludeArgc` 的仓库、`argc.exe` 与 `yq.exe` 会并发下载（`-NoParallel` 可串行），且不查 release API；只想单独重装 argc 或指定目录用 `Deploy-ArgcCompletions [-Root <目录>]`。
- 验收：ListView 输 `get-child` 应见 `[CxxuCommand]`；Tab 输 `get-chi` 应含 `Get-ChildItem`。不达预期按 `Feature-Guide.md §9` 的「Tab 补全自查」定位。
- 仓库、模块路径或 profile 还没配好时，先走上面的极简版或 §0~§4。

```powershell
Deploy-CompletionStack -All                       # 核心 + argc + PSFzf/zoxide + CompletionPredictor + PSCompletions
# 手动挡（等价）：
Sync-CxxuPredictor                                  # 默认层：生成/对齐 net9 predictor 与 5.1 Tab 两套活件
Deploy-ArgcCompletions                              # 可选：只装/重装 argc-completions（默认 ~/argc-completions）
Confirm-ModuleInstalled -ModuleName PSFzf -Install  # 可选：Ctrl+T/Ctrl+R
Confirm-ModuleInstalled -ModuleName CompletionPredictor -Install  # 可选：参数/路径预测
# 按需：Terminal-Icons（`$env:PsExtension=True` 才用得上）、PSCompletions（装后 `Enable-CxxuComponent PSCompletions -Persist`）
# 自研 CxxuPredictor 随仓库自带（PS/CxxuPredictor/，零模块安装，随 init 延迟加载）；
# 内联预测要求 pwsh 7.5+（7.6 可直接用；dll 按 net9.0 编译，加载失败再进 PS/CxxuPredictor/src 重编）；
# 5.1 Tab 版在 PS/CxxuPredictor/ps51/（netstandard2.0），由 Sync-CxxuPredictor 一并发布
```

> `argc-completions`（800+ 命令参数补全）不再默认随 `Deploy-CompletionStack` 部署；需要时加 `-IncludeArgc`，或单独运行 `Deploy-ArgcCompletions [-Root <目录>]`。首次部署、更新、开关与 5.1 注意事项见 [Argc-Completions-Deploy](Argc-Completions-Deploy.md)。

### 可选：carapace（由 init 注册懒加载桩）

carapace 是跨 shell 的命令行补全二进制，补外部 CLI 的参数值，不补 PowerShell cmdlet。它和 `argc-completions` 是并列关系，不是替代关系；git 仍建议由 `git-completion` 负责。效果、候选数量与三方对比见 [Feature-Guide](Feature-Guide.md) 的「carapace（可选，非默认）」。

前置条件：已按「只启用补全」完成 `init` 与补全栈；Windows PowerShell 5.1 或 pwsh 7（5.1 的 `-` 开头词、环境变量上限、空参数与编码差异由 `init` 加载时处理，见 [Feature-Guide](Feature-Guide.md) 的「carapace（可选，非默认）」）；`carapace` 位于 PATH。安装渠道三选一：`Deploy-Carapace`（推荐，Windows/macOS/Linux）、官方 GitHub Release 手工下载、包管理器（Windows `scoop`/`spc` bucket，macOS `brew`，Linux 发行版仓库或官方 `.deb`/`.rpm`/`.apk`）。

**推荐：`Deploy-Carapace`**

```powershell
Deploy-Carapace -Enable
# 只安装不启用：
Deploy-Carapace
# 同时接入 bash（Git Bash / Linux / macOS），装完后调用仓库内 bash/carapace/setup.sh：
Deploy-Carapace -Bash
Deploy-Carapace -Bash -BashLogin          # 登录 shell：改写 --login 的目标 rc
# 网络受限或需要可复现版本时，跳过 GitHub API：
Deploy-Carapace -Version 1.8.2 -Proxy http://127.0.0.1:7897
# 关闭 GitHub 加速镜像，直接连官方源：
Deploy-Carapace -NoGithubMirror
# 临时指定镜像，或强制不用 aria2c：
Deploy-Carapace -GithubMirror 'https://gh-proxy.com'
Deploy-Carapace -NoAria2
```

命令会按当前平台与架构下载官方产物（Windows 为 zip，macOS/Linux 为 tar.gz），用同版本 `checksums.txt` 校验 SHA-256，解压 `carapace` 到目标目录并加入 PATH。下载默认优先使用 `aria2c`（`--split` 与 `--max-connection-per-server` 由 `-Aria2Connections` 控制，默认 16，并启用 1M 分片），未找到 `aria2c` 或加 `-NoAria2` 时回退 `Invoke-WebRequest`。每次下载都会打印原始链接、实际使用的链接、来源（原始地址或 GitHub 加速镜像）以及实际执行命令；代理只显示“已启用”，不回显地址。GitHub 加速镜像默认读取 `$env:PsGithubMirror`（未设置时用 `https://gh-proxy.com`），`-NoGithubMirror`（别名 `-NoMirror`）或 `-GithubMirror ''` 直连，`-GithubMirror`（别名 `-Mirror`）`'<前缀>'` 本次指定。默认目录：Windows 为 `~/.cxxu/bin`，其他平台为 `~/.local/bin`；非 Windows 只把目录加入当前会话，新终端需按提示写进 shell 配置。加 `-Enable` 会同时把 `PsCarapace` 写入用户配置并在当前会话加载；不加则只安装并打印启用方式。加 `-Bash` 会在安装后调用 [bash/carapace/setup.sh](../../bash/carapace/setup.sh) 写入 bash 的 rc 标记块：默认写非登录 shell 的 `~/.bashrc`，`-BashLogin` 改写登录 shell 读取的 rc；未找到 `bash` 或 `setup.sh` 时只告警，不中断安装。`-Force` 覆盖重装，`-Version` 固定版本（本地版本更高时默认拒绝降级，确需降级加 `-AllowDowngrade`），`-Destination` 与 `-SkipPath` 用于自定义目录或测试。它不修改 profile，加载由 init 注册首个 Tab 懒加载桩完成，实际注册在首次 Tab。macOS 的官方产物未签名；若系统提示无法验证开发者，优先改用 `brew install carapace`，或在确认来源后按系统设置放行。

**手工渠道一：官方 GitHub Release**

1. 打开 `https://github.com/carapace-sh/carapace-bin/releases`，按平台下载：Windows 用 `carapace-bin_<版本>_windows_<架构>.zip`，macOS 用 `carapace-bin_<版本>_darwin_<架构>.tar.gz`，Linux 用 `carapace-bin_<版本>_linux_<架构>.tar.gz`（`<架构>` 为 `amd64` 或 `arm64`），并下载同版本的 `carapace-bin_<版本>_checksums.txt`。
2. 校验：Windows 用 `(Get-FileHash <文件> -Algorithm SHA256).Hash`，macOS/Linux 用 `shasum -a 256 <文件>`；与 `checksums.txt` 中对应文件名行比对，不一致时停止并重新下载。
3. 解压出 `carapace`（Windows 为 `carapace.exe`），放到 PATH 中的固定目录（例如 Windows `$env:LOCALAPPDATA\Programs\carapace`，Unix `~/.local/bin`）；macOS/Linux 需要 `chmod +x carapace`。
4. 确认 `Get-Command carapace` 与 `carapace --version`。

手工安装的升级与卸载也需手工完成：替换二进制后重开终端，PowerShell 侧由 `init` 重新生成脚本，bash 侧重新打开对应终端或 `source` 已接入的 rc；不再使用时删除该目录并从 PATH 移除。

**手工渠道二：包管理器（可选）**

```powershell
scoop install carapace-bin        # Windows，需先添加 spc bucket
```

```bash
brew install carapace             # macOS
```

Linux 优先用发行版仓库；没有时从官方 Release 安装 `.deb`、`.rpm` 或 `.apk`。包管理器版本可能滞后于上游，需要固定或最新版本时改用 `Deploy-Carapace -Version`。

**Git Bash / MSYS 与 Linux/macOS bash（可选，与 PowerShell 独立）**

Git Bash 使用同一个 `carapace.exe`，Linux/macOS 使用各自平台的二进制；接入由 bash 自己完成，不经过 `init` 或 `PsCarapace`。启用 PowerShell 组件不会自动改变 bash，反之亦然。仓库提供一键写入/卸载 rc 标记块的脚本；把 `/path/to/scripts` 换成实际克隆目录：

```sh
# 非登录 shell：写 ~/.bashrc
bash /path/to/scripts/bash/carapace/setup.sh --dry-run
bash /path/to/scripts/bash/carapace/setup.sh

# 登录 shell（macOS Terminal、Git Bash 常见）：写 ~/.bash_profile、~/.bash_login 或 ~/.profile
bash /path/to/scripts/bash/carapace/setup.sh --dry-run --login
bash /path/to/scripts/bash/carapace/setup.sh --login
```

如果二进制也还没装，可在 PowerShell 里用一条命令覆盖两边：`Deploy-Carapace -Bash`（登录 shell 用 `Deploy-Carapace -Bash -BashLogin`）。它内部调用同一个 `setup.sh`，写入内容与上面手工执行一致；重复执行只刷新同一个标记块。在 Git Bash 内也可以直接 `bash setup.sh --install`（官方 Release + SHA-256，Windows 下载 windows zip），再按需用 `--install-deps` 补齐依赖。bash 侧修改 rc 前仍建议先 `bash setup.sh --dry-run` 确认目标文件。

macOS 自带 bash 3.2 会被 carapace 拒绝，需要 `brew install bash` 并切换登录 shell；macOS 默认 zsh 不在该接入范围。平台差异、手工片段、PATH 修正原因、与 argc-completions 的共存、验收与未验证项见 [bash/carapace/README.md](../../bash/carapace/README.md)。多个候选时按两次 `<Tab>` 显示列表；`gh` 等外部命令未安装时，静态子命令仍可补全，需要仓库或登录上下文的动态候选才依赖命令本身。先在 bash 中确认 `command -v carapace` 有输出；没有则把安装目录（Git Bash 常见为 `~/.cxxu/bin` 或 `/c/scoop/shims`，Linux/macOS 常见为 `~/.local/bin`）加入 PATH。

**启用（不修改 profile）**

```powershell
Enable-CxxuComponent Carapace -Persist        # 启用；下次启动注册懒加载桩，首个 Tab 加载
Enable-CxxuComponent Carapace -Persist -Now   # 或立即加载（当前会话）
Set-GitCompletionSource Carapace -Persist     # 让 carapace 接管 git/gitk
```

- `PsCarapace=True` 时 init 只计算排除项并注册首个 Tab 懒加载桩，启动阶段不执行 carapace 的注册脚本；默认关闭，未启用时没有这项开销。pwsh 7 首次 Tab 一次性多花约 0.2–0.3 秒；5.1 约 0.4–0.6 秒（名称列表缓存命中，冷缓存约 1 秒；生成并执行注册脚本），之后约 0.1–0.4 秒。
- `PsGitCompletionSource` 决定 git/gitk 归属：`Auto`、`GitCompletion`、`Argc` 时 init 把 `git,gitk` 并入 `CARAPACE_EXCLUDES`；`Carapace` 时不排除，并让 argc 让路。`Argc` 不推荐用于 git：argc 上游生成的 git 补全缺 `--cached`、`--staged` 等选项；`Auto` 的顺序为 `GitCompletion` → `Carapace` → `Argc`，`Argc` 仅作兜底。切换到前三种来源不会关闭 carapace 本身，需要停止加载时另执行 `Disable-PsPlugin Carapace`（加 `-Persist` 长期生效）；已加载的 completer 按 `PsCarapace` 门控立即返回空，`git`/`gitk` 当场回落：`Carapace` 来源优先交给 `git-completion`（模块已安装且组件未关闭），否则用 `Argc`；`GitCompletion` 来源直接重新注册模块。
- 与 argc 同时启用时要注意注册顺序：两者都在首个 Tab 注册，Tab 桩先加载 carapace、再注册 argc，同名 Native completer 后注册者 argc 生效，因此非 git/gitk 的重叠命令会由 argc 接管。需要 carapace 负责这些外部 CLI 时，关闭 argc（`Disable-PsPlugin Argc`，加 `-Persist` 长期生效）；关闭会立即重新注册 carapace，当前会话即接管，不必重开终端。bash 侧的顺序相反（argc 前、carapace 后），见 [bash/carapace README](../../bash/carapace/README.md)。
- 慢命令排除项写配置键 `PsCarapaceExcludes`（逗号分隔，如 `winget,uv`）；init 会把它与 git/gitk 的规则合并。未设置该键时沿用已有的 `CARAPACE_EXCLUDES`，避免覆盖旧配置。
- 旧版 profile 中的手动 carapace 片段需要删除，否则会与懒加载桩重复注册。也不要执行 carapace 文档中的 `Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete`，避免覆盖本仓库的 Tab 桩。
- 版本可以不追新，但生成脚本随版本变化：懒加载或手动加载时，pwsh 7.6 及更早版本按原文匹配空结果补丁，5.1 另匹配环境变量截断、空参数、编码与 ANSI 四处补丁；匹配不到时只告警，不中断启动。
- 验收：重开终端后先按一次真实 `Tab` 触发懒加载（或 `Enable-CxxuComponent Carapace -Now`），再检查 `Get-Command carapace`、`carapace --version`、`carapace --list`（数量随版本变化，不写死）、`TabExpansion2 'scoop install ' 14` 能返回包名候选，`TabExpansion2 'gh pr ' 6` 能返回子命令。直接调用 `TabExpansion2` 不会触发 Tab 懒加载。5.1 下按真实 `Tab` 复验 `git checkout <Tab>`、`git status --sh<Tab>`，并确认菜单中文描述与输入行无零宽字符残留。
- 不需要时执行 `Disable-PsPlugin Carapace`（加 `-Persist` 长期生效）：当前会话立即停止返回候选，argc 已启用时重叠命令当场交回 argc；包管理器渠道按对应命令卸载（`scoop uninstall carapace-bin`、`brew uninstall carapace`），`Deploy-Carapace` 与手工渠道删除二进制（默认 Windows 为 `~/.cxxu/bin/carapace.exe`，其他平台为 `~/.local/bin/carapace`）并从 PATH 移除。bash 侧用 `bash /path/to/scripts/bash/carapace/setup.sh --disable`（登录 shell 加 `--login`）移除 rc 片段，与 PowerShell 侧互不影响；重复执行 `Deploy-Carapace -Bash` 只刷新同一个标记块。慢命令（`winget install`、`uv add`）会阻塞 Tab，按需写入 `PsCarapaceExcludes`。
- `Deploy-CompletionStack -All` 不包含 carapace，也没有 `-IncludeCarapace` 开关；需要时用 `Deploy-Carapace -Enable` 一步安装并启用，或先 `Deploy-Carapace` 再 `Enable-CxxuComponent Carapace -Persist -Now`。

#### 状态检查

carapace 的状态分四层；只看 `Get-Command` 只能确认二进制存在，不能确认组件启用或懒加载桩是否已注册。

| 层 | 正常表现 |
| --- | --- |
| 二进制 | `Get-Command carapace` 返回路径，`carapace --version` 返回版本 |
| 安装与启用 | 依赖报告显示 `已安装`，组件 `Enabled=True`，配置 `PsCarapace=True` |
| 运行态 | `$env:PsCarapace=True`；`CARAPACE_EXCLUDES` 与 git 来源一致；`PsCarapaceGit` 只在 carapace 接管 git 时为 `True`；`$global:PsCarapacePending=True` 表示等待首次 Tab，`$global:PsCarapaceLoaded=True` 表示已加载 |
| 实际补全 | 首次 Tab 后，`TabExpansion2` 对 `gh`、`docker` 等命令返回子命令或参数候选 |

```powershell
# 二进制
Get-Command carapace
carapace --version

# 安装与启用
Get-CxxuDependencyReport -Feature '补全：外部 CLI 参数（carapace）' -Full
Get-CxxuComponent Carapace | Format-List Id, Enabled, Source, Default, Lazy, Init, InitNow
Get-CxxuConfig | Where-Object Key -eq 'PsCarapace' | Format-List Key, Value, Source
doctor -Feature Carapace

# 运行态
$env:PsCarapace
$env:CARAPACE_EXCLUDES
$global:PsCarapaceGit
$global:PsCarapacePending
$global:PsCarapaceLoaded

# git/gitk 补全归属（配置值、解析值、已注册来源与回落原因）
Get-GitCompletionSource | Format-List

# 候选清单（安装、版本、启用、当前生效与安装命令）
Get-GitCompletionSource -List | Format-Table -AutoSize

# 实际补全（先按一次真实 Tab；或先执行 Enable-CxxuComponent Carapace -Now）
(TabExpansion2 'gh pr ' 6).CompletionMatches | Select-Object -First 5 -ExpandProperty CompletionText
(TabExpansion2 'docker --con' 12).CompletionMatches | Select-Object -First 5 -ExpandProperty CompletionText
```

- `PsCarapace=True` 且 `Get-Command carapace` 有输出，才说明 `init` 注册了首个 Tab 懒加载桩；只有二进制没有开关时，`init` 不会注册 completer。`Pending=True` 是正常状态，按一次 Tab 后变为 `Loaded=True`。
- `PsCarapaceGit` 为 `False`（旧会话可能为空）不是错误：`Auto` 且装有 `git-completion` 时 git/gitk 归 git-completion，carapace 只负责其他命令。把 `PsGitCompletionSource` 设为 `Carapace` 后它才变为 `True`，同时 `CARAPACE_EXCLUDES` 不再包含 `git,gitk`。
- 因此 `git diff --st<Tab>` 默认不会出现 carapace 菜单：`CARAPACE_EXCLUDES` 含 `git,gitk`，候选来自 `git-completion`。需要 carapace 接管 git 时执行 `Set-GitCompletionSource Carapace -Persist`，当前会话即会加载并注册 carapace；之后 `git diff --st<Tab>` 出现 carapace 的 `--staged`、`--stat` 等候选。
- `doctor -Feature Carapace` 是较短的汇总入口，显示 `开关 PsCarapace`、依赖与就绪结论；需要核对 git 补全归属时用 `Get-GitCompletionSource`（配置值、解析值、已注册来源与回落原因），其余开关值仍看 `Get-CxxuConfig`。它不执行交互式 Tab；先用真实 Tab 或 `Enable-CxxuComponent Carapace -Now` 触发加载，再用 `TabExpansion2` 检查候选。
- `TabExpansion2` 没有候选时，先看 `$env:PsCarapace`、`Get-Command carapace` 与 `$global:PsCarapaceLoaded`；两者都开启时，Tab 桩先加载 carapace、再注册 argc，argc 的同名 completer 后注册生效。

## 6. scoop 二进制

```powershell
Deploy-ScoopByGithubMirrors   # 国内先换源；或 Deploy-ScoopByGitee
Install-BasicSoftwares        # 基础包
Deploy-ScoopApps              # 应用包（fzf/zoxide/fnm/oh-my-posh 按需在里面）
```

> `fzf`/`zoxide` 也可由 `Deploy-CompletionStack -IncludeFuzzy` 安装：优先 scoop，其次 winget（Windows）或 brew（macOS），最后回退直接下载到 `~/.cxxu/bin`（自动加入用户 PATH）。直接下载优先取 `scripts-deps` 转存仓库的固定版本，失败再回上游 release；scoop 下载不稳定时可走这条。

## 7. python/conda

```powershell
Deploy-Python
Deploy-MiniforgeConfig
Deploy-PipConfig
Deploy-UvConfig
```

## 8. 首次 `init`（缓存自建）

```powershell
init                 # Data.json/OS 版本 env/conf 预编译自动生成
init -Timing         # 分步耗时，定位慢项（`Register-PsUxLazyLoad` 18ms 左右正常）
Test-PromptDelay     # prompt 延迟
```

conda 缓存（`~/.conda_hook_cache.ps1`）与 zoxide 缓存（`~/.zoxide_init_cache.ps1`）都是
“二进制更新才重建”，平时零开销；新开终端等一拍，`Ctrl+R` / `z` 应可用
（`Register-PsUxLazyLoad -Now` 可强制立即装；开关 `$env:PsFzf`/`$env:PsZoxide`）。

补全验收：ListView 输 `get-child` 应出现 `[CxxuCommand]` 的 `Get-ChildItem`；`Tab` 输 `get-chi` 应含 `Get-ChildItem`（`CxxuTab` 默认开，首个 Tab 才加载模块并读命令表缓存，约 0.1~0.4s，之后毫秒级）。5.1 同样按 `get-chi<Tab>` 验收。不达预期按 [Feature-Guide](Feature-Guide.md) §9 的「Tab 补全自查」定位。

## 9. WT 与开机任务（按需）

- 终端配置参考 `Config/wtConf.json`（线上值可能更新过，仅供参考）。
- `Deploy-WtSettings` 把 WT 的 `settings.json` 建成指向 `Config/wtConf.json` 的符号链接；
  运行中的 WT 不保证感知目标文件更新，改完配置要完全退出并重启 WT，否则新 tab 仍按旧
  profile 与旧命令启动（典型表现：配置已改成 `pwsh`，新 tab 却还带 `-c p`，`init` 跑两次）。
- `Deploy-WtSettings` / `Deploy-VsCodeSettings_depends` 写配置；`Deploy-GitConfig` 写 gitconfig。
- 开机任务按需：`Start-StartupTasks`（拉仓库/起软件/报时+IP 双守护进程，见 `Feature-Guide.md §4`）。

## 10. 多设备差异点（每台都要看一眼）

- `PwshVar/confs/VarSet1.conf` 的 `$PC*` 主机名：新机器加自己的，不认识的别删。
- 功能开关：`~/.cxxu/config.psd1`（仓库外，本机生效；`New-CxxuConfigTemplate` 生成 SchemaVersion=2 模板，`Deploy-CompletionStack` 收尾自动补建；`Enable/Disable-CxxuComponent -Persist` 或 `Enable/Disable-PsPlugin -Persist` 管理；`Get-CxxuComponent` 看分组状态，`Get-CxxuConfig` 看平坦键；优先级环境变量 > 配置文件 > 默认值）。组件默认值与选项在仓库 `PS/Init/components.psd1`，Settings 默认值在 `PS/Init/config.defaults.psd1`；`Reset-CxxuConfig` 按两者重写用户配置，各设备拉同一仓库后执行一次即可统一到同一默认偏好（被用户级/机器级环境变量覆盖的项会列出，需先清除对应环境变量）。`-Persist` 写入前会备份旧文件，并按 v2 规范文本重写，手工注释可能被规范化。
- conda 路径：profile 缓存块里的 `$condaExe`（scoop 版在 `C:\scoop\apps\miniforge\...`，改安装位置要同步）。
- 镜像/代理：`Get-SelectedMirror`、`Update-GithubHosts`、`Deploy-ScoopApps` 按当地网络选。
- `Test-PsEnvReadiness` 收尾再跑一遍，必备全绿。默认只做本地对比（零网络）；
  想看远端有没有更新加 `-CheckRemote`（`ls-remote` 只读问远端，不动本地），表尾“建议”行给下一步：
  有更新 → `Update-ReposesConfiged`（见 §13）；已是最新 + 活件一致 → 无事可做。

## 11. 回滚

- profile 改前先备份（`Copy-Item $profile "$profile.bak"`）；`$env:PsShowProgress='False'` 可关进度条。
- 环境变量改错：注册表 `HKCU\Environment` 手工改，或对应 `Remove-EnvVar`/`Set-EnvVar`。

## 12. GitHub 加速与中央变量（国内网络决策）

- **决策**：gitee 对远程脚本执行（`irm|iex`）误报拦截、一键部署常被拦，不再作为默认源；
  改走 github + 加速前缀；部署链与远程脚本不以 gitee 为默认源。仓库更新按名单分流：
  `$CommonRepos` 走 GitHub，其余仓库走 gitee（见 §13）。
- **中央变量 `$env:PsGithubMirror`**：全仓库统一从它拿前缀。喜欢哪个镜像就持久化哪个：
  `Add-EnvVar -EnvVar PsGithubMirror -NewValue 'https://gh-proxy.com'`（以你实测最快的为准，
  `Get-AvailableGithubMirrors` 可测速；5.1 下同样并发探测，不再退化为串行）；不设则走默认 `gh-proxy.com`，
  需要自动挑选时由 `Get-GithubMirrorPrefix`（部署链）调用 `Get-SelectedMirror -Silent` 静默测速并缓存一次会话；
  `Update-ReposesConfiged` 为保证更新可复现，固定使用默认值或 `-GithubMirror`，不做测速。
- **一键部署的镜像**：`Deploy-CxxuPsModules -GithubMirror 'https://gh-proxy.com'` 显式指定，
  同一前缀用于 git clone、raw 脚本与离线包下载；克隆失败会自动回退离线包，直连失败不再让部署中断。
- **统一出口**：模块内拼 raw 地址一律 `Get-RepoRawUrl -Path 'PS/...'`（自动套前缀），
  别手拼；独立脚本（`Deploy-*.ps1`，模块还没加载）内联同策略三行（见 `Deploy-GitForWindows.ps1`）。

## 13. 更新到新版本

> 设计原理见 `Live-Versions.md`（并排版本 + 指针）。前提：`git pull` 只写仓库目录，纯文本**永远不锁**随便拉；dll 活件在仓库外（`~/.cxxu/bin`），仓库版从不被加载——所以 pull 也永不撞锁。剩下唯一规矩： dll 代码随进程，重开终端才换新。

```powershell
Update-ReposesConfiged        # 批量更新：拉取后若 scripts 含 dll 变更，自动同步活件并提示重开
Sync-CxxuPredictor            # 单点操作（首次安装生成/手动修复/本地重编后分发；同时发布 net9 predictor 与 5.1 Tab；日常更新不需要执行）
```

- 入口 loader 只静默装载（旧版照常使用，无警告）：版本检查使用 `Test-PsEnvReadiness` 备注列。活件并排版本存放（只新增版本目录，从不覆盖），同步不受锁限制，任何会话都可执行。
- 源域名与镜像：`Update-ReposesConfiged` 默认按名单选源——`$CommonRepos` 内的仓库走 GitHub（固定默认经 `https://gh-proxy.com` 加速），其余仓库（含 `$CxxuRepos`）走 gitee；`-RepoSource github|gitee` 本次强制统一源，`$PrivateRepos` 名单内仓库始终按 gitee 处理。镜像不做会话测速；未显式传参时读 `$env:PsGithubMirror`，该变量为空时仍用默认值。`-GithubMirror '<前缀>'` 临时换镜像，`-NoMirror` 或 `-GithubMirror ''` 直连。代理默认依次读 `HTTPS_PROXY`、`HTTP_PROXY`、`ALL_PROXY`（兼容小写形式），也可用 `-Proxy '<地址>'` 指定、用 `-NoProxy` 忽略环境变量。命令会把指向 `xuchaoxin1375/<仓库>` 的 http(s) `origin` 改为名单对应主机，使后续拉取沿用本次选择；GitHub 源的推送地址设为直连 GitHub（保留 gitee 等其他推送地址），`Push-ReposesConfiged` 不受影响；SSH 与自定义远端不改写。gitee 源在凭据缺失时快速失败，不会停在交互式输入。
- 更新范围：默认处理 `$CommonRepos`，本机在 `CxxuComputers` 名单内时追加 `$CxxuRepos`；`-RepoDirs 'blogs','scripts'` 只处理列出的仓库。`-Force` 先执行 `fetch`，再执行 `reset --hard origin/<当前分支>`，会丢弃该仓库已跟踪文件的本地未提交改动；未跟踪文件不受影响。
- 拉取含 dll 变更：活件已同步完成，**重新打开终端** → 执行 `init` 即可；只有 psm1 变更：执行 `ipmox` 即可，会话变量不丢失。
- 自编译活件（`local-build.txt` 标记为 local）：`Update-ReposesConfiged` 保持活件不动并提示，不会换回仓库源；若同时有 5.1 Tab 活件更新，更新流程会用 `Sync-CxxuPredictor -Ps51Only` 只同步那一套。想跟进仓库源时，重编后重新 `Sync-CxxuPredictor -DllPath`（net9）或 `-Ps51DllPath`（5.1 Tab），或裸 `Sync-CxxuPredictor` 切回（流程见 `Live-Versions.md §10`）。
- 守护进程（报时/IP）用不上 predictor：`$env:PsPredictor='False'` 门已置（`Start-StartupBgProcesses` 继承 + 两个守护函数按 `-Command` 自断），它们永不加载/锁定 dll， `-Force` 关它们无压力（无状态，重起即回）；交互会话手动调守护函数不受影响。
- 顺序：更新函数（活件已同步）→（dll 变更时重开终端/`-Force`）→ `init` → `Test-PsEnvReadiness` 收尾。

## 14. 时效性资源清单（会过期的东西都在这里）

> 这些资源控制权在外部（镜像站/第三方仓库/上游发版），或需要人工跟进版本，会随时间失效；
> 检查列是只读命令，更新列是人工动作。自动检查不是必需，先保证只读命令可用。

| 资源 | 位置 | 现状快照 | 检查（只读） | 更新动作 | 频率 |
|---|---|---|---|---|---|
| GH 镜像站 13 个 | `TestLinks.psm1` 头部 | 全可用（本机 raw 实测） | `Get-AvailableGithubMirrors` | 删失效条目 | 季度 / 部署失败时 |
| 默认镜像 `gh-proxy.com` | 各独立脚本内联 + `$env:PsGithubMirror` | OK（约 500ms） | `Test-MirrorAvailability -Url <镜像>` | 挑最快的 `Add-EnvVar PsGithubMirror` 持久化 | 同上 |
| Git for Windows 默认版 | `Deploy-GitForWindows.ps1` 的 `$url` 回退值（`-url`/`-PackagePath` 可覆盖） | `v2.55.0.windows.5`（api 实测 latest） | 查 `api.github.com/repos/git-for-windows/git/releases/latest` 的 tag | 改默认值（api 失败自动回退，不急） | 有新版时 |
| pwsh Ubuntu deb 版 | `Install-PwshUbuntu.ps1` 头部 `$pwsh_version`（一处，环境变量可覆盖） | `v7.6.6`（LTS 现行） | 查 PowerShell releases | 改头变量即可 | LTS 更新时 |
| pwsh 最新版查询（两份） | `Deploy-Pwsh7Portable.ps1` 的 `Get-LatestPowerShellDownloadUrl` / `PsEnv.psm1` 对应逻辑（均带超时；独立脚本须自包含故保留两份，改逻辑两边同步） | `v7.6.6` | 同上 | 勿两头各改各的 | 按需 |
| WT 安装包查询 | `TerminalTools.psm1:16` | 超时已加；旧死代码/自递归已修（2026-09-24） | 手动跑 `Get-LatestWindowsTerminalLink` | — | 按需 |
| `scoop.201704.xyz`（第三方域） | `Scoop.psm1:166,173` / `Deploy-GitForWindows.ps1:117` | 存活未变，但说死就死 | `Invoke-WebRequest -Method Head` 探活 | 切官方 `get.scoop.sh` | 失败时 |
| gitee `scoop-installer` forks | `Scoop.psm1`（buckets/gitee 方案） | 第三方控制，同步可能滞后 | `scoop bucket list` 看 Updated 列 | 切回官方源 + 镜像前缀 | 失败时 |
| `duzyn/scoop-cn` raw 路径 | `DevEnv.psm1:16-30` | 第三方仓库，改名/删文件即坏 | 跑一次相关 Deploy 命令 | 跟随上游改路径 | 失败时 |
| 自有 `spc` fork 同步 | `Scoop.psm1:202`（`gitee.com/xuchaoxin1375/spc`） | 自有可控 | 看 gitee 仓库同步时间 | 重跑同步 action | 半年 |
| gitcode 归档包 | `Get-CxxuPsModulePackage` 的候选源列表 | `HEAD 200` 存活（2026-09-24） | `HEAD` 探活 | 删/换 | 失败时 |
| hosts 数据（天然过期） | `Update-GithubHosts`（`raw.hellogithub.com` + GitHub520 回退） | IP 常变 | 看 hosts 尾 `# Update time` 距今 | `Update-GithubHosts`；已装定时任务则自动 | 自动（每小时+开机） |
| pip/conda 高校源 | `DevEnv.psm1` / `ConstantString.conf` / `Tools.psm1:381` | 稳定，偶改路径 | 安装失败时对照 `help.mirrorz.org` | 改 URL | 失败时 |
| `Get-SpeedUpUri` 未定义 | `PsEnv.psm1:238` / `TerminalTools.psm1:9,42` | 已修 | 跑 `Update-PowerShell` 即验 | — | — |
| net9.0 / pwsh 版本门 | `CxxuPredictor.csproj` | 7.6 可直接用；pwsh 8 发布后再复核 | — | 加载失败时重编 dll（见 `Live-Versions.md §10`） | 慢变量 |
| netstandard2.0 / 5.1 Tab | `CxxuPredictor.csproj` / `ps51` 活件 | 仅 Windows；5.1 固定在 .NET Framework 4.8 | 5.1 按 Tab 有模糊候选 | `Sync-CxxuPredictor` 重新发布 | 慢变量 |
| 文档外链（博客/商店/聚合页） | `readme.md` / `Deploy-Guide.md` | 腐烂风险，低优 | 抽查 | 换链 | 年 |
| PSGallery 第三方模块 | `Deploy-CompletionStack -Include*` | 浮动最新，不钉版 | `Test-PsEnvReadiness` | `Deploy-CompletionStack -IncludeFuzzy/-IncludePredictor/-IncludePSCompletions/-IncludeGitCompletion` | 按需 |
| 转存仓库 `scripts-deps` | `PS/Deploy/Sync-GithubDepsMirror.ps1` 的资产表 + `DevEnv.psm1` 里的 `Get-CxxuDepsMirrorAsset` | 已转存 argc、yq、fzf、zoxide 与 argc-completions 快照（2026-11-08） | `Sync-GithubDepsMirror.ps1 -WhatIf` | 跑同步脚本，把打印的钉子回填模块 | 上游发版时 |

> 更新流程见 §13（`Update-ReposesConfiged` 批量更新 + 活件同步 + 重开终端）。
