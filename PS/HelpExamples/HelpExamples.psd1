@{
    RootModule = 'HelpExamples.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'ecc2bc41-76c9-4f95-b01c-c5b429f6f9ed'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: HelpExamples'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Add-ExtensionExample',
        'Operators_Comparison_pwsh',
        'Operators_Logical_pwsh'
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
