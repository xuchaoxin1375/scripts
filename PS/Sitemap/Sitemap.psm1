
function Get-SourceFromUrls
{
    <# 
    .SYNOPSIS
    批量下载url指定的资源,通常是html
    .DESCRIPTION
    主要通过指定保存了url链接的文本文件,读取其中的url,然后串行或者并行下载url资源(比如html文件或其他资源)
    可以配合管道符或者循环来批量下载多个文件.特别适合下载站点地图中的url资源

    下载的资源带有任务启动时的时间信息,实现避免覆盖效果

    .PARAMETER Path
    指定包含url链接的文本文件路径
    .PARAMETER OutputDir
    指定资源下载的目标目录
    .PARAMETER Agent
    自定义HTTP请求的User-Agent。默认为一个通用的浏览器标识，以避免被服务器屏蔽。
    .PARAMETER TimeGap
    下载间隔时间,单位秒
    .PARAMETER Threads
    并发线程数,默认为0,即串行下载
    .EXAMPLE
    # 典型用法:
    PS> Get-SourceFromUrls -Path ame_links.txt -OutputDir amex
    .EXAMPLE
    # 批量下载多个文件,通过ls 过滤出txt文件,并排除X1.txt这个部分,使用10个线程下载
    ls *.txt -Exclude X1.txt |%{Get-SourceFromUrls -Path $_ -OutputDir htmls4ed -Threads 10 }
    .NOTES
    下载网站资源或者网页源代码往往是比较占用磁盘空间的,建议不要直接将文件下载到系统盘(如果条件允许,请下载到其他分区或者硬盘上),除非你确定当前磁盘空间充足或者下载的资源很少,否则长时间不注意可能塞满系统盘导致卡顿甚至崩溃
    #>
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        $Path,
        [parameter(Mandatory = $true)]
        $OutputDir,
        # 指定特定路径下的curl版本(绝对路径!)
        $Curl="curl",
        $Agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", 
        $proxy = "",
        $TimeGap = 1,
        $Threads = 0,
        $TimeOut = 10
    )
    # $dt = Get-DateTimeNumber
    $Path = Get-Item $Path | Select-Object -ExpandProperty FullName
    New-Item -ItemType Directory -Name $OutputDir -Force -Verbose -ErrorAction SilentlyContinue
    if($proxy)
    {
        Write-Verbose "Using proxy: $proxy" -Verbose
        $proxyinline = "-x $proxy"
    }
    else
    {
        $proxyinline = ""
    }
    # 查看当前 curl 版本(部分反爬允许高版本但是不允许低版本curl)
    Get-Command curl*
    "$curl --version" | Invoke-Expression
    # 获取当前IP
    "$curl $proxyinline https://ipinfo.io/" | Invoke-Expression
    # 串行下载
    if(!$Threads)
    {
        
        $i = 1
        Get-Content $Path | ForEach-Object {
            # $file = "$OutputDir/$(($_ -split "/")[-1])-$dt-$i.html"
            $file = "$OutputDir/---$(($_ -split "/")[-1])"
            $cmd = "$curl -m $TimeOut -A '$Agent'  -L  -k $proxyinline -o $file $_" 
            Write-Host "[$cmd]" -ForegroundColor Yellow
            $cmd | Invoke-Expression
            Start-Sleep 1
            
            # $s>"ames/$(($_ -split "/")[-1]).html"
            Write-Host "[$(Get-Date)]Downloaded($i):[ $_ ]-> $file"
            $i++
            Start-Sleep $TimeGap
        } 
    }
    else
    {
        
        # 并行版(简单带有计数)
        $counter = [ref]0
    
        Get-Content $Path | ForEach-Object -Parallel {
            $index = [System.Threading.Interlocked]::Increment($using:counter)
            # $file = "$using:OutputDir/$(($_ -split "/")[-1])-$using:dt-$index.html"
            Write-Host "Processing $_"
            $file = "$using:OutputDir/$(($_.trim('/') -split "/")[-1])"
            # debug
            # return "Debug:stop here.[$file]"
            # curl.exe -A $using:Agent -L  -k -o $file $_  -x $using:proxy
            if($_)
            {

                $cmd = "$using:curl -A '$using:Agent' --connect-timeout 5 -m $using:TimeOut -L  -k $using:proxyinline -o '$file' '$_'" 
                Write-Host "[$cmd]" -ForegroundColor Yellow
                $cmd | Invoke-Expression
            }
        
            Write-Host "[$(Get-Date)]Downloaded($index): [ $_ ] -> $file"
            Start-Sleep $using:TimeGap
        } -ThrottleLimit $threads
    
        Write-Host "`nTotal downloaded: $($counter.Value) files"
    }


    $result_file_dir = (Split-Path $Path -Parent).ToString()
    $result_file_name = (Split-Path $Path -LeafBase).ToString() + '@links_local.txt'
    Write-Verbose "Result file: $result_file_dir\$result_file_name" -Verbose
    $output = "$result_file_dir\$result_file_name"

    # 生成本地页面url文件列表
    # Get-ChildItem $OutputDir | ForEach-Object { "<loc> http://localhost/$OutputDir/$(Split-Path $_ -Leaf) </loc>" } | Out-File -FilePath "$output"
    # Get-UrlListFromDir 
    # 采集 http[参数] -> http[参数1]
    # Get-Content $output | Select-Object -First 10
}
# function Get-SitemapFromUrl {
#     param (
#         OptionalParameters
#     )
    
