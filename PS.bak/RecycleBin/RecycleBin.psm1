<#
.SYNOPSIS   
Function that shows the contents of the Recycle Bin

.DESCRIPTION 
This function is intended to compliment the Clear-RecycleBin cmdlet, which does not provide any functionality to view the files that are stored in the Recycle-Bin

.NOTES   
Name: Get-RecycleBin
Author: Jaap Brasser
DateCreated: 2015-09-24
DateUpdated: 2015-09-24
Version: 1.0
Blog: http://www.jaapbrasser.com

.LINK
https://github.com/jaapbrasser/SharedScripts/blob/master/Clear-RecycleBin/Clear-RecycleBin.ps1

.EXAMPLE
. .\Get-RecycleBin.ps1

Description
-----------
This command dot sources the script to ensure the Get-RecycleBin function is available in your current PowerShell session

.EXAMPLE
Get-RecycleBin

Description
-----------
Executing this function will display the name, size and path of the files stored in the Recycle Bin for the current user
#>
function Get-RecycleBin
{
    (New-Object -ComObject Shell.Application).NameSpace(0x0a).Items() |
    Select-Object Name, Size, Path
}

function Move-ToRecycleBinDir
{
    <# 
    .SYNOPSIS
    代替powershell默认的remove-item命令
    部分想要直接彻底删除的时候,请使用remove-item命令,而不是使用rm命令,这个别名被分配给Move-ToRecycleBinDir
    #>
    param(
        $path
    )
    Update-PwshEnvIfNotYet -Mode Vars
    
    if (!(Test-Path $recycleBinDir))
    {
        mkdir $recycleBinDir -Force -Verbose
    }
    Move-ItemWithTimestampIfNeed -Path $path -Target $RecycleBinDir 

}
function Move-ItemWithTimestampIfNeed
{
    <# 
    .SYNOPSIS
    移动某个文件或目录到指定位置,如果指定的位置(目录)中没有该文件,那么直接移动,否则在目标目录中创建一个新名字,由原名字追加移动时的时间戳

    .DESCRIPTION
    参考move-item命令,移动$Path时,如果$Destination中间目录不存在,将会失败
    这里可以延续这种特点,也可以改进
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        # 将$path指示的文件或目录移动到指定目录中(Target参数是目录而不应该是文件,新位置的文件名由时间戳是否追加在原名为区别)
        # 否则功能和move-item命令重合了
        [Alias('DestinationDir')][string]$Target 
    )

    # 确保路径存在
    if (-not (Test-Path -Path $Path))
    {
        Write-Error "The path '$Path' does not exist."
        return
    }

    # 确保目标是一个目录
    if (Test-Path -Path $Target -PathType Leaf)
    {
        Write-Error "The target '$Target' is not a directory."
        
        return
    }
    # 统一将传入的$path处理为基础名字(如果是文件且有扩展名的,后期再带上扩展名)
    $item = Get-PsIOItemInfo -Path $Path 
    $itemBaseName = $item | Select-Object -ExpandProperty BaseName
    $itemExtension = $item | Select-Object -ExpandProperty Extension
    # 获取文件名或目录名(可以处理目录名)
    # $itemBaseName = (Resolve-Path -Path $Path ) -split '\\'
    # Get-PSIoiteminfo -Path $Path
    # $p = Resolve-Path -Path $Path
    # $p = ($p.Path)
    # # 如果末尾不是以`\`结尾也没关系,不会报错的
    # $p = $p.Trimend('\')
    
    # $itemBaseName = [System.IO.Path]::GetFileName($P)
    # Write-Output $itemBaseName
    # Write-Host $itemBaseName -BackgroundColor Blue

    # 构建目标路径
    $targetPath = Join-Path -Path $Target -ChildPath $item.Name

    # 检查目标路径是否存在同名文件或目录
    if (Test-Path -Path $targetPath)
    {
        # 获取当前时间戳
        $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
        # 添加时间戳到原名称
        $newName = "$($itemBaseName)@$($timestamp)$($itemExtension)"
        # 重建目标路径
        $targetPath = Join-Path -Path $Target -ChildPath $newName
    }

    # 移动项目到新的目标路径
    Move-Item -Path $Path -Destination $targetPath -Verbose
}

# 示例使用：
# Move-ItemWithTimestamp -Path "C:\source\myfile.txt" -Target "C:\destination"

