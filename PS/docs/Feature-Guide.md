# 功能指南（用户手册）

> 面向日常使用者。模块开发规范见 `Module-Conventions.md`，模块清单见 `Module-Map.md`。

## 1. 一次配好，到处能用

```powershell
# 1) 把模块目录加入 PSModulePath（持久化一次即可）
$p = 'C:\repos\scripts\PS'
Add-EnvVar -EnvVar PSModulePath -NewValue $p -Verbose

# 2) profile 里只留一行
'init' > $profile
```

之后所有模块**按需自动加载**，不用手写 `Import-Module`。

## 2. 三个入口：`init` / `p` / 主题

| 命令 | 用途 |
|---|---|
| `init` | 全量初始化（变量+别名+补全+prompt，约 400~700ms）；同会话重复调用直接返回；`-Force` 重跑步骤表，并在已初始化会话真重载全部变量 conf（2026-10-03 起，重载开销约零点几秒；首次初始化路径不变） |
| `init -Timing` | 同上，附每步耗时表（首次启动）；已初始化会话用 `init -Force -Timing` |
| `p` | 新开一个 pwsh 会话，由新进程的 profile 执行 `init`；不刷新当前会话 |
| `Test-StartupPerformance` | 新进程分段计时（bare/profile/init/idle），标明 `init` 是 `profile 税` 的子集；`-Simple` 只测一次带 profile 的启动，`-PassThru` 返回对象 |
| `Set-PsPrompt -version < fast/short/...>` | 切换提示符；加 `-Persist` 才写注册表记住选择 |
| `dm` | 切极简 prompt（做笔记摘录时聚焦命令本身） |
| `Test-PromptDelay` | 测当前 prompt 延迟 |
| `doctor` | 统一诊断入口（定位问题先执行它）：先跑 `Test-PsEnvReadiness`（安装态），再查运行态（init 错误/PSReadLine/历史大小/predictor/门控/懒加载/守护/仓库脏），只读，默认零网络；按平台过滤不适用的检查并在表尾汇总已跳过项。`-Feature <名>` 只查单个功能（如 `doctor -Feature Argc`），支持依赖清单的功能分组名、关键字与正式短名，`-Feature` 可用 Tab 补全 |
| `Get-CxxuDependencyReport` | 按功能列出外部依赖、生成物与当前安装状态，表后给出安装建议；只读、默认零网络，详见 [Feature-Dependencies.md](Feature-Dependencies.md) |
| `New-CxxuConfigTemplate` | 生成 SchemaVersion=2 用户配置模板（`~/.cxxu/config.psd1`，仓库外本机生效；组件来自 `components.psd1`，Settings 来自 `config.defaults.psd1`） |
| `Import-CxxuConfig` | 读用户配置（init 首步自动调；优先级：环境变量 > 配置文件 > 默认值） |
| `Get-CxxuConfig` | 查看各开关的当前生效值、来源（环境变量/配置文件/默认值）与默认值；管道接 `Format-List` 看完整说明 |
| `Reset-CxxuConfig` | 按仓库默认偏好（组件见 `PS/Init/components.psd1`，Settings 见 `PS/Init/config.defaults.psd1`）重置用户配置文件；`-WhatIf` 只预览路径，重置后重开终端生效，并列出仍会覆盖默认值的环境变量 |
| `Enable-PsPlugin` / `Disable-PsPlugin` | 体验插件启停（Fzf/Zoxide/Predictor/Tab/Argc/GitCompletion/Carapace/PSCompletions/Fnm/ScoopSearch，当会话生效；加 `-Persist` 长期有效，写 `~/.cxxu/config.psd1`） |
| `Set-GitCompletionSource` | 切换 `git`/`gitk` 的 Tab 补全来源（`GitCompletion`/`Carapace`/`Argc`）：写入 `PsGitCompletionSource` 与相关开关，由 `init` 在启动时读取，当前会话立即重新注册；选来源即启用对应组件（此前被 `Disable-PsPlugin` 停用也会重新打开），但不会停用其他组件；不改 profile，`-Persist` 落配置，`-WhatIf` 预览 |
| `Get-GitCompletionSource` | 只读查看 `git`/`gitk` 补全的配置来源、解析来源与当前会话已注册来源，附各来源（含 `posh-git`）的安装/启用状态、回落原因与下一步命令；`-List` 按来源逐行列出候选（安装、版本、启用、当前生效与安装命令）；用于确认“当前实际用的是哪个”，不加载补全模块 |
| `Get-CxxuComponent` | 按组件列出启用状态、选项、来源、默认值与安装/文档入口，并给出 `Install`/`Enable` 建议命令；`-Id Carapace` 只查一个；`-Validate` 改跑清单/步骤/依赖一致性自检 |
| `Test-CxxuComponent` | 只读检查组件清单结构、Init 步骤生成与已启用组件的外部依赖；`Status` 为 `OK`/`警告`/`错误`，依赖警告会带安装与启用命令；`Get-CxxuComponent -Validate` 与 `doctor` 复用同一结果 |
| `Enable-CxxuComponent` / `Disable-CxxuComponent` | 按组件 Id 启停；默认只改开关，`-Now` 立即调用组件的 Init 函数；`-Persist` 写 `~/.cxxu/config.psd1` 的 `Components` 段，不加只改当前会话；写入前备份旧文件，并按 v2 规范文本重写（手工注释可能被规范化） |
| `Set-CxxuComponentOption` | 设置组件选项（如 `GitCompletion.Source`、`Carapace.Excludes`）；`-Persist` 写配置，枚举与 List 类型按 `components.psd1` 校验；写入行为同上 |

环境等级（`$PsEnvMode`，`Test-PsEnvMode` 查询）：core(1) 核心变量 → vars(2) 全量变量 →
env(3) 变量+别名。`Update-PwshVars` 全量导入后置 2，`Update-PwshEnv` 置 3；
`Update-PwshEnvIfNotYet` 按需补齐，达到对应等级后不重复导入。

## 3. 改模块 / 加函数（有了 `.psd1` 之后的工作流）

以前只有 `.psm1`，写完函数直接能用；现在每个模块多了 `.psd1`（显式导出表），
**函数只在两个地方都出现才算数**：

```powershell
# 1) 在 PS/<模块>/<模块>.psm1 里写函数（UTF-8 无 BOM，换行跟文件原状走）
# 2) 把函数名加进同目录 .psd1 的 FunctionsToExport（位置随意；GUID/版本不用动，日常改保持 1.0.4）
# 3) 当前会话生效（不用重启 shell；核心价值=保住当前会话变量上下文，新开 pwsh 会丢一部分信息）：
Sync-ModuleManifest <模块名> -Reload  # 偷懒版：自动把 .psm1 新增函数补进 manifest 并重载，一条搞定
Sync-ModuleManifest -Reload            # 不指定模块 = 全部 67 个自有模块（只打印有变化的+汇总；Prompt 跳过重载防嵌套）
# -Name 支持 Tab 补全（空字列出全部）；单模块想手动挡就继续 Import-Module <模块名> -Force -DisableNameChecking
# （-DisableNameChecking 定向压掉双横线警告，见 FAQ；其它警告不受影响）
ipmox                           # 单命令版（推荐）：同上但一步到位（-Global 重装+Pwsh 殿后）
ipmox -Name Prompt -Sync        # 新函数场景：先同步 manifest 再重载；-Name 只动指定模块（Tab 补全）
ipmof | iex                     # 旧版（兼容）：只重载仓库内(PS/)已加载模块；第三方/系统不动；副作用模块(*completion*/*predictor*/*conda*)跳过
```

> **dll 是例外**：`.psm1` 的改动执行 `ipmox` 当场生效，但 `CxxuPredictor.dll`（.NET 程序集，不随模块卸载而卸载）**在当前会话中永远是旧代码**。dll 变更后的正确顺序： `Update-ReposesConfiged`（拉取后自动同步活件）→ 重新打开终端 → `init`（详见 §9；`Test-PsEnvReadiness` 备注列会说明活件是否落后）。

- 模块还没加载过时更省事：直接敲新函数名，PSModulePath 自动发现并加载（前提：manifest 里已导出）。
- 只想模块内部用的 helper：只写 `.psm1`，别进 manifest，外部就不可见。
- 新建模块：`PS/<名>/` 目录 + `<名>.psm1` + `<名>.psd1`（抄 `Whois.psd1` 最小模板，
  GUID 用 `[guid]::NewGuid()` 换一个）；**目录名 = 模块名 = psm1 基名**，否则自动加载找不到。
  建完直接敲函数名即用，再跑 `Test-ModuleManifest` 验一下。
- 改 init 期文件（`Aliases/` 下别名文件、`.conf`、profile）：改完跑对应 loader——变量 conf →
 `init -Force`（2026-10-03 起真重载全部变量 conf）或 `Update-PwshVars` 直刷，别名 → `Update-PwshEnv`，
 profile → `. $profile`；三档分流详见 §6「`source ~/.bashrc` 对应物」。
- 验：`Get-Command <函数名>` 看 Source 是不是你的模块（撞名先查这个）。

```powershell
Get-SourceCode <命令名>     # 看任意自定义函数源码（带补全）
init -Force -Timing         # 看当前会话 init 分步耗时，定位慢项
Test-StartupPerformance     # 新进程分段计时（裸启动/profile/init）
Test-StartupPerformance -Simple   # 只测一次新 pwsh 启动（带 profile）
```

## 4. 开机与后台

- `Start-StartupTasks`：开机拉仓库、起软件/服务、报时 + IP 更新两个守护进程。
- IP 显示不走实时查询：`Update-NetConnectionInfo` 守护进程每 6s 写 `~/Data.json`
 （`IpPrompt`/`ConnectionName`），prompt 只读文件（3ms）；文件缺失才即时算一次并写回。
- 内存占用同理：5s 节流 + 文件缓存；电池 30s 会话缓存。

## 5. profile 与终端的双路径（必读）

- `$profile`（`CurrentUserCurrentHost`）里是 `init`；WT 直接启动 `pwsh` 即可，不需要
  `-c p`。`$profile` 会执行 `init`，`$global:PsInit` 保证同会话只初始化一次；`p` 只负责
  新开一个 pwsh，不刷新当前会话。
- `p` 不判断当前会话是否已初始化，固定新开一个 pwsh。把它放进启动器
  （`pwsh -noe -c p`）会让外层 profile 先 `init` 一次，再由 `p` 开的子进程 `init` 一次，
  终端里就会出现两行 `initing...`；启动器只写 `pwsh`。
- 只保留 `$profile` 这一条路径即可；WT 不需要额外启动参数。
- conda 初始化已换缓存方案（`~/.conda_hook_cache.ps1`，573→59ms）；
  下次跑 `conda init` 会覆盖，届时重新应用（见 `Startup-Optimization.md §8`）。
- profile 里只保留 `init`；`argc` 已有 Init 接管（部署见 [Argc-Completions-Deploy](Argc-Completions-Deploy.md)），`PSCompletions`/`fnm`/`scoop-search` 也迁到组件清单（默认关，`Enable-CxxuComponent <Id> -Persist` 启用），不再改 profile。

## 6. FAQ
- **`scoop update/install` 报 `cannot pull with rebase: Your index contains uncommitted changes`**：任一仓库（scoop 本体 `apps\scoop\current` 或某个 bucket）处于脏状态，git 拒绝执行 pull --rebase。修复：`Repair-ScoopUpdate`（`Scoop` 模块，逐个检查本体与全部 bucket，默认 stash 保留现场，加 `-Discard` 丢弃改动，收尾自动 `scoop update`，只看不动加 `-NoUpdate -WhatIf`）。
- **看不到 `Loading personal and system profiles took ...ms`**：正常。引擎只在四个
  profile 合计 >500ms（硬编码）才打印，不到就静默。
