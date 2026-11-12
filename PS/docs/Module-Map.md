# 模块地图（Module Map）

> 67 个自有模块，全在 `PS/<Name>/<Name>.psm1` + 同名 `.psd1`
>（唯一例外 `CxxuPredictor`：二进制模块，`.psd1` + `.dll` + `src/`，无 `.psm1`）。
> 规范见 `Module-Conventions.md`，性能史见 `Startup-Optimization.md`。
> 图例：🔥 启动/提示热路径（改动先跑终验），❄️ 冷路径（按需加载）。
> 查询：`Get-ModuleByCxxu`（自有全家桶，`-SkipUnavailable` 只看可用；
> 5.1 可用）→ `Get-Command -Module <名>`（看导出）→ `Get-Command <命令>`（反查归属）。

## 启动链与提示（🔥，改这里必须全量验证）

| 模块 | 行数/函数 | 职责 |
|---|---|---|
| `Init` | 2667/59 | 启动编排：`init`（刷新用 `-Force`，分步耗时用 `-Timing`）、`p`（只新开 pwsh，不刷新当前会话）、`PsEnvMode` 等级跟踪、`Optimize-PsHistory`、用户配置（`Import/Get-CxxuConfig`、`New-CxxuConfigTemplate`、`Reset-CxxuConfig`；组件清单 `components.psd1` + Settings `config.defaults.psd1`；v2 嵌套结构与旧平坦键兼容）、组件管理（`Get/Enable/Disable-CxxuComponent`、`Enable-CxxuComponent -Now` 即时调用 `InitNow`（未声明时用 `Init`）、`Set-CxxuComponentOption`、`Test-CxxuComponent` 清单/步骤/依赖自检；`Get-CxxuComponent -Id Carapace` 另带 Runtime/RegisteredCommands/CacheState 运行态与 5.1 缓存字段；可选组件 init 步骤由清单生成）、插件启停（`Enable/Disable-PsPlugin`）、git 补全来源切换与检查（`Set-GitCompletionSource`，配置键 `PsGitCompletionSource`；`Get-GitCompletionSource` 只读报告配置值、解析值、已注册来源与回落原因，注册点维护 `$global:PsGitCompletionActive`）、carapace 懒加载（`Register-CxxuTabStub` 装 argc/carapace 共享 Tab 桩，`Initialize-Carapace` 实际加载，`PsCarapace` 默认关；5.1 兼容 `-` 开头词、环境变量上限、空参数与编码；按来源合并排除项）、argc-completions（懒加载；`git`/`gitk` 在 git-completion 或 carapace 负责时让路）、git-completion（检测到模块才注册，首次补全才导入）、可选组件加载（`Import-PsCompletions`/`Initialize-Fnm`/`Initialize-ScoopSearch`，默认关） |
| `Prompt` | 723/32 | 提示符：`prompt` 入口、`Prompt*` 主题、`Write-*` 片段、`Set-PsPrompt`（`-Persist` 才写注册表）、电池 30s 缓存 |
| `CxxuPredictor` | 1170/0导出 | 自研双 predictor：`CxxuCommand` 命令名（分层模糊：别名精确/前缀/词边界/连续片段/一般子序列 + 严格通配；别名也进候选，PSReadLine 历史频率加权，默认 15 条）+ `CxxuArgcFlags`（argc 覆盖命令首参数位的静态 flag，`-` 前缀，≤10 条，表缓存 `~/.cxxu/cache/argc-flags.tsv`）；二进制：dll 发布件 + src；`CompleteCommand` 公开 Tab 接口；活件并排版本 `~/.cxxu/bin`，loader 按指针装载；OnIdle 加载；命令表缓存 `~/.cxxu/cache/tab-commands-<CLR主版本>.tsv`（24h，删除即重建）；5.1 Tab-only 产物 `ps51/CxxuPredictor.dll`（netstandard2.0，仅 `CompleteCommand`，见 [Live-Versions.md](Live-Versions.md) 的『5.1 Tab-only 产物』） |
| `CxxuTab` | 407/1 | 自研 Tab 命令名补全（独立插件：`TabExpansion2` 包装，命令名位合并 dll 模糊结果，参数位透传；函数 `.SYNOPSIS` 首段注入菜单 tooltip，已加载函数取定义文本、未加载模块在 pwsh 7+ 且候选 ≤20 时解析 `.psm1` 源码（不导入模块），开关 `$env:PsTabSynopsis`，默认开；门控 `$env:PsTab` 逐调用判定，**默认开**（置 `False` 关）；异常/超慢调用自熔断；命令表缓存 `~/.cxxu/cache/tab-commands-<CLR主版本>.tsv`；启停见 `Enable/Disable-PsPlugin`；5.1 读 `~/.cxxu/bin/ps51` 活件，7+ 读根活件） |
| `PwshVar` | 329/6 | `.conf` 变量文件加载（预编译缓存，`Update-PwshVars -NoCache` 回退） |
| `Aliases` | 68/2 | 别名文件加载（`alias_core`/`functions`/`shortcuts`，逐行 iex 是故意的） |
| `ArgumentCompletion` | 115/2 | 参数补全注册（`prompt` 已迁出，只剩补全；B 档 5.1） |
| `EnvVar` | 1021/15 | 环境变量 User/Machine/Process 三档；热路径一律 `Set-ProcessEnvVar` |
| `Startup` | 307/12 | 开机任务、后台守护进程、OS 版本缓存（`Confirm-EnvVarOfInfo`；B 档 5.1，`$IsWindows` 加 `PSEdition` 兜底） |
| `Json` | 251/5 | `Data.json` 读写校验（init 与 prompt 共用，无递归设计；B 档 5.1） |
| `Pwsh` | 460/8 | 模块加载脚手架：`ipmox`/`ipmof` 重载（仅仓库内模块）、`New-ModuleByCxxu`、`Sync-ModuleManifest` 偷懒同步（-Name Tab 补全）；版本环境 8 函数已迁 `PsEnv`、内省调试 13 函数已迁 `PsDebug`（2026-09-22，命令名不变；B 档 5.1，哈希表键改点号取值） |
| `PsEnv` | 261/8 | PowerShell 版本/环境：`Update-PowerShell` 升级、`Set-PsExtension`（init 默认跳过；`PsExtension=True` 才调用）、profile 路径管理（2026-09-22 从 `Pwsh` 迁入，init 链会加载；B 档 5.1） |

