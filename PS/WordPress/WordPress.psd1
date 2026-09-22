@{
    RootModule = 'WordPress.psm1'
    ModuleVersion = '1.0.4'
    GUID = '8b2a8243-10db-42a0-8f2f-28840c7da403'
    Author = 'cxxu'
    Description = 'WordPress local sites build and Deploy-Wp entry'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Remove-WpSitesLocal',
        'Get-WpSitePacks',
        'Get-MoreSites',
        'Confirm-WpEnvironment',
        'Get-XpCgiPort',
        'Stop-phpCgi',
        'Start-XpCgi',
        'Deploy-WpSitesLocal',
        'Deploy-Wp'
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
