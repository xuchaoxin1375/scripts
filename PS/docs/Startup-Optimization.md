# Pwsh 启动与初始化速度优化

> 适用：`PS/` 模块集（`$env:PSModulePath` 引用 `C:/repos/scripts/PS`，`$profile` 里只有 `init`）。
> 测量环境：Windows Server 级虚拟机，pwsh 7.5。个人电脑数值不同，但瓶颈排序一致。

## 1. 基线数据

| 场景 | 耗时 | 说明 |
|---|---|---|
| `pwsh -NoProfile -c exit` | ~208ms | 裸启动，优化天花板 |
| conda hook（`profile.ps1`） | ~450~700ms | 每个 shell 都 fork 一次 conda.exe，**是第一大户，比 init 还贵**；已用缓存方案解决（见 §8） |
| `init`（8 步） | +460~770ms | 沙盒多次测量区间 |
| 真实全 profile（conda + init） | ~800~1300ms | 沙盒 1279ms，真机约 800~950ms |
| `prompt` 每次回车 | ~100ms | 主要是 `Get-MemoryUseSummary` 的 CIM 查询（~100ms/次，由 5s 节流摊薄） |
| `Get-Module -ListAvailable Terminal-Icons` | ~78ms | 每次全盘扫描 PSModulePath，不可放热路径 |
| `Get-CimInstance Win32_OperatingSystem` | ~192ms | 同上，必须缓存 |

