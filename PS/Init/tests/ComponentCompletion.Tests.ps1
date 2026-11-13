<#
.SYNOPSIS
通过 PowerShell 原生补全入口验证组件管理候选、中文提示与帮助，不读写个人配置。
.EXAMPLE
pwsh -NoProfile -File ./PS/Init/tests/ComponentCompletion.Tests.ps1
#>
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Init.psd1') -Force
$module = Get-Module Init
if (& $module { $null -ne $script:CxxuComponentManifestCache }) { throw 'Import eagerly read component manifest' }
$loadedBefore = @(Get-Module | ForEach-Object Name)
$envBefore = @(Get-ChildItem Env: | Where-Object Name -like 'Ps*' | Sort-Object Name | ForEach-Object { $_.Name + '=' + $_.Value }) -join "`n"
$root = Join-Path ([IO.Path]::GetTempPath()) ('cxxu-component-completion-' + [guid]::NewGuid().ToString('N'))

function Assert-Completion
{
    param([string]$Line, [string[]]$Expected, [int]$Cursor = -1)
    if ($Cursor -lt 0) { $Cursor = $Line.Length }
    $result = [System.Management.Automation.CommandCompletion]::CompleteInput($Line, $Cursor, $null)
    $values = @($result.CompletionMatches | Where-Object ResultType -eq ParameterValue)
    if ($Expected.Count -gt 0 -and $values.Count -ne @($result.CompletionMatches).Count) { throw ('Non-component candidates mixed into ' + $Line) }
    if ((@($values | ForEach-Object CompletionText) -join '|') -cne ($Expected -join '|'))
    {
        throw ('Unexpected candidates: {0}; actual={1}; expected={2}' -f $Line, ($values.CompletionText -join ','), ($Expected -join ','))
    }
    foreach ($item in $values)
    {
        if ($item.ToolTip -notmatch '[\u4e00-\u9fff]' -or $item.ToolTip.Contains([string][char]0xfffd)) { throw 'Missing or corrupted Chinese tooltip' }
    }
}