- **嵌套 `pwsh` 又跑一遍 init**：新进程不继承 `$global:PsInit`，只能重跑；
  贵的是 conda + init + 模块发现（见基线表），不是重复 bug。若启动器写成
  `pwsh -noe -c p`，会看到两次 `initing...`（外层 profile 一次、`p` 开的子进程一次）；
  把启动器改成 `pwsh` 即可，原因与验证见 `Startup-Optimization.md` 的启动器重复初始化记录。
- **prompt 显示空 IP**：`~/Data.json` 的 `IpPrompt` 为空且守护进程没跑；
  手动跑一次 `Get-IpAddressFormated` 即写回，以后就快了。
- **`ipmof|iex` 后提示符叠了**：根因不是 Prompt 模块（沙箱最小复现证伪：
  纯 Prompt 重载只会因抓空报错，不会叠）。真凶是 `Conda.psm1:232-247`——每次 import
  都 `Rename-Item prompt→CondaPromptBackup` 再包一层（`ChangePs1` 缺省真），旧 `ipmof`
  全量重载每轮多包一层。2026-09-20 已改白名单：只重载仓库内模块 + `*conda*` 跳过。
  已堆起来的会话跑一行恢复（变量不丢，空槽/叠层两种状态通用）：
  `Remove-Module Prompt,Conda -Force; . $HOME/.conda_hook_cache.ps1; Import-Module Prompt -Force`。
  另：`Prompt.psm1` 顶层已改“全局只抓一次”（`$global:__CxxuOriginalPrompt`），
  裸重载复用首存不再抓空，故 Prompt 可留在轮转里；想换底（如后激活 conda）：
  `Remove-Variable global:__CxxuOriginalPrompt` 后重载一次即重抓。
  真机验证通过（2026-09-20）：新开 shell 单层正常，多轮 `ipmof|iex` 无叠层无报错，本条终结。
- **启动进度条**：默认开（`Loading...` + 分步百分比，跑完自动消失）。
  不想要：`$env:PsShowProgress = 'False'`（当前会话）；一劳永逸：
  `Add-EnvVar -EnvVar PsShowProgress -NewValue 'False'`。agent/CI 等重定向场景自动关闭，不用管。
- **窄窗口（宽<50 或高<5）启动刷 ListView WARNING**：PSReadLine 的硬门槛，
  2026-09-21 已在设 ListView 之前按尺寸分流（`Set-PSReadLinesAdvanced` 里）：
  窄窗口自动用内联视图，无警告；窗口拉大后重跑 `Set-PSReadLinesAdvanced` 即按新尺寸重选。
  同重定向跳过一样，这是控制台相关分流，有新选项先看这里。
- **`source ~/.bashrc` 对应物**：
  - 分三档。
    1. 改了模块函数 → `ipmox`（不用碰 profile）；
    2. 改了 init 期东西 → `init -Force`：2026-10-03 起真重载全部变量 conf（core 名单
       VarSet1/VarSet2/ConstantString + 平时懒加载的全量名单 VarSet3/GlobalConfig 等；
       已初始化会话重载开销约零点几秒，环境等级保持不被打回；首次初始化与新进程路径
       不叠加重载，启动基线不变；冷启动分段用 `Test-StartupPerformance`）。也可用对应 loader 直刷：变量 `Update-PwshVars`
       （`-Fast` 只刷 VarSet1/2，预编译缓存按 mtime 自动失效，无需清理）、别名 `Update-PwshEnv`、
       prompt/PSReadLine 由步骤表重跑。
    3. 改了 profile 文件本身 → `. $profile`；若 profile 只调用 `init`，`. $profile` 仍受 `$global:PsInit` 守卫，实际重跑用 `init -Force`。
  - 安全差异：bash 重 source 会叠 PATH，这边 `init` 有 `$global:PsInit` 防重复（`. $profile` 默认 no-op，真重跑靠 `-Force`），`Add-EnvVar` 自带去重（见 `EnvVar.psm1:621/629`），prompt 全局只抓一次，OnIdle 有标记位。
    注意 `. $profile` 只跑 `CurrentUserCurrentHost` 这一级（conda 钩子在 `CurrentUserAllHosts`
    里，碰不到；即使碰到，缓存 59ms 也不贵）。
- **v5 能用吗**：部分能。B 档 62 模块已降 `5.1`（`init` + 提示符 + Tab 补全 + 历史可用），部署与内联预测明确留 7；5.1 的 Tab 走专用 `ps51` 活件，见 §13。其余留 7 模块进 v5 会明确报错。
- **agent/CI 里曾出现两行 `Set-PSReadLineOption` 红字**（predictive suggestion…redirected、
  句柄无效）：那是 `init` 在 stdout 被重定向时硬设预测源/列表视图闹的，
  2026-09-20 已修（重定向下自动跳过这两项，其余照常；详见 `Startup-Optimization.md §12`）。
  手动开终端永远走交互分支，行为不变。如果以后又看到类似红字，先看是不是新加的
  控制台相关选项没进分流逻辑。
- **`Import-Module` 时的 restricted characters 警告**：触发规则是**函数名里 2 个以上 `-`**
  （16 组合成模块实测）。2026-09-20 已把 17 个双横线名 + 2 个拼写 typo 转正为融合后缀
  （对照表见 `Startup-Optimization.md §16`），警告连根拔起；130+ 无横线个人速记不受影响。
  之后若再见到此警告，先查是不是新加了双横线名（`Sync-ModuleManifest` 重载已内置
  `-DisableNameChecking` 压制，自动加载路径本来就不报）。

## 7. 补全体验件（推荐组合，默认启用）

> 已启用的走延迟加载（`init` 只注册 `OnIdle` 事件，18ms），默认启动盘不受影响。
> 部署层、依赖级别、下载来源与 5.1/7.5+ 的能力对照见 [Deploy-Guide](Deploy-Guide.md) 的「分层、来源与能力」；本节只讲运行期开关与验证。
> 开关：`$env:PsFzf` / `$env:PsZoxide` / `$env:PsPredictor`（默认开，`False` 关；
> 守护进程由 `Start-StartupBgProcesses` 统一置 `PsPredictor=False`，永不加载 dll）；
> `$env:PsTab`（CxxuTab Tab 补全，**默认开，置 `False` 关**）；
> `$env:PsTabSynopsis`（Tab 菜单里的函数 `.SYNOPSIS` 首段，默认开，置 `False` 关；只影响摘要，不影响候选）；
> `$env:PsArgc`（argc-completions 参数补全，默认开，首次在外部 CLI 参数位按 Tab 才注册；需要时由 `Deploy-CompletionStack -IncludeArgc` 部署）；
> `$env:PsGitCompletion`（git-completion 的 `git`/`gitk` 补全，默认开，未装模块时无效果；装模块用 `Deploy-CompletionStack -IncludeGitCompletion`，启停用 `Enable-PsPlugin GitCompletion` / `Disable-PsPlugin GitCompletion`）；
> 来源切换用 `Set-GitCompletionSource GitCompletion|Carapace|Argc [-Persist]`：写入 `PsGitCompletionSource`（由 `init` 读取），不修改 profile；选来源即启用对应组件（此前停用也会重新打开）并在当前会话立即注册（argc 未加载时也当场注册，约 0.15–0.25 秒）；确认当前实际来源用 `Get-GitCompletionSource`（只读，区分“配置值 / 解析值 / 已注册来源”，并说明回落原因）；carapace 的启用与排除项分别由 `PsCarapace`、`PsCarapaceExcludes` 控制；
> 组件统一管理：`Get-CxxuComponent` 按 `PS/Init/components.psd1` 列出状态与选项，`Enable/Disable-CxxuComponent` 与 `Set-CxxuComponentOption` 负责启停和选项；`Enable-CxxuComponent -Now` 立即调用组件的 `InitNow`（未声明时用 `Init`），与 `Enable-PsPlugin` 的即时路径共用同一份清单；用户配置 `~/.cxxu/config.psd1` 的 `Components` 段只表达 `Enabled` 与选项；核心步骤固定，可选组件的加载步骤按 `components.psd1` 的清单顺序生成，新增组件不必再改 init 步骤表。旧版平坦键继续兼容；`-Persist` 会先备份旧文件，再按 v2 规范文本重写，手工注释可能被规范化；`Get-CxxuComponent -Validate` 或 `Test-CxxuComponent` 检查清单结构、Init/InitNow 函数与已启用依赖，`doctor` 的同名行复用该结果；
> 重定向场景自动不加载。新机安装或一键重装看 [Deploy-Guide](Deploy-Guide.md) 的「补全栈与第三方 PS 模块」（`Deploy-CompletionStack -WhatIf` 可空跑）。

| 候选 | 状态 |
|---|---|
| `CompletionPredictor`（参数/路径预测，命令名位置源码级跳过） | 一直在用 |
| `CxxuPredictor`（自研命令名预测：分层模糊 `别名 > 前缀 > 词边界/首字母 > 连续片段 > 一般子序列` + 严格通配，按历史频率加权，默认 15 条，3000 条 1ms 内） | **已启用**（详见 §8） |
| `CxxuTab`（自研命令名 Tab 补全：独立插件，命令名位合并模糊结果，参数位零干扰） | 默认开（开关 `$env:PsTab`，置 `False` 关；不需要时 `Disable-PsPlugin Tab -Persist`）；选中带注释帮助的函数时菜单下方显示 `.SYNOPSIS` 首段与参数语法（`$env:PsTabSynopsis` 可单独关；未加载模块在 pwsh 7+ 按需读源码） |
| `PSFzf`（Ctrl+T 文件 / Ctrl+R 历史） | **已启用**（Tab 不动，仍是 MenuComplete） |
| `zoxide`（`z` 跳转，init 缓存 `~/.zoxide_init_cache.ps1`） | **已启用** |
| `PSCompletions`（~200 命令的参数补全库） | 可选：已装 5.6.9；组件 `PSCompletions` 默认关，`Enable-CxxuComponent PSCompletions -Persist` 后由 `init` 导入模块 |
| `fnm` | 可选（node 用户）：组件 `Fnm` 默认关；装好 fnm 后 `Enable-CxxuComponent Fnm -Persist`，`init` 执行 `fnm env --use-on-cd` |
| `scoop-search` | 可选：组件 `ScoopSearch` 默认关；装好 `scoop-search` 后 `Enable-CxxuComponent ScoopSearch -Persist`，`init` 注入 `--hook` |
| `carapace-bin`（跨 shell 的 CLI 参数补全；本机 1.8.2 实测 743 个 completer，带颜色和描述） | **可选**，`PsCarapace` 默认 `$false`：`Deploy-Carapace -Enable` 一步安装并启用，或安装后 `Enable-CxxuComponent Carapace -Persist`；`init` 只注册懒加载桩，首次在外部 CLI 参数位按 Tab 才加载；git/gitk 归属用 `Set-GitCompletionSource` 切换；5.1 与 7.6 的生成脚本差异（空结果、零宽字符、环境变量、UTF-8/空参数、ANSI）在加载时处理。步骤与 git 对比见下文「carapace（可选，非默认）」 |
| `posh-git` | 已安装，未导入（`init` 不加载；导入时会注册同名 git completer，与其他来源不可混用） |
| `oh-my-posh` | 不开（每回车进程税 + 与现有定制片重叠） |
| `argc-completions`（800+ 命令参数补全；懒加载，首次参数补全时注册约 150ms；选中行反显高亮；首个参数位的静态 flag 自动进 ListView） | **已启用**（仓库 `~/argc-completions` 或 `C:\repos\argc-completions`；开关 `$env:PsArgc`；Tab 7/5.1 均可用，自动 flag 提示仅 7.5+） |
| `git-completion`（`git`/`gitk` 的 Tab 补全：分支、提交、按 git 状态过滤的文件与选项描述） | **已启用**（init 检测到模块即注册 completer，首次补全才导入；未装时自动跳过；开关 `$env:PsGitCompletion`；启用后 argc 让出 `git`/`gitk`；当前归属用 `Get-GitCompletionSource` 确认） |
| `inshellisense` | **否决**（用户拍板，不再考虑） |

