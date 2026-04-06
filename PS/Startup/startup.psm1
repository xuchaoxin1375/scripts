
<# 
# 为了更快的执行开机自启动脚本的执行速度,请在$startup_user目录内创建startup_basic.lnk,并且设置参数为如下
# powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\repos\scripts\startup\startup_basic.ps1"
#这样就不会加载不必要的配置,从而快速完成任务
#可以选择隐藏powershell窗口静默执行:使用选项-WindowStyle Hidden
# $scripts = 'C:\repos\scripts'

#导入基本的powershell环境变量和字符串
# Update-PwshVars
# Set-PwshAlias 
#导入常用命令别名(会占用若干秒的时间)
# 日志:记录当前时间
# "test:$(Get-Date)"> "$scripts\startup\log\log"
 #>
function Get-SystemVersionCoreInfoOfWindows
{
    param (
        
    )
    $os = Get-CimInstance Win32_OperatingSystem
    $Catption = $os.Caption
    ('Win' + $Catption.Split('Windows')[1]) + ' ' + "<$os.Version>"
}

function Get-WindowsOSVersionFromRegistry
{
    <# 
    .SYNOPSIS
    查询windows系统版本的信息
    
    .DESCRIPTION
    这里采用查询注册表的方式来获取相关信息

    指定了注册表路径 HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion，这里存储了 Windows 版本信息。
    定义了要查询的属性列表：
    ProductName：产品名称（如 "Windows 11 Pro"）
    DisplayVersion：显示版本（如 "22H2"）
    CurrentBuild：当前构建号
    UBR（Update Build Revision）：更新构建修订号
    遍历属性列表，从注册表中获取每个属性的值。
    构造完整版本号（CurrentBuild.UBR）。
    格式化输出信息。
    返回格式化后的输出。
    .NOTES
    win10的注冊表和win11有所不同,win10可能有:WinREVersion : 10.0.19041.3920 这种字段
    而win11则是其他形式,比如LCUVersion
        #>
    $registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'


    $result = (Get-ItemProperty -Path $registryPath )
    # 判断是否为 Windows 11
    $isWindows11 = [System.Environment]::OSVersion.Version.Build -ge 22000

    # 如果是 Windows 11 但 ProductName 显示为 Windows 10，则修正
    if ($isWindows11 -and $result.ProductName -like '*Windows 10*')
    {
        $result.ProductName = $result.ProductName -replace 'Windows 10', 'Windows 11'
    }
    # 下面这个拼接方式兼容性好点,可以兼容win10,win11
    $fullVersion = "$($result.CurrentMajorVersionNumber).$($result.CurrentMinorVersionNumber).$($result.CurrentBuild).$($result.UBR)"

    $res = [PSCustomObject]@{
        ProductName               = $result.ProductName
        DisplayVersion            = $result.DisplayVersion
        ReleaseId                 = $result.ReleaseId
        CurrentMajorVersionNumber = $result.CurrentMajorVersionNumber
        CurrentMinorVersionNumber = $result.CurrentMinorVersionNumber
        CurrentBuild              = $result.CurrentBuild
        UBR                       = $result.UBR
        FullVersion               = $fullVersion
        LCUVer                    = $result.LCUVer
        WinREVersion              = $result.WinREVersion
        
        # IsWindows11               = $isWindows11
    }
    return $res
}

function Get-windowsOSFullVersionCode
{
    <# 
    .SYNOPSIS
    利用cmd /c ver命令获取相应的包含完整系统版本号的字符串
    然后利用powershell的字符串处理方法进行过滤,最后提取出相应的字符串
    #>
    param (
        
    )
    cmd /c ver | Select-String '\d+\.\d+\.\d+\.\d+' | Select-Object -ExpandProperty Matches | Select-Object Value
    
}
function Confirm-OSVersionCaption
{
    <# 
    .SYNOPSIS
    确认系统存在OSCaption变量供其他进程使用
    .DESCRIPTION
    如果相应的环境变量缺失,那么执行计算并填充对应变量,否则跳过不做
    #>
    param (
        #强制更新或写入环境变量
        [alias('Update')][switch]$Force
    )
        
    if ($Force -or $null -eq $env:OSCaption)
    {
        if ($IsWindows)
        {

            $os = Get-CimInstance Win32_OperatingSystem
            $Catption = $os.Caption
            $cp = ('Win' + $Catption.Split('Windows')[1])
            Set-EnvVar -Name 'OSCaption' -NewValue $cp | Out-Null
        }
        else
        {
            $Catption = "macOS $(sw_vers -productVersion)"
            Set-EnvVar -Name 'OSCaption' -NewValue $Catption
        }
    }
    return $env:OSCaption
}

