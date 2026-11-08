# argc-completions 部署与更新

> Init 已内置接管：仓库与工具就位后 `init` 自动装 Tab 懒加载桩，首个 Tab 才注册（约 150–200ms）。
> 补全栈定位与自动提示边界见 [Feature-Guide §10](Feature-Guide.md#10-补全全景速查三层--参数层)；本文只讲部署、更新、开关与排障。

## 1. 前置条件

| 依赖 | 要求 | 检查 |
|---|---|---|
| PowerShell | 5.1 或 7+（Tab 均可用；自动 flag 提示需 7.5+） | `$PSVersionTable.PSVersion` |
| Git for Windows | 提供 `bash`（GNU 工具在 Git Bash 的 `/usr/bin` 里，不必加进 Windows PATH） | `Get-Command bash` |
| argc | `bin\argc.exe`，>= 1.24（当前 1.24.0） | `& .\bin\argc.exe --argc-version` |
| yq | `bin\yq.exe`（部分补全脚本使用，当前 4.54.2） | `& .\bin\yq.exe --version` |

- 必须让 argc 找得到 bash：`argc --argc-shell-path` 返回的路径要真实存在且可执行。
- 常见可用值：`C:\scoop\shims\bash.exe`（scoop 的 Git shim）或 `C:\Program Files\Git\bin\bash.exe`。
- 未装 Git for Windows 时：`scoop install git`，或安装 Git for Windows 并勾选“Git from the command line”；完成后 `bash --version` 应有输出。
- 不需要单独安装 `gawk`/`sed`/`unzip`：补全脚本由 bash 启动，直接使用 Git Bash 自带的 `/usr/bin`。

## 2. 首次部署

> 一键部署提示：`Deploy-CompletionStack -IncludeArgc` 会一并部署 argc（仓库 + `argc.exe`/`yq.exe`）；只想单独部署或指定目录用 `Deploy-ArgcCompletions [-Root <目录>] [-Proxy <地址>]`。以下手动步骤用于离线、自定义镜像或排障。
>
> `Deploy-ArgcCompletions` 按“确认缺失项 → 解析并下载 → 安装 → 当前会话注册”四步输出进度：复用的组件会说明跳过原因，下载会标明目标与来源并在结束后报告大小或版本与耗时，镜像失败自动回退直连。缺少的仓库与二进制会并发下载（`-NoParallel` 改串行）；设置 `HTTPS_PROXY`/`HTTP_PROXY` 或加 `-Proxy` 可走代理，`-NoProxy` 强制直连。任一步失败只告警，结尾汇总失败项并提示重跑；重新执行会补齐缺失项，`-Force` 可强制重新下载。

### 2.1 克隆仓库

```powershell
# 默认装到 ~/argc-completions；也可放 C:\repos\argc-completions
git clone https://github.com/sigoden/argc-completions.git C:\repos\argc-completions
```

`Deploy-ArgcCompletions` 默认用 `~/argc-completions`，已存在则复用；`Set-ArgcCompletions` 的探测顺序：

1. `$env:ARGC_COMPLETIONS_ROOT`
2. `~/argc-completions`
3. `~/repos/argc-completions`
4. `C:\repos\argc-completions`（仅 Windows 探测：非 Windows 没有 C 盘）

仓库判定要求存在 `completions` 目录，且 argc 可执行文件可定位：仓库 `bin` 优先，其次 PATH（macOS/Linux 用系统安装的 argc 即可，例如 Homebrew）。放在别处时，在 `init` 前设置（写进 profile 或系统环境变量）：

```powershell
$env:ARGC_COMPLETIONS_ROOT = 'D:\tools\argc-completions'
```

### 2.2 放入工具

从发布页下载 Windows x64 产物，放进仓库的 `bin\`：

- `argc.exe`：`sigoden/argc` releases（>= 1.24）
- `yq.exe`：`mikefarah/yq` releases（>= 4.x）

```powershell
& C:\repos\argc-completions\bin\argc.exe --argc-version
& C:\repos\argc-completions\bin\argc.exe --argc-shell-path
```

> `bin\argc`（无扩展名的 Linux ELF）在 Windows 的 Git Bash 里执行会报“cannot execute binary file”；PowerShell 会按 PATHEXT 优先 `argc.exe`。只在 Git Bash 里用 argc 时，删掉或改名这个 ELF。

### 2.3 初始化

```powershell
Import-Module Init -Force
init          # 或直接打开一个新终端
```

`Set-ArgcCompletions`（init 第 4 步）只做轻量准备：

1. 定位仓库并设置 `ARGC_COMPLETIONS_ROOT`
2. 设置 `ARGC_COMPLETIONS_PATH`（Windows 用 `;` 分隔；`completions\windows` 在前，Windows 专用脚本覆盖同名脚本）
   - 非 Windows 用 `:` 分隔，平台目录为 `completions/macos`（Linux 为 `completions/linux`），其余同上
3. 把 `bin` 前置进 `PATH`，并安装 Tab 懒加载桩

启动只花约 1ms，不注册 846 个 completer。

### 2.4 首次 Tab

- 第一次按 `Tab` 才注册全部 completer，约 150–200ms；之后零开销。
- 需要立即注册（或更新后重注册）：

```powershell
Initialize-ArgcCompletions -Force
```

### 2.5 验收

交互：

```text
git ch<Tab>         -> checkout / cherry / cherry-pick
docker --con<Tab>   -> --config / --context
nginx -<Tab>        -> -? / -h / -v / -V / -t / -T ...
```

非交互：

```powershell
Import-Module Init -Force
Set-PSReadLinesCommon
Set-ArgcCompletions
Initialize-ArgcCompletions
[System.Management.Automation.CommandCompletion]::CompleteInput('git ch', 6, $null).CompletionMatches.Count      # 3
[System.Management.Automation.CommandCompletion]::CompleteInput('docker --con', 12, $null).CompletionMatches.Count  # 2
```

预测视图（7.5+）：输入 `nginx -`，ListView 应出现 `[CxxuArgcFlags]` 来源行。

## 3. 更新

```powershell
git -C C:\repos\argc-completions pull
Initialize-ArgcCompletions -Force   # 当前会话重新注册 Tab 补全
# 或用 Deploy-ArgcCompletions -Force 重新下载仓库与缺失二进制
```

- 静态 flag 表（`~/.cxxu/cache/argc-flags.tsv`）按补全脚本的 mtime 自动重建；**已加载进内存的表不热更新**，重开终端生效（或删表后重开）。
- 只更新 `bin\argc.exe` / `bin\yq.exe` 时不需要重注册（路径不变），用 `--argc-version` 确认版本即可。
- `argc` 与补全脚本的协议要匹配：当前仓库基线为 argc 1.24；跨大版本升级后先跑上面的验收命令。

## 4. 开关

| 目标 | 做法 |
|---|---|
| 本会话关闭 | `$env:PsArgc = 'False'`；或 `Disable-PsPlugin Argc` |
| 持久关闭 | `Disable-PsPlugin Argc -Persist`（写 `~/.cxxu/config.psd1` 的 `PsArgc`） |
| 重新开启 | `Enable-PsPlugin Argc [-Persist]` |
| 只关自动提示 | `Disable-PsPlugin Predictor`（命令名与 flag 提示一起停） |

关闭后 completer 每次调用直接返回空，`Tab` 回落原生补全；不影响 `Get-ChildItem -` 等 cmdlet 的参数补全。

## 5. PowerShell 5.1

- 自带 PSReadLine 2.0 即可，无需安装新版。
- 5.1 的补全引擎不会把 `-`/`--` 开头的词交给 Native 补全器（6.0 才修）。Tab 桩只对 argc 注册过的应用命令临时插入一个零宽字符绕过；选中候选或 `Esc` 取消后都会清理，cmdlet/函数参数补全不受影响。
- 5.1 没有预测视图（`CxxuArgcFlags` 是 net9 dll，需 7.5+），所以参数提示只有 `Tab`。

## 6. 自动 flag 提示（7.5+）

- 由 `CxxuPredictor.dll` 的第二个 predictor `CxxuArgcFlags` 提供。
- 触发条件：命令在 argc 表里 + **首个参数位** + 当前词以 `-` 开头。
- 数据来源：`completions/*.sh` 顶层的 `@flag/@option`；不解析 `# {{` 子命令块，动态值（分支/容器/文件）仍走 `Tab`。
- 表缓存：`~/.cxxu/cache/argc-flags.tsv`（约 3 万行 / 1.9MB）。补全脚本更新后首个会话自动重建；删表可强制重建。
- 关闭：`Disable-PsPlugin Argc`（`PsArgc` 门）或 `Disable-PsPlugin Predictor`。
- 详细取舍与实测见 [Feature-Guide §10](Feature-Guide.md#参数自动提示的边界为什么不是-argc-全量)。

## 7. 排障

| 现象 | 先查 | 处理 |
|---|---|---|
| `init` 后 `$env:ARGC_COMPLETIONS_ROOT` 为空 | 仓库是否在默认位置（`~/argc-completions`、`~/repos/argc-completions`、Windows 的 `C:\repos\argc-completions`）且 argc 可用 | 设置 `ARGC_COMPLETIONS_ROOT` 后重开终端 |
| `Tab` 完全没反应 | `(Get-PSReadLineKeyHandler -Bound \| Where-Object Key -eq 'Tab').Function` 应为 `CustomAction`；`$global:PsArgcScripts.Count` 应为 846 | 旧会话未重载：`Import-Module Init -Force; init -Force`；5.1 不要用 `p -Force`（它开的是 pwsh 7） |
| 首次 Tab 后仍无候选 | `Initialize-ArgcCompletions -Verbose` 的报错；`argc --argc-compgen powershell '' git ch` 是否输出 `checkout`/`cherry`/`cherry-pick` | 补全脚本缺失或脚本依赖的工具不在 Git Bash 中；按报错补依赖 |
| `argc --argc-compgen` 无输出 | `argc --argc-shell-path`；`$env:ARGC_COMPLETIONS_PATH` | bash 路径无效 / 仓库路径错 / 环境变量被清 |
| Git Bash 报 `cannot execute binary file` | `bin\argc` 是否是 Linux ELF | 删掉或改名，让 Git Bash 用 `argc.exe` |
| 只有个别命令不补全 | `completions\<cmd>.sh` 是否存在 | 没有脚本就是不支持；不要改 completer 注册逻辑 |
| 5.1 下 `-` 开头没候选 | 当前 `Init` 是否为最新；`Set-ArgcCompletions` 是否执行 | 重载模块/重开窗口；确认该步骤不再带 `MinPS = 7` |
| 更新仓库后仍是旧候选 | `Initialize-ArgcCompletions -Force` 是否执行 | flag 表需重开终端；Tab completer 当前会话强制重注册 |
| flag 提示不出现 | pwsh 是否 7.5+；`PsArgc`/`PsPredictor` 是否被关；是否首个参数位 | `GetSubsystemInfo` 查 `CxxuArgcFlags` 是否注册；删缓存重开 |
| 选中行看不清 / 描述带颜色码 | `Selection` 是否为 `ESC[7m` | 保持反显方案；completer 已剥掉 ANSI，不要改回固定前景色 |
| 下载经常失败或很慢 | 镜像是否可用；是否已设置代理 | 换 `$env:PsGithubMirror`；先 `Set-Proxy On` 或加 `-Proxy <地址>`；排除代理故障时加 `-NoProxy` |

## 8. 卸载

```powershell
Disable-PsPlugin Argc -Persist          # 停用（推荐，保留仓库与缓存）
# 彻底清理（可选）：
Remove-Item -Recurse -Force C:\repos\argc-completions
Remove-Item -Force ~\.cxxu\cache\argc-flags.tsv
```

只停用自动提示、保留 Tab 补全：`Disable-PsPlugin Predictor`（或 `Disable-PsPlugin Predictor -Persist`）。
