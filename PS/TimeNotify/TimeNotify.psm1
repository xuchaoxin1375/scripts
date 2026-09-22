<#
TimeNotify 模块:定时提醒(Toast 通知/整点报时/消息上报)。
从 TaskSchdPwsh.psm1 迁入: TaskSchdPwsh 只留计划任务触发与守护进程,提醒类归此模块;
调用方命令名不变(自动发现同名模块),Start-Trigger 等跨模块调用走自动加载。
#>

function New-TimeNotification
{
    <# 
    .SYNOPSIS
    弹出一条提示当前时间和日期的系统通知(Toast)
    .DESCRIPTION
    借助第三方模块BurnToast来实现弹窗通知
    #>
    [CmdletBinding()]
    param (
    )
    # 按需导入模块(重复导入也没有关系)
    Import-Module BurntToast
    
    # 弹出Toast报时
    New-BurntToastNotification -Text "Clock:$(Get-Time)", "$(Get-Date)"
        
}
function New-TimeNotificationRobust
{
    param (
    )
    # 检查当前环境是否导入了burnttoast模块
    if (!(Get-Module Burntoast ))
    {
        # 当前环境没有导入burnttoast模块,尝试导入(如果导入失败,则因该还没有安装该模块)
        $res = Import-Module BurntToast -ErrorAction 'SilentlyContinue' -PassThru
        # 检查是否已经安装了burnttoast模块
        if (! $res)
        {
            # 模块导入失败,可能没有安装burnttoast,询问用户是否安装它
            $continue = Confirm-UserContinue -Description 'The needed module BurntToast is not installed. Do you want to install it?'
            if ($continue)
            {
                Install-Module -Name BurntToast
                Import-Module BurntToast
            }
        }
 
        # 弹出Toast报时
        New-BurntToastNotification -Text "Clock:$(Get-Time)", "$(Get-Date)"
    }
    
}

