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

    # Minimal 是 Fast 的兼容别名：步骤表必须完全一致。
    $env:PsStartupTier = 'Fast'
    $fastSteps = @(Get-StepNames 'Fast')
    $minimalSteps = @(Get-StepNames 'Minimal')
    Assert-True (($fastSteps -join ',') -eq ($minimalSteps -join ',')) "Minimal 应与 Fast 步骤一致：$($minimalSteps -join ',')"
    Assert-True (($minimalSteps -join ',') -eq 'Set-PSReadLinesCommon,Set-PSReadLinesAdvanced,Set-ArgcCompletions,Register-GitCompletion,Update-PwshVars,Set-PsPrompt') "Fast 步骤不符：$($minimalSteps -join ',')"

    Assert-Steps -Tier 'Fast' -MustHave @(
        'Set-PSReadLinesCommon', 'Set-PSReadLinesAdvanced', 'Set-ArgcCompletions', 'Register-GitCompletion', 'Update-PwshVars', 'Set-PsPrompt'
    ) -MustNotHave @(
        'Set-ArgumentCompleter', 'Confirm-EnvVarOfInfo', 'Register-PsUxLazyLoad', 'Register-CarapaceLazyLoad',
        'Import-PsCompletions', 'Initialize-Fnm', 'Initialize-ScoopSearch'
    )

    # 富提示符需要补回系统信息与 DataJson，即使档位是 Fast。
    $env:PsPrompt = 'Balance'
    Assert-Steps -Tier 'Fast' -MustHave @('Confirm-EnvVarOfInfo', 'Update-PwshVars', 'Confirm-DataJson', 'Set-PsPrompt') -MustNotHave @()
    $env:PsPrompt = ''

    $balanced = Get-StepNames 'Balanced'
    Assert-True ($balanced.Count -gt 0) 'Balanced 步骤为空'
    Assert-Steps -Tier 'Balanced' -MustHave @(
        'Set-PSReadLinesCommon', 'Set-PSReadLinesAdvanced', 'Set-ArgumentCompleter', 'Confirm-EnvVarOfInfo',
        'Update-PwshVars', 'Set-PsPrompt', 'Register-PsUxLazyLoad', 'Set-ArgcCompletions', 'Register-GitCompletion'
    ) -MustNotHave @()

    $tierChecks = & $module {
        [pscustomobject]@{
            MinimalTab = Test-CxxuTierAllowsComponent -Tier Minimal -Id Tab
            MinimalArgc = Test-CxxuTierAllowsComponent -Tier Minimal -Id Argc
            FastTab    = Test-CxxuTierAllowsComponent -Tier Fast -Id Tab
            FastArgc   = Test-CxxuTierAllowsComponent -Tier Fast -Id Argc
            FastGit    = Test-CxxuTierAllowsComponent -Tier Fast -Id GitCompletion
            BalancedTab = Test-CxxuTierAllowsComponent -Tier Balanced -Id Tab
        }
    }
    Assert-True (-not $tierChecks.MinimalTab) 'Minimal（Fast 别名）不应允许 Tab'
    Assert-True $tierChecks.MinimalArgc 'Minimal（Fast 别名）应允许 Argc'
    Assert-True (-not $tierChecks.FastTab) 'Fast 不应允许 Tab'
    Assert-True $tierChecks.FastArgc 'Fast 应允许 Argc'
    Assert-True $tierChecks.FastGit 'Fast 应允许 GitCompletion'
    Assert-True $tierChecks.BalancedTab 'Balanced 应允许 Tab'

    # 进度条 Auto 跟随档位，显式值优先；不在 init 回写环境变量。
    $progressChecks = & $module {
        [pscustomobject]@{
            AutoFast      = Resolve-CxxuShowProgressSetting -Setting 'Auto' -Tier Fast
            AutoBalanced  = Resolve-CxxuShowProgressSetting -Setting 'Auto' -Tier Balanced
            EmptyFast     = Resolve-CxxuShowProgressSetting -Setting '' -Tier Fast
            ExplicitTrue  = Resolve-CxxuShowProgressSetting -Setting 'True' -Tier Fast
            ExplicitFalse = Resolve-CxxuShowProgressSetting -Setting 'False' -Tier Balanced
        }
    }
    Assert-True ($progressChecks.AutoFast -eq 'False') 'Auto 在 Fast 下应解析为 False'
    Assert-True ($progressChecks.AutoBalanced -eq 'True') 'Auto 在 Balanced 下应解析为 True'
    Assert-True ($progressChecks.EmptyFast -eq 'False') '空值在 Fast 下应解析为 False'
    Assert-True ($progressChecks.ExplicitTrue -eq 'True') '显式 True 不应被档位覆盖'
    Assert-True ($progressChecks.ExplicitFalse -eq 'False') '显式 False 不应被档位覆盖'

    New-CxxuConfigTemplate -Path $configPath -Force | Out-Null
    # 模板写入的进度条默认值是 Auto（跟随档位），不是写死的 True。
    $progressRow = Get-CxxuConfig -Path $configPath | Where-Object Key -eq PsShowProgress
    Assert-True ($progressRow.Default -eq 'Auto') 'PsShowProgress 默认值应为 Auto'
    Assert-True ((Get-Content -LiteralPath $configPath -Raw) -match "PsShowProgress\s*=\s*'Auto'") '模板应写入 PsShowProgress = Auto'
    $env:PsStartupTier = 'Fast'
    $fastTab = Get-CxxuComponent -Id Tab -Path $configPath
    Assert-True ($fastTab.Tier -eq 'Fast') 'Get-CxxuComponent 未报告 Fast 档位'
    Assert-True (-not $fastTab.TierAllowed) 'Fast 下 Tab.TierAllowed 应为 False'
    Assert-True (-not $fastTab.Effective) 'Fast 下 Tab.Effective 应为 False'
    $fastArgc = Get-CxxuComponent -Id Argc -Path $configPath
    Assert-True $fastArgc.Effective 'Fast 下 Argc.Effective 应为 True'

    Set-PsStartupTier Minimal -WhatIf -Path $configPath | Out-Null
    Assert-True ($env:PsStartupTier -eq 'Fast') 'WhatIf 不应改当前进程档位'
    # Minimal 归一化为 Fast：写入配置的应是 Fast。
    Set-PsStartupTier Minimal -Persist -Path $configPath | Out-Null
    Assert-True ($env:PsStartupTier -eq 'Fast') 'Set-PsStartupTier 未把 Minimal 归一化为 Fast'
    Remove-Item Env:PsStartupTier -ErrorAction Ignore
    $saved = Get-CxxuConfig -Path $configPath | Where-Object Key -eq PsStartupTier
    Assert-True ($saved.Value -eq 'Fast') 'PsStartupTier 未按 Fast 写入配置'
    Assert-True ($saved.Source -eq '配置文件') 'PsStartupTier 配置来源不符'

    $env:PsStartupTier = 'Minimal'
    $normalized = & $module { Get-CxxuStartupTier }
    Assert-True ($normalized -eq 'Fast') 'Minimal 应归一化为 Fast'
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
