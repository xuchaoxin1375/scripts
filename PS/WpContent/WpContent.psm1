<#
WpContent 模块:WordPress 内容处理(图片搬运/Shopify 采集/SQL 批量)。
从 WordPress.psm1 迁入: WordPress 只留本地建站与总入口 Deploy-Wp,内容处理归此模块;
调用方命令名不变(自动发现同名模块)。
#>

function Move-ItemImagesFromCsvPathFields
{
    <# 
    .SYNOPSIS
    将csv文件中的指定字段移动到指定目录

    .PARAMETER Path
    csv文件路径
    .PARAMETER Fields
    要移动的字段名(暂时支持1个字段)
    .PARAMETER SourceDir
    需要被移动的文件所在目录
    .PARAMETER Destination
    文件要被移动到的目标目录
    .PARAMETER UseDomainNamePair
    使用一组域名(字符串数组)来简单指定从哪个站的图片目录移动到另一个站的图片目录

    .EXAMPLE

    #修改配置(图片从哪个站点移动到另一个站点)
    $fromDomain = "domain1.com"
    $toDomain = "domain2.com"
    $csv = "p44.csv" #修改为要移动的csv文件名
    $csvFullPath = "$Desktop\data_output\$fromDomain\$csv"
    # 开始处理
    $csvfrom = "$Desktop\data_output\$fromDomain\$csv"
    $csvdest = "$Desktop\data_output\$toDomain\$csv"
    Move-ItemImagesFromCsvPathFields -Path $csvFullPath -UseDomainNamePair $fromDomain, $toDomain  -ImgExtPattern '.webp' -Verbose # -IgnoreExtension

    #移动csv
    Move-Item $csvfrom $csvdest -V

    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "UsePath")]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        $Path,
        $Fields = 'Images',
        
        [Parameter(ParameterSetName = "UsePath")]
        $SourceDir,
        [Parameter(ParameterSetName = "UsePath")]
        [Alias('TargetDir')]$Destination,

        [Parameter(ParameterSetName = "UseDomainNamePair")]
        [string[]]$UseDomainNamePair,

        $WorkingDirectory = "$my_wp_sites",
        $YearField = (Get-Date -Format 'yyyy'),
        # 仅处理后缀名符合匹配模式的图片文件(比如取'*.webp',仅移动webp图片),和-IgnoreExtension参数互斥
        $ImgExtPattern = '',
        # 是否忽略图后缀名,仅匹配文件名前缀并移动对应文件(和-ImgExtPattern参数互斥)
        [switch]$IgnoreExtension
    )
    # $csv = Import-Csv $CsvPath
    process
    {
        Write-Verbose "Processing file: $Path" -Verbose
        if(!(Test-Path $Path))
        {
            Write-Warning "文件不存在: $Path"
            return $False
        }
        if($PSCmdlet.ParameterSetName -eq "UseDomainNamePair" -and $UseDomainNamePair)
        {
            $midPath = "wp-content/uploads/$YearField"
            $SourceDir = "$WorkingDirectory/$($UseDomainNamePair[0])/$midPath"
            $Destination = "$WorkingDirectory/$($UseDomainNamePair[1])/$midPath"
            Write-Host "源目录: [$SourceDir] -> [$Destination]" 
        }
        # pause
        $values = Import-Csv $Path | Select-Object -ExpandProperty $Fields
        if ($IgnoreExtension)
        {
            Write-Warning '忽略图片文件后缀(速度会比较慢),可以配合Get-WpSitesLocalImagesCount 查看' 
            $values = $values | ForEach-Object { $_ -replace '\.\w+$', '.*' }
        }
        elseif($ImgExtPattern)
        {
            Write-Warning "仅处理后缀名符合匹配模式[$ImgExtPattern]的图片文件"
            $values = $values | ForEach-Object { $_ -replace '\.\w+$', $ImgExtPattern }
        }
        # 如果$values中元素为0 则不处理
        if ($values.Count -eq 0)
        {  
            Write-Warning "无对应图片文件需要处理..."         
            return $false
        }
        # Write-Host $values[1..10]
        $movedCount = 0
        $values | ForEach-Object { 
            # Write-Host "Moving file: $SourceDir/$_ to $Destination"

            Move-Item -Path $SourceDir/$_ -Destination $Destination -Verbose -ErrorAction SilentlyContinue # -Confirm
            $movedCount++
        }
        Write-Host "Done! Moved [$movedCount] items."
    } 

}
function Get-WpImages
{
    <# 
    .SYNOPSIS
    获取WordPress网站的图片列表
    #>
    [CmdletBinding()]
    param(
        [Alias('CSVPath')]$Path,
        [Alias('OutputDir')]$Directory,
        $ImageDownloader = "$pys\image_downloader.py"
    )

    python $ImageDownloader -c -n -R auto -k -d $Path -o $Directory
}
function Import-WpSqlBatch
{
    param(
        $Range = @(1, 2, 4, 6, 7),
        $Country = @('us', 'fr', 'de', 'es', 'it')
    )
    foreach($c in $Country)
    {
        # Import-MysqlFile -SqlFilePath C:\sites\wp_sites\base_sqls\1.de.sql -DatabaseName "1.de" -MySqlUser root -key $env:MySqlKey_LOCAL  -verbose
        $Range | ForEach-Object { Import-MysqlFile -SqlFilePath C:\sites\wp_sites\base_sqls\$_.${c}.sql -DatabaseName "$_.${c}" -MySqlUser root -key $env:MySqlKey_LOCAL }
    }
}

