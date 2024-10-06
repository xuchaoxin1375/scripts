

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
    if ($Force -or $null -eq $env:PsInit)
    {
        Write-Verbose 'Init pwsh env...'
        $env:PsInit = 'True' 

    }
    else
    {

        Write-Verbose 'Init work already done!' 
        return
    }

    $startTime = Get-Date

    $tasks = {
        # 设置prompt样式(这里面会导入基础的powershell预定变量和别名)
        Set-PromptVersion Balance 
        # 导入图标模块
        # Import-TerminalIcons
        # 补全模块PSReadline及其相关配置
        Set-PSReadLinesCommon
        Set-PSReadLinesAdvanced
        Set-ArgumentCompleter
        Confirm-EnvVarOfInfo
        Set-PsExtension 
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

        $res = Measure-Command {  Invoke-Expression $line -OutVariable out }
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
    打开新的powershell环境，加载最基础的列表图标模块
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
    # 处理$profile 和windows terminal 中的携带参数启动pwsh冲突或重复关系
    if ($null -eq $env:PsInit)
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
        pwsh -noe -noprofile -c {init -Force -InformationAction continue}
    }
}
function Set-PsExtension
{
    <# 
.SYNOPSIS
是否启用额外的相关扩展
.DESCRIPTION
检查环境变量extent,如果取值为True,那么指导用户安装或启用相应的模块
否则跳过不处理这部分扩展内容
#>
    [CmdletBinding(DefaultParameterSetName = 'PsExtension')]
    param (
        [parameter(ParameterSetName = 'PsExtension')]
        # 要安装的模块列表
        #按照实用性排序
        $modules = @(
            #第一梯队
            'CompletionPredictor'
            # 'ZLocation'
            #第二梯队
            'z'
            # 'Terminal-Icons'
        ),
        # 安装模块的范围
        [ValidateSet('CurrentUser', 'AllUsers')]$Scope = 'CurrentUser',
        # 是否启用额外的相关扩展
        [parameter(ParameterSetName = 'Switch')]
        [ValidateSet('On', 'Off')]
        [parameter(Position = 0)]
        # 出于加载速度和轻便性考虑，不默认启用这部分扩展功能
        $Switch = 'Off'
    )
    if ($PSCmdlet.ParameterSetName -eq 'Switch')
    {

        if ($Switch -eq 'Off')
        {
            
            Write-Verbose 'Skip pwsh extension functions!' -Verbose
            Set-EnvVar -Name 'PsExtension' -NewValue 'False'
        }
        elseif ($Switch -eq 'On')
        {
            
            Set-EnvVar -Name 'PsExtension' -NewValue 'True'
        }
    }
    elseif ($env:PsExtension -eq 'True')
    {

        # scoop 相关
        # Invoke-Expression (&scoop-search --hook)
        # 检查模块是否已经安装,必要时安装对应的模块
        $i = 0
        $count = $modules.Count
        $report = @()
        # $AvailableModules = Get-Module -ListAvailable #性能不佳，不做-Name的话会耗费几百毫秒
        foreach ($module in $modules)
        {
            # 获取指定模块是否可用
            $moduleAvailability = Get-Module -ListAvailable -Name $module #查询一个要几十毫秒
            if ($moduleAvailability)
            {
                Write-Verbose "Module $module is already installed"
            }
            else
            {
                Install-Module -Name $module -Scope $Scope -Force
            }

            # Write-Verbose "Importing module $module" -Verbose
            # $moduleAvailability | Import-Module 
            # 执行导入操作
            # Import-Module $module 
            $res = Measure-Command { 
                Import-Module $module -Verbose:$false
            }
            
            #显示进度条
            $completed = [math]::Round($i++ / $count * 100, 1)
            # Start-Sleep -Milliseconds 500
            Write-Progress -Activity 'Importing Modules... ' -Id 1 -ParentId 0 -Status " $module progress: $completed %" -PercentComplete $completed

            #准备报告导入情况信息 
            $time = [int]$res.TotalMilliseconds
            $res = [PSCustomObject]@{
                Module = $module
                time   = $time
            }
            $report += $res
        }

        $totalTime = $report | Measure-Object -Property time -Sum | Select-Object -ExpandProperty Sum
        # 准备视图
        $report = $report | Sort-Object -Descending time # | Format-Table #| Out-String 
        
        
        if ($InformationPreference)
        {
            # Write-Host $report
            Write-Output $report 

            Write-Verbose "Time Of importing modules: $($totalTime)" -Verbose
        }
        # return $report
        #其他模块导入后的提示信息
        # Write-Host -Foreground Green "`n[ZLocation] knows about $((Get-ZLocation).Keys.Count) locations.`n"
    }
    
}


function Add-CxxuPsModuleToProfile

{
    <# 
    .SYNOPSIS
    将此模块集推荐的自动加载工作添加到powershell的配置文件$profile中
    .DESCRIPTION
    从$profile中移除
    
    .PARAMETER ProfileLevel
    默认情况下写入的是$Profile.CurrentUserCurrentHost
    您也可以选择其他等级的配置,例如最大作用等级$Profile.AllUsersAllHosts
    .Notes
    注意,为所有用户设置需要管理员权限
    .NOTES
    如果要移除,则建议通过编辑对应级别的$Profile来移除相关语句
    比如 移除命令p
     #>
    param (
        $ProfileLevel = $Profile
    )
    $pf = $ProfileLevel
    '# AutoRun commands from CxxuPsModules' + " $(Get-Date)" >> $pf
    {
        # p -NoNewShell
        init 

    }.ToString().Trim()>>$pf #向配置文件追加内容
    '# End AutoRun commands from CxxuPsModules' >> $pf
}
function Add-CxxuPsModuleToEnvVar
{
    <# 
    .SYNOPSIS
    在调用此函数前需要你配置好环境变量
    或者修改$env:PsmodulePath=";$CxxuPsModulePath"
    .DESCRIPTION
    默认仅为当前用户的psmodulepath添加此模块集的路径,部分情况下,比如通过nsudo使用trustedInstaller权限的pwsh窗口中,是不访问用户级别的环境变量的,你需要将$CxxuPsModulePath添加到系统级别的PsModulePath路径中才有效
    使用次函数方便这个过程
    或者在删除了$CxxuPsModulePath后重新设置的时候调用一下把路径加回去
    .EXAMPLE
    Add-EnvVar PSModulePath $env:PSModulePath -Scope Machine 
    #>
    param (
        [ValidateSet('Machine', 'User')]$Scope = 'User'
    )
    # $CxxuPsModulePath = "../$PsScriptRoot"
    $CxxuPsModulePath = $env:CxxuPsModulePath 
    Write-Host 'CxxuPsModulePath:' $CxxuPsModulePath
    Add-EnvVar -EnvVar PsModulePath -NewValue $CxxuPsModulePath -Verbose -Scope $Scope
    
}
function Update-PwshEnv
{
    [CmdletBinding()]param()
    # 先更新变量,再更新别名
    Update-PwshVars -Verbose:$VerbosePreference
    Update-PwshAliases -Verbose:$VerbosePreference
    Set-Variable -Name PsEnvMode -Value 3 -Scope Global
    Set-PromptVersion Balance
    # Start-CoreInit
}
function Get-AdministratorPrivilege
{
    # sudo pwsh #-noprofile -nologo
    # sudo pwsh -noprofile -nologo -noe -c { init }
    sudo pwsh -c { p }
}

function Head
{
    param (

        $file,
        $number = 10
    )
    
    Get-Content $file -head $number | ForEach-Object { '{0,-5} {1}' -f $_.ReadCount, $_ }
}

