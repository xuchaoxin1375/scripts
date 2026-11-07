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
```

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
`argc` 钩子在 profile 里保持注释（Init 已接管，见 [Argc-Completions-Deploy](Argc-Completions-Deploy.md)）；`fnm` 按需再开（见 `Feature-Guide.md §7`）。

## 5. 补全栈与第三方 PS 模块

```powershell
Deploy-CompletionStack            # 核心 CxxuCommand 同步两套活件 + 可选 PSFzf/CompletionPredictor 与 fzf/zoxide；先 -WhatIf 空跑看动作
Deploy-CompletionStack -IncludePSCompletions   # 再加 PSCompletions（按需）
# 手动挡（等价）：
Sync-CxxuPredictor                                  # 核心：生成/对齐 net9 predictor 与 5.1 Tab 两套活件
Confirm-ModuleInstalled -ModuleName PSFzf -Install  # 可选：Ctrl+T/Ctrl+R
Confirm-ModuleInstalled -ModuleName CompletionPredictor -Install  # 可选：参数/路径预测
# 按需：Terminal-Icons（`$env:PsExtension=True` 才用得上）、PSCompletions（70+ 命令补全，延迟加载）
# 自研 CxxuPredictor 随仓库自带（PS/CxxuPredictor/，零模块安装，随 init 延迟加载）；
# 内联预测要求 pwsh 7.5+（7.6 可直接用；dll 按 net9.0 编译，加载失败再进 PS/CxxuPredictor/src 重编）；
# 5.1 Tab 版在 PS/CxxuPredictor/ps51/（netstandard2.0），由 Sync-CxxuPredictor 一并发布
```

> `argc-completions`（800+ 命令参数补全）不在 `Deploy-CompletionStack` 内：仓库 + `bin\argc.exe`/`bin\yq.exe` 就位后由 `init` 自动接管；首次部署、更新、开关与 5.1 注意事项见 [Argc-Completions-Deploy](Argc-Completions-Deploy.md)。

## 6. scoop 二进制

```powershell
Deploy-ScoopByGithubMirrors   # 国内先换源；或 Deploy-ScoopByGitee
Install-BasicSoftwares        # 基础包
Deploy-ScoopApps              # 应用包（fzf/zoxide/fnm/oh-my-posh 按需在里面）
```

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
init -Timing         # 分步耗时，定位慢项（9 步，`Register-PsUxLazyLoad` 18ms 左右正常）
Test-PromptDelay     # prompt 延迟
```

conda 缓存（`~/.conda_hook_cache.ps1`）与 zoxide 缓存（`~/.zoxide_init_cache.ps1`）都是
“二进制更新才重建”，平时零开销；新开终端等一拍，`Ctrl+R` / `z` 应可用
（`Register-PsUxLazyLoad -Now` 可强制立即装；开关 `$env:PsFzf`/`$env:PsZoxide`）。

补全验收：ListView 输 `get-child` 应出现 `[CxxuCommand]` 的 `Get-ChildItem`；`Tab` 输 `get-chi` 应含 `Get-ChildItem`（`CxxuTab` 默认开，首个 Tab 才加载模块并读命令表缓存，约 0.1~0.4s，之后毫秒级）。5.1 同样按 `get-chi<Tab>` 验收。不达预期按 [Feature-Guide](Feature-Guide.md) §9 的「Tab 补全自查」定位。

## 9. WT 与开机任务（按需）

- 终端配置参考 `Config/wtConf.json`（线上值可能更新过，仅供参考）。
- `Deploy-WtSettings` / `Deploy-VsCodeSettings_depends` 写配置；`Deploy-GitConfig` 写 gitconfig。
- 开机任务按需：`Start-StartupTasks`（拉仓库/起软件/报时+IP 双守护进程，见 `Feature-Guide.md §4`）。

## 10. 多设备差异点（每台都要看一眼）

- `PwshVar/confs/VarSet1.conf` 的 `$PC*` 主机名：新机器加自己的，不认识的别删。
- 功能开关：`~/.cxxu/config.psd1`（仓库外，本机生效；`New-CxxuConfigTemplate` 生成模板，`Deploy-CompletionStack` 收尾自动补建；`Enable/Disable-PsPlugin -Persist` 单键管理；优先级环境变量 > 配置文件 > 默认开）。新机器要差异化开关，复制这个文件比改注册表轻。
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
  改走 github + 加速前缀。`-RepoSource` 默认已全切 `github`（gitee 只留兼容）。
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
- 镜像与代理：`Update-ReposesConfiged` 默认经 `https://gh-proxy.com` 拉取，固定默认值，不做会话测速；未显式传参时读 `$env:PsGithubMirror`，该变量为空时仍用默认值。`-GithubMirror '<前缀>'` 临时换镜像，`-NoMirror` 或 `-GithubMirror ''` 直连。代理默认依次读 `HTTPS_PROXY`、`HTTP_PROXY`、`ALL_PROXY`（兼容小写形式），也可用 `-Proxy '<地址>'` 指定、用 `-NoProxy` 忽略环境变量。命令会把指向 `xuchaoxin1375/<仓库>` 的 http(s) `origin` 改为当前镜像或直连地址，使后续拉取沿用本次选择；镜像只用于下载，推送地址设为直连 GitHub（保留 gitee 等其他推送地址），`Push-ReposesConfiged` 不受影响；SSH 与自定义远端不改写。
- 更新范围：默认处理 `$CommonRepos`，本机在 `CxxuComputers` 名单内时追加 `$CxxuRepos`；`-RepoDirs 'blogs','scripts'` 只处理列出的仓库。`-Force` 先执行 `fetch`，再执行 `reset --hard origin/<当前分支>`，会丢弃该仓库已跟踪文件的本地未提交改动；未跟踪文件不受影响。
- 拉取含 dll 变更：活件已同步完成，**重新打开终端** → 执行 `init` 即可；只有 psm1 变更：执行 `ipmox` 即可，会话变量不丢失。
- 自编译活件（`local-build.txt` 标记为 local）：`Update-ReposesConfiged` 保持活件不动并提示，不会换回仓库源；若同时有 5.1 Tab 活件更新，更新流程会用 `Sync-CxxuPredictor -Ps51Only` 只同步那一套。想跟进仓库源时，重编后重新 `Sync-CxxuPredictor -DllPath`（net9）或 `-Ps51DllPath`（5.1 Tab），或裸 `Sync-CxxuPredictor` 切回（流程见 `Live-Versions.md §10`）。
- 守护进程（报时/IP）用不上 predictor：`$env:PsPredictor='False'` 门已置（`Start-StartupBgProcesses` 继承 + 两个守护函数按 `-Command` 自断），它们永不加载/锁定 dll， `-Force` 关它们无压力（无状态，重起即回）；交互会话手动调守护函数不受影响。
- 顺序：更新函数（活件已同步）→（dll 变更时重开终端/`-Force`）→ `init` → `Test-PsEnvReadiness` 收尾。

## 14. 时效性资源清单（会过期的东西都在这里）

> 这些资源控制权在外部（镜像站/第三方仓库/上游发版），会随时间失效；
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
| PSGallery 第三方模块 | `Deploy-CompletionStack` | 浮动最新，不钉版 | `Test-PsEnvReadiness` | `Deploy-CompletionStack` | 按需 |

> 更新流程见 §13（`Update-ReposesConfiged` 批量更新 + 活件同步 + 重开终端）。
