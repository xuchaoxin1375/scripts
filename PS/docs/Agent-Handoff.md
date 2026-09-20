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