```powershell
# 复测命令（重定向/agent 下也干净：PSReadLine 控制台相关选项已按场景跳过，见 §12）
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

`init -Timing` 沙盒实测（顺序即耗时顺序；`Json` 拆分 + conf 缓存后复测）：

| 步骤 | 时间 |
|---|---|
| Set-PsPrompt（含 core 环境导入） | 148~177ms |
| Set-PSReadLinesCommon | ~102ms |
| Set-PSReadLinesAdvanced | ~83ms |
| Confirm-EnvVarOfInfo（稳态命中缓存） | ~37ms |
| Set-ArgumentCompleter | ~36ms |
| Set-PsExtension（默认 False，近乎 no-op） | ~22ms |
| Confirm-DataJson（首调含 Json 模块解析，拆分前 65ms） | ~19ms |
| Register-PsUxLazyLoad（只注册 OnIdle 事件，TerminalTools 首解析在内） | ~18ms |

## 2. 本次改动总览

### 2.1 新增模块

| 模块 | 行数 | 职责 | 来源 |
|---|---|---|---|
| `Prompt/Prompt.psm1` | 723 | 提示符渲染与切换：`prompt/promptx` 入口、`Prompt*` 主题、`Write-*` 片段、`Set-PsPrompt`、`dm`、`Test-PromptDelay`、oh-my-posh 相关 | `Pwsh.psm1` + `ArgumentCompletion.psm1` |
| `Json/Json.psm1` | 251 | JSON 数据文件读写校验（`Update-Json`/`Get-Json`/`Confirm-DataJson` 等，init 热路径） | `Tools.psm1`（见 §9） |
| `Web/Web.psm1` | 1867 | 网络/HTTP 服务/nginx 站点/域名/下载 | `Tools.psm1`（见 §10） |
| `Text/Text.psm1` | 914 | 文本/编码/markdown/格式化 | `Tools.psm1`（见 §10） |
| `TestLinks/TestLinks.psm1` | 347 | GitHub 镜像站可用性测试（含数据源） | `Git` → `Deploy` → 独立（见 §9/§10） |

### 2.2 函数搬迁（只改归属，不改名不改行为）

| 函数 | 从 | 到 | 理由 |
|---|---|---|---|
| `prompt`、`promptx` | `ArgumentCompletion` | `Prompt` | prompt 入口与补全注册无关 |
| `Set-PsPrompt`、`Set-PsPromptStyle`、`dm`、`Test-PromptDelay`、`Get-PromptScriptBlock`、`PromptFast/Balance/Brilliant*/Short*/Default/Simple`、`Write-UserHostname/Uptime/HostIp/PermissoinLevel/Path/OSVersionInfo/PsEnvMode/PsMode/BatteryAndMemoryUse/Data/Time/ColorsPreivew`、`Get-GitInfo`、`write-GitBasicInfo`、`Set-PoshPrompt`、`Enable-PoshGit` | `Pwsh` | `Prompt` | 全部只服务提示符 |
| `Get-MacOSOperatingSystemInfo`、`ProcessDetail`、`Get-ProcessDetail`、`Get-ProcessMemoryView`、`Get-CommitStatus`、`Show-CommitMemoryBar`、`Show-MemoryBar` | `Pwsh` | `Info` | 系统信息查看 |
| `Get-Size`、`Get-ItemSizeSorted`、`Get-PsIOItemInfo`、`Get-ChildItemNameQuatation`、`Get-NonEmptySubdirectories`、`Remove-EmptyDirectories` | `Pwsh` | `FileSystem` | 文件/目录度量（`FileSystem.psm1` 原来只有 13 行，现在名副其实） |
| `Update-PwshEnv`、`Update-PwshvarsIfNotYet`、`Update-PwshEnvIfNotYet`、`Test-PsEnvMode` | `Pwsh` | `Init` | 初始化编排与环境等级跟踪就该住在一起 |
| `Confirm-DataJson` | `Startup` → `Tools` → **`Json`** | 最终在 `Json`（`Json.psm1:69`），与 `Get-Json/Update-Json` 同模块；init 热路径与 prompt 缓存都依赖它 |
| 镜像站数据源 `$GithubMirrors*` + `Test-LinksLinearly/Parallel`、`Test-MirrorAvailability`、`Get-AvailableGithubMirrors` | `Git` → `Deploy` → **`TestLinks`** | 最终独立为 `PS/TestLinks/` 规范模块（见 §9/§10；§2.4 记的是中间态） |
| `Get-BatteryLevel` | `Basic` | `Info` | 与内存数据源同模块（见 §11） |
| `Test-DirectoryEmpty` | `Tools` | `FileSystem` | 目录判空（见 §9） |
| 网络/HTTP/nginx/域名 24 个 | `Tools` | `Web` | 见 §10 |
| 文本/编码/markdown/格式化 14 个 | `Tools` | `Text` | 见 §10 |
| `Add-PythonAliasPy` | `Tools` | `Development` | 见 §10 |

效果：`Pwsh.psm1` 3590 行 → 1235 行；`Init.psm1` 380 → 499 行；
`Tools.psm1` 4172 → 1089 行；`Deploy.psm1` 2996 → 2653 行（镜像站块迁出）。
已用脚本对账：原定义零丢失、跨文件零重复（见 §6）。自有模块现 53 个（见 §6；2026-09-20 新增 `Test`
草稿模块、同日删除 `Deprecated` 归档模块）。

### 2.3 重复定义清理

| 函数 | 处理 | 说明 |
|---|---|---|
| `Set-PoshPrompt`（`Pwsh` 内两份，参数不同） | 删第二份，留带 `-Poshgit` 的版本 | 同文件重复，后加载的静默覆盖前者 |
| `Get-RecycleBin`、`Clear-RecycleBinDir`（`RecycleBin` 内各两份，完全相同） | 删第二份 | 同文件粘贴重复 |
| `exes_`、`dcs_Idm`（`JumpDirectory` 内各两份） | 删第二份（后整个 `JumpDirectory` 模块已删除：61 个个人跳转函数，零外部引用） | 同上（`$Downloads` vs `$downloads` 无实质差异） |
| `Disable-CredentialGuard`（`Basic` vs `Security`，行为不同） | 删 `Basic` 版，留 `Security` 版 | `Basic` 版非管理员时直接 `exit` 退出 shell；且同名跨模块会导致自动加载命中不确定 |
| `Test-Links*` 等 4 函数（`Git` vs `Deploy/TestLinks`，已分叉） | 删 `Git` 版，留 `Deploy` 版 | `TestLinks` 版更新（含可用并行分支）；`Git` 版并行分支被注释 |
| `Add-Extension`（`FileSystem` vs `CommentBasedHelpDocumentExamples` 示例） | 示例改名 `Add-ExtensionExample`，`FileSystem` 为唯一正本 | 零调用方；自动加载曾命中不定（见 §10） |

### 2.4 顺手修掉的三个坑

1. **`Confirm-DataJson` 死循环**（现 `Json.psm1:69`，最初在 `Startup`，中间态在 `Tools`）：
   `$DataJson` 为空时 `Test-Path/Get-Content/Rename-Item` 全报错，又无参自递归 → 无限递归。
   现改为：空值兜底 `~/Data.json`，`try/catch` 校验失败直接备份重建，**无递归**。
2. **`Set-CommonInit` 调用不存在的 `Start-CoreInit`**（`Init.psm1`）：一调即 `CommandNotFound`。
   已删除该行——`Update-PwshEnv`（变量+别名+prompt）已覆盖其语义。
3. **幽灵模块 `Deploy/TestLinks.psm1`**：目录名 `Deploy` ≠ 文件名 `TestLinks`，PowerShell 自动发现
   只认 `<目录名>.psm1`，所以该文件**从未被加载过**，里面的函数一直靠 `Git` 的副本续命。
   先并入 `Deploy.psm1`，后独立为规范的 `PS/TestLinks/` 模块并删除原文件
   （`Get-Command Test-LinksLinearly` 现解析到 `TestLinks`，已验证；见 §9/§10）。

## 3. 启动链优化（`Init.psm1:3`）

旧 `init` 把 7 个调用转成字符串，逐行 `Invoke-Expression`，每行再套 `Measure-Command` + `Write-Progress`。
三个问题：`iex` 慢且报错丢定位；`Write-Progress` 渲染是启动链最贵操作之一；正常启动根本不需要逐项计时。

- 改为**直接调用步骤表**（当前会话作用域，与原来 `iex` 效果一致），默认无进度条、无计时。
- 计时改为轻量 `[datetime]::UtcNow` 差值，仅 `-Timing` 或 `-InformationAction Continue`（即 `p -Force` 路径）时收集并打印报告。
- 新增 `init -Timing` 开关，替代原来“想看报告就得忍受慢启动”的两难。

## 4. 热路径去注册表写（`EnvVar.psm1:941`）

`Set-EnvVar/Add-EnvVar` 默认 `Scope=User`：每次调用先全量扫描环境变量（`Update-EnvVarFromSysEnv`），
再写注册表。在 `init`/`Set-PsPrompt` 这种每次启动都跑的路径上纯属浪费。

- 新增 `Set-ProcessEnvVar`：只 `Set-Item Env:\`，进程级生效，不碰注册表。
- `Set-PsPrompt`（`Prompt.psm1:642`）：默认只进程级写入；加 `-Persist` 才同时写注册表。
  之前每次 `Set-PsPrompt -version X` 都全量扫描+写注册表，之后还重复写一次 `$env:PsPrompt`。
- `Confirm-EnvVarOfInfo` 的 `OSCaption/OSFullVersionCode` 等：持久化到注册表后新 shell 继承即命中，
  稳态 23ms，无需再动（不要改成每次强制刷新，那会把 192ms 的 CIM 查询带回启动链）。

## 5. Prompt 延迟优化（`Prompt.psm1`）

- 默认主题已是 `fast`（`Set-PsPrompt` 无参数且无 `$env:PsPrompt` 时），保持。
- `Get-MemoryUseSummary` 的 CIM 查询已有 5s 节流（`Start-ScriptWhenIntervalEnough`），保留——
  实测 `prompt` 100ms 中它占大头，但每 5 秒才触发一次，摊薄后可接受。
- 新增 `Get-BatteryLevelCached`（`Prompt.psm1:315`，30s TTL，含无电池机器的 `$null` 也缓存）：
  `Write-BatteryAndMemoryUse` 改用它。实测连续两次调用 51ms → 0ms。
  数据源 `Get-BatteryLevel` 已从 `Basic` 迁入 `Info`（见 §11）。
- `Write-HostIp` 走文件缓存（`DataJson` + 后台 `Update-NetConnectionInfo` 守护进程）；
  未命中路径已修：批量取 IP（1233→167ms）+ 60s 会话记忆 + 直接返回计算值（见 §11）。
- 如需极致响应：`Set-PsPrompt -version Simple`（纯 `PS>`），或把 `write-GitBasicInfo` 从常用主题摘掉
  （大仓库 `git rev-parse` 是额外开销；当前实现已优化为读 `.git/HEAD` 文件）。

## 6. 验证（全部通过，2026-09-20 复核）

```powershell
# 1) 自有 53 个模块逐个强制导入，FAIL_COUNT=0；Test-ModuleManifest 全过
# 2) 关键命令解析到正确模块（实测）：
#    Set-PsPrompt -> Prompt；Update-PwshEnvIfNotYet -> Init；
#    Get-ProcessMemoryView/Get-BatteryLevel -> Info；Get-Size -> FileSystem；
#    Confirm-DataJson/Update-Json/Get-Json -> Json；
#    Test-Links*/Get-AvailableGithubMirrors -> TestLinks；
#    Start-HTTPServer -> Web；Convert-MarkdownToHtml -> Text；
#    Add-PythonAliasPy -> Development；Set-ArgumentCompleter -> ArgumentCompletion；
#    init -> Init（prompt 首调由 Prompt 模块提供）
# 3) init 全链 + prompt + 主题切换 + DataJson-null 兜底冒烟通过
# 4) manifest 导出对账：块注释感知的函数解析 vs 各 psd1 FunctionsToExport，零误差
pwsh -NoProfile -File <tmp>/verifyAll.ps1
pwsh -NoProfile -File <tmp>/verify3.ps1
```

结构对账另用脚本比对过：历次搬迁原定义**零丢失、跨文件零重复**；
`JumpDirectory` 删除前已验证其 61 函数零外部引用。

## 8. profile 层优化（2026-09-20 验收追加）

- `CurrentUserAllHosts/profile.ps1` 的 conda 初始化块每次 fork `conda.exe`（实测 443~697ms），
  已改为**缓存方案**：hook 输出存 `~/.conda_hook_cache.ps1`，仅 `conda.exe` 本体更新（mtime 变新）
  才重建，平时直接点源。实测 573ms → 59ms。注意下次运行 `conda init` 会覆盖该块，届时重新应用。
- `CurrentUserCurrentHost` 里的 argc 生成块目前是**注释状态**，不产生开销；`argc` 二进制也不在
  PATH 上——需要时先装 argc 再解注释，不要直接放开（放开后每次还要扫描 800+ 个补全文件）。
- `Update-NetConnectionInfo` 守护进程里的 `Write-Host $DataJson`（每次启动吐一行裸路径）已删除；
  `Get-IpAddressForPrompt` 内对 `Confirm-DataJson` 返回值的泄漏已用 `Out-Null` 堵住。

## 9. 第二轮：manifest、conf 预编译与 Analyzer（2026-09-20）

- 53 个自有模块全部补 `.psd1`（`ModuleVersion 1.0.4`，`FunctionsToExport` 显式全量，
  `PowerShellVersion 7.0`）：自动发现不再解析 `.psm1`，`Test-ModuleManifest` 全过，
  导出对账零误差。教训：解析函数名必须块注释感知（曾把帮助文本 `Function that shows...`
  误收录为函数 `that`），规则见 `Module-Conventions.md §7`。
- `Tools.psm1` 拆出 `Json` 模块（`Update-Json/Get-Json/Confirm-DataJson` 等 5 个）；
  `Test-DirectoryEmpty` 归 `FileSystem`；`Deploy` 尾部的镜像站块独立为规范的
  `PS/TestLinks/TestLinks.psm1`。`Confirm-DataJson` 首调不再解析 4000+ 行。
- `.conf` 变量文件**预编译缓存**（`Get-CompiledPwshVarLines`）：同转换规则单次解析，
  `Parser` 语法校验 + mtime 失效 + 回退逐行路径 + `-NoCache` 逃生。变量级对账
  （legacy/cold/warm 三路）零差异；`Update-PwshVars` 460ms → 334ms。
- Analyzer 实修：`EnvVar` 三处 iex 改直读写 `Env:` 驱动（含单引号值拼接 bug 一并修复）、
  `Clear-EnvVar` 死参数 `-Refresh` 删除、`Get-Json`/`Get-ParametersList` 补 `process` 块
  （管道多对象曾只取最后一个）。其余 Warning 归档为已接受偏差，见 `Module-Conventions.md §10`；
  仓库级排除规则在 `PS/PSScriptAnalyzerSettings.psd1`。
- 新增 `PS/docs/Module-Conventions.md`（目录即模块/命名/导出/输出流/iex/管道/编码/版本）
  与仓库 `.gitattributes`（文本/二进制声明，不强制转行）。

## 10. 第三轮：Tools 拆分与缝合清理（2026-09-20）

- `Tools.psm1` 4172 → 1078 行：网络/HTTP/nginx/域名 24 个 → 新 `Web` 模块；
  文本/编码/markdown/格式化 14 个 → 新 `Text` 模块；`Add-PythonAliasPy` → `Development`。
  拆分中抓到脚本 bug（`$web = Build-Module $WEB` 大小写同变量冲掉行号表，
  与 `$keep/$KEEP` 事件同类，已修；教训：写完先对账再落盘）。
- `CommentBasedHelpDocumentExamples` 的示例 stub 与 `FileSystem` 的 `Add-Extension`
  同名（自动加载命中看运气，零调用方）：示例改名 `Add-ExtensionExample`，正本唯一。
- `Get-ChildItemNameQuatation` 用别名 `^`（别名未加载的新 shell 必错），改直写 `Select-Object`。
- `Set-PsExtension` 进度条去掉悬空 `-ParentId 0` 并收尾 `-Completed`。
- 逐缝合点验尸：仅一处孤儿注释（`Update-PowerShell` 尾注掉到 `Confirm-UserContinue` 头上），已归位；
  其余接缝干净。

## 11. 第四轮：prompt 热路径（2026-09-20）

- `Get-IpAddressFormated` 缓存未命中时 **1233ms**（逐网卡 `Get-NetIPAddress` + 结果丢弃、
  首屏无 IP）：改批量一次取全量（InterfaceIndex 内存配对，输出逐字节一致已验证）、
  加 60s 会话记忆、未命中直接返回计算值。重算 1233→167ms，记忆命中 4ms，文件命中 2ms。
- `Write-OSVersionInfo` 每回车读注册表（~10ms）：`DisplayVersion` 改 init 时持久化
  （`Confirm-EnvVarOfInfo`），prompt 只读 `$env:`。
- `Get-BatteryLevel` 从 `Basic` 迁入 `Info`（与内存数据源同模块）。
- 附带纠偏：模块首解析仅几十毫秒（`Info` 34ms/`Basic` 25ms），运行时（CIM/进程/注册表）
  才是战场；不要为了解析成本拆已经够小的模块。

## 12. 第五轮：PSReadLine 重定向报错根治（2026-09-20）

起因：agent/CI 等重定向场景下 `init` 会刷两行红字，手动开终端从不出现：

```text
Set-PSReadLineOption: The predictive suggestion feature cannot be enabled
  because the console output doesn't support virtual terminal processing or it's redirected.
