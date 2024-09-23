
function Get-CxxuPsModulePackage
{
    [CmdletBinding()]
    param(
        $Directory = "$home/Downloads/CxxuPsModules",
        $url = 'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main',
        $outputFile = "scripts-$( Get-Date -Format 'yyyy-MM-dd--hh-mm-ss').zip"
    )
    $PackgePath = "$Directory/$outputFile"
    Write-Verbose "Downloading $url to $PackgePath"
    Invoke-WebRequest -Uri $url -OutFile $PackgePath 
    return $PackgePath
}
function Deploy-CxxuPsModules
{
    <# 
    .SYNOPSIS
    一键部署CxxuPsModules，将此模块集推荐的自动加载工作添加到powershell的配置文件$profile中
    请使用powershell7部署
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
    PsModulePath C:/TestPsM\PS
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
    [CmdletBinding()]
    param(
        # 模块集所在仓库的存放目录
        $RepoPath = "$env:systemdrive/repos/scripts",
        # 添加到环境变量中的路径
        $NewPsPath = "$RepoPath\PS",
        [ValidateSet('Gitee,Github')]$Source = 'gitee',
        $PackagePath = "$home/Downloads/CxxuPsModules/scripts*.zip",
        # 选择部署模式:如果选择FromPackage,则仅尝试查找本地包,如果没有,则通过下载模块集包到本地,然后执行安装(不保证成功下载)
        # 如果选择默认的Default,则依次检查本地包是否存在,如果不存在,则尝试通过克隆的方式下载(要求已经安装git)
        [ValidateSet('Default', 'FromPackage', 'FromRemoteGit')]$Mode = 'Default',
        [switch]$Force
    )
        
    if ($host.Version.Major -lt 7)
    {
        Throw 'Please use powershell7 to deploy CxxuPsModules!'
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
            
            & $RemoteGitCloneScript
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
    Set-EnvVar -EnvVar CxxuPsModulePath  $NewPsPath -Verbose
    # 你也可以替换`off`为`LTS`不完全禁用更新但是降低更新频率(仅更新LTS长期支持版powershell)
    [System.Environment]::SetEnvironmentVariable('powershell_updatecheck', 'LTS', 'user')

    #添加基础环境自动执行任务到$profile中
    # Add-CxxuPsModuleToProfile

    #检查模块设置效果
    Start-Process -FilePath pwsh -ArgumentList '-noe -c p'
}

# 调用上述定义的函数
## 检查Git是否可用,如果可用,采用最可靠的克隆方案执行,否则采用下载仓库,和本地解压方案
$GitAvailability = Get-Command git -ErrorAction SilentlyContinue

if ($GitAvailability)
{
    #装有Git的用户使用此方案(可以指定参数,也可以不指定)
    Deploy-CxxuPsModules # -RepoPath  C:/temp/scripts -Verbose
    
}
else
{
    
    #没有Git的用户使用此方案(可以进一步指定参数)
    Deploy-CxxuPsModules -Mode FromPackage -Verbose
}