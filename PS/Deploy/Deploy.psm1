<# 
.SYNOPSIS
临时部署此模块

Invoke-RestMethod 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy.psm1' | Invoke-Expression
.DESCRIPTION

#如果你懒得添加引号,那么将镜像链接逐个添加到下面的多行字符串中,即便包含了引号或者双引号逗号也都能够正确处理
# 配置一个相对稳定的镜像源(出了源的贡献者,还有可能被 墙,因此还是要定期检查)
#>




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


function Get-SelectedMirror
{
    <# 
    .SYNOPSIS
    让用户选择可用的镜像连接,允许选择多个,逗号隔开
    此函数放在Deploy.psm1中,许多公开单独部署的一键脚本环境(下载Deploy.psm1)的脚本依赖此函数
    .NOTES
    包含单个字符串的数组被返回时会被自动解包,这种情况下会是一个字符串
    如果确实需要外部接受数组,那么可以在外部使用@()来包装返回结果即可
    .EXAMPLE
    PS C:\repos\scripts> Get-SelectedMirror         
Checking available Mirrors...
         https://demo.testNew.com.
         https://gh.ddlc.top
...

Available Mirrors:
 0: Use No Mirror
 1: https://gh.ddlc.top
 2: https://ghps.cc
 3: https://gh.con.sh
 4: https://gh.noki.icu
 5: https://slink.ltd
 6: https://github.moeyy.xyz
 7: https://ghproxy.homeboyc.cn

Select the number(s) of the mirror you want to use [0~15] ?(default: 1): 1,3,5
Selected mirror:[ 
        https://gh.ddlc.top
        https://gh.con.sh
        https://slink.ltd
]
https://gh.ddlc.top
https://gh.con.sh
https://slink.ltd
PS C:\repos\scripts>
    #>
    [CmdletBinding()]
    param (
        
        $Default = 1, # 默认选择第一个(可能是响应最快的)
        [switch]$Linearly,
        [switch]$Silent # 是否静默模式,不询问用户,返回第$Default个链接($Default默认为1)
    ) 
    if (Get-Command -Name Get-AvailableGithubMirrors -ErrorAction SilentlyContinue)
    {
        Write-Verbose 'Checking available Mirrors...'
    }
    else
    {
        # 临时获取链接测试函数(走中央镜像,不再依赖 gitee)
        $tlMirror = if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }
        Invoke-RestMethod "$tlMirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/TestLinks.psm1" | Invoke-Expression
    }
 
    $Mirrors = Get-AvailableGithubMirrors -PassThru -Linearly:$Linearly

    $res = @()
    if (!$Silent)
    {
        # 交互模式
        $numOfMirrors = $Mirrors.Count
        $range = "[0~$($numOfMirrors-1)]"
        $num = Read-Host -Prompt "Select the number(s) of the mirror you want to use $range ?(default: $default)"
        # $mirror = 'https://mirror.ghproxy.com'
        # if($num.ToCharArray() -contains ','){
        # }

        $numStrs = $num -split ',' | Where-Object { $_.Trim() } | Get-Unique #转换为数组(自动去除空白字符)
        # 如果$num是一个空字符串(Read-Host遇到直接回车的情况),那么$numStrs会是$null
        if (!$numStrs )
        {
            Write-Host 'choose the Default 1'
            # $n = $default
            $res += $Default
        }
        else
        {
            foreach ($num in $numStrs)
            {
                $n = $num -as [int] #可能是数字或者空$null
                if ($VerbosePreference)
                {
            
                    Write-Verbose "`$n=$n"
                    Write-Verbose "`$num=$num"
                    Write-Verbose "`$numOfMirrors=$numOfMirrors"
                }
   
                #  如果输入的是空白字符,则默认设置为0
                # if ( $num.trim().Length -eq 0)
       
                if ($n -notin 0..($numOfMirrors - 1))
                {
                    throw " Input a number within the range! $range"
                }
                else
                {
                    # 合法的序号输入，插入到$res
                    $res += $n
                }
            }
        }
    }
    elseif ($Silent)
    {
        # Silent模式下默认选择第1个镜像
        $res += $default
    }
    # 抽取镜像
    $mirrors = $Mirrors[$res] #利用pwsh的数组高级特性
    # Write-Host $mirrors -ForegroundColor cyan
    $mirrors = @($mirrors) #确保其为数组
    
    # 用户选择了一个合法的镜像代号(0表示不使用镜像)
    Write-Host 'Selected mirror:[ ' # -NoNewline
    foreach ($mir in $mirrors)
    {
        Write-Host "`t$mir" -BackgroundColor Gray -NoNewline
        Write-Host ''

    }
    # Write-Host "$($Mirrors[$n])" -BackgroundColor Gray -NoNewline
    Write-Host ']'#打印一个空行

    # 包含单个字符串的数组被返回时会被自动解包,这种情况下会是一个字符串
    #如果却是需要外部接受数组,那么可以在外部使用@()来包装返回结果即可
    return $mirrors
    # return [array]$Mirrors
    # return $res

}



