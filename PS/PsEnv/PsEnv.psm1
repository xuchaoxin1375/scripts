<#
PsEnv 模块:PowerShell 版本/环境/profile 管理(升级/扩展关联/profile 路径)。
从 Pwsh.psm1 迁入: Pwsh 只留模块加载脚手架,版本环境类归此模块;
调用方命令名不变(自动发现同名模块),init 等跨模块调用走自动加载。
#>

function Set-PsExtension
{
    <# 
.SYNOPSIS
是否启用额外的相关扩展
.DESCRIPTION
检查环境变量extent,如果取值为True,那么指导用户安装或启用相应的模块
否则跳过不处理这部分扩展内容
#>
    [CmdletBinding(DefaultParameterSetName = 'PsExtension')]
    param (
        [parameter(ParameterSetName = 'PsExtension')]
        # 要安装的模块列表
        #按照实用性排序
        $modules = @(

            # 补全模块
            'CompletionPredictor'
            # 'PsCompletions' #这里导入此模块会报错(可能有冲突,请在其他位置导入此模块)
            
            # 目录跳转
            # 'ZLocation' 使用更加强大和通用的zoxide替代(跨平台高性能方案,无需通过powershell导入)
            # 'z'
            
            # 美化模块
            # 'Terminal-Icons' #速度较慢,不默认启用
        ),
        # 安装模块的范围
        [ValidateSet('CurrentUser', 'AllUsers')]$Scope = 'CurrentUser',
        
        # 是否启用额外的相关扩展
        # 出于加载速度和轻便性考虑，不默认启用这部分扩展功能
        [parameter(ParameterSetName = 'Switch')]
        [ValidateSet('On', 'Off')]
        [parameter(Position = 0)]
        $Switch = 'Off'
    )
    if ($PSCmdlet.ParameterSetName -eq 'Switch')
    {

        if ($Switch -eq 'Off')
        {
            
            Write-Verbose 'Skip pwsh extension functions!' -Verbose
            Set-EnvVar -Name 'PsExtension' -NewValue 'False'
        }
        elseif ($Switch -eq 'On')
        {
            
            Set-EnvVar -Name 'PsExtension' -NewValue 'True'
        }
    }
    elseif ($env:PsExtension -eq 'True')
    {

        # scoop 相关
        # Invoke-Expression (&scoop-search --hook)
        # 检查模块是否已经安装,必要时安装对应的模块
        $i = 0
        $count = $modules.Count
        $report = @()
        # $AvailableModules = Get-Module -ListAvailable #性能不佳，不做-Name的话会耗费几百毫秒
        foreach ($module in $modules)
        {
            # 检查指定模块是否可用,如果不可用则尝试安装该模块(使用comfirm动作包装)
            Confirm-ModuleInstalled -Name $module -Scope $Scope -Install

            # Write-Verbose "Importing module $module" -Verbose
            # $moduleAvailability | Import-Module 
            # 执行导入操作
            # Import-Module $module 
            $res = Measure-Command { 
                Import-Module $module -Verbose:$false
            }
            
            #显示进度条(顶层 Id,不再挂 ParentId 0:init 已无父进度条,悬空父引用会导致残留)
            $completed = [math]::Round($i++ / $count * 100, 1)
            # Start-Sleep -Milliseconds 500
            Write-Progress -Activity 'Importing Modules... ' -Id 1 -Status " $module progress: $completed %" -PercentComplete $completed

            #准备报告导入情况信息 
            $time = [int]$res.TotalMilliseconds
            $res = [PSCustomObject]@{
                Module = $module
                time   = $time
            }
            $report += $res
        }

        $totalTime = $report | Measure-Object -Property time -Sum | Select-Object -ExpandProperty Sum
        # 准备视图
        $report = $report | Sort-Object -Descending time # | Format-Table #| Out-String 
        
        
        Write-Progress -Activity 'Importing Modules... ' -Id 1 -Completed
        if ($InformationPreference)
        {
            # Write-Host $report
            Write-Output $report

            Write-Verbose "Time Of importing modules: $($totalTime)" -Verbose
        }
        # return $report
        #其他模块导入后的提示信息
        # Write-Host -Foreground Green "`n[ZLocation] knows about $((Get-ZLocation).Keys.Count) locations.`n"
    }
    
}

