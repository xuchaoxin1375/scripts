# Pwsh 启动与初始化速度优化

> 适用：`PS/` 模块集（`$env:PSModulePath` 引用 `C:/repos/scripts/PS`，`$profile` 里只有 `init`）。
> 测量环境：Windows Server 级虚拟机，pwsh 7.5。个人电脑数值不同，但瓶颈排序一致。
> 本文件按轮次追加历史实测；**现行默认值与性能以 §1 基线表和最后一轮实测为准**（最近更新 2026-11-13）。旧轮次中的“默认关/冷启动约 400ms”等结论只代表当时状态。

## 1. 基线数据

| 场景 | 耗时 | 说明 |
|---|---|---|
| `pwsh -NoProfile -c exit` | ~208ms | 裸启动，优化天花板 |
| conda hook（`profile.ps1`） | ~450~700ms | 每个 shell 都 fork 一次 conda.exe，**是第一大户，比 init 还贵**；已用缓存方案解决（见 §8） |
| `init`（分步任务表） | +460~770ms | 沙盒多次测量区间 |
| 真实全 profile（conda + init） | ~800~1300ms | 沙盒 1279ms，真机约 800~950ms |
| `prompt` 每次回车 | ~100ms | 主要是 `Get-MemoryUseSummary` 的 CIM 查询（~100ms/次，由 5s 节流摊薄） |
| 首屏 OnIdle 单发（predictor + zoxide，命令表缓存热） | ~30ms | 手势桩另计（毫秒级）；缓存缺失时 predictor 建表 +0.1~0.4s，24h 最多一次（§26；2026-11-07 本机实测） |
| `Get-Module -ListAvailable Terminal-Icons` | ~78ms | 每次全盘扫描 PSModulePath，不可放热路径 |
| `Get-CimInstance Win32_OperatingSystem` | ~192ms | 同上，必须缓存 |

```powershell
# 复测命令（重定向/agent 下也干净：PSReadLine 控制台相关选项已按场景跳过，见 §12）
Test-StartupPerformance                      # 启动因子按 Ms 降序，可接 ft/fl（约 3 秒）
Test-StartupPerformance -Report              # 文本摘要：总耗时、分解、前三因素
Test-StartupPerformance -All | ft            # 追加 prompt、体验件全载与开关状态
Test-StartupPerformance -Simple              # 只测一次带 profile 的新 pwsh 启动
init -Force -Timing                           # 当前会话分步耗时（已初始化；首次启动用 init -Timing）
init -Tier Fast -Timing                       # 指定启动档位看分步表（Fast/Balanced，Minimal 为 Fast 别名）
Test-PromptDelay                              # prompt 延迟（默认测 10 次取平均）
```

### 关于 `Loading personal and system profiles took ...ms`

- 这行字是 pwsh 引擎自己打印的，**只有四个级别 profile 文件合计耗时 >500ms（硬编码阈值）才出现**，
  低于就静默。看不到它 = 该实例 profile 不足 500ms，不是“没加载”。
- 嵌套 `pwsh` 是全新进程，`$global:PsInit` 防重复只在同一进程内有效，所以每次都要重跑
  conda + init 全套。与“第几次启动”无关，只和该实例耗时是否过线有关（机器负载、冷热缓存
  会让同一配置在 500ms 线上下横跳，看起来像“有时有、有时无”）。
- `init` 自己打印的 `Environment Loading time` 是函数内部口径，从 `init` 函数入口起算，
  不含 `init` 命令的模块发现、导入与解析，也不含 `$profile` 中排在 `init` 之前的 conda
  缓存段。引擎的 profile 总计包含这些内容，因此通常更大；例如 init 506ms 对应 profile
  701ms 时，约 195ms 来自 conda 钩子、Init 模块导入与 profile 其他语句。两个数字不能
  相加，也不表示 `init` 重复执行；分段对照用 `Test-StartupPerformance`。

`init -Timing` 沙盒实测（顺序即耗时顺序；`Json` 拆分 + conf 缓存后复测；当前 macOS 口径见 §30）：

| 步骤 | 时间 |
|---|---|
| Set-PsPrompt（含 core 环境导入；已消除重复调用） | 130~177ms |
| Set-PSReadLinesCommon | ~90~102ms |
| Set-PSReadLinesAdvanced | ~8~83ms（随冷热与预测视图分支变化） |
| Confirm-EnvVarOfInfo（稳态命中缓存） | ~26~37ms |
| Set-ArgumentCompleter | ~36~51ms |
| Set-PsExtension（默认 False 时 init 直接跳过，不再导入 PsEnv） | 0ms（默认）/ 启用时另计 |
| Confirm-DataJson（仅 Balance/Brilliant 等用到 IP 的主题执行） | 0ms（fast/short/default）/ ~35ms（IP 主题） |
| Register-PsUxLazyLoad（只注册 OnIdle 事件，TerminalTools 首解析在内） | ~18~25ms |
| Register-GitCompletion（只注册 completer，首次补全才导入模块；未装时直接返回） | ~6~8ms |
| Register-CarapaceLazyLoad（默认关闭；启用时只装参数位 Tab 桩） | 0ms（关闭）/ ~7ms（启用）；首次外部 CLI 参数补全另付约 0.2–0.3 秒 |

### 当前 Windows 会话复验

本机 pwsh 7.5.4、PSReadLine 2.3.6、传统控制台，保留 conda 缓存与真实 profile，并同时启用 argc/carapace。独立交互窗口使用临时提示符和禁写历史设置，注入按键后轮询读屏；Tab 数值包含菜单首次重绘，测量分辨率约 10ms。以下为同机先后对照，命令表缓存有效，不代表系统重启后的磁盘冷启动。

| 场景 | 修改前 | 修改后 | 测量范围 |
| --- | --- | --- | --- |
| 新会话 `Get-Chi` 首次 Tab | 404–487ms | 158–170ms | 完整配置，首次进入补全菜单 |
| 同会话后续相同补全 | 30–63ms | 30–61ms | 关闭菜单、清行后重新输入 |
| 完整 profile 启动 | 980ms | 936ms | 非交互新进程，重复三次取中位数 |
| `init` | 530ms | 511ms | 新进程，重复三次取中位数；属于 profile 启动的一部分 |

主要原因是共享 Tab 桩原先不区分输入位置，在 `Get-Chi` 等命令名补全前也初始化 argc/carapace。现在只在外部 CLI 参数位置加载，PowerShell 命令名、已加载函数/cmdlet 参数与重定向路径不触发。管道、分号与嵌套命令按光标所在的命令判断；应用程序别名与 `scoop.ps1` 一类外部脚本仍可触发，动态或无法解析的命令保留原有加载入口。回归入口为 [NativeArgumentContext.Tests.ps1](../Init/tests/NativeArgumentContext.Tests.ps1)，pwsh 7 与 Windows PowerShell 5.1 均通过。

另外，CxxuTab 原先按字节再次加载已供 predictor 使用的程序集，进程内出现两份同版本程序集。现在复用同一活件路径已导入的程序集；pwsh 7+ 在 predictor 尚未加载时改用 `Assembly.LoadFrom` 加载活件，稍后 predictor 导入也复用同一程序集与进程内命令表。5.1 仍按字节装载 Tab-only 活件；独立启停与仓库源从不被加载的规则保持不变。EnvVar 补全注册在模块已加载时只枚举本会话命令，独立调用仍保留模块发现行为。

实际交互复验包括 `git --ver<Tab>` → `git --version`、`scoop ins<Tab>` → `scoop install`、`Get-SystemI<Tab>` 菜单摘要。首次外部 CLI 参数补全仍约 434ms，包含一次性注册与 git 补全模块加载；此成本延后到相关场景，没有消失。首次命令名 Tab 仍承担 CxxuTab 导入、读表和摘要的冷路径，强制清缓存会使下次首次补全更慢。

启动诊断中的“体验件全载（-Now）”包含 PSFzf/CxxuTab，因此不能当作首屏 OnIdle 的实际耗时。结构化结果使用 `UxFullLoadMs`；`IdleMs` 为兼容保留同一数值。真实首屏单发只加载 predictor/zoxide，仍在主线程执行，不能据非交互启动报告推断“输入完全无阻塞”。当前初始化主要开销为提示符设置约 148ms、PSReadLine 基础配置约 96ms，未见步骤错误或重复初始化；继续优化应分别测量这些冷路径，不宜直接把它们集中到 OnIdle 或提前导入全部补全组件。

用户侧开关与显式初始化入口见 [Feature-Guide](Feature-Guide.md) 的补全体验件说明；本轮包含命令表共享的双目标 DLL 更新；开发构建后执行 `Sync-CxxuPredictor` 发布，再新开终端生效。只重跑 `init` 或删除缓存不能替换当前进程已加载的程序集。

### 共享命令表与按输入位置加载复验

本轮沿用 pwsh 7.5.4、PSReadLine 2.3.6 和实际 profile。命令名补全在修改前后各开三个真实窗口，每个窗口关闭菜单、清行后再补全两次；路径与 CLI 参数的对照在独立窗口恢复旧版手势桩与 argc 注册函数，使用同一新活件，因而只隔离加载边界与批量注册，不代表整套旧版本。命令表磁盘缓存有效，屏幕轮询分辨率约 10ms；数值会受负载、磁盘缓存与菜单重绘影响。

| 场景 | 本轮修改前 | 本轮修改后 | 结论 |
| --- | --- | --- | --- |
| `Get-Chi` 首次 Tab | 170、171、170ms | 295、172、173ms | 中位数 170 → 173ms，没有证实加速；更新后首个样本较慢 |
| 同窗口重新输入 `Get-Chi` | 32–63ms | 47–63ms | 后续仍明显快于首次；收益不能归因于重复按菜单切换 |
| `./readm` 首次路径 Tab | 109、109、110ms | 61、61、47ms | 中位数 109 → 61ms；新逻辑不导入 CxxuTab，argc/carapace 也未加载 |
| `git --ver` 首次参数 Tab | 669、646、699ms | 617、595、618ms | 中位数 669 → 617ms；新逻辑不导入 CxxuTab，仍有 CLI 注册与 carapace 运行开销 |
| argc 初始化（组件级、各三次） | 中位数 159.6ms | 中位数 154.6ms | 同为 845 个注册名；批量注册仅节省约 5ms，未消除枚举与闭包准备 |

