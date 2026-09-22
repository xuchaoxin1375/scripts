@{
    RootModule = 'Cloudflare.psm1'
    ModuleVersion = '1.0.4'
    GUID = '9aec29a3-5718-4cda-9fbe-f307794255e9'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Cloudflare'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Set-CFCredentials',
        'Get-CFZoneID',
        'Get-CFZoneDnsInfo',
        'Add-CFZoneDNSRecords',
        'Add-CFZoneConfig',
        'Add-CFZoneCheckActivation',
        'Get-CFZoneInfoFromTable',
        'Get-CFZoneNameServersTable',
        'Get-CFDNSDomains'
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