function Confirm-OSVersionFullCode
{
    <# 
    .SYNOPSIS
    确认系统存在OSCaption变量供其他进程使用
    .DESCRIPTION
    如果相应的环境变量缺失,那么执行计算并填充对应变量,否则跳过不做
    #>
    param (
        #强制更新或写入环境变量
        [alias('Update')][switch]$Force
    )
        
    if ($Force -or $null -eq $env:OSFullVersionCode)
    {
        if($IsWindows)
        {

            $code = Get-WindowsOSVersionFromRegistry | Select-Object -ExpandProperty FullVersion
        }
        else
        {
            $info = Get-WindowsVersionInfoOnDrive
            $OsVersion = $info.OSVersion
            $BuildNumber = $info.BuildNumber
            $code = "${OsVersion}-$BuildNumber"
        }
        Set-EnvVar -Name 'OSFullVersionCode' -NewValue $code
    }
    return $env:OSFullVersionCode
}
function Confirm-EnvVarOfInfo
{
    <# 
    .SYNOPSIS
    确认基本的系统环境信息,比如系统版本号等
    如果相应的环境变量缺失,那么执行计算并填充对应变量,否则跳过不做
    .DESCRIPTION
    除了开机自启，你也可以手动调用此函数随时检查相关环境变量

    #>
    param (
        
    )
    Confirm-OSVersionCaption > $null
    Confirm-OSVersionFullCode > $null
    if ($null -eq $env:Scripts)
    {
        $scripts = $PSScriptRoot | Split-Path | Split-Path 
        # $scripts=Split-Path $env:CxxuPSModulePath
        Set-EnvVar -Name 'Scripts' -NewValue $scripts
    }
    if ($null -eq $env:CxxuPSModulePath)
    {
        $CxxuPsModulePath = $PSScriptRoot | Split-Path
        Set-EnvVar -Name 'CxxuPSModulePath' -NewValue $CxxuPsModulePath
    }
    #确认是否启用扩展功能
    if ($null -eq $env:PsExtension)
    {
        Write-Verbose 'confrim pwsh extension functions' -Verbose
        Set-EnvVar -Name 'PsExtension' -NewValue 'False' #默认禁用扩展部分，加快安装和pwsh启动速度
    }
}
function Start-StartupTasks
{

    <# 
    .SYNOPSIS
    自动执行开机启动任务
    .DESCRIPTION
    取别名时如果直接用startup,有和其他startup脚本发生潜地冲突
    如果发生冲突,直接调用本函数(原名)而不是别名调用
     #>
    param(
        # 开机启动结束后是否要暂停退出shell,默认会退出(如果是在shell内调用,则始终不会自动退出)
        [switch]$Pause,
        #配置几秒后退出shell(单位:秒)
        [int]$Interval = 2
    )
    # 为了使开机自启的脚本能够正常执行(使用别名唤醒软件和服务,需要初始化pwsh)
    Update-PwshEnvIfNotYet
    #在初始化非MainPC时,从远程仓库拉去内容后需要重新运行初始化函数
    
    #路径变量
    # $scriptRoot = Resolve-Path $PSScriptRoot
    # $log_home = "$PS\startup\log"
    # $MapLog = "$scripts\startup\log\MapLog.txt"
    #开机启动日志文件
    # $log_file = "$log_home\log.txt"
    
    # 这里是为了能够检测出当系统更新重启后,更新的系统版本号
    Confirm-OSVersionFullCode -Force
    Confirm-OSVersionCaption -Force
    # Confirm-EnvVarOfInfo
    #如果当前机器不是MainPC,则拉取主PC的blogs,Scripts,configs仓库
    Update-ReposesConfigedIfNeed
    
    # 启动后台周期性执行的计划任务
    # Start-PeriodlyDaemon -WindowStyle Hidden

    Start-StartupBgProcesses

    
    Start-StartupApps -Interval $Interval
    # Start-StartupServices -Interval $Interval #单独使用计划任务来启动，可以在用户登陆前就启动服务

    # Set-Location $env:USERPROFILE
    Set-Location $desktop

}
function Start-StartupApps
{

    #启动基础常用软件(缓慢启动)👺(详情查看softwares.ps1中配置,而不要在这里直接写入启动配置)
    param (
        $Interval = 2
    )
    
    . "$PSScriptroot\softwares.ps1" -Interval $Interval
}
function Start-StartupBgProcesses
{
    # # 开机时刷新一下ip缓存(但是开机指出wifi可能会延迟一会儿才链接上,可以靠后执行它)
    #初始化或检查数据文件DataJson
    # 配置半点报时和整点报时后台进程(精简版系统可能没有可用TTS引擎,弹出一个窗口代替,或者弹出一条系统通知更好)
    Update-PwshEnvIfNotYet

    $exist = Get-Process pwsh* | Where-Object { $_.CommandLine -like '*Start-TimeAnnouncer*' }
    if ($exist)
    {
        $exist | Stop-Process
        Write-Verbose 'Stop-Process existed TimeAnnouncer process' -Verbose
    }
    Write-Verbose 'start new TimeAnnouncer process' -Verbose
    Start-ProcessHidden -scriptBlock { Start-TimeAnnouncer -ToastNotification } -PassThru
    # 后台进程维护一个ConnectionName,每隔一段时间检查一次(若发生变化则更新ConnectionName),可供其他进程快速读取ConnectionName
    Start-IpAddressUpdaterDaemon
 
}
function Start-IpAddressUpdaterDaemon
{
    param (
        [switch]$Force
    )
    Update-PwshEnvIfNotYet -Mode core
    Confirm-DataJson
   
    Start-Process -WindowStyle Hidden -FilePath pwsh -ArgumentList '-noe -c', " Update-NetConnectionInfo -Interval 6 -DataJson `"$DataJson`" " -PassThru
}
function Start-StartupServices
{
    param(
        $interval = 2 
    )
    . "$PSScriptroot\services.ps1" -Interval $Interval
}
function Update-ReposesConfigedIfNeed
{
   
    if (-not(Test-MainPC))
    {
        Write-Host 'This is not MainPC, pulling blogs and Scripts repository...' -ForegroundColor Yellow
        # 从云端拉取仓库更新配置
        Update-ReposesConfiged
        Start-Process wt
        # Start-Process pwsh -ArgumentList @(
        #     '-NoLogo',
        #     '-c', 
        #     'init'
        # )
        #启动新的powershell窗口待命,如果有pull动作使得新的配置生效
        # Start-Process pwsh -WorkingDirectory $desktop 
    }
}
function Confirm-DataJson
{
    <# 
    .SYNOPSIS
    如果不存在默认的DataJson文件，就创建一个
    否则什么事也不做
    #>
    param(
        # $PassThru
        $DataJson = $DataJson
    )
    if (!(Test-Path $DataJson))
    {
        $s = @{
            ConnectionName = '' ;
            IpPrompt       = ''
        }
        $s | ConvertTo-Json | Set-Content $DataJson
    }
    $jsonContent = Get-Content -Path $DataJson -Raw
    $validity = $jsonContent | ConvertFrom-Json
    if ($validity)
    {
        Write-Verbose 'The JSON file is valid.'
        # return $true
        # return $validity
    }
    else
    {
        Write-Warning 'The JSON file is not valid.'
        Rename-Item $DataJson -NewName "$($DataJson).bak.$((Get-Date).ToString('yyyy-MM-dd--HH-mm-ss'))" -Force -Verbose

        # 重新创建datajson文件
        Write-Host 'Create new DataJson file.'
        Confirm-DataJson
        # return $false
    }
}