function Get-PsProfilesPath
{
    <# 
    .SYNOPSIS
    获取所有的$profile级别文件路径,即便文件不存在
    #>
    [CmdletBinding()]
    param(
        # 是否只返回存在文件
        [switch]$ExistOnly
    )
    $profiles = @(
        $profile.CurrentUserCurrentHost,
        $profile.CurrentUserAllHosts,
        $profile.AllUsersCurrentHost,
        $profile.AllUsersAllHosts
    )
    if ($ExistOnly)
    {
        $profiles = $profiles | Where-Object { Test-Path $_ }
    }
    return $profiles
}
 
function Remove-PsProfiles
{
    $profiles = Get-PsProfilesPath
    foreach ($pf in $profiles)
    {
        Remove-Item -Force -Verbose $pf -ErrorAction SilentlyContinue
    }
}


function Confirm-PsVersion
{
    <# 
    .SYNOPSIS
    如果当前版本高于指定版本，则返回当前版本对象，否则返回$False
    直接抛出版本过低的提示错误有点过头了
    #>
    param (
        $Major = 7,
        $Minor = 0,
        $Build = 0

    )
    $version = $host.Version
    if ($Version.Major -ge $Major -and $Version.Minor -ge $Minor -and $Version.Build -ge $Build)
    {
        # $res = $True
        # Write-Host 
        return $Version
    }
    else
    {
        # $res = $false
        Write-Host "Powershell version is lower than $Major.$Minor.$Build" -ForegroundColor Red
        return $False
    }
    # return $res
    
}

function Install-ScoopByLocalProxy
{
    param (
        [ValidateSet('Default', 'Proxy')]$Method = 'Default'
    )
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser # Optional: Needed to run a remote script the first time
    switch ($Method)
    {
        'Default'
        { 
            Write-Host 'Installing scoop in default channel...'
        }
        'Proxy'
        {
            Set-Proxy -Status on
            Write-Host 'Installing scoop in proxy channel...'
            Get-ProxyEnvVarSettings
        }
        default {}
    }
    Invoke-Expression (New-Object net.webclient).downloadstring('https://get.scoop.sh')
    
}

function Update-PowerShellLegacy
{
   
    Write-Output '@maybe you need to try severial times!...'
    Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI"
}

function Get-LatestPowerShellDownloadUrl
{
    param(
        [ValidateSet('msi', 'zip')]$PackageType = 'msi'
    )
    $releasesUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    # api.github.com 国内直连可能失败,失败抛给调用方回退处理(独立脚本 Deploy-Pwsh7Portable 内有同逻辑副本,改逻辑两边同步)
    $releaseInfo = Invoke-RestMethod -Uri $releasesUrl -Headers @{ 'User-Agent' = 'PowerShell-Script' } -TimeoutSec 15 -ErrorAction Stop

    Write-Host "Trying to get latest PowerShell ${PackageType}..."
    foreach ($asset in $releaseInfo.assets)
    {
        if ($asset.name -like "*win-x64.${PackageType}")
        {
            return $asset.browser_download_url
        }
    }
    throw 'No suitable installer found in the latest release.'
}

# 更新 PowerShell 并显示当前版本
# Update-Powershell
function Update-PowerShell
{
    try
    {
        $downloadUrl = Get-LatestPowerShellDownloadUrl
        # 替换为加速链接(配合IDM发挥效果)
        $downloadUrl = Get-SpeedUpUri $downloadUrl
        
        Write-Host $downloadUrl -ForegroundColor Cyan
        $installerPath = "$env:userprofile\Downloads\pwsh7Last.msi"

        Write-Host "Downloading PowerShell installer from $downloadUrl..."
        # Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        # 使用aria2下载
        aria2c.exe $downloadUrl -d $env:userprofile\Downloads -o 'pwsh7Last.msi'

        Write-Host 'Installing PowerShell...'
        Start-Process $installerPath
    }
    catch
    {
        Write-Host "An error occurred: $_"
        return
    }

    # 获取当前 PowerShell 版本
    $currentVersion = $PSVersionTable.PSVersion
    Write-Host "Current PowerShell version: $currentVersion"
}

