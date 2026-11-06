
# $github_mirror="https://gh-proxy.com"
[CmdletBinding()]
param(
    # 仓库源(默认 github+加速;gitee 仅保留兼容)
    [validateSet('gitee', 'github')]
    $RepoSource = 'github',
    # 下载加速镜像:显式指定时不再测速/弹窗;$env:PsGithubMirror 优先,否则默认 gh-proxy
    [Alias('Mirror')]
    $GithubMirror = $(if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }),
    # 开发模式:用本地最新模块(Deploy.psm1/TestLinks.psm1/Git.psm1),不拉远程;仓库根自动从脚本位置推导
    [switch]$Dev,
    $DevRoot = '',
    # 已存在 pwsh 时默认跳过;需要重装/覆盖时显式加 -Force
    [switch]$Force
)
# 预先放行脚本执行:本脚本会落盘并执行下载的模块,执行策略过严会直接中断
try
{
    if ((Get-ExecutionPolicy -Scope Process) -notin @('Bypass', 'Unrestricted'))
    {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
    }
}
catch
{
    Write-Warning "Set-ExecutionPolicy(Process) failed: $($_.Exception.Message)"
}
try
{
    $userPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($userPolicy -in @('Restricted', 'AllSigned'))
    {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        Write-Host 'ExecutionPolicy(CurrentUser) was set to RemoteSigned.' -ForegroundColor Yellow
    }
}
catch
{
    Write-Verbose "Set-ExecutionPolicy(CurrentUser) failed: $($_.Exception.Message)"
}
# 已经能调用 pwsh 时默认不重复安装(避免覆盖用户现有安装);需要重装加 -Force
if ((Get-Command pwsh -ErrorAction SilentlyContinue) -and -not $Force)
{
    Write-Host 'pwsh is already available, skip installation (use -Force to reinstall).' -ForegroundColor Yellow
    return
}
if ($Dev)
{
    if ([string]::IsNullOrWhiteSpace($DevRoot))
    {
        $DevRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    }
    $devDpl = Join-Path $DevRoot 'PS/Deploy/Deploy.psm1'
    $devTl = Join-Path $DevRoot 'PS/TestLinks/TestLinks.psm1'
    $devGit = Join-Path $DevRoot 'PS/Git/Git.psm1'
    if ((Test-Path -LiteralPath $devDpl) -and (Test-Path -LiteralPath $devTl) -and (Test-Path -LiteralPath $devGit))
    {
        Write-Host '[Deploy-Pwsh7Portable]:Dev mode, use local modules.' -ForegroundColor Yellow
        . $devDpl
        . $devTl
        . $devGit
    }
    else
    {
        Write-Warning "Dev mode requested but local modules not found under [$DevRoot], fall back to remote."
        $Dev = $false
    }
}
if (-not $Dev)
{
    if ($RepoSource -eq 'github')
    {
        # 中央镜像:显式参数优先,其次 $env:PsGithubMirror,否则默认 gh-proxy;直连作回退
        $repoMirror = ([string]$GithubMirror).TrimEnd('/')
        $rawDirect = 'https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main'
        $rawBase = if ($repoMirror) { "$repoMirror/$rawDirect" } else { $rawDirect }
    }
    else
    {
        $rawBase = 'https://raw.giteeusercontent.com/xuchaoxin1375/scripts/raw/main'
        $rawDirect = $rawBase
    }

    Write-Host "[Deploy-Pwsh7Portable]: Pull Deploy.psm1 and TestLinks.psm1 modules [$rawBase]..."

    # 远端模块带 UTF-8 BOM,irm 保留为 U+FEFF,不裁掉会让首行 <# 注释失效(解析报错)
    foreach ($modulePath in @('PS/Deploy/Deploy.psm1', 'PS/TestLinks/TestLinks.psm1', 'PS/Git/Git.psm1'))
    {
        try
        {
            (Invoke-RestMethod "$rawBase/$modulePath" -TimeoutSec 60).TrimStart([char]0xFEFF) | Invoke-Expression
        }
        catch
        {
            Write-Warning "Download $modulePath via mirror failed ($($_.Exception.Message)), retry direct..."
            (Invoke-RestMethod "$rawDirect/$modulePath" -TimeoutSec 60).TrimStart([char]0xFEFF) | Invoke-Expression
        }
    }
}
# 镜像命令自检(只列存在的,避免 TestLinks 未加载时报 CommandNotFound 刷红)
if (Get-Command Get-AvailableGithubMirrors -ErrorAction SilentlyContinue)
{
    Write-Verbose 'Mirror commands loaded: Get-AvailableGithubMirrors / Get-SelectedMirror / Test-MirrorAvailability'
}

# 显式镜像(参数或 $env:PsGithubMirror)直接使用,不测速、不弹窗;都没有才进入交互选择
$github_mirror = ([string]$GithubMirror).TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($github_mirror))
{
    $github_mirror = @(Get-SelectedMirror)[0]
}

