[toc]

## 说明

- 本目录提供 PowerShell 模块集的部署脚本，一键入口为 `Deploy-CxxuPsModules.ps1`。
- 模块面向 PowerShell 7 编写，一键部署脚本同时支持 Windows PowerShell 5.1 与 PowerShell 7，允许先部署模块再安装 PowerShell 7。
- 默认不安装 PowerShell 7；需要时显式加 `-InstallPwsh7`。
- 默认下载前缀为 `https://gh-proxy.com`，用于 git 克隆、raw 脚本与离线包；可用 `-GithubMirror` 或 `$env:PsGithubMirror` 替换。克隆失败会自动回退离线包。
- 部署完成后需重开终端并执行 `init`；Windows PowerShell 5.1 的可用功能与限制见 [Feature-Guide.md](../docs/Feature-Guide.md) 的 5.1 兼容章节。

## 选择部署方式

下表的 `~/dcp.ps1` 指按「快速部署」保存到用户主目录的脚本副本。

| 目标 | 推荐入口 | 行为 |
|---|---|---|
| 新机器首次部署 | `~/dcp.ps1` | 有 git 时镜像克隆；无 git 时提示安装；克隆失败回退离线包 |
| 只有 Windows PowerShell 5.1，且不装 git | `~/dcp.ps1 -Light` | 无 git 不提示安装，改走离线包；不安装 PowerShell 7 |
| 已下载仓库 zip 或网络不稳定 | `~/dcp.ps1 -Mode Default -PackagePath <zip>` | 优先使用本地 zip，不依赖 git |
| 默认目录已存在，需要重新部署 | `~/dcp.ps1 -Force` | 旧目录重命名为 `<名称>.bak.<时间戳>` 后重新部署 |
| 更新已有部署 | `Update-ReposesConfiged` | 拉取代码并按需同步 dll 活件，见 [Deploy-Guide.md](../docs/Deploy-Guide.md) 的更新章节 |
| 修改部署脚本本身 | `-Dev` | 使用仓库内的本地脚本，不拉远端 |
| 验证部署流程 | `-Sandbox` | 在下载目录下建沙箱目录，不写环境变量与 profile |

## 快速部署（在线）

下面两种写法等价，任选一种。推荐先落盘再执行，便于检查脚本内容、复用参数和重复运行。

### 方式一：先落盘再执行（推荐）

`-OutFile` 保存原始字节，避免 5.1 用 `>` 重定向时写成 UTF-16。脚本下载后按需追加参数：