function Tail
{
    param (
        $file,
        $number = 10
    )
    # catn $file | Select-Object -Last $number
    Get-Content $file -head $number | ForEach-Object { '{0,-5} {1}' -f $_.ReadCount, $_ }
    
}
function Get-TypeCxxu
{
    
    <#
    .SYNOPSIS
    Get-TypeCxxu用来获取输入对象的类型信息
    .DESCRIPTION
    Get-TypeCxxu是一个用来获取输入对象的类型信息的函数,它接受一个输入对象,并返回一个包含对象的类型信息的对象
    .PARAMETER InputObject
    要获取类型信息的输入对象
    .INPUTS
    可以通过管道传递输入对象
    .OUTPUTS
    Return a custom object that contains information about the type of the input object
    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> "abc"|Get-TypeCxxu

    Name   FullName      BaseType      UnderlyingSystemType
    ----   --------      --------      --------------------
    String System.String System.Object System.String

    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> Get-TypeCxxu -InputObject "abc"

    Name   FullName      BaseType      UnderlyingSystemType
    ----   --------      --------      --------------------
    String System.String System.Object System.String
    .NOTES

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )

    process
    {
        if ($InputObject)
        {
            $typeInfo = $InputObject.GetType()
         
            $output = $typeInfo | Select-Object Name, fullname, BaseType, UnderlyingSystemType
            return $output
        }
    }
}
function Get-ParametersList
{
    param(
        [parameter(ValueFromPipeline = $true)]
        [string]$Name
    )
    Get-Command $Name | Select-Object -ExpandProperty Parameters | Select-Object -ExpandProperty Keys
}
function New-ModuleByCxxu
{
    param(
        $ModuleName
    )
    Update-PwshEnvIfNotYet -Mode Vars
    
    $ModuleDir = "$PS\$ModuleName"
    mkdir $ModuleDir
    New-Item "$ModuleDir\$ModuleName.psm1"

}
function Test-SudoAvailability
{
    <# 
    .SYNOPSIS
    返回当前系统内是否有sudo命令可以调用(如果可以调用,那么可以在函数中自动地临时地切换到管理员模式运行命令)
    .DESCRIPTION
    # sudo命令自windows 11 24h2后可以从设置中启用;或者通过安装第三方模块获得sudo命令(比如scoop install gsudo)

    #>
    $res = Get-Command -Name sudo -ErrorAction SilentlyContinue 
    return $res
}
function Set-PoshPrompt
{
    <# 
    .synopsis
    设置oh-my-posh主题,可以用 ls $env:POSH_THEMES_PATH 查看可用主题,我们只需要获取.omp.json前面部分的主题配置文件名称即可

    .example
    🚀 Set-PoshPrompt ys
    # cxxu @ cxxuwin in ~\Desktop [21:17:20]
    $ Set-PoshPrompt 1_shell
    >  Set-PoshPrompt iterm2
     #>
    param (
        # [Parameter(Mandatory)]
        [string]
        $Theme = $DefaultPoshTheme,
        [switch]$Poshgit
    )
    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\$Theme.omp.json" | Invoke-Expression
    if ($Poshgit)
    {
        # Import-Module posh-git
        Enable-PoshGit
    }
}   
    
function Enable-PoshGit
{
    # 使用包管理器安装posh-git,则使用以下方式激活
    # Import-Module posh-git
    # 否则使用以下方式激活
    Import-Module "$repos\posh-git\src\posh-git.psd1"

}


