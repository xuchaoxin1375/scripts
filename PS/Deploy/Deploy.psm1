<# 
.SYNOPSIS
临时部署此模块

Invoke-RestMethod 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy.psm1' | Invoke-Expression
.DESCRIPTION

#如果你懒得添加引号,那么将镜像链接逐个添加到下面的多行字符串中,即便包含了引号或者双引号逗号也都能够正确处理
# 配置一个相对稳定的镜像源(出了源的贡献者,还有可能被 墙,因此还是要定期检查)
#>




function Install-BasicSoftwares
{
    param (
        $Mirror
    )
    New-Item -ItemType 'directory' -Path "$env:USERPROFILE\scoop\buckets\scoop-cn\bucket"
    New-Item -ItemType 'directory' -Path "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\7-zip"
    New-Item -ItemType 'directory' -Path "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git"
    # 7zip软件资源
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/bucket/7zip.json -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\bucket\7zip.json"
    #注册7-zip的右键菜单等操作
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/7-zip/install-context.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\7-zip\install-context.reg"
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/7-zip/uninstall-context.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\7-zip\uninstall-context.reg"
 
    # git软件资源
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/bucket/git.json -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\bucket\git.json"
      
    #注册git右键菜单等操作
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/git/install-context.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git\install-context.reg"
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/git/uninstall-context.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git\uninstall-context.reg"
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/git/install-file-associations.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git\install-file-associations.reg"
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/git/uninstall-file-associations.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git\uninstall-file-associations.reg"
    #注册aria2
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/bucket/aria2.json -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\bucket\aria2.json"
  
    # 安装时注意顺序是 7-Zip, Git, Aria2
    # 基础软件可以考虑全局安装(所有用户可以用,这需要管理员权限)
    scoop install scoop-cn/7zip -g
    scoop install scoop-cn/git -g
    # scoop install scoop-cn/aria2 -g
    
}
function Set-ScoopAria2Options
{
    <# 
    .SYNOPSIS
    设置scoop config文件中的aria2选项
    例如某些下载不允许使用aria2多路下载,那么关闭aria2(aria2对于代理下载不太友好,这边建议下载大文件时采用aria2(手动启用),其他情况直接用scoop下载)
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
 
    # 将 Scoop 的仓库源替换为代理的
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
     
 
    # 将 Scoop 的 main 仓库源替换为代理加速过的
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
function Confirm-GitCommand
{
    <# 
    .SYNOPSIS
    检查当前设备是否可以执行git命令
    如果没有git命令可用,则尝试用scoop安装 git
    .NOTES
    Confirm-GitCommand
    #>
    param(
        [switch]$CheckOnly,
        # [switch]$InstallGitByScoop,
        [switch]$CurrentUser
    )
    $gitCommand = Get-Command -Name git -ErrorAction SilentlyContinue
    if ($gitCommand)
    {
        return $true
    }
    else
    {
        # if ($InstallGitByScoop)
        if (!$CheckOnly)
        {
            $exp = 'scoop install git'
            # 为所有用户安装(默认)
            if (! $CurrentUser)
            {
                $exp = $exp + ' -g'
            }
            Invoke-Expression $exp 
            return
        }
        return $false
    }
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
function Update-GithubHosts
{
    <# 
    .SYNOPSIS
    函数会修改hosts文件，从github520项目获取快速访问的hosts
    .DESCRIPTION
    需要用管理员权限运行
    原项目提供了bash脚本,这里补充一个powershell版本的,这样就不需要打开git-bash
    .Notes
    与函数配套的,还有一个Deploy-githubHostsAutoUpdater,它可以向系统注册一个按时执行此脚本的自动任务(可能要管理员权限运行),可以用来自动更新hosts
    .NOTES
    可以将本函数放到powershell模块中,也可以当做单独的脚本运行
    .LINK
    https://github.com/521xueweihan/GitHub520
    .LINK
    https://gitee.com/xuchaoxin1375/scripts/tree/main/PS/Deploy

    #>
    <# 
    .EXAMPLE
    
# GitHub520 Host Start
140.82.112.26                 alive.github.com
172.18.0.2                    api.github.com
...
185.199.111.133               private-user-images.githubusercontent.com


# Update time: 2025-02-02T21:59:11+08:00
# Update url: https://raw.hellogithub.com/hosts
# Star me: https://github.com/521xueweihan/GitHub520
# GitHub520 Host End
    #>
    [CmdletBinding()]
    param (
        # 可以使用通用的powershell参数(-verbose)查看运行细节
        $hosts = 'C:\Windows\System32\drivers\etc\hosts',
        $remote = 'https://raw.hellogithub.com/hosts'
    )
    # 创建临时文件
    # $tempHosts = New-TemporaryFile

    # 定义 hosts 文件路径和远程 URL

    # 定义正则表达式
    $pattern = '(?s)# GitHub520 Host Start.*?# GitHub520 Host End'


    # 读取 hosts 文件并删除指定内容,再追加新内容
    # $content = (Get-Content $hosts) 
    $content = Get-Content -Raw -Path $hosts
    # Write-Host $content
    #debug 检查将要替换的内容

    #查看将要被替换的内容片段是否正确
    # $content -match $pattern
    $res = [regex]::Match($content, $pattern)
    Write-Verbose '----start----'
    Write-Verbose $res[0].Value
    Write-Verbose '----end----'

    # return 
    $content = $content -replace $pattern, ''

    # 追加新内容到$tempHosts文件中
    # $content | Set-Content $tempHosts
    #也可以这样写:
    #$content | >> $tempHosts 

    # 下载远程内容并追加到临时文件
    # $NewHosts = New-TemporaryFile
    $New = Invoke-WebRequest -Uri $remote -UseBasicParsing #New是一个网络对象而不是字符串
    $New = $New.ToString() #清理头信息
    #移除结尾多余的空行,避免随着更新,hosts文件中的内容有大量的空行残留
       
    # 将内容覆盖添加到 hosts 文件 (需要管理员权限)
    # $content > $hosts
    $content.TrimEnd() > $hosts
    ''>> $hosts #使用>>会引入一个换行符(设计实验:$s='123',$s > example;$s >> example就可以看出引入的换行),
    # 这里的策略是强控,即无论之前Github520的内容和前面的内容之间隔了多少个空格,
    # 这里总是移除多余(全部)空行,然后手动插入一个空行,再追加新内容(Gith520 hosts)
    $New.Trim() >> $hosts

    
    Write-Verbose $($content + $NewContent)
    # 刷新配置
    ipconfig /flushdns
    
}
function Deploy-GithubHostsAutoUpdater
{
    <# 
    .SYNOPSIS
    向系统注册自动更新GithubHosts的计划任务
    .NOTES
    支持powershell 5+
    依赖于在线仓库,会下载相关脚本,开机运行
    #>
    param (
    )
    Invoke-RestMethod https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/GithubHostsUpdater/Register-GithubHostsAutoUpdater.ps1 | Invoke-Expression

    
}
function Deploy-GithubHostsAutoUpdater-Deprecated
{
    <# 
    .SYNOPSIS
    向系统注册自动更新GithubHosts的计划任务(本函数由于计划任务限制,需要在用户级别环境运行,会定时闪现一个窗口,影响使用体验)
    如果需要支持powershell 5+,使用单独文件部署,可以在用户登陆桌面前运行,效果更好
    .DESCRIPTION
    如果需要修改触发器，可以自行在源代码内调整，或者参考Microsoft相关文档；也可以使用taskschd.msc 图形界面来创建或修改计划任务
    .Notes
    仅支持powershell7+以上版本,如果你只有powershellv5并且不想升级powershell7,则考虑独立的部署版本
    兼容powershell5和powershell7的以归档版本不在维护,此目录是"$PSScriptRoot\GithubHostsUpdater",该目录下有说明
    .Notes
    移除计划任务：
    unregister-ScheduledTask -TaskName  Update-GithubHosts
    .Notes
    自动任务可能被经用,请用管理员权限在shell命令行中启用任务,然后执行配置和信息查询等操作
    PS> enable-scheduledtask -TaskName Update-GithubHosts -Verbose
    Enable-ScheduledTask: 拒绝访问。

    PS🌙[BAT:98%][MEM:54.87% (8.43/15.37)GB][12:27:17]
    # [cxxu@BEFEIXIAOXINLAP][<W:192.168.1.77>][~\Desktop]
    PS> sudo pwsh
    PowerShell 7.4.5
    Setting basic environment in current shell...
    Loading personal and system profiles took 925ms.

    PS🌙[BAT:98%][MEM:54.87% (8.43/15.37)GB][12:27:25]
    #⚡️[cxxu@BEFEIXIAOXINLAP][<W:192.168.1.77>][~\Desktop]
    PS> enable-scheduledtask -TaskName Update-GithubHosts -Verbose

    TaskPath                                       TaskName
    --------                                       --------
    \                                              Update-GithubHosts
    #>
    [CmdletBinding()]
    param (
        
        # [ValidateSet('pwsh', 'powershell')]$shell = 'powershell',
        $shell = 'pwsh', #此函数为pwsh设计(powershell v5不可用)
        
        # 需要执行的更新脚本位置(这个参数在不常用,采用直接通过pwsh调用指定函数的方式执行任务)
        $File = '' , #自行指定
        $TaskName = 'Update-GithubHosts',
        #其中 $ActionFunction 代表要执行的更新任务,是自动导入可执行的函数
        $ActionFunction = 'Update-GithubHosts',
        [alias('Comment')]$Description = "Task Create Time: $(Get-Date -Format 'yyyyMMddHHmmss')"
    )
    $continue = Confirm-PsVersion -Major 7 #检查powershell版本
    if (! $continue) { return $false }
    # 检查参数情况
    Write-Verbose 'Checking parameters ...'
    $PSBoundParameters | Format-Table   

    # 开始注册
    Write-Host 'Registering...'
    # Start-Sleep 3
    # 定义计划任务的基本属性
    # if (! $File)
    # {
    
    #     $File = "$PSScriptRoot\GithubHostsUpdater\fetch-github-hosts.ps1" #自行修改为你的脚本保存目录(我将其放在powershell模块中,可以用$PSScriptRoot来指定目录)
       
    #     # $File = 'C:\repos\scripts\PS\Deploy\fetch-github-hosts.ps1' #这是绝对路径的例子(注意文件名到底是横杠（-)还是下划线(_)需要分清楚
    # }

    $action = New-ScheduledTaskAction -Execute $shell -Argument " -ExecutionPolicy ByPass  -WindowStyle Hidden -c $ActionFunction" 
    # 定义两个触发器
    $trigger1 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
    $trigger2 = New-ScheduledTaskTrigger -AtStartup
    # 任务执行角色设置 #尝试以管理与组的方式指定UserId
    $principal = New-ScheduledTaskPrincipal -UserId "$env:UserName" -LogonType ServiceAccount -RunLevel Highest
    # 这里的-UserId 可以指定创建者;但是注意,任务创建完毕后,不一定能够立即看Author(创建者)字段的信息,需要过一段时间才可以看到,包括taskschd.msc也是一样存在滞后
    # $principal = New-ScheduledTaskPrincipal -UserId $env:UserName -LogonType ServiceAccount -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    # 创建计划任务
    Register-ScheduledTask -TaskName $TaskName -Action $action `
        -Trigger $trigger1, $trigger2 -Settings $settings -Principal $principal -Description $Description
    # 立即执行(初次)
    Write-Host 'Try to start ScheduledTask First time...'
    # Start-ScheduledTask -TaskName $TaskName #初次启动相应的任务
    Start-ScheduledTask -TaskName Update-Githubhosts

    #检查部署效果
    Start-Sleep 5 #等待5秒钟，让更新操作完成
    # 检查hosts文件修改情况(上一次更改时间)
    $hosts = 'C:\Windows\System32\drivers\etc\hosts'
    Get-ChildItem $hosts | Select-Object LastWriteTime #查看hosts文件更新时间(最有一次写入时间),文件内部的更新时间是hosts列表更新时间而不是文件更新时间
    Get-Content $hosts | Select-Object -Last 5 #查看hosts文件的最后5行信息
    Notepad $hosts # 外部打开记事本查看整个hosts文件
}


function Deploy-LinksFromFile
{
    <# 
    .SYNOPSIS
    从文件中创建符号链接,恢复到指定目录(比如家目录)
    .DESCRIPTION
    为了提高成功率,建议你创建另一个本地管理员用户maintainer,然后注销当前用户,切换到另一个用户中执行本函数
    .EXAMPLE
     Deploy-LinksFromFile -Path C:\repos\scripts\PS\Deploy\confs\HomeLinks.conf -DirectoryOfLinksToSave C:\users\cxxu -DirectoryTargetSource D:\users\cxxu\
    #>
    param (
        #配置文件:记录需要创建链接的符号,比如downloads,documents,scoop,vscode,....
        [Alias('BackupFile')]$Path  ,

        # 需要将符号链接创建或者恢复到的目录,比如'C:\users\cxxu'
        $DirectoryOfLinksToSave = "$home",
        #例如 "D:\users\$env:UserName"
        #指定要链接的Target目标存在于哪个目录
        [parameter(Mandatory = $true)]
        $DirectoryTargetSource 
    )
    # 遍历每一行
    Get-Content $Path | ForEach-Object {
        $Path = "$DirectoryOfLinksToSave\$_"
        $Target = "$DirectoryTargetSource\$_"
        if (! $_.StartsWith('#') -and $_.Trim() )
        {
            # write-host $Path
            
            Backup-IfNeed -Path $Path
            
            $script = "New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force -Verbose"
            # Write-Host $script
            $script | Invoke-Expression
        }
    }
}


function Deploy-Python
{
    New-Junction -Path $env:APPDATA\python -Target $env:pythonPacks_Home_Conv
}
# function Deploy-vscodeDoubleSystem{

# }
function Backup-IfNeed
{
    <# 
    .SYNOPSIS
    通过重命名来起到备份的作用，如果原路径存在，则备份(重命名)，否则不做任何操作
    #>
    param (
        $Path,
        $Destination = '.',
        # 为了提高容错率，可以设置为（ `@${Get-Date -format 'yyyy-MM-dd--HH-mm-ss}' )
        $BackupExtension = 'bak' + "`@$(Get-Date -Format 'yyyy-MM-dd--HH-mm-ss')"
    )
     
    
    #备份(如果需要的话)
    if (Test-Path $path)
    {
        $Path = Get-PsIOItemInfo $path
        $Path = $Path.FullName.trim('\')
    
        $backup = "${Path}.${BackupExtension}"
        Write-Host 'origin path exist! try do the backup!'
        # 如果原路径存在,则备份(重命名)
        Rename-Item -Path $path -NewName $backup -Force -Verbose
    }
    else
    {
        Write-Host 'Path does not exist!'
    }
    
}
function Deploy-Userconfig
{
    param (
    )
    
    Update-PwshEnvIfNotYet -Mode Vars

    $path = "$home\.config"
    $Destination = "$configs\user\.config"
    Backup-IfNeed -Path $path
    if (Test-Path $Destination)
    {

        New-Item -ItemType SymbolicLink -Path $path -Target $Destination -Force -Verbose 
    }
    else
    {
        Write-Verbose "$Destination does not exist!,pass it!"
    }
}
function Deploy-UserConfigFromAnotherDrive
{
    <# 
    .SYNOPSIS
    部署家目录中常用目录，适用于双系统跨盘创建符号链接的情况

    #>
    param (
        $ConfigList = '',
        $r = 'C', #一般是C盘,但允许更改
        $s = 'D' , #可以做必要的修改,比如E盘
        $UserName = "$env:UserName" #修改此值为你需要修改的用户家目录名字(一般是用户名)
    )
    if (! $ConfigList  )
    {
        
        $ConfigList = @(
            'documents\powershell',
            'scoop',
            '.config'
        )
    }
    $UserHome = "${r}:\users\$UserName"
    $TargetUserHome = "${s}:\Users\$UserName"
    foreach ($origin in $ConfigList)
    {
        $p = "$userhome\$origin"
        $b = "$userhome\${origin}.bak"
        $t = "$targetuserhome\$origin"
        Write-Host "$p;$b;$t"
        #备份(如果需要的话)
        if (Test-Path $p)
        {
            Write-Host 'origin path exist! try do the backup!'
            # 如果原路径存在,则备份(重命名)
            Rename-Item -Path $p -NewName $b -Force
        }
        else
        {
            Write-Host 'Origin path: '+$origin+' does not exist,Create the symbolic link directly!'
        }
        # 创建符号链接
        New-Item -ItemType SymbolicLink -Path $p -target $t -Force
    }

    
}
function Deploy-CppVscodeThere
{
    param(
        $path = '.vscode'
    )
    if (!(Test-Path '.vscode'))
    {
        # Get-ChildItem $configs\CppVscodeConfig\
        mkdir .vscode
        
    }
    cpFVR $configs\CppVscodeConfig\* .vscode
    Write-SeparatorLine
    Write-Output "@path=$path"

}
function Deploy-FirewallByNetsh
{
    netsh advfirewall firewall add rule dir=out action=block program="C:\Program Files\Mozilla Firefox\firefox.exe" name="blockFirefox" description="createByNetsh" enable=yes
    netsh advfirewall firewall add rule dir=out action=block program="$360zip_home\360zip.exe" name="block360zip" description="createByNetsh" enable=yes

}

function Deploy-PicgoConfig
{
    Write-Output 'for CLI part'
    cpFVR $configs\PicgoConfigs\* $env:picgo_CLI_config
    Write-Output 'for GUI part'
    cpFVR $configs\PicgoConfigs\* $env:picgo_conf
}
function Deploy-PicgoGUI
{
    cpFVR
}
function Deploy-AndroidStudio_depends
{
    param (
        
    )
    Write-Output "gradle_user_home `\n; androidDepends"
    # if (Test-Path $env:androidDepends)
}




function Confirm-AdminPermission
{
    <# 
    .SYNOPSIS
    确保当前shell拥有管理员权限，如果没有，则抛出异常；如果有，则什么都不做
    .DESCRIPTION
    利用抛出异常,来停止调用此函数在权限不足时执行后续的逻辑(打断执行)
    #>
    param (
    )
    if (! (Test-AdminPermission))
    {
        throw 'You need to have Administrator rights to run it.'
    
    }
     
}
function Deploy-Typora
{
    <# 
    .SYNOPSIS
    导入部分typora配置
    .DESCRIPTION
    部署typora:包括主题以及快捷键配置导入
    可选的老版本typora破解补丁打入
    可选设置markdown文件的默认打开方式(调用assoc和ftype命令进行设置,这会改动注册表)


    .Parameter TyporaHome
    指定typora安装目录
    .Parameter InstalledByScoop
    指定typora是否是通过scoop安装的,否则检查默认安装目录
    .Notes
    可能需要管理员权限运行
    细节设置(自动保存,关闭语法检查,选择指定主题等不会还原需要手动选择)
    .Notes
    部署需要在具有pwshEnv环境的命令行下执行,否则会先导入环境变量,然后进行下一步
    如果使用的版本是已经自带激活的,就可以不使用PatchWinmm开关导入补丁,避免多余的副作用
    .Notes
    较新版本的typroa设置选项中提供了资源管理器右键菜单选项,可以右键新建markdown文件(md)
    https://support.typora.io/New-File-in-Context/
    typora安装版可能会注册打开方式:
        Typora.markdown="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.md="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.mdown="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.mkd="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.mmd="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.text="C:\Program Files\Typora\Typora.exe" "%1"

    有的魔改版本提供了注册了格式关联,右键菜单打开方式的bat脚本
    但是注意,如果是用户创建的通过typora打开指定目录的快捷方式
    (这里头的打开方式已经被写死在快捷方式的属性中,不会受markdown本体打开方式设置的影响),
    尤其是对于安装了多个不同版本的typora的环境下

    .EXAMPLE
    为通过scoop安装的typora进行部署
    Deploy-Typora -TyporaHome $scoop_home\apps\typora\current
    #>
    param(
        [switch]$InstalledByScoop,
        $TyporaHome = "$scoop_home\apps\typora\current",
        $Typora_Config = "$home\AppData\Roaming\typora\conf",
        [switch]$PatchWinmm,
        [swithc]$OpenWithTypora
    )


    Update-PwshEnvIfNotYet
    Confirm-AdminPermission

    # Write-Host 'close the typora to apply the settings!'
        
    # check any typora process to kill
    

    if (Get-Process -Name 'typora' -ErrorAction SilentlyContinue)
    {
        Write-Host "The process 'typora' exists."
        $reply = Read-Host -Prompt "press enter 'y' to continue"

        if ($reply -eq 'y')
        {

            Stop-Process -Name 'typora'
        
        }
        else
        {
            Write-Host 'The operation canceled!'
            return
        }
    }
    else
    {
        Write-Host "The process 'typora' does not exist."
    }
    
    Write-Host 'continue to deploy...' -BackgroundColor Yellow

    # 开始建立链接(使用symboliclink支持跨分区的链接文件夹和文件通吃)

    # 设置注册.md扩展名为文件类型MarkdownFile
    # 这里的.md是标准markdown文件的扩展名,而MarkdownFile是可以宽松自定义的名字，也可以是别的名字,但是要注意在后面的ftype命令中使用同一个文件类型名字
    cmd /c assoc .md=MarkdownFile 


    # 注册Markdown文件的打开方式(其中MarkdownFile是上面assoc命令设置的文件类型名)🎈
    # 这个命令不会设置默认打开方式,只是注册了打开方式,除非此前没有其他程序注册打开方式
    if($OpenWithTypora)
    {

        cmd /c ftype MarkdownFile=$TyporaHome\Typora.exe %1 
        # 如果要取消,可以使用下面的命令:(=后面留空即可),但是可能不会完全取消,需要检查是否有同地位的注册语句关联相同后缀,设置后可以用新的值覆盖
        cmd /c ftype MarkdownFile= 

    }

    $items = @($Typora_Themes , $Typora_Config)
    # 移除原有的相关目录,以便能够创建新的符号链接
    $items | ForEach-Object {
        
        Remove-Item -Path $_ -Recurse -Force -Verbose
    } 
    # 按照原来的位置创建新的符号链接
    # $items | ForEach-Object {
    # } 
    New-Item -ItemType SymbolicLink -Path $Typora_Themes -Target $Typora_Themes_backup -Force -Verbose
    New-Item -ItemType SymbolicLink -Path $Typora_Config -Target $Typora_Config_backup -Force -Verbose
        
    # New-Item -ItemType SymbolicLink -Path $Typora_Config -Target $Typora_Config_backup -Force -Verbose
    if($PatchWinmm)
    {
            
        $winmm = "$TyporaHome\winmm.dll"
        $patcher = "$configs\typora\winmm.dll"
        # 打入破解补丁(替换winmm.dll)不一定对所有版本通用(最高1.9.5)
        New-Item -ItemType SymbolicLink -Path $winmm -Value $patcher -Force
    }

    
    $Note = @'
    The basic settings need you to manually set(the config.json just provide the advanced part settings
         the themes settings need you to chose manually , too; 
         It will be provide in the appearance->themes dropdown
    just set the preference->markdown->math formula checkboxes!
         after that , restart the typora to apply the settings!
'@
    Write-Host $Note -ForegroundColor Magenta
}
#下面这三个+ 函数是用来启用网络共享和网络发现的并部署带有使用说明文档的共享文件夹
#还需要外部的一个Grant-PermissionToPath函数

function Deploy-RestartExplorerHotkey
{
    [CmdletBinding()]
    param (
        $path = 'Restart-Explorer-KeyLauncher.lnk',
        $Hotkey = 'Ctrl+Alt+F10',
        [switch]$Activate
    )
    Update-PwshEnvIfNotYet

    $path = "$Desktop/$path"
    
    $expression = @'
    New-Shortcut -Path $path -TargetPath "$windowspowershell_home/powershell.exe" -Arguments "-executionpolicy bypass  -file $scripts\windows\restart-explorer.ps1" -HotKey $Hotkey -Force
'@ 
    Write-Verbose $expression
    Invoke-Expression $expression
    
    if ($Activate)
    {
        Write-Host 'Try to Active the Script For The First Time Use!'
        Start-Sleep 2
        & $path
    }
    
    
}
#一键部署局域网内smb共享文件夹
# 本模块包含其中的4个函数,另一个函数是权限设定函数,Grant-PermissionToPath
function Enable-NetworkDiscoveyAndSharing
{
    <# 
    .SYNOPSIS
    启用共享文件夹和网络发现
    这里通过防火墙设置来实现,可以指定中英文系统语言再执行防火墙设置
    .EXAMPLE
    PS C:\> Enable-NetworkDiscoveyAndSharing
    No rules match the specified criteria.
    No rules match the specified criteria.
    Updated 30 rule(s).
    Ok.
    Updated 62 rule(s).
    Ok.
    PS C:\> Enable-NetworkDiscoveyAndSharing -Language Chinese
    No rules match the specified criteria.
    No rules match the specified criteria.
    PS C:\> Enable-NetworkDiscoveyAndSharing -Language English
    Updated 30 rule(s).
    Ok.
    Updated 62 rule(s).
    Ok.
    #>
    param (
        [validateset('Chinese', 'English', 'Default')]$Language = 'Default'
    )
    #对于中文系统
    $c = { netsh advfirewall firewall set rule group="文件和打印机共享" new enable=Yes
        netsh advfirewall firewall set rule group="网络发现" new enable=Yes }
    #对于英文系统
    $e = { netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes
        netsh advfirewall firewall set rule group="Network Discovery" new enable=Yes }
    switch ($Language)
    {
        'Chinese' { & $c ; break }
        'English' { & $e ; break }
        default { & $c; & $e }
    }
}
function New-SmbSharingReadme
{
    <# 
    .SYNOPSIS
    创建共享文件夹说明文件,一般不单独使用,请把此函数当作片段,需要在其他脚本或函数内部调用以填充字符串内部的变量
    .DESCRIPTION
    下面的分段字符串内引用了此函数没有定义的变量
    而在配合其他函数(Deploy-Smbsharing内部调用)则是可以访问Deploy-SmbSharing内部定义的局部变量
    因此这里无需将变量搬动到这里来,甚至可以放空
    #>
    param (
        # 也可以把这组参数复制到Deploy-Smbsharing内部,而在这里设置为空, 在Deploy-SmbSharing 内部以显式传参的方式调用此函数;
        $readmeFile = "$Path\readme.txt",
        $readmeFileZh = "$Path\readme_zh-cn(本共享文件夹使用说明).txt"
    )
    # 创建说明文件(默认为英文说明)
    @'
Files,folders,and links(symbolicLinks,JunctionLinks,HardLinks are supported to be shared )
Others' can modify and read contents in the folder by defualt,you can change it 

The Default UserName and password to Access Smb Sharing folder is :
'@+
    @"
Server(ComputerName): $env:COMPUTERNAME 
UserName: $smbUser
Password: $SmbUserKey

(if Server(ComputerName) is not available, please use IP address(use `ipconfig` to check))

"@+ 
    @"
The Permission of this user is : $Permission (one of Read,Change,Full)

"@+ 
    @'

You can consider using the other sharing solutions such as CHFS,Alist,TfCenter
These softwares support convenient http and webdav sharing solutions;
Especially Alist, which supports comprehensive access control permissions and cloud disk mounting functions
This means that Users have no need to install other softwares which support smb protocol,just a web browser is enough.

See more detail in https://docs.microsoft.com/en-us/powershell/module/smbshare/new-smbshare
'@ > "$readmeFile"


    #添加中文说明
    @'
支持共享文件、文件夹以及链接（包括符号链接、联合链接和硬链接）。
默认情况下，其他人可以修改和读取文件夹中的内容，您可以更改此设置。

访问 SMB 共享文件夹的默认用户名和密码是：

'@+
    @"
Server(ComputerName): $env:COMPUTERNAME 
用户名: $smbUser
密码: $SmbUserKey

（如果服务器主机名（ComputerName）不可用，请使用IP地址（使用ipconfig检查））

"@+ 
    @"
该用户的权限是：$Permission （可选权限有：Read,Change,Full）

"@+ 
    @'
您可以考虑使用其他共享解决方案，如 CHFS、Alist、TfCenter，
这些软件支持便捷的 HTTP 和 WebDAV 共享方案，尤其是Alist,支持完善的访问控制权限和网盘挂载功能
这意味着用户无需安装支持 SMB 协议的其他软件，仅需一个网络浏览器即可。

更多信息请参阅 https://docs.microsoft.com/zh-cn/powershell/module/smbshare/new-smbshare
'@ > "$readmeFileZh"

}

function Deploy-SmbSharing
{
    <# 
    .SYNOPSIS
    #功能:快速创建一个可用的共享文件夹,能够让局域网内的用户访问您的共享文件夹
    # 使用前提要求:需要使用管理员权限窗口运行powershell命令行窗口
    
    .DESCRIPTION
    如果这个目录将SmbUser的某个权限(比如读/写)设置为Deny，那么纵使设置为FullControl,也会被Deny的项覆盖,SmbUser就会确实相应的权限,甚至无法访问),
    因此,这里会打印出来目录的NTFS权限供用户判断是否设置了Deny
    反之,如果某个用户User1处于不同组内,比如G1,G2组,分别有读权限和写权限,那么最终User1会同时具有读/写权限,除非里面有一个组设置了Deny选项
    注意:没有显式地授予某个组的某个权限不同于设置Deny

    一个思路是新建一个SMB组,设置其拥有对被共享文件夹的权限,然后新建一个目录将其加入到SMB组中
    .EXAMPLE
    #不创建新用户来用于访问Smb共享文件夹,指定C:\share1作为共享文件夹,其余参数保持默认
    PS C:\> Deploy-SmbSharing -Path C:\share1 -NoNewUserForSmb
    .EXAMPLE
    # 指定共享名称为ShareDemo，其他参数默认:共享目录为C:\Share，权限为Change，用户为ShareUser，密码为1
    PS> Deploy-SmbSharing -ShareName ShareDemo -SmbUser ShareUser -SmbUserkey 1
    .EXAMPLE
    完整运行过程(逃过次要信息)
    使用强制Force参数修改被共享文件夹的权限(默认为任意用户完全控制,如果需要进一步控制,需要开放更多参数,为了简单起见,这里就默认选项)
    PS C:\> Deploy-SmbSharing -Path C:\share -SmbUser smb2 -SmbUserkey 1 -Force

    No rules match the specified criteria.
    No rules match the specified criteria.
    Updated 30 rule(s).
    Ok.
    Updated 62 rule(s).
    Ok.
    文件夹已存在：C:\share
    Share name        Share
    Path              C:\share
    Remark
    Maximum users     No limit
    Users
    Caching           Manual caching of documents
    Permission        Everyone, CHANGE

    The command completed successfully.

    The command completed successfully.

    已成功将'C:\share'的访问权限设置为允许任何人具有全部权限。
    Name  ScopeName Path     Description
    ----  --------- ----     -----------
    Share *         C:\share
    共享已创建：Share
    共享专用用户已创建：smb2
    True
...
    True
    已为用户 smb2 设置文件夹权限


    PSPath                  : Microsoft.PowerShell.Core\FileSystem::C:\share
  ...
    CentralAccessPolicyId   :
    Path                    : Microsoft.PowerShell.Core\FileSystem::C:\share
    Owner                   : CXXUCOLORFUL\cxxu
    Group                   : CXXUCOLORFUL\None
    Access                  : {System.Security.AccessControl.FileSystemAccessRule}
    Sddl                    : O:S-1-5-21-1150093504-2233723087-916622917-1001G:S-1-5-21-1150093504-22337230
                            87-916622917-513D:PAI(A;OICI;FA;;;WD)
    AccessToString          : Everyone Allow  FullControl
    AuditToString           :

    .NOTES
    访问方式共享文件夹的方式参考其他资料 https://cxxu1375.blog.csdn.net/article/details/140139320
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        
        # 定义共享文件夹路径和共享名称
        $Path = 'C:\Share',
        $ShareName = 'Share',
        [ValidateSet('Read', 'Change', 'Full')]$Permission = 'Change', #合法的值有:Read,Change,Full 权限从低到高 分别是只读(Read),可读可写(change),完全控制(full)

        #指定是否不创建新用户(仅使用已有用户凭证访问smb文件)
        # 这里的Mandatory=$true不能轻易移除,本函数用了参数集,并且基本上都用默认参数来使配置更简单;
        # 为了让powershell能够在不提供参数的情况下分辨我们调用的是哪个参数集，这里使用了Mandatory=$true来指定一个必须显式传递的参数,让函数能够不提供参数可调用
        [parameter(Mandatory = $true , ParameterSetName = 'NoNewUser')]
        [switch]$NoNewUserForSmb,

        # [parameter(ParameterSetName = 'SmbUser')]
        # [switch]$NewUserForSmb,

        # 指定专门用来访问共享文件夹的用户(这不是必须的,您可以用自己的用户和密码,但是不适合把自己的私人账户密码给别人访问,所以推荐建立一个专门的用户角色用于访问共享文件夹)
        [parameter(ParameterSetName = 'SmbUser')]
        $SmbUser = 'Smb', #如果本地已经有该用户，那么建议改名
        #密码可以改,但是建议尽可能简单,默认为1(为了符合函数设计的安全规范,这里不设置明文默认密码)
        [parameter(ParameterSetName = 'SmbUser')]
        $SmbUserkey = '1',
        [switch]$AllowSmbUserLogonDesktop,
        # 设置宽松的NTFS权限(但是仍然不一定会生效),如果可以用,尽量不要用Force选项
        [switch]$Force
    )
    #启用文件共享功能以及网络发现功能(后者是为了方便我们免ip访问,不是必须的)
    # $ConfirmPreference='High'
    $continue = $PSCmdlet.ShouldProcess("$env:USERNAME`@$env:ComputerName", ('Enable file sharing and discovery' + "`t smbDiscovery:${Path};`t smbUser:${SmbUser};`t smbUserkey:${SmbUserkey}"))
    if (!$continue)
    {
        help Deploy-SmbSharing -Full
        Get-Command Deploy-SmbSharing -Syntax
        return 'User Cancel the operation!'
    }
    # $ConfirmPreference='Medium'
    Enable-NetworkDiscoveyAndSharing

    # 检查文件夹是否存在，如果不存在则创建
    if (-not (Test-Path -Path $Path))
    {
        New-Item -ItemType Directory -Path $Path
        Write-Output "文件夹已创建：$Path"
    }
    else
    {
        Write-Output "文件夹已存在：$Path"
    }

    # 创建共享
    # New-SmbShare -Name $ShareName -Path $Path -FullAccess Everyone
    # 创建共享文件夹(允许任何(带有凭证的)人访问此共享文件夹)
    "New-SmbShare -Name $ShareName -Path $Path -${Permission}Access 'Everyone'" | Invoke-Expression #这里赋予任意用户修改权限(包含了可读权限和修改权限)
    Write-Output "共享已创建：$ShareName"

    #显示刚才创建的(或者已有的)$ShareName共享信息
    net share $ShareName #需要管理员权限才可以看到完整信息

    if ($PSCmdlet.ParameterSetName -eq 'SmbUser'  )
    {

        $res = glu -Name "$SmbUser" -ErrorAction Ignore
        if (! $res)
        {
            # 定义新用户的用户名和密码
            $username = $SmbUser

            # 创建新用户(为了规范起见,最好在使用本地安全策略将Smb共享账户设置为禁止本地登录(加入本地登录黑名单,详情另见它文,这个步骤难以脚本化)这里尝试使用Disable-SmbSharingUserLogonLocallyRight函数来实现此策略设置)
            net user $username $SmbUserKey /add /fullname:"Shared Folder User" /comment:"User for accessing shared folder" /expires:never 
            Set-LocalUser -PasswordNeverExpires $true -Name $username #设置账户的密码永不过期
            # 由于New-LocalUser在不同windows平台上可能执行失败,所以这里用net user,而不是用New-LocalUser
            # New-LocalUser -Name $username -Password $SmbUserKey -FullName 'Shared Folder User' -Description 'User for accessing shared folder'
            # 将新用户添加到Smb共享文件夹的用户组,这不是必须的(默认是没有SMB组的)
            # Add-LocalGroupMember -Group 'SMB' -Member $username
            Write-Output "共享专用用户已创建：$username"
        }
        else
        {
            Write-Error '您指定的用户名已经被占用,更换用户名或者使用已有的账户而不再创建新用户'
            return
        }
    }
    else
    {
        Write-Host '您未选择创建专门用于访问Smb共享文件夹的用户,请使用已有的用户账户及密码(不是pin码)作为访问凭证' -ForegroundColor cyan
    }
    if ($force)
    {
        # 设置共享文件夹权限(NTFS权限)
        Grant-PermissionToPath -Path $Path -ClearExistingRules
        Write-Output "已为用户 $username 设置文件夹权限"
    }
    # 查看目录的权限列表,如果需要进一步确认,使用windows自带的effective Access 查看
    Get-Acl $Path | Format-List *

    # 创建Smb共享文件夹的README
    New-SmbSharingReadme
    if (!$AllowSmbUserLogonDesktop)
    {
        Disable-SmbSharingUserLogonLocallyRight -SmbUser $SmbUser
    }
    else
    {
        Write-Warning "The Smb User is allowed to logon windows desktop locally!(for security reason, it is not recommended to allow this)"
    }
}

function Disable-SmbSharingUserLogonLocallyRight
{
    <# 
    .SYNOPSIS
    使用管理员权限运行函数
    #>
    param (
        $SmbUser,
        $WorkingDirectory = 'C:/tmp'
    )
    if (!(Test-Path $WorkingDirectory ))
    {

        New-Item -ItemType Directory -Path $WorkingDirectory -Force -Verbose
    }
    $path = Get-Location
    Set-Location $WorkingDirectory

    Write-Host 'setting Smb User Logon Locally Right' -ForegroundColor cyan
    # 添加用户到拒绝本地登录策略
    secedit /export /cfg secconfig.cfg
    #修改拒绝本地登陆的项目,注意$smbUser变量的取值,依赖于之前的设置,或者在这里重新设置
    $smbUser = 'smb'#如果和你的设定用户名不同,则需要重新设置

    (Get-Content secconfig.cfg) -replace 'SeDenyInteractiveLogonRight = ', "SeDenyInteractiveLogonRight =$smbUser," | Set-Content secconfig.cfg
 
    secedit /configure /db secedit.sdb /cfg secconfig.cfg > $null
    #上面这个语句可能会提示你设置过程中遇到错误,但是我检查发现其成功设置了响应的策略,您可以重启secpol.msc程序来查看响应的设置是否更新,或者检查切换用户时列表中会不会出现smbUser选项
    Remove-Item secconfig.cfg #移除临时使用的配置文件
    Set-Location $path
}

#部署gitconfig
function Deploy-GitConfig
{
    <# 
    .SYNOPSIS
    使用hardlink强制将git配置文件用$configs中的配置取代
    #>
    Update-PwshEnvIfNotYet -Mode Vars
    # 使用硬链接会有权限问题,这里用复制文件的方式代替
    $t = "$configs\user\.gitconfig"
    $p = "$home\.gitconfig"
    # Copy-Item $t $p -Force -Verbose
    # 使用符号链接支持跨分区
    New-Item -ItemType SymbolicLink -Path $p -Value $t -Verbose -Force
}
function Deploy-VsCodeSettings_depends
{
    <# redifine the extensions path to D district #>
    if (!([Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544'))
    {

        Write-Output 'current powershell run without administrator privilege!;请手动打开管理模式的terminal.'
        return
    }
    if (Test-Path $env:vscode_Depends)
    {
        Write-Output 'you run the script after vscode have been installed!,this will remote the old home to create the coresponding symbolic link!'
        Remove-Item $env:vscode_Depends
    }
    Write-Output 'pre-set the directory as a symbolic link to D partition.. '
    Write-Output 'sleep for 3 senconds for you to think of it whether to stop...'
    # when you debug,you can set the time longer(such as 10 seconds)
    countdown 10
    Write-Output "repointer the software location:$env:vscode_home->$env:vscode_Home_D "
    New-Junction $env:vscode_home $env:vscode_Home_D
    # assure the New-Junction could run successfully
    Write-Output "New-Junction $env:vscode_Depends $env:vscode_Depends_D"
    if (
        !(Test-Path $env:vscode_Depends_D)
    )
    {
        # 读取键盘输入(read input by read-host)
        $Inquery = Read-Host -Prompt "there is not $env:vscode_Depends_D ; to create the corresponding directory, enter 'y' to continue😎('N' to exit the process!)  "
        if ($Inquery -eq 'y')
        {
            mkdir $env:vscode_Depends_D
        }
        else
        {
            return
        }
    }
        
    New-Junction $env:vscode_Depends $env:vscode_Depends_D
    #deploy the settings
    cpFVR $configs\vscodeSettings\* $env:vscodeConfHome
}

function Deploy-WtSettings
{
    <# 
    .Notes
    PS [C:\repos\scripts]> gv wt*

    Name                           Value
    ----                           -----
    wtConf_Home                    C:\Users\cxxu\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalEnabled
    wtConf_Home_Pattern            C:\Users\cxxu\AppData\Local\Packages\Microsoft.WindowsTerminal_*\LocalEnabled
    wtPortableConf_Home            C:\Users\cxxu\AppData\Local\Microsoft\Windows Terminal
    wtStoreConf_Home_Pattern       C:\Users\cxxu\AppData\Local\Packages\Microsoft.WindowsTerminal_*\LocalEnabled
    #>
    [CmdletBinding()]
    param(
        #指定是否为免安装版本的windows terminal
        # $Portable = '' 
        [switch]$Portable,
        [switch]$InstalledByScoop,
        $WtScoopConfig = "$scoop_global\apps\windows-terminal\current\settings\settings.json",
        [switch]$Force
    )
    Update-PwshEnvIfNotYet -Mode Vars
    # 备份的配置文件路径
    $ConfigBackup = "$configs\wtConf.json"
    $WtConfig = "$wtConf_Home\settings.json"
    $WtPortableConfig = "$wtPortableConf_Home\settings.json"
    if ($Force)
    {
        $items = @($WtConfig, $WtPortableConfig)
        
        $items | ForEach-Object { 
            if ((Test-Path $_))
            {

                Remove-Item -Path $_ -Force -Verbose 
            }
        }
    }
    # 根据不同版本的wt,部署配置文件
    if ($Portable)
    {
        # Copy-Item -Path $ConfigBackup -Destination $WtPortableConfig -Verbose -Force
        New-Item -ItemType SymbolicLink -Path $WtPortableConfig -Target $ConfigBackup -Verbose -Force
    }
    elseif ($InstalledByScoop)
    {
        # Copy-Item -Path $ConfigBackup -Destination $WtPortableConfig -Verbose -Force
        if(Test-Path $WtScoopConfig)
        {
            Write-Verbose "$WtScoopConfig exist"
        }
        else
        {
            $WtScoopConfig = "$scoop_home\apps\windows-terminal\current\settings\settings.json"
            Write-Verbose "$wtScoopConfig does not exist,try another candidate path:[$wtScoopConfig]"

        }
        New-Item -ItemType SymbolicLink -Path $WtScoopConfig -Target $ConfigBackup -Verbose -Force
    }
    else
    {
        # 部署安装版的配置文件👺
        New-Item -ItemType SymbolicLink -Path $WtConfig -Value $ConfigBackup -Force -Verbose
    }
}
function Deploy-StartupServices
{
    <# 
    .SYNOPSIS
    启动 配置了开机自启的服务的脚本文件
    .DESCRIPTION
    作为服务,应该在用户还没有登陆到桌面前就应该启动
    .NOTES
    这里的服务类任务是不需要弹出窗口而比较适合在后台默默运行的,一般使用管理员或者系统用户的身份启动服务
    然而系统用户角色无法访问用户级别的环境变量,也就是说例如pwsh.exe所在路径如果仅仅配置到用户级别,那么开机启动的服务将无法找到pwsh.exe
    为了避免这个问题,你有两种选择,一种是讲路径配置到系统级别的环境变量,比如path中;
    对于scoop安装的powershell,若指定了全局安装,那么可以直接使用pwsh.exe,否则需要指定pwsh.exe的绝对路径
    本项目提供的deploy-pwsh7portable 默认仅仅配置到用户级别的Path中,因此无法直接配合Deploy-StartupServices使用;需要手动配置到系统Path中
    #>
    param (
        $shell = 'pwsh',
        # 需要执行的脚本文件(.ps1)
        $Script = "$PSScriptRoot\..\Startup\services.ps1",
        $TaskName = 'StartupServices',
        $UserId = 'SYSTEM' #'$env:Username'
        # $Arguemt = '-ExecutionPolicy ByPass -NoProfile -WindowStyle Normal -File C:\repos\scripts\PS\Deploy\..\Startup\services.ps1'
    )

    
    # 检查参数
    $PSBoundParameters | Format-Table
    # Get-ChildItem $Script
    
    $action = New-ScheduledTaskAction -Execute $shell -Argument " -ExecutionPolicy ByPass  -WindowStyle Hidden -File $Script"
    # 定义触发器
    $trigger = New-ScheduledTaskTrigger -AtStartup
    # 任务执行主体设置(以System身份运行,且优先级最高,无论用户是否登陆都运行,适合于后台服务，如aria2，chfs，alist等)
    $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType ServiceAccount -RunLevel Highest
    # 这里的-UserId 可以指定创建者;但是注意,任务创建完毕后,不一定能够立即看Author(创建者)字段的信息,需要过一段时间才可以看到,包括taskschd.msc也是一样存在滞后

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    # 创建计划任务
    Register-ScheduledTask -TaskName $TaskName -Action $action `
        -Trigger $trigger -Settings $settings -Principal $principal
    
}
function Deploy-StartupTasks
{
    [CmdletBinding()]
    param (
        [validateset('Link', 'Script', 'ScheduledTask')]$Mode = 'Link',
        [ValidateSet('User', 'System')]$Scope = 'User',
        # 检查startup中的自启动触发器是否可以正常工作
        [Alias('Check', 'Test')]
        [switch]$RunAtOnce,
        $shell = 'pwsh',
        $TaskName = 'startup',
        $UserId = $env:USERNAME #'Everyone'
        # $UserId = 'Everyone' #引发out of range错误，是不合法的UserId
        # [switch]$ValidateSingleSource
    )
    Update-PwshEnvIfNotYet -Mode Vars
    # 这里用了一个比较啰嗦但是比较鲁棒的写法,以防止用户的路径不是默认的路径:$env:systemDrive\repos\scripts\PS
    $PsModules = "$PSScriptRoot\.." #$PsScriptRoot这个自动变量在模块中有效
    $startupModule = "$PSModules\startup"
    $startupScript = "$startupModule\startup.ps1"
    # 粗暴的写法是
    # $startupScript = "$PS\Startup\startup.ps1"
    # $Path = "${startup_$`{Scope`}}\startup.ps1"
    # 将创建的快捷方式或者脚本放到那个位置
    if ($Scope -eq 'User')
    {
        $Path = "$startup_user\startup.ps1"
    }
    elseif ($Scope -eq 'System')
    {
        
        $Path = "$startup_common\startup.ps1"
    }
    # else
    # {
    #     # 这种情况是要注册到计划任务中去
    #     $Path = "$startupScript"
    # }

    if ($Mode -eq 'Link')
    {
        # 通过快捷方式执行$startupScript
        # $Path_link = "$startup_user\startup.lnk" #New-shortcut 足够智能,自动添加.lnk后缀
        $PathLnk = "${Path}.lnk"
        New-Shortcut -Path $PathLnk -TargetPath pwsh -TargetPathAsAppName -Arguments $startupScript -Force

    }
    elseif ($mode -eq 'Script')
    {
        # 通过启动器脚本执行 $startupScript
        <# Action when this condition is true #>
        # 写入自启动目录的脚本不需要有什么任务逻辑,让它去启动模块目录中的开机自启动脚本即可
        "pwsh -file $startupScript " > $Path #可以省略 pwsh的 -file 参数
        Write-Host 'The content of the startup script in the shell:startup directory:'
        Get-Content $Path | Write-Host -ForegroundColor cyan
        
        
    }
    elseif ($Mode -eq 'ScheduledTask')
    {
       
        # 通过计划任务执行$startupScript
        $trigger = New-ScheduledTaskTrigger -AtLogOn #-AtStartup #AtLogon是任何用户登陆时触发,对于有些软件比较适合用户登陆触发
        # 比较合理的做法是分开设置,基不需要特定用户看见的任务可以用startup触发,而需要用户看见的用AtLogon触发
            
        $action = New-ScheduledTaskAction -Execute $shell -Argument "-nologo -noe -ExecutionPolicy ByPass -NoProfile -WindowStyle Normal -File $StartupScript"
        # 定义计划任务的主体，设置不论用户是否登录都要运行
        $principal = New-ScheduledTaskPrincipal -UserId $UserId # -RunLevel Highest   #-LogonType ServiceAccount 
        # 说明:不要滥用最高启动权限,否则启动shell是使用conhost,而不是使用windows terminal,并且vscode这类软件对管理员权限比较敏感),还可能造成窗口动画美化软件无法作用于管理员权限运行的窗口上,造成不一致的体验

        # 设置在未通电时仍然运行这个开机启动任务
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable  

        Register-ScheduledTask -TaskName $TaskName -Trigger $trigger -Action $action -Principal $principal -Settings $settings -Force 
        $res = Get-ScheduledTask -TaskName $TaskName 
        Write-Verbose "Registration for $UserId"
        if (!$res)
        {
            Write-Error "The Registration of scheduled tasks $TaskName failed!"
        }
        
    }
    #检查自启动目录中文件情况(一般存放一个startup.ps1即可,否则可能造成重复执行自启动行为)
    $items = ($startup_common, $startup_user)
    $items | ForEach-Object {
        Get-ChildItem $_
    }
    # Write-Host $p.directory -ForegroundColor cyan


    if ($RunAtOnce)
    {
        . $s
    }
}
 

function Deploy-PortableGitPathEnvVar
{
    Update-PwshEnvIfNotYet -Mode Vars
    $items = @($Git_Portable_home, $Git_Portable_bin)
    foreach ($item in $items)
    {

        Add-EnvVar -EnvVar Path -NewValue $item -Scope User
    }
   
}
function Deploy-EnvsByPwsh
{
    <# 
    .SYNOPSIS
    将Backup-EnvsByPwsh备份的环境变量导入到系统环境变量中
    .DESCRIPTION
    .EXAMPLE
    #查看试验素材
    PS[BAT:76%][MEM:41.92% (13.29/31.70)GB][20:55:58]
    # [C:\repos\configs\env]
    ls *csv

            Directory: C:\repos\configs\env


    Mode                LastWriteTime         Length Name
    ----                -------------         ------ ----
    -a---         2024/4/20     20:36           1289 󰈛  system202404203647.csv
    -a---         2024/4/20     20:36            890 󰈛  user202404203647.csv
    -a---         2024/4/20     20:51             30 󰈛  userDemo.csv
    #导入到系统中持久化
    PS[BAT:76%][MEM:41.65% (13.20/31.70)GB][20:51:52]
    # [C:\repos\configs\env]
    deploy-EnvsByPwsh -SourceFile .\userDemo.csv -Scope 'User'
    .EXAMPLE
    PS[BAT:76%][MEM:42.02% (13.32/31.70)GB][20:54:01]
    # [~]
    deploy-EnvsByPwsh -SourceFile C:\repos\configs\env\user202404203647.csv -Scope 'User'
    .EXAMPLE
    PS[BAT:76%][MEM:42.19% (13.38/31.70)GB][20:54:50]
    # [~]
    deploy-EnvsByPwsh -SourceFile C:\repos\configs\env\system202404203647.csv -Scope 'Machine'
    #>
    [CmdletBinding()]
    param (
        # 指定要导入的备份文件
        $SourceFile,
        # 写入到用户环境变量还是系统环境变量
        [parameter(Mandatory = $true)]
        [ValidateSet('User', 'Machine')]$Scope,
        $EnvVar,
        # 是否清除环境变量(由Scope指定的作用于)
        [switch]$Clear,
        # 遇到已有的环境变量,使用指定的备份文件中指定的值覆盖现有的的环境变量取值,对于当前没有的环境变量,则导入;
        # 如果当前已有但是备份文件中没有的变量,不做改动(除非使用了Clear选项)
        [switch]$Replace
    )
    # 从备份文件中读取数据
    $items = Import-Csv $SourceFile 
    # 将读取的数据(是一个可迭代容器)遍历
    if ($EnvVar)
    {
        $item = $items | Where-Object { $_.Name -eq $EnvVar }
        $Value = $item.Value
        Write-Verbose "Set-EnvVar -EnvVar $EnvVar -Value $Value -Scope $Scope"
        
        Set-EnvVar -EnvVar $EnvVar -Value $Value -Scope $Scope
        # 仅设置单个变量然后退出执行
        return 
    }
    # 如果用户使用了-Clear参数,则清除原来的系统环境变量(这是一个高度危险的操作,执行前请做好备份)
    if ($Clear)
    {
        Backup-EnvsByPwsh -Scope $Scope -Directory $home/desktop #用户清空前默认备份一份存放到桌面
        Clear-EnvVar -Scope $Scope
    }
    foreach ($item in $items)
    {
        
        # 采用增量模式来导入环境变量在通常情况下是比较合适的
        $exist = Get-EnvVar -Key $item.Name -Scope $Scope
        if (!$exist)
        {

            Add-EnvVar -EnvVar $item.Name -NewValue $item.Value -Scope $Scope
            # Write-Verbose
            Write-Host "$($item.Name):$($item.Value) was added." -ForegroundColor cyan
        }
        else
        {
            Write-Verbose "$($item.Name) already exists: $($item.Name):$($exist.value)"
            if ($Replace)
            {
                Set-EnvVar -EnvVar $item.Name -NewValue $item.Value -Scope $Scope
            }
        }
    }
    
}

function Deploy-TrafficMonitor
{
    <# 
    .SYNOPSIS
    部署TrafficMonitor的配置文件
    .EXAMPLE
    Deploy-TrafficMonitor -InstalledByScoop -TrafficmonitorHome C:\scoop\apps\trafficmonitor\current\
    #>
    param(
        $TrafficmonitorHome = "$scoop_global_apps\TrafficMonitor\current",
        [switch]$InstalledByScoop
    )
    $process = Get-Process -Name TrafficMonitor -ErrorAction SilentlyContinue
    if ($process)
    {
        $continue = Confirm-UserContinue -Description 'TrafficMonitor is running.To Deploy settings,you must stop it. Do you want to stop it?'
        if ($continue)
        {
            $process | Stop-Process -Force
        }
        else
        {
            return
        }
    }
    # 导入必要的环境变量
    Update-PwshEnvIfNotYet 
    # 配置插件(注意相关变量(VarSet3中配置,$trafficMonitor_home是基础变量,而$trafficMonitor_plugins基于$trafficMonitor_home拼接而成))
    if($InstalledByScoop)
    {
        # $trafficMonitor_home = $TrafficmonitorHome
        #重新计算$trafficMonitor_plugins
        $trafficMonitor_plugins = "$TrafficmonitorHome\plugins"
    }
    New-Junction $trafficMonitor_plugins $configs\trafficMonitor\plugins
    #配置设置
    # HardLink $trafficMonitor\config.ini $configs\trafficMonitor\config.ini
    # 或者复制文件(比创建硬链接成功率高,硬链接无法跨分区创建)
    Copy-Item $configs\trafficMonitor\config.ini $TrafficmonitorHome\config.ini -Force -Verbose

    # 重新启动TrafficMonitor
    TrafficMonitor #别名启动
}
