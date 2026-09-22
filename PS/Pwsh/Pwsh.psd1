@{
    RootModule = 'Pwsh.psm1'
    ModuleVersion = '1.0.4'
    GUID = '7a6243f2-bed4-47b7-a4fe-49bb87a7e2f4'
    Author = 'cxxu'
    Description = 'PowerShell 模块加载脚手架:强制导入/自举/注入profile/manifest 同步'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Confirm-ModuleInstalled',
        'Add-CxxuPsModuleToProfile',
        'Add-CxxuPsModuleToEnvVar',
        'New-ModuleByCxxu',
        'Import-ModuleForce',
        'ipmof',
        'ipmox',
        'Sync-ModuleManifest'
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