function New-PromptStyle
{
    <# 
    .SYNOPSIS
    设置powershell提示符,这里的方案是不影响Prompt函数的
    但是不适合编写复杂的Prompt,可读性不佳
    复杂Prompt可以通过另一个方案:PromptVersion配合环境变量来实现
    两种方案中,第二种方案会覆盖掉本方案,但是可以将本方案打包,作为PromptVersion的一个版本
    .EXAMPLE
    PS [cxxu\Desktop] > New-PromptStyle  -Short
    .EXAMPLE
    PS [Desktop] >  New-PromptStyle  -Simple
    .EXAMPLE
    PS>New-PromptStyle  -Default
    .EXAMPLE
    PS [C:\Users\cxxu\Desktop] > New-PromptStyle
    .EXAMPLE
    PS BAT [12:08:27 AM] [C:\Users\cxxu\Desktop]
    [🔋 100%] MEM:82.62% [6.49/xx] GB > 
    #>
    param(
        #是否设置为简单提示符,便于将交互过程内容聚焦,适合摘录出来做笔记(不显示路径)
        [switch]$Simple,
        #不显示路径,仅显示`PS>`
        [switch]$Default,
        #仅显示最后一个目录层级
        [switch]$Short,
        #显示最后2个层级如果有的话
        [switch]$Short2
    )
    $currentPath = Get-Location
    if ($Default)
    {
        Set-Item -Path function:prompt -Value { "PS [$(Get-Location)] > " }
    }
    elseif ($Short)
    {
        Set-Item -Path function:prompt -Value { "PS [$($currentPath.ProviderPath.Split('\')[-1])]" + ' >  ' }
    }
    elseif ($Short2)
    {
        Set-Item -Path function:prompt -Value {
            $splitPath = $currentPath.Path.Split('\')
            if ($splitPath.Count -ge 3)
            {
                $parentDir = $splitPath[-2]
                $currentDir = $splitPath[-1]
                "PS [$parentDir\$currentDir] > "
            }
            else
            {
                $currentPath.Path  # 返回完整路径，因为只有单级或根目录
            }
        }
    }
    elseif ( $Simple)
    {
        Set-Item -Path function:prompt -Value '> '
    }
    else
    {

        Set-Item -Path function:prompt -Value { $Prompt1 }
        # 显示时分秒,可以用-Format T 或 -Displayhint time
    }
}

function Write-UserHostname
{
    <# 
    .SYNOPSIS
    显示用户名和路径,适用于Prompt 
    默认不换行,如有需要,自行添加
    #>
    $userHostname = Get-UserHostName
    Write-Host (('[' + $userHostname + ']')) -ForegroundColor Cyan -NoNewline
}
function Write-HostIp
{
    <# 
    .SYNOPSIS
    获取本机的ipv4地址,如果有多个网卡,则返回第一个
    .DESCRIPTION
    由Get-IPAddressOfPhysicalAdapter返回的对象处理得到
    .Notes
    将公网ip暴露出来是有风险的,但是局域网私有ip暴露出来没问题,一般是192.168.x.x居多
    .NOTES
    这是一个耗时函数,由于它不需要经常更新,建议将它放到暂存变量中即可
    #>
    param (
        
    )
    $ip = Get-IpAddressForPrompt 
    # Return $ip
    Write-Host (('[' + $ip + ']')) -ForegroundColor Blue -NoNewline
}
function write-PermissoinLevel
{
    param (
    )

    if (Test-AdminPermission)
    {
        $s = '#⚡️', 'Cyan'

    }
    else
    {
        $s = '# ' , 'DarkGray'
    }
    Write-Host $s[0] -BackgroundColor $s[1] -NoNewline
}
function Write-Path
{
    
    $currentPath = (Get-Location).Path
    Write-Host (('[' + $currentPath.Replace($HOME, '~') + ']')) -ForegroundColor DarkGray -NoNewline
    
}
function Write-OSVersionInfo
{
    param (
        [switch]$CaptionOnly
    )
    $res = Confirm-OSVersionCaption
    if (!$CaptionOnly)
    {

        $displayversion = Get-WindowsVersionFromRegistry | Select-Object -ExpandProperty DisplayVersion
        $OsVersionFullCode = (Confirm-OSVersionFullCode)
        $res = $res + '@' + "${displayversion}:" + $OsVersionFullCode
    }
    $res = '[' + $res + ']'
    Write-Host $res -NoNewline -ForegroundColor DarkGray
}
function write-PsEnvMode
{
    [CmdletBinding()]
    param (
        
    )

    # Write-Host $Psenvmode  

    if ($PSEnvMode -eq 3)
    {
        $mode = '☀️'
    }
    elseif ($Psenvmode -eq 2)
    {
        $mode = '🌓'
    }
    elseif ($Psenvmode -eq 1)
    {
        $mode = '🌙'
    }
    Write-Host $mode -NoNewline # -BackgroundColor 'green'
    
}
function write-PsMode
{
  
    Write-Host 'PS' -NoNewline -BackgroundColor Magenta
    write-PsEnvMode
    
}
function Write-BatteryAndMemoryUse
{
    <# 
    .SYNOPSIS
    调用Get-MemoryUseSummary和Get-BatteryLevel,做进一步处理使得其适合作为Prompt的一部分
    #>
    # prepare data
    $MemoryUseSummary = Get-MemoryUseSummary
    $MemoryUsePercentage, $MemoryUseRatio = $MemoryUseSummary.MemoryUsePercentage, $MemoryUseSummary.MemoryUseRatio #0.1s左右
    $BAT = Get-BatteryLevel #0.2s左右
    
 
    write-PsMode
    Write-Host ('[') -NoNewline
    Write-Host 'BAT:' -ForegroundColor Cyan -NoNewline

    # 下面这部分内容在MainPC上执行耗时0.04s左右,可以考虑不使用
    # <<<<
    # $alertGameBook = 80
    # 这里要测试一下是否是在游戏本运行,如果是,则考虑电量低于$alertGameBook等数值时显示红色)
    # 虽然游戏本开省电模式也可以用挺久的
    # $RedCondition1 = (Test-MainPC) -and ($BAT -le $alertGameBook) #执行速度慢(0.01s左右)
    # # 轻薄本考虑30%显示红色
    # $RedCondition2 = ($BAT -le 30)
    # $testRed = $RedCondition1 -or $RedCondition2
    # $BatteryColor = if ($testRed) { 'DarkRed' }else { 'DarkGreen' }
    # >>>>>>
    $BatteryColor = 'DarkYellow'

    Write-Host "$($BAT)%" -ForegroundColor $BatteryColor -NoNewline
    Write-Host (']') -NoNewline
    Write-Host ('[') -NoNewline
    Write-Host 'MEM:' -ForegroundColor Cyan -NoNewline
    Write-Host "${MemoryUsePercentage}%" -ForegroundColor DarkMagenta -NoNewline
    Write-Host " ($MemoryUseRatio)GB" -ForegroundColor DarkGray -NoNewline
    Write-Host(']') -NoNewline 
}
function Write-Data
{
    <# 
    .SYNOPSIS
    显示日期和时间,适用于Prompt 
    默认不换行,如有需要,自行添加
    #>
    $currentDate = Get-Date -Format 'yyyy-MM-dd'
    
    Write-Host (('[' + $currentDate) + ']') -ForegroundColor DarkYellow -NoNewline
    
}

function Write-Time
{
    
    $currentTime = Get-Date -Format T  #'HH:mm:ss'
    Write-Host (('[' + $currentTime + ']')) -ForegroundColor Magenta -NoNewline
}


function Write-ColorsPreivew
{
    $colors = @('Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta', 'DarkYellow', 'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan', 'Red', 'Magenta', 'Yellow', 'White')

    foreach ($color in $colors)
    {
        Write-Host "This is a sample text with background color: $color" -BackgroundColor $color
        # 添加换行符以便每种颜色显示在新行上
        Write-Host ''
    }
}
function PromptShort
{

    $currentPath = Get-Location
    "PS [$($currentPath.ProviderPath.Split('\')[-1])]" + '>  '
}
function PromptShort2
{
    $currentPath = Get-Location
    $splitPath = $currentPath.Path.Split('\')
    if ($splitPath.Count -ge 3)
    {
        $parentDir = $splitPath[-2]
        $currentDir = $splitPath[-1]
        "PS [$parentDir\$currentDir]> "
    }
    else
    {
        "PS $($currentPath.Path) >" # 返回完整路径，因为只有单级或根目录
    }
   
}
function PromptDefault
{

    return "PS [$(Get-Location)]> "
    
}
function PromptSimple
{
    return 'PS> '
    
}

function Import-ModuleForce
{
    <# 
    .SYNOPSIS
    默认重载已经加载了的模块,而不是重载所有模块来加快操作速度
    #>
    [CmdletBinding()]
    param (
        # [switch]$PassThru
    )

    # 获取当前 已经加载了的模块
    $modules = Get-Module | Select-Object -ExpandProperty Name

    $res = @()
    foreach ($module in $modules)
    {
        # 跳过某些模块的重载(如果这个模块比较特殊的话,比如包含注册补全的模块，这个模块就要谨慎重载,默认跳过,可以根据自己的情况调整)
        Remove-Module $module -ErrorAction SilentlyContinue -Force
        # if ($module -like '*completion*')
        # { 
        #     Write-Warning "Skipping $module"
        #     continue 
        # }

        # Import-Module $module -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $exp = "Import-Module $module -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue"
        $res += $exp
        Write-Verbose "Imported $module "
    }
    # if ($PassThru)
    # {

    #     return $res -join "`n"
    # }
    return $res -join "`n"
}
function ipmof
{
    <# 
    .SYNOPSIS
    作为Import-ModuleForce的别名
    由于同一个会话下,powershell无法自动更新已经导入但发生变化的模块,这时候用户有两个选择:
    重新执行pwsh,或者使用ipmo(Import-Module) 配合-Force参数强制重载相应的模块
    前者重载得彻底,但是会无法继承父级会话中的环境,比如定义的变量在新开的pwsh中无法访问,而且开销比较大,速度慢
    后者一种方法更加轻量,由于不会创建新的pwsh进程,不会造成环境变量丢失,但是一个个检查模块然后重新加载对于开发者来说不方便
    为此编写了此函数,可以直接重载已经加载了的模块,方便了这一个刷新变更了的模块的过程
    .NOTES
    一个有意思的现象是,如果自动导入模块的路径$PsModulePath下的模块如果在当前powershell会话中没有加载,例如某个函数x在模块test中
    而当前shell环境没有调用x,也没有调用模块test中的任意函数,或定义的东西,此时对此摸块做了更改后,不需要刷新,在当前会话shell中调用test的变更的内容是自动更新的,也就是说会自动刷新
    可以重载已经加载了的模块,对于开发测试powershell模块很有用
    .Notes
    本函数调用要配合iex,效果比较稳定,如果你的模块比价简单,那么可以更改import-ModuleForce内部让其直接执行强制导入
    .EXAMPLE
    重载已经加载了的模块:
    ipmof|iex
    .ExAMPLE
    Import-ModuleForce -verbose|iex

    #>
    param (
    )
    # Import-Module PSReadLine -Force
    Import-ModuleForce
    
}

function PromptBrilliant
{
    <# 
    .样式颇为美观,但是性能稍差(还可以接受,略有延迟)
    可以把section1化简来提高响应速度
    #>
   
    #section1
    Write-Host ('┌─') -NoNewline
    Write-BatteryAndMemoryUse
    Write-OSVersionInfo
    Write-Host ''
    #section2
    Write-Host ('├─') -ForegroundColor Cyan -NoNewline
    Write-UserHostname
    Write-HostIp
    Write-Data; Write-Time
    Write-Host ''
    Write-Host ('├─') -ForegroundColor Magenta -NoNewline
    #section3
 
    write-PermissoinLevel
    Write-Path
    Write-Host ''
    Write-Host ('└─') -ForegroundColor DarkYellow -NoNewline
}
function PromptBrilliant2
{
    <# 
    .样式颇为美观,但是性能稍差(还可以接受,略有延迟)
    可以把section1化简来提高响应速度
    #>
   
    #section1
    Write-Host ('┌─') -NoNewline
    Write-BatteryAndMemoryUse
    Write-Host ''
    #section2
    Write-Host ('├─') -ForegroundColor Cyan -NoNewline
    Write-Data; Write-Time
    Write-Host ''
    Write-Host ('├─') -ForegroundColor Magenta -NoNewline
    #section2
    Write-UserHostname
    Write-HostIp
    write-PermissoinLevel
    Write-Path
    Write-Host ''
    Write-Host ('└─') -ForegroundColor DarkYellow -NoNewline
}


function PromptBalance
{
    <# 
 .SYNOPSIS
 最常用的prompt样式
 .NOTES
 如果需要清除提示符,可以利用编辑器中正则表达式替换
 PS.*\] 可以清除掉命令行执行记录中的第一行提示符
 如果需要进一步清除第二行,那么复制需要的行,再次替换为空即可
 #>

    #section1
    Write-BatteryAndMemoryUse
    # Write-Host "`t" -NoNewline
    # Write-Data;
    Write-OSVersionInfo
    Write-Time
    
    #section2
    Write-Host ''
    # Write-Host "`t" -NoNewline
    write-PermissoinLevel
    Write-UserHostname
    Write-HostIp
    Write-Path
    write-GitBasicInfo
    Write-Host ''
    
}

function Get-PsIOItemInfo
{
    <# 
    .SYNOPSIS
    获取文件或目录的.Net对象(路径对象),传入的Path对应的是文件,则返回[System.IO.FileInfo]对象，
    传入的Path对应的是目录,则返回[System.IO.DirectoryInfo]对象
    .EXAMPLE
    获取某个目录的路径对象
    PS C:\repos\scripts> 
    Get-PsIOItemInfo ./                                                                               

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    da---           2024/7/29    23:23                scripts


    PS [C:\repos\scripts]> Get-PsIOItemInfo .\PS\

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    da---           2024/7/29     9:10                PS
    .EXAMPLE
    PS [C:\repos\scripts]> (Get-PsIOItemInfo .\PS\).fullname
    C:\repos\scripts\PS\

    .EXAMPLE
    获取某个文件的路径对象
    PS [C:\repos\scripts]> Get-PsIOItemInfo .\readme_zh.md

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    -a---           2024/7/29    21:58            581 readme_zh.md
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path $Path)
    {
        if (Test-Path $Path -PathType Leaf)
        {
            # 如果是文件，返回 [System.IO.FileInfo] 对象
            return [System.IO.FileInfo]::new($Path)
        }
        elseif (Test-Path $Path -PathType Container)
        {
            # 如果是目录，返回 [System.IO.DirectoryInfo] 对象
            return [System.IO.DirectoryInfo]::new($Path)
        }
    }
    else
    {
        Write-Error "The path '$Path' does not exist."
    }
}


