# PS 模块规范（CxxuPsModules）

> 背景：此前只求能跑，50+ 模块存在命名随意、无 manifest、注释块里混函数定义等问题。
> 本规范 2026-09 起执行：**新代码强制，存量 grandfathered（只修高价值项，不重命名现函数）。**

## 1. 目录即模块

- 一个模块 = `PS/<Name>/` 目录 + 同名 `<Name>.psm1`（自动发现只认这个组合；
  曾有 `Deploy/TestLinks.psm1` 因名实不符从未被加载过，已整改为 `PS/TestLinks/TestLinks.psm1`）。
  唯一例外 `CxxuPredictor`：二进制模块（`.psd1` + `.dll` + `src/`，无 `.psm1`；
  `Sync-ModuleManifest` 按“有同名 `.psm1`”枚举，天然跳过它）。
- 每个模块必须有同名 `<Name>.psd1`：
  `RootModule`、`ModuleVersion`（当前集版本见 `Init` 的 manifest，本次 `1.0.4`，破坏性变更才 bump）、
  `GUID`（稳定不变）、`Author`、`PowerShellVersion = '7.0'`、
  **`FunctionsToExport` 显式全量列出**（自动发现不解析 `.psm1`，启动更快）。
- 新增/删除函数后必须同步 manifest（偷懒用 `Sync-ModuleManifest <模块名> -Reload`，
  只增不减，GUID/版本/换行不动；不指定模块名则全量，`-Name` 支持 Tab 补全）。
  校验脚本逻辑（块注释感知，见 §7）：
  `Test-ModuleManifest` 全过 + `Get-Command -Module X` 数量与文件内定义一致。

## 2. 命名

- 新函数一律 `Verb-Noun`，动词用 approved verbs（`Get-Verb` 可查）：
  允许 `Get/Set/New/Remove/Update/Test/Start/Confirm/Install/Deploy/Backup` 等；
  禁止自造动词、私人缩写（`qq`、`dm`、`ipmof` 这类存量保留，别学）。
- **单横线铁律**：导出名最多 1 个 `-`。2 个以上触发 `restricted characters` 警告
  （`Import-Module` 报，自动加载不报；16 组合成模块实测）。废弃/归档/变体标记用
  **融合后缀**（`*Deprecated`、`*Archived`、`*Robust`，见 §16 对照表），禁止 `-Xxx-Yyy` 形式。
- 存量改名三档（2026-09-20 用户拍板，见 `Startup-Optimization.md §16`）：
  改（双横线 17 个 + 拼写 typo 2 个，有调用方先改调用方）；不碰（130+ 无横线个人速记，
  肌肉记忆优先）；不归一（大小写，引擎不敏感，零收益纯 churn）。
- `Test` 模块是临时草稿区，不受本节约束；函数转正（移到正式模块）时再合规化，转正后草稿区删掉。

## 3. 导出

- 以 manifest 的 `FunctionsToExport` 为唯一真相源；`.psm1` 内不要再写
  `Export-ModuleMember`（唯一例外 `Calendar` 已对齐，勿新增）。
- 顶层代码只允许：函数/类定义 + 轻量只读数据（如镜像站列表）。
  **禁止顶层副作用**（网络、写文件、起进程）——模块 import 必须快且静默。
- 跨模块调用只靠函数名（自动加载），禁止 `Import-Module <兄弟模块>` 硬依赖。

## 4. 输出流规范（血泪区）

- 工具函数只向**成功流**输出对象（`return`），装饰性文字走 `Write-Verbose`；
  需要用户确认走 `ShouldProcess`/`Read-Host`，不要 `Write-Host`。
- `Write-Host` 仅允许：prompt 渲染、`init` 等一次性状态提示。
- **热路径（init、prompt）禁区**：`Write-Progress`、`Get-Module -ListAvailable`、
  `Get-CimInstance`、注册表写、spawn 新进程、裸 `Invoke-Expression`。
  高频状态一律走“缓存文件/环境变量 + 后台守护进程更新”（现有模式：`DataJson` + `Update-NetConnectionInfo`）。
- 函数返回值会被调用方管道消费：不需要的值一律 `| Out-Null`，
  曾因此漏出裸路径字符串污染控制台（`Confirm-DataJson` 事件）。

## 5. Invoke-Expression 使用规范

`PSAvoidUsingInvokeExpression` 默认应修，唯二例外（本地可信配置解析，借官方 parser）：

1. `Aliases` 的别名文件：含引号/变量引用/行尾注释，手写 parser 必错，保留 iex。
2. `PwshVar` 的 `.conf` 文件：同上，但已加**预编译缓存**
  （`Get-CompiledPwshVarLines`：同规则单次解析 + `Parser` 语法校验 + mtime 失效 + 回退逐行路径）。

远程内容（`irm ... | iex`）只允许出现在文档示例和一次性部署脚本，禁止进入模块函数。

## 6. 管道与参数

- 声明 `ValueFromPipeline` 的必须写 `process {}` 块（曾有 `Get-Json` 无 process 块，
  管道多对象时只取最后一个，已修）。
- 死参数（声明不用）直接删除，除非补全器签名强制要求
  （`Register-ArgumentCompleter` 的 scriptblock 参数表必须全写，即使函数体不用）。

## 7. manifest 再生成规则

函数定义判定（供脚本用，`parity4.ps1` 逻辑）：

