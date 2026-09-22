

# '-----------------add function below-----------'

function Restart-TrafficMonitor
{
    Get-Process 'trafficMonitor*' | Stop-Process
    trafficMonitor 
}
function Get-Fonts()
{
    # [System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')
    (New-Object System.Drawing.Text.InstalledFontCollection).Families
}



function wiki2latex
{
    param(
        [Parameter(ValueFromPipeline)]
        [String]
        $content = (Get-Clipboard)
    )
    process
    {
        $content>$tmp_clipboard
        py "$repos\pythonLearn\scripts\wiki_deal_bracket.py"
        $data_out = (Get-Content $tmp_clipboard)
        # write-host $data_out
        $data_out | Set-Clipboard
    }
}
function ty2latex
{
    <# 
    .SYNOPSIS
    将字符串中的 \(,\) 转换成 $
    将字符串中的 \[,\] 转换成 $$
    .EXAMPLE
    PS>ty2latex '$\left( \frac{1}{2} \right)$'
    #>

    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline)]
        $String,
        $Path = "$home\desktop\ty2latex.txt"
    )
    #默认从文件中读取内容
    if (!$String)
    {
        if (Test-Path $Path)
        {
            $String = Get-Content $Path
        }
        $String = Get-Clipboard
    }
    #方案1:正则匹配
    $res = $String -replace '(\\\(\s*)|(\s*\\\))', '$' -replace '(\\\[\s*)|(\s*\\\])', '$$$$'
    #方案2:精准替换(容错性不足,但是规则简单,使用字符串的Replace()函数)
    # $res=$String.replace('\(','$').replace('\)','$').replace('\[','$$').replace('\]','$$')

    # $res = $String 
    $res | Set-Clipboard
    $res
}
function wechat_second
{
    Start-ProgramInSandboxie -Program (Get-ShortcutPath wechat)
}
function startup_register
{
    # 先定位到 HKEY_USERS 下对应的 SID 键
    $SID = 'S-1-5-21-1150093504-2233723087-916622917-1001'
    $keyPath = "Registry::HKEY_USERS\$SID\Software\Microsoft\Windows\CurrentVersion\Run"

    # 列出该路径下的注册表键及其值
    Get-ItemProperty -Path $keyPath
}
# function Get-RandomColorName {
#     <# 
#     .SYNOPSIS
#     随机地从颜色数组中获取一种颜色名字返回
#     #>
#     $colors = @('Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta', 'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan', 'Red', 'Magenta', 'Yellow', 'White')

#     $colors | Ge-Random
    
# }
function wechat_multiple
{
    <# 
    .SYNOPSIS
    模拟短时间内点击多次微信弹出多个登录窗口
    如果报错,则可能是微信安装路径出错,请检查微信安装路径

    说明:本程序会判断是否已经有微信进程,如果没有微信进程,则直接打开多个登录窗口
    否则会询问用户是否关闭所有微信进程,以便于多开微信
    (因为这里采用的方法要求在没有微信进程的情况下运行才能生效;在未来,微信可能自带支持多开功能,就像多开qq一样方便)
    但是中所周知,微信团队比qq团队要懒,很多地方没有做好,功能比较受限,可能相当长的时间微信不会主动支持多开
    
    .EXAMPLE
    PS C:\repos\scripts> wechat_multiple -multiple_number 2
        wechat is running,stop all wechat process to start multiple wechat?
        Enter 'y' to continue😎('N' to exit the process!)  : y

    PS C:\Program Files\Typora> wechat_multiple
    2 wechat login process were started!😊
    #>

    param(

        # 配置为自己的微信安装目录即可(注意末尾WeChat是目录)
        $wechat_home = '$wechat_home' ,
        # 可以自行指定多开数量
        $multiple_number = 2
    )

    if (Get-Process | Select-String wechat)
    {
        # 读取键盘输入(read input by read-host)
        $Inquery = Read-Host -Prompt "wechat is running,stop all wechat process to start multiple wechat? `n Enter 'y' to continue😎('N' to exit the process!)  "
        if ($Inquery -eq 'y')
        {
            # 关闭微信进程,以便多开微信
            Get-Process wechat | Stop-Process        
        }
        else
        {
            Write-Host 'operation canceled!'
            return
        }
    }
    # 程序的主体部分
    foreach ($i in 1..$multiple_number)
    {
        Start-Process $wechat_home\wechat.exe
    }

    Write-Host "$multiple_number wechat login processes were started!😊"
}



