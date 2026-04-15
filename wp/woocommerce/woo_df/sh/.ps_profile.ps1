Write-Host "Loading ps env(for *nix)"
$CxxuPSModulePath = "$HOME/repos/scripts/PS"
if ($env:PSModulePath -notlike "*$CxxuPSModulePath*")
{
    $env:PSModulePath += ":$CxxuPSModulePath"
}
# echo $env:PsPrompt
if (!$IsWindows)
{
    Set-PsPrompt $env:PsPrompt #(*nix平台上区分大小写)
    # Write-Host $env:PsPrompt
}
# AutoRun commands from CxxuPsModules 04/06/2026 14:44:04
init
# 全局补全模块需要特殊处理,放在profile中,但是该模块可能导致ipmof|iex报错,所以不自动启用为好
# Confirm-ModuleInstalled -Name PsCompletions -Install *> $null
# Import-Module PSCompletions
        
# $res = Get-Command 'scoop-search' -ErrorAction SilentlyContinue
# if ($res)
# {
#     Write-Host 'scoop-search hook loaded!'
#     Invoke-Expression (&scoop-search --hook)
# }
# End AutoRun commands from CxxuPsModules
# argc-completions
# Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete
$env:ARGC_COMPLETIONS_ROOT = '/Users/cxxu/repos/argc-completions'
if(Test-Path $env:ARGC_COMPLETIONS_ROOT)
{

    $env:ARGC_COMPLETIONS_PATH = ($env:ARGC_COMPLETIONS_ROOT + '/completions/macos:' + $env:ARGC_COMPLETIONS_ROOT + '/completions')
    $env:PATH = $env:ARGC_COMPLETIONS_ROOT + '/bin' + [IO.Path]::PathSeparator + $env:PATH
    # To add completions for only the specified command, modify next line e.g. $argc_scripts = @("cargo", "git")
    $argc_scripts = ((Get-ChildItem -File -Path ($env:ARGC_COMPLETIONS_ROOT + '/completions/macos'), ($env:ARGC_COMPLETIONS_ROOT + '/completions')) | ForEach-Object { $_.BaseName })
    argc --argc-completions powershell $argc_scripts | Out-String | Invoke-Expression
}