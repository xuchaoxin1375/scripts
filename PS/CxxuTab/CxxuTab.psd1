@{
    RootModule = 'CxxuTab.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'd740d667-a86b-496d-92e9-a5333e88cc1d'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: CxxuTab (Tab command-name fuzzy completion backed by CxxuPredictor)'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Install-CxxuTabWrapper'
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
