
function Compress-Tar
{
    <# 
    .SYNOPSIS
    将指定目录下的所有文件打包为tar格式的包文件

    .DESCRIPTION
    该脚本将指定目录下的所有文件打包为tar格式的文件，并保存到指定目录中。
    

.PARAMETER Directory
    要打包的目录路径。
.EXAMPLE
PS> Compress-Tar -Directory C:/sites/wp_sites/1.de
VERBOSE: 正在打包目录: C:/sites/wp_sites/1.de
VERBOSE: 执行: tar -c  -f C:\Users\Administrator\Desktop/1.de.tar -C C:/sites/wp_sites/1.de .
VERBOSE: 打包完成，输出文件: C:\Users\Administrator\Desktop/1.de.tar
.EXAMPLE
PS> Compress-Tar -Path C:\sites\wp_sites\8.us\ -OutputFile 8.1.tar -Debug
VERBOSE: 正在打包目录(Tar): C:\sites\wp_sites\8.us\
VERBOSE: 执行: [tar -c -v -f 8.1.tar -C C:\sites\wp_sites\8.us\/.. 8.us ]
a 8.us
a 8.us/.htaccess
a 8.us/index.php
a 8.us/license.txt
# 列出tar包结构
PS> tar -tf .\8.1.tar
8.us/
8.us/.htaccess
8.us/index.php
8.us/license.txt

#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [alias("SiteDirectory", "Directory")]
        [string]$Path,

        # [Parameter(Mandatory = $true)]
        [string]$OutputFile = "",
        # 默认情况下,执行类似 tar -cf archived.tar -C C:\sites\wp_sites\dir\.. dir ;这使得打包后内部结构为dir/...(就像右键文件夹,然后添加到压缩包那样)
        # 使用-InDirectory参数,则打包目录内部的内容,解压后会把内容直接散出来
        [switch]$InDirectory,
        # [switch]$InParent,
        # 是否仅对目录进行打包,如果Path不是目录,则跳过打包(这种情况下意义不大)
        [switch]$OnlyDirectory,
        [switch]$GUI
        
    )
    if ($GUI)
    {
        Show-Command Compress-Tar 
 
        return
    }
    $v = if ($VerbosePreference -or $DebugPreference) { "-v" } else { "" }
    Write-Verbose "正在打包目录(Tar): $Path " -Verbose
    $dirName = Split-Path $Path -Leaf
    $parentDir = Split-Path $Path -Parent
    if ($OutputFile -eq "")
    {
        Write-Debug "输出文件名未指定，使用默认值: ${dirName}.tar"
        $DefaultOutputDir = [Environment]::GetFolderPath("Desktop")
        Write-Debug "默认存放路径为桌面:$DefaultOutputDir" 
        $OutputFile = "$DefaultOutputDir/${dirName}.tar"
    }
    # 判断$Path是否为一个目录
    if (Test-Path $Path -PathType Container)
    {
        $Dir = $Path.Trim('/').Trim('\')
        if ($InDirectory)
        {
            $exp = "tar -c $v -f $OutputFile -C $Dir * "
            
        }
        else
        {
            $exp = "tar -c $v -f $OutputFile -C $Dir/.. $(Split-Path $Path -Leaf) "
        }
    }
    elseif(!$OnlyDirectory)
    {
        Write-Warning "Path is not a directory, try to pack single file: $Path"
        $fileBaseName = Split-Path -Path $Path -Leaf 
        $exp = "tar -c $v -f $OutputFile  -C $parentDir  $fileBaseName "
    }
    else
    {
        Write-Warning "Path is not a directory, skip pack: $Path"
        Copy-Item $Path $OutputFile.trim(".tar") -Verbose -Force
    }
    if($exp)
    {

        Write-Verbose "执行: [$exp]" -Verbose
        Invoke-Expression $exp
        Write-Verbose "打包完成，输出文件: $OutputFile" -Verbose
    }
    return $OutputFile
}
function Test-TarFile
{
    <# 
    .SYNOPSIS
    检查指定文件是否为tar包
    默认情况下仅检查文件扩展名
    .NOTES
    如果依赖于tar命令行工具(win10及以上版本自带tar命令)
    通过-tf假设文件是tar包,然后列出文件内容,如果返回值为0,则表示是tar包,否则不是
    这种方法不好,容易卡住

    推荐的方案是专门的工具,比如file.exe,但是这需要额外的二进制可执行文件
    scoop install file 或者git 安装目录中的usr/bin/file.exe可以提供此类检测,
    后者依赖于msys2这类环境(dll),不过识别能力比单纯比scoop安装的要强

    #>
    param (
        [string]$Path
        # [switch]$CheckExtOnly
    )

    if (-not (Test-Path $Path))
    { 
        Write-Warning "File not found: [$Path]"
        return $false 
    }
    $ext = Split-Path -Path $Path -Extension
    if($ext.ToLower() -eq ".tar")
    {
        return $true
    }
    else
    {
        return $false
    }

    # 容易出现卡住的情况
    
    # $ErrorActionPreference = 'SilentlyContinue'
    # tar -tf "$Path" 2>&1
    # $exitCode = $LASTEXITCODE
    # $ErrorActionPreference = 'Continue'

    # return ($exitCode -eq 0)
}
function Compress-Lz4Package
{
    <# 
    .SYNOPSIS
    使用lz4归档(压缩)文件夹或目录的过程需通常需要分为2个步骤(因为lz4只能压缩文件,而不能直接压缩文件夹)
    1.使用tar将目录打包为tar文件(得到单个文件),使用tar将文件夹打包为单个文件的速度比较快,而不用zip这种压缩打包的方式
    2.使用lz4压缩tar文件得到.tar.lz4文件(或者可以使用开关参数控制是否将.tar这个次后缀添加到压缩文件中)
    #>
    [cmdletbinding()]
    param (
        $Path,
        # $OutputDirectory = "./",
        $OutputFile = "",
        $Threads = 16,
        # 控制是否在中间文件包中使用tar次后缀
        [switch]$NoTarExtension
    )
    Write-Verbose "正在打包目录(目标lz4): $Path " -Verbose
    $dirName = Split-Path $Path -Leaf

    # 默认输出目录为桌面
    $DefaultOutputDir = [Environment]::GetFolderPath("Desktop")
    # 判断是否将.tar添加到输出文件名中
    $TarExtensionField = if ($NoTarExtension) { "" }else { ".tar" }

    $OutputFileTar = "$DefaultOutputDir/${dirName}${TarExtensionField}"
    # 临时tar文件(被lz4压缩后将会被删除)
    $TempTar = "$DefaultOutputDir/${dirName}.tar"
    # 未指定输出路径时构造输出路径(包括输出目录和文件名)
    if ($OutputFile -eq "")
    {
        Write-Debug "输出文件名未指定，使用默认值: ${dirName}.tar"
        Write-Debug "默认存放路径为桌面:$DefaultOutputDir" 
    }
    # 确定完整的输出文件路径
    $OutputFile = "$OutputFileTar.lz4"

    # 开始处理文件夹的打包(打包到tar临时文件)
    Compress-Tar -Directory $Path -OutputFile $TempTar -OnlyDirectory

    # 若lz4.exe存在,则使用lz4压缩
    Write-Warning "请确保lz4.exe存在于环境变量PATH中,并且版本高于1.10才能支持多线程"

    # 将临时tar包文件压缩成lz4格式
    if(Test-CommandAvailability lz4)
    {
        lz4.exe -T"$Threads" $TempTar $OutputFile
    }
    else
    {
        Write-Error "lz4.exe not found, please add it to the environment variable PATH or specify the path to lz4.exe"
        return $False
    }
    # 检查结果
    Get-Item $OutputFile
    # 清理tar包
    Remove-Item $TempTar -Verbose
    
}

