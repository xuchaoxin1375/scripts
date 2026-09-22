@{
    RootModule = 'ArgumentCompletion.psm1'
    ModuleVersion = '1.0.4'
    GUID = '6b524d25-7750-47cb-8d9d-b1e66d600b3a'
    Author = 'cxxu'
    Description = 'Register-ArgumentCompleter adapters for module commands'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-EnvVarCompleter',
        'Set-ArgumentCompleter'
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
