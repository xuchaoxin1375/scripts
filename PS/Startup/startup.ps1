<# 
.SYNOPSIS
this script is used to startup
It was be linked to user startup directory
.DESCRIPTION
This just invoke the startup function,which is defined in `Startup` module
#>


pwsh -noe -command Start-StartupTasks  #这里通过pwsh启动并添加-NoExit参数(-noe),不会退出shell

# startup #直接运行结束后会退出shell
# pwsh -NoExit -Command Get-Date 
# | Tee-Object "$PSScriptRoot\log\log.txt" 
# $(Get-DateTimeNumber)
