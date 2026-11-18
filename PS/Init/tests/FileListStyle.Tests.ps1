<#
.SYNOPSIS
验证文件列表配色：配置默认值、Auto/Classic/Off 取值与持久化，不执行完整 init。
.EXAMPLE
pwsh -NoProfile -File ./PS/Init/tests/FileListStyle.Tests.ps1
.EXAMPLE
powershell -NoProfile -File ./PS/Init/tests/FileListStyle.Tests.ps1
#>
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Init.psd1') -Force
$module = Get-Module Init
$root = Join-Path ([IO.Path]::GetTempPath()) ('cxxu-file-list-style-' + [guid]::NewGuid().ToString('N'))
$configPath = Join-Path $root 'config.psd1'
$oldStyle = $env:PsFileListStyle
$esc = [char]0x1b

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

try
{
    $null = New-Item -ItemType Directory -Path $root

    # 两个档位都要执行；5.1 由步骤的 MinPS 跳过。
    foreach ($tier in @('Fast', 'Balanced'))
    {
        $names = @(Get-StepNames $tier)
        Assert-True ($names -contains 'Set-PsFileListStyle') "档位 $tier 缺少 Set-PsFileListStyle"
    }

    # 默认值是 Auto，且能由 Get-CxxuConfig 读出。
    $row = Get-CxxuConfig -Path $configPath | Where-Object Key -eq PsFileListStyle
    Assert-True ($row.Default -eq 'Auto') 'PsFileListStyle 默认值应为 Auto'
    Assert-True ($row.Source -eq '默认值') '未配置时来源应为默认值'

    # 解析器：空值/未知值归 Auto，False/0/No 归 Off。
    $resolved = & $module {
        [pscustomobject]@{
            Empty   = Resolve-CxxuFileListStyle -Style ''
            Unknown = Resolve-CxxuFileListStyle -Style 'Bogus'
            False   = Resolve-CxxuFileListStyle -Style 'False'
            Zero    = Resolve-CxxuFileListStyle -Style '0'
            Classic = Resolve-CxxuFileListStyle -Style 'classic'
        }
    }
    Assert-True ($resolved.Empty -eq 'Auto') '空值应解析为 Auto'
    Assert-True ($resolved.Unknown -eq 'Auto') '未知值应解析为 Auto'
    Assert-True ($resolved.False -eq 'Off') 'False 应解析为 Off'
    Assert-True ($resolved.Zero -eq 'Off') '0 应解析为 Off'
    Assert-True ($resolved.Classic -eq 'Classic') 'classic 应不区分大小写解析为 Classic'

    # -Persist 必须同时给出 -Style；-WhatIf 不写环境变量。
    $threw = $false
    try { Set-PsFileListStyle -Persist -Path $configPath } catch { $threw = $true }
    Assert-True $threw '-Persist 未指定 -Style 时应报错'
    $env:PsFileListStyle = 'Classic'
    Set-PsFileListStyle -Style Auto -WhatIf
    Assert-True ($env:PsFileListStyle -eq 'Classic') 'WhatIf 不应写入环境变量'
    Remove-Item Env:PsFileListStyle -ErrorAction Ignore

    if ($PSVersionTable.PSVersion -lt [version]'7.2')
    {
        Write-Output "PASS: file list style config and steps (style skipped on PS $($PSVersionTable.PSVersion))"
        return
    }

    $saved = @{
        Directory    = $PSStyle.FileInfo.Directory
        SymbolicLink = $PSStyle.FileInfo.SymbolicLink
        Executable   = $PSStyle.FileInfo.Executable
    }

    # Auto：无背景的标准前景色。
    $env:PsFileListStyle = ''
    Set-PsFileListStyle
    Assert-True ($PSStyle.FileInfo.Directory -eq "$esc[34m") 'Auto 应把目录设为蓝色前景'
    Assert-True ($PSStyle.FileInfo.SymbolicLink -eq "$esc[36m") 'Auto 应把符号链接设为青色前景'
    Assert-True ($PSStyle.FileInfo.Executable -eq "$esc[32m") 'Auto 应把可执行文件设为绿色前景'
    Assert-True ($PSStyle.FileInfo.Directory -notmatch '44') 'Auto 不应保留背景色'

    # Classic：从环境变量读取，恢复原生蓝底与亮色。
    $env:PsFileListStyle = 'Classic'
    Set-PsFileListStyle
    Assert-True ($PSStyle.FileInfo.Directory -eq "$esc[44;1m") 'Classic 应恢复目录蓝底'
    Assert-True ($PSStyle.FileInfo.SymbolicLink -eq "$esc[36;1m") 'Classic 应恢复链接亮青'
    Assert-True ($PSStyle.FileInfo.Executable -eq "$esc[32;1m") 'Classic 应恢复可执行文件亮绿'

    # Off：显式指定并保持现有值。
    Set-PsFileListStyle -Style Off
    Assert-True ($env:PsFileListStyle -eq 'Off') '显式 -Style 应写入当前进程环境变量'
    Assert-True ($PSStyle.FileInfo.Directory -eq "$esc[44;1m") 'Off 不应改动现有配色'

    # 持久化：写入配置的 Settings 段。
    Set-PsFileListStyle -Style Off -Persist -Path $configPath
    Assert-True ((Get-Content -LiteralPath $configPath -Raw) -match "PsFileListStyle\s*=\s*'Off'") 'Persist 应写入 PsFileListStyle = Off'
    $savedRow = Get-CxxuConfig -Path $configPath | Where-Object Key -eq PsFileListStyle
    Assert-True ($savedRow.Value -eq 'Off') '配置中的 PsFileListStyle 应为 Off'

    Write-Output "PASS: file list style config, steps, Auto/Classic/Off and persist; PS=$($PSVersionTable.PSVersion)"
}
finally
{
    if ($PSVersionTable.PSVersion -ge [version]'7.2')
    {
        $PSStyle.FileInfo.Directory = $saved.Directory
        $PSStyle.FileInfo.SymbolicLink = $saved.SymbolicLink
        $PSStyle.FileInfo.Executable = $saved.Executable
    }
    if ($null -eq $oldStyle) { Remove-Item Env:PsFileListStyle -ErrorAction Ignore }
    else { $env:PsFileListStyle = $oldStyle }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Ignore
}