function Clear-RecycleBinDir
{
    Get-ChildItem $RecycleBinDir -Force
    Write-Output .
    Write-Host 'Do you want to delete them permanently? ' -BackgroundColor Red
    Remove-Item $RecycleBinDir\* -Verbose -Force -Confirm
}<#
.SYNOPSIS   
Function that shows the contents of the Recycle Bin

.DESCRIPTION 
This function is intended to compliment the Clear-RecycleBin cmdlet, which does not provide any functionality to view the files that are stored in the Recycle-Bin

.NOTES   
Name: Get-RecycleBin
Author: Jaap Brasser
DateCreated: 2015-09-24
DateUpdated: 2015-09-24
Version: 1.0
Blog: http://www.jaapbrasser.com

.LINK
https://github.com/jaapbrasser/SharedScripts/blob/master/Clear-RecycleBin/Clear-RecycleBin.ps1

.EXAMPLE
. .\Get-RecycleBin.ps1

Description
-----------
This command dot sources the script to ensure the Get-RecycleBin function is available in your current PowerShell session

.EXAMPLE
Get-RecycleBin

Description
-----------
Executing this function will display the name, size and path of the files stored in the Recycle Bin for the current user
#>
function Get-RecycleBin
{
    (New-Object -ComObject Shell.Application).NameSpace(0x0a).Items() |
    Select-Object Name, Size, Path
}

# 定义名为 Move-ToRecycleBin 的函数，它接受一个必填参数（路径），用于指定要移动到回收站的文件或目录路径
function Move-ToRecycleBin
{
    <# 
    .SYNOPSIS
    模拟右键菜单中的“删除”动作，这会把文件或目录移动到回收站(考虑到命令行)
    .DESCRIPTION
    这里用的硬编码`delete`是系统界面为英文的情况;如果windows显示语言是中文,的需要改为删除(具体看自己系统右键菜单中的对应项)
    可以配置别名rm;这会代替掉powershell的默认别名(默认rm是remove-item)

    实现方式是模拟右键菜单中的“删除”动作,效率不高,一个备选的方案是
    另一个备选方案是在系统的某个位置建立一个文件夹,将其命名为“回收站”(Recycle或Trash),然后我们始终不用rm,而只使用mv(move-item)
    将需要放入回收站的文件或目录移动到这个文件夹
    然后这个目录就充当了回收站,定期清空即可(如果是磁盘做了分区,则跨磁盘或跨分区移动文件到回收站效率也不高
    而如果只有一个磁盘一个分区,可以用这个方案,并且这个方案安全高效)
    (通常为了方便起见,尽量少划分分区,许多操作的速度执行地会比较快;
    而且软件习惯把自己安装在C盘,干脆让系统只有一个C盘,或者保留一点空间给另一个磁盘而大部分空间划分个C盘)
    对于多个分区或者每个硬盘,为了保证移动操作执行速度,可以考虑每个分区分别设置一个回收站,这在使用上就不那么方便了

    #>
    param(
        # 参数名为 $path，要求在调用时必须提供，且位置索引为 0
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$path
    )

    # 检查提供的路径是否存在
    if (Test-Path $path)
    {
        # 尝试执行以下代码块
        try
        {
            # 引入需要的 .NET 组件，以便与 Windows Shell 对象模型交互
            Add-Type -AssemblyName Microsoft.VisualBasic
            Add-Type -AssemblyName System.Windows.Forms

            # 创建一个新的 Shell COM 对象实例
            $shell = New-Object -ComObject 'Shell.Application'

            # 获取路径指向的文件或目录的完整路径名，并通过 Shell Namespace 调用 ParseName 方法解析该路径
            $parsedPath = $shell.Namespace(0).ParseName((Get-Item $path).FullName)

            # 调用 InvokeVerb 方法，模拟右键菜单中的“删除”动作，这会把文件或目录移动到回收站
            $parsedPath.InvokeVerb('delete')
        }
        # 如果在尝试过程中发生错误，则捕获异常并输出错误信息
        catch
        {
            Write-Error -Message "An error occurred moving the item to the Recycle Bin: $_"
        }
    }
    else
    {
        # 如果提供的路径不存在，则输出错误信息
        Write-Error -Message "Path not found: $path"
    }
}


function Clear-RecycleBinDir
{
    Get-ChildItem $RecycleBinDir -Force
    Write-Output .
    Write-Host 'Do you want to delete them permanently? ' -BackgroundColor Red
    Remove-Item $RecycleBinDir\* -Verbose -Force -Confirm
}