

function Start-ScriptWhenIntervalEnough
{
    <#
.SYNOPSIS
调用本函数时判断上一次调用距离现在时间是否足够大,如果足够大,则执行指定脚本或任务
.DESCRIPTION
利用相关环境变量(LastUpdateTime)判断上一次更新是在什么时候,并在间隔达到阈值(Interval)后执行一个或多个脚本
    该函数的主要作用是在每隔指定时间后执行一个或多个脚本,例如定期更新一些数据
    如果指定的脚本是一个文件的路径,则会执行该文件
    如果指定的脚本是一段PowerShell代码,则会在当前脚本的上下文中执行

.PARAMETER Interval
    指定执行间隔的时间,单位是秒

.PARAMETER Scripts
    $Scripts参数 指定要执行的脚本的路径或PowerShell代码,可以是字符串数组

.EXAMPLE
    如果距离上一次执行时间间隔大于2s,则执行C:\repos\scripts\testDir\test.ps1脚本
    PS[BAT:77%][MEM:29.58% (9.38/31.70)GB][9:13:10]
    # [~\Desktop]
    Start-ScriptWhenIntervalEnough -Interval 2 -ScriptBlock C:\repos\scripts\testDir\test.ps1

    Hello World
    Path
    ----
    C:\Users\cxxu\Desktop

.EXAMPLE
   PS[BAT:77%][MEM:30.27% (9.59/31.70)GB][9:20:23]
    # [~\Desktop]
    Start-ScriptWhenIntervalEnough -Interval 2 -ScriptBlock {pwd;pwd}

    Path
    ----
    C:\Users\cxxu\Desktop
    C:\Users\cxxu\Desktop

.EXAMPLE
    PS[BAT:77%][MEM:30.22% (9.58/31.70)GB][9:20:30]
    # [~\Desktop]
    Start-ScriptWhenIntervalEnough -Interval 2 -ScriptBlock pwd

    Path
    ----
    C:\Users\cxxu\Desktop

    如果距离上一次执行时间间隔大于2s,执行Write-Host "Hello World"和Write-Host "Hello again"两段PowerShell代码
#>
    param(
        $Interval = 5,
        $ScriptBlock = '',
        $Scripts = '',
        $LastUpdate = $LastUpdate #来自于启动powershell时初始化的时间变量(Global)
    )
    $currentTime = Get-Date
    
    # Write-Host $currentTime,($currentTime - $LastUpdate).TotalSeconds -BackgroundColor Magenta
    if ( ($currentTime - [datetime]$LastUpdate).TotalSeconds -ge $Interval)
    { 
        #debug
        if ($ScriptBlock)
        {
         
            $ScriptBlock | Invoke-Expression
        }
        elseif ($Scripts)
        {
            foreach ($script in $Scripts)
            {
                if (Test-Path $script)
                {
                    & $script
                }
                else
                {
                    $script | Invoke-Expression
                }
            }
        }
        # 更新时间记录(这里要用全局变量来广播,使得下一次访问$LastUpdate是更新的值)
        $Global:LastUpdate = Get-Date
    }
}
function Start-PeriodlyDaemon
{
 
    <# 
    .SYNOPSIS
    Run a script in the background
    Every $Interval seconds, run the script

    .DESCRIPTION
    if you use windows terminal and set the `default terminal application` to non-windows console host,
    then it will not be hidden perfacetly    
    
    $scriptPath = "$PS\TaskSchdPwsh\LastTimeUpdater.ps1"
    "-NoLogo -NonInteractive -WindowStyle $windowStyle -ExecutionPolicy Bypass -File '$($scriptPath)' -Interval 1 "
    #>
    param(
        [ValidateSet('Normal', 'Minimized', 'Maximized', 'Hidden')]$WindowStyle = 'Hidden',
        $interval = 5
    )
    # $WindowStyle = 'normal'
    $scriptPath = "$LastTimeUpdater"
    # 启动powershell窗口,并把进程信息返回(利用-PassThru参数来实现)
    # $argslist =  "-NoLogo -NonInteractive -WindowStyle $WindowStyle -ExecutionPolicy Bypass -File $($scriptPath) "  
    # write-host 'debuging!'
    # "`$env:LastUpdateLog = $LastUpdateLog" | Invoke-Expression
    # 使用环境变量来实现不同子进程(线程)shell继承父进程的变量(缺点是只能是字符串类型,但是我们可以编码处理)
    $env:LastUpdateLog = $LastUpdateLog
    $env:Interval = $Interval
    # write-host $env:LastUpdateLog,$env:Interval
    # $title = 'PWSH:update-time-periodly'
    # $titleExpression = "`$host.ui.RawUI.WindowTitle = '$title'"

    $TimeUpdater = Start-Process -FilePath pwsh -ArgumentList @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive', 
        '-WindowStyle', $WindowStyle, 
        '-ExecutionPolicy', 'Bypass', 
        '-File', $scriptPath
        # $titleExpression
    ) -PassThru 
    # 如果是-NoNewWindow,就不会新建窗口了,而在调用这个函数的shell中显示,这通常不是我们想要的

    #将进程好记录起来(保存到本地文件中,当有需要杀死时,可以读取文件中保存的进程号进行kill)
    $TimeUpdater.Id>"$TaskSchdPwsh\log\LastTimeUpdaterPid"

    return $TimeUpdater


}