验：新开终端直接可用，`Ctrl+R`/`Ctrl+T` 首按装 PSFzf（本次按键即生效）；`z <目录>` 跳转（zoxide 首屏单发已装）。`CxxuTab` 默认开，首个 `Tab` 才导入它（命令表缓存命中时建表约 20ms，模块导入另计；缓存缺失/过期时现建，5.1 约 0.4s、7 约 0.1s，24h 内最多一次）。`argc-completions` 开关默认开，首次在外部 CLI 参数位按 `Tab` 才注册（需先用 `Deploy-CompletionStack -IncludeArgc` 部署；未部署时自动回退原生补全，约 150ms 的注册不会发生）。`Get-EventSubscriber` 应无残留（单发用 `-MaxTriggerCount 1` 自动退订）。若某主机 OnIdle 不触发（predictor 没装上），跑 `Register-PsUxLazyLoad -Now` 或报回来。自查跑 `Test-StartupPerformance`（分段计时+结论）。

argc/carapace 的共享桩先识别光标所在命令与参数位置：命令名、PowerShell 函数/cmdlet 参数和重定向路径不触发注册；应用程序与外部脚本（如 `scoop.ps1`）的参数位才触发。变量形式调用与当前无法解析的命令保留原有加载入口。两者同时启用时仍按 carapace → argc 的顺序注册，重叠命令由后者接管；首次加载成本只推迟到相关场景。改动后需新开 pwsh 会话生效，运行期开关与显式初始化入口保持不变。

git 补全来源先看 `Get-GitCompletionSource`：`ConfiguredSource` 是配置值（`Auto` 不代表实际用了 `GitCompletion`），`EffectiveSource` 是按开关与安装状态解析的结果，`RegisteredSource` 才是当前会话已注册的 completer；`PoshGit` 列显示 posh-git 是否导入及是否参与同名覆盖；`Fallback` 或 `Note` 非空时按提示修正。需要候选清单时用 `Get-GitCompletionSource -List`（每行一个来源，含安装、版本、启用与当前生效），需要眼见为实再按一次真实 Tab（如 `git diff --st<Tab>`）。`Get-CxxuConfig` 只显示配置键的生效值，不判断补全归属。

### carapace（可选，非默认）

carapace 是一个跨 shell 的命令行补全二进制，按命令读取自身的 completer（补全器），在 PowerShell 里通过 `Register-ArgumentCompleter -Native` 注册。它不补 PowerShell cmdlet 的参数，也不参与命令名模糊补全；定位是补外部 CLI 的参数值，与 `CxxuTab`、`git-completion`、`argc-completions` 并列。

安装渠道不绑定 scoop：推荐 `Deploy-Carapace`，它会按当前平台与架构从官方 GitHub Release 下载产物（Windows 为 zip，macOS/Linux 为 tar.gz）、按 `checksums.txt` 校验并解压到默认目录（Windows `~/.cxxu/bin`，其他平台 `~/.local/bin`），可用 `-Version` 固定版本；也可手工下载官方产物，或用包管理器（Windows `scoop`、macOS `brew`、Linux 发行版仓库）。下载默认优先 `aria2c` 多连接分片（`-Aria2Connections`，默认 16），不可用时回退 `Invoke-WebRequest`；每次尝试都会打印原始链接、实际链接、来源与执行命令。GitHub 加速镜像默认读 `$env:PsGithubMirror`（未设置用 `https://gh-proxy.com`），`-NoGithubMirror`（别名 `-NoMirror`）直连，`-GithubMirror`（别名 `-Mirror`）`'<前缀>'` 本次指定。安装与校验步骤见 [Deploy-Guide](Deploy-Guide.md) 的「可选：carapace」。Windows PowerShell 5.1 与 pwsh 7 均可用，`carapace` 位于 PATH 即可；5.1 的引擎不会把 `-` 开头的词交给 Native completer，由仓库的共享 Tab 桩插入零宽字符绕过，编码、空参数与超长环境变量在加载时按版本处理。

本机 `carapace-bin 1.8.2`、`pwsh 7.6.3` 实测的代表性效果：

| 输入 | 候选 |
|---|---|
| `git checkout ` | 分支、标签、`HEAD`、stash，带提交主题或标签说明 |
| `git commit --` | 47 个长选项，带英文说明 |
| `git log -` | 263 个候选（短选项与长选项），带说明 |
| `git add ` | 已修改与未跟踪文件，带 `(M)` / `(??)` 状态 |
| `git show HEAD:` | 提交内文件树 |
| `git -C ../other checkout ` | 另一个仓库的分支与标签 |
| `npm run ` | `package.json` 的 scripts，并显示对应命令 |
| `scoop install ` | 包名列表；`winget install` 同理，但本机约 3.3 秒 |
| `docker run --`、`gh pr ` | 选项或子命令，带说明 |

`carapace --list` 在本机为 743 个 completer，生成的 PowerShell 脚本注册 1486 个命令名（含 `.exe` 变体）；数量随版本变化，以该命令的实际输出为准。

5.1 侧在 Windows 11 26100、PowerShell 5.1.26100.8875、PSReadLine 2.0.0、carapace-bin 1.8.2 实测：`git checkout <Tab>` 返回 11 个 ref，`git status --sh<Tab>` 返回 `--short`、`--show-stash`，菜单中文描述正常且无 ANSI 残留；首次 Tab 约 0.6 秒（首次建立上下文缓存约 1 秒），之后约 0.1–0.4 秒。候选数量与延迟随版本、仓库状态变化。

**启用步骤（由 `init` 注册懒加载桩，不修改 profile）**：

```powershell
Deploy-Carapace -Enable                     # 安装二进制并直接启用（官方 Release + SHA-256）
Deploy-Carapace -Bash                       # 只装二进制并接入 bash（写 ~/.bashrc）
Deploy-Carapace -Bash -BashLogin            # 登录 shell：改写 --login 的目标 rc
# 或分两步：
Deploy-Carapace                             # 只安装二进制
Enable-CxxuComponent Carapace -Persist      # 启用；下次启动注册懒加载桩，首次参数补全时加载
Enable-CxxuComponent Carapace -Persist -Now # 或立即加载（当前会话）
Set-GitCompletionSource Carapace -Persist   # 需要 carapace 接管 git/gitk 时
```

- `PsCarapace=True` 时 `init` 只计算排除项并注册外部 CLI 参数位 Tab 懒加载桩，启动阶段不执行 carapace 的注册脚本；默认关闭，未启用时没有这项开销。pwsh 7 首次参数补全时加载约 0.2–0.3 秒，之后 Tab 正常。
- 5.1 支持：`Register-ArgumentCompleter -Native` 在 5.1 可用，主要差异由加载时处理。`-`/`--` 开头的词由 Tab 桩在词首临时插零宽字符（与 argc 同一机制），交给 carapace 后随候选替换或由桩删除，不残留在输入行；`CARAPACE_SHELL_*` 名称列表在加载时枚举一次并落盘缓存（`~/.cxxu/cache/carapace-shell-51/`，24 小时或宿主变化后重建），函数名列表截断到 30,000 字符（环境变量上限 32,767），避免 `Environment variable name or value is too long`；调用改走 .NET `Process` 并固定 `StandardOutputEncoding=UTF-8`，同时还原空字符串参数，中文提交说明不再乱码；候选描述去掉 ANSI（PSReadLine 2.0 不解析转义序列）。代价是首次外部 CLI 参数补全约 0.4–0.6 秒（冷缓存约 1 秒），之后约 0.1–0.4 秒。
- `PsGitCompletionSource` 决定 git/gitk 归属：`Auto`、`GitCompletion`、`Argc` 时 `init` 把 `git,gitk` 并入 `CARAPACE_EXCLUDES`；`Carapace` 时不排除，并让 argc 让路。`Argc` 不推荐用于 git：argc 上游生成的 git 补全缺 `--cached`、`--staged` 等只写在 SYNOPSIS 的选项；`Auto` 的顺序为 `GitCompletion` → `Carapace` → `Argc`，`Argc` 仅作兜底。切换到前三种来源不会关闭 carapace 本身，需要停止加载时另执行 `Disable-PsPlugin Carapace`（加 `-Persist` 长期生效）；已加载的 completer 按 `PsCarapace` 门控立即返回空，`git`/`gitk` 当场回落：`Carapace` 来源优先交给 `git-completion`（模块已安装且组件未关闭），否则用 `Argc`；`GitCompletion` 来源直接重新注册模块。
- 与 argc 同开时，两者都在首次参数补全时注册；Tab 桩先加载 carapace，再注册 argc，同名 Native completer 后注册者 argc 生效，因此非 git/gitk 的重叠命令会由 argc 接管。需要 carapace 负责这些外部 CLI 时，关闭 argc（`Disable-PsPlugin Argc -Persist`）或接受 argc 的候选；bash 侧顺序相反，见 [bash/carapace README](../../bash/carapace/README.md)。
- 慢命令排除项写 `PsCarapaceExcludes`（逗号分隔，如 `winget,uv`），与 git/gitk 规则由 `init` 合并；未设置该键时沿用已有的 `CARAPACE_EXCLUDES`。
- 旧版 profile 中的手动 carapace 片段需要删除，否则会与懒加载桩重复注册；也不要执行 carapace 文档中的 `Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete`，避免覆盖现有 Tab 桩。
- 版本可以不追新，但生成脚本随版本变化：懒加载或手动加载时，pwsh 7.6 及更早版本按原文匹配空结果补丁，5.1 另匹配环境变量截断、空参数、编码与 ANSI 四处补丁；匹配不到时只告警，不中断启动。升级 carapace 后按一次真实 `Tab` 复验。
- 验收：重开终端后先在外部 CLI 参数位按一次真实 `Tab`（如 `scoop ins<Tab>`）触发懒加载（或用 `Enable-CxxuComponent Carapace -Now` 手动加载），再 `Get-Command carapace`、`carapace --version`、`carapace --list`（数量随版本变化，不写死）应可用；`TabExpansion2 'scoop install ' 14` 能返回包名候选，`TabExpansion2 'gh pr ' 6` 能返回子命令。直接调用 `TabExpansion2` 不会触发 Tab 懒加载。5.1 下再验 `git checkout <Tab>` 能出分支，`git status --sh<Tab>` 能出 `--short`、`--show-stash`，菜单描述为纯文本且中文不乱码，输入行无零宽字符残留。
- 状态检查：二进制、安装与启用、运行态与实际补全的分层检查见 [Deploy-Guide](Deploy-Guide.md) 的「可选：carapace」；`doctor -Feature Carapace` 可先看开关与依赖结论，git 补全归属用 `Get-GitCompletionSource` 核对。`Get-CxxuComponent -Id Carapace` 额外给出 `Runtime`（未安装/未启用/待参数位 Tab/已加载/未加载）、`RegisteredCommands`、`CachePath` 与 `CacheState`（5.1 上下文缓存是否有效及重建原因）；缓存过期或候选缺失时用 `Reset-PsCommandCache` 清理，新开终端后首次参数补全时重建。
- 启动成本：注册懒加载桩约毫秒级；首次外部 CLI 参数补全时一次性约 0.2–0.3 秒（随版本与主机变化），之后不再重复。`carapace` 不纳入 `Deploy-CompletionStack` 的 `-Include*` 层，但已进入 `Get-CxxuDependencyReport` 与 `doctor -Feature`。
- 慢补全：`winget install` 约 3.3 秒、`uv add` 约 4.4 秒，按 Tab 会同步等待；写入 `PsCarapaceExcludes` 排除。
- 错误候选：命令未安装或上下文缺失时会出现 `ERR` / `_` 候选（例如没有 `package.json` 时的 `npm run`）；写入 `PsCarapaceExcludes` 排除。
- 回滚：`Disable-PsPlugin Carapace -Persist`（当前会话立即生效，重开终端后不再加载）；包管理器渠道按对应命令卸载（`scoop uninstall carapace-bin`、`brew uninstall carapace`），`Deploy-Carapace` 与手工渠道删除二进制（默认 Windows 为 `~/.cxxu/bin/carapace.exe`，其他平台为 `~/.local/bin/carapace`）并从 PATH 移除。bash 侧用 `bash /path/to/scripts/bash/carapace/setup.sh --disable`（登录 shell 加 `--login`）移除 rc 片段，与 PowerShell 侧互不影响；重复执行 `Deploy-Carapace -Bash` 只刷新同一个标记块。

