@{
    RootModule = 'Special.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'a1365b22-e69b-4914-be0e-3cba48e9a1e5'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Special'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Register-AlistStartup'
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