当前完整 profile 启动三次中位数为 1044ms，真实窗口初始化无步骤错误。另一次从临时模块路径加载旧代码的启动对照受到模块发现路径变化影响，不作为速度改善的证据。本轮未增加启动预热或常驻后台任务；首次相关操作仍承担未加载组件的成本。

分段探针在带 profile 的新进程中顺序测得：CxxuTab 导入约 39ms、原生 `Get-Chi` 补全约 43ms、额外模糊查询约 2.4ms、首次摘要装饰约 111ms。这些独立调用包含各自冷路径，**不能与真实按键总耗时直接相加**；它们表明剩余命令名首次延迟主要需要继续审查摘要索引/源码解析与原生补全，而不是重复优化已缓存的模糊匹配。真实菜单 `Get-SystemI` 首次约 267ms、后续 36–40ms，中文摘要正常，`Hardware` 未被导入。

共享表在先注册 predictor 与先触发 Tab 两种顺序下均验证为同一个对象与程序集；Tab 先加载时不隐式注册 predictor。实际窗口等待空闲事件后确认 predictor 从新活件导入，加载错误为空。没有将依赖 `CurrentRunspace` 的建表工作迁到后台线程。命令名、路径、参数、管道、分号、嵌套命令、重定向、禁用开关、失败回落及 argc 的 git 归属、幂等、强制重注册均有回归覆盖；双目标构建无警告、无错误，pwsh 7 与 Windows PowerShell 5.1 的组件测试通过。入口为 [TabGestureContext.Tests.ps1](../TerminalTools/tests/TabGestureContext.Tests.ps1)、[SharedCommandTable.Tests.ps1](../CxxuPredictor/tests/SharedCommandTable.Tests.ps1) 与 [ArgcBatchRegistration.Tests.ps1](../Init/tests/ArgcBatchRegistration.Tests.ps1)。

本轮未引入摘要持久化缓存或启动预热；后续摘要开关的独立测量与取舍见下文。直接把所有导入挪到启动或单发空闲事件只改变等待发生的时间，不能证明总体更快。停用、回落与缓存清理仍使用 [Feature-Guide](Feature-Guide.md) 的既有入口。

### 摘要按需启用复验

沿用 pwsh 7.5.4、PSReadLine 2.3.6、真实 profile 和有效的命令表缓存，在独立传统控制台中输入命令并注入 Tab，按约 10ms 间隔轮询读屏。每个窗口关闭菜单、清行后重输两次，以区分首次调用与缓存后的补全；本轮只切换摘要开关，不提前导入模块。以下是系统持续运行期间的进程内冷路径测试，不代表系统重启后的磁盘冷启动。

| 场景 | 显式开启摘要 | 关闭摘要 | 修改后未设置开关 |
| --- | --- | --- | --- |
| `Get-Chi` 首次 Tab，各三个新窗口 | 270、160、175ms | 149、135、146ms | 266、145、145ms |
| `Get-SystemI` 首次 Tab，匹配未加载模块函数 | 269、256ms | 132、135ms | 144、149、141ms |
| 同窗口重新输入 `Get-SystemI` | 33–43ms | 29–46ms | 28–51ms |

普通命令首个样本仍会出现约 266–270ms 的波动，因此不能承诺每个新窗口都低于 150ms。对未加载模块函数，关闭摘要将首次补全从约 0.26 秒降到约 0.14 秒，减少约 0.12 秒，收益显著；额外复验一对新窗口，默认关闭为 141ms，显式开启为 273ms。相应状态确认加载的是仓库 `CxxuTab` 1.0.7：默认模式没有创建摘要缓存、模块索引或源码 AST 缓存，显式开启才创建模块索引与源码缓存；两种模式均未导入 `Hardware`，`ShowToolTips=True`，没有触发熔断或体验件加载错误。

耗时来自为候选附加摘要前的函数/别名枚举、未加载模块索引、按需解析源码，以及相应首次调用开销；即使当前候选没有可显示的函数摘要，旧默认也会进入装饰分支。`CxxuTab` 1.0.7 改为摘要默认关闭，仅显式 `True`、`1`、`Yes`、`On` 时启用。原生候选、模糊匹配顺序与参数语法提示保持不变；没有新增磁盘缓存、后台任务或启动预热。首次剩余成本仍包括 CxxuTab 导入、命令表读取、原生补全与菜单首次重绘，因此后续相同输入仍明显更快。

当前完整 profile 启动三次中位数为 1072ms，与前轮 1044ms 处于相近量级；本轮不据此声称初始化提速。真实窗口初始化没有步骤错误，摘要开关改变的是首次相关操作的工作量。运行期启停与持久化说明见 [Feature-Guide](Feature-Guide.md) 的「Tab 菜单摘要」；新开终端即可加载新脚本，不需要重新构建或同步 DLL。回归入口 [SynopsisOptIn.Tests.ps1](../CxxuTab/tests/SynopsisOptIn.Tests.ps1) 在 pwsh 7 与 Windows PowerShell 5.1 均通过，覆盖默认不建摘要缓存、非法值关闭、显式开启、中文摘要、原生候选/参数语法和运行期关闭。5.1 另在保留 profile 的真实窗口确认从仓库加载 1.0.7，默认未建立摘要索引，Tab 候选与原生提示正常；其首次耗时不使用 pwsh 7 的数字作为基线。

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
- 计时改为轻量 `[datetime]::UtcNow` 差值，仅 `-Timing` 或 `-InformationAction Continue`（`init -Force -Timing` 走前者）时收集并打印报告。
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
5. ~~**`$profile` 尾部的 `argc/fnm` 钩子**~~——已完成：`argc` 由 `Set-ArgcCompletions` 懒加载，
   `PSCompletions`/`fnm`/`scoop-search` 迁入组件清单（默认关，启用后按组件配置加载），profile 不再保留钩子。
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
  `carapace`/`PSCompletions` 二选一待定、`posh-git`/`fnm` 按需。
- 实现：`TerminalTools.Register-PsUxLazyLoad`，`init` 任务表末步只注册
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

- 新增 `Deploy.Test-PsEnvReadiness`（原名 Test-NewMachineReadiness，新老机器通用故改名）：
  环境 checklist 即代码（必备 7/可选 6/首跑生成物 2，表格 + 备注列（缺时给补法，活件行给版本对比），只读不改机器；
  2026-09-21 加版本/日期列 + 表尾：仓库 commit/日期、pwsh 版本、dll 哈希一致性）。
- 新增 `docs/Deploy-Guide.md`：11 节（缺口检查/pwsh7/git+clone/PSModulePath/profile/第三方模块/
  scoop/python-conda/首次 init/WT 开机/多设备差异/回滚），命令全部核对过签名（宽松风格，直接抄）。
- 附带：edit 工具可能整文件改写换行；本轮 5 文件
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
  后改 VSCode QuickOpen 式模糊（子序列 + 边界/连击打分 + 30 封顶，3000 条 1.2~6.3ms；
  空格多片段 AND 仅 API 层有效，活体里空格分词进参数位、CommandName 门直接空；
  通配符走严格分支回归（`get-*ive` 精确首尾，3000 条 1.9ms；裸 `*` 不放水，残缺括号兜底）；
  同一插件同一张表，不另起（另起要复制门/表/注册，双倍成本）。
- 实现：`PS/CxxuPredictor/`（`src/` 三文件 153 行 + `CxxuPredictor.dll` 7.6KB + `.psd1` 零导出；构建 `dotnet build -c Release`，27s，0 警告）。构建输出在 `src/bin/Release`，仓库件是手工发布（覆盖拷贝；仓库源只会被外置之前的老会话锁定，新会话从不加载）。新增 `CompleteCommand` 公开 Tab 接口后 `src/` 262 行。
  只处理裸命令名 token（参数/路径/`git` 留给 CompletionPredictor，不重叠），
  自匹配排除，30 条封顶，无反馈接口；`OnIdle` loader 里 `-Global` 装载。
- 验证（沙盒）：构建零警告；import 423ms 零错并顶层列出；反射直测过滤逻辑
  （`get-chi`→`Get-ChildItem`、自匹配排除、空前缀排除）；manifest 过；自动发现 OK。
  真机已验证（用户实测通过）：`get-child` 出 `[CxxuCommand]` 来源行，本轮终结。
- 为何编译成 dll（2026-09-21 定论）：两条硬约束。(1) PSReadLine 的 ListView 插件槽只接受 .NET 实现（`ICommandPredictor`），纯 `.psm1` 挂不进去，不用 dll 就没有命令名预测； (2) 预测 20ms 预算：纯 PowerShell 3000 条简单通配实测 22ms（已超，模糊+打分更贵）， C# 版全套 1~6ms。代价（锁/分发/版本门）由并排版本 + 自动化吸收，日常零手工；若不要该功能，退路：`Sync-CxxuPredictor -Uninstall` + 持久化 `PsPredictor='False'`。
- 维护：dll 进仓库（`.gitattributes` 已有 `*.dll binary`，发布件）；活件并排版本 `~/.cxxu/bin/<哈希>/CxxuPredictor.dll` + `current.txt` 指针，loader 按指针装载（旧版照常使用，无警告；只新增目录从不覆盖，同步不受锁限制）；运行时加载的是 dll 二进制， `.cs` 只是图纸，改逻辑重构建后执行 Sync 分发；psd1 无 RootModule（防按名误装空壳）但诚实声明 `PowerShellVersion='7.5'`；net8.0 单目标实测不可行：本机 7.5 的 SMA 自带 System.Runtime 9 引用（CS1705），覆盖 7.4 需 7.4 的 SMA 或 PowerShellStandard（缺预测 API），暂不做；卸载用 `Sync-CxxuPredictor -Uninstall`； `Sync-ModuleManifest` 天然跳过（无 `.psm1`）。
- 边界（已读源码 `CompletionPredictor.cs` 核实，不再是文档推测）：`GetSuggestion` 遇到 `TokenFlags.CommandName` 直接 `return default`（源码注释：command discovery 太贵，跳过），只做非命令位置（参数/路径/成员）+ `git` + `% ? cd dir foreach where` 白名单。所以**命令名前缀（如 `get-child`）它永远沉默**，用户只看到历史是必然的，不是坏了。原生 PSReadLine 没有“TabExpansion 边输边弹”；predictor 须 20ms 内返回（官方硬性），慢同步的命令发现塞不进这个预算。更重的悬浮面板类另见 `Feature-Guide.md §7`。（2026-11-07 补注：命令名候选现已由自研 `CxxuCommand` 提供，本条只说明 `CompletionPredictor` 的边界。）
- 后续：同日用户拍板删除 `Deprecated` 模块（转正后归档无存在必要，零调用），`git rm` 整目录；上表作为历史记录保留，53 模块现数见 §2/§6。

