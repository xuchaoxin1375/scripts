@{
    RootModule = 'Info.psm1'
    ModuleVersion = '1.0.4'
    GUID = '364a6efe-875d-4b78-bfac-de65ecea1155'
    Author = 'cxxu'
    Description = 'System information queries and process/memory views'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'ResourceMonitor',
        'Get-CapacityUnitized',
        'Get-MemoryCapacity',
        'Get-LocalGroupOfUser',
        'Get-NetConnectionInfo',
        'Update-NetConnectionInfo',
        'Get-IpAddressFormated',
        'Get-IpAddressForPrompt',
        'Get-MemoryUseRatio',
        'Get-MemoryUseSummary',
        'Get-BatteryLevel',
        'Get-UserHostName',
        'Get-BIOSInfo',
        'Get-ScreenResolution',
        'Get-SystemInfoBasic',
        'Get-ComputerCoreHardwareInfo',
        'Get-MotherBoardInfo',
        'Get-MemoryChipInfo',
        'Get-MaxMemoryCapacity',
        'Get-DiskDriversInfo',
        'Get-ProcessPath',
        'Get-MacOSOperatingSystemInfo',
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
