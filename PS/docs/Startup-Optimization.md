# Pwsh 启动与初始化速度优化

> 适用：`PS/` 模块集（`$env:PSModulePath` 引用 `C:/repos/scripts/PS`，`$profile` 里只有 `init`）。
> 测量环境：Windows Server 级虚拟机，pwsh 7.5。个人电脑数值不同，但瓶颈排序一致。

## 1. 基线数据

| 场景 | 耗时 | 说明 |
|---|---|---|
| `pwsh -NoProfile -c exit` | ~208ms | 裸启动，优化天花板 |
| conda hook（`profile.ps1`） | ~450~700ms | 每个 shell 都 fork 一次 conda.exe，**是第一大户，比 init 还贵**；已用缓存方案解决（见 §8） |
| `init`（7 步） | +460~770ms | 沙盒多次测量区间 |
| 真实全 profile（conda + init） | ~800~1300ms | 沙盒 1279ms，真机约 800~950ms |
| `prompt` 每次回车 | ~100ms | 主要是 `Get-MemoryUseSummary` 的 CIM 查询（~100ms/次，由 5s 节流摊薄） |
| `Get-Module -ListAvailable Terminal-Icons` | ~78ms | 每次全盘扫描 PSModulePath，不可放热路径 |
| `Get-CimInstance Win32_OperatingSystem` | ~192ms | 同上，必须缓存 |

```powershell
# 复测命令（沙盒重定向下 PSReadLine 会报两行错，不影响结论，真机无此报错）
pwsh -NoProfile -c { Measure-Command { pwsh -NoProfile -c init } }
init -Timing -InformationAction Continue   # 分步耗时报告（默认关闭）
Test-PromptDelay                            # prompt 延迟（默认测 10 次取平均）
```

### 关于 `Loading personal and system profiles took ...ms`

- 这行字是 pwsh 引擎自己打印的，**只有四个级别 profile 文件合计耗时 >500ms（硬编码阈值）才出现**，
  低于就静默。看不到它 = 该实例 profile 不足 500ms，不是“没加载”。
- 嵌套 `pwsh` 是全新进程，`$global:PsInit` 防重复只在同一进程内有效，所以每次都要重跑
  conda + init 全套。与“第几次启动”无关，只和该实例耗时是否过线有关（机器负载、冷热缓存
  会让同一配置在 500ms 线上下横跳，看起来像“有时有、有时无”）。

某次 `init -Timing` 实测（沙盒，顺序即耗时顺序）：

| 步骤 | 时间 |
|---|---|
| Set-PsPrompt（含 core 环境导入） | 177ms |
| Set-PSReadLinesCommon | 103ms（含沙盒报错开销，真机小得多） |
| Set-PSReadLinesAdvanced | 78ms（同上） |
| Confirm-DataJson（首调含 Tools 模块解析） | 65ms |
| Set-ArgumentCompleter | 34ms |
| Set-PsExtension（默认 False，近乎 no-op） | 34ms |
| Confirm-EnvVarOfInfo（稳态命中缓存） | 23ms |

## 2. 本次改动总览

### 2.1 新增模块

| 模块 | 行数 | 职责 | 来源 |
|---|---|---|---|
| `Prompt/Prompt.psm1` | 722 | 提示符渲染与切换：`prompt/promptx` 入口、`Prompt*` 主题、`Write-*` 片段、`Set-PsPrompt`、`dm`、`Test-PromptDelay`、oh-my-posh 相关 | `Pwsh.psm1` + `ArgumentCompletion.psm1` |

### 2.2 函数搬迁（只改归属，不改名不改行为）

| 函数 | 从 | 到 | 理由 |
|---|---|---|---|
| `prompt`、`promptx` | `ArgumentCompletion` | `Prompt` | prompt 入口与补全注册无关 |
| `Set-PsPrompt`、`Set-PsPromptStyle`、`dm`、`Test-PromptDelay`、`Get-PromptScriptBlock`、`PromptFast/Balance/Brilliant*/Short*/Default/Simple`、`Write-UserHostname/Uptime/HostIp/PermissoinLevel/Path/OSVersionInfo/PsEnvMode/PsMode/BatteryAndMemoryUse/Data/Time/ColorsPreivew`、`Get-GitInfo`、`write-GitBasicInfo`、`Set-PoshPrompt`、`Enable-PoshGit` | `Pwsh` | `Prompt` | 全部只服务提示符 |
| `Get-MacOSOperatingSystemInfo`、`ProcessDetail`、`Get-ProcessDetail`、`Get-ProcessMemoryView`、`Get-CommitStatus`、`Show-CommitMemoryBar`、`Show-MemoryBar` | `Pwsh` | `Info` | 系统信息查看 |
| `Get-Size`、`Get-ItemSizeSorted`、`Get-PsIOItemInfo`、`Get-ChildItemNameQuatation`、`Get-NonEmptySubdirectories`、`Remove-EmptyDirectories` | `Pwsh` | `FileSystem` | 文件/目录度量（`FileSystem.psm1` 原来只有 13 行，现在名副其实） |
| `Update-PwshEnv`、`Update-PwshvarsIfNotYet`、`Update-PwshEnvIfNotYet`、`Test-PsEnvMode` | `Pwsh` | `Init` | 初始化编排与环境等级跟踪就该住在一起 |
| `Confirm-DataJson` | `Startup` | `Tools` | 与 `Get-Json/Update-Json` 同模块；init 热路径与 prompt 缓存都依赖它 |
| 镜像站数据源 `$GithubMirrors*` + `Test-LinksLinearly/Parallel`、`Test-MirrorAvailability`、`Get-AvailableGithubMirrors` | `Git` | `Deploy`（并入 `Deploy.psm1`） | 见 2.4 |

