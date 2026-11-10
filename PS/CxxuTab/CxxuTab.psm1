# CxxuTab:自研 Tab 命令名补全(独立插件,TabExpansion2 包装)。
# ListView 预测进不了 Tab(两套管线),这里包全局 TabExpansion2,只在命令名位置合并
# dll 公开接口的模糊结果,其余位置原样透传。开关逐调用读 $env:PsTab(默认开,
# 显式置 False/0/No/Off 才关),关掉就是纯透传,行为与没装一样;启停管理看
# Enable/Disable-PsPlugin。异常/超慢调用会自熔断(本会话只透传),不拖死 Tab。
# 跨作用域说明:global:TabExpansion2 运行在全局作用域,看不到模块 $script:,
# 方法缓存必须放 $global:__CxxuTabMethod(命名避冲突)。
# 5.1 走 ps51 活件(netstandard2.0,只有 CompleteCommand);7+ 走预测器活件
# (net9.0,同一程序集同时提供 predictor 与 CompleteCommand)。两套活件互不混用。

function Get-CxxuTabLiveDll
{
    # 与 loader 同规则解析指针(目录隔离布局):指针→最新版目录→旧单文件。
    # 5.1 的 SMA 没有预测子系统,不能加载 net9 版;固定读 ~/.cxxu/bin/ps51。
    $binDir = Join-Path (Join-Path $HOME '.cxxu') 'bin'
    if ($PSVersionTable.PSVersion.Major -lt 6) { $binDir = Join-Path $binDir 'ps51' }
    $ptrFile = Join-Path $binDir 'current.txt'
    if (Test-Path -LiteralPath $ptrFile)
    {
        $h = Get-Content -LiteralPath $ptrFile -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($h)
        {
            $c = Join-Path (Join-Path $binDir "$h".Trim()) 'CxxuPredictor.dll'
            if (Test-Path -LiteralPath $c) { return $c }
        }
    }
    $best = Get-ChildItem -LiteralPath $binDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'CxxuPredictor.dll') } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($best) { return (Join-Path $best.FullName 'CxxuPredictor.dll') }
    $legacy = Join-Path $binDir 'CxxuPredictor.dll'
    if (Test-Path -LiteralPath $legacy) { return $legacy }
    return $null
}

function Install-CxxuTabWrapper
{
    <#
    .SYNOPSIS
    安装 TabExpansion2 包装(命令名位置合并自研模糊结果,缺省 30 条)。
    #>
    # 程序集按字节加载(不锁定文件,不注册 ListView predictor,与 PsPredictor 门独立)。
    # 已装过就不再重载:重复 Import-Module -Force 不该再付一次加载/建表成本;
    # 新 dll 仍按活件的"重开终端生效"规则走(与 predictor 一致)。
    if (-not $global:__CxxuTabMethod)
    {
        $dll = Get-CxxuTabLiveDll
        if ($dll)
        {
            try
            {
                $asm = [System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($dll))
                $global:__CxxuTabMethod = $asm.GetType('CxxuPredictor.CxxuCommandPredictor').GetMethod('CompleteCommand')
            }
            catch { $global:__CxxuTabMethod = $null }
        }
    }
    # 原函数只存一次(重复 import 不叠包装)
    if (-not $global:__CxxuTabOriginal)
    {
        $orig = Get-Command TabExpansion2 -CommandType Function -ErrorAction SilentlyContinue
        if ($orig) { $global:__CxxuTabOriginal = $orig.ScriptBlock }
    }
    function global:TabExpansion2
    {
        param($inputScript, $cursorColumn)
        $fallBack = {
            if ($global:__CxxuTabOriginal) { & $global:__CxxuTabOriginal $inputScript $cursorColumn }
            else { [System.Management.Automation.CommandCompletion]::CompleteInput($inputScript, $cursorColumn, $null) }
        }
        try
        {
            # 门控逐调用:默认开,显式 False/0/No/Off 才纯透传
            if ($env:PsTab -match '^(False|0|No|Off)$') { return (& $fallBack) }
            if ([string]::IsNullOrEmpty($inputScript)) { return (& $fallBack) }
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($inputScript, [ref]$tokens, [ref]$errors)
            $isCmdName = $false
            $word = ''
            foreach ($cmd in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
            {
                $el = $cmd.CommandElements
                if ($el.Count -and $cursorColumn -ge $el[0].Extent.StartOffset -and $cursorColumn -le $el[0].Extent.EndOffset)
                {
                    $isCmdName = $true
                    $word = $inputScript.Substring($el[0].Extent.StartOffset, $cursorColumn - $el[0].Extent.StartOffset)
                    break
                }
            }
            $base = & $fallBack
            if (-not $isCmdName -or [string]::IsNullOrEmpty($word) -or -not $global:__CxxuTabMethod -or $global:__CxxuTabFuse)
            {
                return $base
            }
            # 自熔断:正常 1ms 级;单次超过 800ms 说明主机/杀软异常,本会话不再加重负担
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $extra = @($global:__CxxuTabMethod.Invoke($null, @($word, 30)))
            $sw.Stop()
            if ($sw.ElapsedMilliseconds -gt 800) { $global:__CxxuTabFuse = $true }
            if (-not $extra.Count) { return $base }
            # 原生前缀命中优先:命令名位置的 base 都是前缀匹配(最强),放在最前;
            # 模糊结果只补充 base 未覆盖的名字,沿用 dll 既有 tier/分数顺序追加。
            $baseMatches = @($base.CompletionMatches)
            $seen = @{}
            foreach ($m in $baseMatches) { $seen[$m.CompletionText] = $true }
            $merged = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
            foreach ($m in $baseMatches) { $merged.Add($m) }
            foreach ($m in $extra)
            {
                if (-not $seen.ContainsKey($m))
                {
                    $merged.Add([System.Management.Automation.CompletionResult]::new($m, $m, 'Command', "CxxuTab fuzzy: $m"))
                    $seen[$m] = $true
                }
            }
            $current = 0
            if ($baseMatches.Count -gt 0 -and $base.CurrentMatchIndex -ge 0) { $current = $base.CurrentMatchIndex }
            return [System.Management.Automation.CommandCompletion]::new($merged, $current, $base.ReplacementIndex, $base.ReplacementLength)
        }
        catch
        {
            # 异常也只伤增强层:本会话熔断为纯透传,避免每次 Tab 重复报错/耗时
            $global:__CxxuTabFuse = $true
            return (& $fallBack)
        }
    }
    # 预热建表(首 Tab 不卡,约数百毫秒一次;失败静默,首 Tab 现建)
    try { if ($global:__CxxuTabMethod) { [void]$global:__CxxuTabMethod.Invoke($null, @('__cxxu_warmup__', 1)) } } catch { }
}

# 模块导入即安装(门控在每次调用时判定,导入本身无副作用)
Install-CxxuTabWrapper
