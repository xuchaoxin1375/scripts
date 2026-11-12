# CxxuTab:自研 Tab 命令名补全(独立插件,TabExpansion2 包装)。
# ListView 预测进不了 Tab(两套管线),这里包全局 TabExpansion2,只在命令名位置合并
# dll 公开接口的模糊结果,其余位置原样透传。开关逐调用读 $env:PsTab(默认开,
# 显式置 False/0/No/Off 才关),关掉就是纯透传,行为与没装一样;启停管理看
# Enable/Disable-PsPlugin。异常/超慢调用会自熔断(本会话只透传),不拖死 Tab。
# 命令名候选另补函数 .SYNOPSIS 首段(与参数语法同屏,开关 $env:PsTabSynopsis,
# 默认开),独立熔断;已加载函数取定义文本,未加载模块在 pwsh 7+ 且候选较少时
# 读 .psm1 源码(不导入模块,5.1 不做这层)。
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

# 从函数定义文本里取 .SYNOPSIS 首段:Get-Help/GetHelpContent 在本机会话 75 个带帮助的
# 函数合计约 678ms,而 Definition 已在内存里,按行解析只需毫秒级。遇空行或下一个 .TAG
# 停止,菜单只展示首段;行注释与块注释两种写法都按同一规则归一化。
function Get-CxxuTabSynopsisFromDefinition
{
    param([string]$Definition)
    if ([string]::IsNullOrWhiteSpace($Definition)) { return $null }
    $lines = $Definition -split '\r?\n'
    $norm = foreach ($line in $lines)
    {
        $t = $line.Trim()
        if ($t -eq '<#' -or $t -eq '#>') { $t = '' }
        elseif ($t.StartsWith('#')) { $t = $t.Substring(1).TrimStart() }
        $t
    }
    $inSynopsis = $false
    $buf = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $norm)
    {
        if (-not $inSynopsis)
        {
            if ($t -match '^\.SYNOPSIS\b')
            {
                $inSynopsis = $true
                $rest = $t.Substring(9).Trim()
                if ($rest) { $buf.Add($rest) }
            }
            continue
        }
        # 摘要到空行或下一个帮助标签结束;首段之外的段落不进菜单
        if ($t -eq '' -or $t -match '^\.[A-Z][A-Z0-9_-]*\b') { break }
        $buf.Add($t)
    }
    if ($buf.Count -eq 0) { return $null }
    return ($buf -join ' ').Trim()
}

# 候选名索引与摘要。索引只含已导入函数/别名(-ListImported 不触发模块自动加载),
# 每个命令名 Tab 重建一次(本机会话约 1ms,首次含 JIT 约 8ms),函数重新定义后立即换新;
# 摘要文本按 ScriptBlock 对象身份缓存在 $global:__CxxuTabSynCache。
function Get-CxxuTabSynopsisIndex
{
    $index = @{ Functions = @{}; Aliases = @{} }
    foreach ($cmd in Get-Command -CommandType Function, Alias -ListImported -ErrorAction Ignore)
    {
        if ($cmd.CommandType -eq 'Alias')
        {
            if ($cmd.Definition) { $index.Aliases[$cmd.Name] = $cmd.Definition.Trim() }
        }
        else
        {
            $index.Functions[$cmd.Name] = $cmd
        }
    }
    return $index
}

# 摘要缓存:命中且 ScriptBlock 未变时直接返回;函数重新定义会换新 ScriptBlock,自动重算。
function Get-CxxuTabSynopsis
{
    param([string]$Name, $Function)
    $cache = $global:__CxxuTabSynCache
    if ($null -eq $cache) { $cache = @{}; $global:__CxxuTabSynCache = $cache }
    $entry = $cache[$Name]
    if ($entry -and [object]::ReferenceEquals($entry.Sb, $Function.ScriptBlock)) { return $entry.Text }
    $text = Get-CxxuTabSynopsisFromDefinition -Definition $Function.Definition
    $cache[$Name] = @{ Sb = $Function.ScriptBlock; Text = $text }
    return $text
}

# 未加载模块的源码索引:Get-Command 不带名字只枚举、不导入(7 约 30ms;5.1 约 260ms,
# 故 5.1 不启用源码解析)。每个进程只建一次,只用于候选较少时的按需解析。
function Get-CxxuTabModuleMap
{
    if ($null -ne $global:__CxxuTabModMap) { return $global:__CxxuTabModMap }
    $map = @{}
    try
    {
        foreach ($cmd in Get-Command -CommandType Function -ErrorAction Ignore)
        {
            if ($cmd.Name -and $cmd.Module -and $cmd.Module.Path -and -not $map.ContainsKey($cmd.Name))
            {
                $map[$cmd.Name] = $cmd.Module.Path
            }
        }
    }
    catch { }
    $global:__CxxuTabModMap = $map
    return $map
}

