
<# 
.SYNOPSIS
每隔一定时间($interval) 将当前日期更新写入到$LastUpdateLog文件中

.DESCRIPTION
调整代码后可以单独调试一下功能
.Example
PS[BAT:77%][MEM:29.89% (9.48/31.70)GB][12:03:56]
# [C:\repos\scripts\PS\TaskSchdPwsh]
 .\LastTimeUpdater.ps1 -Interval 2

2024年4月19日 12:04:00
2024年4月19日 12:04:02
2024年4月19日 12:04:04


PS[BAT:77%][MEM:27.19% (8.62/31.70)GB][12:54:55]
# [C:\repos\scripts\PS\TaskSchdPwsh]
 .\LastTimeUpdater.ps1 -Interval 1 -LastUpdateLog $LastUpdateLog
...
.NOTES
# 默认把日志输入到用户家目录,或者本模块的log目录
# 家目录:($env:USERPROFILE + '\time_log')
# $OutPutFile = "$PSScriptRoot\log\time_log"

#>
param(
    $Interval = 2,
    $LastUpdateLog = ''
)
if ($env:Interval)
{
    $Interval = $env:Interval
    Write-Host $Interval -BackgroundColor DarkBlue
}
if ($LastUpdateLog -eq '')
{
    $DefaultPath = "$PSScriptRoot\log\LastUpdateLog"
    $LastUpdateLog = ($env:LastUpdateLog) ? $env:LastUpdateLog : $DefaultPath
    Write-Host $LastUpdateLog, $env:LastUpdateLog, '>>', $DefaultPath -BackgroundColor DarkCyan
}
# write-host 'Debuging LastTimeUpdater.ps1' -backgroundColor Magenta
# 调试的时候可以用路径:C:\users\cxxu\desktop\
# $LastUpdateLog = "$PSScriptRoot\log\LastUpdateLog"
if (-not (Test-Path $LastUpdateLog)) { New-Item -Force $LastUpdateLog } #如果不存在则创建
# $interval = 2

while ($true)
{
    # Get-Date > $OutPutFile
    $LastUpdate = (Get-Date).ToString()  #可以自定义格式(日期/时间)
    $OS = Get-CimInstance -ClassName Win32_OperatingSystem;
    # 访问硬件信息,所以比较耗时(100ms左右)
    $cachedTotalMemory = $OS.TotalVisibleMemorySize / 1MB;
    $cachedFreeMemory = $OS.FreePhysicalMemory / 1MB;

    $cachedFreeMemory, $cachedTotalMemory, $LastUpdate > $LastUpdateLog #这个指示保存位置的值的变量$LastUpdateLog定义在files.conf文件中
    # 调试的时候可以用|Tee-Object 

    Start-Sleep -Seconds $Interval
    # pause
    # Write-Host $LastUpdate
}
        