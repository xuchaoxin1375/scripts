# 其他函数都是通过start-InitPwsh来调用或间接调用的,在这里可以注释掉某些模块来帮助调试bug
function Start-Pwsh7Init
{
    param(
        [switch]$Fast
    )
    <# 
    .SYNOPSIS
    # 诸如颜色配置,只有powershell7才支持
    #>
    
    Set-PSReadLinesAdvanced

   
}
function Start-CoreInit
{
    <# 
  .SYNOPSIS
  # 诸如pwsh的快捷键,图标,列表颜色,上次prompt返回时间以及Prompt样式设置
  #>
    [CmdletBinding()]
    param(
    
    )
    # 早期执行部分:通用设置,可以放在前面执行的逻辑(或者任意地方):
    Set-PSReadLinesCommon
    Start-OptimizeForPSVersion
    
    Import-TerminalIcons
    # 设置prompt
    # 准备内存信息字段显示;读取PsEnvMode变量来显示当前环境变量等级
    Set-LastUpdateTime # *> $null
    Start-MemoryInfoInit
    # 设置prompt 
    Set-PromptVersion -version Balance
    #中期执行的部分
}

        
        
# function Set-CommonInit
# {
#     param(
#         [ValidateSet('Fast', 'Full')]$Mode = 'Fast'
#     )
#     $ModeBoolean = $Mode -eq 'Fast'
#     # 在你需要通过变量或者表达式来决定是否启用 switch 参数时，才需要使用 : 语法
#     Update-PwshEnv -Fast:$ModeBoolean
#     Start-CoreInit
# }