# }
function Get-SitemapFromUrlIndex
{
    <# 
    .SYNOPSIS
    解析包含一系列gz文件url的索引级站点地图(.xml)
    下载解析到的gz(有时候是.gzip)链接(url)对应的压缩包,批量解压它们,得到一系列的.xml文件(通常,到了这一层的.xml包含的内容是html文件)

    .NOTES
    此方案不保证处理所有情况,尤其是带有反爬的情况,xml文件可能无法用简单脚本下载,就需要手动处理,或者借助于无头浏览器进行下载
    .EXAMPLE
    $Url = 'https://www.eopticians.co.uk/sitemap.xml'
    Get-SitemapFromUrlIndex -Url $Url -OutputDir $localhost/eop
    .EXAMPLE
    set-proxy -port 8800
    Get-SitemapFromUrlIndex -Url https://www.abebooks.co.uk/sitemap.bdp_index.xml -OutputDir $localhost/abe1 -U curl 
    #>
    [CmdletBinding()]
    param(
        [parameter(ParameterSetName = 'FromUrl')]
        [alias('IndexUrl')]
        $Url,
        [parameter(ParameterSetName = 'FromFile')]
        [alias('XmlFile')]
        $Path,
        $Pattern = '<loc[^>]*>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</loc>',
        [alias('Destination')]
        $OutputDir = "",
        $UserAgent = $agent,
        $proxy = $null,
        [ValidateSet('iwr', 'curl.exe', 'curl')]
        [alias('RequestClient', 'RequestBy', 'U')]
        $DownloadMethod = 'iwr', #默认使用powershell 内置的Invoke-WebRequest(iwr)
        # 下载的站点地图是否为gz文件(gzip压缩包)
        [switch]$gz,
        # 删除下载的gz文件
        [switch]$RemoveGz 
    )
    # 合理推测推荐行为:提取用户指定路径中的某个部分拼接到$localhost目录下作为子目录
    
    if($OutputDir)
    {
        # 判断子目录
        if(Get-RelativePath -Path $OutputDir -BasePath $localhost)
        {
            Write-Debug "OutputDir: [$OutputDir] is a child of $localhost,This is a good choice."    
        }
        else
        {
            Write-Warning "OutputDir: [$OutputDir] is not a child of $localhost,This is a bad choice."
            Write-Warning "尝试截取[$outputDir]的最后一级目录名拼接到[$localhost]目录下作为子目录"
            $LeafDir = Split-Path -Path $OutputDir -LeafBase
            $OutputDir = Join-Path -Path $localhost -ChildPath $LeafDir
        }
    }
    # 下载链接对应的资源文件(.xml),抽取其中的url
    $DownloadMethod = $DownloadMethod.trim('.exe').tolower()
    Write-Verbose "DownloadMethod: [$DownloadMethod]"
    function _request_url
    {
        # param (
        #     $Url
        # )
        Write-Verbose "Requesting url: [$Url] by [$DownloadMethod]"
        if ($DownloadMethod -eq 'iwr')
        {
            $res = Invoke-WebRequest -Uri $Url -UseBasicParsing -Proxy $proxy -UserAgent $UserAgent -Verbose
            $content = $res.Content
        }
        elseif ($DownloadMethod -eq 'curl')
        {
            $content = curl.exe -L -A $UserAgent $Url
        }
        return $content
    }
    function _download_url
    {
        param (
            $Url,
            $OutputFile
        )
        Write-Verbose "Downloading url: [$Url] by [$DownloadMethod]"
        if ($DownloadMethod -eq 'iwr')
        {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -Proxy $proxy -UserAgent $UserAgent -OutFile $OutputFile -Verbose
        }
        elseif ($DownloadMethod -eq 'curl')
        {
            curl.exe -L -A $UserAgent $Url -o $OutputFile
        }
    }
    # $res = Invoke-WebRequest -Uri $Url -UseBasicParsing -Proxy $proxy -Verbose
    # $content = $res.Content 
    $content = _request_url  

    $sitemapSubUrls = $content | Get-UrlFromSitemap -Pattern $Pattern
    # 获取当前时间信息,用于构造默认文件名
    $datetime = Get-DateTimeNumber
    # 默认保存文件目录
    if($OutputDir -eq "")
    {
        $OutputDir = "$localhost/$datetime"
    }
    else
    {
        Write-Host "当前工作目录为:$(Get-Location)"
        Write-Warning "用户指定保存目录: [$OutputDir],尽量让保存目录位于[$localhost]内,保持统一性"
    }
    # 确保输出目录存在
    mkdir -Path $OutputDir -Force -ErrorAction SilentlyContinue
    # 下载并保存子级站点地图文件
    $sitemapIdx = 1
    foreach ($url in $sitemapSubUrls)
    {
        # 保存地图文件
        $file = "$OutputDir/$sitemapIdx-$($datetime).xml"
        $isGz = $gz -or $url.EndsWith(".gz") -or $url.EndsWith(".gzip") 
        if($isGz)
        {

            $file = "$file.gz"
        }
        # Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $file -Proxy $proxy
        _download_url $url $file
        
        if($isGz)
        {

            # 解压gz文件
            # 7z x 方案
            $7z = Get-Command 7z -ErrorAction SilentlyContinue
            if ($7z)
            {
                $cmd = "7z x $file -o$OutputDir " 
                Write-Verbose "[$cmd]"
                $cmd | Invoke-Expression
                # todo:检查文件是否是压缩或归档文件而不是普通的文本文件,测试或者检查响应码
            }
            else
            {
                Write-Host "7z不可用,请确保7z已安装并且配置安装目录到环境变量Path"
            }
        }

        $sitemapIdx += 1
    }
    if($RemoveGz)
    {
        Remove-Item $OutputDir/*.gz -Verbose
    }
    Write-Host "编制本地站点地图SitemapIndex"
    Get-SitemapFromLocalFiles -Path $OutputDir -Pattern *.xml
    # 
}
function Get-SitemapFromLocalFiles
{
    <# 
    .SYNOPSIS
    扫描指定目录下的所有html文件,构造合适成适合采集的url链接列表,并输出到指定文件
    .PARAMETER Path
    待扫描的目录
    .PARAMETER Hst
    站点域名(通常本地localhost)
    .PARAMETER Output
    输出文件路径
    .PARAMETER NoLocTag
    是否使用<loc>标签包裹url,默认不使用
    .PARAMETER htmlDirSegment
    html所在路径,通常为空,程序会尝试自动获取
    .PARAMETER Pattern
    输入文件扩展名,默认为.html,也可以设置为.htm,.xml等其他后缀
    如果是任意文件(甚至没有扩展名),则可以设置为*

    .PARAMETER ExtOut
    输出文件扩展名,默认为.xml.txt
    .PARAMETER Preview
    预览生成的url列表,不输出文件
    .PARAMETER PassThru
    输出结果传递,返回结果
    .EXAMPLE
    
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [alias('Directory')]
        $Path = ".",
        $Hst = "localhost",
        $Port = "80",
        # Url中的路径部分(也可以先预览输出,然后根据结果调整html所在位置),如果不指定,程序会尝试为你推测一个默认值
        $HstRoot = "$home/desktop/localhost",
        # 输出文件路径(如果不指定,则默认输出到$Path的同级别目录下)
        $Output = "",
        # 输出到文件时,每个文件最多n条url;对于html很多的情况下,适当分割成多个文件有利于提高采集器的检索速度
        $LinesOfEach = 1000,
        $Pattern = '*.html',
        $ExtOut = ".xml.txt",
        # 预览生成的本地站点url格式
        [switch]$Preview,
        [switch]$NoLocTag,
        
        # 输出(返回)结果传递
        [switch]$PassThru
    )
    # 判断$Path是否为$HstRoot的子目录,如果不是则抛出异常结束此命令
    if (!(Test-Path -Path $Path -PathType Container))
    {
        throw "Path '$Path' is not a valid directory."
    }
    if($Path -eq $HstRoot)
    {
        Write-Error "Current working path '$Path' is equal to '$HstRoot'. This will cause mess problems."
        
        return $False
        Write-Host "Chose or cd to another directory as [Path] value"
    }
    # 大致判断当前将会生成一级还是二级站点地图(顶级地图为index站点地图)
    $isIndex = if($LinesOfEach) { $true }else { $false }
    # 合理意图推测
    if($Pattern -match '.*\.xml')
    {
        Write-Warning "用户当前可能仅仅是要收集xml(比如从gz中解压出来的.xml)"
        Write-Warning "将LinesOfEach调整为0,使得站点地图组织不用多余分级"
        $LinesOfEach = 0
    }
    # 分别获取$path和$HstRoot的绝对路径字符串,对比前缀
    $Path = Get-Item $Path | Select-Object -ExpandProperty FullName
    $HstRoot = Get-Item $HstRoot | Select-Object -ExpandProperty FullName
    $absHstRoot = $HstRoot.ToLower() -replace "\\", "/"
    $absPath = $Path.ToLower() -replace "\\", "/"
    # 计算多级站点地图子级站点地图存放目录(不一定用上)
    $mapsDir = "$absPath/maps"
    if($LinesOfEach)
    {
        # 清空可能已经存在的文件
        if(Test-Path $mapsDir)
        {

            Remove-Item $mapsDir -ErrorAction SilentlyContinue #-Confirm
        }
        mkdir $mapsDir -ErrorAction SilentlyContinue -Verbose
    }
    # return $absPath,$absHstRoot
    if($absPath -notlike "$absHstRoot*")
    {
        Write-Error "Path '$absPath' is not a subdirectory of '$absHstRoot'."
        return $False

    }
    else
    {
        Write-Verbose "[$Path] is a subdirectory of [$HstRoot]."
    }
    
    $absPathSlash = $absPath + '/' #确保输出目录有/便于界定提取的值
    Write-Verbose "待处理目录绝对路径:[$absPath]"
    Write-Debug "$absPathSlash -replace `"$absHstRoot/(.*?)/(?:.*)`""
    $outputParentDefault = $absPathSlash -replace "$absHstRoot/(.*?)/(?:.*)", '$1'
    Write-Host "用户未指定输出文件路径,尝试解析默认路径:[$outputParentDefault]" -ForegroundColor 'yellow'
    $sitemapNameBaseDefault = "${outputParentDefault}_local"
    # 确定默认输出目录尝试自动计算一个合理目录名(参考输入目录)
    if ($Output -eq "")
    {
        # $absPath.Substring($absHstRoot.Length).Trim('\')
        # $OutputDefault = "$absHstRoot/${sitemapNameBaseDefault}${ext}"
        # $Output = $OutputDefault
        if ($LinesOfEach)
        {
            $postfix = "_index"
        }
        else
        {
            $postfix = ""
        }
        $sitemapIndexPath = "$absHstRoot/${sitemapNameBaseDefault}${postfix}${extOut}"
    }
    else
    {

        Write-Host "非默认路径,如果需要,请自行构造本地站点地图的http链接"
        $sitemapIndexPath = $Output
    }

    # # 清空老数据(靠后处理)
    Remove-Item $sitemapIndexPath -Force -Verbose -Confirm -ErrorAction SilentlyContinue
    Write-Host "[🚀]开始扫描[$Pattern]文件(文件数量多时需要一定时间)..."
    $files = Get-ChildItem $Path -Filter $Pattern -Recurse
    $fileCount = $files.Count
    if($fileCount -eq 0)
    {
        Write-Error "未找到符合模式[$Pattern]的文件"
    }
    else
    {

        Write-Host "待处理被匹配到的文件数:[$fileCount]"
    }

    if($LinesOfEach)
    {
        Write-Host "将会得到子级站点地图文件数:[$([math]::Ceiling($files.Count/$LinesOfEach))]"
    }
    $sitemapSubIdx = 0
    $lineIdx = 0
    # 输出路径的相关部分
    # $filebase = Split-Path ${Output} -LeafBase
    # $ext = Split-Path ${Output} -Extension # .txt

    # 遍历处理html文件
    foreach ($file in $files)
    {
        $abshtml = $file.FullName
        $P = $abshtml.Substring($absHstRoot.Length) -replace '\\', "/"
        # Write-Host [$abshtml]
        # Write-Host [$absHstRoot]
        # Write-Host [$absPath]
        # Write-Host [$P]

        # 分步方案
        $url = "http://${Hst}:${Port}/$($P.Trim('/'))" -replace '\\', "/"
        # 一步到位
        # $url = "http://${Hst}:${Port}/$file/DirSegment/$P" -Replace "(?=[^:])[/\\]+", "/"
        if (!$NoLocTag)
        {
            $url = "<loc> $url </loc>"
        }
        # Write-Host $url

        # 写入到文件中
        if($LinesOfEach)
        {
            # 计算待编号的子级站点地图文件名
            # $sitemapSub = "${filebase}_${sitemapSubIdx}${ext}"
            # $sitemapSub = "${sitemapNameBaseDefault}_${sitemapSubIdx}${ext}"
            
            # 计算子级站点地图文件名称并写入到SitemapIndex文件
            if($lineIdx % $LinesOfEach -eq 0)
            {
                $sitemapSubName = "${sitemapSubIdx}_local${ExtOut}"
                $sitemapSubPath = "$mapsDir/$sitemapSubName"
                # 计算相对网站根目录的相对路径
                $sitemapSubUrlRelative = Get-RelativePath -Path $sitemapSubPath -BasePath $absHstRoot -Verbose:$VerbosePreference

                # Write-Debug "更新SitemapIndex文件:[$sitemapIndexPath]"
                Write-Host "当前子级站点地图文件编号:[$sitemapSubIdx]"
                Write-Debug "当前写入的子级站点地图:[$sitemapSubPath]"
                $sitemapSubUrl = "http://${Hst}:${Port}/$sitemapSubUrlRelative" -replace '\\', "/"
                Write-Debug "将被写入到SitemapIndex文件中的内容:[$sitemapSubUrl]"
                if(!$NoLocTag)
                {
                    $sitemapSubUrl = "<loc> $sitemapSubUrl </loc>"
                }
                # 子级站点地图的url写入到SitemapIndex文件
                $sitemapSubUrl | Out-File -FilePath $sitemapIndexPath -Append -Encoding utf8 -Verbose:$VerbosePreference
                $sitemapSubIdx++
            }

           

            Write-Debug "Writing line to file:[$sitemapSubPath]" 
            
            $url | Out-File -FilePath $sitemapSubPath -Append -Encoding utf8 -Verbose:$VerbosePreference 
            
            $lineIdx++
            
            
        }
        else
        {
            # 单独一份
            $url | Out-File -FilePath $sitemapIndexPath -Append -Encoding utf8 -Verbose:$VerbosePreference
        }
    }
    if($sitemapIndexPath)
    {
        Write-Host "[Output(Sitemap/SitemapIndex)] $sitemapIndexPath" -ForegroundColor 'cyan'
        $OutputUrl = "http://${Hst}:${Port}/$(Get-RelativePath -Path $sitemapIndexPath -BasePath $absHstRoot)"
        Write-Host '--------默认output的参考http链接-----------------'
        Write-Host "`n$outputUrl `n" -ForegroundColor 'cyan'
        Write-Host '-------------------------'
        if($isIndex)
        {
            Write-Host "这是一个二级站点地图,注意分二级抽取url"
        }
        else
        {
            Write-Host "这是一个一级站点地图,可以直接抽取其中的url"
        }
    }
    $Output = $sitemapIndexPath
    if($Preview)
    {
        Write-Host "Preview First 5 Lines"
        Get-Content $Output | Select-Object -First 5 | Write-Host -ForegroundColor 'yellow'
    }
    if($PassThru)
    {
        return Get-Content $Output
    }
    
}
function Get-UrlFromSitemap
{
    <# 
    
    .SYNOPSIS
    从字符串(通常针对站点地图源码)中提取url
    支持管道服输入
    .DESCRIPTION
    借助于Select-String 配合-AllMatches参数进行提取
    可以考虑使用.Net api实现,例如[regex]::Matches()
    .PARAMETER Content
    站点地图源码
    .PARAMETER Pattern
    要匹配提取url的正则表达式,通常不需要手动指定,如果有特殊需要,手动指定
    # 使用正则表达式匹配 loc 标签中的 URL，支持普通文本和 CDATA 格式
    # 这里使用了多组非捕获组(?:)
    # 备用正则表达式(需要在合适的地方手动安排\s*,通常不用,除非url中包含未编码的空格)
    # $Pattern = '<loc[^>]*>\s*(?:<!\[\s*CDATA\[\s*)?(.*?)(?:\s*\]\]>)?\s*</loc>'
    .EXAMPLE
    $c1 = Get-Content Sitemap1.xml -Raw
    $c2 = Get-Content Sitemap2.xml -Raw
    # 支持数组方式批量输入多个字符串进行解析
    $c1,$c2|Get-UrlFromSitemap
    .EXAMPLE
    从在线url中获取站点地图内容并传动到此函数进行解析
    方法1:
    Get-UrlFromSitemap -Url "https://www.ryefieldbooks.com/sitemap/sitemap.xml"
    方法2:
    Invoke-WebRequest -Uri "https://www.ryefieldbooks.com/sitemap/sitemap.xml" -UseBasicParsing | Select-Object -ExpandProperty Content | Get-UrlFromSitemap
    .EXAMPLE
    # 从本地文件中读取站点地图内容并传动到此函数进行解析
    Get-UrlFromSitemap -Path "C:\Users\Administrator\Desktop\Sitemap1.xml"
    .EXAMPLE
    错误用例:使用管道服但是Get-Content没有使用-Raw参数,导致逐行传递字符串,可能无法正确解析
    Get-Content Sitemap1.xml | Get-UrlFromSitemap 
    .NOTES
    如果待处理的文件巨大,可以考虑分割成几份操作,否则可能会爆内存
    #>
    [cmdletbinding(DefaultParameterSetName = 'FromFile')]
    param(
        # 从字符串中提取url
        [Parameter(Mandatory = $true, ParameterSetName = 'FromContent', ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [alias('XmlContent')]
        $Content,
        # 从文件中提取url
        [Parameter(ParameterSetName = 'FromFile', Position = 0)]
        # [alias('FilePath')]
        $Path,
        [parameter(ParameterSetName = 'FromFile')]
        [switch]$Recurse,

        # 在线url(站点地图链接)中直接获取content解析其中url
        [parameter(ParameterSetName = 'FromUrl')]
        $Url,
        [parameter(ParameterSetName = 'FromUrl')]
        $Proxy = $null,
        [parameter(ParameterSetName = 'FromUrl')]
        $UserAgent = $agent,
        # 提取url的默认正则表达式模式
        $Pattern = '<loc[^>]*>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</loc>',
        $Output = ""
    )
    
    begin
    {
        
        $urls = [System.Collections.ArrayList]@()
        $idx = 1
    }
    process
    {
        if($PSCmdlet.ParameterSetName -eq 'FromUrl')
        {
            Write-Verbose "Fetching content from url: [$Url]"
            $res = Invoke-WebRequest -Uri $Url -UseBasicParsing -Verbose -Proxy $Proxy -UserAgent $UserAgent
            $Content = $res.Content 
        }
        elseif($PSCmdlet.ParameterSetName -eq 'FromFile')
        {
            if(Test-Path $Path -PathType Container)
            {
                Write-Warning "[$Path] is a directory, try to parse all (.xml) files in the directory."
                $Content = Get-Content "$Path/*.xml" -Verbose -Raw -Recurse:$Recurse
                $Content = $Content -join "`n"
            }
            else
            {

                Write-Verbose "Reading content from file: [$Path]"
                $Content = Get-Content $Path -Raw 
            }
        }
        # 清空空白字符,让正则表达式可以不用考虑空格带来的影响,使得表达式更加简化和高效
        Write-Verbose "Processing String [$($idx)]"
        $Content = $Content -replace "[\s\r\n]+", "" 
        Write-Debug "[$Content]" 
        $idx++
        $urlsCurrent = [System.Collections.ArrayList]@()
        Select-String -Pattern $pattern -InputObject $Content -AllMatches | 
        ForEach-Object { $_.Matches } | 
        ForEach-Object { 
            $urlsCurrent += $_.Groups[1].Value.Trim() 
        }
        Write-Verbose "Extracted URLs: $urlsCurrent"
        $urls.AddRange( $urlsCurrent)
        
    }
    end
    {
        
        if($Output)
        {
            Write-Host "Output URLs to file: $Output" -ForegroundColor Cyan
            $urls | Out-File -FilePath $Output -Encoding utf8 -Verbose
        }
        return $urls
    }

}
function Get-UrlFromSitemapFile 
{
    <# 
    .SYNOPSIS
    从站点地图（sitemap）文件中提取URL。
    
    .DESCRIPTION
    该函数读取sitemap文件，并使用正则表达式提取其中的URL。它可以通过管道接收输入，并支持指定URL的匹配模式。
    
    .PARAMETER Path
    指定sitemap文件(.xml文件)的路径。该参数支持从管道或通过属性名称从管道接收输入。
    
    
    .PARAMETER Pattern
    指定用于匹配URL的正则表达式模式。默认值为"<loc>(.*?)</loc>"，这是针对大多数sitemap.xml文件中URL格式的通用模式。
    
    .EXAMPLE
    Get-UrlFromSitemap -Path "C:\sitemap.xml"
    从C:\sitemap.xml文件中提取URL，默认使用"<loc>(.*?)</loc>"作为匹配模式。
    
    .EXAMPLE
    # 从管道接收sitemap文件路径
    "C:\sitemap.xml" | Get-UrlFromSitemapFile -Pattern "<url>(.*?)</url>"
    从C:\sitemap.xml文件中提取URL，使用"<url>(.*?)</url>"作为匹配模式。

    .EXAMPLE
    # 从多个sitemap文件中提取URL，并将结果输出到文件
    PS> ls Sitemap*.xml|Get-UrlFromSitemapFile -Output links.1.txt
    Pattern to match URLs: <loc>(.*?)</loc>
    Processing sitemap at path: C:\sites\wp_sites\local\maps\Sitemap1.xml [C:\sites\wp_sites\local\maps\Sitemap1.xml]
    Processing sitemap at path: C:\sites\wp_sites\local\maps\Sitemap2.xml [C:\sites\wp_sites\local\maps\Sitemap2.xml]

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        $Path,
        $Pattern = "<loc[^>]*>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</loc>",
        $Output = "",
        [switch]$PassThru
    )
    begin
    {
        Write-Host "Pattern to match URLs: $Pattern" -ForegroundColor Cyan
    }
    process
    {
        $abs = Get-Item $Path | Select-Object -ExpandProperty FullName
        Write-Host "Processing sitemap at path: $Path [$abs]"

        $content = Get-Content $Path -Raw
        $ms = [regex]::Matches($content, $Pattern)
        $res = $ms | ForEach-Object { $_.Groups[1].Value }
        if(!$Output)
        {
            if($localhost)
            {

                $OutputDir = "$localhost/$(Get-DateTimeNumber)"
                mkdir -Path $OutputDir -Force -ErrorAction SilentlyContinue
                $Output = "$OutputDir/sitemap_urls.txt"
            }
            else
            {
                $Output = "$(Get-Location)/sitemap_urls.txt"
            }
        }
        Write-Host "Output URLs to file: $Output" -ForegroundColor Cyan
        if($PassThru)
        {
            return $res
        }
    }
}