# 新机部署指南（Deploy Guide）

> 把这套 55 模块组合搬到另一台机器。先跑 `Test-PsEnvReadiness` 看缺口，再按节补。
> 在新机器上还没有模块路径时，先：`Import-Module C:\repos\scripts\PS\Deploy\Deploy.psd1`

> **极简版（只要补全栈，共 2 条命令）**：第 1 条落仓库+环境，第 2 条装补全栈；下面各节是分步详解。
> ```powershell
> irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1' | iex
> # 关掉重开终端（自动 init），再：
> Deploy-CompletionStack
> # 再重开一次，缓存就绪。版本不够 7.5 会警告（自研 predictor 用不上，其它照常）。
> ```

## 0. 先查缺口

```powershell
Test-PsEnvReadiness   # 必备/可选/首跑生成物三档表格，备注列直接给补法/对比结论
```

## 1. pwsh 7

```powershell
Update-PowerShell          # 自带升级；或 winget/scoop 重装
$PSVersionTable.PSVersion  # 确认 Major >= 7（v5 不可用，manifest 会明确报错）
```

## 2. git + 拉仓库

```powershell
Confirm-GitCommand         # 查 git，没有就装
git clone https://github.com/xuchaoxin1375/scripts C:/repos/scripts
# 国内先定镜像：Get-SelectedMirror（gitee/github 按需）；hosts 拉胯用 Update-GithubHosts
```

目录建议固定 `C:/repos/scripts`（profile/conda 缓存里的路径写的是这个，换地方要同步修改）。

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
`argc`/`fnm` 钩子保持注释（`argc` 二进制、`fnm` 按需再开，见 `Feature-Guide.md §7`）。

## 5. 第三方 PS 模块

```powershell
Deploy-CompletionStack            # 一键：PSFzf/CompletionPredictor + fzf/zoxide（有 scoop 则装）+ 版本门；先 -WhatIf 空跑看动作
Deploy-CompletionStack -IncludePSCompletions   # 再加 PSCompletions（按需）
# 手动挡（等价）：
Confirm-ModuleInstalled -ModuleName PSFzf -Install
Confirm-ModuleInstalled -ModuleName CompletionPredictor -Install
# 按需：Terminal-Icons（`$env:PsExtension=True` 才用得上）、PSCompletions（70+ 命令补全，延迟加载）
# 自研 CxxuPredictor 随仓库自带（PS/CxxuPredictor/，零安装，随 init 延迟加载）；
# 要求 pwsh 7.5+（dll 按 net9.0 编译；其它版本进 PS/CxxuPredictor/src 跑 dotnet build -c Release 重编）
```

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
init -Timing         # 分步耗时，定位慢项（8 步，`Register-PsUxLazyLoad` 18ms 左右正常）
Test-PromptDelay     # prompt 延迟
```

conda 缓存（`~/.conda_hook_cache.ps1`）与 zoxide 缓存（`~/.zoxide_init_cache.ps1`）都是
“二进制更新才重建”，平时零开销；新开终端等一拍，`Ctrl+R` / `z` 应可用
（`Register-PsUxLazyLoad -Now` 可强制立即装；开关 `$env:PsFzf`/`$env:PsZoxide`）。

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
  `Get-AvailableGithubMirrors` 可测速）；不设则走默认 `gh-proxy.com`，模块内调用走
  `Get-SelectedMirror -Silent` 静默测速（会话缓存一次）。
- **统一出口**：模块内拼 raw 地址一律 `Get-RepoRawUrl -Path 'PS/...'`（自动套前缀），
  别手拼；独立脚本（`Deploy-*.ps1`，模块还没加载）内联同策略三行（见 `Deploy-GitForWindows.ps1`）。

## 13. 更新到新版本

> 设计原理见 `Live-Versions.md`（并排版本 + 指针）。前提：`git pull` 只写仓库目录，纯文本**永远不锁**随便拉；dll 活件在仓库外（`~/.cxxu/bin`），仓库版从不被加载——所以 pull 也永不撞锁。剩下唯一规矩： dll 代码随进程，重开终端才换新。

```powershell
Update-ReposesConfiged        # 批量更新：拉取后若 scripts 含 dll 变更，自动同步活件并提示重开
Sync-CxxuPredictor            # 单点操作（首次安装生成/手动修复/本地重编后分发；日常更新不需要执行）
```

- 入口 loader 只静默装载（旧版照常使用，无警告）：版本检查使用 `Test-PsEnvReadiness` 备注列。活件并排版本存放（只新增版本目录，从不覆盖），同步不受锁限制，任何会话都可执行。
- 拉取含 dll 变更：活件已同步完成，**重新打开终端** → 执行 `init` 即可；只有 psm1 变更：执行 `ipmox` 即可，会话变量不丢失。
- 守护进程（报时/IP）用不上 predictor：`$env:PsPredictor='False'` 门已置（`Start-StartupBgProcesses` 继承 + 两个守护函数按 `-Command` 自断），它们永不加载/锁定 dll， `-Force` 关它们无压力（无状态，重起即回）；交互会话手动调守护函数不受影响。
- 顺序：更新函数（活件已同步）→（dll 变更时重开终端/`-Force`）→ `init` → `Test-PsEnvReadiness` 收尾。
