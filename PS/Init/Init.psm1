# 其他函数都是通过init来调用或间接调用的,在这里可以注释掉某些模块来帮助调试bug
 
function init
{ 
    <# 
    .SYNOPSIS
    加载pwsh的配置(包括常用变量和别名,模块导入管理)
    .DESCRIPTION
    对$profile和windows terminal 启动参数中都执行(直接或着间接)做了免重复处理
    .NOTES
    严格上讲,按照powershell的设计规范,加载配置应该放在$profile中
    另一方面,如果不侵入$profile而仅配置terminal软件的启动参数,可以不放在$profile
    最关键的问题在于如果同时配置了terminal和$profile的情况下如何协调载入问题
    #>
    [CmdletBinding()]
    param(
        [switch]$Force,
        # 显示每步耗时报告(默认关闭以保启动速度;`p -Force` 通过 -InformationAction Continue 间接触发)
        [switch]$Timing
    )

    Write-Host 'initing...'
    # 使用临时环境$env:Psinit会引发副作用(子作用域的pwsh也会继承此变量),这里限制其作用域,使用普通变量(局部)
    #考虑到$profile和wt中的启动参数同时调用init,都是同一个作用域,不需要第二个作用域访问到此标记变量,因此使用普通变量即可(同一个会话内可以访问)
    if ($Force -or $null -eq $PsInit)
    {
        Write-Verbose 'Init pwsh env...'
        # $env:PsInit = 'True' 
        $global:PsInit = $True
        # 用户配置文件先行(环境变量 > 配置文件 > 默认;缺文件静默跳过,见 Import-CxxuConfig)
        Import-CxxuConfig
    }
    else
    {

        Write-Verbose 'Init work loaded !' -Verbose
        return
    }


    # 获取当前日期时间
    $startTime = Get-Date
    Set-LastUpdateTime
    # 启动步骤表:直接调用(当前会话作用域),不要转字符串再 iex —— iex 慢且吞错误定位;
    # 进度条默认开(真机实测开销可忽略,用户 306ms 全链含进度条),开关见 $env:PsShowProgress,
    # 重定向下(无处渲染)自动关闭。
    $steps = @(
        # 导入图标模块(建议放到extension部分中)
        # Import-TerminalIcons
        # Import-ANSIColorEnv
        # 补全模块PSReadline及其相关配置
        @{ Name = 'Set-PSReadLinesCommon'; Action = { Set-PSReadLinesCommon } }
        @{ Name = 'Set-PSReadLinesAdvanced'; Action = { Set-PSReadLinesAdvanced } }
        @{ Name = 'Set-ArgumentCompleter'; Action = { Set-ArgumentCompleter } }
        @{ Name = 'Confirm-EnvVarOfInfo'; Action = { Confirm-EnvVarOfInfo } }
        @{ Name = 'Set-PsExtension'; Action = { Set-PsExtension } }
        # 设置prompt样式(这里面会导入基础的powershell预定变量和别名)
        @{ Name = 'Set-PsPrompt'; Action = { Set-PsPrompt } }
        # Confirm-DataJson 有返回值(路径,供调用方使用),init 只关心副作用,屏蔽回显
        @{ Name = 'Confirm-DataJson'; Action = { Confirm-DataJson | Out-Null } }
        # 体验件(PSFzf/zoxide)OnIdle 延迟加载,只注册事件即返回,启动零开销
        @{ Name = 'Register-PsUxLazyLoad'; Action = { Register-PsUxLazyLoad } }
    )

    # 仅在要求时计时/报告(-Timing 或 -InformationAction Continue,`p -Force` 走后者)
    $needTiming = $Timing -or ($InformationPreference -eq 'Continue')
    $report = @()
    # 单步失败只记账不中断:历史上 PSReadLine 在重定向下抛 terminating error,
    # 曾导致后面 5 步静默被跳过(见 docs/Startup-Optimization.md §12);现在失败步骤
    # 记入 $global:PsInitStepErrors,最后统一 Warning 汇总,成功路径行为/耗时不变。
    # 进度条总开关(默认开):$env:PsShowProgress='False'/'0'/'No'/'Off' 关闭,
    # 未设置或其它值均为开;stdout 重定向时(agent/CI/管道,无处渲染)强制关闭。
    # 样式沿用历史原版:Classic 视图 + 一位小数百分比(用户偏爱,不要"优化"掉)。
    $consoleInteractive = try { -not [Console]::IsOutputRedirected } catch { $false }
    $showProgress = ($env:PsShowProgress -notmatch '^(False|0|No|Off)$') -and $consoleInteractive
    if ($showProgress)
    {
        $PSStyle.Progress.View = 'Classic'
    }
    $global:PsInitStepErrors = @()
    for ($i = 0; $i -lt $steps.Count; $i++)
    {
        $step = $steps[$i]
        Write-Verbose "Loading $($step.Name)"
        if ($showProgress)
        {
            $Completed = [math]::Round($i / $steps.Count * 100, 1)
            Write-Progress -Activity 'Loading... ' -Id 0 -Status "$($step.Name) -> Processing: $Completed%" -PercentComplete $Completed
            Write-Information "Loading $($step.Name) "
        }
        $t0 = [datetime]::UtcNow
        try
        {
            & $step.Action
        }
        catch
        {
            $global:PsInitStepErrors += [PSCustomObject]@{
                Step  = $step.Name
                Error = $_.Exception.Message
            }
            Write-Verbose "步骤 $($step.Name) 失败(已跳过,继续后续): $($_.Exception.Message)"
        }
        if ($needTiming)
        {
            $report += [PSCustomObject]@{
                Command = $step.Name
                Time    = [int]([datetime]::UtcNow - $t0).TotalMilliseconds
            }
        }
    }

    if ($showProgress)
    {
        Write-Progress -Activity 'Loading...' -Completed
    }

    if ($global:PsInitStepErrors.Count)
    {
        Write-Warning ("init 有 $($global:PsInitStepErrors.Count) 个步骤失败(其余已继续执行): " +
            (($global:PsInitStepErrors | ForEach-Object { "$($_.Step): $($_.Error)" }) -join ' | '))
    }

    if ($needTiming -and $report.Count)
    {
        $report | Sort-Object Time -Descending | Format-Table -AutoSize | Out-String | Write-Host
    }

    # 其他自定义绑定的任务🎈
    ## 加载时计算方案(耗费一定时间)
    # if(Test-CommandAvailability zoxide)
    # {

    #     Invoke-Expression (& { (zoxide init powershell | Out-String) })
    # }
    # if(Test-CommandAvailability uv)
    # {
    #     Invoke-Expression (& { uv generate-shell-completion powershell | Out-String })
    # }
    # if(Test-CommandAvailability ruff)
    # {
    #     Invoke-Expression (& { ruff generate-shell-completion powershell | Out-String })
    # }

    ## 缓存补全脚本方案(版本更新的情况下可能要清除缓存脚本文件重新生成)
    # zoxide
    # if(Test-CommandAvailability zoxide)
    # {
    #     $zoxideCompletionFile = "$HOME\.zoxide_completion.ps1"
    #     if (!(Test-Path $zoxideCompletionFile))
    #     {
    #         zoxide init powershell > $zoxideCompletionFile
    #     }
    #     . $zoxideCompletionFile
    # }

    # astral系列
    # 检查 uv 是否存在且是否有缓存，如果没有或过时则更新
    # if(Test-CommandAvailability uv)
    # {
    #     $uvCompletionFile = "$HOME\.uv_completion.ps1"
    #     if (!(Test-Path $uvCompletionFile))
    #     {
    #         uv generate-shell-completion powershell > $uvCompletionFile
    #     }
    #     . $uvCompletionFile
    #     # uvx
    #     $uvxCompletionFile = "$HOME\.uvx_completion.ps1"
    #     if(!(Test-Path $uvxCompletionFile))
    #     {
    #         uvx --generate-shell-completion powershell > $uvxCompletionFile
    #     }
    #     . $uvxCompletionFile
    # }
    # if(Test-CommandAvailability ruff)
    # {
    #     $ruffCompletionFile = "$HOME\.ruff_completion.ps1"

    #     if (!(Test-Path $ruffCompletionFile))
    #     {
    #         ruff generate-shell-completion powershell > $ruffCompletionFile
    #     }
    #     . $ruffCompletionFile
    # }

    # 小心conda(miniforge或miniconda)的初始化脚本,部分版本初始化脚本可能引起错误
    # 可以使用调试模式强制加载初始化操作: p -verbose -debug -force
    # if(Test-CommandAvailability conda)
    # {
    #     $condaCompletionFile = "$HOME\.conda_completion.ps1"
    #     if(!(Test-Path $condaCompletionFile))
    #     {

    #         conda 'shell.powershell' 'hook' > $condaCompletionFile
    #         # (& conda 'shell.powershell' 'hook') | Out-String | Invoke-Expression
    #     }
    #     . $condaCompletionFile
    # }
    # 耗时统计
    $endTime = Get-Date
    $loadTime = $endTime - $startTime
    $loadTime = $loadTime.Totalmilliseconds

    Write-Host "Environment Loading time: $loadTime ms " -ForegroundColor Magenta
    # 清理竞争关系变量
    # $env:PsInit = $null
    # Remove-Variable $env:PsInit
}
function p
{
    <# 
    .SYNOPSIS
    打开新的powershell环境 
    .DESCRIPTION
    支持两种模式,一类是当需要要刷新模块时,在当前powershell会话中执行此命令
    另一类是作为每个powershell会话自动导入的基础性配置
    .NOTES
    性能分析
    默认情况下,载入powershell环境或配置不会显示过多细节以保持简洁,但是如果用户对于加载过程中的耗时环节感兴趣,那么可以使用
    `p -force`来查看加载耗时报告(此时内部调用pwsh -noprofile,会忽略$profile中的指令,同时用了-c参数执行`p`函数,以强制重新加载新的pwsh会话以及相应的环境配置导入任务,并且使用-InformationAction continue来输出加载耗时报告)
    .Notes
    报告给的细节部分(比如加载哪些模块对应耗时,但是其他一些语句也会产生耗时,
    尤其是gmo -listavailables是比较耗时的,其耗时比较稳定,这里不展示该项目耗时)
    .NOTES
    将此命令配置到环境变量时,一定要使用原地导入配置的模式,即使用参数`NoNewShell`否则会导致循环创建新的pwsh进程
    这种情况下只能使用Ctrl+C关闭会话,并且使用`ps pwsh`检查相关进程,关闭多余进程
    .NOTES
    如果发现 提示语句被重复导入,那么可能是配置文件中的配置项目重复了
    例如Setting basic environment in current shell...提示了两次,那么用编辑器打开$profile移除多余的导入语句
    #>
    [CmdletBinding()]
    param(
        #是否启动新的shell环境
        [switch]
        [Alias('KeepCurrentShell', 'InlineImport')]
        $NoNewShell , #默认启动新环境
        [switch]$Force

    )
    # 配置编码输出组合防止外部脚本(非powershell脚本输出非英文字符时乱码)
    # Write-Verbose 'Setting Output Encoding to UTF8' -Verbose
    # $OutputEncoding = [System.Text.Encoding]::UTF8
    # [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  
    # 处理$profile 和windows terminal 中的携带参数启动pwsh冲突或重复关系
    if ($null -eq $PsInit)
    {
        if ($NoNewShell)
        {
            # 当前环境不启动新的shell环境，直接执行$script
            Write-Host 'Setting basic environment in current shell...'
            init -Verbose:$VerbosePreference
            
        }
        else
        {
            # 请求启动新的powershell环境
            Write-Host 'Loading new pwsh environment...'
            
            pwsh -noe -c init
            # Start-Process -FilePath pwsh -NoNewWindow -ArgumentList " -noe -c init -Verbose:$([int]$VerbosePreference) "
        }
    }
    if ($Force)
    {
        pwsh -noe -noprofile -c { init -Force -InformationAction continue }
    }
}
function Set-CommonInit
{
    [CmdletBinding()]
    param(
        
    )
        
    Update-PwshEnv -Verbose:$VerbosePreference
    # 注:此处曾调用不存在的 Start-CoreInit(调用即报错),已删除;
    # Update-PwshEnv 已覆盖变量+别名+prompt,"core 初始化"即它
    # 提示prompt当前的环境变量导入等级(模式),修改PsEnvMode
    #使用set-variable 语句来修改变量,而不是直接使用# $PSEnvMode = 1 或$Global:PSEnvMode = 1 的方式修改变量,可以避免IDE不当的警告提示(定义而未使用)
    Set-Variable -Name PsEnvMode -Value 3 -Scope Global
}

