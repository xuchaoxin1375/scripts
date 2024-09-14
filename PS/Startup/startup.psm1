
<# 
# 为了更快的执行开机自启动脚本的执行速度,请在$startup_user目录内创建startup_basic.lnk,并且设置参数为如下
# powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\repos\scripts\startup\startup_basic.ps1"
#这样就不会加载不必要的配置,从而快速完成任务
#可以选择隐藏powershell窗口静默执行:使用选项-WindowStyle Hidden
# $scripts = 'C:\repos\scripts'

#导入基本的powershell环境变量和字符串
# Update-PwshVars
# Set-PwshAlias 
#导入常用命令别名(会占用若干秒的时间)
# 日志:记录当前时间
# "test:$(Get-Date)"> "$scripts\startup\log\log"
 #>

function Start-StartupTasks
{

    <# 
    .SYNOPSIS
    自动执行开机启动任务
    .DESCRIPTION
    取别名时如果直接用startup,有和其他startup脚本发生潜地冲突
    如果发生冲突,直接调用本函数(原名)而不是别名调用
     #>
    param(
        # 开机启动结束后是否要暂停退出shell,默认会退出(如果是在shell内调用,则始终不会自动退出)
        [switch]$Pause,
        #配置几秒后退出shell(单位:秒)
        [int]$Interval = 2
    )
    # 为了使开机自启的脚本能够正常执行(使用别名唤醒软件和服务,需要初始化pwsh)
    init -NoNewPwsh 
    #在初始化非MainPC时,从远程仓库拉去内容后需要重新运行初始化函数
    
    #路径变量
    # $scriptRoot = Resolve-Path $PSScriptRoot
    # $log_home = "$PS\startup\log"
    # $MapLog = "$scripts\startup\log\MapLog.txt"
    #开机启动日志文件
    # $log_file = "$log_home\log.txt"
    
    #如果当前机器不是MainPC,则拉取主PC的blogs,Scripts,configs仓库
    Update-ReposesConfigedIfNeed
    
    # 启动后台周期性执行的计划任务
    # Start-PeriodlyDaemon -WindowStyle Hidden

    Start-StartupBgProcesses

    
    Start-StartupApps -Interval $Interval
    # Start-StartupServices -Interval $Interval #单独使用计划任务来启动，可以在用户登陆前就启动服务

    # Set-Location $env:USERPROFILE
    Set-Location $desktop

}
function Start-StartupApps
{

    #启动基础常用软件(缓慢启动)👺(详情查看softwares.ps1中配置,而不要在这里直接写入启动配置)
    param (
        $Interval = 2
    )
    
    . "$PSScriptroot\softwares.ps1" -Interval $Interval
}
function Start-StartupBgProcesses
{
    # # 开机时刷新一下ip缓存(但是开机指出wifi可能会延迟一会儿才链接上,可以靠后执行它)
    #初始化或检查数据文件DataJson
    # 配置半点报时和整点报时后台进程(精简版系统可能没有可用TTS引擎,弹出一个窗口代替,或者弹出一条系统通知更好)
    Update-PwshEnvIfNotYet

    Start-ProcessHidden -scriptBlock { Start-TimeAnnouncer -ToastNotification } -PassThru
    # 后台进程维护一个ConnectionName,每隔一段时间检查一次(若发生变化则更新ConnectionName),可供其他进程快速读取ConnectionName
    Start-IpAddressUpdaterDaemon
}
function Start-IpAddressUpdaterDaemon
{
    param (
        [switch]$Force
    )
    Update-PwshEnvIfNotYet -Mode core
    Confirm-DataJson
   
    Start-Process -WindowStyle Hidden -FilePath pwsh -ArgumentList '-noe -c', " Update-NetConnectionInfo -Interval 6 -DataJson `"$DataJson`" " -PassThru
}
function Start-StartupServices
{
    param(
        $interval = 2 
    )
    . "$PSScriptroot\services.ps1" -Interval $Interval
}
function Update-ReposesConfigedIfNeed
{
   
    if (-not(Test-MainPC))
    {
        Write-Host 'This is not MainPC, pulling blogs and Scripts repository...' -ForegroundColor Yellow
        # 从云端拉取仓库更新配置
        Update-ReposesConfiged
        Start-Process pwsh -ArgumentList @(
            '-NoLogo',
            '-c', 'init'
        )
        #启动新的powershell窗口待命,如果有pull动作使得新的配置生效
        # Start-Process pwsh -WorkingDirectory $desktop 
    }
}
function Confirm-DataJson
{
    <# 
    .SYNOPSIS
    如果不存在默认的DataJson文件，就创建一个
    否则什么事也不做
    #>
    param(
        # $PassThru
    )
    if (!(Test-Path $DataJson))
    {
        $s = @{
            ConnectionName = '' ;
            IpPrompt       = ''
        }
        $s | ConvertTo-Json | Set-Content $DataJson
    }
}