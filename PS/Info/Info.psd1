@{
    RootModule = 'Info.psm1'
    ModuleVersion = '1.0.4'
    GUID = '364a6efe-875d-4b78-bfac-de65ecea1155'
    Author = 'cxxu'
    Description = 'System information queries and process/memory views'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'ResourceMonitor',
        'Get-LocalGroupOfUser',
        'Get-MemoryUseRatio',
        'Get-MemoryUseSummary',
        'Get-BatteryLevel',
        'Get-UserHostName',
        'Get-ProcessPath',
        'Get-ProcessDetail',
        'Get-ProcessMemoryView',
        'Get-CommitStatus',
        'Show-CommitMemoryBar',
        'Show-MemoryBar'
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
