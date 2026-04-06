

function Confirm-ModuleInstalled
{
    <# 
    .SYNOPSIS
    判断检查指定模块是否已经安装可用,如果不可用则尝试安装该模块(使用comfirm动作包装)

    #>
    [cmdletbinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]
        [alias('ModuleName')]$Name, 
        [ValidateSet('CurrentUser', 'AllUsers')]$Scope = 'CurrentUser',
        [switch]$Install,
        [switch]$Import
    )
    $moduleAvailability = Get-Module -ListAvailable -Name $name #查询一个要几十毫秒
    if ($moduleAvailability)
    {
        Write-Verbose "Module $Name is already installed"
    }
    elseif($Install)
    {
        if($PSCmdlet.ShouldProcess($Name, 'Install Module'))
        {
        
            try
            {
                Install-Module -Name $Name -Scope $Scope -Force -ErrorAction Stop
                $moduleAvailability = Get-Module -ListAvailable -Name $name #再次查询
            }
            catch
            {
                Write-Warning "Install-Module 失败: $($_.Exception.Message)"
                return $False
            }
        }
    }
    else
    {
        return $False
    }
    if($moduleAvailability -and $Import)
    {
        Import-Module $Name
    }
    return $True


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

            # 补全模块
            'CompletionPredictor'
            # 'PsCompletions' #这里导入此模块会报错(可能有冲突,请在其他位置导入此模块)
            
            # 目录跳转
            # 'ZLocation' 使用更加强大和通用的zoxide替代(跨平台高性能方案,无需通过powershell导入)
            # 'z'
            
            # 美化模块
            # 'Terminal-Icons' #速度较慢,不默认启用
        ),
        # 安装模块的范围
        [ValidateSet('CurrentUser', 'AllUsers')]$Scope = 'CurrentUser',
        
        # 是否启用额外的相关扩展
        # 出于加载速度和轻便性考虑，不默认启用这部分扩展功能
        [parameter(ParameterSetName = 'Switch')]
        [ValidateSet('On', 'Off')]
        [parameter(Position = 0)]
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
            # 检查指定模块是否可用,如果不可用则尝试安装该模块(使用comfirm动作包装)
            Confirm-ModuleInstalled -Name $module -Scope $Scope -Install

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
    启用后增加私有工作集列（PrivWS），通过 CIM 查询获取，
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
    $capSumCol = "CapSum($SortBy)"

    # --- 初始化 ---
    $script:PercentSum = 0
    $script:CapacitySum = 0

    $osInfo = Get-CimInstance Win32_OperatingSystem
    $TotalRAM = $osInfo.TotalVisibleMemorySize * 1KB  # 转为字节


    # --- 打印物理内存使用概况 ---
    $usedRAMBytes = ($osInfo.TotalVisibleMemorySize - $osInfo.FreePhysicalMemory) * 1KB
    $usedRAMPercent = [math]::Round(($usedRAMBytes / $TotalRAM) * 100, 2)
    $totalDisp = [math]::Round($TotalRAM / $divisor, 2)
    $usedDisp = [math]::Round($usedRAMBytes / $divisor, 2)
    $freeDisp = [math]::Round(($TotalRAM - $usedRAMBytes) / $divisor, 2)

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
    #  辅助：根据 SortBy 生成百分比计算表达式（字节级原始值 / TotalRAM）
    # ============================================================
    $processes = Get-Process | Where-Object { $_.Name -notin $SKIP_PROCESSES } 
    if ($Group)
    {
        # === 分组模式 ===

        # 1) 构建基础数据（始终包含 WS / PM 列）
        $res = $processes |
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

        # 3) 追加百分比列（基于当前 SortBy 指标）
        $pctExpr = switch ($SortBy)
        {
            "WS"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$wsCol" * $divisor / $TotalRAM) * 100, 2)
                    }
                }
            }
            "PM"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$pmCol" * $divisor / $TotalRAM) * 100, 2)
                    }
                }
            }
            "PrivWS"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$pwsCol" * $divisor / $TotalRAM) * 100, 2)
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
                        [math]::Round(($_."$wsCol" * $divisor / $TotalRAM) * 100, 2)
                    }
                }
            }
            "PM"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$pmCol" * $divisor / $TotalRAM) * 100, 2)
                    }
                }
            }
            "PrivWS"
            {
                @{N = $pctCol; E = {
                        [math]::Round(($_."$pwsCol" * $divisor / $TotalRAM) * 100, 2)
                    }
                }
            }
        }
        $res = $res | Select-Object *, $pctExpr

        # 3) 排序 → 计算累加百分比与容量
        $finalProps = @('ID', 'Name', $wsCol, $pmCol)
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
function Get-NonEmptySubdirectories
{
    
    <#
.SYNOPSIS
    获取指定路径或管道输入中的非空子目录。

.DESCRIPTION
    该函数用于查找一个目录下的所有非空子目录（即包含文件或其他子目录的目录）。
    支持直接指定路径或通过管道传入目录对象。
    可选择递归搜索所有层级目录。

.PARAMETER Path
    [必需，位置0] 要检查的根目录路径。

.PARAMETER InputObject
    [管道输入] 接收来自管道的 [System.IO.DirectoryInfo] 对象（如 Get-ChildItem -Directory 的输出）。

.PARAMETER Recurse
    [可选] 如果指定此参数，则递归搜索所有嵌套层级的子目录；否则仅检查第一级子目录。

.EXAMPLE
    # 示例1：获取当前目录下所有非空的一级子目录
    Get-NonEmptySubdirectories -Path "C:\Example\Path"

    # 示例2：获取当前目录下所有层级中非空的子目录
    Get-NonEmptySubdirectories -Path "C:\Example\Path" -Recurse

    # 示例3：通过管道获取非空目录
    Get-ChildItem "C:\Example\Path" -Directory | Get-NonEmptySubdirectories

.INPUTS
    [string] 指定一个存在的目录路径。
    [System.IO.DirectoryInfo[]] 来自管道的对象（如 Get-ChildItem -Directory 输出）

.OUTPUTS
    [string[]] 返回一个或多个非空子目录的完整路径。
#>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [System.IO.DirectoryInfo[]]$InputObject,

        [switch]$Recurse
    )

    begin
    {
        $directories = @()
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'Path')
        {
            if (-not (Test-Path -Path $Path))
            {
                Write-Error "路径不存在: $Path"
                return
            }

            $getChildItemParams = @{
                Path      = $Path
                Directory = $true
            }
            if ($Recurse)
            {
                $getChildItemParams['Recurse'] = $true
            }

            $directories += Get-ChildItem @getChildItemParams
        }
        else
        {
            foreach ($dir in $InputObject)
            {
                $directories += $dir
            }
        }
    }

    end
    {
        foreach ($dir in $directories)
        {
            $items = Get-ChildItem -Path $dir.FullName -Force -ErrorAction SilentlyContinue
            if ($null -ne $items)
            {
                $dir.FullName
            }
        }
    }
}


