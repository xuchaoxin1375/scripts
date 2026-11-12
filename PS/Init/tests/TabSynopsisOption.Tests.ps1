<#
.SYNOPSIS
验证 Tab.Synopsis 统一管理入口，只在临时目录读写配置，不改变个人配置。
.EXAMPLE
pwsh -NoProfile -File ./PS/Init/tests/TabSynopsisOption.Tests.ps1
#>
$ErrorActionPreference = 'Stop'
$oldSynopsis = $env:PsTabSynopsis
$oldTab = $env:PsTab
$root = Join-Path ([IO.Path]::GetTempPath()) ('cxxu-synopsis-option-' + [guid]::NewGuid().ToString('N'))
$path = Join-Path $root 'config.psd1'
Import-Module (Join-Path $PSScriptRoot '../Init.psd1') -Force
try
{
    $null = New-Item -ItemType Directory -Path $root
    Remove-Item Env:PsTabSynopsis -ErrorAction Ignore
    $env:PsTab = 'False'
    $state = Get-CxxuComponent -Id Tab -Path $path
    if ([string]$state.Options.Synopsis -cne 'False' -or $state.Enabled) { throw 'Incorrect default synopsis or Tab state' }
    if (Get-Module CxxuTab) { throw 'Status query imported CxxuTab' }
    foreach ($value in @($true, 'tRuE', $false, 'fAlSe'))
    {
        Set-CxxuComponentOption -Id Tab -Name Synopsis -Value $value -Path $path
        $expected = [string]$value -ieq 'True'
        if (($env:PsTabSynopsis -eq 'True') -ne $expected) { throw 'Runtime setter mismatch' }
        if ([string](Get-CxxuComponent -Id Tab -Path $path).Options.Synopsis -cne $env:PsTabSynopsis) { throw 'Option query mismatch' }
        if (Test-Path -LiteralPath $path) { throw 'Temporary setter wrote config' }
    }
    foreach ($value in @('invalid', 'Yes', '0'))
    {
        $rejected = $false
        try { Set-CxxuComponentOption -Id Tab -Name Synopsis -Value $value -Persist -Path $path }
        catch { $rejected = $true }
        if (-not $rejected -or $env:PsTabSynopsis -cne 'False' -or (Test-Path -LiteralPath $path)) { throw 'Invalid value changed runtime or config' }
    }
    Set-CxxuComponentOption -Id Tab -Name Synopsis -Value $true -Persist -Path $path -WhatIf
    if ($env:PsTabSynopsis -cne 'False' -or (Test-Path -LiteralPath $path)) { throw 'WhatIf wrote state' }
    New-CxxuConfigTemplate -Path $path
    $data = Import-PowerShellDataFile -LiteralPath $path
    if ([string]$data.Components.Tab.Synopsis -cne 'False') { throw 'Template default mismatch' }
    # 保存选项不能顺带启用父组件，也不能改动其他组件设置。
    [IO.File]::WriteAllText($path, '@{ SchemaVersion = 2; Components = @{ Tab = @{ Enabled = $false; Synopsis = ''False'' }; Carapace = @{ Excludes = @(''winget'') } } }', [Text.UTF8Encoding]::new($true))
    Set-CxxuComponentOption -Id Tab -Name Synopsis -Value $true -Persist -Path $path
    $data = Import-PowerShellDataFile -LiteralPath $path
    if ([string]$data.Components.Tab.Synopsis -cne 'True' -or $data.Components.Tab.Enabled -or
        $data.Components.Carapace.Excludes -notcontains 'winget' -or $env:PsTab -cne 'False') { throw 'Persistence changed unrelated state' }
    if (-not @(Get-ChildItem -LiteralPath $root -Filter 'config.psd1.bak-*').Count) { throw 'Existing config not backed up' }
    Remove-Item Env:PsTabSynopsis -ErrorAction Ignore
    Import-CxxuConfig -Path $path
    if ($env:PsTabSynopsis -cne 'True') { throw 'Persisted value did not load' }
    $flat = Get-CxxuConfig -Path $path | Where-Object Key -eq PsTabSynopsis
    if ($flat.Value -cne 'True' -or $flat.Source -ne '配置文件' -or $flat.Default -cne 'False') { throw 'Flat status mismatch' }
    $env:PsTabSynopsis = 'False'
    Import-CxxuConfig -Path $path
    if ($env:PsTabSynopsis -cne 'False') { throw 'Config overrode explicit environment' }
    Set-CxxuComponentOption -Id Tab -Name Synopsis -Value $false -Persist -Path $path
    Remove-Item Env:PsTabSynopsis -ErrorAction Ignore
    Import-CxxuConfig -Path $path
    if ($env:PsTabSynopsis -cne 'False') { throw 'Persisted disable did not load' }
    if (Get-Module CxxuTab) { throw 'Managing synopsis imported CxxuTab' }
    Write-Output "PASS: synopsis option defaults, bool/string validation, WhatIf, persistence, backup, environment priority and lazy loading; PS=$($PSVersionTable.PSVersion)"
}
finally
{
    $env:PsTabSynopsis = $oldSynopsis
    $env:PsTab = $oldTab
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
