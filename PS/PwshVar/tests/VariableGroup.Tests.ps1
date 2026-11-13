<#
.SYNOPSIS
验证变量组缓存、动态表达式、失效检测、回退与仓库副本隔离。
.DESCRIPTION
在临时模块与临时缓存目录中运行，不读取实际变量配置，不修改用户配置。
.EXAMPLE
pwsh -NoProfile -File ./PS/PwshVar/tests/VariableGroup.Tests.ps1
.EXAMPLE
powershell -NoProfile -File ./PS/PwshVar/tests/VariableGroup.Tests.ps1
#>
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$tempRoot = [IO.Path]::GetTempPath()
$testRoot = Join-Path $tempRoot ('cxxu-var-group-test-' + [guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $testRoot 'PwshVar'
$cacheRoot = Join-Path $testRoot 'cache'
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$utf8 = [Text.UTF8Encoding]::new($true)

function Assert-True
{
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-Fixture
{
    param([string]$Name, [string]$Content)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot "confs/$Name.conf"), $Content, $utf8)
}

function Get-FixtureSnapshot
{
    $snapshot = @{}
    foreach ($name in @('PvCacheBase', 'PvCacheDerived', 'PvCacheChinese', 'PvCacheProcess', 'PvCacheLong', 'PvCacheFailure', 'PvCacheExtra'))
    {
        $snapshot[$name] = [Management.Automation.PSSerializer]::Serialize((Get-Variable -Name $name -Scope Global -ValueOnly), 4)
    }
    return $snapshot
}

function Assert-Snapshot
{
    param([hashtable]$Expected)
    $actual = Get-FixtureSnapshot
    foreach ($name in $Expected.Keys)
    {
        Assert-True ($Expected[$name] -eq $actual[$name]) "变量 $name 与逐行加载结果不一致。"
    }
}

try
{
    $null = [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'confs'))
    $null = [IO.Directory]::CreateDirectory($cacheRoot)
    $env:TEMP = $cacheRoot
    $env:TMP = $cacheRoot
    Assert-True ([IO.Path]::GetTempPath().TrimEnd('\', '/') -eq $cacheRoot.TrimEnd('\', '/')) '临时缓存目录隔离失败。'
    foreach ($file in @('PwshVar.psm1', 'PwshVar.psd1'))
    {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../$file") -Destination (Join-Path $fixtureRoot $file)
    }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'VarLongStrings.ps1'), '$global:PvCacheLong = "长字符串"', $utf8)
    $firstConf = @'
PsEnvMode=1
PvCacheBase='first'
PvCacheProcess=$PID
PvCacheRuns=1 + $global:PvCacheRuns
PvCacheFailure=if($global:PvCacheThrow){throw 'fixture failure'}else{'ok'}
'@
    Write-Fixture 'VarSet1' $firstConf
    Write-Fixture 'VarSet2' 'PvCacheDerived="$PvCacheBase/suffix"'
    Write-Fixture 'ConstantString' "PvCacheChinese='中文 café'"
    Write-Fixture 'GlobalConfig' "PvCacheExtra='fast'"
    foreach ($name in @('VarAndroid', 'VarFiles', 'VarSet3', 'VarSet3.macos')) { Write-Fixture $name '' }
    Import-Module (Join-Path $fixtureRoot 'PwshVar.psd1') -Force
    $module = Get-Module PwshVar
    $global:PvCacheRuns = 0
    $global:PvCacheThrow = $false
    Update-PwshVars -Core -NoCache
    $global:PvCacheExtra = $null
    $expected = Get-FixtureSnapshot
    Assert-True ($global:PvCacheRuns -eq 1) '逐行路径重复执行了表达式。'

    # 从真实调用入口观测逐文件分派次数，避免用耗时阈值制造不稳定测试。
    $global:PvCacheFileCalls = 0
    $breakpoint = Set-PSBreakpoint -Command Import-PwshVarFile -Action { $global:PvCacheFileCalls++ }
    try { Update-PwshVars -Core }
    finally { Remove-PSBreakpoint -Breakpoint $breakpoint }
    Assert-True ($global:PvCacheFileCalls -eq 0) "组加载仍调用了 $global:PvCacheFileCalls 次逐文件入口。"
    Assert-Snapshot $expected
    Assert-True ($global:PvCacheRuns -eq 2) '首次组加载没有恰好执行一次表达式。'
    $cache = & $module { Get-PwshVarGroupCache -VarFiles @('VarSet1', 'VarSet2', 'ConstantString') }
    Assert-True ([IO.File]::Exists($cache)) '未生成组缓存。'
    $cacheTime = [IO.File]::GetLastWriteTimeUtc($cache)
    Update-PwshVars -Core
    Assert-Snapshot $expected
    Assert-True ($global:PvCacheRuns -eq 3) '缓存命中后没有重新求值。'
    Assert-True ([IO.File]::GetLastWriteTimeUtc($cache).Equals($cacheTime)) '缓存命中时不应重写文件。'
    $global:PvCacheFileCalls = 0
    $breakpoint = Set-PSBreakpoint -Command Import-PwshVarFile -Action { $global:PvCacheFileCalls++ }
    try { $output = @(Update-PwshVars -Core -NoCache) }
    finally { Remove-PSBreakpoint -Breakpoint $breakpoint }
    Assert-True ($global:PvCacheFileCalls -eq 3 -and $output.Count -eq 0) 'NoCache 没有绕过组缓存，或泄漏了成功流输出。'
    Assert-True ([IO.File]::GetLastWriteTimeUtc($cache).Equals($cacheTime)) 'NoCache 不应写入缓存。'
    $oldDebug = $DebugPreference
    try
    {
        $DebugPreference = 'Continue'
        $debugOutput = @(Update-PwshVars -Core 5>&1)
        Assert-True (@($debugOutput | Where-Object { $_ -is [Management.Automation.DebugRecord] }).Count -gt 0) '调试路径缺少逐行诊断。'
    }
    finally { $DebugPreference = $oldDebug }

    # 时间戳变旧的同长度修改也须失效，不能只比较“源文件比缓存新”。
    $source = Join-Path $fixtureRoot 'confs/VarSet1.conf'
    $oldTime = [IO.File]::GetLastWriteTimeUtc($source)
    Write-Fixture 'VarSet1' ($firstConf.Replace("'first'", "'other'"))
    [IO.File]::SetLastWriteTimeUtc($source, $oldTime.AddMinutes(-1))
    Update-PwshVars -Core
    Assert-True ($global:PvCacheBase -eq 'other' -and $global:PvCacheDerived -eq 'other/suffix') '源文件修改后仍使用旧缓存。'

    # 动态表达式报错时不得重跑整组，否则先前的副作用会执行两遍。
    $global:PvCacheThrow = $true
    $runs = $global:PvCacheRuns
    $failed = $false
    try { Update-PwshVars -Core } catch { $failed = $true; $runtimeError = $_.Exception.GetType().FullName }
    finally { $global:PvCacheThrow = $false }
    Assert-True $failed '配置表达式的运行错误被吞掉。'
    Assert-True ($global:PvCacheRuns -eq $runs + 1) "表达式报错后执行次数不正确：之前=$runs，之后=$global:PvCacheRuns，错误=$runtimeError。"

    # 损坏的缓存先完整解析失败，安全回退，下一次调用应重新生成。
    [IO.File]::AppendAllText($cache, "`nif (", $utf8)
    Update-PwshVars -Core
    Assert-True ($global:PvCacheDerived -eq 'other/suffix') '缓存损坏后未回退。'
    Update-PwshVars -Core
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($cache, [ref]$null, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) '损坏的缓存未被替换。'

    # 缓存不可写时仍能加载。目录占用缓存文件名，不依赖管理员权限或 ACL。
    [IO.File]::Delete($cache)
    $null = [IO.Directory]::CreateDirectory($cache)
    try { Update-PwshVars -Core }
    finally { [IO.Directory]::Delete($cache) }
    Assert-True ($global:PvCacheBase -eq 'other') '缓存写入失败后未回退。'
    Update-PwshVars -Core

    $global:PsEnvMode = 3
    Update-PwshVars -Core
    Assert-True ($global:PsEnvMode -eq 3) '核心加载降低了已有环境等级。'
    $global:PsEnvMode = 0
    Update-PwshVars -Fast
    Assert-True ($global:PsEnvMode -eq 1 -and $global:PvCacheExtra -eq 'fast') 'Fast 变量组不符合原有语义。'
    Update-PwshVars
    Assert-True ($global:PsEnvMode -eq 2) '完整加载未标记 Vars 等级。'
    Update-PwshVars -Core -Fast
    Assert-True ($global:PsEnvMode -eq 2) 'Core/Fast 优先级或已有等级被改变。'
    $completionLine = 'Update-PwshVars -Co'
    $candidates = [Management.Automation.CommandCompletion]::CompleteInput($completionLine, $completionLine.Length, $null).CompletionMatches.CompletionText
    Assert-True ($candidates -contains '-Core') '原生开关补全不可用。'
    $help = Get-Help Update-PwshVars -Full | Out-String
    Assert-True ($help -match 'NoCache' -and $help -match 'Core') '公共帮助不完整。'

    # 源文件删除后不得继续执行旧缓存。
    $secondSource = Join-Path $fixtureRoot 'confs/VarSet2.conf'
    [IO.File]::Delete($secondSource)
    Remove-Variable -Name PvCacheDerived -Scope Global
    $failed = $false
    try { Update-PwshVars -Core } catch { $failed = $true }
    Assert-True $failed '源文件缺失没有报告错误。'
    Assert-True (-not (Get-Variable -Name PvCacheDerived -Scope Global -ErrorAction SilentlyContinue)) '源文件缺失时仍执行了旧缓存。'
    Write-Fixture 'VarSet2' 'PvCacheDerived="$PvCacheBase/suffix"'

    Remove-Module PwshVar
    $cloneParent = Join-Path $testRoot 'clone'
    $null = [IO.Directory]::CreateDirectory($cloneParent)
    Copy-Item -LiteralPath $fixtureRoot -Destination $cloneParent -Recurse
    $fixtureRoot = Join-Path $cloneParent 'PwshVar'
    Write-Fixture 'VarSet1' ($firstConf.Replace("'first'", "'clone'"))
    Import-Module (Join-Path $fixtureRoot 'PwshVar.psd1') -Force
    Update-PwshVars -Core
    $cloneModule = Get-Module PwshVar
    $cloneCache = & $cloneModule { Get-PwshVarGroupCache -VarFiles @('VarSet1', 'VarSet2', 'ConstantString') }
    Assert-True ($cloneCache -ne $cache -and $global:PvCacheBase -eq 'clone') '不同仓库副本串用了缓存。'
    Write-Output 'PASS: 组加载、动态求值、修改/删除失效、损坏/不可写回退、环境等级、帮助补全及副本隔离。'
}
finally
{
    Remove-Module PwshVar -ErrorAction SilentlyContinue
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $prefix = [IO.Path]::GetFullPath($tempRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "意外的清理路径：$resolved" }
    if ([IO.Directory]::Exists($resolved)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
