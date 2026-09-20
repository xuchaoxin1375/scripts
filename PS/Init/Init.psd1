@{
    RootModule = 'Init.psm1'
    ModuleVersion = '1.0.4'
    GUID = '55ff76df-c972-4ac7-ab2e-b034eba51fa2'
    Author = 'cxxu'
    Description = 'Pwsh startup orchestration: init/p entry points and env-level tracking'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'init',
        'p',
        'Set-CommonInit',
        'Set-LastUpdateTime',
        'Start-MemoryInfoInit',
        'Import-TerminalIcons',
        'Set-PSReadLinesCommon',
        'Set-PSReadLinesAdvanced',
        'Update-PwshEnv',
        'Test-PsEnvMode',
        'Update-PwshvarsIfNotYet',
        'Update-PwshEnvIfNotYet'
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