## 21. 第十四轮：首屏输入卡顿分片 + 用户自查工具（2026-09-22，用户报“启动后 1~2 秒打字滞后”）

- 排查（沙盒 VM，冷进程实测）：裸启动 201~211ms；全 profile 848~907ms（profile 税约 650ms =
  conda 缓存 + `init` 416~442ms，步骤头两名 `Set-PsPrompt` 136~139 + `Set-PSReadLinesCommon` 87~90，
  都是 core 变量/别名与 PSReadLine 选项，无大头可砍）；**首屏 OnIdle 整包约 944~1031ms**
  （`ListAvailable` 探测 71 + PSFzf 238~299 + predictor 380~421 + CxxuTab 276~281 + zoxide 15~20，
  全跑在主线程）——prompt 出现后用户立刻打字，PSReadLine 要等整包跑完才处理输入，
  即“看得见、打不动”的 1~2 秒。
- 修法（`TerminalTools.Register-PsUxLazyLoad`，manifest 不动）：整包改**分片队列**
  （PSFzf→zoxide→CxxuTab→predictor，最重的 predictor 压轴，压轴前 History+CompletionPredictor
  照常供稿），一次 OnIdle 只跑一片，片间引擎处理 pending 输入，打字即回显；队空才摘订阅
  （旧语“触发即摘”作废）；单片失败只记 `$global:PsUxLoadErrors` + Verbose，首屏不刷屏；
  全关（四开关）= 不注册；`-Now` 按序全跑（立测通道不变）。附带省一次扫描：
  PSFzf 去掉 `Get-Module -ListAvailable` 预探测（71ms），直接 import、装上才绑和弦。
- 用户自查：`Init.Test-StartupPerformance [-Repeat 3] [-Detail]`（init 旁边，缺 pwsh 时警告退出，
  5.1 安全）。全新进程分段：裸/profile 税/init 合计+`init -Timing` 原表+idle 合计/
  `-Detail` 四片各测/prompt 5 次均值，文末打印四开关与本会话队列状态并给阈值结论
  （profile 税>1200/init>800/idle>800/prompt>0.3s）。沙盒首跑：201/848/442/944/prompt 0.06s，
  结论仅 idle 一条（VM 值，真机按比例）。
- 验证：双版本解析零错（5.1 侧禁三元/`??`，已守）；`Test-StartupPerformance -Detail` 全绿；
  `-Now` 四件齐（PSFzf/CxxuTab/predictor 顶层列出、`z` 为 Function，ERRS=0）；
  事件分片逻辑与旧“标记位防记账”同机制（$global 队列在动作内可见），
  真机 idle 逐片触发效果以用户首屏打字手感为准。
- **回滚（2026-09-22，用户报“第二条命令卡顿甚至假死、第一条回不来提示符”）**：分片是回归。
  机理——PSReadLine 行编辑等待按键时引擎算 idle，`OnIdle` 照样触发；常驻订阅熬过首屏后，
  第 2~4 片随机砸在“命令刚跑完/正在打字第二条”的当口，主线程一冻几百毫秒到数秒
  （用户机器比沙盒慢，dll/AV 扫描再放大），键吞掉、屏不刷，看着就是卡死/回不来。
  旧单发逻辑“首屏跑一次、跑之前先摘订阅”当时看似安全（用户还没开始打字）；
  2026-11-09 更正：动作内 `Unregister-Event` 会自锁，见 §28。
  处置：`TerminalTools.psm1` 整文件 `git checkout HEAD` 精确回滚（diff 为空实锤），
  分片代码一个字不留；`Test-StartupPerformance` 的队列状态行同步改回单发口径。
  教训：OnIdle 动作=主线程同步执行，“分片让出”是个错觉——让出的是动作之间的缝，
  但每片该冻还是冻，且触发时机不可控。以后延迟加载只两条路：单发整包（可预测的一次），
  或手势按需（Ctrl+T/R 首按、首个 Tab 才装，可预测的归因）；常驻订阅逐片喂不许再用。

## 22. 第十五轮：手势按需（2026-09-22，用户拍板执行“优化 3”）

- 设计：后台冻结全消，成本挪到用户手势上（可归因）。`Install-PsUxGestureStubs`
  （新导出，幂等）：Ctrl+T/R 和弦桩（毫秒级，首按才 Import-Module + 绑原生，
  本次按键直接调 PSFzf 导出函数 `Invoke-FzfPsReadlineHandlerProvider/History`，
  2.7.10 已核实导出；无 PSFzf 的机器记 `$global:PsUxNoPSFzf` 之后零开销）与全局
  `TabExpansion2` 桩（原函数存 `$global:PsUxTabOriginal`；首个 Tab 先恢复原函数再装
  CxxuTab——它会把“当前”TabExpansion2 存为 `__CxxuTabOriginal` 再包，包到桩上即无限递归，
  然后转交新包装；装失败时原函数已恢复，直接透传）。predictor dll + zoxide 仍首屏
  单发（2026-11-09 起改为 `-MaxTriggerCount 1` 自动退订，见 §28；预测是被动显示等不及手势，zoxide 20ms 搭车）。
  `-Now` 全载四件不变；`Enable-PsPlugin Fzf/Tab` 改为立装桩即时生效（7+ 才调安装器）。
- 联动：Deploy 就绪检查认桩（Tab 看 `__CxxuTabOriginal`/`PsUxTabOriginal` 三态，
  PSFzf 看模块/`$global:PsUxFzfStub` 三态）；`Test-StartupPerformance` 文案同步单发口径。
- 验证（沙盒）：双版本解析零错；Tab 桩全流程——装桩（原函数捕获）→首 Tab 519ms 自动装
  CxxuTab（29 候选含 `Get-ChildItem`，dll 模糊已合并，无递归）→次 Tab 28ms 直走包装→
  非命令位透传（`-Path` 在）→`$Error` 零污染；PsTab 默认关（不装桩、默认 Tab 原样），置 True 才启用（2026-11-07 起改为默认开，见 §26）；
  重复安装幂等（包装激活后不再重装桩，原函数不被覆盖）；和弦桩重定向下零污染；
  `-Now` 四件齐 ERRS=0。真机待验：首按 Ctrl+T/R、首个 Tab 的一次性耗时手感。

## 23. 第十六轮：CxxuCommand 排序重做与补全栈定位（2026-11-06，用户报“模糊提示策略不好”）

- 触发：用户开头贴出 `Deploy-CompletionStack` 的 fzf/zoxide 警告后说明——补全插件里只重视 CxxuCommand，但当前提示策略不好。实测旧算法确认：`gci` 首条是 `gcim`、`Get-ChildItem` 掉到第 18；`ls` 前 30 条没有 `Get-ChildItem`；`sel` 被 `Set-*` 混排；单字母 `s`/`x` 灌满 30 条无关命令。
- 根因：单一加权分（命中 +1、边界 +2、连击 +2、间隔与起始扣分）没有硬分层，长度做次键导致短名乱插队；无别名映射与使用频率；固定 30 条且无质量门槛。
- 新排序（层级优先；同层先比匹配质量，再比历史频率，最后长度与字母序）：
  别名精确（`ls`/`gci`/`ps` → 目标命令；目标名与别名可能没有共同子序列，必须先判）→
  完整前缀 → 词边界子序列/首字母（`gci` → Get-ChildItem）→ 从词边界起的连续片段（`chitem` → Get-ChildItem）→
  一般子序列（不设跨度门槛；命中 +2、词边界 +6、连击 +4、间隔按长度扣分，`groute` → `Get-NetRoute`）。
  单字符只认前缀；打全名（非别名）时返回空，参数交给 CompletionPredictor。
  不做层级裁剪——用户要的是“排序好”，不是“只留一条”。
- 别名与频率：`Get-Command` 一次取 Name/CommandType/Definition；别名本身也作为候选（`gci` 能列出 `gcim`，即使该模块未导入、Definition 为空也保留名字），有 Definition 的别名再归并到目标并参与精确命中加权；读 PSReadLine 历史尾部 5000 条统计首个 token（最近 300 条加权 4），别名调用计入目标，权重封顶 20。历史默认路径先直接猜（省约 80ms 的 `Get-PSReadLineOption` 调用），默认文件不存在才回退查询。
- 条数与性能（本机 2633 条候选，pwsh 7.5.4）：predictor 默认 15 条，Tab 仍按 `maxResults`；建表含历史读取 151ms，按键过滤 0.03~0.58ms。
- 实测（新）：`gci`→Get-ChildItem、gcim、Get-CimInstance…（15 条）；`ls`→Get-ChildItem、ls_eza…；`gi`→Get-Item、gin、gip、git*；`ps`→Get-Process、ps_group；`gp`→Get-ItemProperty、gps、gpv；`sel`→Select-* 占头部；`gcm`→Get-Command、gcms、gcmw；`get-chi`→Get-ChildItem 系在前；`get-childitem`→空；`s`/`x` 不再灌无关命令。
- 中途修正一（同日）：第一版把“别名命中只留前缀、前缀命中丢掉子序列”做成硬裁剪，`gci` 只剩 Get-ChildItem 一条，用户指出“用户写 gci 也可能不只匹配 Get-ChildItem”。撤掉裁剪、把别名纳入候选、候选数 8→15 后恢复广度。
- 中途修正二（同日）：第二版把一般子序列卡在“长度 ≥4 且最大间隔 ≤4”，`groute` → `Get-NetRoute` 这类跨词连写被误杀（用户当日报回退）。撤掉跨度/间隔门槛，只保留“单字符只认前缀”，弱匹配交给间隔扣分沉底。
- 召回核对（旧 vs 新，同一台机、同一无配置会话）：`groute`/`grou`/`route`/`gchil`/`getchild`/`gmod`/`gwmi`/`gnr`/`gr`/`get-chi`/`chitem`/`rem-it`/`new-it` 等旧首条仍在新结果中，旧前 5 条多数 4~5 条保留；差异集中在别名场景（`gci`/`ls`/`gi`/`ps`/`gp`/`gcm`/`gc`），新排序把别名目标提到第一，属预期改进。