Set-PSReadLineOption: 句柄无效。
```

根因（沙盒逐行复现，实锤到行）：

| 报错 | 来源 | 含义 |
|---|---|---|
| predictive suggestion…redirected | `Init.psm1` `Set-PSReadLinesAdvanced` 的 `-PredictionSource HistoryAndPlugin` | 预测功能要往控制台写 VT 序列，stdout 被重定向就无处可写，直接抛 terminating error |
| 句柄无效 | 同函数 `-PredictionViewStyle ListView` | 列表视图要拿真实控制台缓冲区句柄，重定向下没有句柄 |

三句关键事实：

1. **手动启动没事，是因为你的 stdout 连着真控制台**；agent 把 stdout/stderr 重定向走
   管道才触发。`[Environment]::UserInteractive` 在重定向下**依然是 True**，指望它判断必错；
   唯一可靠的探针是 `[Console]::IsOutputRedirected`。
2. **这不只是难看**：`init` 的步骤表没有 `try/catch`，这两个是 terminating error，
   一抛后面 5 步（补全注册、OS 信息、prompt、DataJson）**全部被跳过**——重定向下的 `init`
   以前是静默半残的。
3. 其余选项（`-Colors`、`-MaximumHistoryCount`、`-CompletionQueryItems`、
   `-HistorySearchCursorMovesToEnd`、全部 `Set-PSReadLineKeyHandler`）重定向下无害，
   已逐项验证，不用动。

修法（`Set-PSReadLinesAdvanced` 内联分流，不新增函数，manifest 不用动）：

- stdout 未重定向（真机交互）：两行原样执行，行为与以前完全一致；
  外面再套一层 `try/catch`（只 `Write-Verbose`），防“非重定向但 VT 残缺”的怪控制台。
- stdout 已重定向（agent/CI/计划任务/`pwsh -c` 管道）：跳过这**两项**，
  其余照常。反正该场景没有行编辑，预测源取什么值都无人在意。

验证（重定向沙盒）：`Set-PSReadLinesAdvanced` 单调 0 报错；全链 `init` 可见报错 0，
且 `prompt→Prompt`、`OSDisplayVersion`、`~/Data.json` 三项副作用齐全
（修之前后 5 步是被跳过的）。另：`$Error` 里会剩几条 `Env:\X does not exist`
记账，那是 `EnvVar.psm1:871/1015` 的 `-ErrorAction SilentlyContinue` 设计内静默查询，
不打印、不影响，只在沙盒这种缺用户环境变量的机器上多几条，真机也有（`OSDisplayVersion`
先查后设的顺序所致），不用管。

## 7. 剩余开销与后续 TODO（按性价比排序；已完成项已划线）

1. ~~**巨型模块首调解析 cost**：`Tools.psm1`（4100+ 行）拆分、`Deploy.psm1` 镜像站块迁出、全仓库补 `.psd1`~~
   ——已完成（§9/§10）：`Tools` 4172→1089 行，53 模块全 manifest。`Deploy.psm1` 剩 2653 行，
   冷路径，按需再拆。
2. **`Set-PsExtension`**：`$env:PsExtension=True` 时 `Import-Module` 第三方模块（`CompletionPredictor` 等）
   是启动链最大单项（历史数据 300ms+）。默认保持 `False`；启用者自负。
3. **`Set-PSReadLineOption -PredictionSource HistoryAndPlugin`**：拉起插件预测，交互有利、启动有价。
   对启动极敏感者可降级为 `History`。（状态同步：重定向场景已自动跳过预测源/列表视图，见 §12；
   真机交互分支行为不变。）
4. ~~**`Set-PsExtension` 内的 `Write-Progress -ParentId 0`**~~——已完成（§10）：去掉悬空父引用并收尾。
5. **`$profile` 尾部的 `argc/fnm` 钩子**（当前注释状态）：`argc` 二进制缺失时不要放开；
   启用会显著加长启动，后续如需启用建议走 `Register-EngineEvent PowerShell.OnIdle` 延迟加载。
6. **开机任务**（`Startup.psm1:Start-StartupTasks`）：`TimeAnnouncer` + `IpUpdater` 两个常驻 pwsh 进程
   可合并为一个 daemon；`startup.ps1` 阻塞登录过程，建议计划任务延迟执行。
7. ~~**conda 初始化钩子**~~——已完成（§8）：`~/.conda_hook_cache.ps1` 缓存，573→59ms。
8. ~~全仓库补 `.psd1`**~~——已完成（§9）：53 自有模块全 manifest。`Get-Module -ListAvailable`
   类调用保持在冷路径，不要进 `init`/`prompt`。
9. `Tools.psm1` 剩 1078 行（多为 Windows 一次性小工具 + 通用杂项）：继续原子化还是维持“misc”定位，待定。
10. ~~`Mock`、`Test`（whois 跟踪函数名实不符）、`CommentBasedHelpDocumentExamples`（MSDN 示例）：删还是留，待定~~
    ——已解决（§13）：用户拍板全保留做特殊用途；`Test`→`Whois`、`CommentBasedHelpDocumentExamples`→`HelpExamples`
    改名（函数名/GUID 未动），`Mock` 名实相符不动。

## 13. 第六轮：已知问题清扫（2026-09-20）

- **`.gitattributes` 的 `text` 规则引发全仓库假 diff**：`*.psm1 text` 等行让 git 在比较时
  把 CRLF 归一化成 LF，而历史 blob 是 CRLF 原样入库的——`Basic.psm1` 2282 行被标 4571 行、
  `VarSet1.conf`（字节与 HEAD 完全一致）被标 80 行。修法：删掉全部 `text` 行，
  只留 `*.lnk/*.exe/*.dll binary`，另附注释说明“不要声明 text”（最小 diff 原则）。
  附带把之前暂存时被归一化污染的 index blob（如 `Pwsh.psm1` 的 LF 版）刷回工作区原样。
  修后 `git diff` 只剩 12 个真改动文件（`--ignore-cr-at-eol` 对照一致）。
  教训：`VarSet1.conf` 的“换行抖动”从来不是用户编辑器的问题，是我们自己的属性文件闹的。
- **`init` 步骤表加固**：单步包 `try/catch`，失败记入 `$global:PsInitStepErrors`，
  最后 `Write-Warning` 汇总，成功路径行为/耗时不变。以后任何步骤再抛 terminating error，
  最多坏自己，不会静默吃掉后面所有步骤（§12 的教科书案例）。
- **`Deprecated` 指引补齐**：模块头声明只读归档（零调用方、别删、大小写遗留不改名），
  10 个函数逐个加 `# 替代:`行（7 个有现任正本：`Start-StartupTasks`/`Get-MemoryCapacity`/
  `Deploy-SmbSharing`/`Get-IpAddressForPrompt`/`init`/`Get-EnvVar`/`Get-PsIOItemInfo`；
  另 3 个如实标注：`Restart-Process` 反面教材、2 个无现任接替的一次性工具）。
- **改名**：`Test`→`Whois`、`CommentBasedHelpDocumentExamples`→`HelpExamples`
 （`git mv` 保历史，GUID 不变，函数名不动，无按模块名引用已核实）。
  全量门禁：53/53 导入、`Test-ModuleManifest` 全过、函数归属正确、旧名已死、`init` 零报错。
- **核实无问题**：profile 的 conda 缓存块已有 `Test-Path` + `try/catch` 双保险，
  新机器缺缓存文件也能 fallback 当场重建，不用改。

## 14. 第七轮：启动进度条开关（2026-09-20，用户实测纠偏）

- 纠偏：早期注释称进度条是“启动链上最贵的操作之一”。用户真机实测：**开进度条全链 306ms**
  （截图为证），开销可忽略。贵的一直是重定向/agent 场景（无处渲染 + 日志污染），不是进度条本身。
- 开关 `$env:PsShowProgress`（`Init.psm1` 的 `init` 步骤循环）：
  默认开（未设置/空/非显式关闭值均为开）；`False`/`0`/`No`/`Off`（大小写不计）关闭；
  持久关闭：`Add-EnvVar -EnvVar PsShowProgress -NewValue 'False'`（User 级）；
  stdout 重定向时强制关闭（与 §12 同一探针）。
- 实现：循环改 `for` 取下标算百分比；**样式一比一恢复历史原版**
 （`$PSStyle.Progress.View = 'Classic'` + `-Id 0` + `"<步骤> -> Processing: <一位小数>%"` +
  每步 `Write-Information`，仅 `-InformationAction Continue` 时可见），收尾补
  `Write-Progress -Completed`。直接调用/单步加固/计时报告保持本轮改法（不再回 iex）。
- 验证（沙盒重定向）：开关 12 值矩阵全对；默认/显式关两轮全链零报错、`prompt→Prompt`；
  ON 分支调用原文强制走一遍亦无错。真机渲染效果以用户目测为准。

## 15. 第八轮：`Sync-ModuleManifest` 偷懒同步（2026-09-20）

- 背景：53 模块全 manifest 后，日常加函数要手改两处，用户嫌 `.psd1` 帮倒忙。
  新增 `Pwsh.Sync-ModuleManifest <模块名> -Reload`：块注释感知解析 `.psm1`，
  缺失项按定义顺序追加进 `FunctionsToExport`，只增不减，GUID/版本/换行原样保留；
  附带提醒 orphan（在表不在文件，只报不删）。
- 踩坑实录：首版追加统一带尾逗号，被 manifest 受限语言解析器拒绝
  （`@('a',)` 普通代码合法、`.psd1` 里非法，`Missing expression after ','`）；
  改为仅末项无逗号（与 house 模板一致），往返测试（加→调→删还原）全绿。
- 验证：53 模块 noop 全“已同步”（解析器与对账一致）；`Pwsh` 导出 31→32，
  `Test-ModuleManifest` 过，全链 `init` 零回归。
- 后续追加（同轮）：不指定 `-Name` 则全量 54 模块（目录枚举，静默递归自身，只打印有变化的 +
  汇总；批量 `-Reload` 跳过 Prompt 防嵌套并明示重进 shell）。`-Name` 加
  `[ArgumentCompleter()]` 属性式补全（自带走，不碰 init 不碰 manifest；`Wh`→`Whois`、
  空字→54 个全列，沙盒 `CompleteInput` 验过）。
- 同轮附带：restricted characters 警告根因（导出名 2 个以上 `-` 才触发，8 模块 17 个名，
  单横线/点/下划线/大小写/无横线全不触发，合成模块逐个实测；`-` 在警告字符集里是误导源）。
  修法：`Sync-ModuleManifest` 两处重载加 `-DisableNameChecking`（定向压制）+ `-Global`
  （函数内 import 默认嵌套，`Get-Module` 列不出）；自动加载路径本来就不报，不用动，不改名。

## 16. 第九轮：不规范名转正（2026-09-20，用户拍板改名+提交）

- 动因：`restricted characters` 警告的 17 个双横线名 + 2 个拼写 typo，用户拍板转正（替代压制方案）。
- 规则（`Module-Conventions.md §2`）：单横线铁律；废弃/归档/变体标记用**融合后缀**
  （与本就存在的 `Get-EnvVarsDeprecated` 形式统一）；130+ 无横线个人速记 grandfathered 不动；
  大小写不归一（引擎不敏感）。双横线旧名不再以别名兼容（别名带双横线同样触发警告，留了等于没修）。
- 对照表（18 个，调用方审计：Deprecated 系零外部调用；其余仅定义；`Discovey` 另有 2 处代码调用已同改）：

| 旧名 | 新名 | 模块 |
|---|---|---|
| `Deploy-StartupSoftwareAndServices-Deprecated` | `Deploy-StartupSoftwareAndServicesDeprecated` | Deprecated |
| `Restart-Process-Deprecated` | `Restart-ProcessDeprecated` | Deprecated |
| `Get-MemoryCapacity-Deprecated` | `Get-MemoryCapacityDeprecated` | Deprecated |
| `Set-ProgramToOpenWithList-deprecated` | `Set-ProgramToOpenWithListDeprecated` | Deprecated |
| `Deploy-SmbSharing-Deprecated` | `Deploy-SmbSharingDeprecated` | Deprecated |
| `Set-FolderFullControlForEveryone-Deprecated` | `Set-FolderFullControlForEveryoneDeprecated` | Deprecated |
| `Get-IPAddressV4-Deprecated` | `Get-IPAddressV4Deprecated` | Deprecated |
| `Start-PwshInit-deprecated` | `Start-PwshInitDeprecated` | Deprecated |
| `Get-PSDirItem-Deprecated` | `Get-PSDirItemDeprecated` | Deprecated |
| `Deploy-GithubHostsAutoUpdater-Deprecated` | `Deploy-GithubHostsAutoUpdaterDeprecated` | Deploy |
| `Enable-NetworkDiscoveyAndSharing` | `Enable-NetworkDiscoveryAndSharing` | Deploy |
| `Get-MySqlDatabaseNameCmdlet-Deprecated` | `Get-MySqlDatabaseNameCmdletDeprecated` | MySql |
| `Update-Powershell-Leagcy` | `Update-PowerShellLegacy` | Pwsh |
| `Get-CsvTailRows-Archived` | `Get-CsvTailRowsArchived` | CSV |
| `New-TimeNotification-Robust` | `New-TimeNotificationRobust` | TaskSchdPwsh |
| `Set-ScreenResolutionAndOrientation-AntiwiseClock` | `Set-ScreenResolutionAndOrientationAntiwiseClock` | Tools |
| `Get-CxxuPsModuleVersoin` | `Get-CxxuPsModuleVersion` | Tools |
| `Get-XXXShopifyProductJsonUrl-Archived` | `Get-XXXShopifyProductJsonUrlArchived` | WordPress |
| （`Get-EnvVarsDeprecated` 本就融合，无需改动） | | Deprecated |

- 执行：脚本精确替换 41 处（定义/manifest/调用方/help 示例，词边界保护，正本如
  `Deploy-SmbSharing`/`Get-MemoryCapacity` 零误伤已核实），BOM/换行无附带改动。
- 验证：54 模块导入零失败、manifest 全过、`STILL-WARN=NONE`（警告连根拔起）、
  新名归属正确、旧名已死、`init` 零回归。

## 17. 第十轮：体验件延迟加载（2026-09-20，用户拍板推荐组合）

- 开：`PSFzf`（仅 Ctrl+T 文件 / Ctrl+R 历史，Tab 不动）+ `zoxide`（init 输出缓存，
  仿 conda 套路）+ 已有的 `CompletionPredictor`。不开：`oh-my-posh`（每回车进程税）、
  `carapace`/`PSCompletions` 二选一待定、`posh-git`/`fnm`/`argc` 按需。
- 实现：`TerminalTools.Register-PsUxLazyLoad`，`init` 第 8 步只注册
  `PowerShell.OnIdle` 事件即返回（沙盒实测 18ms，含模块首解析）；idle 触发后
  后台装模块，触发即摘掉自己。开关 `$env:PsFzf`/`$env:PsZoxide`（默认开，
  `False`/`0`/`No`/`Off` 关）；重定向下不注册（无交互）；`-Now` 立即执行
  （测试/非 idle 主机用，不受重定向门限制）。
- 踩坑两则：①函数内 `Import-Module` 默认装成嵌套模块（`Get-Module` 列不出，
  `Sync-ModuleManifest` 同款教训），重载/加载一律加 `-Global`；②`Unregister-Event`
  缺订阅时 terminating 错误**抛出即进 `$Error` 记账**，`try/catch` 只能止显示止不住记账
  （隔离实测）——改用 `$global:PsUxOnIdleRegistered` 标记位根治，`-Now`/重复调用零污染。
  另：zoxide 的 `z` 是**别名**（指向 `__zoxide_z`）不是函数，判定时看类型别看名。
- 验证（沙盒 `-Now`）：`ERRS=0`、`PSFzf` 顶层加载、双和弦绑定、`z $HOME` 真跳、
  缓存干净可复用、双关全静默。真机待目测：新开终端等一拍，`Ctrl+R`/`z` 应可用；
  若 OnIdle 在某主机不触发，用 `-Now` 或报回来改方案。

## 18. 第十一轮：新机部署指南（2026-09-20）

- 新增 `Deploy.Test-NewMachineReadiness`：部署前 checklist 即代码（必备 6/可选 6/首跑生成物 1，
  表格 + 缺啥补啥列，只读不改机器；本机实测必备 6/6）。
- 新增 `docs/Deploy-Guide.md`：11 节（缺口检查/pwsh7/git+clone/PSModulePath/profile/第三方模块/
  scoop/python-conda/首次 init/WT 开机/多设备差异/回滚），命令全部核对过签名（宽松风格，直接抄）。
- 附带：抓到 edit 工具整文件改写换行的毛病（见 `Agent-Handoff.md` 踩坑 #14），本轮 5 文件
  diff 已用 `--ignore-cr-at-eol` 对照干净（119+/2- 全是预期行）。

## 19. 第十二轮：CompletionPredictor 补加载（2026-09-20，用户问“输入时没候选”）
- 根因：插件装了（0.1.1）但 `init` 里 `Import-Module` 是注释状态；predictor 必须显式 import
  才会向 ListView 供稿，不会自动生效——ListView 一直只有历史源。用户常用 `ls`/`gci` 别名，
  历史里少有 `Get-ChildItem` 开头条目，所以 `get-child` 无候选而 Tab 有（两套索引）。
- 修法：交互分支内加 `Import-Module CompletionPredictor -ErrorAction SilentlyContinue`
 （实测 35ms；缺失静默降级纯历史；重定向下照旧跳过）。沙盒只能验到语法/门禁，
  交互分支需真机确认（开新终端输 `get-child`，ListView 应出现非 History 源的行）。
- 同轮补：`init` 内加载加 `-Global`（函数内 import 嵌套坑第三次：`Sync`、`PSFzf`、本次）。

## 20. 第十三轮：自研命令名 predictor（2026-09-20，用户拍板“值得就继续”）

- 值得性论证（先实测后立项）：①纯 PowerShell 版**证伪**（predictor 线程无 runspace，
  跑脚本必抛 `There is no Runspace available...`，隔离实测）；②C# 路全通（dotnet SDK 10.0.201
  在，SMA 离线引用本机 pwsh 的 dll，无需 NuGet）；③建表一次 88ms（2831 命令，走 OnIdle 无感），
  每次按键 C# 前缀过滤 1.6ms（PowerShell 版 13.5ms，20ms 预算擦边，C# 余量 10 倍）。
- 实现：`PS/CxxuPredictor/`（`src/` 三文件 153 行 + `CxxuPredictor.dll` 7.6KB +
  `.psd1` 零导出；构建 `dotnet build -c Release`，27s，0 警告）。
  只处理裸命令名 token（参数/路径/`git` 留给 CompletionPredictor，不重叠），
  自匹配排除，30 条封顶，无反馈接口；`OnIdle` loader 里 `-Global` 装载。
- 验证（沙盒）：构建零警告；import 423ms 零错并顶层列出；反射直测过滤逻辑
  （`get-chi`→`Get-ChildItem`、自匹配排除、空前缀排除）；manifest 过；自动发现 OK。
  真机待验证：输 `get-child`，ListView 应出现 `[CxxuCommand]` 来源行。
- 维护：dll 进仓库（`.gitattributes` 已有 `*.dll binary`）；逻辑变更才需重构建；
  卸载 `Remove-Module CxxuPredictor`；`Sync-ModuleManifest` 天然跳过（无 `.psm1`）。
- 边界（已读源码 `CompletionPredictor.cs` 核实，不再是文档推测）：`GetSuggestion` 遇到
  `TokenFlags.CommandName` 直接 `return default`（源码注释：command discovery 太贵，跳过），
  只做非命令位置（参数/路径/成员）+ `git` + `% ? cd dir foreach where` 白名单。
  所以**命令名前缀（如 `get-child`）它永远沉默**，用户只看到历史是必然的，不是坏了。
  原生 PSReadLine 没有“TabExpansion 边输边弹”；predictor 须 20ms 内返回
  （官方硬性），慢同步的命令发现塞不进这个预算。更重的悬浮面板类另见 `Feature-Guide.md §7`。
- 后续：同日用户拍板删除 `Deprecated` 模块（转正后归档无存在必要，零调用），`git rm` 整目录；
  上表作为历史记录保留，53 模块现数见 §2/§6。
