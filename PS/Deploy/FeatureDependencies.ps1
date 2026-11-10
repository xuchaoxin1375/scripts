# 功能依赖清单（数据文件）
# 由 Deploy.psm1 的 Get-CxxuDependencyReport 读取；本文件只放数据，不定义函数。
# 字段说明：
#   Feature      功能分组，报告按此列分组与筛选。
#   Component    依赖名称，显示在报告“依赖”列。
#   Level        级别：必需、推荐、可选、生成物。
#   Kind         检测方式：PowerShellVersion、Command、Module、File、PathContains、ProfileInit、
#                LiveArtifact、ArgcRepo、ArgcExe、ArgcBin、PathOrModule。
#   Platform     All、Windows、Mac、Unix；不匹配当前平台时报告为“不适用”。
#   Gate         插件开关环境变量；取值 False/0/No/Off 时报告为“已关闭”。
#   MissingStatus 缺失时的状态文字；省略时用“缺失”。
#   Install      安装建议；可写字符串，或按平台写 Windows/Mac/Linux 的哈希表。
#   Docs         对应文档位置，便于人工核对。
# 新增依赖时先选 Kind，再补对应字段，并在报告的检测逻辑中确认该 Kind 已实现。

$psRoot = Split-Path $PSScriptRoot -Parent
$homeDir = $HOME

