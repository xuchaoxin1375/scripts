function ConvertTo-LowerCase
{
    <# 
    .SYNOPSIS
    将文本文件中的字符串转换为小写
    .DESCRIPTION
    实现有两类,一类简单但是不适合处理超大文件(一口气读取全部文本,可能会爆内存)
    另一类是流式处理,适合处理超大文件
    这里采用后者

    .NOTES
    推荐方案:
    Goal: Handle very large files without loading entire file into memory.
    How it works now: Streams input line-by-line using System.IO.StreamReader / StreamWriter, preserves detected encoding, supports multiple files and pipeline input, and atomically replaces the original file by writing to a temp file and moving it into place.

    [System.IO.File]::Open 提供了对文件操作的最大灵活性，适用于：
    需要控制文件共享行为（如日志文件被多个进程写入）
    处理二进制数据（如图像、加密文件）
    大文件流式读写（避免一次性加载到内存）
    精确控制文件创建/覆盖逻辑
    注意读写流的创建和对流的读写操作,以及结束读写时流的清理
    .NOTES
    简单方案:
    $content = Get-Content $Path -Raw
    return $content.ToLower() | Set-Content $Path -Verbose -PassThru
    
    .EXAMPLE
    ConvertTo-LowerCase -Path "C:\test.txt"
    .EXAMPLE
    "C:\test.txt" | ConvertTo-LowerCase
    #>
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]] $Path
    )

    process
    {
        foreach ($p in $Path)
        {
            if (-not (Test-Path -Path $p -PathType Leaf))
            {
                Write-Warning "Path [$p] not found or is not a file,processing next path if needed."
                continue
            }

            $temp = [System.IO.Path]::GetTempFileName()
            # 创建文件输入流(open待处理文本文件)
            $inStream = [System.IO.File]::Open($p, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try
            {
                # 为输入流创建流读取器
                $reader = New-Object System.IO.StreamReader($inStream, $true)
                try
                {
                    # 创建文件输出流(create)
                    $outStream = [System.IO.File]::Open($temp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

                    $encoding = $reader.CurrentEncoding
                    try
                    {
                        # 为输出流创建流写入器
                        $writer = New-Object System.IO.StreamWriter($outStream, $encoding)
                        try
                        {
                            while (-not $reader.EndOfStream)
                            {
                                $line = $reader.ReadLine()
                                if ($null -ne $line)
                                {
                                    $writer.WriteLine($line.ToLower())
                                }
                                else
                                {
                                    $writer.WriteLine('')
                                }
                            }
                        }
                        finally
                        {
                            $writer.Flush()
                            $writer.Close()
                        }
                    }
                    finally
                    {
                        $outStream.Close()
                    }
                }
                finally
                {
                    $reader.Close()
                }
            }
            finally
            {
                $inStream.Close()
            }
            # 当前文件处理完毕,将临时文件覆盖旧文件
            try
            {
                Move-Item -Path $temp -Destination $p -Force
                Write-Verbose "Converted to lower-case: $p" -Verbose
                Get-Item $p
            }
            catch
            {
                Remove-Item -Path $temp -ErrorAction SilentlyContinue
                throw
            }
        }
    }
}

function Split-TextFile
{
    <#
    .SYNOPSIS
        将文本文件按指定行数或平均分割成多个文件。
        支持指定输出文件的编号格式化
    
    .DESCRIPTION
        Split-TextFile 函数可以将一个大的文本文件按照行数分割成多个较小的文件。
        支持两种分割模式：
        1. 按行数分割：根据指定的行数限制分割文件
        2. 平均分割：将文件尽可能均匀地分割成指定数量的文件
        输出文件编号格式化借助于[string]::Format() 或 -f操作符
    
    .PARAMETER Path
        指定要分割的源文件路径。
    
    .PARAMETER Lines
        指定每个分割文件的最大行数。此参数与 Average 参数互斥。
    
    .PARAMETER Average
        指定要分割成的文件数量，函数会尽可能均匀地分割文件。此参数与 Lines 参数互斥。
    
    .PARAMETER Destination
        指定分割后文件的存储目录。如果未指定，则使用源文件所在目录。
    
    .PARAMETER Prefix
        指定分割后文件的前缀名称。默认使用源文件名作为前缀。
    
    .PARAMETER SuffixFormat
        指定分割后文件的后缀格式。默认为 "part{0:000}"。
        具体数值字符串格式化语法参考LINKS一节列出的链接,其基础用例如下:
        [string]::Format("var1={0:0000.000},var2={1:0.000}",123.12342,123.11)
        var1=0123.123,var2=123.110
        总之,{}内分用:分成两部分{:},":"前面是引用后面的变量的位置索引,
        ":"后是格式化数值的规则字符串
    
    .PARAMETER Encoding
        指定输出文件的编码格式。默认为 UTF8。
    
    .EXAMPLE
        Split-TextFileByLines -Path "C:\Logs\large.log" -Lines 1000
        将 large.log 文件按每份最大 1000 行进行分割。
    
    .EXAMPLE
        Split-TextFileByLines -Path "C:\Data\input.txt" -Average 5 -Destination "C:\Output"
        将 input.txt 文件平均分割成 5 个文件，并保存到 C:\Output 目录。
    
    .EXAMPLE
        Split-TextFileByLines -Path "C:\Temp\data.txt" -Lines 500 -Prefix "chunk" -SuffixFormat "segment{0:00}"
        将 data.txt 文件按每份最大 500 行分割，文件名前缀为 "chunk"，后缀格式为 "segment01" 等。
    
    .INPUTS
        System.String
    
    .OUTPUTS
        System.IO.FileInfo[]
    
        该函数会保持原文本文件的行完整性，不会将单行内容分割到不同文件中。
    .EXAMPLE
    指定输出文件名格式(数字索引编号写在`{0:}`中冒号之后0表示默认,如果增加0的个数,可以用来对齐低数值的情况比如000可以将1格式化为001)
    Split-TextFile -Path .\local_abe1.xml.txt -Destination $local/abe1s -SuffixFormat 'part{0:0}' -Lines 10

    .LINK
    相关参考
    自定义数值格式字符串
    - https://learn.microsoft.com/zh-cn/dotnet/standard/base-types/custom-numeric-format-strings
    - https://learn.microsoft.com/en-us/dotnet/standard/base-types/formatting-types#custom-format-strings
    #>
    [CmdletBinding(DefaultParameterSetName = "Lines")]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({
                if (-not (Test-Path $_ -PathType Leaf))
                {
                    throw "文件 '$_' 不存在。"
                }
                if ([System.IO.Path]::GetExtension($_) -eq "")
                {
                    throw "路径 '$_' 不是一个有效的文件。"
                }
                return $true
            })]
        [string]$Path,
        
        [Parameter(ParameterSetName = "Lines", Mandatory = $true)]
        [ValidateScript({
                if ($_ -le 0)
                {
                    throw "行数必须大于 0。"
                }
                return $true
            })]
        [int]$Lines,
        
        [Parameter(ParameterSetName = "Average", Mandatory = $true)]
        [ValidateScript({
                if ($_ -le 0)
                {
                    throw "分割数量必须大于 0。"
                }
                return $true
            })]
        [int]$Average,
        
        [alias('OutputDir')]
        [string]$Destination,
        
        [string]$Prefix,
        
        [string]$SuffixFormat = "part{0:0}",
        
        $Encoding = "UTF8"
    )
    
    # 获取源文件的完整路径
    $sourceFile = Get-Item -Path $Path
    $sourcePath = $sourceFile.FullName
    $sourceName = $sourceFile.BaseName
    # $sourceExtension = $sourceFile.Extension
    
    # 设置默认前缀
    if (-not $Prefix)
    {
        $Prefix = $sourceName
    }
    
    # 设置目标目录
    if (-not $Destination)
    {
        $Destination = $sourceFile.DirectoryName
    }
    elseif (-not (Test-Path $Destination -PathType Container))
    {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    
    # 确保目标路径是完整路径
    $Destination = (Resolve-Path $Destination).Path
    
    Write-Verbose "正在分割文件: $sourcePath"
    Write-Verbose "目标目录: $Destination"
    Write-Verbose "文件前缀: $Prefix"
    
    try
    {
        # 根据参数集选择分割方法
        if ($PSCmdlet.ParameterSetName -eq "Lines")
        {
            Write-Verbose "按行数分割模式，每个文件最大: $Lines 行"
            $result = Split-FileByLines_ -Path $sourcePath -Lines $Lines -Destination $Destination -Prefix $Prefix -SuffixFormat $SuffixFormat -Encoding $Encoding
        }
        else
        {
            Write-Verbose "平均分割模式，分割成 $Average 个文件"
            $result = Split-FileAverageByLines_ -Path $sourcePath -Count $Average -Destination $Destination -Prefix $Prefix -SuffixFormat $SuffixFormat -Encoding $Encoding
        }
        
        Write-Verbose "分割完成，共生成 $($result.Count) 个文件"
        return $result
    }
    catch
    {
        Write-Error "分割文件时发生错误: $($_.Exception.Message)"
        throw
    }
}

