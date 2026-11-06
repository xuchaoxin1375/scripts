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
| 日常使用：初始化、命令查询、补全、更新 | [PS/docs/Feature-Guide.md](PS/docs/Feature-Guide.md) |
| 目标机器只有 Windows PowerShell 5.1 | [PS/Deploy/readme.md](PS/Deploy/readme.md)(轻量部署) |
| nginx 与反向代理配置 | [nginx_conf/Readme.md](wp/woocommerce/woo_df/sh/nginx_conf/Readme.md) |
| 故障定位 | powershell内先执行 `doctor`，再按 [PS/docs/README.md](PS/docs/README.md) 分流 |
| 查找功能归属的模块 | [PS/docs/Module-Map.md](PS/docs/Module-Map.md) |
| 开发模块或编写自动化 | [AGENTS.md](AGENTS.md) |
| 部署 shell 环境/交互式shell体验增强(个人电脑、服务器、WSL/Lima) | [sh/README.md](wp/woocommerce/woo_df/sh/README.md) |

## 快速开始

### PowerShell 模块集

前置条件：具备 PowerShell 执行环境(`powershell.exe` 或 `pwsh`)与可用网络。脚本会检查 PowerShell 7 与 git：已安装则直接拉取仓库，未安装则尝试自动安装，失败时按 [Deploy-Guide.md](PS/docs/Deploy-Guide.md) 的镜像说明更换源后重试。

```powershell
iex ((irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1').TrimStart([char]0xFEFF))
```

> 脚本以 UTF-8 BOM 保存(`powershell.exe` 5.1 直接执行含中文脚本时需要),`irm` 会把 BOM 解码成首字符 U+FEFF,
> 直接 `| iex` 会让首行 `<#` 块注释失效并报"参数列表中缺少参量",故先 `TrimStart([char]0xFEFF)`。
> 不方便写这段裁剪时,可先落盘再执行:`irm '<同上地址>' -OutFile ~/dcp.ps1; ~/dcp.ps1`(必须是 `-OutFile`,用 `>` 在 5.1 会写成 UTF-16 双 BOM,脚本反而解析失败)。

重新打开终端(profile 自动执行 `init`)，再安装补全栈：

```powershell
Deploy-CompletionStack
```

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
- 执行策略报错时先执行 `Set-ExecutionPolicy Bypass -Scope CurrentUser -Force`；git 配置损坏时备份或移除 `~/.gitconfig` 后重试。
