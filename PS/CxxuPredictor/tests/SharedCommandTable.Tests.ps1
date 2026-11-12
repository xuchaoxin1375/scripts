<#
.SYNOPSIS
验证活件的命令表复用、两种加载顺序及基础匹配；不加载仓库源 DLL。
.PARAMETER TabFirst
先加载 Tab，再注册预测器。默认先注册预测器；5.1 只验证 Tab。
.EXAMPLE
pwsh -NoProfile -File ./PS/CxxuPredictor/tests/SharedCommandTable.Tests.ps1
.EXAMPLE
pwsh -NoProfile -File ./PS/CxxuPredictor/tests/SharedCommandTable.Tests.ps1 -TabFirst
#>
param([switch]$TabFirst)
$ErrorActionPreference = 'Stop'
$env:PsTab = 'True'
$bin = Join-Path $HOME '.cxxu/bin'
if ($PSVersionTable.PSVersion.Major -lt 7) { $bin = Join-Path $bin 'ps51' }
$hash = [IO.File]::ReadAllText((Join-Path $bin 'current.txt')).Trim()
$dll = Join-Path (Join-Path $bin $hash) 'CxxuPredictor.dll'
$tabManifest = Join-Path $PSScriptRoot '../../CxxuTab/CxxuTab.psd1'
$flags = [Reflection.BindingFlags]'Static,NonPublic'
if (-not $TabFirst -and $PSVersionTable.PSVersion.Major -ge 7) { Import-Module $dll -Global }
Import-Module $tabManifest -Global
if ($TabFirst -and (Get-Module CxxuPredictor)) { throw 'Tab import registered predictor implicitly' }
$type = $global:__CxxuTabMethod.DeclaringType
if (-not $type) { throw 'Tab did not load live assembly' }
$field = $type.GetField('_commandTable', $flags)
if (-not $field) { throw 'Live assembly does not contain shared table' }
$table = $field.GetValue($null)
if (-not $table) { throw 'Command table not initialized' }
if ($PSVersionTable.PSVersion.Major -ge 7)
{
    if ($TabFirst) { Import-Module $dll -Global }
    $predictorModule = Get-Module CxxuPredictor
    if (-not [object]::ReferenceEquals($predictorModule.ImplementingAssembly, $type.Assembly))
    {
        throw 'Tab and predictor loaded different assemblies'
    }
    # 再次构造预测器验证实例字段指向 Tab 已发布的同一对象，不重置静态状态。
    $ctor = $type.GetConstructor([Reflection.BindingFlags]'Instance,NonPublic', $null, [type[]]@([string]), $null)
    $predictor = $ctor.Invoke(@([guid]::NewGuid().ToString()))
    $instanceTable = $type.GetField('_table', [Reflection.BindingFlags]'Instance,NonPublic').GetValue($predictor)
    if (-not [object]::ReferenceEquals($table, $instanceTable)) { throw 'Instance did not reuse shared table' }
}
foreach ($word in @('Get-Chi', 'gci', 'Get-*Item'))
{
    $candidates = @($global:__CxxuTabMethod.Invoke($null, @($word, 30)))
    if ($candidates -notcontains 'Get-ChildItem') { throw "Expected command missing: $word" }
    $again = @($global:__CxxuTabMethod.Invoke($null, @($word, 30)))
    if (($candidates -join '|') -cne ($again -join '|')) { throw "Unstable ordering: $word" }
}
$limited = @($global:__CxxuTabMethod.Invoke($null, @('Get-', 3)))
if ($limited.Count -ne 3) { throw 'Result limit not respected' }
if (@($global:__CxxuTabMethod.Invoke($null, @('', 3))).Count -or
    @($global:__CxxuTabMethod.Invoke($null, @('Get-', 0))).Count) { throw 'Invalid query returned results' }
if (-not [object]::ReferenceEquals($table, $field.GetValue($null))) { throw 'Shared table replaced during completion' }
Write-Output "PASS: shared table, assembly identity, matching and limits; TabFirst=$TabFirst; PS=$($PSVersionTable.PSVersion)"