# 模块清单 → 根 .psm1 路径。优先同名 psm1(仓库约定),缺失再读清单的 RootModule;
# 二进制模块与找不到源文件的模块返回 null,不触发导入。
function Get-CxxuTabModuleSource
{
    param([string]$ModulePath)
    if ([string]::IsNullOrEmpty($ModulePath)) { return $null }
    if ($ModulePath -like '*.psm1') { return $ModulePath }
    if ($ModulePath -notlike '*.psd1') { return $null }
    $cache = $global:__CxxuTabModSrc
    if ($null -eq $cache) { $cache = @{}; $global:__CxxuTabModSrc = $cache }
    if ($cache.ContainsKey($ModulePath)) { return $cache[$ModulePath] }
    $source = $null
    $base = [System.IO.Path]::GetDirectoryName($ModulePath)
    $leaf = [System.IO.Path]::GetFileNameWithoutExtension($ModulePath)
    $guess = Join-Path $base ($leaf + '.psm1')
    if (Test-Path -LiteralPath $guess)
    {
        $source = $guess
    }
    else
    {
        $root = $null
        try
        {
            if (Get-Command Import-PowerShellDataFile -ErrorAction Ignore)
            {
                $root = (Import-PowerShellDataFile -LiteralPath $ModulePath).RootModule
            }
        }
        catch { }
        if (-not $root)
        {
            try
            {
                $tokens = $null; $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($ModulePath, [ref]$tokens, [ref]$errors)
                $table = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)
                if ($table)
                {
                    $data = $table.SafeGetValue()
                    if ($data -and $data.ContainsKey('RootModule')) { $root = $data['RootModule'] }
                }
            }
            catch { }
        }
        if ($root -and $root -like '*.psm1')
        {
            $path = Join-Path $base $root
            if (Test-Path -LiteralPath $path) { $source = $path }
        }
    }
    $cache[$ModulePath] = $source
    return $source
}

# 解析模块源文件并缓存“函数名 → AST”,按文件 LastWriteTimeUtc 失效;失败返回空表。
function Get-CxxuTabSourceFunctions
{
    param([string]$Path)
    $cache = $global:__CxxuTabModFiles
    if ($null -eq $cache) { $cache = @{}; $global:__CxxuTabModFiles = $cache }
    $item = Get-Item -LiteralPath $Path -ErrorAction Ignore
    if (-not $item) { return $null }
    $stamp = $item.LastWriteTimeUtc.Ticks
    $entry = $cache[$Path]
    if ($entry -and $entry.Stamp -eq $stamp) { return $entry.Functions }
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $map = @{}
    foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    {
        if ($fn.Name -and -not $map.ContainsKey($fn.Name)) { $map[$fn.Name] = $fn }
    }
    $cache[$Path] = @{ Stamp = $stamp; Functions = $map }
    return $map
}

