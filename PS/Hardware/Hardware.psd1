@{
    RootModule = 'Hardware.psm1'
    ModuleVersion = '1.0.4'
    GUID = '32582e91-2791-4dc6-8f95-252a42bb8417'
    Author = 'cxxu'
    Description = 'Local hardware and system info: CPU/board/memory/BIOS/disk/display'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-CapacityUnitized',
        'Get-MemoryCapacity',
        'Get-BIOSInfo',
        'Get-ScreenResolution',
        'Get-SystemInfoBasic',
        'Get-ComputerCoreHardwareInfo',
        'Get-MotherBoardInfo',
        'Get-MemoryChipInfo',
        'Get-MaxMemoryCapacity',
        'Get-DiskDriversInfo',
        'Get-MacOSOperatingSystemInfo'
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
