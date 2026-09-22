@{
    RootModule = 'Security.psm1'
    ModuleVersion = '1.0.4'
    GUID = '4e479fd2-3e76-4e73-9570-3276c279870a'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Security'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Confirm-Restart',
        'Get-CredentialGuardStatus',
        'Disable-CredentialGuard',
        'Disable-VBS'
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
