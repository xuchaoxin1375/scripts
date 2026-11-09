@{
    # CxxuPsModules 默认偏好真源（随仓库分发，所有设备共用这一份）
    # 用途：New-CxxuConfigTemplate 生成用户配置、Reset-CxxuConfig 重置默认、Get-CxxuConfig 对照默认值。
    # 改动这里会改变所有设备的默认偏好；用户配置文件与环境变量仍按“环境变量 > 配置文件 > 默认值”覆盖。
    Defaults = @(
        @{ Key = 'PsFzf'; Name = 'Fzf'; Default = $true; Description = 'PSFzf：Ctrl+T 选文件、Ctrl+R 选历史' }
        @{ Key = 'PsZoxide'; Name = 'Zoxide'; Default = $true; Description = 'zoxide：z 目录跳转' }
        @{ Key = 'PsPredictor'; Name = 'Predictor'; Default = $true; Description = 'CxxuPredictor：命令名预测（守护进程固定关闭）' }
        @{ Key = 'PsTab'; Name = 'Tab'; Default = $true; Description = 'CxxuTab：命令名 Tab 模糊补全（首个 Tab 懒加载）' }
        @{ Key = 'PsArgc'; Name = 'Argc'; Default = $true; Description = 'argc-completions：参数补全（首个 Tab 懒加载）' }
        @{ Key = 'PsGitCompletion'; Name = 'GitCompletion'; Default = $true; Description = 'git-completion：git/gitk 的 Tab 补全（首次补全才导入模块）' }
        @{ Key = 'PsGitCompletionSource'; Name = 'GitCompletionSource'; Default = 'Auto'; Description = 'git/gitk 补全来源：Auto/GitCompletion/Carapace/Argc' }
        @{ Key = 'PsCarapace'; Name = 'Carapace'; Default = $false; Description = 'carapace：外部 CLI 参数补全（init 启动时加载，约 0.1–0.2 秒）' }
        @{ Key = 'PsCarapaceExcludes'; Name = 'CarapaceExcludes'; Default = ''; Description = 'carapace 额外排除的命令（逗号分隔，如 winget,uv）' }
        @{ Key = 'PsShowProgress'; Name = 'ShowProgress'; Default = $true; Description = 'init：启动进度条' }
        @{ Key = 'PsGithubMirror'; Name = 'GithubMirror'; Default = ''; Description = 'GitHub 镜像前缀；为空时走默认地址与静默测速' }
    )
}