效果：`Pwsh.psm1` 3590 行 → 1235 行；`Init.psm1` 380 → 498 行。已用脚本对账：70+ 个原定义零丢失、跨文件零重复（见 §6）。

### 2.3 重复定义清理

| 函数 | 处理 | 说明 |
|---|---|---|
| `Set-PoshPrompt`（`Pwsh` 内两份，参数不同） | 删第二份，留带 `-Poshgit` 的版本 | 同文件重复，后加载的静默覆盖前者 |
| `Get-RecycleBin`、`Clear-RecycleBinDir`（`RecycleBin` 内各两份，完全相同） | 删第二份 | 同文件粘贴重复 |
| `exes_`、`dcs_Idm`（`JumpDirectory` 内各两份） | 删第二份 | 同上（`$Downloads` vs `$downloads` 无实质差异） |
| `Disable-CredentialGuard`（`Basic` vs `Security`，行为不同） | 删 `Basic` 版，留 `Security` 版 | `Basic` 版非管理员时直接 `exit` 退出 shell；且同名跨模块会导致自动加载命中不确定 |
| `Test-Links*` 等 4 函数（`Git` vs `Deploy/TestLinks`，已分叉） | 删 `Git` 版，留 `Deploy` 版 | `TestLinks` 版更新（含可用并行分支）；`Git` 版并行分支被注释 |
| `Add-Extension`（`FileSystem` vs `CommentBasedHelpDocumentExamples` 示例） | 保留，暂不动 | 后者是文档示例模块，调用时注意以 `FileSystem` 为准 |

### 2.4 顺手修掉的三个坑

1. **`Confirm-DataJson` 死循环**（`Tools.psm1:3844`）：`$DataJson` 为空时 `Test-Path/Get-Content/Rename-Item` 全报错，
   又无参自递归 → 无限递归。现改为：空值兜底 `~/Data.json`，`try/catch` 校验失败直接备份重建，**无递归**。
2. **`Set-CommonInit` 调用不存在的 `Start-CoreInit`**（`Init.psm1`）：一调即 `CommandNotFound`。
   已删除该行——`Update-PwshEnv`（变量+别名+prompt）已覆盖其语义。
3. **幽灵模块 `Deploy/TestLinks.psm1`**：目录名 `Deploy` ≠ 文件名 `TestLinks`，PowerShell 自动发现
   只认 `<目录名>.psm1`，所以该文件**从未被加载过**，里面的函数一直靠 `Git` 的副本续命。
   已将其内容并入 `Deploy.psm1` 并删除原文件（`Get-Command Test-LinksLinearly` 现解析到 `Deploy`，已验证）。

## 3. 启动链优化（`Init.psm1:3`）

旧 `init` 把 7 个调用转成字符串，逐行 `Invoke-Expression`，每行再套 `Measure-Command` + `Write-Progress`。
三个问题：`iex` 慢且报错丢定位；`Write-Progress` 渲染是启动链最贵操作之一；正常启动根本不需要逐项计时。

- 改为**直接调用步骤表**（当前会话作用域，与原来 `iex` 效果一致），默认无进度条、无计时。
- 计时改为轻量 `[datetime]::UtcNow` 差值，仅 `-Timing` 或 `-InformationAction Continue`（即 `p -Force` 路径）时收集并打印报告。
- 新增 `init -Timing` 开关，替代原来“想看报告就得忍受慢启动”的两难。

## 4. 热路径去注册表写（`EnvVar.psm1:940`）

`Set-EnvVar/Add-EnvVar` 默认 `Scope=User`：每次调用先全量扫描环境变量（`Update-EnvVarFromSysEnv`），
再写注册表。在 `init`/`Set-PsPrompt` 这种每次启动都跑的路径上纯属浪费。

