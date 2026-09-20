@{
    RootModule = 'TaskSchdPwsh.psm1'
    ModuleVersion = '1.0.4'
    GUID = '758bfff9-28e1-4be6-a851-7226541ec5fa'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: TaskSchdPwsh'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Start-ScriptWhenIntervalEnough',
        'Start-PeriodlyDaemon',
        'Stop-LastUpdateDaemon',
        'Get-LastUpdateTimeDemo',
        'Get-LastUpdateMemoryUseCached',
        'Start-ProcessHidden',
        'Start-PwshTasks',
        'New-TimeNotification',
        'New-TimeNotificationRobust',
        'Start-TimeAnnouncer',
        'Get-TimeHMFormatStr',
        'New-MessageReport',
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
