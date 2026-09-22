@{
    RootModule = 'WinSys.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'b3e29f41-7c2a-4d91-9e55-3a6f0c8d21e7'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: WinSys (Windows keyboard/TTS/power controls, moved from Basic)'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-SpeechVoiceOptions',
        'New-TextToSpeech',
        'check_keyboards',
        'check_zh_keyboards',
        'remove_sogou_keyboard',
        'add_sogou_keyboard',
        'set_pinyin_default',
        'remove_en_us_keyboard',
        'add_en_us_keyboard',
        'HibernateComputer',
        'Stop-ComputerInquery',
        'SleepComputer',
        'LockScreen',
        'shutdown_timer1',
        'shutdown_timer2',
        'Stop-ComputerAfterSyncActions'
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
