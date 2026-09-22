<#
WinSys 模块:Windows 本机系统设置(键盘输入法/TTS 语音/电源管理)。
从 Basic.psm1 迁入(2026-09-21):Basic 只留通用小工具,系统设置类归此模块;
调用方命令名不变(自动发现同名模块),TaskSchdPwsh 报时等跨模块调用走自动加载。
#>

function Get-SpeechVoiceOptions
{
  
    <# 
    .SYNOPSIS
    获取可用的系统语音引擎(可能是不完整的,需要您打开系统设置里找到speech查看可用的语音引擎列表)
    较新的windows(我在24h2上操作过)系统语音引擎管理可以添加自然语言的TTS引擎,这类引擎很逼真,和edge浏览器中的朗读引擎基本同款,不过windows系统里是需要下载,可以离线使用,但是这里的api似乎难以调用自然语音朗读引擎(可惜)
    windows中语音转文字主要用来为无障碍功能服务,比如Narrator(旁白),可以在部分情况下朗读屏幕上的文字,比如设置页面中各个按钮或控件及其说明文字
    #>
    $sapi = New-Object -ComObject SAPI.SpVoice
    $sapi.GetVoices() | ForEach-Object { $_.GetDescription() }

}

function New-TextToSpeech
{
    <# 
        .SYNOPSIS
        通过计算机扬声器大声朗读消息。
        
        .Description
        New-TTS
        windows的报时api是一个阻塞调用者进程的进程,类似于sleep 一段时间(报读文字结束后再回来)
        所以可以考虑用异步job来处理
        
        然而,在函数内部直接使用start-job运行ScriptBlock会有变量传递问题,也就是参数在scriptblock中难以被解析,而是以错误告终
        我们可以为这类需要异步执行的函数配置一个Handler辅助函数,也就是对这个函数再次打包一下;
        或者将核心函数名设置Core后缀,然后用不带Core的函数名包装,这样可以便于其他地方用参数-BgJob来指明后台运行相关任务,而不需要在外部使用Start-Job命令来修饰
        
        虽然使用Start-job 也没有那么不便,相反,还可以让函数更加注重逻辑,而不是什么都干
        
        Start-job 使用-ScriptBlock {}参数编写依然可以使用命令行参数补全功能等,注意不要用字符串(引号包裹命令会难以借助补全)
        然而这种用法的问题仍然是定义在ScriptBlock外的变量无法被Start-job新建的powershell进程识别,造成不便

        幸运的是,我们可以利用Start-job -ArgumentList来传递参数，这样就可以在ScriptBlock中使用变量了
        有两类选择:$input配合 -InputObject <arg>,或者{param($p)} 配合-argumentlist <arg>
        

        .Notes
        Alias: New-TextToSpeechMessage->speech
        
        .EXAMPLE
        New-TextToSpeech -Message 'This is the text I want to have read out loud' -Voice Zira
        
        .EXAMPLE
        # Scriptblock中不含有变量,而只有字面量,而且执行的函数New-TextToSpeech是定义在自动导入模块中,
        因此都是可以被pwsh直接识别的而不依赖于外部定义的变量,可以成功按预期运行
        Start-job -scriptblock {New-TextToSpeech -message "Get Time SetSecondsToZero"}
        .EXAMPLE
        # 下面这个例子中用到了变量$m(不是定义在Scriptblock内),无法被Start-job的ScriptBlock识别，因此出问题
        PS C:\Users\cxxu\Desktop> $m='abc'
        PS C:\Users\cxxu\Desktop>  Start-job -scriptblock {New-TextToSpeech -message $m}
        在 PowerShell 中，变量在不同作用域之间是独立的，因此在 ScriptBlock 中直接使用外部定义的变量 $m 是不行的。你可以通过使用 -ArgumentList 参数将变量传递给 Start-Job 的 ScriptBlock。
        执行以下脚本:可以看到效果
        $m = 'abc'
        Start-Job -ScriptBlock {
            param($message)
            New-TextToSpeech -message $message
        } -ArgumentList $m

        .EXAMPLE
        # 使用$input变量和-InputObject参数
        PS C:\exes> start-job {param($m) New-TextToSpeech -message $input} -InputObject $m

        Id     Name            PSJobTypeName   State         HasMoreData     Location
        --     ----            -------------   -----         -----------     --------
        13     Job13           BackgroundJob   Running       True            localhost
        .EXAMPLE
        #使用{param($message)} 传递参数
        PS C:\exes> start-job {param($m) New-TextToSpeech -message $m} -ArgumentList $m

        Id     Name            PSJobTypeName   State         HasMoreData     Location
        --     ----            -------------   -----         -----------     --------
        9      Job9            BackgroundJob   Running       True            localhost
        .EXAMPLE
        PS C:\Users\cxxu\Desktop>  Start-job -scriptblock {speech -message "$(Get-Time -SetSecondstoZero)"}

        Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
        --     ----            -------------   -----         -----------     --------             -------
        9      Job9            BgJob   Running       True            localhost            speech -message "$(Get-T…

        PS C:\Users\cxxu\Desktop>  Start-job -scriptblock {speech -message "$(Get-Date)"}

        Id     Name            PSJobTypeName   State         HasMoreData     Location             Command
        --     ----            -------------   -----         -----------     --------             -------
        11     Job11           BgJob   Running       True            localhost            speech -message "$(Get-D…
         #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'message')]
        [string]$message,
    
        [Parameter(ParameterSetName = 'Path')]
        $Path = '',
        # [ValidateSet('Zira', 'Huihui', 'David',...)] # 区分大小写!
        [string]$DesktopVoice = 'Zira',
        [switch]$BgJob
    )
    if ($Path)
    {
        $message = Get-Content $Path
    }
    $script = {
        Add-Type -AssemblyName System.Speech
        $speak = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $Speak.SelectVoice("Microsoft $DesktopVoice Desktop") #使用start-job可能无法识别$DesktopVoice变量
        $speak.Speak($message)
    }
    & $script

    # if ($BgJob)
    # {
    #     # ScriptBlock中无法解析参数变量,建议放到外部显示使用Start-job -scriptblock { New-TextToSpeech ...}的方式来进行后台运行
    #     $j = Start-Job -ScriptBlock $script 
        
    #     return $j
    # }
    # else
    # {
    #     & $script
    # }

}

