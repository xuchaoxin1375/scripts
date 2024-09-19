

function p
{
    <# 
    .SYNOPSIS
    打开新的powershell环境，加载最基础的列表图标模块
    .DESCRIPTION
    支持两种模式,一类是当需要要刷新模块时,在当前powershell会话中执行此命令
    另一类是作为每个powershell会话自动导入的基础性配置
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
        $NoNewShell #默认启动新环境

    )
    $script = { 
        # 设置prompt样式(这里面会导入基础的powershell预定变量和别名)
        Set-PromptVersion Balance ;  
        # 导入图标模块
        Import-TerminalIcons;
        # 补全模块PSReadline及其相关配置
        Set-PSReadLinesCommon; 
        Set-PSReadLinesAdvanced
        
    }
    if ($NoNewShell)
    {
        # 当前环境不启动新的shell环境，直接执行$script
        Write-Host 'Setting basic environment in current shell...'
        & $script
    }
    else
    {
        # 请求启动新的powershell环境
        Write-Host 'Loading new pwsh environment...'

        pwsh -noe -c $script 
        # pwsh -noe -c {p -NoNewShell }
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
        p -NoNewShell
    }.ToString().Trim()>>$pf #向配置文件追加内容
    '# End AutoRun commands from CxxuPsModules' >> $pf
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

function PromptBrilliant
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

    .PARAMETER Path
    要计算大小的文件或目录的路径。可以是相对路径或绝对路径。

    .PARAMETER Unit
    指定结果显示的单位。可选值为 B（字节）、KB、MB、GB、TB。默认为 MB。

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
        $unitMultiplier = @{
            'B'  = 1
            'KB' = 1KB
            'MB' = 1MB
            'GB' = 1GB
            'TB' = 1TB
        }
    }

    process
    {
        foreach ($item in $Path)
        {
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
                if ($itemInfo -is [System.IO.DirectoryInfo])
                {
                    $size = (Get-ChildItem -Path $item -Recurse -Force | Measure-Object -Property Length -Sum).Sum
                }
                else
                {
                    $size = (Get-Item $item).Length
                }

                $sizeInSpecifiedUnit = $size / $unitMultiplier[$Unit]
                Write-Verbose "`$sizeInSpecifiedUnit: $sizeInSpecifiedUnit"
                $Size = [math]::Round($sizeInSpecifiedUnit, [int]$Precision)
                Write-Verbose "`$size: $Size"
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
        Write-Host 'Calculating ... '
        $res = Get-ChildItem $Path | ForEach-Object {
            $item = $_ | Get-Size -Unit $Unit -Precision $Precision -Detail:$Detail -SizeAsString:$SizeAsString -Verbose:$false # -FormatTable:$FormatTable 
            
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

function Get-CxxuPsModulePackage
{
    param(
        $Directory = "$home/Downloads/CxxuPsModules",
        $url = 'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main',
        $outputFile = "scripts-$( Get-Date -Format 'yyyy-MM-dd--hh-mm-ss').zip"
    )
    $PackgePath = "$Directory/$outputFile"
    Invoke-WebRequest -Uri $url -OutFile $PackgePath 
    return $PackgePath
}
function Deploy-CxxuPsModules
{
    <# 
    .SYNOPSIS
    一键部署CxxuPsModules，将此模块集推荐的自动加载工作添加到powershell的配置文件$profile中
    请使用powershell7部署
    #>
    [CmdletBinding()]
    param(
        $RepoPath = "$env:systemdrive/repos/scripts",
        $newPsPath = "$RepoPath/PS",
        [ValidateSet('Gitee,Github')]$Source = 'gitee',
        $PackagePath = "$home/Downloads/CxxuPsModules/scripts*.zip"
    )
        
    if ($host.Version.Major -lt 7)
    {
        Throw 'Please use powershell7 to deploy CxxuPsModules!'
    }
    
    # 路径准备
    if (!(Test-Path $RepoPath))
    {
        New-Item -ItemType Directory $RepoPath -Verbose
    }
    if ((Test-Path $PackagePath))
    {
        Write-Host "Mode:Expanding local pacakge:[$PackagePath]" -ForegroundColor Green
        $RepoPathParentDir = Split-Path $RepoPath -Parent
        # 指定要解压到的目录,如果不存在Expand-archive会自动创建相应的目录
        # 获取可用的最新版本
        #利用Desceding将最新的排在前面
        $files = Get-ChildItem $PackagePath | Sort-Object -Property LastWriteTime -Descending 
        $PackagePath = @($files)[0]
        Expand-Archive -Path $PackagePath -DestinationPath $RepoPathParentDir -Force
        Rename-Item (Get-ChildItem "$RepoPath/scripts*" | Select-Object -First 1) "$RepoPathParentDir/scripts" -Verbose
    }
    else
    {
        Write-Host "Mode:Clone From Remote repository:[$source]" -ForegroundColor Blue
        $url = "https://${Source}.com/xuchaoxin1375/scripts.git"
        Write-Verbose $url
        # 检查路径占用
        if (Test-Path $RepoPath)
        {
            Write-Host "$($RepoPath) already exists!Choose another path."
            $RepoPath = Read-Host -Prompt 'Input new path (Ctrl+C to exit)'
        }
        Write-Verbose $RepoPath
        #克隆仓库
        # git 支持指定一个不存在的目录作为克隆目的地址,所以可以不用检查目录是否存在并手动创建
        git clone $url $RepoPath
    }
 
    # $RepoPath = 'C:\repos\scripts\PS' #这里修改为您下载的模块所在目录,这里的取值作为示范
    $env:PSModulePath = ";$NewPsPath" #为了能够调用CxxuPSModules中的函数,这里需要这么临时设置一下
    Add-EnvVar -EnvVar PsModulePath -NewValue $newPsPath -Verbose #这里$RepoPath上面定义的(默认是User作用于,并且基于User的原有取值插入新值)
    # 你也可以替换`off`为`LTS`不完全禁用更新但是降低更新频率(仅更新LTS长期支持版powershell)
    [System.Environment]::SetEnvironmentVariable('powershell_updatecheck', 'LTS', 'user')

    #添加基础环境自动执行任务到$profile中
    # Add-CxxuPsModuleToProfile

    #检查模块设置效果
    Start-Process -FilePath pwsh -ArgumentList '-noe -c p'
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
    $releasesUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    $releaseInfo = Invoke-RestMethod -Uri $releasesUrl -Headers @{ 'User-Agent' = 'PowerShell-Script' }

    foreach ($asset in $releaseInfo.assets)
    {
        if ($asset.name -like '*win-x64.msi')
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
        )]$Mode = 'Env'
    )
    # 如果环境模式(等级)不满足要求,则导入对应级别的环境
    if (! (Test-PsEnvMode -Mode $Mode ))
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
function ue
{
    <# 
    .SYNOPSIS 
    作为高优先级的别名,定义为函数Udpate-PwshEnvIfNotYet的可直接调用的别名函数
    #>
    Update-PwshEnvIfNotYet
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
    $PSBoundParameters  
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
            $Destination = Join-Path $Destination $Source.Name
            Write-Verbose "$Destination"
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


