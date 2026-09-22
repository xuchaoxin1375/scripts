
function Add-Extension
{
    <# 
    为满足匹配模式的文件添加后缀(扩展名)
    #>
    param(
        $pattern,
        $extension
    )
    Get-ChildItem | Where-Object { $_.Name -match $pattern } |
    ForEach-Object { rename $_.Name -NewName "$($_.Name).$extension" }
}

# --- 从 Pwsh.psm1 迁入:文件/目录度量(职责:文件系统) ---

function Get-NonEmptySubdirectories
{
    
    <#
.SYNOPSIS
    获取指定路径或管道输入中的非空子目录。

.DESCRIPTION
    该函数用于查找一个目录下的所有非空子目录（即包含文件或其他子目录的目录）。
    支持直接指定路径或通过管道传入目录对象。
    可选择递归搜索所有层级目录。

.PARAMETER Path
    [必需，位置0] 要检查的根目录路径。

.PARAMETER InputObject
    [管道输入] 接收来自管道的 [System.IO.DirectoryInfo] 对象（如 Get-ChildItem -Directory 的输出）。

.PARAMETER Recurse
    [可选] 如果指定此参数，则递归搜索所有嵌套层级的子目录；否则仅检查第一级子目录。

.EXAMPLE
    # 示例1：获取当前目录下所有非空的一级子目录
    Get-NonEmptySubdirectories -Path "C:\Example\Path"

    # 示例2：获取当前目录下所有层级中非空的子目录
    Get-NonEmptySubdirectories -Path "C:\Example\Path" -Recurse

    # 示例3：通过管道获取非空目录
    Get-ChildItem "C:\Example\Path" -Directory | Get-NonEmptySubdirectories

.INPUTS
    [string] 指定一个存在的目录路径。
    [System.IO.DirectoryInfo[]] 来自管道的对象（如 Get-ChildItem -Directory 输出）

.OUTPUTS
    [string[]] 返回一个或多个非空子目录的完整路径。
#>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [System.IO.DirectoryInfo[]]$InputObject,

        [switch]$Recurse
    )

    begin
    {
        $directories = @()
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'Path')
        {
            if (-not (Test-Path -Path $Path))
            {
                Write-Error "路径不存在: $Path"
                return
            }

            $getChildItemParams = @{
                Path      = $Path
                Directory = $true
            }
            if ($Recurse)
            {
                $getChildItemParams['Recurse'] = $true
            }

            $directories += Get-ChildItem @getChildItemParams
        }
        else
        {
            foreach ($dir in $InputObject)
            {
                $directories += $dir
            }
        }
    }

    end
    {
        foreach ($dir in $directories)
        {
            $items = Get-ChildItem -Path $dir.FullName -Force -ErrorAction SilentlyContinue
            if ($null -ne $items)
            {
                $dir.FullName
            }
        }
    }
}


function Remove-EmptyDirectories
{
    <#
.SYNOPSIS
    删除一个或多个空目录。

.DESCRIPTION
    该函数用于删除一个目录中的所有空子目录。默认仅检查一级子目录，也可以通过 -Recurse 递归查找。
    支持从路径或管道输入目录对象。
    空目录是指不包含任何文件或子目录的目录（即使有隐藏文件也被视为“非空”）。

.PARAMETER Path
    [必需，位置0] 要检查并从中删除空目录的根路径。

.PARAMETER InputObject
    [管道输入] 接收来自管道的 [System.IO.DirectoryInfo] 对象（如 Get-ChildItem -Directory 的输出）。

.PARAMETER Recurse
    [可选] 如果指定此参数，则递归检查所有层级的子目录。

.PARAMETER Force
    [可选] 删除具有隐藏或只读属性的目录。

.PARAMETER WhatIf
    显示将要执行的操作，但不实际执行删除。

.PARAMETER Confirm
    在删除每个目录前提示确认。

.EXAMPLE
    # 删除 C:\Temp 中的所有空子目录（不递归）
    Remove-EmptyDirectories -Path "C:\Temp"

    # 删除 C:\Temp 中所有层级的空目录
    Remove-EmptyDirectories -Path "C:\Temp" -Recurse

    # 删除所有名称为 temp 的子目录
    Get-ChildItem "C:\Projects" -Directory -Recurse | Where-Object Name -eq "temp" | Remove-EmptyDirectories -Force

.INPUTS
    [string] 指定一个存在的目录路径。
    [System.IO.DirectoryInfo[]] 来自管道的对象（如 Get-ChildItem -Directory 输出）

.OUTPUTS
    无输出，除非使用 Write-Verbose 或 Write-Warning。
#>
    [CmdletBinding(DefaultParameterSetName = 'Path', SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [System.IO.DirectoryInfo[]]$InputObject,

        [switch]$Recurse,
        [switch]$Force
    )

    begin
    {
        $directories = @()
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'Path')
        {
            if (-not (Test-Path -Path $Path))
            {
                Write-Error "路径不存在: $Path"
                return
            }

            $getChildItemParams = @{
                Path      = $Path
                Directory = $true
            }
            if ($Recurse)
            {
                $getChildItemParams['Recurse'] = $true
            }

            $directories += Get-ChildItem @getChildItemParams
        }
        else
        {
            foreach ($dir in $InputObject)
            {
                $directories += $dir
            }
        }
    }

    end
    {
        foreach ($dir in $directories)
        {
            try
            {
                $items = Get-ChildItem -Path $dir.FullName -Force -ErrorAction Stop
                if ($null -eq $items)
                {
                    if ($PSCmdlet.ShouldProcess($dir.FullName, "删除空目录"))
                    {
                        [System.IO.Directory]::Delete($dir.FullName, $false)
                        Write-Verbose "已删除空目录: $($dir.FullName)"
                    }
                }
            }
            catch
            {
                Write-Warning "无法访问目录 '$($dir.FullName)': $_"
            }
        }
    }
}

function Get-PsIOItemInfo
{
    <# 
    .SYNOPSIS
    获取文件或目录的.Net对象(路径对象),传入的Path对应的是文件,则返回[System.IO.FileInfo]对象，
    传入的Path对应的是目录,则返回[System.IO.DirectoryInfo]对象
    .EXAMPLE
    获取某个目录的路径对象
    PS C:\repos\scripts> 
    Get-PsIOItemInfo ./                                                                               

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    da---           2024/7/29    23:23                scripts


    PS [C:\repos\scripts]> Get-PsIOItemInfo .\PS\

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    da---           2024/7/29     9:10                PS
    .EXAMPLE
    PS [C:\repos\scripts]> (Get-PsIOItemInfo .\PS\).fullname
    C:\repos\scripts\PS\

    .EXAMPLE
    获取某个文件的路径对象
    PS [C:\repos\scripts]> Get-PsIOItemInfo .\readme_zh.md

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    -a---           2024/7/29    21:58            581 readme_zh.md
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path $Path)
    {
        if (Test-Path $Path -PathType Leaf)
        {
            # 如果是文件，返回 [System.IO.FileInfo] 对象
            return [System.IO.FileInfo]::new($Path)
        }
        elseif (Test-Path $Path -PathType Container)
        {
            # 如果是目录，返回 [System.IO.DirectoryInfo] 对象
            return [System.IO.DirectoryInfo]::new($Path)
        }
    }
    else
    {
        Write-Error "The path '$Path' does not exist."
    }
}


