<#
.SYNOPSIS
验证启动档位的步骤过滤、组件上限、配置读写与富提示符回补，不执行完整 init。
.EXAMPLE
pwsh -NoProfile -File ./PS/Init/tests/StartupTier.Tests.ps1
#>
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Init.psd1') -Force
$module = Get-Module Init
$root = Join-Path ([IO.Path]::GetTempPath()) ('cxxu-startup-tier-' + [guid]::NewGuid().ToString('N'))
$configPath = Join-Path $root 'config.psd1'
$oldTier = $env:PsStartupTier
$oldPrompt = $env:PsPrompt

function Assert-True
{
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Get-StepNames
{
    param([string]$Tier)
    @(& $module { param($t) Get-CxxuInitStepsForTier -Tier $t } $Tier | ForEach-Object { [string]$_.Name })
}
function Assert-Steps
{
    param([string]$Tier, [string[]]$MustHave, [string[]]$MustNotHave)
    $names = @(Get-StepNames $Tier)
    foreach ($name in @($MustHave))
    {
        Assert-True ($names -contains $name) "档位 $Tier 缺少步骤 $name；实际：$($names -join ',')"
    }
    foreach ($name in @($MustNotHave))
    {
        Assert-True (-not ($names -contains $name)) "档位 $Tier 不应包含步骤 $name；实际：$($names -join ',')"
    }
}

try
{
    $null = New-Item -ItemType Directory -Path $root

    $env:PsStartupTier = 'Minimal'
    $env:PsPrompt = 'Simple'
    $minimal = Get-StepNames 'Minimal'
    Assert-True (($minimal -join ',') -eq 'Set-PSReadLinesCommon,Set-PsPrompt') "Minimal 步骤不符：$($minimal -join ',')"

    $env:PsStartupTier = 'Fast'
    Assert-Steps -Tier 'Fast' -MustHave @(
        'Set-PSReadLinesCommon', 'Set-PSReadLinesAdvanced', 'Set-ArgcCompletions', 'Register-GitCompletion', 'Set-PsPrompt'
    ) -MustNotHave @(
        'Set-ArgumentCompleter', 'Confirm-EnvVarOfInfo', 'Register-PsUxLazyLoad', 'Register-CarapaceLazyLoad',
        'Import-PsCompletions', 'Initialize-Fnm', 'Initialize-ScoopSearch'
    )

    # 富提示符需要补回系统信息与 DataJson，即使档位是 Fast。
    $env:PsPrompt = 'Balance'
    Assert-Steps -Tier 'Fast' -MustHave @('Confirm-EnvVarOfInfo', 'Confirm-DataJson', 'Set-PsPrompt') -MustNotHave @()
    $env:PsPrompt = ''

    $balanced = Get-StepNames 'Balanced'
    Assert-True ($balanced.Count -gt 0) 'Balanced 步骤为空'
    Assert-Steps -Tier 'Balanced' -MustHave @(
        'Set-PSReadLinesCommon', 'Set-PSReadLinesAdvanced', 'Set-ArgumentCompleter', 'Confirm-EnvVarOfInfo',
        'Set-PsPrompt', 'Register-PsUxLazyLoad', 'Set-ArgcCompletions', 'Register-GitCompletion'
    ) -MustNotHave @()

    $tierChecks = & $module {
        [pscustomobject]@{
            MinimalTab = Test-CxxuTierAllowsComponent -Tier Minimal -Id Tab
            FastTab    = Test-CxxuTierAllowsComponent -Tier Fast -Id Tab
            FastArgc   = Test-CxxuTierAllowsComponent -Tier Fast -Id Argc
            FastGit    = Test-CxxuTierAllowsComponent -Tier Fast -Id GitCompletion
            BalancedTab = Test-CxxuTierAllowsComponent -Tier Balanced -Id Tab
        }
    }
    Assert-True (-not $tierChecks.MinimalTab) 'Minimal 不应允许 Tab'
    Assert-True (-not $tierChecks.FastTab) 'Fast 不应允许 Tab'
    Assert-True $tierChecks.FastArgc 'Fast 应允许 Argc'
    Assert-True $tierChecks.FastGit 'Fast 应允许 GitCompletion'
    Assert-True $tierChecks.BalancedTab 'Balanced 应允许 Tab'

    New-CxxuConfigTemplate -Path $configPath -Force | Out-Null
    $env:PsStartupTier = 'Fast'
    $fastTab = Get-CxxuComponent -Id Tab -Path $configPath
    Assert-True ($fastTab.Tier -eq 'Fast') 'Get-CxxuComponent 未报告 Fast 档位'
    Assert-True (-not $fastTab.TierAllowed) 'Fast 下 Tab.TierAllowed 应为 False'
    Assert-True (-not $fastTab.Effective) 'Fast 下 Tab.Effective 应为 False'
    $fastArgc = Get-CxxuComponent -Id Argc -Path $configPath
    Assert-True $fastArgc.Effective 'Fast 下 Argc.Effective 应为 True'

    Set-PsStartupTier Minimal -WhatIf -Path $configPath | Out-Null
    Assert-True ($env:PsStartupTier -eq 'Fast') 'WhatIf 不应改当前进程档位'
    Set-PsStartupTier Minimal -Persist -Path $configPath | Out-Null
    Assert-True ($env:PsStartupTier -eq 'Minimal') 'Set-PsStartupTier 未更新当前进程'
    Remove-Item Env:PsStartupTier -ErrorAction Ignore
    $saved = Get-CxxuConfig -Path $configPath | Where-Object Key -eq PsStartupTier
    Assert-True ($saved.Value -eq 'Minimal') 'PsStartupTier 未写入配置'
    Assert-True ($saved.Source -eq '配置文件') 'PsStartupTier 配置来源不符'

    $env:PsStartupTier = 'Bogus'
    $fallback = & $module { Get-CxxuStartupTier }
    Assert-True ($fallback -eq 'Balanced') '非法档位应回退 Balanced'

    'PASS: startup tiers'
}
finally
{
    $env:PsStartupTier = $oldTier
    $env:PsPrompt = $oldPrompt
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Ignore
}
