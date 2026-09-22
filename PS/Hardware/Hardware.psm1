<#
Hardware 模块:本机硬件与系统信息(CPU/主板/内存/BIOS/磁盘/显示/macOS)。
从 Info.psm1 迁入: Info 只留内存/进程/电池,硬件信息类归此模块;
调用方命令名不变(自动发现同名模块)。
#>

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

# function Get-MotherBoardInfo
# {
#     return Get-CimInstance -ClassName Win32_baseboard
# }
function Get-MotherBoardInfo
{

    # 5.1 无 $IsWindows 自动变量(恒 $null):用 PSEdition 兜底(5.1 只跑 Windows,Desktop 即 Windows)
    if (($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true))
    {
        return Get-CimInstance -ClassName Win32_BaseBoard
    }
    elseif ($IsMacOS -eq $true)
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

    elseif ($IsLinux -eq $true)
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

