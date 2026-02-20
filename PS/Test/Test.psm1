function Get-ProcessMemoryViewx
{
    <#
    .SYNOPSIS
    查看进程内存占用情况，支持分组、排序、私有工作集、自定义单位等功能。

    .DESCRIPTION
    获取当前系统所有进程的内存使用情况，支持以下特性：
    - 按进程名分组（Group模式），方便排查哪个软件占用大量内存
    - 自定义排序指标（WS/PM/PrivateWS），排序指标决定百分比列和累加列的计算基准
    - 自定义显示单位（KB/MB/GB）
    - 可选显示私有工作集（与任务管理器"内存"列对应）
    - 累加百分比列（sum%），快速定位内存大户
    
    关于百分比列：
    百分比列名和计算基准跟随 SortBy 参数：
    - SortBy WS         → 显示 %WS 列
    - SortBy PM         → 显示 %PM 列
    - SortBy PrivateWS  → 显示 %PrivateWS 列

    关于作用域：
    在管道（Pipeline）内部修改外部变量时，需要显式指定作用域（$script:），
    否则脚本块内部会将其视为局部变量，导致累加失败。

    .PARAMETER First
    获取前几名进程，设为 0 则获取所有进程。默认 10。

    .PARAMETER Group
    启用分组模式，按进程名合并，使用 Measure-Object -Sum 计算分组总和。

    .PARAMETER WorkingSetPrivate
    启用后增加私有工作集列（PrivateWS），通过 CIM 查询获取，
    与任务管理器"详细信息"中的"内存(私有工作集)"一致。

    .PARAMETER SortBy
    指定排序依据的指标，同时决定百分比列的计算基准。
    可选值：WS、PM、PrivateWS。
    当指定 PrivateWS 时会自动启用 -WorkingSetPrivate。默认 WS。

    .PARAMETER Unit
    显示内存的单位。可选值：KB、MB、GB。默认 GB。

    .EXAMPLE
    Get-ProcessMemoryView | ft
    默认参数：前10名，按WS排序，显示%WS，单位GB。

    .EXAMPLE
    Get-ProcessMemoryView -Unit MB -SortBy PM | ft
    以MB为单位，按PM排序，显示%PM。

    .EXAMPLE
    Get-ProcessMemoryView -SortBy PrivateWS -Unit MB | ft
    按私有工作集排序（自动启用该列），显示%PrivateWS，以MB显示。

    .EXAMPLE
    Get-ProcessMemoryView -Group -First 10 | ft -Wrap
    分组模式，换行显示PIDs列。

    .EXAMPLE
    Get-ProcessMemoryView -Group | Select-Object * -ExcludeProperty PIDs | ft
    隐藏PIDs列。

    .EXAMPLE
    Get-ProcessMemoryView | Measure-Object '%WS' -Sum
    计算最占内存的前若干名进程的WS占用率之和。

    .EXAMPLE
    Get-ProcessMemoryView -Group | Where-Object { $_.Name -like 'msedge' }
    筛选特定进程名的分组数据。

    .NOTES
    - 私有工作集通过 Win32_PerfFormattedData_PerfProc_Process 获取，首次查询可能稍慢
    - 百分比基于总可见物理内存计算
    - 如果没有 $script: 前缀，在某些 PowerShell 版本或复杂上下文中，
      $sum 可能不会在每一行之间成功传递累加值
    #>
    param(
        [int]$First = 10,

        [switch]$Group,

        [switch]$WorkingSetPrivate,

        [ValidateSet("WS", "PM", "PrivateWS")]
        [string]$SortBy = "WS",

        [ValidateSet("KB", "MB", "GB")]
        [string]$Unit = "GB"
    )

    # --- 自动修正：按 PrivateWS 排序时自动启用开关 ---
    if ($SortBy -eq "PrivateWS" -and -not $WorkingSetPrivate)
    {
        $WorkingSetPrivate = [switch]::Present
    }

    # --- 打印当前参数 ---
    Write-Host "========== Parameters ==========" -ForegroundColor Cyan
    Write-Host "  First             : $(if ($First) { $First } else { 'All' })" -ForegroundColor Yellow
    Write-Host "  Group             : $Group" -ForegroundColor Yellow
    Write-Host "  WorkingSetPrivate : $WorkingSetPrivate" -ForegroundColor Yellow
    Write-Host "  SortBy            : $SortBy" -ForegroundColor Yellow
    Write-Host "  Unit              : $Unit" -ForegroundColor Yellow
    Write-Host "=================================" -ForegroundColor Cyan

    # --- 单位换算因子 ---
    $divisor = switch ($Unit)
    {
        "KB" { 1KB }
        "MB" { 1MB }
        "GB" { 1GB }
    }

    # --- 列名定义 ---
    $wsCol = "WS($Unit)"
    $pmCol = "PM($Unit)"
    $pwsCol = "PrivateWS($Unit)"
    $pctCol = "%$SortBy"           # 百分比列名跟随排序指标
    $sumCol = "sum(%$SortBy)"      # 累加列名跟随排序指标
    $sortColumn = switch ($SortBy)
    {
        "WS"         { $wsCol }
        "PM"         { $pmCol }
        "PrivateWS"  { $pwsCol }
    }

    # --- 初始化 ---
    $script:Sum = 0
    $TotalRAM = (Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize * 1KB

    # --- 预查询私有工作集 PID → 字节数 ---
    $privateWSMap = @{}
    if ($WorkingSetPrivate)
    {
        Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
            ForEach-Object { $privateWSMap[[int]$_.IDProcess] = [long]$_.WorkingSetPrivate }
    }

    if ($Group)
    {
        # === 分组模式 ===

        # 1) 构建基础数据
        $res = Get-Process | 
        Group-Object -Property Name | 
        Select-Object @{N = "Name"; E = { $_.Name } },
        @{N = "Count"; E = { $_.Count } },
        @{N = "PIDs"; E = { ($_.Group.Id -join ",") } },
        @{N = $wsCol; E = { ($_.Group | Measure-Object WorkingSet64 -Sum).Sum / $divisor } },
        @{N = $pmCol; E = { ($_.Group | Measure-Object PagedMemorySize64 -Sum).Sum / $divisor } }

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

        # 3) 计算百分比列（基于排序指标）
        $res = $res | Select-Object *,
        @{N = $pctCol; E = {
                $bytes = $_.$sortColumn * $divisor
                [math]::Round(($bytes / $TotalRAM) * 100, 2)
            }
        }

        # 4) 排序 → 计算累加 sum
        $finalProps = @("Name", "Count", $wsCol, $pmCol)
        if ($WorkingSetPrivate) { $finalProps += $pwsCol }
        $finalProps += $pctCol
        $finalProps += @{N = $sumCol; E = { 
                $script:Sum += $_.$pctCol
                [math]::Round($script:Sum, 2)
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

        $res = Get-Process | Select-Object $baseProps

        # 2) 计算百分比列（基于排序指标）
        $res = $res | Select-Object *,
        @{N = $pctCol; E = {
                $bytes = $_.$sortColumn * $divisor
                [math]::Round(($bytes / $TotalRAM) * 100, 2)
            }
        }

        # 3) 排序 → 计算累加 sum
        $finalProps = @('ID', 'Name', $wsCol, $pmCol)
        if ($WorkingSetPrivate) { $finalProps += $pwsCol }
        $finalProps += $pctCol
        $finalProps += @{N = $sumCol; E = {
                $script:Sum += $_.$pctCol
                [math]::Round($script:Sum, 2)
            }
        }

        $res = $res | Sort-Object $sortColumn -Descending | Select-Object $finalProps
    }

    # --- 截取前 N 条 ---
    if ($First) { $res = $res | Select-Object -First $First }

    return $res
}