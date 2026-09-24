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
| `Init` | 821/17 | 启动编排：`init`/`p` 入口、8 步任务表（`-Timing` 看耗时）、`PsEnvMode` 等级跟踪、`Optimize-PsHistory`、用户配置（`Import/New-CxxuConfig*`）、插件启停（`Enable/Disable-PsPlugin`） |
| `Prompt` | 723/32 | 提示符：`prompt` 入口、`Prompt*` 主题、`Write-*` 片段、`Set-PsPrompt`（`-Persist` 才写注册表）、电池 30s 缓存 |
| `CxxuPredictor` | 262/0导出 | 自研命令名 predictor（模糊+严格通配，二进制：dll 发布件 + src；新增 `CompleteCommand` 公开 Tab 接口；活件并排版本 `~/.cxxu/bin`，loader 按指针装载；OnIdle 加载） |
| `CxxuTab` | 111/1 | 自研 Tab 命令名补全（独立插件：`TabExpansion2` 包装，命令名位合并 dll 模糊结果，参数位透传；门控 `$env:PsTab` 逐调用判定；启停见 `Enable/Disable-PsPlugin`） |
| `PwshVar` | 329/6 | `.conf` 变量文件加载（预编译缓存，`Update-PwshVars -NoCache` 回退） |
| `Aliases` | 68/2 | 别名文件加载（`alias_core`/`functions`/`shortcuts`，逐行 iex 是故意的） |
| `ArgumentCompletion` | 115/2 | 参数补全注册（`prompt` 已迁出，只剩补全；B 档 5.1） |
| `EnvVar` | 1021/15 | 环境变量 User/Machine/Process 三档；热路径一律 `Set-ProcessEnvVar` |
| `Startup` | 307/12 | 开机任务、后台守护进程、OS 版本缓存（`Confirm-EnvVarOfInfo`；B 档 5.1，`$IsWindows` 加 `PSEdition` 兜底） |
| `Json` | 251/5 | `Data.json` 读写校验（init 与 prompt 共用，无递归设计；B 档 5.1） |
| `Pwsh` | 460/8 | 模块加载脚手架：`ipmox`/`ipmof` 重载（仅仓库内模块）、`New-ModuleByCxxu`、`Sync-ModuleManifest` 偷懒同步（-Name Tab 补全）；版本环境 8 函数已迁 `PsEnv`、内省调试 13 函数已迁 `PsDebug`（2026-09-22，命令名不变；B 档 5.1，哈希表键改点号取值） |
| `PsEnv` | 261/8 | PowerShell 版本/环境：`Update-PowerShell` 升级、`Set-PsExtension`（init 调用，默认关）、profile 路径管理（2026-09-22 从 `Pwsh` 迁入，init 链会加载；B 档 5.1） |

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
| `PathProcess` | 315/5 | 路径压缩/转换/风格判定（B 档 5.1，2026-09-22 酌情降档） |
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
| `Deploy` | 1401/24 | 新机收尾：github hosts/镜像前缀、防火墙/SMB/自启任务、环境变量；`Test-PsEnvReadiness`、`doctor` 在此；Scoop 生态 10 函数已迁 `Scoop`、语言工具链 12 函数已迁 `DevEnv`（2026-09-22，命令名不变；B 档 5.1，doctor 三元改子表达式 `if`） |
| `Scoop` | 984/11 | Scoop 包管理：国内镜像部署、批量装机、版本切换、`Repair-ScoopUpdate`（修复 update 被未提交更改中断，2026-09-22 从 `Deploy` 迁入，冷路径按需加载） |
| `DevEnv` | 733/12 | 语言工具链与编辑器开箱：Python/conda/C++/Typora/VSCode/WT/补全栈（2026-09-22 从 `Deploy` 迁入，冷路径按需加载） |
| `Development` | 340/22 | Django 快捷命令、ssh 别名、文本清理 |
| `Git` | 505/15 | git 日常：浅克隆、一键提交、镜像加速下载 |
| `RepoSync` | 265/8 | 多仓库同步/开发环境同步：`Push/Update-ReposesConfiged*`、`update_functions`（2026-09-22 从 `Basic` 迁入，B 档 5.1） |
| `MySql` | 905/12 | MySQL 库表备份/建删/查询（`Get-MySqlDatabaseNameCmdletDeprecated` 已删，2026-09-22） |
| `WordPress` | 1685/9 | WP 本地建站 + 总入口 `Deploy-Wp`；线上运维 18 函数已迁 `WpOnline`、内容处理 6 函数已迁 `WpContent`（2026-09-22，命令名不变） |
| `WpOnline` | 1382/18 | WP 线上运维：建站上线/插件/订单/远程更新（2026-09-22 从 `WordPress` 迁入，冷路径按需加载） |
| `WpContent` | 748/6 | WP 内容处理：图片搬运/Shopify 采集/SQL 批量（2026-09-22 从 `WordPress` 迁入，冷路径按需加载） |
| `CSV` | 837/9 | CSV 预览/切分/导出 |
| `Sitemap` | 838/6 | sitemap 抓取/解析/URL 提取 |
| `TextProcess` | 610/7 | 文本切分/行处理 |
| `ArchiveProcess` | 610/8 | tar/zstd/lz4/gz 压缩解压 |
| `Cloudflare` | 509/9 | CF Zone/DNS 管理（B 档 5.1，调用走网络，5.1 下直调已验导入） |
| `BTCN` | 722/9 | 批量建站（宝塔）脚本生成（B 档 5.1） |
| `TerminalTools` | 504/12 | WT 链接、scoop 安装、scp、目录树、`Register-PsUxLazyLoad`（手势按需：Ctrl+T/R 首按装 PSFzf、首个 Tab 装 CxxuTab；predictor/zoxide 首屏单发）+ `Install-PsUxGestureStubs`（手势桩安装器，幂等）+ `Sync-CxxuPredictor`（并排版本同步活件，-Uninstall/-Force） |
| `PsDebug` | 463/13 | pwsh 内省/诊断：`Head`/`Tail`/`Get-SourceCode`/`Get-PipelineInput`、权限（`Set-Owner`/`Grant-PermissionToPath`，Deploy 用）、`Confirm-UserContinue`（Deploy/Link/Git 用）、`Write-PsDebugLog`（2026-09-22 从 `Pwsh` 迁入；B 档 5.1，冷路径按需加载） |
| `openApps` | 166/16 | 常用软件别名启动（qq/微信/typora 等；B 档 5.1，冗余后台 `&` 去掉） |
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
  ├─ Confirm-EnvVarOfInfo                  (Startup：OSCaption/FullCode/DisplayVersion 持久化)
  ├─ Set-PsExtension                       (默认 False，no-op)
  ├─ Set-PsPrompt                          (Prompt；内含 core 环境导入)
  ├─ Confirm-DataJson                      (Json：~/Data.json 兜底+校验)
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
