@{
    RootModule = 'Search.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'ede1c668-6a26-4cd9-8cde-1e94c01595ef'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Search'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-ItemMatchedPattern',
        'Find-Directory',
        'searchStrings',
        'search_item',
        'listRecurse',
        'searchConstStrWithCatn',
        'Get-ServiceMainInfo',
        'Disable-Service',
        'Disable-ServiceBasic'
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
