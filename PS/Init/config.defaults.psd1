@{
    # CxxuPsModules 默认偏好真源（随仓库分发，所有设备共用这一份）。
    # 组件（Fzf/Zoxide/Predictor/Tab/Argc/GitCompletion/Carapace 等）的默认值与选项在 components.psd1；
    # 本文件只保留不属于单个组件的 Settings。
    # 用途：New-CxxuConfigTemplate 生成用户配置、Reset-CxxuConfig 重置默认、Get-CxxuConfig 对照默认值。
    # 改动这里会改变所有设备的默认偏好；用户配置文件与环境变量仍按“环境变量 > 配置文件 > 默认值”覆盖。
    Defaults = @(
        @{ Key = 'PsShowProgress'; Name = 'ShowProgress'; Default = $true; Description = 'init：启动进度条' }
        @{ Key = 'PsStartupTier'; Name = 'StartupTier'; Default = 'Balanced'; Description = 'init：启动档位 Minimal/Fast/Balanced；Minimal 最轻，Fast 保留常用补全，Balanced 为默认' }
        @{ Key = 'PsGithubMirror'; Name = 'GithubMirror'; Default = ''; Description = 'GitHub 镜像前缀；为空时走默认地址与静默测速' }
    )
}
