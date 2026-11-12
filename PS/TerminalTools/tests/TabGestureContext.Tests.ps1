<#
.SYNOPSIS
验证 Tab 手势桩只在裸命令名位置导入增强层，不执行外部命令。
.EXAMPLE
pwsh -NoProfile -File ./PS/TerminalTools/tests/TabGestureContext.Tests.ps1
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../TerminalTools.psd1') -Force
$module = Get-Module TerminalTools

# 以测试模块代替增强层，直接观察桩是否发起导入，不受真实 DLL 与缓存影响。
& $module {
    function script:Get-Module { param($Name) return $null }
    function script:Set-PSReadLineKeyHandler { param($Key, $BriefDescription, $Description, $ScriptBlock) }
    function script:Import-Module { param($Name, [switch]$Global) $global:CxxuContextImports++ }
}
$oldTab = (Get-Command TabExpansion2 -CommandType Function).ScriptBlock
$oldPsTab = $env:PsTab
try
{
    $cases = @(
        @{ Line = '<cursor>'; Load = $false },
        @{ Line = 'Get-Chi<cursor>'; Load = $true },
        @{ Line = 'Get-Chi<cursor> -Force'; Load = $true },
        @{ Line = 'Get-ChildItem -Pa<cursor>'; Load = $false },
        @{ Line = 'git --ver<cursor>'; Load = $false },
        @{ Line = './PS/<cursor>'; Load = $false },
        @{ Line = 'PS<cursor>/Init/'; Load = $false },
        @{ Line = '.\PS\<cursor>'; Load = $false },
        @{ Line = 'C:\Windows\<cursor>'; Load = $false },
        @{ Line = '\\server\share\<cursor>'; Load = $false },
        @{ Line = 'Env:Pa<cursor>'; Load = $false },
        @{ Line = 'Get-ChildItem ./PS/<cursor>'; Load = $false },
        @{ Line = '$env:PA<cursor>'; Load = $false },
        @{ Line = '& $command<cursor>'; Load = $false },
        @{ Line = "& 'Get-Chi<cursor>'"; Load = $false },
        @{ Line = '& Get-Chi<cursor>'; Load = $true },
        @{ Line = 'Write-Output x | Get-Chi<cursor>'; Load = $true },
        @{ Line = 'Get-Chi<cursor> | Write-Output x'; Load = $true },
        @{ Line = 'Write-Output x; Get-Chi<cursor>'; Load = $true },
        @{ Line = 'Write-Output $(Get-Chi<cursor>)'; Load = $true },
        @{ Line = 'Get-ChildItem > ./out<cursor>'; Load = $false },
        @{ Line = 'Get-ChildItem > <cursor>'; Load = $false },
        @{ Line = 'Get-ChildItem | <cursor>'; Load = $false },
        @{ Line = 'Get-*Chi<cursor>'; Load = $true }
    )
    foreach ($case in $cases)
    {
        $env:PsTab = 'True'
        $global:CxxuContextImports = 0
        $global:PsUxTabStub = $false
        $global:PsUxNoCxxuTab = $false
        function global:TabExpansion2 { param($inputScript, $cursorColumn) 'native-fallback' }
        Install-PsUxGestureStubs -Force
        $cursor = $case.Line.IndexOf('<cursor>')
        $line = $case.Line.Replace('<cursor>', '')
        $actual = TabExpansion2 $line $cursor
        if (($global:CxxuContextImports -eq 1) -ne $case.Load -or $actual -ne 'native-fallback')
        {
            throw "Context mismatch: $($case.Line); imports=$global:CxxuContextImports; result=$actual"
        }
        if (-not $case.Load)
        {
            # 第一次透传不能拆桩：稍后补命令名仍应尝试导入。
            $null = TabExpansion2 'Get-Chi' 7
            if ($global:CxxuContextImports -ne 1) { throw "Stub removed too early: $($case.Line)" }
        }
    }
    foreach ($cursor in @(-1, 1000))
    {
        $global:CxxuContextImports = 0
        $global:PsUxTabStub = $false
        $global:PsUxNoCxxuTab = $false
        function global:TabExpansion2 { param($inputScript, $cursorColumn) 'native-fallback' }
        Install-PsUxGestureStubs -Force
        $null = TabExpansion2 'Get-Chi' $cursor
        if ($global:CxxuContextImports) { throw "Invalid cursor loaded module: $cursor" }
    }
    $env:PsTab = 'False'
    $null = TabExpansion2 'Get-Chi' 7
    if ($global:CxxuContextImports) { throw 'Disabled enhancement loaded module' }
    Write-Output 'PASS: bare command names, paths, parameters, nesting, retained stub and fallback'
}
finally
{
    Set-Item -Path 'function:global:TabExpansion2' -Value $oldTab
    $env:PsTab = $oldPsTab
    Remove-Variable CxxuContextImports, PsUxTabStub, PsUxNoCxxuTab, PsUxTabOriginal -Scope Global -ErrorAction SilentlyContinue
}
