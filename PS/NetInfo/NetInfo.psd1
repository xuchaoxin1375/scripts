@{
    RootModule = 'NetInfo.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'd193bda8-b902-4a2a-ace1-d72a96c22268'
    Author = 'cxxu'
    Description = 'Network connection and IP info for prompt and daemons'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-NetConnectionInfo',
        'Update-NetConnectionInfo',
        'Get-IpAddressFormated',
        'Get-IpAddressForPrompt'
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
