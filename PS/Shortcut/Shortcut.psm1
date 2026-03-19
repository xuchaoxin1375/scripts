
function Get-ShortcutLinkInfo
{
    <# 
    .SYNOPSIS
    获取快捷方式(lnk文件)的信息 
    .EXAMPLE
    PS> get-ShortcutLinkInfo C:\Users\cxxu\Desktop\GodMode.lnk

    FullName         : C:\Users\cxxu\Desktop\GodMode.lnk
    Arguments        : shell:::{ED7BA470-8E54-465E-825C-99712043E01C}
    Description      :
    Hotkey           :
    IconLocation     : ,0
    RelativePath     :
    TargetPath       : C:\WINDOWS\explorer.exe
    WindowStyle      : 1
    WorkingDirectory :

    #>
    param(
        $Path
    )
    $shell = New-Object -ComObject WScript.Shell
    if (Test-Path $Path)
    {
        $Path = Resolve-Path $Path #获取绝对路径(使用相对路径的话可能会受到当前路径或环境的影响)
    }
    elseif ($Path -match '\./*')
    {
        
        $Path = (Join-Path -Path (Get-Location).Path -ChildPath $Path)
    }
    $shortcut = $shell.createShortcut($Path)
    return $shortcut
}


function New-Shortcut
{

    <# 
    .SYNOPSIS
    创建一个快捷方式
    .DESCRIPTION

    TargetPath 可以是相对路径/绝对路径/也可以是配置在系统变量Path中的可以直接根据软件名启动的程序名
    将该参数设置为非路径的字符串通常没有意义,除非桌面上有个文件名为该字符串的文件或目录
    函数执行完毕后会调用Get-shortcutLinkInfo获取快捷方式的信息

    .DESCRIPTION
    使用此命令行方式创建的快捷方式会在路径(TargetPath)不可用时默认将其拼接到用户桌面目录后,例如`TargetPath = startup.myfile`,
    如果此文件系统无法直接找到该文件，则会自动创建新的路径"$env:USERPROFILE\Desktop\startup.myfile"
    尽管如此,这个自动生成的路径只是一种猜测而已,往往是不可靠的
    快捷方式(Shortcut)不支持相对路径,只支持绝对路径
    在这种仅指定一个名字(不是绝对路径)的情况下,利用本函数提供的参数`TargetPathAsAppName`开关来告诉创建脚本,
    我这个是一个程序名,而不是绝对路径,需要进一步将其转换为绝对路径才可以用(事实上,这个参数也兼容路径字符串)
    在此参数作用下,这里利用了`gcm`命令来解析TargetPath,解析成功的前提是`TargetPath`是存在的路径,
    或者是通过path环境变量配置过路径,能够在命令行直接打开的文件(通常是可执行文件.exe,.msc等),比如说,notepad就是合法的取值

    .EXAMPLE
    为一个目录创建桌面快捷资源管理器快捷方式
    New-Shortcut -Path $desktop/woo_df -TargetPath $scripts\wp\woocommerce\woo_df -Verbose -Force
    
    下面的方案效果类似,但是有区别,比如许多右键打开目录的选项都不适用
    New-Shortcut -Path $desktop\woo_df -TargetPath explorer.exe -Arguments $scripts\wp\woocommerce\woo_df -TargetPathAsAppName -Verbose -Force
    

    .EXAMPLE
    
    PS[BAT:69%][MEM:27.80% (8.81/31.70)GB][12:01:17]
    # [~\Desktop]
    PS> New-Shortcut -Path demo3 -TargetPath C:\repos\scripts\PS\Startup\startup.ps1 -Arguments  '-Nologo -NoProfile'
            The shortcut file name must has a suffix of .lnk or .url
            The .lnk extension is used by default
    [C:\Users\cxxu\Desktop\demo3.lnk] will be used
    New-Shortcut: File already exists: C:\Users\cxxu\Desktop\demo3.lnk
    You can use -Force to overwrite it,or move the existing file first

    .EXAMPLE
    # 使用Force参数强制覆盖已有的同名链接文件(如果已经有了的话)
    PS> New-Shortcut -Path demo4 -TargetPath C:\repos\scripts\PS\Startup\startup.ps1 -Arguments  '-Nologo -NoProfile' -Force
            The shortcut file name must has a suffix of .lnk or .url
    [C:\Users\cxxu\Desktop\demo4.lnk] will be used

    Check action result:

    FullName         : C:\Users\cxxu\Desktop\demo4.lnk
    Arguments        : -Nologo -NoProfile
    Description      : 09/22/2024 11:46:37
    Hotkey           :
    IconLocation     : ,0
    RelativePath     :
    TargetPath       : C:\repos\scripts\PS\Startup\startup.ps1
    WindowStyle      : 1
    WorkingDirectory :

    PS[BAT:69%][MEM:27.74% (8.79/31.70)GB][12:01:38]
    # [~\Desktop]
    PS> ls

            Directory: C:\Users\cxxu\Desktop


    Mode                LastWriteTime         Length Name
    ----                -------------         ------ ----
    -a---         2024/1/17     10:31           1411   blogs_home.lnk
    -a---         2024/4/21     21:35            715   DCIM.lnk
    -a---         2024/4/28     12:01           1000   demo3.lnk
    -a---         2024/4/16     12:10           1453   EM.lnk
    -a---         2024/4/16     12:10           1439   Math.lnk
    -a---         2024/4/21     22:47           4874   scratch@bugs.md
    -a---         2024/3/22     16:35           1421   Todo.lnk


    PS[BAT:69%][MEM:27.70% (8.78/31.70)GB][12:01:46]
    # [~\Desktop]
    PS> get-ShortcutLinkInfo .\demo3.lnk

    FullName         : C:\Users\cxxu\Desktop\demo3.lnk
    Arguments        : -Nologo -NoProfile
    Description      :
    Hotkey           :
    IconLocation     : ,0
    RelativePath     :
    TargetPath       : C:\repos\scripts\PS\Startup\startup.ps1
    WindowStyle      : 1
    WorkingDirectory :


    .EXAMPLE
    # 设置一个快捷方式,保存在桌面,效果为调用 Typora 打开某个文件夹
    PS[BAT:69%][MEM:27.32% (8.66/31.70)GB][12:04:02]
    # [~\Desktop]
    PS> New-Shortcut -path C:\Users\cxxu\desktop\linux_blogs.lnk -TargetPath 'C:\Program Files\typora\Typora.exe' -Arguments C:\repos\blogs\Linux
    Shortcut created at C:\Users\cxxu\desktop\linux_blogs.lnk

    PS[BAT:69%][MEM:27.33% (8.66/31.70)GB][12:04:52]
    # [~\Desktop]
    PS> ls .\linux_blogs.lnk

            Directory: C:\Users\cxxu\Desktop


    Mode                LastWriteTime         Length Name
    ----                -------------         ------ ----
    -a---         2024/4/28     12:04           1007   linux_blogs.lnk


    PS[BAT:69%][MEM:27.34% (8.67/31.70)GB][12:05:00]
    # [~\Desktop]
    PS> Get-ShortcutLinkInfo .\linux_blogs.lnk

    FullName         : C:\Users\cxxu\Desktop\linux_blogs.lnk
    Arguments        : C:\repos\blogs\Linux
    Description      :
    Hotkey           :
    IconLocation     : ,0
    RelativePath     :
    TargetPath       : C:\Program Files\Typora\Typora.exe
    WindowStyle      : 1
    WorkingDirectory :

    .EXAMPLE
    # 创建上帝模式的快捷方式
    $GodModeFolderGUID = 'ED7BA470-8E54-465E-825C-99712043E01C'
    $GodModePath = "shell:::{$GodModeFolderGUID}"
    New-shortcut -path "$home\desktop\GodMode.lnk" -TargetPath 'explorer.exe' -Arguments $GodModePath -Force -TargetPathAsAppName
    
    #执行结果:
    explorer.exe
    Shortcut created at C:\Users\cxxu\Desktop\GodMode.lnk

    FullName         : C:\Users\cxxu\Desktop\GodMode.lnk
    Arguments        : shell:::{ED7BA470-8E54-465E-825C-99712043E01C}
    Description      :
    Hotkey           :
    IconLocation     : ,0
    RelativePath     :
    TargetPath       : C:\WINDOWS\explorer.exe
    WindowStyle      : 1
    WorkingDirectory :
    .EXAMPLE
    #创建一个powershell脚本的快捷方式
    #powershell脚本文件的后缀是.ps1,但是windows系统对于powershell脚本文件默认是不会直接执行的,甚至不会识别出`.ps1`后缀的文件应该调用自带的windows powershell还是用户安装的新版powershell(pwsh)
    而是用快捷方式局面将变得不一样,因为快捷方式可以指定要启动或打开的软件以及启动参数,因此可解决掉打开方式的问题
    PS> $startup_user='C:\Users\cxxu\AppData\Roaming\Microsoft\windows\Start Menu\programs\Startup'
    PS> New-Shortcut -Path $startup_user\startup.lnk  -TargetPath pwsh -TargetPathAsAppName   -Arguments $scripts\ps\startup\startup.ps1 -Force

    Check action result:

    FullName         : C:\Users\cxxu\AppData\Roaming\Microsoft\windows\Start Menu\programs\Startup\startup.lnk
    Arguments        : C:\repos\scripts\ps\startup\startup.ps1
    Description      :
    Hotkey           :
    IconLocation     : ,0
    RelativePath     :
    TargetPath       : C:\Program Files\PowerShell\7\pwsh.exe
    WindowStyle      : 1
    WorkingDirectory :
    .EXAMPLE
    设置scoop安装的typora为markdown文件所在目录的打开方式
    PS> New-Shortcut -Path $HOME\desktop\Mathx -TargetPath typora.exe -Arguments C:\repos\blogs\Courses\Math\ -IconLocation C:\ProgramData\scoop\apps\typora\current\resources\assets\app.ico -Force -TargetPathAsAppName

    .EXAMPLE
    #创建一个任务管理器的快捷方式,直接指定taskmger作为TargetPath(需要配合ResolveTargetPath选项),默认打开最大化 显示创建过程中的信息,强制创建
    PS> new-Shortcut -Path tsk -TargetPath taskmgr -WindowStyle Maximized -Force -ResolveTargetPath
        The shortcut file name must has a suffix of .lnk or .url
    [C:\Users\cxxu\Desktop\tsk.lnk] will be used

    Check action result:

    FullName         : C:\Users\cxxu\Desktop\tsk.lnk
    Arguments        :
    Description      : 09/22/2024 12:13:03
    Hotkey           :
    IconLocation     : ,0
    RelativePath     :
    TargetPath       : C:\WINDOWS\system32\taskmgr.exe
    WindowStyle      : 3
    WorkingDirectory :

    .EXAMPLE
    创建taskmgr的快捷方式,这里没有指定TargetPathAsAppName选项，函数内部会推荐你尝试将TargetPath作为可执行程序名(用户可能经常会忘记使用TargetPathAsAppName选项)
    PS> new-Shortcut -Path tsk -TargetPath taskmgr -WindowStyle Minimized  -Force -Verbose -TargetPathAsAppName
    VERBOSE: The path []  is converted to absolute path: [C:\Users\cxxu\Desktop\tsk]
    Try Consider the targetPath as a callable name:@{Source=C:\WINDOWS\system32\Taskmgr.exe}

    Key                 Value
    ---                 -----
    Path                tsk
    TargetPath          taskmgr
    WindowStyle         Minimized
    Force               True
    Verbose             True
    TargetPathAsAppName True

            The shortcut file name must has a suffix of .lnk or .url
    VERBOSE:        The .lnk extension is used by default
    [C:\Users\cxxu\Desktop\tsk.lnk] will be used
    VERBOSE: WindowStyle: 7

    Check action result:

    FullName         : C:\Users\cxxu\Desktop\tsk.lnk
    Arguments        :
    Description      : 09/22/2024 16:28:53
    Hotkey           :
    IconLocation     : ,0
    RelativePath     :
    TargetPath       : C:\WINDOWS\system32\taskmgr.exe
    WindowStyle      : 7
    WorkingDirectory :
  
    .EXAMPLE
    创建声音设置控制面板(sound)
    PS> New-Shortcut -Path $home/desktop/snd -TargetPath control -Arguments '/name Microsoft.sound'
    TargetPath is not a available path: control
    Try with Option  -TargetPathAsAppName?[y/n](default y to continue):
    Try Consider the targetPath as a callable name:@{Source=C:\WINDOWS\system32\control.exe}
            The shortcut file name must has a suffix of .lnk or .url
    [C:\Users\cxxu/desktop/snd.lnk] will be used

    Check action result:

    FullName         : C:\Users\cxxu\desktop\snd.lnk
    Arguments        : /name Microsoft.sound
    Description      : 09/22/2024 17:59:07
    Hotkey           :
    IconLocation     : ,0
    RelativePath     :
    TargetPath       : C:\WINDOWS\system32\control.exe
    WindowStyle      : 1

    .EXAMPLE
    在桌面上创建可选功能配置控制面板的快捷方式
    PS>  New-Shortcut -Path $home/desktop/windows可选功能配置 -TargetPath optionalfeatures.exe -Force
    #>

    [CmdletBinding()]
    param (
        # 快捷方式要存放的路径
        [string]$Path = '.',

        # 快捷方式指向的目标(目录或文件,可以是课执行程序文件或代码文件)
        [alias('Destination')][string]$TargetPath,

        # 快捷方式启动参数(当TargetPath为可执行程序时并且接受命令行参数时有用)
        [string]$Arguments = '',
        # 快捷方式的工作目录,部分可执行程序对于工作目录比价敏感,这时候指定工作目录比较有用
        [string]$WorkingDirectory = '',
        # 指定快捷方式的图标,比较少使用此参数,如果快捷方式的图标有问题，或者想要其他的非默认图标,可以使用此参数指定
        $IconLocation = '',

        # 指定快捷方式的目标是一个可执行程序的名字,而不是一个目录或文件的路径
        # 用户可能经常会忘记使用TargetPathAsAppName选项,函数会向用户做出决策推荐
        [switch]
        [alias('ResolveTargetPath')]
        $TargetPathAsAppName,

        # 指定快捷方式的快捷键启动(主要针对放在桌面上的快捷方式)
        $HotKey = '',
        # 对快捷方式的描述
        $Description = "$(Get-Date)",
        # 窗口样式(1为普通，3为最大化，7为最小化),默认为1;此参数不一定有效,例如shell窗口一般有效
        [ValidateSet('Normal', 'Maximized', 'Minimized')]
        $WindowStyle ,
        # 如果已经存在同名快捷方式,使用Force选项覆盖已经存在的快捷方式
        [switch]$Force
    )
    # 处理快捷方式各个属性值
    # 虽然快捷方式仅支持绝对路径,这里尝试获取$Path的绝对路径,将函数间接支持相对路径
    # $Path = Convert-Path $Path #无法解析尚不存在的路径,另寻它法
    if ((Get-PathType $Path ) -eq 'RelativePath')
    {
        $RawPath
        $Path = Join-Path -Path $PWD -ChildPath $Path
        Write-Verbose "The path [$RawPath]  is converted to absolute path: [$Path]"
        
    }
    # 如果不指定为AppName的话，尝试解析传入的TargetPath

    if (! $TargetPathAsAppName)
    {
        # 尝试将TargetPath作为一个路径来解析(同一成绝对路径的形式)
        $TargetPathAbs = Convert-Path $TargetPath -ErrorAction SilentlyContinue
        if (! $TargetPathAbs)
        {
            # 如果解析失败,很可能是用户直接输入了一个可执行程序的名字,那么尝试将它作为可执行程序的名字来处理(也就是不用修改TargetPath)
            Write-Host "TargetPath is not a available path: $TargetPath;You can try the option -TargetPathAsAppName to run it" -ForegroundColor DarkGray
            # 向用户确认是否尝试推荐的决策(这一块代码不是必须的,完全可以要求用户重新追加参数再次执行命令)
            # 为了方便起见,这里加入了交互式的询问
            $Continue = Read-Host -Prompt 'Try with Option  -TargetPathAsAppName?[y/n](default y to continue)'
            if ($Continue.ToLower() -eq 'y' -or $Continue.Trim() -eq '')
            {
                # 报告更改后的行为是如何的
                $TargetPathAsAppName = $true
            
            }
            else
            {
                # 用户放弃推荐的决策,结束函数
                return
            }
        
        }
    }
    # 这里两个if顺序有讲究(如果前面没有指定TargetPathAsAppName,但是函数认为用户很可能会使用TargetPathAsAppName选项,那么会把$TargetPathAsAppName设置为$True)
    if ($TargetPathAsAppName)
    {
        # 如果TargetPath是一个程序名字(而不是路径),那么可以原原本本的传递给TargetPath属性就行(前提是命令中直接输入此名字的换可以打开某个文件或者程序)
        # pass
        # $TargetPathAbs = Convert-Path $TargetPath -ErrorAction SilentlyContinue
        
        $detail = $(Get-Command $TargetPath -ErrorAction Stop | Select-Object Source )  
        # try
        # {

        # }
        # catch
        # {
        #     return
        # }

        Write-Host "Try Consider the targetPath as a callable name: ${Detail} " -ForegroundColor Cyan
    }

 
    
    if ($VerbosePreference)
    {
        $PSBoundParameters | Format-Table
    }

    # Write-Host $TargetPath

    # 设置快捷方式取名
    if (!($Path -match '.*\.(lnk|url)$'))
    {
        
        $indent = "`t"
        Write-Host "${indent}The shortcut file name must has a suffix of .lnk or .url" -ForegroundColor Magenta

        Write-Verbose "${indent}The .lnk extension is used by default "

        $Path = "$Path.lnk"
        Write-Host "[$Path] will be used"
    }
    # 检查文件是否存在,根据Force参数决定是否覆盖
    if (Test-Path $Path)
    {
        if ($Force)
        {
            Remove-Item $Path -Force
            # Write-Host $Path 'exist!,Force to remove it'
            # 事实上,如果不移除的话,也会被直接覆盖
        }
        else
        {
            Write-Error "File already exists: $Path"
            return 'You can use -Force to overwrite it,or move the existing file first'
        }
    }
    else
    {
        # Write-Host $path 'does not exist!'
    }
    # Write-Host -BackgroundColor Green $TargetPath

    # 设置对象
    $TargetPath = Get-PathStyle $TargetPath -Verbose
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.createShortcut($Path)
    $Shortcut.TargetPath = $TargetPath
    $Shortcut.Hotkey = $HotKey
    $Shortcut.Description = $Description

    #如果语句是 $Shortcut.TargetPath = 'string example',则会被拼接为"$env:userprofile/desktop/string example";这是api决定的
    # 事实上,快捷方式是针对计算机上的某个位置(资源)的快捷访问方式,而不是对于一个字符串做访问,因此targetPath参数不要设置为非路径或者软件名的字符串,否则会出现意外的效果,而且本身也没有意义,例如将数字123设置为一个快捷方式的目标路径,通常是没有意义的,除非您的桌面上恰好有一个文件或目录名为123
    $Shortcut.Arguments = $Arguments

    if ($WindowStyle )
    {

        $windowStyleCode = switch ($WindowStyle)
        {
            'Maximized' { 3 }
            'Minimized' { 7 }
            Default { 1 }
        }
        Write-Verbose "WindowStyle: $windowStyleCode"
        $Shortcut.WindowStyle = $windowStyleCode
    }
    # 以下属性如果默认置空容易报错,这里将他们放到分支中,当参数不为空时才设置
    if ($WorkingDirectory -ne '')
    {
        $Shortcut.WorkingDirectory = $WorkingDirectory
    }
    if ($IconLocation)
    {
        
        $Shortcut.IconLocation = $IconLocation
    }
    $Shortcut.Save()

    # Release the COM object when done
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WshShell) | Out-Null
    Remove-Variable WshShell

    Write-Host ''
    Write-Host 'Check action result:' -ForegroundColor Cyan
    # debug
    Get-ShortcutLinkInfo $Path
}




