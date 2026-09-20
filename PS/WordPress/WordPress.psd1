@{
    RootModule = 'WordPress.psm1'
    ModuleVersion = '1.0.4'
    GUID = '8b2a8243-10db-42a0-8f2f-28840c7da403'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: WordPress'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Remove-WpSitesLocal',
        'Get-WpSitePacks',
        'Get-MoreSites',
        'Confirm-WpEnvironment',
        'Get-XpCgiPort',
        'Stop-phpCgi',
        'Start-XpCgi',
        'Deploy-WpSitesLocal',
        'Deploy-WpSitesOnline',
        'Update-NginxVhostOnHost',
        'Get-CFAccountsCodeDF',
        'Get-ServerList',
        'Update-WpAllPluginPackagesOnServers',
        'Update-WpFunctionsphpOnServer',
        'Update-WpFunctionsphpOnServers',
        'update-WpSqlOnServers',
        'Get-WpOrdersByEmailOnServers',
        'Update-Servers',
        'Push-ServerItem',
        'Update-WpPluginsDFOnServer',
        'Update-WpPluginsDFOnServers',
        'Update-WpSitesRobots',
        'Update-WpTitle',
        'Update-WpUrl',
        'Move-ItemImagesFromCsvPathFields',
        'Get-WpImages',
        'Import-WpSqlBatch',
        'Deploy-WpServerDF',
        'Get-XXXShopifyProductJsonUrlArchived',
        'Get-ShopifyProductJsonUrl',
        'Get-WpSitesLocalImagesCount',
        'Backup-WpBaseSql',
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
