@{
    RootModule = 'EnvVar.psm1'
    ModuleVersion = '1.0.4'
    GUID = '0817e7ab-c5c2-4242-b4b4-46190f5f5674'
    Author = 'cxxu'
    Description = 'Environment variable management (User/Machine/Process scopes)'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-EnvList',
        'Get-EnvVar',
        'Get-EnvPath',
        'Remove-RedundantSemicolon',
        'Get-EnvVarRawValue',
        'Get-EnvVarExpandedValue',
        'Add-EnvVar',
        'Clear-EnvVar',
        'Clear-EnvValue',
        'Remove-EnvVarValue',
        'Remove-EnvVar',
        'Set-EnvVar',
        'Set-ProcessEnvVar',
        'Get-EnvCountedValues',
        'Update-EnvVarFromSysEnv'
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
