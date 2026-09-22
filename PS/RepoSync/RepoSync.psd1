@{
    RootModule = 'RepoSync.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'fc2215c8-56d0-4fde-a9cd-908a0f858ca2'
    Author = 'cxxu'
    Description = 'Repo sync and dev-env sync'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Install-SubModules',
        'update_functions',
        'vscodeExtListExport',
        'Push-ReposesConfiged',
        'Push-ReposesConfigedFromMainPC',
        'Update-ReposesConfiged',
        'pipUpdateIntegration',
        'status'
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
