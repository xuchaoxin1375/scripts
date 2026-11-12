<#
.SYNOPSIS
验证摘要默认跳过索引和源码解析，显式开启后保留中文摘要与原生语法。
.EXAMPLE
pwsh -NoProfile -File ./PS/CxxuTab/tests/SynopsisOptIn.Tests.ps1
#>
$ErrorActionPreference = 'Stop'
$oldSynopsis = $env:PsTabSynopsis
$oldPsTab = $env:PsTab
$oldTab = (Get-Command TabExpansion2 -CommandType Function).ScriptBlock
try
{
    $env:PsTab = 'True'
    function global:Get-CxxuSynopsisFixture
    {
        <#
        .SYNOPSIS
        用于验证菜单摘要的中文内容。
        #>
        [CmdletBinding()]
        param([string]$Name)
    }
    Import-Module (Join-Path $PSScriptRoot '../CxxuTab.psd1') -Global -Force
    # 隔离模糊匹配，仅比较真实包装入口的摘要分支与原生候选。
    $global:__CxxuTabMethod = $null
    $line = 'Get-CxxuSynopsisFixt'
    $native = & $global:__CxxuTabOriginal $line $line.Length
    $original = @($native.CompletionMatches | Where-Object CompletionText -eq 'Get-CxxuSynopsisFixture')
    if ($original.Count -ne 1 -or -not $original[0].ToolTip) { throw 'Native fixture missing' }
    $globals = @('__CxxuTabSynCache', '__CxxuTabModMap', '__CxxuTabModSrc', '__CxxuTabModFiles', '__CxxuTabSrcSynCache')
    foreach ($setting in @($null, '', 'False', '0', 'No', 'Off', 'invalid'))
    {
        $env:PsTabSynopsis = $setting
        foreach ($name in $globals) { Remove-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue }
        $actual = TabExpansion2 $line $line.Length
        if ($global:__CxxuTabSynFuse -or $global:__CxxuTabFuse) { throw 'Unexpected completion fuse' }
        foreach ($name in $globals)
        {
            if (Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue) { throw "Disabled synopsis initialized $name; setting=[$setting]" }
        }
        $rows = @($actual.CompletionMatches)
        if ($rows.Count -ne $native.CompletionMatches.Count -or
            $actual.ReplacementIndex -ne $native.ReplacementIndex -or
            $actual.ReplacementLength -ne $native.ReplacementLength) { throw 'Native completion shape changed' }
        for ($i = 0; $i -lt $rows.Count; $i++)
        {
            foreach ($field in @('CompletionText', 'ListItemText', 'ResultType', 'ToolTip'))
            {
                if ($rows[$i].$field -cne $native.CompletionMatches[$i].$field) { throw "Native $field changed with synopsis disabled" }
            }
        }
    }
    foreach ($setting in @('True', '1', 'Yes', 'On', 'tRuE'))
    {
        $env:PsTabSynopsis = $setting
        $actual = TabExpansion2 $line $line.Length
        $row = $actual.CompletionMatches | Where-Object CompletionText -eq 'Get-CxxuSynopsisFixture'
        if (-not $row.ToolTip.StartsWith('用于验证菜单摘要的中文内容。') -or
            -not $row.ToolTip.EndsWith($original[0].ToolTip.Trim())) { throw "Synopsis or native syntax missing: $setting" }
        if ($global:__CxxuTabSynFuse -or $global:__CxxuTabFuse) { throw 'Enabled synopsis failed' }
    }
    $env:PsTabSynopsis = 'False'
    $again = TabExpansion2 $line $line.Length
    $row = $again.CompletionMatches | Where-Object CompletionText -eq 'Get-CxxuSynopsisFixture'
    if ($row.ToolTip -cne $original[0].ToolTip) { throw 'Runtime synopsis disable retained decoration' }
    Write-Output "PASS: synopsis opt-in, disabled cold paths, Chinese summary, original candidates and syntax; PS=$($PSVersionTable.PSVersion)"
}
finally
{
    Set-Item -Path function:global:TabExpansion2 -Value $oldTab
    $env:PsTabSynopsis = $oldSynopsis
    $env:PsTab = $oldPsTab
    Remove-Item function:global:Get-CxxuSynopsisFixture -ErrorAction SilentlyContinue
    Remove-Variable -Name __CxxuTabMethod, __CxxuTabOriginal, __CxxuTabFuse, __CxxuTabSynFuse, __CxxuTabSynCache, __CxxuTabModMap, __CxxuTabModSrc, __CxxuTabModFiles, __CxxuTabSrcSynCache -Scope Global -ErrorAction SilentlyContinue
}