function Start-TimeAnnouncer
{
    <# 
.SYNOPSIS
整点报时或者半点报时或者指定分钟报时
立即报时
定点报时
倒计时报时

.description
可以配合Start-ProcessHidden来使用,实现后台运行此任务
需要系统安装了TTS引擎(一般原版系统都有自带几个可用引擎,而精简版系统可能没有可用引擎,那么语音播报就不可用)

.EXAMPLE
#整点与半点时报时
Start-ProcessHidden -scriptBlock {Start-TimeAnnouncer}
.EXAMPLE
#创建一个独立的后台powershell进程进行报时活动;指定在每个小时的20,21分时进行报时,其他分钟不报时
PS C:\exes> Start-ProcessHidden -scriptBlock {Start-TimeAnnouncer -TickMins 20,21 }

 NPM(K)    PM(M)      WS(M)     CPU(s)      Id  SI ProcessName
 ------    -----      -----     ------      --  -- -----------
      6     0.42       2.61       0.02   19044   1 pwsh
.EXAMPLE
#临时运行,不需要保持后台运行,则直接调用,这里指定输出日志;指定处于28分时,每三秒请求一次报时
#由于是前台执行(当前会话会被占用),按下Ctrl+C结束此任务
PS C:\Users\cxxu\Desktop> Start-TimeAnnouncer -TickMins 28 -Verbose -TryReportInterval 3 -CheckInterval 1 -showWinodw
.EXAMPLE
查找后台运行的报时任务:

PS C:\Users\cxxu\Desktop> ps pwsh|select id,CommandLine|sls Start-TimeAnnouncer

@{Id=19044; CommandLine="C:\Program Files\PowerShell\7\pwsh.exe" -Command Start-TimeAnnouncer -TickMins 20,21 }
@{Id=26924; CommandLine="C:\Program Files\PowerShell\7\pwsh.exe" -Command Start-TimeAnnouncer}

.EXAMPLE
指定时间报时;整分钟刚好报时,可以指定这一组轮询组合 -TryReportInterval 60 -CheckInterval 1

PS C:\Users\cxxu\Desktop> Start-TimeAnnouncer -InHour24Format 21 -InMinute 49 -Verbose -TryReportInterval 60 -CheckInterval 1
VERBOSE:  21:48:34
.....
....
VERBOSE:  21:48:58
VERBOSE:  21:48:59
Reporting time:21:49:00

Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
--     ----            -------------   -----         -----------     --------             -------
5      Job5            BackgroundJob   Running       True            localhost            New-TextToSpeech -messag…

.EXAMPLE
#指定语音引擎报时(倒计时),同时弹出一个窗口,显示结束时间
可用的引擎可以自己安装语音包获取
例如:PS C:\repos\scripts> Get-SpeechVoiceOptions #自定义函数,另见它文
Microsoft David Desktop - English (United States)
Microsoft Zira Desktop - English (United States)
Microsoft Huihui Desktop - Chinese (Simplified)
Microsoft Tracy Desktop - Chinese(Traditional, HongKong SAR)
Microsoft Hanhan Desktop - Chinese (Taiwan)
# 倒计时3秒后报时,同时弹出一个窗口,3秒后关闭;这里语音报时和显示窗口都是会阻塞当前绘画的调用,因此这里设法把他们送到后台作业去执行
PS C:\repos\scripts> start-timeAnnouncer -Timer 3 -Verbose -ShowWindow -Duration 3 -DesktopVoice Zira
Reporting timer Start From:22:51:47
waiting...
Reporting time:3 seconds  Passed!

Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
--     ----            -------------   -----         -----------     --------             -------
13     Job13           BackgroundJob   Running       True            localhost            New-TextToSpeech -messag…
15     Job15           BackgroundJob   Running       True            localhost            Show-Message -Message " …
Reporting timer end at:22:51:50

#>
    # 定义 TTS 报时函数
    [CmdletBinding(DefaultParameterSetName = 'DefaultMode')]
    
    param (
        # 自定义报时(分钟)
        
        [parameter(ParameterSetName = 'MinsOnly')]
        $TickMins = @(),
        # 设定闹钟
        # [parameter(ParameterSetName = 'Alarm')]
        # $InHour24Format ,
        # [parameter(ParameterSetName = 'Alarm')]
        # $InMinute ,
        [parameter(ParameterSetName = 'Alarm')]
        $AlarmTime,
        #闹钟精确到秒
        [parameter(ParameterSetName = 'Alarm')]
        [switch]$AlarmTimeWithSecond,
        #倒计时报时(秒),例如输入4.5*60，表示倒计时4分钟半后倒计时报时(闹钟)
        [parameter(ParameterSetName = 'Timer')]
        $Timer = 0,


        [parameter(ParameterSetName = 'DefaultMode')]
        [switch]$Default,
        
        [parameter(ParameterSetName = 'Now')]
        [switch]$Now,
        # 间隔报时时间（秒）
        [parameter(ParameterSetName = 'Repeate')]
        $RepeateInterval = 0,
        [switch]$ShowWindow,
        [switch]$ReadSecond,
        # 窗口显示维持时间
        $Duration = 2,
        [Alias('Toast', 'Notification')][switch]$ToastNotification,
        # 可以自行查找系统安装的TTS引擎,参考Microsoft官方文档
        $DesktopVoice = 'Huihui', #常见的还有Zira(英文引擎)等,Huihui是中文引擎

        [ValidateSet('Chinese', 'Default')][string]    
        $Language = 'Chinese',

        # 等待一分钟，以避免重复报时
        #设置每多秒请求一次报时(不超过60),如果设置为0,表示不启用此参数
        # 否则建议配合$CheckInterval=1来使用,否则可能漏报,调试时可以设置的短一些,比如5秒,甚至是3秒(也不易过小)
        [ValidateRange(1, 60)][int]
        $TryReportInterval = 0,

        # 本函数采用定时检查时分秒的方式，这里控制每多少秒检查一下时间如果是调试报时,可以将60改为1等小的数试试报时效果)
        # 当检查间隔为1时是最密集的检查,再小则是浪费;
        # 如果启用RepeateInterval(取大于0的值),那么CheckInterval应该服从于$RepeateInterval
        $CheckInterval = 60
    )
    # 守护进程用不上 predictor:经 -Command 起来的后台会话关掉它(交互会话手动调本函数不受影响,此时命令行无 -Command)
    if (@([Environment]::GetCommandLineArgs()) -match '^-(?i:c|command)$')
    {
        $env:PsPredictor = 'False'
    }
    # function New-TextToSpeech{}
    $PSBoundParameters
    # 默认要报的消息是时间,(那么仅需要报出时:分(而不报秒))
    $messageIsTime = $true
    function New-MessageReportInner
    {
        <# 
        .SYNOPSIS
        这里是对外部New-MessageReport的一个简单封装
        .DESCRIPTION
        设置了默认的行为,在被调用时自动引用外部函数的相应变量的值,而不需要手动传参,只需要传递必要的参数或者设置相关变量即可
        .NOTES
        此内部函数一般不设置参数,直接引用外部参数,如果需要更改,则修改外部参数即可
        如果不希望影响到外部参数,那么可以考虑设立对应的参数
        #>
        param (
            # [switch]$MessageIsTime
            $message = $message,
            [switch]$ReadSecond 
        )
        New-MessageReport -message $message -MessageIsTime:$messageIsTime -ReadSecond:$ReadSecond -ToastNotification:$ToastNotification  
        # New-TextToSpeech -message $message -DesktopVoice $DesktopVoice 
        
    }

    $TickMins = @($TickMins)
    # 处理定点报时:采用轮询的方式,为了判断当前时间是否应该报时,需要放置在循环中,每隔一段时间检查一次(比如1秒)
    while ($true)
    {
        # $currentHour = (Get-Date).Hour
        # 关键是分钟,是否是30分(半点)还是0分 (整点)
        $currentMinute = (Get-Date).Minute
        $currentSecond = (Get-Date).Second
        
        # $TimeRaw = Get-Time
        $message = Get-Time
        # $Time = Get-Time -SetSecondsToZero
        
        $report = $false
        
        # 检查是否要播报当前时间
        if ($Now)
        {
            New-MessageReportInner 
            return
        }
        elseif ($RepeateInterval -and $PSCmdlet.ParameterSetName -eq 'Repeate' )
        {
            # 这里有2中方案,一种是在这里内部启动自己的循环,执行间隔时间报时
            # 另一种是公用外部循环

            ## plan1
            # while (1)
            # {

            #     Start-Sleep $RepeateInterval
            #     New-MessageReport
            # }
            ## plan2
            $CheckInterval = $RepeateInterval
            $report = $true
        }
        # 是否处于倒计时模式
        elseif ($PSCmdlet.ParameterSetName -eq 'Timer' )
        {
    
            Write-Host "Reporting timer Start From:$TimeRaw" -ForegroundColor Green
            Write-Host 'waiting...'
            # 直接倒计时$timer秒即可
            Start-Sleep $Timer
            # $report = $true
            $msg_cn = "倒计时${Timer}秒结束"
            $msg_en = "Countdown ${Timer} seconds end"
            # $DesktopVoice
            if ($Language -eq 'Chinese')
            {
                $message = $msg_cn
            }
            else
            {
                $message = $msg_en
            }
            New-MessageReportInner -message $message -messageIsTime:$false

            Write-Host "Reporting timer end at:$(Get-Time)" -ForegroundColor Red
            # 闹钟报时后直接return(但是会导致Start-ProcessHidden中运行来不及报时就退出了,也就是说后台起一个新进程中如果再使用start-job就要考虑异步任务能否来得及执行(通常来不及),可以考虑用-NoExit不主动退出后台shell)
            return
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Alarm')
        {
            $AlarmTime = [datetime]$AlarmTime 
            Write-Host "Reporting alarm at:$AlarmTime" -ForegroundColor Magenta
            $CurrentDate = Get-Date
            Write-Verbose "$AlarmTime -eq $CurrentDate"
            # $delta = ($AlarmTime - $CurrentDate)
            # $delta = [math]::abs($delta.TotalSeconds)
            
            # $shouldReport = $AlarmTime -eq $CurrentDate
            # if ($delta -lt 1)
            # {
            #     $shouldReport = $true
            # }
            $shouldReport = $AlarmTime.Hour -eq $CurrentDate.Hour -and $AlarmTime.Minute -eq $CurrentDate.Minute 
            if ($AlarmTimeWithSecond)
            {

                $shouldReport = $shouldReport -and $AlarmTime.Second -eq $CurrentDate.Second
                $ReadSecond = $true
            }
            else
            {
                $ReadSecond = $false
            }
            
            if ($shouldReport )
            {
                Write-Host 'readsecond:'$ReadSecond
                Write-Host 'Reporting Time...'
                New-MessageReportInner -ReadSecond:$ReadSecond
                return
                # $shouldReport = $false #防止重复报时
                # Start-Sleep 1
            }
            else
            {
                Write-Host 'Not Time...'
            }

            # if ($currentHour -eq $InHour24Format -and $currentMinute -eq $InMinute)
            # {
            #     # $report = $true
            #     New-MessageReportInner
            #     return 
            # }

        }
        # 下面的情况设置报时标记,统一报时即可
        elseif ($PSCmdlet.ParameterSetName -eq 'MinsOnly')
        {
            if (
                $TickMins -contains $currentMinute 
            )
            {
                # Announce time
                $report = $true
            }
        }
        elseif (
            $currentMinute -eq 0 -or
            $currentMinute -eq 30 
        )
        {
            $report = $true
        }
        # 统一根据需要报时
      
             
    

        # $currentSecond -eq 0
        Write-Verbose " $(Get-Time)"

        if ($TryReportInterval)
        {
            # 提高报时频率用的,主要用于调试(一分钟内会报时几次)
            if ( $currentSecond % $TryReportInterval -eq 0 )
            {
                # New-MessageReport # 报时
                # 这里用输出文字日志来检查报告时机
                Write-Host "$DesktopVoice $(Get-Time)" -ForegroundColor Cyan
                # 调用报时函数
                if ($report)
                {
                    New-MessageReportInner
            
                }
            }
        }
        else
        {
            if ($report)
            {
                New-MessageReportInner
            
            }
        }
        # Start-Sleep -Seconds 60
        Start-Sleep -Seconds $CheckInterval

    }
}
function Get-TimeHMFormatStr
{
    <# 
    .SYNOPSIS
    对输入的时间字符串转换为DataTime类型,并且将其转换为HH:mm的格式,方便中文语音引擎播报时间
    .DESCRIPTION
    如果时间字符串无效，返回原字符串,并给出警告
    #>
    param (
        $TimeStr
    )
    # [datetime]$TimeStr
    $Time = $TimeStr -as [datetime]
    if ($Time)
    {
        return $Time.ToString('HH:mm')
    }
    else
    {

        Write-Error "[ $TimeStr ] is not a valid time string"

        return $TimeStr
    }
}
function New-MessageReport
{
    <# 
    .SYNOPSIS
    
    检查时间并在指定分钟时报时
    这里是内部函数,参数请定义在外部函数的param()中
    .example
    使用正确的语音引擎,例如Huihui,中文简体语音引擎,可以正确读出诸如19:30这样的时间(十九点三十分)
            #>
    #如果$TickMins不为空,则只报定义于$TickMins中指定分钟,包括整点和半点都不搞特殊
    [CmdletBinding()]
    param(
        $message = $TimeRaw,
        $DesktopVoice = 'Huihui',
        [switch]$MessageIsTime,
        # 默认不读秒,如果设置为$true则读秒
        [switch]$ReadSecond,
        [switch]$ToastNotification,
        # 可用用msg命令创建简单的弹窗(但是需要手动确认关闭)
        [switch]$ShowWindow
    )
    $PSBoundParameters | Format-Table
    if ($MessageIsTime)
    {
        
        Write-Host "Reporting time:$message" -ForegroundColor Red
    
        if (!$ReadSecond)
        {
            # 移除秒的部分(不读秒)
            $message = Get-TimeHMFormatStr -TimeStr $message 
            Write-Verbose "message:$message"
        }

    }
    New-TextToSpeech -message $message -DesktopVoice $DesktopVoice   &  #这里使用后台执行运算符&
    # 但是注意,如果外层调用Start-TimeAnnouncer，会造成重复后台,即发生嵌套,会导致内层的后台任无法运行,比如这里的New-TextToSpeech将无法顺利执行

    if ($ShowWindow)
    {
        Show-Message -Message " $Message" -Duration $Duration   & #是否要默认后台运行?如果不启用,则需要等上一条耗时命令结束后才能显示消息框;总之,受限于powershell的后台运行机制,难以做到start-processHidden {Start-TimeAnnouncer }和Start-timeAnnouncer & 两列调用都完美;这里主要用Start-ProcessHidden来包装使其具有独立后台进程,所以启用&符
    }
    if ($ToastNotification)
    {
        New-TimeNotification -Verbose:$false #这里就不要使用verbose了,强制指定Verbose:$false,输出内容太多我们不关心的
    }

}  

