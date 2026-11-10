[toc]

日常使用的脚本集合：PowerShell 模块集([PS/](PS/)，pwsh 优先)与 shell 脚本库(bash/zsh，个人电脑与服务器共用)。

不同网络环境可以访问不同的在线地址:

- [github](https://github.com/xuchaoxin1375/scripts) 
-  [gitee](https://gitee.com/xuchaoxin1375/scripts)

## 定位与设计

本仓库是长期自用的脚本集合，目标是把日常环境配置、命令补全、仓库更新与服务器运维收敛成可重复执行的脚本，而不是一次性命令的堆叠。仓库分为两条主线：

- PowerShell 模块集以 Windows 日常使用为主；
- shell(bash/zsh) 脚本库面向 Linux/macOS 与服务器，覆盖 shell 环境、nginx 配置等内容。

### 关于powershell(pwsh)的部分

- **模块化按需加载**：每个 PowerShell 模块有独立的清单文件与显式导出表；模块经 `PSModulePath` 按需自动加载，`init` 只负责环境初始化。
- **提示/补全插件**: dll 采用并排版本加指针的活件机制，更新时写入新版本目录，不锁文件，也不要求关闭终端。
- **文档单一真相源**：[PS/docs/](PS/docs/) 是模块集的唯一真相源；各入口文档只放指引，细节留在对应模块或子目录的文档里。

### 关于bash脚本的部分

- **部署与更新可重复执行**：一键脚本先判断当前状态，未部署则安装、已部署则更新，不在已有环境上重复安装。

### 其他

- **考虑不同网络场景**：默认经 GitHub 加速镜像获取资源，gitee 只保留兼容(实测对远程脚本执行常误报拦截)。

## 内部文档入口

| 场景 | 从这里开始 |
|---|---|
| 新机器部署 PowerShell 环境 | [PS/docs/Deploy-Guide.md](PS/docs/Deploy-Guide.md) |
| 只启用补全（机器已就绪） | [PS/docs/Deploy-Guide.md](PS/docs/Deploy-Guide.md) §5 → [Feature-Guide.md](PS/docs/Feature-Guide.md) §7/§9 |
| Git Bash / Linux / macOS 的 bash 补全（carapace） | [bash/carapace/README.md](bash/carapace/README.md) | 平台差异、登录 shell 与 rc 选择、安装/卸载、验收与未验证项 |
| bash 补全组合部署（argc 补缺口 + carapace 负责 git） | [bash/completion-stack/README.md](bash/completion-stack/README.md) | 一条命令写入两个 rc 块、顺序规则、验收与卸载 |
| zsh 的 git 补全选项描述缺失 | [bash/shell-completion-descriptions.md](bash/shell-completion-descriptions.md) | wrapper 遮住原生 `_git` 的原因、fpath 降级修复、验收与回退 |
| 日常使用：初始化、命令查询、补全、更新 | [PS/docs/Feature-Guide.md](PS/docs/Feature-Guide.md) |
| 目标机器只有 Windows PowerShell 5.1 | [PS/Deploy/readme.md](PS/Deploy/readme.md)(轻量部署) |
| nginx 与反向代理配置 | [nginx_conf/Readme.md](wp/woocommerce/woo_df/sh/nginx_conf/Readme.md) |
| 故障定位 | powershell内先执行 `doctor`，再按 [PS/docs/README.md](PS/docs/README.md) 分流 |
| 查找功能归属的模块 | [PS/docs/Module-Map.md](PS/docs/Module-Map.md) |
| 查看功能依赖与安装状态 | [PS/docs/Feature-Dependencies.md](PS/docs/Feature-Dependencies.md) |
| 开发模块或编写自动化 | [AGENTS.md](AGENTS.md) |
| 部署 shell 环境/交互式shell体验增强(个人电脑、服务器、WSL/Lima) | [sh/README.md](wp/woocommerce/woo_df/sh/README.md) |

## 快速开始

### PowerShell 模块集

前置条件：具备 PowerShell 执行环境(`powershell.exe` 或 `pwsh`)与可用网络；先按下面第 1 步设置执行策略。

- 部署脚本是仓库里的 `PS/Deploy/Deploy-CxxuPsModules.ps1`。先保存到本地，再按参数运行；保存后可反复使用，也便于查看内容。
- 脚本会检查 git：已安装则用镜像克隆仓库；未安装时提示选择安装 Git 或直接下载仓库压缩包；克隆失败自动回退离线包。
- 默认不安装 PowerShell 7，需要时加 `-InstallPwsh7`。
- 下载与仓库更新默认走 `https://gh-proxy.com`，可用 `-GithubMirror` 或 `$env:PsGithubMirror` 覆盖，更新时也可用 `-NoMirror` 直连；镜像与代理细节见 [Deploy-Guide.md](PS/docs/Deploy-Guide.md)。
- 参数较多时建议写进哈希表，完整参数、离线安装与沙箱调试见 [PS/Deploy/readme.md](PS/Deploy/readme.md)。

```powershell
# 1. 前置：允许当前用户运行本地脚本（与 Scoop 安装前置相同）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 2. 保存脚本
$deployScript = "$HOME\Downloads\Deploy-CxxuPsModules.ps1"
$mirror = if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }
irm "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1" -OutFile $deployScript

# 3. 下载文件带 Mark-of-the-Web 时先解锁（irm 保存的通常没有）
Unblock-File $deployScript

# 4. 运行
& $deployScript
# 需要时改用参数，例如：
# & $deployScript -Light          # 只有 5.1、免 git
# & $deployScript -InstallPwsh7   # 顺便安装 PowerShell 7
```

> 第 1 步若报错，通常是 `MachinePolicy`/`UserPolicy` 组策略在管控，`Set-ExecutionPolicy` 改不动，需要管理员处理后再运行。

> 保存必须用 `-OutFile`：它写出原始字节。Windows PowerShell 5.1 用 `>` 会把脚本写成 UTF-16，叠加脚本自带的 BOM 后解析失败。

重新打开终端(profile 自动执行 `init`)，再安装补全栈：

```powershell
Deploy-CompletionStack
```

> 默认只装仓库内核心补全（CxxuCommand + Tab），不下载仓库外依赖；需要 argc、PSFzf、fzf/zoxide 等加对应 `-Include*` 或 `-All`，详见 [PS/docs/Deploy-Guide.md](PS/docs/Deploy-Guide.md)。

> 若提示找不到 `Deploy-CompletionStack`，说明 profile 的 `init` 没有执行；先回到第 2 步检查执行策略，而不是重复运行部署脚本。

轻量部署(仅 5.1、免 git)、临时使用单个模块、用本地代码验证部署，见 [PS/Deploy/readme.md](PS/Deploy/readme.md)；分步部署与多设备差异见 [PS/docs/Deploy-Guide.md](PS/docs/Deploy-Guide.md)。

### shell 脚本库

个人电脑(具备 bash 即可)：

```bash
bash <(curl -sSfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/update_shell_config.sh)
```

Linux 服务器(未部署过则完整克隆，已部署则更新代码)：

```bash
bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh) -U
```

服务器参数、WSL/Lima 共用宿主仓库、更新脚本自救与 zsh 增强，见 [sh/README.md](wp/woocommerce/woo_df/sh/README.md)。

## 仓库结构

- [PS/](PS/)：PowerShell 模块集，含部署脚本与模块文档；入口 [PS/docs/README.md](PS/docs/README.md)(按任务分流的文档地图)。
- [wp/woocommerce/woo_df/sh/](wp/woocommerce/woo_df/sh/)：shell 脚本库，含 shell 环境、nginx 配置与 WordPress 运维脚本；入口 [README.md](wp/woocommerce/woo_df/sh/README.md)。
- [AGENTS.md](AGENTS.md)：agent 工作入口与全仓红线。
- [PwshModuleByCxxu.md](PwshModuleByCxxu.md)：旧结构说明，仅供考古，现状以 [PS/docs/](PS/docs/) 为准。
- 许可：[Apache License 2.0](LICENSE)。

## 兼容与网络

- 推荐 PowerShell 7 及以上；Windows PowerShell 5.1 的可用范围、轻量部署与 UTF-8 读取注意事项，见 [Feature-Guide.md](PS/docs/Feature-Guide.md) 的 5.1 兼容说明，模块级兼容性用 `Get-CxxuModuleCompatibility` 自查。
- 国内网络默认经 `gh-proxy.com` 加速；镜像测速与时效性清单见 [Deploy-Guide.md](PS/docs/Deploy-Guide.md) 的镜像与时效性说明。
- 执行策略报错时，先按 Scoop 同款前置设置：`Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`；仍被下载标记拦截时对文件执行 `Unblock-File`。dll 加载不受执行策略影响，排查见 [Feature-Guide.md](PS/docs/Feature-Guide.md) 的 dll/活件章节。git 配置损坏时备份或移除 `~/.gitconfig` 后重试。
