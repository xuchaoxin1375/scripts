# 功能依赖清单与检测

> 本页整理 PowerShell 模块集中需要外部组件、外部代码或首跑生成物才能完整使用的功能，并说明检测入口与状态含义。检测命令是 `Get-CxxuDependencyReport`，由 `Deploy` 模块提供，`PSModulePath` 正常时无需手动导入；依赖清单真源是 [FeatureDependencies.ps1](../Deploy/FeatureDependencies.ps1)。

## 用途与边界

- 检测命令只读、默认零网络，不安装软件、不修改配置；安装动作仍由 `Deploy-CompletionStack`、`Deploy-ArgcCompletions`、`Sync-CxxuPredictor`、`Confirm-ModuleInstalled`、`Deploy-MiniforgeConfig` 等既有命令负责。
- 检测范围是 PowerShell 模块集的外部依赖与生成物，包括命令、PS 模块、仓库文件、插件开关和 predictor 活件。
- 不覆盖 shell 脚本与 Python 脚本的依赖：shell 侧用 [install_shell_deps.sh](../../wp/woocommerce/woo_df/sh/install_shell_deps.sh) 的 `--check` 检查，Python 侧按对应目录的 `requirements.txt` 安装。
- 检测只回答“本机是否具备该组件”，不验证远端服务器是否具备对应命令；`ssh`、`scp` 等只检查本机入口。
- 依赖级别不等于部署层：这里的“可选”与 `Deploy-CompletionStack` 的“可选层”不是一回事，分层、来源与能力对照见 [Deploy-Guide.md](Deploy-Guide.md) 的「分层、来源与能力」。

## 快速使用

```powershell
Get-CxxuDependencyReport                 # 全部适用项，表后列出待处理项与安装建议
Get-CxxuDependencyReport -Missing        # 只看待处理项
Get-CxxuDependencyReport -Feature '补全*' -Full
Get-CxxuDependencyReport -Level Recommended -PassThru
Get-CxxuDependencyReport -SummaryOnly    # 按功能汇总
Get-CxxuDependencyReport -Json           # 供其他程序消费
```

- `-Feature` 同时匹配功能名与依赖名，可传多个模式；不含通配符时按包含匹配，含 `*`、`?` 时按通配符匹配。
- `-Missing` 只保留缺失、未部署、未生成和版本过低的项；主动关闭与平台不适用不计入。
- `-Full` 在待处理项中附带影响说明，默认只列安装建议。
- `-IncludeSkipped` 在表格模式下显示当前平台不适用的依赖；默认隐藏，只在汇总中计数。`-Json` 始终包含筛选后的全部项。
- `-PassThru` 返回对象，`-Json` 返回带 `summary` 与 `items` 的 JSON，便于脚本判断或接入看板。
- 表格受终端宽度限制会省略右侧列，因此安装建议统一放在表后的「待处理项」列表中，保证完整可见。

