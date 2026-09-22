@{
    RootModule = 'ColorSettings.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'e5fd3986-70d4-4096-94fe-d2e2f61122c5'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: ColorSettings'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'closeColor',
        'colorSet'
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