- 仅匹配行首 `^function Name`，且 `Name` 后只能跟 `{`、`(`、行尾或 `#`；
- 跳过 `<# ... #>` 块注释内部（曾把帮助文本 `Function that shows...` 误收录为函数 `that`）；
- 单行定义（`function ept { explorer . }`）、`Name()` 形式都算数。

## 8. 编码与换行

- 统一 UTF-8 **无 BOM**（PS7 默认即此；Analyzer 的 BOM 规则已在 settings 中排除）。
- 例外：B 档 5.1 兼容集（见 `Feature-Guide.md §13`，34 模块 psm1 + `VarSet3.conf` + `VarLongStrings.ps1`）**必须带 BOM**——5.1 中文 Windows 无 BOM 按 GBK 解码，中文全乱码；psd1 降版行以 `# B档兼容集` 注释标记，BOM 文件不再回退。
- 换行 LF/CRLF 均可，存量文件保持原状（最小 diff 原则），新文件建议 CRLF。
  `.gitattributes` 只声明二进制（lnk/exe/dll），**不声明 `text`**——历史 blob 是 CRLF
  原样入库的，声明 `text` 会触发归一化、把全仓库标成假 diff（2026-09-20 实测，见
  `Startup-Optimization.md §13`）。仓库本地 `core.autocrlf=false`（两侧共享），不要改；
  WSL 访问注意事项见 `Agent-Handoff.md §4`。

## 9. 版本与变更

- 集版本号存在各 manifest 的 `ModuleVersion`（当前 `1.0.4`）；
  加函数/修 bug 不 bump，只有删除/改名/改行为才 bump 并在提交信息注明。
- 提交信息沿用仓库风格：`perf:`/`fix:`/`chore:` + 中文简述。

## 10. 已接受偏差清单（Analyzer Warning 不修项）

| 规则 | 原因 |
|---|---|
| `PSAvoidUsingWriteHost` | prompt 渲染刚需（settings 已排除） |
| `PSUseBOMForUnicodeEncodedFile` | PS7 无 BOM 即正确（settings 已排除） |
| `PSUseShouldProcessForStateChangingFunctions` | 存量 `Set/Update/Remove/Start-*` 追溯加 ShouldProcess 会改变交互行为（可能卡住非交互流程），新函数按需加 |
| `PSUseSingularNouns` | 改名破坏兼容（`Tasks`/`Profiles`/`Vars` 等存量保留） |
| 补全器 scriptblock 的未用参数 | 注册器签名强制要求 |
| `oh-my-posh ... \| Invoke-Expression` | 上游官方用法，无替代 |

## 11. 文档语言规范（用户可见文本）

> 背景：简短黑话（“锁主”“拷不过去”“不断根会装回来”）含义不明，易误解。函数帮助、指南、表格、警告信息必须用正式规范语言；代码注释可简，但缩写首次出现须注。

- 用完整主谓结构，不堆无主短句；禁用未定义的缩写与比喻（不写“咬住/锁主/拷/一把梭/自愈/不断根”）。
- 动作说明写全三要素：前置条件 → 执行者 → 善后（是否需重开终端/确认/持久化）。
- 警告与失败信息必须给出路（给出命令或步骤，不只陈述失败）。
- 术语首次出现必须定义，之后统一复用，以下表为准：

| 术语 | 定义 |
|---|---|
| 仓库源 | 随仓库分发的文件原件（如 `PS/CxxuPredictor/CxxuPredictor.dll`），运行期从不被加载 |
| 活件 | 实际被加载的副本（`~/.cxxu/bin/<哈希>/CxxuPredictor.dll`，文件名不变以保证模块名正确） |
| 指针 | `~/.cxxu/bin/current.txt`，单行内容为当前版本目录名，入口 loader 按指针装载 |
| 无锁子进程 | `pwsh -NoProfile -NonInteractive` 拉起的子进程，不运行 init、不加载 predictor，文件操作不受锁限制 |
| 自锁 | 当前会话已加载旧版活件，文件被本进程锁定，覆盖/删除操作必然失败 |
| 他锁 | 文件被其他 pwsh 会话锁定 |

## 12. 长文档语言风格（正式、严谨、清晰易懂）

> §11 管"用词"（禁黑话、术语统一），本节管"行文"。设计型章节（如并排版本活件）必须同时满足三条，缺一不可。

- 正式：完整主谓结构，中文标点（，。：；），不用口语缩写与感叹式表达。
- 严谨：每个机制陈述前置条件与边界（何时成立、何时不成立、失败时发生什么）；数字给出来源（实测/源码/文档），不写"很快""基本"这类无刻度副词。
- 清晰易懂：定义 → 机制 → 示例的顺序；单个流程超过三步必须配 mermaid 图（`flowchart` 表流程分支，`graph` 表静态结构，`sequenceDiagram` 表多角色交互）；图后必须有一段文字复述图的结论（图挂了读者仍能懂）。
- 一章只讲一件事：背景、结构、流程、故障、命令分工各自成节，互不掺杂。
- 换行：一个段落（或列表项）写成一个逻辑行，充分使用水平空间；禁止句中硬换行（渲染无差异，但源码难读、diff 噪音大）。围栏代码、表格、标题除外。
- 加粗：只强调三类——结论判定句、禁止/必须约束、关键阈值。命令/路径/文件/参数用行内代码，不加粗；术语用代码 + 定义，不加粗。一段至多一处加粗，表格每行至多一处；警告块首句加粗（如必须重开终端）。