function Get-Size
{
    <#
    .SYNOPSIS
    计算指定文件或目录的大小。

    .DESCRIPTION
    此函数计算指定路径的文件或目录的大小。对于目录，它会递归计算所有子目录和文件的总大小。
    函数支持以不同的单位（如 B、KB、MB、GB、TB）显示结果。

    .NOTES
    次函数遇到Path为目录的情况时,使用的是ls 的-recurse参数,不需要自己编写循环遍历,也不便使用进度计数
    而内部的process块内对$path做遍历是为了支持管道符,也就是形如ls *|Get-Size的方式调用,这时候$Path会是一个数组,对其做遍历

    .PARAMETER Path
    要计算大小的文件或目录的路径。可以是相对路径或绝对路径。

    .PARAMETER Unit
    指定结果显示的单位。可选值为 B（字节）、KB、MB、GB、TB。默认为 MB。

    #>

    <# 
    .EXAMPLE
    Get-Size -Path "C:\Users\Username\Documents"
    计算 Documents 文件夹的大小，并以默认单位（MB）显示结果。

    .EXAMPLE
    Get-Size -Path "C:\large_file.zip" -Unit GB
    计算 large_file.zip 文件的大小，并以 GB 为单位显示结果。

    .EXAMPLE
    "C:\Users\Username\Downloads", "C:\Program Files" | Get-Size -Unit MB
    计算多个路径的大小，并以 MB 为单位显示结果。
    .EXAMPLE
    指定显示单位为KB ,显示5位小数
    PS> Get-Size -SizeAsString -Precision 5 -Unit KB

    Mode  BaseName Size      Unit
    ----  -------- ----      ----
    da--- PS       563.93848 KB
    .EXAMPLE
    保留3位小数(但是显示位数保持默认的2位),使用管道符`|fl`来查看三位小数
    PS> Get-Size -Precision 3 -Unit KB

    Mode  BaseName   Size Unit
    ----  --------   ---- ----
    da--- PS       564.14 KB
    .EXAMPLE
    PS> Get-Size -Precision 3 -Unit KB|fl

    Mode     : da---
    BaseName : PS
    Size     : 564.408
    Unit     : KB
    
    .EXAMPLE
    指定显示精度为4为小数(由于这里恰好第3,4位小数为0,所以没有显示出来,指定更多位数,可以显示)
    PS🌙[BAT:79%][MEM:44.52% (14.12/31.71)GB][0:03:01]
    # [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\PS]
    PS> Get-Size -SizeAsString -Precision 4

    Mode  BaseName Size Unit
    ----  -------- ---- ----
    da--- PS       0.55 MB

    指定显示精度为5为小数
    PS🌙[BAT:79%][MEM:44.55% (14.13/31.71)GB][0:03:05]
    # [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\PS]
    PS> Get-Size -SizeAsString -Precision 5

    Mode  BaseName Size    Unit
    ----  -------- ----    ----
    da--- PS       0.55002 MB

    .INPUTS
    System.String[]
    你可以通过管道传入一个或多个字符串路径。

    .OUTPUTS
    PSCustomObject
    返回一个包含路径、大小和单位的自定义对象。

    #>

    [CmdletBinding()]
    param(
        [Parameter( ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$Path = '.',
        # [switch]$ItemType,
        [Parameter(Mandatory = $false)]
        [ValidateSet('B', 'KB', 'MB', 'GB', 'TB')]
        [string]$Unit = 'MB',

        #文件大小精度
        $Precision = 2,
        [switch]$SizeAsString,
        [switch]$Detail,
        [switch]$FormatTable
    )
    
    begin
    {
        if ($VerbosePreference)
        {
            # 即使外部不显示传入-Verbose参数,也会显示Verbose信息
            $PSBoundParameters | Format-Table  
            
        }
        # 大小单位换算(倍率)
        $unitMultiplier = @{
            'B'  = 1
            'KB' = 1KB
            'MB' = 1MB
            'GB' = 1GB
            'TB' = 1TB
        }
        #进度计数器
        $PSStyle.Progress.View = 'Classic'
        $i = 0
        # $PSStyle.Progress.View = 'Minimal'
        $count = (Get-ChildItem $Path).count
        Write-Verbose "$count Path(s) will be processed" # -ForegroundColor Blue
    }

    process
    {
        # $i = 0

        foreach ($item in $Path)
        {
            # 增加write-process支持
                
            # Write-Verbose "Calculating size of directory $item"
            if ($count -gt 1)
            {

                $Completed = ($i / $count) * 100
                # 精度控制
                $Completed = [math]::Round($Completed, 1)
                # Write-Host $i 
                Write-Progress -Activity "Calculating size of $item" -Status "Progress: $Completed %" -PercentComplete $Completed
                $i += 1
            }
            # 模拟耗时逻辑检查进度条功能
            # Start-Sleep -Milliseconds 500

            if (Test-Path -Path $item)
            {
                $size = 0
                # 利用Get-item 判断$Path是文件还是目录,如果是目录,则调用ls -Recurse找到所有文件(包括子目录),然后利用管道符传递给Measure计算该子目录的大小
                $itemInfo = (Get-Item $item)
                $baseName = $itemInfo.BaseName
                $Mode = $itemInfo.Mode
                # $ItemType = $itemInfo.GetType().Name
                if ($itemInfo -is [System.IO.FileInfo])
                {
                    $ItemType = 'File'
                }
                elseif ($itemInfo -is [System.IO.DirectoryInfo])
                {
                    $ItemType = 'Directory'
                }
                # 计算$Path的一级子目录或文件的大小
                if ($itemInfo -is [System.IO.DirectoryInfo])
                {
                    $size = (Get-ChildItem -Path $item -Recurse -Force | Measure-Object -Property Length -Sum).Sum
                }
                else
                {
                    $size = (Get-Item $item).Length
                }
                # 大小单位换算
                $sizeInSpecifiedUnit = $size / $unitMultiplier[$Unit]
                Write-Verbose "`$sizeInSpecifiedUnit: $sizeInSpecifiedUnit"
                $Size = [math]::Round($sizeInSpecifiedUnit, [int]$Precision)
                Write-Verbose "`$size: $Size"
                # 制表格式输出
                if ($SizeAsString)
                {
                    $size = "$size"
                }
                $res = [PSCustomObject]@{
                    Mode     = $Mode
                    BaseName = $baseName
                    Size     = $Size #默认打印数字的时候只保留小数点后2位
                    Unit     = $Unit
                }
                $verbo = [pscustomobject]@{
                    Itemtype = $itemType
                    Path     = $item
                    
                }
                if ($Detail)
                {

                    # $res | Add-Member -MemberType NoteProperty -Name FullPath -Value (Convert-Path $item)
                    foreach ($p in $verbo.PsObject.Properties)
                    {

                        $res | Add-Member -MemberType NoteProperty -Name $p.Name -Value $p.value
                    }
                }
                # 这个选项其实有点多余,用户完全可以自己用管道符|ft获取表格试图,有更高的灵活性
                if ($FormatTable)
                {

                    $res = $res | Format-Table #数据表格化显示
                }
                return $res
            }
            else
            {
                Write-Warning "路径不存在: $item"
            }
        }
    }
    end
    {
        # return $res
    }
}

function Get-ItemSizeSorted
{
    <# 
    .SYNOPSIS
    对指定目录以文件大小从大到小排序展示其中的子目录和文件列表
    .DESCRIPTION
    继承大多数Get-Size函数的参数,比如可以指定文件文件大小的单位，大小数值保留的小数位数等(详情请参考Get-Size函数)。
    .NOTES
    这里默认不是用并行计算,如果需要启用并行计算，可以通过参数-Parallel来启用。
    
    .PARAMETER Parallel
    这里可以考虑使用并行方案进行统计,但是建议不要滥用,因为并行计算创建多线程也是需要资源和时间开销的,在文件数量不是很巨大的情况下,使用并行方案反而会降低速度,并行数量通常建议不超过3个为宜;
    .PARAMETER ThrottleLimit
    并行计算时的并发数,如果启用并行计算，ThrottleLimit参数默认为5,可以通过此参数指定为其他正整数

    .PARAMETER Path
    要排序的目录
    .PARAMETER Unit
    将文件大小单位转换为指定单位
    


    .EXAMPLE
    PS🌙[BAT:79%][MEM:44.53% (14.12/31.71)GB][0:00:19]
    # [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\PS]
    PS> get-ItemSizeSorted -Unit KB

    Mode  BaseName                          Size Unit
    ----  --------                          ---- ----
    da--- Deploy                           82.45 KB
    da--- Basic                            78.55 KB
    d---- Pwsh                             49.91 KB
    d---- TaskSchdPwsh                     40.06 KB
    #>
    [CmdletBinding()]
    param (
        $Path = '.',
        [Parameter(Mandatory = $false)]
        [ValidateSet('B', 'KB', 'MB', 'GB', 'TB')]
        [string]$Unit = 'MB',
        #文件大小精度
        $Precision = 3,
        [switch]$Detail,
        [switch]$SizeAsString,
        [switch]$FormatTable,
        [switch]$Parallel,
        $ThrottleLimit = 5
    )
    if ($VerbosePreference)
    {
        $PSBoundParameters | Format-Table
    }
    $verbose = $VerbosePreference
    if ($Parallel)
    {
        Write-Host 'Parallel Mode.'
        $res = Get-ChildItem $Path | ForEach-Object -Parallel {
            $Unit = $using:Unit
            $Precision = $using:Precision
            $Detail = $using:Detail
            $SizeAsString = $using:SizeAsString
            $item = $_ | Get-Size -Unit $Unit -Precision $Precision -Detail:$Detail `
                -SizeAsString:$SizeAsString # -FormatTable:$FormatTable 
            
            # Write-Output $item 
            # $item | Format-Table  | Out-String 
            $verbose = $using:verbose
            if ($verbose)
            {
                Write-Host $item -ForegroundColor blue
            }
            return $item
        } -ThrottleLimit $ThrottleLimit
    }
    else
    {
        $i = 0
        $items = Get-ChildItem $Path
        $count = $items.count
        Write-Host 'Calculating ... '
        $res = $items | ForEach-Object {

            $item = $_ | Get-Size -Unit $Unit -Precision $Precision -Detail:$Detail -SizeAsString:$SizeAsString -Verbose:$false # -FormatTable:$FormatTable 
            
            $Completed = [math]::Round($i++ / $count * 100, 1)
            Write-Progress -Activity 'Calculating items sizes... ' -Status "Processing: $Completed%" -PercentComplete $Completed
            # Write-Host $item  -ForegroundColor Red
            # $item | Format-Table #会被视为返回值,后续的管道服sort将无法正确执行(利用break可以验证,这个语句本身没有问题,但是后续的管道无法正常执行)
            # break
            # 非-parallel脚本块,可以直接引用外部变量
            if ($VerbosePreference)
            {

                Write-Host $item
            }
            # Write-Output $item 
            return $item
        }
    }
        

    $sorted = $res | Sort-Object -Property size -Descending
    $sumUnit = ($sorted | Measure-Object -Property size -Sum).Sum
    $sumByte = $sumUnit * ([int]"1$Unit")
    # $smbBit = $sumByte * 8 #精度不够,不展示
    $sumKB = $sumByte / 1KB
    $sumMB = $sumByte / 1MB
    $sumGB = $sumByte / 1GB
    Write-Host "SUM size: $sumUnit $Unit" -ForegroundColor Magenta
    Write-Host "SUM size: $sumGB GB" -ForegroundColor Magenta
    $sumReport = [PSCustomObject]@{
        # "sum$Unit"   = $sum
        # smbBit  = $smbBit
        sumByte = $sumByte
        sumKB   = $sumKB
        sumMB   = $sumMB
        sumGB   = $sumGB
    }
    $sumReport | Format-Table

    if ($FormatTable)
    {

        $sorted = $sorted | Format-Table
    }
    return $sorted
}


function write-GitBasicInfo
{
    <# 
 .SYNOPSIS
 提示当前位置是某个git仓库,并且显示当前分支
 .DESCRIPTION
 此调用会消耗一定的时间,如果重视prompt的响应速度,可以不用使用此函数
 并且,即便使用,建议只计算基础信息,否则对于大型仓库会拖慢prompt响应速度
 .NOTES
 如果当前目录是git目录,并且git命令可用(已安装),则返回基本的git仓库信息(比如当前分支名字)
 否则不是git目录或者git命令不可用,返回空(可以用来判断当前目录是否在git仓库中)
 #>   
    # 获取当前路径
    $path = (Get-Location).Path

    # 初始化Git分支名称为空
    $gitBranch = ''

    # 检查当前路径是否在Git仓库中
    if (Test-Path (Join-Path $path '.git') )
    {
        $Gitavailability = Get-Command git -ErrorAction SilentlyContinue
        if ($Gitavailability)
        {
            # 使用git命令获取当前分支名称
            $gitBranch = & git symbolic-ref --short HEAD
            $gitBranch = $gitBranch.Trim()
        }
        else
        {
            # 捕获任何异常（例如，当前目录不是Git仓库）
            $gitBranch = ''
        }
    }
    if ($gitBranch)
    {
        <# Action to perform if the condition is true #>
        $gitBranch = "{Git:$gitBranch}"
        
        Write-Host $gitBranch -ForegroundColor DarkCyan -NoNewline
    }
    # return $gitBranch
    

    # 保存以上内容到你的PowerShell配置文件$PROFILE中，然后重新加载它或重启PowerShell
}

function Prompt
{
    <# 
    .SYNOPSIS
    设置powershell提示符(powershell 默认调用)
    但我们这里改写Prompt函数,而且还可以通过设置环境变量来更改当前prompt主题
    Prompt函数无法传参,但是可以通过设置辅助函数Set-PromptVersion,修改主题来间接传参(控制全局变量)
    关于这部分逻辑详见外部的Set-PromptVersion
    #>
    # 和上一层输出间隔一行
    Write-Host ''

    switch ($env:PromptVersion)
    {
        # 'Fast' { PromptFast }
        'Brilliant' { PromptBrilliant }
        'Brilliant2' { PromptBrilliant2 }
        'Balance' { PromptBalance }
        'Simple' { PromptSimple }
        'short2' { PromptShort2 }
        'short' { PromptShort }
        'Default' { PromptDefault }
        Default { PromptDefault }
    }
    return 'PS> '
    # 如果追求纯净,可以返回空字符串或者tab缩进
    # return ' '
    
}

function Get-PathType
{
    <# 
    .SYNOPSIS
    判断输入的路径是绝对路径还是相对路径,无论这个路径是否存在
    .EXAMPLE
    PS[BAT:69%][MEM:26.27% (8.33/31.70)GB][11:47:30]
    # [~\Desktop]
    PS> Get-PathType "./script"
    RelativePath

    PS[BAT:69%][MEM:26.22% (8.31/31.70)GB][11:47:33]
    # [~\Desktop]
    PS> Get-PathType "C:\script"
    FullPath

    PS[BAT:69%][MEM:26.22% (8.31/31.70)GB][11:47:36]
    # [~\Desktop]
    PS> Get-PathType "C:/script"
    FullPath

    PS[BAT:69%][MEM:26.18% (8.30/31.70)GB][11:47:45]
    # [~\Desktop]
    PS> Get-PathType "/script"
    FullPath

    PS[BAT:69%][MEM:26.18% (8.30/31.70)GB][11:47:50]
    # [~\Desktop]
    PS> Get-PathType "/script"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # 判断是否为绝对路径

    # ^\/ 和 ^/ 在匹配字符串开始的斜杠(/)时都是有效的，尤其是在处理Unix/Linux风格的文件路径时。不过，在不同编程环境或工具中，可能会有细微的差别需要考虑。

    if ($Path -match '^[A-Za-z]:[\\/]|^\/') # ^[A-Za-z]:\ 匹配windows的绝对路径 ^/或^\/ 匹配Unix/Linux的绝对路径
    {
        Write-Output 'FullPath'
    }
    else
    {
        Write-Output 'RelativePath'
    }
}

function Get-PsProfilesPath
{
    <# 
    .SYNOPSIS
    获取所有的$profile级别文件路径,即便文件不存在
    #>
    $profiles = @(
        $profile.CurrentUserCurrentHost,
        $profile.CurrentUserAllHosts,
        $profile.AllUsersCurrentHost,
        $profile.AllUsersAllHosts
    )
    return $profiles
}
 
function Remove-PsProfiles
{
    $profiles = Get-PsProfilesPath
    foreach ($profile in $profiles)
    {
        Remove-Item -Force -Verbose $profile -ErrorAction SilentlyContinue
    }
}


function Confirm-PsVersion
{
    <# 
    .SYNOPSIS
    如果当前版本高于指定版本，则返回当前版本对象，否则返回$False
    直接抛出版本过低的提示错误有点过头了
    #>
    param (
        $Major = 7,
        $Minor = 0,
        $Build = 0

    )
    $version = $host.Version
    if ($Version.Major -ge $Major -and $Version.Minor -ge $Minor -and $Version.Build -ge $Build)
    {
        # $res = $True
        # Write-Host 
        return $Version
    }
    else
    {
        # $res = $false
        Write-Host "Powershell version is lower than $Major.$Minor.$Build" -ForegroundColor Red
        return $False
    }
    # return $res
    
}

function Install-ScoopByLocalProxy
{
    param (
        [ValidateSet('Default', 'Proxy')]$Method = 'Default'
    )
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser # Optional: Needed to run a remote script the first time
    switch ($Method)
    {
        'Default'
        { 
            Write-Host 'Installing scoop in default channel...'
        }
        'Proxy'
        {
            Set-Proxy -Status on
            Write-Host 'Installing scoop in proxy channel...'
            Get-ProxySettings
        }
        Default {}
    }
    Invoke-Expression (New-Object net.webclient).downloadstring('https://get.scoop.sh')
    
}
function Set-Owner
{
    <# 
    .SYNOPSIS
    设置指定目录或文件的所有者
    .EXAMPLE
    默认讲所有者设置为当前用户,域和用户名定义在VarSet1中,如果不导入,可以通过[System.Environment]::UserDomainName,[System.Environment]::UserName  或者简单通过$env:ComputerName和whoami命令获取
    #>

    param(
        # 设置目录路径
        $Path = '.',
        # 新所有者
        $NewOwner = $UserName,
        #domain
        $domain = $UserDomainName

    )

    # check the admin permission
    if (! (Test-AdminPermission))
    {
        Write-Error 'You need to have administrator rights to run this script.'
        return 
    }

    $NewOwner = "$domain\$NewOwner"
    # 获取当前 ACL
    $acl = Get-Acl -Path $Path

    # 创建新所有者的 NTAccount 对象
    $newOwnerAccount = New-Object System.Security.Principal.NTAccount($newOwner)

    # 设置新的所有者
    $acl.SetOwner($newOwnerAccount)

    # 应用修改后的 ACL
    Set-Acl -Path $Path -AclObject $acl

    # 检查新的所有者是否设置成功
    return (Get-Acl -Path $Path)
}

function Grant-PermissionToPath
{
    <# 
    .SYNOPSIS
    可以清除某个目录的访问控制权限,并设置权限,比如让任何人都可以完全控制的状态
    这是一个有风险的操作;建议配合其他命令使用,比如清除限制后再增加约束
    .DESCRIPTION
    设置次函数用来清理发生权限混乱的文件夹,可以用来做共享文件夹的权限控制强制开放
    .EXAMPLE
    PS [C:\]> Grant-PermissionToPath -Path C:/share1 -ClearExistingRules
    True
    True
    已成功将'C:/share1'的访问权限设置为允许任何人具有全部权限。
    .PARAMETER Path
    需要执行访问控制权限修改的目录
    .PARAMETER Group
    指定文件夹要授访问权限给那个组,结合Permission参数,指定该组对Path具有则样的访问权限
    默认值为:'Everyone'
    .PARAMETER Permission
    增加/赋于新的访问控制权限,可用的合法值参考:https://learn.microsoft.com/zh-cn/dotnet/api/system.security.accesscontrol.filesystemrights?view=net-8.0
    .PARAMETER ClearExistingRules
    清空原来的访问控制规则
    .NOTES
    需要管理员权限,相关api参考下面连接
    .LINK
     相关AIP文档:https://learn.microsoft.com/zh-cn/dotnet/api/system.security.accesscontrol.filesystemaccessrule?view=net-8.0
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        $Group = 'Everyone',
        # 指定下载权限
        $permission = 'FullControl',

        [switch]$ClearExistingRules

    )

    try
    {
        # 获取目标目录的当前 ACL
        $acl = Get-Acl -Path $Path

        # 创建允许“任何人（Everyone）”具有“完全控制”权限的新访问规则
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Group,
            $permission, 
            'ContainerInherit, ObjectInherit',
            'None',
            'Allow'
        )
        # 也可以考虑用icacls命令来做
        # cmd /c ' icacls $Path  /grant cxxu:(OI)(CI)F  /T '

        if ($ClearExistingRules)
        {
            # 如果指定了清除现有规则，则先移除所有现有访问规则
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
        }

        # 添加新规则到 ACL
        $acl.SetAccessRule($rule)

        # 应用修改后的 ACL 到目标目录
        Set-Acl -Path $Path -AclObject $acl

        Write-Host 'Permission settings completed!'
    }
    catch
    {
        Write-Error "Permission setting failed: $_"
    }
}





function Get-PipelineInput
{
    <# 
   .SYNOPSIS
   
   MrToolkit 模块包含一个名为 Get-MrPipelineInput 的函数。 此 cmdlet 可用于轻松确定接受管道输入的命令参数、接受的对象类型，以及是按值还是按属性名称接受管道输入。 
   .LINK
   https://learn.microsoft.com/zh-cn/powershell/scripting/learn/ps101/04-pipelines?view=powershell-7.4#finding-pipeline-input-the-easy-way
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [System.Management.Automation.WhereOperatorSelectionMode]$Option = 'Default',

        [ValidateRange(1, 2147483647)]
        [int]$Records = 2147483647
    )

    (Get-Command -Name $Name).ParameterSets.Parameters.Where({
            $_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName
        }, $Option, $Records).ForEach({
            [pscustomobject]@{
                ParameterName                   = $_.Name
                ParameterType                   = $_.ParameterType
                ValueFromPipeline               = $_.ValueFromPipeline
                ValueFromPipelineByPropertyName = $_.ValueFromPipelineByPropertyName
            }
        })
}
function Get-SourceCode
{
    <# 
    .SYNOPSIS
    查看Powershell当前环境下某个命令(通常是自定义的函数)的源代码
    .DESCRIPTION
    为例能够更方便地查看,在函数外面配置了本函数的Register-ArgumentCompleter 自动补全注册语句
    这样在输入命令名后按Tab键,就能自动补全命令名,然后按Tab键再次,就能查看命令的源代码

    .EXAMPLE
    PS>Get-CommandSourceCode -Name prompt

        if ($Env:CONDA_PROMPT_MODIFIER) {
            $Env:CONDA_PROMPT_MODIFIER | Write-Host -NoNewline
        }
        CondaPromptBackup;

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Get-Command $Name | Select-Object -ExpandProperty ScriptBlock

}

# 注册参数补全，使其用于 Get-CommandSourceCode 的 Name 参数
Register-ArgumentCompleter -CommandName Get-CommandSourceCode -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    # 搜索所有可能的命令以便于补全
    $commands = Get-Command -Name "$wordToComplete*" | ForEach-Object { $_.Name }
    
    # 返回补全结果
    $commands | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
function dm
{
    <# 
    .SYNOPSIS
    将powershell的prompt设置为简单的状态,以便于将聚焦到命令行上,而不是其他多余或次要的信息
    #>
    param (
    )
    Set-PromptVersion -version Default
    
}
function Set-PromptVersion
{
    <# 
    .SYNOPSIS

    设置powershell的prompt版本
    为了设置balance以及信息更丰富的prompt,这里会导入基础的powershell变量和别名

    .DESCRIPTION
    默认使用最朴素的prompt
    .EXAMPLE
    PS>Set-PromptVersion -version 'Balance'
    
    PS🌙[BAT:98%][MEM:44.97% (6.91/15.37)GB][10:27:41]
    # [cxxu@BEFEIXIAOXINLAP][<W:192.168.1.77>][~]
    PS>
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Balance', 'Simple', 'Brilliant', 'Brilliant2', 'Default', 'Short', 'short2')]
        $version = 'Default'
    )
    # 检查基础环境信息,以便powershell prompt字段可以正确显示
    Update-PwshEnvIfNotYet -Mode core # > $null
    Update-PwshAliases -Core
    Set-LastUpdateTime -Verbose:$VerbosePreference

    $env:PromptVersion = $version
    Write-Verbose "Prompt Version: $version"
}

function Set-PoshPrompt
{
    <# 
    .synopsis
    设置oh-my-posh主题,可以用 ls $env:POSH_THEMES_PATH 查看可用主题,我们只需要获取.omp.json前面部分的主题配置文件名称即可
    
    .example
    🚀 Set-PoshPrompt ys
    # cxxu @ cxxuwin in ~\Desktop [21:17:20]
    $ Set-PoshPrompt 1_shell
    >  Set-PoshPrompt iterm2
     #>
    param (
        # [Parameter(Mandatory)]
        [string]
        $Theme
    )
    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\$Theme.omp.json" | Invoke-Expression
}

function Test-PromptDelay
{
    <# 
    .SYNOPSIS
    # 测量当前使用的 Prompt 响应性能(延迟)
    通过执行多次计算平均时间来评估延迟
    .EXAMPLE

    #>
    param(
        # 加载prompt的次数,10次基本就够了(5次也够的)
        $iterations = 10
    )
    $DurationArrays = (1..$iterations | ForEach-Object { Measure-Command { Prompt *> $null } })
    $DurationSum = ($DurationArrays | ForEach-Object { $_.TotalSeconds }) | Measure-Object -Sum
    $averageDuration = $DurationSum.Sum / ($DurationArrays.Count)
    Write-Host $averageDuration 'seconds'
}

function Operators_Comparison_pwsh
{
    help about_Comparison_Operators
}
function  Operators_Logical_pwsh
{
    help about_Logical_Operators
}



function Update-Powershell-Leagcy
{
   
    Write-Output '@maybe you need to try severial times!...'
    Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI"
}

function Get-LatestPowerShellDownloadUrl
{
    param(
        [ValidateSet('msi', 'zip')]$PackageType = 'msi'
    )
    $releasesUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    $releaseInfo = Invoke-RestMethod -Uri $releasesUrl -Headers @{ 'User-Agent' = 'PowerShell-Script' }

    Write-Host "Trying to get latest PowerShell ${PackageType}..."
    foreach ($asset in $releaseInfo.assets)
    {
        if ($asset.name -like "*win-x64.${PackageType}")
        {
            return $asset.browser_download_url
        }
    }
    throw 'No suitable installer found in the latest release.'
}


function Update-PowerShell
{
    try
    {
        $downloadUrl = Get-LatestPowerShellDownloadUrl
        # 替换为加速链接(配合IDM发挥效果)
        $downloadUrl = Get-SpeedUpUri $downloadUrl
        
        Write-Host $downloadUrl -ForegroundColor Blue
        $installerPath = "$env:userprofile\Downloads\pwsh7Last.msi"

        Write-Host "Downloading PowerShell installer from $downloadUrl..."
        # Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        # 使用aria2下载
        aria2c.exe $downloadUrl -d $env:userprofile\Downloads -o 'pwsh7Last.msi'

        Write-Host 'Installing PowerShell...'
        Start-Process $installerPath
    }
    catch
    {
        Write-Host "An error occurred: $_"
        return
    }

    # 获取当前 PowerShell 版本
    $currentVersion = $PSVersionTable.PSVersion
    Write-Host "Current PowerShell version: $currentVersion"
}

# 更新 PowerShell 并显示当前版本
# Update-Powershell
function Get-ChildItemNameQuatation
{
    <# 
    .SYNOPSIS
    获取文件或者目录的名称,并添加双引号
    这是因为有时候目录中会出现一些名字奇怪的文件或目录
    他们在资源管理器中对于许多操作有不寻常的行为(比如报错)

    虽然在powershell中可以用tab 来补全文件名称,即利用ls来按下tab键,如果文件名称需要加引号,会自动加上引号
    然而这个方法并不可靠,个别情况下提示的文件名会无法被正确解析
    .EXAMPLE
    PS[BAT:76%][MEM:26.72% (8.47/31.70)GB][8:49:01]
    # [~\Downloads]
    Get-ChildItemNameQuatation

    NameQuat           FullNameQuat
    --------           ------------
    ' '                "C:\Users\cxxu\Downloads\ "
    'Compressed'       "C:\Users\cxxu\Downloads\Compressed"
    'Documents'        "C:\Users\cxxu\Downloads\Documents"
    'll'               "C:\Users\cxxu\Downloads\ll"
    'Programs'         "C:\Users\cxxu\Downloads\Programs"
    'tldr_en'          "C:\Users\cxxu\Downloads\tldr_en"
    'Video'            "C:\Users\cxxu\Downloads\Video"
    'tldr-book-en.pdf' "C:\Users\cxxu\Downloads\tldr-book-en.pdf"
    #>
    param(
        $Path = '.'
    )
    Get-ChildItem -Path $Path | ^ @{Name = 'NameQuat'; e = { "'$($_.Name)'" } }, @{Name = 'FullNameQuat'; e = { '"' + $_.fullname + '"' } }
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

    Return $PsEnvMode -ge $Value
}
function Confirm-UserContinue
{
    <# 
    .SYNOPSIS
    该函数提示用户输入y（表示继续）或n（表示停止）。
    .DESCRIPTION
    基于用户的输入，函数将返回一个布尔值：$true如果用户输入y，$false如果用户输入n。
    .EXAMPLE
    您可以直接在PowerShell脚本中调用这个Confirm-UserContinue函数，并根据返回值来执行不同的逻辑。例如：

    $continue = Confirm-UserContinue -Description "Do you want to proceed? "
    if ($continue) {
        Write-Host "User chose to continue."
        # 放置继续执行的代码
    } else {
        Write-Host "User chose to stop."
        # 放置停止执行的代码
    }
    这段代码首先会提示用户是否要继续，然后根据用户的输入执行相应的代码块。如果用户输入y，则执行继续的逻辑；如果用户输入n，则执行停止的逻辑。
    .EXAMPLE
    PS C:\repos\scripts> Confirm-UserContinue -Description 'Destription about the event to continue or not'
    Destription about the event to continue or not {Continue? [y/n]} : y
    True

    PS>Confirm-UserContinue -Description 'Destription about the event to continue or not' 
    Destription about the event to continue or not {Continue? [y/n]} : N
    False
    #>
    param (
        $Description = '',
        [string]$QuestionTail = ' {Continue? [y/n]} '
    )
    $PromptMessage = $Description + $QuestionTail
    # Write-Host $PromptMessage -ForegroundColor Blue
    while ($true)
    {
        $in = Read-Host -Prompt $PromptMessage

        switch ($in.ToLower())
        {
            'y' { return $true }
            'n' { return $false }
            default
            {
                Write-Host "Invalid input. Please enter 'y' for yes or 'n' for no."
            }
        }
    }
}
function Write-PsDebugLog
{
    <# 
    .SYNOPSIS
    调用本函数会向指定的日志文件中写入日志
    .DESCRIPTION
    函数日志包括调用词日志的函数的名字,以及函数所属的模块,调用发生的时间,以及需要追加说明的内容
    这些信息不回自动生成,需要用户自己填写,可以有选择性的填写
    #>
    param (
        [string]$FunctionName = '',
        [string]$ModuleName = ' ',
        [string]$Time ,
        $LogFilePath,
        $Comment
    )
    $PSBoundParameters
    if (! $Time)
    {
        $Time = Get-Time -TimeStap yyyyMMddHHmmssfff
        # "$(Get-Date -Format 'yyyy-MM-dd--HH-mm-ss-fff')"
    }
    if (! $LogFilePath)
    {
        #对于System这类账户使用桌面路径无效,可以考虑段路径C:\tmp或C:\Log,可以提前创建好
        if (!(Test-Path 'C:\Log'))
        {
            mkdir 'C:\Log'
        }
        $logFilePath = "c:\Log\Log`@${FunctionName}_$Time.txt"
        Write-Host $LogFilePath
        # $logFilePath = Join-Path -Path ([Environment]::GetFolderPath('Desktop')) -ChildPath "Log_$FunctionName_$Time.txt"
    }
    $logContent = "Function Name: $FunctionName`nModule Name: $ModuleName`nCall Time: $Time `n" + "comments: $Comment"

    Set-Content -Path $logFilePath -Value $logContent
    return $logContent
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
        Set-PromptVersion -version Balance -Verbose:$VerbosePreference
    }

    Write-Verbose 'Environment  have been Imported in the current powershell!'
}
 
function Start-VscodeSSh
{
    param (

        #根据查询到的ip地址,创建变量
        $Server = 'cxxuRedmibook',
        # $Path="/home/" #需要打开的目录
        $Path = $home 
    )
    code --folder-uri "vscode-remote://ssh-remote+$Server/$Path"
}

function Copy-Robocopy
{
    <# 
    .Synopsis
    对多线程复制工具Robocopy的简化使用封装,使更加易于使用,语法更加接近powershell命令
    默认启用多线程复制,如果需要递归,需要手动启用-Recurse选项
    .DESCRIPTION
    - 帮助用户更加容易的使用robocopy的核心功能(多线程复制和递归复制),作为常规copy命令的一个补充
    - 而简单的单文件复制一般用普通的copy命令就足够方便快捷了
    如果需要输出日志,使用LogFile参数指定日志文件
    .EXAMPLE
    #robocopy 原生用法常见语法用例举例
    robocopy C:\source\folder\path\ D:\destination\folder\path\ /E /ZB /R:5 /W:5 /V /MT:32
    .ExAMPLE
    PS C:\Users\cxxu\Desktop> copy-Robocopy -Source .\dir4 -Destination .\dir1\ -Recurse
    The Destination directory name is different from the Source directory name! Create the Same Name Directory? {Continue? [y/n]} : y
    Executing: robocopy ".\dir4" ".\dir1\dir4"  /E /MT:16 /R:1 /W:1

#>
    [CmdletBinding()]
    param (
        #第一批参数
        [Parameter(Mandatory = $true, Position = 0)]
        $Source,

        [Parameter(Mandatory = $true, Position = 1)]
        $Destination,

        [Parameter(Position = 2)]
        [string[]]$Files = '',
        [int]$Threads = 16, #默认是8
        [switch]$Recurse,
        # 控制失败时重试的次数和时间间隔(一般不用重试,基本上都是权限问题或者符号所指的连接无法访问或找不到)
        $Retry = 1,
        $Wait = 1,

        # 第二批
        $ExcludeDirs = '',
        $ExcludeFiles = '',
        [switch]$RecurseWithoutEmptyDirs,
        [switch]$ContinueIfbroken,

        # 第三批
        [switch]$Mirror,

        [switch]$Move,

        [switch]$NoOverwrite,

        [switch]$V,

        [string]$LogFile,


        [string[]]$OtherArgumentList
    )
   
    # Construct the robocopy command
    # 确保source和destination都是目录
    if (Test-Path $Source -PathType Leaf)
    {
        Throw 'Source must be a Directory!'
    }if (Test-Path $Destination -PathType Leaf)
    {
        throw 'Destination must be a Directory!'
    }

    Write-Host 'checking directory name...'
    #向用户展示参数设置
    # $PSBoundParameters  
    # 这里要求$source和$destination在函数参数定义出不可以定为String类型,会导致Get-PsIOItemInfo返回值无法正确赋值
    # $Source = Get-PsIOItemInfo $Source
    # $destination = Get-PsIOItemInfo $Destination

    # 检查目录名是否相同(basename)
    # $SN = $source.name
    # $DN = $Destination.name
    $SN = Split-Path -Path $Source -Leaf
    $DN = Split-Path -Path $Destination -Leaf

    Write-Verbose "$SN,$DN"
    if ($SN -ne $DN)
    {
        # Write-Verbose "$($Source.name) -ne $($destination.name)"

        $continue = Confirm-UserContinue -Description 'The Destination directory name is different from the Source directory name! Create the Same Name Directory?'
        if ($continue)
        {
            $Destination = Join-Path $Destination $SN
            Write-Verbose "$Destination" -Verbose
        }
    }

    #debug
    # return
    $robocopyCmd = "robocopy `"$Source`" `"$Destination`" $Files"

    if ($Mirror)
    {
        $robocopyCmd += ' /MIR'
    }

    if ($Move)
    {
        $robocopyCmd += ' /MOVE'
    }

    if ($NoOverwrite)
    {
        $robocopyCmd += ' /XN /XO /XC'
    }

    if ($Verbose)
    {
        $robocopyCmd += ' /V'
    }

    if ($LogFile)
    {
        $robocopyCmd += " /LOG:`"$LogFile`""
    }

    # if ($Threads -gt 1)
    # {
    #     $robocopyCmd += " /MT:$Threads"
    # }
    if ($OtherArgumentList)
    {
        $robocopyCmd += ' ' + ($OtherArgumentList -join ' ')
    }
    if ($Recurse)
    {
        $robocopyCmd += ' /E'
    }
    # if ($ContinueIfbroken)
    # {
    #     $robocopyCmd += ' /Z'
    # }
    if ($RecurseWithoutEmptyDirs)
    {
        $robocopyCmd += ' /S'
    }if ($ExcludeDirs)
    {
        $robocopyCmd += " /XD $ExcludeDirs"
    }if ($ExcludeFiles)
    {
        $robocopyCmd += " /XF $ExcludeFiles"
    }

    # 默认使用(每个参数前有一个空格分割)
    $robocopyCmd += " /MT:$Threads"
    #默认启用自动重连(断点续传)
    $robocopyCmd += ' /z' 
    # 重试次数和间隔限制
    $robocopyCmd += " /R:$Retry /W:$Wait"

    # Invoke the robocopy command
    Write-Host "Executing: $robocopyCmd"
    Invoke-Expression $robocopyCmd
}


