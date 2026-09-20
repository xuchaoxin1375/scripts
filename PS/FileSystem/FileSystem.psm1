
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
        #进度计数器
        $PSStyle.Progress.View = 'Classic'
        # $PSStyle.Progress.View = 'Minimal'
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
    if ($Parallel)
    {
        Write-Host 'Parallel Mode.'
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
