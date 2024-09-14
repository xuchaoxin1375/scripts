
<# 

.SYNOPSIS
# 也可以在startup中调用这个脚本来运行,这里设置了参数$Interval,每隔$Interval秒启动下一个需要开机自启的服务或软件
这个脚本文件可以并入到startup中,比如用来套壳
    function Start-SoftwaresWhenStartup
    {
        
    }

.DESCRIPTION
脚本内获取脚本自己所在位置 Resolve-Path $PSScriptRoot

注意cfw会将日志打印占用终端,导致无法退出终端的问题,最为开机自启,如果使用 hidden参数隐藏窗口也是可以的
Start-Job -ScriptBlock { & 'C:\exes\cfw\Cfw.exe' }
使用start-job达不到效果,shell退出后,进程会消亡 sajb -ScriptBlock {C:\exes\chfs\chfs.exe --file ./chfs.ini}
可以使用vbs来启动阻塞性的进程
(vbs免弹出窗口,同时也不会由信息输出,所以可以不用后台执行)#详情查看readme.md中alist部分
Set-Location $chfs_home; "$chfs_home\startup.vbs" | Invoke-Expression
Set-Location $alist_home; "$alist_home\startup.vbs" | Invoke-Expression;

.EXAMPLE
#获取脚本帮助
PS> get-help $PS\startup\softwares.ps1

NAME
    C:\repos\scripts\PS\startup\softwares.ps1
    
SYNOPSIS
.EXAMPLE
[C:\repos\scripts\PS\Startup]
PS> .\softwares.ps1 -Interval 0.5
start apps every 0.5 seconds,to reduce the stress of the cpu load
Starting Services:
         chfs 
         alist 
All Services started!
 #>
[CmdletBinding()]
param (
        
    #默认每5秒启动一次,如果后续的服务需要间隔启动，可以单独设置,否则都取这个值
    $Interval = 5,
    # 可以单独设置每个服务的启动间隔时间
    # $IntervalServices = $Interval,
    #可以单独设置每个软件的启动间隔时间
    $IntervalSoftwares = $Interval
)

Update-PwshEnvIfNotYet #导入别名（需要的话）

Write-Host "start apps every $Interval seconds,to reduce the stress of the cpu load"
# Start-Sleep $Interval


#启动软件
$softwares = @(
    # 'dock_finder',
    'listary',
    'mydockfinder',
    'cfw' ,
    # 'whale',#公交车,虽然速度挺快,而且试用期长,但是容易导致许多网站使用出现频繁验证和报错,例如openai
    # 'Verge',
    'trafficMonitor', #配置在里面在个别场合容易启动失败,可以单独启动
    'snipaste', #高性能截图软件,用途比较单一
    # 'pixpin', #辅助snipaste用来长截图和录制gif以及做ocr
    'windhawk',
    'ditto'
    
    # memorymaster
)
Write-Host 'Starting Softwares:' -ForegroundColor Magenta

$index = 0
# 查看参数
# $PSBoundParameters | Format-Table 
# Write-Host "IntervalSoftwares: $IntervalSoftwares"

foreach ($item in $softwares)
{
    # Write-Output $item

    Start-Sleep $IntervalSoftwares
    # ($item | Invoke-Expression) 
    try
    {

        # $item | Invoke-Command -ScriptBlock { & $input ; Write-Verbose $input } -ErrorAction SilentlyContinue
        & $item
    }
    catch
    {
        #这里使用了-bacKgroundColor参数，是为了让颜色背景不要投影到下一行,这里使用-Noewline;转而使用Write-host ''(打印空)来换行
        Write-Host " $item is unavailable on the host!" -BackgroundColor Gray -NoNewline
        Write-Host ''
        
        continue
    }
    # Write-Host 'Start: ' -NoNewline
    # Write-Host $colors 

    Write-Host "`t $item " -ForegroundColor ($colors[$index]) 
    $index = ($index + 1) % $colors.Count
}

#其他软件启动
# trafficMonitor 

if ($TotalMemory -le 8)
{
    Write-Host 'The amount of memory is no more than 8G, the softwares will not be started.' -ForegroundColor Magenta
    memorymaster #this program will auto clean memory when the memory usage ratio is too high
}

Write-Host 'All softwares started!' -ForegroundColor Blue

Write-Host 'All done!' -ForegroundColor Green
#映射alist网络磁盘分区
# Set-AlistLocalhostDrive #用的不多,直接用网页版就够了,个别时候可以手动调用该函数映射一下