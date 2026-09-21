@{
    RootModule = 'PwshVar.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'dca6cb93-c6f3-4c53-a0ee-00f2da9a0e3c'
    Author = 'cxxu'
    Description = 'Predefined PowerShell variables loader (.conf files)'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Import-PwshVarFileTesting',
        'Update-PwshVars',
        'Get-CompiledPwshVarLines',
        'Import-PwshVarFileLegacy',
        'Import-PwshVarFile',
        'Import-ANSIColorEnv'
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