function Get-ShortcutLinkInfoBasic
{
    <# 
    .SYNOPSIS
    获取主要的信息(通常我们对快捷方式的跳转目录最感兴趣)
    主要应用于开始菜单中固定的常用程序的快捷方式,从中提取跳转的目标路径 #>
    param (
        $Path
    )
    $res = (Get-ShortcutLinkInfo $Path | Select-Object TargetPath)
    $targetPath = $res.targetPath
    $targetPath | Set-Clipboard
    # $targetPath
    Write-Output "$res`n🎈 the targetPath was set to clipboard!"
    #我将快捷方式的目标路径复制到剪切板中
}
function getShortcutTargetPath
{
    <# 
    .SYNOPSIS
    获取主要的信息(通常我们对快捷方式的跳转目录最感兴趣)
    .EXAMPLE
    PS C:\ProgramData\Microsoft\Windows\Start Menu\Programs> Get-ShortcutLinkInfoBasic .\yyy.lnk|cd      
    PS C:\repos\CCSER> 
    #>
    param (
        $Path
    )
    $res = (Get-ShortcutLinkInfo $Path | Select-Object TargetPath)
    $targetPath = $res.targetPath
    $targetPath | Set-Clipboard
    $targetPath
}

function Get-ShortcutTargetDir
{
    <# 
.SYNOPSIS
根据解析指定的快捷方式,如果该快捷方式是一个目录则直接返回该目录
否则该快捷方式是指向一个文件,那么会被解析成目标文件所在的目录
.EXAMPLE
PS C:\ProgramData\Microsoft\Windows\Start Menu\Programs> Get-ShortcutTargetDir '.\Word.lnk' |cd
PS C:\Program Files\Microsoft Office\root\Office16> Get-ShortcutTargetDir C:\Users\cxxu\desktop\test.lnk |cd
PS C:\repos>
    #>
    param (
        $Path
    )
    $target = (getShortcutTargetPath $Path)

    #slow method:
    # $targetType = (Get-Item $target)
    # if ($targetType -is [System.IO.fileInfo])
    # {
    #     return $targetType.DirectoryName 
    # }

    #faster method:
    if ( [System.IO.File]::Exists($target))
    {
        $targetFileInfo = [System.IO.FileInfo]$target
        return $targetFileInfo.DirectoryName 
    }
    #  | ForEach-Object { $_.DirectoryName }#ok,too
    return $target

}

