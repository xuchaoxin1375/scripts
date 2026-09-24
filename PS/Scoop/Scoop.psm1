<#
Scoop 模块:Windows 包管理 Scoop 的国内镜像部署与批量装机。
从 Deploy.psm1 迁入: Deploy 回归新机收尾本义,Scoop 生态归此模块;
调用方命令名不变(自动发现同名模块)。
#>

function Set-ScoopAria2Options
{
    <# 
    .SYNOPSIS
    设置scoop config文件中的aria2选项
    例如某些下载不允许使用aria2多路下载,那么关闭aria2(aria2对于proxy下载不太友好,这边建议下载大文件时采用aria2(手动启用),其他情况直接用scoop下载)
    如果允许使用aria2,那么可以起到加速的作用
    .EXAMPLE
    # 基础地设置是否启用aria2进行下载
    PS C:\Users\cxxu> Set-ScoopAria2Options False
    'aria2-enabled' has been set to 'False'
    .EXAMPLE
    #>
    param (
        [parameter(Position = 0)]
        [ValidateSet('False', 'True', 'F', 'T')] #其中F,T分别对应False和True,是简写
        $Enabled = 'True',
        [switch]$DefaultConfig
    )
    switch ($Enabled)
    {
        'T' { $Enabled = 'True' }
        'F' { $Enabled = 'False' }
    }
    scoop config aria2-enabled $Enabled
    if ($Enabled -eq 'False')
    {
        return
    }
    
    if ($DefaultConfig)
    {
        $options = ''
    }
    else
    {

        $options = '-s 16 -x 16 -k 1M --retry-wait=2 --async-dns false'
    }
    scoop config aria2-options $options
}
function Deploy-ScoopByGithubMirrors
{
    
    [CmdletBinding()]
    param (
        
        [switch]$InstallBasicSoftwares,
        $ScriptsDirectory = "$home/Downloads",
        [switch]$InstallForAdmin,
        [switch]$Silent
    )
  
    # 获取可用的github加速镜像站(用户选择的)
    $mirrors = Get-SelectedMirror -Silent:$Silent
    $mirror = @($mirrors)[0]
    ## 加速下载scoop原生安装脚本
    $script = (Invoke-RestMethod $mirror/https://raw.githubusercontent.com/scoopinstaller/install/master/install.ps1)
 
    $installer = "$ScriptsDirectory/scoop_installer.ps1"
    $installer_cn = "$ScriptsDirectory/scoop_cn_installer.ps1"
    # 利用字符串的Replace方法，将 https://github.com 替换为 $mirror/https://github.com加速
    $script> $installer
    $script.Replace('https://github.com', "$mirror/https://github.com") > $installer_cn
 
    # 根据scoopd官方文档,管理员(权限)安装scoop时需要添加参数 -RunAsAdmin参数,否则会无法安装
    # 或者你可以直接将上述代码下载下来的家目录scoop_installer_cn文件中的相关代码片段注释掉(Deny-Install 调用语句注释掉)
    # $r = Read-Host -Prompt 'Install scoop as Administrator Privilege? [Y/n]'
    # if ($r)
    # {
    #     #必要时请手动打开管理员权限的powershell,然后运行此脚本
    #     Invoke-Expression "& $installer_cn -RunAsAdmin"
    # }
    # else
    # {
 
    #     Invoke-Expression "& $installer_cn"
    # }
    if ($InstallForAdmin)
    {
        #必要时请手动打开管理员权限的powershell,然后运行此脚本
        Invoke-Expression "& $installer_cn -RunAsAdmin"
    }
    else
    {
        Invoke-Expression "& $installer_cn"
    }
 
    # 将 Scoop 的仓库源替换为proxy的
    scoop config scoop_repo $mirror/https://github.com/ScoopInstaller/Scoop
 
    #确保git可用
    Confirm-GitCommand
    
    # 可选部分
    ## 如果没有安装 Git等常用工具,可以解开下面的注释
    ## 先下载几个必需的软件的 JSON，组成一个临时的应用仓库
    if ($InstallBasicSoftwares)
    {
        Install-BasicSoftwares
    
        # 推荐使用aria2,设置多路下载
        # scoop config aria2-split 16
        Set-ScoopAria2Options 
    }
     
 
    # 将 Scoop 的 main 仓库源替换为proxy加速过的
    if (Test-Path -Path "$env:USERPROFILE\scoop\buckets\main")
    {
        # 先移除默认的源，然后添加同名bucket和加速后的源
        scoop bucket rm main
    }
    Write-Host 'Adding speedup main bucket...'+" powered by： [$mirror]"
    scoop bucket add main $mirror/https://github.com/ScoopInstaller/Main
 
    # 之前的scoop-cn 库是临时的,还不是来自Git拉取的完整库，删掉后，重新添加 Git 仓库
    Write-Host 'remove Temporary scoop-cn bucket...'
    if (Test-Path -Path "$env:USERPROFILE\scoop\buckets\scoop-cn")
    {
        scoop bucket rm scoop-cn
    }
    Write-Host 'Adding scoop-cn bucket (from git repository)...'
    scoop bucket add scoop-cn $mirror/https://github.com/duzyn/scoop-cn
 
    # Set-Location "$env:USERPROFILE\scoop\buckets\scoop-cn"
    # git config pull.rebase true
 
    Write-Host 'scoop and scoop-cn was installed successfully!'
    return $mirror
     
}

function Deploy-ScoopByGitee
{
    [CmdletBinding()]
    param (
        [switch]$InstallForAdmin,
        [switch]$InstallBasicSoftwares
    )
    # 脚本执行策略更改
    Set-ExecutionPolicy -ExecutionPolicy bypass -Scope CurrentUser
    #如果询问, 输入Y或A，同意
    
    # 执行安装命令（默认安装在用户目录下，如需更改请执行“自定义安装目录”命令）
    
    ## 自定义安装目录（注意将目录修改为合适位置)
    if ($InstallForAdmin)
    {
        $Script = "$home\Downloads\install.ps1"
        Invoke-RestMethod scoop.201704.xyz -OutFile $script #'install.ps1'
        # .\install.ps1 -ScoopDir 'D:\Scoop' -ScoopGlobalDir 'D:\GlobalScoopApps'
        & $Script -RunAsAdmin
    }
    else
    {

        Invoke-WebRequest -useb scoop.201704.xyz | Invoke-Expression
    }
    #添加包含国内软件的的scoopcn bucket,其他bucket可以自行添加
    # 更换scoop的repo地址
    scoop config SCOOP_REPO 'https://gitee.com/scoop-installer/scoop'
    # 确保git可用
    Confirm-GitCommand 
    # 拉取新库地址()
    scoop update
    Write-Verbose 'Scoop add more buckets(this process may failed to perform!You can retry to add buckets manually later!'
   
    Add-ScoopBuckets
    # scoop bucket add scoopcn https://gitee.com/scoop-installer/scoopcn

    if ($InstallBasicSoftwares)
    {
        scoop install 7zip git -g
        scoop install scoop-search -g
        scoop install aria2 -g
    }
}
function Add-ScoopBuckets
{
    <# 
    .SYNOPSIS
    基本上，添加spc这个bucket就够了,软件数量很丰富
    .DESCRIPTION
    可以根据自己的需要往里面修改或添加更多的bucket
    优先从gitee加速的仓库(利用github action fork的仓库自动同步上游,然后gitee再从自己的fork同步到gitee)
    https://gitee.com/xuchaoxin1375/spc

    补充方案才是直接利用github配合镜像加速
    创建冗余bucket,提高可用性和更大几率,更好的加速备选选择(使用scoop install -k 来避免可能造成错误的断点恢复下载)
    scoop bucket add spc https://github.moeyy.xyz/https://github.com/lzwme/scoop-proxy-cn
    scoop bucket add spc1 https://ghproxy.cc/https://github.com/lzwme/scoop-proxy-cn 
    scoop bucket add spc2 https://ghproxy.net/https://github.com/lzwme/scoop-proxy-cn
    scoop bucket add spc3 'https://mirror.ghproxy.com/https://github.com/lzwme/scoop-proxy-cn'

    .NOTES
    建议在Deploy-ScoopForCNUser调用时就指定相应的参数,不推荐单独调用(需要传入加速镜像地址参数)
    .EXAMPLE
    Add-ScoopBuckets -mirror  'https://mirror.ghproxy.com'
     
    #>
    [CmdletBinding()]
    param (
        # [parameter(Mandatory = $true)]    
        $mirror,
        [switch]$NoMirror,
        [switch]$Silent
    )
    if ($mirror)
    {

        Write-Verbose "The mirror is: $mirror"    
    }
    elseif ($NoMirror  )
    {
        $mirror = ''
        Write-Verbose 'The mirror is not specified!'
    }
    else
    {
        $mirror = Get-SelectedMirror -Silent:$Silent
        # $mirror=@($mirror)[0]
        Write-Verbose "The mirror is: $mirror"
    }
    $spc = "$mirror/https://github.com/lzwme/scoop-proxy-cn".Trim('/')
    # $spc = 'https://gitee.com/xuchaoxin1375/spc'

    Write-Host 'Adding more buckets...(It may take a while, please be patient!)'
    Write-Verbose "The spc bucket is: $spc"
    scoop bucket add spc $spc  
    scoop bucket add extras
            
}

function Deploy-ScoopAppsPath
{
    <# 
    .SYNOPSIS
    让scoop安装的GUI软件可以从命令行中启动(.LNK)
    .DESCRIPTION
    通过配置Scoop Apps目录添加到Path变量,以及PathExt系统环境变量中添加.LNK实现命令行中启动LNK快捷方式
    包括scoop install 和 scoop install -g 所安装的软件
    # 需要以管理员权限运行此脚本
    #>
    [CmdletBinding()]
    param()
    # 定义 Scoop Apps 目录路径
    $scoopAppsPathEx = [System.Environment]::ExpandEnvironmentVariables('%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps')
    $scoopAppsPath = '%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps'

    # 修改用户 PATH 环境变量
    $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath -notlike "*$scoopAppsPathEx*")
    {
        $newUserPath = $scoopAppsPath + ';' + $userPath
        [System.Environment]::SetEnvironmentVariable('PATH', $newUserPath, 'User')
        Write-Host '已将 Scoop Apps 目录添加到用户 PATH 环境变量中。'
    }
    else
    {
        Write-Host 'Scoop Apps 目录已在用户 PATH 环境变量中。'
    }
    #刷新当前shell中的Path变量(非永久性,当前shell会话有效)
    $env:path += $scoopAppsPath
    # 修改系统 PATHEXT 环境变量
    $systemPathExt = [System.Environment]::GetEnvironmentVariable('PATHEXT', 'Machine')
    if ($systemPathExt -notlike '*.LNK*')
    {
        $newSystemPathExt = '.LNK' + ';' + $systemPathExt
        [System.Environment]::SetEnvironmentVariable('PATHEXT', $newSystemPathExt, 'Machine')
        Write-Host '已将 .LNK 添加到系统 PATHEXT 环境变量中。'
    }
    else
    {
        Write-Host '.LNK 已在系统 PATHEXT 环境变量中。'
    }
    #全局安装的GUI软件添加到Path(系统级Path)
    $systemPath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $ScoopAppsG = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Scoop Apps'
    if ($systemPath -notlike "*$ScoopAppsG*")
    {

        $newSystemPath = $scoopAppsG + ';' + $SystemPath
        [System.Environment]::SetEnvironmentVariable( 'Path', $newSystemPath, 'Machine')
        Write-Host '已将 全局Scoop Apps 添加到系统 PATH 环境变量中。'
    }
    else
    {
        Write-Host '全局Scoop Apps 已在系统 PATH 环境变量中。'
    }

    Write-Host '环境变量修改完成。请重新启动命令提示符或 PowerShell 以使更改生效。'
}

