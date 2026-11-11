@{
    # CxxuPsModules 组件清单（仓库真源）。
    # 用途：Get/Enable/Disable-CxxuComponent 读取同一份元数据；init 也按清单顺序为
    # 可选组件生成加载步骤，因此新增组件只需在这里登记并实现 Init 函数。
    # Phase 只做分组与说明；用户配置只表达 Enabled 与选项，不在这里改加载逻辑。
    # 新增组件：补一条记录，并在 Init.psm1 提供对应的 Init 函数。
    # Init 是 init 启动步骤调用的入口；需要首用懒加载的组件，Init 指向注册桩，
    # 再用 InitNow 指向立即加载函数（Enable-CxxuComponent -Now 调用）。
    # Lazy 只描述预期加载时机（展示/文档用），实际加载由 Init/InitNow 函数决定；
    # 两者不一致时以函数行为为准，并在 Test-CxxuComponent 中补检查。
    # 可选 EnableHint：Get-CxxuComponent/Test-CxxuComponent 的启用提示（默认 Enable-CxxuComponent <Id> -Persist）。
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
            EnableHint  = 'Set-GitCompletionSource GitCompletion -Persist'
            Docs        = 'Feature-Guide.md §7'
            Options     = @(
                @{
                    Name        = 'Source'
                    Key         = 'PsGitCompletionSource'
                    Default     = 'Auto'
                    Type        = 'Enum'
                    Values      = @('Auto', 'GitCompletion', 'Carapace', 'Argc')
                    Description = 'git/gitk 补全来源：Auto/GitCompletion/Carapace/Argc（Argc 缺 --cached/--staged 等选项，不推荐）'
                }
            )
        }
        @{
            Id          = 'Carapace'
            Name        = 'carapace'
            Phase       = 'Completions'
            Key         = 'PsCarapace'
            Default     = $false
            Description = '外部 CLI 参数补全（首个 Tab 懒加载，7 约 0.2–0.3 秒；5.1 约 0.5–1 秒）'
            Lazy        = 'FirstUse'
            Init        = 'Register-CarapaceLazyLoad'
            InitNow     = 'Initialize-Carapace'
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
        @{
            Id          = 'PSCompletions'
            Name        = 'PSCompletions'
            Phase       = 'Completions'
            Key         = 'PsCompletions'
            Default     = $false
            Description = '约 200 个命令的参数补全（init 导入模块）'
            Lazy        = 'Startup'
            Init        = 'Import-PsCompletions'
            Detect      = 'PSCompletions'
            Install     = 'Deploy-CompletionStack -IncludePSCompletions'
            Docs        = 'Feature-Guide.md §7'
        }
        @{
            Id          = 'Fnm'
            Name        = 'fnm'
            Phase       = 'Environment'
            Key         = 'PsFnm'
            Default     = $false
            Description = 'node 版本切换（init 执行 fnm env --use-on-cd）'
            Lazy        = 'Startup'
            Init        = 'Initialize-Fnm'
            Detect      = 'fnm'
            Install     = 'scoop install fnm（或 brew install fnm）'
            Docs        = 'Feature-Guide.md §7'
        }
        @{
            Id          = 'ScoopSearch'
            Name        = 'scoop-search'
            Phase       = 'Tools'
            Key         = 'PsScoopSearch'
            Default     = $false
            Description = 'scoop 搜索加速（init 注入 scoop-search --hook）'
            Lazy        = 'Startup'
            Init        = 'Initialize-ScoopSearch'
            Detect      = 'scoop-search'
            Install     = 'scoop install scoop-search'
            Docs        = 'Feature-Guide.md §11'
        }
    )
}
