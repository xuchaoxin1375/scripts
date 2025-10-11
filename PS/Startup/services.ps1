

param(
    $Interval = 1
)
# 启动服务
Write-Host 'Starting Services:' -ForegroundColor Magenta
# 向桌面写一个日志文件,来检查脚本文件是否能够被计划任务成功调用
# $log = 'C:\users\cxxu\Desktop\log_startupServices.txt' 
# "$(Get-Date),write by the StartupServices.txt Taskschd ">$log

# Get-Module -ListAvailable | Out-File -FilePath $log -Append
# 经过实验发现,使用system角色调用,导致自动导入模块无法自动导入,这里我们使用临时变通方法
$env:PSModulePath += ';C:\repos\scripts\ps'

Update-PwshEnvIfNotYet >> $log
"Check the pwshenv import status:$psenvmode">>$log

$services = { 
    Start-Aria2Rpc
    Start-AlistServer
    Start-ChfsServer 
}
$servicesStr = $services.ToString().Trim()
$services = $servicesStr -split '\s+'

foreach ($service in $services)
{
    & $service # > $null
    Write-Host " $service" -ForegroundColor Green 
    Start-Sleep $Interval
}
# Aria2Rpc的启动比较特殊
# Write-PsDebugLog -FunctionName 'Start-Aria2Rpc' -ModuleName Mount-NetDrive
# 检查相关服务是否启动成功(如果是线性任务,不需要延迟查看)
# Get-Process alist, chfs, aria2c
# Get-Process $services #services 不是程序名，而是cmdlet名字,无法直接作为get-Process 的参数
Write-Host 'All Services started!' -ForegroundColor Cyan
# 如果需要检查运行进程或服务,请使用PS <Name>查看,例如ps alist查看alist进程
# 也可以手动调用服务启动函数来检查,例如Start-ChfsServer,看看能否启动进程并维持,否则请修复相关启动命令
# 或者也可以查看服务软件的日志文件记录排查故障