@{
    RootModule = 'Calendar.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'b2f5a98d-0cbe-4803-8d20-63acf2df8361'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Calendar'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Show-Calendar'
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