## prompt 首渲染会顺带加载

| 模块 | 行数/函数 | 职责 |
|---|---|---|
| `Info` | 1086/12 | 系统信息：内存/进程查看、电池（留 7）；硬件 11 函数已迁 `Hardware`、网络连接/IP 4 函数已迁 `NetInfo`（2026-09-22；7 下 prompt 经自动发现走 `NetInfo` 真身，5.1 垫片不受影响已验） |
| `Basic` | 908/46 | 通用小工具与查询（`Get-ModuleByCxxu` 5.1 可用）；文件操作 19 函数已迁 `FileSystem`、网络 13 函数已迁 `NetWork`、仓库同步 8 函数已迁 `RepoSync`（2026-09-22，命令名不变） |
| `TaskSchdPwsh` | 711/9 | `Start-ScriptWhenIntervalEnough`（内存 5s 节流就靠它）、计划任务触发、守护进程；定时提醒 5 函数已迁 `TimeNotify`（2026-09-22，命令名不变） |
| `TimeNotify` | 447/5 | 定时提醒：Toast 通知（`New-TimeNotification(Robust)`）、整点报时（`Start-TimeAnnouncer`）、消息上报（2026-09-22 从 `TaskSchdPwsh` 迁入，冷路径按需加载） |

## 网络与系统

