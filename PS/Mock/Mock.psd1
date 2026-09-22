@{
    RootModule = 'Mock.psm1'
    ModuleVersion = '1.0.4'
    GUID = '83771a1c-8b6c-4f37-bb68-4f9b31c38151'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Mock'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-RandomString',
        'New-GrowFile'
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