- 补全栈定位：`Deploy-CompletionStack` 改为先同步 CxxuCommand 活件（核心），PSFzf/CompletionPredictor 与 fzf/zoxide 标为可选；缺二进制合成一行提示，不再逐条 `Write-Warning`。
- 发布：`dotnet build -c Release -p:SmaPath=...` → 覆盖 `PS/CxxuPredictor/CxxuPredictor.dll` → `Sync-CxxuPredictor`；重开终端生效（dll 锁随进程）。

## 24. 第十七轮：argc 静态参数提示（2026-11-07，用户问“argc 能否像 CxxuCommand 一样自动提示”）

- 触发：argc 目前 Tab 唤醒；用户问能否接进 CxxuCommand 的自动 ListView，以及是否推荐。
- 结论：可以结合，但不建议把 argc 全量塞进每键预测；落地为同 dll 的第二个 predictor `CxxuArgcFlags`（静态 flag 表）。
- 管线差异：`CxxuCommand` 只处理 `TokenFlags.CommandName`；argc 是 `Register-ArgumentCompleter -Native`，只在 `CommandCompletion`/Tab 生效；PSReadLine 的自动提示只接受 `PredictiveSuggestion`（整行文本 + tooltip），没有自动开菜单的 API。
- 关键实测：`CompletionPredictor` 在私有 runspace（`InitialSessionState.CreateDefault`）里调 `CommandCompletion`，看不到会话注册的 argc；`Get-ChildItem -F`→4、`nginx -`→0、`docker --con`→0、`nginx -s r`→4 个文件名（回退）。走完整补全调用的每键成本：`nginx -` 16–18ms、`docker --con` 57–70ms、`git ch` 84–184ms、`git checkout ` 83–135ms（预测预算约 20ms）。
- 方案：解析 `completions/*.sh` 顶层（遇 `# {{` 即停）的 `@flag/@option` → `~/.cxxu/cache/argc-flags.tsv`（30,769 行 / 1.9MB）；只做“首个参数位 + `-` 前缀”，字典查表 + 前缀过滤 <1ms，不启动进程。别名 flag 分别入表（`-p`/`--paginate`），去重键区分大小写（`-v`/`-V`、`-t`/`-T` 都保留）。
- 性能：dll import（含 CxxuCommand 建表 + flag 表加载）本机 150ms（缓存热）；冷建表约 100ms、热读表约 30ms，都在 OnIdle 单发里；预测调用 0–4ms（首调 JIT）。
- 范围：只解析顶层 flag，子命令 flag 与动态值（分支/容器/文件）仍走 Tab；5.1 无预测视图，维持 Tab-only。
- 验证（新 dll，pwsh 7.5.4）：`nginx -` 10 条、`docker --con` 2 条、`git -` 10 条、`git checkout -` 0、`Get-ChildItem -F` 0、`nginx -s reload` 0、`nginx.exe -`/`NGINX -`/管道/`&` 均命中、`PsArgc=False` 0、表过期自动重建。
- 发布：`dotnet build -c Release` → 覆盖 `PS/CxxuPredictor/CxxuPredictor.dll` → `Sync-CxxuPredictor`（哈希 `F57A131B`）；重开终端生效。

## 25. 第十八轮：5.1 Tab-only 构建（2026-11-07，用户问“CxxuCommand 能否适配 PowerShell 5.1”）

- 结论：内联预测不能，Tab 补全可以。5.1 的引擎是 SMA 3.0，没有 `System.Management.Automation.Subsystem.Prediction`，`ICommandPredictor` 注册不了；装 .NET 9 也不会改变 5.1 固定在 .NET Framework 4.8 CLR 的事实（实测加载 net9 dll 取类型即报 `System.Runtime, Version=9.0.0.0` 找不到）。
- 构建：`CxxuPredictor.csproj` 在 Windows 上多目标 `net9.0;netstandard2.0`；`netstandard2.0` 定义 `PS51`，同一份 `CxxuPredictor.cs` 条件编译去掉 `ICommandPredictor` 实现，只保留 `CompleteCommand`，引用 5.1 的 GAC SMA。产物 `PS/CxxuPredictor/ps51/CxxuPredictor.dll`（12KB）。
- 分发：`Sync-CxxuPredictor` 同时发布 `~/.cxxu/bin/<哈希>`（net9）与 `~/.cxxu/bin/ps51/<哈希>`（5.1 Tab）；根目录回收时保留 `ps51`。`CxxuTab` 在 5.1 只读 `ps51` 指针，按字节装载（不锁文件），7+ 仍读根活件。
- 启动：`Register-PsUxLazyLoad` 在 5.1 只装 CxxuTab 手势桩，首个 Tab 才导入模块并建表；`Enable-PsPlugin Tab` 在 5.1 直接导入，二者都不给启动加负担。
- 验证（5.1.26100 / .NET Framework 4.8）：`get-chi`、`gci`、`ls`、`get-*item`、`get-netr` 均返回；接 CxxuTab 的 `TabExpansion2` 合并 27 条；冷启动约 380ms（建表），之后约 1ms；2026-11-07 加命令表缓存后建表约 20ms（见 §26）。7.5 的 net9 构建回归通过（`ICommandPredictor` 可赋值、`CompleteCommand` 正常）。
- 边界：5.1 只有 Tab 菜单，没有边输边弹的 ListView；内联预测需 pwsh 7.2+（本仓库现成 dll 要求 7.5+）。

## 26. 第十九轮：Tab 补全默认开 + 命令表缓存（2026-11-07，用户要求“默认启用 tab 补全”）

- 历史顾虑核对：早期“卡顿/假死”的实锤是 §21 的 OnIdle 分片回归（常驻订阅砸在第二条命令上），已回滚；CxxuTab 自身只在按键时同步执行，不会在后台冻主线程。默认关是当时的保守选择，不是遗留缺陷。既然按 Tab 的代价可控，改为默认开。
- 门控统一：`PsTab` 与 `PsFzf`/`PsZoxide`/`PsPredictor` 同风格——**未设 = 开，显式 `False`/`0`/`No`/`Off` = 关**。改到 `CxxuTab` 包装、`Install-PsUxGestureStubs`（桩与桩内判定）、`Register-PsUxLazyLoad`（5.1 `-Now`、`$pieceTab`）、配置模板、`doctor` 门控行。
- 首 Tab 提速（实测）：命令表建表 5.1 约 373ms、7 约 104ms，来自 `Get-Command -CommandType Function,Cmdlet,Alias`；新增磁盘缓存 `~/.cxxu/cache/tab-commands-<CLR主版本>.tsv`（`C` 行存真实命令、`A` 行存别名及目标），命中后建表部分两项都是 **19ms**（CxxuTab 模块导入本身另约 80~90ms），预测器 import 从 124ms 降到 10ms。
- 缓存失效：宿主不符（`Environment.Version`/`BaseDirectory`）、超过 24h、文件损坏/只有表头时现建并回写；`Definition` 只对别名取（7 约省 24ms）。代价：新装模块的模糊候选最多晚 24h 生效（原生 Tab 仍可补），删缓存文件可立即强制重建。
- 自熔断：包装内单次 dll 调用超过 800ms 或抛异常，则本会话置 `$global:__CxxuTabFuse`，之后纯透传——异常主机/杀软扫描不会每次 Tab 都冻结；重复 `Import-Module -Force` 不再重载程序集/重建表。
- 验证：5.1/7 冷热两轮候选列表逐条一致；损坏/过期/截断缓存均触发重建且回写无 BOM；5.1 `TabExpansion2` 合并 27 条、7 合并 29 条；双版本解析/导入/`Test-ModuleManifest` 全绿。



## 27. 第二十轮：macOS 启动基线（2026-11-08，用户报“pwsh 加载太慢”）

