@{
    RootModule = 'NetDrivers.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'b770e464-54cc-4f92-85e2-f86120522691'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: NetDrivers'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-PSNetDriveList',
        'Mount-AlistLocalhostDrive',
        'Mount-NetDrive',
        'Start-AlistHomePage',
        'Start-AliyundrivePage',
        'Remove-NetDrive',
        'Start-ChfsServer',
        'Start-AlistServer',
        'Start-Aria2Rpc'
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
