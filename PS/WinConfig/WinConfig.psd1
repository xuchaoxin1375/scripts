@{
    RootModule = 'WinConfig.psm1'
    ModuleVersion = '1.0.4'
    GUID = '3d558b37-d0ba-4f9d-a754-29eb385f47fd'
    Author = 'cxxu'
    Description = 'Windows 本机配置开关:Defender/小组件/更新/任务栏/时间同步/激活/分辨率'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Set-Defender',
        'Set-ExplorerSoftwareIcons',
        'Set-ScreenResolutionAndOrientationAntiwiseClock',
        'Deploy-WindowsActivation',
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