- 新增 `Set-ProcessEnvVar`：只 `Set-Item Env:\`，进程级生效，不碰注册表。
- `Set-PsPrompt`（`Prompt.psm1:641`）：默认只进程级写入；加 `-Persist` 才同时写注册表。
  之前每次 `Set-PsPrompt -version X` 都全量扫描+写注册表，之后还重复写一次 `$env:PsPrompt`。
- `Confirm-EnvVarOfInfo` 的 `OSCaption/OSFullVersionCode` 等：持久化到注册表后新 shell 继承即命中，
  稳态 23ms，无需再动（不要改成每次强制刷新，那会把 192ms 的 CIM 查询带回启动链）。

## 5. Prompt 延迟优化（`Prompt.psm1`）

- 默认主题已是 `fast`（`Set-PsPrompt` 无参数且无 `$env:PsPrompt` 时），保持。
- `Get-MemoryUseSummary` 的 CIM 查询已有 5s 节流（`Start-ScriptWhenIntervalEnough`），保留——
  实测 `prompt` 100ms 中它占大头，但每 5 秒才触发一次，摊薄后可接受。
- 新增 `Get-BatteryLevelCached`（`Prompt.psm1:314`，30s TTL，含无电池机器的 `$null` 也缓存）：
  `Write-BatteryAndMemoryUse` 改用它。实测连续两次调用 51ms → 0ms。
- `Write-HostIp` 走文件缓存（`DataJson` + 后台 `Update-NetConnectionInfo` 守护进程），不动。
- 如需极致响应：`Set-PsPrompt -version Simple`（纯 `PS>`），或把 `write-GitBasicInfo` 从常用主题摘掉
  （大仓库 `git rev-parse` 是额外开销；当前实现已优化为读 `.git/HEAD` 文件）。

## 6. 验证（全部通过）

```powershell
# 1) 51 个模块逐个强制导入，FAIL_COUNT=0
# 2) 关键命令解析到正确模块：
#    prompt/Set-PsPrompt/*Prompt* -> Prompt；Update-PwshEnv*/Test-PsEnvMode -> Init；
#    Get-ProcessMemoryView -> Info；Get-Size -> FileSystem；Confirm-DataJson -> Tools；
#    Test-Links*/Get-AvailableGithubMirrors -> Deploy；Set-ArgumentCompleter -> ArgumentCompletion
# 3) init 全链 + prompt + 主题切换 + DataJson-null 兜底冒烟通过
pwsh -NoProfile -File <tmp>/verifyAll.ps1
pwsh -NoProfile -File <tmp>/verify3.ps1
```

结构对账另用脚本比对过：`Pwsh` 原 77 个定义在新位置**零丢失、跨文件零重复**。

## 8. profile 层优化（2026-09-20 验收追加）

- `CurrentUserAllHosts/profile.ps1` 的 conda 初始化块每次 fork `conda.exe`（实测 443~697ms），
  已改为**缓存方案**：hook 输出存 `~/.conda_hook_cache.ps1`，仅 `conda.exe` 本体更新（mtime 变新）
  才重建，平时直接点源。实测 573ms → 59ms。注意下次运行 `conda init` 会覆盖该块，届时重新应用。
- `CurrentUserCurrentHost` 里的 argc 生成块目前是**注释状态**，不产生开销；`argc` 二进制也不在
  PATH 上——需要时先装 argc 再解注释，不要直接放开（放开后每次还要扫描 800+ 个补全文件）。
- `Update-NetConnectionInfo` 守护进程里的 `Write-Host $DataJson`（每次启动吐一行裸路径）已删除；
  `Get-IpAddressForPrompt` 内对 `Confirm-DataJson` 返回值的泄漏已用 `Out-Null` 堵住。

## 7. 已知剩余开销与后续 TODO（按性价比排序）

1. **巨型模块首调解析 cost**：`Tools.psm1`（4100+ 行）、`Deploy.psm1`（~3000 行）首次自动加载即全量解析，
   `Confirm-DataJson` 首调 65ms 里大头是这个。后续按需拆分，或补 `.psd1`（`FunctionsToExport` 缩小发现集）。
2. **`Set-PsExtension`**：`$env:PsExtension=True` 时 `Import-Module` 第三方模块（`CompletionPredictor` 等）
   是启动链最大单项（历史数据 300ms+）。默认保持 `False`；启用者自负。
3. **`Set-PSReadLineOption -PredictionSource HistoryAndPlugin`**：拉起插件预测，交互有利、启动有价。
   对启动极敏感者可降级为 `History`。
4. **`Set-PsExtension` 内的 `Write-Progress -ParentId 0`**：`init` 已无 Id 0 进度条与之配对，效果打折，
   后续可改为 `-Verbose` 输出或删掉。
5. **`$profile` 尾部的 `argc/fnm` 钩子**（当前注释状态）：启用会显著加长启动，后续如需启用建议走
   `Register-EngineEvent PowerShell.OnIdle` 延迟加载。
6. **开机任务**（`Startup.psm1:Start-StartupTasks`）：`TimeAnnouncer` + `IpUpdater` 两个常驻 pwsh 进程
   可合并为一个 daemon；`startup.ps1` 阻塞登录过程，建议计划任务延迟执行。
7. **conda 初始化钩子**：`init` 内已注释，按需用缓存文件方案（注释中有模板），不要直接 `iex` 生成脚本。
8. 全仓库尚无 `.psd1`（除 `CompletionPredictor`）：`Get-Module -ListAvailable` 类调用保持在冷路径，
   不要进 `init`/`prompt`。