- 测量环境：macOS 27.2（26B123）、Apple Silicon、pwsh 7.6.9、PSReadLine 2.4.5；`median` 取 n=12 次独立进程。裸启动 305ms，完整 profile 优化前 **1524ms**。
- 分项实测（均为冷进程，含 305ms 裸启动基线）：`Confirm-EnvVarOfInfo` 421ms、conda/mamba hook 254ms、`argc --argc-completions` 整包注册 250ms、`Set-PsPrompt` 153ms、`Set-PSReadLinesCommon` 101ms、`Set-ArgumentCompleter` 54ms；`init` 步骤表合计约 469ms，另有模块导入等约 200ms 不在步骤计时内。
- 四处贵项都有明确成因。`Set-EnvVar` 每次走 User 作用域持久化，本机单次约 105ms，`Confirm-EnvVarOfInfo` 连调四次；非 Windows 分支调 `Get-WindowsVersionInfoOnDrive`，macOS 下要 spawn `sw_vers` 三次、`sysctl`、`uname` 各一次，合计约 197ms；conda hook 的真实成本是 `Import-Module Mamba.psm1`（约 226ms），生成 hook 文本本身只有 163 字节；argc 整包注册里 `argc` 二进制只占 3.8ms，其余是 PowerShell 解析并执行数百个 `Register-ArgumentCompleter`。
- 处置：`Confirm-EnvVarOfInfo` 新增 `Set-StartupInfoEnvVar` 分流——Windows 保留原 `Set-EnvVar` 的 User 级持久化（外部程序可能读 `%scripts%`），非 Windows 改 `Set-ProcessEnvVar`（这些值在 macOS 上没有跨进程消费者）；非 Windows 的 `OSCaption`/`OSFullVersionCode` 改用引擎已算好的 `$PSVersionTable.OS`，不再 spawn；用户 profile 删掉 `init` 之前那次重复的 `Set-PsPrompt`（步骤表里已有）；删掉 profile 里的 argc 整包注册，统一交给 `Set-ArgcCompletions` 的 Tab 桩懒加载；本机 `profile.ps1` 的 mamba hook 改为首次调用 `mamba` 才 `Import-Module`（当日后续整块移除，见下一条）。
- 结果：完整 profile 从 1524ms 降到 **972ms**（n=12，median），约减 36%。剩余构成为裸启动 305ms 加 `init` 实测约 670ms（其中步骤表 469ms、模块导入约 200ms）。
- 行为变化：非 Windows 上 `OSCaption` 与 `OSFullVersionCode` 的值由原来的 `macOS 27.2`、`27.2-26B123` 统一变为 `macOS 27.2.0`（`$PSVersionTable.OS` 原样）；两者只作展示，macOS 的 prompt 不读取。mamba 的环境变量仍在启动时设置，`mamba activate`/`deactivate` 在首次调用时可用，prompt 环境前缀也随首次导入生效。
- 验证：`mamba --version` 输出 2.5.0 且 `Invoke-Mamba` 按需出现；`Initialize-ArgcCompletions` 后 `$global:PsArgcLoaded=True`；`init -Timing` 显示 `Confirm-EnvVarOfInfo` 从 421ms 降到 26ms，`Set-PsPrompt` 129ms、`Set-PSReadLinesCommon` 94ms。
- 后续（同日）：用户停用 mamba/conda，两处 shell 集成整体移除。`~/.config/powershell/profile.ps1` 清空并留迁移注释；`~/.zshrc` 的 `conda initialize` 块删除（备份为 `~/.zshrc.bak.<时间戳>`），zsh 交互启动从 1485ms 降到 914ms。miniforge 安装保留，`conda`/`mamba` 仍在 `/opt/homebrew/bin`，但 `conda activate` 需重新执行 `conda init zsh` 才可用。两个文件都不入仓库，换机需另配。接线与恢复步骤见 [macOS-Shell-Setup.md](macOS-Shell-Setup.md)。
- 边界：`init` 剩余步骤（`Set-PsPrompt`、`Set-PSReadLinesCommon` 等）未动，单项都在百毫秒级，继续压缩需要拆 core 变量与别名导入，收益小于改动风险。zsh 侧剩余约 910ms 与 mamba 无关，是 omz/补全等其它初始化，未在本轮范围内。

## 28. 第二十一轮：OnIdle 单发自锁（2026-11-09，用户报“首条命令输入假死、任何键无反应”）

- 现场：卡住的 pwsh 存活、CPU 0%，ttys 处于 raw 模式，`FIONREAD` 读到输入队列里堆着
  用户敲下的 110 字节（字母、退格、ESC、Ctrl+C、回车）。终端已把按键全部送达，是 pwsh 没在读。
- 线程栈（`sample` + `DOTNET_PerfMapEnabled` 还原）：`PSConsoleReadLine.ReadKey()` 里
  的 `PowerShell.Invoke()` 正在执行事件动作，链路是 `PSEventJob.Invoke` →
  `UnregisterEventCommand.ProcessRecord` → `PSLocalEventManager.UnsubscribeEvent` →
  `DrainPendingActions` → `Thread.Sleep`。`DrainPendingActions` 等的是“当前正在执行的
  这个动作”自己，形成自锁；期间 PSReadLine 的 ReadKey 停摆，按键只能堆在 tty。
- 触发条件：`TerminalTools.Register-PsUxLazyLoad` 的单发动作第一句是
  `Unregister-Event -SourceIdentifier PowerShell.OnIdle`，在动作内部自摘订阅。
  与 Tab 补全、CxxuTab/CxxuPredictor 无关。
- 最小复现（`profile.ps1`，pwsh 7.6.9 / macOS 27.2）：同一源注册两次、动作里自摘。
  首屏出现后即卡死；只注册一次不复现，说明死锁还需要“该订阅另有待执行动作”：

  ```powershell
  $a = { Unregister-Event -SourceIdentifier PowerShell.OnIdle }
  Register-EngineEvent PowerShell.OnIdle -Action $a | Out-Null
  Register-EngineEvent PowerShell.OnIdle -Action $a | Out-Null
  ```
- 上游已知：PowerShell/PowerShell#16154（2021 年报告，因长期无活动被自动关闭，未修复），
  其中已指出“`Unregister-Event` 调用时若还有其他事件待处理就会挂起”。本次补充的是交互式后果：
  事件动作由 PSReadLine 的 `ReadKey` 触发，管线线程被 `DrainPendingActions` 占住后，
  整个终端的按键都不再被读取。
- 修法：动作内不再调 `Unregister-Event`；注册改用
  `Register-EngineEvent PowerShell.OnIdle -MaxTriggerCount 1`，由事件管理器在动作结束后
  自动退订。`$global:PsUxOnIdleRegistered` 标记位保留，继续承担幂等判断。
- 验证：`-MaxTriggerCount 1` 在 pwsh 7.6.9 实测只触发一次且订阅自动消失；改后首屏仍会
  加载 predictor/zoxide，`Get-EventSubscriber` 无残留。
- 排查工具：`python/pwsh_hang_capture.py`。交互 shell 启动前设
  `DOTNET_PerfMapEnabled=1`，卡住时用 `sample` 采样并按 `/tmp/perf-<pid>.map` 还原
  托管方法名；同时读取 tty 输入队列深度。

## 29. 第二十二轮：carapace 首个 Tab 懒加载（2026-11-10，用户要求“加载优化”）

- 现场：macOS、carapace-bin 1.8.2、`PsCarapace=True`；`Test-StartupPerformance` 显示
  `Initialize-Carapace` 216ms，是 init 步骤表最大单项。
- 成因：`carapace _carapace powershell` 生成约 108KB 脚本，注册 1486 个命令名（含 `.exe`
  变体），启动阶段必须解析并执行；与用户是否马上按 Tab 无关。
- 处置：新增 `Register-CarapaceLazyLoad`，init 只计算排除项并注册首个 Tab 桩；
  `Initialize-Carapace` 保留为实际加载函数，`Enable-CxxuComponent -Now` 走清单新增的
  `InitNow` 立即加载。argc 与 carapace 共用 `Register-CxxuTabStub` 安装的同一个
  Tab 桩；两者同开时桩内先加载 carapace、再注册 argc。
- 结果：同机 `Test-StartupPerformance` 的 init 从 757ms 降到 558ms，profile 从 1324ms
  降到 1121ms；`Register-CarapaceLazyLoad` 约 8ms。首次 Tab 一次性约 254ms，之后正常。
- 行为变化：`$global:PsCarapacePending=True` 表示等待首次 Tab；
  `$global:PsCarapaceLoaded=True` 表示已加载。直接调用 `TabExpansion2` 不触发 Tab 桩，
  验证前需先按一次真实 Tab 或执行 `Enable-CxxuComponent Carapace -Now`。加载失败会摘下
  Pending，不在后续 Tab 重复告警。
- 5.1：把 `CARAPACE_SHELL_*` 名称列表改为加载一次并落盘缓存（见 §32），函数名截断到
  30,000 字符；调用改走 .NET `Process`（`StandardOutputEncoding=UTF-8`，保留空字符串参数），
  避免环境变量超长、中文乱码与空参数丢失；候选描述去 ANSI。首次 Tab 约 0.4–0.6 秒
  （冷缓存约 1 秒），之后约 0.1–0.4 秒。
- 边界：`PSCompletions`/`fnm`/`scoop-search` 保持原加载方式；默认关闭，启用后仍按组件
  清单加载。carapace 首次 Tab 的 0.2–0.3 秒（5.1 约 0.4–0.6 秒）是功能成本，不摊到每个
  会话启动。

## 30. 第二十三轮：启动链审计、计时口径与 conda prompt 边界（2026-11-10）

- 审计范围：`init` 的固定步骤、组件清单生成的步骤、`Set-PsPrompt`/`Update-PwshEnv*`/
  `Update-PwshVars`、argc/carapace/git-completion 的装载入口，以及 `p` 的嵌套进程路径。
- 修掉的逻辑与重复：
  - `Set-PsPrompt` 首次执行会经 `Update-PwshEnvIfNotYet -Mode core` 回调自身，导致
    prompt、core 别名和 `LastUpdate` 各执行两遍。改为直接检查 `Test-PsEnvMode -Mode core`
    后调用 `Update-PwshVars -Core`，不再回调。
  - `Update-PwshEnvIfNotYet -Mode Env` 在 `Update-PwshEnv` 已刷新 prompt 后又调一次
    `Set-PsPrompt`；改为 Env 分支只由 `Update-PwshEnv` 负责，core/Vars 分支才补 prompt。
  - `Update-PwshVars` 全量导入后原先仍停留在 `PsEnvMode=1`，`Test-PsEnvMode -Mode Vars`
    永远为假，`Update-PwshEnvIfNotYet -Mode Vars` 每次调用都重复导入全量变量。现在全量
    导入标记为 2，`-Core`/`-Fast` 保持 1，已有更高级别时不降级。
  - `Set-PSReadLinesCommon` 先把 Tab 绑到 `Complete`，下一行又改成 `MenuComplete`；
    删除这次无效绑定。`Set-PsExtension` 默认关闭时 init 直接跳过，不再为 no-op 导入
    PsEnv 模块；`Confirm-DataJson` 只在 Balance/Brilliant 等使用 IP 的主题执行。
  - `Set-ArgcCompletions` 原先在 `PsArgc=False` 时仍会写 `ARGC_COMPLETIONS_ROOT`/PATH；
    现在关闭即返回，不再改环境。`Initialize-Carapace` 的提前返回路径会清掉
    `PsCarapacePending`，避免禁用后每次 Tab 重复做开关/路径检查。
  - `init` 的 `$global:PsInit` 改为在步骤表构建完成后才置位：前置阶段失败时仍可重试。
    重复调用 `init` 不再打印 `initing...`；`Init work loaded` 与
    `confrim pwsh extension functions` 不再强制 `-Verbose` 输出。
  - `promptx` 增加原 prompt 缺失/执行失败的守卫。原实现直接 `& $originalPromptScript`，
    在 `prompt` 被移除或宿主未定义时每次渲染都会抛
    “expression after '&' ... was not valid”。
