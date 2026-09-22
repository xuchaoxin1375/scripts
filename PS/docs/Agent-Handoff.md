# Agent 交接（开发与维护手册）

> 给下一个接手的 agent（或人）看的：怎么做事、怎么验证、哪里埋过雷。
> 用户手册见 `Feature-Guide.md`，模块清单见 `Module-Map.md`，编码铁律见 `Module-Conventions.md`。

## 1. 标准工作流

1. `Read` 看现状（改前必读，edit 工具强制要求）。
2. 大搬迁一律写**搬迁脚本**放 `$env:TEMP\opencode\`（仓库外，不污染 repo），ail：
   行号断言 → 搬运 → 落盘。行号变了就先 abort，绝不硬搬。
3. 跑门禁（§2），不过不落盘、不提交。
4. 更新受影响的 manifest + 相关文档（本目录四份 md 分工见 §5）。
5. 提交信息沿用 `perf:/fix:/chore:` + 中文简述；只暂存自己动的文件
   （`wp/` 下常有别人未提交的修改，别碰）。

## 2. 验证门禁（按顺序跑，全绿才算完）

```powershell
# ① 全模块强制导入（目录名=模块名，CompletionPredictor 是第三方不管）
# ② Test-ModuleManifest 全过
# ③ manifest 导出对账：块注释感知的 ^function 解析 vs 各 psd1 FunctionsToExport，零误差
# ④ init 全链 + prompt + 主题切换冒烟；关键命令 Get-Command 看 Source 归属
# ⑤ 有性能声明必附前后实测数（沙盒要注明；重定向下 PSReadLine 会报两行错，真机没有）
```

历史用过的脚本名（TEMP 下，用完即走，仓库里不留）：
`verifyAll`（全导入）/`parity4`（manifest 对账）/`verify3`（init+prompt+切换冒烟）/
`timing`（`init -Timing`）/`docfacts`+`docres`（文档断言取数）/`vardump`（变量级对账）。

## 3. 踩坑清单（每一条都是真金白银交过学费的）

1. **变量名大小写不敏感**：`$keep` 和 `$KEEP` 是同一个变量。
   教训：搬迁脚本里计数器/行号表用绝不撞名的名字（`$keepLines`/`$keepRanges`）。
2. **`@( (a,b) )` 单元素数组自动解包**：`$INFO = @( (162,1088) )` 结果是 `@(162,1088)`，
   循环会跑两次倒序垃圾。单区间用 `,@(...)` 或直接写标量逻辑。
3. **`return @()`/`return $array` 解包**：空数组 return 出去变 `$null`，单元素变标量。
   调用方一律 `@(...)` 归一化后再判空；失败路径用裸 `return`。
4. **管道里 `$Matches` 跨作用域失效**：`... | Where { $_ -match } | ForEach { $Matches[1] }`
   拿到的是脏数据。匹配和取值必须在**同一个** scriptblock 里。
5. **换行符**：仓库混用 LF/CRLF。`edit` 工具保留原样；凡用脚本写文件，先查原编码
   （`Info`/`FileSystem` 是 LF，别翻成 CRLF），新文件用 CRLF。
6. **成功流泄漏**：函数 `return` 的值会被调用方管道消费。热路径调用一律确认：
   要值就接住，不要就 `| Out-Null`（`Confirm-DataJson` 裸路径污染控制台事件）。
7. **日志行序不可信**：`> file 2>&1` 下成功流/错误流/宿主输出的落盘顺序会重排。
   定罪靠“收进变量数个数”（`$o = init; @($o).Count`），不靠看日志行号。
8. **bash 工具引号地狱**：行内 `pwsh -Command '...'` 转义必炸。一律写成 `.ps1` 文件再 `-File` 执行。
9. **模块作用域**：`$global:` 显式前缀才跨模块。旧文档曾写“prompt 重载抓旧值堆叠”，
    2026-09-20 沙箱最小复现证伪（纯重载抓空只报错不叠）；真凶是 conda 每次 import 重包
    prompt（`Conda.psm1:232-247`，`Rename-Item` + `ChangePs1` 缺省真）。
    `Import-ModuleForce` 已改白名单（仅仓库路径，动态模块 Path 为空天然排除）+
    三卫哨（`*completion*`/`*predictor*`/`*conda*`），叠加防御；旧理论作废，以此条为准。
    另补：`Prompt.psm1` 顶层已改“全局只抓一次”（`$global:__CxxuOriginalPrompt`），
    沙箱三轮 Remove/Import（含空槽）实测无报错无叠层，故 Prompt 不用跳过、留在轮转里。
    真机验证通过（2026-09-20，用户新开 shell + 多轮 ipmof|iex，单层无报错）。
10. **manifest 是真相源**：增删函数必同步 `.psd1`（GUID 保持不动）；
    函数名解析要块注释感知（`Function that shows...` 曾被误收录成函数 `that`）。
11. **重定向 vs 交互是两种宇宙**：`[Environment]::UserInteractive` 在重定向下仍为 True，
    唯一探针是 `[Console]::IsOutputRedirected`。`Set-PSReadLinesAdvanced` 已按此分流
    （交互全量 / 重定向跳过预测源+列表视图，详见 `Startup-Optimization.md §12`）；
    计时仍以真机为准，沙盒数只看相对变化。另：`$Error` 里几条 `Env:\X does not exist`
    是 `EnvVar.psm1:871/1015` 的 SilentlyContinue 记账，不打印，不用追。
12. **restricted characters 警告 = 双横线**：`Import-Module` 报它，当且仅当导出名含 2 个以上 `-`
    （16 组合成模块实测；2026-09-20 已转正 18 个，`STILL-WARN=NONE`，对照表见
    `Startup-Optimization.md §16`；之后再见先查新加的双横线名）。
    修法：在**我们的** import 处加 `-DisableNameChecking`（定向压制），不改名；
    手动 `Import-Module` 也请带上。另：模块函数内调 `Import-Module` 默认装成**嵌套模块**
    （命令可用但 `Get-Module` 列不出），要顶层必须加 `-Global`（`Sync-ModuleManifest`
    的 `-Reload` 已加）。教训：给函数加批量分支后，单路径回归漏测导致 `$n` 未赋值发布出去，
    测试脚本当场抓获——**改批量逻辑必重跑单路径用例**。
13. **提交看第二列**：`git status` 第一列是已暂存、第二列是未暂存——门禁测的是工作区，
    提交的是暂存区。2026-09-20 实测：脚本直写工作区后忘了 `git add`，提交漏了整轮改名，
    靠事后 `git show HEAD:file` 抓获。流程：`add` → `commit` → 必用
    `git show HEAD:<关键文件>` + 全新 `status` 复验（`c7cffe3` 就是 `--amend` 补救的）。
14. **edit 工具可能整文件改写换行**：实测 `Pwsh.psm1` 在 LF/CRLF 间横跳过（内容 zero diff
    但换行翻了，`git diff` 整篇标红才发现）。改完 `.psm1`/`.psd1` 必跑换行断言：
    `git diff --stat` 与 `--ignore-cr-at-eol --stat` 对不上就是翻了；翻了就 python 按 HEAD
    惯例转回去（utf-8-sig 读、`newline=''` 写保 BOM），不要 `git add` 蒙混过去。
15. **`ipmof|iex` 为什么要管道**：`Import-ModuleForce` 把活拆两半——Remove 立刻做，
    Import 攒成文本返回；光跑 `ipmof` 不管道，装的那半根本没执行（“没生效”主因，
    不是作用域魔法；另见 #12 嵌套/-Global）。新命令 `ipmox`（`Pwsh.psm1`）把两半合一：
    复用卸+名单、直调重装一律显式 `-Global`、Pwsh 自己殿后；`ipmof|iex` 照旧可用。
    沙箱仿真通过（解析+殿后排序）；真机验证通过（2026-09-20，用户三步全绿），本条终结。
    要点：`ipmof|iex`/`ipmox` 存在的理由就是保当前会话变量上下文（重开 pwsh 会丢一部分信息）。
16. **`ipmox` 选项（新函数两步并一步）**：`-Name` 只动指定模块（Tab 补全，抄 `Sync-ModuleManifest`
    的补全器模式；未加载的名字警告跳过）；`-Sync` 先 `Sync-ModuleManifest -Reload`（新函数先进
    manifest）再统一重载——正好补上 Sync 自身跳过的 Prompt（capture-once 保护）。
    沙箱真加载实测全绿：补全 `Pw`→`Pwsh,PwshVar`、错名警告跳过、裸跑自重载后 `ipmox` 可用、
    `-Sync` 全 53 模块 0 追加且 prompt 完好。注意：`Sync` 只增不减，改名留下的悬空导出
    （如 `Test: cchh`）只警告不清，需手改 manifest。
17. **`Deploy-CompletionStack`（新机一键补全栈）**：`Deploy.psm1` 末尾；模块直装 +
    二进制（有 scoop 则装、无则给命令）+ 7.5 版本门（不够只警告不停手）+
    `-IncludePSCompletions`/`-SkipBinaries`；全程 `SupportsShouldProcess`，
    `-WhatIf` 空跑零副作用（沙箱已验：前后 `ListAvailable` 一致）。
    CxxuPredictor 随仓库零安装，不在其中。
18. **`Close-OtherPwsh`（换被锁文件前清场）**：`Pwsh.psm1`；列出除自己外的所有 pwsh
    （PID/启动时间/标题），`ConfirmImpact=High` 默认逐个询问，`-WhatIf` 空跑；
    守护进程也会被列出（杀了需重跑）。结论：dll 锁只影响本机热更新换文件，
    新机部署全是新文件、无进程占用，不会因此失败。
20. **（条目已移除，见 #31）**
21. **dll 外置决策（2026-09-21，用户拍板）**：活件搬 `~/.cxxu/bin`
    （后演进为并排版本 + 指针，见 #29；以下为当时形态，留档）；当时 loader 按哈希同步后按路径装载；
    仓库版从不被加载→pull 永不撞锁。代价：`ipmof` 必须跳过 CxxuPredictor（按名重载装出空壳还注销 predictor，
    守卫注释已换因）；psd1 去 RootModule（防误装）。退役：测锁/`-AutoFix`/`Close-OtherPwsh`/
    Basic 守卫（未提交过，干净删除）；重启规矩不变（程序集随进程）。
22. **退役记录**：#21 之前有过一套锁内 machinery（`Close-OtherPwsh`、`-AutoFix`、fetch 测锁），
    外置后不再需要，已删；引号三层笔误教训保留：组装类字符串必断言内容，解析过不代表语义对。
23. **守护进程不加载 predictor + `-Force`（2026-09-21）**：loader 加 `$env:PsPredictor` 门
    （风格同 PsFzf/PsZoxide）；`Start-StartupBgProcesses` 置 False（子进程继承），
    两个守护函数按 `-Command` 自断（交互手动调不受影响）。`-Force`（dll 变更时，跳过确认直接动手）：
    关其它（含无状态守护，随后 `Start-StartupBgProcesses` 重起）→脱钩子进程等退→开新窗→退自己；
    重定向拒绝。守护进程从不加载 dll，锁问题当时收敛到交互会话（后并排版本根治，见 #29）。
19. **国内网络：gitee→github+加速（2026-09-21 决策）**：gitee 对 `irm|iex` 误报拦截，
    默认源全切 github；中央变量 `$env:PsGithubMirror`（持久化自选镜像，不设走默认/静默测速），
    统一出口 `Get-GithubMirrorPrefix`/`Get-RepoRawUrl`（Deploy 模块内），独立脚本内联同策略；
    `Get-SelectedMirror` 的 gitee fallback 已摘。动 URL 先查这两函数，别手拼。
24. **活件同步手动化（2026-09-21，用户偏好）**：入口 loader 只静默装载（旧版照用，零警告），版本检查/同步收归 `Sync-CxxuPredictor`（以下为旧单文件时代描述，现并排版本见 #29；当时：哈希对比，不同才复制；被锁定时默认给手动步骤，`-Force` 关闭其它会话后重试，重定向拒绝；同步后重开终端才生效）。 readiness 活件行备注报不一致→指去本命令；当时专用更新命令的 dll 变更分支文案同步改。原则：入口默认不做任何版本检查/网络动作，重活全手动（同 `-CheckRemote` opt-in 思路）。
25. **历史瘦身 + `doctor`（2026-09-21，用户要的）**：历史文件 3.2 万行/1.5MB（去重率仅 37%， `ipmof|iex` 750 遍）是 Ctrl+R 慢的主因。新 `Optimize-PsHistory`（Init 模块，去重保最近+去杂+截断，旧行进 `.archive-时间.txt`，原文件 `.bak-时间`；`-WhatIf` 诊断；历史无时间戳，只能按新旧顺序切）。init 加 `HistoryNoDuplicates` 治本。新 `doctor`（Deploy，无横线速记风格）：先调 `Test-PsEnvReadiness` 再查运行态（init 账本/PSReadLine/历史大小/predictor 三态/门控/懒加载/守护新鲜度/仓库脏/conda 缓存），只读默认零网络。注意 `@($null)` 会数出 1 个：`$global:PsInitStepErrors` 没跑过 init 时是 $null，必须 `Where-Object { $_ }` 先滤（已踩）。
27. **自锁实测 + 更新合并（2026-09-21，已被 #29 推翻假设，留档）**：已加载旧 dll 的会话覆盖活件必败（`being used by another process`，锁定者是本会话）——所以“重开→Sync”有竞态， `Sync -Force` 也只能关闭其它会话、不能解除自锁。当时合并结论（子进程拉完一并同步，自认无锁）因"持有者存在即失败"不成立，已改并排版本。职责切分（现行）：Update=版本推进(git)+分发，Sync=单点文件动作，Test=检查，doctor=统一诊断入口。
28. **移除真相（2026-09-21）**：`Remove-Module` 后文件照样锁（实测 `Loaded=False` 但 `Remove-Item` 报 `being used`，程序集锁跟进程到关闭）——指南旧"手动两行"已更正。真方案：`Sync-CxxuPredictor -Uninstall`（以下为旧单文件时代描述，现并排版本见 #29；当时：删除走无锁子进程；自锁/他锁失败给裸会话一行；`-Force` 只关闭其它会话）。删完若不禁用会自动装回，彻底不用要持久化 `PsPredictor=False`。
29. **并排版本活件（2026-09-21，用户选的）**：自锁实测证明子进程复制同样撞锁（持有者存在即失败，上轮"无锁天生"假设不成立），改并排版本根治： `~/.cxxu/bin/<哈希8>/CxxuPredictor.dll`（文件名不变，模块名才正确；改名文件 import 后模块名跟文件名走，`Get-Module CxxuPredictor` 会空，已踩）， `current.txt` 单行指针指当前版本目录。同步只新增目录+更新指针（原子换文件），从不覆盖→永不撞锁，任何会话都可执行；loader 按指针装载+两级回退（最新版目录→旧单文件）； GC 每次同步一并回收非当前版本（被锁跳过）。当时专用更新命令拉完调 Sync（已退役，见 #31）， `Update-ReposesConfiged` 收尾 guarded 调 Sync（用户主流程，差异才出声）。 readiness/doctor 全改指针解析（Deploy 内自带 6 行 resolver，与 TT/Basic 各一份，三处重复是已知债，统一需导出 helper，会增命令数，暂缓）。设计专章：`docs/Live-Versions.md`（结构/指针协议/流程/GC/故障/命令分工 + mermaid 图）。
26. **用户配置文件（2026-09-21，用户要的）**：`~/.cxxu/config.psd1`（psd1 数据文件，只读不执行；仓库外本机生效）。`Import-CxxuConfig`（init 首步自动调，只填环境变量空位）+ `New-CxxuConfigTemplate`（[-Force] 生成注释模板）。已知键：PsFzf/PsZoxide/PsPredictor/PsTab/PsShowProgress/PsGithubMirror；优先级环境变量 > 文件 > 默认开；坏文件警告一次忽略。沙箱 5 项已验（缺文件静默/模板/文件生效/环境优先/坏文件警告）。后补：真机回环已验（建模板→读回填充→双向持久化→环境复位）；持久化改写保列对齐（键宽 15）；`Deploy-CompletionStack` 收尾自动补建模板（已存在 no-op，`-WhatIf` 安全）。
30. **文档口径统一（2026-09-21，用户叫"到文档"）**：Handoff #21/#24/#27/#28 是编年留档，与现行 #29 不一致处已加"旧单文件时代"标注，不改写历史；现行口径唯一来源是 #29 + `Module-Conventions.md §11`（术语表）+ `Feature-Guide.md §9`（四件套表格）。 dll-why 定论记 `Startup-Optimization.md §20`（插件槽只认 .NET + 20ms 预算，纯 PS 3000 条 22ms 超预算，C# 1~6ms）。动用户可见行为前先看这三处定口径，改完同步三处。
32. **独立 Tab 插件 + 插件启停（2026-09-21，用户要的）**：ListView 预测进不了 Tab（两套管线），新模块 `CxxuTab`（`TabExpansion2` 包装，只在命令名位置合并 dll 模糊结果，参数位透传；dll 新增 `CompleteCommand` 公开静态接口，独立缓存表，失败返空数组）。踩坑：`global:` 函数看不到模块 `$script:`，方法缓存必须放 `$global:__CxxuTabMethod`；改名文件 import 会跟走模块名，并排目录布局保住 `CxxuPredictor.dll` 文件名才没事。启停：`Enable/Disable-PsPlugin`（Fzf/Zoxide/Predictor/Tab，当会话环境变量；`-Persist` 行级写 config 保注释；`-Path` 可覆盖）。教训：双引号字符串里 `$(` 会被当子表达式执行，持久化改行级处理（`[regex]::Escape` 拼 pattern，不用 `-replace` 写值）。模块数 54→55 相关三处已同步。
33. **Tab 发版实录（2026-09-21）**：构建输出在 `src/bin/Release`，仓库件是手工发布（`Copy-Item` 覆盖）。发布时仓库源被两个 09:28 的 VSCode 旧终端锁定——它们是外置之前的会话，直接从仓库路径加载；新会话从不加载仓库源，这是最后一批，死后仓库源永久无锁（已验证零持有）。教训：并排版本保的是活件，不管发布；发布要动仓库源就得先清老会话。发版 `0203935B`→`E7CF2C8A`，`Sync` 全程无感（旧会话留旧版），新终端 `getser` Tab 首选 `Get-Service`，参数位零干扰，用户已体验确认。另：首调用建表约 400ms，包装在导入时预热，首 Tab 不卡。
31. **退役 `Update-CxxuPsModules`（2026-09-21，用户：想不出调用它的情况）**：102 行整函数删除，导出同步摘除。`Sync` 并进 `Update` 的方案否决：钩子要的是纯文件同步，`Update` 得加"仅文件模式"，等于换名不换量，且活下来的 `Update` 依然无人调用。现行更新入口只剩 `Update-ReposesConfiged`（收尾 guarded 调 Sync）+ `Sync-CxxuPredictor`（单点）。代价：`-Force` 一键重开链消失，手动等价操作是关闭会话、重新打开、`init`；readiness 建议行、`Sync` 帮助、指南 §13、§9、Live §8、Map 行同步改。
34. **5.1 兼容 B 档（2026-09-21，用户选 B：交互可用）**：拦路虎分三级——P0 import 即炸（psd1 版本声明、三元 `?:`、行首管道、`Join-String`、`$PSStyle` 裸赋值、`$IsWindows` 裸分支）、P1 跑到才炸（`-Parallel`、PSReadLine 2.0 缺参数）、P2 架构不可兼（predictor dll/预测子系统/UTF-8 无 BOM 中文乱码，接受不修）。兼容集 9 模块（Basic/Aliases/FileSystem/PwshVar/Search/CxxuTab/Prompt/Init/EnvVar，psd1 降 5.1，psm1 补 BOM，conventions §8 已开口）；init 步骤表 `MinPS = 7` 静默跳过 5 个 7-only 步骤。真机 `powershell.exe` 全绿：9 模块导入 + init 零失败 + prompt 渲染 + Tab 包裹。用法与禁区见 `Feature-Guide.md §13`。
35. **5.1 真机抓到的四个坑（2026-09-21，全是静态扫描漏网）**：(1) `SilentlyContinue` 照样往 `$Error` 记账，探针一律 `-ErrorAction Ignore`（v3+ 通用）；(2) `$old + @(...) -join X` 里字符串+数组先按空格压平成标量，`-join` 直接失效——先 join 成标量再拼；(3) 模块私有兜底函数用户直接调用撞坏模块（自动发现找到导不出的 Info 就报错），5.1 兜底必须 `function global:` 定义，缓存变量同步从 `$script:` 换 `$global:` 命名空间（全局函数读不到模块 `$script:`，见 #32 同类教训）；(4) `Get-Command` 探针在 5.1 下对导不出的模块返回 $null，不要信 CommandInfo 残留，`local-fns=0`（`Get-ChildItem function:` 全局不可见）才是模块私有的铁证。
36. **拆分 Basic/Pwsh（2026-09-21，用户选 Pwsh 小手术 + Basic 簇搬迁）**：新模块 `WinSys`（键盘 7/TTS 2/电源 7，命令名不变，自动发现即用）；Pwsh 教学 2 函数迁 `HelpExamples`、Robocopy 2 函数迁 `FileSystem`。WordPress 最大但用户在改 + 业务内聚，不碰；Info 拆了 prompt 反增跨模块调用，不拆；Deploy 按域拆是立项级，没选。教训：`Get-Content | Measure-Object -Line` 少算约 250 行（管道计数问题），看体量以 `[IO.File]::ReadAllLines.Count` 或编辑器 "of N" 为准；搬迁体与 HEAD 逐行字节对账（`Compare-Object` 遇近重复行会误报对齐，以 `rg` 行号复核为准）；大段搬迁用行号脚本删（锚点断言 fail-stop），`Edit` 转录 300 行必出注释空格误差。模块数 55→56，Map 已同步。
37. **5.1 prompt 全对齐 + 免手动（2026-09-21，用户要的）**：`Balance` 差的 7 个 Info/Startup 命令在 `Prompt.psm1` 顶部移植（CIM/注册表同口径，IP 格式 `<网卡首字:ip>` 逐字照抄；会话缓存 IP 60s/内存 10s/开机 120s/电池复用 30s），渲染与 7.5 逐字一致，稳态 50ms/次（首屏冷缓存 1.4s 一次性）。`Install-Ps51Profile`（Init 模块）：写 5.1 专属 profile（UTF8+BOM，`Set-Content -Encoding utf8` 在 5.1/7 下含义不同，必须 .NET 写死；有旧 profile 无标记则追加不覆盖），之后开 `powershell.exe` 自动 init。另修 `Get-EnvCountedValues` 的 `catn` phantom 依赖（仅示例文件定义，干净会话必炸，7 亦然）改自带编号。
38. **查询命令 5.1 可用化（2026-09-21，用户问"怎么查模块"）**：`Get-ModuleByCxxu` 住在留 7 的 Info 里，5.1 整模块导不出——迁入 B 档 `Basic`（体小、无依赖、5.1 原生语法），附带修 `$env:CxxuPSModulePath` 未设置时 `-like "*"` 全匹配噪音（回退到本模块所在仓库根）。查询链固定下来记 `Module-Map.md` 头：`Get-ModuleByCxxu` → `Get-Command -Module` → `Get-Command` 反查。教训：放查询/诊断类命令先问"5.1 能用吗"，留 7 模块里的便民命令等于半残。
39. **文档 BOM 方案推翻（2026-09-21，用户：外部文档控不了）**：中间试过给仓库 18 个中文 `.md` 批量补 BOM（裸读当时已验），但写侧修只能覆盖自有文件，外部 uncontrolled 的 UTF-8 照样乱码，方向错，整单 revert（`f9d6e52`），conventions §8 回到 B 档例外原样。改读侧：新 `Get-ContentUTF8`（Basic，B 档；.NET `ReadAllLines`/`ReadAllText` 直读，默认 UTF-8 + 自动识别 BOM，5.1/7 同行为），外部文件一次解决。另记：5.1 沙箱捕获输出本身按 GBK，验证读正确性要用字节往返（读→写文件→对字节），不能看捕获屏显——屏显乱码≠读错了。
41. **5.1 乱码归因（2026-09-21，用户问 GBK 行为取决于什么）**：取决于 Windows"非 Unicode 程序的语言"（ANSI 页，`GetACP`），不是 PowerShell；.NET Framework 的 `Encoding.Default` 跟系统走（本机实测 ANSI=`gb2312`）。读文件走 ANSI 页、控制台显示走 OEM 页（本机 `utf-8`），两旋钮独立，查乱码先分清读错还是显示错。非中文系统同样中招（ANSI=1252 等，错法不同）；.NET Core 的 `Encoding.Default` 恒为 UTF-8，跨版本对比时别被它骗了。不动系统（Beta UTF-8 worldwide 影响全局老软件），从读侧解决，见 §13。
42. **大模块拆分开工（2026-09-22，用户：先拆到足够灵巧 + 删 uploadPic + 删 Deprecated）**：删除 `uploadPic`（`uploadPicMarkdown` 独立调 picgo，不受影响）、`Deploy-GithubHostsAutoUpdaterDeprecated`（未进 manifest，只删体）、`Get-MySqlDatabaseNameCmdletDeprecated`（含 manifest）；第一刀 `Pwsh(1162/29)→Pwsh(460/8)+PsEnv(261/8)+PsDebug(463/13)`，命令名不变，跨模块调用走自动发现（已验路由）。施工教训：`[IO.File]::WriteAllLines` 默认 CRLF，会把 LF 存量全改写——拆分脚本一律显式 join+`WriteAllText` 保换行；`Write` 工具建的新文件是 LF，记得转 CRLF；切除脚本禁止重复执行（锚点校验是唯一保险）。Module-Map 58 模块。
43. **第二刀（2026-09-22）：`TaskSchdPwsh(1151/14)→TaskSchdPwsh(711/9)+TimeNotify(447/5)`**：提醒簇（Toast/报时/上报）迁出，`Start-Trigger` 内调 `New-TimeNotification` 走自动发现。另记：原文件尾无换行符，拆分顺手补上（diff 里单个 `+}` 即此）；`git diff` 与 `--ignore-cr-at-eol` 统计差 1 行时先查尾行换行符，别慌。
44. **第三刀（2026-09-22）：`Tools(1089/24)→Tools(405/10)+WinConfig(696/14)`**：系统配置开关簇迁出（Defender/更新/任务栏/时间同步/激活/分辨率/重启）；`Tools` 留通用小工具，Map 里顺手补上一直缺失的 `Tools` 行。Module-Map 60 模块。第一批三刀收工，下一批 Basic/Deploy/Web/Info。
45. **第四刀（2026-09-22）：`Basic(2005/86)→Basic(908/46)+FileSystem(+19)+NetWork(+13)+RepoSync(265/8)`**：86 函数体逐字对账零差异（86/86；13 个 EXTRA 全是 FS/Net 原有函数）。附带 `NetWork` 升 B 档：2 处三元改 `if` + psd1 降 5.1 + 补 BOM（11 个 B 档 manifest 5.1 全过）。
46. **psd1 中文引号坑（2026-09-22，血泪）**：无 BOM 的 psd1 里，中文写进**引号字符串**（如 Description）会让 5.1 报"restricted language / string missing terminator"——5.1 按 GBK 解码，某些字的 UTF-8 字节重组后落单成 GBK lead（如"送"=E9 80 81 的 0x81），fallback 把后面的收引号一起吞掉，字符串从此不闭合。中文写进 **`#` 注释**则安全（坏只坏到行尾）。铁律：**无 BOM 的 psd1，中文只许进注释，不许进引号**（psm1 有 BOM 免疫）。已把本次引入的两处中文 Description 改回英文；新 B 档模块 Description 一律英文。
47. **第五刀（2026-09-22）：`Deploy(2931/46)→Deploy(1401/24)+Scoop(827/10)+DevEnv(733/12)`**：46/46 函数体逐字对账零差异。Deploy 回归"新机收尾"本义。Module-Map 63 模块。
48. **第六刀（2026-09-22）：`Web(1867/24)→Web(1498/21)+SSH(+3)`、`Info(1719/27)→Info(1086/12)+Hardware(438/11)+NetInfo(213/4)`**：两处 24/24、27/27 函数体逐字对账零差异。教训：`Info` 4 网络函数曾短暂进 B 档 `NetWork`，5.1 下 `Import-Module` 当时能过（20/20），但直调即炸——`Confirm-DataJson`（Json 留 7）运行时依赖会顶掉 Prompt 的 5.1 垫片（`Get-Command` 找得到就不定义垫片）。遂回滚独立成留 7 的 `NetInfo`，5.1 prompt/ Balance 双双 0 错误复验通过。铁律补一条：**往 B 档塞函数，光解析过不够，必须 5.1 直调跑一遍**；`Update-SSNameServers` 是 Spaceship 域名不是 SSH，留 Web。Module-Map 65 模块。
49. **第七刀（2026-09-22）：`WordPress(3799/33)→WordPress(1685/9)+WpOnline(1382/18)+WpContent(748/6)`**：33/33 函数体逐字对账零差异；原文件尾本就无换行符，原样保留（这次没顺手补）。WordPress 留本地建站 + 总入口 `Deploy-Wp`（跨模块调用走自动发现）。Module-Map 67 模块。至此 Top8 全拆完。
50. **酌情 5.1 第一批（2026-09-22）：`PsDebug`/`PsEnv`/`Shortcut`/`PathProcess`/`Hardware`/`Proxy` 降 B 档**：全仓库 5.1 解析扫描先行（25 个 7.0 模块解析零错误，余下全有 7 语法），这 6 个日常价值高 + 运行时无 7 依赖，逐个 5.1 直调冒烟（11 个调用 0 错误）+ 7 回归后降档，psm1 补 BOM。`Hardware` 修一处 `$IsWindows` 空值穿透（`($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)`，mac/linux 分支加 `-eq $true`）。B 档 9→17。剩下解析零错误的（Json/Startup/WinSys/ArgumentCompletion 等）要动 init 链或价值低，留待下一批按需定级。
51. **酌情 5.1 第二批（2026-09-22，从易到难）：17 个解析零错误模块降 B 档**：`Json`/`WinSys`/`Startup`/`ArgumentCompletion`/`Mock`/`Users`/`Calendar`/`ColorSettings`/`Browser`/`TestLinks`/`NetDrivers`/`ControlPanel`/`WIFI`/`HelpExamples`/`backup`/`BTCN`/`Cloudflare`，逐个 5.1 导入 + 代表函数直调冒烟 + 7 回归。两处真修：`Mock` 的 `$printableChars` 等 5 个字符集全仓库无定义（catn 式 phantom，7 下静默空串、5.1 下 `Get-Random` 抛错），改函数内自包含（有预定义仍尊重调用方）；`colorSet` 的 `inlineprediction` 配色在 PSReadLine 2.0.0（5.1 自带）必炸，改"未加载跳过 + 2.1 才设 inlineprediction"，双版本已验。`Startup` 三处 `$IsWindows` 同 Hardware  pattern 兜底。副作用类（backup 全写文件/Cloudflare-TestLinks 走网络/Browser 开页面）只验导入不直调；`HelpExamples` 教学函数沙箱无 help 文件会炸、7 沙箱同炸，系环境缺 help 非版本问题。B 档 17→34。
52. **酌情 5.1 第三批（2026-09-22）：`Pwsh`/`Deploy`/`Link`/`openApps` 降 B 档，BOM 归一重扫先行**：教训——无 BOM 中文在 5.1 下 GBK 解码吞引号，报的全是误报位置；内存加 BOM 后重扫才是真错误数（`Deploy`28→1、`Web`22→0、`Tools`24→0，`Whois`47→34 仍是真硬）。`Pwsh` 的 1 处即 BOM 误报，另修 `Sync-ModuleManifest` 取哈希表键（5.1 的 `Select-Object -ExpandProperty` 看不见，改点号取值，双版本同行为）；`Deploy` 修 doctor 三元 + `$IsWindows` 文案分支；`Link` 修三元；`openApps` 去冗余后台 `&`。`TaskSchdPwsh`/`TimeNotify` 的真后台 `&` 在 5.1 无等价写法，留 7（已记 §13）。B 档 34→38。另记两坑：我自己的验证命令 `Measure-Object | Select-Object -ExpandProperty Count` 在 5.1 下同炸（以后验证脚本只用点号/索引取值）；`Get-GithubMirrorPrefix` 交互选镜在非交互会话 5.1/7 同炸（7 侧还有 `.Trim()` 老 bug，待修）。
53. **`Sync-ModuleManifest` 5.1 双重编码事故（2026-09-22，自摆乌龙）**：验证跑 `Sync-ModuleManifest -Name Mock` 时，5.1 下 `Select-Object -ExpandProperty` 取键失败是非终止错误，执行流带着空 `$exported` 继续走，把"缺失"误判全量追加（`Mock.psd1` 被写出重复导出）；更糟的是读路径 `Get-Content -Raw` 按 GBK 解、写路径 `[IO.File]::WriteAllText(UTF8)`，中文注释被双重编码洗坏（56→62 字符，逐字节对 HB 查出）。已修两处（点号取值 + `[IO.File]::ReadAllText($psd1, UTF8)` 自动识别 BOM），`Mock.psd1` 从 HEAD 恢复，双版本空跑哈希一致已验。铁律：**验证脚本不许调用会写仓库的函数**（`Sync-ModuleManifest -Reload`、各类 `Deploy-*`、`Install-*`），只读验证；真要测写路径，拷到沙箱外测。
54. **裸 `$IsWindows` 探针门禁（2026-09-22，用户问"有好方法修类似问题吗"）**：5.1 根本没有 `$IsWindows` 自动变量，`if($IsWindows)` 恒假，Windows 分支被跳过、掉进 mac/linux 分支（`Get-MemoryCapacity` 在 5.1 下调 `sysctl` 即此病）。三件套治本：(1)**分诊**——只有 psd1=5.1 的 B 档模块才会被 5.1 加载，裸探针只查 B 档，7.0 模块的今天无害；(2)**门禁**——降档/动平台分支必跑 `rg -n 'if\s*\(\s*\$[Ii]sWindows\s*\)' PS/<模块>/<模块>.psm1`，活代码必须零命中（`#` 注释除外），命中即换 `($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)`；(3)**双版本冒烟**——7 跑通 + 5.1 真跑（如 `Get-MemoryCapacity` 双版本同吐 31.77GB）。不建中央 `Test-IsWindows()` 函数：跨模块调用拉依赖，单独 `Import-Module` 即断，违背灵巧模块初衷，内联探针零耦合（7 上 `($PSEdition -eq 'Desktop')` 恒假，语义与旧条件逐字等价）。本次预修 5 处 7.0 潜伏点（`DevEnv:120/252`、`Sitemap:326`、`Web:680`、`WinConfig:419`，另 `Info:424` 同修），最阴的是 `Sitemap:326`——降档后会静默跳过路径归一化（错得无声，比报错更坏）。
55. **酌情 5.1 第四批 + `Json` 读写根治（2026-09-22，用户：值得兼容的继续）**：BOM 归一重扫颠覆认知——剩余 7.0 模块里 25 个真错误数是 0（之前 `Scoop/Security` 的 2、`Git/SSH` 的 3 全是无 BOM 误报；真硬只剩 `Whois`34 个 `??`、`TaskSchdPwsh`1 个 `&`、`TimeNotify`2 个 `&`）。本批降 6 小模块（`Special`/`Window`/`Security`/`RecycleBin`/`NetInfo`/`Tools`，B 档 38→44），抓到两条运行时刻录：(1)`Special` 无 BOM 时 5.1 报 `Missing ')' in function parameter list`——BOM 归一解析零错也拦不住，铁律再加一条：**解析过≠能跑，必须 5.1 真机直调**（#48 铁律的回声）；(2)`NetInfo` 的 prompt IP 缓存在 5.1 下读出 `浠?`——`Json` 读路径 `Get-Content -Raw` 按 GBK 解 UTF-8（`E4 BB`→`浠`），修 `Json` 4 读 2 写为 `[IO.File]::ReadAllText/WriteAllText(UTF8)`（`ReadAllText` 自动识别 BOM；有意不用 `Get-ContentUTF8`：跨模块调用在单独 `Import-Module Json` 时即断，零耦合优先），`Update-Json→Get-Json` 双向字节往返已验（`以`=`E4 BB A5` 双向无损），5.1 的 prompt IP 回到 `<以:192.168.0.104>`。另记三事：验证脚本本身含中文必须带 BOM 跑 5.1（否则入参进函数前已乱码，修出误报冤案）；行内 `pwsh -Command` 里 `$b[0]` 之类索引写法会被吃掉，复杂命令一律写 `.ps1` 再 `-File`；`PsFzf`/`PsZoxide` 不是本仓库模块（是第三方模块的环境变量开关），`Test` 是用户草稿区（manifest 还有幽灵导出），两类都不碰。
56. **酌情 5.1 第五批（2026-09-22，日常高频）：`Git`/`Scoop`/`SSH`，B 档 47**：三模块 BOM 归一真错误数都是 0，psd1 Description 本就英文，直降。冒烟分三档：`Git` 的 `gitS`（`git status` 只读）双版本直调；`Scoop` 全员 `Deploy/Set/Update` 副作用（装软件/换源/写配置，多需管理员+联网）、`SSH` 全员需远端主机/密钥——只验导入不直调（副作用/外依赖类一律如此，前批 `backup`/`Cloudflare` 同例）。5.1/7 双版本 `Test-ModuleManifest` + 导入函数数一致（Git 15/Scoop 10/SSH 12；5.1 下 `Deploy-*` 动词警告是既有命名风格，7 同制，非阻塞）。另记：`Git.psm1` 有两处 `function git` 重复定义（后胜前），历史包袱，行为不变，不动。
57. **酌情 5.1 第六批 + 第七批（2026-09-22，非高风险全收，B 档 47→62）**：第六批低风险（`TextProcess`/`Text`/`CSV`/`ArchiveProcess`/`Info`/`Sitemap`，代表函数双版本直调），第七批中风险（`TerminalTools`/`Development`/`DevEnv`/`MySql`/`WinConfig`/`Web`/`WordPress`/`WpContent`/`WpOnline`，只验导入+逐项注明，`Test-IsIPAddress` 直调）。三处真修：(1)`ArchiveProcess:129` 的 `Split-Path -Extension` 是 6+ 独占参数，改 `[IO.Path]::GetExtension`（与 `TextProcess` 内既有写法统一）；(2)`Info` 的 `Get-MemoryUseRatio` 跨模块调留 7 的 `Start-ScriptWhenIntervalEnough`，5.1 下 `Get-Command -ErrorAction Ignore` 探不到就直接 `& $s`（与首建缓存分支一致；注意 `& 脚本块` 调用在 5.1 合法，禁的是后台 `&`）；(3)`WinConfig.psd1` 中文 Description 转英文（#46）。`Sitemap` 的 `-Parallel` 只在 `-Threads` 非零时触发，默认串行，5.1 不传参即安全。本轮最大收获是**注释吃行**机制（#55 预告的验证脚本 BOM 要求之根因）：无 BOM 的 LF 文件里，`#` 注释尾字若是中文，其 UTF-8 尾字节常落单成 GBK lead（如 `给`=`E7 BB 99` 的 `0x99`），吞掉后面的换行符，注释把下一行代码"吃掉"——下一行静默不执行、无报错（实测 `$global:DataJson` 赋值凭空丢失就是这么来的；mini 复现：纯 ASCII 脚本正常，加一行中文注释即复现；GBK 视角看两行已合并为一行）。推论与处置：B 档 psm1 全有 BOM，免疫；全仓库无 BOM psd1 扫描——行首/行尾 `#` 中文尾字仅 `PSScriptAnalyzerSettings.psd1:1`（Analyzer 自读 UTF-8，不进 5.1 引擎，无害），其余全是留 7 模块的休眠雷（降档补 BOM 时自然消除）。铁律升级：**验证脚本含中文必须带 BOM**（#55）+ **psd1 中文注释尾字禁 CJK**（行尾加个 ASCII 标点即破，如 `# B档兼容集` 行尾的 `)` 就是安全的）。
58. **跨设备编辑与 BOM（2026-09-22，用户问 Linux/mac 改完会不会丢 BOM）**：结论——**git 传不丢**（无 `text`/filter 声明 + `core.autocrlf=false`，字节透明；本仓库无 `.editorconfig`，更无服务端改写），BOM 只会在编辑保存瞬间丢。风险排序：vim 默认 strip（`bomb` 默认 off，头号雷）> 显式"Save with Encoding" > 格式化插件重写 > VS Code 默认（自动识别保留，最稳）；新建文件各家默认都无 BOM。最阴的是爆炸半径只在 Windows 5.1（乱码/#46/#57），Linux/mac 上全绿、回 Windows 才炸。处置见 `Module-Conventions.md §8.1`（机制 + 门禁扫描命令 + 补 BOM 命令，当前 62/62 全绿已验；门禁片段照抄可跑，初版缺 `Test-Path` 守卫已修）。另：Linux 编辑器常存 LF，入库无碍（5.1/7 都认），别整文件转 CRLF。
59. **5.1 老 conhost 下 VT 序列原文输出（2026-09-22，用户报 `Show-MemoryBar` 满屏 `e[1A`e[2K` 且刷新起新行）**：根因——`` `e `` 转义本身 5.1 合法，坏的是 conhost 默认没开 VT 解析（`ENABLE_VIRTUAL_TERMINAL_PROCESSING`），`[1A`上移/`[2K`清行全成字面量，刷新自然只能另起新行。全仓库活 VT 仅此一处（`Prompt` 的是注释，`BTCN:528/534` 的 SGR 颜色码另案）。修法（`Info.psm1`，嵌套 helper 与函数原有风格一致）：首帧前 `Enable-VirtualTerminalProcessing`（Add-Type 调 kernel32 开 VT，只编译一次；重定向/老系统/非 Windows 返回 `$false`）；开成就走原 VT 逻辑（与 7/WT 行为一致），打不开走 RawUI 兜底（光标回块首→按行覆空格清尾→回块首等重绘，全版本通用，try/catch 包裹，终极失败退化为现状）。沙箱验证：双版本解析零错 + `-NoLoop` 单帧 + 5.1 后台两帧输出无 VT 残留；真 conhost 原位覆盖效果需用户真机确认（沙箱重定向测不到）。
60. **真机打回：`` `e `` 是 6.0+ 转义，5.1 下退化成字母 `e`（2026-09-22，接 #59）**：用户真机仍满屏 `e[1A`——注意是字母 `e` 不是 ESC 控制符，说明发的根本不是 ESC 字节，开 VT 也白开。`` `e `` 系 6.0 新增，5.1 遇到未知转义直接掉字面（与 `Split-Path -Extension` 同类：解析零错、运行时跨版本行为不一致）。修法：`Info:1032` 与 `BTCN:528/534`（同类连带，B 档 `Write-Highlighted` 的 SGR 颜色在 5.1 下同样吐 `e[0m` 字面）一律换 `$([char]0x1b)`（从远古版本通用，双版本逐字节同行为）。5.1 字节实锤：清行串=`1B 5B 31 41 1B 5B 32 4B`（真 ESC），`Write-Highlighted` 输出 `[31;40m…[0m` 无 `e` 字面（该函数走 `Write-Host`，管道收不到是预期，字节以屏显为准）。禁区行已加：B 档禁 `` `e ``。`Init:376` 的 `` `ep `` 在 `<# #>` 注释块内，不执行，不管。待用户真机复验（真 ESC + VT 开启两条件齐了，原位刷新应好）。

## 4. 环境事实（这台机器，2026-09 实测）

- pwsh 7.5，`$HOME=C:\Users\Administrator`，`$env:PSModulePath` 首位是
  `Documents\PowerShell\Modules`，`C:/repos/scripts/PS` 在第 5 位。
- 四级 profile：`AllUsers*` 不存在；`CurrentUserAllHosts` 只有 conda 块；
  `CurrentUserCurrentHost` 是 `init` + 注释掉的 argc/fnm。
- WT 线上配置无 pwsh7 自定义 profile；仓库 `Config/wtConf*.json` 仅供参考，
  部分 tab 用 `pwsh -noe -c p`（外层 profile 跑完 `init` 后 `p` 会 no-op，别被两层吓到）。
- 常驻进程：`Start-TimeAnnouncer`、`Update-NetConnectionInfo` 守护进程、
  用户开 tab 留下的 `pwsh -noe -c p/init` 瞬态进程——测启动耗时前先看一眼，
  别把别人的常驻进程当自己的 bug。
- `~/Data.json` 是运行态文件（IpPrompt/ConnectionName/内存缓存），别提交；
  `~/.conda_hook_cache.ps1`、`$TEMP/CxxuPwshVar_*.cache.ps1` 同理。

### WSL 直接访问本仓库（2026-09-20 与 WSL git 2.54 对测，结论：能用，但三条红线）

- **能直接用**：同一 `.git` 目录，`git -c core.quotepath=false --git-dir=/mnt/c/repos/scripts/.git
  --work-tree=/mnt/c/repos/scripts status` 与 Windows 侧已做到逐行一致（`PS/` 100%，
  含 5 个 `wp/` 真修改）。先天已有 `core.filemode=false` + `ignorecase=true`，不用动。
- **红线 1——不要动仓库本地 `core.autocrlf=false`**（`.git/config`，两侧共享，一处写两处生效；
  WSL 全局保持默认即可，千万别设 `true`）。血泪史：Windows 全局曾是 `true`，
  `git add` 把 CRLF 归一化成 LF 存进 index，而工作区字节从没变过——Windows 双向过同一滤镜
  所以显示干净，WSL 做原始比较当场现形（`A` 变 `AM`）。找这类病用 blob 哈希数学：
  `blob(raw)` vs `git rev-parse :path`，对不上就是 index 被污染。
- **红线 2——racy-git 缓存会瞎**：只改配置/属性不动文件时，mtime/size 全一样，
  `git add` 会信 stat 跳过重哈希（配置变了但 stat 没变）。强制重哈希：`touch` 文件再 `add`
 （或 `git add --renormalize`，但注意它会把真改动也顺手暂存）。修完必用 `blob()` 验 index。
- **红线 3——`wp/` 是用户领地**：WSL 可能比 Windows 更早看到 ` M`
  （DrvFs 的 stat 视角不同，会逼 git 重哈希说真话；Windows 的陈旧 stat 缓存过期后也会显示）。
  如那 5 个 conf/sql（用户编辑器翻成 CRLF 相对 LF 历史是真修改）：**别顺手 add**，
  更别 `--renormalize` 整个仓库——范围永远限定在 `PS/` 与根。
- 其余：换机器若报 `detected dubious ownership`，在 WSL 里跑
  `git config --global --add safe.directory '/mnt/c/repos/scripts'`（注意是 WSL 路径格式）；
  两侧不要同时跑 git（抢 `index.lock`）；WSL 下 push 要单独配 credential（远端是 gitee+github
  双 pushurl）；`/mnt/c` IO 慢，`status` 耗时长正常；`wsl` 偶发
  `Failed to start the systemd user session` 不影响 git 命令本身，无视。
- WSL 里新建/改文件同样守 `Module-Conventions.md §8`（存量换行不动，新文件 CRLF）；
  诊断三件套：`git ls-files --eol`、`git diff --ignore-cr-at-eol --stat`、blob 哈希对账。

## 5. 文档分工（改代码必看要不要同步）

| 文档 | 内容 | 什么时候更新 |
|---|---|---|
| `Module-Map.md` | 53 模块画像、热路径链、数据流 | 增删模块/搬迁/热路径变化 |
| `Deploy-Guide.md` | 新机部署：checklist 命令 + 分步指南 + 多设备差异 | 新机器部署/增删部署步骤 |
| `Feature-Guide.md` | 用户手册：入口、主题、开机、FAQ | 用户可见行为变化 |
| `Module-Conventions.md` | 编码铁律、已接受偏差清单 | 立新规矩/新例外 |
| `Startup-Optimization.md` | 性能基线、搬迁史、TODO | 每次性能改动（附实测数） |

## 6. 未决事项（2026-09-20 更新：前三项已解决）

- ~~`Mock`、`Test`（whois 名实不符）、`CommentBasedHelpDocumentExamples`：删还是留~~
  → 用户拍板：全保留做特殊用途；`Test`→`Whois`、`CommentBasedHelpDocumentExamples`→`HelpExamples`
  已改名（函数名/GUID 未动），`Mock` 不动。
- `Deprecated` 模块：用户拍板删除（转正后仍无存在必要，零调用已核实），`git rm` 整目录，
  历史可追溯，对照表见 `Startup-Optimization.md §16`（历史记录）。
- ~~`VarSet1.conf` 换行抖动~~ → 查清是 `.gitattributes` 的 `text` 归一化假 diff，
  不是用户编辑器问题；已修（见 `Startup-Optimization.md §13`），文件本身零改动。
- `Tools` 剩 1078 行：继续原子化还是维持 misc 定位，待定。
- `Deploy.psm1` 2653 行：冷路径，暂不动。
