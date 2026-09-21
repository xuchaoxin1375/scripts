function ResourceMonitor
{
    <#
    .SYNOPSIS
    打开资源监视器
    #>
    # windir目录中的perfmon是windows性能监视器,资源监视器可以通过传入/res 来启动
    perfmon.exe /res
}

function Get-CapacityUnitized
{
    <#

.SYNOPSIS
    Calculates the memory value in the specified unit.

.DESCRIPTION
    This function takes a memory value and a unit as input and returns the memory value in the specified unit.

.PARAMETER memory
    The memory value to be calculated.

.PARAMETER divisor
    The divisor to be used for calculation.

.EXAMPLE
    PS C:\> Get-CapacityUnitized -memory 1024 -divisor 1KB
    1

    This example calculates the memory value of 1024 bytes in kilobytes and returns 1.
#>
    param ($memory, $divisor)
    
    [math]::Round($memory / $divisor, 2)

}

function Get-MemoryCapacity
{
    [CmdletBinding()]
    param (
        [ValidateSet('B', 'KB', 'MB', 'GB', 'TB')]
        [string]$Unit = ''
    )

    # 获取总内存
    $totalMemory = if($isWindows) { Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory }else
    {
        sysctl -n hw.memsize
    }

    # 定义单位与除数的哈希表
    $unitDivisors = @{
        B  = 1
        KB = 1KB
        MB = 1MB
        GB = 1GB
        TB = 1TB
    }

    if ($Unit)
    {
        # 输出指定单位的内存大小
        $memoryValue = Get-CapacityUnitized -memory $totalMemory -divisor $unitDivisors[$Unit]
        [PSCustomObject]@{
            Value = $memoryValue
            Unit  = $Unit
        }
    }
    else
    {
        # 默认以表格形式输出所有单位
        $outputTable = foreach ($u in $unitDivisors.Keys)
        {
            [PSCustomObject]@{
                Value = Get-CapacityUnitized -memory $totalMemory -divisor $unitDivisors[$u]
                Unit  = $u
            }
        }

        # 输出表格
        $outputTable | Format-Table -AutoSize
    }
}


function Get-LocalGroupOfUser
{
    <# 
    .SYNOPSIS
    查询用户所在的本地组,可能有多个结果
    功能类似于lusrmgr中的Member of,即可以用lusrmgr GUI查看
    .EXAMPLE
    PS>get-LocalGroupOfUser cxxu
    docker-users
    Administrators
    PS>get-LocalGroupOfUser usertest
    Administrators
    PS>get-LocalGroupOfUser NotExistUser
    #>
    param (
        $UserName
    )
    
    Get-LocalGroup | ForEach-Object {
        $members = Get-LocalGroupMember -Group $_ 
        # return $members
        foreach ($member in $members)
        {
            $name = ($member.name -split '\\')[-1]#
            if ( $name -match $UserName)
            {
                
                Write-Host "$_" -ForegroundColor Magenta
                return
            } 
        }
    }
    #  Get-LocalGroupMember -Group $_| Where-Object { ($i.name -split '\\')[-1] -match 'UserTest'}
}
function Get-NetConnectionInfo
{
    <# 
    .SYNOPSIS
    返回当前所链接wifi的名字(如果连上了的话)
    #>
    [CmdletBinding()]
    param(
        # [switch]$WriteToEnv,
        $EnvName = 'ConnectionName'
        # [switch]$CheckUpdateEnvConnectionName
    )
    # 老式方法:netsh (不推荐)
    # $wifiProfile = netsh wlan show interfaces | Select-String '^\s+Profile\s+:\s+(.*)$'
    # $ConnectionName = $wifiProfile.Matches[0].Groups[1].Value.Trim()

    $Name = (Get-NetConnectionProfile).Name
    return $Name
}

