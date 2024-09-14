
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

    .EXAMPLE
    
    PS[BAT:69%][MEM:27.80% (8.81/31.70)GB][12:01:17]
    # [~\Desktop]
    PS> new-Shortcut -Path demo3 -TargetPath C:\repos\scripts\PS\Startup\startup.ps1 -Arguments  '-Nologo -NoProfile'
            The shortcut file name must has a suffix of .lnk or .url
            The .lnk extension is used by default
    [C:\Users\cxxu\Desktop\demo3.lnk] will be used
    New-Shortcut: File already exists: C:\Users\cxxu\Desktop\demo3.lnk
    You can use -Force to overwrite it,or move the existing file first

    .EXAMPLE
    PS[BAT:69%][MEM:27.79% (8.81/31.70)GB][12:01:20]
    # [~\Desktop]
    PS> new-Shortcut -Path demo3 -TargetPath C:\repos\scripts\PS\Startup\startup.ps1 -Arguments  '-Nologo -NoProfile' -Force
            The shortcut file name must has a suffix of .lnk or .url
            The .lnk extension is used by default
    [C:\Users\cxxu\Desktop\demo3.lnk] will be used
    Shortcut created at C:\Users\cxxu\Desktop\demo3.lnk

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
    new-shortcut -path "$home\desktop\GodMode.lnk" -TargetPath 'explorer.exe' -Arguments $GodModePath -Force -TargetPathAsAppName
    
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
    
    #>

    param (
        [string]$TargetPath,
        [string]$Path = '.',
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        $IconLocation = '',
        [switch]$TargetPathAsAppName,
        $HotKey = '',
        [switch]$Force
    )
    # 处理快捷方式各个属性值
    if ((Get-PathType $Path ) -eq 'RelativePath')
    {
        
        $Path = Join-Path -Path $PWD -ChildPath $Path
 
    }
    # $Path = Resolve-Path $Path
    if (! $TargetPathAsAppName)
    {
        $TargetPath = Resolve-Path $TargetPath
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
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.createShortcut($Path)
    # debug TargetPath property
    $Shortcut.TargetPath = $TargetPath
    $Shortcut.Hotkey = $HotKey
    $Shortcut.IconLocation = $IconLocation
    #如果语句是 $Shortcut.TargetPath = 'string example',则会被拼接为"$env:userprofile/desktop/string example";这是api决定的
    # 事实上,快捷方式是针对计算机上的某个位置(资源)的快捷访问方式,而不是对于一个字符串做访问,因此targetPath参数不要设置为非路径或者软件名的字符串,否则会出现意外的效果,而且本身也没有意义,例如将数字123设置为一个快捷方式的目标路径,通常是没有意义的,除非您的桌面上恰好有一个文件或目录名为123
    $Shortcut.Arguments = $Arguments

    if ($WorkingDirectory -ne '')
    {
        $Shortcut.WorkingDirectory = $WorkingDirectory
    }
    $Shortcut.Save()

    # Release the COM object when done
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WshShell) | Out-Null
    Remove-Variable WshShell

    Write-Host ''
    Write-Host 'Check action result:' -ForegroundColor Blue
    # debug
    Get-ShortcutLinkInfo $Path
}

# 使用示例：
# New-Shortcut -TargetPath "C:\Path\To\Your\Application.exe" -Path "C:\Users\Public\Desktop\Application.lnk"



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