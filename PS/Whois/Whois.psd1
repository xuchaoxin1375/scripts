@{
    RootModule = 'Whois.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'efc05034-c3a9-4205-b19e-578d638157c3'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Whois'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-WhoisInfo',
        'Format-WhoisResult'
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