function Split-FileByLines_
{
    param(
        [string]$Path,
        [int]$Lines,
        [string]$Destination,
        [string]$Prefix,
        [string]$SuffixFormat,
        $Encoding
    )
    
    $files = @()
    $reader = $null
    $writer = $null
    $currentFileIndex = 0
    $currentLineCount = 0
    
    try
    {
        $reader = New-Object System.IO.StreamReader($Path)
        $writer = CreateNewPartFile_ -Destination $Destination -Prefix $Prefix -SuffixFormat $SuffixFormat -Index $currentFileIndex -Extension ([System.IO.Path]::GetExtension($Path)) -Encoding $Encoding
        $files += $writer.BaseStream.Name
        $currentFileIndex++
        
        while (-not $reader.EndOfStream)
        {
            $line = $reader.ReadLine()
            $currentLineCount++
            
            # 如果当前行数超过限制且当前文件已有内容，则创建新文件
            if ($currentLineCount -gt $Lines -and $currentLineCount -gt 1)
            {
                $writer.Close()
                $writer = CreateNewPartFile_ -Destination $Destination -Prefix $Prefix -SuffixFormat $SuffixFormat -Index $currentFileIndex -Extension ([System.IO.Path]::GetExtension($Path)) -Encoding $Encoding
                $files += $writer.BaseStream.Name
                $currentFileIndex++
                $currentLineCount = 1 # 重置行计数器，并将当前行写入新文件
            }
            
            $writer.WriteLine($line)
        }
    }
    finally
    {
        if ($reader) { $reader.Close() }
        if ($writer) { $writer.Close() }
    }
    
    return Get-Item $files
}

