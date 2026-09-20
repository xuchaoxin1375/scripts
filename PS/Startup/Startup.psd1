@{
    RootModule = 'Startup.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'c72e11e9-cfe1-4535-8913-f9260df16b2b'
    Author = 'cxxu'
    Description = 'Windows auto-start tasks, background daemons and OS version cache'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-SystemVersionCoreInfoOfWindows',
        'Get-WindowsOSVersionFromRegistry',
        'Get-windowsOSFullVersionCode',
        'Confirm-OSVersionCaption',
        'Confirm-OSVersionFullCode',
        'Confirm-EnvVarOfInfo',
        'Start-StartupTasks',
        'Start-StartupApps',
        'Start-StartupBgProcesses',
        'Start-IpAddressUpdaterDaemon',
        'Start-StartupServices',
        'Update-ReposesConfigedIfNeed'
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
