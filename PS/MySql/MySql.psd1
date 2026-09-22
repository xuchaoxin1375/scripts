@{
    RootModule = 'MySql.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'fa230ac9-7fee-4846-891e-366c79eb021e'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: MySql'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-MysqlDbInfo',
        'Import-MysqlFile',
        'Remove-MysqlDB',
        'Remove-MysqlIsolatedDB',
        'Export-MysqlFile',
        'Get-MySqlDatabaseNameDotNet',
        'Get-MySqlDatabaseNameNative',
        'Get-MysqlTablesList',
        'Start-MySqlQueryForDbs',
        'Start-MysqlConnectionFromConfig',
        'Get-MysqlKeyInline',
        'New-MysqlDB'
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
