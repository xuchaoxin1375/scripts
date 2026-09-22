@{
    RootModule = 'Pwsh.psm1'
    ModuleVersion = '1.0.4'
    GUID = '7a6243f2-bed4-47b7-a4fe-49bb87a7e2f4'
    Author = 'cxxu'
    Description = 'PowerShell 模块加载脚手架:强制导入/自举/注入profile/manifest 同步'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Confirm-ModuleInstalled',
        'Add-CxxuPsModuleToProfile',
        'Add-CxxuPsModuleToEnvVar',
        'New-ModuleByCxxu',
        'Import-ModuleForce',
        'ipmof',
        'ipmox',
        'Sync-ModuleManifest',
        'Get-CxxuModuleCompatibility'
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
