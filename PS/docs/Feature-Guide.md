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
| `init` | 全量初始化（变量+别名+补全+prompt，约 400~700ms）；同会话重复调用直接返回 |
| `init -Timing` | 同上，附每步耗时表（调优用） |
| `p` | WT 启动行/轻量场景用；`-NoNewShell` 在当前 shell 原地执行，`-Force` 看耗时报告 |
| `Set-PsPrompt -version < fast/short/...>` | 切换提示符；加 `-Persist` 才写注册表记住选择 |
| `dm` | 切极简 prompt（做笔记摘录时聚焦命令本身） |
| `Test-PromptDelay` | 测当前 prompt 延迟 |
| `doctor` | 统一诊断入口（定位问题先执行它）：先跑 `Test-PsEnvReadiness`（安装态），再查运行态（init 错误/PSReadLine/历史大小/predictor/门控/懒加载/守护/仓库脏），只读，默认零网络 |
| `New-CxxuConfigTemplate` | 生成用户配置模板（`~/.cxxu/config.psd1`，仓库外本机生效） |
| `Import-CxxuConfig` | 读用户配置（init 首步自动调；优先级：环境变量 > 配置文件 > 默认开） |
| `Enable-PsPlugin` / `Disable-PsPlugin` | 体验插件启停（Fzf/Zoxide/Predictor/Tab，当会话生效；加 `-Persist` 长期有效，写 `~/.cxxu/config.psd1`） |

环境等级（`$PsEnvMode`，`Test-PsEnvMode` 查询）：core(1) 核心变量 → vars(2) 全量变量 →
env(3) 变量+别名。`Update-PwshEnvIfNotYet` 按需补齐，不重复干活。

## 3. 改模块 / 加函数（有了 `.psd1` 之后的工作流）

以前只有 `.psm1`，写完函数直接能用；现在每个模块多了 `.psd1`（显式导出表），
**函数只在两个地方都出现才算数**：