function Start-PwshInit0
{
    <# 
    .SYNOPSIS
    在已经打开的powershell中切换到一个新的shell环境
    .DESCRIPTION

    新加载的这个新环境会重新加载配置模,当您的模块发生变换时,执行此命令会更新环境以便于您检验模块修改后是否达到预期
    启动powershell时加载$profile是很耗时的,即便$profile中的内容不多,启动延迟也是令人难以接受的,通常命令行的响应延迟超过100ms就会让一部分人产生性能对机器或shell性能的怀疑和焦虑

    其实现方式就是嗲用pwsh程序,设置参数-noexit即-noe,这样新加载的shell环境就不会退出,然后用-c 执行命令init0,这个命令定义在自动加载模块中(自动加载并调用其中的逻辑这不会消耗时间,除非被调用的命令逻辑本身是耗时的)

    init0中编写满足一个环境的基本初始化设置的命令调用,例如提供基础的全局可用的变量,包括常用的字符串,最基础的常用路径变量(比如家目录中常用变量)
    .NOTES
    如果使用支持指定启动参数的Terminal,例如windows Termnial,那么可以通过指定启动参数为`pwsh -noe -c 'Start=PwshInit0'`来启动,这样也没有动用$profile;当在terminal中新建一个terminal时,会类似于$profile自动执行基础的初始化操作
    而输入pwsh时仍然能够保持最快的响应速度!因为此时pwsh仍然没有$profile读取和执行操作
    #>
    pwsh -noe -c 'init0'
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
function init0
{
    pwsh -noe -c { 
        Update-PwshEnv
        Start-CoreInit
    }
}
function init
{
    <#
    .SYNOPSIS
    这里配置需要自动运行的模块函数;不在此函数中列出的不会自动执行! 
    .DESCRIPTION
    这里组织的代码块分为早期，中期，和周期，当然也有些无所谓调用位置的，可以放到最后，提现重要性
    .Notes
    #psReadLines对于pwsh5从某些方式进入可能会不识别相关命令
    #目前已知单独打开pwsh5的窗口时可以正常加载这部分内容
    #但是从pwsh7中启子shell pwsh5会导致其不识别,尚不清除

    #>
    [CmdletBinding()]
    param (
        [switch]$NoNewPwsh
    )
    # 显示init调用时的时间
    # $start = Get-Time -TimeStap yyyyMMddHHmmssfff
    Get-Date
    
    if ($NoNewPwsh)
    {
        Set-CommonInit -Verbose:$VerbosePreference
        <# Action to perform if the condition is true #>
    }
    else
    {
        # # 无法直接通过$start名字访问外部变量
        $env:vbf = $VerbosePreference
        if ($VerbosePreference)
        {
            pwsh -noe -c {
                Set-CommonInit -Verbose:1
            }
        }
        else
        {
            pwsh -noe -c {
                Set-CommonInit -Verbose:0
            }
        }
        # 这里利用自动变量实现
        # $start | pwsh -noe -c { 
            
        #     Set-CommonInit;
        #     # calculate the timespan the init took
        #     $end = Get-Date
        #     # Write-Host "Init time: $span" -ForegroundColor Magenta 
        #     $start = $input | Select-Object -ExpandProperty datetime
        #     $start = [datetime]($start)

        #     $end = Get-Date

        #     $duration = $end - $start
        #     $span=$duration.TotalSeconds
        #     Write-Host "Init time: $span s" -ForegroundColor Magenta
        # }

        # Invoke-Command -ScriptBlock { 
        #     pwsh -noe -c
        #     { param($start)
        #         # Set-CommonInit;
        #         # $end = Get-Time -TimeStap yyyyMMddHHmmssfff
        #         $end = Get-Date
        #         $span = $end - $start
        #         Write-Host "Init time: $span" -ForegroundColor Magenta 
        #     }
        # } -ArgumentList $start
    }
    # 结尾被上面的pwsh -noe会阻塞，后面的代码需要到上面的pwsh退出后才会执行,如果需要测量内部加载时间,得需要在内部执行时间计算
    Get-Date

}
function Start-MemoryInfoInit
{

    $OS = Get-CimInstance -ClassName Win32_OperatingSystem
    $env:cachedTotalMemory = $OS.TotalVisibleMemorySize / 1MB
    $env:cachedFreeMemory = $OS.FreePhysicalMemory / 1MB
}
function Start-OptimizeForPSVersion
{

    #目前采用 start $env:systemRoot\system32\WindowsPowerShell\v1.0\powershell.exe 作为pwsh5函数内容
    if ($PSVersionTable.PSVersion.Major -ge 7)
    {
        Start-Pwsh7Init
    }
    else
    {
        Write-Verbose "You are using powershell [[$($PSVersionTable.psversion)]]"
           
        # write-verbose 'try run [ Set-ExecutionPolicy -ExecutionPolicy Bypass ]'
    }
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

function Import-TerminalIcons
{
    [cmdletbinding()]
    param()
    if (!(Get-Module -ListAvailable -Name Terminal-Icons))
    {
        Write-Host 'Terminal-Icons module not Found!'
        $r = Read-Host -Prompt 'Try to install it ? (estimate 5-10s) [y/n]'
        if ($r.ToUpper() -eq 'Y')
        {

            Install-Module Terminal-Icons -Force
            
        }
        else
        {
            # 用户拒绝安装，直接退出
            return
        }
    }
    # 导入模块（这里确保已经安装上了模块）
    Import-Module Terminal-Icons -ErrorAction Ignore
}

function Set-PSReadLinesAdvanced
{
    [cmdletbinding()]
    param()
    <# beautify the powershell interactive interface  #>
    # modify the color of the inlinePrediction:
    Write-Verbose ('loading psReadLines & keyHandler!(advanced)' + "`n")
    Set-PSReadLineOption -PredictionSource History # 设置预测文本来源为历史记A
    
    <# set colors #>
    Set-PSReadLineOption -Colors @{'inlineprediction' = '#d0d0cb' }#grayLight(grayDark #babbb4)
    <# suggestion list #>
    # Set-PSReadLineOption -PredictionViewStyle ListView
    # Set-PSReadLineOption -EditMode Windows
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