function Update-NetConnectionInfo
{
    <# 
    .SYNOPSIS
    检测网络间接信息(连接名,比如wifi名字或者以太网名字)
    从DataJson中尝试读取相关信息,如果和当前检测到的信息内容不对应,那么认为链接发生了变化,需要更新连接名称(ConnectionName)

    此更新进程不会检查ip地址是否变化,只会在需要时更新连接名(顺便重置ip地址)
    也就是说,只要网络连接没有发生变换,那么dataJson文件就不会被此进程更改,指示定时读取里面的数据和当前的实际情况进行对比来检测网络状态变换以及更新对应的ip地址,供其他进程使用,比如Prompt显示ip地址
    #>
    [CmdletBinding()]
    param (
        $DataJson = $DataJson,
        $connectionName = 'ConnectionName',
        $Interval = 6
    )
    # 注:此处曾有 Write-Host $DataJson 调试输出(每次守护进程启动都会向控制台吐一行路径),已删除
    # 守护进程用不上 predictor:经 -Command/-c 起来的后台会话关掉它(交互会话手动调不受影响)
    if (@([Environment]::GetCommandLineArgs()) -match '^-(?i:c|command)$')
    {
        $env:PsPredictor = 'False'
    }
    while ($true)
    {
        $Name = @(Get-Json -Key $ConnectionName -dataJson $DataJson -ErrorAction SilentlyContinue)
        $newName = @(Get-NetConnectionInfo)
        if ($VerbosePreference)
        {

            # "Name: $Name, NewName: $newName"
            [PSCustomObject]@{
                Name    = $Name
                NewName = $newName
            } | Format-Table
        }

        # 排序并转换为字符串
        $NameValue = ($Name | Sort-Object) -join ','
        $NewNameValue = ($NewName | Sort-Object) -join ','
        # $res = $newName -eq $Name
        $res = $NameValue -eq $NewNameValue
        if (!$res)
        {
            Write-Host "Name changed: $NameValue -> $NewNameValue" -ForegroundColor Magenta
            # 修改数据文件
            Update-Json -Key $connectionName -Value $NewNameValue -Path $DataJson
            Get-IpAddressFormated -dataJson $DataJson # 重新获取IP 
            Update-DataJsonLastWriteTime -DataJson $DataJson
                    
        }
        else
        {
            Write-Host "Name not changed: $NameValue" -ForegroundColor Green
        }
          
        Start-Sleep $Interval
    }
}
# prompt 高频调用时的会话级记忆(文件缓存由守护进程维护,此处只兜底文件未命中;含 $null 也缓存以避免反复全量枚举)
$script:IpFormatedCache = @{ Value = $null; Time = [datetime]::MinValue }
function Get-IpAddressFormated
{
    <# 
    .SYNOPSIS
    获取接入网络的物理网卡的地址(ipv4),比如WI-FI的IP地址,或者Ethernet的ip地址
    .DESCRIPTION
    函数主要由Get-IPAddressForPrompt调用,也可以手动调用刷新IP缓存信息
    .NOTES
    这是一个耗时函数,如果直接用于Prompt,大幅增加加载时间,因此引入了缓存机制


    #>
    [CmdletBinding(DefaultParameterSetName = 'Cache')]
    param (
        [ValidateSet('Up', 'Disconnected', 'All')]$Status = 'up',
        [parameter(ParameterSetName = 'Cache')]
        # 是否优先读取环境变量缓存中的IP地址
        [switch]$Cache,
        # 是否强制置空缓存(不会触发重新计算)
        [switch]$Clear,
        $dataJson = $DataJson,
        # 会话内记忆秒数:文件缓存未命中(守护进程未跑/新文件)时,避免每回车都全量枚举网卡(单次可达上秒)
        $TTLSeconds = 60
        # 是否重新计算并更新缓存
        # [parameter(ParameterSetName = 'Update')]
        # [switch]$UpdateIfWifiChange
    )
    # $ips = Get-IPAddressOfPhysicalAdapter
    #一般我们只对物理网卡比较感兴趣,并且我们只需名字和IP地址
    if ($Clear)
    {
        # $env:IpPrompt = $null
        Update-Json -Key IpPrompt -Value '' -DataJson $DataJson
        # 或者 remove-item env:/IpPrompt
        $env:ClearIpPrompt = 1
        return
    }
    if ($Cache)
    {

        # 尝试直接读取环境变量中的ip信息,并直接返回
    
        # return $env:IpPrompt
        # $s = Get-EnvVar -Key IpPrompt | Select-Object -ExpandProperty Value
        $s = Get-Json -JsonInput $DataJson -Key IpPrompt
        return  $s
    }
    
    # 会话级记忆:文件缓存未命中时,连续 prompt 只算一次(网络切换由守护进程写文件,文件命中不受 TTL 影响)
    $expired = ($script:IpFormatedCache.Time -eq [datetime]::MinValue) -or `
        (([datetime]::UtcNow - $script:IpFormatedCache.Time).TotalSeconds -ge $TTLSeconds)
    if (-not $expired -and $null -ne $script:IpFormatedCache.Value)
    {
        return $script:IpFormatedCache.Value
    }

    $adapters = Get-NetAdapter -Physical
    if ($Status -ne 'All')
    {
        $adapters = $adapters | Where-Object { $_.Status -eq $Status }
    }

    # return $adapters

    # 一次性取全量 IPv4,内存中按 InterfaceIndex 配对(原逐网卡调用 Get-NetIPAddress,网卡多时成倍变慢)
    $ipTable = @{}
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $ipTable.ContainsKey($_.InterfaceIndex)) { $ipTable[$_.InterfaceIndex] = @() }
        $ipTable[$_.InterfaceIndex] += $_.IPAddress
    }

    if ($VerbosePreference)
    {
        $adapters | Format-Table
    }

    $s = ''
    foreach ($adapter in ($adapters | Select-Object Name, Status, InterfaceIndex))
    {
        # if ($adapters)
        # $s += ("[$($ip.InterfaceAlias) : $($ip.IpAddress)]")
        $ips = $ipTable[$adapter.InterfaceIndex]
        $s += ("<$($adapter.Name[0]):$ips>")
    }
    # $ip = Get-IPAddressOfPhysicalAdapter | Select-Object -First 1 | Select-Object -ExpandProperty ipaddress
    # 将ip信息写入到环境变量保存起来,以便后续访问
    Write-Verbose $s
    # 写入环境变量
    # Set-EnvVar -EnvVar IpPrompt $s *> $null
    Update-Json -Key IpPrompt -Value $s -DataJson $dataJson
    $script:IpFormatedCache = @{ Value = $s; Time = [datetime]::UtcNow }

    return $s

}

function Get-IpAddressForPrompt
{
    <# 
    .SYNOPSIS
    由于重新计算ip地址是十分耗时的过程,建议用一个后台进程来更新
    而另一个进程直接读取后台进程算好的ip即可
        
    .DESCRIPTION
    测试方式:可以用路由器的wifi信号和手机wifi热点信号分别链接,然后分别测试刷新方法
    #>
    param (
        # $Interval = 3600 , #比如距离上次更新时间超过一小时后再更新它
        [switch]$KeepUpdate
    )
    # Update-PwshEnvIfNotYet -Mode core
    Update-PwshEnvIfNotYet -Mode Core
    # 确保需要的Json文件存在(屏蔽返回值,此前漏出的路径字符串会污染调用方输出)
    Confirm-DataJson | Out-Null

    $IpPrompt = Get-Json -Key IpPrompt -ErrorAction SilentlyContinue
    if (!$IpPrompt -and !$env:ClearIpPrompt)
    {
        # 文件缓存未命中:即时计算并直接返回(原计算完丢弃,首屏无 IP 还白白耗时;
        # 计算函数自带 60s 会话记忆 + 写文件,连续渲染不会反复枚举网卡)
        $IpPrompt = Get-IpAddressFormated -dataJson $DataJson
    }
    # 去除潜在可能出现的重复情况
    # $IpPrompt
    return $IpPrompt
}

function Get-MemoryUseRatio
{
    <# 
    .SYNOPSIS
    获取内存占用数值
    .DESCRIPTION
    如果您可以接受个别时候加载速度略慢(也不会太慢,100ms左右),且不希望后台额外运行计算内存占用的磁盘进程,那么可以使用这个函数
    
    如果不按住回车键,几乎感觉不到卡顿,总体资源占用会比 Get-MemoryUseRatioCache 要低,属于懒惰计算)

    被调用时,直接获取内存占用信息(在间隔超过预设时会调用耗时操作(计算内存占用),
    所以shell响应速度稳定性稍差,但是最慢的情况也能够在100ms左右返回结果
    #>
    [cmdletbinding()]
    param(
        $Interval = 5
    )
    # 获取系统总内存和可用内存
    # $TotalMemory = (Get-CimInstance -ClassName Win32_OperatingSystem).TotalVisibleMemorySize / 1MB
    # $TotalMemory  #为了提升响应速度,对于同一台计算机,总内存不变,因此可以配置环境变量或判断读取数值
    # $FreeMemory = (Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory / 1MB
    # if (((Get-Date) - $LastUpdate).TotalSeconds -ge $Interval)

    $s = {
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem;
        # 访问硬件信息,所以比较耗时(100ms左右)
        # $env:cachedTotalMemory = 
        $cachedTotalMemory = $OS.TotalVisibleMemorySize / 1MB;
        # $env:cachedFreeMemory =
        $cachedFreeMemory = $OS.FreePhysicalMemory / 1MB;
        
        Update-Json -Key cachedTotalMemory -Value $cachedTotalMemory -DataJson $DataJson
        Update-Json -Key cachedFreeMemory -Value $cachedFreeMemory -DataJson $DataJson
    }
    # 跟据指定时间间隔参数$Interval执行耗时逻辑
    Start-ScriptWhenIntervalEnough -Interval $Interval -ScriptBlock $s

    # 从Json文件获取已用内存和占用信息(速度很快)
    $cachedFreeMemory = Get-Json -Key cachedFreeMemory -ErrorAction SilentlyContinue
    $cachedTotalMemory = Get-Json -Key cachedTotalMemory -ErrorAction SilentlyContinue
    if ($null -eq $cachedFreeMemory)
    # {
    #     Write-Host 'the key of cachedFreeMemory not found' -ForegroundColor Red
    #     return 'pending'
    # }
    {
        # 创建对应的项目
        Write-Host 'creating cached..json items.'
        & $s
        # 递归调用(此次调用正常情况下不会失败)
        # return Get-MemoryUseRatio
    }
    $cachedFreeMemory = [float]$cachedFreeMemory
    $cachedTotalMemory = [float]$cachedTotalMemory
    # return
    if ($VerbosePreference)
    {
        Write-Host "$env:cachedTotalMemory MB", ($env:cachedFreeMemory).GetType()
        # write-host "$env:cachedFreeMemory MB"
    }
    # 计算已用内存和占用百分比
    # $UsedMemory = $TotalMemory - $FreeMemory
    $UsedMemory = $cachedTotalMemory - $cachedFreeMemory
    $FreeMemory = $cachedFreeMemory
    $res = [PSCustomObject]@{
        UsedMemory  = $UsedMemory
        TotalMemory = $cachedTotalMemory
        FreeMemory  = $FreeMemory
    }
    return $res
    
}

# function Get-MemoryUseInfoCached
# {
#     <# 
#     .SYNOPSIS
#     获取内存占用数值
#     如果您在意prompt返回的速度稳定性,且不在意后台定时进行少量的磁盘读写,那么可以使用该函数

#     用独立于当前shell的保存到磁盘上的近期数值,理论上响应速度更加稳定,但会在后台占用一定资源,每隔一定时间(预设时间),耗时任务被后台进程独立执行和维护,进程会进行磁盘读写,读写的量很少,时间主要在于计算内存占用的调用上
#     .DESCRIPTION
#     由于计算内存占用的进程被独立出去,要设置计算频率(时间间隔),详见Start-PeriodlyDaemon
#     关于这个后台进程,可以手动结束掉,模块中配备了Stop-LastUpdateDaemon函数,都可以独立调用
#     然而,多个地方或多次调用Start-PeriodlyDaemon会导致进程号混乱,此时Stop-lastUpdateDaemon可能无法全部相关进程,您可以用任务管理器,搜索具有相关命令行
    
#     #>
#     param (
#         $SourceFile = $LastUpdate
#     )
#     $res = Get-Content $SourceFile
#     $res = $res -split "`n"
#     $FreeMemory = $res[0]
#     # $TotalMemory = $res[1]
#     $UsedMemory = $TotalMemory - $FreeMemory
#     return $UsedMemory, $TotalMemory, $FreeMemory
# }
function Get-MemoryUseSummary
{
    <# 
    .SYNOPSIS
    .返回内存占用百分比和已用内存和总内存之比的字符串,保留2位小数,使其格式符合人类阅读习惯
    结果是一个数组,包含2个字符串

    .DESCRIPTION
    下面获取内存占用百分比的两个数值有两种办法
    既可以Get-MemoryUseInfoCached
    也可以用Get-MemoryUseRatio 
    总的体验下来,实际体验几乎没有差别,我这里两种方式都提供了
    .NOTES
    通常,间隔($Interval)设置的不大时,可以用Get-MemoryUseRatio,比较节约资源(默认)
    反之,如果您把间隔设置的比较小,比如2秒以内,那么使用Cached版体验更好(比较依赖于磁盘,磁盘占用不大,那么可以用很低的资源实现很高效率的prompt相应速度,以及更加准精确的内存占用率数值)
    然而过于频繁计算内存资源使用情况会没有其他重要的副作用暂不明确(也不用太担心,这个进程占用资源很小)
    .EXAMPLE

    #>
    # $cachedFreeMemory = Get-JsonValue -Key cachedFreeMemory -DataJson $DataJson
    
    # if (!$env:cachedFreeMemory)
    # if(!$cachedFreeMemory)
    # {
    #     Write-Host 'init Memory Info' -ForegroundColor Magenta
        
    #     Set-LastUpdateTime

    #     Start-MemoryInfoInit
    # }


    $MemoryUseRatio = Get-MemoryUseRatio
    
    $UsedMemory, $TotalMemory, $FreeMemory = $MemoryUseRatio.UsedMemory, $MemoryUseRatio.TotalMemory, $MemoryUseRatio.FreeMemory
    # Get-MemoryUseInfoCached #
    $MemoryUsePercentage = ($UsedMemory / $TotalMemory) * 100
    # 保留2为小数,输出内存占用百分比
    # $MemoryUsePercentage = $MemoryUsePercentage.ToString('N2') + '%'
    # $MemoryUseRatio = "$($UsedMemory.ToString('N2'))/$($TotalMemory.ToString('N2'))"
    # Write-Output " MEM:$MemoryUsePercentage% ($MemoryUseRatio) GB"

    $MemoryUsePercentage = [math]::Round($MemoryUsePercentage, 2)
    $MemoryUseRatio = "$([math]::Round($UsedMemory,2))/$([math]::Round($TotalMemory, 2))"

    $res = [PSCustomObject]@{
        MemoryUsePercentage = $MemoryUsePercentage
        MemoryUseRatio      = $MemoryUseRatio
    }
    # return $MemoryUsePercentage, $MemoryUseRatio
    return $res
}
# Get-MemoryUseSummary

function Get-UserHostName
{
    <# 
    .SYNOPSIS
    返回符合ssh连接规范的用户名@计算机名
    #>
    # 方案1:
    # 分支判断方案:
    # 获取用户名
    # $username = if ($IsWindows) { $env:USERNAME } else { $env:USER }
    # # 获取计算机名
    # $computername = if ($IsWindows) { $env:COMPUTERNAME } else { $env:HOSTNAME }
    # $res = "$username@$computername"

    # 方案2:
    $username = [System.Environment]::UserName
    $computername = [System.Environment]::MachineName
    $res = "$username@$computername"

    return  $res
}
function Get-BIOSInfo
{

    $res = systeminfo | Select-String bios
    return $res

}
function Get-ScreenResolution
{
    <# 
    .SYNOPSIS
    获取屏幕分辨率 ,返回水平和数值的分辨率数值构成的数组
    .EXAMPLE
    > get-ScreenResolution
        2560
        1440
    #>
    $info = Get-WmiObject -Class Win32_VideoController;
    return $info.CurrentHorizontalResolution , $info.CurrentVerticalResolution
}

function Get-SystemInfoBasic
{
    <# 
    .SYNOPSIS
    获取系统信息的方式有许多,这里只显示最常用的信息
    其他方法包括执行:
    1.get-computerinfo #详情查看帮助文档,对于windows版本号可能识别不准,有的版本把win11识别为win10
    2.systeminfo #对于cmd也适用

   #>
    Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture, BuildNumber
}

function Get-ComputerCoreHardwareInfo
{
    # 输出信息，使用不同颜色和格式化显示
    Write-Host '---------------------------' -ForegroundColor Cyan
    Write-Host '系统核心配置信息:' -ForegroundColor Yellow
    Write-Host '---------------------------' -ForegroundColor Cyan
    
    # 获取硬件信息
    # 方案1:串行等待执行
    function Get-HardwareInfoSerial
    {
        $s = {
            $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
            $memory = Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object Manufacturer, Capacity, Speed
            $disk = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object Model, Size, MediaType
            $os = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture, LastBootUpTime
            $motherboard = Get-CimInstance -ClassName Win32_BaseBoard | Select-Object Manufacturer, Product, SerialNumber
            $gpu = Get-CimInstance -ClassName Win32_VideoController | Select-Object Name, AdapterRAM, DriverVersion 
        }
        $tasks = $s.ToString() -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $index = 0
        foreach ($task in $tasks)
        {
            $completed = $index / ($tasks.Count)
            $completed = [math]::round($completed * 100, 2) 
            Write-Progress -Activity "Geting hardware info" -Status "Completed: $completed %" -PercentComplete ($completed)
            Invoke-Expression $task
            # Start-Sleep 1
            # Write-Host $index 
            $index++
        }
        return $cpu, $memory, $disk, $os, $motherboard, $gpu
    }
    $cpu, $memory, $disk, $os, $motherboard, $gpu = Get-HardwareInfoSerial
    #方案2:后台并行执行
    # # 启动后台任务
    function Get-HardwareInfobyJobs
    { 
        $cpuJob = Start-Job -ScriptBlock { Get-CimInstance -ClassName Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed }
        $memoryJob = Start-Job -ScriptBlock { Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object Manufacturer, Capacity, Speed }
        $diskJob = Start-Job -ScriptBlock { Get-CimInstance -ClassName Win32_DiskDrive | Select-Object Model, Size, MediaType }
        $osJob = Start-Job -ScriptBlock { Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture, LastBootUpTime }
        $motherboardJob = Start-Job -ScriptBlock { Get-CimInstance -ClassName Win32_BaseBoard | Select-Object Manufacturer, Product, SerialNumber }
        $gpuJob = Start-Job -ScriptBlock { Get-CimInstance -ClassName Win32_VideoController | Select-Object Name, AdapterRAM, DriverVersion }

        # 等待所有任务完成
        Wait-Job -Job $cpuJob, $memoryJob, $diskJob, $osJob, $motherboardJob, $gpuJob

        # 获取结果
        $cpu = Receive-Job -Job $cpuJob
        $memory = Receive-Job -Job $memoryJob
        $disk = Receive-Job -Job $diskJob
        $os = Receive-Job -Job $osJob
        $motherboard = Receive-Job -Job $motherboardJob
        $gpu = Receive-Job -Job $gpuJob

        # 清理任务
        Remove-Job -Job $cpuJob, $memoryJob, $diskJob, $osJob, $motherboardJob, $gpuJob

        # # 输出结果
        # $cpu
        # $memory
        # $disk
        # $os
        # $motherboard
        # $gpu
    }

    # 计算总内存容量 (以GB为单位)
    $totalMemoryGB = ($memory | Measure-Object -Property Capacity -Sum).Sum / 1GB
    
    # CPU 信息
    Write-Host 'CPU 信息' -ForegroundColor Green
    $cpu | ForEach-Object {
        Write-Host ('名称: {0}' -f $_.Name)
        Write-Host ('核心数量: {0}' -f $_.NumberOfCores)
        Write-Host ('逻辑处理器数量: {0}' -f $_.NumberOfLogicalProcessors)
        Write-Host ('最大主频: {0} MHz' -f $_.MaxClockSpeed)
    }
    Write-Host ''

    # 内存信息
    Write-Host '内存信息' -ForegroundColor Green
    Write-Host ('内存总容量: {0} GB' -f [math]::round($totalMemoryGB, 2)) -ForegroundColor Cyan
    $memory | ForEach-Object -Begin { $index = 1 } {
        Write-Host ('---------------------------') -ForegroundColor Cyan
        Write-Host ('内存条 {0}' -f $index) -ForegroundColor Yellow
        Write-Host ('制造商: {0}' -f $_.Manufacturer)
        Write-Host ('容量: {0} GB' -f ([math]::round($_.Capacity / 1GB, 2)))
        Write-Host ('速度: {0} MHz' -f $_.Speed)
        Write-Host ('---------------------------') -ForegroundColor Cyan
        $index++
    }
    Write-Host ''

    # 磁盘信息
    Write-Host '磁盘信息' -ForegroundColor Green
    $disk | ForEach-Object {
        Write-Host ('型号: {0}' -f $_.Model)
        Write-Host ('大小: {0} GB' -f ([math]::round($_.Size / 1GB, 2)))
        Write-Host ('类型: {0}' -f $_.MediaType)
    }
    Write-Host ''

    # 操作系统信息
    Write-Host '操作系统信息' -ForegroundColor Green
    $os | ForEach-Object {
        Write-Host ('系统: {0}' -f $_.Caption)
        Write-Host ('版本: {0}' -f $_.Version)
        Write-Host ('架构: {0}' -f $_.OSArchitecture)
        Write-Host ('上次启动时间: {0}' -f $_.LastBootUpTime)
    }
    Write-Host ''

    # 主板信息
    Write-Host '主板信息' -ForegroundColor Green
    $motherboard | ForEach-Object {
        Write-Host ('制造商: {0}' -f $_.Manufacturer)
        Write-Host ('型号: {0}' -f $_.Product)
        Write-Host ('序列号: {0}' -f $_.SerialNumber)
    }
    Write-Host ''

    # 显卡信息
    Write-Host '显卡信息' -ForegroundColor Green
    $gpu | ForEach-Object -Begin { $index = 1 } {
        Write-Host '---------------------------' -ForegroundColor Cyan
        Write-Host ('显卡 {0}' -f $index) -ForegroundColor Yellow
        Write-Host ('名称: {0}' -f $_.Name)
        # Write-Host ('显存: {0} GB' -f ([math]::round($_.AdapterRAM / 1GB, 2))) #不准确
        Write-Host ('驱动版本: {0}' -f $_.DriverVersion)
        Write-Host ('---------------------------') -ForegroundColor Cyan
        $index++
    }
    Write-Warning ('显存: 建议使用专门工具或任务管理器中的性能面板查看:dxgi-info.exe,dxdiag.exe' +
        "`n下面显示的信息来自于dxgi-info.exe;每个显卡都用====Adapter===== 分割引出信息(省电模式可能会禁用显卡导致部分信息不可用)") 
    dxgi-info.exe
    
}

function Get-ModuleByCxxu
{
    <# 
    .SYNOPSIS
    获取CxxuPSModulePath下的模块信息
    .DESCRIPTION
    如果需要进一步调整信息显示，可以利用管道符进一步处理,比如排序等
    #>
    param(
        [switch]$SkipUnavailable
    )
    $res = Get-Module -ListAvailable | Where-Object { $_.ModuleBase -like "$env:CxxuPSModulePath*" }
    # $res = $res | Where-Object { $_.ExportedCommands }
    if ($SkipUnavailable)
    {

        $res = $res | Where-Object { $_.ExportedCommands.Count }
    }
    return $res 
    
}

# function Get-MotherBoardInfo
# {
#     return Get-CimInstance -ClassName Win32_baseboard
# }
function Get-MotherBoardInfo
{

    if ($IsWindows)
    {
        return Get-CimInstance -ClassName Win32_BaseBoard
    }
    elseif ($IsMacOS)
    {
        $model = (sysctl -n hw.model)
        $serial = (ioreg -l | Select-String IOPlatformSerialNumber).ToString().Split('"')[-2]

        return [PSCustomObject]@{
            Manufacturer = "Apple"
            Product      = $model
            SerialNumber = $serial
            Version      = "N/A"
        }
    }
    # elseif ($IsMacOS) {
    #     $info = system_profiler SPHardwareDataType

    #     return [PSCustomObject]@{
    #         Manufacturer = "Apple"
    #         Product      = ($info | Select-String "Model Identifier").ToString().Split(":")[1].Trim()
    #         SerialNumber = ($info | Select-String "Serial Number").ToString().Split(":")[1].Trim()
    #         Version      = "N/A"
    #     }
    # }

    elseif ($IsLinux)
    {
        return Get-Content /sys/class/dmi/id/board_* | Out-String
    }
}
function Get-MemoryChipInfo
{
    <# 
    .synopsis
    返回内存芯片信息
    .EXAMPLE
    PS>Get-MemoryChipInfo

    DeviceLocator : Controller1-ChannelA-DIMM0
    Manufacturer  : Crucial Technology
    Capacity      : 17179869184
    Speed         : 4800
    PartNumber    : CT16G56C46S5.M8G1
    #>
    
    $res = Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object -Property DeviceLocator, Manufacturer, Capacity, Speed, PartNumber
    return $res
}


function Get-MaxMemoryCapacity
{
    <# 
    .SYNOPSIS
    Get the max memory capacity of the system (Unit:GB)
    .EXAMPLE
    PS>get-MaxMemoryCapacity
    The first line is KB, the second line is GB

    Value    Unit
    -----    ----
    67108864 KB
    64.00    GB
    #>
    $info = wmic memphysical get maxcapacity
    $kBs = [regex]::Match($info, '\d+') | Select-Object value
    $kBs = $kBs.Value
    $GBs = $kBs / [math]::pow(2, 20)
    # return $kBs, $GBs
    Write-Host 'The first line is KB, the second line is GB'
    # 创建一个对象数组，包含容量值和单位  
    $res = @(  
        [PSCustomObject]@{  
            Value = $kBs  
            Unit  = 'KB'  
        }  ,
        [PSCustomObject]@{  
            Value = $GBs 
            Unit  = 'GB'  
        }  
    )  
    return $res
}


function Get-DiskDriversInfo
{
    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name.Length -eq 1 }
    Write-Output '😊❤️only show the disk with the name that no more than 2 characters'
}
function Get-ProcessPath
{
    param(
        $pattern
    )
    $pattern = "*$pattern*"
    Get-Process $pattern | Select-Object Name, path
}