- 计时口径：
  - `init` 的 `Environment Loading time` 主数字是 `total`（从函数入口到初始化收尾），括号内
    为 `prep + steps + other`，三项按定义严格等于 `total`：`prep` 含配置读取、变量重载与
    步骤表构建；`steps` 只含步骤循环（含进度条渲染）；`other` 是循环前后的计时、环境等级
    恢复与进度条收尾开销。`init -Timing` 的步骤表另给 `Share` 与“步骤合计”行，合计只表示
    各步骤自身耗时之和，与 `steps` 的差额是循环内未被单步计时的开销，不参与上面的拆分。
  - `Test-StartupPerformance` 输出按耗时降序的因子对象，列 `Category`/`Name`/`Ms`/`Share`/`Note`，
    可接 `ft`/`fl`；因子包含 `bare`、`Init 模块导入`、`conda/其他 profile`、`init 准备/收尾`
    与各 init 步骤。`bare`、`profile`、`init`、`idle` 都按 `-Repeat` 取中位数。`idle 全载`
    是启动后首屏一次的成本，不计入 `profile`。日常只关心“新开一个 pwsh 要多久”时用
    `-Simple`（默认一次，支持 `-Repeat` 取中位数）。
- 同机复测（macOS，一次采样，数值随负载抖动）：
  `bare 328ms`、`profile 1051ms`、`profile 税 723ms`、`init 497ms`、
  `profile 其他 226ms`、`idle 全载 529ms`；对比第二十二轮的 `init 564ms`/`profile 1122ms`。
  `init -Timing` 步骤表前三名为 `Set-PsPrompt 134ms`、`Set-PSReadLinesCommon 89ms`、
  `Set-ArgumentCompleter 43ms`，步骤合计约 364ms。
- 仍偏贵的项：`Set-ArgumentCompleter` 的 43ms 主要花在
  `Get-Command -Module EnvVar` 的模块发现，不是注册本身；`Set-PsPrompt` 的 134ms 与
  `Set-PSReadLinesCommon` 的 89ms 多为首次模块/PSReadLine 初始化。继续压缩需要把
  EnvVar 补全注册或 PSReadLine 初始化改成就绪后/首用触发，会增加桩与失败路径，本轮未做。
- conda 与嵌套加载：
  - 用与 conda 相同的 prompt 包装器（保存原 prompt、按 `CONDA_PROMPT_MODIFIER` 写前缀）
    实测两种顺序：包装器在 `Init` 之前（`promptx` 捕获并执行它）或在 `init` 之后
    （包装器重命名当前 `prompt` 为备份再包一层）。两种情况 `prompt` 都能正常返回，
    `(base)` 前缀保留，没有递归或异常。未在本机实际执行 conda 模块（当前 profile 已
    移除 mamba/conda hook），结论按上游 `Conda.psm1` 的 prompt 契约复现。
  - `promptx` 只丢弃原 prompt 的返回值，不屏蔽其 `Write-Host`，因此 conda 的
    `CONDA_PROMPT_MODIFIER` 仍会显示；原 prompt 缺失或抛错时现在静默降级为不执行它。
  - `p` 启动的是新进程，只继承环境变量，不继承 `$global:PsInit`/`$global:PsEnvMode`；
    子进程会重新执行 profile + init。实测嵌套后 PATH 未新增重复项（父进程原有的重复项
    保持不变），`ARGC_COMPLETIONS_ROOT` 与开关正常传递。
  - 边界：如果 conda 在同一会话用 `Import-Module Conda.psm1 -Force` 重载，上游
    `Rename-Item Function:\prompt CondaPromptBackup` 可能因目标已存在而报错；这是 conda
    自身的重入限制，不是 `init` 路径。需要换 prompt 底时按 Prompt 模块注释先
    `Remove-Variable global:__CxxuOriginalPrompt` 再重载 Prompt。

## 31. 第二十四轮：启动器与 init 幂等判据（2026-11-11，用户报“双重初始化”）

- 现象：`$profile` 里只写 `init`，新开终端连续打印两次 `initing...` 与两行
  `Environment Loading time`（353ms / 386ms），之后才出现提示符。
- 定位（进程树，创建时间 08:19:43 / 08:19:45）：

```text
WindowsTerminal.exe
└─ pwsh（scoop shim）  "pwsh -noe -c p"
   └─ pwsh             "-noe -c p"   → profile → init（第 1 次）
      └─ pwsh          "-NoLogo"      → profile → init（第 2 次，真正的交互 shell）
```

- 根因：`e51aa26` 重写了 `p` 的语义。旧实现是“当前会话已初始化（`$PsInit` 非空）就
  直接返回，否则 `pwsh -noe -c init`”；新实现固定为 `pwsh -NoLogo`，即永远新开进程。
  启动器若仍写 `pwsh -noe -c p`，外层 profile 先 init 一次，`p` 开的子进程再 init 一次。
- 同一提交已把 `Config/wtConf.json` 里的两处 `pwsh -noe -c p` 改成 `pwsh`。本机运行中的
  WT 的 `settings.json` 是指向该文件的符号链接，没有感知目标文件更新，新 tab 仍按旧命令
  启动；改 `wtConf.json` 后要完全退出并重启 WT（见 `Deploy-Guide.md` 的 WT 一节）。
- 幂等判据（现行决策）：
  - 用进程内 `$global:PsInit` 判断“本进程是否跑完 init”，在步骤表构建完成后置位；
    同一进程重复调用直接 no-op（`-Verbose` 显示 `Init work loaded !`），`init -Force`
    才是强制重跑入口。标记放在步骤表构建之后，前置阶段失败时仍可重试。
  - 不用 `$env:PsInit`：子 pwsh 会继承环境变量，但函数、别名与 prompt 不会继承；子会话
    会误判为已初始化而跳过 init，变成没有环境定义的残废会话，该变量还会泄漏给其他子进程。
  - 如果将来确实需要跨进程判断，可把环境变量写成 `$env:PsInit = $PID` 并与当前 PID 比较
    （子进程 PID 不同，照常重跑）；当前无此需求，不引入。
  - 与 init 门分离的状态：`$global:PsEnvMode` 记录变量导入等级（core/Vars/Env），负责
    懒加载逐级补齐；`$global:PsInitStepErrors` 记录本次步骤失败；组件另有
    `PsArgcLoaded`/`PsCarapaceLoaded`/`PsGitCompletion` 等标记。
- 结论：嵌套 pwsh 重跑 init 是设计边界，不是重复执行缺陷；跨进程无法也不应该去重。
  启动器只写 `pwsh`，`p` 留给已开的会话新开窗口。验收看“每个 pwsh 进程恰好一行
  `initing...`”，并用 `Get-CimInstance Win32_Process` 确认新 tab 不再带 `-c p`。

## 32. 第二十五轮：5.1 carapace 上下文列表落盘缓存（2026-11-11，用户问“5.1 首个 Tab 约 2 秒能否优化”）

- 现场：Windows PowerShell 5.1.26100、PSReadLine 2.0.0、carapace-bin 1.8.2、argc 与
  carapace 同开；真实窗口注入 Tab 测量首个 Tab 约 1.1 秒（首次落盘/冷磁盘时约 2 秒），
  pwsh 7.5.4 同条件约 1.1 秒。
- 分解（5.1，profile 已加载）：`Initialize-Carapace` 约 490ms，其中 `Get-Alias` 5ms、
  `Get-Command -CommandType Cmdlet` 63ms、`Get-Command -CommandType Function` 275ms、
  `Get-Variable` 12ms、生成脚本 28ms、文本补丁 35ms、`Invoke-Expression` 38ms；
  `Initialize-ArgcCompletions` 130ms、CxxuTab 导入 35ms（命令表缓存命中）、实际补全调用
  约 185ms，其余为 PSReadLine 菜单与 5.1 的桩逻辑。5.1 比 7 多出的主要就是约 350ms
  名称列表枚举（7 同类枚举约 100ms）。
- 处置：新增 `Get-CarapaceShellContext51`，把四个 `CARAPACE_SHELL_*` 名称列表落盘到
  `~/.cxxu/cache/carapace-shell-51/`（四个 txt + `meta.txt` 记录宿主、PSHOME 与写入时间），
  首个 Tab 命中缓存只读 4 个小文件（约 2–3ms）。失效条件：宿主或 PSHOME 变化、超过
  24 小时、文件缺失或为空、`Initialize-Carapace -Force`；24 小时口径与 CxxuTab 命令表
  缓存一致。缓存写入失败只影响下次首 Tab 的耗时，不阻断加载。
- 结果（同机、真实窗口注入）：5.1 首个 Tab 从约 1.1 秒降到约 0.6 秒；首次落盘
  （冷缓存）约 1.05 秒；`Initialize-Carapace` 从约 490ms 降到约 150ms。7 未受影响。
- 查询与清理：`Get-CxxuComponent -Id Carapace` 的 `Runtime`、`RegisteredCommands`、
  `CachePath`、`CacheState` 分别给出加载阶段、已注册命令数、缓存目录与有效性/重建原因；
  `Reset-PsCommandCache` 会连同 `carapace-shell-51` 目录一起删除（新开终端后首个 Tab 重建），
  当前会话仍用内存中的旧全局变量。
- 边界：24 小时内新增的函数/别名不会进入 carapace 的 shell 名称列表（外部 CLI 的参数
  补全不受影响）；需要立即刷新时删除缓存目录或执行 `Initialize-Carapace -Force`。
  函数名列表仍按 30,000 字符截断。

## 33. 第二十六轮：Tab 菜单显示函数 .SYNOPSIS（2026-11-11，用户问“自定义函数的 synopsis 能否显示在补全菜单”）

- 现场：用户的自定义函数带注释帮助，Tab 菜单只能看到参数语法，看不到 `.SYNOPSIS`。
  核对 PSReadLine 2.3.6 源码与 `Changes.txt`：`MenuComplete` 一直会渲染选中项的
  `CompletionResult.ToolTip`（tooltip 与候选文本不同、窗口高度够时才显示），本机
  `ShowToolTips=True`；ListView 自 2.3.1 起也支持选中项 tooltip，最多 4 行。
  问题不在渲染层，而是引擎给命令候选的 ToolTip 只含参数语法。
- 处置：`CxxuTab` 在命令名位置合并模糊结果后，给 `ResultType=Command` 的候选补摘要，
  顺序为“`.SYNOPSIS` 首段 + 原有参数语法”，独立开关 `$env:PsTabSynopsis`（当时默认开，现行默认关闭，见「摘要按需启用复验」）
  与独立熔断 `$global:__CxxuTabSynFuse`，失败只丢摘要，不影响候选与模糊。