function Update-ScoopMirror
{

    <# 
    .SYNOPSIS
    更新 Scoop 使用的加速镜像,用来提高scoop的加速可用性和用户主动性
    本函数主要用于更新已有的bucket的source
    不适合直接添加新的bucket
    .DESCRIPTION
    更新 Scoop 使用的加速镜像
    更新scoop_repo的镜像
    更新指定bucket的加速镜像(兼容为不曾加速过的bucket source做加速)
    .EXAMPLE
    
PS🌙[BAT:70%][MEM:31.42% (9.96/31.71)GB][22:28:30]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][~\Desktop]
PS> scoop bucket list

Name         Source                                                                       Updated            Manifests
----         ------                                                                       -------            ---------
main         https://ghproxy.cc/https://github.com/ScoopInstaller/Main                    2024/9/3 12:28:38       1340
extras       https://ghproxy.cc/https://github.com/ScoopInstaller/Extras                  2024/9/3 12:31:26       2067
sysinternals https://github.com/niheaven/scoop-sysinternals                               2024/7/24 0:37:20         75
nerd-fonts   https://github.moeyy.xyz//https://github.com/matthewjberger/scoop-nerd-fonts 2024/8/31 16:26:12       336
 
# 为不曾加速的原始github链接添加加速镜像
PS🌙[BAT:70%][MEM:32.21% (10.21/31.71)GB][22:28:52]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][~\Desktop]
PS> Update-ScoopMirror -BucketName sysinternals -UpdateBucket
Checking available Mirrors...
         https://gh.con.sh
         https://gh.ddlc.top.
         https://gh-proxy.com