function Expand-Lz4TarPackage
{
    <# 
    .SYNOPSIS
    解压.tar.lz4压缩包
    #>
    [cmdletbinding()]
    param(
        $Path,
        $OutputDirectory = "",
        $Threads = 16
    )
    $temp = "$(Split-Path -Path $Path -LeafBase)"
    Write-Verbose "Expand Tar: $temp" -Verbose
    if($OutputDirectory)
    {

        New-Item -ItemType Directory -Path $OutputDirectory -Verbose -Force 
    }
    else
    {
        $OutputDirectory = $pwd.Path
    }
    if(Test-CommandAvailability lz4)
    {

        lz4 -T"$Threads" -d $Path $temp; 
    }
    else
    {
        Write-Error "lz4.exe not found, please add it to the environment variable PATH or specify the path to lz4.exe"
        return $False
    }
    Write-Verbose "Expand Tar: [$temp] to [$OutputDirectory]" -Verbose
    tar -xvf $temp -C $OutputDirectory
}
function Compress-ZstdPackage
{
    <# 
    .SYNOPSIS
    使用zstd归档(压缩)文件夹或目录的过程需通常需要分为2个步骤(因为zstd只能压缩文件,而不能直接压缩文件夹)
    .DESCRIPTION
    zstd算法达到了当前的帕累托最优,是当前最先进算法中的首选方法,在速度设置为`-1`时,速度接近lz4,如果使用`--fast`参数可以更快更接近lz4,而压缩程度会得到明显提高
    zstd的另一个优势是较早支持多线程压缩/解压,而且支持zstd格式的软件更多,win11较新版本原生支持zstd格式,7z标准版和增强版都支持解压zstd,后者还支持创建(打包成zstd)
    使用起来比lz4更加方便和友好
    .NOTES
    默认使用的压缩参数如下(速度偏好)
    线程数默认按照逻辑核心数来设置
    -T0 --auto-threads=logical -f -1
    如果需要更加灵活和自定义的zstd压缩参数,请使用原zstd命令行工具压缩
    也可以配合Compress-Tar或者直接使用tar命令,将目录打包为tar文件,然后压缩为zstd格式
    .NOTES

    1.使用tar将目录打包为tar文件(得到单个文件),使用tar将文件夹打包为单个文件的速度比较快,而不用zip这种压缩打包的方式
    2.使用zstd压缩tar文件得到.tar.zst文件(或者可以使用开关参数控制是否将.tar这个次后缀添加到压缩文件中)
    #>
    [cmdletbinding()]
    param (
        $Path,
        # $OutputDirectory = "./",
        $OutputFile = "",
        # 设置线程为0时,表示自动根据核心数量设置线程数
        $Threads = 0,
        # 自动设置线程数时(Threads=0)时,要使用逻辑核心数还是物理核心数;默认使用逻辑核心数(可以选择物理核心数模式)
        [ValidateSet('physical', 'logical')]$AutoThreads = "logical",
        # 压缩级别,默认为3,推荐范围为1-19,如果使用额外参数--ultra,级别可以达到22,但是很慢,不太推荐,值越高压缩率越高,但压缩速度也会变慢
        [ValidateRange(1, 22)]
        $CompressionLevel = 3,
        # 控制是否在中间文件包中使用tar次后缀
        [switch]$NoTarExtension
    )
    Write-Verbose "正在打包目录(目标zstd): $Path " -Verbose
    $dirName = Split-Path $Path -Leaf

    # 默认输出目录为桌面
    $DefaultOutputDir = [Environment]::GetFolderPath("Desktop")
    # 判断是否将.tar添加到输出文件名中
    $TarExtensionField = if ($NoTarExtension) { "" }else { ".tar" }

    $OutputFileTar = "$DefaultOutputDir/${dirName}${TarExtensionField}"
    # 临时tar文件(被zstd压缩后将会被删除)
    $TempTar = "$DefaultOutputDir/${dirName}.tar"
    # 未指定输出路径时构造输出路径(包括输出目录和文件名)
    if ($OutputFile -eq "")
    {
        Write-Debug "输出文件名未指定，使用默认值: ${dirName}.tar"
        Write-Debug "默认存放路径为桌面:$DefaultOutputDir" 
    }
    # 确定完整的输出文件路径
    $OutputFile = "$OutputFileTar.zst"

    # 开始处理文件夹的打包(打包到tar临时文件)
    Compress-Tar -Directory $Path -OutputFile $TempTar

    # 若zstd.exe存在,则使用zstd压缩
    Write-Warning "请确保zstd.exe存在于环境变量PATH中,并且版本尽可能高(1.5.7+)获得更好的压缩效率"

    # 将临时tar包文件压缩成zstd格式
    if(Test-CommandAvailability zstd)
    {
        
        $cmd = "zstd -T$Threads --auto-threads=$AutoThreads --ultra -f  -$CompressionLevel $TempTar -o $OutputFile"
        Write-Verbose "executeing:[ $cmd  ]" -Verbose
        $cmd | Invoke-Expression
    }
    else
    {
        Write-Error "zstd.exe not found, please add it to the environment variable PATH or specify the path to zstd.exe"
        return $False
    }
    # 检查结果
    Get-Item $OutputFile
    # 清理tar包
    Remove-Item $TempTar -Verbose
    
}
function Compress-ZstdPackageDev
{
    <# 
    .SYNOPSIS
    使用zstd归档(压缩)文件夹或目录的过程需通常需要分为2个步骤(因为zstd只能压缩文件,而不能直接压缩文件夹)
    .DESCRIPTION
    zstd算法达到了当前的帕累托最优,是当前最先进算法中的首选方法,在速度设置为`-1`时,速度接近lz4,如果使用`--fast`参数可以更快更接近lz4,而压缩程度会得到明显提高
    zstd的另一个优势是较早支持多线程压缩/解压,而且支持zstd格式的软件更多,win11较新版本原生支持zstd格式,7z标准版和增强版都支持解压zstd,后者还支持创建(打包成zstd)
    使用起来比lz4更加方便和友好
    .NOTES
    默认使用的压缩参数如下(速度偏好)
    线程数默认按照逻辑核心数来设置
    -T0 --auto-threads=logical -f -1
    如果需要更加灵活和自定义的zstd压缩参数,请使用原zstd命令行工具压缩
    也可以配合Compress-Tar或者直接使用tar命令,将目录打包为tar文件,然后压缩为zstd格式
    .NOTES

    1.使用tar将目录打包为tar文件(得到单个文件),使用tar将文件夹打包为单个文件的速度比较快,而不用zip这种压缩打包的方式
    2.使用zstd压缩tar文件得到.tar.zst文件(或者可以使用开关参数控制是否将.tar这个次后缀添加到压缩文件中)
    #>
    [cmdletbinding()]
    param (
        $Path,
        # $OutputDirectory = "./",
        $OutputFile = "",
        # 设置线程为0时,表示自动根据核心数量设置线程数
        $Threads = 0,
        # 自动设置线程数时(Threads=0)时,要使用逻辑核心数还是物理核心数;默认使用逻辑核心数(可以选择物理核心数模式)
        [ValidateSet('physical', 'logical')]$AutoThreads = "logical",
        # 压缩级别,默认为3,推荐范围为1-19,如果使用额外参数--ultra,级别可以达到22,但是很慢,不太推荐,值越高压缩率越高,但压缩速度也会变慢
        [ValidateRange(1, 22)]
        $CompressionLevel = 3,
        # 控制是否在中间文件包中使用tar后缀
        [switch]$NoTarExtension
    )
    Write-Verbose "正在处理(目标文件zstd): $Path " -Verbose
    $dirName = Split-Path $Path -Leaf

    # 默认输出目录为桌面
    $DefaultOutputDir = [Environment]::GetFolderPath("Desktop")
    # 判断是否将.tar添加到输出文件名中
    $TarExtensionField = if ($NoTarExtension) { "" }else { ".tar" }

    $OutputFileTar = "$DefaultOutputDir/${dirName}${TarExtensionField}"
    # 临时tar文件(被zstd压缩后将会被删除)
    $tempraw = "$DefaultOutputDir/${dirName}"
    $TempTar = "$tempraw.tar" # compress-tar 打包文件(而非目录)时可能因为参数会跳过处理,后缀不一定是tar文件,建议判断被压缩对象然后分情况处理
    # 未指定输出路径时构造输出路径(包括输出目录和文件名)
    if ($OutputFile -eq "")
    {
        Write-Debug "输出文件名未指定，使用默认值: ${dirName}.tar"
        Write-Debug "默认存放路径为桌面:$DefaultOutputDir" 
    }
    # 确定完整的输出文件路径
    $OutputFile = "$OutputFileTar.zst"

    # 开始处理文件夹的打包(打包到tar临时文件)
    if (Test-Path $Path -PathType Container)
    {
        Compress-Tar -Directory $Path -OutputFile $TempTar 
        $tempfile = $TempTar
    }
    else
    {
        Write-Warning "Path is not a directory, skip tar single file: $Path"
        Copy-Item $Path $tempraw -Verbose -Force
        $tempfile = $tempraw
    }

    # 若zstd.exe存在,则使用zstd压缩
    Write-Warning "请确保zstd.exe存在于环境变量PATH中,并且版本尽可能高(1.5.7+)获得更好的压缩效率"

    # 将临时tar包文件压缩成zstd格式
    if(Test-CommandAvailability zstd)
    {
        
        $cmd = "zstd -T$Threads --auto-threads=$AutoThreads --ultra -f  -$CompressionLevel $Tempfile -o $OutputFile"
        Write-Verbose "executeing:[ $cmd  ]" -Verbose
        $cmd | Invoke-Expression
    }
    else
    {
        Write-Error "zstd.exe not found, please add it to the environment variable PATH or specify the path to zstd.exe"
        return $False
    }
    # 检查结果
    Get-Item $OutputFile
    # 清理tar包
    Remove-Item $Tempfile -Verbose
    
}
function Expand-ZstdTarPackage
{
    <# 
    .SYNOPSIS
    解压.tar.zst压缩包
    #>
    [cmdletbinding()]
    param(
        $Path,
        $OutputDirectory = "",
        $Threads = 0,
        # 自动设置线程数时(Threads=0)时,要使用逻辑核心数还是物理核心数;默认使用逻辑核心数(可以选择物理核心数模式)
        [ValidateSet('physical', 'logical')]$AutoThreads = "logical"
    )
    $temp = "$(Split-Path -Path $Path -LeafBase)"
    Write-Verbose "Expand Tar: $temp" -Verbose
    if($OutputDirectory)
    {

        New-Item -ItemType Directory -Path $OutputDirectory -Verbose -Force 
    }
    else
    {
        $OutputDirectory = $pwd.Path
    }
    if(Test-CommandAvailability zstd)
    {

        # zstd -T"$Threads" -d $Path $temp; 
        zstd -T"$Threads" --auto-threads=$AutoThreads -f -d $Path -o $temp;
    }
    else
    {
        Write-Error "zstd.exe not found, please add it to the environment variable PATH or specify the path to zstd.exe"
        return $False
    }
    Write-Verbose "Expand Tar: [$temp] to [$OutputDirectory]" -Verbose
    tar -xvf $temp -C $OutputDirectory
}
function Expand-GzFile
{
    <# 
    .SYNOPSIS
    解压指定目录下的所有 .gz 文件。
    .DESCRIPTION
    如果通过管道符传递扫描到的gz文件,则直接解压这些文件
    否则,默认情况下,该函数遍历指定目录下的所有文件，并检查文件扩展名是否为 .gz，如果是则解压到指定目录下(目录不存在时自动创建)。
    
    默认优先使用 7z 解压，如果 7z 不可用则使用 gzip 解压。
    
    .PARAMETER Path
    要解压的 .gz 文件路径或包含 .gz 文件的目录路径。默认为当前目录。
    
    .PARAMETER Destination
    解压后的文件存放目录。默认为文件所在目录。
    
    .PARAMETER Force
    是否覆盖已存在的文件。
    .EXAMPLE
    # [Administrator@CXXUDESK][~\Desktop\localhost\fahrwerk-24.de][15:41:59][UP:3.82Days]
    PS> ls *gz|Expand-GzFile
    .EXAMPLE
    Expand-GzFile -Path "C:\archive\*.gz"
    解压指定路径下的所有 .gz 文件
    
    .EXAMPLE
    Get-ChildItem -Path "C:\Downloads" -Filter "*.gz" | Expand-GzFile
    通过管道传递 .gz 文件进行解压
    
    .EXAMPLE
    Expand-GzFile -Path "C:\archive" -Destination "C:\extracted"
    将目录中的所有 .gz 文件解压到指定目录
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("FullName")]
        [string[]]$Path = ".",
        
        [string]$Destination = "",
        
        [switch]$Force
    )
    
    begin
    {
        # 检查可用的解压工具
        # $7zAvailable = Test-CommandAvailability 7z
        # $gzipAvailable = Test-CommandAvailability gzip
        $7zAvailable = Get-Command 7z -ErrorAction SilentlyContinue
        $gzipAvailable = Get-Command gzip -ErrorAction SilentlyContinue
        
        if (-not $7zAvailable -and -not $gzipAvailable)
        {
            Write-Error "系统中未找到 7z 或 gzip 命令，请安装 7-Zip 或 gzip 工具后再使用此功能。"
            return
        }
        
        # 优先使用 7z，如果不可用则使用 gzip
        $decompressor = if ($7zAvailable) { "7z" } else { "gzip" }
        Write-Verbose "使用解压工具: $decompressor"
    }
    
    process
    {
        foreach ($item in $Path)
        {
            if (Test-Path -Path $item -PathType Container)
            {
                # 如果是目录，则获取该目录下所有 .gz 文件
                $gzFiles = Get-ChildItem -Path $item -Filter "*.gz" -File
            }
            elseif (Test-Path -Path $item -PathType Leaf)
            {
                # 如果是文件，则直接使用
                $gzFiles = Get-Item -Path $item
            }
            else
            {
                Write-Warning "路径不存在或无效: $item"
                continue
            }
            
            foreach ($file in $gzFiles)
            {
                # 确定输出目录
                if ([string]::IsNullOrEmpty($Destination))
                {
                    $outputDir = Split-Path -Path $file.FullName -Parent
                }
                else
                {
                    $outputDir = $Destination
                    # 确保输出目录存在
                    if (-not (Test-Path -Path $outputDir -PathType Container))
                    {
                        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
                    }
                }
                
                # 构造输出文件路径
                $outputFileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $outputFilePath = Join-Path -Path $outputDir -ChildPath $outputFileName
                
                # 检查文件是否已存在
                if (Test-Path -Path $outputFilePath -PathType Leaf)
                {
                    if ($Force)
                    {
                        Write-Verbose "覆盖已存在的文件: $outputFilePath"
                        Remove-Item -Path $outputFilePath -Force
                    }
                    else
                    {
                        Write-Warning "文件已存在，跳过解压: $outputFilePath (使用 -Force 参数覆盖)"
                        continue
                    }
                }
                
                try
                {
                    Write-Verbose "正在解压: $($file.FullName) -> $outputFilePath"
                    
                    if ($decompressor -eq "7z")
                    {
                        # 使用 7z 解压
                        $result = 7z x "$($file.FullName)" -o"$outputDir" -y
                        if ($LASTEXITCODE)
                        {
                            Write-Warning "7z 解压可能失败: $($file.FullName)"
                        }
                    }
                    else
                    {
                        # 使用 gzip 解压
                        gzip -d -c "$($file.FullName)" > "$outputFilePath"
                    }
                    
                    if (Test-Path -Path $outputFilePath -PathType Leaf)
                    {

                        Write-Verbose "成功解压: $outputFilePath" -Verbose
                    }
                    else
                    {
                        Write-Warning "解压可能失败，输出文件不存在: $outputFilePath"
                    }
                }
                catch
                {
                    Write-Error "解压文件失败: $($file.FullName) 错误: $_"
                }
            }
        }
    }
}