# --- 从 Pwsh.psm1 迁入:进程/内存查看(职责:系统信息) ---

function Get-MacOSOperatingSystemInfo
{

    # 1. 获取操作系统基础信息 (对应 Caption, Version, BuildNumber)
    $productName = (sw_vers -productName).Trim()
    $productVersion = (sw_vers -productVersion).Trim()
    $buildVersion = (sw_vers -buildVersion).Trim()
    
    # 2. 获取架构和内核信息 (对应 OSArchitecture)
    $arch = (uname -m).Trim()
    $kernelVersion = (uname -r).Trim()
    $osArchitecture = if ($arch -eq 'arm64') { 'ARM 64-bit (Apple Silicon)' } else { '64-bit (Intel)' }
    
    # 3. 获取内存信息 (WMI 中 TotalVisibleMemorySize 和 FreePhysicalMemory 的单位是 KB)
    # 获取总内存 (Bytes 转 KB)
    $totalMemBytes = [int64](sysctl -n hw.memsize)
    $totalVisibleMemorySize = [math]::Round($totalMemBytes / 1KB)
    
    # 获取可用内存 (通过 vm_stat 和 pagesize 计算)
    $pageSize = [int64](sysctl -n hw.pagesize)
    $vmStat = vm_stat
    $pagesFreeMatch = $vmStat | Select-String 'Pages free:\s+(\d+)'
    $pagesFree = if ($pagesFreeMatch) { [int64]$pagesFreeMatch.Matches.Groups[1].Value } else { 0 }
    $freePhysicalMemory = [math]::Round(($pagesFree * $pageSize) / 1KB)
    
    # 4. 获取系统启动时间 (对应 LastBootUpTime)
    $bootTimeRaw = sysctl -n kern.boottime
    # 提取 Epoch 秒数并转换为 DateTime 对象
    if ($bootTimeRaw -match 'sec = (\d+)')
    {
        $bootTimeSec = [int]$matches[1]
        $lastBootUpTime = [timezone]::CurrentTimeZone.ToLocalTime(([datetime]'1/1/1970').AddSeconds($bootTimeSec))
    }
    else
    {
        $lastBootUpTime = $null
    }
    
    # 5. 估算系统安装时间 (对应 InstallDate)
    # macOS 没有统一的系统安装日期属性，通常使用核心系统目录的创建时间来替代
    $installDate = (Get-Item /System/Library/CoreServices/SystemVersion.plist).CreationTime
    
    # 6. 获取主机名 (对应 CSName)
    $csName = (hostname).Trim()
    
    # ==========================================
    # 组装模拟的 WMI 对象
    # ==========================================
    $osInfo = [PSCustomObject]@{
        Caption                = "$productName $productVersion"
        Version                = $productVersion
        BuildNumber            = $buildVersion
        OSArchitecture         = $osArchitecture
        Manufacturer           = 'Apple Inc.'
        TotalVisibleMemorySize = $totalVisibleMemorySize # 单位: KB
        FreePhysicalMemory     = $freePhysicalMemory     # 单位: KB
        LastBootUpTime         = $lastBootUpTime
        InstallDate            = $installDate
        SystemDirectory        = '/System'
        CSName                 = $csName
        OSType                 = 'Darwin'
        KernelVersion          = $kernelVersion
    }
    return $osInfo
    
}
class ProcessDetail
{
    [int]      $Id
    [string]   $Name
    [double]   $CPUSeconds
    [double]   $WorkingSetMB
    [datetime] $StartTime
    [timespan] $RunTime
    [string]   $User
    [int]      $ParentPID
    [string]   $Path
    [string]   $CommandLine
}