Select the number of the mirror you want to use [0~10] ?(default: 1): 2
You Selected mirror:[2 : https://gh-proxy.com]
The sysinternals bucket was removed successfully.
Checking repo... OK
The sysinternals bucket was added successfully.
Updating Scoop...
Updating Buckets...
 
Scoop was updated successfully!

PS🌙[BAT:70%][MEM:32.8% (10.4/31.71)GB][22:30:49]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][~\Desktop]
PS> scoop bucket list

Name         Source                                                                       Updated            Manifests
----         ------                                                                       -------            ---------
main         https://ghproxy.cc/https://github.com/ScoopInstaller/Main                    2024/9/3 20:32:16       1340
extras       https://ghproxy.cc/https://github.com/ScoopInstaller/Extras                  2024/9/3 20:35:06       2067
sysinternals https://gh-proxy.com/https://github.com/niheaven/scoop-sysinternals          2024/7/24 0:37:20         75

对指定bucket更新加速镜像
PS🌙[BAT:70%][MEM:32.59% (10.33/31.71)GB][22:31:07]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][~\Desktop]
PS> Update-ScoopMirror -BucketName sysinternals -UpdateBucket
Checking available Mirrors...
 
Available Mirrors:
 0: Use No Mirror
 1: https://gh.con.sh
 2: https://cf.ghproxy.cc
 3: https://hub.gitmirror.com
 4: https://github.moeyy.xyz
 
