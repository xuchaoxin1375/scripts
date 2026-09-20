@{
    RootModule = 'Tools.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'edfc2706-8431-43b4-91a4-d9ce76f52857'
    Author = 'cxxu'
    Description = 'Miscellaneous daily tools (network, text, system)'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-PSConsoleHostHistory',
        'Get-CxxuPsModuleVersion',
        'Test-CommandAvailability',
        'Start-SleepWithProgress',
        'Set-OpenWithVscode',
        'Get-RepositoryVersion',
        'Set-Defender',
        'Set-ExplorerSoftwareIcons',
        'pow',
        'Set-ScreenResolutionAndOrientationAntiwiseClock',
        'Get-MsysSourceScript',
        'Set-CondaSource',
        'Deploy-WindowsActivation',
        'Get-BeijingTime',
        'Enable-WindowsUpdateByDelay',
        'Disable-WindowsWidgets',
        'Disable-WindowsUpdateByDelay',
        'Get-BootEntries',
        'Rename-ComputerMac',
        'Get-WindowsVersionInfoOnDrive',
        'Restart-OS',
        'Set-TaskBarTime',
        'Sync-SystemTime',
        'Update-SystemTime'
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
