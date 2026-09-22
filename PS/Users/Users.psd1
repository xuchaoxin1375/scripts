@{
    RootModule = 'Users.psm1'
    ModuleVersion = '1.0.4'
    GUID = '7b50d246-578a-4e4e-bbad-34985967b8f3'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Users'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-UsersGroupsCmdlets',
        'Get-UsersProfileList'
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