**Git Bash / MSYS 与 Linux/macOS bash（可选，与 PowerShell 独立）**：

Git Bash 使用同一个 carapace 二进制，Linux/macOS 使用各自平台的二进制；接入由 bash 自己完成，不经过 `init`，`PsCarapace` 与 `Enable-CxxuComponent` 只控制 PowerShell。非登录 shell 通常写 `~/.bashrc`；macOS Terminal、Git Bash 等登录 shell 读 `~/.bash_profile`、`~/.bash_login` 或 `~/.profile`，用 `bash /path/to/scripts/bash/carapace/setup.sh --login` 写入。二进制与 rc 一次接好时用 `Deploy-Carapace -Bash`（登录 shell 加 `-BashLogin`），它内部调用同一个 `setup.sh`。macOS 自带 bash 3.2 不满足 carapace 要求，需 `brew install bash` 并切换登录 shell；macOS 默认 zsh 不在该接入范围。运行 `bash /path/to/scripts/bash/carapace/setup.sh [--login]` 写入标记块，`--disable` 停用（不删除二进制）；平台差异、手工片段、PATH 修复、与 argc-completions 的顺序和验收见 [bash/carapace/README.md](../../bash/carapace/README.md)。多个候选需按两次 `<Tab>`；`gh` 未安装时静态子命令仍可补全，需要上下文的动态候选才依赖命令本身。本机 Git Bash 5.2 + carapace 1.8.2 实测运行时脚本 `source` 约 40–55 ms，`git checkout` 返回带说明的候选，`gh pr` 返回静态子命令候选。

**git 补全对比（同一测试仓库）**：

| 维度 | carapace | git-completion | argc-completions |
|---|---|---|---|
| 分支、标签、提交 | 强；`checkout --` 返回 ref 而不是修改文件 | 强且语义准确 | 弱：`checkout`、`switch`、`merge`、`rebase`、`reset`、`branch` 在本机回退为文件补全 |
| 选项覆盖 | `commit -` 65 项、`log -` 263 项、`checkout -` 40 项，均带说明 | `commit --` 39 项带说明；`log -` 仅 3 项；`checkout -` 仅 12 个短选项 | `commit --` 41 项、`log --` 164 项，带说明 |
| 文件与状态过滤 | 有状态标记；`commit` 混入未跟踪，`clean` 混入已修改，`rm --cached` 混入未跟踪 | `commit` 排除未跟踪，`checkout --` 只列已跟踪文件（排除未跟踪），`rm --cached` 只列已跟踪 | `add`、`checkout --` 可用；`checkout --` 混入未跟踪，`commit` 列原生文件，`rm --cached` 混入 `.git` |
| 特殊路径 | 支持 `-C` 与 `HEAD:`；不支持 `--git-dir` | 支持 `-C` 与 `--git-dir`；不支持 `HEAD:` | 支持 `HEAD:`；`-C` 仅部分命令可用 |
| PowerShell 适配 | 外部进程；5.1 需 Tab 桩绕过 `-` 开头词并去掉 ANSI；空结果在 pwsh 7.6 会打断 Tab；需要 `MenuComplete` | 纯 PowerShell 模块，最稳 | 依赖 `argc.exe` 与 bash 脚本；有 `PsArgc` 开关 |
| 延迟（本机） | 静态选项约 19–75ms；git ref 约 150–370ms | 首次约 470ms，之后约 20–310ms | 首次注册约 150ms，之后约 20–220ms |

结论：git 继续用 `git-completion`；carapace 用于 `scoop`、`winget`、`gh`、`docker`、`kubectl`、`cargo`、`uv`、`npm` 等非 git 命令；argc 保留为 800+ 命令的补充。carapace 与 argc 的命令重合有限（本机 743 与 841 中约 271 个同名），不是互相替代关系。

> 实测条件：`pwsh 7.6.3`、`PSReadLine 2.4.5`、`carapace-bin 1.8.2`、`git-completion 2.1.0`、`argc 1.24.0`；argc 测试时临时设 `$env:PsArgc='True'`。候选数量与延迟会随版本和仓库状态变化。

## 8. FAQ（续）：补全候选与预测视图

- 先看 ListView 的候选**来源**：它只显示历史 + 插件（`HistoryAndPlugin`），Tab 走的是另一套
  全量索引——两边结果不一样是正常的，不是谁坏了。
- `get-child` 这类没候选，先分清是哪一层：
  - ListView（边输边弹）：应出现 `[CxxuCommand]` 来源的 `Get-ChildItem`。`CompletionPredictor`
    在源码层跳过 `CommandName`，命令名候选只由 `CxxuCommand` 提供；它没出现时先查
    `$env:PsPredictor` 与活件（§9）。
  - Tab 菜单：原生索引本来就能补到 `Get-ChildItem`；连写前缀的模糊增补走 `CxxuTab`
    （默认开），不达预期按 §9 的「Tab 补全自查」定位。
  - 输 `get child`（有空格）时第二段已进参数位，两套补全都不会把它当命令名——多片段请连写。
- 想要 zsh-autocomplete 那种悬浮面板：原生没有（predictor 须 20ms 内返回，慢同步的
  TabExpansion2 镜像不了）。**自研 predictor 已落地并真机验证通过**（`CxxuPredictor`，
  只做裸命令名，按可信度分层：
  别名精确（`ls`/`gci`/`ps` → 目标命令）→ 完整前缀 → 词边界/首字母（`gci`、`getser`、`chitem`）→
  从词边界起的连续片段 → 一般子序列（按间隔扣分排序，`groute` → `Get-NetRoute`）；
  同层内按“匹配质量 → PSReadLine 历史频率”排序，默认返回 15 条。
  别名本身也作为候选（`gci` 会同时列出 `gcim` 这类同前缀别名），不按层级裁剪；`ls` 等别名精确命中时目标命令排第一。
  严格通配符（`get-*ive` 精确首尾）不受影响。
  注意空格天然分词——光标后 token 进了参数位，预测器的 CommandName 门直接返回空，
  所以多片段 AND 只存在于 API 层，活体里请连写；`get-child` 出 `[CxxuCommand]` 来源行；
  打全名（如 `get-childitem`）时不再提示更长的命令；当会话卸载用 `Remove-Module CxxuPredictor`，
  彻底移除见 §9）。参数位首个 `-` 的静态 flag 由同一 dll 的 `CxxuArgcFlags` 补充，边界见 §10。
   重型外挂不再考虑（`inshellisense` 用户已否决；`hintshell`/`PSCue`/`PSPredictor` v2 观察）。
- 关预测：`predictNo`（当会话有效）；切回行内视图：`Set-PSReadLineOption -PredictionViewStyle InlineView`
  或按 `F2` 切换。彻底不用看 §9（删活件 + 关 `$env:PsPredictor`）。
- **ListView 为什么最多显示 10 行**：硬编码（`ListViewMaxHeight`，历史固定占前 3 行），
  **没有设置能改**（官方 issue 有人提过，未开放）。2.3+ 可用 `↑`/`↓` 滚动，最多翻到 50 条；
  要全量翻历史用 `Ctrl+R`（PSFzf 模糊搜）。`CompletionQueryItems=100` 是另一套
  （Tab 菜单的阈值），别混了。另：历史源内部还有个 `HistoryMaxCount=10` 的硬上限——
  历史最多只贡献 10 条；总数到不了 50 往往是插件对该输入没返回（总数=历史+插件），不是卡住了。

## 9. dll / 活件管理（检查 / 安装 / 更新 / 移除）

> 设计原理见 `Live-Versions.md`（并排版本 + 指针）。背景一句话：`CxxuPredictor` 的 net9.0 自研 dll 提供内联预测（pwsh 须 7.5+；7.5/7.6 均可，7.6 基于 .NET 10，可直接加载 net9.0 产物）。仓库里的 `PS/CxxuPredictor/CxxuPredictor.dll` 是**源**（从不被加载，所以 `git pull` 永不撞锁）；真正被加载的是外置**活件** `~/.cxxu/bin/<哈希>/CxxuPredictor.dll`（由 `~/.cxxu/bin/current.txt` 指针选中）。两边靠哈希同步，程序集随进程：**同步后必须重开终端才换新代码**，`ipmox` 刷不动 dll。原则：入口 loader 只静默装载（旧版照用，零警告），版本动作全手动。
>
> 5.1 另有 Tab-only 产物 `~/.cxxu/bin/ps51/<哈希>/CxxuPredictor.dll`（netstandard2.0，只保留 `CompleteCommand`，由 `CxxuTab` 按字节装载；5.1 引擎没有预测子系统，不能注册 ListView predictor），同由 `Sync-CxxuPredictor` 发布。

| 动作 | 命令 | 说明 |
|---|---|---|
| 检查 | `doctor` / `Test-PsEnvReadiness` | `doctor` 先跑（安装态 + 运行态，含 `Tab 包装`/`Tab 缓存` 行，Windows 另有 `CxxuTab 5.1`）；只查预测器用 `doctor -Feature Predictor`；readiness 活件行备注直接给出结论（`与仓库一致[hash]` / `不一致→执行 Sync-CxxuPredictor`），表尾另有仓库/pwsh/活件三行 |
| 检查依赖 | `Get-CxxuDependencyReport [-Missing]` | 按功能列外部命令、PS 模块、argc 组件与活件状态，表后给安装建议；只读、零网络，详见 [Feature-Dependencies.md](Feature-Dependencies.md) |
| 检查远端 | `Test-PsEnvReadiness -CheckRemote` | 默认零网络；加开关才询问远端是否有更新（`ls-remote` 只读，12s 超时） |
| 安装 | `Sync-CxxuPredictor` | 无活件时生成两套产物（net9 predictor 写 `~/.cxxu/bin/<哈希>`；5.1 Tab 写 `~/.cxxu/bin/ps51/<哈希>`）并更新各自指针，缺目录自动创建；`-WhatIf` 可空跑查看意图 |
| 更新 | `Update-ReposesConfiged` → 重开终端 → `init` | 拉取后自动调用 `Sync-CxxuPredictor` 同步活件（只新增版本目录，不受锁限制，任何会话都可执行）；纯文本变更执行 `ipmox` 即可（见 §3） |
| 移除 | `Sync-CxxuPredictor -Uninstall`（有其他会话锁定加 `-Force`） | 删除两套指针与版本目录（含 `ps51`）；被会话锁定的版本删不掉会报告，下次再收；`Remove-Module` 不能卸载程序集（锁随进程存在，已实测）；彻底停用请持久化 `$env:PsPredictor='False'`（5.1 Tab 另加 `$env:PsTab='False'`），否则下次同步或更新会重新安装 |
| 自编译 | 先 `dotnet build`（见 `Live-Versions.md §10`），再 `Sync-CxxuPredictor -DllPath <产物>`；5.1 Tab 用 `-Ps51DllPath <产物>` | macOS/新版 pwsh 与仓库源 dll 的 SMA 对不上时用；不碰仓库源，检查端显示 `自编译版本[哈希]` 属正常，`Update-ReposesConfiged` 会保持活件不动 |

