@{
    RootModule = 'Git.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'dcb4f0eb-cda3-4d7f-99f5-b486ca2f4c9e'
    Author = 'cxxu'
    Description = 'Git daily operations and repository helpers'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'git_clone_shallow',
        'gitUpdateReposSimply',
        'Remove-GitImagesFromHistory',
        'Set-GitProxy',
        'Get-SpeedUpUrl',
        'Invoke-GithubResourcesSpeedup',
        'Update-CodeiumVScodeExtension',
        'gitconfigEdit',
        'git_initial_email_name',
        'gitLogGraphSingleLine',
        'gitLogGraphDetail',
        'gitS',
        'gitNoRepeatValidate',
        'checkGitReports',
        'gctm'
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
