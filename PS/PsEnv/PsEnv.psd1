@{
    RootModule = 'PsEnv.psm1'
    ModuleVersion = '1.0.4'
    GUID = '6d3a057a-cac9-4d98-bba1-442ca9e9b500'
    Author = 'cxxu'
    Description = 'PowerShell 版本/环境/profile 管理:升级/扩展关联/profile 路径'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Set-PsExtension',
        'Get-PsProfilesPath',
        'Remove-PsProfiles',
        'Confirm-PsVersion',
        'Install-ScoopByLocalProxy',
        'Update-PowerShellLegacy',
        'Get-LatestPowerShellDownloadUrl',
        'Update-PowerShell'
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
