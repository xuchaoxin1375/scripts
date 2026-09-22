@{
    RootModule = 'TextProcess.psm1'
    ModuleVersion = '1.0.4'
    GUID = '0e5516b5-ca0c-44d0-95af-85bdb042b284'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: TextProcess'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'ConvertTo-LowerCase',
        'Split-TextFile',
        'Split-FileByLines_',
        'Split-FileAverageByLines_',
        'CreateNewPartFile_',
        'Add-LinesAfterMark',
        'Measure-AlphabeticChars'
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