function Set-LastUpdateTime
{

    <# 
    .SYNOPSIS
    这是一个无聊的函数,里面创建了一个global 变量，用于记录上次运行的时间
    单独封装进函数是为了让init等函数内部的语句更加整齐
    #>
    [CmdletBinding()]
    param(
        [switch]$Passthru
    )
    #启动powershell时初始化时间,供其他函数计算时间间隔时做参考
    Set-Variable -Name LastUpdate -Value ([string](Get-Date)) -Scope Global -Verbose:$VerbosePreference
    # Set-Variable -Name xxx -Value vvv -Verbose
    # $Global:LastUpdate = [string](Get-Date) #会引发变量定义后未使用的警告,因此这里用set-variable 来修改变量

    # Write-Host $LastUpdate -ForegroundColor DarkBlue #blue
    if ($Passthru)
    {
        return $LastUpdate
    }
}
function Start-MemoryInfoInit
{

    $OS = Get-CimInstance -ClassName Win32_OperatingSystem
    $env:cachedTotalMemory = $OS.TotalVisibleMemorySize / 1MB
    $env:cachedFreeMemory = $OS.FreePhysicalMemory / 1MB
}
function Import-TerminalIcons
{
    [cmdletbinding()]
    param()
    <#     
    # if (!(Get-Module -ListAvailable -Name Terminal-Icons))
    # {
    #     Write-Host 'Terminal-Icons module not Found!'
    #     $r = Read-Host -Prompt 'Try to install it ? (estimate 5-10s) [y/n]'
    #     if ($r.ToUpper() -eq 'Y')
    #     {

    #         Install-Module Terminal-Icons -Force
            
    #     }
    #     else
    #     {
    #         # 用户拒绝安装，直接退出
    #         return
    #     }
    # } 
#>
    Confirm-ModuleInstalled -ModuleName Terminal-Icons -Install
    # 导入模块（这里确保已经安装上了模块）
    Import-Module Terminal-Icons -ErrorAction Ignore
}
function Set-PSReadLinesCommon
{
    [cmdletbinding()]
    param()
    Write-Verbose 'loading psReadLines & keyHandler!(common)'
    # Set-PSReadLineOption -Colors @{"inlineprediction"="#51ed9c"}#green

    #modify the color of selection:
    Set-PSReadLineOption -Colors @{'selection' = '#0080ff' } 
  
    # PSColor to color the folders(in the ls command excute result.)
    # Import-Module Get-ChildItemColor

    <#  set tab auto completion(optional item)
    #set tab auto completion(optional item)
    #(the command line will try to offer you a list(candidated) when you press the `tab`key
    #of course,if the current path have only one or even none can match what you want to match,it will just try to complete the current object name
    #>
    Set-PSReadLineKeyHandler -Key Tab -Function Complete
    Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function ForwardWord
    Set-PSReadLineKeyHandler -Key 'Tab' -Function MenuComplete # 设置 Ctrl+d 为菜单补全和 Intellisense
    Set-PSReadLineKeyHandler -Key 'Ctrl+z' -Function Undo # 设置 Ctrl+z 为撤销
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward # 设置向上键为后向搜索历史记录, 光标前的数据将为筛选
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward # 设置向下键为前向搜索历史纪录, 光标前的数据将为筛选
    # Set-PSReadLineKeyHandler -Chord "rightArrow" -Function ForwardWord
    # Set-PSReadLineKeyHandler -Chord "tab" -Function ForwardWord
    # Set-PSReadLineOption -PredictionSource History # 设置预测文本来源为历史记A
    # Set-PSReadLineKeyHandler -Key "Ctrl+d" -Function MenuComplete # 设置 Ctrl+d 为菜单补全和 Intellisense

    <# # Note! parameter is not allowed in the Set-Alias,for instance:`Set-Alias ep "explorer ." will not works ;
    however ,you can add the `ep parameter` to run the cmdlet;
    of course ,if your parameters are often long paramter,you can try the function to achieve your goal
    Attention!
    you'd better do not let the two kind names with the same name(one of them will not work normally.)
    #>

}