function Stop-LastUpdateDaemon
{
    <# 
    .SYNOPSIS
    Stop the daemon process which update the memoryusage periodly

    .DESCRIPTION
    The function read the LastTimeUpdaterPid from the file, and stop the process
    .EXAMPLE
    #搜索相关后台进程(计算内存占用的,我将该模块放在TaskSchdPwsh路径下,所以可以用 -like '*TaskSchd*'检索)
    检索到后可以用管道符传递给stop-process进行进程结束操作
    PS[BAT:77%][MEM:36.88% (11.69/31.70)GB][20:34:13]
    # [~\Desktop]
    ps pwsh|?{$_.CommandLine -like '*TaskSchd*'}|select id,ProcessName ,CommandLine|ft -AutoSize -Wrap

    Id ProcessName CommandLine
    -- ----------- -----------
    22012 pwsh        "C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile          
                        -NonInteractive -WindowStyle Hidden -Exec
                        utionPolicy Bypass -File C:\repos\scripts\PS\TaskSchdPwsh\lastTimeUpdater.ps1
    .EXAMPLE
    ps pwsh|?{$_.CommandLine -like '*TaskSchd*'}|select id,ProcessName ,CommandLine|Stop-Process

    #>
    param (
        $PidSource = "$TaskSchdPwsh\log\LastTimeUpdaterPid"
    )
    $id = [int](Get-Content $PidSource)
    Stop-Process -Id $id
    Write-Host "Stop the daemon process $id !" -BackgroundColor Cyan
}

function Get-LastUpdateTimeDemo
{
    <# 
    .SYNOPSIS
    Deprecated!(just test function)
    Read DateTime String for the LastUpdateLog which record the last update time(Daemon)

    #>
    param(

        $SourceFile = $LastUpdateLog
    )
    $SourceFile = $LastUpdateLog
    $DateTimeStr = Get-Content $SourceFile
    Write-Host $DateTimeStr
    $LastUpdate = Get-Date -Date "$DateTimeStr" #双引号不能省略,否则可能会报错
    return $LastUpdate
}
function Get-LastUpdateMemoryUseCached
{
    param(

        $SourceFile = "$TaskSchdPwsh\log\LastUpdateMemoryUse"
    )
    # $SourceFile = $LastUpdateLog
    $res = Get-Content $SourceFile
    Write-Host $res
    $res = $res -split ';'
    $MemoryUsed = $res[0]
    $MemoryTotal = $res[1]
    return $MemoryUsed, $MemoryTotal

}

