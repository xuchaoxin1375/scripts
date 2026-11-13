# 其他函数都是通过init来调用或间接调用的,在这里可以注释掉某些模块来帮助调试bug
 
# 本会话由用户配置文件注入的开关(键=值),供 Get-CxxuConfig 标注来源;
# Import-CxxuConfig 每次执行先清空,避免 init -Force 后残留旧记录。
$script:CxxuConfigAppliedFromFile = @{}
# 模块根目录:5.1 的 $PSScriptRoot 在函数内是动态作用域(取调用方脚本),不能用于定位 PS 根
$script:CxxuModuleRoot = $PSScriptRoot
# 组件清单与默认值在会话内不变，缓存解析结果，避免 Get-CxxuConfig/导入时反复读 PSD1。
$script:CxxuComponentManifestCache = $null
$script:CxxuSettingsDefaultCache = $null
$script:CxxuConfigDefaultListCache = $null
# 标准 psd1 解析器是否可见：缺失时 Read-CxxuDataFile 退回 AST 解析，只探测一次。
$script:CxxuDataFileReaderAvailable = $null
# argc-completions 的平台差异:可执行名与专用补全目录。
# 5.1 无 $IsWindows/$IsMacOS 自动变量,先用 PSEdition 兜底判 Windows(5.1 只跑在 Windows 上)。
$script:ArgcPlatform = @{ Executable = 'argc'; CompletionDir = 'linux' }
if (($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true))
{
    $script:ArgcPlatform = @{ Executable = 'argc.exe'; CompletionDir = 'windows' }
}
elseif ($IsMacOS -eq $true)
{
    $script:ArgcPlatform.CompletionDir = 'macos'
}