function Set-PSReadLinesAdvanced
{
    [cmdletbinding()]
    param()
    <# beautify the powershell interactive interface  #>
    # modify the color of the inlinePrediction:
    Write-Verbose ('loading psReadLines & keyHandler!(advanced)' + "`n")
    # Import-Module CompletionPredictor -Verbose #-Verbose:$VerbosePreference

    # 预测源与列表视图依赖可写控制台(VT/控制台句柄):
    # - 交互场景(WT/终端直连):照常应用,行为与以前完全一致;
    # - 重定向场景(agent/CI/计划任务/`pwsh -c` 管道):没有行编辑,跳过此二项,
    #   否则两条 terminating error 会打断 init 后续步骤(步骤表无 try/catch)。
    # 注意:[Environment]::UserInteractive 在重定向下仍为 True,不可用;
    # 只有 [Console]::IsOutputRedirected 能区分。
    $consoleInteractive = try { -not [Console]::IsOutputRedirected } catch { $false }
    if ($consoleInteractive)
    {
        try
        {
            # 插件必须显式 import 才会向 ListView 供稿(装了不等于加载了);缺失时静默降级为纯历史
            # -Global:函数内 import 默认嵌套(Get-Module 列不出),强制顶层
            Import-Module CompletionPredictor -Global -ErrorAction SilentlyContinue
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin # 设置预测文本来源为历史和插件
            # 窄窗口(<50 宽或 <5 高)PSReadLine 会刷 ListView WARNING:事先按尺寸分流,窄用内联
            # (取不到尺寸按宽处理,行为与以前一致;窗口拉大后重跑本函数即按新尺寸重选)
            $wideEnough = try { ([Console]::WindowWidth -ge 50) -and ([Console]::WindowHeight -ge 5) } catch { $true }
            if ($wideEnough)
            {
                Set-PSReadLineOption -PredictionViewStyle ListView -BellStyle None  #使用视图列表显示预测后选
            }
            else
            {
                Set-PSReadLineOption -PredictionViewStyle InlineView -BellStyle None
                Write-Verbose '窗口过窄(<50x5),预测视图用内联(避开 ListView 警告);拉大窗口后重跑 Set-PSReadLinesAdvanced 切回列表'
            }
        }
        catch
        {
            Write-Verbose "跳过 PSReadLine 预测视图(当前控制台不支持): $($_.Exception.Message)"
        }
    }
    else
    {
        Write-Verbose 'stdout 已重定向,跳过 PSReadLine 预测源/列表视图(无交互行编辑)'
    }
    # listView列表设置
    Set-PSReadLineOption -MaximumHistoryCount 3000  # 可选：增大历史记录总数
    Set-PSReadLineOption -HistoryNoDuplicates  # 历史不存重复命令(防 ConsoleHost_history.txt 无限膨胀,Ctl+R 读全文件,3 万行是它慢的主因)
    Set-PSReadLineOption -CompletionQueryItems 100  # 可选：增大自动完成候选列表数量
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd

    # Set-PSReadLineOption -PredictionViewStyle MenuView
    

    # 设置建议窗口高度为 30 行

    <# set colors #>
    Set-PSReadLineOption -Colors @{'inlineprediction' = '#d0d0cb' }#grayLight(grayDark #babbb4)
    <# suggestion list #>
    # Set-PSReadLineOption -PredictionViewStyle ListView
    # Set-PSReadLineOption -EditMode Windows
}