function Get-Size
{
    <#
    .SYNOPSIS
    计算指定文件或目录的大小。

    .DESCRIPTION
    此函数计算指定路径的文件或目录的大小。对于目录，它会递归计算所有子目录和文件的总大小。
    函数支持以不同的单位（如 B、KB、MB、GB、TB）显示结果。

    .NOTES
    次函数遇到Path为目录的情况时,使用的是ls 的-recurse参数,不需要自己编写循环遍历,也不便使用进度计数
    而内部的process块内对$path做遍历是为了支持管道符,也就是形如ls *|Get-Size的方式调用,这时候$Path会是一个数组,对其做遍历

    .PARAMETER Path
    要计算大小的文件或目录的路径。可以是相对路径或绝对路径。

    .PARAMETER Unit
    指定结果显示的单位。可选值为 B（字节）、KB、MB、GB、TB。默认为 MB。

    #>

    <# 
    .EXAMPLE
    Get-Size -Path "C:\Users\Username\Documents"
    计算 Documents 文件夹的大小，并以默认单位（MB）显示结果。

    .EXAMPLE
    Get-Size -Path "C:\large_file.zip" -Unit GB
    计算 large_file.zip 文件的大小，并以 GB 为单位显示结果。

    .EXAMPLE
    "C:\Users\Username\Downloads", "C:\Program Files" | Get-Size -Unit MB
    计算多个路径的大小，并以 MB 为单位显示结果。
    .EXAMPLE
    指定显示单位为KB ,显示5位小数
    PS> Get-Size -SizeAsString -Precision 5 -Unit KB

    Mode  BaseName Size      Unit
    ----  -------- ----      ----
    da--- PS       563.93848 KB
    .EXAMPLE
    保留3位小数(但是显示位数保持默认的2位),使用管道符`|fl`来查看三位小数
    PS> Get-Size -Precision 3 -Unit KB

    Mode  BaseName   Size Unit
    ----  --------   ---- ----
    da--- PS       564.14 KB
    .EXAMPLE
    PS> Get-Size -Precision 3 -Unit KB|fl

    Mode     : da---
    BaseName : PS
    Size     : 564.408
    Unit     : KB
    
    .EXAMPLE
    指定显示精度为4为小数(由于这里恰好第3,4位小数为0,所以没有显示出来,指定更多位数,可以显示)
    PS🌙[BAT:79%][MEM:44.52% (14.12/31.71)GB][0:03:01]
    # [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\PS]
    PS> Get-Size -SizeAsString -Precision 4

    Mode  BaseName Size Unit
    ----  -------- ---- ----
    da--- PS       0.55 MB

    指定显示精度为5为小数
    PS🌙[BAT:79%][MEM:44.55% (14.13/31.71)GB][0:03:05]
    # [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\PS]
    PS> Get-Size -SizeAsString -Precision 5

    Mode  BaseName Size    Unit
    ----  -------- ----    ----
    da--- PS       0.55002 MB

    .INPUTS
    System.String[]
    你可以通过管道传入一个或多个字符串路径。

    .OUTPUTS
    PSCustomObject
    返回一个包含路径、大小和单位的自定义对象。

    #>

    [CmdletBinding()]
    param(
        [Parameter( ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$Path = '.',
        # [switch]$ItemType,
        [Parameter(Mandatory = $false)]
        [ValidateSet('B', 'KB', 'MB', 'GB', 'TB')]
        [string]$Unit = 'MB',

        #文件大小精度
        $Precision = 2,
        [switch]$SizeAsString,
        [switch]$Detail,
        [switch]$FormatTable
    )
    
    begin
    {
        if ($VerbosePreference)
        {
            # 即使外部不显示传入-Verbose参数,也会显示Verbose信息
            $PSBoundParameters | Format-Table  
            
        }
        # 大小单位换算(倍率)
        $unitMultiplier = @{
            'B'  = 1
            'KB' = 1KB
            'MB' = 1MB
            'GB' = 1GB
            'TB' = 1TB
        }
        #进度计数器($PSStyle 仅 7.2+,5.1 无此变量,守卫后静默跳过)
        if ($PSVersionTable.PSVersion.Major -ge 7)
        {
            $PSStyle.Progress.View = 'Classic'
        }
        $items = Get-ChildItem $path
        $count = $items.count
        Write-Verbose "$count Path(s) will be processed" 
    }

    process
    {
        # $i = 0

        foreach ($item in $Path)
        {
            # 增加write-progress支持
                
            # Write-Verbose "Calculating size of directory $item"
            # if ($count -gt 1)
            # {

            #     $Completed = ($i / $count) * 100
            #     # 精度控制
            #     $Completed = [math]::Round($Completed, 1)
            #     Write-Host "$i ,$Completed"
            #     Write-Progress -Activity "Calculating size of $item" -Status "Progress: $Completed %" -PercentComplete $Completed
            #     $i += 1
            # }
            # 模拟耗时逻辑检查进度条功能
            # Start-Sleep -Milliseconds 500

            if (Test-Path -Path $item)
            {
                $size = 0
                # 利用Get-item 判断$Path是文件还是目录,如果是目录,则调用ls -Recurse找到所有文件(包括子目录),然后利用管道符传递给Measure计算该子目录的大小
                $itemInfo = (Get-Item $item)
                $baseName = $itemInfo.BaseName
                $Mode = $itemInfo.Mode
                # $ItemType = $itemInfo.GetType().Name
                if ($itemInfo -is [System.IO.FileInfo])
                {
                    $ItemType = 'File'
                }
                elseif ($itemInfo -is [System.IO.DirectoryInfo])
                {
                    $ItemType = 'Directory'
                }
                # 计算$Path的一级子目录或文件的大小
                if ($itemInfo -is [System.IO.DirectoryInfo])
                {
                    $size = (Get-ChildItem -Path $item -Recurse -Force | Measure-Object -Property Length -Sum).Sum
                }
                else
                {
                    $size = (Get-Item $item).Length
                }
                # 大小单位换算
                $sizeInSpecifiedUnit = $size / $unitMultiplier[$Unit]
                Write-Verbose "`$sizeInSpecifiedUnit: $sizeInSpecifiedUnit"
                $Size = [math]::Round($sizeInSpecifiedUnit, [int]$Precision)
                Write-Verbose "`$size: $Size"
                # 制表格式输出
                if ($SizeAsString)
                {
                    $size = "$size"
                }
                $res = [PSCustomObject]@{
                    Mode     = $Mode
                    BaseName = $baseName
                    Size     = $Size #默认打印数字的时候只保留小数点后2位
                    Unit     = $Unit
                }
                $verbo = [pscustomobject]@{
                    Itemtype = $itemType
                    Path     = $item
                    
                }
                if ($Detail)
                {

                    # $res | Add-Member -MemberType NoteProperty -Name FullPath -Value (Convert-Path $item)
                    foreach ($p in $verbo.PsObject.Properties)
                    {

                        $res | Add-Member -MemberType NoteProperty -Name $p.Name -Value $p.value
                    }
                }
                # 这个选项其实有点多余,用户完全可以自己用管道符|ft获取表格试图,有更高的灵活性
                if ($FormatTable)
                {

                    $res = $res | Format-Table #数据表格化显示
                }
                return $res
            }
            else
            {
                Write-Warning "路径不存在: $item"
            }
        }
    }
    end
    {
        # return $res
    }
}

function Get-ItemSizeSorted
{
    <# 
    .SYNOPSIS
    对指定目录以文件大小从大到小排序展示其中的子目录和文件列表
    .DESCRIPTION
    继承大多数Get-Size函数的参数,比如可以指定文件文件大小的单位，大小数值保留的小数位数等(详情请参考Get-Size函数)。
    .NOTES
    这里默认不是用并行计算,如果需要启用并行计算，可以通过参数-Parallel来启用。
    
    .PARAMETER Parallel
    这里可以考虑使用并行方案进行统计,但是建议不要滥用,因为并行计算创建多线程也是需要资源和时间开销的,在文件数量不是很巨大的情况下,使用并行方案反而会降低速度,并行数量通常建议不超过3个为宜;
    .PARAMETER ThrottleLimit
    并行计算时的并发数,如果启用并行计算，ThrottleLimit参数默认为5,可以通过此参数指定为其他正整数

    .PARAMETER Path
    要排序的目录
    .PARAMETER Unit
    将文件大小单位转换为指定单位
    


    .EXAMPLE
    PS🌙[BAT:79%][MEM:44.53% (14.12/31.71)GB][0:00:19]
    # [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\PS]
    PS> get-ItemSizeSorted -Unit KB

    Mode  BaseName                          Size Unit
    ----  --------                          ---- ----
    da--- Deploy                           82.45 KB
    da--- Basic                            78.55 KB
    d---- Pwsh                             49.91 KB
    d---- TaskSchdPwsh                     40.06 KB
    #>
    [CmdletBinding()]
    param (
        $Path = '.',
        [Parameter(Mandatory = $false)]
        [ValidateSet('B', 'KB', 'MB', 'GB', 'TB')]
        [string]$Unit = 'MB',
        #文件大小精度
        $Precision = 3,
        [switch]$Detail,
        [switch]$SizeAsString,
        [switch]$FormatTable,
        [switch]$Parallel,
        $ThrottleLimit = 5
    )
    if ($VerbosePreference)
    {
        $PSBoundParameters | Format-Table
    }
    $verbose = $VerbosePreference
    if ($Parallel -and ($PSVersionTable.PSVersion.Major -ge 7))
    {
        Write-Host 'Parallel Mode.'
        # 5.1 无 ForEach-Object -Parallel,自动走下方串行分支
        $res = Get-ChildItem $Path | ForEach-Object -Parallel {
            $Unit = $using:Unit
            $Precision = $using:Precision
            $Detail = $using:Detail
            $SizeAsString = $using:SizeAsString
            $item = $_ | Get-Size -Unit $Unit -Precision $Precision -Detail:$Detail `
                -SizeAsString:$SizeAsString # -FormatTable:$FormatTable 
            
            # Write-Output $item 
            # $item | Format-Table  | Out-String 
            $verbose = $using:verbose
            if ($verbose)
            {
                Write-Host $item -ForegroundColor Cyan
            }
            return $item
        } -ThrottleLimit $ThrottleLimit
    }
    else
    {
        $i = 0
        $items = Get-ChildItem $Path
        $count = $items.count
        Write-Host 'Calculating ... '
        $res = $items | ForEach-Object {

            $item = $_ | Get-Size -Unit $Unit -Precision $Precision -Detail:$Detail -SizeAsString:$SizeAsString -Verbose:$false # -FormatTable:$FormatTable 
            
            $Completed = [math]::Round($i++ / $count * 100, 1)
            Write-Progress -Activity 'Calculating items sizes... ' -Status "Processing: $Completed%" -PercentComplete $Completed
            # Write-Host $item  -ForegroundColor Red
            # $item | Format-Table #会被视为返回值,后续的管道服sort将无法正确执行(利用break可以验证,这个语句本身没有问题,但是后续的管道无法正常执行)
            # break
            # 非-parallel脚本块,可以直接引用外部变量
            if ($VerbosePreference)
            {

                Write-Host $item
            }
            # Write-Output $item 
            return $item
        }
    }
        

    $sorted = $res | Sort-Object -Property size -Descending
    $sumUnit = ($sorted | Measure-Object -Property size -Sum).Sum
    $sumByte = $sumUnit * ([int]"1$Unit")
    # $smbBit = $sumByte * 8 #精度不够,不展示
    $sumKB = $sumByte / 1KB
    $sumMB = $sumByte / 1MB
    $sumGB = $sumByte / 1GB
    Write-Host "SUM size: $sumUnit $Unit" -ForegroundColor Magenta
    Write-Host "SUM size: $sumGB GB" -ForegroundColor Magenta
    $sumReport = [PSCustomObject]@{
        # "sum$Unit"   = $sum
        # smbBit  = $smbBit
        sumByte = $sumByte
        sumKB   = $sumKB
        sumMB   = $sumMB
        sumGB   = $sumGB
    }
    $sumReport | Format-Table

    if ($FormatTable)
    {

        $sorted = $sorted | Format-Table
    }
    return $sorted
}

function Get-ChildItemNameQuatation
{
    <# 
    .SYNOPSIS
    获取文件或者目录的名称,并添加双引号
    这是因为有时候目录中会出现一些名字奇怪的文件或目录
    他们在资源管理器中对于许多操作有不寻常的行为(比如报错)

    虽然在powershell中可以用tab 来补全文件名称,即利用ls来按下tab键,如果文件名称需要加引号,会自动加上引号
    然而这个方法并不可靠,个别情况下提示的文件名会无法被正确解析
    .EXAMPLE
    PS[BAT:76%][MEM:26.72% (8.47/31.70)GB][8:49:01]
    # [~\Downloads]
    Get-ChildItemNameQuatation

    NameQuat           FullNameQuat
    --------           ------------
    ' '                "C:\Users\cxxu\Downloads\ "
    'Compressed'       "C:\Users\cxxu\Downloads\Compressed"
    'Documents'        "C:\Users\cxxu\Downloads\Documents"
    'll'               "C:\Users\cxxu\Downloads\ll"
    'Programs'         "C:\Users\cxxu\Downloads\Programs"
    'tldr_en'          "C:\Users\cxxu\Downloads\tldr_en"
    'Video'            "C:\Users\cxxu\Downloads\Video"
    'tldr-book-en.pdf' "C:\Users\cxxu\Downloads\tldr-book-en.pdf"
    #>
    param(
        $Path = '.'
    )
    # 注:原用别名 `^`(= Select-Object,定义见 Aliases/functions),此处直写全名,
    # 否则未加载别名的新 shell 调用必错
    Get-ChildItem -Path $Path | Select-Object @{Name = 'NameQuat'; e = { "'$($_.Name)'" } }, @{Name = 'FullNameQuat'; e = { '"' + $_.fullname + '"' } }
}

# --- 从 Tools.psm1 迁入:目录判空(职责:文件系统) ---

function Test-DirectoryEmpty
{
    <# 
    .SYNOPSIS
    判断一个目录是否为空目录
    .PARAMETER directoryPath
    要检查的目录路径
    .PARAMETER CheckNoFile
    如果为true,递归子目录检查是否有文件
    #>
    param (
        [string]$directoryPath,
        [switch]$CheckNoFile
    )

    if (-not (Test-Path -Path $directoryPath))
    {
        throw "The directory path '$directoryPath' does not exist."
    }
    if ($CheckNoFile)
    {

        $itemCount = (Get-ChildItem -Path $directoryPath -File -Recurse | Measure-Object).Count
    }
    else
    {
        $items = Get-ChildItem -Path $directoryPath
        $itemCount = $items.count
    }
    return $itemCount -eq 0
}

function Remove-RobocopyMirEmpty
{
    <# 
    .SYNOPSIS
    使用 RoboCopy 多线程快速删除文件夹及其内容。

    .DESCRIPTION
    此函数利用 RoboCopy 的 /mir 参数和多线程能力快速删除文件夹及其所有内容。
    比传统的 Remove-Item 或 cmd 的 rd/del 命令在处理大量文件时更高效。

    .PARAMETER Path
    指定要删除的文件夹路径。支持相对路径和绝对路径。

    .PARAMETER ThreadCount
    指定 RoboCopy 使用的线程数。默认值为 32，可根据系统性能调整。

    .PARAMETER WhatIf
    显示将要执行的操作，但不实际执行删除。

    .PARAMETER Confirm
    在执行删除前提示确认。

    .EXAMPLE
    Remove-RobocopyMirEmpty -Path "C:\LargeFolder"
    删除 C:\LargeFolder 及其所有内容。

    .EXAMPLE
    Remove-RobocopyMirEmpty -Path ".\TempFiles" -ThreadCount 64 -WhatIf
    模拟使用64个线程删除当前目录下的 TempFiles 文件夹。

    .NOTES
    文件名: Remove-RobocopyMirEmpty.ps1
    日期: $(Get-Date -Format 'yyyy-MM-dd')

    .LINK
    https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if (-not (Test-Path -Path $_ -PathType Container))
                {
                    throw "路径 '$_' 不存在或不是文件夹"
                }
                $true
            })]
        [string]$Path,

        [Parameter()]
        [ValidateRange(1, 128)]
        [int]$ThreadCount = 32,
        $logFile = "C:/temp/robocopy_mir_empty.log"
    )

    begin
    {
        # 创建临时空目录
        $emptyDir = Join-Path -Path $env:TEMP -ChildPath "RoboCopyEmpty_$(New-Guid)"
        $null = New-Item -Path $emptyDir -ItemType Directory -Force
    }

    process
    {
        try
        {
            $fullPath = Convert-Path -Path $Path 
            

            if ($PSCmdlet.ShouldProcess($fullPath, "删除文件夹及其所有内容"))
            {
                Write-Verbose "正在使用 RoboCopy 删除文件夹: $fullPath (线程数: $ThreadCount)"
                
                # 执行 RoboCopy 删除操作
                $robocopyArgs = @(
                    "'$emptyDir'"
                    "'$fullPath'"
                    "/mir"          # 镜像空目录
                    "/mt:$ThreadCount" # 多线程
                    "/E" #递归处理

                    "/log:'$logFile'"
                    # "/nfl"          # 不记录文件名
                    # "/ndl"          # 不记录目录名
                    # "/njh"          # 无作业头
                    # "/njs"          # 无作业摘要
                    # "/ns"           # 无大小
                    # "/nc"          # 无类别
                )
                $argsStr = $robocopyArgs -join "  "
                # $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                $cmd = "Robocopy.exe $argsStr" 
                Write-Verbose $cmd -Verbose

                $cmd | Invoke-Expression

                if ($process.ExitCode -ge 8)
                {
                    Write-Warning "RoboCopy 完成但可能有错误 (退出代码: $($process.ExitCode))"
                }
                else
                {
                    Write-Verbose "RoboCopy 成功完成 (退出代码: $($process.ExitCode))"
                }

                # 删除空文件夹
                Remove-Item -Path $fullPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch
        {
            Write-Error "删除文件夹时出错: $_"
            throw
        }
    }

    end
    {
        # 清理临时空目录
        if (Test-Path -Path $emptyDir)
        {
            Remove-Item -Path $emptyDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}
function Copy-Robocopy
{
    <# 
    .Synopsis
    对多线程复制工具Robocopy的简化使用封装,使更加易于使用,语法更加接近powershell命令
    默认启用多线程复制,如果需要递归,需要手动启用-Recurse选项
    .DESCRIPTION
    - 帮助用户更加容易的使用robocopy的核心功能(多线程复制和递归复制),作为常规copy命令的一个补充
    - 而简单的单文件复制一般用普通的copy命令就足够方便快捷了
    如果需要输出日志,使用LogFile参数指定日志文件
    .EXAMPLE
    #robocopy 原生用法常见语法用例举例
    #1:将复制过程的输出重定向到指定文件中(始终推荐使用LOG参数指定日志输出,经验表明,日志输出到屏幕会对性能有重大影响(可达10倍以上))
    PS> Robocopy.exe .\7.us\ .\rb1 /E /B /MT:8  /LOG:07091121
      日志文件: C:\sites\wp_sites\07091121

    #2: 适用于从网络复制的场景,增加更多参数(重试,详细日志级别等)
    robocopy C:\source\folder\path\ D:\destination\folder\path\ /E  /MT:32  /ZB /R:5 /W:5 /V /LOG:C:\log\robocopy.log
    
    参数	含义	推荐用途
    /E	复制所有子目录，包括空目录	确保完整复制整个目录结构
    /V	显示详细信息（包括跳过文件）	调试或审计用
    /MT[:n]	多线程复制（默认 8，最大 128）	提升 I/O 性能
    /ZB :: 使用可重新启动模式；如果拒绝访问，请使用备份模式。(效果是/Z /B)
        使用可重启模式 + 强制权限访问	网络复制 + 克服锁定文件(需要管理员权限才能访问某些受保护的系统文件)
    /R:n	失败重试次数（默认 1000000）	控制失败后的尝试次数
    /W:n	重试等待时间（秒）	避免频繁失败冲击资源

    .ExAMPLE
    PS C:\Users\cxxu\Desktop> copy-Robocopy -Source .\dir4 -Destination .\dir1\ -Recurse
    The Destination directory name is different from the Source directory name! Create the Same Name Directory? {Continue? [y/n]} : y
    Executing: robocopy ".\dir4" ".\dir1\dir4"  /E /MT:16 /R:1 /W:1

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        #第一批参数
        [Parameter(Mandatory = $true, Position = 0)]
        $Source,

        [Parameter(Mandatory = $true, Position = 1)]
        $Destination,

        [Parameter(Position = 2)]
        [string[]]$Files = '',
        [int]$Threads = 16, #默认是8
        [switch]$Recurse,
        # 控制失败时重试的次数和时间间隔(一般不用重试,基本上都是权限问题或者符号所指的连接无法访问或找不到)
        $Retry = 1,
        $Wait = 1,
        [string]$LogFile = "",
        $LogPreviewEncodings = 'ansi',
        # 不询问直接执行所有步骤
        [switch]$Force,

        # 第二批
        $ExcludeDirs = '',
        $ExcludeFiles = '',
        [switch]$RecurseWithoutEmptyDirs,
        [switch]$ContinueIfbroken,

        # 第三批
        [switch]$Mirror,

        [switch]$Move,

        [switch]$NoOverwrite,

        [switch]$V,

        [string[]]$OtherArgumentList
    )
    if(!$LogFile)
    {
        Write-Warning "No LogFile specified, the output will be displayed on the console and the speed will be affected seriously!"
        Write-Warning "Stop and restart with -LogFile <logFilePath> is recommended!(such as '-LogFile C:\log\robocopy.log')" -WarningAction Inquire
    }
    # Construct the robocopy command
    # 确保source和destination都是目录
    if (Test-Path $Source -PathType Leaf)
    {
        throw 'Source must be a Directory!'
    }if (Test-Path $Destination -PathType Leaf)
    {
        throw 'Destination must be a Directory!'
    }

    Write-Host 'checking directory name...'
    #向用户展示参数设置🎈
    # $PSBoundParameters  
    # 注意,$source和$destination在函数参数定义时不可以定为String类型,会导致Get-PsIOItemInfo返回值无法正确赋值
    Write-Debug "Source: $Source"
    Write-Debug "Destination: $Destination"
    if($Files)
    {
        Write-Debug "Files: $Files"
    }
    # $Source = Get-PsIOItemInfo $Source
    # $destination = Get-PsIOItemInfo $Destination

    # 检查目录名是否相同(basename)
    # $SN = $source.name
    # $DN = $Destination.name
    $SN = Split-Path -Path $Source -Leaf
    $DN = Split-Path -Path $Destination -Leaf

    Write-Verbose "$SN,$DN" 
    if ($Force -and !$Confirm)
    {
        $ConfirmPreference = 'none'
    }
    # if ($SN -ne $DN)
    # {
    #     # Write-Verbose "$($Source.name) -ne $($destination.name)"
 
    #     $msg = 'The Destination directory name is different from the Source directory name! Create the Same Name Directory?'
    #     # $continue = Confirm-UserContinue -Description 
    #     $continue = $PSCmdlet.ShouldProcess($Destination, $msg)
    #     if ($continue)
    #     {
    #         $Destination = Join-Path $Destination $SN
    #         Write-Verbose "$Destination" -Verbose
    #     }
    # }

    #debug
    # return
    $robocopyCmd = "robocopy `"$Source`" `"$Destination`" $Files"

    if ($Mirror)
    {
        $robocopyCmd += ' /MIR'
    }

    if ($Move)
    {
        $robocopyCmd += ' /MOVE'
    }

    if ($NoOverwrite)
    {
        $robocopyCmd += ' /XN /XO /XC'
    }

    if ($Verbose)
    {
        $robocopyCmd += ' /V'
    }

    if ($LogFile)
    {
        $robocopyCmd += " /LOG:`"$LogFile`""
    }

    # if ($Threads -gt 1)
    # {
    #     $robocopyCmd += " /MT:$Threads"
    # }
    if ($OtherArgumentList)
    {
        $robocopyCmd += ' ' + ($OtherArgumentList -join ' ')
    }
    if ($Recurse)
    {
        $robocopyCmd += ' /E'
    }
    # if ($ContinueIfbroken)
    # {
    #     $robocopyCmd += ' /Z'
    # }
    if ($RecurseWithoutEmptyDirs)
    {
        $robocopyCmd += ' /S'
    }if ($ExcludeDirs)
    {
        $robocopyCmd += " /XD $ExcludeDirs"
    }if ($ExcludeFiles)
    {
        $robocopyCmd += " /XF $ExcludeFiles"
    }

    # 默认使用(每个参数前有一个空格分割)
    $robocopyCmd += " /MT:$Threads"
    #默认启用自动重连(断点续传)
    $robocopyCmd += ' /ZB' 
    # 重试次数和间隔限制
    $robocopyCmd += " /R:$Retry /W:$Wait"


    if($PSCmdlet.ShouldProcess($Destination, "Executing: $robocopyCmd"))
    {

        Invoke-Expression $robocopyCmd
        
    }
    
    Write-Verbose "Set LogPreviewEncodings to Preview log in specified way(utf-8,ansi,gbk,etc)" -Verbose
    # 预览日志总结
    if($LogFile -and (Test-Path $LogFile))
    {
        Get-Content $logFile -Encoding $LogPreviewEncodings | Select-Object -Last 13
    }
}

function ls_eza
{
    <# 
.SYNOPSIS
eza is a modern, maintained replacement for the venerable file-listing command-line program ls that ships with Unix and Linux operating systems, giving it more features and better defaults. It uses colours to distinguish file types and metadata. It knows about symlinks, extended attributes, and Git. And it’s small, fast, and just one single binary.

By deliberately making some decisions differently, eza attempts to be a more featureful, more user-friendly version of ls.
.description
the windows version of eza is very easy to install (just need a good network)
however, in the linux version, the installation may be difficult to success in the first time
.LINK
- https://github.com/eza-community/eza
- https://www.sysgeek.cn/eza-command/
.EXAMPLE
PS>eza -ghil --icons
Mode  Size Date Modified Name
-a--- 331k 18 Mar 18:59   20240318_185950.mp4
-a--- 1.2M 18 Mar 19:10   20240318_191010.mp4
d----    - 10 Mar 23:22   ansel
d-r--    - 18 Mar 19:34  󰉌 Contacts
d-r--    - 18 Mar 19:36   Desktop
.EXAMPLE
PS>eza --icons -TL 2
 .
├──  20240318_185950.mp4
├──  20240318_191010.mp4
├──  ansel
├── 󰉌 Contacts
├──  Desktop
│  ├──  blogs_home.lnk
│  ├──  EM.lnk
│  ├──  math.lnk
│  ├──  neep.lnk
│  └──  四边形加固为刚性结构.ggb
├──  Documents
│  ├──  Apowersoft
│  ├──  Captura

.EXAMPLE
PS>eza --icons -ghilTL 2
Mode  Size Date Modified Name
d----    - 18 Mar 19:34   .
-a--- 331k 18 Mar 18:59  ├──  20240318_185950.mp4
-a--- 1.2M 18 Mar 19:10  ├──  20240318_191010.mp4
d----    - 10 Mar 23:22  ├──  ansel
d-r--    - 18 Mar 19:34  ├── 󰉌 Contacts
d-r--    - 18 Mar 19:36  ├──  Desktop
-a--- 1.4k 17 Jan 10:31  │  ├──  blogs_home.lnk
-a--- 1.4k 19 Jan 14:15  │  ├──  EM.lnk
-a--- 1.4k 19 Jan 14:14  │  ├──  math.lnk
-a--- 1.4k 17 Jan 10:33  │  ├──  neep.lnk
-a---  44k 15 Mar 20:13  │  └──  四边形加固为刚性结构.ggb
d-r--    - 18 Mar 19:34  ├──  Documents
d----    - 18 Mar 18:22  │  ├──  Apowersoft
d----    - 18 Mar 18:03  │  ├──  Captura
#>

    [CmdletBinding()]
    param (
        [Parameter()]
        [int]
        $deepth = 2
    )
    eza -ghil --icons -TL $deepth

    
}

function extract_markdown_titiles
{
    <# 
    .synopsis
    extract markdown titles,configs like 
        1.level
        2.indent char
        3.show title text only 
    are available to specifiy.

    .example
    PS C:\> extract_markdown_titiles .\01_导数和微分.md -level 2 -indent_with_chr '*'
    * 一元函数微分
    ** 函数在$x=x_0$导数的定义
    ** 导函数的定义
    ** 导数与微分@微商
    ** 对数函数的导函数
    ** 函数间四则运算组合函数的求导法则
    ** 反函数求导法则
    ** 对数求导法
    ** 微积分和深度学习
    * 导数表示法&导数记号系统
    ** 莱布尼兹记号法@Leibniz's notation
    ** 拉格朗日记号法@Lagrange's notation
    ** 欧拉记号法@Euler's notation
    ** 牛顿记号Newton's notation


    #>
    param(
        # pass content from pipeline
        # [Parameter(ValueFromPipeline)]
        # [String]
        # $content = 'Noting!',

        $file,
        $level = 3,
        $indent_with_chr = '#',
        # copy result to clipborad
        $scb = $true,
        [switch]$title_only

    )
    process
    {
        # write-host $level
    
        # $pattern = '^(#+)(\s+)(\S+)'
        $pattern = '^(#+)(\s+)(.*)'
        Write-Host $file.Length
        if ($file -ne '')
        {
            $content = Get-Content $file 
            Write-Host 'content from file'
        }
        else
        {
            Write-Host 'contents from clipboard'
        }


        $titles_with_level = $content | Where-Object { $_ -match $pattern } 
        # Remove potential excess spaces as they can affect aesthetics 
        # in titles "##[ ]<title content>",the '[]' indicate the space character width
        $titles_with_level = $titles_with_level -replace $pattern, '$1 $3'

        $titles_leveled = $titles_with_level | ForEach-Object {
            $titles_sharps = $_ -replace $pattern, '$1' 
            # write-host "'$titles_sharps'"
            $title_level = $titles_sharps.Length

            # write-host "$title_level;$_"

            if ($title_level -gt $level)
            {
                return
            }
            else
            {
                # 在管道符中通过write的方式将被遍历的元素添加到数组中
                Write-Host $_

            }
        }

        # write-host $titles_leveled
    
        $titles_with_level = $titles_leveled

        $titles = $titles_with_level | ForEach-Object { $_ -replace $pattern, '$3' }
        $res = ''
        if ($title_only)
        {
            $res = $titles
        }
        elseif ($indent_with_chr -eq '#')
        {
        
            $res = $titles_with_level
        }
        else
        {
            $res = $titles_with_level | ForEach-Object {
                $title_level = ( $_ -replace $pattern, '$1' ).Length
                $_ -replace '^(#+)', ($indent_with_chr * $title_level)
            }
        }
        # 根据需要将内容自动复制到剪切板
        if ($scb)
        {
            $res | Set-Clipboard

        }
        return $res 
    }
    
}

function tree_lsd
{
    param(
        $depth_opt = 3
    )
    lsd --tree --depth $depth_opt
}
function ld
{
    lsd -l --color never
}
function l1
{
    lsd -1
}


function remote_folder
{
    param(
        $hostname_opt = "$AliCloudServerIP",
        $dir = '/home/cxxu/cppCodes'
    )
    code --folder-uri "vscode-remote://ssh-remote+$hostname_opt$dir"
}
function Get-LineNumberWidth
{
    param (
        $content
    )
    [math]::Max([int][math]::Log10($contents.Count) + 1, 2)
}

function Get-ContentNL
{
    <# 
.SYNOPSIS
该函数用于计数地输出文本内容:在每行的开头显示该行是文本中的第几行(行号),以及该行的内容
支持管道符输入被统计对象
#>
    <# 
.EXAMPLE
#常规用法,通过参数指定文本文件路径来计数地输出文本内容
Get-ContentNL -InputData .\r.txt
.EXAMPLE
rvpa .\r.txt |Get-ContentNL
.EXAMPLE
将一个三行的文本字符串作为管道输入，然后将其,显式指出将管道符内容视为字符串而不是路径字符串进行统计
#创建测试多行字符串变量
$mlstr=@'
line1
line2
line3
'@

$mlstr|Get-ContentNL -AsString

.EXAMPLE
计数一个多行字符串变量的行数
PS C:\repos\scripts\PS\Test> $mlstr=@'
>> line1
>> line2
>> line3
>> '@
PS C:\repos\scripts\PS\Test> $mlstr
line1
line2
line3
PS C:\repos\scripts\PS\Test> Get-ContentNL -InputData $mlstr -AsString
1:line1
2:line2
3:line3
.EXAMPLE
#跟踪文本文件内容的变化(每秒刷新一次内容);
Get-ContentNL -InputData .\log.txt -RepetitionInterval 1
.EXAMPLE
#在powershell新窗口中更新
Start-Process powershell -ArgumentList '-NoExit -Command Get-ContentNL -InputData .\log.txt -RepetitionInterval 1'
.EXAMPLE
ls传递给cat读取合并,然后在传给Get-ContentNL来计数处理

PS> ls ab*.cpp|cat|Get-ContentNL -AsString -Verbose
VERBOSE: Checking contents...
1:#include <iostream>
2:using namespace std;
3:int main()
4:{
5:
6:    int a, b, c;
7:    cin >> a >> b;
8:    c = a + b;
9:    cout << c << endl;
10:    return 0;
11:}
12:#include <iostream>
13:using namespace std;
14:int main()
15:{
16:
17:
18:    int a, b, c;
19:    cin >> a >> b >> c;
20:    cout << (a + b) * c << endl;
21:    return 0;
22:}
VERBOSE: 2024/9/14 22:03:43
 
.EXAMPLE
#从ls命令通过管道符传递多个文件进行读取
PS🌙[BAT:79%][MEM:48.16% (15.27/31.71)GB][22:03:52]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\Cpp\stars_printer]
PS> ls ab*.cpp|Get-ContentNL
# Start File(1) [C:\repos\scripts\Cpp\stars_printer\ab.cpp]:

1:#include <iostream>
2:using namespace std;
3:int main()
4:{
5:
6:    int a, b, c;
7:    cin >> a >> b;
8:    c = a + b;
9:    cout << c << endl;
10:    return 0;
11:}

# End File(1) [C:\repos\scripts\Cpp\stars_printer\ab.cpp]:

# Start File(2) [C:\repos\scripts\Cpp\stars_printer\abc.cpp]:

1:#include <iostream>
2:using namespace std;
3:int main()
4:{
5:
6:
7:    int a, b, c;
8:    cin >> a >> b >> c;
9:    cout << (a + b) * c << endl;
10:    return 0;
11:}

# End File(2) [C:\repos\scripts\Cpp\stars_printer\abc.cpp]:

.EXAMPLE
通过get-item命令(别名gi)获取字符串对应的文件
PS🌙[BAT:79%][MEM:48.52% (15.39/31.71)GB][22:04:07]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts\Cpp\stars_printer]
PS> gi .\ab.cpp|Get-ContentNL
# Start File(1) [C:\repos\scripts\Cpp\stars_printer\ab.cpp]:

1:#include <iostream>
2:using namespace std;
3:int main()
4:{
5:
6:    int a, b, c;
7:    cin >> a >> b;
8:    c = a + b;
9:    cout << c << endl;
10:    return 0;
11:}

# End File(1) [C:\repos\scripts\Cpp\stars_printer\ab.cpp]:

.Notes
可以设置别名,比如pscatn,psnl
#>
    [CmdletBinding()]
    param(
        # 可以是一个表示文件路径的字符串，也可以是一个需要被统计行数并显示内容的字符串;后者需要追加 -AsString 选项
        [Parameter(
            Mandatory = $false, #这里如果使用这个参数的话，必须要指定非空值,为了增强兼容性,不适用改参数,或者指定为$false
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        # [string]
        [Alias('InputObject')]$InputData,
        
        # [Parameter(ParameterSetName = 'FilePath')]
        # [switch]$AsFilePath,

        # [Parameter(ParameterSetName = 'String')]
        [switch]$AsString,
        # 定时刷新查看文件内容的间隔时间（秒）,0表示一次性查看
        $RepetitionInterval = 0,
        [switch]$Clear,
        $LineSeparator = '#'
        # [switch]$NewShell #todo

    )

    begin
    {
        Write-Verbose 'Checking contents...'
        $itemNumber = 1
        $lineNumber = 0 #为了支持列表输入,对多个文件分别计数,此变量放到process块中
    }

    process
    {
        
        
        if ($AsString)
        # if ($PSCmdlet.ParameterSetName -eq 'String')
        {
            # 如果是字符串，则认为是直接传入的文件内容
            $InputData -split "`n" | ForEach-Object {
                $lineNumber++
                "${lineNumber}:$_"
            }
        }
        else
        {
            # 否则，认为是文件路径,但是还是要检查文件是否存在或者合法
            if (!(Test-Path $InputData -PathType Leaf))
            {
                Write-Error "File does not exist:$($InputData.Trim()) Do you want to consider the Input as a string?(use -AsString option ) "
                return
            }
            $lineNumber = 0

            Write-Host "$LineSeparator Start File($itemNumber) [$_]" -BackgroundColor Yellow -NoNewline
            Write-Host "`n"
            
            try
            {
                if (Test-Path $InputData -PathType Leaf)
                {
                    Get-Content $InputData | ForEach-Object {
                        $lineNumber++
                        "${lineNumber}:$_"
                    }
                }
                else
                {
                    Write-Error "File does not exist: $InputData"
                }
            }
            catch
            {
                Write-Error "An error occurred: $_"
            }

            Write-Host ''
            Write-Host "$LineSeparator End File($itemNumber) [$_]:"-BackgroundColor Blue -NoNewline
            Write-Host "`n"
            $itemNumber++

        }
        # 定时刷新查看指定文件内容
        if ($RepetitionInterval)
        {
            
            while (1)
            {
                # 清空屏幕(上一轮的内容会被覆盖)
                if ($Clear) { Clear-Host }

                # 这里使用递归调用(并且将此处调用的RepetitionInterval指定为不刷新(0),否则嵌套停不下来了)
                Get-ContentNL -InputData $InputData -RepetitionInterval 0
                # 也可以简单使用 
                # Get-Content $InputData
                Start-Sleep $RepetitionInterval
            }

        }
     

    }
    end
    {
        Write-Verbose (Get-DateTime)
    }
}

function Open-AllFiles
{
    <# 
    .synopsis
    open all file that exist in the current directory with default program 
    #>
    # --------------
    <#     if (Test-Path ./Open-AllFilesFiles.ps1)
    {
        Remove-Item Open-AllFilesFiles.ps1 -V
    }
    Get-ChildItem -File | ForEach-Object { ".`/" + $_.Name>>Open-AllFilesFiles.ps1 }
    ./Open-AllFilesFiles.ps1
    write-host 'end the Open-AllFiles script running'
    # 删除临时脚本:
    Remove-Item ./Open-AllFilesFiles.ps1 #>

    # ----------------------

    Get-ChildItem -File | ForEach-Object { Write-Host $_; & $_ }
}

function New-Junction
{
    [cmdletbinding()]
    param(
        $Path,
        [alias('Destination')]$Target
    )
    # Write-Host 'if failed(access Denied), please run the terminal with administor permission.(考虑到部署的门槛，scoope未必可用，您需要手动打开带有管理员权限的terminal进行操作（而不在这里使用sudo;这里提供了参数，您可以传入sudo选项）'
    if (Test-Path $path)
    {
        Write-Host 'removing the existing dir/symbolicLink!'
        # Remove-Item -Force -Verbose $path 
        # timer_tips
    }
    if (!(Test-Path $Target))
    {
        Write-Host 'target does not exist!'
        New-Item -ItemType Directory -Force -Verbose $Target
    }

    New-Item -Force -ItemType junction -Path $Path -Target (Resolve-Path $Target) -Verbose:$VerbosePreference
    
}
# 注:Get-BatteryLevel 已迁至 Info 模块(与 Get-MemoryUseSummary 等 prompt 电池内存段同模块),此处删除原定义

function New-File
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (Test-Path $Path)
    {
        # 文件已存在，更新最后写入时间
        (Get-Item $Path).LastWriteTime = Get-Date
    }
    else
    {
        # 文件不存在，创建文件
        New-Item -ItemType File -Path $Path | Out-Null
    }
}

function mvToNEEPSub
{
    param (
        $obj,
        $desBase
    )
    $des = "$env:Neep`\$desBase"

    Move-Item $obj $des
    Write-Host "displayed:$des = $env:Neep`\$desBase"
}

function renamePrefix
{
    param (
        $dirName
    )
    EnvironmentRequireTips
    py $scripts\pythonScripts\rename_prefix.py $dirName
}




function search_contents
{
    param(
        #选择需要扫描的目录路径,默认为当前路径
        $path = '.',
        $content_pattern = 'text',
        $file_pattern = '*',
        #使用groupby进行分组(每个文件在匹配到的所有行及其行数统计,所有存在被匹配行的文件总数统计),并将分组结果输出为表格,支持进一步排序
        [switch]$TableViewGroup
    )
    $res = Get-ChildItem -Path $path -R -File -FollowSymlink $file_pattern | Select-String -Pattern $content_pattern
    $sum = $($res | Group-Object -Property Filename).Count
    if ($TableViewGroup)
    {
        $res = $res | Select-Object Filename, LineNumber, Line | Group-Object -Property Filename 
        $res = $res | Format-Table -AutoSize
    }
    Write-Host $res
    Write-Host args: -ForegroundColor DarkMagenta -BackgroundColor Cyan
    $params = "
        path = $path,
        content_pattern = $content_pattern,
        file_pattern = $file_pattern,
        TableViewGroup=$TableViewGroup"
    Write-Host $params -ForegroundColor Yellow

    Write-Host "Total files matched pattern_contents:$sum" -ForegroundColor 'Blue' #-BackgroundColor Yellow

    <# 
    .SYNOPSIS
    扫描指定目录下所有包含特定内容的文件，输出文件名，行号，行内容
    支持切换为分组显示,并将分组结果输出为表格
    .EXAMPLE
    PS 🕰️1:24:27 AM [C:\repos\scripts\testDir] 🔋100%→search_contents  -content_pattern tex

    f1:1:text2
    f1:2:text3
    f1:3:text abc
    f2:1:!text abc
    dir_test\f4:1:text x abc
    args:

            path = .,
            content_pattern = tex,
            file_pattern = *,
            TableViewGroup=False
    Total files matched pattern_contents:4
    .EXAMPLE
    PS 🕰️1:24:29 AM [C:\repos\scripts\testDir] 🔋100%→search_contents  -content_pattern tex -TableViewGroup

    Count Name     Group
    ----- ----     -----
        3 f1       {@{Filename=f1; LineNumber=1; Line=text2}, @{Filename=f1; LineNumber=2; Line=text3}, @{Filename=f1; Lin…
        1 f2       {@{Filename=f2; LineNumber=1; Line=!text abc}}
        1 f4       {@{Filename=f4; LineNumber=1; Line=text x abc}}

    args:

            path = .,
            content_pattern = tex,
            file_pattern = *,
            TableViewGroup=True
    Total files matched pattern_contents:4
    #>
    
}

function aliasEdit
{
    param(
        #[functions,shortcuts]
        $type = 'shortcuts'
    )
    vim $aliases\shortcuts
}







# testing.
function mkdirSafeCd
{
    param(
        $DirectoryName

    )
    if ( Test-Path $DirectoryName)
    {
        Write-Host "directory already exist, now Set-Location to the directory:$DirectoryName"
        Set-Location $DirectoryName
    }
    else
    {
        New-Item -ItemType Directory $DirectoryName
        Set-Location $DirectoryName
    }
}

function c
{
    <# use vscode open specified dir or file #>
    param(
        $dirName = '.'
    )
    # code_pwsh $dirName 
    code $dirName
    # --proxy-pac-url=http://127.0.0.1:1083/proxy.pac
}


function Get-ScriptRootPath
{
    <# .synopsis
    获取当前脚本所在的绝对路径 
    #>
    Resolve-Path $PSScriptRoot
}



function Write-WorkingDir
{
    param(
        $path = './'
    )
    Write-Host "`t 📁❤️function working on dir: $((Resolve-Path $path))..."
    Write-SeparatorLine '..'
}



#(please note that the function name can't not have a same name with a certain Alias).

<# start comman software by name #>