try
{
    $null = New-Item -ItemType Directory -Path $root
    $marker = Join-Path $root 'config.psd1'
    [IO.File]::WriteAllText($marker, 'invalid config: completion must not parse this file', [Text.UTF8Encoding]::new($false))
    $manifest = & $module { @(Read-CxxuComponentManifest) }
    $ids = @($manifest | ForEach-Object { [string]$_.Id })
    $optionIds = @($manifest | Where-Object { @($_.Options | Where-Object { $_ }).Count } | ForEach-Object { [string]$_.Id })
    foreach ($command in @('Get-CxxuComponent', 'Enable-CxxuComponent', 'Disable-CxxuComponent'))
    {
        Assert-Completion ($command + ' -Id ') $ids
        Assert-Completion ($command + ' -Id tA') @('Tab')
    }
    Assert-Completion 'Set-CxxuComponentOption -Id ' $optionIds
    Assert-Completion 'Init\Set-CxxuComponentOption -Id ' $optionIds
    Set-Alias -Name SetComponentFixture -Value Set-CxxuComponentOption
    Assert-Completion 'SetComponentFixture -Id ' $optionIds
    Assert-Completion 'Enable-CxxuComponent Ta' @('Tab')
    Assert-Completion "Set-CxxuComponentOption -Id 'ta" @('Tab')
    Assert-Completion 'Init\Get-CxxuComponent -Id Ta' @('Tab')
    Assert-Completion 'Set-CxxuComponentOption -Id Tab -Name ' @('Synopsis')
    Assert-Completion 'Set-CxxuComponentOption -Id tab -Name sy' @('Synopsis')
    Assert-Completion 'Set-CxxuComponentOption -Id Tab -Name Synopsis -Value ' @('False', 'True')
    Assert-Completion 'Set-CxxuComponentOption -Name Synopsis -Id Tab -Value t' @('True')
    Assert-Completion 'Set-CxxuComponentOption -Id GitCompletion -Name Source -Value ' @('Auto', 'GitCompletion', 'Carapace', 'Argc')
    Assert-Completion 'Set-CxxuComponentOption -Id Carapace -Name ' @('Excludes')
    Assert-Completion 'Set-CxxuComponentOption -Id Carapace -Name Excludes -Value ' @()
    Assert-Completion 'Set-CxxuComponentOption -Id Unknown -Name ' @()
    Assert-Completion 'Set-CxxuComponentOption -Id Tab -Name Unknown -Value ' @()
    Assert-Completion 'Set-CxxuComponentOption -Name ' @()
    Assert-Completion 'Set-CxxuComponentOption -Id Tab -Name Synopsis -Value zz' @()
    Assert-Completion 'Set-CxxuComponentOption -Id [' @()
    Assert-Completion ("Set-CxxuComponentOption -Path '$marker' -Id Tab -Name Synopsis -Value F") @('False')
    $reordered = 'Set-CxxuComponentOption -Value T -Name Synopsis -Id Tab'
    Assert-Completion $reordered @('True') ($reordered.IndexOf(' T ') + 2)
    $line = 'Set-CxxuComponentOption -Id Tab -Name Synopsis -Value F'
    $tab = TabExpansion2 -inputScript $line -cursorColumn $line.Length
    if (@($tab.CompletionMatches).Count -ne 1 -or $tab.CompletionMatches[0].CompletionText -cne 'False') { throw 'TabExpansion2 did not use enum completer' }

    # 补全元数据变动应立即反映，避免测试只证明手写名单碰巧与清单一致。
    & $module { $script:CxxuComponentManifestCache += @{ Id = 'CompletionFixture'; Description = '测试候选'; Default = $false; Options = @(@{ Name = 'Mode'; Type = 'Enum'; Default = 'With Space'; Values = @('With Space', "It's"); Description = '测试枚举' }) } }
    Assert-Completion 'Set-CxxuComponentOption -Id CompletionF' @('CompletionFixture')
    Assert-Completion 'Set-CxxuComponentOption -Id CompletionFixture -Name ' @('Mode')
    Assert-Completion 'Set-CxxuComponentOption -Id CompletionFixture -Name Mode -Value ' @("'With Space'", "'It''s'")

    $pathLine = "Set-CxxuComponentOption -Id Tab -Name Synopsis -Value False -Path '$root/config"
    $pathResult = [System.Management.Automation.CommandCompletion]::CompleteInput($pathLine, $pathLine.Length, $null)
    if (-not @($pathResult.CompletionMatches | Where-Object { $_.ResultType -eq 'ProviderItem' -and $_.ToolTip -eq $marker }).Count) { throw 'Native path completion was lost' }
    foreach ($command in @('Get-CxxuComponent', 'Enable-CxxuComponent', 'Disable-CxxuComponent', 'Set-CxxuComponentOption'))
    {
        $help = Get-Help $command -Full
        $parameters = (Get-Command $command).Parameters.Keys | Where-Object { $_ -in @('Id', 'Name', 'Value', 'Path', 'Persist', 'Now', 'Validate') }
        foreach ($name in $parameters)
        {
            $entry = @($help.parameters.parameter | Where-Object name -eq $name)
            if (-not $entry.Count -or [string]::IsNullOrWhiteSpace(($entry[0].description.Text -join ' '))) { throw ('Missing parameter help: ' + $command + '.' + $name) }
        }
        if (-not @($help.examples.example).Count) { throw ('Missing examples: ' + $command) }
    }
    $envAfter = @(Get-ChildItem Env: | Where-Object Name -like 'Ps*' | Sort-Object Name | ForEach-Object { $_.Name + '=' + $_.Value }) -join "`n"
    if ($envAfter -cne $envBefore) { throw 'Completion changed component environment' }
    if (@(Get-ChildItem -LiteralPath $root).Count -ne 1 -or [IO.File]::ReadAllText($marker) -cne 'invalid config: completion must not parse this file') { throw 'Completion wrote config or backups' }
    foreach ($name in @('CxxuTab', 'CxxuPredictor', 'PSFzf', 'git-completion', 'PSCompletions'))
    {
        if ($loadedBefore -notcontains $name -and (Get-Module $name)) { throw ('Completion loaded optional module: ' + $name) }
    }
    if (Get-Command Complete-CxxuComponentArgument -ErrorAction Ignore) { throw 'Private completion helper was exported' }
    Write-Output "PASS: native component/option/enum completion, quoting, reordered arguments, Chinese tooltips, paths, help and read-only lazy behavior; PS=$($PSVersionTable.PSVersion)"
}
finally
{
    Remove-Item Alias:SetComponentFixture -ErrorAction Ignore
    & $module { $script:CxxuComponentManifestCache = @($script:CxxuComponentManifestCache | Where-Object { $_.Id -ne 'CompletionFixture' }) }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