function check_keyboards
{
    powershell.exe { 
        Write-Host $(Get-WinUserLanguageList)
        #  $zh = $l[1].inputMethodTips;
    }
}

function check_zh_keyboards
{
    powershell.exe { 
        $l = Get-WinUserLanguageList
        $zh = $l | Where-Object { $_.languageTag -match 'zh-hans-cn' }
        return $zh
    }
}

function remove_sogou_keyboard
{
    powershell.exe { 
        $l = Get-WinUserLanguageList 
        # $zh = $l[1].inputMethodTips;
        # $zh = check_zh_keyboards#无法直接从pwsh5传递对象回pwsh7
        $zh = $l | Where-Object { $_.languageTag -match 'zh-hans-cn' }
        $zhTips = $zh.inputMethodTips
        Write-Host "list:$l; `nzh:$zh"
        # $sogou_keyboard = $zhTips[1]
        $sogou_keyboard = $zhTips | Where-Object { $_ -like '*e7ea*' }
        Write-Host "sogou:$sogou_keyboard"
        $zhTips.remove($sogou_keyboard)
        Write-Host "now:$zh"

        Set-WinUserLanguageList -LanguageList $l -Force }
}

function add_sogou_keyboard
{
    # param ()
    powershell.exe {
        $sogou_keyboard_tips = '0804:{E7EA138E-69F8-11D7-A6EA-00065B844310}{E7EA138F-69F8-11D7-A6EA-00065B844311}'
        $l = Get-WinUserLanguageList
        $zh = $l | Where-Object { $_.languageTag -match 'zh-hans-cn' }
        Write-Host "list:$l; `nzh:$zh;`nsogou_keyboard_tips:$sogou_keyboard_tips"
        $zhTips = $zh.inputMethodTips
        $zhTips.add($sogou_keyboard_tips)
        Write-Host "now:zh:$zh"
        Set-WinUserLanguageList -LanguageList $l -Force
    }

}

function set_pinyin_default
{
 
    pwsh5 {
        Set-WinDefaultInputMethodOverride -InputTip '0804:{81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E}{FA550B04-5AD7-411F-A5AC-CA0
                  38EC515D7}'
        Write-Host 'done!'
    }
    
}

function remove_en_us_keyboard
{
    powershell.exe { 
        $l = Get-WinUserLanguageList 
        $en = $l | Where-Object { $_.languageTag -match 'en-us' }
        $enTips = $en.inputMethodTips
        $enus_keyboard = $enTips | Where-Object { $_ -like '*0409:00000409*' }
        Write-Host "sogou:$enus_keyboard"
        $enTips.remove($enus_keyboard)
        Write-Host "now:$en"

        Set-WinUserLanguageList -LanguageList $l -Force }
}

