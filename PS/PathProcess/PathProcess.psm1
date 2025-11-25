function Compress-PathDots
{
    <# 
    .SYNOPSIS
    压缩路径,将路径中的多个连续的斜杠或反斜杠替换为单个/,并且将/../和/./压缩
    .DESCRIPTION
    分为两类
    # 对于/./?的压缩: a/./b/.-> a/b/
    # 对于/../?或处于结尾的/..的压缩: /a/p/../b/c/p/../d/p/.. -> /a/b/c/d
    .PARAMETER Path
    输入路径或者字符串

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Path
    )
    begin
    {
        Write-Verbose "Compress path dots and remove redundant slashes..."
    }
    process
    {
        $Path = $Path.Replace("\\", "/").Trim("/")
        # 对于/./?的压缩: a/./b/.-> a/b/
        if($Path -match '/[.]/')
        {
            Write-Debug "Compress /./? in path [$Path] ,for example: a/./b/.-> a/b/"
            $Path = $Path -replace '/[.]/', '/'  #-replace '/+','/' #.ToLower()
        }
        # 对于/../的压缩: /a/p/../b/c/p/../d/e -> /a/b/c/d/e
        if($Path -match '/[.]{2}/?')
        {
            Write-Debug "Compress /../? in path [$Path] ,for example: /a/p/../b/c/p/../d/p/.. -> /a/b/c/d/"
            $Path = $Path -replace '(.*?)([^/]*)/[.]{2}/?', '$1'
        }
        $res = $Path -replace '[\\/]+', '/'
        return $res.TrimEnd(".")
    }
}
function Get-AbsPath
{
    <# 
    .SYNOPSIS
    将输入路径转换为规范化的绝对路径,即便原路径本身就是绝对路径
    此外,允许尚未存在的路径参与计算判断
    .DESCRIPTION
    此函数尝试识别输入路径的类型,然后转换为规范化的绝对路径
    如果输入是相对路径,则会默认基于当前工作路径转换为绝对路径,当然,也可以指定BasePath参数来指定转换的基准路径
    .EXAMPLE
     Get-AbsPath -Path absdef
        c:/users/administrator/desktop/absdef
    .EXAMPLE
     Get-AbsPath -Path absdef -BasePath C:/
        c:/absdef
    .EXAMPLE
     Get-AbsPath -Path ../abs -BasePath C:/users/home/a/b
        C:/users/home/a/abs
    .EXAMPLE
     Get-AbsPath -Path ../abs -BasePath C:/users/home/../a/b -NoCompressDots
        C:/users/home/../a/b/../abs
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$BasePath = $(Get-Location).Path,
        [switch]$NoCompressDots
    )
    if($Path -match "^(\w:|/)")
    {
        Write-Debug "Path [$Path] looks like a absolute path"
    }
    elseif($Path -match "^[^\\/]" -or $Path -match "^[\\/]\.")
    {
        Write-Debug "Path [$Path] looks like a relative path"
        Write-Verbose "convert relative path to absolute path"
        $Path = Join-Path -Path $BasePath -ChildPath $Path
    }
    else
    {
        Write-Warning "Path [$Path] likes like a invalid path!!!"
    }
    $res = $Path.Replace("\", "/").Trim("/")
    # 酌情美化
    if(!$NoCompressDots)
    {
        $res = Compress-PathDots -Path $res

    }
    return $res
}
function Get-RelativePath
{
    <# 
    .SYNOPSIS
    计算路径a相对于路径b的相对路径(如果a是b的子目录的话)
    通常输入的两个路径都是绝对路径,这样允许被比较计算的路径可以是上不存在的路径

    .DESCRIPTION
    计算前需要将路径转换为统一目录分隔符(层级分隔符)
    系统分隔符 [System.IO.Path]::DirectorySeparatorChar
    根据通用性(兼容windows,linux路径),建议用`/`代替`\`

    .PARAMETER Path
    待处理的路径
    .PARAMETER BasePath
    基础路径


    .EXAMPLE
    可以得到理想结果的情况
    Get-RelativePath -Path "C:\Users/Administrator\Desktop/test.txt" -BasePath "C:\Users\Administrator"
    结果为: Desktop/test.txt
    .EXAMPLE
    非理想结果和异常处理1(绝对路径)
    Get-RelativePath -Path "C:/Users/Administrator/Desktop" -BasePath "C:/Users/Administrator/localhost"
    .EXAMPLE
    非理想结果和异常处理2(相对路径)
    cd $desktop
    Get-RelativePath -Path ./imgs -BasePath "C:/Users/Administrator/localhost"
    #>
    [CmdletBinding()]
    param (
        $Path,
        $BasePath
    )
    if ($Path -eq $BasePath)
    {
        return "."
    }
    # 构造绝对路径(如果$Path是相对路径的话),规范两个绝对路径(全部小写并且路径内目录分隔符统一为/)
    $Path = Get-AbsPath -Path $Path
    $BasePath = Get-AbsPath -Path $BasePath
    # 规范化
    $Path = $Path.Replace("\", "/").Trim("/") | Compress-PathDots
    $BasePath = $BasePath.Replace("\", "/").trim("/") | Compress-PathDots
    Write-Verbose "Path: $Path"
    Write-Verbose "BasePath: $BasePath"
    # 比较两个已经规范化的绝对路径(相似性检测,比如-match或者-like)
    if ("$Path" -like "$BasePath*")
    {
        Write-Verbose "Path is a child of BasePath"
    }
    else
    {
        Write-Error "Path [$Path] is not a child of BasePath [$BasePath]"
        return $false
    }
    # 如果相似性通过,则进行提取
    # $cmd = "'$Path'.Replace('$BasePath', '').Trim('/')"
    # Write-Verbose "cmd: $cmd"
    # $rel=$cmd | Invoke-Expression

    $rel = $Path.Replace($BasePath, '').Trim('/')
    if($rel -eq "")
    {
        $rel = "."
    }
    return $rel
}
function Get-PathStyleByDotNet
{
    <# 
    .SYNOPSIS
    将给定的路径字符串转换为指定系统风格的路径
    默认为Windows风格，可选Linux风格

    调用.Net api处理,会展开成绝对路径(如果路径不存在,则会基于当前目录构造路径)
    这可能不是你想要的,那么可以考虑用另一个命令:Get-StylePath
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [alias('Input')]
        [string]$Path,

        [ValidateSet("Windows", "Linux")]
        [string]$Style = "windows"
    )

    # 1. 先获取完整路径，确保是绝对路径（可处理 ...）
    $fullPath = [System.IO.Path]::GetFullPath($Path)

    # 2. 使用 Uri 来标准化路径
    $uri = New-Object System.Uri($fullPath)

    switch ($Style)
    {
        "Windows"
        {
            # Windows 风格: 返回本地路径（反斜杠）
            $convertedPath = $uri.LocalPath
        }
        "Linux"
        {
            # Linux 风格: 将 Windows 路径转为 Uri，然后手动改为 /
            $linuxStyle = $uri.LocalPath -replace '\\', '/'
            $convertedPath = $linuxStyle
        }
    }
    Write-Verbose "convert process(by dotnet): $path -> $convertedPath"
    return $convertedPath
}
function Get-PathStyle
{
    <# 
    .SYNOPSIS
    将给定的字符串(通常是path或uri路径)转换为指定风格的字符串
    .DESCRIPTION
    windows(反斜杠)风格:将路径中的/(1个或多个连续的`/`)替换为单个\ (注意,可以使用DoubleBackSlash选项,它将`/`以及单独的`\`替换为`\\`)
    posix/uri(正斜杠)风格:将路径中的\(1个或多个连续的`\`)替换为单个/
    .PARAMETER Path
    待转换的路径字符串
    .PARAMETER Style
    转换的风格,可选"Windows"或"posix"
    .NOTES
    此命令使用正则表达式来匹配路径中的斜杠，并将其替换为指定的风格。
    .EXAMPLE
     "C:/a//b//c\d\\e"|Get-PathStyle
    C:/a/b/c/d/e
    .EXAMPLE
    #⚡️[Administrator@CXXUDESK][C:\repos\scripts\wp\woocommerce\woo_df\sh][16:33:46] PS >
    "C:/a//b//c\d\\e/"|Get-PathStyle -Style posix
    C:/a/b/c/d/e/
    #⚡️[Administrator@CXXUDESK][C:\repos\scripts\wp\woocommerce\woo_df\sh][16:33:58] PS >
    "C:/a//b//c\d\\e/"|Get-PathStyle -Style Windows -DoubleBackSlash
    C:\\a\\b\\c\\d\\e\\
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        # [alias('Input')]
        # [string]
        $Path,

        [ValidateSet("Windows", "posix")]
        [string]$Style = "Windows",
        [switch]$DoubleBackSlash
    )

    process
    {
        # 对每个管道输入项进行处理
        if ($null -eq $Path)
        {
            return 
        }
        # 去掉左右多余空格
        $normalizedPath = $Path.Trim()
        Write-Debug "normalize path: [$normalizedPath]" 
        switch ($Style)
        {
            "Windows"
            {
                # 替换所有正斜杠为反斜杠
                $separator = '\'
                if($DoubleBackSlash)
                {
                    $separator = '\\'
                }
                $convertedPath = $normalizedPath -replace '[/\\]+', $separator # \号本身在正则中需要转义为\\
            }
            "posix"
            {
                # 替换所有反斜杠为正斜杠
                $convertedPath = $normalizedPath -replace '[/\\]+', '/'
            }
        }
        Write-Verbose "convert process: $path -> $convertedPath"
    }end
    {
        return $convertedPath
    }
}
    