function Get-XXXShopifyProductJsonUrlArchived
{
    <#
.SYNOPSIS
    解析给定的Shopify网站URL,查找并提取所有产品的.json链接。

.DESCRIPTION
    该函数首先访问给定URL下的 /sitemap.xml 文件,这是一个站点地图索引。
    然后,它会查找所有指向产品站点地图(通常包含 "_products_" 字符串)的链接。
    接着,它会访问每一个产品站点地图,并提取其中列出的所有产品URL。
    最后,为每个产品URL附加".json"后缀,并输出一个包含源站点和最终URL的自定义对象。
    此函数完全支持管道输入,可以轻松地进行批量处理。



.PARAMETER Url
    一个或多个Shopify网站的URL。此参数接受管道输入。可以是单个URL字符串,也可以是URL字符串数组。

#>

    [CmdletBinding()]
    param (
        [
        Parameter(
            # Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0,
            HelpMessage = "请输入一个或多个Shopify网站的URL"
        )   
        ]
        # 输入的URL(可以是数组)
        [string[]]$Url,
        # 另一种输入url的方式:可以是包含url的文本文件(每行一个),函数会尝试将此参数解释为文件路径,如果不是,则将其作为url字符串(数组)处理
        [alias('Table', 'Path', 'File')]$UrlsFromFile = "",
        [alias('Wrapper')]$Tag = "loc",
        $Destination = ".",
        [switch]$OutFiles
    )

    begin
    {
        Write-Verbose "函数开始执行。"
        $successList = [System.Collections.Generic.List[string]]::new()
        $failedList = [System.Collections.Generic.List[string]]::new()
        if ($OutFiles -and (-not (Test-Path $Destination)))
        {
            New-Item -Path $Destination -ItemType Directory -Force -ErrorAction SilentlyContinue -Verbose
        }
        if(Test-Path $UrlsFromFile)
        {
            Write-Verbose "使用Table模式将优先从url配置文件中读取url(要求格式为每行一个url),并且Url参数取值将被忽略."
            Write-Verbose "正在尝试从文件$UrlsFromFile 中读取url列表"
            $Url = Get-Content $UrlsFromFile 
            $msg = $Url | Format-DoubleColumn | Out-String
            Write-Verbose "读取到以下url列表:`n $msg"
        }
    }

    process
    {
        # 循环处理从管道或参数传入的每一个URL
        # 使用foreach主要为了支持使用参数传入多个URL的情况
        foreach ($singleUrl in $Url)
        {
            try
            {
                # 1. 构造URI对象并获取主站点地图URL
                $uri = [System.Uri]$singleUrl
                # $mainSitemapUrl="$singleurl/sitemap.xml"
                $mainSitemapUrl = "$($uri.Scheme)://$($uri.Host)/sitemap.xml"

                Write-Verbose "正在处理站点: $($uri.Host)"
                Write-Verbose "正在获取主站点地图: $mainSitemapUrl"

                # 2. 获取并解析主站点地图 (sitemap.xml)
                # 使用[xml]强制类型转换,将返回的文本内容解析为XML对象
                # 方案1:使用iwr
                # $mainSitemapXml = [xml](Invoke-WebRequest -Uri $mainSitemapUrl -ErrorAction Stop -UseBasicParsing).Content
                # 方案2:使用curl
                # [xml]$mainSitemapXml = curl.exe -s $mainSitemapUrl | Out-String
                $tmpFile = "$env:TEMP/sitemap.xml"
                curl.exe -o $tmpFile $mainSitemapUrl #使用-s参数静默模式,不输出任何信息

                if (Test-Path $tmpFile)
                {
                    [xml]$mainSitemapXml = Get-Content -Path $tmpFile
                }
                else
                {
                    Write-Error "无法下载站点地图 XML 文件。"
                }

                # 3. 查找所有产品相关的子站点地图URL(有些大站不止一个站点地图)
                # sitemapindex -> sitemap -> loc
                $productSitemapUrls = $mainSitemapXml.sitemapindex.sitemap |
                Where-Object { $_.loc -like '*_products_*.xml*' } |
                Select-Object -ExpandProperty loc

                if (-not $productSitemapUrls)
                {
                    Write-Warning "在 $($uri.Host) 上未找到任何产品相关的站点地图。"
                    continue # 继续处理下一个URL
                }
                # 收集所有产品相关的.json链接写入文件(如果需要)
                # $jsonUrls = [System.Collections.Generic.List[string]]::new()
                
                # 4. 遍历所有找到的产品站点地图URL,逐个地图解析处理
                foreach ($productSitemapUrl in $productSitemapUrls)
                {
                    Write-Verbose "正在获取产品子站点地图: $productSitemapUrl"
                    # 5. 获取并解析产品子站点地图
                    $productSitemapXml = [xml](Invoke-WebRequest -Uri $productSitemapUrl -ErrorAction Stop -UseBasicParsing).Content
                    # [xml]$mainSitemapXml = curl.exe  $productSitemapUrl | Out-String

                    # 6. 提取所有产品链接并构造.json链接
                    # urlset -> url -> loc
                    $productUrls = $productSitemapXml.urlset.url.loc
                    
                    $cnt = 0
                    foreach ($productUrl in $productUrls)
                    {
                        $productUrl = $productUrl.TrimEnd('/') # 去掉末尾的斜杠
                        if($productUrl -eq $Url)
                        {
                            # 跳过主站点url
                            continue
                        }
                        # 7. 输出结构化对象
                        if ($Tag)
                        {
                            $productJsonUrl = "<$Tag>${productUrl}.json</$Tag>"
                        }
                        else
                        {
                            $productJsonUrl = "$productUrl.json"
                        }
                        # 构造单条jsonurl结果
                        if($OutFiles)
                        {
                            
                            $file = Join-Path $Destination "$($uri.Host).txt"
                            $productJsonUrl | Out-File -FilePath $file -Encoding utf8 -Force -Append
                        }
                        [PSCustomObject]@{
                            SourceSite     = $uri.Host
                            ProductJsonUrl = $productJsonUrl
                        }
                        $cnt += 1
                    }
                    Write-Verbose "在 $productSitemapUrl 中找到 $cnt 个产品链接。" -Verbose
                }

                # 记录成功处理的站点
                $successList.Add($singleUrl)
            
            }
            catch
            {
                # 统一的错误处理,使调试更容易
                Write-Error "处理输入站点URL '$singleUrl' 时发生: $($_.Exception.Message);跳过处理,可能不是shopify站点"
                # 记录失败处理的站点
                $failedList.Add($singleUrl)
            
            }
        }
    }

    end
    {
        $nl = [System.Environment]::NewLine 
        Write-Verbose "====全部执行完毕=====" -Verbose
        Write-Verbose "成功处理 $($successList.Count) 个站点,失败 $($failedList.Count) 个站点。" -Verbose
        Write-Verbose "成功列表:${nl}$($successList -join $nl)" -Verbose
        Write-Verbose "失败列表:${nl}$($failedList -join $nl)" -Verbose
    }
}

