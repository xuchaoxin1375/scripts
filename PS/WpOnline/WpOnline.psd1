@{
    RootModule = 'WpOnline.psm1'
    ModuleVersion = '1.0.4'
    GUID = '38c8829a-67ff-45e5-8237-8eeadf8dc112'
    Author = 'cxxu'
    Description = 'WordPress online ops: deploy/plugins/orders/remote update'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
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
        'Deploy-WpServerDF',
        'Backup-WpBaseSql'
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