# --- 从 Pwsh.psm1 迁入:环境等级跟踪与导入(职责:初始化) ---

function Update-PwshEnv
{
    [CmdletBinding()]param()
    # 先更新变量,再更新别名
    Update-PwshVars -Verbose:$VerbosePreference
    Update-PwshAliases -Verbose:$VerbosePreference
    Set-Variable -Name PsEnvMode -Value 3 -Scope Global
    Set-PsPrompt 
    # Start-CoreInit
}

function Test-PsEnvMode
{
    <# 
    .SYNOPSIS
    获取当前的环境变量模式，函数没有太多逻辑，只是隐藏具体的模式变量
    .EXAMPLE
    PS C:\Users\cxxu\Desktop> test-PsEnvMode -Mode Vars
    False

    PS [C:\Users\cxxu\Desktop]> test-PsEnvMode -Mode Env
    False

    PS [C:\Users\cxxu\Desktop]> $PSEnvmode

    PS [C:\Users\cxxu\Desktop]> update-PwshVars


    PS [C:\Users\cxxu\Desktop]> Test-PsEnvMode -Mode Vars
    True

    PS [C:\Users\cxxu\Desktop]> Test-PsEnvMode -Mode Env
    False

    PS [C:\Users\cxxu\Desktop]> $PSEnvmode
    1

    PS [C:\Users\cxxu\Desktop]> init
    updating envs!
    updating aliases!
    ...

    2024/7/17 9:44:20

    PS☀️[BAT:70%][MEM:33.02% (10.47/31.71)GB][9:44:20]
    # [cxxu@CXXUCOLORFUL][~\Desktop]
    PS> test-PsEnvMode -Mode Env
    True

    PS☀️[BAT:70%][MEM:33.02% (10.47/31.71)GB][9:44:26]
    # [cxxu@CXXUCOLORFUL][~\Desktop]
    PS> test-PsEnvMode -Mode vars
    True
    #>
    param(
        [ValidateSet('Vars', 'Env', 'core')]$Mode = 'Env'
    )
    if ($Mode -eq 'Env')
    {

        # $res = Get-Variable -Name 'PsEnvMode' -ErrorAction SilentlyContinue 
        # 或者更直接地判断: $res=$PsEnvMode -ne $null
        # 或者直接返回 $PsEnvMode
        # $res = $PsEnvMode
        $Value = 3
    }
    elseif ($Mode -eq 'Vars')
    {
        $Value = 2
    }
    elseif ($Mode -eq 'Core')
    {
        $Value = 1
    }

    return $PsEnvMode -ge $Value
}

