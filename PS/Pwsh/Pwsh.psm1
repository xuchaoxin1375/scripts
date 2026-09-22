

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

function Add-CxxuPsModuleToProfile

{
    <# 
    .SYNOPSIS
    将此模块集推荐的自动加载工作添加到powershell的配置文件$profile中
    .DESCRIPTION
    写入位置为$profile;
    在vscode中,情况和普通终端管理器(例如windows terminal)中有所不同,尤其是如果用户启用了powershell extension terminal时;
    建议不要使用这个特殊的交互式shell,powershell extension用其服务于powershell语言服务器,提供语法检查等功能,而不适合用于交互式使用;
    在这个shell环境下,$profile取值和vscode相关.
    可以考虑使用powershell.integratedConsole.startInBackground此选项会从终端列表中隐藏powershell extension terminal;
    
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
    Update-PwshEnvIfNotYet
    '# AutoRun commands from CxxuPsModules' + " $(Get-Date)" >> $pf
    Get-Content $scripts/config/core_ps_profile.ps1 >>$pf #向配置文件追加内容
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

function Import-ModuleForce
{
    <# 
    .SYNOPSIS
    只重载仓库内已加载模块(白名单即本意:刷新我改过的模块,变量不丢);第三方/系统模块一律不动,仍配合 iex 在当前作用域执行
    #>
    [CmdletBinding()]
    param (
        # 只处理指定模块(不指定=白名单内全部);ipmof 不传,行为不变
        [string[]]$Name
        # [switch]$PassThru
    )

    # 白名单根:本函数所在模块的上级目录(即 PS/ 仓库目录),自举不依赖外部变量
    $repoRoot = Split-Path -Parent $PSScriptRoot

    # 获取当前已经加载且位于仓库内的模块(动态模块 Path 为空,天然排除)
    $loaded = @(Get-Module | Where-Object {
        $_.Path -and $_.Path.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -ExpandProperty Name)
    if ($Name)
    {
        foreach ($wanted in $Name)
        {
            if ($wanted -notin $loaded)
            {
                Write-Warning "$wanted 未加载(未加载模块改完下次调用自动生效),跳过"
            }
        }
        $modules = @($loaded | Where-Object { $_ -in $Name })
    }
    else
    {
        $modules = $loaded
    }

    $res = @()
    foreach ($module in $modules)
    {
        # 纵深防御:import 有副作用的仍跳过(黑名单,和白名单叠加)
        # completion:注册补全的模块谨慎重载;predictor:CxxuPredictor 只能由 loader 按外置路径装载,
        # 裸重载按名装出空壳(还注销掉已注册的 predictor),必须跳过,改了它重开终端
        # conda:Conda.psm1 每次 import 都 Rename-Item prompt 为 CondaPromptBackup 再包一层(ChangePs1 缺省真),裸重载=每轮多一层 prompt
        if ($module -like '*completion*' -or $module -like '*predictor*' -or $module -like '*conda*')
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
    为此编写了此函数,可以直接重载仓库内(PS/ 路径下)已经加载了的模块,方便了这一个刷新变更了的模块的过程
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
function ipmox
{
    <# 
    .SYNOPSIS
    ipmof|iex 的单命令版:白名单内模块先卸后装,一次搞定,不用管道 iex
    .NOTES
    ipmof 把活拆成两半:Remove 立刻做,Import 攒成文本靠 iex 在调用方全局作用域执行——
    光跑 ipmof 不管道,装的那半根本没执行(这就是"不用 iex 没生效",不是作用域魔法)。
    本函数把两半合一:复用 Import-ModuleForce 做卸+名单,重装一律显式 -Global(作用域确定,
    见 Agent-Handoff #12),Pwsh 自己殿后(执行中不拆自己的台)。ipmof|iex 照旧可用。
    本函数把两半合一:复用 Import-ModuleForce 做卸+名单,重装一律显式 -Global(作用域确定,
    见 Agent-Handoff #12),Pwsh 自己殿后(执行中不拆自己的台)。ipmof|iex 照旧可用。
    核心价值:不丢当前会话定义的变量/上下文(重开 pwsh 会丢一部分信息),这就是本函数存在的理由。
    选项:-Name 只动指定模块(Tab 补全);-Sync 先 Sync-ModuleManifest -Reload(新函数先进
    manifest,再统一重载——Sync 自身跳过 Prompt,本函数的重载补上, Prompt 有 capture-once 保护)。
    .EXAMPLE
    ipmox
    .EXAMPLE
    ipmox -Name Prompt -Sync
    #>
    [CmdletBinding()]
    param (
        # 只重载指定模块(Tab 补全仓库内有同名 .psm1 的目录);不指定=白名单内全部
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $pwshMod = Get-Module Pwsh | Select-Object -First 1
            if (-not $pwshMod) { return }
            $root = Split-Path $pwshMod.ModuleBase -Parent
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -like "$wordToComplete*" -and
                    (Test-Path -LiteralPath (Join-Path $_.FullName ($_.Name + '.psm1'))) } |
                ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new(
                        $_.Name, $_.Name, 'ParameterValue', "重载 $($_.Name)") }
        })]
        [string[]]$Name,
        # 先同步 manifest(新函数场景),再统一重载
        [switch]$Sync
    )

    if ($Sync)
    {
        if ($Name)
        {
            foreach ($n in $Name) { Sync-ModuleManifest -Name $n -Reload }
        }
        else
        {
            Sync-ModuleManifest -Reload
        }
    }
    $script = if ($Name) { Import-ModuleForce -Name $Name } else { Import-ModuleForce }
    $names = @($script -split "`r?`n" | ForEach-Object {
        if ($_ -match '^Import-Module\s+(\S+)\s+-Force') { $Matches[1] }
    } | Where-Object { $_ })
    # Pwsh 自己殿后:卸自己发生在 Import-ModuleForce 里,装自己放最后,函数体跑完才收尾最稳
    $ordered = @($names | Where-Object { $_ -ne 'Pwsh' }) + @($names | Where-Object { $_ -eq 'Pwsh' })
    $ok = 0
    foreach ($n in $ordered)
    {
        Import-Module $n -Force -Global -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        $ok++
    }
    Write-Verbose "ipmox reloaded $ok modules: $($ordered -join ',')"
}


function Sync-ModuleManifest
{
    <#
    .SYNOPSIS
    偷懒同步:把 .psm1 里新增的函数自动补进 .psd1 的 FunctionsToExport(只增不减)。
    .DESCRIPTION
    改完 .psm1 后跑 Sync-ModuleManifest <模块名> -Reload,新函数即可调用,免手改 manifest。
    不指定模块名则处理全部自有模块(只打印有变化的+汇总;批量重载跳过 Prompt 防嵌套)。
    只追加缺失项(按 .psm1 定义顺序),从不删除;GUID/版本/其它字段原样保留,换行原样保留。
    .EXAMPLE
    Sync-ModuleManifest Mock -Reload
    .EXAMPLE
    Sync-ModuleManifest -Reload
    #>
    [CmdletBinding()]
    param(
        # 不指定 = 全部自有模块(PS/ 下有同名 .psm1 的目录;Tab 补全模块名)
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $pwshMod = Get-Module Pwsh | Select-Object -First 1
            if (-not $pwshMod) { return }
            $root = Split-Path $pwshMod.ModuleBase -Parent
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -like "$wordToComplete*" -and
                    (Test-Path -LiteralPath (Join-Path $_.FullName ($_.Name + '.psm1'))) } |
                ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new(
                        $_.Name, $_.Name, 'ParameterValue', "同步 $($_.Name) 的 manifest") }
        })]
        $Name,
        [switch]$Reload,
        # 批量内部递归用:静默(有变化才由调用方汇总打印)并返回结果对象
        [switch]$Quiet
    )
    if (-not $Name)
    {
        $psRoot = Split-Path $PSScriptRoot -Parent
        $targets = @(Get-ChildItem -LiteralPath $psRoot -Directory | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName ($_.Name + '.psm1')) } |
            Select-Object -ExpandProperty Name | Sort-Object)
        $results = @(foreach ($n in $targets) { Sync-ModuleManifest -Name $n -Quiet })
        $changedMods = @($results | Where-Object { -not $_.Failed -and $_.Added.Count -gt 0 })
        $failedMods = @($results | Where-Object { $_.Failed })
        foreach ($r in $changedMods)
        {
            Write-Host "$($r.Module) 已追加 $($r.Added.Count) 个: $($r.Added -join ', ')"
        }
        foreach ($f in $failedMods)
        {
            Write-Warning "$($f.Module): $($f.Failed)"
        }
        if ($Reload -and $changedMods.Count -gt 0)
        {
            foreach ($r in $changedMods)
            {
                if ($r.Module -eq 'Prompt')
                {
                    Write-Warning 'Prompt 有变更已同步文件,跳过重载(防提示符嵌套),请重进 shell'
                    continue
                }
                Import-Module $r.Module -Force -DisableNameChecking -Global
                foreach ($m in $r.Added)
                {
                    if (-not (Get-Command $m -ErrorAction SilentlyContinue))
                    {
                        Write-Warning "$m 同步后仍不可调用(请检查函数体是否有语法错)"
                    }
                }
            }
        }
        $okCount = $targets.Count - $changedMods.Count - $failedMods.Count
        Write-Host "同步完成:共 $($targets.Count) 个模块,$($changedMods.Count) 个有追加,$($failedMods.Count) 个失败,${okCount} 个已同步"
        return
    }
    $n = $Name
    $mod = Get-Module -ListAvailable $n | Select-Object -First 1
    if (-not $mod)
    {
        $msg = "找不到模块 ${n}(PSModulePath 自动发现无此模块)"
        if ($Quiet) { Write-Warning $msg; return [PSCustomObject]@{ Module = $n; Failed = $msg; Added = @() } }
        Write-Error $msg
        return
    }
    $psm1 = Join-Path $mod.ModuleBase "$n.psm1"
    $psd1 = Join-Path $mod.ModuleBase "$n.psd1"
    if (-not (Test-Path -LiteralPath $psm1))
    {
        $msg = "缺少 $psm1(目录名/模块名/psm1 基名必须一致)"
        if ($Quiet) { Write-Warning $msg; return [PSCustomObject]@{ Module = $n; Failed = $msg; Added = @() } }
        Write-Error $msg
        return
    }
    if (-not (Test-Path -LiteralPath $psd1))
    {
        $msg = "缺少 $psd1(本函数只做同步,不新建 manifest)"
        if ($Quiet) { Write-Warning $msg; return [PSCustomObject]@{ Module = $n; Failed = $msg; Added = @() } }
        Write-Error $msg
        return
    }
    # 块注释感知解析(与对账脚本同规则):先去 <#...#> 块,再取行首 function
    $noBlock = [regex]::Replace((Get-Content -LiteralPath $psm1 -Raw), '<#.*?#>', '', 'Singleline')
    $defined = @($noBlock -split "`r?`n" | ForEach-Object {
        if ($_ -cmatch '^function\s+([\w-]+)\s*(\{|\(|$|#)') { $Matches[1] }
    } | Select-Object -Unique)
    # 5.1 的 Select-Object -ExpandProperty 看不见哈希表键(7 可以):一律点号取值,双版本同行为
    $exported = @((Import-PowerShellDataFile -LiteralPath $psd1).FunctionsToExport)
    $missing = @($defined | Where-Object { $_ -notin $exported })
    $orphan = @($exported | Where-Object { $_ -notin $defined })
    foreach ($o in $orphan)
    {
        Write-Warning "${n}: $o 在 manifest 中但 .psm1 里没有定义(只提醒,不删除)"
    }
    if ($missing.Count -eq 0)
    {
        if (-not $Quiet) { Write-Host "${n} 已同步(导出 $($exported.Count) 个,无新增)" }
    }
    else
    {
        # 文本级追加:换行/其它内容原样保留,只动 FunctionsToExport 数组尾
        # 显式 UTF-8 读(自动识别 BOM):Get-Content -Raw 在 5.1 按 GBK 解码,中文注释会被读成乱码再写回造成双重编码(已踩坑,见交接)
        $raw = [IO.File]::ReadAllText($psd1, [Text.Encoding]::UTF8)
        $eol = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
        $lines = @($raw -split "`r?`n")
        $start = -1
        for ($k = 0; $k -lt $lines.Count; $k++)
        {
            if ($lines[$k] -match 'FunctionsToExport\s*=\s*@\(') { $start = $k; break }
        }
        $end = -1
        for ($k = $start + 1; $k -lt $lines.Count; $k++)
        {
            if ($lines[$k] -match '^\s*\)') { $end = $k; break }
        }
        if ($start -lt 0 -or $end -lt 0)
        {
            $msg = "$psd1 里找不到 FunctionsToExport 数组(模板被改过?请手改)"
            if ($Quiet) { Write-Warning $msg; return [PSCustomObject]@{ Module = $n; Failed = $msg; Added = @() } }
            Write-Error $msg
            return
        }
        # manifest 受限语言不认数组尾逗号(@('a',) 非法):新增项只有非末项带逗号;
        # 前一项若无逗号则补(模板末项本就没有);空数组(@( 后直接 ))则不动前行。
        $prev = $end - 1
        while ($prev -gt $start -and $lines[$prev] -match '^\s*$') { $prev-- }
        if ($lines[$prev] -notmatch '@\($' -and $lines[$prev] -notmatch ',\s*(#.*)?$')
        {
            $lines[$prev] += ','
        }
        $add = @()
        for ($m = 0; $m -lt $missing.Count; $m++)
        {
            $suffix = if ($m -eq $missing.Count - 1) { '' } else { ',' }
            $add += "        '$($missing[$m])'$suffix"
        }
        $newLines = @($lines[0..($end - 1)] + $add + $lines[$end..($lines.Count - 1)])
        [IO.File]::WriteAllText($psd1, ($newLines -join $eol), [Text.UTF8Encoding]::new($false))
        if (-not $Quiet) { Write-Host "${n} 已追加 $($missing.Count) 个: $($missing -join ', ')" }
    }
    if ($Reload)
    {
        # -Global:在模块函数内 Import-Module 默认装成嵌套模块(Get-Module 列不出),强制顶层
        Import-Module $n -Force -DisableNameChecking -Global
        foreach ($m in $missing)
        {
            if (-not (Get-Command $m -ErrorAction SilentlyContinue))
            {
                Write-Warning "$m 同步后仍不可调用(请检查函数体是否有语法错)"
            }
        }
    }
    if ($Quiet)
    {
        return [PSCustomObject]@{ Module = $n; Failed = $null; Added = @($missing) }
    }
}
function Get-CxxuModuleCompatibility
{
    <#
    .SYNOPSIS
    查模块集 5.1/7 兼容声明总表:逐模块读 psd1 的 PowerShellVersion + psm1 首字节 BOM。
    .DESCRIPTION
    真相源是各模块自己的 .psd1(文档 Feature-Guide.md §13 是批次流水账,查数以本命令为准)。
    B 档=声明 5.1 且 psm1 带 BOM(5.1 中文 Windows 无 BOM 按 GBK 解码,中文必乱码);
    声明 5.1 但缺 BOM 会单拎出来(补 BOM 即好);留 7 的附登记理由,没登记的报回来补。
    只读文件头、不导入任何模块,秒出。运行时冒烟另用 init -Timing / Test-StartupPerformance。
    .EXAMPLE
    Get-CxxuModuleCompatibility
    .EXAMPLE
    Get-CxxuModuleCompatibility -Name 'Git*' | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    param(
        # 模块名过滤(通配符,默认全量)
        [string]$Name = '*'
    )
    $psRoot = Split-Path -Parent $PSScriptRoot
    $stay7Reasons = @{
        'Whois'               = '34 个 ??(空合并)待重写'
        'TaskSchdPwsh'        = '后台 & 在 5.1 无等价写法,留 7'
        'TimeNotify'          = '后台 & 在 5.1 无等价写法,留 7'
        'Test'                = '用户草稿区,不动'
        'CompletionPredictor' = '第三方模块,不管'
        'CxxuPredictor'       = 'net9 dll,永不降'
    }
    $rows = @()
    $dirs = Get-ChildItem -LiteralPath $psRoot -Directory | Where-Object { $_.Name -like $Name } | Sort-Object Name
    foreach ($dir in $dirs)
    {
        $psd1 = Join-Path $dir.FullName ($dir.Name + '.psd1')
        if (-not (Test-Path -LiteralPath $psd1)) { continue }
        $ver = ''
        $m = [regex]::Match([IO.File]::ReadAllText($psd1), "PowerShellVersion\s*=\s*'([^']+)'")
        if ($m.Success) { $ver = $m.Groups[1].Value }
        $bom = $false
        $psm1 = Join-Path $dir.FullName ($dir.Name + '.psm1')
        if (Test-Path -LiteralPath $psm1)
        {
            $fs = [IO.File]::OpenRead($psm1)
            try
            {
                $head = New-Object byte[] 3
                $n = $fs.Read($head, 0, 3)
                $bom = ($n -eq 3) -and ($head[0] -eq 0xEF) -and ($head[1] -eq 0xBB) -and ($head[2] -eq 0xBF)
            }
            finally { $fs.Close() }
        }
        if ($ver -eq '5.1')
        {
            if ($bom) { $verdict = 'B档5.1' }
            else { $verdict = '缺BOM(5.1中文必乱码)' }
        }
        elseif ($ver -like '7.*')
        {
            if ($stay7Reasons.ContainsKey($dir.Name)) { $verdict = '留7:' + $stay7Reasons[$dir.Name] }
            else { $verdict = '留7:原因未登记' }
        }
        else { $verdict = '未声明(看一眼)' }
        $rows += [PSCustomObject]@{ Module = $dir.Name; Declared = $ver; BOM = $bom; Verdict = $verdict }
    }
    $b = @($rows | Where-Object { $_.Verdict -eq 'B档5.1' }).Count
    $s = @($rows | Where-Object { $_.Verdict -like '留7*' }).Count
    $bad = @($rows | Where-Object { ($_.Verdict -like '缺BOM*') -or ($_.Verdict -like '未声明*') -or ($_.Verdict -like '*未登记') }).Count
    Write-Host "B档5.1=$b 留7=$s 待处理=$bad(缺BOM/未声明/未登记)" -ForegroundColor Cyan
    return $rows
}