function Split-FileAverageByLines_
{
    <# 
    .SYNOPSIS
    将文本文件平均分割成n份
    
    #>
    param(
        [string]$Path,
        [int]$Count,
        [string]$Destination,
        [string]$Prefix,
        [string]$SuffixFormat,
        $Encoding
    )
    
    # 首先计算总行数
    Write-Verbose "正在计算文件总行数..."
    $totalLines = 0
    $reader = New-Object System.IO.StreamReader($Path)
    try
    {
        while (-not $reader.EndOfStream)
        {
            $reader.ReadLine() | Out-Null
            $totalLines++
        }
    }
    finally
    {
        $reader.Close()
    }
    
    Write-Verbose "文件总行数: $totalLines"
    
    # 计算每份的行数
    $linesPerFile = [Math]::Floor($totalLines / $Count)
    $remainder = $totalLines % $Count
    Write-Verbose "每份基础行数: $linesPerFile，前 $remainder 份会多 1 行"
    
    # 开始分割
    $files = @()
    $reader = New-Object System.IO.StreamReader($Path)
    try
    {
        for ($i = 0; $i -lt $Count; $i++)
        {
            # 计算当前文件应该有多少行
            $currentFileLines = $linesPerFile
            if ($i -lt $remainder)
            {
                $currentFileLines++ # 前 remainder 份多分配一行以均匀分布
            }
            
            # 创建新文件
            $writer = CreateNewPartFile_ -Destination $Destination -Prefix $Prefix -SuffixFormat $SuffixFormat -Index $i -Extension ([System.IO.Path]::GetExtension($Path)) -Encoding $Encoding
            $files += $writer.BaseStream.Name
            
            # 写入指定行数的内容
            for ($j = 0; $j -lt $currentFileLines -and -not $reader.EndOfStream; $j++)
            {
                $line = $reader.ReadLine()
                $writer.WriteLine($line)
            }
            
            $writer.Close()
            
            Write-Verbose "已创建文件: $($writer.BaseStream.Name)，写入 $currentFileLines 行"
        }
    }
    finally
    {
        if ($reader) { $reader.Close() }
    }
    
    return Get-Item $files
}

