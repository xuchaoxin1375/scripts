<#
Prompt 模块:提示符(prompt)及其片段(Write-*)、主题切换(Set-PsPrompt* FutureWarning)
从 Pwsh.psm1(Write-*/Prompt*/Set-PsPrompt/dm/Test-PromptDelay/oh-my-posh 相关)
与 ArgumentCompletion.psm1(prompt/promptx 入口)迁入,职责单一:只管提示符渲染与切换.
首次调用 prompt 或 Set-PsPrompt 时由 powershell 自动加载.
#>

# 只抓一次(存全局):ipmof|iex 会 Remove 后裸重载,此时全局 prompt 为空,重抓只会抓到 $null 造成每回车报错;
# 首轮非 Prompt 模块拥有的 prompt(conda 包壳/默认)才存,之后重载一律复用,不再跟随当前值;
# 想换底(如后激活 conda):Remove-Variable global:__CxxuOriginalPrompt 后重载一次即可重抓
if ($null -eq $global:__CxxuOriginalPrompt)
{
    $curPromptCmd = Get-Command prompt -ErrorAction SilentlyContinue
    if ($curPromptCmd -and $curPromptCmd.ModuleName -ne 'Prompt' -and $null -ne $Function:prompt)
    {
        $global:__CxxuOriginalPrompt = $Function:prompt
    }
}
$originalPromptScript = $global:__CxxuOriginalPrompt #禁止在自定义prompt函数体内部执行此代码
# 5.1 兜底:Info/Startup 两模块留 7,prompt 热路径依赖的外部命令本地实现(与真身同口径,纯 CIM/注册表/内置 cmdlet,5.1 原生可用;7.x 永不进入,行为不变)。
# 必须 function global: 定义:模块私有函数 prompt 内部能用,但用户直接调用走自动发现会撞上坏的 Info;全局定义两边都通。缓存同理用 $global: 命名空间变量。
if ($PSVersionTable.PSVersion.Major -lt 7)
{
    # 与 Info 真身方案 2 同口径
    if (-not (Get-Command Get-UserHostName -ErrorAction Ignore))
    {
        function global:Get-UserHostName { "$([System.Environment]::UserName)@$([System.Environment]::MachineName)" }
    }
    # 5.1 无 Get-Uptime cmdlet;调用方只取 .TotalDays,TimeSpan 同形(开机时间小时级不变,缓存 120s)
    $global:__Cxxu51Uptime = @{ Value = $null; Time = [datetime]::MinValue }
    if (-not (Get-Command Get-Uptime -ErrorAction Ignore))
    {
        function global:Get-Uptime
        {
            $expired = ($global:__Cxxu51Uptime.Time -eq [datetime]::MinValue) -or (([datetime]::UtcNow - $global:__Cxxu51Uptime.Time).TotalSeconds -ge 120)
            if ($expired)
            {
                $global:__Cxxu51Uptime = @{ Value = (New-TimeSpan -Start (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime -End (Get-Date)); Time = [datetime]::UtcNow }
            }
            return $global:__Cxxu51Uptime.Value
        }
    }
    # 与 Info 真身同表达式(无电池机器同样 $null,调用方行为一致)
    if (-not (Get-Command Get-BatteryLevel -ErrorAction Ignore))
    {
        function global:Get-BatteryLevel { Get-CimInstance -ClassName Win32_Battery | Select-Object -ExpandProperty EstimatedChargeRemaining }
    }
    # 与 Info 真身同形({.MemoryUsePercentage,.MemoryUseRatio},GB 两位小数);CIM 每回车查太贵,缓存 10s
    $global:__Cxxu51Mem = @{ Value = $null; Time = [datetime]::MinValue }
    if (-not (Get-Command Get-MemoryUseSummary -ErrorAction Ignore))
    {
        function global:Get-MemoryUseSummary
        {
            $expired = ($global:__Cxxu51Mem.Time -eq [datetime]::MinValue) -or (([datetime]::UtcNow - $global:__Cxxu51Mem.Time).TotalSeconds -ge 10)
            if ($expired)
            {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem
                $total = $os.TotalVisibleMemorySize / 1MB
                $used = $total - ($os.FreePhysicalMemory / 1MB)
                $global:__Cxxu51Mem = @{ Value = ([PSCustomObject]@{
                        MemoryUsePercentage = [math]::Round(($used / $total) * 100, 2)
                        MemoryUseRatio      = "$([math]::Round($used, 2))/$([math]::Round($total, 2))"
                    }); Time = [datetime]::UtcNow }
            }
            return $global:__Cxxu51Mem.Value
        }
    }
    # 真身(Get-IpAddressFormated)在 Info(留 7):同格式<网卡首字:ip>的 5.1 移植版(去文件缓存,会话 60s;参数集与真身对齐,直接调用也可用)
    $global:__Cxxu51IpFormat = @{ Value = $null; Time = [datetime]::MinValue }
    if (-not (Get-Command Get-IpAddressFormated -ErrorAction Ignore))
    {
        function global:Get-IpAddressFormated
        {
            [CmdletBinding(DefaultParameterSetName = 'Cache')]
            param(
                [ValidateSet('Up', 'Disconnected', 'All')]$Status = 'up',
                [parameter(ParameterSetName = 'Cache')][switch]$Cache,
                [switch]$Clear,
                $dataJson = $null,
                $TTLSeconds = 60
            )
            if ($Clear)
            {
                $global:__Cxxu51IpFormat = @{ Value = $null; Time = [datetime]::MinValue }
                return
            }
            $expired = ($global:__Cxxu51IpFormat.Time -eq [datetime]::MinValue) -or (([datetime]::UtcNow - $global:__Cxxu51IpFormat.Time).TotalSeconds -ge $TTLSeconds)
            if (-not $expired -and ($null -ne $global:__Cxxu51IpFormat.Value))
            {
                return $global:__Cxxu51IpFormat.Value
            }
            $ipTable = @{}
            Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
                if (-not $ipTable.ContainsKey($_.InterfaceIndex)) { $ipTable[$_.InterfaceIndex] = @() }
                $ipTable[$_.InterfaceIndex] += $_.IPAddress
            }
            $s = ''
            $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue
            if ($Status -ne 'All')
            {
                $adapters = $adapters | Where-Object { $_.Status -eq $Status }
            }
            foreach ($adapter in ($adapters | Select-Object Name, Status, InterfaceIndex))
            {
                $s += ("<$($adapter.Name[0]):$($ipTable[$adapter.InterfaceIndex])>")
            }
            $global:__Cxxu51IpFormat = @{ Value = $s; Time = [datetime]::UtcNow }
            return $s
        }
    }
    # 真身走 DataJson/环境缓存链(留 7);5.1 直接复用上面的移植版(调用时解析,定义顺序无关)
    if (-not (Get-Command Get-IpAddressForPrompt -ErrorAction Ignore))
    {
        function global:Get-IpAddressForPrompt
        {
            param([switch]$KeepUpdate)
            return (Get-IpAddressFormated)
        }
    }
    # 与 Startup 真身同语义(缺失才算,进程级;Caption 拼接表达式逐字照抄)
    if (-not (Get-Command Confirm-OSVersionCaption -ErrorAction Ignore))
    {
        function global:Confirm-OSVersionCaption
        {
            param([alias('Update')][switch]$Force)
            if ($Force -or ($null -eq $env:OSCaption))
            {
                $os = Get-CimInstance Win32_OperatingSystem
                $env:OSCaption = 'Win' + $os.Caption.Split('Windows')[1]
            }
            return $env:OSCaption
        }
    }
    # 真身读注册表 FullVersion(Startup 留 7);显示形如 10.0.26100.2152
    if (-not (Get-Command Confirm-OSVersionFullCode -ErrorAction Ignore))
    {
        function global:Confirm-OSVersionFullCode
        {
            param([alias('Update')][switch]$Force)
            if ($Force -or ($null -eq $env:OSFullVersionCode))
            {
                $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
                $env:OSFullVersionCode = '{0}.{1}.{2}.{3}' -f $cv.CurrentMajorVersionNumber, $cv.CurrentMinorVersionNumber, $cv.CurrentBuildNumber, $cv.UBR
            }
            return $env:OSFullVersionCode
        }
    }
    # Write-OSVersionInfo 在 $env:OSDisplayVersion 缺失时调 Startup 取 DisplayVersion;直读注册表
    if (-not (Get-Command Get-WindowsOSVersionFromRegistry -ErrorAction Ignore))
    {
        function global:Get-WindowsOSVersionFromRegistry
        {
            $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            [PSCustomObject]@{ DisplayVersion = $cv.DisplayVersion }
        }
    }
}
function promptx
{
    <# 
    .SYNOPSIS
    Prompt:设置powershell提示符(powershell 默认调用)
    .DESCRIPTION
    读取相应的环境变量类设定prompt样式,配合Set-PsPrompt来指定prompt样式.
    Prompt最终结果由两类输出/打印组成,一类是prompt中包含的打印语句(主要是write-host,可能带有颜色),
    另一部分是返回值(隐式或显式的返回值),这部分可以在返回之前做字符串处理
    
    但我们这里改写Prompt函数,而且还可以通过设置环境变量来更改当前prompt主题
    Prompt函数无法传参,但是可以通过设置辅助函数Set-PsPrompt,修改主题来间接传参(控制全局变量)
    关于这部分逻辑详见外部的Set-PsPrompt
    .NOTES
    调试:
    借助prompt -Debug可以调试prompt函数,尤其是在使用模块重载时如果prompt发生异常,则-Debug选项会显示脚本代码块
    目前配置自动激活后(例如mamba shell init --shell powershell --root-prefix=~/.local/share/mamba)
    powershell的提示符才会带上(base)这类前缀
    .NOTES
     2026-09-20 已有更好解决办法:顶层改"全局只抓一次"($global:__CxxuOriginalPrompt),
     Remove 后裸重载复用首存,不再抓空/抓旧,故 Prompt 可留在 ipmof 轮转里正常刷新
    #>
    [CmdletBinding()]
    param()
    # 和上一层输出间隔一行
    # Write-Host ''
    # Write-Host '# PS> '

    # 计算原来的提示符(conda,nvm等程序可能会在这个阶段完成修改)
    # $originalPromptScript = $function:prompt #禁止在prompt内部执行此代码
    Write-Debug "{$originalPromptScript}" 
    # & $originalPromptScript
    $prefix = & $originalPromptScript
    # 丢弃此部分的返回值
    $prefix > $null
    # 或打印出来查看
    # Write-Host "[[$prefix]]"
    
    # 不要在当前函数prompt中调用prompt,会导致递归调用,逻辑上出不来.
    # $prefix = prompt # 禁止直接执行!应当在自定义函数prompt外部就把原prompt的脚本块提取出来执行
    # $prefix = $prefix.TrimEnd('>')+'|'
    # Write-Verbose "Original Prompt: $prefix" -verbose

    # 根据环境变量PS_PATH_CUR 取值是否为true,来决定是否总是将工作目录添加到PATH中
    ##  Set-EnvVar -EnvVar PS_PATH_CUR -NewValue true #(持久生效)
    ##  $env:PS_PATH_CUR=false #(临时生效)
    if ($env:PS_PATH_CUR -eq 'true')
    {
        # 将当前目录添加到环境变量PATH中,实现简化: .\runable.ext -> runable.ext
        $currentPath = Get-Location | Select-Object -ExpandProperty Path
        if (($env:Path -split ';') -notcontains $currentPath)
        {
            # Write-Host "# Adding $currentPath to PATH"
            $env:Path += ";$currentPath"
        }
    }

    switch ($env:PsPrompt)
    {
        'Fast' { PromptFast }
        'Brilliant' { PromptBrilliant }
        'Brilliant2' { PromptBrilliant2 }
        'Balance' { PromptBalance }
        'Simple' { PromptSimple }
        'short2' { PromptShort2 }
        'short' { PromptShort }
        'Default' { PromptDefault }
        default { PromptDefault }
    }
    # return 'PS> '
    # 如果追求纯净,可以返回空字符串或者tab缩进
    return ' '
    
}
function prompt
{
    param (
    )
    promptx
    
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

function Set-PsPromptStyle
{
    <# 
    .SYNOPSIS
    设置powershell提示符,这里的方案是不影响Prompt函数的
    但是不适合编写复杂的Prompt,可读性不佳

    复杂Prompt可以通过另一个方案:PsPrompt配合环境变量来实现
    两种方案中,第二种方案会覆盖掉本方案,但是可以将本方案打包,作为PsPrompt的一个版本
    .EXAMPLE
    PS [cxxu\Desktop] > Set-PsPromptStyle  -Short
    .EXAMPLE
    PS [Desktop] >  Set-PsPromptStyle  -Simple
    .EXAMPLE
    PS>Set-PsPromptStyle  -Default
    .EXAMPLE
    PS [C:\Users\cxxu\Desktop] > Set-PsPromptStyle
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
function Write-Uptime
{
    param (
        
    )
    $time = Get-Uptime | Select-Object -ExpandProperty TotalDays
    $res = [math]::Round($time, 2)
    Write-Host "[UP:${res}Days]" -ForegroundColor DarkGray -NoNewline
    
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
    Write-Host (('[' + $ip + ']')) -ForegroundColor Cyan -NoNewline
}
function write-PermissoinLevel
{
    <# 
    
    .SYNOPSIS

    定义权限区域的颜色(但是容易引起错位显示,尤其是amd平台,建议不启用颜色)
    #>
    param (
    )
    if (Test-AdminPermission)
    {
        # $s = '#⚡️', 'Cyan'
        $s = '#Admin', 'Cyan'
        

    }
    else
    {
        $s = '# ' , 'DarkGray'
    }
    # Write-Host $s[0] -BackgroundColor $s[1] -NoNewline
    Write-Host $s[0] -NoNewline
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
    #获取windows edition 例如 Win 11 Pro
    $res = Confirm-OSVersionCaption
    if (!$CaptionOnly)
    {
        # 优先读 init 持久化的缓存,缺失才读注册表(例如24H2)
        $displayversion = if ($env:OSDisplayVersion) { $env:OSDisplayVersion } `
            else { Get-WindowsOSVersionFromRegistry | Select-Object -ExpandProperty DisplayVersion }
        $OsVersionFullCode = (Confirm-OSVersionFullCode) #例如 10.0.26100.2152
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

    # if ($PSEnvMode -eq 3)
    # {
    #     $mode = '☀️'
    # }
    # elseif ($Psenvmode -eq 2)
    # {
    #     $mode = '🌓'
    # }
    # elseif ($Psenvmode -eq 1)
    # {
    #     $mode = '🌙'
    # }
    $mode = $Psenvmode
    Write-Host "[Mode:$mode]" -NoNewline # -BackgroundColor 'green'
    
}
function write-PsMode
{
  
    Write-Host 'PS' -NoNewline -BackgroundColor Magenta
    write-PsEnvMode
    
}
# prompt 高频调用,电池 CIM 查询按 TTL 缓存(内存占用已有 5s 节流,见 Get-MemoryUseRatio)
$script:BatteryCache = @{ Value = $null; Time = [datetime]::MinValue }
function Get-BatteryLevelCached
{
    <# .SYNOPSIS prompt 专用:带 30s 缓存的电量读取(含无电池机器的 $null 也缓存) #>
    param($TTLSeconds = 30)
    $expired = ($script:BatteryCache.Time -eq [datetime]::MinValue) -or `
        (([datetime]::UtcNow - $script:BatteryCache.Time).TotalSeconds -ge $TTLSeconds)
    if ($expired)
    {
        $script:BatteryCache.Value = Get-BatteryLevel
        $script:BatteryCache.Time = [datetime]::UtcNow
    }
    return $script:BatteryCache.Value
}
function Write-BatteryAndMemoryUse
{
    <#
    .SYNOPSIS
    调用Get-MemoryUseSummary和Get-BatteryLevel,做进一步处理使得其适合作为Prompt的一部分
    #>
    # prepare data
    $MemoryUseSummary = Get-MemoryUseSummary #耗时逻辑
    #数据解包
    $MemoryUsePercentage, $MemoryUseRatio = $MemoryUseSummary.MemoryUsePercentage, $MemoryUseSummary.MemoryUseRatio #0.1s左右
    $BAT = Get-BatteryLevelCached
    
 
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


function PromptFast
{
    <# 
 .SYNOPSIS
 对性能影响小的快速提示符
 #>


    # Write-Host "`t" -NoNewline
    write-PermissoinLevel
    Write-Host "[$current_shell]" -NoNewline
    Write-UserHostname
    # Write-HostIp
    Write-Path
    Write-Time
    # Write-Uptime #统计不太准,而且比较少用
    write-GitBasicInfo
    Write-Host ''
    # Write-Host ' PS >'
    
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
    Write-BatteryAndMemoryUse #这个部分内部设计比较复杂，肆意修改容易出现错误，如果出现错误，请注释掉它来检验是否是它引起的
    # Write-Host "`t" -NoNewline
    # Write-Data;
    Write-OSVersionInfo
    Write-Time
    Write-Uptime
    
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

function Get-GitInfo
{
    # ── 1. 获取 .git 目录路径 ──────────────────────────────────────
    $gitDir = git rev-parse --git-dir 2>$null
    if (-not $gitDir) { return "" }          # 不在 git 仓库，直接返回

    # ── 2. 构建 HEAD 文件路径 ──────────────────────────────────────
    $headFile = Join-Path $gitDir "HEAD"
    if (-not (Test-Path $headFile -PathType Leaf)) { return "" }

    # ── 3. 读取 HEAD 内容 ──────────────────────────────────────────
    # 只读第一行，等价于 read
    $headContent = Get-Content -LiteralPath $headFile -TotalCount 1 -Encoding utf8

    # ── 4. 判断分支 or Detached HEAD ──────────────────────────────
    $branch = if ($headContent -match '^ref: refs/heads/(.+)$')
    {
        $Matches[1]                              # 捕获组1 = 分支名
    }
    else
    {
        $headContent.Substring(0, [Math]::Min(7, $headContent.Length))
    }                                            # 游离状态取前7位 hash

    # ── 5. 构建带颜色的输出 ────────────────────────────────────────
    # $yellow = "`e[33m"    # ANSI 黄色  (PowerShell 7+ 支持 `e 转义)
    # $red = "`e[31m"    # ANSI 红色
    # $reset = "`e[0m"     # 重置颜色

    # return " ${yellow}on${reset} ${red}git:${branch}${reset}"
    return "${branch}"
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
    # if (Test-Path (Join-Path $path '.git') )
    # {
    #     $Gitavailability = Get-Command git -ErrorAction SilentlyContinue
    #     if ($Gitavailability)
    #     {
    #         # 使用git命令获取当前分支名称
    #         $gitBranch = & git symbolic-ref --short HEAD
    #         $gitBranch = $gitBranch.Trim()
    #     }
    #     else
    #     {
    #         # 捕获任何异常（例如，当前目录不是Git仓库）
    #         $gitBranch = ''
    #     }
    # }
    $gitBranch = Get-GitInfo $Path
    if ($gitBranch)
    {
        <# Action to perform if the condition is true #>
        $gitBranch = "{Git:$gitBranch}"
        
        Write-Host $gitBranch -ForegroundColor DarkCyan -NoNewline
    }
    # return $gitBranch
    

    # 保存以上内容到你的PowerShell配置文件$PROFILE中，然后重新加载它或重启PowerShell
}

function Get-PromptScriptBlock
{
    <# 
    .SYNOPSIS
    获取当前prompt脚本块
    .DESCRIPTION
    获取当前prompt脚本块
    #>
    param (
    )
    return $function:Prompt
    
}

function dm
{
    <# 
    .SYNOPSIS
    将powershell的prompt设置为简单的状态,以便于将聚焦到命令行上,而不是其他多余或次要的信息
    #>
    param (
    )
    Set-PsPrompt -version Default
    
}

function Set-PsPrompt
{
    <# 
    .SYNOPSIS

    设置powershell的prompt版本
    .DESCRIPTION
    通过设置环境变量PsPrompt,间接指定prompt版本(具体的prompt指定函数会读取这个环境变量)
    .NOTES
    为了设置balance以及信息更丰富的prompt,这里会导入基础的powershell变量和别名

    .DESCRIPTION
    默认使用最朴素的prompt
    .EXAMPLE
    PS>Set-PsPrompt -version 'Balance'
    
    PS🌙[BAT:98%][MEM:44.97% (6.91/15.37)GB][10:27:41]
    # [cxxu@BEFEIXIAOXINLAP][<W:192.168.1.77>][~]
    PS>
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('fast', 'Balance', 'Simple', 'Brilliant', 'Brilliant2', 'Default', 'Short', 'short2')]
        # $version = 'Default'
        $version = '',
        # 是否将选择持久化到用户注册表(慢,一次性;默认仅进程级生效,启动更快)
        [switch]$Persist
        # ,
        # [switch]$Permanent
    )

    if (! $version)
    {
        # 用户不指定prompt版本时,尝试读取环境变量PsPrompt
        if ($env:PsPrompt)
        {
            Write-Verbose "env:PsPrompt=[$env:PsPrompt]"
            $version = $env:PsPrompt
        }
        else
        {
            # 用户没有指定Prompt版本且环境变量PsPrompt也没有指定Prompt版本时,则默认启用Balance版本
            $version = 'fast'
        }
    }
    else
    {
        # 进程级写入(快);仅 -Persist 时才写注册表(慢,Set-EnvVar 会全量扫描+写注册表)
        Set-ProcessEnvVar -EnvVar PsPrompt -NewValue $version
        if ($Persist)
        {
            Set-EnvVar -EnvVar PsPrompt -NewValue $version
        }
    }

    # 检查基础环境信息,以便powershell prompt字段可以正确显示
    Update-PwshEnvIfNotYet -Mode core # > $null
    Update-PwshAliases -Core
    Set-LastUpdateTime -Verbose:$VerbosePreference

    $env:PsPrompt = $version
    Write-Verbose "Prompt Version: $version"
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
    $DurationArrays = (1..$iterations | ForEach-Object { Measure-Command { prompt *> $null } })
    $DurationSum = ($DurationArrays | ForEach-Object { $_.TotalSeconds }) | Measure-Object -Sum
    $averageDuration = $DurationSum.Sum / ($DurationArrays.Count)
    Write-Host $averageDuration 'seconds'
}
