<# 
.SYNOPSIS
部署CxxuPsModules

.DESCRIPTION

这里会尝试通过在线仓库导入 Deploy-GitForWindows 模块,会引入一些外部命令;
如果本地调整此脚本时,注意在线仓库中的版本可能不是最新的.
也可以考虑用本地导入的方式暂时代替默认的导入在线版本.
.NOTES
本文件保留 UTF-8 BOM:Windows PowerShell 5.1 会把无 BOM 的含中文脚本按 ANSI 代码页解码而解析报错,
所以不要为了在线执行而删 BOM。在线执行时 irm 会把该 BOM 解码成 U+FEFF 留在字符串开头,
使首行 <# 块注释失效(表现为 "参数列表中缺少参量"),须先裁掉再 iex:
PS> iex ((irm '<此文件的在线地址>').TrimStart([char]0xFEFF))
或者先落盘再执行(保留完整中文与参数;必须用 -OutFile,用 ">" 在 5.1 会写出 UTF-16 双 BOM 而解析失败):
PS> irm '<此文件的在线地址>' -OutFile ~/dcp.ps1; ~/dcp.ps1 -Light
本地开发测试(未推送到远程时,用本地最新代码测试部署效果):
在仓库目录中直接运行此脚本并加 -Dev 即可,不拉取远程代码
PS> C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Dev -Light -Verbose