# 未加载函数 → 从源码取 .SYNOPSIS 首段。每次 Tab 最多新解析 $MaxParses 个模块文件,
# 已缓存的模块不计;候选过多(宽前缀)由调用方跳过,避免一次解析几十个文件。
function Get-CxxuTabSourceSynopsis
{
    param([string]$Name, [ref]$Parses, [int]$MaxParses = 3)
    if ([string]::IsNullOrEmpty($Name)) { return $null }
    $map = Get-CxxuTabModuleMap
    $modulePath = $map[$Name]
    if (-not $modulePath) { return $null }
    $source = Get-CxxuTabModuleSource -ModulePath $modulePath
    if (-not $source) { return $null }
    $cache = $global:__CxxuTabSrcSynCache
    if ($null -eq $cache) { $cache = @{}; $global:__CxxuTabSrcSynCache = $cache }
    $item = Get-Item -LiteralPath $source -ErrorAction Ignore
    if (-not $item) { return $null }
    $stamp = $item.LastWriteTimeUtc.Ticks
    $entry = $cache[$Name]
    if ($entry -and $entry.Stamp -eq $stamp) { return $entry.Text }
    $files = $global:__CxxuTabModFiles
    $known = $null -ne $files -and $files.ContainsKey($source)
    if (-not $known)
    {
        if ($Parses.Value -ge $MaxParses) { return $null }
        $Parses.Value++
    }
    $functions = Get-CxxuTabSourceFunctions -Path $source
    $text = $null
    if ($functions -and $functions.ContainsKey($Name))
    {
        try
        {
            $help = $functions[$Name].GetHelpContent()
            if ($help -and $help.Synopsis)
            {
                $text = (($help.Synopsis -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' ')
            }
        }
        catch { }
    }
    $cache[$Name] = @{ Stamp = $stamp; Text = $text }
    return $text
}

# 命令名候选统一附加摘要:摘要在前、原有参数语法保留在后;非命令候选原样保留。
# 查表直接内联(大候选集下逐个函数调用白付数百次开销),只有确有注释帮助时才取摘要。
function Add-CxxuTabSynopsis
{
    param([System.Management.Automation.CommandCompletion]$Completion)
    if ($null -eq $Completion -or $null -eq $Completion.CompletionMatches) { return $Completion }
    $index = Get-CxxuTabSynopsisIndex
    # 源码回退只在候选较少(pwsh 7+)时启用:首次要建模块索引并解析文件,宽前缀会放大成本
    $allowSource = $Completion.CompletionMatches.Count -le 20 -and $PSVersionTable.PSVersion.Major -ge 6
    $parses = 0
    $list = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()
    $changed = $false
    foreach ($m in $Completion.CompletionMatches)
    {
        if ($m.ResultType -eq 'Command')
        {
            $lookup = $m.CompletionText
            $func = $index.Functions[$lookup]
            if (-not $func)
            {
                $target = $index.Aliases[$lookup]
                if ($target)
                {
                    $func = $index.Functions[$target]
                    $lookup = $target
                }
            }
            $text = $null
            if ($func -and $func.Definition -and $func.Definition.Contains('.SYNOPSIS'))
            {
                $text = Get-CxxuTabSynopsis -Name $m.CompletionText -Function $func
            }
            elseif ($allowSource -and $lookup -notmatch '\\')
            {
                $text = Get-CxxuTabSourceSynopsis -Name $lookup -Parses ([ref]$parses)
            }
            if ($text)
            {
                $tip = [string]$m.ToolTip
                if ($tip) { $tip = $text + "`n" + $tip.Trim() } else { $tip = $text }
                # 只重建真正要改的候选,其余原对象复用,避免大候选集(如 Get-)白付分配成本
                $list.Add([System.Management.Automation.CompletionResult]::new($m.CompletionText, $m.ListItemText, $m.ResultType, $tip))
                $changed = $true
                continue
            }
        }
        $list.Add($m)
    }
    if (-not $changed) { return $Completion }
    return [System.Management.Automation.CommandCompletion]::new($list, $Completion.CurrentMatchIndex, $Completion.ReplacementIndex, $Completion.ReplacementLength)
}

function Install-CxxuTabWrapper
{
    <#
    .SYNOPSIS
    安装 TabExpansion2 包装(命令名位置合并自研模糊结果,缺省 30 条,并补函数摘要)。
    #>
    # 优先复用同一活件的 predictor 程序集;7+ 按活件路径加载,使稍后 Import-Module
    # 也复用同一程序集与命令表。5.1 仍按字节装载 Tab-only 产物,不注册 predictor。
    # 已装过就不再重载:重复 Import-Module -Force 不该再付一次加载/建表成本;
    # 新 dll 仍按活件的"重开终端生效"规则走(与 predictor 一致)。
    if (-not $global:__CxxuTabMethod)
    {
        $dll = Get-CxxuTabLiveDll
        if ($dll)
        {
            try
            {
                $asm = $null
                $predictor = Get-Module CxxuPredictor | Where-Object { $_.Path -eq $dll } | Select-Object -First 1
                if ($predictor) { $asm = $predictor.ImplementingAssembly }
                if (-not $asm)
                {
                    if ($PSVersionTable.PSVersion.Major -ge 7) { $asm = [System.Reflection.Assembly]::LoadFrom($dll) }
                    else { $asm = [System.Reflection.Assembly]::Load([System.IO.File]::ReadAllBytes($dll)) }
                }
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
            if (-not $isCmdName -or [string]::IsNullOrEmpty($word)) { return $base }
            $result = $base
            if ($global:__CxxuTabMethod -and -not $global:__CxxuTabFuse)
            {
                # 自熔断:正常 1ms 级;单次超过 800ms 说明主机/杀软异常,本会话不再加重负担
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $extra = @($global:__CxxuTabMethod.Invoke($null, @($word, 30)))
                $sw.Stop()
                if ($sw.ElapsedMilliseconds -gt 800) { $global:__CxxuTabFuse = $true }
                if ($extra.Count)
                {
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
                    $result = [System.Management.Automation.CommandCompletion]::new($merged, $current, $base.ReplacementIndex, $base.ReplacementLength)
                }
            }
            # 摘要装饰:独立开关与独立熔断,失败只丢摘要,不影响候选与模糊
            if ($env:PsTabSynopsis -notmatch '^(False|0|No|Off)$' -and -not $global:__CxxuTabSynFuse)
            {
                try { $result = Add-CxxuTabSynopsis -Completion $result }
                catch { $global:__CxxuTabSynFuse = $true }
            }
            return $result
        }
        catch
        {
            # 异常也只伤增强层:本会话熔断为纯透传,避免每次 Tab 重复报错/耗时
            $global:__CxxuTabFuse = $true
            return (& $fallBack)
        }
    }
    # 首次导入时预热建表;由首个 Tab 懒加载时,本次手势仍承担该成本。
    try { if ($global:__CxxuTabMethod) { [void]$global:__CxxuTabMethod.Invoke($null, @('__cxxu_warmup__', 1)) } } catch { }
}

# 模块导入即安装(门控在每次调用时判定,导入本身无副作用)
Install-CxxuTabWrapper