- 5.1 Tab：`Sync-CxxuPredictor` 生成的 `ps51` 活件由 `CxxuTab` 在 PowerShell 5.1 下选用；默认开，首个 Tab 才导入模块并读命令表缓存（缓存缺失时现建）。不需要时 `Disable-PsPlugin Tab -Persist`（或 `$env:PsTab='False'` 后重跑 `init`）。只提供 Tab 菜单，不提供边输边弹的内联预测。
- 自编译 net9 活件保持不动时，更新流程只对 5.1 Tab 活件调用 `Sync-CxxuPredictor -Ps51Only`；手动等价命令相同。
- 拉取网络：`Update-ReposesConfiged` 按名单分流——`$CommonRepos` 走 GitHub（默认 `https://gh-proxy.com` 加速），其余仓库走 gitee；`-RepoSource github|gitee` 本次强制统一源，`-NoMirror` 直连、`-GithubMirror` 换镜像、`-Proxy`/`-NoProxy` 控制代理；优先级与 `-Force` 的丢弃范围见 [Deploy-Guide.md](Deploy-Guide.md) 的更新章节。
- 守护进程（报时/IP）默认不碰 dll：`Start-StartupBgProcesses` 置 `PsPredictor=False` 继承 + 两个守护函数按 `-Command` 自断，所以 `-Force` 关它们无压力（无状态，重起即回）。
- 同一结论在 `Test-PsEnvReadiness` 的“建议”行也会再说一遍（缺必备 > 有更新 > 活件不一致）。

**加载失败排查**（先跑 `doctor`，再按行对照）：

| 现象 | 先查 | 处理 |
|---|---|---|
| `doctor` 报 `pwsh 7.5+` 必备项缺失 | `$PSVersionTable.PSVersion` | 升级到 7.5 及以上；7.6 可直接用，不需要重编 dll |
| 活件存在但未加载 | `$Error[0]`、`$global:PsUxLoadErrors` | 看具体异常；多为 SMA 代际不匹配，按 `Live-Versions.md §10` 用本机 SMA 重编后 `Sync-CxxuPredictor -DllPath` |
| 脚本或模块被策略拦 | `Get-ExecutionPolicy -List` | 先按 Scoop 同款前置设置 `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`；仍被下载标记拦截时执行 `Unblock-File`；`MachinePolicy`/`UserPolicy` 由组策略控制，需管理员 |
| 下载的 zip 解压后提示未签名 | `Get-Item <文件> -Stream Zone.Identifier` | 对解压目录执行 `Get-ChildItem -Recurse` 再接 `Unblock-File`（MOTW 只影响 `.ps1`/`.psm1`，不影响 dll） |
| 同步后行为没变 | `doctor` 的 predictor 行 | 重开终端；`ipmox` 刷不动 dll |

- 执行策略只约束脚本与模块脚本文件，不约束 `.dll`；dll 加载失败时改执行策略无效。临时一次性运行也可用 `powershell -ExecutionPolicy Bypass -File ...`，日常保持 `RemoteSigned`。

**Tab 补全自查**（`CxxuTab` + `argc`；先跑 `doctor`，看 `Tab 包装`、`Tab 键`、`Tab 缓存`、`argc 补全` 行，Windows 另看 `CxxuTab 5.1` 行；只查 Tab 层用 `doctor -Feature Tab`，只查 argc 层用 `doctor -Feature Argc`）：

| 检查项 | 命令 | 正常表现 |
|---|---|---|
| 开关 | `$env:PsTab` | 空（默认开）或 `True`；只有 `False` 才是关闭 |
| 摘要开关 | `$env:PsTabSynopsis` | 空（默认开）或 `True`；显式 `False` 才关闭；只影响菜单摘要，不影响候选 |
| 未加载模块的函数没有摘要 | 5.1 不启用源码解析；模块为二进制或帮助写在 MAML；候选超过 20 个时跳过 | pwsh 7+ 用更短的前缀（候选 ≤20）再按一次 Tab；或先 `Import-Module <模块>` / 用一次该函数；5.1 同样先导入模块 |
| 模块 | `Get-Module CxxuTab` | 首个 Tab 后应有；5.1 与 7 都靠它装包装 |
| dll 方法 | `$global:__CxxuTabMethod` | 非空；空 = 活件没找到或加载失败 |
| 命令表缓存 | `Get-ChildItem $HOME\.cxxu\cache\tab-commands-*.tsv` | 存在且 24h 内为命中；过期/缺失会自动重建；比仓库模块文件旧时 `init` 会删除（只对新终端生效） |
| 包装/桩 | `doctor` 的 `Tab 包装` 行 | `CxxuTab 包装已装入` 或 `桩已装,首个 Tab 自动装入` |
| 熔断 | `$global:__CxxuTabFuse` | 正常为 `$false`/空；`True` 表示本会话已退回原生 Tab |
| argc 仓库 | `$env:ARGC_COMPLETIONS_ROOT`、`<根>\completions`、`argc --argc-version` | 根有值且 `completions` 在；`get-command argc` 有输出（仓库 `bin` 或 PATH，macOS/Linux 用系统安装的 argc）；空 = 未部署（`Deploy-CompletionStack -IncludeArgc` 可装） |

| 现象 | 原因 | 处理 |
|---|---|---|
| Tab 只有原生候选，没有 `CxxuTab fuzzy:` | `$env:PsTab` 被显式关；`CxxuTab` 未导入；`__CxxuTabMethod` 为空；5.1 缺 `ps51` 活件 | 按上表逐项查；`Enable-PsPlugin Tab`；5.1 执行 `Sync-CxxuPredictor` 后重开终端 |
| Tab 完全没反应（连原生候选也没有） | Tab 键绑定异常（旧会话/argc 桩残留），或 PSReadLine 未加载 | `doctor` 看 `Tab 键` 行；`Import-Module Init -Force; init -Force` 或重开终端 |
| 应用命令的 `-` 参数没候选（如 `nginx -<Tab>`） | argc 未部署；`argc --argc-shell-path` 的 bash 不存在；`PsArgc=False` | 跑 `Deploy-CompletionStack -IncludeArgc` 或 `Deploy-ArgcCompletions`；`doctor` 看 `argc 补全`/`Tab 键`；细节见 Argc 文档 §7 |
| `nginx <Tab>` 的文件名候选中文乱码 | 当前会话在修复前启动，仍用旧 completer | 重开终端或 `Initialize-ArgcCompletions -Force`；当前 completer 固定按 UTF-8 读取 argc 输出，不随控制台代码页变化 |
| 首个 Tab 卡 0.1~0.4s | CxxuTab 首次导入与读表、首次按需解析摘要；外部 CLI 参数位还会注册 argc/carapace | 命令名位不加载 argc/carapace；用相同输入在同一窗口复测，区分一次性加载与持续慢补全。缓存缺失/过期时重建，清空缓存会增加下次首次耗时 |
| 候选里缺新装模块的命令 | 缓存仍是旧表，或当前窗口在更新前已建表 | 仓库更新后 `init` 会自动删除比模块文件旧的缓存；执行 `Reset-PsCommandCache` 并重开终端可立即刷新。原生 Tab 的前缀匹配不受缓存影响 |
| 用一会儿后突然只剩原生候选 | 自熔断触发（单次调用 >800ms 或异常） | `$global:__CxxuTabFuse` 为 `True`；重开终端恢复；反复出现查主机/杀软扫描 |
| 5.1 完全没有模糊增补 | `ps51` 活件/指针缺失，或 `PsTab=False` | `Sync-CxxuPredictor` → `doctor` 的 `CxxuTab 5.1` 行；确认开关 |

命令表在每个进程**只建一次**（predictor 构造时、Tab 首次调用时各建一份内存表）。因此删除缓存或 `init` 自动清理都只影响之后启动的进程：当前窗口继续使用旧表，必须新开终端；新终端首次 Tab 或 predictor 首次触发时才重建。

需要按用户视角自动复验界面效果（真实窗口、按键注入、读屏与截图）时，见 [交互式控制台验证](Interactive-Console-Verification.md)。

## 10. 补全全景速查（三层 + 参数层）

| 层 | 按键/视图 | 来源 | 说明 |
|---|---|---|---|
| Tab 全量索引 | `Tab`（MenuComplete） | 引擎全量：函数/别名/文件/参数 | 命令名位经 `CxxuTab` 包装增强（模糊连写可选中，选中函数时显示 `.SYNOPSIS` 首段与参数语法；参数位零干扰；默认开，置 `$env:PsTab='False'` 关）；和下面两层**不是同一套索引**，结果不一样正常 |
| ListView 预测 | 输入时自动浮现（`HistoryAndPlugin`） | 历史（最多 10 条，硬上限）+ 插件 | 插件= `CompletionPredictor`（参数/路径，命令名位跳过）+ `CxxuPredictor`（命令名，分层排序 + 别名/历史加权，默认 15 条，§8）+ `CxxuArgcFlags`（argc 覆盖命令的首个参数位，`-` 前缀，静态 flag ≤10 条；7.5+）；须 20ms 内返回，实测 2600 条 <1ms、flag 查表 <1ms |
| 模糊搜历史/文件 | `Ctrl+R` / `Ctrl+T`（PSFzf） | 全量历史/文件 | 历史翻不完用这个，不走 10/50 上限 |
| 参数值补全 | `Tab` 在参数位 | `argc-completions`（800+ 命令库，开关默认开、懒加载；按需 `-IncludeArgc` 部署）+ `PSCompletions`（~200 命令库，可选）+ 自带 `ArgumentCompleter`（EnvVar 系、`Get-Json -Key` 等，`Set-ArgumentCompleter` 批量注册） | PSCompletions 用法：装模块后 `Enable-CxxuComponent PSCompletions -Persist`；argc 开关 `$env:PsArgc`，首次参数补全时注册；`git`/`gitk` 由 `git-completion` 提供，argc 不重复注册 |

- 参数值补全还有可选的 carapace 来源（由 `PsCarapace` 控制，见本文「carapace（可选，非默认）」）：适合 `scoop`、`winget`、`gh`、`docker`、`kubectl`、`cargo`、`uv`、`npm` 等外部 CLI；git 来源由 `PsGitCompletionSource` 决定。
- **Tab 菜单顺序**：原生前缀命中排在前并保持原生顺序，`CxxuTab` 的模糊补充按 dll 的 tier/分数顺序排在后面，同名去重。输入完整前缀时第一次 Tab 落在原生候选；只有没有原生前缀命中（如 `uprepos`）时，才由模糊结果主导。
- **Tab 菜单摘要**：选中项若是函数（或其别名）且带注释帮助，菜单下方显示 `.SYNOPSIS` 首段与参数语法。已加载函数直接取定义文本；未加载模块的函数在 pwsh 7+、候选不超过 20 个时读模块源文件解析（不导入模块），首次每模块约几十毫秒、之后缓存；5.1 只覆盖已加载函数。cmdlet、二进制模块与帮助写在 MAML 的函数保持原生提示。摘要不调用 `Get-Help`，不因候选触发模块自动加载；重新定义函数后下一次 Tab 自动刷新；不需要时置 `$env:PsTabSynopsis='False'`。
- **菜单中的 Ctrl+C**：真实按键在默认控制台模式下会被当作控制事件，Tab 菜单不响应；只把 `Ctrl+C` 绑到 `CancelLine` 也不会生效。要取消整行，按 `Esc` 关闭菜单（恢复输入前缀）再按 `Ctrl+C`；若要一次 `Ctrl+C` 直接清行，需在 Tab/MenuComplete 包装里临时设置 `[Console]::TreatControlCAsInput = $true` 并绑定 `CancelLine`（原理、验证与示例见 [交互式控制台验证](Interactive-Console-Verification.md)）。该包装只在菜单显示期间生效，命令执行时的 Ctrl+C 中断不受影响。
- 相关命令：`doctor`（统一诊断入口，定位问题先执行它；`doctor -Feature <功能>` 只查单个功能）、`Get-CxxuDependencyReport [-Missing]`（按功能查外部依赖与安装建议，详见 [Feature-Dependencies.md](Feature-Dependencies.md)）、`Register-PsUxLazyLoad [-Now]`（延迟加载入口）、
  `Deploy-CompletionStack [-WhatIf] [-IncludeArgc] [-IncludeFuzzy] [-IncludePredictor] [-IncludePSCompletions] [-IncludeGitCompletion] [-All]`（新机一键装栈）、
  `Test-PsEnvReadiness`（查缺）、`predictNo`（当会话关预测）、
  `Enable-PsPlugin` / `Disable-PsPlugin`（插件启停，Fzf/Zoxide/Predictor/Tab/Argc/GitCompletion/Carapace/PSCompletions/Fnm/ScoopSearch）。
