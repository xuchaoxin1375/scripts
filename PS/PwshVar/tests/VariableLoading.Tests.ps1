<#
.SYNOPSIS
验证变量加载顺序、动态求值、单文件缓存回退、环境等级与原生帮助补全。
.DESCRIPTION
在隔离的临时模块与缓存目录中运行，不读取或修改用户配置。需要 PowerShell 5.1 或更高版本。
失败时报告断言错误并返回非零退出码；临时文件在结束时清理。
.EXAMPLE
pwsh -NoProfile -File ./PS/PwshVar/tests/VariableLoading.Tests.ps1
.EXAMPLE
powershell -NoProfile -File ./PS/PwshVar/tests/VariableLoading.Tests.ps1
#>
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$tempRoot = [IO.Path]::GetTempPath()
$testRoot = Join-Path $tempRoot ('cxxu-var-loading-test-' + [guid]::NewGuid().ToString('N'))
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
    $global:PvCacheRuns = 0
    $global:PvCacheThrow = $false

    $output = @(Update-PwshVars -Core -NoCache 6>$null)
    Assert-True ($output.Count -eq 0 -and $global:PvCacheRuns -eq 1) '逐行加载重复执行或泄漏成功流输出。'
    Assert-True (@(Get-ChildItem -LiteralPath $cacheRoot -File).Count -eq 0) 'NoCache 不应写入缓存。'
    foreach ($run in 2..3)
    {
        $output = @(Update-PwshVars -Core 6>$null)
        Assert-True ($global:PvCacheRuns -eq $run -and $global:PvCacheProcess -eq $PID) '缓存构建或命中未恰好求值一次。'
        Assert-True ($global:PvCacheDerived -eq 'first/suffix') '配置依赖顺序被改变。'
        Assert-True ($global:PvCacheChinese -eq '中文 café' -and $global:PvCacheLong -eq '长字符串') '缓存或长字符串中的中文被破坏。'
        Assert-True ($output.Count -eq 0) '缓存加载泄漏了成功流输出。'
    }
    $cache = Join-Path $cacheRoot 'CxxuPwshVar_VarSet1.cache.ps1'
    Assert-True ([IO.File]::Exists($cache)) '未生成单文件缓存。'
    $cacheTime = [IO.File]::GetLastWriteTimeUtc($cache)
    Update-PwshVars -Core -NoCache 6>$null
    Assert-True ([IO.File]::GetLastWriteTimeUtc($cache).Equals($cacheTime)) 'NoCache 不应重写缓存。'

    $oldDebug = $DebugPreference
    try
    {
        $DebugPreference = 'Continue'
        $records = @(Update-PwshVars -Core 5>&1 6>$null)
        Assert-True (@($records | Where-Object { $_ -is [Management.Automation.DebugRecord] }).Count -gt 0) '缺少逐行调试输出。'
    }
    finally { $DebugPreference = $oldDebug }

    $source = Join-Path $fixtureRoot 'confs/VarSet1.conf'
    Write-Fixture 'VarSet1' ($firstConf.Replace("'first'", "'other'"))
    [IO.File]::SetLastWriteTimeUtc($source, $cacheTime.AddSeconds(5))
    Update-PwshVars -Core 6>$null
    Assert-True ($global:PvCacheBase -eq 'other' -and $global:PvCacheDerived -eq 'other/suffix') '较新的源配置未使缓存失效。'
    [IO.File]::SetLastWriteTimeUtc($source, [IO.File]::GetLastWriteTimeUtc($cache).AddSeconds(-1))

    $validCache = [IO.File]::ReadAllBytes($cache)
    [IO.File]::AppendAllText($cache, "`nif (", $utf8)
    Update-PwshVars -Core 6>$null
    Assert-True ($global:PvCacheDerived -eq 'other/suffix') '损坏缓存未回退到配置。'
    [IO.File]::WriteAllBytes($cache, $validCache)
    $global:PvCacheThrow = $true
    $runs = $global:PvCacheRuns
    $failed = $false
    try { Update-PwshVars -Core 6>$null } catch { $failed = $true }
    finally { $global:PvCacheThrow = $false }
    Assert-True ($failed -and $global:PvCacheRuns -eq $runs + 1) '运行错误被吞掉或重复执行了表达式。'

    [IO.File]::Delete($cache)
    $null = [IO.Directory]::CreateDirectory($cache)
    try { Update-PwshVars -Core 6>$null }
    finally { [IO.Directory]::Delete($cache) }
    Assert-True ($global:PvCacheBase -eq 'other') '缓存不可写时未回退。'

    $global:PsEnvMode = 3
    Update-PwshVars -Core 6>$null
    Assert-True ($global:PsEnvMode -eq 3) 'Core 降低了已有环境等级。'
    $global:PsEnvMode = 0
    $global:PvCacheExtra = $null
    Update-PwshVars -Core -Fast 6>$null
    Assert-True ($global:PsEnvMode -eq 1 -and $null -eq $global:PvCacheExtra) 'Core/Fast 优先级改变。'
    Update-PwshVars -Fast 6>$null
    Assert-True ($global:PvCacheExtra -eq 'fast' -and $global:PsEnvMode -eq 1) 'Fast 加载范围改变。'
    Update-PwshVars 6>$null
    Assert-True ($global:PsEnvMode -eq 2) 'Full 未提升环境等级。'

    $line = 'Update-PwshVars -Co'
    $candidates = [Management.Automation.CommandCompletion]::CompleteInput($line, $line.Length, $null).CompletionMatches.CompletionText
    Assert-True ($candidates -contains '-Core') '原生开关补全不可用。'
    $help = Get-Help Update-PwshVars -Full | Out-String
    Assert-True ($help -match 'NoCache' -and $help -match 'Core') '公共帮助不完整。'

    [IO.File]::Delete((Join-Path $fixtureRoot 'confs/VarSet2.conf'))
    Remove-Variable -Name PvCacheDerived -Scope Global
    $failed = $false
    try { Update-PwshVars -Core 6>$null } catch { $failed = $true }
    Assert-True ($failed -and -not (Get-Variable -Name PvCacheDerived -Scope Global -ErrorAction SilentlyContinue)) '源文件缺失时仍执行了旧缓存。'
    Write-Output 'PASS: 加载顺序、动态求值、中文、单文件缓存回退、运行错误、环境等级、帮助与补全。'
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