function add_en_us_keyboard
{
    # param ()
    powershell.exe {
        $en_keyboard_tips = '{0409:00000409}'
        $l = Get-WinUserLanguageList
        $en = $l | Where-Object { $_.languageTag -match 'en-us' }
        $enTips = $en.inputMethodTips
        $enTips.add($en_keyboard_tips)
        Write-Host "now:en:$en"
        Set-WinUserLanguageList -LanguageList $l -Force
    }

}

function HibernateComputer
{
    param (
        
    )
    Shutdown /h
}

function Stop-ComputerInquery
{
    Write-Host 'the pc will be shutdown '
    # in 3 senconds'
    # write-host '❤️⛔control+c to stop the behaviour...'
    # timer_tips 3
    $Inquery = Read-Host -Prompt ' input y key to continue shutdown!(prevent the unexpected shutdown) '
    if ($Inquery -eq 'y')
    {
        Shutdown /p
    }
}

function SleepComputer
{
    Push-ReposesConfiged 
    rundll32.exe powrprof.dll, SetSuspendState 0, 1, 0
}

function LockScreen
{
    Push-ReposesConfiged 
    rundll32.exe user32.dll, LockWorkStation
}

function shutdown_timer1
{
    <# 
    .SYNOPSIS
    在给定时间内关机,假设以5秒为例,默认5秒
    5秒内可以输入y来继续立即关机,也可以输入n取消关机
    如果没有任何操作,时间到达5秒后自动关机

    函数的缺点是无法通过调用指定倒计时时间,因为start-job实现的函数,无法传递给start-job scriptblock
    如果需要修改,请编辑函数代码,将$timer出现的2个位置都替换为需要的值
    #>
    param(
        $timier = 5 #无法传递给start-job scriptblock,这个参数其实不太有用
    )
    # $log = "$home\shutdown_log.txt"
    # 创建后台作业来处理用户输入
    $job = Start-Job -ScriptBlock {
        # 可以使用日志文件的方式记录$job的运行过程和结果
        # $log = 'c:\users\cxxu\shutdown_log.txt'
        # '准备关机' >> $log
        # Start-Sleep $scriptblock中无法继承shell变量,外部变量$Timier 无法识别,这里睡眠时间要硬编码
        
        $timer = 5 ; #赋值给变量timer
        Start-Sleep $timer
   
        #关机
        Stop-Computer 

    }
    $result = Read-Host 'Do you want to shutdown the computer now? (y/n)' "`n You have $Timier seconds to cancel"

    # 获取作业的结果
    # $result = Receive-Job -Job $job -Wait

    # 根据用户的选择进行处理
    if ($result -eq 'y')
    {
        # 用户选择了'y'，执行关机
        # 'User press [y],Shutting down...' | Tee-Object -Append $log
        Start-Sleep -Seconds 0.5
        
        Stop-Computer  # 实际执行关机时取消注释这行
    }
    elseif ($result -eq 'n')
    {
        # 用户选择了'n'，取消关机
        # 'User press [n],Shutdown cancelled.' | Tee-Object -Append $log
        
        # 清理作业
        Remove-Job -Job $job -Force
    }

}

function shutdown_timer2
{
    <# 
    .SYNOPSIS
    默认5秒后关机,5秒内可以反悔取消关机(按下Ctrl+C取消关机)
    无法提前关机,只能在5秒后触发关机
    #>
    param(
        $Timier = 5 
    )

    Write-Host "You have $Timier seconds to cancel(press Ctrl+C to cancel)" -BackgroundColor Yellow
    Write-Host 'Please ensure all tasks have been saved!' -BackgroundColor Cyan
    timer_tips $Timier
    Write-Host 'shutting down!'
    Start-Sleep 1
    Stop-Computer
    # 打印作业返回的结果

}
# 调用函数测试
# Shutdown-Computer
function Stop-ComputerAfterSyncActions
{
    param(
        [switch]$Force
    )
    # 将笔记和脚本配置上传到云端
    Push-ReposesConfigedFromMainPC
    # 关闭电脑
    Start-Sleep 1.5
    # 尝试关机(普通模式下如果有其他用户登录到该计算机,则无法关机)
    #如果要强制关机，则使用Force选项
    
    if ($Force)
    {
        Write-Host 'shutting down Forcely!'
        Start-Sleep 1.5
        Stop-Computer -Force
    }
    Start-Sleep 1.5
    Stop-Computer
}
