@{
    RootModule = 'Scoop.psm1'
    ModuleVersion = '1.0.4'
    GUID = '37428d77-6d4e-41de-becd-764fc42c3d5f'
    Author = 'cxxu'
    Description = 'Scoop package manager: CN mirrors deploy and batch install'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Set-ScoopAria2Options',
        'Deploy-ScoopByGithubMirrors',
        'Deploy-ScoopByGitee',
        'Add-ScoopBuckets',
        'Deploy-ScoopAppsPath',
        'Update-ScoopMirror',
        'Set-ScoopVersion',
        'Deploy-ScoopForCNUser',
        'Deploy-ScoopApps',
        'Deploy-ScoopStartMenuAppsStarter'
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
