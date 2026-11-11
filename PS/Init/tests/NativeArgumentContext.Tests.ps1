<#
.SYNOPSIS
验证原生命令补全的按需加载边界，不执行 init 或外部命令。
.EXAMPLE
pwsh -NoProfile -File ./PS/Init/tests/NativeArgumentContext.Tests.ps1
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Init.psd1') -Force
$initModule = Get-Module Init
$nativePath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$native = "& '$nativePath'"

function global:Invoke-CxxuContextFixture { param([string]$Value) $Value }
Set-Alias -Name cxxuContextFunction -Value Invoke-CxxuContextFixture -Scope Global
Set-Alias -Name cxxuContextNative -Value $nativePath -Scope Global

try
{
    $cases = @(
        @{ Line = '<cursor>'; Native = $false },
        @{ Line = 'Get-Chi<cursor>'; Native = $false },
        @{ Line = "$native<cursor>"; Native = $false },
        @{ Line = "$native <cursor>"; Native = $true },
        @{ Line = "$native --ver<cursor>"; Native = $true },
        @{ Line = 'Get-ChildItem -<cursor>'; Native = $false },
        @{ Line = 'Invoke-CxxuContextFixture -Value <cursor>'; Native = $false },
        @{ Line = 'cxxuContextFunction -Value <cursor>'; Native = $false },
        @{ Line = 'cxxuContextNative --ver<cursor>'; Native = $true },
        @{ Line = "& '$PSCommandPath' -<cursor>"; Native = $true },
        @{ Line = "Get-ChildItem | $native --ver<cursor>"; Native = $true },
        @{ Line = "$native --ver<cursor> | Get-ChildItem"; Native = $true },
        @{ Line = "$native --version | <cursor>"; Native = $false },
        @{ Line = "$native --version; Get-ChildItem -<cursor>"; Native = $false },
        @{ Line = "Write-Output x; $native --ver<cursor>"; Native = $true },
        @{ Line = ('Write-Output $(' + $native + ' --ver<cursor>)'); Native = $true },
        @{ Line = ($native + ' $(Get-Chi<cursor>)'); Native = $false },
        @{ Line = "$native > ./output<cursor>"; Native = $false },
        @{ Line = "$native > <cursor>"; Native = $false },
        @{ Line = "'$nativePath --ver<cursor>'"; Native = $false },
        @{ Line = '& $env:ComSpec /<cursor>'; Native = $true }
    )
    foreach ($case in $cases)
    {
        $cursor = $case.Line.IndexOf('<cursor>')
        $line = $case.Line.Replace('<cursor>', '')
        $actual = & $initModule { param($Line, $Cursor) Test-CxxuNativeArgumentContext -Line $Line -Cursor $Cursor } $line $cursor
        if ($actual -ne $case.Native)
        {
            throw "Context mismatch: $($case.Line); expected $($case.Native), got $actual"
        }
    }
    foreach ($cursor in @(-1, 1000))
    {
        if (& $initModule { param($Cursor) Test-CxxuNativeArgumentContext -Line 'Get-ChildItem' -Cursor $Cursor } $cursor)
        {
            throw "Invalid cursor accepted: $cursor"
        }
    }
    Write-Output 'PASS: native argument contexts, aliases, pipelines, nested commands and redirections'
}
finally
{
    Remove-Item -LiteralPath 'Function:/Invoke-CxxuContextFixture' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'Alias:/cxxuContextFunction', 'Alias:/cxxuContextNative' -ErrorAction SilentlyContinue
}