# Write-Verbose $github_mirror -Verbose

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
        $mirror = $github_mirror,
        # "$env:ProgramFiles\PowerShell\7" #可能要管理员权限
        $InstallPath = "$env:systemDrive\powershell\7"

    )
    # 给用户一个取消部署的选择机会
    if ($PSCmdlet.ShouldProcess("$env:UserName@$env:COMPUTERNAME", 'Deploy-Pwsh7Portable'))
    {
        Write-Verbose 'Start deploy powershell7 portable...'
    }
    else
    {
        return
    }
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
        # api.github.com 国内直连可能失败,失败则抛给调用方回退处理
        try
        {
            $releaseInfo = Invoke-RestMethod -Uri $releasesUrl -Headers @{ 'User-Agent' = 'PowerShell-Script' } -TimeoutSec 15 -ErrorAction Stop
        }
        catch
        {
            throw "Query latest PowerShell release failed ($($_.Exception.Message)). Pass -BaseUrl explicitly, e.g. a mirror-prefixed zip URL."
        }

        Write-Host "Trying to get latest PowerShell ${PackageType}..."
        foreach ($asset in $releaseInfo.assets)
        {
            if ($asset.name -like "*win-x64.${PackageType}")
            {
                $url = $asset.browser_download_url
                Write-Verbose $url -Verbose
                return $url
            }
        }
        throw 'No suitable installer found in the latest release.'
    }
    # 定义下载 URL 模板
    if ( ! $baseUrl )
    {
        $baseUrl = Get-LatestPowerShellDownloadUrl -PackageType zip
    }
    $directUrl = $baseUrl
    if ( $mirror )
    {
        Write-Host "try use mirror: $mirror to speed up link"
        # $mirror 为空字符串表示不走镜像,不要拼出 "/https://..." 坏链接
        $BaseUrl = "$(([string]$mirror).TrimEnd('/'))/$BaseUrl"
        Write-Host "Downloading from $BaseUrl"
    }
    else
    {
        Write-Host 'Use no mirror'
    }
    $versionCode = $BaseUrl -replace '.*(\d+\.\d+\.\d+).*', '$1'
    # 下载文件
    $outputPath = "$env:TEMP\powershell-$versionCode.zip"
    $downloadNeed = $True
    if (!(Test-Path -Path $outputPath))
    {
        Write-Host "$outputPath does not exist, start downloading..."
    }
    else
    {
        Write-Output "$outputPath is already exist"
        $answer = Read-Host "Download again ?(Y/N)"
        if ($answer -like 'Y*')
        {
            Write-Host "Redownload..."
            $downloadNeed = $True
            Remove-Item -Path $outputPath -Verbose
        }
        else
        {
            Write-Host "Use cached file: $outputPath"
            $downloadNeed = $False
        }
    }
    
    if($downloadNeed)
    {
        $dlUrls = @($BaseUrl, $directUrl) | Select-Object -Unique
        $downloaded = $false
        foreach ($dlUrl in $dlUrls)
        {
            Write-Host "Downloading from $dlUrl"
            # 调用 Invoke-WebRequest 下载文件(5.1 用 -UseBasicParsing,避免 IE 解析器;大文件给足超时)
            try
            {
                Invoke-WebRequest -Uri $dlUrl -UseBasicParsing -OutFile $outputPath -TimeoutSec 900 -ErrorAction Stop
                if ((Test-Path -LiteralPath $outputPath) -and (Get-Item -LiteralPath $outputPath).Length -gt 0)
                {
                    # 只认 zip 签名(PK),避免把镜像返回的 HTML 错误页当成安装包
                    $head = New-Object byte[] 2
                    $fs = [IO.File]::OpenRead($outputPath)
                    try { $n = $fs.Read($head, 0, 2) } finally { $fs.Close() }
                    if ($n -eq 2 -and $head[0] -eq 0x50 -and $head[1] -eq 0x4B)
                    {
                        $downloaded = $true
                        break
                    }
                    throw 'Downloaded file is not a zip package.'
                }
                throw 'Downloaded file is empty.'
            }
            catch
            {
                Write-Warning "Download failed ($($_.Exception.Message)): $dlUrl"
                Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $downloaded)
        {
            throw 'PowerShell 7 package download failed from mirror and direct link. Pass -BaseUrl with a reachable zip URL.'
        }
    }
    
    # 确保安装路径存在
    # $InstallPath="$InstallPath\$versionCode"
    if ((Test-Path -Path $installPath))
    {
        # 备份原来的路径(Rename-Item 的 -NewName 只能是叶子名)
        $backupName = "$([IO.Path]::GetFileName($InstallPath)).bak.$((Get-Date).ToString('yyyy-MM-dd--HH-mm-ss'))"
        Rename-Item -Path $InstallPath -NewName $backupName -Verbose
        # 新建一个路径用于全新安装
        New-Item -ItemType Directory -Path $installPath -Verbose
    }
    # 解压文件
    Expand-Archive -Path $outputPath -DestinationPath $installPath -Force 

    # 清理下载的压缩包(明确不确认,避免部署中途停下来等回车)
    Remove-Item -Path $outputPath -Verbose -Confirm:$false
    
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
#调用函数
Deploy-Pwsh7Portable -mirror $github_mirror -Verbose