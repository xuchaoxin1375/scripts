
function openLink
{
    param (
        $linkMark
    )
    msedge $linkMark
}

function New-HardLink
{
    <# 
    .SYNOPSIS
    创建硬链接,相较于New-item -ItemType -Path 改进了目标路径是对相对路径时的支持不佳的问题
    .DESCRIPTION
    只有文件才可以创建硬链接,目录无法创建硬链接
    .Notes
    '@注意,Target必须使用绝对路径!'
    "@当然, 也可以是这样的表达式:`"`$pwd\\file`""
    '@带上-target 选项'
    #>
    [CmdletBinding()]
    param(
        $Path ,
        [alias('Destination')][String]$Target 
    )
    # 下面这段判断处理可有可无
    <# if ($Target.ToString().StartsWith(".\")) {
        $Target=$Target.TrimStart(".\")
    } #>
    # $absTarget = "$pwd\" + "$Target"
    # 因为Hardlink只能对文件创建,那么使用ls 检查$Target后获得System.IO.FileInfo,然后用其FullName属性
    $absTarget = (Get-PsIOItemInfo -Path $Target).FullName


    if (Test-Path $Path)
    {
        Remove-Item -Verbose -Force $Path
    }
    New-Item -ItemType HardLink -Path $Path -Target $absTarget -Force -Verbose
}

