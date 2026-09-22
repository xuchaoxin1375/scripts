# 模块地图（Module Map）

> 56 个自有模块，全在 `PS/<Name>/<Name>.psm1` + 同名 `.psd1`
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
| `ArgumentCompletion` | 115/2 | 参数补全注册（`prompt` 已迁出，只剩补全） |
| `EnvVar` | 1021/15 | 环境变量 User/Machine/Process 三档；热路径一律 `Set-ProcessEnvVar` |
| `Startup` | 307/12 | 开机任务、后台守护进程、OS 版本缓存（`Confirm-EnvVarOfInfo`） |
| `Json` | 251/5 | `Data.json` 读写校验（init 与 prompt 共用，无递归设计） |
| `Pwsh` | 1162/29 | 通用工具箱：模块安装、profile 管理、`ipmox`/`ipmof` 重载（仅仓库内模块）、`Sync-ModuleManifest` 偷懒同步（-Name Tab 补全）、`Set-PsExtension`（默认关）；教学 2 函数迁 `HelpExamples`、Robocopy 2 函数迁 `FileSystem` |

## prompt 首渲染会顺带加载

| 模块 | 行数/函数 | 职责 |
|---|---|---|
| `Info` | 1736/28 | 系统信息：内存/进程查看、IP（批量+60s 记忆）、电池已迁入 |
| `Basic` | 1969/86 | 通用小工具（网络/git/时间/速记等）+ 模块查询（`Get-ModuleByCxxu`，2026-09-21 从 `Info` 迁入，5.1 可用）；键盘/TTS/电源 16 函数已迁 `WinSys`，prompt 只剩间接依赖 |
| `TaskSchdPwsh` | 1146/14 | `Start-ScriptWhenIntervalEnough`（内存 5s 节流就靠它）、计划任务、报时守护进程 |

## 网络与系统

| 模块 | 行数/函数 | 职责 |
|---|---|---|
| `Web` | 1867/24 | HTTP 服务、nginx 站点、域名、下载（`Tools` 拆出） |
| `Text` | 914/14 | 文本/编码/markdown/格式化（`Tools` 拆出） |
| `NetWork` | 60/3 | 网络发现/共享/SMB 会话 |
| `WIFI` | 77/6 | WiFi 连接/重连/测试 |
| `NetDrivers` | 443/9 | 网络驱动器挂载、alist/chfs/aria2 服务 |
| `Proxy` | 168/5 | 代理开关与系统代理设置 |
| `SSH` | 394/9 | SSH 密钥/服务端/客户端初始化 |
| `TestLinks` | 347/4 | GitHub 镜像站可用性测试（含数据源） |
| `FileSystem` | 1041/10 | 文件/目录度量（`Get-Size` 等）+ Robocopy 封装（2026-09-21 从 `Pwsh` 迁入 2 函数） |
| `WinSys` | 351/16 | Windows 本机设置：键盘输入法/TTS 语音/电源管理（2026-09-21 从 `Basic` 迁入，命令名不变） |
| `PathProcess` | 315/5 | 路径压缩/转换/风格判定 |
| `Link` | 178/5 | 硬链接/软链接/目录链接管理 |
| `RecycleBin` | 224/5 | 回收站查看/移动/清空 |
| `Security` | 113/4 | CredentialGuard/VBS/重启确认（`Disable-CredentialGuard` 唯一正本） |
| `Shortcut` | 622/8 | 快捷方式读写 |
| `Users` | 14/2 | 用户组/profile 列表查询 |
| `Window` | 110/1 | `Show-Message` 消息弹窗 |
| `ControlPanel` | 147/1 | 控制面板小程序启动 |
| `Search` | 565/9 | 文件内容/目录/服务搜索 |
| `Whois` | 678/2 | whois 查询（原名 `Test` 名实不符，2026-09-20 改名；函数名未动） |

## 开发与部署

| 模块 | 行数/函数 | 职责 |
|---|---|---|
| `Deploy` | 3020/46 | 一键部署：scoop/github hosts/python/conda/开机任务等；`Get-SelectedMirror`/`Get-GithubMirrorPrefix`/`Get-RepoRawUrl`、`Test-PsEnvReadiness`（版本表尾 + `-CheckRemote` 远端对比 + 建议行）、`doctor`（统一诊断入口）在此 |
| `Development` | 340/22 | Django 快捷命令、ssh 别名、文本清理 |
| `Git` | 505/15 | git 日常：浅克隆、一键提交、镜像加速下载 |
| `MySql` | 984/13 | MySQL 库表备份/建删/查询 |
| `WordPress` | 3793/33 | WP 站点本地/线上部署、插件/订单管理（最大业务模块，冷路径别碰） |
| `CSV` | 837/9 | CSV 预览/切分/导出 |
| `Sitemap` | 838/6 | sitemap 抓取/解析/URL 提取 |
| `TextProcess` | 610/7 | 文本切分/行处理 |
| `ArchiveProcess` | 610/8 | tar/zstd/lz4/gz 压缩解压 |
| `Cloudflare` | 509/9 | CF Zone/DNS 管理 |
| `BTCN` | 722/9 | 批量建站（宝塔）脚本生成 |
| `TerminalTools` | 504/12 | WT 链接、scoop 安装、scp、目录树、`Register-PsUxLazyLoad`（PSFzf/zoxide/predictor 延迟加载，入口按指针静默装载）+ `Sync-CxxuPredictor`（并排版本同步活件，-Uninstall/-Force） |
| `openApps` | 166/16 | 常用软件别名启动（qq/微信/typora 等） |
| `Browser` | 24/4 | 浏览器搜索/收藏夹小命令 |
| `Calendar` | 144/1 | `Show-Calendar`（唯一用 `Export-ModuleMember` 的模块，已与 manifest 对齐） |
| `ColorSettings` | 15/2 | 终端颜色开关 |
| `Mock` | 74/2 | 随机串/撑大文件（测试用） |
| `Special` | 49/1 | alist 开机注册 |
| `backup` | 248/14 | 各软件配置备份（与 `Deploy-*` 配对） |
| `HelpExamples` | 71/3 | comment-based help 示例 + pwsh 运算符教学 2 函数（2026-09-21 从 `Pwsh` 迁入；原名 `CommentBasedHelpDocumentExamples` 过长，2026-09-20 改短名） |
| `Test` | 3/0 | 临时函数草稿区（用户专用，不受命名规范约束；转正后删，见 `Module-Conventions.md §2`） |

## 存疑区（2026-09-20 用户已拍板，见下）

| 模块 | 行数/函数 | 状态 |
|---|---|---|
| `Mock` | 74/2 | 保留：用户有时要模拟造数据（`Get-RandomString`/`New-GrowFile`），名实相符不动 |
| `JumpDirectory` | — | 已删除（61 函数零引用，用户动手） |

已解决：`Test`（whois，名实不符）→ 改名 `Whois`；`CommentBasedHelpDocumentExamples`
→ 改名 `HelpExamples`。函数名一律未动，GUID 未动，53 模块总数不变。

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
