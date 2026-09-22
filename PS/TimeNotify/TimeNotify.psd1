@{
    RootModule = 'TimeNotify.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'dc7349a4-63aa-493c-a983-5572db6350ef'
    Author = 'cxxu'
    Description = '定时提醒:Toast 通知/整点报时/消息上报'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'New-TimeNotification',
        'New-TimeNotificationRobust',
        'Start-TimeAnnouncer',
        'Get-TimeHMFormatStr',
        'New-MessageReport'
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