- `doctor -Feature` 与 `Get-CxxuDependencyReport -Feature` 支持 Tab 补全，候选为正式短名（`Core`、`Argc`、`Carapace`、`GitCompletion` 等）；完整对应表见 [Feature-Dependencies.md](Feature-Dependencies.md)。
- **历史膨胀（Ctrl+R 变慢）**：`Optimize-PsHistory -WhatIf` 先看诊断（总数/去重率/重复 Top5）， `Optimize-PsHistory [-KeepLast 3000]` 动手（去重只留最后一次 + 去杂 + 截断，旧行进同目录 `.archive-时间.txt`，原文件留 `.bak-时间`，均可恢复）。治本：init 已开 `HistoryNoDuplicates`（新命令不再重复入库）+ `MaximumHistoryCount 3000`。注意历史文件无时间戳，切割按新旧顺序（文件尾=最近）；当前会话内存里的旧历史重启才换新。
- 新终端对照：ListView 输 `get-child` 应出现 `Get-ChildItem`（`[CxxuCommand]`），Tab 输 `get-chi` 也应含它；`get child`（有空格）第二段进参数位，不会按命令名补（§8）。仍不对就按 §9 的「Tab 补全自查」/`doctor` 定位。

### 参数自动提示的边界（为什么不是 argc 全量）

- 三条管线互不相通：`Tab` 走 `CommandCompletion/MenuComplete`（全量、带描述、可选中），
  自动提示走 `ICommandPredictor`（只接受整行文本 + tooltip，没有描述列/反显/菜单语义）；
  PSReadLine **没有**“输入即自动开 MenuComplete”的开关。
- `CompletionPredictor` 看不到 argc：它在私有 runspace（`InitialSessionState.CreateDefault`）
  里调 `CommandCompletion`，用户会话 `Register-ArgumentCompleter -Native` 的 846 个 completer 不在其中。
  实测：`Get-ChildItem -F` 有 4 条（内置），`nginx -`/`docker --con` 0 条，`nginx -s r` 反而回退成 4 个文件名。
- 所以“argc 全量自动提示”只能自写 predictor 每次按键调 `argc --argc-compgen`。本机实测：
  裸 compgen 8–13ms（静态 flag），完整补全调用 `nginx -` 16–18ms、`docker --con` 57–70ms、
  `git ch` 84–184ms、`git checkout ` 83–135ms；PSReadLine 预测预算约 20ms，慢命令会拖预测，
  且 ListView 只剩整行文本、描述丢失。
- 现方案（`CxxuArgcFlags`，与 `CxxuPredictor` 同一 dll 的第二个 predictor）：
  从 `completions/*.sh` 顶层 `@flag/@option` 注释预生成静态表（缓存 `~/.cxxu/cache/argc-flags.tsv`，
  约 3 万行/1.9MB；补全脚本更新后首个会话自动重建，冷建表约 100ms、热读表约 30ms，都在 OnIdle 单发里）；
  只处理 **argc 覆盖命令的首个参数位** + 当前词以 `-` 开头，查表 + 前缀过滤，<1ms，不启动进程。
- 范围/限制：只覆盖顶层 flag（`# {{` 子命令块不解析，`docker run -`、`git checkout -` 这类走 Tab）；
  动态值（分支、容器、文件）仍走 Tab；不改变 `Tab`/`CompletionPredictor` 的现有行为；5.1 没有插件预测视图（升级 PSReadLine 后只有历史预测），参数仍走 Tab。
- 关闭：`Disable-PsPlugin Argc`（predictor 每次调用读 `$env:PsArgc`，立即停供稿，Tab 也停）；
  只关预测用 `Disable-PsPlugin Predictor`；强制重建表删 `~/.cxxu/cache/argc-flags.tsv` 或重开终端。
- 实测（pwsh 7.5.4，新 dll）：`nginx -`→10 条（`-?`/`-h`/`-v`/`-V`/`-t`/`-T`…）、`docker --con`→2 条、
  `git -`→10 条顶层 flag、`git checkout -`→0、`Get-ChildItem -F`→0、`nginx -s reload`→0、`PsArgc=False`→0。
- 部署最短路径（详见 [Argc-Completions-Deploy](Argc-Completions-Deploy.md)）：
  `Deploy-CompletionStack -IncludeArgc`（或单跑 `Deploy-ArgcCompletions`）→
  仓库与 `bin\argc.exe`/`bin\yq.exe` 就位 → 重开终端/`init`（首次参数补全时注册 completer）→
  更新仓库后 `Initialize-ArgcCompletions -Force`；5.1 用自带 PSReadLine 2.0 即可，需要历史预测/ListView 时按 [Deploy-Guide](Deploy-Guide.md) 的 PSReadLine 升级步骤处理。
- 部署/更新/开关/排障全文：[Argc-Completions-Deploy](Argc-Completions-Deploy.md)。

## 11. 手动启用清单（自动导入之外的东西）

> 分界：`PSModulePath` 自动发现 + `init` + 延迟加载 + 缓存自建都是自动的，
> 以下只有"缺了才管"，`Test-PsEnvReadiness` 的"可选"行即体检口（`doctor` 同步可见）；
> 逐项外部依赖状态用 `Get-CxxuDependencyReport -Missing` 查，完整清单见 [Feature-Dependencies.md](Feature-Dependencies.md)。
> 组件缺失时的统一入口：`Get-CxxuComponent | Select-Object Id, Enabled, Install, Enable | Format-Table -Wrap`。
> 先按 `Install` 安装依赖，再按 `Enable` 启用；想当会话立即生效，执行 `Enable-CxxuComponent <Id> -Persist -Now`。

| 功能 | 默认状态 | 手动启用 | 说明 |
|---|---|---|---|
| `PSCompletions`（~200 命令参数补全） | 未装；组件 `PSCompletions` 默认关 | `Deploy-CompletionStack -IncludePSCompletions`，再 `Enable-CxxuComponent PSCompletions -Persist` | 由 `init` 导入模块；旧注"可能导致 `ipmof`/`iex` 报错"已过期（白名单+`ipmox` 时代） |
| `fzf` / `zoxide` 二进制 | 无则 `Ctrl+T/R`、`z` 不可用（不影响 CxxuCommand） | `Deploy-CompletionStack -IncludeFuzzy`（scoop→winget/brew→`scripts-deps` 转存→上游），或 `scoop install fzf zoxide` | 装完重开终端，init 缓存自建 |
| `scoop` 本体 | 无则二进制系列全停 | 按官网装，或 `Deploy-ScoopByGithubMirrors`（国内） | 装完补 buckets（`Add-ScoopBuckets`） |
| `conda` | 无则 prompt  conda 段静默缺失 | `Deploy-MiniforgeConfig`；`$condaExe` 路径按机器对（profile 缓存块） | 缓存 `~/.conda_hook_cache.ps1`，首跑慢一次 |
| `fnm` + 钩子 | 未装；组件 `Fnm` 默认关 | `scoop install fnm`（或 `brew install fnm`），再 `Enable-CxxuComponent Fnm -Persist` | `init` 执行 `fnm env --use-on-cd`；node 用户才需要 |
| `scoop-search` 钩子 | 组件 `ScoopSearch` 默认关 | `scoop install scoop-search`，再 `Enable-CxxuComponent ScoopSearch -Persist` | `init` 注入 `scoop-search --hook` |
| `argc` 整块 | 未部署 | `Deploy-CompletionStack -IncludeArgc`（或 `Deploy-ArgcCompletions`） | 由 `init` 的 `Set-ArgcCompletions` 懒加载；装完重开终端/`init` |
| `carapace-bin` | 可选，`PsCarapace` 默认 `$false` | `Deploy-Carapace -Enable`（推荐，安装并启用），或安装后再 `Enable-CxxuComponent Carapace -Persist`；也可用官方 GitHub Release 产物或包管理器（`scoop install carapace-bin`、`brew install carapace`、Linux 发行版仓库） | `init` 只注册参数位 Tab 懒加载桩；不纳入 `Deploy-CompletionStack`；跨平台默认目录不同；版本可固定；git/gitk 归属用 `Set-GitCompletionSource` 切换 |
| `carapace`（Git Bash/MSYS 与 Linux/macOS bash） | 可选，与 PowerShell 组件独立 | `bash /path/to/scripts/bash/carapace/setup.sh`（`--disable` 停用，不删除二进制；登录 shell 加 `--login`；`--install` 装二进制、`--install-deps` 补依赖），或手工 source；步骤见 [bash/carapace/README.md](../../bash/carapace/README.md) | 不经过 `init`；PowerShell 的 `PsCarapace` 开关不影响 bash；macOS 系统 bash 3.2 需先换 bash 4+ |
| `posh-git` | 已安装，未导入 | 仅需提示符的 git 状态时才导入 | 其 git 补全与现有来源注册同名 completer，导入后按顺序覆盖，已有 `git-completion` 时不要混用 |
| prompt 主题持久化 | 当会话有效，重开复原 | `Set-PsPrompt -version <…> -Persist`（写注册表） | 临展用 `dm` 切极简，不持久化 |
| 开机任务 + 守护进程 | 未注册 | `Start-StartupTasks`（或 `Deploy-StartupTasks` 部署） | 报时/IP 守护，无状态，`-Force` 可杀 |
| WT 设置下发 | 仓库 `Config/wtConf*.json` 仅供参考 | `Deploy-WtSettings` | 线上 WT 无自定义 profile 时才需要；`settings.json` 为符号链接，改完配置需重启 WT 才生效 |
| github hosts 定时更新 | 未装 | `Deploy-GithubHostsAutoUpdater` | hosts 拉胯地区按需 |
| 镜像持久化 | 默认自动（静默测速+缓存） | `$env:PsGithubMirror` 持久化（`Add-EnvVar`）指定镜像 | 出国/回国切换用 |
| 开关组 | 组件默认值见 `PS/Init/components.psd1`，Settings 见 `PS/Init/config.defaults.psd1` | `~/.cxxu/config.psd1`（SchemaVersion=2；`New-CxxuConfigTemplate` 建模板）或 `Enable/Disable-CxxuComponent [-Persist]`；`Get-CxxuComponent` 看分组状态，`Get-CxxuConfig` 看平坦键，`Reset-CxxuConfig` 恢复仓库默认 | `PsFzf/PsZoxide/PsPredictor/PsTab/PsArgc/PsGitCompletion/PsGitCompletionSource/PsCarapace/PsCarapaceExcludes/PsCompletions/PsFnm/PsScoopSearch/PsShowProgress`；环境变量永远优先 |
| 历史瘦身 | 从不自动执行 | `Optimize-PsHistory [-WhatIf]`（超 8000 行或 500KB 时 `doctor` 会提示） | 备份+归档双保险 |
| pwsh 7.5+ 版本门 | 随安装 | `Update-PowerShell`（`CxxuPredictor` 需 net9；7.6 可直接用） | 不够 7.5 只缺 predictor，其余照常 |