function New-SymbolicLink
{
    <# 
    .SYNOPSIS
    创建符号链接
    .DESCRIPTION
    符号链接在windows中是最通用最强大的一种链接类型,能够跨分区链接文件和文件夹,尽管可能需要管理员权限
    junctionLink和HardLink的短板都比价明显,前者只对文件夹管用,后者只对文件管用,而且还不能够跨分区创建,还容易被git config这类命令破换链接

    此外,SymbolicLink有更好的兼容性,是Microsoft为了兼容Linux等系统引入
    powershell 的一些命令和一些git工具对于SymbolicLink的支持更加直接
    比如是否递归到SymbolicLink的目标目录,git操作是否要跟踪到SymbolicLink的目标目录等
    
    同时SymbolicLink作用于文件时,也能在ls或者dir中更加直观的看到链接类型和链接目标,这一点是Hardlink所不具备的
    symbolicLink作用于文件时是非常有用的,提供了比作用于目录更高的灵活性
    例如,我有一个仓库专门用来保存软件配置文件的,我希望在一个新设备X,克隆这个配置文件仓库到设备X上后,可以快速部署各个软件的配置,比如windows terminal的设置,或者git的配置文件.gitconfig
    这时候利用SymbolicLink,在对应的目录创建符号链接到配置文件仓库中的对应文件,就可以设置新设备上的软件了

    .NOTES

    严禁滥用符号链接(其他类型的链接也是类似的,通过链接的修改会影响掉目标文件,比如通过某个目录的链接删除链接所指的目录中的文件,目标目录中的文件也会被删除,尽管删除链接本身不会影响目标)
    如果使用不当(比如创建符号链接的时机不对,可能会导致数据丢失)
    尤其是软件配置,例如我要部署Typora编辑器的主题和快捷键配置,那么应该在软件安装完毕之后在调用基于SymbolicLink的配置部署函数
    如果先部署完配置文件,然后安装软件,可能会导致软件覆盖掉部署的配置文件或目录,导致数据丢失,或者安装失败

    此外，对于多系统用户,虽然SymbolicLink可以跨分区创建目标链接,但是访问权限可能会阻碍你直接使用其他分区上的windows系统中的某些用户的家目录的配置文件(例如安装在D盘的vscode,如果想要用SymbolicLink链接到该系统中的某个用户的.vscode目录,会有访问权限问题),这种情况下,您可以考虑在系统中启用Administrator权限(通过本地安全策略,`以管理员批准模式运行所有管理员`设置为禁用,使得非内置的Administrator用户默认使用Administrator权限访问硬盘上的文件,尽管还是有部分情况管理员也无法直接访问,这时可以借助icacls 命令来设置权限,参考Grant-PermissionToPath函数)

    #>

    [CmdletBinding()]
    param(
        $Path ,
        $Target ,
        [switch]$Force 
    )
    if ($Force)
    {
        $continue = Confirm-UserContinue -Description "Remove $Path and create new SymbolicLink"
        if ($continue)
        {
            Remove-Item -Verbose -Force $Path
        }
        
    }
    # 创建对应的SymbolicLink
    New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force -Verbose
}
function Get-Links
{
    <# 
    .SYNOPSIS
    查看指定类型的链接,以表格的形式输出(包括:name,linktype,linktarget)
    可用的类型包括:hardlink,symboliclink,junction
    默认不区分大小写.
    .DESCRIPTION
    相较于直接使用ls管道符Where ,本函数将用户感兴趣的属性select出来
    .EXAMPLE
    PS☀️[BAT:71%][MEM:36.25% (11.49/31.71)GB][22:20:59]
    # [cxxu@COLORFULCXXU][~\Desktop]
    PS> pwsh
    PowerShell 7.4.2
    PS C:\Users\cxxu\Desktop> Get-Links -Directory C:\Users\cxxu -LinkType symboliclink

    Name  LinkType     LinkTarget Mode
    ----  --------     ---------- ----
    repos SymbolicLink C:\repos   l----

    .EXAMPLE
    PS C:\Users\cxxu\Desktop> Get-Links -Directory ./ -LinkType symboliclink

    Name             LinkType     LinkTarget     Mode
    ----             --------     ----------     ----
    symbolDir        SymbolicLink T:\DirInFat32\ l----
    TestSymbolicLink SymbolicLink U:\demo.txt    la---
    
    .EXAMPLE
    PS C:\Users\cxxu\Desktop> Get-Links

    Name             LinkType     LinkTarget                             Mode
    ----             --------     ----------                             ----
    demoHardlink.txt HardLink                                            la---
    demoJunctionDir  Junction     C:\Users\cxxu\desktop\testDir\innerDir l----
    symbolDir        SymbolicLink T:\DirInFat32\                         l----
    TestSymbolicLink SymbolicLink U:\demo.txt                            la---
     #>
    param(
        [Alias('D')]$Directory = '.',
        [validateset( 'symboliclink', 'junction', 'hardlink' , 'all')]$LinkType = 'all'

    )
    $all = Get-ChildItem $Directory | Where-Object { $_.LinkType } | Sort-Object -Property LinkType
    $Specifiedtype = $all | Where-Object { $_.LinkType -eq $linkType } 
    if ($LinkType -eq 'all') { $res = $all } else { $res = $Specifiedtype }
    $res = $res | Format-Table name, LinkType, LinkTarget, Mode
    return $res
}
function Get-LinksInCriticalPaths
{
    <# 
    .example
    Get-Links 'C:\Program Files\',d:\,c:\users
    PS C:\repos\scripts> Get-Links 'C:\Program Files\',d:\,c:\users
    # comments:😁😁detecting the path:@ C:\repos\scripts...

    Junction Microsoft VS Code C:\Program Files\Microsoft VS Code
    # comments:😁😁detecting the path:@ C:\repos\scripts...
    Junction books             d:\org\booksRepository
    Junction dp                C:\Program Files\
    Junction dp86              C:\Program Files (x86)\
    Junction org               d:\OneDrive - pop.zjgsu.edu.cn\
    #>
    param (
        # 数组
        $checkPath_opt = @($home, 'C:\', $localAppData)
    )
    # Write-Output "......# comments:😁😁detecting the path:$(Get-Location)..."
    # $buffer = Get-ChildItem | Sort-Object -Property Name | Select-Object linktype, name, target | Where-Object { $_.Target }  

    $buffer = $checkPath_opt.ForEach(
        {
            Write-Output "# detecting in $_)"
            # Get-ChildItem $_ | Sort-Object -Property Name | Select-Object linktype, fullname, target | Where-Object { $_.Target }   
    
            Get-ChildItem $_ | Where-Object { $_.Target } | Select-Object linktype, @{label = 'fullname_q'; expression = { "`"$($_.fullname)`"" } }, @{label = 'target_q'; expression = { "`"$($_.target)`"" } } | Sort-Object -Property Name  
            Write-Output "`n"
            # Write-SeparatorLine '#' 
        }
    )
    $buffer = $buffer | Format-Table -HideTableHeaders
    # Write-Output $buffer
    return $buffer
    
}



