# macOS 上 pwsh 与 zsh 的配置现状

> 适用：macOS + pwsh 7.6.9 + zsh（oh-my-zsh）的本机环境。本文记录 shell 配置文件的接线方式与变更历史（含停用 mamba/conda），不复制启动优化数据与故障处置步骤：性能测量见 [Startup-Optimization.md](Startup-Optimization.md)，进程层故障见 [macOS-Pwsh-Runtime.md](macOS-Pwsh-Runtime.md)，仓库内可分发配置见 [Deploy-Guide.md](Deploy-Guide.md)。

## 1. pwsh profile 的接线

- `~/.config/powershell/Microsoft.PowerShell_profile.ps1` 与 `Microsoft.VSCode_profile.ps1` 均是指向仓库内 [.ps_profile.ps1](../../wp/woocommerce/woo_df/sh/.ps_profile.ps1) 的符号链接，因此终端与 VS Code 集成终端共用同一份正文，改动仓库文件即同时生效。
- 该正文只做两件事：把 `$HOME/repos/scripts/PS` 追加进 `PSModulePath`（已包含时跳过），随后调用 `init`。提示符、PSReadLine、补全与环境变量全部由 `init` 的步骤表负责。
- `~/.config/powershell/profile.ps1`（CurrentUserAllHosts）不在仓库中，当前只有迁移注释。`$profile` 只指向 CurrentUserCurrentHost 这一级，AllHosts 级内容需直接编辑该文件。

## 2. 启动阶段的既有约定

- `Set-PsPrompt` 只在 `init` 的步骤表执行一次，profile 不再重复调用。
- argc 补全不在 profile 里整包注册。`Set-ArgcCompletions` 只设置 `ARGC_COMPLETIONS_ROOT`、`ARGC_COMPLETIONS_PATH` 并安装 Tab 桩，首次按 Tab 才调用 `Initialize-ArgcCompletions` 完成注册；升级补全仓库后执行 `Initialize-ArgcCompletions -Force` 重新注册。
- 启动期系统信息由 `Confirm-EnvVarOfInfo` 写入：Windows 保留 User 级持久化，非 Windows 只写当前进程。macOS 上取自 `$PSVersionTable.OS`，取值形如 `macOS 27.2.0`。
- 复测启动耗时用 `init -Timing -InformationAction Continue` 看步骤表，进程整体耗时另用外部计时；本机基线与分项见 [Startup-Optimization.md](Startup-Optimization.md)。

## 3. 停用 mamba/conda（2026-11-08）

### 3.1 移除范围

- pwsh：`~/.config/powershell/profile.ps1` 的 mamba 初始化块先改为懒加载（首次调用 `mamba` 才 `Import-Module`），当日整体移除。当前会话不设 `MAMBA_EXE`、`MAMBA_ROOT_PREFIX`，也不存在 `Invoke-Mamba`；`mamba` 仅作为 `/opt/homebrew/bin/mamba` 的独立可执行文件存在。
- zsh：`~/.zshrc` 中由 `conda init` 生成的 `conda initialize` 块已删除，交互启动不再 fork `conda shell.zsh hook`。原文备份在 `~/.zshrc.bak.20261108235507`，原位置保留两行迁移注释。
- 两个文件都不在仓库中，换机后需按本节重新处理。

### 3.2 实测变化

| 场景 | 停用前 | 停用后 |
|---|---|---|
| pwsh 完整 profile | 1524ms | 约 980ms |
| pwsh 裸启动（`-NoProfile`） | 305ms | 305ms |
| zsh 交互启动（`zsh -i -c exit`） | 1485ms | 914ms |
| zsh 无配置启动（`zsh -f`） | — | 4ms |

pwsh 的降幅主要来自同日的启动优化（`Confirm-EnvVarOfInfo`、非 Windows 系统信息、重复 `Set-PsPrompt`、argc 整包注册），mamba 块在移除前已改为懒加载，不再位于启动路径；zsh 的约 570ms 降幅来自删除 conda hook。

### 3.3 保留项与能力变化

- miniforge 安装保留在 `/opt/homebrew/Caskroom/miniforge`（约 1.4G），base 环境完整，Python 版本为 3.13.12。
- 仍可用：`conda`、`mamba` 子命令（例如 `conda run -n base python -V`）；`/opt/homebrew/bin/python3` 为 3.14.5，不受影响。
- 不可用：`conda activate`、`conda deactivate` 以及提示符里的环境前缀。未加载 hook 时执行 `conda activate` 会报 `CondaError: Run 'conda init' before 'conda activate'`。
- 单次会话临时激活可手动加载 hook：

```zsh
eval "$(/opt/homebrew/Caskroom/miniforge/base/bin/conda shell.zsh hook)"
conda activate base
```

### 3.4 恢复方式

- zsh：执行 `/opt/homebrew/Caskroom/miniforge/base/bin/conda init zsh` 重新生成初始化块，重开终端生效。
- pwsh：执行 `mamba shell init -s powershell` 或 `conda init powershell` 重新生成初始化块。若需保留懒加载，需按 3.1 的旧写法改写：先设 `MAMBA_ROOT_PREFIX` 与 `MAMBA_EXE`，再定义同名函数，首次调用时才 `Import-Module`。
- 如需彻底卸载安装：`brew uninstall --cask miniforge`，并按需删除 `~/.local/share/mamba`。该操作不可逆，当前未执行。

## 4. 待办与缺口

- zsh 剩余约 914ms 与 mamba 无关，主要来自 oh-my-zsh 与补全初始化，尚未拆分测量。
- `~/.config/powershell/profile.ps1` 与 `~/.zshrc` 不受仓库跟踪，本机改动只能依赖备份文件与本文命令恢复。

## 5. 相关文档

- [Startup-Optimization.md](Startup-Optimization.md)：启动基线、分项耗时与历轮处置记录。
- [macOS-Pwsh-Runtime.md](macOS-Pwsh-Runtime.md)：pwsh 假死与残留进程空转的判据、清理与防复发。
- [Deploy-Guide.md](Deploy-Guide.md)：新机部署与可分发配置。
- [Feature-Guide.md](Feature-Guide.md)：用户手册与 FAQ（含 conda 提示符段）。