function Start-ProcessHidden
{
    <# 
    .SYNOPSIS
    在后台运行指定任务(可以是启动一个软件(一般是服务软件比较适合后台独立运行),或者运行一段命令行,或脚本块),由powershell启动
    .DESCRIPTION
    默认情况下,启动后的进程是独立的后台进程(隐藏窗口,可以通过设定WindowStyle为非hidden来显示)
    本函数启动的进程和启动者pwsh进程相互独立,启动者被杀死也不会影响后台进程
    这是和Start-Job的一个重要区别(依赖于当前powershell进程)

    如果是启动特定的软件,比如alist,chfs,aria2 rpc,那么建议使用-FilePath 来指定软件位置,然后使用-argumentList指定启动参数
    这比通过powershell间接启动会更加直接和方便

    本命令启动的进程窗口通过-WindowStyle Hidden属性隐藏(隐藏窗口,而不是最小化窗口),来达到后台运行任务的效果
    如果使用windows terminal(wt)管理shell 窗口,利用本命令启动powershell后台任务隐藏窗口后,可能会在windows terminal窗口列表中留下一个空shell选项卡
    
    .EXAMPLE
    #执行桌面上的一个日志脚本(其他内容比如说是每隔1秒钟就往log文件中写入一行时间日志)
    PS C:\Users\cxxu\Desktop> Start-ProcessHidden -File .\LogTime.ps1
    .EXAMPLE
    #Scriptblock参数支持接受字符串包裹的命令行脚本块

    Start-ProcessHidden -scriptBlock 'start-TimeAnnouncer -TickMins 35 -Verbose'
    Start-ProcessHidden -scriptBlock {start-TimeAnnouncer -TickMins 33 -Verbose}

    .EXAMPLE
    #利用Scriptblock参数来执行指定的命令行脚本块,而不是执行指定的脚本文件
    PS C:\Users\cxxu\Desktop> Start-ProcessHidden -scriptBlock {
    >> function Write-TimeToLog
    >> {
    >>     param (
    >>
    >>     )
    >>     # 获取当前时间
    >>     $currentTime = Get-Date -Format 'HH:mm:ss'
    >>
    >>     # 构建日志文件路径
    >>     $logFilePath = Join-Path $([Environment]::GetFolderPath('Desktop')) 'log.txt'
    >>
    >>     # 追加当前时间到日志文件
    >>     Add-Content -Path $logFilePath -Value $currentTime
    >>
    >> }
    >> while (1)
    >>  {
    >>     Write-Host 'writing...'
    >>     Write-TimeToLog
    >>     Start-Sleep 1
    >>  }
    >> }

    NPM(K)    PM(M)      WS(M)     CPU(s)      Id  SI ProcessName
    ------    -----      -----     ------      --  -- -----------
        6     0.45       2.64       0.02   20416   1 pwsh


    PS [C:\Users\cxxu\Desktop]> cat .\log.txt -Wait
    22:31:43
    22:31:44
    22:31:45
    22:31:46
    22:31:47
    22:31:48
    ...

    .EXAMPLE
    # 启动chfs后台任务(注意chfs严格检查参数的大小写,例如-file不能写成-File,否则会报错,这是一个linux风格的命令行工具)
    Start-ProcessHidden -FilePath C:\exes\chfs\chfs -ArgumentList "-file C:\exes\chfs\chfs.ini" #-file 不能作-File
    .EXAMPLE
    # 启动aria2c rpc后台服务
    $configs="C:\repos\configs"
    Start-ProcessHidden -FilePath C:\exes\aria2\aria2c.exe -ArgumentList "--conf-path=$configs\aria2.conf"

    #>
    [CmdletBinding()]
    param (
        # executable file Path(like the -FilePath parameter of Start-Process)
        
        [Parameter( Mandatory = $true, ParameterSetName = 'FilePath')]
        # [Parameter( Mandatory = $false, ParameterSetName = 'PwshScriptBlock')]
        [Alias('File')]$FilePath,

        [Parameter(  ParameterSetName = 'FilePath')]
        $ArgumentList,

        # 使用ScriptBlock参数时,默认使用的程序是pwsh,而不需要$FilePath指定可执行程序
        [Parameter( ParameterSetName = 'PwshScriptBlock')]
        $scriptBlock,

        [validateset('Normal', 'Minimized', 'Maximized', 'Hidden')]$WindowStyle = 'Hidden',

        [switch]$PassThru
        # [switch]$Verbose
        # [Parameter(ParameterSetName = 'PwshScriptFile')]
        # $scriptFile
    )
    # 检查参数
    if ($VerbosePreference) # if($verbosePreference -eq 'continue')
    {
        # 特殊对象无法使用write-verbose直接输出，这里利用$verbose变量来判断,然后用其他方式输出
        Write-Host $PSBoundParameters
        # 这种对象的输出可能会影响到其他对象的输出,应该是powershell的bug
    }

    if ($PSCmdlet.ParameterSetName -eq 'FilePath')
    {
        $p = Start-Process -WindowStyle $WindowStyle -FilePath $FilePath -ArgumentList $ArgumentList -PassThru:$PassThru
        Write-Verbose "Start-Process -WindowStyle $WindowStyle -FilePath $FilePath -ArgumentList $ArgumentList -PassThru:$PassThru"
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'PwshScriptBlock')
    {
        # $p = Start-Process -WindowStyle Hidden -FilePath pwsh.exe -ArgumentList '-noe', '-Command', ([scriptblock]::Create($scriptBlock.ToString()) -join "`n") -PassThru
     
        $p = Start-Process -WindowStyle $WindowStyle -FilePath pwsh.exe -ArgumentList '-noe', '-Command', $scriptBlock -PassThru:$PassThru
    }

    return $p
}