默认行为:可用 git 时优先镜像克隆,克隆失败自动回退离线包;默认不安装 PowerShell 7,
需要时显式加 -InstallPwsh7。脚本启动时会先放行当前进程的执行策略,必要时把用户级
执行策略从 Restricted/AllSigned 调为 RemoteSigned。
本地调试(不碰真实环境,产物落用户下载目录,失败或加 -KeepSandbox 时保留):
PS> C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Sandbox -Mode FromPackage -KeepSandbox
PS> C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Sandbox -Mode Default -PackagePath ./scripts-main.zip
#>
[CmdletBinding()]
param(
    # 仓库源(默认 github+加速;gitee 对远程脚本执行误报拦截,已弃用,仅保留兼容)
    [validateSet('gitee', 'github')]
    $RepoSource = 'github',
    # 下载加速镜像:默认 gh-proxy,$env:PsGithubMirror 可覆盖;git clone 与 raw/包下载都用它
    [Alias('Mirror')]
    $GithubMirror = $(if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }),
    # 适用于开发(维护调整)的测试模式(用本地最新代码,不拉远程;仓库根自动从脚本位置推导)
    [switch]$Dev,
    $DevRoot = '',
    [switch]$Force,
    # 轻量部署(仅 Windows PowerShell 5.1):免 git(走离线包下载),落 PSModulePath + 写 5.1 专属 profile,
    # 新开 powershell.exe 即用(B 档交互可用,见 Feature-Guide §13)。默认就不装 pwsh,本开关保留兼容。
    [switch]$Light,
    # 可选:部署完成后安装 PowerShell 7 portable(默认不装,避免只想要 5.1 的机器被强制拉 100MB+)
    [switch]$InstallPwsh7,
    # 部署模式:Default 自动(本地包→git 克隆→离线包);FromPackage 强制离线包;FromRemoteGit 强制克隆
    [ValidateSet('Default', 'FromPackage', 'FromRemoteGit')]
    $Mode = 'Default',
    # 本地包路径(可选):Default 模式下优先使用,便于用当前仓库打的 zip 离线测试
    $PackagePath = '',
    # 本地调试:用户下载目录下的独立目录部署,不改环境变量、不装 git/pwsh、不写 profile;默认成功后清理
    [switch]$Sandbox,
    # 本地调试:保留沙箱目录(失败时也会保留),便于检查解压/克隆结果
    [switch]$KeepSandbox
)
# 预先放行脚本执行:本脚本会落盘并执行 dgw/dp7 等下载脚本,执行策略过严会直接中断
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
    if (-not $Sandbox)
    {
        $userPolicy = Get-ExecutionPolicy -Scope CurrentUser
        if ($userPolicy -in @('Restricted', 'AllSigned'))
        {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
            Write-Host 'ExecutionPolicy(CurrentUser) was set to RemoteSigned.' -ForegroundColor Yellow
        }
    }
}
catch
{
    Write-Verbose "Set-ExecutionPolicy(CurrentUser) failed: $($_.Exception.Message)"
}
# 本地调试:使用独立沙箱目录(优先用户下载目录),跑完不碰真实环境
$sandboxRoot = $null
if ($Sandbox)
{
    if ($InstallPwsh7)
    {
        Write-Warning 'Sandbox mode does not install PowerShell 7; -InstallPwsh7 is ignored.'
        $InstallPwsh7 = $false
    }
    # 沙箱根目录:优先用户下载目录(便于查看/保留),取不到再回退系统临时目录
    $sandboxBase = $null
    try
    {
        # 从资源管理器登记项取实际下载目录,兼容 OneDrive/自定义重定向
        $downloadsReg = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name '{374DE290-123F-4565-9164-39C4925E467B}' -ErrorAction Stop
        $sandboxBase = [Environment]::ExpandEnvironmentVariables([string]$downloadsReg.'{374DE290-123F-4565-9164-39C4925E467B}')
    }
    catch
    {
        $sandboxBase = $null
    }
    if ([string]::IsNullOrWhiteSpace($sandboxBase) -or -not (Test-Path -LiteralPath $sandboxBase -PathType Container))
    {
        $sandboxBase = Join-Path $home 'Downloads'
    }
    if (-not (Test-Path -LiteralPath $sandboxBase -PathType Container))
    {
        # 下载目录不可用时退回系统临时目录,保证沙箱模式始终可跑
        $sandboxBase = [IO.Path]::GetTempPath()
    }
    $sandboxRoot = Join-Path $sandboxBase ("CxxuPsModules-Sandbox-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    Write-Host "[Sandbox] target: $sandboxRoot" -ForegroundColor Cyan
}
Write-Host "[Deploy-CxxuPsModules]:开始运行CxxuPsModules部署脚本(来源:${RepoSource};镜像:${GithubMirror})..."
# 导入 Deploy-GitForWindows 命令(适合独立部署用户使用),分开放置确保灵活性
# Light 模式免 git,跳过导入(其尾部会直接执行安装,不跳过就装上了)
if ($Light -or $Sandbox)
{
    Write-Host '[Deploy-CxxuPsModules]:Light/Sandbox mode, skip Deploy-GitForWindows.'
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
        . $devDgw -RepoSource $RepoSource -Dev -DevRoot $DevRoot -GithubMirror $GithubMirror
    }
    else
    {
        Write-Warning "Dev mode requested but local file not found [$devDgw], fall back to remote."
        $Dev = $false
    }
}
if (!$Light -and !$Dev -and !$Sandbox -and (Get-Command git -ErrorAction SilentlyContinue))
{
    Write-Host '[Deploy-CxxuPsModules]:Git already available, skip Deploy-GitForWindows.' -ForegroundColor Yellow
}
elseif (!$Light -and !$Dev -and !$Sandbox)
{
    # 正式版(github 走加速前缀,gitee 直连;raw 一律用 raw.githubusercontent 形式)
    if ($RepoSource -eq 'github')
    {
        $dgwRaw = 'https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-GitForWindows.ps1'
        $mirrorPrefix = ([string]$GithubMirror).TrimEnd('/')
        $dgwUrl = if ($mirrorPrefix) { "$mirrorPrefix/$dgwRaw" } else { $dgwRaw }
        Write-Verbose "GithubMirror:[$mirrorPrefix]"
    }
    else
    {
        $dgwRaw = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-GitForWindows.ps1'
        $dgwUrl = $dgwRaw
    }

    Write-Host "拉取Deploy-GitForWindows 命令:[$dgwUrl]..."
    # 用 -OutFile 直存原始字节:5.1 的 ">" 会把内容写成 UTF-16,叠加内容自带的 BOM 变成双 BOM,脚本随即解析失败
    try
    {
        Invoke-RestMethod $dgwUrl -OutFile ~/dgw.ps1 -TimeoutSec 60
    }
    catch
    {
        Write-Warning "Download Deploy-GitForWindows from mirror failed ($($_.Exception.Message)), retry direct..."
        Invoke-RestMethod $dgwRaw -OutFile ~/dgw.ps1 -TimeoutSec 60
    }
    # 兼容旧版 dgw(尚未声明 -GithubMirror):有参数才透传,没有就只传 RepoSource
    $dgwCmd = Get-Command ~/dgw.ps1 -ErrorAction SilentlyContinue
    if ($dgwCmd -and $dgwCmd.Parameters.ContainsKey('GithubMirror'))
    {
        ~/dgw.ps1 -RepoSource $RepoSource -GithubMirror $GithubMirror -Verbose
    }
    else
    {
        ~/dgw.ps1 -RepoSource $RepoSource -Verbose
    }
}