| 模块 | 行数/函数 | 职责 |
|---|---|---|
| `Web` | 1498/21 | HTTP 服务、nginx 站点、域名、下载（`Tools` 拆出）；SSH 远程 3 函数已迁 `SSH`（2026-09-22，`Update-SSNameServers` 是 Spaceship 域名、留 Web） |
| `Text` | 914/14 | 文本/编码/markdown/格式化（`Tools` 拆出） |
| `NetWork` | 242/16 | 网络发现/共享/SMB 会话 + 连通性/IP 网卡/图床上传（2026-09-22 从 `Basic` 迁入 13 函数；顺手把 2 处三元改 `if`，psd1 降 5.1 进 B 档，补 BOM） |
| `NetInfo` | 213/4 | 网络连接/IP 信息：连接名、`Get-IpAddressFormated/ForPrompt`（2026-09-22 从 `Info` 迁入，留 7；曾短暂进 `NetWork`，Json 运行时依赖会顶掉 5.1 垫片，遂独立） |
| `Hardware` | 438/11 | 本机硬件与系统信息：CPU/主板/内存/BIOS/磁盘/显示（2026-09-22 从 `Info` 迁入；B 档 5.1，`$IsWindows` 分支加 `PSEdition` 兜底） |
| `WIFI` | 77/6 | WiFi 连接/重连/测试（B 档 5.1） |
| `NetDrivers` | 443/9 | 网络驱动器挂载、alist/chfs/aria2 服务（B 档 5.1） |
| `Proxy` | 168/5 | 代理开关与系统代理设置（B 档 5.1，2026-09-22 酌情降档） |
| `SSH` | 766/12 | SSH 密钥/服务端/客户端初始化 + 远程执行（`Invoke-RemoteSSH(0)`、`Add-SSHkeyOnHost` 2026-09-22 从 `Web` 迁入） |
| `TestLinks` | 347/4 | GitHub 镜像站可用性测试（含数据源；B 档 5.1） |
| `FileSystem` | 1733/29 | 文件/目录度量（`Get-Size` 等）+ Robocopy 封装 + 日常操作（浏览/检索/改名/链接，2026-09-22 从 `Basic` 迁入 19 函数，B 档 5.1） |
| `WinSys` | 351/16 | Windows 本机设置：键盘输入法/TTS 语音/电源管理（2026-09-21 从 `Basic` 迁入，命令名不变；B 档 5.1） |
| `Tools` | 405/10 | 通用日常小工具：历史/版本/命令可用性/vscode 右键/conda 源（系统配置 14 函数已迁 `WinConfig`，2026-09-22） |
| `WinConfig` | 696/14 | Windows 本机配置开关：Defender/小组件/更新/任务栏/时间同步/激活/分辨率/重启（2026-09-22 从 `Tools` 迁入，冷路径按需加载） |
| `PathProcess` | 351/6 | 路径压缩/转换/风格判定（B 档 5.1，2026-09-22 酌情降档；2026-10-30 `Get-PathStyle` 支持 `Get-Location`/`Get-ChildItem` 等路径对象管道输入） |
| `Link` | 178/5 | 硬链接/软链接/目录链接管理（B 档 5.1，三元改 `if`） |
| `RecycleBin` | 224/5 | 回收站查看/移动/清空 |
| `Security` | 113/4 | CredentialGuard/VBS/重启确认（`Disable-CredentialGuard` 唯一正本） |
| `Shortcut` | 622/8 | 快捷方式读写（B 档 5.1，2026-09-22 酌情降档） |
| `Users` | 14/2 | 用户组/profile 列表查询（B 档 5.1） |
| `Window` | 110/1 | `Show-Message` 消息弹窗 |
| `ControlPanel` | 147/1 | 控制面板小程序启动（B 档 5.1） |
| `Search` | 565/9 | 文件内容/目录/服务搜索 |
| `Whois` | 678/2 | whois 查询（原名 `Test` 名实不符，2026-09-20 改名；函数名未动） |

## 开发与部署