Select the number of the mirror you want to use [0~13] ?(default: 1): 4
You Selected mirror:[4 : https://github.moeyy.xyz]
The sysinternals bucket was removed successfully.
Checking repo... OK
The sysinternals bucket was added successfully.
Updating Scoop...
Updating Buckets...
Scoop was updated successfully!

# 检查更新效果
PS🌙[BAT:70%][MEM:32.69% (10.37/31.71)GB][22:32:09]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][~\Desktop]
PS> scoop bucket list|sls sysinternal

@{Name=sysinternals; Source=https://github.moeyy.xyz/https://github.com/niheaven/scoop-sysinternals; Updated=07/24/2024 00:37:20; Manifests=75}

    #>
    <# 
    .EXAMPLE
    PS> update-scoopMirror -BucketName spc -BackupBucketWithName spc1
Checking available Mirrors...
         https://ghproxy.cc
...

Available Mirrors:
 0: Use No Mirror
 1: https://ghproxy.cc
...
 10: https://slink.ltd
 11: https://sciproxy.com
 12: https://ghproxy.homeboyc.cn
Select the number of the mirror you want to use [0~12] ?(default: 1): 10
You Selected mirror:[10 : https://slink.ltd]
Checking repo... OK
The spc1 bucket was added successfully.
    #>
    
    [CmdletBinding(DefaultParameterSetName = 'BasicRepoBuckets')]
    param (
        [parameter(ParameterSetName = 'Bucket')]
        $Mirror,
        # [parameter(ParameterSetName = 'gitee')]
        [switch]$UseGiteeScoop,
        [parameter(ParameterSetName = 'BasicRepoBuckets')]
        [switch]$BasicRepoBuckets,
        [parameter(ParameterSetName = 'Bucket')]
        $BucketName ,
        [parameter(ParameterSetName = 'Bucket')]
        [switch]$UpdateBucket,
        [parameter(ParameterSetName = 'Bucket')]
        $BackupBucketWithName,
        [switch]$Silent
    )

    if (!$Mirror -and !$UseGiteeScoop)
    {
        $Mirror = Get-SelectedMirror -Silent:$Silent
        # $Mirror=@($Mirror)[0]
    }
    if ($VerbosePreference)
    {
        # 查询旧的配置和bucket
        scoop config
        scoop bucket list    

    }


    # $Spc = "$mirror/https://github.com/lzwme/scoop-proxy-cn".Trim('/')

    
    $Name = $BucketName
    $Source = scoop bucket list | Where-Object { $_.name -eq $Name } | Select-Object -ExpandProperty source
    $count = ($Source | Select-String -Pattern 'http' -AllMatches).Matches.Count
    if ($count -gt 1)
    {

        $newSource = $Source -replace '(http.*)(http)', $($mirror + '/$2')
    }
    else
    {
        $newSource = "$mirror/$Source"
    }
    Write-Verbose "newSource: $newSource"
    if ($UpdateBucket)
    {
        
        $s = {
            scoop bucket rm $Name
            scoop bucket add $Name $newSource 
            scoop update #可以留到后面一起调用

        }    
        & $s
        return
    }
    elseif ($BackupBucketWithName)
    {
        scoop bucket add $BackupBucketWithName $newSource
        return #仅增加spc的冗余bucket,完成后结束函数
    }
    # 是否只更新bucket而不更新scoop_repo,如果不特别说明,那么连同scoop_repo一起更新
    elseif ($BasicRepoBuckets)
    {
        # 添加(更新)基本 bucket
        $scoop_repo = "$mirror/https://github.com/ScoopInstaller/Scoop".Trim('/')
        $main = "$mirror/https://github.com/ScoopInstaller/Main".Trim('/')
        $extras = "$mirror/https://github.com/ScoopInstaller/Extras".Trim('/')
        scoop config scoop_repo $scoop_repo
        scoop update #这里不适合后面一起调用,当场调用以便后续更新main,extras


    }
    elseif ($UseGiteeScoop)
    {
        scoop config scoop_repo https://gitee.com/scoop-installer/scoop
        scoop update
        # 这种情况下直接 执行 scoop bucket add main 或 extras 而不需要用指定链接 
        # scoop bucket add main $null 不会报错,这里不做$main的更改,留到最后一节一并执行
    }
    if (
        $BasicRepoBuckets 
        # -or $UseGiteeScoop
    )
    {
        #更新bucket(先移除,后更新)
        # 移除旧bucket
        Write-Verbose 'Removing old buckets...'
        $buckets = @('main', 'extras')
        foreach ($bucket in $buckets)
        {
            Write-Verbose "Removing $bucket bucket..."
            scoop bucket rm $bucket 2> $null #如果不存在,直接重定向到$null,利用 2> 重定向错误输出,正常执行则输出普通信息
        }
        scoop bucket add main $main
        scoop bucket add extras $extras
    }

    scoop update
    
}

function Set-ScoopVersion
{
    <# 
    .SYNOPSIS
    设置scoop版本
    .DESCRIPTION
    
    .Notes
    家目录可以用$home,或~表示,但是前者更加鲁棒,许多情况下后者会解析错误
    .PARAMETER Path
    您的scoop目录(默认为$home\scoop),默认安装的话你不需要手动传入该参数
    .PARAMETER ToPath
    您想要切换的Scoop版本所在目录,比如$home\scoop1
    .EXAMPLE
    Set-ScoopVersion -Path $home\scoop -ToPath $home\scoop1
    .EXAMPLE
    Set-ScoopVersion -ToPath $home\scoop0
    .EXAMPLE
    # [cxxu@BFXUXIAOXIN][<W:192.168.1.77>][~]
    PS> Set-ScoopVersion -ToPath ~/scoop1
    VERBOSE: Performing the operation "Create Junction" on target "Destination: C:\Users\cxxu\scoop".
    VERBOSE: Performing the operation "Create Directory" on target "Destination: C:\Users\cxxu\scoop".

        Directory: C:\Users\cxxu

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    l----          10/30/2024  5:49 PM                scoop -> C:\Users\cxxu\scoop1
    Scoop was found in C:\Users\cxxu\scoop1,so scoop is available now!


    Name     Source                                                          Updated               Manifests
    ----     ------                                                          -------               ---------
    main     https://github.moeyy.xyz/https://github.com/ScoopInstaller/Main 10/30/2024 4:31:22 PM      1344
    scoop-cn https://github.moeyy.xyz/https://github.com/duzyn/scoop-cn      10/30/2024 9:52:06 AM      5734
    spc      https://gh-proxy.com/https://github.com/lzwme/scoop-proxy-cn    10/30/2024 9:53:02 AM     10017


    PS[Mode:1][BAT:97%][MEM:60.79% (9.34/15.37)GB][Win 11 IoT @24H2:10.0.26100.2033][5:49:09 PM][UP:1.9Days]
    # [cxxu@BFXUXIAOXIN][<W:192.168.1.77>][~]
    PS> Set-ScoopVersion -ToPath ~/scoop0
    VERBOSE: Performing the operation "Create Junction" on target "Destination: C:\Users\cxxu\scoop".
    VERBOSE: Performing the operation "Create Directory" on target "Destination: C:\Users\cxxu\scoop".

        Directory: C:\Users\cxxu

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    l----          10/30/2024  5:49 PM                scoop -> C:\Users\cxxu\scoop0
    Scoop was found in C:\Users\cxxu\scoop0,so scoop is available now!


    Name    Source                                                       Updated                Manifests
    ----    ------                                                       -------                ---------
    main    https://gitee.com/scoop-installer/Main.git                   10/30/2024 12:29:54 PM      1344
    extras  https://gitee.com/scoop-installer/Extras                     10/30/2024 12:32:18 PM      2092
    java    https://gitee.com/scoop-installer/Java                       10/25/2024 9:20:21 AM        294
    scoopcn https://gitee.com/scoop-installer/scoopcn                    10/28/2024 4:39:06 PM         30
    spc     https://gh-proxy.com/https://github.com/lzwme/scoop-proxy-cn 10/30/2024 9:53:02 AM      10017
    .NOTES
    Author: Cxxu
    #>
    param(
        # 这里指定scoop安装目录(家目录)(也是符号/链接点链接所在目录),可以创建相应的环境变量来更优雅指定此路径,比如`setx Scoop $home\scoop`,然后使用$env:scoop 表示scoop家目录
        $Path = "$home\scoop",
        # 在这里设置默认版本,当你不提供参数时,默认使用这个默认指定的版本
        [parameter(Position = 0)]
        $ToPath = "$home\scoop0"
    )
    #检查现有相关的目录和链接
    # 获取$path模式(如果存在对应的目录或链接)
    $mode = Get-Item $Path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Mode #如果不存在对应目录或链接,则返回$null
    # 检查$Path指定名字链接是否存在
    if ($mode -notlike 'l*')
    {
        #存在目录$path
        Write-Warning "The scoop path [$Path] already exist! Try to backup it first"
        $NewPath = Read-Host "Please input the new name of the path (default is [$ToPath])"
        if ($NewPath.Trim() -eq '')
        {
            $NewPath = $ToPath
            Write-Host "Use default backup Path name $NewPath"
        }
        # 备份已有目录为新名字
        Rename-Item $Path -NewName $NewPath -Verbose
    }
    elseif ($mode ) 
    {
        # 存在$path链接
        Write-Verbose "The [$path] link already exist,change to $ToPath" -Verbose
    }
    else
    {
        Write-Verbose "The [$path] does not exist,create it now..."
    }
   
    # 确保指定目录存在
    $path, $ToPath | ForEach-Object {
        New-Item -Path $_ -ItemType Directory -Verbose -ErrorAction SilentlyContinue 
    }
    $ToPath = Resolve-Path $ToPath
    New-Item -ItemType Junction -Path $Path -Target $ToPath -Verbose -Force

    $NewName = Split-Path $ToPath -Leaf #用作配置文件目录
    $ConfigHome = "$home\.config"
    $ScoopConfigHome = "$ConfigHome\scoop"
    $ToScoopConfigHome = "$configHome\$newName"

    $mode = Get-Item $ScoopConfigHome -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Mode
    if ($mode -notlike 'l*')
    {
        Write-Warning 'The scoop config path already exist! Try to backup it first'
      
        Rename-Item $ScoopConfigHome -NewName $ToScoopConfigHome -Verbose
    }
    New-Item -ItemType Directory -Path $ToScoopConfigHome -Verbose -ErrorAction SilentlyContinue
    New-Item -ItemType Junction -Path $scoopConfigHome -Target $ToScoopConfigHome -Verbose -Force
    #检查切换后的目录内是否有scoop可以用
    $res = Get-Command scoop -ErrorAction SilentlyContinue
    if (!$res)
    {
        Write-Warning "Scoop not found in $ToPath,Scoop isn't available now"
        Write-Warning 'Consider to install a new scoop version before use it'
    }
    else
    {
        Write-Host "Scoop was found in $ToPath,so scoop is available now!" 
        # 查看当前版本下的buckets
        scoop bucket list | Format-Table 
        scoop config 
    }
}

function Deploy-ScoopForCNUser
{
 
    # & "$PSScriptRoot\scoopDeploy.ps1"
    
    <# 
.SYNOPSIS
国内用户部署scoop
.Description
允许用户在一台没有安装git等软件的windows电脑上部署scoop包管理工具
如果你事先安装好了git,那么可以选择不安装(默认行为)

脚本会通过github镜像站加速各个相关链接进行达到提速的目的
    通过加速站下载原版安装脚本
    通过替换原版安装脚本中的链接为加速链接来加速安装scoop
    根据需要创建临时的bucket,让用户可以通过scoop来安装git等软件
针对某些Administrator用户,scoop默认拒绝安装,这里根据官方指南,做了修改,允许用户选择仍然安装

使用gitee方案的,默认的bucket main 是加速过的,安装 7z,git等软件比较方便,不像镜像加速方案需要先自行建立临时的bucket提供初始下载
所以这里InstallBasicSoftwares参数是工给加速镜像方案的,不为gitee方案使用,让不同方案内体验更一致
.NOTES
代码来自git/gitee上的开源项目(感谢作者的相关工作和贡献)
.EXAMPLE
deploy-ScoopForCNUser
# 采用默认镜像加速方案部署scoop,并且安装基础软件(7z,git,aria2等),适合于新电脑环境下使用(如果需要为管理员权限安装,请追加-InstallForAdmin参数)
deploy-ScoopForCNUser -InstallBasicSoftwares

deploy-ScoopForCNUser -InstallBasicSoftwares -AddScoopBuckets #部署的时候一并添加常用的bucket

# 简洁用法:已经安装了7z git等软件,直接部署镜像加速的scoop
deploy-ScoopForCNUser #不需要参数
# 部署Gitee上的scoop爱好者贡献的加速仓库资源项目加速(最方便,但是可能比消耗资源)
例如,这里选择以管理员权限安装scoop,并且安装基础软件(7z,git,aria2等),使用了一下选项
deploy-ScoopForCNUser -UseGiteeForkAndBucket -InstallBasicSoftwares -InstallForAdmin 
# 

.DESCRIPTION
使用镜像加速下载scoop原生安装脚本并做一定的修改提供加速安装(但是稳定性和可靠性不做保证)
此脚本参考了多个开源方案,为提供了更多的灵活性和备用方案的选择,尤其是可以添加spc这个大型bucket,以提供更多的软件包
.LINK
镜像加速参考
https://github.akams.cn/ 
.LINK
https://gitee.com/twelve-water-boiling/scoop-cn
.LINK
# 提供 Deploy-ScoopByGitee 实现资源
https://gitee.com/scoop-installer/scoop
.LINK
# 提供 Deploy-scoopbyGithubMirrors 实现方式
https://lzw.me/a/scoop.html#2%20%E5%AE%89%E8%A3%85%20Scoop
.LINK
# 提供 大型bucket spc 资源
https://github.com/lzwme/scoop-proxy-cn
.LINK
相关博客
#提供 Deploy-ScoopForCNUser 整合与改进
https://cxxu1375.blog.csdn.net/article/details/121067836

在这里搜索scoop相关笔记
https://gitee.com/xuchaoxin1375/blogs/blob/main/windows 

#>
    # [CmdletBinding(DefaultParameterSetName = 'Manual')]
    param(
       
        # 是否仅查看内置的候选镜像列表
        # [switch]$CheckMirrorsBuildin,
        # 从镜像列表中选择镜像
        # [switch]$SelectMirrorFromList,
        # 是否安装基础软件，比如git等（考虑到有些用户已经安装过了，我们可以按需选择）
        # [parameter(ParameterSetName = 'Manual')]
        [switch]$InstallBasicSoftwares,
        [parameter(ParameterSetName = 'Gitee')]
        # 使用Gitee改版的国内Scoop加速版
        [switch]$UseGiteeForkAndBucket,
        
        # 是否添加一个大型的bucket
        # [switch]$AddMoreBuckets,

        # 管理员权限下安装
        [switch]$InstallForAdmin,
        # 延迟启动安装,给用户一点时间反悔
        $delay = 1
    )
    
    
    # return $mirror

    # 安装 Scoop
    # Gitee方案(简短,执行完后自动退出)
    if ($UseGiteeForkAndBucket)
    {
        Write-Host 'UseGiteeForkAndBucket scheme...'
        Start-Sleep $delay
        Deploy-ScoopByGitee -InstallBasicSoftwares:$InstallBasicSoftwares -InstallForAdmin:$InstallForAdmin 

 
    }
    # 手动配置镜像方案
    else
    {
        Write-Host 'Use manual scheme...'
        # Start-Sleep $delay
        Deploy-ScoopByGithubMirrors -InstallBasicSoftwares:$InstallBasicSoftwares -InstallForAdmin:$InstallForAdmin

    }


    # if ($addMoreBuckets)
    # {
    #     # 可以单独执行add-scoopbuckets
    #     Add-ScoopBuckets $mirror #无论$mirror取何值(空值或者链接字符串,采用位置参数传参都不影响执行)
    # }
    #检查用户安装了哪些bucket,以及对应的bucket源链接
    scoop bucket list

}


function Deploy-ScoopApps
{
    scoop install "$configs\scoop_apps.json"
}

function Deploy-ScoopStartMenuAppsStarter
{
    <# 
    .SYNOPSIS
    将Scoop开始菜单 Scoop Apps 目录添加到用户 PATH 环境变量中
    并且为了能够使得命令行内能够直接启动.lnk，需要配置环境变量PathExt，这个变量一般配置系统别环境变量PATHEXT，需要管理员权限
    .NOTES
    # 需要以管理员权限运行此脚本
    #>
    [CmdletBinding()]
    param(
        
        $scoopAppsPath = '%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps',
        $ScoopAppsG = '$scoop_global\Microsoft\Windows\Start Menu\Programs\Scoop Apps'
    )
    # 定义 Scoop Apps 目录路径
    $scoopAppsPathEx = [System.Environment]::ExpandEnvironmentVariables('%USERPROFILE%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Scoop Apps')

    # 修改用户 PATH 环境变量
    $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath -notlike "*$scoopAppsPathEx*")
    {
        # 新的PATH路径的构造方式会影响同名命令名的优先级(lnk和exe)
        # $newUserPath = $scoopAppsPath + ';' + $userPath
        $newUserPath = $userPath + ';' + $scoopAppsPath
        [System.Environment]::SetEnvironmentVariable('PATH', $newUserPath, 'User')
        Write-Host '已将 Scoop Apps 目录添加到用户 PATH 环境变量中。'
    }
    else
    {
        Write-Host 'Scoop Apps 目录已在用户 PATH 环境变量中。'
    }
    #刷新当前shell中的Path变量(非永久性,当前shell会话有效)
    $env:path += $scoopAppsPath
    # 修改系统 PATHEXT 环境变量
    $systemPathExt = [System.Environment]::GetEnvironmentVariable('PATHEXT', 'Machine')
    if ($systemPathExt -notlike '*.LNK*')
    {
        $newSystemPathExt = '.LNK' + ';' + $systemPathExt
        [System.Environment]::SetEnvironmentVariable('PATHEXT', $newSystemPathExt, 'Machine')
        Write-Host '已将 .LNK 添加到系统 PATHEXT 环境变量中。'
    }
    else
    {
        Write-Host '.LNK 已在系统 PATHEXT 环境变量中。'
    }
    #全局安装的GUI软件添加到Path(系统级Path)
    $systemPath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
    if ($systemPath -notlike "*$ScoopAppsG*")
    {

        $newSystemPath = $scoopAppsG + ';' + $SystemPath
        [System.Environment]::SetEnvironmentVariable( 'Path', $newSystemPath, 'Machine')
        Write-Host '已将 全局Scoop Apps 添加到系统 PATH 环境变量中。'
    }
    else
    {
        Write-Host '全局Scoop Apps 已在系统 PATH 环境变量中。'
    }
    Write-Host '环境变量修改完成。请重新启动命令提示符或 PowerShell 以使更改生效。'
}

