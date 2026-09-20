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
| `Set-PsPrompt -version < fast \| Balance \| Simple \| Brilliant \| Default \| Short >` | 切换提示符；加 `-Persist` 才写注册表记住选择 |
| `dm` | 切极简 prompt（做笔记摘录时聚焦命令本身） |
| `Test-PromptDelay` | 测当前 prompt 延迟 |

环境等级（`$PsEnvMode`，`Test-PsEnvMode` 查询）：core(1) 核心变量 → vars(2) 全量变量 →
env(3) 变量+别名。`Update-PwshEnvIfNotYet` 按需补齐，不重复干活。

## 3. 改模块 / 加函数（有了 `.psd1` 之后的工作流）

以前只有 `.psm1`，写完函数直接能用；现在每个模块多了 `.psd1`（显式导出表），
**函数只在两个地方都出现才算数**：

```powershell
# 1) 在 PS/<模块>/<模块>.psm1 里写函数（UTF-8 无 BOM，换行跟文件原状走）
# 2) 把函数名加进同目录 .psd1 的 FunctionsToExport（位置随意；GUID/版本不用动，日常改保持 1.0.4）
# 3) 当前会话生效（不用重启 shell）：
Sync-ModuleManifest <模块名> -Reload  # 偷懒版：自动把 .psm1 新增函数补进 manifest 并重载，一条搞定
Sync-ModuleManifest -Reload            # 不指定模块 = 全部 54 个自有模块（只打印有变化的+汇总；Prompt 跳过重载防嵌套）
# -Name 支持 Tab 补全（空字列出全部）；单模块想手动挡就继续 Import-Module <模块名> -Force -DisableNameChecking
# （-DisableNameChecking 定向压掉双横线警告，见 FAQ；其它警告不受影响）
ipmof | iex                     # 重载所有已加载模块（跳过 *completion* 类；Prompt 见下）
```

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
- **`ipmof|iex` 后提示符叠了**：`Prompt` 模块加载时会抓 `$originalPromptScript`，
  重载就抓到旧的自定义 prompt 造成嵌套（`Import-ModuleForce` 只跳过 `*completion*`，
  不跳 Prompt，跳 Prompt 的代码还是注释状态）。改完 Prompt 模块直接重进 shell，别 ipmof。
- **启动进度条**：默认开（`Loading...` + 分步百分比，跑完自动消失）。
  不想要：`$env:PsShowProgress = 'False'`（当前会话）；一劳永逸：
  `Add-EnvVar -EnvVar PsShowProgress -NewValue 'False'`。agent/CI 等重定向场景自动关闭，不用管。
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
