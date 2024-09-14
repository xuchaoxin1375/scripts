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
    $totalMemory = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory

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
    Write-Host $DataJson    
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
        $dataJson = $DataJson
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
    
    $adapters = Get-NetAdapter -Physical
    if ($Status -ne 'All')
    {
        $adapters = $adapters | Where-Object { $_.Status -eq $Status }
    }
    $adapters = $adapters | Select-Object Name, Status 
    
    # return $adapters

 

    if ($VerbosePreference)
    {
        $adapters | Format-Table
    }

    $s = ''
    foreach ($adapter in $adapters)
    {
        # if ($adapters)
        # $s += ("[$($ip.InterfaceAlias) : $($ip.IpAddress)]")
        $ip = Get-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 | Select-Object IPAddress
        $s += ("<$($adapter.Name[0]):$($ip.IPAddress)>")
    }
    # $ip = Get-IPAddressOfPhysicalAdapter | Select-Object -First 1 | Select-Object -ExpandProperty ipaddress 
    # 将ip信息写入到环境变量保存起来,以便后续访问
    Write-Verbose $s
    # 写入环境变量
    # Set-EnvVar -EnvVar IpPrompt $s *> $null
    Update-Json -Key IpPrompt -Value $s -DataJson $dataJson

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
    # 确保需要的Json文件存在
    Confirm-DataJson
    
    $IpPrompt = Get-Json -Key IpPrompt -ErrorAction SilentlyContinue
    if (!$IpPrompt )
    {
        # 如果dataJson没有IP字段或者字段为空,检查是否有意置空(虽然置空没什么大用)
        if (!$env:ClearIpPrompt)
        {

            $ipPrompt = Get-IpAddressFormated
            # $IpPrompt = Get-Json -Key IpPrompt
        }
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
    如果您可以接受个别时候加载速度略慢(也不会太慢,100ms左右),且不希望后台额外运行计算内存占用的磁盘进程,那么可以使用这个函数
    
    如果不按住回车键,几乎感觉不到卡顿,总体资源占用会比 Get-MemoryUseRatioCache 要低,属于懒惰计算)

    被调用时,当场计算直接获取(在间隔超过预设时会调用耗时操作(计算内存占用),所以shell相应的稳定性稍差,但是最慢的情况也能够在100ms左右返回结果
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

    # 跟据指定时间间隔参数$Interval执行耗时逻辑
    Start-ScriptWhenIntervalEnough -Interval $Interval -ScriptBlock {
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem;
        # 访问硬件信息,所以比较耗时(100ms左右)
        $env:cachedTotalMemory = $OS.TotalVisibleMemorySize / 1MB;
        $env:cachedFreeMemory = $OS.FreePhysicalMemory / 1MB;
    }
    # return
    if ($VerbosePreference)
    {
        Write-Host "$env:cachedTotalMemory MB", ($env:cachedFreeMemory).GetType()
        # write-host "$env:cachedFreeMemory MB"
    }
    # 计算已用内存和占用百分比
    # $UsedMemory = $TotalMemory - $FreeMemory
    $UsedMemory = [float]$env:cachedTotalMemory - [float]$env:cachedFreeMemory
    $FreeMemory = [float]$env:cachedFreeMemory
    $res = [PSCustomObject]@{
        UsedMemory  = $UsedMemory
        TotalMemory = [float]$env:cachedTotalMemory
        FreeMemory  = $FreeMemory
    }
    return $res
    
}

function Get-MemoryUseInfoCached
{
    <# 
    .SYNOPSIS
    获取内存占用数值
    如果您在意prompt返回的速度稳定性,且不在意后台定时进行少量的磁盘读写,那么可以使用该函数

    用独立于当前shell的保存到磁盘上的近期数值,理论上响应速度更加稳定,但会在后台占用一定资源,每隔一定时间(预设时间),耗时任务被后台进程独立执行和维护,进程会进行磁盘读写,读写的量很少,时间主要在于计算内存占用的调用上
    .DESCRIPTION
    由于计算内存占用的进程被独立出去,要设置计算频率(时间间隔),详见Start-PeriodlyDaemon
    关于这个后台进程,可以手动结束掉,模块中配备了Stop-LastUpdateDaemon函数,都可以独立调用
    然而,多个地方或多次调用Start-PeriodlyDaemon会导致进程号混乱,此时Stop-lastUpdateDaemon可能无法全部相关进程,您可以用任务管理器,搜索具有相关命令行
    
    #>
    param (
        $SourceFile = $LastUpdate
    )
    $res = Get-Content "$LastUpdateLog"
    $res = $res -split "`n"
    $FreeMemory = $res[0]
    # $TotalMemory = $res[1]
    $UsedMemory = $TotalMemory - $FreeMemory
    return $UsedMemory, $TotalMemory, $FreeMemory
}
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
    
    if (!$env:cachedFreeMemory)
    {
        Write-Host 'init Memory Info' -ForegroundColor Magenta

        Set-LastUpdateTime
        Start-MemoryInfoInit
    }


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
    $res = "$env:USERNAME@$env:COMPUTERNAME"
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
function Get-MatherBoardInfo
{
    return Get-CimInstance -ClassName Win32_baseboard
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