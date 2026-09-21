@{
    RootModule = 'Init.psm1'
    ModuleVersion = '1.0.4'
    GUID = '55ff76df-c972-4ac7-ab2e-b034eba51fa2'
    Author = 'cxxu'
    Description = 'Pwsh startup orchestration: init/p entry points and env-level tracking'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'init',
        'p',
        'Set-CommonInit',
        'Set-LastUpdateTime',
        'Start-MemoryInfoInit',
        'Import-TerminalIcons',
        'Set-PSReadLinesCommon',
        'Set-PSReadLinesAdvanced',
        'Optimize-PsHistory',
        'Import-CxxuConfig',
        'New-CxxuConfigTemplate',
        'Disable-PsPlugin',
        'Enable-PsPlugin',
        'Update-PwshEnv',
        'Test-PsEnvMode',
        'Update-PwshvarsIfNotYet',
        'Update-PwshEnvIfNotYet',
        'Install-Ps51Profile'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('CxxuPsModules')
            ProjectUri = 'https://github.com/xuchaoxin1375/scripts'
        }
    }
}
