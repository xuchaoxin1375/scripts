<# 
.SYNOPSIS
部署CxxuPsModules

.DESCRIPTION

这里会尝试通过在线仓库导入 Deploy-GitForWindows 模块,会引入一些外部命令;
如果本地调整此脚本时,注意在线仓库中的版本可能不是最新的.
也可以考虑用本地导入的方式暂时代替默认的导入在线版本.
.NOTES
本地开发测试(未推送到远程时,用本地最新代码测试部署效果):
在仓库目录中直接运行此脚本并加 -Dev 即可,不拉取远程代码
PS> C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Dev -Light -WhatIf

#>
[CmdletBinding()]
param(
    # 仓库源(默认 github+加速;gitee 对远程脚本执行误报拦截,已弃用,仅保留兼容)
    [validateSet('gitee', 'github')]
    $RepoSource = 'github',
    $GithubMirror = $(if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }),
    # 适用于开发(维护调整)的测试模式(用本地最新代码,不拉远程;仓库根自动从脚本位置推导)
    [switch]$Dev,
    $DevRoot = '',
    [switch]$Force,
    # 轻量部署(仅 Windows PowerShell 5.1):免 git(走离线包下载),免 pwsh(不装 portable),
    # 落 PSModulePath + 写 5.1 专属 profile,新开 powershell.exe 即用(B 档交互可用,见 Feature-Guide §13)
    [switch]$Light
)
Write-Host "[Deploy-CxxuPsModules]:开始运行CxxuPsModules部署脚本(来源:${RepoSource})..."
# 导入 Deploy-GitForWindows 命令(适合独立部署用户使用),分开放置确保灵活性
# Light 模式免 git,跳过导入(其尾部会直接执行安装,不跳过就装上了)
if ($Light)
{
    Write-Host '[Deploy-CxxuPsModules]:Light mode, skip Deploy-GitForWindows.'
}
elseif ($Dev)
{
    # 开发模式:用本地最新代码,不拉远程(仓库根从脚本位置自动推导:PS/Deploy 上两级)
    if ([string]::IsNullOrWhiteSpace($DevRoot))
    {
        $DevRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    }
    $devDgw = Join-Path $DevRoot 'PS/Deploy/Deploy-GitForWindows.ps1'
    if (Test-Path -LiteralPath $devDgw)
    {
        Write-Host "[Deploy-CxxuPsModules]:Dev mode, use local [$devDgw]..." -ForegroundColor Yellow
        . $devDgw -RepoSource $RepoSource -Dev -DevRoot $DevRoot
    }
    else
    {
        Write-Warning "Dev mode requested but local file not found [$devDgw], fall back to remote."
        $Dev = $false
    }
}
if (!$Light -and !$Dev)
{
    # 正式版(github 走加速前缀,gitee 直连;raw 一律用 raw.githubusercontent 形式)
    if ($RepoSource -eq 'github')
    {
        $dgwRaw = 'https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-GitForWindows.ps1'
        $dgwUrl = if ($GithubMirror) { "$GithubMirror/$dgwRaw" } else { $dgwRaw }
        Write-Verbose "GithubMirror:[$GithubMirror]"
    }
    else
    {
        $dgwUrl = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-GitForWindows.ps1'
    }

    Write-Host "拉取Deploy-GitForWindows 命令:[$dgwUrl]..."
    Invoke-RestMethod $dgwUrl > ~/dgw.ps1
    ~/dgw.ps1 -RepoSource $RepoSource -Verbose
}