function downkyi_clickToLaunch
{

    explorer "$bilibiliDownloader_home"
} 

function remove_colors_icons
{
    param (
    )
    # keep the icons but remove colors except black texts
    <# PS C:\Users\cxxu\Downloads\Compressed> h terminal-icons

    Name                              Category  Module                    Synopsis
    ----                              --------  ------                    --------
    Set-TerminalIconsTheme            Function  Terminal-Icons            Set the Terminal-Icons color or icon theme
    Set-TerminalIconsIcon             Function  Terminal-Icons            Set a specific icon in the current Terminal-Icons icon theme or allows…
    #>
    Set-TerminalIconsTheme -DisableColorTheme
    # Remove-Module Terminal-Icons 
}
function ps_group
{
    Get-Process | Group-Object ProcessName | Sort-Object Name
}





function rpg
{
    Remove-Module posh-git
    Remove-Module oh-my-posh  
}

function ord
{

    param(
        $char
    )
    [byte][char]"$char"
}
function chr
{
    param(
        $ascii_value = 0
    )
    [char][int]"$ascii_value"
}


function BT
{
    Start-Process http://123.56.72.67:8888/d97fbc20
}

function colorPicker_vscode
{
    c $blogs\styles\colorPicker.css 
}

function getAssembler_att
{
    param(
        $fileName
    )
    g++ -S $fileName 
}
function getAssemble_intel
{
    param(
        $fileName
    )
    g++ -S -masm=intel $fileName -o "$($fileName)_intel"       
}

function Start-ProgramInSandboxie
{
    <#
    .SYNOPSIS
    在sandboxie沙盒中启动指定的程序

    .PARAMETER InputObject
    当使用管道传递文件名时，此参数接收从管道中传入的字符串（即文件路径）。

    .PARAMETER Program
    指定要读取的文件路径。当直接通过参数指定文件路径时，使用此参数。

    .EXAMPLE

    #>

    # 使用 CmdletBinding 提供默认参数集、支持 ShouldProcess 等特性
    [CmdletBinding(DefaultParameterSetName = 'Pipe')]

    # 定义函数参数
    # 这里定义了两个参数集:Pipe,Program
    # 通过管道符传递文件名时,激活的时前者,否则用参数传递的,激活的是后者
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ParameterSetName = 'Pipe')]
        [string]$InputObject,


        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Program')]
        [string]$Program
        
    )

    # process 区块：处理从管道或其他方式输入的对象
    process
    {
        # 根据当前激活的参数集获取文件内容
        if ($PSCmdlet.ParameterSetName -eq 'Pipe')
        {
            sandbox_start $InputObject
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Program')
        {
            sandbox_start $Program
        }
       
    }
}

function Set-WindowsUpdate
{
    $path = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows'
    #以下命令为强制写入,使用/f
    reg add $path /v WindowsUpdate /t REG_SZ /d '' /f
    reg add 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' /v AUOptions /t REG_DWORD /d 1 /f 
}

function Get-DateTimeNumber
{
    <# 
    .SYNOPSIS
    获取时间,格式为yyyyMMDDHHmm (仅包含数字)
    HH 是24小时制
    hh 是12小时制
    获取时间不是很常用,这里给它标记一下
    #>
    param(
        $Format = "yyyyMMddHHmm"
    )
    $res = Get-Date -Format $Format
    return $res
}
function Get-DateTime
{
    <# 
    .SYNOPSIS
    返回当前日期和时间,包含年,月,日等文字
    #>
    return (Get-Date -DisplayHint DateTime)
}
function Get-Time
{
    <# 
.DESCRIPTION
    使用SetSecondsToZero参数来设置秒数为0,可以让windows语音播报时间为读出小时和分钟,适用于整点报时脚本
 #>
    [CmdletBinding()]
    param(
        $Format = 'HH:mm:ss',
        [switch]$NoSeconds,
        [switch]$SetSecondsToZero,
        [ValidateSet('yyyyMMddHHmmssfff', 'yyyyMMddHHmmss')]$TimeStap
    )

    Write-Verbose $Format
    # $Format = if ($NoSeconds) { $Format -replace ':ss', '' }
    if ($NoSeconds)
    {

        $Format = $Format -replace ':ss', ''
    }
    elseif ($SetSecondsToZero)
    {

        $Format = $Format -replace ':ss', ':00'
    }
    elseif ($TimeStap)
    {
        $timestamp = Get-Date -Format 'yyyyMMddHHmmssfff'
        return $timestamp
    }
    Write-Verbose $Format
    $Time = Get-Date -Format $Format
    return $Time
    
}


