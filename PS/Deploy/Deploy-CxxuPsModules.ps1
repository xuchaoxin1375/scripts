
function Get-CxxuPsModulePackage
{
    <# 
    .SYNOPSIS
    Github目前允许用户没有登录的情况下开源仓库包
    #>
    [CmdletBinding()]
    param(
        $Directory = "$home/Downloads/CxxuPsModules",
        $url = 'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main',
        $outputFile = "scripts-$( Get-Date -Format 'yyyy-MM-dd--hh-mm-ss').zip"
    )
    $urls = @(
        'https://gitcode.net/xuchaoxin1375/scripts/-/archive/SourceCodePackage/scripts-SourceCodePackage.zip',
        'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main'
    )
    $index = 0
    foreach ($url in $urls)
    {

        Write-Host "${index}:[${url}]" -ForegroundColor Blue
        $index++
    }
    $UrlCode = Read-Host "Enter the Deploy Scheme code [0..$($urls.Count-1)](default:0)"
    if ($UrlCode.Trim() -eq '') { $UrlCode = 0 }
    $url = $urls[$UrlCode]
    if (!(Test-Path $Directory))
    {
        New-Item -ItemType Directory -Path $Directory -Verbose
    }
    $PackgePath = "$Directory/$outputFile"
    Write-Verbose "Downloading [$url] to $PackgePath" -Verbose
    Invoke-WebRequest -Uri $url -OutFile $PackgePath -Verbose
    return $PackgePath
}