| 模块 | 行数/函数 | 职责 |
|---|---|---|
| `Deploy` | 2178/34 | 新机收尾：github hosts/镜像前缀、防火墙/SMB/自启任务、环境变量；`Test-PsEnvReadiness`、`doctor`、`Get-CxxuDependencyReport`（按功能查外部依赖，清单见 `Deploy/FeatureDependencies.ps1`）在此；Scoop 生态 10 函数已迁 `Scoop`、语言工具链 12 函数已迁 `DevEnv`（2026-09-22，命令名不变；B 档 5.1，doctor 三元改子表达式 `if`） |
| `Scoop` | 984/11 | Scoop 包管理：国内镜像部署、批量装机、版本切换、`Repair-ScoopUpdate`（修复 update 被未提交更改中断，2026-09-22 从 `Deploy` 迁入，冷路径按需加载） |
| `DevEnv` | 2378/27 | 语言工具链与编辑器开箱：Python/conda/C++/Typora/VSCode/WT/补全栈（`Deploy-CompletionStack` 默认只装仓库内核心层，argc/PSFzf/fzf/zoxide 按 `-Include*` 追加；`-IncludePSReadLine51` 把 5.1 的 PSReadLine 从 2.0.0 升到 2.3.6，优先离线复制本机模块；`Install-Ps51PSReadLine` 提供单独入口；`Deploy-ArgcCompletions` 并发下载、支持代理，并优先取 `scripts-deps` 转存仓库的固定版本；`Deploy-Carapace` 按 Windows/macOS/Linux 与 amd64/arm64 从官方 Release 下载、校验并安装 carapace，下载优先 aria2c 多连接并打印链接/来源，镜像可用 `-NoGithubMirror`/`-GithubMirror` 控制，`-Enable` 可安装后直接启用组件，`-Bash`/`-BashLogin` 装完顺带写入 bash rc；2026-09-22 从 `Deploy` 迁入，冷路径按需加载） |
| `Development` | 340/22 | Django 快捷命令、ssh 别名、文本清理 |
| `Git` | 548/16 | git 日常：浅克隆、一键提交、镜像加速下载（`Get-SpeedUpUri` 轻量单链版，2026-09-24 补） |
| `RepoSync` | 556/8 | 多仓库同步/开发环境同步：`Push/Update-ReposesConfiged*`、`update_functions`（`Update-ReposesConfiged` 按名单选源：`$CommonRepos` 走 GitHub 加速镜像，其余仓库（含 `$CxxuRepos`）默认走 gitee；支持 `-RepoSource auto/github/gitee`、`-GithubMirror`/`-NoMirror`、`-PrivateRepos` 与 `-Proxy`/`-NoProxy`；已有仓库 origin 指向本账号同名仓库时按名单迁移主机，镜像失败自动直连重试；2026-09-22 从 `Basic` 迁入，B 档 5.1） |
| `MySql` | 905/12 | MySQL 库表备份/建删/查询（`Get-MySqlDatabaseNameCmdletDeprecated` 已删，2026-09-22） |
| `WordPress` | 1685/9 | WP 本地建站 + 总入口 `Deploy-Wp`；线上运维 18 函数已迁 `WpOnline`、内容处理 6 函数已迁 `WpContent`（2026-09-22，命令名不变） |
| `WpOnline` | 2818/21 | WP 线上运维：建站上线/插件/订单/远程更新/文件批量推送/cron 批量部署（2026-09-22 从 `WordPress` 迁入，冷路径按需加载） |
| `WpContent` | 748/6 | WP 内容处理：图片搬运/Shopify 采集/SQL 批量（2026-09-22 从 `WordPress` 迁入，冷路径按需加载） |
| `CSV` | 837/9 | CSV 预览/切分/导出 |
| `Sitemap` | 838/6 | sitemap 抓取/解析/URL 提取 |
| `TextProcess` | 610/7 | 文本切分/行处理 |
| `ArchiveProcess` | 610/8 | tar/zstd/lz4/gz 压缩解压 |
| `Cloudflare` | 509/9 | CF Zone/DNS 管理（B 档 5.1，调用走网络，5.1 下直调已验导入）；域名配置经 `cf_api/cloudflare_dns_tool.py --provision`（旧 `cf_config_api.py` 已退役），zone/DNS 查询经 `--list-zones`/`--list-dns`（外部 `flarectl` 已淘汰） |
| `BTCN` | 722/9 | 批量建站（宝塔）脚本生成（B 档 5.1） |
| `TerminalTools` | 845/15 | WT 链接、scoop 安装、scp、目录树、`Register-PsUxLazyLoad`（手势按需：Ctrl+T/R 首按装 PSFzf、首个 Tab 装 CxxuTab；predictor/zoxide 首屏单发）+ `Install-PsUxGestureStubs`（手势桩安装器，幂等）+ `Reset-PsCommandCache`（删除命令表缓存与 5.1 carapace 上下文缓存，配合新终端刷新候选）+ `Sync-CxxuPredictor`（并排版本同步 net9 predictor 与 5.1 Tab 两套活件，-Uninstall/-Force） |
| `PsDebug` | 463/13 | pwsh 内省/诊断：`Head`/`Tail`/`Get-SourceCode`/`Get-PipelineInput`、权限（`Set-Owner`/`Grant-PermissionToPath`，Deploy 用）、`Confirm-UserContinue`（Deploy/Link/Git 用）、`Write-PsDebugLog`（2026-09-22 从 `Pwsh` 迁入；B 档 5.1，冷路径按需加载） |
| `openApps` | 256/17 | 常用软件别名启动（qq/微信/typora 等；`Start-Typora` 跨平台打开文件/目录；B 档 5.1，冗余后台 `&` 去掉） |
| `Browser` | 24/4 | 浏览器搜索/收藏夹小命令（B 档 5.1） |
| `Calendar` | 144/1 | `Show-Calendar`（唯一用 `Export-ModuleMember` 的模块，已与 manifest 对齐；B 档 5.1） |
| `ColorSettings` | 15/2 | 终端颜色开关（B 档 5.1，`inlineprediction` 配色按 PSReadLine 版本 gating） |
| `Mock` | 74/2 | 随机串/撑大文件（测试用；B 档 5.1，字符集已自包含） |
| `Special` | 49/1 | alist 开机注册 |
| `backup` | 248/14 | 各软件配置备份（与 `Deploy-*` 配对；B 档 5.1） |
| `HelpExamples` | 71/3 | comment-based help 示例 + pwsh 运算符教学 2 函数（2026-09-21 从 `Pwsh` 迁入；原名 `CommentBasedHelpDocumentExamples` 过长，2026-09-20 改短名；B 档 5.1，教学函数依赖 help 文件，沙箱无 help 会炸、真机正常） |
| `Test` | 3/0 | 临时函数草稿区（用户专用，不受命名规范约束；转正后删，见 `Module-Conventions.md §2`） |

