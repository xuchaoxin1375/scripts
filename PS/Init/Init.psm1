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
        [switch]$Force
    )

    Write-Host 'initing...'
    # 使用临时环境$env:Psinit会引发副作用(子作用域的pwsh也会继承此变量),这里限制其作用域,使用普通变量(局部)
    #考虑到$profile和wt中的启动参数同时调用init,都是同一个作用域,不需要第二个作用域访问到此标记变量,因此使用普通变量即可(同一个会话内可以访问)
    if ($Force -or $null -eq $PsInit)
    {
        Write-Verbose 'Init pwsh env...'
        # $env:PsInit = 'True' 
        $global:PsInit = $True

    }
    else
    {

        Write-Verbose 'Init work loadded !' -Verbose
        return
    }


    # 获取当前日期时间
    $startTime = Get-Date
    Set-LastUpdateTime
    $tasks = {
        # 导入图标模块(建议放到extension部分中)
        # Import-TerminalIcons
        # Import-ANSIColorEnv
        # 补全模块PSReadline及其相关配置
        Set-PSReadLinesCommon
        Set-PSReadLinesAdvanced
        Set-ArgumentCompleter
        Confirm-EnvVarOfInfo
        Set-PsExtension 
        
        # 设置prompt样式(这里面会导入基础的powershell预定变量和别名)
        Set-PsPrompt  
        Confirm-DataJson
    }
    $taskScriptStr = $tasks.ToString()
    # 原始多行字符串

    # 提取非注释行
    $TaskLines = $taskScriptStr -split "`n" 
    | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' }
    | ForEach-Object { $_.Trim() }

    $report = @()
    $i = 0
    $count = $TaskLines.Count
    $PSStyle.Progress.View = 'Classic'
    foreach ($line in $TaskLines)
    {

        $Completed = [math]::Round($i++ / $count * 100, 1)
        Write-Progress -Activity 'Loading... ' -Id 0 -Status "$line -> Processing: $Completed%" -PercentComplete $Completed
            
        # Write-Verbose "Loading $line " # -ForegroundColor DarkCyan   
        Write-Information "Loading $line " #-ForegroundColor DarkCyan # -NoNewline #配合执行时间显示

        # & $line #不支持参数解析,不好用
        # Invoke-Command -ScriptBlock { $line } #作用域不在当前会话

        #iex 支持当前会话作用域，但是速度较慢
        # $line | Invoke-Expression

        $res = Measure-Command { Invoke-Expression $line -OutVariable out }
        Write-Output $out #从Measure-commnd 内部获取输出


        $time = [int]$res.TotalMilliseconds
        # Write-Host "time: $time " -ForegroundColor Magenta
        # 整理为表格对象(总结报告加载情况)
        $res = [PSCustomObject]@{
            Command = $line
            Time    = $time
        }
        $report += $res
        # $res | Format-Table
        # return $res 
            
        # Start-Sleep -Milliseconds 500
    }

    if ($InformationPreference)
    {
        $report | Sort-Object Time -Descending | Format-Table -AutoSize
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
    Start-CoreInit -Verbose:$VerbosePreference
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

    Set-PSReadLineOption -PredictionSource HistoryAndPlugin # 设置预测文本来源为历史和插件
    Set-PSReadLineOption -PredictionViewStyle ListView -BellStyle None  #使用视图列表显示预测后选
    # listView列表设置
    Set-PSReadLineOption -MaximumHistoryCount 3000  # 可选：增大历史记录总数
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
