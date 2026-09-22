@{
    RootModule = 'Basic.psm1'
    ModuleVersion = '1.0.4'
    GUID = '0cabeabe-fb5c-41a4-b90c-f3d011dec739'
    Author = 'cxxu'
    Description = 'General utilities and query: Get-ModuleByCxxu/Get-ContentUTF8'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Restart-TrafficMonitor',
        'Get-Fonts',
        'wiki2latex',
        'ty2latex',
        'wechat_second',
        'startup_register',
        'wechat_multiple',
        'downkyi_clickToLaunch',
        'remove_colors_icons',
        'ps_group',
        'rpg',
        'ord',
        'chr',
        'BT',
        'colorPicker_vscode',
        'getAssembler_att',
        'getAssemble_intel',
        'Start-ProgramInSandboxie',
        'Set-WindowsUpdate',
        'Get-DateTimeNumber',
        'Get-DateTime',
        'Get-Time',
        'u20',
        'Get-WslInfo',
        'Get-EdgeUpdaterPath',
        'Set-EdgeUpdater',
        'Test-MainPC',
        'Set-DoubleOwnerOfRepos',
        'Test-CxxuComputer',
        'reboot',
        'timer_tips',
        'Test-IsAdministrator',
        'Test-AdminPermission',
        'Test-AdminPermission2',
        'jupyter2markdown',
        'Write-SeparatorLine',
        'gcmw',
        'clock',
        'javav',
        'EnvironmentRequireTips',
        'Restart-Explorer',
        'Restart-Process',
        'time_show',
        'btm_cxxu',
        'Get-ModuleByCxxu',
        'Get-ContentUTF8'
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