```powershell
# 1) 在 PS/<模块>/<模块>.psm1 里写函数（UTF-8 无 BOM，换行跟文件原状走）
# 2) 把函数名加进同目录 .psd1 的 FunctionsToExport（位置随意；GUID/版本不用动，日常改保持 1.0.4）
# 3) 当前会话生效（不用重启 shell；核心价值=保住当前会话变量上下文，新开 pwsh 会丢一部分信息）：
Sync-ModuleManifest <模块名> -Reload  # 偷懒版：自动把 .psm1 新增函数补进 manifest 并重载，一条搞定
Sync-ModuleManifest -Reload            # 不指定模块 = 全部 55 个自有模块（只打印有变化的+汇总；Prompt 跳过重载防嵌套）
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
- 改 init 期文件（`Aliases/` 下别名文件、`.conf`、profile）：改完跑对应 loader
 （`Update-PwshEnv` / `Update-PwshVars`）或 `init -Force`（`$global:PsInit` 防重复，`-Force` 强制重跑）。
- 验：`Get-Command <函数名>` 看 Source 是不是你的模块（撞名先查这个）。

```powershell
Get-SourceCode <命令名>     # 看任意自定义函数源码（带补全）
p -Force                    # 看 init 分步耗时，定位慢项
```

## 4. 开机与后台

- `Start-StartupTasks`：开机拉仓库、起软件/服务、报时 + IP 更新两个守护进程。
- IP 显示不走实时查询：`Update-NetConnectionInfo` 守护进程每 6s 写 `~/Data.json`
 （`IpPrompt`/`ConnectionName`），prompt 只读文件（3ms）；文件缺失才即时算一次并写回。
- 内存占用同理：5s 节流 + 文件缓存；电池 30s 会话缓存。

## 5. profile 与终端的双路径（必读）

- `$profile`（`CurrentUserCurrentHost`）里是 `init`；WT 部分 profile 的启动行是
  `pwsh -noe -c p`。两者**都会**跑 profile，`$global:PsInit` 保证同会话只初始化一次。
- 想只走一边：删 WT 启动行参数（推荐，行为统一），别删 `$profile`。
- conda 初始化已换缓存方案（`~/.conda_hook_cache.ps1`，573→59ms）；
  下次跑 `conda init` 会覆盖，届时重新应用（见 `Startup-Optimization.md §8`）。
- `argc`/`fnm` 钩子保持注释；`argc` 二进制缺失时不要放开。

## 6. FAQ

- **看不到 `Loading personal and system profiles took ...ms`**：正常。引擎只在四个
  profile 合计 >500ms（硬编码）才打印，不到就静默。
- **嵌套 `pwsh` 又跑一遍 init**：新进程不继承 `$global:PsInit`，只能重跑；
  贵的是 conda + init + 模块发现（见基线表），不是重复 bug。
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
    2. 改了 init 期东西（别名/`.conf`/变量/prompt）→ `init -Force`（或对应 loader）；
    3. 改了 profile 文件本身 → `. $profile`。
  - 安全差异：bash 重 source 会叠 PATH，这边 `init` 有 `$global:PsInit` 防重复（`. $profile` 默认 no-op，真重跑靠 `-Force`），`Add-EnvVar` 自带去重（见 `EnvVar.psm1:621/629`），prompt 全局只抓一次，OnIdle 有标记位。
    注意 `. $profile` 只跑 `CurrentUserCurrentHost` 这一级（conda 钩子在 `CurrentUserAllHosts`
    里，碰不到；即使碰到，缓存 59ms 也不贵）。
- **v5 能用吗**：不能。本模块集只要 PS7（manifest 已声明，进 v5 直接明确报错）。
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

## 7. 补全体验件（2026-09-21 现状：推荐组合已启用）

> 已启用的走延迟加载（`init` 只注册 `OnIdle` 事件，18ms），默认启动盘不受影响。
> 开关：`$env:PsFzf` / `$env:PsZoxide` / `$env:PsPredictor`（默认开，`False` 关；
> 守护进程由 `Start-StartupBgProcesses` 统一置 `PsPredictor=False`，永不加载 dll）；
> 重定向场景自动不加载。一键重装看 `Deploy-CompletionStack -WhatIf`。

| 候选 | 状态 |
|---|---|
| `CompletionPredictor`（参数/路径预测，命令名位置源码级跳过） | 一直在用 |
| `CxxuPredictor`（自研命令名预测：模糊连写 + 严格通配，3000 条 1~6ms，20ms 预算内） | **已启用**（详见 §8） |
| `CxxuTab`（自研命令名 Tab 补全：独立插件，命令名位合并模糊结果，参数位零干扰） | **已启用**（开关 `$env:PsTab`，启停见 `Enable/Disable-PsPlugin`） |
| `PSFzf`（Ctrl+T 文件 / Ctrl+R 历史） | **已启用**（Tab 不动，仍是 MenuComplete） |
| `zoxide`（`z` 跳转，init 缓存 `~/.zoxide_init_cache.ps1`） | **已启用** |
| `PSCompletions`（~200 命令的参数补全库） | 可选：已装 5.6.9；profile 里两行钩子默认注释着，解开即用 |
| `fnm` | 待定（node 用户；profile 里放着注释） |
| `carapace-bin`（千级命令补全） | 未装：逃生通道，真缺了再 `scoop install carapace-bin` 对比 |
| `posh-git` | 未装（只要 git Tab 补全才装） |
| `oh-my-posh` | 不开（每回车进程税 + 与现有定制片重叠） |
| `argc` | 缺二进制，先装再说 |
| `inshellisense` | **否决**（用户拍板，不再考虑） |

验：新开终端等一拍，`Ctrl+R` 翻历史、`z <目录>` 跳转；`Get-EventSubscriber` 应无残留（触发即摘）。若某主机 OnIdle 不触发导致没装上，跑 `Register-PsUxLazyLoad -Now` 或报回来。

## 8. FAQ（续）：输入时下面没候选？

- 先看 ListView 的候选**来源**：它只显示历史 + 插件（`HistoryAndPlugin`），Tab 走的是另一套
  全量索引——两边结果不一样是正常的，不是谁坏了。
- `get-child` 这类没候选：大概率历史里就没这么敲过（平时都用 `ls`/`gci` 别名）。
  插件（`CompletionPredictor`）2026-09-20 已接入 `init`，但读过它源码：
  **命令名位置直接跳过**（`command discovery 太贵`），只做参数/路径/`git`/小白名单——
  所以命令名前缀它永远沉默，只看到历史是必然的，不是坏了。
  开新终端输个高频前缀（如 `git che`）对照一下：有候选 = 一切正常。
- 想要 zsh-autocomplete 那种悬浮面板：原生没有（predictor 须 20ms 内返回，慢同步的
  TabExpansion2 镜像不了）。**自研 predictor 已落地并真机验证通过**（`CxxuPredictor`，
  只做裸命令名：模糊（`getser` 连写子序列、`chitem` 跨驼峰）+ 严格通配符（`get-*ive` 精确首尾；
  注意空格天然分词——光标后 token 进了参数位，预测器的 CommandName 门直接返回空，
  所以多片段 AND 只存在于 API 层，活体里请连写；`get-child` 出 `[CxxuCommand]` 来源行；当会话卸载用 `Remove-Module CxxuPredictor`，彻底移除见 §9）。
   重型外挂不再考虑（`inshellisense` 用户已否决；`hintshell`/`PSCue`/`PSPredictor` v2 观察）。
- 关预测：`predictNo`（当会话有效）；切回行内视图：`Set-PSReadLineOption -PredictionViewStyle InlineView`
  或按 `F2` 切换。彻底不用看 §9（删活件 + 关 `$env:PsPredictor`）。
- **ListView 为什么最多显示 10 行**：硬编码（`ListViewMaxHeight`，历史固定占前 3 行），
  **没有设置能改**（官方 issue 有人提过，未开放）。2.3+ 可用 `↑`/`↓` 滚动，最多翻到 50 条；
  要全量翻历史用 `Ctrl+R`（PSFzf 模糊搜）。`CompletionQueryItems=100` 是另一套
  （Tab 菜单的阈值），别混了。另：历史源内部还有个 `HistoryMaxCount=10` 的硬上限——
  历史最多只贡献 10 条；总数到不了 50 往往是插件对该输入没返回（总数=历史+插件），不是卡住了。

## 9. dll / 活件管理（检查 / 安装 / 更新 / 移除）

> 设计原理见 `Live-Versions.md`（并排版本 + 指针）。背景一句话：`CxxuPredictor` 是 net9.0 自研 dll（pwsh 须 7.5+）。仓库里的 `PS/CxxuPredictor/CxxuPredictor.dll` 是**源**（从不被加载，所以 `git pull` 永不撞锁）；真正被加载的是外置**活件** `~/.cxxu/bin/CxxuPredictor.dll`。两边靠哈希同步，程序集随进程：**同步后必须重开终端才换新代码**，`ipmox` 刷不动 dll。原则：入口 loader 只静默装载（旧版照用，零警告），版本动作全手动。

| 动作 | 命令 | 说明 |
|---|---|---|
| 检查 | `Test-PsEnvReadiness` | 活件行备注直接给出结论（`与仓库一致[hash]` / `不一致→执行 Sync-CxxuPredictor`）；表尾另有仓库/pwsh/活件三行 |
| 检查远端 | `Test-PsEnvReadiness -CheckRemote` | 默认零网络；加开关才询问远端是否有更新（`ls-remote` 只读，12s 超时） |
| 安装 | `Sync-CxxuPredictor` | 无活件时生成（新增版本目录 `~/.cxxu/bin/<哈希>` 并更新指针，缺目录自动创建）；`-WhatIf` 可空跑查看意图 |
| 更新 | `Update-ReposesConfiged` → 重开终端 → `init` | 拉取后自动调用 `Sync-CxxuPredictor` 同步活件（只新增版本目录，不受锁限制，任何会话都可执行）；纯文本变更执行 `ipmox` 即可（见 §3） |
| 移除 | `Sync-CxxuPredictor -Uninstall`（有其他会话锁定加 `-Force`） | 删除指针与版本目录；被会话锁定的版本删不掉会报告，下次再收；`Remove-Module` 不能卸载程序集（锁随进程存在，已实测）；彻底停用请持久化 `$env:PsPredictor='False'`，否则下次同步或更新会重新安装 |

- 守护进程（报时/IP）默认不碰 dll：`Start-StartupBgProcesses` 置 `PsPredictor=False` 继承 + 两个守护函数按 `-Command` 自断，所以 `-Force` 关它们无压力（无状态，重起即回）。
- 同一结论在 `Test-PsEnvReadiness` 的“建议”行也会再说一遍（缺必备 > 有更新 > 活件不一致）。

## 10. 补全全景速查（三层 + 参数层）

| 层 | 按键/视图 | 来源 | 说明 |
|---|---|---|---|
| Tab 全量索引 | `Tab`（MenuComplete） | 引擎全量：函数/别名/文件/参数 | 命令名位经 `CxxuTab` 包装增强（模糊连写可选中，参数位零干扰；开关 `$env:PsTab`）；和下面两层**不是同一套索引**，结果不一样正常 |
| ListView 预测 | 输入时自动浮现（`HistoryAndPlugin`） | 历史（最多 10 条，硬上限）+ 插件 | 插件= `CompletionPredictor`（参数/路径，命令名位跳过）+ `CxxuPredictor`（命令名，§8）；须 20ms 内返回，实测 3000 条 1~6ms |
| 模糊搜历史/文件 | `Ctrl+R` / `Ctrl+T`（PSFzf） | 全量历史/文件 | 历史翻不完用这个，不走 10/50 上限 |
| 参数值补全 | `Tab` 在参数位 | `PSCompletions`（~200 命令库，可选）+ 自带 `ArgumentCompleter`（EnvVar 系、`Get-Json -Key` 等，`Set-ArgumentCompleter` 批量注册） | PSCompletions 用法：解开 profile 里注释的两行 |

- 相关命令：`doctor`（统一诊断入口，定位问题先执行它）、`Register-PsUxLazyLoad [-Now]`（延迟加载入口）、
  `Deploy-CompletionStack [-WhatIf/-IncludePSCompletions/-SkipBinaries]`（新机一键装栈）、
  `Test-PsEnvReadiness`（查缺）、`predictNo`（当会话关预测）、
  `Enable-PsPlugin` / `Disable-PsPlugin`（插件启停，Fzf/Zoxide/Predictor/Tab）。
- **历史膨胀（Ctrl+R 变慢）**：`Optimize-PsHistory -WhatIf` 先看诊断（总数/去重率/重复 Top5）， `Optimize-PsHistory [-KeepLast 3000]` 动手（去重只留最后一次 + 去杂 + 截断，旧行进同目录 `.archive-时间.txt`，原文件留 `.bak-时间`，均可恢复）。治本：init 已开 `HistoryNoDuplicates`（新命令不再重复入库）+ `MaximumHistoryCount 3000`。注意历史文件无时间戳，切割按新旧顺序（文件尾=最近）；当前会话内存里的旧历史重启才换新。
- 新终端对照：输高频前缀（如 `git che`）有候选 = 一切正常；`get-child` 这类没候选多半是历史里没敲过 + 命令名插件只认连写（空格分词进参数位，见 §8）。

## 11. 手动启用清单（自动导入之外的东西）

> 分界：`PSModulePath` 自动发现 + `init` + 延迟加载 + 缓存自建都是自动的，
> 以下只有"缺了才管"，`Test-PsEnvReadiness` 的"可选"行即体检口（`doctor` 同步可见）。

| 功能 | 默认状态 | 手动启用 | 说明 |
|---|---|---|---|
| `PSCompletions`（~200 命令参数补全） | 未装，profile 两行钩子注释中 | `Confirm-ModuleInstalled -ModuleName PSCompletions -Install`，再解开 profile 第 4~5 行 | 旧注"可能导致 `ipmof|iex` 报错"已过期（白名单+`ipmox` 时代），现可放心开 |
| `fzf` / `zoxide` 二进制 | 无则 `Ctrl+T/R`、`z` 不可用 | `scoop install fzf zoxide`（或 `Deploy-CompletionStack` 一键） | 装完重开终端，init 缓存自建 |
| `scoop` 本体 | 无则二进制系列全停 | 按官网装，或 `Deploy-ScoopByGithubMirrors`（国内） | 装完补 buckets（`Add-ScoopBuckets`） |
| `conda` | 无则 prompt  conda 段静默缺失 | `Deploy-MiniforgeConfig`；`$condaExe` 路径按机器对（profile 缓存块） | 缓存 `~/.conda_hook_cache.ps1`，首跑慢一次 |
| `fnm` + 钩子 | 未装，profile 末行注释中 | `scoop install fnm`，再解开 profile 末行 | node 用户才需要 |
| `scoop-search` 钩子 | profile 6 行注释中 | 有 `scoop-search` 才解开（`--hook` 注入） | 无则不用管 |
| `argc` 整块 | 缺二进制，profile 8 行注释中 | 先装 argc + `C:\repos\argc-completions` 仓库，再解开 | 不全则保持注释 |
| `carapace-bin` / `posh-git` | 未装 | 逃生/按需：`scoop install carapace-bin`；只要 git Tab 才装 posh-git | 决策见 §7 |
| prompt 主题持久化 | 当会话有效，重开复原 | `Set-PsPrompt -version <…> -Persist`（写注册表） | 临展用 `dm` 切极简，不持久化 |
| 开机任务 + 守护进程 | 未注册 | `Start-StartupTasks`（或 `Deploy-StartupTasks` 部署） | 报时/IP 守护，无状态，`-Force` 可杀 |
| WT 设置下发 | 仓库 `Config/wtConf*.json` 仅供参考 | `Deploy-WtSettings` | 线上 WT 无自定义 profile 时才需要 |
| github hosts 定时更新 | 未装 | `Deploy-GithubHostsAutoUpdater` | hosts 拉胯地区按需 |
| 镜像持久化 | 默认自动（静默测速+缓存） | `$env:PsGithubMirror` 持久化（`Add-EnvVar`）指定镜像 | 出国/回国切换用 |
| 开关组 | 默认全开 | `~/.cxxu/config.psd1`（`New-CxxuConfigTemplate` 建模板）或 `Enable/Disable-PsPlugin [-Persist]` | `PsFzf/PsZoxide/PsPredictor/PsTab/PsShowProgress`；环境变量永远优先 |
| 历史瘦身 | 从不自动执行 | `Optimize-PsHistory [-WhatIf]`（超 8000 行或 500KB 时 `doctor` 会提示） | 备份+归档双保险 |
| pwsh 7.5 版本门 | 随安装 | `Update-PowerShell`（`CxxuPredictor` 需 net9） | 不够 7.5 只缺 predictor，其余照常 |

- 新机按表自上而下过一遍即可；`Test-PsEnvReadiness` 全绿 + `doctor` 全绿 = 生效确认。

## 12. 非 Windows 说明（Linux/macOS）

> 本模块集按 Windows 日常开发，其它系统"核心可用、部署件受限"。`doctor` 会标出平台行。

- 可直接用：纯 pwsh 模块（自动发现/`init`/补全栈/`doctor`）；`CxxuPredictor` 是 net9.0（pwsh 7 跨平台可加载，dll 随仓库分发）；活件/配置/历史/`Data.json` 全在 `$HOME` 下，路径跨平台；`Test-PsEnvReadiness` 的 `PSModulePath` 检查已做分隔符自适应（`:`/`;`）。
- 不可用（Windows 专属，不做跨平台适配）：`scoop` 系（安装/换源/buckets）、注册表持久化（`Add-EnvVar`、`Set-PsPrompt -Persist`、镜像持久化——改走 `$profile` 或 env 文件）、计划任务与开机（`Deploy-StartupTasks`/`Start-StartupTasks`）、WT 下发、CIM/WMI 信息类、`conda` scoop 路径、业务模块硬编码路径（如 WordPress/phpstudy、`C:\` 前缀）。
- 部分兼容：`PwshVar` 有分平台变量文件表（`$PwshVarFilesWindows`/`$PwshVarFilesMacOs`），新增变量按此模式分文件存放；`Info` 个别函数有 `$IsWindows`/`$IsMacOS` 分支，其余缺分支的函数在非 Windows 下报错即代表不支持。
- 建议：先跑 `Test-PsEnvReadiness` 看缺口（缺的多为 Windows 专属，按 §11 逐项取舍）；`PwshVar/confs/VarSet1.conf` 的 `$PC*` 主机名按本机添加。

## 13. Windows PowerShell 5.1 兼容（B 档：交互可用）

> 目标是在 5.1 里 `init` + 提示符 + Tab 补全 + 历史可用；部署/预测/dll 链明确留 7。

- 兼容集（psd1 已降 `5.1`，psm1 带 BOM，见 `Module-Conventions.md §8`）：`Basic`、`Aliases`、`FileSystem`、`PwshVar`、`Search`、`CxxuTab`、`Prompt`、`Init`、`EnvVar`、`NetWork`、`RepoSync`、`PsDebug`、`PsEnv`、`Shortcut`、`PathProcess`、`Hardware`、`Proxy`（后 8 个 2026-09-22 酌情降档：解析零错误 + 5.1 直调冒烟通过）。
- 5.1 下自动降级：`init` 步骤表 `MinPS = 7` 的 5 步静默跳过（`ArgumentCompletion`/`Startup`/`Pwsh`/`Json`/`TerminalTools`）；`ForEach-Object -Parallel` 走串行分支；`CxxuTab` 探不到 dll 方法时纯透传；`HistoryNoDuplicates`/`inlineprediction` 配色按 PSReadLine 版本 gating（5.1 自带 2.0.0 跳过）。
- 提示符全对齐：`fast`/`Simple`/`Short`/`Default` 原生可用；`Balance` 的 Info/Startup 外部依赖在 `Prompt.psm1` 顶部有 5.1 本地兜底（CIM/注册表/内置 cmdlet 同口径；必须 `function global:` 定义，否则模块私有、直接调用撞坏 Info；缓存用 `$global:__Cxxu51*`，`$script:` 跨不了作用域），渲染与 7.5 逐字一致，稳态约 50ms/次（首屏冷缓存 1.4s 一次性）；`Get-IpAddressFormated` 含参数集的移植版，直接调用也可用。
- 明确不可用：`CxxuPredictor`（net9 dll）、预测视图（需 7.2+ 子系统）、`Deploy` 全系、`Test-PsEnvReadiness` 的 `pwsh 7+` 必备项（在 5.1 下即提示装 pwsh7）。
- 用法：`powershell -NoProfile` 起 5.1，保证 `PSModulePath` 含模块集后 `init` 即可；`$env:PsTab='Off'` 可关 Tab 包裹。
- 免手动：跑一次 `Install-Ps51Profile`（`Init` 模块，7/5.1 均可跑），写入 5.1 专属 profile（`~\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`，UTF8+BOM，与 7 互不干扰），之后开 `powershell.exe` 自动 `init` + 自定义 prompt；已有 profile 无标记则追加，有标记直接返回（`-Force` 重写）。
- 修过的 5.1 专属坑：`Get-EnvCountedValues` 曾依赖仅示例文件定义的 `catn`（干净会话必炸），已改为自带编号输出；`Import-CxxuConfig` 的 env 探针改 `Ignore`（`SilentlyContinue` 仍会污染 `$Error`）。
- 读 UTF-8 文档：5.1 的 `Get-Content` 默认按 GBK 解码，无 BOM 中文必乱码；外部文件控不了编码，一律用 `Get-ContentUTF8 <路径>`（`Basic` 模块，.NET 直读，自动识别 BOM，有无通吃，`-Raw` 整文）。
- 乱码归因（实测）：读文件用 ANSI 页（本机 5.1 下 `gb2312`），控制台显示用 OEM 页（本机 `utf-8`），两者独立；跟随 Windows"非 Unicode 程序的语言"（`GetACP`），非中文系统同样中招（错法不同）。不动系统，从读侧解决。
- 加新代码禁区：兼容集内禁三元 `?:`/行首管道/`Join-String`/`$PSStyle` 裸赋值/`$IsWindows` 裸分支；真机校验：`powershell -NoProfile -File <脚本>` 逐模块 `Import-Module` 全绿 + `init` 零失败（沙箱脚本见交接记录）。