function u20
{
    ssh cxxu@u20
}


function Get-WslInfo
{
    wsl -l -v
    Write-Host '参考内容:https://blog.csdn.net/xuchaoxin1375/article/details/112004891?ops_request_misc=%257B%2522request%255Fid%2522%253A%2522166341800516782425199224%2522%252C%2522scm%2522%253A%252220140713.130102334.pc%255Fblog.%2522%257D&request_id=166341800516782425199224&biz_id=0&utm_medium=distribute.pc_search_result.none-task-blog-2~blog~first_rank_ecpm_v1~rank_v31_ecpm-1-112004891-null-null.nonecase&utm_term=wsl2&spm=1018.2226.3001.4450'
}



function Get-EdgeUpdaterPath
{
    <# 
    .SYNOPSIS
    获取edge update的路径并返回,通常不会直接调用,而是由Set-EdgeUpdater调用
    #>
    # 以管理员权限打开一个shell窗口,保证防火墙能够顺利配置
    # 创建一个正则表达式对象
    $path_raw = 'reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\edgeupdate /v ImagePath' | Invoke-Expression
    $regex = [regex] '"(.*)"'
    # 对字符串执行匹配并获取所有匹配项
    $all_matches = $regex.Matches($path_raw)
    $edge_updater_path = $all_matches[-1].Value -replace '"', ''

    return $edge_updater_path
    #通常这个路径是:"C:\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"

}
function Set-EdgeUpdater
{
    <# 
    .SYNOPSIS
    设置edge update是否启用(通过配置防火墙实现)

    .EXAMPLE
    PS>set-EdgeUpdater -Disable

    Rule Name:                            Disable Edge Updates
    ----------------------------------------------------------------------
    Enabled:                              Yes
    Direction:                            Out
    Profiles:                             Domain,Private,Public
    Grouping:
    LocalIP:                              Any
    RemoteIP:                             Any
    Protocol:                             Any
    Edge traversal:                       No
    Action:                               Block
    Ok.

    there is already a rule of disable edge update,enable it...

    Updated 1 rule(s).
    Ok.


    Rule Name:                            Disable Edge Updates
    ----------------------------------------------------------------------
    Enabled:                              Yes
    Direction:                            Out
    Profiles:                             Domain,Private,Public
    Grouping:
    LocalIP:                              Any
    RemoteIP:                             Any
    Protocol:                             Any
    Edge traversal:                       No
    Action:                               Block
    Ok.
    #>
    param(
        [switch]$Enable,
        [switch]$Disable
    )
    $deu = 'Disable Edge Updates'
    if ($Enable)
    {
        #将禁止edge update的规则禁用,就是恢复edge update
        netsh advfirewall firewall set rule name=$deu new enable=no

    }
    elseif ($Disable)
    {
        #方案1:删除防火墙规则(比较简单的做法)
        # netsh advfirewall firewall delete rule name=$deu
        # 方案2:禁用防火墙规则(为了避免反复配置相同的规则,需要一定的判断逻辑,更加安全)
        netsh advfirewall firewall show rule name=$deu
        if ($?)
        {
            Write-Host 'there is already a rule of disable edge update,enable it...'
            netsh advfirewall firewall set rule name=$deu new enable=yes
        }
        else
        {

            Write-Host 'create a new rule of disable edge update...'
            $edge_updater_path = Get-EdgeUpdaterPath
            #修改防火墙需要管理员权限,因此在此操作之前,以管理员权限打开一个shell窗口(如果已经处于管理员窗口,则直接执行下面的语句)
            netsh advfirewall firewall add rule name=$deu dir=out action=block program=$edge_updater_path
        }
    }
    # 配置完检查结果
    netsh advfirewall firewall show rule name=$deu
}


