@{
    RootModule = 'Deploy.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'a92ff02b-239e-4ead-bdf3-ba336326d073'
    Author = 'cxxu'
    Description = 'Software and environment one-click deployment'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Install-BasicSoftwares',
        'Set-ScoopAria2Options',
        'Deploy-ScoopByGithubMirrors',
        'Confirm-GitCommand',
        'Deploy-ScoopByGitee',
        'Add-ScoopBuckets',
        'Deploy-ScoopAppsPath',
        'Update-ScoopMirror',
        'Set-ScoopVersion',
        'Get-SelectedMirror',
        'Get-GithubMirrorPrefix',
        'Get-RepoRawUrl',
        'Deploy-ScoopForCNUser',
        'Deploy-ScoopApps',
        'Deploy-ScoopStartMenuAppsStarter',
        'Update-GithubHosts',
        'Deploy-GithubHostsAutoUpdater',
        'Deploy-LinksFromFile',
        'Deploy-Python',
        'Backup-IfNeed',
        'Deploy-Userconfig',
        'Deploy-UserConfigFromAnotherDrive',
        'Deploy-CppVscodeThere',
        'Deploy-FirewallByNetsh',
        'Deploy-PipConfig',
        'Deploy-UvConfig',
        'Deploy-AndroidStudio_depends',
        'Confirm-AdminPermission',
        'Deploy-Typora',
        'Deploy-RestartExplorerHotkey',
        'Enable-NetworkDiscoveryAndSharing',
        'New-SmbSharingReadme',
        'Deploy-SmbSharing',
        'Disable-SmbSharingUserLogonLocallyRight',
        'Deploy-GitConfig',
        'Deploy-VsCodeSettings_depends',
        'Deploy-WtSettings',
        'Deploy-StartupServices',
        'Deploy-StartupTasks',
        'Deploy-PortableGitPathEnvVar',
        'Deploy-EnvsByPwsh',
        'Deploy-MiniforgeConfig',
        'Deploy-TrafficMonitor',
        'Test-PsEnvReadiness',
        'Deploy-CompletionStack',
        'Update-CxxuPsModules'
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