function Deploy-GitForwindows
{
    [CmdletBinding(DefaultParameterSetName = 'Online')]
    param(
        # 使用镜像加速下载git release文件
        [parameter(ParameterSetName = 'Online')]
        $mirror = 'https://gh-proxy.com',
        # 注意区分这url是一个自解压文件还是压缩包文件
        [parameter(ParameterSetName = 'Online')]
        $url = 'https://github.com/git-for-windows/git/releases/download/v2.46.2.windows.1/PortableGit-2.46.2-64-bit.7z.exe',

        [parameter(ParameterSetName = 'PackagePath')]
        $PackagePath ,
        
        $Path = 'C:\PortableGit'
    )
    # 实用New-Item的-force参数,即便路径已经存在,也不会报错(如果已经存在此目录,内部的也不会被覆盖(移除))
    New-Item -ItemType Directory $Path -Verbose -Force 
    if ( $PSCmdlet.ParameterSetName -eq 'PackagePath' )
    {
        $Package = $PackagePath
    }
    else
    {

        $Package = "$Path\PortableGit.7z.exe"
        if (!(Test-Path $Package))
        {
            $url = "${mirror}/${url}"
            Invoke-WebRequest -Uri $url -OutFile $Package -Verbose
        }
        
    }
    # Write-Host "$Package  exist!" 
    # $Package = "$home/downloads/PortableGit.7z.exe"
    # 静默安装(默认解压到$Pacakge所在目录的PortableGit子目录)
    # & $Package -y #这种做法会抛到后台进程去执行安装,前台继续执行,可能会引发顺序命令顺序问题
    Write-Host 'Installing PortableGit...(it may take a while)' -ForegroundColor Blue

    Start-Process "$Package" -ArgumentList '-y' -Wait #使用Start-Process命令执行安装,配合-wait参数等待安装完成再执行后续内容
    #将目录转移到专门的目录下
    # Move-Item $Path\PortableGit "$env:SystemDrive\" -Verbose -Force
    Move-Item $Path\PortableGit\* "$path" -Verbose -Force
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
    使用在线方案,从默认的gitee仓库克隆下载(要求预先安装Git软件)
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        # 模块集所在仓库的存放目录(这个目录不一定是git clone下来的仓库目录,也可以是从本地包解压到对应位置的目录)
        $RepoPath = "$env:systemdrive\repos\scripts",
        # 添加到环境变量中的路径
        $NewPsPath = "$RepoPath\PS",
        
        [ValidateSet('Gitee,Github')]
        $Source = 'gitee',
        # 如果使用从包安装的方案,需要指定包的位置,这里的路径是包文件路径,而不是包文件所在目录
        #和从远程仓库克隆有多个来源可选一样,下载离线包也有多种选择,同样是github可以直接下载,但是速度慢或者下不动,
        # 而国内的仓库平台需要登录,登录有下载快,成功率高
        $PackagePath = "$home/Downloads/CxxuPsModules/scripts*.zip",
        
        [ValidateSet('Default', 'FromPackage', 'FromRemoteGit')]
        $Mode = 'Default',
        [switch]$Force
    )
    
    # 打印此函数的所有参数极其取值,方便用户排查问题
    $params = [pscustomobject]@{
        RepoPath    = $RepoPath
        NewPsPath   = $NewPsPath
        Source      = $Source
        PackagePath = $PackagePath
        Mode        = $Mode
        Force       = $Force
    }

    $PSBoundParameters | Format-Table
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

    if ($host.Version.Major -lt 7)
    {
        Write-Warning 'Please use powershell7 use full feature of the CxxuPsModules!' 
    }
    
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

            Write-Host "The default RepoPath directory [$RepoPath] is already exist!" -ForegroundColor Magenta
            Write-Host "Plans:Try run Deploy-CxxuPsModules it with -Force option  to overlay the exist directory! `
            Or run Deploy-CxxuPsModules  with Option -RepoPath <YourNewPath> to retry!`
                eg. & {Deploy-CxxuPsModules -RepoPath  C:/PwshCxxu/scripts -Verbose} " -ForegroundColor Blue

            # Throw 'Try another path(RepoPath)! OR delete or rename(backup) the exist directory!' #报错可能会让新用户不知所措,这里直接退出即可
            return

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

    #模式及其代码准备
    $RemoteGitCloneScript = { 
        Write-Host "Mode:Clone From Remote repository:[$source]" -ForegroundColor Blue
        $GitCmdAvailability = Get-Command git -ErrorAction SilentlyContinue
        if (!$GitCmdAvailability)
        {
            Throw 'Git is not available on your system,please install it first!'
        }
        $url = "https://${Source}.com/xuchaoxin1375/scripts.git"
        Write-Verbose $url
   
        Write-Verbose $RepoPath
        #克隆仓库
        # git 支持指定一个不存在的目录作为克隆目的地址,所以可以不用检查目录是否存在并手动创建
        git clone $url $RepoPath 
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

        Write-Host @($rawPath, $newPath  ) -ForegroundColor Blue

        Move-Item $rawPath/* $RepoPath -Force
        #移除空目录(如果上述步骤顺利的话)
        Remove-Item $rawPath -Verbose #如果非空,会警报用户
        # Rename-Item $rawPath $newPath -Verbose
    }
    if ($Mode -eq 'Default')
    {

        
        if ((Test-Path $PackagePath))
        {
            & $LocalScript
        }
        else
        {
            
            ## 检查Git是否可用,如果可用,采用最可靠的克隆方案执行,否则采用下载仓库,和本地解压方案
            $GitAvailability = Get-Command git -ErrorAction SilentlyContinue
            if (!$GitAvailability)
            {

                #向用户推荐一键安装git的方案,然后使用默认的下载方案
                Write-Host 'Git is not available on your system!' -ForegroundColor Blue
                $InstallGit = Read-Host 'Do you want to install it (it take a few seconds)!(y/n)(Default: y)'
                if ($InstallGit -eq 'y' -or $InstallGit.Trim() -eq '')
                {
                    Deploy-GitForwindows -Verbose
                    # & $RemoteGitCloneScript
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
                $PackagePath = Get-CxxuPsModulePackage
                & $LocalScript
            } 
        }
    }
    elseif ($Mode -eq 'FromPackage')
    {
        # 自动调用默认的下载行为
        # 您也可以手动调用Get-CxxuPsModulePackage下载包到指定位置,然后通过外部传递包的目录
        $PackagePath = Get-CxxuPsModulePackage
        & $LocalScript
    }
    elseif ($Mode -eq 'FromRemoteGit')
    {
        & $RemoteGitCloneScript
    }
 
    # $RepoPath = 'C:\repos\scripts\PS' #这里修改为您下载的模块所在目录,这里的取值作为示范
    $env:PSModulePath = ";$NewPsPath" #为了能够调用CxxuPSModules中的函数,这里需要这么临时设置一下
    Add-EnvVar -EnvVar PsModulePath -NewValue $newPsPath -Verbose #这里$RepoPath上面定义的(默认是User作用于,并且基于User的原有取值插入新值)
    # 添加本模块集所在目录的环境变量,便于后续引用(虽然不是必须的)
    Set-EnvVar -EnvVar CxxuPsModulePath $NewPsPath -Verbose
    # 你也可以替换`off`为`LTS`不完全禁用更新但是降低更新频率(仅更新LTS长期支持版powershell)
    [System.Environment]::SetEnvironmentVariable('powershell_updatecheck', 'LTS', 'user')

    #添加基础环境自动执行任务到$profile中
    # Add-CxxuPsModuleToProfile

    #检查模块设置效果
    Start-Process -FilePath pwsh -ArgumentList '-noe -c p'
}

function Install-CxxuPsModules-Deprecated
{
    <# 
    .SYNOPSIS
    # 调用上述定义的函数
    .DESCRIPTION
    这里判断Git是否可用，如果可用，采用最可靠的克隆方案执行，否则采用下载仓库,和本地解压方案,然后用合适的参数调用Deploy-CxxuPsModule
    本函数适合作为一种默认方案,如果失败,用户可以尝试手动调用相关的函数,自行指定参数,比如Deploy-CxxuPsModule
    #>

    ## 检查Git是否可用,如果可用,采用最可靠的克隆方案执行,否则采用下载仓库,和本地解压方案
    $GitAvailability = Get-Command git -ErrorAction SilentlyContinue

    if ($GitAvailability)
    {
        #装有Git的用户使用此方案
        Deploy-CxxuPsModules # -RepoPath  C:/temp/scripts -Verbose
    
    }
    else
    {
    
        #没有Git的用户使用此方案
        Deploy-CxxuPsModules -Mode FromPackage -Verbose
    } 
}

#交互脚本
# $continue = Read-Host 'Install the CxxuPSModules in Default Parameters?
# [Input y to continue,n to exit and use your customized parameters to install it](y/n)'
# if ($continue)
# {
#     Deploy-CxxuPsModules -Verbose
# }

Deploy-CxxuPsModules -Verbose -Confirm