function Repair-ScoopUpdate
{
    <#
    .SYNOPSIS
    修复 scoop update 或 scoop install 更新阶段被 git 中断的问题。
    .DESCRIPTION
    前置条件:scoop 本体与各 bucket 均为 git 仓库,scoop update 内部执行 git pull --rebase。
    当任一仓库存在未提交的更改(中断的更新、误编辑、换行符改动均可造成)时,git 拒绝执行
    pull --rebase,表现为 Updating Scoop... 或 Updating Buckets... 之后报错
    cannot pull with rebase: Your index contains uncommitted changes。
    本函数逐个检查 scoop 本体仓库与全部 bucket 仓库,定位处于脏状态的仓库并恢复为干净
    状态,恢复后可重新执行 scoop update。默认执行 git stash 保留现场,加 -Discard 则
    执行 git reset --hard 与 git clean,丢弃本地改动(各 bucket 内容与上游保持一致)。
    执行者为当前用户,无需管理员权限。善后:默认收尾执行一次 scoop update,加 -NoUpdate
    则只修复 git 状态,不执行更新;stash 保留的现场可用 git stash list 查看。
    .PARAMETER ScoopRoot
    用户级 scoop 根目录。缺省时取环境变量 SCOOP,未设置时取 HOME 下 scoop 目录。
    如需修复全局安装,请显式传入全局根目录。
    .PARAMETER Discard
    丢弃脏仓库中的本地改动并清理未跟踪文件。缺省不加时执行 stash 保留现场。
    .PARAMETER NoUpdate
    只修复各仓库的 git 状态,跳过收尾的 scoop update。
    .EXAMPLE
    Repair-ScoopUpdate
    定位全部脏仓库并 stash,收尾执行 scoop update。
    .EXAMPLE
    Repair-ScoopUpdate -Discard
    丢弃全部脏仓库的本地改动,收尾执行 scoop update。
    .EXAMPLE
    Repair-ScoopUpdate -NoUpdate -WhatIf
    空跑查看哪些仓库处于脏状态,不改动文件,不执行更新。
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ScoopRoot = '',
        [switch]$Discard,
        [switch]$NoUpdate
    )
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git)
    {
        Write-Warning '未找到 git 命令,请先安装 git 后再执行本函数。'
        return
    }
    if ([string]::IsNullOrEmpty($ScoopRoot))
    {
        if ([string]::IsNullOrEmpty($env:SCOOP))
        {
            $ScoopRoot = Join-Path $HOME 'scoop'
        }
        else
        {
            $ScoopRoot = $env:SCOOP
        }
    }
    if (-not (Test-Path -LiteralPath $ScoopRoot))
    {
        Write-Warning "Scoop 根目录不存在: $ScoopRoot"
        return
    }
    $repos = @()
    $corePath = Join-Path $ScoopRoot 'apps\scoop\current'
    if ((Test-Path -LiteralPath (Join-Path $corePath '.git')))
    {
        $repos += $corePath
    }
    $bucketsPath = Join-Path $ScoopRoot 'buckets'
    if (Test-Path -LiteralPath $bucketsPath)
    {
        $bucketDirs = Get-ChildItem -LiteralPath $bucketsPath -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $bucketDirs)
        {
            if (Test-Path -LiteralPath (Join-Path $dir.FullName '.git'))
            {
                $repos += $dir.FullName
            }
        }
    }
    if ($repos.Count -eq 0)
    {
        Write-Warning "在 $ScoopRoot 下未找到任何 git 仓库(scoop 本体或 bucket)。"
        return
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($repo in $repos)
    {
        $status = & git -C $repo status --porcelain 2>&1
        if ([string]::IsNullOrEmpty("$status".Trim()))
        {
            Write-Verbose "干净: $repo"
            [pscustomobject]@{
                Repository = (Split-Path $repo -Leaf)
                Path       = $repo
                Status     = 'Clean'
                Detail     = ''
            }
            continue
        }
        $detail = ($status | Out-String).Trim()
        Write-Verbose "发现脏仓库: $repo"
        Write-Verbose $detail
        if ($Discard)
        {
            if ($PSCmdlet.ShouldProcess($repo, 'git reset --hard HEAD 并清理未跟踪文件'))
            {
                $resetOut = & git -C $repo reset --hard HEAD 2>&1
                $cleanOut = & git -C $repo clean -fd 2>&1
                $recheck = & git -C $repo status --porcelain 2>&1
                $state = 'Reset'
                if (-not [string]::IsNullOrEmpty("$recheck".Trim()))
                {
                    $state = 'ResetFailed'
                }
                [pscustomobject]@{
                    Repository = (Split-Path $repo -Leaf)
                    Path       = $repo
                    Status     = $state
                    Detail     = (($resetOut, $cleanOut | Out-String).Trim())
                }
            }
        }
        else
        {
            if ($PSCmdlet.ShouldProcess($repo, 'git stash 保留现场'))
            {
                $stashOut = & git -C $repo stash push -u -m "Repair-ScoopUpdate $stamp" 2>&1
                $recheck = & git -C $repo status --porcelain 2>&1
                $state = 'Stashed'
                if (-not [string]::IsNullOrEmpty("$recheck".Trim()))
                {
                    $state = 'StashFailed'
                }
                [pscustomobject]@{
                    Repository = (Split-Path $repo -Leaf)
                    Path       = $repo
                    Status     = $state
                    Detail     = (($stashOut | Out-String).Trim())
                }
            }
        }
    }
    if ($NoUpdate)
    {
        return
    }
    $scoop = Get-Command scoop -ErrorAction SilentlyContinue
    if ($null -eq $scoop)
    {
        Write-Warning 'git 状态已修复,但未找到 scoop 命令,收尾的 scoop update 未执行。'
        return
    }
    if ($PSCmdlet.ShouldProcess('scoop', 'scoop update'))
    {
        scoop update
    }
}