function Remove-EmptyDirectories
{
    <#
.SYNOPSIS
    删除一个或多个空目录。

.DESCRIPTION
    该函数用于删除一个目录中的所有空子目录。默认仅检查一级子目录，也可以通过 -Recurse 递归查找。
    支持从路径或管道输入目录对象。
    空目录是指不包含任何文件或子目录的目录（即使有隐藏文件也被视为“非空”）。

.PARAMETER Path
    [必需，位置0] 要检查并从中删除空目录的根路径。

.PARAMETER InputObject
    [管道输入] 接收来自管道的 [System.IO.DirectoryInfo] 对象（如 Get-ChildItem -Directory 的输出）。

.PARAMETER Recurse
    [可选] 如果指定此参数，则递归检查所有层级的子目录。

.PARAMETER Force
    [可选] 删除具有隐藏或只读属性的目录。

.PARAMETER WhatIf
    显示将要执行的操作，但不实际执行删除。

.PARAMETER Confirm
    在删除每个目录前提示确认。

.EXAMPLE
    # 删除 C:\Temp 中的所有空子目录（不递归）
    Remove-EmptyDirectories -Path "C:\Temp"

    # 删除 C:\Temp 中所有层级的空目录
    Remove-EmptyDirectories -Path "C:\Temp" -Recurse

    # 删除所有名称为 temp 的子目录
    Get-ChildItem "C:\Projects" -Directory -Recurse | Where-Object Name -eq "temp" | Remove-EmptyDirectories -Force

.INPUTS
    [string] 指定一个存在的目录路径。
    [System.IO.DirectoryInfo[]] 来自管道的对象（如 Get-ChildItem -Directory 输出）

.OUTPUTS
    无输出，除非使用 Write-Verbose 或 Write-Warning。
#>
    [CmdletBinding(DefaultParameterSetName = 'Path', SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [System.IO.DirectoryInfo[]]$InputObject,

        [switch]$Recurse,
        [switch]$Force
    )

    begin
    {
        $directories = @()
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'Path')
        {
            if (-not (Test-Path -Path $Path))
            {
                Write-Error "路径不存在: $Path"
                return
            }

            $getChildItemParams = @{
                Path      = $Path
                Directory = $true
            }
            if ($Recurse)
            {
                $getChildItemParams['Recurse'] = $true
            }

            $directories += Get-ChildItem @getChildItemParams
        }
        else
        {
            foreach ($dir in $InputObject)
            {
                $directories += $dir
            }
        }
    }

    end
    {
        foreach ($dir in $directories)
        {
            try
            {
                $items = Get-ChildItem -Path $dir.FullName -Force -ErrorAction Stop
                if ($null -eq $items)
                {
                    if ($PSCmdlet.ShouldProcess($dir.FullName, "删除空目录"))
                    {
                        [System.IO.Directory]::Delete($dir.FullName, $false)
                        Write-Verbose "已删除空目录: $($dir.FullName)"
                    }
                }
            }
            catch
            {
                Write-Warning "无法访问目录 '$($dir.FullName)': $_"
            }
        }
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
    # 确保文件存在
    New-Item -ItemType File -Path $ProfileLevel -Force -Verbose -ErrorAction SilentlyContinue
    $pf = $ProfileLevel
    '# AutoRun commands from CxxuPsModules' + " $(Get-Date)" >> $pf
    {
        init
        # 全局补全模块需要特殊处理,放在profile中,但是该模块可能导致ipmof|iex报错,所以不自动启用为好
        # Confirm-ModuleInstalled -Name PsCompletions -Install *> $null
        # Import-Module PSCompletions
        
        # $res = Get-Command 'scoop-search' -ErrorAction SilentlyContinue
        # if ($res)
        # {
        #     Write-Host 'scoop-search hook loaded!'
        #     Invoke-Expression (&scoop-search --hook)
        # }

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
    Set-PsPrompt 
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
        $s = '#⚡️', 'Cyan'
        

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

        $displayversion = Get-WindowsOSVersionFromRegistry | Select-Object -ExpandProperty DisplayVersion #例如24H2
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
        if ($module -like '*completion*')
        { 
            Write-Warning "Skipping $module"
            continue 
        }
        Remove-Module $module -ErrorAction SilentlyContinue -Force

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
    # prompt=$originalPromptScript
    Import-ModuleForce
    # $currentPromptScript = $function:prompt
    # Write-Verbose "[[$currentPromptScript]]" -Verbose
    # Set-Item -Path Function:prompt -Value $currentPromptScript
    
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
    Write-UserHostname
    # Write-HostIp
    Write-Path
    Write-Time
    # Write-Uptime #统计不太准,而且比较少用
    write-GitBasicInfo
    # Write-Host ''
    Write-Host ' PS >'
    
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
        # $PSStyle.Progress.View = 'Minimal'
        $items = Get-ChildItem $path
        $count = $items.count
        Write-Verbose "$count Path(s) will be processed" 
    }

    process
    {
        # $i = 0

        foreach ($item in $Path)
        {
            # 增加write-progress支持
                
            # Write-Verbose "Calculating size of directory $item"
            # if ($count -gt 1)
            # {

            #     $Completed = ($i / $count) * 100
            #     # 精度控制
            #     $Completed = [math]::Round($Completed, 1)
            #     Write-Host "$i ,$Completed"
            #     Write-Progress -Activity "Calculating size of $item" -Status "Progress: $Completed %" -PercentComplete $Completed
            #     $i += 1
            # }
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
                Write-Host $item -ForegroundColor Cyan
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
    [CmdletBinding()]
    param(
        # 是否只返回存在文件
        [switch]$ExistOnly
    )
    $profiles = @(
        $profile.CurrentUserCurrentHost,
        $profile.CurrentUserAllHosts,
        $profile.AllUsersCurrentHost,
        $profile.AllUsersAllHosts
    )
    if ($ExistOnly)
    {
        $profiles = $profiles | Where-Object { Test-Path $_ }
    }
    return $profiles
}
 
function Remove-PsProfiles
{
    $profiles = Get-PsProfilesPath
    foreach ($pf in $profiles)
    {
        Remove-Item -Force -Verbose $pf -ErrorAction SilentlyContinue
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
            Get-ProxyEnvVarSettings
        }
        default {}
    }
    Invoke-Expression (New-Object net.webclient).downloadstring('https://get.scoop.sh')
    
}
function Set-Owner
{
    <# 
    .SYNOPSIS
    设置指定目录或文件的所有者
    .EXAMPLE
    默认将所有者设置为当前用户,域和用户名定义在VarSet1中,如果不导入,可以通过[System.Environment]::UserDomainName,[System.Environment]::UserName  或者简单通过$env:ComputerName和whoami命令获取
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
            # 将conda当前激活的环境名打印出来(不带换行,便于和原来的拼接起来)
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
        $version = ''
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
        
        # 将综合的决策结果写入到环境变量(自动更新当前环境的PsPrompt变量)
        Set-EnvVar PsPrompt $version  #这是一个耗时逻辑,不建议作为默认参数集使用
    }

    # 检查基础环境信息,以便powershell prompt字段可以正确显示
    Update-PwshEnvIfNotYet -Mode core # > $null
    Update-PwshAliases -Core
    Set-LastUpdateTime -Verbose:$VerbosePreference

    $env:PsPrompt = $version
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
    $DurationArrays = (1..$iterations | ForEach-Object { Measure-Command { prompt *> $null } })
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
        
        Write-Host $downloadUrl -ForegroundColor Cyan
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

    return $PsEnvMode -ge $Value
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
    # Write-Host $PromptMessage Cyan
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
        Set-PsPrompt -Verbose:$VerbosePreference
    }

    Write-Verbose 'Environment  have been Imported in the current powershell!'
}
 