function Test-CxxuPs7ModulePathEntry
{
    # 判断路径是否属于 PowerShell 7 的模块目录(不导出):
    # 7 的用户级与机器级目录以 \PowerShell\Modules 结尾;便携或 scoop 安装的 7 为 \powershell\<版本或别名>\Modules。
    param([Parameter(Mandatory)][string]$Path)

    $p = $Path.TrimEnd('\')
    if ($p -match '(?i)\\WindowsPowerShell\\Modules$') { return $false }
    if ($p -match '(?i)\\PowerShell\\Modules$') { return $true }
    return [bool]($p -match '(?i)\\powershell\\[^\\]+\\Modules$')
}
function Update-CxxuModulePathOrder
{
    # 修正 5.1 会话的模块路径顺序(不导出)。
    # 从 pwsh 7 终端启动 VS Code、Windows Terminal 等程序时,子进程会继承 7 的 PSModulePath,
    # 7 的模块目录因此排在 5.1 自带目录之前;5.1 会优先解析到仅 7 可用的模块。
    # 实测 Microsoft.PowerShell.Utility 7.0.0.0 在 5.1 下加载后,Import-PowerShellDataFile 等命令不可见,
    # init 读组件清单与用户配置即失败。修复分两步:把 5.1 自带的机器级与 $PSHOME\Modules 前置(不删除条目),
    # 再重新导入已被错误版本占位的 Microsoft.PowerShell.Utility;顺序正常时不动作。
    if ($PSVersionTable.PSEdition -ne 'Desktop') { return }

    # 从 pwsh 7 终端启动 5.1 时,子进程可能继承一个不含 5.1 用户模块目录的 PSModulePath;
    # PSReadLine 在首个提示符前才加载,这里前置用户目录后,升级到 2.3.6 的模块才会被自动选中。
    $userModules = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
    $entries = @($env:PSModulePath -split ';' | Where-Object { $_ })
    if ($userModules -and (Test-Path -LiteralPath $userModules) -and ($entries -notcontains $userModules))
    {
        $entries = @($userModules) + $entries
        $env:PSModulePath = $entries -join ';'
        Write-Verbose "PSModulePath 缺少 5.1 用户模块目录,已前置: $userModules"
    }

    $ownHome = Join-Path $PSHOME 'Modules'
    $ownNorm = @($ownHome.TrimEnd('\'))
    if ($env:ProgramFiles) { $ownNorm += (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules').TrimEnd('\') }
    $entries = @($env:PSModulePath -split ';' | Where-Object { $_ })
    $ownIndex = -1
    $ps7Index = -1
    for ($i = 0; $i -lt $entries.Count; $i++)
    {
        $current = $entries[$i].TrimEnd('\')
        if ($ownIndex -lt 0 -and ($ownNorm -contains $current)) { $ownIndex = $i; continue }
        if ($ps7Index -lt 0 -and ($ownNorm -notcontains $current) -and (Test-CxxuPs7ModulePathEntry -Path $entries[$i])) { $ps7Index = $i }
    }
    # 自带目录不在路径里或 7 目录并未抢在它前面时,保持原样
    if ($ownIndex -lt 0 -or $ps7Index -lt 0 -or $ps7Index -gt $ownIndex) { return }

    $front = @($entries | Where-Object { $ownNorm -contains $_.TrimEnd('\') })
    $back = @($entries | Where-Object { $ownNorm -notcontains $_.TrimEnd('\') })
    $env:PSModulePath = (@($front) + @($back)) -join ';'
    Write-Verbose 'PSModulePath 中 pwsh 7 的目录原本排在 5.1 自带目录之前,已把 5.1 自带目录前置。'

    # 已经加载 7 版 Utility 的会话不会因排序自动恢复,需要重新导入
    if (-not (Get-Command Import-PowerShellDataFile -ErrorAction Ignore))
    {
        try
        {
            Import-Module Microsoft.PowerShell.Utility -Force -ErrorAction Stop
            Write-Verbose '已重新导入 Microsoft.PowerShell.Utility,恢复 5.1 自带命令。'
        }
        catch
        {
            Write-Verbose "重新导入 Microsoft.PowerShell.Utility 失败(清单读取已由内置解析兜底):$($_.Exception.Message)"
        }
    }
}

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
        [switch]$Force,
        # 显示每步耗时报告(默认关闭以保启动速度;`init -Force -Timing` 可直接看报告)
        [switch]$Timing,
        # 启动档位:Minimal 最轻/Fast 保留常用补全/Balanced 当前默认;省略时读 PsStartupTier(环境变量 > 用户配置 > 默认)
        [ValidateSet('Minimal', 'Fast', 'Balanced')]
        [string]$Tier = ''
    )

    # 显式 -Tier 优先于环境变量与配置文件；写入进程环境，供步骤内组件判断与子进程继承。
    if ($Tier) { $env:PsStartupTier = $Tier }

    # 计时从函数入口开始：配置读取/变量重载与步骤表分开统计，避免把准备阶段漏在总数外。
    $initStart = [datetime]::UtcNow
    # 使用临时环境$env:Psinit会引发副作用(子作用域的pwsh也会继承此变量),这里限制其作用域,使用普通变量(局部)
    #考虑到$profile和wt中的启动参数同时调用init,都是同一个作用域,不需要第二个作用域访问到此标记变量,因此使用普通变量即可(同一个会话内可以访问)
    if ($Force -or $null -eq $PsInit)
    {
        Write-Host 'initing...'
        Write-Verbose 'Init pwsh env...'
        # 首次初始化与"重跑已初始化会话"分流:只有后者需要重载变量 conf
        #(init -Force 是已初始化会话的重载路径,不叠加重载,保住启动基线)
        $reInit = $null -ne $PsInit
        # $env:PsInit = 'True' 
        # 从 pwsh 7 终端启动的宿主会让 5.1 继承 7 的模块路径,先修正顺序再读配置与导入模块
        Update-CxxuModulePathOrder
        # 用户配置文件先行(环境变量 > 配置文件 > 默认;缺文件静默跳过,见 Import-CxxuConfig)
        Import-CxxuConfig
        # 仓库模块文件比命令表缓存新时删缓存:插件每进程只建一次表(见 CxxuPredictor),
        # 这里只保证“之后启动的进程”不再读到旧表,当前会话未建表时首次 Tab 也会直接重建。
        Clear-PsCommandCacheIfStale
        if ($reInit)
        {
            # -Force 必须真重载变量 conf:步骤表唯一变量入口(Set-PsPrompt 内的
            # Update-PwshEnvIfNotYet -Mode core)受 $PsEnvMode 门控(>=core 即跳过),
            # 已初始化会话必被跳过,conf 改动刷不进当前会话。
            # 两连跑取并集:Core 名单(含 ConstantString) + 全量名单(VarSet3/GlobalConfig 等
            # 平时懒加载的部分);VarSet1/2 幂等重跑,预编译缓存命中,开销低。
            # VarSet1.conf 会把等级恒写 1,步骤尾恢复原等级,Env 级会话不被打回。
            $prevEnvMode = $global:PsEnvMode
            Update-PwshVars -Core
            Update-PwshVars
        }
    }
    else
    {

        Write-Verbose 'Init work loaded !'
        return
    }


    # 启动步骤表:直接调用(当前会话作用域),不要转字符串再 iex —— iex 慢且吞错误定位;
    # 进度条默认开(真机实测开销可忽略,用户 306ms 全链含进度条),开关见 $env:PsShowProgress,
    # 重定向下(无处渲染)自动关闭。
    # 档位决定核心步骤与可选组件的上限:Minimal 只留基础 PSReadLine + prompt,
    # Fast 再加 advanced PSReadLine + Argc/Git 补全,Balanced 保持原有全部步骤。
    $tierName = Get-CxxuStartupTier
    if ($env:PsStartupTier -and ($env:PsStartupTier -notmatch '^(?i:Minimal|Fast|Balanced)$'))
    {
        Write-Warning "未知的 PsStartupTier 值 '$env:PsStartupTier'，本次按 Balanced 处理。可用值：Minimal、Fast、Balanced。"
    }
    # Minimal 默认使用极简提示符;用户显式设置的 PsPrompt 优先。
    if ($tierName -eq 'Minimal' -and [string]::IsNullOrWhiteSpace($env:PsPrompt))
    {
        $env:PsPrompt = 'Simple'
    }
    # Fast/Minimal 默认不渲染启动进度条;用户显式设置的 PsShowProgress 优先。
    if (($tierName -in @('Minimal', 'Fast')) -and [string]::IsNullOrWhiteSpace($env:PsShowProgress))
    {
        $env:PsShowProgress = 'False'
    }
    $steps = @(Get-CxxuInitStepsForTier -Tier $tierName)

    # 步骤表构建完成后再置已初始化标记：前面任何一步失败时保留未初始化状态，允许重试；
    # 步骤表内部单步失败只记账不中断。
    $global:PsInit = $True
    $prepMs = [int]([datetime]::UtcNow - $initStart).TotalMilliseconds

    # 仅在要求时计时/报告(-Timing 或 -InformationAction Continue;`init -Force -Timing` 走前者)
    $needTiming = $Timing -or ($InformationPreference -eq 'Continue')
    $report = @()
    # 单步失败只记账不中断:历史上 PSReadLine 在重定向下抛 terminating error,
    # 曾导致后面 5 步静默被跳过(见 docs/Startup-Optimization.md §12);现在失败步骤
    # 记入 $global:PsInitStepErrors,最后统一 Warning 汇总,成功路径行为/耗时不变。
    # 进度条总开关(默认开):$env:PsShowProgress='False'/'0'/'No'/'Off' 关闭,
    # 未设置或其它值均为开;stdout 重定向时(agent/CI/管道,无处渲染)强制关闭。
    # 样式沿用历史原版:Classic 视图 + 一位小数百分比(用户偏爱,不要"优化"掉)。
    $consoleInteractive = try { -not [Console]::IsOutputRedirected } catch { $false }
    $showProgress = ($env:PsShowProgress -notmatch '^(False|0|No|Off)$') -and $consoleInteractive
    if ($showProgress -and ($PSVersionTable.PSVersion.Major -ge 7))
    {
        $PSStyle.Progress.View = 'Classic'
    }
    $global:PsInitStepErrors = @()
    $stepsStart = [datetime]::UtcNow
    for ($i = 0; $i -lt $steps.Count; $i++)
    {
        $step = $steps[$i]
        # MinPS 步骤在低版本下静默跳过(Verbose 留痕),不记失败:ArgumentCompletion/Startup/Pwsh/Json 明确留 7;
        # TerminalTools 的 Register-PsUxLazyLoad 已按版本分支,5.1 只装 Tab 桩
        if ($step.MinPS -and ($PSVersionTable.PSVersion.Major -lt $step.MinPS))
        {
            Write-Verbose "跳过 $($step.Name)(需 pwsh $($step.MinPS)+,当前 $($PSVersionTable.PSVersion))"
            continue
        }
        Write-Verbose "Loading $($step.Name)"
        if ($showProgress)
        {
            $Completed = [math]::Round($i / $steps.Count * 100, 1)
            Write-Progress -Activity 'Loading... ' -Id 0 -Status "$($step.Name) -> Processing: $Completed%" -PercentComplete $Completed
            Write-Information "Loading $($step.Name) "
        }
        $t0 = [datetime]::UtcNow
        try
        {
            & $step.Action
        }
        catch
        {
            $global:PsInitStepErrors += [PSCustomObject]@{
                Step  = $step.Name
                Error = $_.Exception.Message
            }
            Write-Verbose "步骤 $($step.Name) 失败(已跳过,继续后续): $($_.Exception.Message)"
        }
        if ($needTiming)
        {
            $report += [PSCustomObject]@{
                Command = $step.Name
                Time    = [int]([datetime]::UtcNow - $t0).TotalMilliseconds
            }
        }
    }

    $stepsMs = [int]([datetime]::UtcNow - $stepsStart).TotalMilliseconds

    # -Force 重载后恢复环境等级:VarSet1.conf 恒写 1,已到 Env 级的会话不被打回,
    # 免得后续第一个 Update-PwshEnvIfNotYet 调用再多跑一次全量补齐
    if ($reInit -and $prevEnvMode -gt $global:PsEnvMode)
    {
        Set-Variable -Name PsEnvMode -Value $prevEnvMode -Scope Global
    }

    if ($showProgress)
    {
        Write-Progress -Activity 'Loading...' -Completed
    }

    # 总耗时在打印报告与警告之前取：-Timing 的步骤表属于诊断输出，不计入 init 本身。
    $totalMs = [int]([datetime]::UtcNow - $initStart).TotalMilliseconds
    # 三段按定义严格加总：other 是步骤循环前后的计时、环境等级恢复与进度条收尾开销。
    $otherMs = [Math]::Max(0, $totalMs - $prepMs - $stepsMs)

    if ($global:PsInitStepErrors.Count)
    {
        Write-Warning ("init 有 $($global:PsInitStepErrors.Count) 个步骤失败(其余已继续执行): " +
            (($global:PsInitStepErrors | ForEach-Object { "$($_.Step): $($_.Error)" }) -join ' | '))
    }

    if ($needTiming -and $report.Count)
    {
        # 步骤表带占比与合计：一眼看出“步骤内部”谁最贵，也说明合计口径。
        $sumStepMs = [int](($report | Measure-Object -Property Time -Sum).Sum)
        $report = @($report | Sort-Object Time -Descending | ForEach-Object {
                $share = ''
                if ($sumStepMs -gt 0) { $share = '{0:P0}' -f ($_.Time / $sumStepMs) }
                [PSCustomObject]@{ Command = $_.Command; Time = $_.Time; Share = $share }
            })
        $report += [PSCustomObject]@{ Command = '步骤合计'; Time = $sumStepMs; Share = '100%' }
        $report | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
    }

    # 其他自定义绑定的任务🎈
    ## 加载时计算方案(耗费一定时间)
    # if(Test-CommandAvailability zoxide)
    # {

    #     Invoke-Expression (& { (zoxide init powershell | Out-String) })
    # }
    # if(Test-CommandAvailability uv)
    # {
    #     Invoke-Expression (& { uv generate-shell-completion powershell | Out-String })
    # }
    # if(Test-CommandAvailability ruff)
    # {
    #     Invoke-Expression (& { ruff generate-shell-completion powershell | Out-String })
    # }

    ## 缓存补全脚本方案(版本更新的情况下可能要清除缓存脚本文件重新生成)
    # zoxide
    # if(Test-CommandAvailability zoxide)
    # {
    #     $zoxideCompletionFile = "$HOME\.zoxide_completion.ps1"
    #     if (!(Test-Path $zoxideCompletionFile))
    #     {
    #         zoxide init powershell > $zoxideCompletionFile
    #     }
    #     . $zoxideCompletionFile
    # }

    # astral系列
    # 检查 uv 是否存在且是否有缓存，如果没有或过时则更新
    # if(Test-CommandAvailability uv)
    # {
    #     $uvCompletionFile = "$HOME\.uv_completion.ps1"
    #     if (!(Test-Path $uvCompletionFile))
    #     {
    #         uv generate-shell-completion powershell > $uvCompletionFile
    #     }
    #     . $uvCompletionFile
    #     # uvx
    #     $uvxCompletionFile = "$HOME\.uvx_completion.ps1"
    #     if(!(Test-Path $uvxCompletionFile))
    #     {
    #         uvx --generate-shell-completion powershell > $uvxCompletionFile
    #     }
    #     . $uvxCompletionFile
    # }
    # if(Test-CommandAvailability ruff)
    # {
    #     $ruffCompletionFile = "$HOME\.ruff_completion.ps1"

    #     if (!(Test-Path $ruffCompletionFile))
    #     {
    #         ruff generate-shell-completion powershell > $ruffCompletionFile
    #     }
    #     . $ruffCompletionFile
    # }

    # 小心conda(miniforge或miniconda)的初始化脚本,部分版本初始化脚本可能引起错误
    # 可以使用调试模式强制加载初始化操作: p -verbose -debug -force
    # if(Test-CommandAvailability conda)
    # {
    #     $condaCompletionFile = "$HOME\.conda_completion.ps1"
    #     if(!(Test-Path $condaCompletionFile))
    #     {

    #         conda 'shell.powershell' 'hook' > $condaCompletionFile
    #         # (& conda 'shell.powershell' 'hook') | Out-String | Invoke-Expression
    #     }
    #     . $condaCompletionFile
    # }
    # 耗时统计：主数字是 init 总耗时，括号内三段严格等于总耗时；末尾标注当前档位。
    Write-Host ("Environment Loading time: {0} ms (prep {1} + steps {2} + other {3}) [{4}]" -f $totalMs, $prepMs, $stepsMs, $otherMs, $tierName) -ForegroundColor Magenta
    # 清理竞争关系变量
    # $env:PsInit = $null
    # Remove-Variable $env:PsInit
}
function Test-StartupPerformance
{
    <#
    .SYNOPSIS
    自查 pwsh 启动性能:分段计时(裸启动/profile 税/init 合计+步骤表/体验件全载/prompt)并给结论。
    .DESCRIPTION
    每段都在全新 pwsh 进程里测(冷数字,排除本会话已摊销的解析成本);本机改动对照看 Startup-Optimization.md。
    -Simple 只测一次(或 -Repeat 次)带 profile 的新 pwsh 启动,几秒内出结果;-PassThru 返回结构化对象。
    耗时组成(参考值见 Startup-Optimization.md 的基线表,真机按比例):裸启动 + profile 税(conda 缓存 + init)
    + 首屏单发(predictor/zoxide);PSFzf/CxxuTab 转手势按需(首按 Ctrl+T/R、首次裸命令名 Tab 才装)。
    体验件全载使用 Register-PsUxLazyLoad -Now,包含手势组件,不是首屏 OnIdle 的实际耗时;
    argc/carapace 的首次参数补全加载另计。首屏单发也在主线程执行,冷缓存仍可能短暂阻塞输入。
    新进程继承当前 PsStartupTier;测其他档位前先设置 $env:PsStartupTier。
    .EXAMPLE
    Test-StartupPerformance
    .EXAMPLE
    Test-StartupPerformance -Repeat 3 -Detail
    .EXAMPLE
    $env:PsStartupTier='Fast'; Test-StartupPerformance -Simple
    .EXAMPLE
    Test-StartupPerformance -Simple
    .EXAMPLE
    Test-StartupPerformance -Simple -PassThru
    #>
    [CmdletBinding()]
    param(
        # 每段重复次数(默认 1;传 3 取中位数,压住机器抖动;代价是总耗时翻倍)
        [int]$Repeat = 1,
        # 加测 OnIdle 四片各自耗时(默认只测合计;排查"哪片最重"时开)
        [switch]$Detail,
        # 简单模式:只测新 pwsh 启动(带 profile),不做 bare/init 分段与步骤表
        [Alias('Quick')]
        [switch]$Simple,
        # 返回结构化对象;与 -Simple 连用时只输出对象,不打印表格
        [switch]$PassThru
    )
    # 嵌套 helper:与 Show-MemoryBar 内嵌套风格一致;顶层解析器看不见,不进 manifest
    function Get-MedianMs([scriptblock]$Probe, [int]$N)
    {
        $v = @(1..([Math]::Max(1, $N)) | ForEach-Object { & $Probe })
        $s = @($v | Sort-Object)
        # 偶数次取中间两个的平均，避免 -Repeat 2 时系统性偏向较大的那次。
        if (($s.Count % 2) -eq 0)
        {
            return [int](($s[$s.Count / 2 - 1] + $s[$s.Count / 2]) / 2)
        }
        return [int]$s[[int][Math]::Floor($s.Count / 2)]
    }
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh)
    {
        Write-Warning '没找到 pwsh(本工具在新进程里测 7 的启动链);5.1 会话可用 init -Timing 看步骤表。'
        return
    }
    if ($Repeat -lt 1) { $Repeat = 1 }
    if ($Simple)
    {
        $simpleRuns = [Math]::Max(1, $Repeat)
        $ms = Get-MedianMs { [int](Measure-Command { & $pwsh -NonInteractive -Command 'exit' *> $null }).TotalMilliseconds } $simpleRuns
        $result = [PSCustomObject]@{
            Mode    = 'Profile'
            Ms      = $ms
            Runs    = $simpleRuns
            Command = 'pwsh -NonInteractive -Command exit'
        }
        if ($PassThru) { return $result }
        Write-Host ("pwsh startup (profile, {0} run(s){1}): {2} ms" -f $simpleRuns, $(if ($simpleRuns -gt 1) { ', median' } else { '' }), $ms) -ForegroundColor Cyan
        return
    }
    Write-Host "分段计时中(新进程每段 $Repeat 次,约需 $((10 + 5 * $Repeat)) 秒)..." -ForegroundColor Cyan
    $null = & $pwsh -NoProfile -NonInteractive -Command 'exit' *> $null
    $bare = Get-MedianMs { [int](Measure-Command { & $pwsh -NoProfile -NonInteractive -Command 'exit' *> $null }).TotalMilliseconds } $Repeat
    $null = & $pwsh -NonInteractive -Command 'exit' *> $null
    $prof = Get-MedianMs { [int](Measure-Command { & $pwsh -NonInteractive -Command 'exit' *> $null }).TotalMilliseconds } $Repeat
    $probeInit = @'
Import-Module Init -ErrorAction Stop
[int](Measure-Command { init *> $null }).TotalMilliseconds
'@
    $tInit = Get-MedianMs { [int](& $pwsh -NoProfile -NonInteractive -Command $probeInit) } $Repeat
    $probeIdle = @'
Import-Module TerminalTools -ErrorAction Stop
[int](Measure-Command { Register-PsUxLazyLoad -Now *> $null }).TotalMilliseconds
'@
    $tIdle = Get-MedianMs { [int](& $pwsh -NoProfile -NonInteractive -Command $probeIdle) } $Repeat
    # profile 税 = bare 之外的全部启动开销；init 是它的子集，必须扣掉才能得到 conda/模块导入等其余部分。
    $profileTax = $prof - $bare
    $profileOther = [Math]::Max(0, $profileTax - $tInit)
    $rows = @(
        [PSCustomObject]@{ 段 = 'bare（裸启动基线）'; ms = $bare; 说明 = '不含 profile' },
        [PSCustomObject]@{ 段 = 'profile（完整启动）'; ms = $prof; 说明 = 'bare + profile 税' },
        [PSCustomObject]@{ 段 = 'profile 税'; ms = $profileTax; 说明 = 'profile - bare' },
        [PSCustomObject]@{ 段 = '  init 合计'; ms = $tInit; 说明 = 'profile 税的子集，不另外相加' },
        [PSCustomObject]@{ 段 = '  profile 其他'; ms = $profileOther; 说明 = 'profile 税 - init（conda/模块导入等）' },
        [PSCustomObject]@{ 段 = '体验件全载（-Now）'; ms = $tIdle; 说明 = '含 PSFzf/CxxuTab，不等于首屏 OnIdle；不计入 profile' }
    )
    $rows | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
    Write-Host '--- init -Timing 步骤表（另一次新进程，仅供占比；总量看上一行 init 合计） ---' -ForegroundColor Cyan
    & $pwsh -NoProfile -NonInteractive -Command 'Import-Module Init; init -Timing' 2>$null |
        Select-Object -Skip 1 | Where-Object { $_ -notmatch 'Environment Loading time' } | Write-Host
    if ($Detail)
    {
        Write-Host '--- -Now 全载四件各自耗时(与 Register-PsUxLazyLoad -Now 同源,改动两边同步) ---' -ForegroundColor Cyan
        $probeDetail = @'
$r = @()
$r += 'PSFzf:' + [int](Measure-Command { if (Get-Module -ListAvailable PSFzf) { Import-Module PSFzf -Global; Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' } }).TotalMilliseconds
$dll = $null; $ptr = Join-Path (Join-Path $HOME '.cxxu/bin') 'current.txt'
if (Test-Path -LiteralPath $ptr) { $h = (Get-Content -LiteralPath $ptr | Select-Object -First 1).Trim(); $c = Join-Path (Join-Path (Join-Path $HOME '.cxxu') 'bin') $h 'CxxuPredictor.dll'; if (Test-Path -LiteralPath $c) { $dll = $c } }
$r += 'Predictor:' + $(if ($dll) { [int](Measure-Command { Import-Module $dll -Global }).TotalMilliseconds } else { -1 })
$r += 'CxxuTab:' + [int](Measure-Command { Import-Module CxxuTab -Global -ErrorAction SilentlyContinue }).TotalMilliseconds
$zc = Join-Path $HOME '.zoxide_init_cache.ps1'
$r += 'zoxide:' + $(if (Test-Path -LiteralPath $zc) { [int](Measure-Command { . $zc | Out-Null }).TotalMilliseconds } else { -1 })
$r -join ' '
'@
        Write-Host (& $pwsh -NoProfile -NonInteractive -Command $probeDetail)
        Write-Host '(-1=本机缺件,已跳过)'
    }
    Write-Host '--- prompt 均值(5 次) ---' -ForegroundColor Cyan
    $promptLine = & $pwsh -NoProfile -NonInteractive -Command 'Test-PromptDelay 5' 2>$null | Select-Object -Last 1
    Write-Host $promptLine
    $promptSec = 0
    if ($promptLine -match '([\d.]+)') { $promptSec = [double]$Matches[1] }
    Write-Host '--- 开关与延迟加载(本会话) ---' -ForegroundColor Cyan
    # 5.1 无 ??,不用;单发模式无队列,$null 直接 .Count 会吞显示,先归零
    $uxErrs = 0
    if ($global:PsUxLoadErrors) { $uxErrs = $global:PsUxLoadErrors.Count }
    Write-Host ("PsFzf=$env:PsFzf PsZoxide=$env:PsZoxide PsTab=$env:PsTab PsPredictor=$env:PsPredictor | " +
        "OnIdle已注册=$global:PsUxOnIdleRegistered(单发,触发即摘) 加载错误=$uxErrs")
    Write-Host '--- 结论 ---' -ForegroundColor Cyan
    $verdicts = @()
    if (($prof - $bare) -gt 1200) { $verdicts += 'profile 税偏高:查 conda 缓存是否命中(~/.conda_hook_cache.ps1 时间戳应不早于 conda.exe)与 profile 杂项' }
    if ($tInit -gt 800) { $verdicts += 'init 偏高:看上面步骤表头两名(常见 Set-PsPrompt/PSReadLine 两项)' }
    if ($tIdle -gt 800) { $verdicts += '体验件全载偏高:该值包含 PSFzf/CxxuTab 的首用成本;实际首屏单发只加载 predictor + zoxide,需在交互终端分别核验' }
    if ($promptSec -gt 0.3) { $verdicts += 'prompt 偏高:换 Set-PsPrompt -version Simple 或给主题做减法(见 Startup-Optimization.md §5)' }
    if (-not $verdicts.Count) { $verdicts += '启动各段未超过诊断阈值;首次 Tab 与首屏输入延迟需在交互终端另行核验' }
    $verdicts | ForEach-Object { Write-Host "- $_" }
    if ($PassThru)
    {
        # 完整模式仍会打印上面的报告；-PassThru 额外返回一份便于脚本消费的数据。
        return [PSCustomObject]@{
            Mode            = 'Full'
            BareMs          = $bare
            ProfileMs       = $prof
            ProfileTaxMs    = $profileTax
            InitMs          = $tInit
            ProfileOtherMs  = $profileOther
            IdleMs          = $tIdle
            UxFullLoadMs    = $tIdle
            PromptSeconds   = [math]::Round($promptSec, 3)
        }
    }
}
function p
{
    <#
    .SYNOPSIS
    启动一个新的 pwsh 会话。
    .DESCRIPTION
    只负责新进程，不刷新当前会话：新 pwsh 读取 profile 后会执行 init。
    刷新当前会话的配置用 init -Force；冷启动耗时分段用 Test-StartupPerformance；
    当前会话分步耗时用 init -Force -Timing。
    .EXAMPLE
    p
    #>
    [CmdletBinding()]
    param()
    pwsh -NoLogo
}
function Set-CommonInit
{
    [CmdletBinding()]
    param(
        
    )
        
    Update-PwshEnv -Verbose:$VerbosePreference
    # 注:此处曾调用不存在的 Start-CoreInit(调用即报错),已删除;
    # Update-PwshEnv 已覆盖变量+别名+prompt,"core 初始化"即它
    # 提示prompt当前的环境变量导入等级(模式),修改PsEnvMode
    #使用set-variable 语句来修改变量,而不是直接使用# $PSEnvMode = 1 或$Global:PSEnvMode = 1 的方式修改变量,可以避免IDE不当的警告提示(定义而未使用)
    Set-Variable -Name PsEnvMode -Value 3 -Scope Global
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
function Start-MemoryInfoInit
{

    $OS = Get-CimInstance -ClassName Win32_OperatingSystem
    $env:cachedTotalMemory = $OS.TotalVisibleMemorySize / 1MB
    $env:cachedFreeMemory = $OS.FreePhysicalMemory / 1MB
}
function Import-TerminalIcons
{
    [cmdletbinding()]
    param()
    <#     
    # if (!(Get-Module -ListAvailable -Name Terminal-Icons))
    # {
    #     Write-Host 'Terminal-Icons module not Found!'
    #     $r = Read-Host -Prompt 'Try to install it ? (estimate 5-10s) [y/n]'
    #     if ($r.ToUpper() -eq 'Y')
    #     {

    #         Install-Module Terminal-Icons -Force
            
    #     }
    #     else
    #     {
    #         # 用户拒绝安装，直接退出
    #         return
    #     }
    # } 
#>
    Confirm-ModuleInstalled -ModuleName Terminal-Icons -Install
    # 导入模块（这里确保已经安装上了模块）
    Import-Module Terminal-Icons -ErrorAction Ignore
}
function Set-PSReadLinesCommon
{
    [cmdletbinding()]
    param()
    Write-Verbose 'loading psReadLines & keyHandler!(common)'
    # Set-PSReadLineOption -Colors @{"inlineprediction"="#51ed9c"}#green

    #modify the color of selection:
    # 菜单补全选中行用反显(ESC[7m):浅色/深色主题各自反转前景/背景,对比度由主题保证;
    # 固定前景色会被候选自带的 ANSI 覆盖(argc-completions 的描述就是),不要改回单色。
    try { Set-PSReadLineOption -Colors @{'selection' = ([char]27 + '[7m') } }
    catch { Write-Verbose "跳过 selection 反显配色: $($_.Exception.Message)" }
  
    # PSColor to color the folders(in the ls command excute result.)
    # Import-Module Get-ChildItemColor

    <#  set tab auto completion(optional item)
    #set tab auto completion(optional item)
    #(the command line will try to offer you a list(candidated) when you press the `tab`key
    #of course,if the current path have only one or even none can match what you want to match,it will just try to complete the current object name
    #>
    Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function ForwardWord
    Set-PSReadLineKeyHandler -Key 'Tab' -Function MenuComplete # Tab 用菜单补全（与 Intellisense 一致）
    # Tab 已重置为原生 MenuComplete，之前装的 argc/carapace 懒加载桩随之失效；
    # 清标记，让后续组件步骤重新装桩（init -Force 重跑时也走这条）。
    $global:PsArgcTabStub = $false
    $global:PsCarapaceTabStub = $false
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

function Set-PSReadLinesAdvanced
{
    [cmdletbinding()]
    param()
    <# beautify the powershell interactive interface  #>
    # modify the color of the inlinePrediction:
    Write-Verbose ('loading psReadLines & keyHandler!(advanced)' + "`n")
    # Import-Module CompletionPredictor -Verbose #-Verbose:$VerbosePreference

    # 预测源与列表视图依赖可写控制台(VT/控制台句柄):
    # - 交互场景(WT/终端直连):照常应用,行为与以前完全一致;
    # - 重定向场景(agent/CI/计划任务/`pwsh -c` 管道):没有行编辑,跳过此二项,
    #   否则两条 terminating error 会打断 init 后续步骤(步骤表无 try/catch)。
    # 注意:[Environment]::UserInteractive 在重定向下仍为 True,不可用;
    # 只有 [Console]::IsOutputRedirected 能区分。
    $consoleInteractive = try { -not [Console]::IsOutputRedirected } catch { $false }
    # PSReadLine 版本决定可用的预测源与视图:
    # - 插件预测源(HistoryAndPlugin/Plugin)要求 PowerShell 7.2+;
    # - 5.1 升级到 PSReadLine 2.2.6+ 后可用 History,但插件源仍不可用;
    # - 2.0 没有预测参数,整段跳过,避免把 terminating error 当版本不兼容。
    $rlVer = try { (Get-Module PSReadLine | Sort-Object Version -Descending | Select-Object -First 1).Version } catch { $null }
    if ($consoleInteractive)
    {
        try
        {
            if (($PSVersionTable.PSVersion -ge [version]'7.2') -and ($null -ne $rlVer) -and ($rlVer -ge [version]'2.2.2'))
            {
                # 插件必须显式 import 才会向 ListView 供稿(装了不等于加载了);缺失时静默降级为纯历史
                # -Global:函数内 import 默认嵌套(Get-Module 列不出),强制顶层
                Import-Module CompletionPredictor -Global -ErrorAction SilentlyContinue
                Set-PSReadLineOption -PredictionSource HistoryAndPlugin # 设置预测文本来源为历史和插件
            }
            elseif (($null -ne $rlVer) -and ($rlVer -ge [version]'2.1'))
            {
                Set-PSReadLineOption -PredictionSource History # 5.1 只能用历史预测
            }

            if (($null -ne $rlVer) -and ($rlVer -ge [version]'2.2.2'))
            {
                # 窄窗口(<50 宽或 <5 高)PSReadLine 会刷 ListView WARNING:事先按尺寸分流,窄用内联
                # (取不到尺寸按宽处理,行为与以前一致;窗口拉大后重跑本函数即按新尺寸重选)
                $wideEnough = try { ([Console]::WindowWidth -ge 50) -and ([Console]::WindowHeight -ge 5) } catch { $true }
                if ($wideEnough)
                {
                    Set-PSReadLineOption -PredictionViewStyle ListView -BellStyle None  #使用视图列表显示预测后选
                }
                else
                {
                    Set-PSReadLineOption -PredictionViewStyle InlineView -BellStyle None
                    Write-Verbose '窗口过窄(<50x5),预测视图用内联(避开 ListView 警告);拉大窗口后重跑 Set-PSReadLinesAdvanced 切回列表'
                }
            }
        }
        catch
        {
            Write-Verbose "跳过 PSReadLine 预测视图(当前控制台不支持): $($_.Exception.Message)"
        }
    }
    else
    {
        Write-Verbose 'stdout 已重定向,跳过 PSReadLine 预测源/列表视图(无交互行编辑)'
    }
    # listView列表设置
    Set-PSReadLineOption -MaximumHistoryCount 3000  # 可选：增大历史记录总数
    # HistoryNoDuplicates 需 PSReadLine 2.1+;5.1 自带 2.0 无此参数,版本不足跳过
    if (($null -ne $rlVer) -and ($rlVer -ge [version]'2.1'))
    {
        Set-PSReadLineOption -HistoryNoDuplicates  # 历史不存重复命令(防 ConsoleHost_history.txt 无限膨胀,Ctl+R 读全文件,3 万行是它慢的主因)
    }
    Set-PSReadLineOption -CompletionQueryItems 100  # 可选：增大自动完成候选列表数量
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd

    # Set-PSReadLineOption -PredictionViewStyle MenuView
    

    # 设置建议窗口高度为 30 行

    <# set colors #>
    # inlineprediction 配色需 PSReadLine 2.1+;低版本(5.1 自带 2.0)未知键会报错,版本不足跳过
    if (($null -ne $rlVer) -and ($rlVer -ge [version]'2.1'))
    {
        try { Set-PSReadLineOption -Colors @{'inlineprediction' = '#d0d0cb' } -ErrorAction Stop } catch { Write-Verbose "跳过 inlineprediction 配色: $($_.Exception.Message)" }#grayLight(grayDark #babbb4)
    }
    <# suggestion list #>
    # Set-PSReadLineOption -PredictionViewStyle ListView
    # Set-PSReadLineOption -EditMode Windows
}

function Get-CxxuArgcExecutable
{
    # 定位 argc 可执行文件(不导出):仓库 bin 优先,其次 PATH(Homebrew 等系统安装)。
    param([string]$Root)
    if ($Root)
    {
        $local = Join-Path (Join-Path $Root 'bin') $script:ArgcPlatform.Executable
        if (Test-Path -LiteralPath $local) { return $local }
    }
    $cmd = Get-Command $script:ArgcPlatform.Executable -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($cmd) { return [string]$cmd.Source }
    return $null
}

function Test-CxxuArgcCompletionsRoot
{
    # 仓库可用 = 有 completions 目录且 argc 可定位(仓库 bin 或 PATH);(不导出)
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Path 'completions'))) { return $false }
    return [bool](Get-CxxuArgcExecutable -Root $Path)
}

function Get-ArgcCompletionsRoot
{
    # 仓库定位顺序:环境变量 > 用户目录 > 本机固定仓库。
    # C:\repos\argc-completions 只在 Windows 探测:非 Windows 没有 C 盘,
    # 对 'C:\...' 调 Join-Path 会抛 "Cannot find drive",成为 init 启动报错来源。
    $root = $env:ARGC_COMPLETIONS_ROOT
    if (-not $root)
    {
        $candidates = @(
            (Join-Path $HOME 'argc-completions')
            (Join-Path (Join-Path $HOME 'repos') 'argc-completions')
        )
        if (($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true))
        {
            $candidates += 'C:\repos\argc-completions'
        }
        foreach ($cand in $candidates)
        {
            if (Test-CxxuArgcCompletionsRoot -Path $cand) { $root = $cand; break }
        }
    }
    if (Test-CxxuArgcCompletionsRoot -Path $root) { return $root }
    return $null
}

function Set-ArgcCompletionsEnvironment
{
    # 环境变量按平台拼:Windows 用 ';' 与 completions\windows,
    # macOS 用 ':' 与 completions/macos,Linux 用 ':' 与 completions/linux。
    param([string]$Root)
    $env:ARGC_COMPLETIONS_ROOT = $Root
    $completions = Join-Path $Root 'completions'
    $platformDir = Join-Path $completions $script:ArgcPlatform.CompletionDir
    $env:ARGC_COMPLETIONS_PATH = ($platformDir + [IO.Path]::PathSeparator + $completions)
    $bin = Join-Path $Root 'bin'
    if (($env:PATH -split [IO.Path]::PathSeparator) -notcontains $bin)
    {
        $env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
    }
}

function Test-CxxuNativeArgumentContext
{
    # 只在原生命令的参数位置加载 CLI 补全,命令名、PowerShell 参数和重定向路径不承担该成本。
    param([string]$Line, [int]$Cursor)
    if ([string]::IsNullOrWhiteSpace($Line) -or $Cursor -lt 0 -or $Cursor -gt $Line.Length) { return $false }
    $lexemes = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$lexemes, [ref]$errors)
    $command = $null
    foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
    {
        if (-not $node.CommandElements.Count -or $node.Extent.StartOffset -gt $Cursor) { continue }
        # AST 不包含末尾空格;允许命令后的空白,但不能跨越管道或分号选择上一条命令。
        if ($node.Extent.EndOffset -lt $Cursor -and
            -not [string]::IsNullOrWhiteSpace($Line.Substring($node.Extent.EndOffset, $Cursor - $node.Extent.EndOffset))) { continue }
        if (-not $command -or $node.Extent.StartOffset -gt $command.Extent.StartOffset) { $command = $node }
    }
    if (-not $command -or $Cursor -le $command.CommandElements[0].Extent.EndOffset) { return $false }
    $argument = $false
    $previousEnd = $command.CommandElements[0].Extent.EndOffset
    foreach ($element in $command.CommandElements | Select-Object -Skip 1)
    {
        if ($element.Extent.StartOffset -le $Cursor -and $element.Extent.EndOffset -ge $Cursor) { $argument = $true; break }
        if ($element.Extent.EndOffset -lt $Cursor) { $previousEnd = $element.Extent.EndOffset }
    }
    if (-not $argument -and -not [string]::IsNullOrWhiteSpace($Line.Substring($previousEnd, $Cursor - $previousEnd))) { return $false }
    $name = $command.GetCommandName()
    # 动态命令与尚不可发现的命令保留加载入口,避免破坏变量调用或工具提供的静态候选。
    if (-not $name) { return $true }
    $info = Get-Command -Name $name -ListImported -ErrorAction Ignore | Select-Object -First 1
    if ($info -and $info.CommandType -eq 'Alias') { $info = $info.ResolvedCommand }
    return (-not $info -or $info.CommandType -in 'Application', 'ExternalScript')
}

function Register-CxxuTabStub
{
    # 安装统一的 Tab 桩:按需加载 carapace/argc,并处理 5.1 的 - 开头词。
    # 5.1 的补全引擎不会把 - 开头的词交给 Native 补全器(6.0 才修),
    # 先在词首临时插一个零宽字符(引擎当作普通词),MenuComplete 返回后再删掉;
    # 选中候选时该字符随整个词被替换,不会残留。只对 argc/carapace 注册过的
    # 应用命令生效,cmdlet/函数的参数补全仍走引擎原生逻辑(不能被破坏)。
    # 每次 init 都重装:Set-PSReadLinesCommon 会把 Tab 重置成 MenuComplete。
    Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
        $needArgc = ($env:PsArgc -notmatch '^(False|0|No|Off)$') -and
            (-not $global:PsArgcLoaded) -and (-not $global:PsArgcUnavailable)
        if ($global:PsCarapacePending -or $needArgc)
        {
            $line = ''
            $cursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if (Test-CxxuNativeArgumentContext -Line $line -Cursor $cursor)
            {
                if ($global:PsCarapacePending) { Initialize-Carapace }
                if ($needArgc) { Initialize-ArgcCompletions }
            }
        }

        $sentinel = [char]0x200B
        $sentinelIndex = -1
        $cursor = 0
        $carapaceActive = (-not [string]::IsNullOrWhiteSpace($env:PsCarapace)) -and
            ($env:PsCarapace -notmatch '^(False|0|No|Off)$')
        if (($PSVersionTable.PSVersion.Major -lt 6) -and
            ($global:PsArgcScripts -or ($carapaceActive -and $global:PsCarapaceScripts)))
        {
            $line = ''
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ($cursor -gt 0)
            {
                $start = $cursor
                while ($start -gt 0 -and -not [char]::IsWhiteSpace($line[$start - 1])) { $start-- }
                if (($start -lt $cursor) -and ($line[$start] -eq '-'))
                {
                    $cmdName = $null
                    try
                    {
                        $astTokens = $null
                        $astErrors = $null
                        $ast = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$astTokens, [ref]$astErrors)
                        $cmdAst = $ast.Find({
                            param($node)
                            ($node -is [System.Management.Automation.Language.CommandAst]) -and
                            ($node.Extent.StartOffset -le $cursor) -and
                            ($node.Extent.EndOffset -ge $cursor)
                        }, $true)
                        if ($cmdAst) { $cmdName = $cmdAst.GetCommandName() }
                    }
                    catch { }
                    $isCompletionCommand = $false
                    if ($cmdName)
                    {
                        $name = [string]$cmdName
                        $baseName = [IO.Path]::GetFileNameWithoutExtension($name)
                        if ($global:PsArgcScripts)
                        {
                            $isCompletionCommand = $global:PsArgcScripts.ContainsKey($name) -or
                                $global:PsArgcScripts.ContainsKey($baseName)
                        }
                        if (-not $isCompletionCommand -and $carapaceActive -and $global:PsCarapaceScripts)
                        {
                            $isCompletionCommand = $global:PsCarapaceScripts.ContainsKey($name) -or
                                $global:PsCarapaceScripts.ContainsKey($baseName)
                        }
                    }
                    if ($isCompletionCommand)
                    {
                        $sentinelIndex = $start
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($start)
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert([string]$sentinel)
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
                    }
                }
            }
        }

        try
        {
            [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete()
        }
        finally
        {
            if ($sentinelIndex -ge 0)
            {
                try
                {
                    $line = ''
                    $nowCursor = 0
                    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$nowCursor)
                    $idx = $line.IndexOf($sentinel)
                    if ($idx -ge 0)
                    {
                        $newPos = if ($nowCursor -gt $idx) { $nowCursor - 1 } else { $nowCursor }
                        [Microsoft.PowerShell.PSConsoleReadLine]::Delete($idx, 1)
                        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($newPos)
                    }
                }
                catch { }
            }
        }
    }
    $global:PsArgcTabStub = $true
    $global:PsCarapaceTabStub = $true
}

function Set-ArgcCompletions
{
    <#
    .SYNOPSIS
    启用 argc-completions(懒加载:首次外部 CLI 参数补全 才注册,启动仅作轻量准备)。
    .DESCRIPTION
    只做轻量准备(定位仓库、设 ARGC_COMPLETIONS_ROOT/PATH、PATH 前置)并装 Tab 桩;
    真正注册 845+ 个命令的补全推迟到第一次按 Tab。仓库定位顺序:
    ARGC_COMPLETIONS_ROOT > ~/argc-completions > ~/repos/argc-completions
    > C:\repos\argc-completions(仅 Windows)。仓库判定要求有 completions 目录,
    argc 可执行文件可来自仓库 bin 或 PATH(macOS/Linux 用系统安装的 argc)。
    关闭:$env:PsArgc='False'/'0'/'No'/'Off'(逐次判定,无需重载);关闭时
    不再设置 ARGC_COMPLETIONS_ROOT/PATH，也不装 Tab 桩；后续 Register 的 completer
    直接返回空,不影响 PowerShell 原生补全。
    .EXAMPLE
    Set-ArgcCompletions
    .EXAMPLE
    Initialize-ArgcCompletions -Force   # 更新补全仓库后重新注册
    #>
    [CmdletBinding()]
    param()

    # 关闭时不改 ARGC_COMPLETIONS_ROOT/PATH，也不装 Tab 桩；需要时再打开并 init -Force。
    if ($env:PsArgc -match '^(False|0|No|Off)$') { return }

    $root = Get-ArgcCompletionsRoot
    if (-not $root)
    {
        Write-Verbose 'argc-completions 未找到(需 completions 目录 + 可用的 argc),跳过'
        return
    }
    Set-ArgcCompletionsEnvironment -Root $root

    # 每次 init 都重装(Set-PSReadLinesCommon 会把 Tab 重置成 MenuComplete;
    # init -Force 重跑时不能因为全局标记而跳过)
    try
    {
        Register-CxxuTabStub
        Write-Verbose 'argc-completions: 已装 Tab 懒加载桩'
    }
    catch
    {
        Write-Verbose "argc-completions: 安装 Tab 桩失败,跳过: $($_.Exception.Message)"
    }
}

function Invoke-CxxuArgcCompgen
{
    # 读取 argc --argc-compgen 的输出(不导出)。
    # argc 固定输出 UTF-8,而默认 [Console]::OutputEncoding 是系统代码页(中文 Windows
    # 为 936),直接 & 会把中文文件名解成乱码;这里用 ProcessStartInfo 固定 UTF-8。
    # 5.1 没有 ArgumentList,手工引用参数,空字符串仍按一个参数位置传给 argc。
    param([string]$Executable, [string[]]$Arguments)
    try
    {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Executable
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        # 原生命令按 PowerShell 当前位置执行(Set-Location 不会改 OS 工作目录)。
        try { $psi.WorkingDirectory = (Get-Location).ProviderPath } catch { }
        if ($PSVersionTable.PSVersion.Major -ge 6)
        {
            foreach ($arg in $Arguments) { $psi.ArgumentList.Add($arg) }
        }
        else
        {
            $quoted = foreach ($arg in $Arguments)
            {
                if ($arg.Length -eq 0) { '""'; continue }
                if ($arg -notmatch '[\s"]') { $arg; continue }
                $escaped = [regex]::Replace($arg, '(\\*)"', '$1$1\"')
                $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
                '"' + $escaped + '"'
            }
            $psi.Arguments = $quoted -join ' '
        }
        $process = [System.Diagnostics.Process]::Start($psi)
        # stderr 异步读完,避免 argc 报错内容占满管道导致死锁。
        $errTask = $process.StandardError.ReadToEndAsync()
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        $null = $errTask.Result
        return $output
    }
    catch
    {
        # 补全失败按无候选处理,不把异常抛给 Tab 管线。
        return ''
    }
}

function Initialize-ArgcCompletions
{
    <#
    .SYNOPSIS
    注册 argc-completions 的原生参数补全(幂等;首次外部 CLI 参数补全 由桩自动调用)。
    .DESCRIPTION
    描述文本去掉 argc 自带的 ANSI,改由 PSReadLine 的 Selection(反显)统一着色,
    这样菜单选中行在浅色/深色主题下都有完整、可读的高亮。协议取自
    argc --argc-completions 生成的 completer(argc 1.24),仅移除颜色与加上 PsArgc 开关。
    git-completion 模块由 init 挂载时跳过 git/gitk(同名 completer 后注册者胜出,argc 首个
    Tab 才注册,不跳过会顶掉先注册的 git-completion)。
    #>
    [CmdletBinding()]
    param([switch]$Force)

    if ($global:PsArgcLoaded -and -not $Force) { return }

    $root = Get-ArgcCompletionsRoot
    if (-not $root)
    {
        $global:PsArgcUnavailable = $true
        return
    }
    Set-ArgcCompletionsEnvironment -Root $root
    $argcExe = Get-CxxuArgcExecutable -Root $root
    if (-not $argcExe)
    {
        $global:PsArgcUnavailable = $true
        return
    }

    $dirs = @((Join-Path $root 'completions'))
    $platformDir = Join-Path $dirs[0] $script:ArgcPlatform.CompletionDir
    if (Test-Path -LiteralPath $platformDir) { $dirs += $platformDir }
    $scripts = @(Get-ChildItem -File -Path $dirs -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName })
    # argc 自身也注册(与上游生成器一致;无专用脚本时由引擎回退路径补全)
    $scripts = @('argc') + @($scripts)
    $scripts = @($scripts | Select-Object -Unique)
    # git-completion 或 carapace 负责 git/gitk 时把它们从 argc 名单里去掉:三者都注册同名
    # Native completer,后注册者覆盖先注册者,而 argc 首次外部 CLI 参数补全 才注册,会顶掉先注册的来源。
    # 判定看 Register-GitCompletion 置的 $global:PsGitCompletion、carapace 懒加载桩置的
    # $global:PsCarapaceGit,以及"模块已导入"(init 只注册 completer,首次补全才 Import-Module);
    # 都没有时保留 argc 自己的 git 补全。
    # 来源明确选 Argc 时，即使其他来源已加载也让 argc 接管 git/gitk（后注册者胜出），
    # 供 Set-GitCompletionSource Argc 在当前会话直接切换。
    if ((Get-CxxuGitCompletionSource) -ne 'Argc' -and
        ($global:PsGitCompletion -or $global:PsCarapaceGit -or (Get-Module git-completion -ErrorAction SilentlyContinue)))
    {
        $scripts = @($scripts | Where-Object { $_ -notin 'git', 'gitk' })
    }
    if (-not $scripts.Count)
    {
        $global:PsArgcUnavailable = $true
        return
    }

    # 闭包捕获函数体,避免 completer 在调用方作用域解析不到模块私有函数。
    $argcRunner = ${function:Invoke-CxxuArgcCompgen}
    $completer = {
        param($wordToComplete, $commandAst, $cursorPosition)
        if ($env:PsArgc -match '^(False|0|No|Off)$') { return }
        # 5.1 的 Tab 桩会在词首插零宽字符,查询前去掉
        $zw = [string][char]0x200B
        $words = @($commandAst.CommandElements | Where-Object { $_.Extent.StartOffset -lt $cursorPosition } | ForEach-Object {
            $word = $_.ToString()
            if ($word.Length -gt 2)
            {
                if (($word.StartsWith('"') -and $word.EndsWith('"')) -or ($word.StartsWith("'") -and $word.EndsWith("'")))
                {
                    $word = $word.Substring(1, $word.Length - 2)
                }
            }
            return $word.Replace($zw, '')
        })
        $emptyS = ''
        $lastElemIndex = -1
        if ($words.Count -lt $commandAst.CommandElements.Count) { $lastElemIndex = $words.Count - 1 }
        if ($commandAst.CommandElements[$lastElemIndex].Extent.EndOffset -lt $cursorPosition) { $words += $emptyS }
        # 走 .NET Process 固定按 UTF-8 读取 argc 输出:默认控制台代码页(中文 Windows
        # 为 936)会把中文文件名解成乱码。参数用 ArgumentList / 手工引用保留空字符串位置。
        $lines = & $argcRunner $argcExe (@('--argc-compgen', 'powershell', $emptyS) + $words)
        foreach ($line in ($lines -split "`n"))
        {
            $line = $line.TrimEnd("`r")
            if (-not $line) { continue }
            $parts = $line -split "`t"
            if ($parts.Count -lt 3) { continue }
            $value = if ($parts[1] -eq '1') { $parts[0] + ' ' } else { $parts[0] }
            # 不带 ANSI:选中行由 PSReadLine 的 Selection 统一反显
            $text = if ($parts.Count -ge 4 -and $parts[3]) { $parts[2] + ' (' + $parts[3] + ')' } else { $parts[2] }
            [System.Management.Automation.CompletionResult]::new($value, $text, [System.Management.Automation.CompletionResultType]::ParameterValue, ' ')
        }
    }.GetNewClosure()

    try
    {
        Register-ArgumentCompleter -Native -ScriptBlock $completer -CommandName $scripts
        # 5.1 的 Tab 桩靠它判断该不该补 - 开头的参数(只处理应用命令)
        $global:PsArgcScripts = @{}
        foreach ($scriptName in $scripts) { $global:PsArgcScripts[$scriptName] = $true }
        $global:PsArgcLoaded = $true
        $global:PsArgcUnavailable = $false
        # argc 名单含 git 时它最后注册、覆盖其他来源；不含时不动上一来源的标记。
        if ($scripts -contains 'git') { $global:PsGitCompletionActive = 'Argc' }
        Write-Verbose "argc-completions: 已注册 $($scripts.Count) 个命令"
    }
    catch
    {
        $global:PsArgcUnavailable = $true
        Write-Verbose "argc-completions: 注册失败: $($_.Exception.Message)"
    }
}

function Test-CxxuGitCompletionInstalled
{
    # 静态探测 PSModulePath，不调用 Get-Module -ListAvailable（冷启动约省 140ms）。
    return [bool](@($env:PSModulePath -split [IO.Path]::PathSeparator |
            Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'git-completion')) }).Count)
}

function Get-CxxuGitCompletionSource
{
    # 解析 git/gitk 补全来源：PsGitCompletionSource 优先；未设置时沿用 PsGitCompletion 旧语义。
    $raw = [string]$env:PsGitCompletionSource
    if ([string]::IsNullOrWhiteSpace($raw))
    {
        if ($env:PsGitCompletion -match '^(False|0|No|Off)$') { return 'Argc' }
        if (Test-CxxuGitCompletionInstalled) { return 'GitCompletion' }
        return 'Argc'
    }
    switch -Regex ($raw.Trim())
    {
        '^(?i:Auto)$'
        {
            if (Test-CxxuGitCompletionInstalled) { return 'GitCompletion' }
            # 没有 git-completion 时优先 carapace；argc 的 git 补全缺 --cached/--staged 等选项，只作最后兜底。
            if (-not [string]::IsNullOrWhiteSpace($env:PsCarapace) -and $env:PsCarapace -notmatch '^(False|0|No|Off)$') { return 'Carapace' }
            return 'Argc'
        }
        '^(?i:GitCompletion)$'
        {
            # 组件级禁用优先：Disable-CxxuComponent GitCompletion 不应被来源键抵消。
            if ($env:PsGitCompletion -match '^(False|0|No|Off)$') { return 'Argc' }
            return 'GitCompletion'
        }
        '^(?i:Carapace)$'
        {
            # carapace 未启用时按可用来源回落：git-completion 选项更全，优先；
            # 组件被显式关闭（PsGitCompletion=False）或模块缺失时才用 argc。
            if ([string]::IsNullOrWhiteSpace($env:PsCarapace) -or $env:PsCarapace -match '^(False|0|No|Off)$')
            {
                if ($env:PsGitCompletion -notmatch '^(False|0|No|Off)$' -and (Test-CxxuGitCompletionInstalled)) { return 'GitCompletion' }
                return 'Argc'
            }
            return 'Carapace'
        }
        '^(?i:Argc)$' { return 'Argc' }
        default
        {
            Write-Warning "未知 PsGitCompletionSource=$raw；按 Auto 处理。"
            if (Test-CxxuGitCompletionInstalled) { return 'GitCompletion' }
            if (-not [string]::IsNullOrWhiteSpace($env:PsCarapace) -and $env:PsCarapace -notmatch '^(False|0|No|Off)$') { return 'Carapace' }
            return 'Argc'
        }
    }
}

function Set-CarapaceCompletionOptions
{
    # 计算 carapace 的排除项与 git 归属，只写环境变量和全局标记，不加载补全脚本。
    $source = Get-CxxuGitCompletionSource
    $global:PsCarapaceGit = $false
    # 配置键优先；未配置时沿用已有的 CARAPACE_EXCLUDES，避免覆盖用户自定义的慢命令排除项。
    $baseExcludes = [string]$env:PsCarapaceExcludes
    if ([string]::IsNullOrWhiteSpace($baseExcludes)) { $baseExcludes = [string]$env:CARAPACE_EXCLUDES }
    $excludes = @($baseExcludes -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($source -eq 'Carapace')
    {
        # 来源优先：即使 PsCarapaceExcludes 写了 git/gitk，也不让 carapace 让出。
        $excludes = @($excludes | Where-Object { $_ -notmatch '^(?i:git|gitk)$' })
        $global:PsCarapaceGit = $true
    }
    else
    {
        foreach ($name in @('git', 'gitk'))
        {
            if (-not ($excludes | Where-Object { $_ -ieq $name })) { $excludes += $name }
        }
    }
    $env:CARAPACE_EXCLUDES = ($excludes -join ',')
    return $source
}

function Get-CarapaceShellCacheInfo51
{
    # 只读：返回 5.1 上下文缓存的位置与有效性，不创建目录，也不枚举当前会话名称。
    # Valid 为 $false 时 Reason 指出重建原因；AgeHours 只在 meta.txt 可读时有值。
    $cacheDir = $null
    try { $cacheDir = Join-Path (Join-Path (Join-Path $HOME '.cxxu') 'cache') 'carapace-shell-51' } catch { }
    $info = [pscustomobject]@{
        Path      = $cacheDir
        Exists    = $false
        AgeHours  = $null
        HostMatch = $false
        Valid     = $false
        Reason    = '未建立'
    }
    if (-not $cacheDir -or -not (Test-Path -LiteralPath $cacheDir)) { return $info }
    $info.Exists = $true
    $metaPath = Join-Path $cacheDir 'meta.txt'
    if (-not (Test-Path -LiteralPath $metaPath)) { $info.Reason = 'meta.txt 缺失'; return $info }
    try
    {
        $meta = [IO.File]::ReadAllLines($metaPath)
        if ($meta.Count -lt 2) { $info.Reason = 'meta.txt 不完整'; return $info }
        $hostKey = '{0}|{1}|{2}' -f $PSVersionTable.PSVersion, [Environment]::Version, $PSHOME
        $info.HostMatch = ($meta[0].Trim() -eq $hostKey)
        $info.AgeHours = ([DateTime]::UtcNow.Ticks - [long]$meta[1].Trim()) / [TimeSpan]::TicksPerHour
        if (-not $info.HostMatch) { $info.Reason = '宿主或 PSHOME 已变化'; return $info }
        if (($info.AgeHours -lt 0) -or ($info.AgeHours -gt 24)) { $info.Reason = '已过期'; return $info }
        foreach ($file in @('aliases.txt', 'builtins.txt', 'functions.txt', 'variables.txt'))
        {
            $path = Join-Path $cacheDir $file
            if (-not (Test-Path -LiteralPath $path)) { $info.Reason = "缺少 $file"; return $info }
            if ((Get-Item -LiteralPath $path).Length -le 0) { $info.Reason = "$file 为空"; return $info }
        }
        $info.Valid = $true
        $info.Reason = ''
    }
    catch
    {
        $info.Reason = 'meta.txt 不可读'
    }
    return $info
}

function Get-CarapaceShellContext51
{
    # 5.1 的 carapace 生成脚本每次补全都会枚举别名/内置/函数/变量（合计约 350ms）；
    # 加载时算一次并缓存到磁盘，后续会话首个 Tab 只读缓存。缓存失效：-Force、宿主或
    # PSHOME 变化、超过 24 小时、任一文件缺失或为空。24 小时上限与 CxxuTab 命令表
    # 缓存一致：新装模块的函数名最多晚一天进入列表，外部 CLI 的参数补全不受影响。
    param([switch]$Force)

    $names = @('Aliases', 'Builtins', 'Functions', 'Variables')
    $fileNames = @{
        Aliases   = 'aliases.txt'
        Builtins  = 'builtins.txt'
        Functions = 'functions.txt'
        Variables = 'variables.txt'
    }
    $cache = Get-CarapaceShellCacheInfo51
    $cacheDir = $cache.Path
    $metaPath = if ($cacheDir) { Join-Path $cacheDir 'meta.txt' } else { $null }
    $hostKey = '{0}|{1}|{2}' -f $PSVersionTable.PSVersion, [Environment]::Version, $PSHOME
    $result = @{}

    if (-not $Force -and $cache.Valid)
    {
        try
        {
            $loaded = @{}
            foreach ($name in $names)
            {
                $text = [IO.File]::ReadAllText((Join-Path $cacheDir $fileNames[$name]))
                if ([string]::IsNullOrEmpty($text)) { $loaded = $null; break }
                $loaded[$name] = $text
            }
            if ($loaded)
            {
                foreach ($name in $names) { $result[$name] = $loaded[$name] }
                Write-Verbose "carapace: 已读取 5.1 上下文缓存（$cacheDir）"
                return $result
            }
        }
        catch
        {
            Write-Verbose "carapace: 读取 5.1 上下文缓存失败，改为重建：$($_.Exception.Message)"
        }
    }

    $result.Aliases = (Get-Alias | ForEach-Object { $_.Name } | Out-String).TrimEnd()
    $result.Builtins = (Get-Command -CommandType Cmdlet | ForEach-Object { $_.Name } | Out-String).TrimEnd()
    $result.Functions = (Get-Command -CommandType Function | ForEach-Object { $_.Name } | Out-String).TrimEnd()
    if ($result.Functions.Length -gt 30000)
    {
        $result.Functions = $result.Functions.Substring(0, 30000)
    }
    $result.Variables = (Get-Variable | ForEach-Object { $_.Name } | Out-String).TrimEnd()

    # 缓存写入是尽力而为：失败只影响下次首 Tab 的耗时，不影响本次加载。
    try
    {
        if ($cacheDir -and -not (Test-Path -LiteralPath $cacheDir))
        {
            $null = New-Item -ItemType Directory -Path $cacheDir -Force
        }
        if ($cacheDir)
        {
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            foreach ($name in $names)
            {
                [IO.File]::WriteAllText((Join-Path $cacheDir $fileNames[$name]), $result[$name], $utf8)
            }
            [IO.File]::WriteAllText($metaPath, ($hostKey + "`n" + [DateTime]::UtcNow.Ticks + "`n"), $utf8)
        }
    }
    catch
    {
        Write-Verbose "carapace: 写入 5.1 上下文缓存失败，跳过：$($_.Exception.Message)"
    }
    return $result
}

function Initialize-Carapace
{
    <#
    .SYNOPSIS
    按配置加载 carapace 补全（默认关闭；首次外部 CLI 参数补全 或显式调用时执行）。
    .DESCRIPTION
    开关 PsCarapace（默认 $false）；启用时要求 carapace 在 PATH。
    根据 PsGitCompletionSource 决定 carapace 是否接管 git/gitk：
    - Carapace：不排除 git/gitk，并置 $global:PsCarapaceGit，供 argc 让路；
    - GitCompletion、Argc、Auto：把 git/gitk 并入 CARAPACE_EXCLUDES。
    PsCarapaceExcludes 提供用户自己的慢命令排除项；两处合并后写入环境变量。
    init 只调用 Register-CarapaceLazyLoad 装桩；首次外部 CLI 参数补全 才由桩调用本函数完成注册。
    5.1 也可用：Register-ArgumentCompleter -Native 在 5.1 可用，但引擎不会把
    - 开头的词交给 Native completer（6.0 才修），由 Tab 桩插零宽字符绕过；
    环境变量超长与空字符串参数丢弃这两个 5.1 差异在生成脚本上打补丁，
    其中函数名列表截断会让 PowerShell 函数名补全不完整，外部 CLI 不受影响。
    加载失败只告警，不中断 init，也不在后续 Tab 反复重试。
    .PARAMETER Force
    已加载时也重新执行注册，用于同名 Native completer 被其他来源覆盖后夺回（如关闭 argc 后）。
    .EXAMPLE
    Initialize-Carapace
    .EXAMPLE
    Initialize-Carapace -Force
    .EXAMPLE
    Enable-CxxuComponent Carapace -Persist -Now
    #>
    [CmdletBinding()]
    param([switch]$Force)

    if ($global:PsCarapaceLoaded -and -not $Force) { return }
    if ($env:PsCarapace -match '^(False|0|No|Off)$')
    {
        $global:PsCarapacePending = $false
        $global:PsCarapaceGit = $false
        return
    }
    if ([string]::IsNullOrWhiteSpace($env:PsCarapace))
    {
        $global:PsCarapacePending = $false
        $global:PsCarapaceGit = $false
        return
    }
    if (-not (Get-Command carapace -ErrorAction SilentlyContinue))
    {
        $global:PsCarapacePending = $false
        $global:PsCarapaceGit = $false
        Write-Warning 'PsCarapace 已启用，但 PATH 中没有 carapace；先执行 Deploy-Carapace。'
        return
    }

    $source = Set-CarapaceCompletionOptions

    try
    {
        $script = carapace _carapace powershell | Out-String
        $needle = 'return "" # prevent default file completion'
        if ($PSVersionTable.PSVersion -lt [version]'7.7')
        {
            if ($script.Contains($needle))
            {
                $script = $script.Replace($needle, 'return')
            }
            else
            {
                Write-Warning 'carapace 生成脚本已变化，空结果补丁未匹配；请核对当前版本的空结果处理。'
            }
        }
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {
            # 5.1: 环境变量单值上限 32767，函数名列表通常超长会直接抛
            # "Environment variable name or value is too long"；截断只影响
            # PowerShell 函数名补全，外部 CLI 的参数补全不受影响。
            # 枚举成本约 350ms/次，改为加载时算一次并落盘缓存（Get-CarapaceShellContext51）。
            $context = Get-CarapaceShellContext51 -Force:$Force
            $global:PsCarapaceShellAliases = $context.Aliases
            $global:PsCarapaceShellBuiltins = $context.Builtins
            $global:PsCarapaceShellFunctions = $context.Functions
            $global:PsCarapaceShellVariables = $context.Variables

            $envPatches = @(
                @{ Old = '$env:CARAPACE_SHELL_ALIASES = (Get-Alias | ForEach-Object { $_.Name } | Out-String).TrimEnd()'; New = '$env:CARAPACE_SHELL_ALIASES = $global:PsCarapaceShellAliases' }
                @{ Old = '$env:CARAPACE_SHELL_BUILTINS = (Get-Command -CommandType Cmdlet | ForEach-Object { $_.Name } | Out-String).TrimEnd()'; New = '$env:CARAPACE_SHELL_BUILTINS = $global:PsCarapaceShellBuiltins' }
                @{ Old = '$env:CARAPACE_SHELL_FUNCTIONS = (Get-Command -CommandType Function | ForEach-Object { $_.Name } | Out-String).TrimEnd()'; New = '$env:CARAPACE_SHELL_FUNCTIONS = $global:PsCarapaceShellFunctions' }
                @{ Old = '$env:CARAPACE_SHELL_VARIABLES = (Get-Variable | ForEach-Object { $_.Name } | Out-String).TrimEnd()'; New = '$env:CARAPACE_SHELL_VARIABLES = $global:PsCarapaceShellVariables' }
            )
            foreach ($patch in $envPatches)
            {
                if ($script.Contains($patch.Old)) { $script = $script.Replace($patch.Old, $patch.New) }
                else { Write-Warning "carapace 生成脚本已变化，5.1 环境变量补丁未匹配：$($patch.New)" }
            }
            # 5.1 的 ConvertFrom-Json 把 JSON 数组当作单个对象输出，直接接
            # ForEach-Object 只会跑一次并把整份候选拼成一条；先赋值再逐项构造。
            # 调用改走 .NET Process：StandardOutputEncoding 固定 UTF-8，避免控制台
            # 代码页把中文提交说明解成乱码；空字符串参数也由参数拼装函数还原为 ""，
            # 不受 PowerShell 5.1 丢弃空参数的影响。
            $global:PsCarapaceExe = (Get-Command carapace -ErrorAction Stop).Source
            $script = $script.Replace('carapace ($elems[0]', '$__r = Invoke-Carapace51 ($elems[0]')
            $script = $script.Replace('| ConvertFrom-Json | ForEach-Object {', "`n          `$__r | ForEach-Object {")
            # PowerShell 函数调用会把 $($elems|...) 当成一个字符串参数；改为传数组，
            # 由 Invoke-Carapace51 展平，保留原有的参数边界与末尾空参数。
            $script = $script.Replace('$($elems| ForEach-Object {$_})', '$elems')
            # Tab 桩会在 - 开头的词前插入零宽字符，查询前去掉。
            $script = $script.Replace('$t = $_.Extent.Text', '$t = $_.Extent.Text.Replace([string][char]0x200B, [string]::Empty)')
            # PSReadLine 2.0 的菜单不解析 ANSI，候选描述会显示成 `^[[21;...`；
            # 5.1 去掉颜色，保留纯文本描述（选中行仍由 PSReadLine 的 Selection 反显）。
            $script = $script.Replace('$_.ListItemText.replace(''`e['', "`e[")', '($_.ListItemText -replace ''`e\[[0-9;]*m'', [string]::Empty -replace "`e\[[0-9;]*m", [string]::Empty)')
            $script = $script.Replace('$_.ToolTip.replace(''`e['', "`e[")', '($_.ToolTip -replace ''`e\[[0-9;]*m'', [string]::Empty -replace "`e\[[0-9;]*m", [string]::Empty)')

            # 生成的 completer 在会话里调用这两个全局辅助函数；仅 5.1 定义。
            $helper = @'
function global:ConvertTo-CarapaceArg51 {
    param([string]$Value)
    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}
function global:Invoke-Carapace51 {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
    $flat = @()
    foreach ($item in $Arguments)
    {
        if ($item -is [array]) { $flat += $item }
        else { $flat += [string]$item }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $global:PsCarapaceExe
    $psi.Arguments = ($flat | ForEach-Object { ConvertTo-CarapaceArg51 $_ }) -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $null = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($out) { $out | ConvertFrom-Json }
}
'@
            $helper | Invoke-Expression
        }
        # 在 completer 入口加 PsCarapace 门控：已注册的 Native completer 无法撤销，
        # 没有这道门时 Disable-PsPlugin Carapace 后旧绑定仍会返回候选，停用要等重开终端才见效。
        $paramNeedle = 'param($wordToComplete, $commandAst, $cursorPosition)'
        $gate = '    if ($env:PsCarapace -match ''^(False|0|No|Off)$'') { return }'
        if ($script.Contains($paramNeedle))
        {
            $script = $script.Replace($paramNeedle, $paramNeedle + "`n" + $gate)
        }
        else
        {
            Write-Warning 'carapace 生成脚本已变化，PsCarapace 门控未注入；停用 carapace 后需重开终端才完全停止。'
        }
        $script | Invoke-Expression
        # 记录 carapace 注册的命令名，供 5.1 的 Tab 桩判断是否需要插零宽字符。
        $global:PsCarapaceScripts = @{}
        foreach ($line in ($script -split "`r?`n"))
        {
            if ($line -match '^Register-ArgumentCompleter -Native -ScriptBlock \$_carapace_completer -CommandName (.+)$')
            {
                foreach ($name in ($Matches[1] -split ','))
                {
                    $trimmed = $name.Trim()
                    if ($trimmed) { $global:PsCarapaceScripts[$trimmed] = $true }
                }
            }
        }
        $global:PsCarapaceLoaded = $true
        $global:PsCarapacePending = $false
        # git/gitk 由 carapace 接管时才记来源；被排除时保留上一来源的标记。
        if ($source -eq 'Carapace') { $global:PsGitCompletionActive = 'Carapace' }
        Write-Verbose ("carapace 已加载；git 来源={0}，排除项={1}" -f $source, $env:CARAPACE_EXCLUDES)
    }
    catch
    {
        # 失败后摘掉待加载标记，避免每个 Tab 重复告警；显式调用本函数仍会重试。
        # 若 carapace 原本负责 git/gitk，交出归属，让 argc 在首次外部 CLI 参数补全 补上。
        $global:PsCarapacePending = $false
        $global:PsCarapaceGit = $false
        Write-Warning ("carapace 加载失败：{0}" -f $_.Exception.Message)
    }
}

function Register-CarapaceLazyLoad
{
    <#
    .SYNOPSIS
    为 carapace 安装首次外部 CLI 参数补全 懒加载桩（启用时由 init 调用）。
    .DESCRIPTION
    只校验开关、计算排除项并装 Tab 桩，不执行 carapace 生成的注册脚本；
    首次外部 CLI 参数补全 才调用 Initialize-Carapace，把约 0.2 秒的注册成本从启动挪到用户手势。
    与 argc 共用同一个 Tab 桩（Register-CxxuTabStub），两者都未启用时不装桩。
    .EXAMPLE
    Register-CarapaceLazyLoad
    #>
    [CmdletBinding()]
    param()

    if ($global:PsCarapaceLoaded)
    {
        # 已加载时 init -Force 仍可能改了来源或排除项；completer 已注册无法撤销，但环境变量要跟着更新。
        # Set-PSReadLinesCommon 会把 Tab 重置成 MenuComplete，因此共享桩也要重装。
        if ($env:PsCarapace -match '^(False|0|No|Off)$' -or [string]::IsNullOrWhiteSpace($env:PsCarapace))
        {
            $global:PsCarapacePending = $false
            $global:PsCarapaceGit = $false
            return
        }
        $null = Set-CarapaceCompletionOptions
        try { Register-CxxuTabStub } catch { Write-Verbose "carapace: 重装 Tab 桩失败，跳过：$($_.Exception.Message)" }
        return
    }

    # 每次 init 都重新校验，让 init -Force 能反映启停变化。
    if ($env:PsCarapace -match '^(False|0|No|Off)$' -or [string]::IsNullOrWhiteSpace($env:PsCarapace))
    {
        $global:PsCarapacePending = $false
        $global:PsCarapaceGit = $false
        return
    }
    if (-not (Get-Command carapace -ErrorAction SilentlyContinue))
    {
        $global:PsCarapacePending = $false
        $global:PsCarapaceGit = $false
        Write-Warning 'PsCarapace 已启用，但 PATH 中没有 carapace；先执行 Deploy-Carapace。'
        return
    }
    $null = Set-CarapaceCompletionOptions
    $global:PsCarapacePending = $true

    try
    {
        # 与 argc 共用同一个桩：桩内按需加载 carapace/argc，并处理 5.1 的 - 开头词。
        Register-CxxuTabStub
        Write-Verbose 'carapace: 已装首次外部 CLI 参数补全 懒加载桩'
    }
    catch
    {
        Write-Verbose "carapace: 安装 Tab 桩失败，跳过：$($_.Exception.Message)"
    }
}

function Register-GitCompletion
{
    <#
    .SYNOPSIS
    为 git/gitk 挂 git-completion 模块的 Tab 补全(懒加载,模块未安装时静默跳过)。
    .DESCRIPTION
    git-completion v2 起导入模块不再自动开启补全,必须自行注册 Native completer。
    这里只注册 completer,首次补全才 Import-Module,启动不付导入成本;同时置
    $global:PsGitCompletion,供 Initialize-ArgcCompletions 让出 git/gitk(两者同名
    completer 后注册者胜出,argc 首次外部 CLI 参数补全 才注册会顶掉这里的注册)。
    模块位置按 PSModulePath 静态探测,不调用 Get-Module -ListAvailable(冷启动约 140ms)。
    来源由 PsGitCompletionSource 决定(Auto/GitCompletion/Carapace/Argc,见 Get-CxxuGitCompletionSource);
    未设置该键时沿用 PsGitCompletion 的旧语义,关闭后 argc 继续负责 git。
    .PARAMETER Force
    已注册时也重新注册，用于其他来源覆盖 git/gitk 后夺回（如 Set-GitCompletionSource GitCompletion）。
    .EXAMPLE
    Register-GitCompletion
    .EXAMPLE
    Register-GitCompletion -Force
    .EXAMPLE
    $env:PsGitCompletion = 'False'   # 本次会话不挂载,git 回到 argc 或原生补全
    #>
    [CmdletBinding()]
    param([switch]$Force)

    if ($global:PsGitCompletion -and -not $Force) { return }
    # 来源不是 git-completion 时不注册；来源解析见 Get-CxxuGitCompletionSource。
    if ((Get-CxxuGitCompletionSource) -ne 'GitCompletion') { return }
    if (-not (Test-CxxuGitCompletionInstalled)) { return }

    $global:PsGitCompletion = $true
    $global:PsGitCompletionActive = 'GitCompletion'
    Register-ArgumentCompleter -CommandName git -Native -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        if (-not (Get-Module git-completion)) { Import-Module git-completion -Global -ErrorAction SilentlyContinue }
        if (Get-Command Complete-Git -ErrorAction SilentlyContinue)
        {
            return (Complete-Git -CommandAst $commandAst -CursorPosition $cursorPosition)
        }
    }
    Register-ArgumentCompleter -CommandName gitk -Native -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        if (-not (Get-Module git-completion)) { Import-Module git-completion -Global -ErrorAction SilentlyContinue }
        if (Get-Command Complete-Gitk -ErrorAction SilentlyContinue)
        {
            return (Complete-Gitk -CommandAst $commandAst -CursorPosition $cursorPosition)
        }
    }
}

function Import-PsCompletions
{
    <#
    .SYNOPSIS
    按组件配置导入 PSCompletions 模块（默认关闭，启用时由 init 调用）。
    .DESCRIPTION
    开关 PsCompletions（默认 $false）；启用后要求模块已安装。
    模块只导入到全局会话，失败只告警，不中断 init。
    .EXAMPLE
    Import-PsCompletions
    .EXAMPLE
    Enable-CxxuComponent PSCompletions -Persist
    #>
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:PsCompletions)) { return }
    if ($env:PsCompletions -match '^(False|0|No|Off)$') { return }
    if (Get-Module PSCompletions) { return }
    if (-not (Get-Module -ListAvailable PSCompletions -ErrorAction SilentlyContinue))
    {
        Write-Warning 'PsCompletions 已启用，但模块未安装；先执行 Deploy-CompletionStack -IncludePSCompletions。'
        return
    }

    try
    {
        Import-Module PSCompletions -Global -ErrorAction Stop
        Write-Verbose 'PSCompletions 已导入'
    }
    catch
    {
        Write-Warning ("PSCompletions 导入失败：{0}" -f $_.Exception.Message)
    }
}

function Initialize-Fnm
{
    <#
    .SYNOPSIS
    按组件配置加载 fnm 的 PowerShell 环境（默认关闭，启用时由 init 调用）。
    .DESCRIPTION
    开关 PsFnm（默认 $false）；启用后要求 fnm 在 PATH。
    执行 fnm env --use-on-cd，注册 node 版本切换所需的环境变量与目录切换钩子；
    失败只告警，不中断 init。
    .EXAMPLE
    Initialize-Fnm
    .EXAMPLE
    Enable-CxxuComponent Fnm -Persist
    #>
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:PsFnm)) { return }
    if ($env:PsFnm -match '^(False|0|No|Off)$') { return }
    if (-not (Get-Command fnm -ErrorAction SilentlyContinue))
    {
        Write-Warning 'PsFnm 已启用，但 PATH 中没有 fnm；先执行 scoop install fnm（或 brew install fnm）。'
        return
    }

    try
    {
        $hookScript = & fnm env --use-on-cd --shell powershell 2>$null | Out-String
        if ($LASTEXITCODE -ne 0)
        {
            $hookScript = & fnm env --use-on-cd 2>$null | Out-String
        }
        if ($LASTEXITCODE -ne 0) { throw "fnm env 退出码 $LASTEXITCODE" }
        $hookScript | Invoke-Expression
        Write-Verbose 'fnm 环境已加载'
    }
    catch
    {
        Write-Warning ("fnm 环境加载失败：{0}" -f $_.Exception.Message)
    }
}