function Deploy-CxxuPsModules
{
    <# 
    .SYNOPSIS
    一键部署CxxuPsModules，将此模块集推荐的自动加载工作添加到powershell的配置文件$profile中
    请使用powershell7部署
    .DESCRIPTION
    部署方案有多种,可以自动操作,如果失败,可以尝试分步骤操作
    此脚本部署的模块为windows适配,调用了.Net API,其他平台部署可能会出错或不适用
    .PARAMETER Mode
    选择部署模式:如果选择FromPackage,则仅尝试查找本地包,如果没有,则通过下载模块集包到本地,然后执行安装(不保证成功下载)
    如果选择默认的Default,则依次检查本地包是否存在,如果不存在,则尝试通过克隆的方式下载(要求已经安装git)
    .EXAMPLE
    直接调用,不是用参数,适合第一次部署
    deploy-CxxuPsModules
    .EXAMPLE
    轻量部署(仅 Windows PowerShell 5.1,免 git 免 pwsh):无 git 时不提示安装,直走离线包下载;
    结尾不装 pwsh,改写 5.1 专属 profile,新开 powershell.exe 跑 init 即用
    deploy-CxxuPsModules -Light -Verbose
    .EXAMPLE
    使用在线方案,从默认的gitee/github(要求预先安装Git软件)
    PS C:\Users\cxxu > deploy-CxxuPsModules -Mode FromRemoteGit -RepoPath C:/TestPsM -Verbose
    Mode:Clone From Remote repository:[gitee]
    VERBOSE: https://gitee.com/xuchaoxin1375/scripts.git
    VERBOSE: C:/TestPsM
    Cloning into 'C:/TestPsM'...
    remote: Enumerating objects: 430, done.
    remote: Counting objects: 100% (238/238), done.
    remote: Compressing objects: 100% (206/206), done.
    remote: Total 430 (delta 72), reused 82 (delta 1), pack-reused 192
    Receiving objects: 100% (430/430), 1004.73 KiB | 659.00 KiB/s, done.
    Resolving deltas: 100% (80/80), done.

    Name         Value
    ----         -----
    PsModulePath C:\TestPsM\PS
                C:\Users\cxxu\Desktop\TestPsy\PS
                C:\Users\cxxu\scoop\modules
                
    .EXAMPLE
    从远程的Github仓库下载zip包,并解压到指定目录(如果本地已经有包,则优先使用本地的包)
    
    PS C:\Users\cxxu\scoop\apps\powershell\current> deploy-CxxuPsModules -Mode FromPackage -RepoPath C:/TestDirPs -PackagePath $home/desktop  -Verbose
    VERBOSE: Downloading https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main to C:\Users\cxxu/Downloads/CxxuPsModules/scripts-2024-09-19--09-05-42.zip
    VERBOSE: Requested HTTP/1.1 GET with 0-byte payload
    VERBOSE: Received HTTP/1.1 response of content type application/zip of unknown size
    VERBOSE: File Name: scripts-2024-09-19--09-05-42.zip
    Mode:Expanding local pacakge:[C:\Users\cxxu/Downloads/CxxuPsModules/scripts-2024-09-19--09-05-42.zip]
    C:\TestDirPs\scripts-main C:/TestDirPs/scripts
    VERBOSE: Performing the operation "Remove Directory" on target "C:\TestDirPs\scripts-main".

    Name         Value
    ----         -----
    PsModulePath C:/TestDirPs\PS
                C:\Users\cxxu\scoop\modules

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        # 模块集所在仓库的存放目录(这个目录不一定是git clone下来的仓库目录,也可以是从本地包解压到对应位置的目录)
        $RepoPath = "$env:systemdrive\repos\scripts",
        # 添加到环境变量中的路径
        $NewPsPath = "$RepoPath\PS",
        
        [ValidateSet('gitee', 'github')]
        $RepoSource = 'github',
        # 如果使用从包安装的方案,需要指定包的位置,这里的路径是包文件路径,而不是包文件所在目录
        #和从远程仓库克隆有多个来源可选一样,下载离线包也有多种选择,同样是github可以直接下载,但是速度慢或者下不动,
        # 而gitee等仓库平台需要登录,条件允许的话,登录下载快,成功率高
        $PackagePath = "$home/Downloads/CxxuPsModules/scripts*.zip",
        
        # default 自动切换策略(优先尝试从本地包安装,如果失败,则尝试从远程仓库克隆)
        [ValidateSet('Default', 'FromPackage', 'FromRemoteGit')]
        $Mode = 'Default', 
        [switch]$Force,
        # 轻量部署(仅 Windows PowerShell 5.1):无 git 时不提示安装,直走离线包;结尾不装 pwsh,改写 5.1 profile
        [switch]$Light
    )
    
    # 打印此函数的所有参数极其取值,方便用户排查问题
    $params = [pscustomobject]@{
        RepoPath    = $RepoPath
        NewPsPath   = $NewPsPath
        Source      = $RepoSource
        PackagePath = $PackagePath
        Mode        = $Mode
        Force       = $Force
    }
    Write-Verbose "check deploy params (by user):"
    $PSBoundParameters | Format-Table
    Write-Verbose "check deploy params (full:user and default):"
    $params | Format-Table

    $isContinue = $PSCmdlet.ShouldProcess("$env:UserName@$env:COMPUTERNAME", 'Deploy CxxuPsModules')
    if ($isContinue)
    {
        # 用户选择继续执行
        Write-Host 'Deploy CxxuPsModules...'
    }
    else
    {
        #用户取消继续执行
        # 向用户展示调用语法
        Get-Command Deploy-CxxuPsModules -Syntax
        # 退出执行
        return 
    }

    # if ($host.Version.Major -lt 7)
    # {
    #     Write-Warning 'Please use powershell7 use full feature of the CxxuPsModules!' 
    # }
    
    # 路径准备
    # $NewPsPath = $NewPsPathPattern | Invoke-Expression
    # 检查路径占用
    if (Test-Path $RepoPath)
    {
        Write-Host "$($RepoPath) already exists!"
        # if (! (Test-DirectoryEmpty $RepoPath )){
        # }
        if ($Force)
        {
            Rename-Item -Path $RepoPath -NewName "$($RepoPath).bak.$((Get-Date).ToString('yyyy-MM-dd--HH-mm-ss'))" -Verbose
        }
        else
        {

            Write-Host "The default RepoPath directory [$RepoPath] is already exist!(Remove or rename the old dir and try again.)" -ForegroundColor Magenta


            # Throw 'Try another path(RepoPath)! OR delete or rename(backup) the exist directory!' #报错可能会让新用户不知所措,这里直接退出即可
            return $false

            # $RepoPath = Read-Host -Prompt 'Input new path (Ctrl+C to exit)'
            # Write-Verbose "Updated RepoPath to [$RepoPath]"
            # # $newPsPath = "$RepoPath\PS"
            # $NewPsPath = $NewPsPathPattern | Invoke-Expression
            # Write-Verbose "Updated newPsPath to [$newPsPath]"
        }
        New-Item -ItemType Directory $RepoPath -Verbose
    }
    # if (!(Test-Path $RepoPath))
    # {
    #     New-Item -ItemType Directory $RepoPath -Verbose
    # }

    # 定义代码下载安装模式片段
    # 模式1:从远程Git仓库克隆
    $RemoteGitCloneScript = { 
        Write-Host "Mode:Clone From Remote repository:[$RepoSource]" -ForegroundColor cyan
        $GitCmdAvailability = Get-Command git -ErrorAction SilentlyContinue
        if (!$GitCmdAvailability)
        {
            throw 'Git is not available on your system,please install it first!'
        }
        $url = "https://${RepoSource}.com/xuchaoxin1375/scripts.git"
        Write-Verbose $url
   
        Write-Verbose $RepoPath
        #克隆仓库
        # git 支持指定一个不存在的目录作为克隆目的地址,所以可以不用检查目录是否存在并手动创建
        git clone --recursive --depth 1 --shallow-submodules $url $RepoPath 
         
    }
    $LocalScript = {
        Write-Host "Mode:Expanding local pacakge:[$PackagePath]" -ForegroundColor Green
        # $RepoPathParentDir = Split-Path $RepoPath -Parent
        # 指定要解压到的目录,如果不存在Expand-archive会自动创建相应的目录
        # 获取本地已下载的可用的最新版本
        #利用Desceding将最新的排在前面
        $files = Get-ChildItem $PackagePath | Sort-Object -Property LastWriteTime -Descending 
        $PackagePath = @($files)[0]
        # 解压到合适的目录下
        Expand-Archive -Path $PackagePath -DestinationPath $RepoPath -Force
        
        $rawPath = Get-ChildItem "$RepoPath/scripts*" -Directory | Select-Object -First 1
        $newPath = "$RepoPath/scripts"

        Write-Host @($rawPath, $newPath  ) -ForegroundColor cyan

        Move-Item $rawPath/* $RepoPath -Force
        #移除空目录(如果上述步骤顺利的话)
        Remove-Item $rawPath -Verbose #如果非空,会警报用户
        # Rename-Item $rawPath $newPath -Verbose
    }
    if ($Mode -eq 'Default')
    {

        
        if ((Test-Path $PackagePath))
        {
            Write-Verbose "Local package exist,try local mode..."
            & $LocalScript
        }
        else
        {
            
            Write-Verbose @"
            检查Git是否可用:
            1.如果可用,采用最可靠的克隆方案执行,否则采用下载仓库,和本地解压方案;
            2.如果不可用,则尝试安装git,然后情况变回第一种情况
"@
            $GitAvailability = Get-Command git -ErrorAction SilentlyContinue
            if (!$GitAvailability)
            {

                if ($Light)
                {
                    Write-Host 'Light mode: git not found, skip installation, use offline package instead.' -ForegroundColor cyan
                }
                else
                {
                    #向用户推荐一键安装git的方案,然后使用默认的下载方案
                    Write-Host 'Git is not available on your system now!' -ForegroundColor cyan
                    $InstallGit = Read-Host 'Do you want to install it (it take a few seconds)!(y/n)(Default: y)'
                    if ($InstallGit -eq 'y' -or $InstallGit.Trim() -eq '')
                    {
                        Deploy-GitForwindows -Verbose
                        # & $RemoteGitCloneScript
                    }
                }
                #重新计算Git是否可用
                $GitAvailability = Get-Command git -ErrorAction SilentlyContinue
            }
            # 根据用户是否有git，调用不同的方案
            if ($GitAvailability)
            {
                #装有Git的用户使用此方案
    
                & $RemoteGitCloneScript
            }
            else
            {
    
    
                #没有Git且不想安装git的用户使用此方案(前面检测过了没有本地包,git又不可用,所以从云端仓库clone代码)
                # Light 模式 -Silent:不弹窗选源,直走 codeload + 中央镜像
                $PackagePath = Get-CxxuPsModulePackage -Silent:$Light
                & $LocalScript
            } 
        }
    }
    elseif ($Mode -eq 'FromPackage')
    {
        # 自动调用默认的下载行为
        # 您也可以手动调用Get-CxxuPsModulePackage下载包到指定位置,然后通过外部传递包的目录
        $PackagePath = Get-CxxuPsModulePackage -Silent:$Light
        & $LocalScript
    }
    elseif ($Mode -eq 'FromRemoteGit')
    {
        & $RemoteGitCloneScript
    }
 
    # $RepoPath = 'C:\repos\scripts\PS' #这里修改为您下载的模块所在目录,这里的取值作为示范
    # 临时生效以便调用模块中的函数(前置追加,不要覆盖原有取值)
    $env:PSModulePath = "$NewPsPath;$env:PSModulePath"
    if ($host.Version.Major -ge 7)
    {

        Add-EnvVar -EnvVar PsModulePath -NewValue $newPsPath -Verbose #这里$RepoPath上面定义的(默认是User作用于,并且基于User的原有取值插入新值)
        # 添加本模块集所在目录的环境变量,便于后续引用(虽然不是必须的)
        Set-EnvVar -EnvVar CxxuPsModulePath $NewPsPath -Verbose
    }
    else
    {
        # 在powershel了低版本上，无法使用Add-EnvVar,使用setx 来设置相应的环境变量,PsModulePath的用户级别变量默认情况下通常是空的
        # 而系统级别的PsModulePath则是有预设值的(和windows powershell共用)
        # 追加而非覆盖:用户级已有取值要保留(旧代码直接覆盖会丢用户原有模块路径)
        $curUserPsmp = [Environment]::GetEnvironmentVariable('PSModulePath', 'User')
        if ($curUserPsmp -like "*$newPsPath*")
        {
            Write-Verbose 'PSModulePath already contains the new path, skip setx.'
        }
        elseif ([string]::IsNullOrWhiteSpace($curUserPsmp))
        {
            setx PSModulePath $newPsPath
        }
        else
        {
            setx PSModulePath "$newPsPath;$curUserPsmp"
        }
    }

    # 你也可以替换`off`为`LTS`不完全禁用更新但是降低更新频率(仅更新LTS长期支持版powershell)
    [System.Environment]::SetEnvironmentVariable('powershell_updatecheck', 'LTS', 'user')

    #添加基础环境自动执行任务到$profile中
    # Add-CxxuPsModuleToProfile
    Write-Warning 'Please use powershell7 use full feature of the CxxuPsModules!' 
    $PwshAvailability = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($Light)
    {
        # 轻量模式:免 pwsh,不装 portable;写 5.1 专属 profile(幂等),新开 powershell.exe 即用
        Write-Host 'Light mode: skip pwsh installation.' -ForegroundColor cyan
        try
        {
            Install-Ps51Profile -ErrorAction Stop
        }
        catch
        {
            Write-Warning "Install-Ps51Profile failed ($($_.Exception.Message)). After reopening powershell.exe, run it manually (needs PSModulePath set)."
        }
        Write-Host "Done. Reopen powershell.exe (Windows PowerShell 5.1) and run 'init'." -ForegroundColor Green
        return
    }
    if(! $PwshAvailability)
    # if ($host.Version.Major -lt 7)
    {
        $continue = $PSCmdlet.ShouldProcess("Install-Pwsh7Portable", 'Install pwsh7 portable')
        if ($continue)
        {

            # Invoke-RestMethod "https://$RepoSource.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-Pwsh7Portable.ps1" | Invoke-Expression
            if ($RepoSource -eq 'github')
            {
                $dp7Raw = 'https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-Pwsh7Portable.ps1'
                $dp7Url = if ($GithubMirror) { "$GithubMirror/$dp7Raw" } else { $dp7Raw }
            }
            else
            {
                $dp7Url = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-Pwsh7Portable.ps1'
            }
            Write-Verbose "Downloading Deploy-Pwsh7Portable.ps1 from $dp7Url"
            Invoke-RestMethod $dp7Url > ~/dp7.ps1
            ~/dp7.ps1 -RepoSource $RepoSource -Verbose
        }
    }
    #检查模块设置效果
    Start-Process -FilePath pwsh -ArgumentList '-noe -c p'
}
function Get-CxxuPsModulePackage
{
    <# 
    .SYNOPSIS
    Github目前允许用户没有登录的情况下开源仓库包
    当主要方案无法成功下载部分代码时,尝试用github等其他的线路来下载
    #>
    [CmdletBinding()]
    param(
        $Directory = "$home/Downloads/CxxuPsModules",
        $url = 'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main',
        $outputFile = "scripts-$( Get-Date -Format 'yyyy-MM-dd--hh-mm-ss').zip",
        # 静默:不弹窗选源,直走 codeload + 中央镜像(给 -Light 轻量部署用)
        [switch]$Silent
    )
    $urls = @(
        'https://gitcode.net/xuchaoxin1375/scripts/-/archive/SourceCodePackage/scripts-SourceCodePackage.zip',
        'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main'
    )
    if ($Silent)
    {
        # 取 codeload 直链套中央镜像,不弹窗(脚本头部 $GithubMirror 与中央同策略)
        $dlMirror = if ($GithubMirror) { ([string]$GithubMirror).TrimEnd('/') } else { '' }
        $dlUrl = $urls[1]
        if ($dlMirror)
        {
            $dlUrl = "$dlMirror/$dlUrl"
        }
        Write-Host "Silent mode, downloading [$dlUrl]" -ForegroundColor cyan
    }
    else
    {
        $index = 0
        foreach ($url in $urls)
        {

            Write-Host "${index}:[${url}]" -ForegroundColor cyan
            $index++
        }
        $UrlCode = Read-Host "Enter the Deploy Scheme code [0..$($urls.Count-1)](default:0)"
        if ($UrlCode.Trim() -eq '') { $UrlCode = 0 }
        $dlUrl = $urls[$UrlCode]
    }
    if (!(Test-Path $Directory))
    {
        # Out-Null:目录对象别漏进成功流,否则 return 的包路径会被污染成数组
        New-Item -ItemType Directory -Path $Directory -Verbose | Out-Null
    }
    $PackgePath = "$Directory/$outputFile"
    Write-Verbose "Downloading [$dlUrl] to $PackgePath" -Verbose
    Invoke-WebRequest -Uri $dlUrl -OutFile $PackgePath -TimeoutSec 120 -Verbose
    return $PackgePath
}





 

#交互脚本
# $continue = Read-Host 'Install the CxxuPSModules in Default Parameters?
# [Input y to continue,n to exit and use your customized parameters to install it](y/n)'
# if ($continue)
# {
#     Deploy-CxxuPsModules -Verbose
# }
function Remove-CxxuPsModulesEnvVars
{
    <# 
    .SYNOPSIS
    供调试时使用
    移除CxxuPsModules的环境变量设置,包括PsModulePath,CxxuPsModulePath,Path中相关的设置,便于恢复相关的环境变量到初始状态

    #>
    param (
        
    )

    Remove-EnvVar -EnvVar CxxuPsModulePath
    Remove-EnvVarValue -EnvVar Path -ValueToRemove 'C:\PortableGit\bin' 
    Remove-EnvVarValue -EnvVar Path -ValueToRemove "$env:systemDrive\powershell\7"
    
}
# 调用函数执行安装(配置默认行为)
Deploy-CxxuPsModules -RepoSource $RepoSource -Verbose -Force:$Force -Light:$Light