# if ( ( Get-Location | Resolve-Path).ToString() -eq "django" )
function Test-MainPC
{
    <# 
    .SYNOPSIS
    return whether the current Pc is the main PC or not.
    #>
    return (Get-MotherBoardInfo).SerialNumber -eq $PC1

}


function Set-DoubleOwnerOfRepos
{
    param (
        
    )
    $reps = @('configs', 'blogs', 'scripts')
    
    foreach ($rep in $reps)
    {

        git config --global --add safe.directory "D:/repos/$rep"
    }
    
}
function Test-CxxuComputer
{
    <# 
    .SYNOPSIS
    测试当前机器是否为Cxxu所属或使用的设备
    #>
    param (
        $CxxuComputers = $CxxuComputers
    )
    Update-PwshvarsIfNotYet
    Write-Verbose "$CxxuComputers"
    # Update-PwshEnvIfNotYet
    return  [System.Environment]::MachineName -in @($CxxuComputers)

    
}


function reboot
{
    param(
        $timeOut = 0
    )
    # cmd中可以利用shutdown /r重启,/t指定倒计时时间
    # Shutdown /r /t $timeOut
    Restart-Computer
}


function timer_tips
{
    param(

        $i = 5
    )
    while ($i--)
    {
        Start-Sleep -Seconds 1
        Write-Host ($i + 1)

    }
}
function Test-IsAdministrator
{
    <#
    .SYNOPSIS
        判断当前 PowerShell 进程是否以管理员权限运行。

    .DESCRIPTION
        Test-IsAdministrator 检测当前 PowerShell 进程的访问令牌是否包含
        Windows 内置 Administrators 角色。

        该函数用于判断当前进程是否“已提升”，不是判断当前用户账户是否“属于管理员组”。

        在 UAC 开启的 Windows 系统中：
        - 用户属于 Administrators 组，但 PowerShell 未以管理员身份运行：返回 $false
        - 用户属于 Administrators 组，且 PowerShell 已提升运行：返回 $true
        - 标准用户：返回 $false

    .OUTPUTS
        System.Boolean

    .EXAMPLE
        Test-IsAdministrator

    .EXAMPLE
        if (-not (Test-IsAdministrator)) {
            Write-Error "请以管理员身份重新运行此脚本。"
            exit 1
        }

    .EXAMPLE
        #Requires -RunAsAdministrator

        如果你的整个脚本都必须管理员运行，也可以直接使用 PowerShell 的 requires 声明。
        但 Test-IsAdministrator 更适合做条件判断、自定义错误信息或自动重启提升。

    .NOTES
        Platform: Windows
        Compatible with:
        - Windows PowerShell 5.1
        - PowerShell 7+

        返回 $false 的情况：
        - 当前进程未提升
        - 当前系统不是 Windows
        - 当前运行环境不支持 WindowsIdentity
        - 检测过程中发生异常
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # PowerShell 7+ 有 $IsWindows；Windows PowerShell 5.1 没有。
    # 因此这里用 RuntimeInformation 或环境变量做兼容判断。
    $isWindowsPlatform = $false

    try
    {
        if (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue)
        {
            $isWindowsPlatform = $IsWindows
        }
        else
        {
            $isWindowsPlatform = $env:OS -eq 'Windows_NT'
        }

        if (-not $isWindowsPlatform)
        {
            return $false
        }

        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)

        return $principal.IsInRole(
            [System.Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }
    catch
    {
        return $false
    }
}
function Test-AdminPermission
{
    <#
.SYNOPSIS
    Determines whether the current user has administrative privileges.
    This is a very useful function to prevent misleading error messages casued by a permission insufficiency.

    many actions need admin permission to run,with the common permission it will be failed.In ideail cases,the command return a 'Permission denied' error message,but some other will return other errors which is not cleared as 'Permission denied',Such as :`Set-Acl: Some or all identity references could not be translated.`
    That's not good for us to judge why the action of the command failed.

    so if you now certain function need admin permission, you can use this function to check to exclude many unnecessary error messages.

.DESCRIPTION
    This function uses the [Security.Principal.WindowsIdentity] class to check
    whether the user belongs to the Administrators group. It returns $true if the
    user is a member of the Administrators group and $false otherwise.

.EXAMPLE
    Test-AdminPermission

    This example calls the Test-AdminPermission function and displays the
    result.

.INPUTS
    None. This function does not accept any input.

.OUTPUTS
    System.Boolean

    This function returns a boolean value. If the user is a member of the
    Administrators group, the function returns $true; otherwise, it returns
    $false.
#>

    # 5.1 无 $IsWindows($null),PSEdition Desktop 即 Windows,防误入 Linux 分支
    if (($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows)
    {
        # Windows 逻辑：检查 SID
        return ([Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544')
    }
    else
    {
        # macOS/Linux 逻辑：检查有效用户 ID 是否为 0 (root)
        # 也可以使用：id -u
        return (id -u) -eq 0
    }

}

function Test-AdminPermission2
{
    param (
    )
    if ( ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    {
        return $true
    }
    else
    {
        return $false
    }
    
}

# 注:Disable-CredentialGuard 唯一定义在 Security 模块,此处原有一份重复定义已删除
#(旧版本含 exit 语句,非管理员调用时会直接退出 shell,不安全)

function jupyter2markdown
{
    param(
        $jupyter_file = './*ipynb',
        $format = 'markdown'
    )
    jupyter nbconvert $jupyter_file --to markdown
}

function Write-SeparatorLine
{
    param (
        $borderUnit = '-~',
        $timesOfRepeat = 30
    )
    # $border = ''
    $border = $borderUnit * $timesOfRepeat
    <#     # write-host 50*$borderUnit
    # for ($i = 0; $i -lt $timesOfRepeat; $i++)
    # {
    #     # $border = $border + $borderUnit
    #     $border += $borderUnit
    # } #>
    # write-host $border
    # return语句也会自动打印出来
    return $border
}
#----------------------------
# Write-SeparatorLine > 5
function gcmw
{
    param (
        $pattern
    )
    $wildcardPattern = "*$pattern*"
    Write-Host "🥰result returned by gcm wildcard:$wildcardPattern"
    Write-SeparatorLine
    Get-Command $wildcardPattern
    # write-host "🥰result returned by help"
    Write-SeparatorLine
    # Get-Help $wildcardPattern
    # help $Pattern |Format-Table |write-host

}
# gcmw screen

function clock
{
    node $scripts\jsScripts\clock.js
}
function javav
{
    java -version
}



function EnvironmentRequireTips
{
    Write-Host "💕you are try to run the python script; `n 💕if it does not work, please check the [`py`] command to check the python enviroment to locate the exceptions."
}




function Restart-Explorer
{
    param (
        
    )
    # for powershell ,to restart the explorer just need a cmdlet(more simple than command in cmd like bellow.)
    Stop-Process -Name explorer 
    # taskkill /f /im explorer.exe 
    # Start-Process explorer.exe
}


function Restart-Process
{
   
    <#
.SYNOPSIS
    重启指定的进程。指定参数的形式类似于stop-process,支持管道符
    为了简单起见,没有实现想Get-process 那样tab键自动补全进程名的功能

.DESCRIPTION
    该函数用于重启指定的进程。它可以根据进程的名称、ID 或直接传递的进程对象来停止和重新启动进程。
    特别适用于需要重启 Windows 资源管理器 (explorer.exe) 的情况。
    
.PARAMETER Name
    要重启的进程的名称（不包括扩展名）。例如：'explorer'。

.PARAMETER Id
    要重启的进程的 ID。

.PARAMETER InputObject
    要重启的进程对象。

.EXAMPLE
    Restart-Process -Name 'explorer'
    该示例将重启 Windows 资源管理器。

.EXAMPLE
    Restart-Process -Id 1234
    该示例将重启进程 ID 为 1234 的进程。

.EXAMPLE
    Get-Process -Name 'explorer' | Restart-Process
    该示例将重启通过管道传递的进程对象。

.NOTES
    作者: cxxu1375
#>

    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param (
        [Parameter(ParameterSetName = 'ByName', ValueFromPipelineByPropertyName = $true, Mandatory = $true, Position = 0, HelpMessage = 'Enter the name of the process to restart.')]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName = $true, Mandatory = $true, Position = 0, HelpMessage = 'Enter the ID of the process to restart.')]
        [int]$Id,

        [Parameter(ParameterSetName = 'ByInputObject', Mandatory = $true, ValueFromPipeline = $true, HelpMessage = 'Enter the process object to restart.')]
        $InputObject
    )
    
    process
    {
        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'ByName')
            {
                # 通过名称获取进程对象
                $process = Get-Process -Name $Name -ErrorAction Stop
              
                
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ById')
            {
                # 通过ID获取进程
                $process = Get-Process -Id $Id -ErrorAction Stop
               
                
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ByInputObject')
            {
                $process = $InputObject
                
            }
            # 获取第一个进程(同一个软件可能创建了多个进程,或者说多个进程可能有共同的ProcessName,这里从中选出一个进程对象)
            $fp = $process[0]
            Write-Verbose $fp
            # 获取进程对应软件的路径
            $s = $fp.Path
            Write-Verbose "Performing the operation `"restart-process`" on target `"$process`" "
            Write-Debug "Process path: $s"
            
            # 重启软件进程:先关闭目标进程,然后根据先前获取的目标进程对应的软件的路径,来启动目标进程
            Stop-Process $process -Verbose:$VerbosePreference 
            Start-Process -FilePath $s -Verbose:$VerbosePreference
        }
        catch
        {
            Write-Error "Failed to restart process. $_"
        }
    }
}

# 调用函数重启进程
# Restart-Process -ProcessName $Name


function time_show
{
    param (
        
    )
    EnvironmentRequireTips    
    py $scripts\pythonscripts\timer.py
}



function btm_cxxu
{
    btm --color nord-light
}

<# functions with parameters #>

function Get-ModuleByCxxu
{
    <#
    .SYNOPSIS
    获取CxxuPSModulePath下的模块信息(2026-09-21 从 Info 迁入:Info 留 7,查询命令要 5.1 可用)。
    .DESCRIPTION
    如果需要进一步调整信息显示，可以利用管道符进一步处理,比如排序等
    #>
    param(
        [switch]$SkipUnavailable
    )
    # $env:CxxuPSModulePath 未设置(如 5.1 裸会话)时回退到本模块所在仓库根,行为与设置时一致
    $root = if ($env:CxxuPSModulePath) { $env:CxxuPSModulePath } else { Split-Path $PSScriptRoot -Parent }
    $res = Get-Module -ListAvailable | Where-Object { $_.ModuleBase -like "$root*" }
    # $res = $res | Where-Object { $_.ExportedCommands }
    if ($SkipUnavailable)
    {

        $res = $res | Where-Object { $_.ExportedCommands.Count }
    }
    return $res

}

function Get-ContentUTF8
{
    <#
    .SYNOPSIS
    按 UTF-8 读文本文件(5.1 的 Get-Content 默认按系统 GBK 解码,无 BOM 中文必乱码;外部文件控不了编码,只能读侧解决)。
    .DESCRIPTION
    .NET 读文件默认即 UTF-8 且自动识别 BOM,有/无 BOM 通吃,5.1/7 行为一致。
    默认逐行输出(同 Get-Content),-Raw 整文返回。
    .EXAMPLE
    Get-ContentUTF8 README.md
    Get-ContentUTF8 C:\tmp\notes.md -Raw
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $Path,
        [switch]$Raw
    )
    foreach ($r in @(Resolve-Path -Path $Path -ErrorAction Stop))
    {
        if ($Raw) { [IO.File]::ReadAllText($r.ProviderPath) }
        else { [IO.File]::ReadAllLines($r.ProviderPath) }
    }
}


