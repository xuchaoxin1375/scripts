<# 
.SYNOPSIS
临时部署此脚本文件
$mirror = 'https://gh-proxy.com'   # 镜像单独设置；也可用 $env:PsGithubMirror
Invoke-Expression ((Invoke-RestMethod "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-GitForWindows.ps1").TrimStart([char]0xFEFF))
.DESCRIPTION
此脚本文件用于部署Git for Windows到windows系统,可以自动下载最新版本的Git for Windows安装包,也可以指定下载链接,也可以指定本地安装包路径进行部署
#>
[CmdletBinding()]
param(
    # 仓库源(默认 github+加速;gitee 仅保留兼容)
    [validateSet('gitee', 'github')]
    $RepoSource = 'github',
    # 下载加速镜像:显式指定时不再测速/弹窗;$env:PsGithubMirror 优先,否则默认 gh-proxy
    [Alias('Mirror')]
    $GithubMirror = $(if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }),
    # 开发模式:用本地最新模块(Deploy.psm1/Git.psm1),不拉远程;仓库根自动从脚本位置推导
    [switch]$Dev,
    $DevRoot = ''
    # [switch]$Force
)
# 预先放行脚本执行:本脚本会落盘并执行下载的模块/脚本,执行策略过严会直接中断
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
Write-Host "[Deploy-GitForWindows]:RepoSource=$RepoSource,Dev=$Dev,Mirror=$GithubMirror"
# 检查git是否已经可用,如果已经可用,则跳过后续安装步骤.
if (Get-Command git -ErrorAction SilentlyContinue)
{
    Write-Host 'Git command already exists,skip installation.' -ForegroundColor yellow
    return $true
}
# $github_mirror="https://gh-proxy.com"
## 导入其他模块(Deploy.psm1/Git.psm1 只提供函数定义,点源本地版与 irm 远端版等价)
if ($Dev)
{
    if ([string]::IsNullOrWhiteSpace($DevRoot))
    {
        $DevRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    }
    $devDeploy = Join-Path $DevRoot 'PS/Deploy/Deploy.psm1'
    $devGit = Join-Path $DevRoot 'PS/Git/Git.psm1'
    $devTl = Join-Path $DevRoot 'PS/TestLinks/TestLinks.psm1'
    if ((Test-Path -LiteralPath $devDeploy) -and (Test-Path -LiteralPath $devGit) -and (Test-Path -LiteralPath $devTl))
    {
        Write-Host '[Deploy-GitForWindows]:Dev mode, use local modules.' -ForegroundColor Yellow
        . $devDeploy
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
    # 中央镜像:显式参数优先,其次 $env:PsGithubMirror,否则默认 gh-proxy;直连作回退
    $repoMirror = ([string]$GithubMirror).TrimEnd('/')
    $rawDirect = 'https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main'
    $rawBase = if ($RepoSource -eq 'github') {
        if ($repoMirror) { "$repoMirror/$rawDirect" }
        else { $rawDirect }
    }
    else { 'https://gitee.com/xuchaoxin1375/scripts/raw/main' }
    if ($RepoSource -ne 'github') { $rawDirect = $rawBase }
    # 方案1:iex执行
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

# 方案2:下载 Deploy.psm1 到临时目录
# $deployModulePath = Join-Path $env:TEMP 'Deploy.psm1'
# Invoke-WebRequest https://$RepoSource.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy.psm1 -OutFile $deployModulePath -UseBasicParsing

# # 导入模块
# Import-Module $deployModulePath -Force

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
Write-Verbose "Selected mirror: $github_mirror"
function Deploy-GitForwindows
{
    <# 
    .SYNOPSIS
    帮助windows系统用户一键部署Git for Windows
    .DESCRIPTION
    部署方案有多种,可以自动操作,如果失败,可以尝试分步骤操作
    此函数提供了灵活的参数组合供用户选择,理想情况下使用无参数版本就可以了
    但是无参数其实依赖于预设的默认参数,资源链接可能会过时,这种情况下需要用户自行寻找资源链接,然后使用相应的参数选项传递给此函数

    #>
    
    [CmdletBinding(DefaultParameterSetName = 'Online')]
    param(
        # 使用镜像加速下载git release文件
        [parameter(ParameterSetName = 'Online')]
        #如果不是用mirror,可以指定其为空字符串''
        #加速镜像可能会失效,如果不可用自行替换此参数,可以在命令行中指定
        $mirror = $github_mirror,
        # 注意区分这url是一个自解压文件还是压缩包文件
        # url可以是从git for windows 的二进制文件镜像站提供的文件下载链接(网页中右键复制指定文件的链接即可,注意是Portable版本的(一般后缀为.7z.exe),而不是普通的安装版)
        # 下面默认值只是回退(api 查不到才用,最新版跟踪见 Deploy-Guide §14);要用指定版本传 -url,或离线包传 -PackagePath
        [parameter(ParameterSetName = 'Online')]
        $url = 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.5/PortableGit-2.55.0.5-64-bit.7z.exe',

        [parameter(ParameterSetName = 'PackagePath')]
        # 出来上述指定提供链接的方法来下载,还可以自己手动下载,然后将保存的路径作为$PackagePath的取值来调用函数部署Git
        $PackagePath ,
        [switch]$InstallByGiteeScoop,
        
        $Path = 'C:\PortableGit',
        # 如果检测到git命令已经可用,是否仍然通过此方法再次安装(默认取消)
        [switch]$Force,
        [switch]$IgnoreCache
    )
    Write-Host 'Checking git command availability......'

    if((Get-Command git -ErrorAction SilentlyContinue) -and !$Force)
    {
        Write-Host 'Git command already exists,skip installation.' -ForegroundColor yellow
        return $true
    }
    Write-Verbose 'Try to get the lastest version of git portable version...'
    # api.github.com 国内直连可能失败,失败则回退到默认 $url,不中断部署
    try
    {
        $latestRelease = Invoke-WebRequest -UseBasicParsing -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Method Get -TimeoutSec 15 -ErrorAction Stop | ConvertFrom-Json
    }
    catch
    {
        Write-Warning "Query latest git release failed ($($_.Exception.Message)). Use default version link."
        $latestRelease = $null
    }
    if ($latestRelease)
    {
        
        $LastUrls = $latestRelease.assets | Where-Object { $_.name -like '*PortableGit*' } | Select-Object -ExpandProperty browser_download_url
        $url = @($LastUrls) | Where-Object { $_ -like '*64*' } | Select-Object -First 1
        Write-Verbose "Latest release url: $url"
    }
    else
    {
        
        Write-Warning 'Get the lastest version failed.Use default version link'
    }

    if ($InstallByGiteeScoop)
    {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

        Invoke-WebRequest -useb scoop.201704.xyz | Invoke-Expression

        scoop install git  #为当前用户安装,如果全局需要管理员权限
    }

    # 用New-Item的-force参数,即便路径已经存在,也不会报错(如果已经存在此目录,内部的也不会被覆盖(移除))
    New-Item -ItemType Directory $Path -Verbose -Force # -ErrorAction SilentlyContinue
    if ( $PSCmdlet.ParameterSetName -eq 'PackagePath' )
    {
        $Package = $PackagePath
    }
    else
    {

        $Package = "$Path\PortableGit.7z.exe"
        if ($IgnoreCache -or !(Test-Path $Package))
        {
            # 镜像优先,失败再直连;空镜像不拼 "/https://..." 坏链接
            $dlUrls = @()
            if (-not [string]::IsNullOrWhiteSpace($mirror))
            {
                $dlUrls += "$(([string]$mirror).TrimEnd('/'))/$url"
            }
            $dlUrls += $url
            $dlUrls = @($dlUrls | Select-Object -Unique)
            $downloaded = $false
            foreach ($dlUrl in $dlUrls)
            {
                Write-Host "Downloading [$dlUrl] to $Package" -ForegroundColor cyan
                try
                {
                    Invoke-WebRequest -UseBasicParsing -Uri $dlUrl -OutFile $Package -TimeoutSec 600 -ErrorAction Stop
                    if ((Test-Path -LiteralPath $Package) -and (Get-Item -LiteralPath $Package).Length -gt 0)
                    {
                        # 只认 PE 签名(MZ),避免把镜像返回的 HTML 错误页当成安装包
                        $head = New-Object byte[] 2
                        $fs = [IO.File]::OpenRead($Package)
                        try { $n = $fs.Read($head, 0, 2) } finally { $fs.Close() }
                        if ($n -eq 2 -and $head[0] -eq 0x4D -and $head[1] -eq 0x5A)
                        {
                            $downloaded = $true
                            break
                        }
                        throw 'Downloaded file is not an executable.'
                    }
                    throw 'Downloaded file is empty.'
                }
                catch
                {
                    Write-Warning "Download failed ($($_.Exception.Message)): $dlUrl"
                    Remove-Item -LiteralPath $Package -Force -ErrorAction SilentlyContinue
                }
            }
            if (-not $downloaded)
            {
                throw 'Git package download failed from mirror and direct link. Pass -url or -PackagePath manually.'
            }
        }
        
    }
    # Write-Host "$Package  exist!" 
    # $Package = "$home/downloads/PortableGit.7z.exe"
    # 静默安装(默认解压到$Pacakge所在目录的PortableGit子目录)
    # & $Package -y #这种做法会抛到后台进程去执行安装,前台继续执行,可能会引发顺序命令顺序问题
    Write-Host 'Installing PortableGit...(it may take a while)' -ForegroundColor cyan

    Start-Process "$Package" -ArgumentList '-y' -Wait #使用Start-Process命令执行安装,配合-wait参数等待安装完成再执行后续内容
    #将目录转移到专门的目录下(连隐藏文件一起搬)
    $extracted = Join-Path $Path 'PortableGit'
    if (-not (Test-Path -LiteralPath $extracted))
    {
        throw "PortableGit extraction failed: [$extracted] not found."
    }
    Get-ChildItem -LiteralPath $extracted -Force | Move-Item -Destination $Path -Force
    Remove-Item -LiteralPath $extracted -Recurse -Force -ErrorAction SilentlyContinue
    # Expand-Archive -Path $Package -DestinationPath $Path 

    # 临时地(在当前powershell会话内,让git命令可以在任意目录下调用),如果需要后续任意目录下调用，需要添加git.exe所在目录到环境变量Path
    $GitBin = "$Path\bin"
    $env:Path = "$GitBin;$env:path" #临时添加到当前会话的Path变量中(如果需要添加到User或Machine级环境变量,建议把$env:Path替换为更准确的对应级别的变量值,防止污染)
    Write-Verbose 'Check the first value of the environment variable Path:' -Verbose
    $env:path -split ';' | Select-Object -First 1
    
    # 向系统注册git所在路径
    $UserPath = [System.Environment]::GetEnvironmentVariable('path', 'user') <# -split ';' #>
    
    #不会自动转换或丢失%var%形式的Path变量提取
    #采用reg query命令查询而不使用Get-ItemProperty 查询注册表,因为Get-ItemProperty 会自动转换或丢失%var%形式的Path变量
    $RawPathValue = reg query 'HKEY_CURRENT_USER\Environment' /v Path
    $RawPathValue = @($RawPathValue) -join '' #确保$RawPathValue是一个字符串
    # $RawPathValue -match 'Path\s+REG_EXPAND_SZ\s+(.+)'
    $RawPathValue -match 'Path\s+REG.*SZ\s+(.+)'
    $UserPath = $Matches[1] 
    Write-Verbose "Path value of [$env:Username] `n$($UserPath -split ';' -join "`n")" -Verbose
    # 将Git所在目录插入到系统环境变量Path中(这里仅操作User级别,不需要管理权限)
    $NewUserPath = "$GitBin;$UserPath"
    [System.Environment]::SetEnvironmentVariable('Path', $NewUserPath, 'user')
    
    #检查命令可用性
    Get-Command git | Format-List *
    # 可以选择列出潜在的所有git版本
    Get-Command git.exe* | Select-Object Name, Source, CommandType, Version
}

#检查当前命令是否可用
Get-Command Deploy-GitForwindows -Syntax

Deploy-GitForwindows -mirror $github_mirror