@{
    RootModule = 'Browser.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'd166fcde-f6a8-4778-b35b-c14523b2d411'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Browser'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'edge_favoriates',
        'googleSearch',
        'csdn_writer',
        'https_open'
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
