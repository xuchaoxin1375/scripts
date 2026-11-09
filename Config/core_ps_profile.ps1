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

# git-completion: git/gitk 的 Tab 补全(v2 起必须手动注册 ArgumentCompleter)
# 首次补全才导入模块;argc-completions 认 $global:PsGitCompletion,把 git/gitk 让出来
if (@($env:PSModulePath -split [IO.Path]::PathSeparator) | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'git-completion')) })
{
    $global:PsGitCompletion = $true
    Register-ArgumentCompleter -CommandName git -Native -ScriptBlock {
        param($wordToComplete, $CommandAst, $CursorPosition)
        if (-not (Get-Module git-completion)) { Import-Module git-completion -Global -ErrorAction SilentlyContinue }
        if (Get-Command Complete-Git -ErrorAction SilentlyContinue) {
            return (Complete-Git -CommandAst $CommandAst -CursorPosition $CursorPosition)
        }
    }
    Register-ArgumentCompleter -CommandName gitk -Native -ScriptBlock {
        param($wordToComplete, $CommandAst, $CursorPosition)
        if (-not (Get-Module git-completion)) { Import-Module git-completion -Global -ErrorAction SilentlyContinue }
        if (Get-Command Complete-Gitk -ErrorAction SilentlyContinue) {
            return (Complete-Gitk -CommandAst $CommandAst -CursorPosition $CursorPosition)
        }
    }
}