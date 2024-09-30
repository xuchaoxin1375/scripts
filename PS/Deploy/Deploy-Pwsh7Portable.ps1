
function Deploy-Pwsh7Portable
{
    <# 
    .SYNOPSIS
    一键安装powershell7 portable(便携版)
    .DESCRIPTION
    要求powershell5.1或以上版本执行此脚本,否则无法保证可以解压并部署安装文件
    这里提供一键安装的方法,试图使用最快捷的操作完成安装或部署
    其他备选值得推荐的方法有国内应用软件镜像站下载安装包,或者应用商店比如联想应用商店下载安装版
    官方推荐的方法国内比较慢或者稳定性不足
    .NOTES
    虽然Microsoft官方推荐使用winget 或者应用商店下载,但是前者从github直接下载不稳定,
    后者从应用商店下载有时候网络问题点击下载会反应比较久,而且安装路径不方便确定
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # 'https://github.com/PowerShell/PowerShell/releases/latest/download/powershell-7.x.x-win-x64.zip'
        $BaseUrl = '',
        $mirror = 'https://gh-proxy.com',
        # "$env:ProgramFiles\PowerShell\7" #可能要管理员权限
        $InstallPath = "$env:systemDrive\powershell\7"

    )

    function Get-LatestPowerShellDownloadUrl
    {
        <# 
        .SYNOPSIS
        从github获取powershell最新稳定版下载链接,支持指定下载类型(zip/msi)
        #>
        param(
            [ValidateSet('msi', 'zip')]$PackageType = 'msi'
        )
        $releasesUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
        $releaseInfo = Invoke-RestMethod -Uri $releasesUrl -Headers @{ 'User-Agent' = 'PowerShell-Script' }

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
    # 定义下载 URL 模板
    if ( ! $baseUrl )
    {
        $baseUrl = Get-LatestPowerShellDownloadUrl -PackageType zip
    }
    if ( $mirror )
    {
        Write-Host "try use mirror: $mirror to speed up link"
        $BaseUrl = "$mirror/$BaseUrl".trim('/')
    }
    else
    {
        Write-Host 'Use no mirror'
    }
    $versionCode = $s -replace '.*(\d+\.\d+\.\d+).*', '$1'
    # 下载文件
    $outputPath = "$env:TEMP\powershell-$versionCode.zip"
    if (!(Test-Path -Path $outputPath))
    {

        # 调用 Invoke-WebRequest 下载文件
        Invoke-WebRequest -Uri $baseUrl -OutFile $outputPath
    }
    else
    {
        Write-Output "$outputPath is already exist"
    }

    
    # 确保安装路径存在
    # $InstallPath="$InstallPath\$versionCode"
    if ((Test-Path -Path $installPath))
    {
        # 备份原来的路径
        Rename-Item -Path $InstallPath -NewName "$($InstallPath).bak.$((Get-Date).ToString('yyyy-MM-dd--HH-mm-ss'))" -Verbose
        # 新建一个路径用于全新安装
        New-Item -ItemType Directory -Path $installPath -Verbose
    }
    # 解压文件
    Expand-Archive -Path $outputPath -DestinationPath $installPath -Force 

    # 清理下载的压缩包
    Remove-Item -Path $outputPath -Verbose -Confirm
    
    if ($PSCmdlet.ShouldProcess("$installPath", 'Add to PATH'))
    {
        
        # 将 pwsh.exe 添加到 PATH 环境变量
        # 方案1
        # $UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        # $NewUserPath = "$installPath;$UserPath"
        # 方案2
        $RawPathValue = reg query 'HKEY_CURRENT_USER\Environment' /v Path
        $RawPathValue = @($RawPathValue) -join '' #确保$RawPathValue是一个字符串
        # $RawPathValue -match 'Path\s+REG_EXPAND_SZ\s+(.+)'
        $RawPathValue -match 'Path\s+REG.*SZ\s+(.+)'
        $UserPath = $Matches[1] 

        Write-Verbose "Path value of [$env:Username] `n$($UserPath -split ';' -join "`n")" -Verbose
        # 这里仅操作User级别,不需要管理权限
        $NewUserPath = "$InstallPath;$UserPath"

        # 执行添加操作
        [Environment]::SetEnvironmentVariable(
            'Path', $NewUserPath , [System.EnvironmentVariableTarget]::User
        )
        # 更新当前环境变量
        $env:Path = "$InstallPath;$env:path"
        
    }
    $pwshPath = "$installPath\pwsh.exe"
    # 验证安装
    if (Test-Path -Path $pwshPath)
    {
        Write-Output 'PowerShell 7 installed successfully'
    }
    if (Get-Command pwsh -ErrorAction SilentlyContinue)
    {
        Write-Output 'PowerShell 7 was added to the PATH environment variable.'
        Start-Process pwsh
    }
    else
    {
        Write-Output '安装失败，请检查脚本和网络连接。'
    }
    
}