function Initialize-ScoopSearch
{
    <#
    .SYNOPSIS
    按组件配置注入 scoop-search 的搜索钩子（默认关闭，启用时由 init 调用）。
    .DESCRIPTION
    开关 PsScoopSearch（默认 $false）；启用后要求 scoop-search 在 PATH。
    执行 scoop-search --hook，让 scoop search 走加速索引；失败只告警，不中断 init。
    .EXAMPLE
    Initialize-ScoopSearch
    .EXAMPLE
    Enable-CxxuComponent ScoopSearch -Persist
    #>
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:PsScoopSearch)) { return }
    if ($env:PsScoopSearch -match '^(False|0|No|Off)$') { return }
    if (-not (Get-Command scoop-search -ErrorAction SilentlyContinue))
    {
        Write-Warning 'PsScoopSearch 已启用，但 PATH 中没有 scoop-search；先执行 scoop install scoop-search。'
        return
    }

    try
    {
        $hookScript = & scoop-search --hook 2>$null | Out-String
        if ($LASTEXITCODE -ne 0) { throw "scoop-search --hook 退出码 $LASTEXITCODE" }
        # scoop-search 的钩子用 `function scoop` 定义；在模块函数内直接执行只会留在函数作用域，
        # 这里把函数定义提升到全局，等价于原先在 profile 顶层执行 hook。
        $hookScript = [regex]::Replace($hookScript, '(?m)^(\s*function\s+)(?!global:)', '$1global:')
        $hookScript | Invoke-Expression
        Write-Verbose 'scoop-search 钩子已加载'
    }
    catch
    {
        Write-Warning ("scoop-search 钩子加载失败：{0}" -f $_.Exception.Message)
    }
}