function CreateNewPartFile_
{
    <# 
    .SYNOPSIS
    文本文件划分切割辅助函数
    创建一个新的分片文件
    提供文件名格式化设定支持

     #>
    param(
        [string]$Destination,
        [string]$Prefix,
        [string]$SuffixFormat,
        [int]$Index,
        [string]$Extension,
        $Encoding
    )
    # 输出路径/文件名格式化构造
    ## 格式化编号🎈
    $suffix = [string]::Format($SuffixFormat, $Index)
    ## 构造文件名
    $fileName = "{0}.{1}{2}" -f $Prefix, $suffix, $Extension
    ## 拼接完整路径
    $fullPath = Join-Path $Destination $fileName
    
    # 根据编码创建相应的 StreamWriter
    switch ($Encoding)
    {
        "UTF8"
        { 
            return New-Object System.IO.StreamWriter($fullPath, $false, [System.Text.Encoding]::UTF8) 
        }
        "Unicode"
        { 
            return New-Object System.IO.StreamWriter($fullPath, $false, [System.Text.Encoding]::Unicode) 
        }
        "ASCII"
        { 
            return New-Object System.IO.StreamWriter($fullPath, $false, [System.Text.Encoding]::ASCII) 
        }
        default
        { 
            return New-Object System.IO.StreamWriter($fullPath, $false, [System.Text.Encoding]::UTF8) 
        }
    }
}
function Add-LinesAfterMark
{
    <# 
    .SYNOPSIS
        在指定的 Mark 后添加配置行，如果配置行已存在则跳过。
        如果配置项不存在，则添加该配置项并保存。
    .PARAMETER Path
        配置文件路径。
    .PARAMETER Mark
        配置项的标记。内容将插入其后
    .PARAMETER ConfigLine
        要添加的配置行。

    .EXAMPLE
    # 调用示例
    if($env:MYSQL_HOME){
        $mysql_home = $env:MYSQL_HOME
    }elseif($env:MYSQL_BIN_HOME){
        $mysql_home="$env:MYSQL_BIN_HOME/../"
    }

    mysql -uroot -p"$env:MySqlKey_LOCAL" -e "PURGE BINARY LOGS BEFORE '2050-11-01 00:00:00';"
    Add-LinesAfterMark -Path "$mysql_bin_home\..\my.ini" -Mark "[mysqld]" -ConfigLine "skip-log-bin"
    Remove-Item "$mysql_home\data\binlog*.0*" -Force -Confirm
    mysql -uroot -p"$env:MySqlKey_LOCAL" -e "show binary logs;"
    
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        [alias("Tag")]
        [string]$Mark,
        
        [Parameter(Mandatory = $true)]
        [alias("Lines", "NewLines", "Content")]
        [string]$ConfigLine
    )
    
    # 首先检查配置项是否已经存在
    $content = Get-Content $Path
    if ($content -contains $ConfigLine)
    {
        Write-Host "配置项 '$ConfigLine' 已存在，跳过处理"
        return
    }
    
    # 使用 StreamReader 和 StreamWriter 实现高性能读写
    $tempFile = [System.IO.Path]::GetTempFileName()
    
    $reader = $null
    $writer = $null
    
    try
    {
        $reader = [System.IO.File]::OpenText($Path)
        $writer = [System.IO.File]::CreateText($tempFile)
        $MarkFound = $false
        
        while (-not $reader.EndOfStream)
        {
            $line = $reader.ReadLine()
            $writer.WriteLine($line)
            
            # 检查是否匹配目标 Mark 且尚未添加配置
            if (-not $MarkFound -and $line -eq $Mark)
            {
                $writer.WriteLine($ConfigLine)
                $MarkFound = $true
            }
        }
        
        # 关闭资源
        $reader.Close()
        $writer.Close()
        
        # 替换原文件
        [System.IO.File]::Copy($tempFile, $Path, $true)
        Write-Host "成功添加配置项 '$ConfigLine'"
    }
    catch
    {
        # 如果发生错误，确保清理资源
        if ($reader  ) { $reader.Close() }
        if ($writer  ) { $writer.Close() }
        throw
    }
    finally
    {
        # 清理临时文件
        if (Test-Path $tempFile)
        {
            Remove-Item $tempFile -Force
        }
    }
}
function Measure-AlphabeticChars
{

    <#
    .SYNOPSIS
        Counts the number of alphabetic characters in a given string or array of strings.

    .DESCRIPTION
        This function takes a string or an array of strings and counts all the alphabetic characters (A-Z, a-z) in each string.
        It supports both pipeline input and direct parameter input.

    .PARAMETER InputString
        The string or array of strings in which to count the alphabetic characters.
    #>
    <# 
.EXAMPLE
    Measure-AlphabeticChars -InputString "Hello, World!"
    Output: 10

.EXAMPLE
    "Hello, World!" | Measure-AlphabeticChars
    Output: 10

.EXAMPLE
    Measure-AlphabeticChars -InputString @("Hello, World!", "PowerShell 7")
    Output: 10
            10

.EXAMPLE
    @("Hello, World!", "PowerShell 7") | Measure-AlphabeticChars
    Output: 10
            10

.NOTES
    Author: Your Name
    Date: Today's date
    #>


    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$InputString
    )

    process
    {
        foreach ($str in $InputString)
        {
            # Use regex to find all alphabetic characters and count them
            $ms = [regex]::Matches($str, '[a-zA-Z]')
            $ms.Count
        }
    }
}