function Get-GithubMirrorPrefix
{
    <#
    .SYNOPSIS
    中央镜像前缀:全仓库统一从这里拿(环境变量优先,会话缓存,其次静默测速)。
    .DESCRIPTION
    决策(2026-09-21):gitee 对远程脚本执行误报拦截,不再作为默认源;github 走加速前缀。
    `$env:PsGithubMirror` 由用户持久化(喜欢哪个写哪个,Add-EnvVar),设了就用它,零探测;
    没设则本会话第一次调用时 Get-SelectedMirror -Silent 测一次并缓存;实在没有返回 ''。
    所有拼 raw URL 的地方调 Get-RepoRawUrl,不要自己拼前缀。
    .EXAMPLE
    Get-GithubMirrorPrefix
    #>
    [CmdletBinding()]
    param(
    )

    if ($env:PsGithubMirror)
    {
        return ([string]$env:PsGithubMirror).TrimEnd('/')
    }
    if ($script:CachedGithubMirrorPrefix)
    {
        return $script:CachedGithubMirrorPrefix
    }
    $first = Get-SelectedMirror -Silent | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($first))
    {
        return ''
    }
    $script:CachedGithubMirrorPrefix = ([string]$first).TrimEnd('/')
    return $script:CachedGithubMirrorPrefix
}
function Get-RepoRawUrl
{
    <#
    .SYNOPSIS
    仓库内文件 raw 地址统一出口:自动套中央镜像前缀。
    .EXAMPLE
    Get-RepoRawUrl -Path 'PS/Deploy/Deploy.psm1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Path,
        $Branch = 'main'
    )

    $raw = "https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/$Branch/$Path"
    $prefix = Get-GithubMirrorPrefix
    if ($prefix)
    {
        return "$prefix/$raw"
    }
    return $raw
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

