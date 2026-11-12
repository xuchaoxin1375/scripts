<#
.SYNOPSIS
验证 argc 一次注册全部命令，保留 git 来源、幂等及强制重注册语义。
.EXAMPLE
pwsh -NoProfile -File ./PS/Init/tests/ArgcBatchRegistration.Tests.ps1
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Init.psd1') -Force
$module = Get-Module Init
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('cxxu-argc-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'completions'))
foreach ($name in @('git', 'gitk', 'fixture-cli'))
{
    [IO.File]::WriteAllText((Join-Path $fixture ('completions/' + $name + '.sh')), '# fixture')
}
try
{
    & $module {
        param($Root)
        $script:ArgcTestRoot = $Root
        $script:ArgcTestCalls = 0
        $script:ArgcTestSource = 'Carapace'
        function script:Get-ArgcCompletionsRoot { $script:ArgcTestRoot }
        function script:Set-ArgcCompletionsEnvironment { param($Root) }
        function script:Get-CxxuArgcExecutable { param($Root) 'fixture-argc' }
        function script:Get-CxxuGitCompletionSource { $script:ArgcTestSource }
        function script:Register-ArgumentCompleter
        {
            param([switch]$Native, [scriptblock]$ScriptBlock, [string[]]$CommandName)
            $script:ArgcTestCalls++
            $script:ArgcTestCommands = $CommandName
            if (-not $Native -or -not $ScriptBlock) { throw 'Completer contract missing' }
        }
    } $fixture
    $global:PsArgcLoaded = $false
    $global:PsCarapaceGit = $true
    Initialize-ArgcCompletions
    $state = & $module { ,@($script:ArgcTestCalls, $script:ArgcTestCommands) }
    if ($state[0] -ne 1 -or $state[1].Count -ne 2 -or $state[1] -notcontains 'argc' -or
        $state[1] -notcontains 'fixture-cli' -or $global:PsArgcScripts.ContainsKey('git') -or
        -not $global:PsArgcLoaded -or $global:PsArgcUnavailable) { throw 'Batch registration/ownership failed' }
    Initialize-ArgcCompletions
    if ((& $module { $script:ArgcTestCalls }) -ne 1) { throw 'Idempotence failed' }
    & $module { $script:ArgcTestSource = 'Argc' }
    Initialize-ArgcCompletions -Force
    if ((& $module { $script:ArgcTestCalls }) -ne 2 -or -not $global:PsArgcScripts.ContainsKey('git') -or
        -not $global:PsArgcScripts.ContainsKey('gitk') -or $global:PsGitCompletionActive -ne 'Argc')
    {
        throw 'Explicit argc ownership/forced registration failed'
    }
    Write-Output 'PASS: argc batch registration, git ownership, idempotence and Force'
}
finally
{
    if ([IO.Directory]::Exists($fixture)) { [IO.Directory]::Delete($fixture, $true) }
    Remove-Variable PsArgcLoaded, PsArgcScripts, PsArgcUnavailable, PsCarapaceGit, PsGitCompletionActive -Scope Global -ErrorAction SilentlyContinue
}
