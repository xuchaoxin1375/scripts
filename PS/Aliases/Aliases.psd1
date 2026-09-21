@{
    RootModule = 'Aliases.psm1'
    ModuleVersion = '1.0.4'
    GUID = '27f5ee9e-b77b-42f3-b83e-0246b9c9264b'
    Author = 'cxxu'
    Description = 'Predefined aliases and shortcuts loader'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Update-PwshAliases',
        'Set-PwshAliasFile'
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