# --- 从 Pwsh.psm1 迁入:环境等级跟踪与导入(职责:初始化) ---

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
        # Update-PwshEnv 已包含 Set-PsPrompt,不再重复刷新
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
        # Env 分支已由 Update-PwshEnv 刷新 prompt；core/Vars 只导入变量，需要单独刷新
        if ($Mode -ne 'Env')
        {
            Set-PsPrompt -Verbose:$VerbosePreference
        }
    }

    Write-Verbose 'Environment  have been Imported in the current powershell!'
}
function Read-CxxuUtf8Text
{
    # 5.1/7 通用:按 UTF-8 读文本。5.1 的 Get-Content 对无 BOM 文件按 ANSI 解码,
    # 会把配置里的中文注释读成乱码,写回即永久损坏;有 BOM 时 StreamReader 自动识别并去掉。
    param([Parameter(Mandatory)][string]$Path)
    return [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false))
}
function Write-CxxuUtf8Text
{
    # 5.1/7 通用:按 UTF-8 写文本。5.1 的 Set-Content 不认 -Encoding utf8NoBOM
    # (枚举只有 UTF8,且会加 BOM),故统一走 .NET。
    # -NoNewline 对齐 Set-Content:默认在末尾补一个换行,指定时逐字节写 $Text
    # (空文本不补换行,对应空数组管道 Set-Content 的 0 字节结果)。
    # -Bom 供 5.1 必须识别的配置文件使用(无 BOM 时 5.1 按 GBK 解码,中文注释会解析失败)。
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [switch]$NoNewline,
        [switch]$Bom
    )
    if (-not $NoNewline -and $Text.Length -gt 0) { $Text += "`n" }
    $encoding = [Text.UTF8Encoding]::new($false)
    if ($Bom) { $encoding = [Text.UTF8Encoding]::new($true) }
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}
function Optimize-PsHistory
{
    <#
    .SYNOPSIS
    历史瘦身:去重(保最近一次,保序)+去杂+截断,被裁行进归档(默认留最近 3000 行)。
    .DESCRIPTION
    PSFzf Ctrl+R 每次读全文件,3 万行 1.5MB 是它慢的主因。流程:备份 .bak → 去重(同命令只留
    最后一次,相对顺序不变) → 去杂(空行/纯空白/孤反引号) → 超 KeepLast 截断,被裁行追加进
    同目录 archive 文件(可恢复)。-WhatIf 只出诊断(总数/去重率/ топ 重复),不动文件。
    治本靠 init:HistoryNoDuplicates + MaximumHistoryCount 3000(新命令不再重复入库)。
    注意:历史文件无时间戳,切割按"新旧顺序"(文件尾=最近),不是按日期。
    .EXAMPLE
    Optimize-PsHistory -WhatIf
    .EXAMPLE
    Optimize-PsHistory -KeepLast 2000
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 活动文件保留最近多少行(默认 3000,与 MaximumHistoryCount 对齐)
        [int]$KeepLast = 3000
    )
    $file = try { (Get-PSReadLineOption).HistorySavePath } catch { '' }
    if ([string]::IsNullOrWhiteSpace($file) -or -not (Test-Path -LiteralPath $file))
    {
        Write-Warning '取不到 PSReadLine 历史文件路径,先确认 PSReadLine 已加载。'
        return
    }
    $raw = Read-CxxuUtf8Text -Path $file
    $lines = @($raw -split '\r?\n')
    # 与 Get-Content 对齐:文件末尾的换行不算一行
    if ($lines.Count -gt 1 -and $lines[-1] -eq '') { $lines = @($lines[0..($lines.Count - 2)]) }
    $total = $lines.Count
    # 去重保最后:记每行最后下标,按最后下标排序(相对顺序=最近一次出现顺序)
    $lastIdx = @{}
    for ($i = 0; $i -lt $total; $i++) { $lastIdx[$lines[$i]] = $i }
    $ordered = @($lastIdx.GetEnumerator() | Sort-Object Value | ForEach-Object { $_.Key })
    # 去杂:空行/纯空白/孤反引号(续行手误)
    $junk = @($ordered | Where-Object { $_ -notmatch '\S' -or $_ -eq '`' }).Count
    $clean = @($ordered | Where-Object { $_ -match '\S' -and $_ -ne '`' })
    $keep = @($clean | Select-Object -Last $KeepLast)
    $drop = @($clean | Select-Object -SkipLast $KeepLast)
    $top = @($lines | Group-Object | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name)=$($_.Count)" })
    Write-Host "历史 $file"
    Write-Host "总数 $total;去重后 $($clean.Count)(杂 $junk);保留 $($keep.Count);归档 $($drop.Count)"
    Write-Host "重复 Top5: $($top -join ', ')"
    if ($drop.Count -eq 0 -and $junk -eq 0 -and $clean.Count -eq $total)
    {
        Write-Host '已是最简,无事可做。'
        return
    }
    if ($PSCmdlet.ShouldProcess($file, "瘦身 $total→$($keep.Count),归档 $($drop.Count) 行"))
    {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $file -Destination "$file.bak-$stamp" -Force
        Write-CxxuUtf8Text -Path $file -Text ($keep -join "`n")
        if ($drop.Count)
        {
            $archive = "$file.archive-$stamp.txt"
            Write-CxxuUtf8Text -Path $archive -Text ($drop -join "`n")
            Write-Host "已备份 $file.bak-$stamp,归档 $archive"
        }
        else { Write-Host "已备份 $file.bak-$stamp(无行需归档)" }
    }
}
function Clear-PsCommandCacheIfStale
{
    # 仓库模块文件比命令表缓存新时删除缓存(不导出)。
    # 补全插件每进程只建一次表(CxxuPredictor 实例字段与 CompleteCommand 静态字段),
    # 删除只影响之后启动的进程;当前会话已建表时继续用旧表,不做无效刷新。
    # 模块目录只扫一层(PS/<模块>/*.psm1|*.psd1),与插件建表口径一致,约 5ms。
    param([string]$CacheDir, [string]$ModuleRoot)
    try
    {
        if (-not $CacheDir) { $CacheDir = Join-Path (Join-Path $HOME '.cxxu') 'cache' }
        if (-not $ModuleRoot) { $ModuleRoot = Split-Path $script:CxxuModuleRoot -Parent }
        $cache = Join-Path $CacheDir ('tab-commands-' + [Environment]::Version.Major + '.tsv')
        if (-not (Test-Path -LiteralPath $cache)) { return }
        if (-not (Test-Path -LiteralPath $ModuleRoot)) { return }
        $cacheTime = (Get-Item -LiteralPath $cache).LastWriteTimeUtc
        $newest = [datetime]::MinValue
        foreach ($dir in [IO.Directory]::EnumerateDirectories($ModuleRoot))
        {
            foreach ($file in [IO.Directory]::EnumerateFiles($dir))
            {
                $name = [IO.Path]::GetFileName($file)
                if (-not ($name.EndsWith('.psm1') -or $name.EndsWith('.psd1'))) { continue }
                $t = [IO.File]::GetLastWriteTimeUtc($file)
                if ($t -gt $newest) { $newest = $t }
            }
        }
        if ($newest -gt $cacheTime)
        {
            Remove-Item -LiteralPath $cache -Force -ErrorAction Stop
            Write-Verbose "命令表缓存早于仓库模块文件,已删除($cache);新终端首次 Tab 会重建。"
        }
    }
    catch
    {
        Write-Verbose "命令表缓存检查跳过: $($_.Exception.Message)"
    }
}
function Read-CxxuDataFile
{
    # 读 .psd1 数据文件(不导出)：优先标准解析器，会话里识别不到该 cmdlet 时改用 AST 解析。
    # 部分宿主(如 VS Code 集成控制台的 5.1 会话)可能出现该 cmdlet 不可见的情况，
    # 组件清单与默认值读不到时 init 会连发三条警告。兜底只接受单个哈希表字面量，
    # 不执行文件里的其它代码；文件按 UTF-8 读取，顺带覆盖 5.1 对无 BOM 中文的误判。
    param([Parameter(Mandatory)][string]$Path)

    if ($null -eq $script:CxxuDataFileReaderAvailable)
    {
        $script:CxxuDataFileReaderAvailable = [bool](Get-Command Import-PowerShellDataFile -ErrorAction Ignore)
    }
    if ($script:CxxuDataFileReaderAvailable)
    {
        return Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop
    }

    Write-Verbose "会话缺少 Import-PowerShellDataFile，改用内置解析:$Path"
    $text = Read-CxxuUtf8Text -Path $Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors)
    {
        $first = $parseErrors[0]
        throw ("{0} 第 {1} 行解析失败:{2}" -f $Path, $first.Extent.StartLineNumber, $first.Message)
    }
    $statements = @($ast.EndBlock.Statements)
    $pipeline = if ($statements.Count -eq 1) { $statements[0] -as [System.Management.Automation.Language.PipelineAst] } else { $null }
    $elements = if ($pipeline) { @($pipeline.PipelineElements) } else { @() }
    $element = if ($elements.Count -eq 1) { $elements[0] -as [System.Management.Automation.Language.CommandExpressionAst] } else { $null }
    if ($null -eq $element -or $element.Expression -isnot [System.Management.Automation.Language.HashtableAst])
    {
        throw "$Path 不是单个哈希表字面量，无法在缺少 Import-PowerShellDataFile 的会话里读取。"
    }
    return $element.Expression.SafeGetValue()
}
function Read-CxxuComponentManifest
{
    # 读组件清单(不导出)：PS/Init/components.psd1。
    param([string]$Path = (Join-Path $script:CxxuModuleRoot 'components.psd1'))
    if ($null -ne $script:CxxuComponentManifestCache) { return $script:CxxuComponentManifestCache }
    try
    {
        $data = Read-CxxuDataFile -Path $Path
        $script:CxxuComponentManifestCache = @($data.Components)
        return $script:CxxuComponentManifestCache
    }
    catch
    {
        Write-Warning "组件清单读失败($Path):$($_.Exception.Message);本次按无组件处理。"
        $script:CxxuComponentManifestCache = @()
        return @()
    }
}
function Get-CxxuStartupTier
{
    # 读取启动档位(不导出):显式参数 > 环境变量/用户配置 > Balanced。
    # 环境变量由 Import-CxxuConfig 按“环境变量 > 配置文件 > 默认值”注入。
    param([string]$Tier = '')
    if ($Tier) { return $Tier }
    $value = [string]$env:PsStartupTier
    foreach ($known in @('Minimal', 'Fast', 'Balanced'))
    {
        if ($value -ieq $known) { return $known }
    }
    return 'Balanced'
}
function Test-CxxuTierAllowsComponent
{
    # 档位对可选组件是上限(不导出):Minimal 全关，Fast 只留 Argc/GitCompletion，
    # Balanced 按组件自身开关。显式 Enable 不能突破档位，需先切换档位。
    param(
        [string]$Tier = 'Balanced',
        [string]$Id
    )
    if ($Tier -eq 'Minimal') { return $false }
    if ($Tier -eq 'Fast')
    {
        return ($Id -in @('Argc', 'GitCompletion'))
    }
    return $true
}
function Get-CxxuInitStepsForTier
{
    # 按档位生成 init 步骤表(不导出):核心步骤先过滤，再生成允许的组件步骤。
    param([ValidateSet('Minimal', 'Fast', 'Balanced')][string]$Tier = 'Balanced')

    $core = Get-CxxuCoreInitSteps
    $beforeNames = @(if ($Tier -eq 'Minimal') { 'Set-PSReadLinesCommon' }
        elseif ($Tier -eq 'Fast') { 'Set-PSReadLinesCommon'; 'Set-PSReadLinesAdvanced' })
    $afterNames = @(if ($Tier -eq 'Balanced') { } else { 'Set-PsPrompt' })
    # 用户显式选择富信息提示符时，即使 Fast/Minimal 也补回其依赖的系统信息步骤。
    if ($Tier -ne 'Balanced' -and ($env:PsPrompt -match '^(?i:Balance|Brilliant|Brilliant2)$'))
    {
        $afterNames += @('Confirm-EnvVarOfInfo', 'Confirm-DataJson')
    }

    $before = @(if ($beforeNames.Count) { @($core.Before | Where-Object { $beforeNames -contains [string]$_.Name }) } else { @($core.Before) })
    $after = @(if ($afterNames.Count) { @($core.After | Where-Object { $afterNames -contains [string]$_.Name }) } else { @($core.After) })
    $coveredInit = @()
    $coveredInit += @($before | ForEach-Object { [string]$_.Name })
    $coveredInit += @($after | ForEach-Object { [string]$_.Name })
    $componentSteps = @(Get-CxxuComponentInitSteps -CoveredInit $coveredInit -Tier $Tier)
    $result = @()
    $result += @($before)
    $result += @($componentSteps)
    $result += @($after)
    return $result
}
function Get-CxxuCoreInitSteps
{
    # 固定核心步骤（不导出）：Before 在可选组件之前，After 在之后。
    # 组件清单里的 Init 若与这里的 Name 相同，则由核心步骤统一承担，不再重复生成。
    @{
        Before = @(
            # 导入图标模块(建议放到extension部分中)
            # Import-TerminalIcons
            # Import-ANSIColorEnv
            # 补全模块PSReadline及其相关配置
            @{ Name = 'Set-PSReadLinesCommon'; Action = { Set-PSReadLinesCommon } }
            @{ Name = 'Set-PSReadLinesAdvanced'; Action = { Set-PSReadLinesAdvanced } }
            @{ Name = 'Set-ArgumentCompleter'; Action = { Set-ArgumentCompleter }; MinPS = 7 }
        )
        After = @(
            @{ Name = 'Confirm-EnvVarOfInfo'; Action = { Confirm-EnvVarOfInfo }; MinPS = 7 }
            # 默认关闭时跳过调用，避免为一次 no-op 导入 PsEnv 模块（约 17ms）。
            @{ Name = 'Set-PsExtension'; Action = { if ($env:PsExtension -eq 'True') { Set-PsExtension } }; MinPS = 7 }
            # 设置prompt样式(这里面会导入基础的powershell预定变量和别名)
            @{ Name = 'Set-PsPrompt'; Action = { Set-PsPrompt } }
            # 只有用到网卡 IP 的主题才需要 Data.json；fast/short/default 不必在启动时解析。
            @{ Name = 'Confirm-DataJson'; Action = { if ($env:PsPrompt -match '^(?i:Balance|Brilliant|Brilliant2)$') { Confirm-DataJson | Out-Null } }; MinPS = 7 }
            # 体验件手势桩+单发收尾(7: PSFzf/Tab 首用才装,predictor/zoxide 首屏单发;
            # 5.1: 只装 CxxuTab 的手势桩,其余 7-only 项跳过),启动零开销
            @{ Name = 'Register-PsUxLazyLoad'; Action = { Register-PsUxLazyLoad } }
        )
    }
}
function Get-CxxuComponentInitSteps
{
    # 由组件清单生成可选组件的 init 步骤（不导出）。
    # 跳过：Init 为空、已被核心步骤覆盖、同名 Init 重复（多个组件共享一次加载）、
    # 当前启动档位不允许的组件。
    param(
        [string[]]$CoveredInit = @(),
        [ValidateSet('Minimal', 'Fast', 'Balanced')][string]$Tier = 'Balanced'
    )

    $seen = @{}
    foreach ($component in (Read-CxxuComponentManifest))
    {
        if (-not (Test-CxxuTierAllowsComponent -Tier $Tier -Id ([string]$component.Id))) { continue }
        $init = [string]$component.Init
        if ([string]::IsNullOrWhiteSpace($init)) { continue }
        if ($CoveredInit -contains $init) { continue }
        if ($seen.ContainsKey($init)) { continue }
        $seen[$init] = $true

        # 不在这里用 GetNewClosure：闭包会脱离模块会话状态，调用不到模块内部函数。
        # 由模块内生成一个只含函数调用的脚本块，执行时仍按 init 的作用域查找函数。
        $step = @{
            Name   = $init
            Action = [scriptblock]::Create(('& {0}' -f $init))
        }
        # 组件可在清单里声明最低 PowerShell 版本；与步骤表的 MinPS 语义一致。
        if ($component.ContainsKey('MinPS') -and $component.MinPS)
        {
            $step.MinPS = [int]$component.MinPS
        }
        $step
    }
}
function Read-CxxuSettingsDefaultList
{
    # 读全局设置默认值(不导出)：PS/Init/config.defaults.psd1。
    param([string]$Path = (Join-Path $script:CxxuModuleRoot 'config.defaults.psd1'))
    if ($null -ne $script:CxxuSettingsDefaultCache) { return $script:CxxuSettingsDefaultCache }
    try
    {
        $data = Read-CxxuDataFile -Path $Path
        $script:CxxuSettingsDefaultCache = @($data.Defaults)
        return $script:CxxuSettingsDefaultCache
    }
    catch
    {
        Write-Warning "默认偏好文件读失败($Path):$($_.Exception.Message);本次按无默认值处理。"
        $script:CxxuSettingsDefaultCache = @()
        return @()
    }
}
function Read-CxxuConfigDefaultList
{
    # 把 Settings 与组件清单合成平坦键列表，供 Get-CxxuConfig、Reset-CxxuConfig 与旧键兼容使用。
    if ($null -ne $script:CxxuConfigDefaultListCache) { return $script:CxxuConfigDefaultListCache }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($component in (Read-CxxuComponentManifest))
    {
        $rows.Add(@{
                Key         = [string]$component.Key
                Name        = [string]$component.Name
                Default     = $component.Default
                Description = [string]$component.Description
            })
        foreach ($option in @($component.Options | Where-Object { $_ }))
        {
            $rows.Add(@{
                    Key         = [string]$option.Key
                    Name        = ("{0}.{1}" -f $component.Name, $option.Name)
                    Default     = $option.Default
                    Description = [string]$option.Description
                })
        }
    }
    foreach ($item in (Read-CxxuSettingsDefaultList)) { $rows.Add($item) }
    $script:CxxuConfigDefaultListCache = $rows.ToArray()
    return $script:CxxuConfigDefaultListCache
}
function ConvertTo-CxxuBool
{
    # 配置文件里的布尔可能是真正的 bool，也可能是旧版平坦键的 'False' 字符串。
    param($Value)
    if ($Value -is [bool]) { return $Value }
    return -not ([string]$Value -match '^(False|0|No|Off)$')
}
function New-CxxuConfigModel
{
    # 按组件清单与 Settings 默认值构造 v2 内存模型。
    $model = @{ SchemaVersion = 2; Components = @{}; Settings = @{} }
    foreach ($component in (Read-CxxuComponentManifest))
    {
        $entry = @{ Enabled = [bool]$component.Default }
        foreach ($option in @($component.Options | Where-Object { $_ }))
        {
            if ([string]$option.Type -eq 'List') { $entry[[string]$option.Name] = @($option.Default) }
            else { $entry[[string]$option.Name] = $option.Default }
        }
        $model.Components[[string]$component.Id] = $entry
    }
    foreach ($item in (Read-CxxuSettingsDefaultList))
    {
        $model.Settings[[string]$item.Key] = $item.Default
    }
    return $model
}
function Get-CxxuModelValueByKey
{
    # 用旧版平坦键名读取模型值；找不到时返回 $null。
    param($Model, [string]$Key)
    foreach ($component in (Read-CxxuComponentManifest))
    {
        if ([string]$component.Key -ieq $Key) { return [bool]$Model.Components[[string]$component.Id].Enabled }
        foreach ($option in @($component.Options | Where-Object { $_ }))
        {
            if ([string]$option.Key -ieq $Key) { return $Model.Components[[string]$component.Id][[string]$option.Name] }
        }
    }
    foreach ($name in $Model.Settings.Keys)
    {
        if ([string]$name -ieq $Key) { return $Model.Settings[$name] }
    }
    return $null
}
function Set-CxxuModelValueByKey
{
    # 用旧版平坦键名写模型值；选项 List 接受数组或逗号分隔字符串。
    param($Model, [string]$Key, $Value)
    foreach ($component in (Read-CxxuComponentManifest))
    {
        if ([string]$component.Key -ieq $Key)
        {
            $Model.Components[[string]$component.Id].Enabled = ConvertTo-CxxuBool $Value
            return $true
        }
        foreach ($option in @($component.Options | Where-Object { $_ }))
        {
            if ([string]$option.Key -ieq $Key)
            {
                if ([string]$option.Type -eq 'List')
                {
                    if ($Value -is [string]) { $Value = @($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                    else { $Value = @($Value | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
                }
                $Model.Components[[string]$component.Id][[string]$option.Name] = $Value
                return $true
            }
        }
    }
    foreach ($name in @($Model.Settings.Keys))
    {
        if ([string]$name -ieq $Key) { $Model.Settings[$name] = $Value; return $true }
    }
    return $false
}
function Format-CxxuPsd1Value
{
    # 渲染 PSD1 字面量（不导出）：bool/数组/字符串/数字。
    param($Value)
    if ($Value -is [bool]) { if ($Value) { return '$true' } return '$false' }
    if ($null -eq $Value) { return "''" }
    if ($Value -is [array])
    {
        $items = @($Value | ForEach-Object { Format-CxxuPsd1Value $_ })
        return '@(' + ($items -join ', ') + ')'
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Value) }
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}
function ConvertTo-CxxuConfigText
{
    # 由内存模型生成带注释的 v2 配置文本；写入前会先备份旧文件。
    param($Model)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@{')
    $lines.Add('    # CxxuPsModules 用户配置（本机生效，仓库外；优先级：环境变量 > 本文件 > 默认值）')
    $lines.Add('    # 改完重开终端（或 init -Force）生效；查看生效值与来源：Get-CxxuConfig / Get-CxxuComponent。')
    $lines.Add('    SchemaVersion = 2')
    $lines.Add('')
    $lines.Add('    Components = @{')
    foreach ($component in (Read-CxxuComponentManifest))
    {
        $id = [string]$component.Id
        $entry = $Model.Components[$id]
        $lines.Add(("        # {0}：{1}" -f $component.Name, $component.Description))
        $lines.Add(("        {0} = @{{" -f $id))
        $lines.Add(("            Enabled = {0}" -f (Format-CxxuPsd1Value ([bool]$entry.Enabled))))
        foreach ($option in @($component.Options | Where-Object { $_ }))
        {
            $value = $entry[[string]$option.Name]
            $lines.Add(("            {0} = {1}  # {2}" -f $option.Name, (Format-CxxuPsd1Value $value), $option.Description))
        }
        $lines.Add('        }')
    }
    $lines.Add('    }')
    $lines.Add('')
    $lines.Add('    Settings = @{')
    foreach ($item in (Read-CxxuSettingsDefaultList))
    {
        $key = [string]$item.Key
        $lines.Add(("        {0} = {1}  # {2}" -f $key, (Format-CxxuPsd1Value $Model.Settings[$key]), $item.Description))
    }
    $lines.Add('    }')
    $lines.Add('}')
    return ($lines -join "`n")
}
function Read-CxxuConfigState
{
    # 读用户配置为 v2 模型；同时返回实际出现的平坦键（Present）和未识别键（Unknown）。
    param([Parameter(Mandatory)][string]$Path)
    $model = New-CxxuConfigModel
    $present = @{}
    $unknown = New-Object System.Collections.Generic.List[string]
    $exists = Test-Path -LiteralPath $Path
    if (-not $exists)
    {
        return [pscustomobject]@{ Model = $model; Present = $present; Unknown = @(); Exists = $false }
    }
    $data = Import-CxxuConfigData -Path $Path
    $knownFlat = @{}
    foreach ($row in (Read-CxxuConfigDefaultList)) { $knownFlat[[string]$row.Key] = $true }
    $components = $null
    if ($data.Contains('Components')) { $components = $data['Components'] }
    if ($components -is [System.Collections.IDictionary])
    {
        foreach ($component in (Read-CxxuComponentManifest))
        {
            $id = [string]$component.Id
            $actualId = @($components.Keys | Where-Object { [string]$_ -ieq $id } | Select-Object -First 1)
            if (-not $actualId.Count) { continue }
            $entry = $components[$actualId[0]]
            if ($entry -isnot [System.Collections.IDictionary]) { continue }
            if ($entry.Contains('Enabled'))
            {
                $model.Components[$id].Enabled = ConvertTo-CxxuBool $entry['Enabled']
                $present[[string]$component.Key] = $true
            }
            foreach ($option in @($component.Options | Where-Object { $_ }))
            {
                $actualOption = @($entry.Keys | Where-Object { [string]$_ -ieq [string]$option.Name } | Select-Object -First 1)
                if (-not $actualOption.Count) { continue }
                $value = $entry[$actualOption[0]]
                if ([string]$option.Type -eq 'List') { $value = @($value | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
                $model.Components[$id][[string]$option.Name] = $value
                $present[[string]$option.Key] = $true
            }
            foreach ($name in $entry.Keys)
            {
                if (($name -notin @('Enabled') ) -and (-not (@($component.Options | ForEach-Object { $_.Name }) -contains [string]$name))) { $unknown.Add("Components.$id.$name") }
            }
        }
        foreach ($name in $components.Keys)
        {
            if (-not (@(Read-CxxuComponentManifest | ForEach-Object { $_.Id }) -contains [string]$name)) { $unknown.Add("Components.$name") }
        }
    }
    if ($data.Contains('Settings') -and ($data['Settings'] -is [System.Collections.IDictionary]))
    {
        $settings = $data['Settings']
        foreach ($item in (Read-CxxuSettingsDefaultList))
        {
            $key = [string]$item.Key
            $actual = @($settings.Keys | Where-Object { [string]$_ -ieq $key } | Select-Object -First 1)
            if ($actual.Count)
            {
                $model.Settings[$key] = $settings[$actual[0]]
                $present[$key] = $true
            }
        }
        foreach ($name in $settings.Keys)
        {
            if (-not (@(Read-CxxuSettingsDefaultList | ForEach-Object { $_.Key }) -contains [string]$name)) { $unknown.Add("Settings.$name") }
        }
    }
    # 兼容旧版平坦键：v1 文件或 v2 文件里同时保留的键仍然生效。
    foreach ($key in $data.Keys)
    {
        if ($key -in @('SchemaVersion', 'Components', 'Settings')) { continue }
        if ($knownFlat.ContainsKey([string]$key))
        {
            if (-not $present.ContainsKey([string]$key))
            {
                $null = Set-CxxuModelValueByKey -Model $model -Key ([string]$key) -Value $data[$key]
                $present[[string]$key] = $true
            }
        }
        else { $unknown.Add([string]$key) }
    }
    return [pscustomobject]@{ Model = $model; Present = $present; Unknown = @($unknown); Exists = $true }
}
function Write-CxxuConfigState
{
    # 以 v2 规范文本写用户配置；旧文件先备份。
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Model)
    if (Test-Path -LiteralPath $Path)
    {
        Copy-Item -LiteralPath $Path -Destination ($Path + '.bak-' + (Get-Date -Format 'yyyyMMddHHmmssfff')) -Force
    }
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-CxxuUtf8Text -Path $Path -Text (ConvertTo-CxxuConfigText -Model $Model) -NoNewline -Bom
}
function Set-CxxuConfigModelValues
{
    # 一次读取、批量修改、一次写回；未知键只警告（旧文件已备份）。
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Values
    )
    $state = Read-CxxuConfigState -Path $Path
    if ($state.Unknown.Count)
    {
        Write-Warning ("用户配置含未识别键，重写会忽略：{0}；旧文件已备份。" -f ($state.Unknown -join '、'))
    }
    foreach ($key in $Values.Keys)
    {
        if (-not (Set-CxxuModelValueByKey -Model $state.Model -Key ([string]$key) -Value $Values[$key]))
        {
            throw "配置键未在 components.psd1/config.defaults.psd1 中定义：$key"
        }
    }
    Write-CxxuConfigState -Path $Path -Model $state.Model
}
function Get-CxxuConfigStateTextValue
{
    # 把模型值转成环境变量/表格里的字符串。
    param($Value)
    if ($Value -is [bool]) { if ($Value) { return 'True' } return 'False' }
    if ($Value -is [array]) { return ($Value -join ',') }
    return [string]$Value
}
function Import-CxxuConfigData
{
    # 读用户配置(不导出):优先标准 psd1 解析;失败时按 UTF-8 读出另存带 BOM 的临时文件再解析。
    # 5.1 对无 BOM 的中文配置按 ANSI 页解码,直接解析会失败;
    # 该兜底让历史配置无需先重置即可继续生效,真实语法错误仍会在第二次解析时暴露。
    # 会话里识别不到 Import-PowerShellDataFile 时,Read-CxxuDataFile 已按 UTF-8 走 AST 解析,无需临时文件。
    param([Parameter(Mandatory)][string]$Path)
    try
    {
        return Read-CxxuDataFile -Path $Path
    }
    catch
    {
        if (-not $script:CxxuDataFileReaderAvailable) { throw }
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('cxxu-cfg-' + [guid]::NewGuid().ToString('N') + '.psd1')
        try
        {
            Write-CxxuUtf8Text -Path $tmp -Text (Read-CxxuUtf8Text -Path $Path) -NoNewline -Bom
            return Import-PowerShellDataFile -LiteralPath $tmp -ErrorAction Stop
        }
        finally
        {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction Ignore
        }
    }
}
function Import-CxxuConfig
{
    <#
    .SYNOPSIS
    读用户配置(默认 ~/.cxxu/config.psd1):只填环境变量的空位,不覆盖已设的值。
    .DESCRIPTION
    支持 v2 嵌套结构（SchemaVersion=2，Components/Settings）与旧版平坦键；两者都按
    环境变量 > 配置文件 > 默认值 的优先级注入。组件清单与默认值见 PS/Init/components.psd1，
    Settings 默认值见 PS/Init/config.defaults.psd1。
    缺文件静默跳过（首用零成本）；文件损坏或含未知键时警告，但都不阻塞 init。
    本函数记录哪些键由配置文件注入，供 Get-CxxuConfig 标注来源。
    init 首步自动调；改完配置重开终端（或 init -Force）生效。-Path 供测试/便携覆盖。
    .EXAMPLE
    Import-CxxuConfig
    #>
    [CmdletBinding()]
    param(
        # 配置文件路径(默认 ~/.cxxu/config.psd1,仓库外,本机生效)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    $script:CxxuConfigAppliedFromFile = @{}
    $state = try { Read-CxxuConfigState -Path $Path } catch
    {
        Write-Warning "用户配置读失败($Path):$($_.Exception.Message);已忽略,用默认值。"
        return
    }
    $global:CxxuConfigModel = $state.Model
    if (-not $state.Exists) { return }
    if ($state.Unknown.Count)
    {
        Write-Warning ("用户配置含未知键,已忽略:{0};可用键见 Get-CxxuConfig。" -f ($state.Unknown -join '、'))
    }
    foreach ($item in (Read-CxxuConfigDefaultList))
    {
        $key = [string]$item.Key
        if (-not $state.Present.ContainsKey($key)) { continue }
        if (-not [string]::IsNullOrEmpty((Get-Item "env:$key" -ErrorAction Ignore).Value)) { continue }
        $value = Get-CxxuModelValueByKey -Model $state.Model -Key $key
        $text = Get-CxxuConfigStateTextValue $value
        if ([string]::IsNullOrEmpty($text)) { continue }
        Set-Item "env:$key" -Value $text
        $script:CxxuConfigAppliedFromFile[$key] = $text
        Write-Verbose "用户配置生效: $key=$text"
    }
}
function Get-CxxuConfig
{
    <#
    .SYNOPSIS
    查看配置开关的当前生效值、来源与默认值。
    .DESCRIPTION
    逐项列出组件与 init 行为开关,来源为“环境变量”“配置文件”“默认值”之一:
    环境变量优先于用户配置文件,配置文件优先于仓库默认值(组件见 PS/Init/components.psd1,
    Settings 见 PS/Init/config.defaults.psd1)。
    配置文件的键由 init 首步注入环境变量,因此来源标注依赖本会话的注入记录;未跑过 init 时,
    已存在的环境变量一律标为“环境变量”。输出为对象,可用 Format-List 查看完整说明。
    .EXAMPLE
    Get-CxxuConfig
    .EXAMPLE
    Get-CxxuConfig | Format-List
    #>
    [CmdletBinding()]
    param(
        # 用户配置文件路径(默认 ~/.cxxu/config.psd1)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    $state = try { Read-CxxuConfigState -Path $Path } catch
    {
        Write-Warning "用户配置读失败($Path):$($_.Exception.Message);来源按环境变量与默认值判定。"
        [pscustomobject]@{ Model = New-CxxuConfigModel; Present = @{}; Unknown = @(); Exists = $false }
    }
    foreach ($item in (Read-CxxuConfigDefaultList))
    {
        $key = [string]$item.Key
        $envValue = (Get-Item "env:$key" -ErrorAction Ignore).Value
        if (-not [string]::IsNullOrEmpty($envValue))
        {
            $value = $envValue
            if ($script:CxxuConfigAppliedFromFile -and $script:CxxuConfigAppliedFromFile[$key] -eq $envValue) { $source = '配置文件' }
            else { $source = '环境变量' }
        }
        elseif ($state.Present.ContainsKey($key))
        {
            $value = Get-CxxuConfigStateTextValue (Get-CxxuModelValueByKey -Model $state.Model -Key $key)
            $source = '配置文件'
        }
        else
        {
            $value = Get-CxxuConfigStateTextValue $item.Default
            $source = '默认值'
        }
        [pscustomobject]@{
            Name        = [string]$item.Name
            Key         = $key
            Value       = [string]$value
            Source      = $source
            Default     = (Get-CxxuConfigStateTextValue $item.Default)
            Description = [string]$item.Description
        }
    }
}
function New-CxxuConfigTemplate
{
    <#
    .SYNOPSIS
    生成用户配置模板(默认 ~/.cxxu/config.psd1):有文件默认不动,加 -Force 覆盖。
    .DESCRIPTION
    模板由组件清单(PS/Init/components.psd1)与 Settings 默认值(PS/Init/config.defaults.psd1)
    渲染为 SchemaVersion=2 的嵌套结构,组件与选项都带取值说明。
    环境变量优先于本文件;要恢复默认偏好用 Reset-CxxuConfig,查看生效值用 Get-CxxuConfig/Get-CxxuComponent。
    .EXAMPLE
    New-CxxuConfigTemplate
    .EXAMPLE
    New-CxxuConfigTemplate -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 配置文件路径(默认 ~/.cxxu/config.psd1,仓库外,本机生效)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1'),
        # 已有文件也覆盖
        [switch]$Force
    )
    if ((Test-Path -LiteralPath $Path) -and -not $Force)
    {
        Write-Host "模板已存在($Path):改值直接编辑;重建加 -Force。"
        return
    }
    $model = New-CxxuConfigModel
    if (-not $model.Components.Count)
    {
        Write-Warning "组件清单缺失或为空,未生成模板:$(Join-Path $script:CxxuModuleRoot 'components.psd1')"
        return
    }
    if ($PSCmdlet.ShouldProcess($Path, '写用户配置模板'))
    {
        Write-CxxuConfigState -Path $Path -Model $model
        Write-Host "模板已写 $Path"
    }
}
function Reset-CxxuConfig
{
    <#
    .SYNOPSIS
    把用户配置重置为仓库默认偏好(默认 ~/.cxxu/config.psd1)。
    .DESCRIPTION
    以仓库 PS/Init/components.psd1 与 config.defaults.psd1 为准重写用户配置文件;各设备拉同一仓库后执行本命令,
    即可得到同一份默认偏好。重置只改写配置文件,不改当前会话:$env: 中的值在会话结束前仍然生效,
    重开终端(或 init -Force)后按新配置生效。
    若同名环境变量已在用户级或机器级持久化,按“环境变量 > 配置文件”仍会覆盖默认值;
    本命令会逐项列出这些覆盖项及其作用域。-WhatIf 只显示将改写的路径,不落盘。
    .EXAMPLE
    Reset-CxxuConfig
    .EXAMPLE
    Reset-CxxuConfig -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 配置文件路径(默认 ~/.cxxu/config.psd1,仓库外,本机生效)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    $blocked = New-Object System.Collections.Generic.List[string]
    foreach ($item in (Read-CxxuConfigDefaultList))
    {
        $key = [string]$item.Key
        $value = (Get-Item "env:$key" -ErrorAction Ignore).Value
        if ([string]::IsNullOrEmpty($value)) { continue }
        if ($script:CxxuConfigAppliedFromFile -and $script:CxxuConfigAppliedFromFile[$key] -eq $value) { continue }
        $scope = '进程级'
        try
        {
            if ($value -eq [Environment]::GetEnvironmentVariable($key, 'User')) { $scope = '用户级' }
            elseif ($value -eq [Environment]::GetEnvironmentVariable($key, 'Machine')) { $scope = '机器级' }
        }
        catch { $scope = '进程级' }
        $blocked.Add("$key=$value($scope)")
    }
    if ($PSCmdlet.ShouldProcess($Path, '重置为仓库默认偏好'))
    {
        New-CxxuConfigTemplate -Path $Path -Force -Confirm:$false
        Write-Host '重置完成:重开终端(或 init -Force)后按默认偏好生效。'
    }
    if ($blocked.Count)
    {
        Write-Warning ("以下环境变量优先于配置文件,重置后仍按环境变量值生效:{0}。需要彻底回到默认时,先清除对应环境变量(如 Add-EnvVar 或 [Environment]::SetEnvironmentVariable)。" -f ($blocked -join '、'))
    }
}
function Set-PsStartupTier
{
    <#
    .SYNOPSIS
    切换启动档位(Minimal/Fast/Balanced),可持久化到用户配置。
    .DESCRIPTION
    档位决定 init 的步骤上限：Minimal 只保留核心变量/别名、基础 PSReadLine 与 prompt；
    Fast 再加 advanced PSReadLine 与 Argc/GitCompletion；Balanced 保持原有默认。
    组件开关不能突破档位上限；被档位挡住的组件可用 Get-CxxuComponent 查看 TierAllowed。
    本命令只切换当前进程并可选写入 ~/.cxxu/config.psd1；当前会话已加载的模块不会卸载，
    新开终端(或 init -Force)后按新档位重新构建步骤表。
    .PARAMETER Tier
    目标档位：Minimal、Fast、Balanced。
    .PARAMETER Persist
    同时写入用户配置的 Settings.PsStartupTier；已有文件先备份，再规范重写。
    .PARAMETER Path
    用户配置文件路径，默认 ~/.cxxu/config.psd1；只影响本次持久化。
    .EXAMPLE
    Set-PsStartupTier Fast
    .EXAMPLE
    Set-PsStartupTier Fast -Persist
    .EXAMPLE
    Set-PsStartupTier Minimal -Persist -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Minimal', 'Fast', 'Balanced')]
        [string]$Tier,
        # 写入用户配置，重开终端后保持
        [switch]$Persist,
        # 用户配置文件路径(默认 ~/.cxxu/config.psd1)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    if ($PSCmdlet.ShouldProcess($Path, "切换启动档位为 $Tier"))
    {
        $env:PsStartupTier = $Tier
        if ($Persist)
        {
            Set-CxxuConfigModelValues -Path $Path -Values @{ PsStartupTier = $Tier }
        }
        Write-Host "PsStartupTier=$Tier；当前会话已加载的模块不会卸载，新开终端(或 init -Force)后生效。"
    }
}
function Disable-PsPlugin
{
    <#
    .SYNOPSIS
    停用体验插件(当会话生效;加 -Persist 长期禁用,重开也关)。
    .DESCRIPTION
    插件注册表：Fzf(PSFzf 快捷键)/Zoxide(z 跳转)/Predictor(命令名 ListView 预测)/
    Tab(CxxuTab 命令名 Tab 模糊，默认开,不需要时停用)/
    Argc(argc-completions 参数补全,默认开,懒加载)/GitCompletion(git/gitk 的 Tab 补全)/
    Carapace(外部 CLI 参数补全,默认关,首个 Tab 懒加载)/
    PSCompletions(约 200 个命令的参数补全)/Fnm(node 版本切换)/ScoopSearch(scoop 搜索加速)；
    后三项默认关，启用后由 init 按组件配置加载。
    停用只关本命令的合并/加载，引擎原生行为不受影响；持开关逐调用判定，无需重载。
    已注册的 Native completer 无法在当前会话撤销：停用 GitCompletion/Carapace 后需重开终端，
    剩余来源才会重新接管 git/gitk。Argc 例外：停用时若 carapace 可用会重新注册它，
    重叠命令在当前会话即交还 carapace；Enable-PsPlugin Argc 会再注册回来。
    停用 Carapace 时 completer 按 PsCarapace 门控立即返回空，重叠命令交回 argc，
    git/gitk 按 PsGitCompletionSource 解析后当场回落。
    -Persist 写 ~/.cxxu/config.psd1 的 Components 段（v2 结构，旧文件先备份）。
    .EXAMPLE
    Disable-PsPlugin Tab
    .EXAMPLE
    Disable-PsPlugin Predictor -Persist
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 插件名(Tab 补全可用)
        [Parameter(Mandatory)]
        [ValidateSet('Fzf', 'Zoxide', 'Predictor', 'Tab', 'Argc', 'GitCompletion', 'Carapace', 'PSCompletions', 'Fnm', 'ScoopSearch')]
        [string]$Name,
        # 写入用户配置文件,长期有效(否则只关当会话)
        [switch]$Persist,
        # 配置文件路径(默认 ~/.cxxu/config.psd1)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    if ($PSCmdlet.ShouldProcess($Name, '停用插件'))
    {
        if ($Name -eq 'GitCompletion')
        {
            Set-Item 'env:PsGitCompletion' -Value 'False'
            Set-Item 'env:PsGitCompletionSource' -Value 'Argc'
            if ($Persist)
            {
                Set-CxxuConfigModelValues -Path $Path -Values @{ PsGitCompletion = $false; PsGitCompletionSource = 'Argc' }
            }
            Write-Host "$Name 已停用(当会话)。"
            Write-Host '当前会话已注册的 git/gitk completer 无法撤销；重开终端后 argc 才会重新接管。'
        }
        else
        {
            Disable-CxxuComponent -Id $Name -Persist:$Persist -Path $Path
            if ($Name -eq 'Carapace')
            {
                # carapace 的 completer 带 PsCarapace 门控，停用后已注册的绑定立即返回空；
                # argc 已启用时重新注册，让重叠命令当场换回 argc（与停用 Argc 时对称）。
                # git/gitk 由 carapace 负责时先按来源解析回落，再让 argc 注册把它们纳入。
                $gitFallback = $null
                if ($global:PsCarapaceGit)
                {
                    $global:PsCarapaceGit = $false
                    $gitFallback = Get-CxxuGitCompletionSource
                }
                # 回落到 git-completion 时先注册，argc 重新注册就会继续让出 git/gitk。
                if ($gitFallback -eq 'GitCompletion' -and (Test-CxxuGitCompletionInstalled))
                {
                    # -Force：git-completion 可能在本会话更早注册过，需覆盖 carapace 留在同名的 completer。
                    Register-GitCompletion -Force
                }
                $argcOn = -not [string]::IsNullOrWhiteSpace($env:PsArgc) -and
                    $env:PsArgc -notmatch '^(False|0|No|Off)$'
                if ($argcOn -and $global:PsArgcLoaded)
                {
                    Initialize-ArgcCompletions -Force
                    Write-Host 'carapace 已停用；argc 已重新注册，重叠命令由 argc 接管。'
                }
                elseif ($argcOn)
                {
                    Write-Host 'carapace 已停用；argc 尚未注册，下一个 Tab 由 argc 接管重叠命令。'
                }
                else
                {
                    Write-Host 'carapace 已停用；argc 未启用，当前会话这些命令无候选，重开终端后回到原生补全。'
                }
                if ($gitFallback -eq 'GitCompletion')
                {
                    if ($global:PsGitCompletion) { Write-Host 'git/gitk 已改由 git-completion 接管。' }
                    elseif (Test-CxxuGitCompletionInstalled) { Write-Host 'git-completion 未重新注册（已加载或来源未指向它），git/gitk 维持当前来源。' }
                    else { Write-Host 'git/gitk 暂无来源：git-completion 未安装，重开终端后按来源配置回落。' }
                }
                elseif ($gitFallback -eq 'Argc')
                {
                    $argcGit = $argcOn -and $global:PsArgcLoaded -and
                        $global:PsArgcScripts -and $global:PsArgcScripts.ContainsKey('git')
                    if ($argcGit)
                    {
                        Write-Host 'git/gitk 已改由 argc 接管；偏好 git-completion 可执行 Set-GitCompletionSource GitCompletion。'
                    }
                    elseif ($argcOn)
                    {
                        Write-Host 'git/gitk 将在 argc 注册后由它接管；偏好 git-completion 可执行 Set-GitCompletionSource GitCompletion。'
                    }
                    else
                    {
                        $global:PsGitCompletionActive = if ($global:PsGitCompletion) { 'GitCompletion' } else { 'Pending' }
                        Write-Host 'git/gitk 暂无来源：argc 未启用；重开终端后按来源配置回落，或执行 Set-GitCompletionSource GitCompletion。'
                    }
                }
            }
            elseif ($Name -eq 'Argc')
            {
                # 已注册的 argc completer 不随开关撤销，只会返回空；carapace 可用时立即重新注册，
                # 让重叠命令（npm、docker 等）在当前会话就交还 carapace，不必重开终端。
                $carapaceOn = -not [string]::IsNullOrWhiteSpace($env:PsCarapace) -and
                    $env:PsCarapace -notmatch '^(False|0|No|Off)$' -and
                    $null -ne (Get-Command carapace -ErrorAction SilentlyContinue)
                if ($carapaceOn)
                {
                    Initialize-Carapace -Force
                    if ($global:PsCarapaceLoaded) { Write-Host 'carapace 已重新注册，当前会话接管重叠命令的参数补全。' }
                }
                else
                {
                    Write-Host '没有可接管的 carapace；当前会话已注册的 argc completer 无法撤销，重开终端后这些命令才回到原生补全。'
                }
                # argc 的 git completer 已被 PsArgc 门控停用；来源仍指向 GitCompletion 时当场接回。
                if ((Get-CxxuGitCompletionSource) -eq 'GitCompletion' -and (Test-CxxuGitCompletionInstalled))
                {
                    Register-GitCompletion -Force
                    Write-Host 'git/gitk 已交回 git-completion。'
                }
            }
            elseif ($Name -in @('PSCompletions', 'Fnm', 'ScoopSearch'))
            {
                Write-Host '当前会话已加载的模块或钩子无法撤销；重开终端后完全停用。'
            }
        }
    }
}
function Enable-PsPlugin
{
    <#
    .SYNOPSIS
    启用体验插件(当会话生效;加 -Persist 长期启用,重开也开)。
    .DESCRIPTION
    启用是显式开(环境变量 True,盖过配置文件)。GitCompletion 额外切换来源并注册 git/gitk；
    其余组件统一走 Enable-CxxuComponent -Now：先写开关，再调用清单里的 InitNow（未声明时用 Init）。
    Fzf/Tab 在 pwsh 7+ 继续补手势桩，5.1 的 Tab 直接导入 CxxuTab；Argc 的即时调用只装 Tab 桩，
    argc 的首次注册仍由外部 CLI 参数位 Tab 触发；Predictor/Zoxide 若 OnIdle 单发已过，仍建议重开终端
    (或 Register-PsUxLazyLoad -Now 立装)。
    .EXAMPLE
    Enable-PsPlugin Tab
    .EXAMPLE
    Enable-PsPlugin Predictor -Persist
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 插件名(Tab 补全可用)
        [Parameter(Mandatory)]
        [ValidateSet('Fzf', 'Zoxide', 'Predictor', 'Tab', 'Argc', 'GitCompletion', 'Carapace', 'PSCompletions', 'Fnm', 'ScoopSearch')]
        [string]$Name,
        # 写入用户配置文件,长期有效(否则只开当会话)
        [switch]$Persist,
        # 配置文件路径(默认 ~/.cxxu/config.psd1)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    if ($PSCmdlet.ShouldProcess($Name, '启用插件'))
    {
        if ($Name -eq 'GitCompletion')
        {
            Set-Item 'env:PsGitCompletion' -Value 'True'
            Set-Item 'env:PsGitCompletionSource' -Value 'GitCompletion'
            if ($Persist)
            {
                Set-CxxuConfigModelValues -Path $Path -Values @{ PsGitCompletion = $true; PsGitCompletionSource = 'GitCompletion' }
            }
            Write-Host "$Name 已启用(当会话)。"
            if (Test-CxxuGitCompletionInstalled)
            {
                # -Force：从其他来源切回时覆盖同名 completer。
                Register-GitCompletion -Force
            }
            else
            {
                Write-Warning 'git-completion 模块未安装：先执行 Deploy-CompletionStack -IncludeGitCompletion，再启用 GitCompletion。'
            }
        }
        else
        {
            Enable-CxxuComponent -Id $Name -Persist:$Persist -Path $Path -Now
            if ($Name -eq 'Argc' -and $global:PsArgcLoaded)
            {
                # 停用期间 carapace 可能已重新注册并覆盖同名 completer，重开时再注册回来；
                # 未注册过时仍等首次外部 CLI 参数补全由桩注册。
                Initialize-ArgcCompletions -Force
            }
        }

        if ((($Name -eq 'Fzf') -or ($Name -eq 'Tab')) -and ($PSVersionTable.PSVersion.Major -ge 7))
        {
            # 立装桩即时生效(幂等,只补缺;交互门由安装器自己判定,重定向下静默跳过)
            Install-PsUxGestureStubs -ErrorAction SilentlyContinue
        }
        elseif (($Name -eq 'Tab') -and ($PSVersionTable.PSVersion.Major -lt 7))
        {
            # 5.1 直接导入 CxxuTab 立即生效(默认关,显式开启才走到这里)
            Import-Module CxxuTab -Global -ErrorAction SilentlyContinue
        }
    }
}

function Get-GitCompletionSource
{
    <#
    .SYNOPSIS
    查看 git/gitk Tab 补全的来源配置、解析结果与当前会话已注册来源。
    .DESCRIPTION
    只读检查：不修改配置，也不加载补全模块或触发首个 Tab。
    结果分三层，避免把配置值当成实际生效值：
    - ConfiguredSource：PsGitCompletionSource 的当前值；为空时显示“未设置”，表示沿用 PsGitCompletion 旧语义。
    - EffectiveSource：按开关、安装状态与回落规则解析出的来源；Auto 的顺序为 GitCompletion、Carapace、Argc。
    - RegisteredSource：当前会话最后接管 git/gitk 补全的来源；Pending 表示尚未注册，posh-git 已导入时优先显示 PoshGit。
    Fallback 非空表示配置来源不可用并已回落；Note 给出下一步命令或状态说明。
    加 -List 按来源逐行列出候选的安装、版本、启用与当前状态，类似 Get-Module -ListAvailable；
    该模式会调用 carapace/argc 的版本命令，仅用于人工查看。
    .EXAMPLE
    Get-GitCompletionSource
    .EXAMPLE
    Get-GitCompletionSource | Format-List
    .EXAMPLE
    Get-GitCompletionSource -List | Format-Table -AutoSize
    .EXAMPLE
    Get-GitCompletionSource | Select-Object ConfiguredSource, EffectiveSource, RegisteredSource
    #>
    [CmdletBinding()]
    param(
        # 按来源列出全部候选（安装、版本、启用、当前状态与安装命令）
        [switch]$List
    )

    $switchOff = '^(False|0|No|Off)$'
    $configured = [string]$env:PsGitCompletionSource
    $configuredLabel = if ([string]::IsNullOrWhiteSpace($configured)) { '未设置' } else { $configured.Trim() }
    $effective = Get-CxxuGitCompletionSource

    $gitInstalled = Test-CxxuGitCompletionInstalled
    $gitModule = if ($gitInstalled) { Get-Module -ListAvailable git-completion | Sort-Object Version -Descending | Select-Object -First 1 }
    $carapaceInstalled = [bool](Get-Command carapace -ErrorAction SilentlyContinue)
    $argcInstalled = [bool](Get-Command argc -ErrorAction SilentlyContinue)
    $poshGitModule = Get-Module -ListAvailable posh-git | Sort-Object Version -Descending | Select-Object -First 1
    $poshGitLoaded = [bool](Get-Module posh-git)
    $carapaceEnabled = (-not [string]::IsNullOrWhiteSpace($env:PsCarapace)) -and ($env:PsCarapace -notmatch $switchOff)
    $argcEnabled = (-not [string]::IsNullOrWhiteSpace($env:PsArgc)) -and ($env:PsArgc -notmatch $switchOff)
    $gitRegistered = [bool]$global:PsGitCompletion
    $carapaceLoaded = [bool]$global:PsCarapaceLoaded
    $carapaceOwnsGit = [bool]$global:PsCarapaceGit
    $argcLoaded = [bool]$global:PsArgcLoaded

    $registered = [string]$global:PsGitCompletionActive
    if ([string]::IsNullOrWhiteSpace($registered))
    {
        # 旧会话没有来源标记：按各来源的注册状态推断，carapace 需已加载才算真正接管。
        if ($carapaceOwnsGit -and $carapaceLoaded) { $registered = 'Carapace' }
        elseif ($gitRegistered) { $registered = 'GitCompletion' }
        elseif ($argcLoaded) { $registered = 'Argc' }
        else { $registered = 'Pending' }
    }
    # posh-git 导入时注册同名 Native completer，按导入顺序可能与实际候选不一致。
    if ($poshGitLoaded) { $registered = 'PoshGit' }

    $fallback = ''
    if ($configuredLabel -notmatch '^(未设置|(?i:Auto))$' -and $effective -ne $configuredLabel)
    {
        $fallback = "配置为 $configuredLabel，当前开关或安装状态不满足，回落到 $effective"
    }

    $gitState = if (-not $gitInstalled) { '未安装' }
        elseif (-not $gitModule) { '已安装，未注册' }
        elseif ($gitRegistered) { "已安装 $($gitModule.Version)，已注册" }
        else { "已安装 $($gitModule.Version)，未注册" }
    $carapaceState = if (-not $carapaceInstalled) { '未安装' }
        elseif (-not $carapaceEnabled) { '已安装，未启用' }
        elseif ($carapaceOwnsGit -and $carapaceLoaded) { '已启用，已加载并接管 git/gitk' }
        elseif ($carapaceOwnsGit) { '已启用，待参数位 Tab 加载后接管 git/gitk' }
        elseif ($carapaceLoaded) { '已启用，已加载，git/gitk 已排除' }
        else { '已启用，待参数位 Tab 加载，git/gitk 已排除' }
    $argcState = if (-not $argcInstalled) { '未安装' }
        elseif ($global:PsArgcUnavailable) { '已安装，补全库未就绪' }
        elseif (-not $argcEnabled) { '已安装，未启用' }
        elseif ($registered -eq 'Argc') { '已启用，已注册并接管 git/gitk' }
        elseif ($argcLoaded) { '已启用，已注册，git/gitk 已排除' }
        else { '已启用，待参数位 Tab 注册' }
    $poshGitState = if ($poshGitLoaded) { "已导入 $($poshGitModule.Version)，注册同名 completer（后注册者生效）" }
        elseif ($poshGitModule) { "已安装 $($poshGitModule.Version)，未导入" }
        else { '未安装' }

    if ($List)
    {
        # 候选清单：每行一个来源，字段对齐 Get-Module 的“是否安装/启用”视角。
        $carapaceVersion = ''
        if ($carapaceInstalled)
        {
            try { $carapaceVersion = [string]@(& carapace --version 2>$null)[0] } catch { }
        }
        $argcVersion = ''
        if ($argcInstalled)
        {
            try { $argcVersion = [string]@(& argc --argc-version 2>$null)[0] } catch { }
        }
        $gitEnabled = $env:PsGitCompletion -notmatch $switchOff
        $gitStatus = if (-not $gitInstalled) { '未安装' }
            elseif (-not $gitEnabled) { '已安装，组件已停用' }
            elseif (-not $gitRegistered) { '已安装，未注册' }
            elseif ($registered -eq 'GitCompletion') { "已安装 $($gitModule.Version)，当前生效" }
            else { "已安装 $($gitModule.Version)，已注册但被 $registered 覆盖" }

        return @(
            [pscustomobject]@{
                Source    = 'GitCompletion'
                Version   = if ($gitModule) { [string]$gitModule.Version } else { '' }
                Installed = $gitInstalled
                Enabled   = [bool]$gitEnabled
                Current   = ($registered -eq 'GitCompletion')
                Status    = $gitStatus
                Install   = 'Deploy-CompletionStack -IncludeGitCompletion'
            }
            [pscustomobject]@{
                Source    = 'Carapace'
                Version   = $carapaceVersion
                Installed = $carapaceInstalled
                Enabled   = [bool]$carapaceEnabled
                Current   = ($registered -eq 'Carapace')
                Status    = $carapaceState
                Install   = 'Deploy-Carapace -Enable'
            }
            [pscustomobject]@{
                Source    = 'Argc'
                Version   = $argcVersion
                Installed = $argcInstalled
                Enabled   = [bool]$argcEnabled
                Current   = ($registered -eq 'Argc')
                Status    = $argcState
                Install   = 'Deploy-CompletionStack -IncludeArgc'
            }
            [pscustomobject]@{
                Source    = 'PoshGit'
                Version   = if ($poshGitModule) { [string]$poshGitModule.Version } else { '' }
                Installed = [bool]$poshGitModule
                Enabled   = [bool]$poshGitLoaded
                Current   = ($registered -eq 'PoshGit')
                Status    = $poshGitState
                Install   = 'Install-Module posh-git -Scope CurrentUser -Force'
            }
        )
    }

    $sourceReady = switch ($effective)
    {
        'GitCompletion' { $gitInstalled }
        'Carapace' { $carapaceEnabled -and $carapaceInstalled }
        'Argc' { $argcEnabled -and $argcInstalled -and -not $global:PsArgcUnavailable }
        default { $false }
    }
    $note = if ($fallback) { "按 EffectiveSource 的条件修复开关或安装，或用 Set-GitCompletionSource 改选可用来源。" }
        elseif (-not $sourceReady) { "解析来源 $effective 当前不可用（开关关闭或未安装）；用 Set-GitCompletionSource 改选可用来源，或打开对应开关。" }
        elseif ($poshGitLoaded) { '检测到 posh-git 已导入：它也在导入时注册同名 git completer，后注册者生效；不要与其他来源混用，切换前先 Remove-Module posh-git。' }
        elseif ($registered -eq 'Pending') { '当前会话尚未注册；首次外部 CLI 参数补全时完成，本检查不会触发加载。' }
        elseif ($effective -eq 'Argc' -and -not $argcLoaded) { "$registered 仍在当前会话生效；argc 尚未注册，首次外部 CLI 参数补全接管后会覆盖它。需要立即切回可执行 Set-GitCompletionSource $registered。" }
        elseif ($effective -ne $registered) { "解析来源为 $effective，当前会话仍由 $registered 注册；执行 Set-GitCompletionSource $effective 可当场重注册。" }
        else { '' }

    [pscustomobject]@{
        ConfiguredSource = $configuredLabel
        EffectiveSource  = $effective
        Available        = [bool]$sourceReady
        RegisteredSource = $registered
        Fallback         = $fallback
        GitCompletion    = $gitState
        Carapace         = $carapaceState
        Argc             = $argcState
        PoshGit          = $poshGitState
        GitExcluded      = [bool](@([string]$env:CARAPACE_EXCLUDES -split ',' | ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -match '^(?i:git|gitk)$' }).Count)
        Note             = $note
    }
}

function Set-GitCompletionSource
{
    <#
    .SYNOPSIS
    在 git-completion、carapace、argc 之间切换 git/gitk 的 Tab 补全来源。
    .DESCRIPTION
    来源由配置键 PsGitCompletionSource 决定（Auto/GitCompletion/Carapace/Argc），
    由 init 在启动时读取；本命令只改环境变量与用户配置，不修改 profile。
    - GitCompletion：启动时注册 git-completion；
    - Carapace：同时打开 PsCarapace，由 init 注册懒加载桩并让它接管 git/gitk；
      carapace 停用或未加载时按可用来源回落（git-completion 优先，其次 argc）。
    - Argc：同时打开 PsArgc，并当场注册 argc completer（不推荐：argc 的 git 补全缺 --cached/--staged 等选项）。
    选来源即启用对应组件：GitCompletion/Carapace/Argc 之前处于停用状态也会被打开；
    但不会停用其他组件，切走时保留原状态，供回落。
    carapace 的额外排除项用 PsCarapaceExcludes 配置，不再写 profile。
    -Persist 把来源与开关写入 ~/.cxxu/config.psd1；不加时只改当前会话。
    切换会在当前会话重新注册对应 completer，git/gitk 立即生效；argc 首次注册约 0.15–0.25 秒。
    .EXAMPLE
    Set-GitCompletionSource GitCompletion
    .EXAMPLE
    Set-GitCompletionSource Carapace -Persist
    .EXAMPLE
    Set-GitCompletionSource Argc -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 目标来源：GitCompletion | Carapace | Argc
        [Parameter(Mandatory)]
        [ValidateSet('GitCompletion', 'Carapace', 'Argc')]
        [string]$Source,
        # 把来源及相关开关写入用户配置文件，重开终端后保持
        [switch]$Persist,
        # 用户配置文件路径（-Persist 时写入）
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )

    $wantGitCompletion = $Source -eq 'GitCompletion'

    $applied = $false
    if ($PSCmdlet.ShouldProcess("git 补全来源 -> $Source", '设置'))
    {
        Set-Item 'env:PsGitCompletionSource' -Value $Source
        # 选来源即打开该来源的组件开关；但不反向停用其他组件，切走时保留原状态供回落。
        if ($wantGitCompletion) { Set-Item 'env:PsGitCompletion' -Value 'True' }
        if ($Source -eq 'Carapace') { Set-Item 'env:PsCarapace' -Value 'True' }
        if ($Source -eq 'Argc') { Set-Item 'env:PsArgc' -Value 'True' }
        if ($Persist)
        {
            $updates = @{ PsGitCompletionSource = $Source }
            if ($wantGitCompletion) { $updates['PsGitCompletion'] = $true }
            if ($Source -eq 'Carapace') { $updates['PsCarapace'] = $true }
            if ($Source -eq 'Argc') { $updates['PsArgc'] = $true }
            Set-CxxuConfigModelValues -Path $Path -Values $updates
        }
        $applied = $true
    }

    if ($Source -eq 'GitCompletion')
    {
        if (Test-CxxuGitCompletionInstalled)
        {
            $global:PsCarapaceGit = $false
            if ($PSCmdlet.ShouldProcess('git-completion', '注册 git/gitk completer')) { Register-GitCompletion -Force }
        }
        else
        {
            Write-Warning 'git-completion 模块未安装：先执行 Deploy-CompletionStack -IncludeGitCompletion。'
        }
    }
    elseif ($Source -eq 'Carapace')
    {
        if (Get-Command carapace -ErrorAction SilentlyContinue)
        {
            if ($PSCmdlet.ShouldProcess('carapace', '加载并重新注册补全')) { Initialize-Carapace -Force }
        }
        else
        {
            Write-Warning '未检测到 carapace：先执行 Deploy-Carapace 安装。'
        }
    }
    elseif (-not (Get-Command argc -ErrorAction SilentlyContinue))
    {
        Write-Warning '未检测到 argc：先执行 Deploy-CompletionStack -IncludeArgc 或 Deploy-ArgcCompletions。'
    }
    else
    {
        # 选 Argc 即强制启用并当场注册；未加载过也直接注册，不再等首个 Tab。
        $global:PsCarapaceGit = $false
        if ($PSCmdlet.ShouldProcess('argc', '注册 git/gitk completer')) { Initialize-ArgcCompletions -Force }
        if ($global:PsArgcUnavailable)
        {
            Write-Warning 'argc 补全库未就绪（仓库或依赖缺失）：先执行 Deploy-CompletionStack -IncludeArgc 或 Deploy-ArgcCompletions。'
        }
    }

    Write-Host ("git 补全来源：{0}" -f $Source)
    if ($applied)
    {
        Write-Host ("当前会话：PsGitCompletionSource={0}，PsGitCompletion={1}" -f $Source, $env:PsGitCompletion)
        if ($Source -eq 'Carapace') { Write-Host '当前会话：PsCarapace=True' }
        if ($Source -eq 'Argc') { Write-Host ("当前会话：PsArgc={0}" -f $env:PsArgc) }
    }
    else
    {
        Write-Host '当前会话未改动（-WhatIf）。'
    }
    if ($Persist)
    {
        if ($applied) { Write-Host '已写入用户配置，重开终端后保持。' }
        else { Write-Host '未写入用户配置（-WhatIf）。' }
    }
    else
    {
        Write-Host '未加 -Persist：只改当前会话，重开终端后按配置文件决定。'
    }
    if (($Source -ne 'Carapace') -and ($env:PsCarapace -and ($env:PsCarapace -notmatch '^(False|0|No|Off)$')))
    {
        Write-Host 'carapace 仍处于启用状态，只让出 git/gitk；需要停止加载用 Disable-PsPlugin Carapace -Persist。'
    }
    if (Get-Module posh-git)
    {
        Write-Warning 'posh-git 已导入并注册同名 git completer；它的注册可能覆盖本次切换，建议先 Remove-Module posh-git。'
    }
    if ($Source -eq 'GitCompletion' -and $global:PsGitCompletion)
    {
        Write-Host 'git/gitk 已在当前会话由 git-completion 注册。'
    }
    elseif ($Source -eq 'Carapace' -and $global:PsCarapaceGit -and $global:PsCarapaceLoaded)
    {
        Write-Host 'git/gitk 已在当前会话改由 carapace 接管。'
    }
    elseif ($Source -eq 'Argc' -and $global:PsArgcLoaded)
    {
        Write-Host 'git/gitk 已在当前会话改由 argc 接管。'
    }
    else
    {
        if ($applied) { Write-Host 'git/gitk 未在当前会话重新注册；按来源条件修复后，首次外部 CLI 参数补全或下一次切换会完成接管。' }
        else { Write-Host '当前会话未改动（-WhatIf），未执行注册。' }
    }
}

function Complete-CxxuComponentArgument
{
    # 按需读取并缓存清单，不查询用户配置、探测依赖或加载补全组件，避免把管理补全变成启动热路径。
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'CommandAst', Justification = '原生补全回调的固定签名；仅使用原生绑定结果，不执行命令行表达式。')]
    param(
        [string]$CommandName,
        [string]$ParameterName,
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [System.Collections.IDictionary]$BoundParameters
    )
    $prefix = $WordToComplete.Trim([char[]]@([char]39, [char]34))
    $components = @(Read-CxxuComponentManifest)
    $candidates = @()
    if ($ParameterName -eq 'Id')
    {
        foreach ($component in $components)
        {
            if (($CommandName -split '\\')[-1] -eq 'Set-CxxuComponentOption' -and -not @($component.Options | Where-Object { $_ }).Count) { continue }
            $candidates += @{ Text = [string]$component.Id; Tip = ('{0}；默认启用：{1}' -f $component.Description, $component.Default) }
        }
    }
    else
    {
        # 依赖原生参数绑定结果，支持参数重排；不执行用户在命令行中写入的表达式。
        $component = @($components | Where-Object { [string]$_.Id -ieq [string]$BoundParameters['Id'] } | Select-Object -First 1)
        if (-not $component.Count) { return }
        foreach ($option in @($component[0].Options | Where-Object { $_ }))
        {
            $default = if ([string]$option.Type -eq 'List') { '@(' + ($option.Default -join ', ') + ')' } else { [string]$option.Default }
            $tip = '{0}.{1}：{2}；默认值：{3}' -f $component[0].Id, $option.Name, $option.Description, $default
            if ($ParameterName -eq 'Name')
            {
                $candidates += @{ Text = [string]$option.Name; Tip = $tip }
            }
            elseif ($ParameterName -eq 'Value' -and [string]$option.Name -ieq [string]$BoundParameters['Name'] -and [string]$option.Type -eq 'Enum')
            {
                foreach ($value in $option.Values) { $candidates += @{ Text = [string]$value; Tip = $tip } }
            }
            # List 是开放输入，不伪造固定候选；无可用枚举时保留 PowerShell 的原生回退。
        }
    }
    foreach ($candidate in $candidates)
    {
        $text = $candidate.Text
        if (-not $text.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $completion = if ($text -match '^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$') { $text } else { "'" + $text.Replace("'", "''") + "'" }
        [System.Management.Automation.CompletionResult]::new($completion, $text, 'ParameterValue', $candidate.Tip)
    }
}
function Get-CxxuComponent
{
    <#
    .SYNOPSIS
    列出组件清单与当前启用状态、选项值及来源。
    .DESCRIPTION
    元数据来自 PS/Init/components.psd1；值按“环境变量 > 用户配置 > 默认值”解析。
    输出对象可直接接 Format-List/Format-Table；-Id 只查一个组件（不区分大小写）。
    Tier/TierAllowed/Effective 表示当前启动档位、档位是否允许该组件、以及最终是否会在
    init 中加载；组件开关不能突破档位上限（Minimal 全关，Fast 只留 Argc/GitCompletion）。
    Carapace 额外带 Runtime、RegisteredCommands、CachePath、CacheState 四个运行态字段：
    Runtime 区分未安装/未启用/档位禁用/待参数位 Tab/已加载/未加载，CacheState 描述 5.1 上下文缓存是否有效。
    Install 给出依赖安装入口，Enable 给出未启用时的组件启用命令；-Validate 不列组件，
    改跑清单结构、Init 步骤生成与已启用依赖的一致性检查。
    .PARAMETER Id
    组件标识，不区分大小写；Tab 列出清单候选，省略时查询全部组件。
    .PARAMETER Path
    用户配置文件路径，默认 ~/.cxxu/config.psd1；查询不写入文件。
    .PARAMETER Validate
    执行一致性检查并输出 Component/Check/Status/Detail，不输出组件状态对象。
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    .EXAMPLE
    Get-CxxuComponent
    .EXAMPLE
    Get-CxxuComponent -Id Carapace | Format-List
    .EXAMPLE
    Get-CxxuComponent -Id Carapace | Select-Object Enabled, Runtime, RegisteredCommands, CacheState
    .EXAMPLE
    Get-CxxuComponent | Select-Object Id, Enabled, Install, Enable | Format-Table -Wrap
    .EXAMPLE
    Get-CxxuComponent | Select-Object Id, Enabled, TierAllowed, Effective | Format-Table
    .EXAMPLE
    Get-CxxuComponent -Validate | Where-Object Status -ne 'OK'
    #>
    [CmdletBinding()]
    param(
        # 组件 Id；省略时列出全部
        [string]$Id = '',
        # 用户配置文件路径(默认 ~/.cxxu/config.psd1)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1'),
        # 只做一致性自检，输出 Component/Check/Status/Detail 行
        [switch]$Validate
    )
    if ($Validate) { return Test-CxxuComponent -Path $Path }
    $tierName = Get-CxxuStartupTier
    $state = try { Read-CxxuConfigState -Path $Path } catch
    {
        Write-Warning "用户配置读失败($Path):$($_.Exception.Message);按环境变量与默认值判定。"
        [pscustomobject]@{ Model = New-CxxuConfigModel; Present = @{}; Unknown = @(); Exists = $false }
    }
    foreach ($component in (Read-CxxuComponentManifest))
    {
        if ($Id -and ([string]$component.Id -ine $Id)) { continue }
        $tierAllowed = Test-CxxuTierAllowsComponent -Tier $tierName -Id ([string]$component.Id)
        $key = [string]$component.Key
        $envValue = (Get-Item "env:$key" -ErrorAction Ignore).Value
        if (-not [string]::IsNullOrEmpty($envValue))
        {
            $enabled = ConvertTo-CxxuBool $envValue
            $source = '环境变量'
        }
        elseif ($state.Present.ContainsKey($key))
        {
            $enabled = [bool]$state.Model.Components[[string]$component.Id].Enabled
            $source = '配置文件'
        }
        else
        {
            $enabled = [bool]$component.Default
            $source = '默认值'
        }
        $options = [ordered]@{}
        foreach ($option in @($component.Options | Where-Object { $_ }))
        {
            $optKey = [string]$option.Key
            $optEnv = (Get-Item "env:$optKey" -ErrorAction Ignore).Value
            if (-not [string]::IsNullOrEmpty($optEnv))
            {
                if ([string]$option.Type -eq 'List') { $options[[string]$option.Name] = @($optEnv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                else { $options[[string]$option.Name] = $optEnv }
            }
            elseif ($state.Present.ContainsKey($optKey))
            {
                $options[[string]$option.Name] = $state.Model.Components[[string]$component.Id][[string]$option.Name]
            }
            else
            {
                $options[[string]$option.Name] = $option.Default
            }
        }
        $enableHint = if ($enabled -and $tierAllowed)
        {
            ''
        }
        elseif (-not $tierAllowed)
        {
            "Set-PsStartupTier Balanced"
        }
        elseif ($component.ContainsKey('EnableHint') -and -not [string]::IsNullOrWhiteSpace([string]$component.EnableHint))
        {
            [string]$component.EnableHint
        }
        else
        {
            "Enable-CxxuComponent $([string]$component.Id) -Persist"
        }
        $row = [pscustomobject]@{
            Id          = [string]$component.Id
            Name        = [string]$component.Name
            Phase       = [string]$component.Phase
            Enabled     = [bool]$enabled
            Tier        = $tierName
            TierAllowed = [bool]$tierAllowed
            Effective   = [bool]($enabled -and $tierAllowed)
            Source      = $source
            Default     = [bool]$component.Default
            Key         = $key
            Options     = [pscustomobject]$options
            Description = [string]$component.Description
            Lazy        = [string]$component.Lazy
            MinPS       = [int]$component.MinPS
            Init        = [string]$component.Init
            InitNow     = [string]$component.InitNow
            Detect      = [string]$component.Detect
            Install     = [string]$component.Install
            Enable      = $enableHint
            Docs        = [string]$component.Docs
        }
        # Carapace 额外带运行态与 5.1 上下文缓存：开关/配置与实际是否加载、缓存是否可用
        # 是两层信息，分开列，避免把 Enabled 当成"已生效"。
        if ([string]$component.Id -eq 'Carapace')
        {
            $installed = [bool](Get-Command carapace -ErrorAction SilentlyContinue)
            $runtime = if (-not $installed) { '未安装' }
                elseif (-not $enabled) { '未启用' }
                elseif (-not $tierAllowed) { '档位禁用' }
                elseif ($global:PsCarapaceLoaded) { '已加载' }
                elseif ($global:PsCarapacePending -eq $false) { '未加载（加载失败或已停用）' }
                else { '待参数位 Tab' }
            $registered = if ($global:PsCarapaceScripts) { [int]$global:PsCarapaceScripts.Count } else { 0 }
            if ($PSVersionTable.PSVersion.Major -lt 6)
            {
                $cache = Get-CarapaceShellCacheInfo51
                $cachePath = [string]$cache.Path
                $cacheState = if (-not $cache.Exists) { '未建立' }
                    elseif ($cache.Valid) { '有效（{0:N1} 小时 / 24 小时）' -f [double]$cache.AgeHours }
                    elseif ($cache.Reason -eq '宿主或 PSHOME 已变化') { '宿主已变化，下次首 Tab 重建' }
                    elseif ($cache.Reason -eq '已过期') { '已过期（{0:N1} 小时 / 24 小时），下次首 Tab 重建' -f [double]$cache.AgeHours }
                    else { '不完整（{0}），下次首 Tab 重建' -f $cache.Reason }
            }
            else
            {
                $cachePath = ''
                $cacheState = '不适用（仅 5.1 使用）'
            }
            $row | Add-Member -NotePropertyName Runtime -NotePropertyValue $runtime
            $row | Add-Member -NotePropertyName RegisteredCommands -NotePropertyValue $registered
            $row | Add-Member -NotePropertyName CachePath -NotePropertyValue $cachePath
            $row | Add-Member -NotePropertyName CacheState -NotePropertyValue $cacheState
        }
        $row
    }
}
function Test-CxxuComponent
{
    <#
    .SYNOPSIS
    检查组件清单、Init 步骤生成与已启用组件的外部依赖是否一致。
    .DESCRIPTION
    只读检查，不修改配置。清单结构错误、Init 步骤未覆盖或 Init 函数缺失记为“错误”；
    组件已启用但 Detect 命令/模块不存在记为“警告”（附安装入口）。
    输出对象含 Component、Check、Status、Detail，Status 为 OK/警告/错误。
    .EXAMPLE
    Test-CxxuComponent
    .EXAMPLE
    Test-CxxuComponent | Where-Object Status -ne 'OK'
    #>
    [CmdletBinding()]
    param(
        # 用户配置文件路径(默认 ~/.cxxu/config.psd1)
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    $rows = New-Object System.Collections.Generic.List[object]
    $add = {
        param([string]$Component, [string]$Check, [string]$Status, [string]$Detail)
        [void]$rows.Add([pscustomobject]@{
                Component = $Component
                Check     = $Check
                Status    = $Status
                Detail    = $Detail
            })
    }

    $manifest = @(Read-CxxuComponentManifest)
    if (-not $manifest.Count)
    {
        & $add '(清单)' '读取' '错误' 'components.psd1 为空或读取失败'
        return $rows
    }

    # 步骤覆盖以 init 实际生成结果为准：核心步骤 + 清单生成的组件步骤。
    $core = Get-CxxuCoreInitSteps
    $coveredInit = @(($core.Before + $core.After) | ForEach-Object { [string]$_.Name })
    $generated = @(Get-CxxuComponentInitSteps -CoveredInit $coveredInit)
    $stepNames = @($coveredInit) + @($generated | ForEach-Object { [string]$_.Name })

    $ids = @{}
    $keys = @{}
    foreach ($component in $manifest)
    {
        $id = [string]$component.Id
        $label = if ([string]::IsNullOrWhiteSpace($id)) { '(未命名)' } else { $id }
        $key = [string]$component.Key
        $init = [string]$component.Init
        $detect = [string]$component.Detect
        $lazy = [string]$component.Lazy

        if ($lazy -and (@('Startup', 'FirstUse', 'OnIdle') -notcontains $lazy))
        {
            & $add $label 'Lazy' '警告' "未知 Lazy 值：$lazy（可选 Startup/FirstUse/OnIdle）"
        }

        if ([string]::IsNullOrWhiteSpace($id)) { & $add $label 'Id' '错误' '组件缺少 Id' }
        elseif ($ids.ContainsKey($id)) { & $add $label 'Id' '错误' "Id 重复：$id" }
        else { $ids[$id] = $true }

        if ([string]::IsNullOrWhiteSpace($key)) { & $add $label 'Key' '错误' '组件缺少 Key' }
        elseif ($keys.ContainsKey($key)) { & $add $label 'Key' '错误' "Key 重复：$key" }
        else { $keys[$key] = $true }

        if ([string]::IsNullOrWhiteSpace($init))
        {
            & $add $label 'Init 步骤' '错误' '组件缺少 Init 字段'
        }
        elseif ($stepNames -notcontains $init)
        {
            & $add $label 'Init 步骤' '错误' "清单已登记，但 init 步骤未覆盖：$init"
        }
        elseif (-not (Get-Command -Name $init -ErrorAction SilentlyContinue))
        {
            & $add $label 'Init 步骤' '错误' "init 步骤已生成，但函数不存在：$init"
        }
        else
        {
            & $add $label 'Init 步骤' 'OK' "$init 已生成"
        }

        $initNow = [string]$component.InitNow
        if (-not [string]::IsNullOrWhiteSpace($initNow) -and -not (Get-Command -Name $initNow -ErrorAction SilentlyContinue))
        {
            & $add $label '立即加载' '错误' "InitNow 函数不存在：$initNow"
        }

        if ([string]::IsNullOrWhiteSpace($detect))
        {
            & $add $label 'Detect' '警告' '未声明 Detect，跳过已启用依赖检查'
        }

        # 选项只做结构校验：Name/Key 必须唯一，Enum 必须有可选值。
        $optionNames = @{}
        $optionKeys = @{}
        foreach ($option in @($component.Options | Where-Object { $_ }))
        {
            $optionName = [string]$option.Name
            $optionKey = [string]$option.Key
            if ([string]::IsNullOrWhiteSpace($optionName)) { & $add $label '选项' '错误' '选项缺少 Name' }
            elseif ($optionNames.ContainsKey($optionName)) { & $add $label '选项' '错误' "选项 Name 重复：$optionName" }
            else { $optionNames[$optionName] = $true }

            if ([string]::IsNullOrWhiteSpace($optionKey)) { & $add $label '选项' '错误' "选项 $optionName 缺少 Key" }
            elseif ($optionKeys.ContainsKey($optionKey)) { & $add $label '选项' '错误' "选项 Key 重复：$optionKey" }
            else { $optionKeys[$optionKey] = $true }

            if ([string]$option.Type -eq 'Enum' -and -not @($option.Values).Count)
            {
                & $add $label '选项' '错误' "枚举选项 $optionName 缺少 Values"
            }
        }
    }

    # 已启用组件的外部依赖：命令、已加载模块或 PSModulePath 下的模块目录。
    $states = try { @(Get-CxxuComponent -Path $Path) } catch { @() }
    foreach ($state in @($states | Where-Object { $_.Enabled }))
    {
        $component = @($manifest | Where-Object { [string]$_.Id -eq [string]$state.Id } | Select-Object -First 1)
        if (-not $component.Count) { continue }
        $detect = [string]$component[0].Detect
        if ([string]::IsNullOrWhiteSpace($detect)) { continue }
        $found = [bool](Get-Command -Name $detect -ErrorAction SilentlyContinue)
        if (-not $found) { $found = [bool](Get-Module -Name $detect -ErrorAction SilentlyContinue) }
        if (-not $found)
        {
            $found = [bool](@($env:PSModulePath -split [IO.Path]::PathSeparator |
                        Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ $detect)) }).Count)
        }
        if ($found)
        {
            & $add ([string]$state.Id) '依赖' 'OK' "$detect 已就绪"
        }
        else
        {
            $install = [string]$component[0].Install
            $enableHint = if ($component[0].ContainsKey('EnableHint') -and -not [string]::IsNullOrWhiteSpace([string]$component[0].EnableHint))
            {
                [string]$component[0].EnableHint
            }
            else
            {
                "Enable-CxxuComponent $($state.Id) -Now"
            }
            $hint = if ([string]::IsNullOrWhiteSpace($install))
            {
                "安装后重开终端，或执行 $enableHint。"
            }
            else
            {
                "先 $install，再重开终端或执行 $enableHint。"
            }
            & $add ([string]$state.Id) '依赖' '警告' ("组件已启用，但未检测到 {0}；{1}" -f $detect, $hint)
        }
    }

    $rows
}
function Enable-CxxuComponent
{
    <#
    .SYNOPSIS
    启用一个组件：写当前会话环境变量；-Persist 写用户配置；-Now 立即调用组件的立即加载函数。
    .DESCRIPTION
    组件 Id 来自 PS/Init/components.psd1。默认只负责启用意图，不立即加载；
    加 -Now 时调用清单里的 `InitNow`（未声明时用 `Init`），等价于 Enable-PsPlugin 的即时加载路径。
    部分组件即使立即调用 Init 也需重开终端才完全生效（如已注册的 completer）。
    .PARAMETER Id
    必填的组件标识，不区分大小写；Tab 列出组件清单中的候选。
    .PARAMETER Persist
    同时保存到用户配置；省略时仅修改当前进程环境变量。已有配置先备份再规范重写。
    .PARAMETER Now
    立即调用组件的 InitNow 或 Init 入口；省略时不主动加载组件。与 Persist 可同时使用。
    .PARAMETER Path
    用户配置文件路径，默认 ~/.cxxu/config.psd1；仅 Persist 时写入。
    .INPUTS
    None
    .OUTPUTS
    None
    .NOTES
    支持 WhatIf；预览时不修改环境变量、不写配置、不调用加载入口。
    先修改当前会话再保存配置；持久化失败不会自动回滚环境变量。
    .EXAMPLE
    Enable-CxxuComponent Carapace
    .EXAMPLE
    Enable-CxxuComponent Carapace -Persist
    .EXAMPLE
    Enable-CxxuComponent Fnm -Persist -Now
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$Persist,
        # 立即调用组件清单里的立即加载函数（不需要重开终端时可加）
        [switch]$Now,
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    $component = @(Read-CxxuComponentManifest | Where-Object { [string]$_.Id -ieq $Id } | Select-Object -First 1)
    if (-not $component.Count) { throw "未知组件：$Id；运行 Get-CxxuComponent 查看可用 Id。" }
    $tierName = Get-CxxuStartupTier
    if (-not (Test-CxxuTierAllowsComponent -Tier $tierName -Id ([string]$component[0].Id)))
    {
        Write-Warning "当前启动档位 $tierName 不加载组件 $Id；本次只保存开关或立即调用，启动仍需先 Set-PsStartupTier Balanced。"
    }
    $key = [string]$component[0].Key
    if ($PSCmdlet.ShouldProcess($Id, '启用组件'))
    {
        Set-Item "env:$key" -Value 'True'
        if ($Persist) { Set-CxxuConfigModelValues -Path $Path -Values @{ $key = $true } }
        Write-Host ("组件 {0} 已启用{1}。" -f $Id, $(if ($Persist) { '并写入配置' } else { '（当会话）' }))
        if ($Now)
        {
            $initNow = if ($component[0].ContainsKey('InitNow') -and -not [string]::IsNullOrWhiteSpace([string]$component[0].InitNow))
            {
                [string]$component[0].InitNow
            }
            else
            {
                [string]$component[0].Init
            }
            if ([string]::IsNullOrWhiteSpace($initNow)) { Write-Warning "组件 $Id 没有 Init 函数，跳过立即加载。" }
            elseif (Get-Command -Name $initNow -ErrorAction SilentlyContinue) { & $initNow }
            else { Write-Warning "组件 $Id 的立即加载函数不存在：$initNow" }
        }
    }
}
function Disable-CxxuComponent
{
    <#
    .SYNOPSIS
    停用一个组件：写当前会话环境变量；-Persist 时写用户配置。
    .DESCRIPTION
    组件 Id 来自 PS/Init/components.psd1。已注册的 Native completer 无法在当前会话撤销，
    需要重开终端才完全停用。
    .PARAMETER Id
    必填的组件标识，不区分大小写；Tab 列出组件清单中的候选。
    .PARAMETER Persist
    同时保存到用户配置；省略时仅修改当前进程环境变量。已有配置先备份再规范重写。
    .PARAMETER Path
    用户配置文件路径，默认 ~/.cxxu/config.psd1；仅 Persist 时写入。
    .INPUTS
    None
    .OUTPUTS
    None
    .NOTES
    支持 WhatIf；预览时不修改环境变量或配置。不会卸载模块或删除已安装依赖。
    先修改当前会话再保存配置；持久化失败不会自动回滚环境变量。
    .EXAMPLE
    Disable-CxxuComponent Carapace
    .EXAMPLE
    Disable-CxxuComponent Carapace -Persist
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$Persist,
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    $component = @(Read-CxxuComponentManifest | Where-Object { [string]$_.Id -ieq $Id } | Select-Object -First 1)
    if (-not $component.Count) { throw "未知组件：$Id；运行 Get-CxxuComponent 查看可用 Id。" }
    $key = [string]$component[0].Key
    if ($PSCmdlet.ShouldProcess($Id, '停用组件'))
    {
        Set-Item "env:$key" -Value 'False'
        if ($Persist) { Set-CxxuConfigModelValues -Path $Path -Values @{ $key = $false } }
        Write-Host ("组件 {0} 已停用{1}。" -f $Id, $(if ($Persist) { '并写入配置' } else { '（当会话）' }))
    }
}
function Set-CxxuComponentOption
{
    <#
    .SYNOPSIS
    设置组件选项（如 Tab.Synopsis、GitCompletion.Source、Carapace.Excludes）。
    .DESCRIPTION
    选项定义、默认值与可选枚举来自 PS/Init/components.psd1。List 类型接受数组或逗号分隔字符串。
    -Persist 时把选项写入用户配置；不加只改当前会话。
    Tab.Synopsis 接受 True/False 或 $true/$false；下一次 Tab 生效，不提前加载 CxxuTab。
    只改选项本身；git/gitk 来源切换请用 Set-GitCompletionSource（它同时维护 PsGitCompletion 与 PsCarapace）。
    Id、Name、枚举 Value 提供联动 Tab 候选与用途提示；提示直接读取组件清单，
    不受 PsTabSynopsis 控制，不解析函数源码、不连接网络、不安装或加载可选组件。
    .PARAMETER Id
    必填的组件标识，不区分大小写；Tab 只推荐定义了选项的组件。
    .PARAMETER Name
    必填的选项名称，不区分大小写；Tab 根据已填写的 Id 推荐选项。
    .PARAMETER Value
    必填的选项值。枚举值不区分大小写并规范化保存，Tab 根据 Id 和 Name 提供合法枚举。
    Tab.Synopsis 默认 False，接受 True/False 字符串或布尔值；其他值报错。
    List 接受数组或逗号分隔字符串，空项移除；它是开放输入，不提供固定取值候选。
    .PARAMETER Persist
    同时写当前会话与用户配置；省略时只写当前进程环境变量，子进程会继承。
    配置目录不存在时创建；已有文件先生成 .bak-* 备份，再规范重写，手工注释可能被规范化。
    .PARAMETER Path
    用户配置文件路径，默认 ~/.cxxu/config.psd1；仅 Persist 时读写，不改变启动时的默认配置路径。
    .INPUTS
    None
    .OUTPUTS
    None
    .NOTES
    前提是已导入 Init；正常 profile 中的 init 已完成导入。支持 WhatIf，预览不写环境变量或配置。
    未知组件、选项或非法枚举在写入前报错；先设置环境变量再持久化，文件写入失败不回滚环境变量。
    启动时优先级为环境变量 > 用户配置 > 清单默认值；profile 赋值可能覆盖持久配置。
    设置选项不改变组件启用状态；除 Tab.Synopsis 下一次 Tab 生效外，其他组件的生效时机见对应组件说明。
    .EXAMPLE
    Set-CxxuComponentOption -Id Tab -Name Synopsis -Value $true
    .EXAMPLE
    Set-CxxuComponentOption -Id Tab -Name Synopsis -Value $false -Persist
    .EXAMPLE
    Set-CxxuComponentOption -Id GitCompletion -Name Source -Value Carapace -Persist
    .EXAMPLE
    Set-CxxuComponentOption -Id Carapace -Name Excludes -Value @('winget','uv') -Persist
    .EXAMPLE
    Set-CxxuComponentOption -Id Tab -Name Synopsis -Value True -Persist -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [switch]$Persist,
        [string]$Path = (Join-Path (Join-Path $HOME '.cxxu') 'config.psd1')
    )
    $component = @(Read-CxxuComponentManifest | Where-Object { [string]$_.Id -ieq $Id } | Select-Object -First 1)
    if (-not $component.Count) { throw "未知组件：$Id；运行 Get-CxxuComponent 查看可用 Id。" }
    $option = @($component[0].Options | Where-Object { $_ -and ([string]$_.Name -ieq $Name) } | Select-Object -First 1)
    if (-not $option.Count) { throw "组件 $Id 没有选项 $Name；可用选项见 Get-CxxuComponent -Id $Id。" }
    $definition = $option[0]
    if ([string]$definition.Type -eq 'Enum')
    {
        $canonical = @($definition.Values | Where-Object { [string]$_ -ieq [string]$Value } | Select-Object -First 1)
        if (-not $canonical.Count) { throw ("选项 {0}.{1} 只接受：{2}" -f $Id, $Name, ($definition.Values -join '、')) }
        $Value = [string]$canonical[0]
    }
    elseif ([string]$definition.Type -eq 'List')
    {
        if ($Value -is [string]) { $Value = @($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        else { $Value = @($Value | ForEach-Object { [string]$_ } | Where-Object { $_ }) }
    }
    $envText = if ($Value -is [array]) { $Value -join ',' } else { [string]$Value }
    $key = [string]$definition.Key
    if ($PSCmdlet.ShouldProcess(("{0}.{1}" -f $Id, $Name), '设置组件选项'))
    {
        Set-Item "env:$key" -Value $envText
        if ($Persist) { Set-CxxuConfigModelValues -Path $Path -Values @{ $key = $Value } }
        Write-Host ("{0}.{1} = {2}{3}" -f $Id, $Name, $envText, $(if ($Persist) { '（已写入配置）' } else { '（当会话）' }))
    }
}

function Install-Ps51Profile
{
    <#
    .SYNOPSIS
    为 Windows PowerShell 5.1 安装 profile 入口,之后 5.1 启动自动 init + 自定义 prompt,免手动。
    .DESCRIPTION
    写入位置固定为 5.1 的 CurrentUserCurrentHost profile
    (~\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1,与 pwsh7 互不干扰);
    内容仅 3 行:确保 PSModulePath 含模块集、显式导入 Init、跑 init(主题/补全/历史全由 init 接管)。
    幂等:已安装(标记行存在)直接返回,加 -Force 重写。从 pwsh7 或 5.1 跑均可,跑一次即可。
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([switch]$Force)
    $psRoot = Split-Path $PSScriptRoot -Parent
    $dir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell'
    $profile51 = Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
    $marker = '# CxxuPsModules-ps51'
    if ((Test-Path -LiteralPath $profile51) -and ((Get-Content -LiteralPath $profile51 -Raw) -match [regex]::Escape($marker)) -and (-not $Force))
    {
        Write-Host "5.1 profile 已安装($profile51),加 -Force 重写。"
        return $profile51
    }
    if ($PSCmdlet.ShouldProcess($profile51, '写入 5.1 profile 入口'))
    {
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        # 已有 profile 无标记则追加(保用户旧内容),否则整写;读回统一按原文拼,编码恒为 UTF8+BOM
        $old = if (Test-Path -LiteralPath $profile51) { [IO.File]::ReadAllText($profile51) } else { '' }
        if ($old -ne '' -and (-not $old.EndsWith("`r`n")) -and (-not $old.EndsWith("`n"))) { $old += "`r`n" }
        # 注意:字符串 + 数组会先按空格压平成标量(再 -join 也救不回),必须先 join 成标量再拼 $old
        $body = $old + ((@(
            "$marker(Install-Ps51Profile 生成;手动改前先看 Feature-Guide §13)"
            "if ((`$env:PSModulePath -split ';') -notcontains '$psRoot') { `$env:PSModulePath = '$psRoot;' + `$env:PSModulePath }"
            'Import-Module Init -ErrorAction SilentlyContinue'
            'init'
        ) -join "`r`n"))
        [IO.File]::WriteAllText($profile51, $body, [Text.UTF8Encoding]::new($true))
        Write-Host "已写入 $profile51,重开 powershell.exe 即生效。"
        return $profile51
    }
}

# 在模块作用域注册，保证回调能访问私有清单读取器；参数属性回调在调用者作用域执行。
# 导入时只登记回调，候选到按 Tab 时才生成；独立导入 Init 与 5.1 同样可用。
$componentCompleter = ${function:Complete-CxxuComponentArgument}
Register-ArgumentCompleter -CommandName Get-CxxuComponent, Enable-CxxuComponent, Disable-CxxuComponent, Set-CxxuComponentOption -ParameterName Id -ScriptBlock $componentCompleter
foreach ($parameter in @('Name', 'Value'))
{
    Register-ArgumentCompleter -CommandName Set-CxxuComponentOption -ParameterName $parameter -ScriptBlock $componentCompleter
}