function Start-CodeSSh
{
    <# 
    .SYNOPSIS
    命令行中启动vscode的ssh远程连接,进行远程编程或文件管理
    .PARAMETER Server
    远程服务器的名称(可以主机名)或ip地址
    .PARAMETER Path
    需要打开的目录,默认是用户的主目录
    例如'/www/wwwroot/xcx/tissuschic.com/wordpress'
    .EXAMPLE
    linux主机的ip地址为192.168.1.111;并且配置了ssh免密登录(上传了公钥),可以直接使用如下命令进行远程编程或文件管理:
    比如我要编辑网站demosite.com根目录,就可以用以下命令打开
    
    PS> Start-CodeSSh -Server 192.168.1.111 -Path /www/wwwroot/xcx/demosite.com/wordpress

    #>
    param (

        #根据查询到的ip地址,创建变量
        $Editor = 'code',
        $Server = 'localhost',
        # $Path="/home/" #需要打开的目录
        $Path = $home,
        $Port = ""
    )
    # code --folder-uri "vscode-remote://ssh-remote+$Server/$Path"
    $cmd = "$Editor --folder-uri vscode-remote://ssh-remote+$Server/$Path"
    Invoke-Expression $cmd
}
function Remove-RobocopyMirEmpty
{
    <# 
    .SYNOPSIS
    使用 RoboCopy 多线程快速删除文件夹及其内容。

    .DESCRIPTION
    此函数利用 RoboCopy 的 /mir 参数和多线程能力快速删除文件夹及其所有内容。
    比传统的 Remove-Item 或 cmd 的 rd/del 命令在处理大量文件时更高效。

    .PARAMETER Path
    指定要删除的文件夹路径。支持相对路径和绝对路径。

    .PARAMETER ThreadCount
    指定 RoboCopy 使用的线程数。默认值为 32，可根据系统性能调整。

    .PARAMETER WhatIf
    显示将要执行的操作，但不实际执行删除。

    .PARAMETER Confirm
    在执行删除前提示确认。

    .EXAMPLE
    Remove-RobocopyMirEmpty -Path "C:\LargeFolder"
    删除 C:\LargeFolder 及其所有内容。

    .EXAMPLE
    Remove-RobocopyMirEmpty -Path ".\TempFiles" -ThreadCount 64 -WhatIf
    模拟使用64个线程删除当前目录下的 TempFiles 文件夹。

    .NOTES
    文件名: Remove-RobocopyMirEmpty.ps1
    日期: $(Get-Date -Format 'yyyy-MM-dd')

    .LINK
    https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if (-not (Test-Path -Path $_ -PathType Container))
                {
                    throw "路径 '$_' 不存在或不是文件夹"
                }
                $true
            })]
        [string]$Path,

        [Parameter()]
        [ValidateRange(1, 128)]
        [int]$ThreadCount = 32,
        $logFile = "C:/temp/robocopy_mir_empty.log"
    )

    begin
    {
        # 创建临时空目录
        $emptyDir = Join-Path -Path $env:TEMP -ChildPath "RoboCopyEmpty_$(New-Guid)"
        $null = New-Item -Path $emptyDir -ItemType Directory -Force
    }

    process
    {
        try
        {
            $fullPath = Convert-Path -Path $Path 
            

            if ($PSCmdlet.ShouldProcess($fullPath, "删除文件夹及其所有内容"))
            {
                Write-Verbose "正在使用 RoboCopy 删除文件夹: $fullPath (线程数: $ThreadCount)"
                
                # 执行 RoboCopy 删除操作
                $robocopyArgs = @(
                    "'$emptyDir'"
                    "'$fullPath'"
                    "/mir"          # 镜像空目录
                    "/mt:$ThreadCount" # 多线程
                    "/E" #递归处理

                    "/log:'$logFile'"
                    # "/nfl"          # 不记录文件名
                    # "/ndl"          # 不记录目录名
                    # "/njh"          # 无作业头
                    # "/njs"          # 无作业摘要
                    # "/ns"           # 无大小
                    # "/nc"          # 无类别
                )
                $argsStr = $robocopyArgs -join "  "
                # $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                $cmd = "Robocopy.exe $argsStr" 
                Write-Verbose $cmd -Verbose

                $cmd | Invoke-Expression

                if ($process.ExitCode -ge 8)
                {
                    Write-Warning "RoboCopy 完成但可能有错误 (退出代码: $($process.ExitCode))"
                }
                else
                {
                    Write-Verbose "RoboCopy 成功完成 (退出代码: $($process.ExitCode))"
                }

                # 删除空文件夹
                Remove-Item -Path $fullPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch
        {
            Write-Error "删除文件夹时出错: $_"
            throw
        }
    }

    end
    {
        # 清理临时空目录
        if (Test-Path -Path $emptyDir)
        {
            Remove-Item -Path $emptyDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
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
    #1:将复制过程的输出重定向到指定文件中(始终推荐使用LOG参数指定日志输出,经验表明,日志输出到屏幕会对性能有重大影响(可达10倍以上))
    PS> Robocopy.exe .\7.us\ .\rb1 /E /B /MT:8  /LOG:07091121
      日志文件: C:\sites\wp_sites\07091121

    #2: 适用于从网络复制的场景,增加更多参数(重试,详细日志级别等)
    robocopy C:\source\folder\path\ D:\destination\folder\path\ /E  /MT:32  /ZB /R:5 /W:5 /V /LOG:C:\log\robocopy.log
    
    参数	含义	推荐用途
    /E	复制所有子目录，包括空目录	确保完整复制整个目录结构
    /V	显示详细信息（包括跳过文件）	调试或审计用
    /MT[:n]	多线程复制（默认 8，最大 128）	提升 I/O 性能
    /ZB :: 使用可重新启动模式；如果拒绝访问，请使用备份模式。(效果是/Z /B)
        使用可重启模式 + 强制权限访问	网络复制 + 克服锁定文件(需要管理员权限才能访问某些受保护的系统文件)
    /R:n	失败重试次数（默认 1000000）	控制失败后的尝试次数
    /W:n	重试等待时间（秒）	避免频繁失败冲击资源

    .ExAMPLE
    PS C:\Users\cxxu\Desktop> copy-Robocopy -Source .\dir4 -Destination .\dir1\ -Recurse
    The Destination directory name is different from the Source directory name! Create the Same Name Directory? {Continue? [y/n]} : y
    Executing: robocopy ".\dir4" ".\dir1\dir4"  /E /MT:16 /R:1 /W:1

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
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
        [string]$LogFile = "",
        $LogPreviewEncodings = 'ansi',
        # 不询问直接执行所有步骤
        [switch]$Force,

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

        [string[]]$OtherArgumentList
    )
    if(!$LogFile)
    {
        Write-Warning "No LogFile specified, the output will be displayed on the console and the speed will be affected seriously!"
        Write-Warning "Stop and restart with -LogFile <logFilePath> is recommended!(such as '-LogFile C:\log\robocopy.log')" -WarningAction Inquire
    }
    # Construct the robocopy command
    # 确保source和destination都是目录
    if (Test-Path $Source -PathType Leaf)
    {
        throw 'Source must be a Directory!'
    }if (Test-Path $Destination -PathType Leaf)
    {
        throw 'Destination must be a Directory!'
    }

    Write-Host 'checking directory name...'
    #向用户展示参数设置🎈
    # $PSBoundParameters  
    # 注意,$source和$destination在函数参数定义时不可以定为String类型,会导致Get-PsIOItemInfo返回值无法正确赋值
    Write-Debug "Source: $Source"
    Write-Debug "Destination: $Destination"
    if($Files)
    {
        Write-Debug "Files: $Files"
    }
    # $Source = Get-PsIOItemInfo $Source
    # $destination = Get-PsIOItemInfo $Destination

    # 检查目录名是否相同(basename)
    # $SN = $source.name
    # $DN = $Destination.name
    $SN = Split-Path -Path $Source -Leaf
    $DN = Split-Path -Path $Destination -Leaf

    Write-Verbose "$SN,$DN" 
    if ($Force -and !$Confirm)
    {
        $ConfirmPreference = 'none'
    }
    # if ($SN -ne $DN)
    # {
    #     # Write-Verbose "$($Source.name) -ne $($destination.name)"

    #     $msg = 'The Destination directory name is different from the Source directory name! Create the Same Name Directory?'
    #     # $continue = Confirm-UserContinue -Description 
    #     $continue = $PSCmdlet.ShouldProcess($Destination, $msg)
    #     if ($continue)
    #     {
    #         $Destination = Join-Path $Destination $SN
    #         Write-Verbose "$Destination" -Verbose
    #     }
    # }

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
    $robocopyCmd += ' /ZB' 
    # 重试次数和间隔限制
    $robocopyCmd += " /R:$Retry /W:$Wait"


    if($PSCmdlet.ShouldProcess($Destination, "Executing: $robocopyCmd"))
    {

        Invoke-Expression $robocopyCmd
        
    }
    
    Write-Verbose "Set LogPreviewEncodings to Preview log in specified way(utf-8,ansi,gbk,etc)" -Verbose
    # 预览日志总结
    if($LogFile -and (Test-Path $LogFile))
    {
        Get-Content $logFile -Encoding $LogPreviewEncodings | Select-Object -Last 13
    }
}