function Deploy-FirewallByNetsh
{
    netsh advfirewall firewall add rule dir=out action=block program="C:\Program Files\Mozilla Firefox\firefox.exe" name="blockFirefox" description="createByNetsh" enable=yes
    netsh advfirewall firewall add rule dir=out action=block program="$360zip_home\360zip.exe" name="block360zip" description="createByNetsh" enable=yes

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
function Enable-NetworkDiscoveryAndSharing
{
    <# 
    .SYNOPSIS
    启用共享文件夹和网络发现
    这里通过防火墙设置来实现,可以指定中英文系统语言再执行防火墙设置
    .EXAMPLE
    PS C:\> Enable-NetworkDiscoveryAndSharing
    No rules match the specified criteria.
    No rules match the specified criteria.
    Updated 30 rule(s).
    Ok.
    Updated 62 rule(s).
    Ok.
    PS C:\> Enable-NetworkDiscoveryAndSharing -Language Chinese
    No rules match the specified criteria.
    No rules match the specified criteria.
    PS C:\> Enable-NetworkDiscoveryAndSharing -Language English
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
    Enable-NetworkDiscoveryAndSharing

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
        $TrafficmonitorHome = "$scoop_apps\TrafficMonitor\current",
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

# 注:镜像站测试函数已独立为 TestLinks 模块(同级目录),此处删除内联版本以降低 Deploy 解析成本

function Test-PsEnvReadiness
{
    <#
    .SYNOPSIS
    新机部署前检查:逐项查必备件,缺什么补什么(只读,不改机器)。
    .DESCRIPTION
    配合 docs/Deploy-Guide.md 使用。分 必备/可选/首跑生成物 三档;表格展示,不返回值。
    .EXAMPLE
    Test-PsEnvReadiness
    .EXAMPLE
    Test-PsEnvReadiness -CheckRemote
    #>
    [CmdletBinding()]
    param(
        # 问远端有没有更新(ls-remote 只读,不 fetch 不动本地;默认关,本地对比零网络)
        [switch]$CheckRemote
    )
    $psRoot = Split-Path $PSScriptRoot -Parent
    # 路径归一化(分隔符统一为系统分隔符,尾部分隔符不敏感;PSModulePath 切分另用系统分隔符,见下)
    $sep = [IO.Path]::DirectorySeparatorChar
    $normPath = { param($p) (([string]$p) -replace '[/\\]', $sep).TrimEnd('/', '\') }.GetNewClosure()
    # 用 ArrayList 攒行(闭包捕获同一对象引用)
    $rows = [System.Collections.ArrayList]::new()
    $chk = {
        param($Item, $Level, $Test, $Need, $Date = { '' }, $Ver = { '' }, $Note = { '' })
        $ok = try { [bool](& $Test) } catch { $false }
        $date = try { & $Date } catch { '' }
        $ver = try { & $Ver } catch { '' }
        # 备注:缺时给补法,OK 时给补充说明(如活件与仓库的版本对比)
        $note = if ($ok) { try { & $Note } catch { '' } } else { $Need }
        [void]$rows.Add([PSCustomObject]@{
                事项 = $Item
                级别 = $Level
                状态 = if ($ok) { 'OK' } else { '缺' }
                版本 = $ver
                日期 = $date
                备注 = $note
            })
    }.GetNewClosure()
    # 日期小料:模块取 psd1 日期,二进制取 exe 日期,文件直接取,取不到空串(列对齐不断)
    $modDate = { param($n) try { (Get-Item -LiteralPath (Join-Path (Get-Module -ListAvailable $n | Select-Object -First 1).ModuleBase "$n.psd1") -ErrorAction Stop).LastWriteTime.ToString('yyyy-MM-dd HH:mm') } catch { '' } }.GetNewClosure()
    $binDate = { param($n) try { $src = (Get-Command $n -ErrorAction Stop).Source; if ([string]::IsNullOrWhiteSpace($src) -or -not (Test-Path -LiteralPath $src)) { '' } else { (Get-Item -LiteralPath $src).LastWriteTime.ToString('yyyy-MM-dd HH:mm') } } catch { '' } }.GetNewClosure()
    $fileDate = { param($p) try { (Get-Item -LiteralPath $p -ErrorAction Stop).LastWriteTime.ToString('yyyy-MM-dd HH:mm') } catch { '' } }.GetNewClosure()
    # 活件解析小料:指针→版本目录→旧单文件,返回可用 dll 路径(取不到空串,永不抛;定义须在使用者之前)
    $liveDllPath = { try { $bd = Join-Path (Join-Path $HOME '.cxxu') 'bin'; $p = Join-Path $bd 'current.txt'; if (Test-Path -LiteralPath $p) { $h = Get-Content -LiteralPath $p -ErrorAction Stop | Select-Object -First 1; if ($h) { $c = Join-Path (Join-Path $bd "$h".Trim()) 'CxxuPredictor.dll'; if (Test-Path -LiteralPath $c) { return $c } } }; $best = Get-ChildItem -LiteralPath $bd -Directory -ErrorAction Stop | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'CxxuPredictor.dll') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($best) { return (Join-Path $best.FullName 'CxxuPredictor.dll') }; $lg = Join-Path $bd 'CxxuPredictor.dll'; if (Test-Path -LiteralPath $lg) { return $lg }; '' } catch { '' } }.GetNewClosure()
    # 活件版本对比小料:指针解析出的活件哈希 vs 仓库源,结果进 备注 列(取不到空串,永不抛)
    $dllSyncNote = { try { $lv = & $liveDllPath; $rp = Join-Path (Join-Path $psRoot 'CxxuPredictor') 'CxxuPredictor.dll'; if (-not (Test-Path -LiteralPath $rp)) { '仓库源不存在' } elseif (-not $lv) { '无活件' } else { $lh = (Get-FileHash -LiteralPath $lv -Algorithm SHA256).Hash.Substring(0, 8); $rh = (Get-FileHash -LiteralPath $rp -Algorithm SHA256).Hash.Substring(0, 8); if ($lh -eq $rh) { "与仓库一致[$rh]" } else { "与仓库不一致(仓 $rh)，请执行 Sync-CxxuPredictor 同步" } } } catch { '' } }.GetNewClosure()
    # 版本小料:只取文件级/内存级信息,不起新进程(git --version 这类免谈);取不到空串
    $modVer = { param($n) try { (Get-Module -ListAvailable $n | Select-Object -First 1).Version.ToString() } catch { '' } }.GetNewClosure()
    $binVer = { param($n) try { [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Get-Command $n -ErrorAction Stop).Source).FileVersion } catch { '' } }.GetNewClosure()
    # 必备
    & $chk 'pwsh 7+' '必备' { $PSVersionTable.PSVersion.Major -ge 7 } 'Update-PowerShell 或重装 pwsh 7' { & $binDate 'pwsh' } { $PSVersionTable.PSVersion.ToString() }
    & $chk 'PSModulePath 含模块集' '必备' { @(($env:PSModulePath -split [regex]::Escape([IO.Path]::PathSeparator)) | ForEach-Object { & $normPath $_ }) -contains (& $normPath $psRoot) } "Add-EnvVar -EnvVar PSModulePath -NewValue '$psRoot'"
    & $chk '$profile 有 init' '必备' { (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost) -and ((Get-Content -LiteralPath $PROFILE.CurrentUserCurrentHost -Raw) -match '(?m)^\s*init\s*$') } 'Add-CxxuPsModuleToProfile 或手写 init' { & $fileDate $PROFILE.CurrentUserCurrentHost }
    & $chk 'git' '必备' { Get-Command git -ErrorAction SilentlyContinue } 'Confirm-GitCommand / 装 git' { & $binDate 'git' } { & $binVer 'git' }
    & $chk 'PSFzf 模块' '必备' { Get-Module -ListAvailable PSFzf } 'Confirm-ModuleInstalled -ModuleName PSFzf -Install' { & $modDate 'PSFzf' } { & $modVer 'PSFzf' }
    & $chk 'CompletionPredictor 模块' '必备' { Get-Module -ListAvailable CompletionPredictor } 'Confirm-ModuleInstalled -ModuleName CompletionPredictor -Install' { & $modDate 'CompletionPredictor' } { & $modVer 'CompletionPredictor' }
    & $chk 'pwsh 7.5+(CxxuPredictor 需 net9)' '必备' { $PSVersionTable.PSVersion -ge [version]'7.5' } 'Update-PowerShell 到 7.5+(或进 PS/CxxuPredictor/src 重编 dll)'
    # 可选
    & $chk 'fzf 二进制' '可选' { Get-Command fzf -ErrorAction SilentlyContinue } 'scoop install fzf' { & $binDate 'fzf' } { & $binVer 'fzf' }
    & $chk 'zoxide 二进制' '可选' { Get-Command zoxide -ErrorAction SilentlyContinue } 'scoop install zoxide' { & $binDate 'zoxide' } { & $binVer 'zoxide' }
    & $chk 'scoop' '可选' { Get-Command scoop -ErrorAction SilentlyContinue } '按官网装 scoop(参考 Deploy-ScoopByGithubMirrors)' { & $binDate 'scoop' } { & $binVer 'scoop' }
    & $chk 'conda' '可选' { Get-Command conda -ErrorAction SilentlyContinue } 'Deploy-MiniforgeConfig' { & $binDate 'conda' } { & $binVer 'conda' }
    & $chk 'fnm' '可选' { Get-Command fnm -ErrorAction SilentlyContinue } 'scoop install fnm(后解开 profile 钩子)' { & $binDate 'fnm' } { & $binVer 'fnm' }
    & $chk 'PSCompletions 模块' '可选' { Get-Module -ListAvailable PSCompletions } 'Confirm-ModuleInstalled -ModuleName PSCompletions -Install(后解开 profile 钩子)' { & $modDate 'PSCompletions' } { & $modVer 'PSCompletions' }
    # 首跑生成物(跑一次 init 自动建)
    & $chk '~/Data.json' '生成物' { Test-Path -LiteralPath (Join-Path $HOME 'Data.json') } '跑一次 init' { & $fileDate (Join-Path $HOME 'Data.json') }
    & $chk 'predictor 活件 ~/.cxxu/bin' '生成物' { [bool](& $liveDllPath) } '执行 Sync-CxxuPredictor 生成活件' { $lp = & $liveDllPath; if ($lp) { & $fileDate $lp } else { '' } } { '' } { & $dllSyncNote }
    $rows | Format-Table -AutoSize | Out-Host
    $must = @($rows | Where-Object { $_.级别 -eq '必备' })
    $mustOk = @($must | Where-Object { $_.状态 -eq 'OK' }).Count
    Write-Host "必备 $($mustOk)/$($must.Count);缺的按“备注”列补，补完重跑本检查。"
    # 版本/日期表尾(只读,取不到标未知,永不抛;二进制不取进程版本,只取文件级信息)
    $repoRoot = Split-Path $psRoot -Parent
    $repoVer = try { (git -C $repoRoot log -1 --format='%h %ci' HEAD 2>$null).Trim() } catch { '' }
    if ([string]::IsNullOrWhiteSpace($repoVer)) { $repoVer = '未知(非 git 环境?)' }
    $liveDll = & $liveDllPath
    $dllMismatch = $false
    $dllInfo = '未生成(请执行 Sync-CxxuPredictor)'
    if ($liveDll)
    {
        try
        {
            $liveHash = (Get-FileHash -LiteralPath $liveDll -Algorithm SHA256).Hash.Substring(0, 8)
            $liveDate = (Get-Item -LiteralPath $liveDll).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            $repoDll = Join-Path (Join-Path $psRoot 'CxxuPredictor') 'CxxuPredictor.dll'
            $syncState = '仓库源不存在'
            if (Test-Path -LiteralPath $repoDll)
            {
                $repoHash = (Get-FileHash -LiteralPath $repoDll -Algorithm SHA256).Hash.Substring(0, 8)
                $syncState = if ($repoHash -eq $liveHash) { '与仓库一致' } else { $dllMismatch = $true; "与仓库不一致(仓 $repoHash)" }
            }
            $dllInfo = "$liveDate [$liveHash] $syncState"
        }
        catch { $dllInfo = '未知(读取失败)' }
    }
    Write-Host "仓库 $repoVer;pwsh $($PSVersionTable.PSVersion);dll 活件 $dllInfo"
    # 远端版本对比(仅 -CheckRemote:ls-remote 只问远端,不 fetch 不动本地;12s 超时防卡死,离线/超时标未知,永不抛)
    $remoteInfo = '未查(加 -CheckRemote 问远端)'
    $remoteBehind = $false
    if ($CheckRemote)
    {
    try
    {
        $branch = (git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null).Trim()
        $url = (git -C $repoRoot remote get-url origin 2>$null).Trim()
        if (-not [string]::IsNullOrWhiteSpace($url) -and -not [string]::IsNullOrWhiteSpace($branch) -and $branch -ne 'HEAD')
        {
            $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) 'CxxuLsRemote.txt'
            $tmpErr = Join-Path ([System.IO.Path]::GetTempPath()) 'CxxuLsRemote.err'
            $p = Start-Process git -ArgumentList @('-C', $repoRoot, 'ls-remote', $url, "refs/heads/$branch") -NoNewWindow -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
            if ($p.WaitForExit(12000))
            {
                $remoteHash = ((Get-Content -LiteralPath $tmpOut -ErrorAction SilentlyContinue | Select-Object -First 1) -split '\s+' | Select-Object -First 1)
                Remove-Item -LiteralPath @($tmpOut, $tmpErr) -ErrorAction SilentlyContinue
                if ($remoteHash -match '^[0-9a-f]{40}$')
                {
                    $localHash = (git -C $repoRoot rev-parse HEAD 2>$null).Trim()
                    $remoteShort = $remoteHash.Substring(0, 7)
                    if ($remoteHash -eq $localHash) { $remoteInfo = "$remoteShort 已是最新" }
                    elseif ((git -C $repoRoot status -sb 2>$null | Select-Object -First 1) -match '\[ahead') { $remoteInfo = "$remoteShort 本地超前(有未推提交?)" }
                    else { $remoteInfo = "$remoteShort 有更新"; $remoteBehind = $true }
                }
                else { $remoteInfo = '未知(远端无此分支?)' }
            }
            else { try { $p.Kill() } catch { }; Remove-Item -LiteralPath @($tmpOut, $tmpErr) -ErrorAction SilentlyContinue; $remoteInfo = '未知(查询超时)' }
        }
        else { $remoteInfo = '未知(无 origin/分支?)' }
    }
    catch { $remoteInfo = '未知(查询失败)' }
    }
    Write-Host "远端 $remoteInfo"
    # 下一步建议(优先级:缺必备 > 有更新 > 活件不一致 > 远端未知/未查 > 无事)
    $advice = if ($CheckRemote) { '无(已是最新,活件一致)' } else { '无(本地一致;加 -CheckRemote 问远端更新)' }
    if ($mustOk -lt $must.Count) { $advice = '按“备注”列补,补完重跑本检查' }
    elseif ($remoteBehind) { $advice = '请执行 Update-ReposesConfiged 拉取（dll 变更会自动同步活件，之后重开终端）' }
    elseif ($dllMismatch) { $advice = '请执行 Sync-CxxuPredictor 同步活件后再执行 init' }
    elseif ($remoteInfo -like '未知*') { $advice = '远端未知(离线/超时?):联网后重跑看更新' }
    Write-Host "建议 $advice"
}

function doctor
{
    <#
    .SYNOPSIS
    pwsh 健康诊断：先执行 Test-PsEnvReadiness（安装态），再检查运行态（init 错误/PSReadLine/历史大小/predictor/门控/懒加载/守护/仓库脏）。
    .DESCRIPTION
    只读，不修改机器，默认零网络（远端版本通过 readiness 的 -CheckRemote 查看）。每行给出状态与处理动作，
    收尾计数。定位问题时先执行本命令，再按行处理。
    .EXAMPLE
    doctor
    .EXAMPLE
    doctor -CheckRemote
    #>
    [CmdletBinding()]
    param(
        # 转发给 Test-PsEnvReadiness:问远端有没有更新(默认关)
        [switch]$CheckRemote
    )
    Test-PsEnvReadiness -CheckRemote:$CheckRemote
    $rows = [System.Collections.ArrayList]::new()
    $dchk = {
        param($Item, $Ok, $Note)
        [void]$rows.Add([PSCustomObject]@{
                检查 = $Item
                状态 = if ($Ok) { 'OK' } else { 'WARN' }
                备注 = $Note
            })
    }.GetNewClosure()
    # init 错误账本(没跑过 init 时变量是 $null,先滤掉,不然 @($null) 数出 1 个空失败)
    $stepErrs = @($global:PsInitStepErrors | Where-Object { $_ })
    & $dchk 'init' ($global:PsInit -and -not $stepErrs.Count) $(if ($stepErrs.Count) { "有 $($stepErrs.Count) 步失败:$($stepErrs.Step -join ',')" } elseif (-not $global:PsInit) { '本会话没跑过 init' } else { 'clean' })
    # PSReadLine 关键选项
    $pr = try { Get-PSReadLineOption } catch { $null }
    if ($pr)
    {
        & $dchk '预测源/视图' ($pr.PredictionSource -match 'HistoryAndPlugin') "$($pr.PredictionSource)/$($pr.PredictionViewStyle)(窄窗 Inline 正常)"
        & $dchk '历史策略' ($pr.HistoryNoDuplicates -and $pr.MaximumHistoryCount -ge 3000) "去重 $($pr.HistoryNoDuplicates),上限 $($pr.MaximumHistoryCount)"
    }
    else { & $dchk 'PSReadLine' $false '取不到选项(模块没加载?)' }
    # 历史文件大小(超 8000 行或 500KB 建议瘦身)
    $histFile = try { (Get-PSReadLineOption).HistorySavePath } catch { '' }
    if ($histFile -and (Test-Path -LiteralPath $histFile))
    {
        $hl = @(Get-Content -LiteralPath $histFile).Count
        $hkb = [int]((Get-Item -LiteralPath $histFile).Length / 1KB)
        & $dchk '历史大小' (($hl -le 8000) -and ($hkb -le 500)) "$hl 行/$hkb KB(超 8000 行或 500KB 跑 Optimize-PsHistory)"
    }
    else { & $dchk '历史大小' $false '历史文件不存在(还没存过?)' }
    # predictor:门控/活件/加载三态(活件按指针解析,见 Test-PsEnvReadiness 的 $liveDllPath)
    $gateOff = $env:PsPredictor -match '^(False|0|No|Off)$'
    $binDir = Join-Path (Join-Path $HOME '.cxxu') 'bin'
    $liveDll = $null
    $ptrF = Join-Path $binDir 'current.txt'
    if (Test-Path -LiteralPath $ptrF)
    {
        $hd = Get-Content -LiteralPath $ptrF -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hd) { $cd = Join-Path (Join-Path $binDir "$hd".Trim()) 'CxxuPredictor.dll'; if (Test-Path -LiteralPath $cd) { $liveDll = $cd } }
    }
    if (-not $liveDll)
    {
        $bd = Get-ChildItem -LiteralPath $binDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'CxxuPredictor.dll') } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($bd) { $liveDll = Join-Path $bd.FullName 'CxxuPredictor.dll' }
        else { $lgF = Join-Path $binDir 'CxxuPredictor.dll'; if (Test-Path -LiteralPath $lgF) { $liveDll = $lgF } }
    }
    $loaded = [bool](Get-Module CxxuPredictor)
    if ($gateOff) { & $dchk 'predictor' $true '开关已关闭(PsPredictor=False)，按需开启' }
    elseif (-not $liveDll) { & $dchk 'predictor' $false '无活件：请执行 Sync-CxxuPredictor 生成' }
    elseif (-not $loaded) { & $dchk 'predictor' $false '活件存在但未加载：等待一拍(OnIdle)或执行 Register-PsUxLazyLoad -Now' }
    else
    {
        $repoDll = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'CxxuPredictor') 'CxxuPredictor.dll'
        $same = try { (Get-FileHash -LiteralPath $liveDll -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $repoDll -Algorithm SHA256).Hash } catch { $false }
        & $dchk 'predictor' $same $(if ($same) { '已加载且与仓库一致' } else { '内存中是旧版本：请重开终端，活件已可同步（Sync-CxxuPredictor 不受锁限制）' })
    }
    # 三门控 + 懒加载
    $gates = @('PsFzf', 'PsZoxide', 'PsPredictor', 'PsTab') | ForEach-Object { "$_=$([string]::IsNullOrEmpty((Get-Item "env:$_" -ErrorAction SilentlyContinue).Value) ? '默认开' : (Get-Item "env:$_").Value)" }
    & $dchk '门控' $true ($gates -join ' ')
    & $dchk '平台' $true $(if ($IsWindows) { 'Windows' } else { '非 Windows：scoop/注册表/计划任务/WT 系列不可用，详见 Feature-Guide §12' })
    $tabWrapped = try { (Get-Command TabExpansion2 -CommandType Function -ErrorAction Stop).ScriptBlock.ToString() -match 'CxxuTab' } catch { $false }
    & $dchk 'Tab 包装' ($tabWrapped -or $env:PsTab -match '^(False|0|No|Off)$') $(if ($tabWrapped) { 'CxxuTab 包装已装入' } elseif ($env:PsTab -match '^(False|0|No|Off)$') { '开关已关闭，按需开启' } else { '未装入：执行 Install-CxxuTabWrapper 或重开终端' })
    & $dchk '懒加载' ([bool](Get-Module PSFzf) -or $env:PsFzf -match '^(False|0|No|Off)$') $(if (Get-Module PSFzf) { 'PSFzf 已装入(OnIdle 已触发)' } elseif ($global:PsUxOnIdleRegistered) { 'OnIdle 已注册,等一拍' } else { '没注册:跑 Register-PsUxLazyLoad' })
    # 守护进程代理:Data.json 新鲜度(>5 分钟没写=守护可能没跑)
    $dj = Join-Path $HOME 'Data.json'
    if (Test-Path -LiteralPath $dj)
    {
        $age = (Get-Date) - (Get-Item -LiteralPath $dj).LastWriteTime
        & $dchk '守护(IP)' ($age.TotalMinutes -le 5) ("Data.json $($age.TotalMinutes.ToString('0')) 分钟前更新(超 5 分钟查守护)")
    }
    else { & $dchk '守护(IP)' $false '无 Data.json:跑一次 init' }
    # 仓库脏检查(本地,只读)
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $dirty = @(git -C $repoRoot status --porcelain 2>$null)
    & $dchk '仓库干净' (-not $dirty.Count) $(if ($dirty.Count) { "$($dirty.Count) 个未提交改动(更新前先看)" } else { 'clean' })
    # conda 缓存
    & $dchk 'conda 缓存' (Test-Path -LiteralPath (Join-Path $HOME '.conda_hook_cache.ps1')) '无则下次 init 现场生成(慢一次)'
    $rows | Format-Table -AutoSize | Out-Host
    $warn = @($rows | Where-Object { $_.状态 -eq 'WARN' }).Count
    Write-Host $(if ($warn) { "WARN $warn 项,按备注列逐个处理,处理完重跑 doctor。" } else { '全绿,无事可做。' })
}