function Set-Shortcut
{
    <# 
    .SYNOPSIS
    对已存在的快捷方式进行修改
    如果不存在相应快捷方式,则创建一个TODO #>
    param(
        $Path,
        $TargetPath,
        $Description = "Edited by $env:username $(Get-DateTimeNumber)",
        $argumentsProp = '',
        $hotkeyProp = '',
        $WindowStyleProp = '',
        $IconLocation = ''
    )
    $shortcut = Get-ShortcutLinkInfo($Path)
    # $Path对应的快捷方式不存在时,该函数会返回一个快捷方式对象,不会报错
    $shortcut.TargetPath = $TargetPath
    $shortcut.Description = $Description
    if ($Path)
    {
        if (!(Test-Path $Path))
        {
            
            New-Item -ItemType File -Path $Path
        }
        $shortcut.FullName = (Resolve-Path $Path)
    }
    #处理次要属性
    if ($hotkeyProp)
    {
        $shortcut.HotKey = $hotkeyProp
    }
    if ($argumentsProp)
    {
        $shortcut.Arguments = $argumentsProp
    }
    if ($WindowStyleProp)
    {
        $shortcut.WindowStyle = $WindowStyleProp
    }
    if ($IconLocationProp)
    {
        $shortcut.IconLocation = $IconLocationProp
    }
    
    # save changes
    $shortcut.Save()
    if (Test-Path $Path)
    {

        Get-ShortcutLinkInfoBasic -Path $Path
    }
    else
    {
        Write-Error 'The shortcut was not created!'
    }
}
function Set-ShortcutIcons
{
    
    $icon_cache_db = "$USERPROFILE\appdata\local\IconCache.db"
    if (Test-Path $icon_cache_db)
    {
        # Set-Location $env:USERPROFILE\appdata\local
        Remove-Item $icon_cache_db -Force
        # restartExplorer
        Stop-Process -Name explorer
        Write-Output 'operation done!'

    }
    else
    {
        Write-Output "fix operation passed!`n there is no file@ { $icon_cache_db }!"
    }
}

function Get-ShortcutPath
{
    param(
        $shortcut,
        [switch]$SendToClipboard
    )
    $s = Get-Command $shortcut | Select-Object -ExpandProperty Definition
    if (!$s.EndsWith('exe'))
    {
        $s += '.exe'
    }
    
    $s = (Resolve-Path $s)

    return $s
    


}