- 新机按表自上而下过一遍即可；`Test-PsEnvReadiness` 全绿 + `doctor` 全绿 = 生效确认。

## 12. 非 Windows 说明（Linux/macOS）

> 本模块集按 Windows 日常开发，其它系统"核心可用、部署件受限"。`doctor` 与 `Test-PsEnvReadiness` 按平台过滤：Windows 专属检查（`scoop`、`CxxuTab 5.1`、守护(IP) 等）在 macOS/Linux 不显示，表尾汇总已跳过项；`平台` 行给出当前平台与限制。

- 可直接用：纯 pwsh 模块（自动发现/`init`/补全栈/`doctor`）；`CxxuPredictor` 是 net9.0（pwsh 7 跨平台可加载，dll 随仓库分发；仓库源点不亮时本地重编，见 `Live-Versions.md §10`）；活件/配置/历史/`Data.json` 全在 `$HOME` 下，路径跨平台；`Test-PsEnvReadiness` 的 `PSModulePath` 检查已做分隔符自适应（`:`/`;`），备注列按 Win/macOS/Linux 三平台给安装建议，scoop 等 Windows 专属行在非 Windows 不出现；`argc` 探测按平台使用 `completions/macos`、`completions/linux` 与 PATH 中的 `argc`。
- Linux 可用链（2026-09-25 静态链路梳理，非全模块真机验证）：`init` 热路径已跨平台（变量文件/活件路径全走 `Join-Path`，`Startup`/`Prompt` 的 CIM/注册表分支凭 PSEdition 兜底跳过，`Test-AdminPermission` 走 `id -u`）；`Update-ReposesConfiged` 更新链可用（含自编译保持）；`PwshVar` 在 Linux 下不套 Windows/macOS 专属变量文件（仅基础集），conf 里 Windows 路径变量会指向空，需按本机改。仍不可用：scoop/注册表/计划任务/WT/CIM 信息类（`Hardware`/`Info` 多数为 Windows 专属，调用即报错，不做跨平台适配）。
- 不可用（Windows 专属，不做跨平台适配）：`scoop` 系（安装/换源/buckets）、注册表持久化（`Add-EnvVar`、`Set-PsPrompt -Persist`、镜像持久化——改走 `$profile` 或 env 文件）、计划任务与开机（`Deploy-StartupTasks`/`Start-StartupTasks`）、WT 下发、CIM/WMI 信息类、`conda` scoop 路径、业务模块硬编码路径（如 WordPress/phpstudy、`C:\` 前缀）。
- 部分兼容：`PwshVar` 有分平台变量文件表（`$PwshVarFilesWindows`/`$PwshVarFilesMacOs`），新增变量按此模式分文件存放；`Info` 个别函数有 `$IsWindows`/`$IsMacOS` 分支，其余缺分支的函数在非 Windows 下报错即代表不支持。
- 建议：先跑 `Get-CxxuDependencyReport -Missing` 看外部依赖，再跑 `Test-PsEnvReadiness` 看安装态（Windows 专属项已按平台隐藏，剩下的按需补齐）；`PwshVar/confs/VarSet1.conf` 的 `$PC*` 主机名按本机添加。
- `typora` 命令：由别名 `typora` → `openApps` 的 `Start-Typora` 提供（首次调用才自动加载模块），macOS 用 `open -a /Applications/Typora.app` 打开文件或目录，省略参数只启动应用；支持管道（`Get-ChildItem *.md | typora`）。该别名优先于 PATH 中的同名程序，因此 `/usr/local/bin/typora` 变成失效符号链接时仍可用。

## 13. Windows PowerShell 5.1 兼容（B 档：交互可用）

> 目标是在 5.1 里 `init` + 提示符 + Tab/参数补全 + 历史可用；部署与插件内联预测明确留 7，Tab 补全走 5.1 专用 dll 活件。5.1 自带 PSReadLine 2.0.0，可选升级到 2.3.6 后可用历史预测与 ListView（见本节末尾）。
> 查数用命令（真相源是各模块自己的 `.psd1`，下面批次是流水账）：`Get-CxxuModuleCompatibility`（`Pwsh` 模块，只读文件头秒出：B 档 62/留 7 有理由/缺 BOM 或未声明单拎）。

- 兼容集（psd1 已降 `5.1`，psm1 带 BOM，见 `Module-Conventions.md §8`）：`Basic`、`Aliases`、`FileSystem`、`PwshVar`、`Search`、`CxxuTab`、`Prompt`、`Init`、`EnvVar`、`NetWork`、`RepoSync`、`PsDebug`、`PsEnv`、`Shortcut`、`PathProcess`、`Hardware`、`Proxy`（后 8 个 2026-09-22 酌情降档：解析零错误 + 5.1 直调冒烟通过）。
- 第二批（2026-09-22，从易到难：解析零错误 + 逐个 5.1 直调冒烟）：`Json`、`WinSys`、`Startup`（`$IsWindows` 加 `PSEdition` 兜底）、`ArgumentCompletion`、`Mock`（字符集自包含，旧代码依赖会话外变量）、`Users`、`Calendar`、`ColorSettings`（`inlineprediction` 配色按 PSReadLine 版本 gating）、`Browser`、`TestLinks`、`NetDrivers`、`ControlPanel`、`WIFI`、`HelpExamples`（教学函数需 help 文件）、`backup`、`BTCN`、`Cloudflare`。B 档 17→34。
- 第三批（2026-09-22，真语法错误只有几处）：`Pwsh`（1 处系 BOM 误报，加 BOM 即零错；另修 `Sync-ModuleManifest` 的 `Select-Object -ExpandProperty` 取哈希表键，5.1 不认，改点号取值）、`Deploy`（doctor 三元改子表达式 `if` + `$IsWindows` 文案分支加 `PSEdition` 兜底）、`Link`（三元改 `if`）、`openApps`（`Start-Process $p &` 的 `&` 冗余，`Start-Process` 本就不阻塞，去之行为不变）。B 档 34→38。`TaskSchdPwsh`/`TimeNotify` 的后台 `&` 在 5.1 无等价写法（`Start-Job` 另起进程且函数不可见，同步降级体验差），留 7 不降；`Get-GithubMirrorPrefix` 的交互选镜在非交互会话下 5.1/7 同炸（7 侧另有一处 `.Trim()` 老 bug），系环境非版本问题。
- 第四批（2026-09-22，小模块 + 真 bug 在运行时）：`Special`（补 BOM 即好，`Register-AlistStartup` 只验导入不直调，写计划任务副作用）、`Window`（`Show-Message` 弹窗只验导入）、`Security`（`Get-CredentialGuardStatus` 直调）、`RecycleBin`（`Get-RecycleBin` 直调）、`NetInfo`（`Get-NetConnectionInfo`/`Get-IpAddressForPrompt` 直调）、`Tools`（`pow`/`Test-CommandAvailability`/`Get-CxxuPsModuleVersion` 直调，`Description` 中文按 #46 铁律转英文，`Get-BeijingTime` 联网只验导入）。B 档 38→44。`Test` 是用户草稿区且 manifest 有幽灵导出，不碰。本批抓到运行时刻录：`Special` 无 BOM 时 5.1 报 `Missing ')' in function parameter list`（BOM 归一解析零错也拦不住，必须 5.1 真跑）；`NetInfo` 的 IP 缓存在 5.1 下读出 `浠?`（`Json` 模块读路径 `Get-Content -Raw` 按 GBK 解 UTF-8 缓存），已修 `Json` 4 处读 + 2 处写为 .NET UTF-8 直读写（零跨模块依赖），双向字节往返已验，5.1 的 prompt IP 回到 `以:192.168.0.104`。
- 第五批（2026-09-22，日常高频）：`Git`（`gitS` 直调，`Get-SpeedUpUrl` 联网只验导入；`Git.psm1` 有两处 `function git` 重复定义，后胜前，历史包袱不动）、`Scoop`（全 `Deploy/Set/Update` 副作用，只验导入）、`SSH`（全需远端主机/密钥，只验导入）。三模块 psd1 的 Description 本就是英文，无 #46 坑；补 BOM + 双版本 manifest 全绿。B 档 44→47。
- 第六批（2026-09-22，低风险本地组）：`TextProcess`（`Measure-AlphabeticChars` 等纯函数直调）、`Text`（`Format-FileSize`/`Get-CharCount` 直调，GUI 类只验导入）、`CSV`（自建小表 `Get-CsvPreview` 直调，`Get-CsvTailRowsGUI` 弹窗只验导入；注意 `Get-CsvPreview` 的 `$csv` 参数非管道绑定，必须具名传）、`ArchiveProcess`（`tar.exe` 现场打小包后 `Test-TarFile` 直调；修 1 处真 7 独占：`Split-Path -Extension` 是 6+ 参数，改 `[IO.Path]::GetExtension`，与 `TextProcess` 内既有写法统一）、`Info`（`Get-UserHostName`/`Get-MemoryUseSummary`/`Get-MemoryUseRatio`/`Test-SubItem` 直调；修跨模块运行时依赖：`Get-MemoryUseRatio` 调留 7 的 `TaskSchdPwsh` 的 `Start-ScriptWhenIntervalEnough`，5.1 探不到时直接 `& $s` 执行，与首建缓存分支行为一致，`Get-Command -ErrorAction Ignore` 探针无 `$Error` 污染）、`Sitemap`（`Test-SubItem` 直调；`Get-SourceFromUrls` 的 `ForEach-Object -Parallel` 只在 `-Threads` 非零时进并行分支，默认 0 走串行，5.1 不传参即安全，见 §13 串行分支惯例；`Sitemap:326` 的裸探针上轮已预修）。B 档 47→53。
- 第七批（2026-09-22，中风险组，只验导入 + 逐项注明）：`TerminalTools`（`Install-Scoop`/`Push-ByScp`/`Sync-CxxuPredictor` 高 stakes，只验导入）、`Development`（短名裸命令包装多，只验导入）、`DevEnv`（全 `Deploy` 写配置/装软件，只验导入）、`MySql`（需服务端+配置，只验导入）、`WinConfig`（注册表/Defender/激活/`Restart-OS`，`Description` 中文转英文，只验导入）、`Web`（`Test-IsIPAddress` 直调，其余 hosts/nginx/phpstudy 只验导入）、`WordPress`/`WpContent`（硬编码路径+外部依赖，只验导入）、`WpOnline`（`Test-IsIPAddress` 同源直调已验；`Start-ThreadJob` 在 5.1 非内置，需 `Install-Module ThreadJob` 才能真跑部署流，只验导入）。15 模块双版本 manifest 全绿（函数数两边一致）。B 档 53→62。剩余 7.0：`Whois`（34 个 `??` 待重写）、`TaskSchdPwsh`/`TimeNotify`（`&` 无等价写法留 7）、`Test`（用户草稿区不动）、`CompletionPredictor`（第三方不管）、`CxxuPredictor`（内联预测留 7；5.1 Tab 另走 ps51 构建）。
- 5.1 下自动降级：`init` 步骤表 `MinPS = 7` 的步骤静默跳过（`ArgumentCompletion`/`Startup`/`Pwsh`/`Json`）；`ForEach-Object -Parallel` 走串行分支；`Register-PsUxLazyLoad` 在 5.1 只装 CxxuTab 手势桩；`CxxuTab` 读 `~/.cxxu/bin/ps51` 的 netstandard2.0 活件（缺活件时纯透传），命令表缓存 `~/.cxxu/cache/tab-commands-4.tsv`；`HistoryNoDuplicates`/`inlineprediction` 配色按 PSReadLine 版本 gating（5.1 自带 2.0.0 跳过；升级到 2.1+ 后启用）。
- `argc-completions` 在 5.1 也可用：依赖现有 `argc.exe` + Git Bash（`bash`/GNU 工具在 PATH），PSReadLine 2.0 与升级后的 2.3.6 均支持 `MenuComplete`/`Selection`；首次外部 CLI 参数补全时注册约 200ms，之后零开销，开关 `$env:PsArgc`，与 7 同一套懒加载。5.1 的补全引擎不会把 `-`/`--` 开头的词交给 Native 补全器（6.0 才修），Tab 桩会在词首临时插一个零宽字符绕过（只对 argc/carapace 注册过的应用命令，cmdlet/函数参数补全不受影响；Esc 取消或选中后都会清掉，缓冲区不留字符）。
- `git`/`gitk` 的补全由 `git-completion` 提供，5.1 同样可用（init 检测到模块即挂载，首个补全才导入）。受同一条引擎限制，选项补全在 5.1 不触发，子命令、分支与文件补全正常。模块须位于 5.1 的 `PSModulePath` 中：`-Scope CurrentUser` 在 7 与 5.1 落在不同目录，只在 7 上装过时 5.1 不会挂载，安装步骤见 [Deploy-Guide](Deploy-Guide.md) 的「分层、来源与能力」。
- `carapace` 在 5.1 也可用：`Register-ArgumentCompleter -Native` 本身可用，`-` 开头的词由共享 Tab 桩插入零宽字符绕过引擎限制，因此参数、git ref 与 flag 都能触发；加载时会把 shell 名称列表落盘缓存并截断、用 UTF-8 读取 carapace 输出、去掉候选描述里的 ANSI（5.1 默认 2.0；升级到 2.3.6 后仍保留该处理，兼容未升级会话）。首次外部 CLI 参数补全约 0.4–0.6 秒（冷缓存约 1 秒），之后约 0.1–0.4 秒。启用与来源切换与 7 相同。
- 提示符全对齐：`fast`/`Simple`/`Short`/`Default` 原生可用；`Balance` 的 Info/Startup 外部依赖在 `Prompt.psm1` 顶部有 5.1 本地兜底（CIM/注册表/内置 cmdlet 同口径；必须 `function global:` 定义，否则模块私有、直接调用撞坏 Info；缓存用 `$global:__Cxxu51*`，`$script:` 跨不了作用域），渲染与 7.5 逐字一致，稳态约 50ms/次（首屏冷缓存 1.4s 一次性）；`Get-IpAddressFormated` 含参数集的移植版，直接调用也可用。
- 明确不可用：`CxxuCommand` 内联预测（net9 predictor，插件预测源需 7.2+）、完整部署流程（建议在 pwsh 7 执行，5.1 可单独运行 `Install-Ps51PSReadLine`）、`Test-PsEnvReadiness` 的 `pwsh 7+` 必备项（在 5.1 下即提示装 pwsh7）。PSReadLine 2.0 没有预测视图；升级到 2.2.6+ 后历史预测与 ListView 可用，但插件预测仍不可用。
- 5.1 Tab 补全可用（默认开）：`CxxuTab` 读 `~/.cxxu/bin/ps51/<哈希>/CxxuPredictor.dll`（netstandard2.0，只含 `CompleteCommand`），由 `Sync-CxxuPredictor` 发布。首个 Tab 才导入模块并读命令表缓存（命中约 20ms，缺失/过期时现建约 0.4s；缓存与排查见 §9「Tab 补全自查」），启动不加负担；默认只有 Tab 菜单，没有内联预测（升级 PSReadLine 后可用历史预测，见下）。不用时 `Disable-PsPlugin Tab -Persist`。
- 用法：`powershell -NoProfile` 起 5.1，保证 `PSModulePath` 含模块集后 `init` 即可；Tab 包裹默认开，`$env:PsTab='False'` 关。
- **PSReadLine 升级（可选）**：默认不升级，保持 5.1 原样；需要历史预测、历史去重与 `inlineprediction` 配色时执行
  `Deploy-CompletionStack -IncludePSReadLine51`，或单独 `Install-Ps51PSReadLine`（默认 2.3.6；优先离线复制本机 pwsh 自带模块，缺失时才从 PSGallery 安装；`-Latest` 取 PSGallery 最新稳定版）。
  目标目录为 `~\Documents\WindowsPowerShell\Modules\PSReadLine\<版本>`；默认还会把该模块目录前插到 User 级 `PSModulePath`（`-NoPersistModulePath` 可跳过），否则 PSReadLine 可能在 `init` 之前就加载系统自带的 2.0.0。
  完全重开 5.1 生效；`init` 会在 5.1 下改用 `PredictionSource History`，再按版本启用 ListView/InlineView。
  安装不依赖 pwsh 7：没有 pwsh 时用 `-Version` 走 PSGallery，完全离线用 `-SourcePath <目录>`（含 `PSReadLine.psd1` 与 `net462`/`netstd`）；不使用同步入口时，pwsh 升级不会改变 5.1 的版本。
  `pwsh` 升级不会自动传导到这份副本：需要跟随时用 `Sync-Ps51PSReadLine`（`-CheckOnly` 先看两边版本），或给部署层加 `-PSReadLine51FollowPwsh`；只报告、不降级，缺少可加载资产（`net462`/`netstd`）的新版本会跳过。
  2.3.x 的资产目录是 `net462`，2.4.x 起是 `netstd`；2.4.5 已在 5.1 验证可用，`-Latest` 可直接装最新稳定版。
  不同版本按目录并存、5.1 取最高版本，旧目录不自动删除；AllUsers 已有同版本时默认不重复安装（`-Force` 建用户副本）。
  插件预测（`CxxuCommand`）仍要求 pwsh 7.2+；回退时关闭所有 5.1 窗口并删除该版本目录。部署细节见 [Deploy-Guide](Deploy-Guide.md) 的「可选：Windows PowerShell 5.1 的 PSReadLine」。
- 轻量部署（免 git，新机器只有 v5 时）：先按 Deploy-Guide 的「前置：执行策略」设置执行策略，再保存部署脚本并运行 `& $deployScript -Light`；`$deployScript` 是仓库 `PS/Deploy/Deploy-CxxuPsModules.ps1` 的本地副本，保存方法与参数说明见 [Deploy-Guide](Deploy-Guide.md) 和 [PS/Deploy/readme](../Deploy/readme.md)。
  走离线包下载（codeload + 中央镜像静默，不弹窗选源），落 `PSModulePath`（setx 追加，不覆盖），
  写 5.1 专属 profile，重开 `powershell.exe` 跑 `init` 即用；部署结束会提示可选的
  `Install-Ps51PSReadLine` 入口。默认不安装 PowerShell 7，
  需要完整功能时再加 `-InstallPwsh7`：
  ```powershell
  # 前置：允许当前用户运行本地脚本（与 Scoop 安装前置相同）
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  $deployScript = "$HOME\Downloads\Deploy-CxxuPsModules.ps1"
  $mirror = if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }  # 换源只改这一行
  irm "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1" -OutFile $deployScript
  & $deployScript -Light
  # 需要 pwsh 7 时：& $deployScript -InstallPwsh7
  ```
- 免手动：跑一次 `Install-Ps51Profile`（`Init` 模块，7/5.1 均可跑），写入 5.1 专属 profile（`~\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`，UTF8+BOM，与 7 互不干扰），之后开 `powershell.exe` 自动 `init` + 自定义 prompt；已有 profile 无标记则追加，有标记直接返回（`-Force` 重写）。
- 修过的 5.1 专属坑：`Get-EnvCountedValues` 曾依赖仅示例文件定义的 `catn`（干净会话必炸），已改为自带编号输出；`Import-CxxuConfig` 的 env 探针改 `Ignore`（`SilentlyContinue` 仍会污染 `$Error`）；`Enable/Disable-PsPlugin -Persist` 曾用 `Set-Content -Encoding utf8NoBOM`（5.1 枚举无此值，直接绑定失败），`New-CxxuConfigTemplate`/`Optimize-PsHistory` 同源，已统一改 `Read-CxxuUtf8Text`/`Write-CxxuUtf8Text`（.NET UTF-8 直读写，读侧防中文注释乱码）。用户配置文件由这两个函数写入时另加 `-Bom`：5.1 的 `Import-PowerShellDataFile` 对无 BOM 的中文配置直接解析失败；历史记录等其他文本仍保持无 BOM。
- 部分宿主（如 VS Code 集成控制台的 5.1 会话）会出现识别不到 `Import-PowerShellDataFile` 的情况，导致 `init` 读不到组件清单与用户配置。现在 `components.psd1`、`config.defaults.psd1` 与用户配置统一走内部入口 `Read-CxxuDataFile`：cmdlet 可见时按原样解析，不可见时退回内置 AST 解析（只接受单个哈希表字面量，不执行文件里的其它代码），启动时不再连发“读失败”警告。
- 上述现象的根因是模块路径顺序：从 pwsh 7 终端启动 VS Code、Windows Terminal 等程序时，子进程会继承 7 的 `PSModulePath`，7 的模块目录因此排在 5.1 自带目录之前，5.1 会优先解析到仅 7 可用的模块（实测 `Microsoft.PowerShell.Utility` 7.0.0.0 加载后，`Import-PowerShellDataFile` 等命令不可见）。`init` 在 5.1 下检测到这种顺序时，会先把 5.1 自带的机器级与 `$PSHOME\Modules` 前置（不删除条目），再重新导入已被错误版本占位的 `Microsoft.PowerShell.Utility`；顺序正常时不动作，修复记录用 `init -Verbose` 查看。需要彻底避免时可改为从资源管理器启动 VS Code，而不是在 pwsh 7 终端里执行 `code`。
- 读 UTF-8 文档：5.1 的 `Get-Content` 默认按 GBK 解码，无 BOM 中文必乱码；外部文件控不了编码，一律用 `Get-ContentUTF8 <路径>`（`Basic` 模块，.NET 直读，自动识别 BOM，有无通吃，`-Raw` 整文）。
- 乱码归因（实测）：读文件用 ANSI 页（本机 5.1 下 `gb2312`），控制台显示用 OEM 页（本机 `utf-8`），两者独立；跟随 Windows"非 Unicode 程序的语言"（`GetACP`），非中文系统同样中招（错法不同）。不动系统，从读侧解决。
- 加新代码禁区：兼容集内禁三元 `?:`/行首管道/`Join-String`/`$PSStyle` 裸赋值/`$IsWindows` 裸分支/`` `e `` 转义（6.0+ 才有，5.1 下退化成字母 `e`，ESC 一律 `$([char]0x1b)`）；`PwshVar/confs/*.conf` 是被逐行 `iex` 执行的变量文件，同样禁三元（5.1 报 `Unexpected token '?'`），条件赋值写 `if (...) { } else { }`；重定义 5.1 内置别名（`rm`/`r`/`ps`/`h` 等）必须写 `Set-Alias <名> <目标> -Option AllScope -Scope Global`，漏掉 `-Option AllScope` 会报 `The AllScope option cannot be removed`，别名保持原样、自定义静默失效；文件读写禁裸 `Get-Content`/`Set-Content`（5.1 默认 ANSI 页，中文必乱码），一律 `[IO.File]::ReadAllText/WriteAllText($path, UTF8)`（自动识别 BOM，双版本同行为，零跨模块依赖）；真机校验：`powershell -NoProfile -File <脚本>` 逐模块 `Import-Module` 全绿 + `init` 零失败（沙箱脚本见交接记录）。
