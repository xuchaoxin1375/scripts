

function Start-ScriptWhenIntervalEnough
{
    <#
.SYNOPSIS
调用本函数时判断上一次调用距离现在时间是否足够大,如果足够大,则执行指定脚本或任务
满足触发条件时,会更新$LastUpdateTime全局变量
.DESCRIPTION
利用相关环境变量(LastUpdateTime)判断上一次更新是在什么时候,并在间隔达到阈值(Interval)后执行一个或多个脚本
    该函数的主要作用是在每隔指定时间后执行一个或多个脚本,例如定期更新一些数据
    如果指定的脚本是一个文件的路径,则会执行该文件
    如果指定的脚本是一段PowerShell代码,则会在当前脚本的上下文中执行

.PARAMETER Interval
    指定执行间隔的时间,单位是秒

.PARAMETER Scripts
    $Scripts参数 指定要执行的脚本的路径或PowerShell代码,可以是字符串数组
    #>
    <# 
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
        #来自于启动powershell时初始化的时间变量(Global)
        
        $LastUpdate = $LastUpdate 
    )
    $currentTime = Get-Date
    
    # Write-Host $currentTime,($currentTime - $LastUpdate).TotalSeconds -BackgroundColor Magenta
    if (!$LastUpdate)
    {
        # $Global:LastUpdate = Get-Date
        Set-LastUpdateTime
        Write-Warning 'Create new LastUpdate variable!'
    }
    
    # 这里需要确保$LastUpdate不为空
    $enough = ($currentTime - [datetime]$LastUpdate).TotalSeconds -ge $Interval
    if ( $enough )
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
        # $Global:LastUpdate = Get-Date
        Set-LastUpdateTime
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
                Write-Host "$DesktopVoice $(Get-Time)" -ForegroundColor Cyan
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
