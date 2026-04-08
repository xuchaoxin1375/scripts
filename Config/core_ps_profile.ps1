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