function Deploy-CxxuPsModules
{
    <# 
    .SYNOPSIS
    一键部署CxxuPsModules，将此模块集推荐的自动加载工作添加到powershell的配置文件$profile中
    .DESCRIPTION
    部署方案有多种,可以自动操作,如果失败,可以尝试分步骤操作
    此脚本部署的模块为windows适配,调用了.Net API,其他平台部署可能会出错或不适用
    默认不安装 PowerShell 7;需要时加 -InstallPwsh7。可用 git 时优先用镜像克隆,
    克隆失败(例如直连 github 被重置)会自动回退到离线包下载。
    .PARAMETER Mode
    选择部署模式:Default 优先使用 -PackagePath 指定的本地包,没有则尝试镜像克隆,克隆失败再下载离线包;
    FromPackage 重新下载离线包后安装(不使用 -PackagePath);FromRemoteGit 只从远程仓库克隆(要求已安装 git)。
    .PARAMETER GithubMirror
    下载加速镜像,默认 https://gh-proxy.com;用于 git clone、raw 脚本与离线包下载。
    .PARAMETER InstallPwsh7
    部署完成后安装 PowerShell 7 portable;默认关闭,只想要 Windows PowerShell 5.1 的机器不必下载。
    .PARAMETER Sandbox
    本地调试模式:在用户下载目录下建独立沙箱目录部署(下载目录不可用时回退系统临时目录),
    不改环境变量、不装 git/pwsh、不写 profile;成功后默认清理。
    .PARAMETER KeepSandbox
    本地调试时保留沙箱目录,便于检查解压/克隆结果;失败时无论是否指定都会保留。
    .PARAMETER PackagePath
    本地 zip 包路径;默认模式下优先使用,配合 -Sandbox 可在不通网时快速回归。
    .EXAMPLE
    直接调用,不是用参数,适合第一次部署
    deploy-CxxuPsModules
    .EXAMPLE
    轻量部署(仅 Windows PowerShell 5.1,免 git):无 git 时不提示安装,直走离线包下载;
    改写 5.1 专属 profile,新开 powershell.exe 跑 init 即用
    deploy-CxxuPsModules -Light -Verbose
    .EXAMPLE
    需要完整功能时显式安装 PowerShell 7
    deploy-CxxuPsModules -InstallPwsh7 -Verbose
    .EXAMPLE
    本地调试:在用户下载目录下建沙箱部署,不改真实环境;用本地 zip 包可完全离线回归
    deploy-CxxuPsModules -Sandbox -Mode Default -PackagePath ./scripts-main.zip -KeepSandbox
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
        # 下载加速镜像:显式指定时不测速、不弹窗;为空则回退脚本级参数/环境变量
        [Alias('Mirror')]
        $GithubMirror = '',
        # 轻量部署(仅 Windows PowerShell 5.1):无 git 时不提示安装,直走离线包;改写 5.1 profile
        [switch]$Light,
        # 可选:安装 PowerShell 7 portable(默认不装)
        [switch]$InstallPwsh7,
        # 本地调试:临时目录部署,结尾只校验并清理/保留,不写环境变量与 profile
        [switch]$Sandbox,
        [switch]$KeepSandbox
    )
    # 函数参数为空时继承脚本级默认值(直接调用函数也能拿到同一镜像)
    if ([string]::IsNullOrWhiteSpace($GithubMirror))
    {
        $GithubMirror = $script:GithubMirror
    }
    $GithubMirror = ([string]$GithubMirror).TrimEnd('/')
    if ($Sandbox)
    {
        # 沙箱不安装任何持久组件
        $InstallPwsh7 = $false
    }
    # 沙箱把离线包也放在沙箱目录,不混入常规包目录或用户指定的包目录
    $packageDirectory = if ($Sandbox) { Join-Path $RepoPath 'packages' } else { "$home/Downloads/CxxuPsModules" }

    # 打印此函数的所有参数极其取值,方便用户排查问题
    $params = [pscustomobject]@{
        RepoPath     = $RepoPath
        NewPsPath    = $NewPsPath
        Source       = $RepoSource
        PackagePath  = $PackagePath
        Mode         = $Mode
        Force        = $Force
        GithubMirror = $GithubMirror
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
            # Rename-Item 的 -NewName 只能是叶子名,不能带路径分隔符
            $backupName = "$([IO.Path]::GetFileName($RepoPath)).bak.$((Get-Date).ToString('yyyy-MM-dd--HH-mm-ss'))"
            Rename-Item -Path $RepoPath -NewName $backupName -Verbose
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
    # 模式1:从远程Git仓库克隆(镜像优先,失败再直连,最后交给调用方回退离线包)
    $RemoteGitCloneScript = { 
        Write-Host "Mode:Clone From Remote repository:[$RepoSource]" -ForegroundColor cyan
        $GitCmdAvailability = Get-Command git -ErrorAction SilentlyContinue
        if (!$GitCmdAvailability)
        {
            throw 'Git is not available on your system,please install it first!'
        }
        $directUrl = "https://${RepoSource}.com/xuchaoxin1375/scripts.git"
        $cloneUrls = @()
        if ($RepoSource -eq 'github' -and -not [string]::IsNullOrWhiteSpace($GithubMirror))
        {
            $cloneUrls += "$GithubMirror/$directUrl"
        }
        $cloneUrls += $directUrl
        Write-Verbose "RepoPath: $RepoPath"

        foreach ($url in $cloneUrls)
        {
            # git 支持指定一个不存在的目录作为克隆目的地址;失败残留的目录先清掉再试下一个源
            if (Test-Path -LiteralPath $RepoPath)
            {
                if (Test-Path -LiteralPath (Join-Path $RepoPath 'PS'))
                {
                    return $true
                }
                Remove-Item -LiteralPath $RepoPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Host "Cloning from [$url]..." -ForegroundColor cyan
            # 输出先转成字符串再决定是否显示,避免 5.1 把 git 的 stderr 当成红色错误刷屏
            $gitOutput = @(& git clone --recursive --depth 1 --shallow-submodules $url $RepoPath 2>&1 | ForEach-Object { "$_" })
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $RepoPath 'PS')))
            {
                Write-Verbose ($gitOutput -join [Environment]::NewLine)
                return $true
            }
            Write-Warning "Clone failed from [$url] (exit $LASTEXITCODE), try next source..."
            Write-Host ($gitOutput -join [Environment]::NewLine)
        }
        return $false
    }
    $LocalScript = {
        Write-Host "Mode:Expanding local pacakge:[$PackagePath]" -ForegroundColor Green
        # $RepoPathParentDir = Split-Path $RepoPath -Parent
        # 指定要解压到的目录,如果不存在Expand-archive会自动创建相应的目录
        # 获取本地已下载的可用的最新版本
        #利用Desceding将最新的排在前面
        $packagePattern = $PackagePath
        $files = Get-ChildItem $packagePattern -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime -Descending 
        $PackagePath = @($files)[0]
        if (-not $PackagePath)
        {
            throw "No package matched [$packagePattern]."
        }
        # 解压到合适的目录下
        Expand-Archive -Path $PackagePath -DestinationPath $RepoPath -Force
        
        $rawPath = Get-ChildItem "$RepoPath/scripts*" -Directory | Select-Object -First 1
        if (-not $rawPath)
        {
            throw "Package [$PackagePath] does not contain a scripts-* directory."
        }
        $newPath = "$RepoPath/scripts"

        Write-Host @($rawPath, $newPath  ) -ForegroundColor cyan

        # 用 -Force 连隐藏文件(.gitattributes/.gitignore)一起搬,避免解压后的仓库缺文件
        Get-ChildItem -LiteralPath $rawPath -Force | Move-Item -Destination $RepoPath -Force
        #移除空目录(如果上述步骤顺利的话)
        Remove-Item $rawPath -Recurse -Force -Confirm:$false -Verbose #如果非空,会警报用户
        # Rename-Item $rawPath $newPath -Verbose
        if (-not (Test-Path -LiteralPath (Join-Path $RepoPath 'PS')))
        {
            throw "Package [$PackagePath] was expanded but [$RepoPath/PS] is still missing."
        }
        return $true
    }
    # 重新准备空目录:上一次克隆/解压失败可能留下半成品,直接覆盖会撞目录
    $ResetRepoPath = {
        if (Test-Path -LiteralPath $RepoPath)
        {
            Remove-Item -LiteralPath $RepoPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $RepoPath -Force | Out-Null
    }
    if ($Mode -eq 'Default')
    {
        # 本地包优先(有则省一次网络);损坏/解压失败时继续走 git 或重新下载
        if ((Test-Path $PackagePath))
        {
            Write-Verbose "Local package exist,try local mode..."
            try
            {
                & $LocalScript | Out-Null
            }
            catch
            {
                Write-Warning "Local package deploy failed ($($_.Exception.Message)), try git/download instead."
                & $ResetRepoPath
            }
        }

        if (-not (Test-Path -LiteralPath (Join-Path $RepoPath 'PS')))
        {
            Write-Verbose @"
            检查Git是否可用:
            1.如果可用,采用最可靠的克隆方案执行,否则采用下载仓库,和本地解压方案;
            2.如果不可用,则尝试安装git,然后情况变回第一种情况
"@
            $GitAvailability = Get-Command git -ErrorAction SilentlyContinue
            if (!$GitAvailability)
            {

                if ($Light -or $Sandbox)
                {
                    Write-Host 'Light/Sandbox mode: git not found, skip installation, use offline package instead.' -ForegroundColor cyan
                }
                else
                {
                    #向用户推荐一键安装git的方案,然后使用默认的下载方案
                    Write-Host 'Git is not available on your system now!' -ForegroundColor cyan
                    $InstallGit = Read-Host 'Do you want to install it (it take a few seconds)!(y/n)(Default: y)'
                    if ($InstallGit -eq 'y' -or $InstallGit.Trim() -eq '')
                    {
                        # 正常模式下 dgw 是以脚本方式执行的,其内部函数不会留在当前作用域;
                        # 有函数就直调,没有就重新执行已下载的 dgw.ps1(同样先检查 git)
                        if (Get-Command Deploy-GitForwindows -ErrorAction SilentlyContinue)
                        {
                            Deploy-GitForwindows -mirror $GithubMirror -Verbose
                        }
                        elseif (Test-Path -LiteralPath ~/dgw.ps1)
                        {
                            $dgwCmd = Get-Command ~/dgw.ps1 -ErrorAction SilentlyContinue
                            if ($dgwCmd -and $dgwCmd.Parameters.ContainsKey('GithubMirror'))
                            {
                                & ~/dgw.ps1 -RepoSource $RepoSource -GithubMirror $GithubMirror -Verbose
                            }
                            else
                            {
                                & ~/dgw.ps1 -RepoSource $RepoSource -Verbose
                            }
                        }
                        else
                        {
                            Write-Warning 'Deploy-GitForWindows script is not available; skip git installation.'
                        }
                        # & $RemoteGitCloneScript
                    }
                }
                #重新计算Git是否可用
                $GitAvailability = Get-Command git -ErrorAction SilentlyContinue
            }
            # 根据用户是否有git，调用不同的方案
            if ($GitAvailability)
            {
                #装有Git的用户使用此方案;克隆失败(如直连 github 被重置)自动回退离线包
                $cloned = & $RemoteGitCloneScript
                if (-not $cloned)
                {
                    Write-Warning 'Git clone failed from all sources, fall back to offline package.'
                    & $ResetRepoPath
                    $PackagePath = Get-CxxuPsModulePackage -Silent:$true -Directory $packageDirectory
                    & $LocalScript | Out-Null
                }
            }
            else
            {


                #没有Git且不想安装git的用户使用此方案(前面检测过了没有本地包,git又不可用,所以从云端仓库clone代码)
                # Light 模式 -Silent:不弹窗选源,直走 codeload + 中央镜像
                & $ResetRepoPath
                $PackagePath = Get-CxxuPsModulePackage -Silent:($Light -or $Sandbox) -Directory $packageDirectory
                & $LocalScript | Out-Null
            } 
        }
    }
    elseif ($Mode -eq 'FromPackage')
    {
        # 自动调用默认的下载行为
        # 您也可以手动调用Get-CxxuPsModulePackage下载包到指定位置,然后通过外部传递包的目录
        & $ResetRepoPath
        $PackagePath = Get-CxxuPsModulePackage -Silent:($Light -or $Sandbox) -Directory $packageDirectory
        & $LocalScript | Out-Null
    }
    elseif ($Mode -eq 'FromRemoteGit')
    {
        $cloned = & $RemoteGitCloneScript
        if (-not $cloned)
        {
            & $ResetRepoPath
            throw 'Git clone failed from all sources. Check network or use -Mode FromPackage.'
        }
    }
 
    if ($Sandbox)
    {
        $hasDeploy = Test-Path -LiteralPath (Join-Path $NewPsPath 'Deploy/Deploy.psd1')
        $hasInit = Test-Path -LiteralPath (Join-Path $NewPsPath 'Init/Init.psd1')
        $hasGitAttr = Test-Path -LiteralPath (Join-Path $RepoPath '.gitattributes')
        $result = [pscustomobject]@{
            RepoPath      = $RepoPath
            NewPsPath     = $NewPsPath
            Mode          = $Mode
            DeployManifest = $hasDeploy
            InitManifest  = $hasInit
            GitAttributes = $hasGitAttr
            Kept          = $false
        }
        $ok = $hasDeploy -and $hasInit -and $hasGitAttr
        $result.Kept = $KeepSandbox -or (-not $ok)
        Write-Host '--- Sandbox result ---' -ForegroundColor Cyan
        $result | Format-List | Out-Host
        if (-not $ok)
        {
            Write-Warning 'Sandbox verification found missing files; directory kept for inspection.'
        }
        elseif ($KeepSandbox)
        {
            Write-Host "Sandbox kept: $RepoPath (use -KeepSandbox to keep it next time)" -ForegroundColor Yellow
        }
        else
        {
            Remove-Item -LiteralPath $RepoPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host 'Sandbox removed (use -KeepSandbox to keep it for inspection).' -ForegroundColor Cyan
        }
        return $result
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
    $PwshAvailability = Get-Command pwsh -ErrorAction SilentlyContinue

    # 默认不装 PowerShell 7:只有显式 -InstallPwsh7 才下载便携版
    if (-not $PwshAvailability -and $InstallPwsh7)
    {
        $continue = $PSCmdlet.ShouldProcess("Install-Pwsh7Portable", 'Install pwsh7 portable')
        if ($continue)
        {
            try
            {
                # Invoke-RestMethod "https://$RepoSource.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-Pwsh7Portable.ps1" | Invoke-Expression
                if ($RepoSource -eq 'github')
                {
                    $dp7Raw = 'https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-Pwsh7Portable.ps1'
                    $dp7Url = if ($GithubMirror) { "$GithubMirror/$dp7Raw" } else { $dp7Raw }
                }
                else
                {
                    $dp7Raw = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-Pwsh7Portable.ps1'
                    $dp7Url = $dp7Raw
                }
                Write-Verbose "Downloading Deploy-Pwsh7Portable.ps1 from $dp7Url"
                # 同上:统一 -OutFile,避免 5.1 的 ">" 写出双 BOM
                try
                {
                    Invoke-RestMethod $dp7Url -OutFile ~/dp7.ps1 -TimeoutSec 60
                }
                catch
                {
                    Write-Warning "Download Deploy-Pwsh7Portable from mirror failed ($($_.Exception.Message)), retry direct..."
                    Invoke-RestMethod $dp7Raw -OutFile ~/dp7.ps1 -TimeoutSec 60
                }
                $dp7Cmd = Get-Command ~/dp7.ps1 -ErrorAction SilentlyContinue
                if ($dp7Cmd -and $dp7Cmd.Parameters.ContainsKey('GithubMirror'))
                {
                    ~/dp7.ps1 -RepoSource $RepoSource -GithubMirror $GithubMirror -Verbose
                }
                else
                {
                    ~/dp7.ps1 -RepoSource $RepoSource -Verbose
                }
            }
            catch
            {
                Write-Warning "Install PowerShell 7 failed ($($_.Exception.Message)). Deployment of CxxuPsModules still continues."
            }
            $PwshAvailability = Get-Command pwsh -ErrorAction SilentlyContinue
        }
    }
    elseif (-not $PwshAvailability)
    {
        Write-Host 'Skip PowerShell 7 installation (default). Use -InstallPwsh7 if you need full features.' -ForegroundColor Yellow
    }

    if ($Light -or (-not $PwshAvailability -and $host.Version.Major -lt 7))
    {
        # 轻量模式或 5.1 未装 pwsh:写 5.1 专属 profile(幂等),新开 powershell.exe 即用
        if ($Light)
        {
            Write-Host 'Light mode: skip pwsh installation.' -ForegroundColor cyan
        }
        try
        {
            if (-not (Get-Command Install-Ps51Profile -ErrorAction SilentlyContinue))
            {
                $initManifest = Join-Path (Join-Path $NewPsPath 'Init') 'Init.psd1'
                if (Test-Path -LiteralPath $initManifest)
                {
                    Import-Module $initManifest -Force -ErrorAction Stop
                }
            }
            Install-Ps51Profile -ErrorAction Stop
            Write-Host "Done. Reopen powershell.exe (Windows PowerShell 5.1) and run 'init'." -ForegroundColor Green
        }
        catch
        {
            Write-Warning "Install-Ps51Profile failed ($($_.Exception.Message)). After reopening powershell.exe, run it manually (needs PSModulePath set)."
        }
        return
    }

    if ($PwshAvailability)
    {
        Write-Host "Done. Reopen your terminal and run 'init'." -ForegroundColor Green
    }
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
        $outputFile = "scripts-$( Get-Date -Format 'yyyy-MM-dd--HH-mm-ss').zip",
        # 下载加速镜像:为空则继承脚本级 $GithubMirror
        [string]$Mirror = '',
        # 静默:不弹窗选源,按镜像→直连→gitcode 顺序自动重试(给 -Light 轻量部署用)
        [switch]$Silent
    )
    if ([string]::IsNullOrWhiteSpace($Mirror))
    {
        $Mirror = $GithubMirror
    }
    $Mirror = ([string]$Mirror).TrimEnd('/')
    $codeload = 'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main'
    $candidates = @()
    if ($Mirror)
    {
        $candidates += "$Mirror/$codeload"
    }
    $candidates += $codeload
    $candidates += 'https://gitcode.net/xuchaoxin1375/scripts/-/archive/SourceCodePackage/scripts-SourceCodePackage.zip'
    $candidates = @($candidates | Select-Object -Unique)

    if ($Silent)
    {
        Write-Host "Silent mode, try package sources in order: $($candidates -join ', ')" -ForegroundColor cyan
        $order = $candidates
    }
    else
    {
        for ($i = 0; $i -lt $candidates.Count; $i++)
        {
            Write-Host "${i}:[$($candidates[$i])]" -ForegroundColor cyan
        }
        $UrlCode = Read-Host "Enter the Deploy Scheme code [0..$($candidates.Count-1)](default:0)"
        if ([string]::IsNullOrWhiteSpace($UrlCode)) { $UrlCode = 0 }
        $UrlCode = $UrlCode -as [int]
        if ($null -eq $UrlCode -or $UrlCode -lt 0 -or $UrlCode -ge $candidates.Count) { $UrlCode = 0 }
        # 选中的优先,失败后自动尝试其余源
        $order = @($candidates[$UrlCode]) + @($candidates | Where-Object { $_ -ne $candidates[$UrlCode] })
    }

    if (!(Test-Path $Directory))
    {
        # Out-Null:目录对象别漏进成功流,否则 return 的包路径会被污染成数组
        New-Item -ItemType Directory -Path $Directory -Verbose | Out-Null
    }
    $PackagePath = "$Directory/$outputFile"
    foreach ($dlUrl in $order)
    {
        Write-Host "Downloading [$dlUrl] to [$PackagePath]..." -ForegroundColor cyan
        try
        {
            # 5.1 用 -UseBasicParsing 避开 IE 解析器;包不大,超时给足
            Invoke-WebRequest -Uri $dlUrl -OutFile $PackagePath -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
            if ((Test-Path -LiteralPath $PackagePath) -and (Get-Item -LiteralPath $PackagePath).Length -gt 0)
            {
                # 只认 zip 签名(PK),避免把镜像返回的 HTML 错误页当成包
                $head = New-Object byte[] 2
                $fs = [IO.File]::OpenRead($PackagePath)
                try { $n = $fs.Read($head, 0, 2) } finally { $fs.Close() }
                if ($n -eq 2 -and $head[0] -eq 0x50 -and $head[1] -eq 0x4B)
                {
                    return $PackagePath
                }
                throw 'Downloaded file is not a zip package.'
            }
            throw 'Downloaded file is empty.'
        }
        catch
        {
            Write-Warning "Package source failed ($($_.Exception.Message)): $dlUrl"
            Remove-Item -LiteralPath $PackagePath -Force -ErrorAction SilentlyContinue
        }
    }
    throw 'All package sources failed. Download the repository zip manually, then use -PackagePath.'
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
if ($Sandbox)
{
    $sandboxArgs = @{
        RepoPath     = $sandboxRoot
        NewPsPath    = Join-Path $sandboxRoot 'PS'
        PackagePath  = if ([string]::IsNullOrWhiteSpace($PackagePath)) { Join-Path $sandboxRoot 'packages/scripts*.zip' } else { $PackagePath }
        RepoSource   = $RepoSource
        GithubMirror = $GithubMirror
        Mode         = $Mode
        Sandbox      = $true
        KeepSandbox  = $KeepSandbox
        Force        = $Force
        Confirm      = $false
        Verbose      = $true
    }
    try
    {
        $null = Deploy-CxxuPsModules @sandboxArgs
    }
    catch
    {
        if (-not (Test-Path -LiteralPath $sandboxRoot))
        {
            New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
        }
        Write-Warning "Sandbox deployment failed; kept at [$sandboxRoot] for inspection."
        throw
    }
}
else
{
    $deployArgs = @{
        RepoSource   = $RepoSource
        GithubMirror = $GithubMirror
        Mode         = $Mode
        Verbose      = $true
        Force        = $Force
        Light        = $Light
        InstallPwsh7 = $InstallPwsh7
    }
    if (-not [string]::IsNullOrWhiteSpace($PackagePath))
    {
        $deployArgs.PackagePath = $PackagePath
    }
    Deploy-CxxuPsModules @deployArgs
}