- 取摘要方式：不走 `Get-Help`/`Ast.GetHelpContent()`——本机会话 75 个带帮助的函数合计
  约 678ms，且 `Get-Command` 不带 `-ListImported` 会为未加载模块触发自动加载（30 个候选
  实测可拖到数秒）。已加载函数从 `FunctionInfo.Definition` 文本解析首段（遇空行或下一个
  帮助标签停止，行注释/块注释统一归一化），函数/别名索引每命令名 Tab 用
  `Get-Command -CommandType Function, Alias -ListImported` 重建（约 1ms，首次含 JIT 约 8ms），
  摘要文本按 ScriptBlock 对象身份缓存，函数重新定义后下一次 Tab 自动换新。
- 未加载模块（第二版）：用户报 `Get-SystemInfoBasic` 没有摘要，实测它属于 `Hardware`，
  该模块启动时未导入；`Get-Help` 能出摘要是因为自动导入了模块。为兼顾懒加载，新增源码
  回退：`Get-Command -CommandType Function` 只枚举不导入（1901 个函数约 33ms，每进程一次），
  得到函数名→清单路径；按同名 `.psm1`（缺失时读清单 `RootModule`）解析文件，
  缓存“函数名→AST”，按文件 LastWriteTimeUtc 失效。只在 pwsh 7+ 且候选不超过 20 个时启用，
  每次 Tab 最多新解析 3 个模块文件；已缓存模块不计。5.1 枚举约 260ms，维持仅已加载函数。
- 性能（profile 已加载，交错 20 次取中位数）：668 个候选的 `Get-` 前缀，摘要开 52.0ms、
  关 36.9ms；单独调用装饰逻辑约 2.7ms（大候选集只重建真正要改的 15 个候选，其余原对象
  复用）；常规 4~12 个候选（`Get-EnvVar`、`Confirm-`）无可测差异（约 24.6ms 与 24.8ms）。
  源码回退：`Get-SystemInfo` 首次 105ms（含模块索引 33ms 与解析 `Hardware.psm1`），
  同会话第二次 29ms；`Hardware` 始终未导入；宽前缀 `Get-` 不触发源码解析。
- 验证：pwsh 7.5.4 与 Windows PowerShell 5.1.26100 直调 `TabExpansion2`——函数摘要、
  别名指向函数、无帮助函数保持原样、cmdlet 保持参数语法、重定义立即刷新、开关关闭、
  参数位不受影响；真实窗口注入按键（pwsh 7.5.4 + profile）`Get-EnvVar<Tab>` 与
  `Get-SystemInfo<Tab>` 菜单下方均显示摘要与参数语法，后者验证时不导入 `Hardware`。
  单候选（如 `Confirm-EnvVar`）不展开菜单，属 MenuComplete 行为，直接检查 ToolTip 可见摘要。
- 边界：已加载函数走定义文本；未加载模块只在 pwsh 7+、候选 ≤20 时读源码，二进制模块、
  嵌套模块中找不到根 `.psm1`、帮助写在 MAML 的函数拿不到；5.1 只覆盖已加载函数；cmdlet
  的内置帮助不读取；只取 `.SYNOPSIS` 首段；ListView 不改（其 tooltip 需在
  `CxxuPredictor` 的 dll 里给 `PredictiveSuggestion` 补第二个参数）。
- 版本：`CxxuTab` 1.0.6。

## 34. 第二十七轮：变量与别名加载优化（2026-11-13）

- 现场：变量/别名本身是启动链的固定成本，且不全在首屏。核心变量约 100ms；全量变量
  约 470ms，其中 `GlobalConfig.conf` 的 `Get-CimInstance` 约 330ms、`Get-MemoryCapacity`
  约 100ms；全量别名约 150ms，逐行 `Get-Content`、`Get-Alias` 与 `Invoke-Expression`
  占主要部分。`Update-PwshEnv`（全量变量 + 全量别名 + prompt）实测约 748ms。
- 变量优化：
  - `VarSet1.conf` 的 `current_shell` 从 `Get-Process -Id $PID` 改为
    `[System.Diagnostics.Process]::GetCurrentProcess()`，避免 cmdlet 首次调用开销。
  - `GlobalConfig.conf` 的 `$SystemCaption` 改读 `$env:OSCaption`（`Confirm-EnvVarOfInfo`
    已缓存），`$TotalMemory` 优先读 `$env:TotalMemoryGB`，其次读 `Data.json` 的
    `cachedTotalMemory`，缺失才调用 `Get-MemoryCapacity`；`$PermissionLevel` 在 Windows
    内联 .NET 管理员组判断，避免为一个布尔值自动导入 `Basic` 模块。
  - `GlobalConfig` 单文件从约 346ms 降到约 38ms；全量变量从约 472ms 降到约 227ms
    （缓存热，另一次 241ms）。
- 别名优化：`Aliases` 新增 `Get-CompiledPwshAliasFile`，把 `alias_core.ps1`、`functions`、
  `shortcuts` 预编译为 `$TEMP/CxxuPwshAlias_*.cache.ps1`，按文件 mtime 失效，构建时
  判定一次 AllScope，运行时只点源一次；`Update-PwshAliases -NoCache` 保留逐行回退。
  全量别名从约 149ms 降到约 57ms（首次构建）/ 19ms（缓存命中）。
- 结果：`Update-PwshEnv` 从约 748ms 降到约 318ms；`profile` 仍约 996ms，因为首屏只加载
  核心变量/别名，主要成本仍是 PSReadLine、`Set-PsPrompt` 与体验件桩，不能用全量加载的
  改善宣传首屏提速。以上为同一台 Windows 虚拟机、新进程、一次采样，数值随负载和冷热
  缓存抖动；5.1 与 pwsh 7 均已直调验证，`-NoCache` 回退路径正常。

## 35. 第二十八轮：启动档位（2026-11-13）

- 目标：在现有组件开关之上提供整体档位，允许用户用一次切换放弃整套扩展，而不是逐个
  `Disable-CxxuComponent`。档位只约束 `init` 的步骤表；`$profile` 中的 conda 钩子与终端
  启动参数不在其中，conda 仍需单独处理（按用户决定不纳入档位）。
- 初版做过三档（`Minimal`/`Fast`/`Balanced`）。复测发现 `Minimal` 与 `Fast` 的差值在噪声内
  （新进程三次中位数 441ms 与 438ms），保留两档没有意义，最终收敛为两档，`Minimal` 只作
  兼容别名：
  - `Fast`：`Set-PSReadLinesCommon` + `Set-PSReadLinesAdvanced` + `Set-PsPrompt` +
    `Set-ArgcCompletions` + `Register-GitCompletion`；体验件（`Register-PsUxLazyLoad`）、
    `Set-ArgumentCompleter`、`Confirm-EnvVarOfInfo`、`Carapace` 与 PSCompletions/Fnm/
    ScoopSearch 不加载。
  - `Balanced`：原有默认步骤表与已启用组件，行为不变。
- 实现：
  - `init` 新增 `-Tier Fast|Balanced`（`Minimal` 仍被接受）；省略时按“`$env:PsStartupTier` >
    用户配置 > `Balanced`”解析。显式 `-Tier` 写入进程环境，子进程与组件判断可见。
  - `Get-CxxuStartupTier` 统一把 `Minimal` 归一化为 `Fast`；`Get-CxxuInitStepsForTier`、
    `Test-CxxuTierAllowsComponent` 内部同样按 `Fast` 处理，避免两处语义漂移。
  - 新增 `Set-PsStartupTier`（`-Persist` 写 `~/.cxxu/config.psd1` 的 Settings，
    `-WhatIf` 可预览）；持久化时把 `Minimal` 归一化为 `Fast`。`PsStartupTier` 加入
    `config.defaults.psd1`，`Get-CxxuConfig`、`New-CxxuConfigTemplate`、`Reset-CxxuConfig`
    自动包含。
  - 新增 `Get-CxxuInitStepsForTier`、`Test-CxxuTierAllowsComponent`：核心步骤按档位过滤，
    组件步骤按 `components.psd1` 的 Id 过滤，`Argc`/`GitCompletion` 是 Fast 唯一保留的组件。
  - `Get-CxxuComponent` 增加 `Tier`、`TierAllowed`、`Effective`；`Enable-CxxuComponent` 在
    档位不允许时警告“只保存开关或立即调用，启动仍需切回 Balanced”。档位是硬上限，组件开关不能突破。
  - `PsShowProgress` 默认值改为 `Auto`，由档位解析（`Fast` 关、`Balanced` 开），显式
    `True`/`False` 优先。初版用“环境变量为空才关”的写法，但模板会把默认值 `$true` 写进
    配置文件，模板用户的该分支永远不成立，属于缺陷修正；用户显式选择
    `Balance`/`Brilliant`/`Brilliant2` 时，`Fast` 仍补回 `Confirm-EnvVarOfInfo`
    与 `Confirm-DataJson`，避免富提示符缺数据。初版 `Minimal` 的 `Simple` 提示符默认值
    随档位合并取消，`Fast` 不再改写 `PsPrompt`。
- 差额归因（pwsh 7.5、新进程三次中位数、init 内部口径，多次复测）：`Fast` 约 430ms
  （steps 约 280）、`Balanced` 约 550~580ms（steps 约 390~420），差约 120~150ms，
  几乎全在步骤表：`Register-PsUxLazyLoad` 20~50ms、`Set-ArgumentCompleter` 约 40ms、
  `Confirm-EnvVarOfInfo` 25~35ms、`Register-CarapaceLazyLoad` 约 7ms、三个可选组件桩
  合计约 3ms。`Set-PsPrompt`（约 145~180ms）与 `Set-PSReadLinesCommon`（约 95ms）两档都执行，
  prep（约 150ms，含配置读取与核心变量/别名）也不受档位影响，所以档位最多只能省这两成，
  不能据此宣称首屏减半。含 conda 缓存（约 150ms）与 Init 模块导入的进程级口径同样差
  约 120~150ms。若还要更快，优先处理 conda 钩子、`Set-PsPrompt` 与 Init 模块导入，
  而不是继续拆档位。