function Get-ShopifyProductJsonUrl
{
    <#
.SYNOPSIS
    解析Shopify网站URL，智能提取所有产品的.json链接，支持会话缓存、双引擎、自动重试和代理切换。

.DESCRIPTION
    此函数实现了智能会话缓存：当成功请求一个主机后，它会“记住”所用的引擎（IWR/Curl）和代理。
    在处理该主机的后续请求（如多级站点地图）时，会优先使用已知的成功配置，极大提升处理效率。
    如果优先尝试失败，它会自动回退到包含双引擎切换和代理轮询的完整重试逻辑，确保最高的成功率。

.PARAMETER Url
    一个或多个Shopify网站的URL。此参数接受管道输入。

.PARAMETER UrlsFromFile
    提供一个包含URL列表的文本文件路径（每行一个URL）。

.PARAMETER Engine
    选择用于下载内容的引擎。
    - 'Auto' (默认): 先用 IWR 尝试，失败后自动回退到 Curl.exe。
    - 'Iwr':  仅使用 PowerShell 的 Invoke-WebRequest。
    - 'Curl': 仅使用 curl.exe (如果可用)。
    [ValidateSet('Auto', 'Iwr', 'Curl')]

.PARAMETER TimeoutSec
    为 curl.exe 设置的超时时间（秒）。默认为 60 秒。

.PARAMETER Proxy
    用于重试的代理服务器地址数组。默认为: @('http://localhost:7897', 'http://localhost:8800')。

.PARAMETER RetryCount
    每个引擎的最大请求尝试次数。默认为3次。

.PARAMETER UserAgent
    指定在Web请求中使用的用户代理字符串。

.PARAMETER Tag
    一个可选的字符串，用于将输出的JSON URL包裹起来。

.PARAMETER Destination
    如果使用 -OutFiles 开关，则指定保存结果文件的目录。

.PARAMETER OutFiles
    一个开关参数，用于将结果按站点保存到文本文件。
.EXAMPLE
    # 典型用法🎈
    Get-ShopifyProductJsonUrl -Destination "$desktop/localhost/$(get-date -format 'MMdd')" -OutFiles -Verbose -UrlsFromFile 'C:\Users\Administrator\desktop\your_urls.txt' 

.EXAMPLE
    # 智能处理一个大型网站，-Verbose会显示缓存命中和更新过程
    'https://ca.shop.gymshark.com' | Get-ShopifyProductJsonUrl -Verbose

.EXAMPLE
    # 强制使用 curl 引擎处理文件中的站点列表
    Get-ShopifyProductJsonUrl -UrlsFromFile 'sites.txt' -Engine Curl -Destination ".\ShopifyLinks" -OutFiles


.EXAMPLE
# 适当配置代理可以提高判断正确率(比如有些站禁止你所在地区的ip,从而返回403这类错误,影响到代码对站点的类型(是否为shopify)的判断)
Set-Proxy 7897
# 执行站点地图转换
Get-ShopifyProductJsonUrl -UrlsFromFile 'abc.txt' -Destination "$desktop/localhost" -OutFiles 

.EXAMPLE
# 单挑链接处理
    PS C:\> Get-ShopifyProductJsonUrl -Url 'https://pwrpux.com'

    SourceSite   ProductJsonUrl
    ----------   --------------
    pwrpux.com   https://pwrpux.com/products/the-original.json
    pwrpux.com   https://pwrpux.com/products/the-original-refill-3-pack.json
    ...

    描述: 处理单个URL。

.EXAMPLE
    PS C:\> 'https://pwrpux.com', 'https://ca.shop.gymshark.com' | Get-ShopifyProductJsonUrl

    描述: 通过管道传递一个URL数组来批量处理两个网站。

.EXAMPLE
    PS C:\> Get-Content -Path .\sites.txt | Get-ShopifyProductJsonUrl -Verbose

    描述: 从一个名为 sites.txt 的文件中读取URL列表 (每行一个URL),
    然后通过管道将其传递给函数进行处理。-Verbose开关会显示详细的操作过程,便于调试。

.EXAMPLE
    PS C:\> 'https://pwrpux.com' | Get-ShopifyProductJsonUrl | Export-Csv -Path .\product_links.csv -NoTypeInformation

    描述: 获取一个网站的所有产品JSON链接,并将结果导出为CSV文件。

.NOTES
    常用参数组合:
    -Destination "$desktop/localhost/$(get-date -format 'MMdd')" -OutFiles -Verbose
.NOTES
    - 依赖于 Invoke-WebRequest, 因此需要有效的网络连接。
    - 使用了try/catch块来处理网络请求失败或XML解析错误,增强了脚本的健壮性。
    - 输出为PSCustomObject,方便进行排序、筛选(Where-Object)或导出(Export-Csv)等后续操作。

.NOTES
    - 核心优势：对每个主机（域名）的成功连接方法进行缓存，避免对同一站点的重复试错。
    - 在处理包含数十个产品站点地图的大型Shopify商店时，此优化效果尤为显著。
    - 依然保留了双引擎回退和代理重试的健壮性作为后备方案。
#>

    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Position = 0)]
        [Object[]]$Url,

        [alias('Table', 'Path', 'File')]
        [string]$UrlsFromFile,

        [ValidateSet('Auto', 'Iwr', 'Curl')]
        [string]$Engine = 'Auto',

        [int]$TimeoutSec = 10,

        [string[]]$Proxy = @('http://localhost:7897', 'http://localhost:8800'),

        [int]$RetryCount = 3,

        [string]$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        
        [alias('Wrapper')]
        [string]$Tag = 'loc',

        [string]$Destination = ".",

        [switch]$OutFiles
    )

    begin
    {
        Write-Verbose "函数开始执行。引擎模式: $Engine。启用智能会话缓存。"
        
        $curlPath = Get-Command curl.exe -ErrorAction SilentlyContinue
        if (-not $curlPath -and ($Engine -ne 'Iwr'))
        {
            Write-Warning "未找到 curl.exe。引擎 '$Engine' 模式下的 Curl 功能将不可用。"
        }
        
        # 初始化主机成功配置缓存
        $hostSuccessCache = @{}
        $successList = [System.Collections.Generic.List[string]]::new()
        $failedList = [System.Collections.Generic.List[string]]::new()

        # --- 内部请求函数，已集成智能缓存逻辑 ---
        function Invoke-RequestWithRetry
        {
            param(
                [string]$Uri,
                [string]$RequestEngine,
                [hashtable]$Cache,
                [string[]]$Proxies,
                [int]$Retries,
                [string]$UA,
                [int]$Timeout = $TimeoutSec ,
                [System.Management.Automation.CommandInfo]$CurlExecutable
            )
            
            $HostName = ([System.Uri]$Uri).Host
            $proxyRotation = @($null) + $Proxies
            $maxAttemptsPerEngine = [math]::Min($Retries, $proxyRotation.Count)

            # 1. 智能尝试：优先使用缓存的成功配置
            if ($Cache.ContainsKey($HostName))
            {
                $cachedConfig = $Cache[$HostName]
                $cachedProxyDisplay = if ($cachedConfig.Proxy) { "'$($cachedConfig.Proxy)'" } else { '直连' }
                Write-Verbose "发现主机 '$host' 的缓存配置。优先尝试引擎: '$($cachedConfig.Engine)', 代理: $cachedProxyDisplay"

                try
                {
                    if ($cachedConfig.Engine -eq 'Iwr')
                    {
                        $iwrParams = @{ Uri = $Uri; UseBasicParsing = $true; ErrorAction = 'Stop'; UserAgent = $UA; TimeoutSec = $TimeoutSec }
                        if ($cachedConfig.Proxy) { $iwrParams.Proxy = $cachedConfig.Proxy }
                        $response = Invoke-WebRequest @iwrParams
                        Write-Verbose "缓存配置请求成功！"
                        return $response.Content
                    }
                    elseif ($cachedConfig.Engine -eq 'Curl' -and $CurlExecutable)
                    {
                        $curlArgs = @('-sL', '--connect-timeout', $Timeout, '--max-time', $Timeout, '-A', $UA)
                        if ($cachedConfig.Proxy) { $curlArgs += '--proxy', $cachedConfig.Proxy }
                        $curlArgs += $Uri
                        $result = & $CurlExecutable.Source @curlArgs | Out-String
                        if ($LASTEXITCODE -eq 0)
                        {
                            Write-Verbose "缓存配置请求成功！"
                            return $result
                        }
                        throw "Curl使用缓存配置失败 (退出码: $LASTEXITCODE)。"
                    }
                }
                catch
                {
                    Write-Warning "缓存的配置此次请求失败: $($_.Exception.Message)。将回退到标准重试流程。"
                }
            }

            # 2. 标准重试流程 (仅当智能尝试失败或无缓存时执行)
            # --- 引擎 1: Invoke-WebRequest ---
            if ($RequestEngine -in ('Auto', 'Iwr'))
            {
                Write-Verbose "使用引擎 [Invoke-WebRequest] 开始标准重试流程..."
                for ($i = 0; $i -lt $maxAttemptsPerEngine; $i++)
                {
                    $currentProxy = $proxyRotation[$i]
                    $proxyDisplay = if ($currentProxy) { "'$currentProxy'" } else { '直连' }
                    
                    try
                    {
                        Write-Verbose "IWR 尝试 $($i+1)/$maxAttemptsPerEngine 使用代理 $proxyDisplay"
                        # 注意配置超时限制,否则会无限尝试卡住
                        $iwrParams = @{ Uri = $Uri; UseBasicParsing = $true; ErrorAction = 'Stop'; UserAgent = $UA ; TimeoutSec = $TimeoutSec }
                        if ($currentProxy) { $iwrParams.Proxy = $currentProxy }
                        $response = Invoke-WebRequest @iwrParams
                        
                        Write-Verbose "IWR 请求成功。为 '$host' 缓存配置 (Proxy: $proxyDisplay)"
                        $Cache[$HostName] = @{ Engine = 'Iwr'; Proxy = $currentProxy }
                        return $response.Content
                    }
                    catch
                    { 
                        Write-Warning "IWR 尝试 $($i+1) 失败: $($_.Exception.Message)" 
                    }
                }
            }

            # --- 引擎 2: curl.exe ---
            if ($RequestEngine -in ('Auto', 'Curl') -and $CurlExecutable)
            {
                Write-Verbose "使用引擎 [curl.exe] 开始标准重试流程..."
                for ($i = 0; $i -lt $maxAttemptsPerEngine; $i++)
                {
                    $currentProxy = $proxyRotation[$i]
                    $proxyDisplay = if ($currentProxy) { "'$currentProxy'" } else { '直连' }

                    try
                    {
                        Write-Verbose "Curl 尝试 $($i+1)/$maxAttemptsPerEngine 使用代理 $proxyDisplay"
                        $curlArgs = @('-sL', '--connect-timeout', $Timeout, '--max-time', $Timeout, '-A', $UA)
                        if ($currentProxy) { $curlArgs += '--proxy', $currentProxy }
                        $curlArgs += $Uri
                        $result = & $CurlExecutable.Source @curlArgs | Out-String
                        if ($LASTEXITCODE -eq 0)
                        {
                            Write-Verbose "Curl 请求成功。为 '$host' 缓存配置 (Proxy: $proxyDisplay)"
                            $Cache[$HostName] = @{ Engine = 'Curl'; Proxy = $currentProxy }
                            return $result
                        }
                        Write-Warning "Curl 尝试 $($i+1) 失败 (退出码: $LASTEXITCODE)。"
                    }
                    catch
                    { 
                        Write-Warning "Curl 尝试 $($i+1) 发生脚本错误: $($_.Exception.Message)" 
                    }
                }
            }
            
            throw "经过所有引擎和重试后，无法获取'$Uri'。"
        }
        
        # url字符串的列表
        $allUrls = [System.Collections.Generic.List[string]]::new()
        if ($Url) { $allUrls.AddRange($Url) }
        if ($UrlsFromFile -and (Test-Path $UrlsFromFile))
        {
            Write-Verbose "正在从文件 '$UrlsFromFile' 中读取URL列表..."
            $content = Get-Content $UrlsFromFile #$content是Object[]数组
            
            $allUrls.AddRange([String[]]$content)
        }
        $allUrls = $allUrls | Select-Object -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        Write-Verbose "将要处理 $($allUrls.Count) 个唯一的URL。"
        if ($OutFiles -and (-not (Test-Path $Destination)))
        {
            New-Item -Path $Destination -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }

    process
    {
        foreach ($singleUrl in $allUrls)
        {
            try
            {
                $uri = [System.Uri]$singleUrl
                $mainSitemapUrl = "$($uri.Scheme)://$($uri.Host)/sitemap.xml"
                Write-Verbose "===== 开始处理站点: $($uri.Host) ====="
                
                # 每次调用都传入同一个缓存对象
                $requestParams = @{
                    RequestEngine  = $Engine
                    Cache          = $hostSuccessCache
                    Proxies        = $Proxy
                    Retries        = $RetryCount
                    UA             = $UserAgent
                    Timeout        = $TimeoutSec
                    CurlExecutable = $curlPath
                }
                
                $requestParams.Uri = $mainSitemapUrl
                $mainSitemapXmlContent = Invoke-RequestWithRetry @requestParams
                [xml]$mainSitemapXml = $mainSitemapXmlContent

                $productSitemapUrls = $mainSitemapXml.sitemapindex.sitemap |
                Where-Object { $_.loc -like '*_products_*.xml*' } |
                Select-Object -ExpandProperty loc

                if (-not $productSitemapUrls)
                {
                    Write-Warning "在 $($uri.Host) 上未找到任何产品相关的站点地图。主站点地图已获取，但内容不符合预期。"
                    $successList.Add($singleUrl) # 标记为成功因为主sitemap已获取
                    continue
                }

                foreach ($productSitemapUrl in $productSitemapUrls)
                {
                    Write-Verbose "正在处理产品子站点地图: $productSitemapUrl"
                    $requestParams.Uri = $productSitemapUrl
                    $productSitemapXmlContent = Invoke-RequestWithRetry @requestParams
                    [xml]$productSitemapXml = $productSitemapXmlContent
                    
                    $productUrls = $productSitemapXml.urlset.url.loc
                    $productCount = 0

                    foreach ($productUrl in $productUrls)
                    {
                        $trimmedProductUrl = $productUrl.TrimEnd('/')
                        if ($trimmedProductUrl -like "*/collections*" -or $trimmedProductUrl -eq $uri.AbsoluteUri.TrimEnd('/')) { continue }
                        
                        $productCount++
                        $finalJsonUrl = "$($trimmedProductUrl).json"
                        if ($Tag) { $finalJsonUrl = "<$Tag>$finalJsonUrl</$Tag>" }
                        
                        [PSCustomObject]@{
                            SourceSite     = $uri.Host
                            ProductJsonUrl = $finalJsonUrl
                        }

                        if ($OutFiles)
                        {
                            $file = Join-Path $Destination "$($uri.Host).txt"
                            $finalJsonUrl | Out-File -FilePath $file -Encoding utf8 -Append
                        }
                    }
                    Write-Verbose "在 $productSitemapUrl 中找到 $productCount 个有效产品链接。"
                }
                $successList.Add($singleUrl)
            }
            catch
            {
                Write-Error "处理URL '$singleUrl' 时发生严重错误: $($_.Exception.Message)"
                $failedList.Add($singleUrl)
            }
            finally 
            {
                Write-Verbose "===== 完成处理站点: $($uri.Host) ====="
            }
        }
    }

    end
    {
        $nl = [System.Environment]::NewLine
        Write-Verbose "---"
        Write-Verbose "全部执行完毕"
        Write-Verbose "成功处理 $($successList.Count) 个站点, 失败 $($failedList.Count) 个站点。"
        if ($successList.Count -gt 0)
        {
            Write-Verbose "成功列表:${nl}$($successList -join $nl)"
        }
        if ($failedList.Count -gt 0)
        {
            Write-Warning "失败列表:${nl}$($failedList -join $nl)"
        }
    }
}
function Get-WpSitesLocalImagesCount
{
    [CmdletBinding()]
    param (
        [Alias('Root', "Directory")]$Path = "$desktop/my_wp_sites",
        $Pattern = (Get-Date).Year,
        $Depth = 4
    )

    # 记录开始时间
    $startTime = Get-Date

    # 获取所有匹配的目录
    $directories = Get-ChildItem -Path $Path -Recurse -Directory -Depth $Depth -Filter $Pattern

    if ($directories.Count -eq 0)
    {
        Write-Warning "未找到符合 Pattern='$Pattern' 的目录"
        return
    }

    Write-Verbose "开始并行处理 $($directories.Count) 个目录..." -Verbose

    # 并行统计每个目录中的文件数量
    $results = $directories | ForEach-Object -Parallel {
        $dir = $_.FullName
        $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()

        $count = (Get-ChildItem -Path $dir -Recurse -File | Measure-Object).Count

        $stopWatch.Stop()
        $duration = $stopWatch.Elapsed.ToString("g")

        # 构建结果对象
        $result = [PSCustomObject]@{
            Directory = $dir
            Count     = $count
        }

        # 立即输出完成信息（verbose）
        $msg = "[完成] 目录: $dir | 文件数: $count | 耗时: $duration" 
        # Write-Verbose $msg-Verbose
        Write-Host $msg

        return $result
    } -ThrottleLimit 8

    # 按文件数量排序输出结果
    $sortedResults = $results | Sort-Object -Property Count

    # 总体耗时报告
    $totalDuration = (Get-Date) - $startTime
    Write-Verbose "✅ 完成全部目录统计，总耗时: $($totalDuration.ToString("g"))" -Verbose

    return $sortedResults
}
