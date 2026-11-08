# Agent 决策要点

> 只记录会影响实现选择的硬规则与常见坑，不记录日期、流水账和一次性过程。
> 原理与操作步骤以对应主题文档为准；本文只做短索引。

## 编码与兼容

- `PS/` 以 PowerShell 7 为基线；标 B 档（5.1）的模块必须同时通过 5.1 解析与导入。
  兼容集与加码禁区见 `Feature-Guide.md §13`。
- 5.1 禁区：三元 `? :`、行首管道、`Join-String`、`$PSStyle` 裸赋值、裸 `$IsWindows`、
  `` `e `` 转义。条件赋值写 `if/else`。
- 5.1 没有 `ForEach-Object -Parallel`。需要并发时用 runspace 池（参考
  `PS/TestLinks/TestLinks.psm1` 的 `Test-LinksConcurrently`），不要静默退化为串行。
- 含中文的 `.ps1`/`.psm1` 必须带 UTF-8 BOM。`irm|iex` 在线执行前必须
  `TrimStart([char]0xFEFF)`；落盘用 `-OutFile`，不要用 `>`。
- `PwshVar/confs/*.conf` 会被逐行 `iex`，同样禁三元。读写中文文件用 .NET UTF-8 API，
  不用裸 `Get-Content`/`Set-Content`。
- 重定义内置别名（`rm`/`r`/`ps`/`h` 等）必须
  `Set-Alias <名> <目标> -Option AllScope -Scope Global`。

## 模块与输出

- manifest 是导出真相源。新增或删除函数时同步 `FunctionsToExport`，并跑
  `Test-ModuleManifest`。
- 不要向成功流泄漏中间对象。目录创建、探测结果等用 `| Out-Null`，只返回调用方需要的数据。
- 跨模块访问变量要显式作用域，不依赖动态作用域碰运气。
- 模块目录名必须与模块名一致，否则无法自动发现。

## 部署与网络

- 国内默认 GitHub + 镜像前缀 `https://gh-proxy.com`；可用 `-GithubMirror` 或
  `$env:PsGithubMirror` 覆盖。
- 一键部署默认不安装 PowerShell 7；需要时显式 `-InstallPwsh7`。已有 git/pwsh 时跳过安装，
  不重复覆盖。
- 克隆优先镜像，失败回退直连，再失败回退离线包。下载后校验 zip/PE 签名，不能只看文件非空。
- 补全栈二进制默认优先 `xuchaoxin1375/scripts-deps` 的固定版本（`Get-CxxuDepsMirrorAsset` 里的钉子），
  失败才回上游；发新版先跑 `PS/Deploy/Sync-GithubDepsMirror.ps1`，再把脚本打印的钉子同步回模块。
  版本钉子是有意为之：不在部署时查 release API，避免新机多一次网络往返与限流。
- 交互提示按后果二选一：未装 git 时说明“安装 git 后克隆”与“直接下载压缩包”的差别，不只问 y/n；
  克隆加 `--progress` 并按约 10% 输出一行，避免长时间没有任何输出。
- 本地调试用 `-Sandbox`：在用户下载目录下建独立沙箱目录（下载目录取资源管理器登记的实际路径，
  取不到时回退 `%TEMP%`），不写环境和 profile、不装组件；成功后清理，
  失败或 `-KeepSandbox` 时保留。离线包固定落沙箱 `packages/`。
- 5.1 镜像探测用 runspace 池并发，并设置整体截止时间，避免多个慢站串行累加等待。
- 计划任务或无人值守脚本不弹交互选择；镜像直接用脚本头部默认值或环境变量。

## 文档与提交

- 用户可见行为变更同步 `Feature-Guide.md`、`Deploy-Guide.md` 或对应 `README`。
  入口文档只放指引与可执行示例，不复制正文。
- 部署示例中的本地脚本副本统一用 `$deployScript`，并在首次出现处说明它来自仓库的哪个文件、保存到哪里；
  不使用 `~/dcp.ps1` 这类未解释的简写。部署示例优先给出可逐项修改参数的写法（哈希表），
  不把单行命令作为主路径：用户通常需要更换目录、离线包或镜像。
- 下载镜像先赋值给 `$mirror`，URL 中只引用变量，不把镜像前缀直接拼进字面地址；换源时只改变量赋值。
- 文档不写死仓库清单数量、章节编号和日期；具体值以真相源为准。
- 换行默认忽略 CRLF/LF 差异；仅 `.sh` 用 LF、`.cmd`/`.bat` 用 CRLF。
- 含中文的提交信息先写 UTF-8 文件，由 pwsh 7 执行 `git commit -F`。提交前做隐私扫描。
- 推送/PR 仅在用户明确指示时执行。

## WSL 访问仓库

- 不要在 Windows 与 WSL 同时跑 git；会抢 `index.lock`。
- 不要改仓库本地的 `core.autocrlf`；两侧共享同一份配置。
- 只暂存本次任务涉及的文件，不要用 `--renormalize` 全量处理。
- 报 `dubious ownership` 时，在 WSL 里对仓库路径执行
  `git config --global --add safe.directory <WSL 路径>`。