`-Json` 的字段名固定，便于脚本读取：

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-11-08T12:00:00.0000000+08:00",
  "platform": "Windows",
  "summary": {
    "total": 42,
    "installed": 34,
    "missing": 5,
    "missingRequired": 0,
    "missingRecommended": 0,
    "missingOptional": 5,
    "missingGenerated": 0,
    "disabled": 1,
    "notApplicable": 2
  },
  "items": [
    {
      "feature": "补全：模糊搜索",
      "component": "PSFzf 模块",
      "level": "推荐",
      "status": "已安装",
      "version": "2.7.10",
      "location": "C:\\Users\\...\\PSFzf\\2.7.10",
      "impact": "Ctrl+T 选文件、Ctrl+R 搜历史不可用；Tab 补全不受影响。",
      "detail": "...",
      "install": "Confirm-ModuleInstalled -ModuleName PSFzf -Install",
      "docs": "Feature-Guide.md §7",
      "platform": "All",
      "gate": "PsFzf",
      "isReady": true
    }
  ]
}
```

## 状态与级别

| 状态 | 含义 | 是否计入待处理 |
|---|---|---|
| `已安装` | 命令、模块或文件已找到，版本满足清单要求 | 否 |
| `已关闭` | 插件开关为 `False`/`0`/`No`/`Off`，依赖未检测；需要时用对应 `Enable-PsPlugin` 开启 | 否 |
| `缺失` | 未找到命令、模块或文件 | 是 |
| `未部署` | argc 仓库、argc 可执行文件或仓库内附属工具未就位 | 是 |
| `未生成` | predictor 活件尚未由 `Sync-CxxuPredictor` 生成 | 是 |
| `版本过低` | 已安装，但版本低于清单要求 | 是 |
| `不适用` | 当前平台不需要该依赖；加 `-IncludeSkipped` 可显示 | 否 |

| 级别 | 含义 |
|---|---|
| `必需` | 模块自动加载或新终端初始化的前提 |
| `推荐` | 默认体验的重要组成；缺失时功能降级，但核心模块仍可用 |
| `可选` | 按需启用的增强或运维能力 |
| `生成物` | 由仓库内命令生成并放到用户目录的活件，不是通过包管理器安装的软件 |

## 依赖总览

完整条目、检测方式和平台差异以 [FeatureDependencies.ps1](../Deploy/FeatureDependencies.ps1) 为准；下表用于快速判断缺什么、影响什么。

| 功能 | 外部依赖或生成物 | 级别 | 缺失影响 | 安装或生成入口 |
|---|---|---|---|---|
| 核心运行环境 | `PSModulePath` 含模块集、profile 含 `init`、pwsh 7.5+、git、PSReadLine 2.1+ | 必需/推荐 | 模块不自动加载、新终端不初始化、命令名预测不可用、更新与克隆不可用、历史增强不可用 | `Add-EnvVar`、`Add-CxxuPsModuleToProfile`、`Update-PowerShell`、`Confirm-GitCommand`、`Install-Module PSReadLine` |
| 补全：命令名预测 | `CxxuPredictor` 活件；本地重编另需 `dotnet` SDK | 生成物/可选 | 命令名内联预测不工作；Tab 补全仍可用 | `Sync-CxxuPredictor`；本地重编另装 .NET SDK 9+ |
| 补全：Tab 增强 | `CxxuTab` 的 Windows PowerShell 5.1 活件 | 生成物 | 5.1 的 Tab 模糊补全不可用；pwsh 7 使用根活件 | `Sync-CxxuPredictor` |
| 补全：模糊搜索 | `PSFzf` 模块、`fzf` 二进制 | 推荐 | `Ctrl+T` 选文件、`Ctrl+R` 搜历史不可用 | `Deploy-CompletionStack -IncludeFuzzy`；或 `Confirm-ModuleInstalled -ModuleName PSFzf -Install`、`scoop install fzf` 或 `brew install fzf` |
| 补全：参数/路径预测 | `CompletionPredictor` 模块 | 推荐 | 参数值与路径的内联预测不可用 | `Confirm-ModuleInstalled -ModuleName CompletionPredictor -Install` |
| 补全：参数补全（argc） | `argc-completions` 仓库、`argc`、`yq`、Windows 下的 `bash` | 推荐 | 应用命令的参数补全不可用 | `Deploy-CompletionStack -IncludeArgc` 或 `Deploy-ArgcCompletions` |
| 补全：git/gitk（git-completion） | `git-completion` 模块 | 推荐 | `git`/`gitk` 回落 argc 或原生补全 | `Install-Module git-completion -Scope CurrentUser -Force`；profile 中的注册块自动生效 |
| 补全：目录跳转 | `zoxide` 二进制 | 可选 | `z` 目录跳转不可用 | `Deploy-CompletionStack -IncludeFuzzy`；或 `scoop install zoxide` 或 `brew install zoxide` |
| 补全：参数补全（PSCompletions） | `PSCompletions` 模块 | 可选 | 约 200 个命令的参数补全不可用 | `Confirm-ModuleInstalled -ModuleName PSCompletions -Install`，再解开 profile 钩子 |
| 交互：文件图标 | `Terminal-Icons` 模块 | 可选 | `Get-ChildItem` 的文件图标不显示 | `Confirm-ModuleInstalled -ModuleName Terminal-Icons -Install` |
| 提示符：conda | `conda` | 可选 | 提示符 conda 段不显示；`Deploy-MiniforgeConfig` 也需要 | `Deploy-MiniforgeConfig` 或 `scoop install miniforge` / `brew install miniforge` |
| 提示符：node | `fnm` | 可选 | node 版本切换与 profile 钩子不可用 | `scoop install fnm` 或 `brew install fnm`，再解开 profile 钩子 |
| 提示符：posh-git | `posh-git` 模块或仓库 | 可选 | `Set-PoshPrompt -Poshgit` 的 git 状态段不可用 | `Install-Module posh-git -Scope CurrentUser -Force` 或 clone 到 `~/repos/posh-git` |
| 提示符：oh-my-posh | `oh-my-posh` | 可选 | `Set-PoshPrompt` 主题不可用；默认 prompt 不受影响 | `scoop install oh-my-posh`、`brew install oh-my-posh` 或官网脚本，并设置 `POSH_THEMES_PATH` |
| 工具链：包管理器 | `scoop`、`scoop-search`、`brew` | 可选 | 不能一键安装 fzf、zoxide、fnm 等二进制；scoop 搜索增强不可用 | 按官网安装，或 `Deploy-ScoopByGithubMirrors`；`scoop install scoop-search` |
| 运维：压缩归档 | `7z`、`zstd`、`lz4`、`gzip` | 可选 | 对应格式的压缩或解压不可用 | `scoop`、`brew` 或系统包管理器 |
| 运维：SSH 远程 | `ssh`、`scp`、`sshpass`、`ssh-keygen`、`sshd` | 可选 | 远程执行、文件上传、密码自动登录、密钥生成或服务端初始化不可用 | OpenSSH 客户端、系统包管理器或 `scoop install openssh` |
| 运维：MySQL | `mysql`、`mysqldump` | 可选 | 建库、查询、导入与备份不可用 | 安装 MySQL 客户端或使用 phpstudy 自带的 `mysql.exe`、`mysqldump.exe` |
| 运维：Nginx | `nginx` | 可选 | 本地站点启动、重载与配置检查不可用 | 安装 phpstudy 或 nginx，并把可执行文件目录加入 `PATH` |
| 运维：Cloudflare 与脚本 | `python`、`curl`、`ThreadJob` 模块 | 可选 | Cloudflare/BTCN 脚本、curl 下载或 5.1 并行部署不可用 | `python` 与 `curl` 按平台安装；`Install-Module ThreadJob` |
| 运维：网络驱动器 | `alist`、`chfs`、`aria2c` | 可选 | 服务启动或下载加速不可用 | 下载 alist/chfs 并加入 `PATH`；`scoop install aria2` |
| 通知：Toast | `BurntToast` 模块 | 可选 | Toast 通知与整点报时不可用 | `Install-Module BurntToast -Scope CurrentUser -Force` |

## 与其他检查命令的分工

| 命令 | 关注点 | 网络行为 | 典型输出 |
|---|---|---|---|
| `Get-CxxuDependencyReport` | 按功能列出外部依赖、生成物、状态与安装建议 | 默认零网络 | 表格、待处理列表、JSON |
| `Test-PsEnvReadiness` | 新机安装态：必备、可选、首跑生成物 | 默认零网络；`-CheckRemote` 才查远端 | 安装态表与建议 |
| `doctor` | 运行态：init 错误、PSReadLine、历史大小、predictor 加载、argc 注册、门控、守护进程、仓库状态 | 默认零网络 | 健康检查表 |
| `install_shell_deps.sh --check` | shell 侧的 `zsh`、`git`、`curl`、`tar` 等系统依赖 | 只检查，不安装 | 缺失列表与非零退出码 |

定位顺序建议：先跑 `Get-CxxuDependencyReport -Missing` 看缺什么，再按安装建议补齐；补完仍不生效时跑 `doctor` 看运行态，最后按 [Feature-Guide.md](Feature-Guide.md) 的补全与 dll 章节排查。

## 维护依赖清单

新增或调整依赖时，修改 [FeatureDependencies.ps1](../Deploy/FeatureDependencies.ps1)，不需要改检测命令本身：

- `Feature`、`Component`：报告中的功能分组与依赖名称；`-Feature` 同时匹配两者。
- `Level`：`必需`、`推荐`、`可选`、`生成物`。
- `Kind`：检测方式，当前支持 `PowerShellVersion`、`Command`、`Module`、`File`、`PathContains`、`ProfileInit`、`LiveArtifact`、`ArgcRepo`、`ArgcExe`、`ArgcBin`、`PathOrModule`。
- `Platform`：`All`、`Windows`、`Mac`、`Unix`；不匹配当前平台时报告为 `不适用`。
- `Gate`：插件开关环境变量；取值 `False`/`0`/`No`/`Off` 时报告为 `已关闭`。
- `MissingStatus`：缺失时的状态文字，可写 `未部署`、`未生成`、`版本过低` 等；省略时用 `缺失`。
- `AllowAnyCommand`：命令可能是函数（例如 `conda`）时设为 `$true`，允许回退到任意命令类型。
- `Install`：安装建议；可写字符串，也可按 `Windows`/`Mac`/`Linux` 写哈希表。
- `Docs`、`Impact`、`Note`：文档位置、缺失影响和补充说明。

新增 `Kind` 时，除补数据外还要在 `Get-CxxuDependencyReport` 的检测分支中实现对应逻辑，并同步本页表格。该文件与 `Deploy.psm1` 同属 Windows PowerShell 5.1 兼容范围，含中文时必须保留 UTF-8 BOM。

## 平台与已知边界

- Windows 专属依赖（`scoop`、`sshd`、`alist`、`chfs`、`BurntToast`、5.1 Tab 活件）在 macOS/Linux 上自动标记为 `不适用`，不计入待处理。
- macOS 专属依赖（`brew`）在 Windows/Linux 上标记为 `不适用`；Linux 使用系统包管理器安装同类软件。
- `pwsh 7.5+` 与 `PSReadLine 2.1+` 只比较版本；其余命令依赖只判断是否存在，不执行 `--version`，避免报告过程启动大量子进程。
- 模块依赖只检查已加载或可发现的模块，不验证能否在当前 PowerShell 版本加载；实际加载状态由 `doctor` 与 `init` 错误账本给出。
- `argc` 的检查覆盖仓库、平台补全目录、可执行文件和 Windows 下的 `bash`；更细的注册状态与 `argc --argc-shell-path` 结果由 `doctor` 的 `argc 补全` 行给出。
- 运维模块的远端依赖不在本表：例如 `WpOnline` 还需要目标服务器具备 `unzip`、`screen`、`mysql` 等命令，详见对应模块帮助与 [Module-Map.md](Module-Map.md)。
- WordPress 本地建站还依赖 phpstudy 的 `php-cgi`、`xp.cn_cgi` 与硬编码目录，未纳入通用清单；按 `Module-Map.md` 与 WordPress 模块帮助核对。
- shell 与 Python 依赖保持各自入口，不并入本命令，避免在 PowerShell 报告里混入系统包管理器与虚拟环境状态。