function Start-PwshTasks
{
    <#
.SYNOPSIS
    在新的独立 PowerShell 进程中执行后台任务。

.DESCRIPTION
    此函数创建一个新的 PowerShell 进程，通过 `Start-Process` 运行指定的脚本或命令。
    该进程与当前会话分离，独立执行，不会阻塞当前 PowerShell 会话的执行。
    可用于执行需要后台运行的任务，如长时间运行的脚本、批处理任务等。

.PARAMETER ScriptBlock
    需要在后台执行的 PowerShell 脚本块。如果同时指定了 `Command` 参数，则 `ScriptBlock` 将被忽略。

.PARAMETER Command
    需要在后台执行的命令字符串。如果提供了此参数，则将忽略 `ScriptBlock`。

.PARAMETER WorkingDirectory
    指定新进程的工作目录。默认为当前目录。

.PARAMETER NoNewWindow
    如果指定此参数，后台进程将在当前控制台窗口中运行，而不是新窗口中。

.PARAMETER PassThru
    如果指定此参数，函数将返回启动的进程对象。否则，不返回任何值。

.PARAMETER ArgumentList
    传递给后台进程的其他参数。

.EXAMPLE
    Start-PwshTasks -ScriptBlock {
        Get-Process | Out-File "C:\temp\processes.txt"
    }

    在后台运行 `Get-Process` 并将输出保存到指定的文件中。

.EXAMPLE
    Start-PwshTasks -Command "Get-EventLog -LogName System | Export-Csv 'C:\temp\SystemLog.csv'"

    在后台执行指定的命令字符串，并将系统日志导出到 CSV 文件。

.EXAMPLE
    $process = Start-PwshTasks -ScriptBlock {
        Start-Sleep -Seconds 10
    } -PassThru

    通过 `PassThru` 参数获取启动的进程对象，并在脚本中使用它。

.NOTES
    此函数是通过 `Start-Process` 创建的，因此它不会阻塞当前会话的执行。
    在命令或脚本块执行期间，用户仍然可以使用当前的 PowerShell 会话。
#>

    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Position = 1)]
        [string]$Command,

        [Parameter(Position = 2)]
        [string]$WorkingDirectory = (Get-Location).Path,

        [switch]$NoNewWindow,

        [validateset('Normal', 'Minimized', 'Maximized', 'Hidden')]$WindowStyle = 'Hidden',
        
        [switch]$PassThru,

        [Parameter(Position = 3)]
        [string[]]$ArgumentList
    )

    # 确定要执行的脚本或命令
    if ($Command)
    {
        $commandToExecute = $Command
    }
    elseif ($ScriptBlock)
    {
        $commandToExecute = $ScriptBlock.ToString()
    }
    else
    {
        throw '必须提供 ScriptBlock 或 Command 参数。'
    }

    # 准备 Start-Process 的参数
    $startProcessParams = @{
        FilePath         = 'pwsh.exe'
        ArgumentList     = " -NoExit -Command `"& { $commandToExecute }`""
        WorkingDirectory = $WorkingDirectory
        WindowStyle      = $WindowStyle
    }
    # 参数扩展
    # if ($NoNewWindow)
    # {
    #     $startProcessParams.NoNewWindow = $true
    # }
    if ($ArgumentList)
    {
        $startProcessParams.ArgumentList += ' ' + ($ArgumentList -join ' ')
    }
    # 检查start-process的参数
    $startProcessParams
    # 启动进程
    $process = Start-Process @startProcessParams

    # 如果指定了 PassThru 参数，则返回进程对象
    if ($PassThru)
    {
        return $process
    }
}


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
function New-TimeNotification-Robust
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
        $currentHour = (Get-Date).Hour
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
                Write-Host "$DesktopVoice $(Get-Time)" -ForegroundColor Blue
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

function Start-Trigger
{
    <# 
    .SYNOPSIS
    当它被调用时,可以给用户一些反馈信息,可以用来提示用户后台任务启动了,
 可以指定一些参数指定提示方式,比如弹出一个系统通知
 
    #>
    #如果$TickMins不为空,则只报定义于$TickMins中指定分钟,包括整点和半点都不搞特殊
    param(
        $time = '',
        $message = $TimeRaw,
        [switch]$ToastNotification,
        [switch]$ShowWindow
    )
       
    if (! $time)
    {
        $time = $(Get-Time)
    }
    if (! $message)
    {
        $message = $(Get-Time)
    }
    Write-Host "Reporting time:$message" -ForegroundColor Red
        

    if ($ShowWindow)
    {
        Show-Message -Message " $Message" -Duration $Duration   & #是否要默认后台运行?如果不启用,则需要等上一条耗时命令结束后才能显示消息框;总之,受限于powershell的后台运行机制,难以做到start-processHidden {Start-TimeAnnouncer }和Start-timeAnnouncer & 两列调用都完美;这里主要用Start-ProcessHidden来包装使其具有独立后台进程,所以启用&符
    }
    if ($ToastNotification)
    {
        New-TimeNotification -Verbose:$false #这里就不要使用verbose了,输出内容太多我们不关心的
    }

}

function Start-SimpleScheduledTaskBasedTime
{
    <# 
.SYNOPSIS
整点执行任务或者半点执行任务或者指定分钟执行任务
立即执行任务
定点执行任务
倒计时执行任务


.Description
可以配合Start-ProcessHidden来使用,实现后台运行此任务
通过制定$Scriptblock参数来执行任务
例如启动某个软件,执行一个维护脚本都行
默认情况下,每半个小时执行一次,可以指定更多方式,就像闹钟一样设定启动时间
你可以用 Start-process -windowstyle hidden 来创建独立进程,实现后台运行脚本
.NOTES
最初我只是想创建一个能够定点报时的powershell脚本,后来增加了倒计时功能,按间隔报时的功能
最后我想既然能够定时报时,不放改造一下,让其可以实现定时执行特定任务
现在我抽出这个函数,允许用户指定一个powershell脚本块,这样可以定时执行任务,有点像系统的计划任务一样(简化版)


.EXAMPLE
# 每隔2秒钟,执行cmd /c dir C:\(查看C盘目录内容)
#这是个无聊的需求,但是可以说明这个函数的基本用法
 Start-SimpleScheduledTaskByPwsh -Scriptblock {cmd /c dir C:\ } -RepeateInterval 2
.EXAMPLE
 Start-SimpleScheduledTaskByPwsh -Scriptblock {Start-Trigger -ToastNotification } -Now 
 这里调用一个powershell函数Start-Trigger(我自定义的函数,当它被调用时,可以给用户一些反馈信息,可以用来提示用户后台任务启动了,
 可以指定一些参数指定提示方式,比如弹出一个系统通知)
 这里利用了-Now参数,用来检查一次调用后会出现什么效果
.EXAMPLE
语音报时
PS C:\Users\cxxu> Start-SimpleScheduledTaskBasedTime -Scriptblock {New-TextToSpeech -Message (Get-Time -SetSecondsToZero) -Voice Huihui}
Start-SimpleScheduledTaskByPwsh...

Key         Value
---         -----
Scriptblock New-TextToSpeech -Message (Get-Time -SetSecondsToZero) -Voice Huihui

running & waiting ...

#>
    # 定义 TTS 执行任务函数
    [CmdletBinding(DefaultParameterSetName = 'DefaultMode')]
    
    param (
        # 自定义执行任务(分钟)
        
        [parameter(ParameterSetName = 'MinsOnly')]
        $TickMins = @(),
        # 
        [parameter(ParameterSetName = 'Alarm')]
        $InHour24Format ,
        [parameter(ParameterSetName = 'Alarm')]
        $InMinute ,

        #倒计时执行任务(秒),例如输入4.5*60，表示倒计时4分钟半后倒计时执行任务(闹钟)
        [parameter(ParameterSetName = 'Timer')]
        $Timer = 0,


        [parameter(ParameterSetName = 'DefaultMode')]
        [switch]$Default,
        
        [parameter(ParameterSetName = 'Now')]
        [switch]$Now,
        # 间隔执行任务时间（秒）
        [parameter(ParameterSetName = 'Repeate')]
        $RepeateInterval = 0,
        [switch]$ShowWindow,
        # 窗口显示维持时间
        $Duration = 2,
        [Alias('Toast', 'Notification')][switch]$ToastNotification,
        
        $Scriptblock,
        # 可以自行查找系统安装的TTS引擎,参考Microsoft官方文档
        # [ValidateSet('Chinese', 'Default')][string]    
        # $Language = 'Default',

        # 等待一分钟，以避免重复执行任务
        #设置每多秒请求一次执行任务(不超过60),如果设置为0,表示不启用此参数
        # 否则建议配合$CheckInterval=1来使用,否则可能漏报,调试时可以设置的短一些,比如5秒,甚至是3秒(也不易过小)
        [ValidateRange(1, 60)][int]
        $TryReportInterval = 0,

        # 本函数采用定时检查时分秒的方式，这里控制每多少秒检查一下时间如果是调试执行任务,可以将60改为1等小的数试试执行任务效果)
        # 当检查间隔为1时是最密集的检查,再小则是浪费;
        # 如果启用RepeateInterval(取大于0的值),那么CheckInterval应该服从于$RepeateInterval
        $CheckInterval = 60
        
    )
    # function New-TextToSpeech{}
    Write-Host 'Start-SimpleScheduledTaskByPwsh...'

    $PSBoundParameters | Format-Table #如果省略|format-table,可能无法显示

     
    $TickMins = @($TickMins)
    # 处理定点执行任务:采用轮询的方式,为了判断当前时间是否应该执行任务,需要放置在循环中,每隔一段时间检查一次(比如1秒)
    while ($true)
    {
        Write-Host 'running & waiting ...'
        $currentHour = (Get-Date).Hour
        # 关键是分钟,是否是30分(半点)还是0分 (整点)
        $currentMinute = (Get-Date).Minute
        $currentSecond = (Get-Date).Second
        
        $TimeRaw = Get-Time
        # $Time = Get-Time -SetSecondsToZero
        
        
        $report = $false
        
        # 检查是否要播报当前时间
        if ($Now)
        {
            & $Scriptblock
            return
        }
        elseif ($RepeateInterval -and $PSCmdlet.ParameterSetName -eq 'Repeate' )
        {
            # 这里有2中方案,一种是在这里内部启动自己的循环,执行间隔时间执行任务
            # 另一种是公用外部循环

            ## plan1
            # while (1)
            # {

            #     Start-Sleep $RepeateInterval
            #     & $Scriptblock
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
            & $Scriptblock -message "$Timer seconds  Passed!"

            Write-Host "Reporting timer end at:$(Get-Time)" -ForegroundColor Red
            # 闹钟执行任务后直接return(但是会导致Start-ProcessHidden中运行来不及执行任务就退出了,也就是说后台起一个新进程中如果再使用start-job就要考虑异步任务能否来得及执行(通常来不及),可以考虑用-NoExit不主动退出后台shell)
            return
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Alarm')
        {
            if ($currentHour -eq $InHour24Format -and $currentMinute -eq $InMinute)
            {
                # $report = $true
                & $Scriptblock
                return 
            }

        }
        # 下面的情况设置执行任务标记,统一执行任务即可
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
        # 统一根据需要执行任务
      
             
    

        # $currentSecond -eq 0
        Write-Verbose " $(Get-Time)"

        if ($TryReportInterval)
        {
            # 提高执行任务频率用的,主要用于调试(一分钟内会执行任务几次)
            if ( $currentSecond % $TryReportInterval -eq 0 )
            {
                # & $Scriptblock # 执行任务
                # 这里用输出文字日志来检查报告时机
                Write-Host "$DesktopVoice $(Get-Time)" -ForegroundColor Blue
                # 调用执行任务函数
                if ($report)
                {
                    & $Scriptblock
            
                }
            }
        }
        else
        {
            if ($report)
            {
                & $Scriptblock
            
            }
        }
     

        
        # Start-Sleep -Seconds 60
        Start-Sleep -Seconds $CheckInterval

    }
}