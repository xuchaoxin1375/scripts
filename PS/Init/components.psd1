@{
    # CxxuPsModules 组件清单（仓库真源）。
    # 用途：init 按 Phase 顺序加载；Get/Enable/Disable-CxxuComponent 读取同一份元数据；
    # 用户配置只表达 Enabled 与选项，不在这里改加载顺序。
    # 新增组件：补一条记录，并在 Init.psm1 提供对应的 Init 函数。
    SchemaVersion = 1
    Components    = @(
        @{
            Id          = 'Fzf'
            Name        = 'PSFzf'
            Phase       = 'Interaction'
            Key         = 'PsFzf'
            Default     = $true
            Description = 'Ctrl+T 选文件、Ctrl+R 选历史'
            Lazy        = 'FirstUse'
            Init        = 'Register-PsUxLazyLoad'
            Detect      = 'PSFzf'
            Install     = 'Deploy-CompletionStack -IncludeFuzzy'
            Docs        = 'Feature-Guide.md §7'
        }
        @{
            Id          = 'Zoxide'
            Name        = 'zoxide'
            Phase       = 'Interaction'
            Key         = 'PsZoxide'
            Default     = $true
            Description = 'z 目录跳转'
            Lazy        = 'OnIdle'
            Init        = 'Register-PsUxLazyLoad'
            Detect      = 'zoxide'
            Install     = 'Deploy-CompletionStack -IncludeFuzzy'
            Docs        = 'Feature-Guide.md §7'
        }
        @{
            Id          = 'Predictor'
            Name        = 'CxxuPredictor'
            Phase       = 'Prediction'
            Key         = 'PsPredictor'
            Default     = $true
            Description = '命令名预测（守护进程固定关闭）'
            Lazy        = 'OnIdle'
            Init        = 'Register-PsUxLazyLoad'
            Detect      = 'CxxuPredictor'
            Install     = '随仓库分发'
            Docs        = 'Feature-Guide.md §7'
        }
        @{
            Id          = 'Tab'
            Name        = 'CxxuTab'
            Phase       = 'Tab'
            Key         = 'PsTab'
            Default     = $true
            Description = '命令名 Tab 模糊补全（首个 Tab 懒加载）'
            Lazy        = 'FirstUse'
            Init        = 'Register-PsUxLazyLoad'
            Detect      = 'CxxuTab'
            Install     = '随仓库分发'
            Docs        = 'Feature-Guide.md §7'
        }
        @{
            Id          = 'Argc'
            Name        = 'argc-completions'
            Phase       = 'Completions'
            Key         = 'PsArgc'
            Default     = $true
            Description = '参数补全（首个 Tab 懒加载）'
            Lazy        = 'FirstUse'
            Init        = 'Set-ArgcCompletions'
            Detect      = 'argc'
            Install     = 'Deploy-CompletionStack -IncludeArgc'
            Docs        = 'Argc-Completions-Deploy.md'
        }
        @{
            Id          = 'GitCompletion'
            Name        = 'git-completion'
            Phase       = 'Completions'
            Key         = 'PsGitCompletion'
            Default     = $true
            Description = 'git/gitk 的 Tab 补全（首次补全才导入模块）'
            Lazy        = 'FirstUse'
            Init        = 'Register-GitCompletion'
            Detect      = 'git-completion'
            Install     = 'Deploy-CompletionStack -IncludeGitCompletion'
            Docs        = 'Feature-Guide.md §7'
            Options     = @(
                @{
                    Name        = 'Source'
                    Key         = 'PsGitCompletionSource'
                    Default     = 'Auto'
                    Type        = 'Enum'
                    Values      = @('Auto', 'GitCompletion', 'Carapace', 'Argc')
                    Description = 'git/gitk 补全来源：Auto/GitCompletion/Carapace/Argc'
                }
            )
        }
        @{
            Id          = 'Carapace'
            Name        = 'carapace'
            Phase       = 'Completions'
            Key         = 'PsCarapace'
            Default     = $false
            Description = '外部 CLI 参数补全（init 启动时加载，约 0.1–0.2 秒）'
            Lazy        = 'Startup'
            Init        = 'Initialize-Carapace'
            Detect      = 'carapace'
            Install     = 'Deploy-Carapace'
            Docs        = 'Feature-Guide.md §7'
            Options     = @(
                @{
                    Name        = 'Excludes'
                    Key         = 'PsCarapaceExcludes'
                    Default     = @()
                    Type        = 'List'
                    Description = 'carapace 额外排除的命令（数组，如 winget、uv）'
                }
            )
        }
    )
}