## 存疑区（2026-09-20 用户已拍板，见下）

| 模块 | 行数/函数 | 状态 |
|---|---|---|
| `Mock` | 74/2 | 保留：用户有时要模拟造数据（`Get-RandomString`/`New-GrowFile`），名实相符不动 |
| `JumpDirectory` | — | 已删除（61 函数零引用，用户动手） |

已解决：`Test`（whois，名实不符）→ 改名 `Whois`；`CommentBasedHelpDocumentExamples`
→ 改名 `HelpExamples`。函数名一律未动，GUID 未动；后续拆分到 67 模块（见各搬迁记录）。

## 热路径调用链（启动/首渲染）

```text
$profile -> init
  ├─ Set-PSReadLinesCommon / Advanced      (PSReadLine + 按键)
  ├─ Set-ArgumentCompleter                 (EnvVar 模块，补全注册)
  ├─ Register-GitCompletion                (git-completion：注册 completer，首次补全才导入)
  ├─ Set-ArgcCompletions                   (argc-completions：设环境 + Tab 懒加载桩)
  ├─ Register-CarapaceLazyLoad             (carapace：只装首个 Tab 桩；Initialize-Carapace 实际加载，默认关)
  ├─ Initialize-Fnm                        (可选组件：fnm env --use-on-cd，默认关)
  ├─ Import-PsCompletions                  (可选组件：导入 PSCompletions，默认关)
  ├─ Initialize-ScoopSearch                (可选组件：scoop-search --hook，默认关)
  ├─ Confirm-EnvVarOfInfo                  (Startup：OSCaption/FullCode/DisplayVersion 持久化)
  ├─ Set-PsExtension                       (默认 False：init 直接跳过，不导入 PsEnv)
  ├─ Set-PsPrompt                          (Prompt；含 core 环境检查/按需导入)
  ├─ Confirm-DataJson                      (Json：仅 Balance/Brilliant 等 IP 主题执行)
  └─ Register-PsUxLazyLoad                 (TerminalTools：只注册 OnIdle 事件即返回)
首渲染 prompt (PromptFast 默认)
  ├─ Write-BatteryAndMemoryUse → Info(Get-MemoryUseSummary 5s节流 / Get-BatteryLevelCached 30s)
  ├─ Write-HostIp → Info(Get-IpAddressForPrompt：文件 3ms / 会话记忆 4ms / 重算 167ms)
  ├─ Write-OSVersionInfo                   ($env: 缓存，缺失才读注册表)
  └─ write-GitBasicInfo                    (读 .git/HEAD 文件)
```

## 数据流

```text
Data.json (~/.Data.json) ← Update-NetConnectionInfo 守护进程(6s) ← 网络变化
  ↑读                                    ↑写 IpPrompt/ConnectionName/cached*Memory
prompt / Get-MemoryUseRatio(5s节流) / Confirm-DataJson(校验+重建)
~/.conda_hook_cache.ps1 ← profile 点源（conda.exe 更新才重建）
$TEMP/CxxuPwshVar_*.cache.ps1 ← conf 预编译（conf 更新才重建）
```
