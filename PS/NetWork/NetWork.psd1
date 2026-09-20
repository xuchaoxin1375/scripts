@{
    RootModule = 'NetWork.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'c94f5682-ac5f-46b1-929a-b6468fcbef25'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: NetWork'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Set-NetworkDiscovery',
        'Set-NetworkFileAndPrinterSharing',
        'Get-SmbSessionMainInfo'
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