- 验证入口：`init -Tier Fast -Timing`、`init -Tier Balanced -Timing`、
  `Get-CxxuComponent | Select-Object Id, Enabled, Tier, TierAllowed, Effective`、
  `PS/Init/tests/StartupTier.Tests.ps1`；pwsh 7 与 5.1 均可运行。

## 36. 第二十九轮：启动计时默认提速（2026-11-13）

- 现场：`Test-StartupPerformance` 默认探针提示“约需 15 秒”，实际约 6 秒；提示既不准，也把
  一次分段体检做成了需要专门等待的操作。用户预期是默认跑一次就列出全部分段。
- 处置：默认单次不再做预热；`init` 合计与步骤表合并到同一次新进程（原先为占比多开一次），
  总量改读该次 `Environment Loading time`；只有 `-Repeat > 1` 才预热并取中位数。
  输出改为对象流，列固定为 `Category`/`Name`/`Ms`/`Share`/`Note`，可直接接 `ft`/`fl`；
  默认按耗时降序给出可加分解：`bare`、`Init 模块导入`、`conda/其他 profile`、`init 准备/收尾`
  与各 init 步骤，`Share` 为占 profile 的百分比，第一行即当前最大影响因素。不再打印表头与结论；
  交互终端测量时显示进度条（重定向或 `PsShowProgress=False` 时关闭），`-Report` 额外提供文本摘要
  （总耗时、分解、前三因素）。`-Prompt`/`-Ux`/`-Status` 追加其他评估面，`-All` 全开。
- 结果：同机默认约 3 秒（含两次新进程），`-All` 约 4~5 秒，`-Repeat 2` 约 5 秒；分解各项
  之和与 profile 的差额来自取整与测量抖动，`-Simple` 仍为 1~2 秒。

## 变量组缓存与预设变量启动开销

**结论：分组缓存已撤回，保留 `.conf` 配置、既有单文件缓存、直接点源加载长字符串和公共帮助。** 普通启动只调用 `Update-PwshVars -Core`，主要目标是减少新窗口的首次加载；完整变量与同进程重复加载的改善不能替代这个目标。当前使用方式见 [预设变量配置与缓存](Feature-Guide.md#预设变量配置与缓存)。

### 实验范围与结果

2026-11-13，本机 Windows、pwsh 7.5.4 使用相同配置对照旧单文件加载器与分组缓存实现（提交 `a18551b`）。两者都在新进程中测量，模块导入单列，不包含在变量加载时间中；磁盘缓存已存在。同进程第二次调用单独记录，不称为新窗口启动收益。原数据为三次中位数；完整 profile 使用 Balanced 档位另测三次，包含进程启动、真实 profile 与 conda 缓存。

| 测量范围 | 单文件缓存 | 分组缓存 | 解释 |
| --- | --- | --- | --- |
| Core，新进程首次调用 | 116ms | 105ms | 普通启动实际路径，节省约 11ms |
| Core，同进程再次调用 | 26ms | 14ms | 运行时已预热，不能套用到每次新开窗口 |
| Full，新进程首次调用 | 211ms | 145ms | 节省约 66ms，但普通首屏不加载 Full |
| Full，同进程再次调用 | 86ms | 52ms | 完整变量重复刷新场景 |
| 完整 profile 的进程耗时 | 1151ms | 1054ms | 整体观察，不能全部归因于分组缓存 |
| 上述 profile 中的 init 内部耗时 | 601ms | 562ms | 同属整体观察，不与变量加载时间机械相加 |

复核时另一次新进程 Core 对照为 129.4ms / 109.4ms，第二次为 26.2ms / 13.3ms；这支持“普通首次加载只改善十几毫秒”的判断，不构成稳定收益区间。原完整启动测试每对均先旧后新，样本少，耗时范围重叠，存在文件缓存、执行顺序与系统负载影响。此前将约 100ms 的完整 profile 差额归为本补丁收益，证据不足，应撤销该归因。

### 已尝试方案与放弃原因

| 方案 | 观测与限制 | 决定 |
| --- | --- | --- |
| 合并所选配置，生成一个分组脚本 | 简化原型首次约 68–72ms；未包含正式校验与全部调用开销 | 原型不能作为交付预期 |
| 加入源文件、组别、版本隔离、原子写入和回退 | 正式 Core 首次约 105ms；复核拆分中校验首次约 27ms、执行约 60ms，第二次才分别降至不足 1ms、约 6ms | 可靠性成本抵消了大量流程节省；加载器净增约 170 行，首屏收益不足，撤回 |
| 用路径摘要隔离分组缓存 | 加密组件首次初始化约 14–17ms | 改为普通路径十六进制标识后仍未改变低收益结论；不继续围绕缓存标识微调 |
| 保留简单改进 | 长字符串直接点源，补全原生帮助；单文件缓存保留 UTF-8 BOM，并将配置运行错误与缓存准备失败分开处理 | 保留，价值是减少间接调用、说明用法及避免重复副作用，不单独宣称提速 |

原有实现已经使用单文件脚本缓存，分组缓存主要减少逐文件调度、文本返回和调试遍历，没有消除配置表达式求值与模块导入。生成的 `.ps1` 仍是文本，每个新进程仍有首次解析、绑定与运行时初始化成本；它并非跨进程保存的机器码。配置化本身无需放弃。

分组实现曾在 pwsh 7 与 Windows PowerShell 5.1 通过动态求值、失效检测、损坏及不可写回退、仓库副本隔离等回归；这些是历史验证，不能当作撤回后的单文件缓存保证。现行 [变量加载回归](../PwshVar/tests/VariableLoading.Tests.ps1) 在两种版本均通过，只验证保留的加载契约；单文件缓存的命名与时间判据限制见使用指南。撤回后另启保留真实 profile 的 ConsoleHost 窗口，确认仓库模块已加载、`$scripts` 指向存在的目录、初始化错误为零，Tab 处理器仍为 `CustomAction`；静态检查无 Error，存量 Warning 未增加。

### 避免重复探索与重新评估条件

- 后续处理“预设变量导致启动慢”时，先读取本节与 [用户指南](Feature-Guide.md#预设变量配置与缓存)，不从分组脚本原型重新开始。历史实现和回归可通过提交 `a18551b` 查阅，无需为留证保留线上分支逻辑。
- 仅在 Core 规模、真实调用频率、运行时或底层成本发生实质变化，或用户明确要求时重新评估分组缓存；重试前写明变化和目标收益。Full 变快或同进程第二次变快，仍不足以证明新窗口首屏改善。
- 后续若继续优化，先定位 Core 内实际表达式、文件读取与系统查询的占比，再考虑减少必要工作或延迟非必要工作；尚未验证的方案不承诺可省数百毫秒。
- 优化或重构收益小、落在测量波动内或难以抵消维护成本时，应先向用户说明证据和代价，询问是否放弃或收敛。用户已选定撤回时直接执行；将已尝试方案、测量条件、结果、放弃原因及重试条件留在同一处，后续先查记录。

## 5.1 PSReadLine 可选升级与预测版本门控

- 现场：Windows PowerShell 5.1.26100.8875 自带 PSReadLine 2.0.0，`HistoryNoDuplicates`、
  `inlineprediction` 配色、历史预测与 ListView 都缺席；补全栈此前只按版本跳过这些选项，
  没有升级入口。
- 处置：`DevEnv` 新增 `Install-Ps51PSReadLine`，`Deploy-CompletionStack` 增加
  `-IncludePSReadLine51`（`-All` 包含）。默认取 PSGallery 最新稳定版（当前 2.4.5），
  本机已有同版本时直接复制、不联网；`-NoGallery` 或查询失败时回退本机可用版本，
  `-Version` 可固定版本；安装到
  `~\Documents\WindowsPowerShell\Modules\PSReadLine\<版本>`，并在 5.1 子进程里实际导入验证。
  `Sync-Ps51PSReadLine` 跟随 pwsh 版本，`-SourcePath` 支持完全离线安装。安装还会默认把用户
  模块目录前插到 User 级 `PSModulePath`（`-NoPersistModulePath` 可跳过），否则 PSReadLine
  可能在 `init` 之前加载，窗口里仍是 2.0.0。默认层仍不联网、不装仓库外组件，
  未选择该开关时行为不变。
- `init` 的 `Set-PSReadLinesAdvanced` 改为按版本分流：pwsh 7.2+ 且 PSReadLine 2.2.2+
  用 `HistoryAndPlugin`，其余 2.1+（含升级后的 5.1）用 `History`，2.0 跳过预测参数；
  `PredictionViewStyle` 另按 2.2.2+ 门控，不再依赖 catch 兜底。
- 验证（5.1.26100.8875 + PSReadLine 2.3.6，**真实交互窗口 + 实际 profile/init**，
  通过控制台注入命令读回）：`PS=5.1.26100.8875`、`PSRL=2.3.6`、
  `BASE=~\Documents\WindowsPowerShell\Modules\PSReadLine\2.3.6`、`PRED=History`、
  `VIEW=ListView`、`NODUP=True`、`PATHHAS=True`。另在 5.1 子进程里验证
  `HistoryNoDuplicates`、`CompletionQueryItems`、`inlineprediction` 配色与 `MenuComplete`；
  `HistoryAndPlugin`/`Plugin` 按预期失败，提示插件预测源需要 7.2+。此前只看子进程导入，
  层级低于用户实际窗口，不能作为验收依据。
- 边界：2.3.x 的模块资产是 `net462`，2.4.x 起改为 `netstd`；两者都接受，2.4.5 已在
  5.1.26100 上验证可导入并可用（本机组件级验证 + 用户另一台 5.1 实际使用）。默认安装取
  PSGallery 最新稳定版，`-NoGallery` 或查询失败时回退本机可用版本（通常是 pwsh 附带的
  2.3.6），`-Version` 可固定。5.1 启动前
  `PSModulePath` 必须包含用户模块目录，安装命令会持久化 User 级路径，已加载旧版的窗口
  必须完全重开才能换版本。从 pwsh 7 启动 5.1 时，`init` 的
  `Update-CxxuModulePathOrder` 也会前置该目录，但不能替代启动前的 User 级路径。
  回退为关闭所有 5.1 窗口后删除对应版本目录。