function Update-PwshvarsIfNotYet
{
    <# 
    .SYNOPSIS
    检查当前powershell是否已经导入pwsh 变量
    如果没有,则导入,否则不做任何事情
    #>
    Update-PwshVars
    
}
function Update-PwshEnvIfNotYet
{
    <# 
    .SYNOPSIS
    检查当前powershell是否已经导入pwsh环境（包括两种模式）
    如果没有,则导入,否则不做任何事情
    .DESCRIPTION
    这个函数单独调用时并不慢
    但是如果在powershell载入之初就调用,则比较影响性能
    因为单独载入pwsh是不慢的,而载入pwsh后单独调用Update-PwshEnvIfNotYet也是不慢的
    但是在载入pwsh的时候调用update-pwshenvifnotyet会慢很多
    我猜测是pwsh分分部导入环境,基础环境导入后命令提示符已经可以响应用户的输入了,但是后台还有内容需要继续加载,这部分是耗时逻辑
    或者是采用懒惰加载的方式,在用到的时候会初次加载需要的运行时,因此第一次执行某个任务比较慢,但是第二次以及之后的执行速度机会快不少
    #>
    [CmdletBinding()]
    param (

        [ValidateSet(
            'core',
            'Vars', 
            # 'Aliases',
            'Env' #both Vars and Aliases
        )]$Mode = 'Env',
        $Force
    )
    # 如果环境模式(等级)不满足要求,则导入对应级别的环境
    if ($Force)
    {
        Update-PwshEnv
    }
    elseif (! (Test-PsEnvMode -Mode $Mode ))
    {
        if ($Mode -eq 'core')
        {
            Update-PwshVars -Core
        }
        elseif ($Mode -eq 'Vars')
        {
            Update-PwshVars
        }
        elseif ($Mode -eq 'Env')
        {
            Update-PwshEnv
        }
        # 导入变量后,更新命令提示符
        Set-PsPrompt -Verbose:$VerbosePreference
    }

    Write-Verbose 'Environment  have been Imported in the current powershell!'
}
function Optimize-PsHistory
{
    <#
    .SYNOPSIS
    历史瘦身:去重(保最近一次,保序)+去杂+截断,被裁行进归档(默认留最近 3000 行)。
    .DESCRIPTION
    PSFzf Ctrl+R 每次读全文件,3 万行 1.5MB 是它慢的主因。流程:备份 .bak → 去重(同命令只留
    最后一次,相对顺序不变) → 去杂(空行/纯空白/孤反引号) → 超 KeepLast 截断,被裁行追加进
    同目录 archive 文件(可恢复)。-WhatIf 只出诊断(总数/去重率/ топ 重复),不动文件。
    治本靠 init:HistoryNoDuplicates + MaximumHistoryCount 3000(新命令不再重复入库)。
    注意:历史文件无时间戳,切割按"新旧顺序"(文件尾=最近),不是按日期。
    .EXAMPLE
    Optimize-PsHistory -WhatIf
    .EXAMPLE
    Optimize-PsHistory -KeepLast 2000
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 活动文件保留最近多少行(默认 3000,与 MaximumHistoryCount 对齐)
        [int]$KeepLast = 3000
    )
    $file = try { (Get-PSReadLineOption).HistorySavePath } catch { '' }
    if ([string]::IsNullOrWhiteSpace($file) -or -not (Test-Path -LiteralPath $file))
    {
        Write-Warning '取不到 PSReadLine 历史文件路径,先确认 PSReadLine 已加载。'
        return
    }
    $lines = @(Get-Content -LiteralPath $file)
    $total = $lines.Count
    # 去重保最后:记每行最后下标,按最后下标排序(相对顺序=最近一次出现顺序)
    $lastIdx = @{}
    for ($i = 0; $i -lt $total; $i++) { $lastIdx[$lines[$i]] = $i }
    $ordered = @($lastIdx.GetEnumerator() | Sort-Object Value | ForEach-Object { $_.Key })
    # 去杂:空行/纯空白/孤反引号(续行手误)
    $junk = @($ordered | Where-Object { $_ -notmatch '\S' -or $_ -eq '`' }).Count
    $clean = @($ordered | Where-Object { $_ -match '\S' -and $_ -ne '`' })
    $keep = @($clean | Select-Object -Last $KeepLast)
    $drop = @($clean | Select-Object -SkipLast $KeepLast)
    $top = @($lines | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name)=$($_.Count)" })
    Write-Host "历史 $file"
    Write-Host "总数 $total;去重后 $($clean.Count)(杂 $junk);保留 $($keep.Count);归档 $($drop.Count)"
    Write-Host "重复 Top5: $($top -join ', ')"
    if ($drop.Count -eq 0 -and $junk -eq 0 -and $clean.Count -eq $total)
    {
        Write-Host '已是最简,无事可做。'
        return
    }
    if ($PSCmdlet.ShouldProcess($file, "瘦身 $total→$($keep.Count),归档 $($drop.Count) 行"))
    {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $file -Destination "$file.bak-$stamp" -Force
        $keep | Set-Content -LiteralPath $file -Encoding utf8NoBOM
        if ($drop.Count)
        {
            $archive = "$file.archive-$stamp.txt"
            $drop | Set-Content -LiteralPath $archive -Encoding utf8NoBOM
            Write-Host "已备份 $file.bak-$stamp,归档 $archive"
        }
        else { Write-Host "已备份 $file.bak-$stamp(无行需归档)" }
    }
}
function Import-CxxuConfig
{
    <#
    .SYNOPSIS
    读用户配置(默认 ~/.cxxu/config.psd1):只填环境变量的空位,不覆盖已设的值。
    .DESCRIPTION
    优先级:真正的环境变量 > 配置文件 > 默认(开)。缺文件静默跳过(首用零成本);
    文件坏了警告一次然后忽略,不挡 init。已知键见 New-CxxuConfigTemplate 模板,未知键忽略。
    init 首步自动调;改完配置重开终端(或 init -Force)生效。-Path 供测试/便携覆盖。
    .EXAMPLE
    Import-CxxuConfig
    #>
    [CmdletBinding()]
    param(
        # 配置文件路径(默认 ~/.cxxu/config.psd1,仓库外,本机生效)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $data = try { Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop } catch
    {
        Write-Warning "用户配置读失败($Path):$($_.Exception.Message);已忽略,用默认。"
        return
    }
    foreach ($key in @('PsFzf', 'PsZoxide', 'PsPredictor', 'PsTab', 'PsShowProgress', 'PsGithubMirror'))
    {
        if (-not [string]::IsNullOrEmpty((Get-Item "env:$key" -ErrorAction SilentlyContinue).Value)) { continue }
        if (-not $data.Contains($key)) { continue }
        $v = $data[$key]
        if ($null -eq $v -or "$v" -eq '') { continue }
        # 布尔转环境变量惯用字符串(True/False 正好命中各开关的正则)
        Set-Item "env:$key" -Value "$v"
        Write-Verbose "用户配置生效: $key=$v"
    }
}
function New-CxxuConfigTemplate
{
    <#
    .SYNOPSIS
    生成用户配置模板(默认 ~/.cxxu/config.psd1):有文件默认不动,加 -Force 覆盖。
    .DESCRIPTION
    模板里每个键都有注释(作用+取值);全 True = 默认行为,想关哪个改 False。
    记得:环境变量优先,注册表/Add-EnvVar 持久化的值会盖掉这里。
    .EXAMPLE
    New-CxxuConfigTemplate
    .EXAMPLE
    New-CxxuConfigTemplate -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 配置文件路径(默认 ~/.cxxu/config.psd1,仓库外,本机生效)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1'),
        # 已有文件也覆盖
        [switch]$Force
    )
    if ((Test-Path -LiteralPath $Path) -and -not $Force)
    {
        Write-Host "模板已存在($Path):改值直接编辑;重建加 -Force。"
        return
    }
    if ($PSCmdlet.ShouldProcess($Path, '写用户配置模板'))
    {
        $dir = Split-Path $Path -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        @'
@{
    # CxxuPsModules 用户配置(本机生效,仓库外;优先级:环境变量 > 本文件 > 默认开)
    # 改完重开终端(或 init -Force)生效;生成:New-CxxuConfigTemplate;读取:每次 init 自动。
    PsFzf          = $true  # PSFzf Ctrl+T 文件 / Ctrl+R 历史
    PsZoxide       = $true  # zoxide z 跳转
    PsPredictor    = $true  # CxxuPredictor 命令名预测(守护进程由启动链强制 False,不受此影响)
    PsTab          = $true  # CxxuTab 命令名 Tab 模糊补全(独立插件,见 Enable/Disable-PsPlugin)
    PsShowProgress = $true  # init 启动进度条
    PsGithubMirror = ''     # 为空走默认/静默测速;填镜像前缀如 'https://gh-proxy.com'
}
'@ | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
        Write-Host "模板已写 $Path"
    }
}
function Set-CxxuConfigValue
{
    # 写用户配置文件单键(供 Enable/Disable-PsPlugin -Persist 用,不导出):
    # 行级改写(保注释保其余键);无键则追到 } 前;无文件先建模板。失败警告,永不抛。
    param([string]$Path, [string]$Key, [bool]$Value)
    try
    {
        if (-not (Test-Path -LiteralPath $Path)) { New-CxxuConfigTemplate -Path $Path }
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $val = if ($Value) { '$true' } else { '$false' }
        $ls = $text -split '\r?\n'
        $done = $false
        for ($i = 0; $i -lt $ls.Count; $i++)
        {
            if ($ls[$i] -match ('^(?<ind>\s*)' + [regex]::Escape($Key) + '(?<rest>\s*=).*?(?<cmt>\s*#.*)?$'))
            {
                $ls[$i] = $Matches.ind + $Key.PadRight(15) + '= ' + $val + $Matches.cmt
                $done = $true
                break
            }
        }
        if (-not $done)
        {
            $at = @($ls).Count - 1
            for ($k = $ls.Count - 1; $k -ge 0; $k--) { if ($ls[$k] -match '^\s*\}\s*$') { $at = $k; break } }
            if ($at -le 0) { $ls = @("$Key = $val") + @($ls) }
            else { $ls = @($ls[0..($at - 1)]) + @("$Key = $val") + @($ls[$at..($ls.Count - 1)]) }
        }
        Set-Content -LiteralPath $Path -Value ($ls -join "`n") -Encoding utf8NoBOM -NoNewline
        Write-Host "用户配置已持久化: $Key=$val($Path)"
    }
    catch
    {
        Write-Warning "用户配置持久化失败($Path):$($_.Exception.Message)"
    }
}
function Disable-PsPlugin
{
    <#
    .SYNOPSIS
    停用体验插件(当会话生效;加 -Persist 长期禁用,重开也关)。
    .DESCRIPTION
    插件注册表：Fzf(PSFzf 快捷键)/Zoxide(z 跳转)/Predictor(命令名 ListView 预测)/
    Tab(CxxuTab 命令名 Tab 模糊)。停用只关本命令的合并/加载，引擎原生行为不受影响；
    持开关逐调用判定，无需重载。-Persist 写 ~/.cxxu/config.psd1（行级替换，保注释）。
    .EXAMPLE
    Disable-PsPlugin Tab
    .EXAMPLE
    Disable-PsPlugin Predictor -Persist
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 插件名(Tab 补全可用)
        [Parameter(Mandatory)]
        [ValidateSet('Fzf', 'Zoxide', 'Predictor', 'Tab')]
        [string]$Name,
        # 写入用户配置文件,长期有效(否则只关当会话)
        [switch]$Persist,
        # 配置文件路径(默认 ~/.cxxu/config.psd1)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    $key = @{ Fzf = 'PsFzf'; Zoxide = 'PsZoxide'; Predictor = 'PsPredictor'; Tab = 'PsTab' }[$Name]
    if ($PSCmdlet.ShouldProcess($Name, '停用插件'))
    {
        Set-Item "env:$key" -Value 'False'
        Write-Host "$Name 已停用(当会话)。"
        if ($Persist) { Set-CxxuConfigValue -Path $Path -Key $key -Value $false }
    }
}
function Enable-PsPlugin
{
    <#
    .SYNOPSIS
    启用体验插件(当会话生效;加 -Persist 长期启用,重开也开)。
    .DESCRIPTION
    启用是显式开(环境变量 True,盖过配置文件)。Tab/Predictor 即时生效(逐调用判定,
    无需重载);Fzf/Zoxide 下次 OnIdle 加载时生效(已加载的不受影响,或重开终端)。
    .EXAMPLE
    Enable-PsPlugin Tab
    .EXAMPLE
    Enable-PsPlugin Predictor -Persist
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 插件名(Tab 补全可用)
        [Parameter(Mandatory)]
        [ValidateSet('Fzf', 'Zoxide', 'Predictor', 'Tab')]
        [string]$Name,
        # 写入用户配置文件,长期有效(否则只开当会话)
        [switch]$Persist,
        # 配置文件路径(默认 ~/.cxxu/config.psd1)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    $key = @{ Fzf = 'PsFzf'; Zoxide = 'PsZoxide'; Predictor = 'PsPredictor'; Tab = 'PsTab' }[$Name]
    if ($PSCmdlet.ShouldProcess($Name, '启用插件'))
    {
        Set-Item "env:$key" -Value 'True'
        Write-Host "$Name 已启用(当会话)。"
        if ($Persist) { Set-CxxuConfigValue -Path $Path -Key $key -Value $true }
    }
}