function Get-ProcessDetail
{
    <# 
    .SYNOPSIS
    默认的 ps (即 Get-Process) 只显示基本列。
    这里补充其他一些常用的列，例如启动命令行.
    要获取更详细的信息（命令行、可执行路径、启动时间、父进程、用户等），推荐用 Get-CimInstance Win32_Process。
    .NOTES
    ⚠️ 注意：CommandLine、User 等字段需要 管理员权限 才能获取到其他用户的进程信息，你已经是 Administrator 所以没问题。
    .EXAMPLE
    # 使用：
    Get-ProcessDetail ssh | Format-List
    Get-ProcessDetail ssh | Format-Table -AutoSize
    #>
    [OutputType([ProcessDetail])]          # ← 关键：告诉补全器输出类型
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $cim = Get-CimInstance Win32_Process -Filter "Name='$Name.exe'"

    Get-Process -Name $Name | ForEach-Object {
        $p = $_
        $c = $cim | Where-Object ProcessId -EQ $p.Id
        $o = Invoke-CimMethod -InputObject $c -MethodName GetOwner

        [ProcessDetail]@{
            Id           = $p.Id
            Name         = $p.Name
            CPUSeconds   = [math]::Round($p.CPU, 2)
            WorkingSetMB = [math]::Round($p.WorkingSet64 / 1MB, 2)
            StartTime    = $p.StartTime
            RunTime      = (Get-Date) - $p.StartTime
            User         = "$($o.Domain)\$($o.User)"
            ParentPID    = $c.ParentProcessId
            Path         = $p.Path
            CommandLine  = $c.CommandLine
        }
    }
}
function Get-ProcessMemoryView
{
    <#
    .SYNOPSIS
    查看进程内存占用情况，支持分组、排序、私有工作集、自定义单位等功能。

    .DESCRIPTION
    获取当前系统所有进程的内存使用情况，支持以下特性：
    - 按进程名分组（Group模式），方便排查哪个软件占用大量内存
    - 自定义排序指标（WS/PM/PrivWS）
    - 自定义显示单位（KB/MB/GB）
    - 可选显示私有工作集（与任务管理器"内存"列对应）
    - 累加百分比列（sum%），快速定位内存大户
    - 百分比列自动跟随排序指标切换（%WS / %PM / %PrivWS）

    关于作用域：
    在管道（Pipeline）内部修改外部变量时，需要显式指定作用域（$script:），
    否则脚本块内部会将其视为局部变量，导致累加失败。

    .PARAMETER First
    获取前几名进程，设为 0 则获取所有进程。默认 10。

    .PARAMETER Group
    启用分组模式，按进程名合并，使用 Measure-Object -Sum 计算分组总和。

    .PARAMETER WorkingSetPrivate
    启用后增加私有工作集列（PrivWS），通过 CIM 查询获取(仅windows平台可用)，
    与任务管理器"详细信息"中的"内存(私有工作集)"一致。

    .PARAMETER SortBy
    指定排序依据的指标。可选值：WS、PM、PrivWS。
    当指定 PrivWS 时会自动启用 -WorkingSetPrivate。
    百分比列会自动切换为对应指标的占比（%WS / %PM / %PrivWS）。
    默认 WS。

    .PARAMETER Unit
    显示内存的单位。可选值：KB、MB、GB。默认 GB。

    .EXAMPLE
    Get-ProcessMemoryView | ft
    默认参数：前10名，按WS排序，显示%WS，单位GB。

    .EXAMPLE
    Get-ProcessMemoryView -Unit MB -SortBy PM | ft
    以MB为单位，按PM排序，显示%PM。

    .EXAMPLE
    Get-ProcessMemoryView -SortBy PrivWS -Unit MB | ft
    按私有工作集排序（自动启用该列），显示%PrivWS，以MB显示。

    .EXAMPLE
    Get-ProcessMemoryView -Group -First 10 | ft -Wrap
    分组模式，换行显示PIDs列。

    .EXAMPLE
    Get-ProcessMemoryView -Group | Select-Object * -ExcludeProperty PIDs | ft
    隐藏PIDs列。

    .EXAMPLE
    Get-ProcessMemoryView | Measure-Object '%WS' -Sum
    计算最占内存的前若干名进程的内存占用率之和。

    .EXAMPLE
    Get-ProcessMemoryView -Group | Where-Object { $_.Name -like 'msedge' }
    筛选特定进程名的分组数据。

    .NOTES
    - 私有工作集通过 Win32_PerfFormattedData_PerfProc_Process 获取，首次查询可能稍慢
    - 百分比列基于总可见物理内存计算对应指标的占比
    - 如果没有 $script: 前缀，在某些 PowerShell 版本或复杂上下文中，
      $sum 可能不会在每一行之间成功传递累加值
    - 工作集（WorkingSet）= 专用工作集（Private WS）+ 共享工作集（Shared WS）。

    .NOTES
      多个进程可能共享同一段物理内存页（如共享 DLL），因此对所有进程的 WS 简单求和
      会重复计算共享部分，导致累加百分比（%Sum）通常高于系统实际物理内存占用率。(总和可能超过100%)
      类似的,针对私有工作集(Private WS)的求和也是不准确的(偏少),因为共享工作集没有计入占用.
      而这部分和资源管理器中的内存字段值是对应的(采用的是私有工作集).
      然而,资源管理器的内存一列的设计很具有迷惑性,总结性的全部进程内存占用百分比之和计算依据既不是私有工作集,
      也不是总工作集,更不是共享工作集,而是直接根据物理内存被占用了多少得出的.)
        内存占用的视图(无论是数值还是百分比,都是基于私有工作集的),
        计算百分比仅仅是进程的私有工作集相对物理内存的占用比,而不是包含共享工作集.
      同理，PM（PagedMemorySize）包含已换出到页面文件的部分，与物理内存占用并非
      一一对应，其累加百分比同样可能偏高或与实际物理内存使用率不一致。
      若需精确的系统级内存占用率，请参考函数开头打印的物理内存使用信息。
    
    1. Idle 进程 (PID 0)
        不是真正的进程，它是内核用来统计 CPU 空闲时间的占位符
        WS = 0, PM = 0，实际不占用物理内存
        这里显示的 PrivWS = xxx 是虚假且无意义的数据(也不是可用(空闲)内存)，很可能是统计工具的误报或者内核地址空间的映射
        资源监视器和任务管理器都不显示它的内存占用
    2. Memory Compression
        这是 Windows 的内存压缩机制（System 进程的子工作）
        它显示的数值代表的是被压缩后存放的内存内容
        这些内存原本属于其他进程，只是被压缩存储了
        如果算上它，就会造成重复计算（double counting）
    #>
    [CmdletBinding()]
    param(
        [int]$First = 10,

        [switch]$Group,

        [switch]$WorkingSetPrivate,

        [ValidateSet("WS", "PM", "PrivWS")]
        [string]$SortBy = "WS",

        [ValidateSet("KB", "MB", "GB")]
        [string]$Unit = "GB"
    )
    # 最保守的跳过列表（推荐）
    $SKIP_PROCESSES = @( "Idle", "Memory Compression" )
    # 如果只关注应用层
    # $SKIP_PROCESSES = { "Idle", "Memory Compression", "System" }

    # --- 自动修正：按 PrivWS 排序时自动启用开关 ---
    if ($SortBy -eq "PrivWS" -and -not $WorkingSetPrivate)
    {
        $WorkingSetPrivate = [switch]::Present
    }

    # --- 单位换算因子 ---
    $divisor = switch ($Unit)
    {
        "KB" { 1KB }
        "MB" { 1MB }
        "GB" { 1GB }
    }

    # 列名，如 WS(MB)、PM(GB)、PrivWS(GB)
    $wsCol = "WS($Unit)"
    $pmCol = "PM($Unit)"
    $pwsCol = "PrivWS($Unit)"

    # --- 排序列名映射 ---
    $sortColumn = switch ($SortBy)
    {
        "WS" { $wsCol }
        "PM" { $pmCol }
        "PrivWS" { $pwsCol }
    }

    # --- 百分比列名跟随排序指标 ---
    $pctCol = "%$SortBy"          # %WS / %PM / %PrivWS
    $pctSumCol = "%Sum($SortBy)"  # %Sum(WS) / %Sum(PM) / %Sum(PrivWS)
    $capSumCol = "CapSum($SortBy)" # Capacity Sum

    # --- 初始化 ---
    $script:PercentSum = 0
    $script:CapacitySum = 0
    if($IsWindows)
    {

        $osInfo = Get-CimInstance Win32_OperatingSystem
        $totalRAMBytes = $osInfo.TotalVisibleMemorySize * 1KB  # 转为字节
        $usedRAMBytes = ($osInfo.TotalVisibleMemorySize - $osInfo.FreePhysicalMemory) * 1KB
    }
    elseif ($IsMacOS)
    {
        Write-Verbose "Macos 上由于机制不同,部分指标(虚拟内存相关)显示为0;
        - PeakVirtualMemorySize64 峰值虚拟内存大小64
        - PeakWorkingSet64
        描述提交大小的字段: PagedMemorySize(64) 或同义字段 PrivateMemorySize(64)
        - PrivateMemorySize64 私有内存大小64
        "
        
        
        $totalRAMBytes = [long]$(sysctl -n hw.memsize)

        # 获取空闲内存页数
        $vmStat = vm_stat
        $pageSize = [long](($vmStat | Select-String "page size of") -replace '.*page size of (\d+) bytes.*', '$1')
        if ($pageSize -eq 0) { $pageSize = 4096 }

        $freePages = [long][regex]::Match(($vmStat | Select-String "^Pages free:"), '\d+').Value
        $inactivePages = [long][regex]::Match(($vmStat | Select-String "^Pages inactive:"), '\d+').Value

        $freeRAMBytes = ($freePages + $inactivePages) * $pageSize
        $usedRAMBytes = $totalRAMBytes - $freeRAMBytes

        Write-Host "总内存:   $totalRAMBytes 字节 ($([math]::Round($totalRAMBytes/1GB,2)) GB)"
        Write-Host "已用内存: $usedRAMBytes 字节 ($([math]::Round($usedRAMBytes/1GB,2)) GB)"
    }
    elseif($IsLinux)
    {
        $totalRAMBytes = $(awk '/^MemTotal:/ {print $2 * 1024}' /proc/meminfo)
        # 直接获取 used 字节数
        $usedRAMBytes = [long](free -b | awk '/^Mem:/ {print $3}')

        # Write-Host "已用内存: $usedRAMBytes 字节"
        # Write-Host "已用内存: $([math]::Round($usedRAMBytes/1GB,2)) GB"
    }


    # --- 打印物理内存使用概况 ---
    $usedRAMPercent = [math]::Round(($usedRAMBytes / $totalRAMBytes) * 100, 2)
    $totalDisp = [math]::Round($totalRAMBytes / $divisor, 2)
    $usedDisp = [math]::Round($usedRAMBytes / $divisor, 2)
    $freeDisp = [math]::Round(($totalRAMBytes - $usedRAMBytes) / $divisor, 2)

    Write-Host ""
    Write-Host "Physical Memory" -ForegroundColor Cyan
    Write-Host "  Total : $totalDisp $Unit" -ForegroundColor White
    Write-Host "  Used  : $usedDisp $Unit  ($usedRAMPercent %)" -ForegroundColor $(if ($usedRAMPercent -gt 85) { "Red" } elseif ($usedRAMPercent -gt 70) { "Yellow" } else { "Green" })
    Write-Host "  Free  : $freeDisp $Unit" -ForegroundColor White

    # --- 打印当前参数 ---
    Write-Host "Parameters" -ForegroundColor Cyan
    Write-Host "  First             : $(if ($First) { $First } else { 'All' })" -ForegroundColor Yellow
    Write-Host "  Group             : $Group" -ForegroundColor Yellow
    Write-Host "  WorkingSetPrivate : $WorkingSetPrivate" -ForegroundColor Yellow
    Write-Host "  SortBy            : $SortBy  (percent col: $pctCol)" -ForegroundColor Yellow
    Write-Host "  Unit              : $Unit" -ForegroundColor Yellow

    # --- 预查询私有工作集 PID → 字节数 ---
    Write-Verbose "Querying More info by Get-CimInstance ,wait for a moment..."
    $privateWSMap = @{}
    if ($WorkingSetPrivate)
    {
        Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
        ForEach-Object { $privateWSMap[[int]$_.IDProcess] = [long]$_.WorkingSetPrivate }
    }

    # ============================================================
    #  辅助：根据 SortBy 生成百分比计算表达式（字节级原始值 / totalRAMBytes）
    # ============================================================
    $processes = Get-Process | Where-Object { $_.Name -notin $SKIP_PROCESSES } 
    if ($Group)
    {
        # === 分组模式 ===

        # 1) 构建基础数据（始终包含 WS / PM 列）
        $columns = @(
            @{N = "Name"; E = { $_.Name } },
            @{N = "Count"; E = { $_.Count } },
            @{N = "PIDs"; E = { ($_.Group.Id -join ",") } },
            @{N = $wsCol; E = { ($_.Group | Measure-Object WorkingSet64 -Sum).Sum / $divisor } }
        )
        # 只有属性存在时才添加最后一列
        if (! $IsMacOS)
        {
            $columns += @{N = $pmCol; E = { ($_.Group | Measure-Object PagedMemorySize64 -Sum).Sum / $divisor } }
        }
        $res = $processes |
        Group-Object -Property Name |
        Select-Object $columns

        # 2) 可选：追加私有工作集列
        if ($WorkingSetPrivate)
        {
            $res = $res | Select-Object *,
            @{N = $pwsCol; E = {
                    $pids = $_.PIDs -split ","
                    $total = ($pids | ForEach-Object { $privateWSMap[[int]$_] } | Measure-Object -Sum).Sum
                    [math]::Round($total / $divisor, 4)
                }
            }
        }

        # 3) 追加百分比列（基于当前 SortBy 指标）
        $pctExpr = switch ($SortBy)
        {
            "WS"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$wsCol" * $divisor / $totalRAMBytes) * 100, 2)
                    }
                }
            }
            "PM"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$pmCol" * $divisor / $totalRAMBytes) * 100, 2)
                    }
                }
            }
            "PrivWS"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$pwsCol" * $divisor / $totalRAMBytes) * 100, 2)
                    }
                }
            }
        }
        $res = $res | Select-Object *, $pctExpr

        # 4) 排序 → 计算累加百分比与容量
        $finalProps = @("Name", "Count", $wsCol, $pmCol)
        if ($WorkingSetPrivate) { $finalProps += $pwsCol }
        $finalProps += $pctCol
        $finalProps += @{N = $pctSumCol; E = {
                $script:PercentSum += $_."$pctCol"
                [math]::Round($script:PercentSum, 2)
            }
        }
        $finalProps += @{N = $capSumCol; E = {
                $script:CapacitySum += $_."$sortColumn"
                [math]::Round($script:CapacitySum, 2)
            }
        }
        $finalProps += "PIDs"

        $res = $res | Sort-Object $sortColumn -Descending | Select-Object $finalProps
    }
    else
    {
        # === 非分组模式 ===

        # 1) 构建基础数据
        $baseProps = @(
            'ID', 'Name',
            @{N = $wsCol; E = { $_.WorkingSet64 / $divisor } },
            @{N = $pmCol; E = { $_.PagedMemorySize64 / $divisor } }
        )
        if ($WorkingSetPrivate)
        {
            $baseProps += @{N = $pwsCol; E = {
                    [math]::Round(($privateWSMap[[int]$_.ID]) / $divisor, 4)
                }
            }
        }

        $res = $processes | Select-Object $baseProps

        # 2) 追加百分比列
        $pctExpr = switch ($SortBy)
        {
            "WS"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$wsCol" * $divisor / $totalRAMBytes) * 100, 2)
                    }
                }
            }
            "PM"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$pmCol" * $divisor / $totalRAMBytes) * 100, 2)
                    }
                }
            }
            "PrivWS"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$pwsCol" * $divisor / $totalRAMBytes) * 100, 2)
                    }
                }
            }
        }
        $res = $res | Select-Object *, $pctExpr

        # 3) 排序 → 计算累加百分比与容量
        $finalProps = @('ID', 'Name', $wsCol)
        if(! $IsMacOS)
        {
            $finalProps += $pmCol
        }
        if ($WorkingSetPrivate) { $finalProps += $pwsCol }
        $finalProps += $pctCol
        $finalProps += @{N = $pctSumCol; E = {
                $script:PercentSum += $_."$pctCol"
                [math]::Round($script:PercentSum, 2)
            }
        }
        $finalProps += @{N = $capSumCol; E = {
                $script:CapacitySum += $_."$sortColumn"
                [math]::Round($script:CapacitySum, 2)
            }
        }

        $res = $res | Sort-Object $sortColumn -Descending | Select-Object $finalProps
    }

    # --- 截取前 N 条 ---
    if ($First) { $res = $res | Select-Object -First $First }

    return $res
}
function Get-CommitStatus
{
    <#
    .SYNOPSIS
        计算并显示当前系统的内存提交量（Commit Charge）。
    .DESCRIPTION
    TotalVirtualMemorySize: 这是 WMI 中对 Commit Limit 的定义。它不是指硬盘大小，而是 物理内存 + 分页文件 的总和。
    FreeVirtualMemory: 系统当前还能“许诺”出去的剩余额度。
    减法逻辑: 任务管理器显示的“已提交”本质上就是：系统总额度减去还没被许诺出去的额度。
    #>
    [CmdletBinding()]
    param()

    process
    {
        # 获取操作系统内存数据 (单位为 KB)
        $OS = Get-CimInstance Win32_OperatingSystem
        
        # 1. 核心计算
        $CommitLimitKB = $OS.TotalVirtualMemorySize
        $FreeCommitKB = $OS.FreeVirtualMemory
        $CommittedKB = $CommitLimitKB - $FreeCommitKB
        
        # 2. 转换单位为 GB
        $CommittedGB = [Math]::Round($CommittedKB / 1MB, 2)
        $LimitGB = [Math]::Round($CommitLimitKB / 1MB, 2)
        $Percent = [Math]::Round(($CommittedKB / $CommitLimitKB) * 100, 1)

        # 3. 确定显示颜色 (压力预警)
        $StatusColor = "Green"
        if ($Percent -gt 70) { $StatusColor = "Yellow" }
        if ($Percent -gt 90) { $StatusColor = "Red" }

        # 4. 格式化输出
        Write-Host "`n--- 内存提交状态 (Commit Charge) ---" -ForegroundColor Cyan
        Write-Host "已提交 (Committed): " -NoNewline
        Write-Host "$CommittedGB GB" -ForegroundColor $StatusColor
        
        Write-Host "提交限制 (Limit):     $LimitGB GB"
        
        Write-Host "使用百分比:           " -NoNewline
        Write-Host "$Percent %" -ForegroundColor $StatusColor
        

    }
}
function Show-CommitMemoryBar
{
    <#
    .SYNOPSIS
        动态监控系统内存提交量（Commit Charge）并显示进度条。
    
    .DESCRIPTION
        该函数会实时读取系统的 Committed Bytes 计数器，并对比系统的 Commit Limit（物理内存 + 分页文件）。
        进度条会根据当前压力自动变换颜色：
        - 绿色: < 70% (正常)
        - 黄色: 70% - 90% (警戒)
        - 红色: > 90% (危险)

        Commit Limit 的动态性：如果你的 Windows 设置了“自动管理所有驱动器的分页文件大小”，当你运行之前写的内存增加脚本时，你会发现 Commit Limit（分母）偶尔也会变大，因为 Windows 正在动态扩充物理硬盘上的分页文件来应对压力。
 
    .NOTES
    控制台的“自动换行”机制
    行宽溢出：你的控制台窗口不够宽。当 [时间] [进度条] 比例 这一串字符的总长度超过了窗口宽度时，即便我们用了 \r（回到行首），余下的部分也会被强制挤到下一行。
    上一次输出的残留：如果前一次输出较长，后一次输出较短，旧的末尾字符会留在屏幕上。
    我们需要在代码中加入动态宽度计算，并确保每一行输出后都用空格“擦除”掉行尾的残余。

    .EXAMPLE
        Watch-CommitMemory -RefreshInterval 1
    #>
    param (
        [Parameter(HelpMessage = "刷新间隔（秒）")]
        [double]$RefreshInterval = 1
    )

    # 1. 初始化系统限制数据 (单位转换为 GB)
    # TotalVirtualMemorySize 在 WMI 中代表 Commit Limit
    function Get-CommitLimit
    {
    
        try
        {
            $OS = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $CommitLimitGB = [Math]::Round($OS.TotalVirtualMemorySize / 1MB, 2)
            return $CommitLimitGB
        }
        catch
        {
            Write-Error "无法获取系统内存信息。"
            return
        }
    }

    Write-Host "`n>>> 启动内存提交量监控 <<<" -ForegroundColor Cyan
    Write-Host "初始系统提交限制 (RAM + 分页文件): $(Get-CommitLimit) GB"
    Write-Host "提示: 按 Ctrl+C 停止监控`n"

    # 2. 持续循环刷新
    try
    {
        # 使用性能计数器获取“已提交字节”
        Get-Counter "\Memory\Committed Bytes" -SampleInterval $RefreshInterval -Continuous | ForEach-Object {
            $CurrentBytes = $_.CounterSamples[0].CookedValue
            $CurrentGB = [Math]::Round($CurrentBytes / 1GB, 2)
            $CommitLimitGB = Get-CommitLimit
            $Percent = [Math]::Min(100, [Math]::Round(($CurrentGB / $CommitLimitGB) * 100, 0))
    
            # --- 核心改进：动态获取窗口宽度 ---
            # 我们预留 20 个字符给时间、百分比和括号，剩下的全给进度条
            $HostWidth = $Host.UI.RawUI.WindowSize.Width
            $BarWidth = [Math]::Max(10, $HostWidth - 35) 
    
            $FilledWidth = [Math]::Floor(($Percent / 100) * $BarWidth)
            $EmptyWidth = [Math]::Max(0, $BarWidth - $FilledWidth)
    
            $Color = "Green"
            if ($Percent -gt 70) { $Color = "Yellow" }
            if ($Percent -gt 90) { $Color = "Red" }
    
            $BarText = "#" * $FilledWidth
            $SpaceText = "-" * $EmptyWidth
    
            $Timestamp = Get-Date -Format "HH:mm:ss"
    
            # 构建最终字符串
            $Output = "[$Timestamp] [$BarText$SpaceText] $Percent% ($CurrentGB/$CommitLimitGB GB)"
    
            # 关键点：用新字符串覆盖旧字符串，并在末尾补空格防止残留
            Write-Host "`r$Output" -NoNewline -ForegroundColor $Color
        }
    }
    catch
    {
        # 处理 Ctrl+C 退出或其他异常
        Write-Host "`n`n监控已停止。" -ForegroundColor Cyan
    }
}
function Show-MemoryBar
{
    <#
    .SYNOPSIS
        模拟 Windows 资源监视器中的内存占用条
    .PARAMETER RefreshInterval
        刷新间隔（秒），默认 2
    .PARAMETER NoLoop
        只显示一次
    .EXAMPLE
        Show-MemoryBar
    .EXAMPLE
        Show-MemoryBar -RefreshInterval 1
    #>
    [CmdletBinding()]
    param(
        [int]$RefreshInterval = 2,
        [switch]$NoLoop
    )

    function Format-Size
    {
        param([double]$Bytes)
        if ($Bytes -ge 1GB) { "{0:N2} GB" -f ($Bytes / 1GB) }
        elseif ($Bytes -ge 1MB) { "{0:N0} MB" -f ($Bytes / 1MB) }
        elseif ($Bytes -ge 1KB) { "{0:N0} KB" -f ($Bytes / 1KB) }
        else { "{0:N0} B" -f $Bytes }
    }

    function Get-TruePhysicalMemory
    {
        $sticks = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
        if ($sticks)
        {
            $sum = ($sticks | Measure-Object -Property Capacity -Sum).Sum
            if ($sum -gt 0) { return [double]$sum }
        }
        return [double](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    }

    function Write-Block
    {
        param([int]$Width, [ConsoleColor]$BgColor)
        if ($Width -le 0) { return }
        $saved = $Host.UI.RawUI.BackgroundColor
        $Host.UI.RawUI.BackgroundColor = $BgColor
        Write-Host (" " * $Width) -NoNewline
        $Host.UI.RawUI.BackgroundColor = $saved
    }

    function Get-DisplayWidth
    {
        # 计算字符串的显示宽度（CJK 宽字符算 2 列）
        param([string]$Text)
        $w = 0
        foreach ($c in $Text.ToCharArray())
        {
            $code = [int]$c
            if (($code -ge 0x2E80 -and $code -le 0x9FFF) -or
                ($code -ge 0xF900 -and $code -le 0xFAFF) -or
                ($code -ge 0xFE30 -and $code -le 0xFE4F) -or
                ($code -ge 0xFF01 -and $code -le 0xFF60) -or
                ($code -ge 0x20000 -and $code -le 0x2FA1F))
            {
                $w += 2
            }
            else
            {
                $w += 1
            }
        }
        return $w
    }

    function Write-TruncateToWidth
    {
        # 按显示宽度截断字符串，超出部分用 … 替代
        param([string]$Text, [int]$MaxWidth)
        if ($MaxWidth -le 0) { return "" }
        $w = 0
        $sb = [System.Text.StringBuilder]::new()
        foreach ($c in $Text.ToCharArray())
        {
            $code = [int]$c
            $cw = 1
            if (($code -ge 0x2E80 -and $code -le 0x9FFF) -or
                ($code -ge 0xF900 -and $code -le 0xFAFF) -or
                ($code -ge 0xFE30 -and $code -le 0xFE4F) -or
                ($code -ge 0xFF01 -and $code -le 0xFF60) -or
                ($code -ge 0x20000 -and $code -le 0x2FA1F))
            {
                $cw = 2
            }
            if (($w + $cw) -gt ($MaxWidth - 1))
            {
                # 剩余空间放不下当前字符 + 省略号
                [void]$sb.Append([char]0x2026)  # …
                return $sb.ToString()
            }
            [void]$sb.Append($c)
            $w += $cw
        }
        return $sb.ToString()
    }

    function Write-Truncated
    {
        param(
            [string]$Text,
            [int]$MaxWidth,
            [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
        )
        $dw = Get-DisplayWidth $Text
        if ($dw -gt $MaxWidth)
        {
            $Text = Write-TruncateToWidth $Text $MaxWidth
        }
        Write-Host $Text -ForegroundColor $ForegroundColor
    }

    $trueTotal = Get-TruePhysicalMemory

    $segDefs = @(
        @{ Name = "硬件保留"; BgColor = [ConsoleColor]::Gray; LegendFg = [ConsoleColor]::Gray }
        @{ Name = "正在使用"; BgColor = [ConsoleColor]::DarkGreen; LegendFg = [ConsoleColor]::Green }
        @{ Name = "已修改  "; BgColor = [ConsoleColor]::DarkYellow; LegendFg = [ConsoleColor]::Yellow }
        @{ Name = "备用    "; BgColor = [ConsoleColor]::DarkCyan; LegendFg = [ConsoleColor]::Cyan }
        @{ Name = "可用    "; BgColor = [ConsoleColor]::DarkBlue; LegendFg = [ConsoleColor]::Blue }
    )

    $lineCount = 0
    $firstRun = $true
    try
    {
        while ($true)
        {

            # ── 终端宽度 ──
            $termWidth = $Host.UI.RawUI.WindowSize.Width
            if ($termWidth -le 0) { $termWidth = 120 }

            # 进度条宽度 = 终端宽度 - 左边距(4) - 左右边框(2)
            $barWidth = $termWidth - 6
            if ($barWidth -lt 20) { $barWidth = 20 }

            # ── 采集 ──
            $os = Get-CimInstance Win32_OperatingSystem
            $perf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory

            $totalVisible = [double]$os.TotalVisibleMemorySize * 1KB
            $hardwareReserved = $trueTotal - $totalVisible
            if ($hardwareReserved -lt 0) { $hardwareReserved = 0 }

            $standbyTotal = [double]$perf.StandbyCacheCoreBytes `
                + [double]$perf.StandbyCacheNormalPriorityBytes `
                + [double]$perf.StandbyCacheReserveBytes

            $modified = [double]$perf.ModifiedPageListBytes
            $freeAndZero = [double]$perf.FreeAndZeroPageListBytes

            $inUse = $totalVisible - $standbyTotal - $modified - $freeAndZero
            if ($inUse -lt 0)
            {
                $inUse = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 1KB
                $freeAndZero = $totalVisible - $inUse - $standbyTotal - $modified
                if ($freeAndZero -lt 0) { $freeAndZero = 0 }
            }

            $segValues = @($hardwareReserved, $inUse, $modified, $standbyTotal, $freeAndZero)
            $grandTotal = ($segValues | Measure-Object -Sum).Sum
            if ($grandTotal -le 0) { $grandTotal = $trueTotal }

            # ── 柱宽 ──
            $widths = @(0, 0, 0, 0, 0)
            $usedW = 0
            for ($i = 0; $i -lt 5; $i++)
            {
                $w = [Math]::Floor(($segValues[$i] / $grandTotal) * $barWidth)
                if ($w -lt 0) { $w = 0 }
                if ($segValues[$i] -gt 0 -and $w -eq 0 -and ($barWidth - $usedW) -gt 0) { $w = 1 }
                $widths[$i] = $w
                $usedW += $w
            }
            $diff = $barWidth - $usedW
            if ($diff -ne 0)
            {
                $maxIdx = 0; $maxV = 0
                for ($i = 0; $i -lt 5; $i++)
                {
                    if ($segValues[$i] -gt $maxV) { $maxV = $segValues[$i]; $maxIdx = $i }
                }
                $widths[$maxIdx] += $diff
                if ($widths[$maxIdx] -lt 0) { $widths[$maxIdx] = 0 }
            }

            # ── 清除上次输出 ──
            if (-not $firstRun -and $lineCount -gt 0)
            {
                for ($j = 0; $j -lt $lineCount; $j++)
                {
                    Write-Host "`e[1A`e[2K" -NoNewline
                }
            }

            $lines = 0

            # ── 标题 ──
            Write-Host ""
            $lines++

            Write-Host ""
            $lines++

            # ── 进度条（宽度已受控，固定 1 行）──
            Write-Host "  " -NoNewline
            Write-Host "▐" -ForegroundColor DarkGray -NoNewline
            for ($i = 0; $i -lt 5; $i++)
            {
                Write-Block -Width $widths[$i] -BgColor $segDefs[$i].BgColor
            }
            Write-Host "▌" -ForegroundColor DarkGray
            $lines++

            Write-Host ""
            $lines++

            # ── 图例：每行一个 ──
            for ($i = 0; $i -lt 5; $i++)
            {
                $pct = if ($grandTotal -gt 0) { ($segValues[$i] / $grandTotal) * 100 } else { 0 }

                # 构造完整行文本（用于截断计算）
                # $legendText = "        {0}  {1¡,10}  ({2,5:N1}%)" -f $segDefs[$i].Name, (Format-Size $segValues[$i]), $pct
                # 色块占 4 列 + 左边距 2 列 = 前 6 列已被色块和边距占用
                # 所以文字部分最大宽度 = termWidth - 6
                $textPart = "  {0}  {1,10}  ({2,5:N1}%)" -f $segDefs[$i].Name, (Format-Size $segValues[$i]), $pct
                $textDW = Get-DisplayWidth $textPart
                $maxTextWidth = $termWidth - 6
                if ($textDW -gt $maxTextWidth)
                {
                    $textPart = Write-TruncateToWidth $textPart $maxTextWidth
                }

                Write-Host "  " -NoNewline
                $savedBg = $Host.UI.RawUI.BackgroundColor
                $Host.UI.RawUI.BackgroundColor = $segDefs[$i].BgColor
                Write-Host "    " -NoNewline
                $Host.UI.RawUI.BackgroundColor = $savedBg
                Write-Host $textPart -ForegroundColor $segDefs[$i].LegendFg
                $lines++
            }

            Write-Host ""
            $lines++

            # ── 摘要 ──
            $pctInUse = if ($totalVisible -gt 0) { ($inUse / $totalVisible) * 100 } else { 0 }
            $available = $standbyTotal + $freeAndZero

            $summaryText = "  物理内存: {0}  |  OS可见: {1}  |  已使用: {2} ({3:N1}%)  |  可用: {4}" -f `
            (Format-Size $trueTotal),
            (Format-Size $totalVisible),
            (Format-Size $inUse),
            $pctInUse,
            (Format-Size $available)
            Write-Truncated $summaryText $termWidth White
            $lines++

            $ts = Get-Date -Format "HH:mm:ss"
            $tsLine = "  [$ts] 每 ${RefreshInterval}s 刷新 | Ctrl+C 退出"
            Write-Truncated $tsLine $termWidth DarkGray
            $lines++

            Write-Host ""
            $lines++

            $lineCount = $lines
            $firstRun = $false

            if ($NoLoop) { break }
            Start-Sleep -Seconds $RefreshInterval
        }
    }
    catch { }
    finally
    {
        [Console]::ResetColor()
        Write-Host ""
    }
}

# --- 从 Basic.psm1 迁入:电池电量(与 Get-MemoryUseSummary 同为 prompt 电池内存段的数据源) ---
function Get-BatteryLevel
{
    # get battery charge:
    $charge = Get-CimInstance -ClassName Win32_Battery | Select-Object -ExpandProperty EstimatedChargeRemaining
    return $charge
}
