@{
    RootModule = 'Deploy.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'a92ff02b-239e-4ead-bdf3-ba336326d073'
    Author = 'cxxu'
    Description = 'New-machine final setup: mirrors/hosts/firewall/SMB/startup/env check'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Confirm-GitCommand',
        'Get-SelectedMirror',
        'Get-GithubMirrorPrefix',
        'Get-RepoRawUrl',
        'Update-GithubHosts',
        'Deploy-GithubHostsAutoUpdater',
        'Deploy-LinksFromFile',
        'Backup-IfNeed',
        'Deploy-Userconfig',
        'Deploy-UserConfigFromAnotherDrive',
        'Deploy-FirewallByNetsh',
        'Confirm-AdminPermission',
        'Deploy-RestartExplorerHotkey',
        'Enable-NetworkDiscoveryAndSharing',
        'New-SmbSharingReadme',
        'Deploy-SmbSharing',
        'Disable-SmbSharingUserLogonLocallyRight',
        'Deploy-StartupServices',
        'Deploy-StartupTasks',
        'Deploy-PortableGitPathEnvVar',
        'Deploy-EnvsByPwsh',
        'Deploy-TrafficMonitor',
        'Test-PsEnvReadiness',
        'doctor'
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