- 不带参数：标准部署，有 git 时镜像克隆，无 git 时提示安装。
- `-Light`：只有 Windows PowerShell 5.1 且不想安装 git 时使用。
- `-InstallPwsh7`：部署完成后安装 PowerShell 7 便携版。

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1' -OutFile ~/dcp.ps1
# 任选一条执行
~/dcp.ps1
# ~/dcp.ps1 -Light
# ~/dcp.ps1 -InstallPwsh7
```

执行策略为 Restricted/AllSigned 时，脚本会先放行当前进程；若策略仍阻止脚本文件启动，改用 `powershell -ExecutionPolicy Bypass -File ~/dcp.ps1` 启动。

### 方式二：管道执行

适合一次性执行，不落盘。多行写法便于检查镜像变量与地址：

```powershell
$mirror = if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }
$url = "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1"
$scripts = (Invoke-RestMethod $url).TrimStart([char]0xFEFF)
$scripts | Invoke-Expression
```

一行等价写法：

```powershell
iex ((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1').TrimStart([char]0xFEFF))
```

- 脚本以 UTF-8 BOM 保存，Windows PowerShell 5.1 直接执行含中文脚本时依赖它。`irm` 会把 BOM 解码成首字符 U+FEFF，直接 `iex` 可能让首行 `<#` 块注释失效并报“参数列表中缺少参量”，因此先 `TrimStart([char]0xFEFF)`。
- 不想写这段裁剪时，改用上面的落盘方式；落盘必须用 `-OutFile`，用 `>` 在 5.1 会写成 UTF-16 双 BOM。
- 默认镜像 `gh-proxy.com` 不可用时，可直接查 [TestLinks.psm1](../TestLinks/TestLinks.psm1) 头部的镜像列表；部署完成后也可运行 `Get-AvailableGithubMirrors` 测速，再替换链接前缀。gitee 仅保留兼容，`irm|iex` 常被拦截，不再推荐。

## 部署参数

### 一键脚本参数

| 参数 | 默认值 | 作用 |
|---|---|---|
| `-RepoSource` | `github` | 仓库源；`gitee` 仅为兼容保留 |
| `-GithubMirror`（别名 `-Mirror`） | `$env:PsGithubMirror`；未设置时 `https://gh-proxy.com` | 克隆、raw 与离线包共用的加速前缀；传空字符串表示直连 |
| `-Mode` | `Default` | `Default`：本地包 → git 克隆 → 离线包；`FromPackage`：重新下载离线包；`FromRemoteGit`：只走克隆 |
| `-PackagePath` | 空 | 本地 zip 文件路径；与 `-Mode Default` 配合时优先使用，配合 `-Sandbox` 可完全离线 |
| `-Light` | 关 | 无 git 时不提示安装，改走离线包；不安装 PowerShell 7；写 5.1 专属 profile |
| `-InstallPwsh7` | 关 | 部署完成后安装 PowerShell 7 便携版；已有 `pwsh` 时跳过 |
| `-Force` | 关 | 目标目录已存在时，先重命名为 `<名称>.bak.<时间戳>` 再部署 |
| `-Dev` | 关 | 使用仓库内的本地脚本，不拉远端；`-DevRoot` 可指定仓库根 |
| `-Sandbox` | 关 | 沙箱部署：下载目录下独立目录；不写环境变量与 profile，不装 git 与 PowerShell 7 |
| `-KeepSandbox` | 关 | 保留沙箱目录；失败时总是保留 |

### 部署函数参数

通过 `Invoke-Expression`（上面的管道方式）加载后，`Deploy-CxxuPsModules` 函数在当前会话可用；也可在已导入 `Deploy` 模块的会话中直接调用。函数与一键脚本的主要差别是目标目录与本地包默认值：

| 参数 | 默认值 | 作用 |
|---|---|---|
| `-RepoPath` | `$env:SystemDrive\repos\scripts` | 仓库解压或克隆目录 |
| `-NewPsPath` | `$RepoPath\PS` | 写入 `PSModulePath` 的模块根目录 |
| `-PackagePath` | `$home/Downloads/CxxuPsModules/scripts*.zip` | 本地 zip 匹配模式；命中多个时取最新；仅在 `Default` 模式下使用 |

- 其余参数与一键脚本同名同义，见上表。
- 脚本被加载时会按默认参数执行一次部署；需要用其他目录或离线包重试时，再调用函数并显式传参。

### 典型参数组合

- 5.1 最小部署：`~/dcp.ps1 -Light`
- 标准部署（有 git）：`~/dcp.ps1`
- 标准部署并安装 PowerShell 7：`~/dcp.ps1 -InstallPwsh7`
- 重新部署默认目录：`~/dcp.ps1 -Force`
- 完全离线（已下载 zip）：`~/dcp.ps1 -Mode Default -PackagePath /path/to/scripts-main.zip`
- 指定镜像：`~/dcp.ps1 -GithubMirror 'https://gh-proxy.com'`
- 自定义目录（加载脚本后调用函数）：`Deploy-CxxuPsModules -RepoPath /path/to/scripts -Mode Default -PackagePath /path/to/scripts-main.zip`
- 沙箱回归：`C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Sandbox -Mode FromPackage -KeepSandbox`

## 轻量部署（仅 Windows PowerShell 5.1，免 git）

适用条件：目标机只有 Windows PowerShell 5.1，且不安装 git 与 PowerShell 7。

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1' -OutFile ~/dcp.ps1
~/dcp.ps1 -Light
```

- 无 git 时不提示安装，改为下载离线包；包源按镜像、codeload、gitcode 顺序静默重试，不弹窗选源。
- 不安装 PowerShell 7；需要时另加 `-InstallPwsh7`。
- 追加用户级 `PSModulePath`，不覆盖原有取值。
- 写入 Windows PowerShell 5.1 专属 profile；重开 `powershell.exe` 后自动执行 `init`。
- 5.1 的可用范围与编码禁区见 [Feature-Guide.md](../docs/Feature-Guide.md) 的 5.1 兼容章节。

不加 `-Light` 时同样不要求 PowerShell 7：有 git 则镜像克隆，克隆失败回退离线包；只有 `-InstallPwsh7` 才下载 PowerShell 7。

## 开发模式（用本地最新代码，不拉远端）

前置条件：在仓库内运行，且脚本所在目录结构完整。

- 加 `-Dev` 后，一键脚本使用仓库内的本地文件，不下载远端版本；仓库根默认从脚本位置推导，可用 `-DevRoot` 指定。
- 同类一键脚本通用：`Deploy-CxxuPsModules`、`Deploy-GitForWindows`、`Deploy-Pwsh7Portable`、`Register-GithubHostsAutoUpdater`。
- 脚本尾部有真实部署调用；在已有默认目录的机器上会因目录存在而提前返回，需要时加 `-Force` 或改用 `-Sandbox` 验证。

```powershell
C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Dev -Verbose # 可叠 -Light；注意脚本尾部有真实调用
```

## 本地调试（沙箱，不碰真实环境）

不想为每次改动找一台干净 Windows 时，用 `-Sandbox`。沙箱部署到独立目录，不写用户环境变量与 profile，不安装 git 与 PowerShell 7：

- 位置：用户下载目录下的 `CxxuPsModules-Sandbox-<时间戳>-<随机后缀>`；下载目录取资源管理器登记的实际路径，兼容 OneDrive 与自定义重定向，取不到时回退 `%TEMP%`。
- 内容：`PS/` 为部署出的模块集，`packages/` 为下载的 zip；不混入常规包目录 `~/Downloads/CxxuPsModules`。
- 副作用：不生成 `~/dgw.ps1` 与 `~/dp7.ps1`；`-InstallPwsh7` 在沙箱中被忽略。
- 结果：列出 `RepoPath`、`NewPsPath` 与 `DeployManifest`、`InitManifest`、`GitAttributes` 校验；失败时保留目录并给出路径。
- 清理：成功后默认删除整个目录；`-KeepSandbox` 或失败时保留。
- 代码来源：脚本使用当前本地文件，无需先推送；目标仓库仍按 `-Mode` 走镜像克隆或离线包。

```powershell
# 测镜像克隆（真实下载，但不落真实目录）
C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Sandbox -Mode FromRemoteGit -KeepSandbox

# 测离线包路径（镜像下载 codeload zip）
C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Sandbox -Mode FromPackage

# 完全离线：用本机已有的 zip，不联网
C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Sandbox -Mode Default -PackagePath /path/to/scripts-main.zip -KeepSandbox

# 默认自动模式：有本地包用包，否则 git 克隆，克隆失败回退离线包
C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Sandbox
```

- 已有 git 时，一键部署会跳过 `Deploy-GitForWindows` 的下载与安装。
- 已有 `pwsh` 时，`-InstallPwsh7` 不会重装。
- 单独运行 `Deploy-Pwsh7Portable.ps1` 时，检测到 `pwsh` 也会跳过；需要重装或覆盖时加 `-Force`。



## 部署失败时

部署耗时取决于网络：镜像克隆通常几十秒完成，离线包为数十 MB 的下载时间。

### 常见失败与处理

| 现象 | 原因 | 处理 |
|---|---|---|
| 提示 Git 不可用 | 未安装 git | 安装 Git for Windows 后重开终端重试；或改用 `-Light` / 离线包 |
| 目标目录已存在 | 之前部署残留 | 加 `-Force` 重命名旧目录；或加载脚本后调用函数并指定 `-RepoPath` |
| 镜像超时或返回错误页 | 镜像不可用或网络受限 | 换 `-GithubMirror`；或手动下载 zip 后用 `-PackagePath` |
| 执行策略拒绝运行 | 用户级策略为 Restricted/AllSigned | 用 `powershell -ExecutionPolicy Bypass -File ~/dcp.ps1` 启动 |
| 5.1 下部分功能不可用 | 模块要求 PowerShell 7 | 见 [Feature-Guide.md](../docs/Feature-Guide.md) 的 5.1 兼容章节 |

### 提高成功率的方式

- 安装 Git for Windows：最简单，部署命令与参数都不改。安装后关闭所有 PowerShell 终端，重新打开再执行部署命令。
- 使用离线包：不依赖 git。到仓库的 gitee 或 github 页面下载 zip，记下文件路径，执行 `~/dcp.ps1 -Mode Default -PackagePath /path/to/scripts-main.zip`。

> gitee 下载仓库压缩包可能需要登录；github 免登录，但直连不一定通，不通时在下载地址前加镜像前缀，例如 `https://gh-proxy.com/https://github.com/xuchaoxin1375/scripts/archive/refs/heads/main.zip`。

### 备用入口：手动选择下载源

镜像与直连都不稳定时，可交互选择脚本下载源。方案码依次对应镜像、gitee、github 直连：

```powershell
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force
$mirror = if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }
$urls = @(
    "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1"
    'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'
    'https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1'
)
for ($i = 0; $i -lt $urls.Count; $i++) { Write-Host "${i}: $($urls[$i])" }
$code = Read-Host "Enter the Deploy Scheme code [0..$($urls.Count - 1)] (default: 0)"
if ([string]::IsNullOrWhiteSpace($code)) { $code = 0 }
$code = $code -as [int]
if ($null -eq $code -or $code -lt 0 -or $code -ge $urls.Count) { $code = 0 }
$scripts = (Invoke-RestMethod $urls[$code]).TrimStart([char]0xFEFF)
$scripts | Invoke-Expression
```

## 操作演示（分步骤离线安装）

下面的演示假设已下载仓库 zip，并在同一会话内执行：

```powershell
$mirror = 'https://gh-proxy.com'
$url = "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1"
$scripts = (Invoke-RestMethod $url).TrimStart([char]0xFEFF)
$scripts | Invoke-Expression
# 默认部署失败后，用本地 zip 重试（函数已由上面的脚本定义）
Deploy-CxxuPsModules -PackagePath '/path/to/scripts-main.zip' -RepoPath '/path/to/CxxuPS' -Verbose
```

- `-PackagePath` 指向 zip 文件本身，不是所在目录。
- `-RepoPath` 是解压目标；目标已存在时函数会返回并提示，需加 `-Force` 或换目录。
- 成功后输出 `PSModulePath` 与 `CxxuPsModulePath`，用于确认写入结果；重开终端执行 `init` 后生效。

## 查看命令语法与帮助

```powershell
Get-Command Deploy-CxxuPsModules -Syntax
Get-Help Deploy-CxxuPsModules -Full
```

## 部署临时使用 CxxuPsModule Deploy 模块

- `Deploy` 模块集中了大部分 `Deploy-*` 函数，单独的 `Deploy-*.ps1` 中能找到的功能通常也能在模块中找到。
- 模块内容较多，可能被杀毒软件误判；建议使用 PowerShell 7 执行，Windows PowerShell 5.1 仅部分函数可用。

```powershell
iex ((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy.psm1').TrimStart([char]0xFEFF))

```

然后可以执行Deploy中存在的命令,例如Deploy-SmbSharing

```powershell
Deploy-SmbSharing

```

### 部署SmbSharing共享文件夹

部署smbsharing

```powershell
iex ((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy.psm1').TrimStart([char]0xFEFF))
gcm Deploy-SmbSharing -syntax
# help Deploy-SmbSharing #执行这一行查看使用帮助,默认不执行直接部署配置
Deploy-SmbSharing -DisableSmbUserLogonLocally -Verbose -confirm:$false #使用$true会逐步向你询问确认

```

重置smbsharing:清理默认smb专用用户名和共享名称

```powershell
Remove-LocalUser smb
Remove-SmbShare share

```

### 部署ScoopForCnUser

```powershell
iex ((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy.psm1').TrimStart([char]0xFEFF))
gcm Deploy-ScoopForCnUser -syntax
Deploy-ScoopForCNUser -UseGiteeForkAndBucket -InstallBasicSoftwares # -InstallForAdmin
Add-ScoopBuckets -Silent

```

### 查看可用的github_mirror加速镜像站

```powershell
iex ((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy.psm1').TrimStart([char]0xFEFF))
# get functions or commands about mirror operations!
gcm *mirror* 
#check commands usage (syntax)
gcm Get-AvailableGithubMirrors -Syntax #use this is enough in general cases
gcm Get-SelectedMirror -Syntax
#choose a mirror which is available

$github_mirror = Get-SelectedMirror #choose default mirror
Write-Verbose $github_mirror -Verbose #check what mirror is chosen

```



## 部署 PowerShell 7

- 安装 PowerShell 7 的方式较多，下面给出一键安装便携版的脚本；该方式不保证每次成功。
- 安装过程会复用 `%temp%` 下已下载的 zip；若已存在会询问是否重新下载，安装完成后自动清理压缩包。
- 若失败，可重试，或检查输出中的下载地址是否可用；能在浏览器中手动下载说明重试有意义，否则把便携版安装包放到 `%temp%` 后重跑脚本。
- 脚本会把 PowerShell 7 所在目录加入用户级 `Path`，之后可在任意位置用 `pwsh` 启动。

```powershell
iex ((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-Pwsh7Portable.ps1').TrimStart([char]0xFEFF))
```

## 部署 Git for Windows

```powershell
iex ((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-GitForWindows.ps1').TrimStart([char]0xFEFF))
Deploy-GitForWindows -IgnoreCache

```

