# 新机部署指南（Deploy Guide）

> 把这套 53 模块组合搬到另一台机器。先跑 `Test-NewMachineReadiness` 看缺口，再按节补。
> 在新机器上还没有模块路径时，先：`Import-Module C:\repos\scripts\PS\Deploy\Deploy.psd1`

## 0. 先查缺口

```powershell
Test-NewMachineReadiness   # 必备/可选/首跑生成物三档表格，缺啥补啥列直接给命令
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

目录建议固定 `C:/repos/scripts`（profile/conda 缓存里的路径写的是这个，换地方要顺手改）。

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
- conda 路径：profile 缓存块里的 `$condaExe`（scoop 版在 `C:\scoop\apps\miniforge\...`，改安装位置要同步）。
- 镜像/代理：`Get-SelectedMirror`、`Update-GithubHosts`、`Deploy-ScoopApps` 按当地网络选。
- `Test-NewMachineReadiness` 收尾再跑一遍，必备全绿。

## 11. 回滚

- profile 改前先备份（`Copy-Item $profile "$profile.bak"`）；`$env:PsShowProgress='False'` 可关进度条。
- 环境变量改错：注册表 `HKCU\Environment` 手工改，或对应 `Remove-EnvVar`/`Set-EnvVar`。