@(
    # 核心运行环境
    [PSCustomObject]@{
        Feature   = '核心运行环境'
        Component = 'PSModulePath 含模块集'
        Level     = '必需'
        Kind      = 'PathContains'
        EnvVar    = 'PSModulePath'
        Path      = $psRoot
        Impact    = '模块无法按需自动加载，新终端找不到本仓库命令。'
        Install   = @{
            Windows = "Add-EnvVar -EnvVar PSModulePath -NewValue '$psRoot'"
            Mac     = "在 `$PROFILE 中追加 `$env:PSModulePath = '${psRoot}:' + `$env:PSModulePath"
            Linux   = "在 `$PROFILE 中追加 `$env:PSModulePath = '${psRoot}:' + `$env:PSModulePath"
        }
        Docs      = 'Deploy-Guide.md §3'
    }
    [PSCustomObject]@{
        Feature   = '核心运行环境'
        Component = '$profile 有 init'
        Level     = '必需'
        Kind      = 'ProfileInit'
        Impact    = '新终端不会自动执行 init，变量、别名、补全与提示符不会初始化。'
        Install   = 'Add-CxxuPsModuleToProfile，或在 $PROFILE 中加一行 init'
        Docs      = 'Deploy-Guide.md §4'
    }
    [PSCustomObject]@{
        Feature       = '核心运行环境'
        Component     = 'pwsh 7.5+'
        Level         = '推荐'
        Kind          = 'PowerShellVersion'
        MinVersion    = '7.5'
        MissingStatus = '版本过低'
        Impact        = 'CxxuPredictor 命令名内联预测不可用；Windows PowerShell 5.1 仍可使用 Tab 补全。'
        Install       = @{
            Windows = 'Update-PowerShell，或重装 pwsh 7.5+'
            Mac     = 'brew upgrade --cask powershell'
            Linux   = '按微软文档升级 pwsh 7.5+'
        }
        Docs          = 'Feature-Guide.md §9'
    }
    [PSCustomObject]@{
        Feature   = '核心运行环境'
        Component = 'git'
        Level     = '推荐'
        Kind      = 'Command'
        Name      = 'git'
        Impact    = '仓库更新、克隆与 Scoop 相关流程不可用；已有离线包时仍可部署。'
        Install   = @{
            Windows = 'Confirm-GitCommand，或 scoop install git'
            Mac     = 'brew install git'
            Linux   = '系统包管理器安装 git'
        }
        Docs      = 'Deploy-Guide.md §2'
    }
    [PSCustomObject]@{
        Feature       = '核心运行环境'
        Component     = 'PSReadLine 2.1+'
        Level         = '推荐'
        Kind          = 'Module'
        Name          = 'PSReadLine'
        MinVersion    = '2.1'
        MissingStatus = '版本过低'
        Impact        = '历史去重、inlineprediction 配色等增强不可用；Windows PowerShell 5.1 自带 2.0.0。'
        Install       = '随 pwsh 分发；需要时 Install-Module PSReadLine -Scope CurrentUser -Force'
        Docs          = 'Feature-Guide.md §13'
    }

    # 补全：命令名预测
    [PSCustomObject]@{
        Feature       = '补全：命令名预测'
        Component     = 'CxxuPredictor 活件'
        Level         = '生成物'
        Kind          = 'LiveArtifact'
        Root          = (Join-Path (Join-Path $homeDir '.cxxu') 'bin')
        FileName      = 'CxxuPredictor.dll'
        Gate          = 'PsPredictor'
        MissingStatus = '未生成'
        Impact        = '命令名内联预测不工作；Tab 补全与其余模块不受影响。'
        Install       = 'Sync-CxxuPredictor'
        Docs          = 'Feature-Guide.md §9'
    }

    [PSCustomObject]@{
        Feature   = '补全：命令名预测'
        Component = 'dotnet SDK'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'dotnet'
        Impact    = '本地重编 CxxuPredictor 活件不可用；使用仓库预编译 dll 时不需要。'
        Install   = @{
            Windows = '安装 .NET SDK 9+'
            Mac     = 'brew install dotnet-sdk'
            Linux   = '系统包管理器或微软文档安装 .NET SDK 9+'
        }
        Docs      = 'Live-Versions.md §10'
        Note      = '仅在 pwsh 与仓库 dll 的 SMA 对不上、需要本地重编时使用。'
    }

    # 补全：Tab 增强
    [PSCustomObject]@{
        Feature       = '补全：Tab 增强'
        Component     = 'CxxuTab 5.1 活件'
        Level         = '生成物'
        Kind          = 'LiveArtifact'
        Root          = (Join-Path (Join-Path $homeDir '.cxxu') 'bin')
        SubDir        = 'ps51'
        FileName      = 'CxxuPredictor.dll'
        Platform      = 'Windows'
        Gate          = 'PsTab'
        MissingStatus = '未生成'
        Impact        = 'Windows PowerShell 5.1 的 Tab 模糊补全不可用；pwsh 7 使用根活件。'
        Install       = 'Sync-CxxuPredictor'
        Docs          = 'Feature-Guide.md §13'
    }

    # 补全：模糊搜索
    [PSCustomObject]@{
        Feature   = '补全：模糊搜索'
        Component = 'PSFzf 模块'
        Level     = '推荐'
        Kind      = 'Module'
        Name      = 'PSFzf'
        Gate      = 'PsFzf'
        Impact    = 'Ctrl+T 选文件、Ctrl+R 搜历史不可用；Tab 补全不受影响。'
        Install   = 'Deploy-CompletionStack -IncludeFuzzy，或 Confirm-ModuleInstalled -ModuleName PSFzf -Install'
        Docs      = 'Feature-Guide.md §7'
    }
    [PSCustomObject]@{
        Feature   = '补全：模糊搜索'
        Component = 'fzf 二进制'
        Level     = '推荐'
        Kind      = 'Command'
        Name      = 'fzf'
        Gate      = 'PsFzf'
        Impact    = 'PSFzf 缺少底层 fzf 可执行文件，Ctrl+T/Ctrl+R 仍不可用。'
        Install   = @{
            Windows = 'Deploy-CompletionStack -IncludeFuzzy（scoop→winget→GitHub release），或 scoop install fzf'
            Mac     = 'Deploy-CompletionStack -IncludeFuzzy（brew），或 brew install fzf'
            Linux   = '系统包管理器安装 fzf'
        }
        Docs      = 'Feature-Guide.md §7'
    }

    # 补全：参数/路径预测
    [PSCustomObject]@{
        Feature   = '补全：参数/路径预测'
        Component = 'CompletionPredictor 模块'
        Level     = '推荐'
        Kind      = 'Module'
        Name      = 'CompletionPredictor'
        Impact    = '参数值与路径的内联预测不可用；命令名预测由 CxxuPredictor 提供。'
        Install   = 'Confirm-ModuleInstalled -ModuleName CompletionPredictor -Install'
        Docs      = 'Feature-Guide.md §7'
        Note      = '仅 pwsh 7 使用。'
    }

    # 补全：参数补全（argc）
    [PSCustomObject]@{
        Feature       = '补全：参数补全（argc）'
        Component     = 'argc-completions 仓库'
        Level         = '推荐'
        Kind          = 'ArgcRepo'
        Gate          = 'PsArgc'
        MissingStatus = '未部署'
        Impact        = '应用命令的参数补全不可用；CxxuCommand 与原生 Tab 不受影响。'
        Install       = 'Deploy-CompletionStack -IncludeArgc，或 Deploy-ArgcCompletions'
        Docs          = 'Argc-Completions-Deploy.md'
    }
    [PSCustomObject]@{
        Feature       = '补全：参数补全（argc）'
        Component     = 'argc 可执行文件'
        Level         = '推荐'
        Kind          = 'ArgcExe'
        Gate          = 'PsArgc'
        MissingStatus = '未部署'
        Impact        = 'argc 无法执行补全脚本，应用命令的参数补全不可用。'
        Install       = 'Deploy-ArgcCompletions（仓库 bin），或用包管理器安装 argc'
        Docs          = 'Argc-Completions-Deploy.md'
    }
    [PSCustomObject]@{
        Feature       = '补全：参数补全（argc）'
        Component     = 'yq（Windows 仓库 bin）'
        Level         = '推荐'
        Kind          = 'ArgcBin'
        Name          = 'yq.exe'
        Platform      = 'Windows'
        Gate          = 'PsArgc'
        MissingStatus = '未部署'
        Impact        = '部分 argc 补全脚本依赖 yq，缺少时对应命令没有参数候选。'
        Install       = 'Deploy-ArgcCompletions 会补齐仓库 bin/yq.exe'
        Docs          = 'Argc-Completions-Deploy.md'
    }
    [PSCustomObject]@{
        Feature   = '补全：参数补全（argc）'
        Component = 'yq（PATH）'
        Level     = '推荐'
        Kind      = 'Command'
        Name      = 'yq'
        Platform  = 'Unix'
        Gate      = 'PsArgc'
        Impact    = '部分 argc 补全脚本依赖 yq，缺少时对应命令没有参数候选。'
        Install   = @{
            Mac   = 'brew install yq'
            Linux = '系统包管理器安装 yq'
        }
        Docs      = 'Argc-Completions-Deploy.md'
    }
    [PSCustomObject]@{
        Feature   = '补全：参数补全（argc）'
        Component = 'bash（argc 运行环境）'
        Level     = '推荐'
        Kind      = 'Command'
        Name      = 'bash'
        Platform  = 'Windows'
        Gate      = 'PsArgc'
        Impact    = 'argc 无法启动补全脚本，Windows 下应用命令的参数补全失败。'
        Install   = '安装 Git for Windows，或 scoop install git'
        Docs      = 'Argc-Completions-Deploy.md §7'
    }

    # 补全：目录跳转
    [PSCustomObject]@{
        Feature   = '补全：目录跳转'
        Component = 'zoxide 二进制'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'zoxide'
        Gate      = 'PsZoxide'
        Impact    = 'z 目录跳转不可用；不影响补全与提示符。'
        Install   = @{
            Windows = 'Deploy-CompletionStack -IncludeFuzzy（scoop→winget→GitHub release），或 scoop install zoxide'
            Mac     = 'Deploy-CompletionStack -IncludeFuzzy（brew），或 brew install zoxide'
            Linux   = '系统包管理器安装 zoxide'
        }
        Docs      = 'Feature-Guide.md §7'
    }

    # 补全：参数补全（PSCompletions）
    [PSCustomObject]@{
        Feature   = '补全：参数补全（PSCompletions）'
        Component = 'PSCompletions 模块'
        Level     = '可选'
        Kind      = 'Module'
        Name      = 'PSCompletions'
        Gate      = 'PsCompletions'
        Impact    = '约 200 个命令的参数补全不可用。'
        Install   = 'Confirm-ModuleInstalled -ModuleName PSCompletions -Install（或 Deploy-CompletionStack -IncludePSCompletions），再 Enable-CxxuComponent PSCompletions -Persist'
        Docs      = 'Feature-Guide.md §11'
        Note      = '组件默认关闭；启用后由 init 导入模块。'
    }

    # 补全：git/gitk（git-completion）
    [PSCustomObject]@{
        Feature   = '补全：git/gitk'
        Component = 'git-completion 模块'
        Level     = '推荐'
        Kind      = 'Module'
        Name      = 'git-completion'
        Impact    = 'git/gitk 回落 argc 或原生补全，分支、按状态过滤的文件与选项描述缺失。'
        Install   = 'Install-Module git-completion -Scope CurrentUser -Force（或 Deploy-CompletionStack -IncludeGitCompletion）；init 检测到后自动挂载'
        Docs      = 'Feature-Guide.md §7'
        Note      = '启用后 argc 让出 git/gitk；首次补全才导入模块；开关 PsGitCompletion，来源切换用 Set-GitCompletionSource。'
    }

    # 补全：外部 CLI 参数补全（carapace）
    [PSCustomObject]@{
        Feature   = '补全：外部 CLI 参数（carapace）'
        Component = 'carapace 二进制'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'carapace'
        Platform  = 'Windows'
        Gate      = 'PsCarapace'
        Impact    = 'scoop、winget、gh、docker 等外部 CLI 的参数值补全不可用。'
        Install   = 'Deploy-Carapace -Enable（安装并启用），或 Deploy-Carapace 后 Enable-CxxuComponent Carapace -Persist -Now；bash 侧用 Deploy-Carapace -Bash/-BashLogin'
        Docs      = 'Feature-Guide.md §7'
        Note      = '默认关闭；启用时 init 加载约 0.1–0.2 秒；git/gitk 归属用 Set-GitCompletionSource 切换。'
    }

    # 交互：文件图标
    [PSCustomObject]@{
        Feature   = '交互：文件图标'
        Component = 'Terminal-Icons 模块'
        Level     = '可选'
        Kind      = 'Module'
        Name      = 'Terminal-Icons'
        Impact    = 'Get-ChildItem 的文件图标不显示。'
        Install   = 'Confirm-ModuleInstalled -ModuleName Terminal-Icons -Install'
        Docs      = 'Feature-Guide.md §11'
        Note      = '不随 init 自动加载。'
    }

    # 提示符：conda
    [PSCustomObject]@{
        Feature   = '提示符：conda'
        Component = 'conda'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'conda'
        AllowAnyCommand = $true
        Impact    = '提示符中的 conda 段不显示；Deploy-MiniforgeConfig 也需要 conda。'
        Install   = @{
            Windows = 'Deploy-MiniforgeConfig，或 scoop install miniforge'
            Mac     = 'brew install miniforge，再运行 Deploy-MiniforgeConfig'
            Linux   = '安装 miniforge，再运行 Deploy-MiniforgeConfig'
        }
        Docs      = 'Feature-Guide.md §11'
    }

    # 提示符：node
    [PSCustomObject]@{
        Feature   = '提示符：node'
        Component = 'fnm'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'fnm'
        Gate      = 'PsFnm'
        Impact    = 'node 版本切换不可用；仅 node 用户需要。'
        Install   = @{
            Windows = 'scoop install fnm，再 Enable-CxxuComponent Fnm -Persist'
            Mac     = 'brew install fnm，再 Enable-CxxuComponent Fnm -Persist'
            Linux   = '按官网脚本安装 fnm，再 Enable-CxxuComponent Fnm -Persist'
        }
        Docs      = 'Feature-Guide.md §11'
        Note      = '组件默认关闭；启用后由 init 执行 fnm env --use-on-cd。'
    }

    # 提示符：posh-git
    [PSCustomObject]@{
        Feature   = '提示符：posh-git'
        Component = 'posh-git 模块或仓库'
        Level     = '可选'
        Kind      = 'PathOrModule'
        Name      = 'posh-git'
        Path      = (Join-Path (Join-Path (Join-Path $homeDir 'repos') 'posh-git') 'src/posh-git.psd1')
        Impact    = 'Set-PoshPrompt -Poshgit 的 git 状态段不可用。'
        Install   = 'Install-Module posh-git -Scope CurrentUser -Force，或 clone 到 ~/repos/posh-git'
        Docs      = 'Feature-Guide.md §7'
        Note      = '需在 Set-PoshPrompt 时加 -Poshgit。'
    }

    # 提示符：oh-my-posh
    [PSCustomObject]@{
        Feature   = '提示符：oh-my-posh'
        Component = 'oh-my-posh'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'oh-my-posh'
        Impact    = 'Set-PoshPrompt 主题不可用；默认 prompt 不受影响。'
        Install   = @{
            Windows = 'scoop install oh-my-posh'
            Mac     = 'brew install oh-my-posh'
            Linux   = '按官网脚本安装 oh-my-posh'
        }
        Docs      = 'Feature-Guide.md §7'
        Note      = '需要 POSH_THEMES_PATH 指向主题目录；默认不启用。'
    }

    # 工具链：包管理器
    [PSCustomObject]@{
        Feature   = '工具链：包管理器'
        Component = 'scoop'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'scoop'
        Platform  = 'Windows'
        Impact    = 'Windows 下不能一键安装 fzf、zoxide、fnm 等二进制。'
        Install   = '按官网安装，或运行 Deploy-ScoopByGithubMirrors'
        Docs      = 'Feature-Guide.md §11'
    }
    [PSCustomObject]@{
        Feature   = '工具链：包管理器'
        Component = 'scoop-search'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'scoop-search'
        Platform  = 'Windows'
        Gate      = 'PsScoopSearch'
        Impact    = 'scoop search 仍可用但较慢。'
        Install   = 'scoop install scoop-search，再 Enable-CxxuComponent ScoopSearch -Persist'
        Docs      = 'Feature-Guide.md §11'
        Note      = '组件默认关闭；启用后由 init 注入 scoop-search --hook。'
    }
    [PSCustomObject]@{
        Feature   = '工具链：包管理器'
        Component = 'brew'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'brew'
        Platform  = 'Mac'
        Impact    = 'macOS 下安装 fzf、zoxide、fnm 等依赖不方便。'
        Install   = '按 https://brew.sh/ 安装'
        Docs      = 'Feature-Guide.md §7'
    }

    # 运维：压缩归档
    [PSCustomObject]@{
        Feature   = '运维：压缩归档'
        Component = '7z'
        Level     = '可选'
        Kind      = 'Command'
        Name      = '7z'
        Impact    = 'ArchiveProcess 的 7z 压缩/解压，以及 Sitemap/WordPress 的 7z 解包不可用。'
        Install   = @{
            Windows = 'scoop install 7zip'
            Mac     = 'brew install sevenzip'
            Linux   = '系统包管理器安装 7zip'
        }
        Docs      = 'Module-Map.md ArchiveProcess'
    }
    [PSCustomObject]@{
        Feature   = '运维：压缩归档'
        Component = 'zstd'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'zstd'
        Impact    = 'ArchiveProcess 的 zstd 压缩/解压不可用。'
        Install   = @{
            Windows = 'scoop install zstd'
            Mac     = 'brew install zstd'
            Linux   = '系统包管理器安装 zstd'
        }
        Docs      = 'Module-Map.md ArchiveProcess'
    }
    [PSCustomObject]@{
        Feature   = '运维：压缩归档'
        Component = 'lz4'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'lz4'
        Impact    = 'ArchiveProcess 的 lz4 压缩/解压不可用。'
        Install   = @{
            Windows = 'scoop install lz4'
            Mac     = 'brew install lz4'
            Linux   = '系统包管理器安装 lz4'
        }
        Docs      = 'Module-Map.md ArchiveProcess'
    }
    [PSCustomObject]@{
        Feature   = '运维：压缩归档'
        Component = 'gzip'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'gzip'
        Impact    = '7z 不可用时，ArchiveProcess 无法解压 .gz 文件。'
        Install   = '随 Git for Windows 或系统提供；Windows 可用 scoop install gzip'
        Docs      = 'Module-Map.md ArchiveProcess'
    }

    # 运维：SSH 远程
    [PSCustomObject]@{
        Feature   = '运维：SSH 远程'
        Component = 'ssh'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'ssh'
        Impact    = 'SSH 与 WpOnline 的远程执行、部署流程不可用。'
        Install   = @{
            Windows = 'scoop install openssh，或启用 Windows 可选功能 OpenSSH Client'
            Mac     = '系统自带；缺少时 brew install openssh'
            Linux   = '系统包管理器安装 openssh-client'
        }
        Docs      = 'Module-Map.md SSH'
    }
    [PSCustomObject]@{
        Feature   = '运维：SSH 远程'
        Component = 'scp'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'scp'
        Impact    = 'WpOnline 与 SSH 的文件上传/下载不可用。'
        Install   = @{
            Windows = 'scoop install openssh，或启用 Windows 可选功能 OpenSSH Client'
            Mac     = '系统自带；缺少时 brew install openssh'
            Linux   = '系统包管理器安装 openssh-client'
        }
        Docs      = 'Module-Map.md SSH'
    }
    [PSCustomObject]@{
        Feature   = '运维：SSH 远程'
        Component = 'sshpass'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'sshpass'
        Impact    = 'SSH 密码自动登录不可用；优先使用密钥认证时不受影响。'
        Install   = @{
            Windows = '在 Git Bash/MSYS2 中安装 sshpass，或改用密钥认证'
            Mac     = 'brew install hudochenkov/sshpass/sshpass'
            Linux   = '系统包管理器安装 sshpass'
        }
        Docs      = 'Module-Map.md SSH'
        Note      = '优先密钥认证。'
    }
    [PSCustomObject]@{
        Feature   = '运维：SSH 远程'
        Component = 'ssh-keygen'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'ssh-keygen'
        Impact    = 'SSH 密钥生成与免密配置不可用。'
        Install   = @{
            Windows = 'scoop install openssh，或启用 Windows 可选功能 OpenSSH Client'
            Mac     = '系统自带'
            Linux   = '系统包管理器安装 openssh-client'
        }
        Docs      = 'Module-Map.md SSH'
    }
    [PSCustomObject]@{
        Feature   = '运维：SSH 远程'
        Component = 'sshd'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'sshd'
        Platform  = 'Windows'
        Impact    = 'Windows SSH 服务端初始化不可用。'
        Install   = 'scoop install openssh，再运行 install-sshd.ps1'
        Docs      = 'Module-Map.md SSH'
    }

    # 运维：MySQL
    [PSCustomObject]@{
        Feature   = '运维：MySQL'
        Component = 'mysql'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'mysql'
        Impact    = 'MySql 模块的备份、建库、查询与导入不可用。'
        Install   = @{
            Windows = '安装 MySQL 客户端或 phpstudy 自带 mysql.exe，并把所在目录加入 PATH'
            Mac     = 'brew install mysql-client'
            Linux   = '系统包管理器安装 mysql-client'
        }
        Docs      = 'Module-Map.md MySql'
        Note      = '部分函数可用 -MySqlCliPath 指定路径。'
    }

    [PSCustomObject]@{
        Feature   = '运维：MySQL'
        Component = 'mysqldump'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'mysqldump'
        Impact    = 'MySql 模块的数据库备份不可用。'
        Install   = @{
            Windows = '安装 MySQL 客户端或 phpstudy 自带 mysqldump.exe，并把所在目录加入 PATH'
            Mac     = 'brew install mysql-client'
            Linux   = '系统包管理器安装 mysql-client'
        }
        Docs      = 'Module-Map.md MySql'
        Note      = '通常随 mysql 客户端一起安装。'
    }

    # 运维：Nginx
    [PSCustomObject]@{
        Feature   = '运维：Nginx'
        Component = 'nginx'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'nginx'
        Impact    = 'Web 模块的本地站点启动、重载与配置检查不可用。'
        Install   = @{
            Windows = '安装 phpstudy 或 nginx，并把 nginx.exe 所在目录加入 PATH'
            Mac     = 'brew install nginx'
            Linux   = '系统包管理器安装 nginx'
        }
        Docs      = 'Module-Map.md Web'
        Note      = '部分函数可用 -NginxPath 指定路径。'
    }

    # 运维：Cloudflare 与 Python 脚本
    [PSCustomObject]@{
        Feature   = '运维：Cloudflare 与脚本'
        Component = 'python'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'python'
        Impact    = 'Cloudflare、BTCN 等 Python 脚本功能不可用。'
        Install   = @{
            Windows = 'scoop install python，或从官网安装'
            Mac     = 'brew install python'
            Linux   = '系统包管理器安装 python3，并确保 python 命令可用'
        }
        Docs      = 'Module-Map.md Cloudflare'
        Note      = 'Cloudflare 脚本还需要 pip install requests。'
    }
    [PSCustomObject]@{
        Feature   = '运维：Cloudflare 与脚本'
        Component = 'curl'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'curl'
        Impact    = 'Cloudflare token 校验、WpContent/Sitemap 的 curl 下载不可用；部分功能可用 Invoke-WebRequest 替代。'
        Install   = @{
            Windows = 'Windows 10+ 自带 curl.exe；缺少时 scoop install curl'
            Mac     = '系统自带'
            Linux   = '系统包管理器安装 curl'
        }
        Docs      = 'Module-Map.md Cloudflare'
    }
    [PSCustomObject]@{
        Feature   = '运维：Cloudflare 与脚本'
        Component = 'ThreadJob 模块'
        Level     = '可选'
        Kind      = 'Module'
        Name      = 'ThreadJob'
        Impact    = 'Windows PowerShell 5.1 下 WpOnline 的并行部署流程不可用。'
        Install   = 'Install-Module ThreadJob -Scope CurrentUser -Force'
        Docs      = 'Feature-Guide.md §13'
        Note      = '仅 Windows PowerShell 5.1 需要。'
    }

    # 运维：网络驱动器
    [PSCustomObject]@{
        Feature   = '运维：网络驱动器'
        Component = 'alist'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'alist'
        Platform  = 'Windows'
        Impact    = 'NetDrivers 的 alist 服务启动不可用。'
        Install   = '下载 alist 并加入 PATH，或放到模块约定目录'
        Docs      = 'Module-Map.md NetDrivers'
    }
    [PSCustomObject]@{
        Feature   = '运维：网络驱动器'
        Component = 'chfs'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'chfs'
        Platform  = 'Windows'
        Impact    = 'NetDrivers 的 chfs 服务启动不可用。'
        Install   = '下载 chfs 并加入 PATH，或放到模块约定目录'
        Docs      = 'Module-Map.md NetDrivers'
    }
    [PSCustomObject]@{
        Feature   = '运维：网络驱动器'
        Component = 'aria2c'
        Level     = '可选'
        Kind      = 'Command'
        Name      = 'aria2c'
        Impact    = 'Git 模块的 aria2 下载加速与 NetDrivers 的 aria2 RPC 不可用。'
        Install   = @{
            Windows = 'scoop install aria2'
            Mac     = 'brew install aria2'
            Linux   = '系统包管理器安装 aria2'
        }
        Docs      = 'Module-Map.md NetDrivers'
    }

    # 通知：Toast
    [PSCustomObject]@{
        Feature   = '通知：Toast'
        Component = 'BurntToast 模块'
        Level     = '可选'
        Kind      = 'Module'
        Name      = 'BurntToast'
        Platform  = 'Windows'
        Impact    = 'TimeNotify 的 Toast 通知与整点报时不可用。'
        Install   = 'Install-Module BurntToast -Scope CurrentUser -Force'
        Docs      = 'Module-Map.md TimeNotify'
    }
)
