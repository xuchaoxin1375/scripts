@{
    RootModule = 'TaskSchdPwsh.psm1'
    ModuleVersion = '1.0.4'
    GUID = '758bfff9-28e1-4be6-a851-7226541ec5fa'
    Author = 'cxxu'
    Description = '计划任务触发与守护进程:定时触发/后台守护/隐藏启动'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Start-ScriptWhenIntervalEnough',
        'Start-PeriodlyDaemon',
        'Stop-LastUpdateDaemon',
        'Get-LastUpdateTimeDemo',
        'Get-LastUpdateMemoryUseCached',
        'Start-ProcessHidden',
        'Start-PwshTasks',
        'Start-Trigger',
        'Start-SimpleScheduledTaskBasedTime'
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
