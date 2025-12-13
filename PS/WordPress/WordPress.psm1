
function Remove-WpSitesLocal
{
    <# 
    .SYNOPSIS
    批量删除本地Wordpress网站
    建议在建下一批网站之前执行这个清理操作!
    
    .DESCRIPTION
    默认读取my_table.conf文件中配置的网站域名,然后逐个执行以下操作
    - 删除网站根目录
    - 删除数据库
    - 删除nginx配置文件(调用Restart-Nginx也可以触发此动作)
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        $Table = "$desktop/my_table.conf",
        $SitesDir = $my_wp_sites,
        $NginxVhostsDir = "$env:nginx_vhosts_dir",
        [switch]$Force
    )
    $domains = Get-DomainUserDictFromTableLite -Table $Table | Select-Object -ExpandProperty domain
    # Write-Host $domains
    $msg = $domains | Format-DoubleColumn | Out-String
    Write-Verbose $msg -Verbose
    if ($Force -and !$PSBoundParameters.ContainsKey('Confirm') )
    {
        $ConfirmPreference = "None"
    }
    Write-Warning "准备并行删除相关本地站点,配套配置和数据库(如果有已经下载到网站根目录的图片也会一并删除,如果要保留图片请移动图片目录到其他位置!!!)"

    Get-WpSitesLocalImagesCount
    
    Write-Warning "继续删除?" -WarningAction Inquire

    # 多线程删除网站根目录
    foreach ($domain in $domains)
    {
        $siteRoot = "$SitesDir/$domain"
        # 正式删除前,检查一下站点目录下是否存在大量图片或文件(可能是已经下载好图片了),提示用户是否进行备份后再删除(默认停止操作)
        # $imgDir = "$siteRoot/wp-content/uploads"
        # $imgCount = (Get-ChildItem $imgDir -Recurse -File | Measure-Object).Count
        # if ($imgCount -gt 1000)
        # {
        #     write-warning "站点目录下的uploads中存在大量($imgCount)个图片或文件,请确认是否进行备份后再删除" 
        #     if($PSCmdlet.ShouldProcess($imgDir, "删除网站目录及其相关配置"))
        #     {
        #         Write-Host "删除网站目录及其相关配置(start-threadjob)..." 
        #     }
        #     else
        #     {
        #         Write-Host "取消删除网站目录及其相关配置..."
        #         continue
        #     }
        # }else{
        #     Write-Host "网站图片目录不足1000张, 删除网站目录及其相关配置(start-job)..."
        # }

        Remove-Item -Path $siteRoot -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed site root: $Path" 

    }

    # 尝试删除数据库及其相关配置
    Remove-MysqlIsolatedDB -SitesDir $SitesDir
    Approve-NginxValidVhostsConf -NginxVhostConfDir $NginxVhostsDir
    $domains | Remove-LineInFile -Path $hosts -Debug
    
}


function Get-WpSitePacks
{
    <# 
    .SYNOPSIS
    获取WordPress站点的打包文件以及对应的数据库sql文件
    .NOTES
    为了最方便地使用此脚本自动打包和导出WordPress站点，需要满足以下条件：
    1.站点根目录命名为域名,例如domain.com
    2.站点配套的数据库在创建取名的时候就要是和上述domain.com一致,
        以便于用脚本自动导出,速度很快,但要配置mysql.exe所在路径(mysql安装路径下的bin目录)到环境变量PATH中
    满足上述两点的情况下,脚本可以正确解析域名,然后根据域名自动导出对应的sql文件并压缩

    #>
    [cmdletbinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias('Directory')]$SiteDirecotry,
        $Domain = "",
        $DatabaseName = "",
        $DatabaseKey = $env:MySqlKey_LOCAL,
        $OutputDir = "$home/Desktop",
        [ValidateSet('zip', '7z', 'tar', 'lz4', 'zstd')]
        [alias('Mode')]
        $ArchiveMode = 'zstd',
        $CompressionLevel = 3,
        $Threads = 16,
        #是否宽容处理导出的数据库大小(异常检查),默认情况下，数据库导出文件如果低于1MB,则会报错(数据库大概率异常,可能是系统数据库损坏或丢失)
        [Switch]$Permissive

    )

    if ($Domain)
    {
        $SiteParentdir = Split-Path $SiteDirecotry -Parent
        $SiteDirecotryOld = $SiteDirecotry
        $SiteDirecotry = Join-Path $SiteParentdir $Domain
        Write-Host $SiteDirecotryOld -ForegroundColor Cyan
        Write-Host $SiteDirecotry -ForegroundColor Cyan
        Move-Item $SiteDirecotryOld $SiteDirecotry -Force -Verbose
        Write-Debug "[+] SiteDirecotry: $SiteDirecotry"
    }
    # 尝试从站点根目录字符串解析站点域名
    # $Domain = $SiteDirecotry.Split("/")[-1]
    $Domain = Split-Path $SiteDirecotry -Leaf
    Write-Debug "[+] Domain: $Domain"
    # return 
    # 站点sql文件
    
    $SqlFile = "$OutputDir/${Domain}.sql"
    $SqlFileArchiveZip = "$SqlFile.zip"
    $SqlFileArchive7z = "$SqlFile.7z"
    $SqlFileArchiveTar = "$SqlFile.tar"
    $SqlFileArchiveLz4 = "$SqlFile.lz4"
    $SqlFileArchiveZstd = "$SqlFile.zst"
    # 站点根目录
    $SitePackArchiveZip = "$OutputDir/${Domain}.zip"
    $SitePackArchive7z = "$OutputDir/${Domain}.7z"
    $SitePackArchiveTar = "$OutputDir/${Domain}.tar"
    $SitePackArchiveLz4 = "$OutputDir/${Domain}.lz4"
    $SitePackArchiveZstd = "$OutputDir/${Domain}.zst"

    $SitePackArchive = ""
    $SqlFileArchive = ""
    Write-Debug "[+] Trying to export database file to $SqlFile"
    # 导出数据库文件并压缩
    if ($DatabaseName -eq "")
    {
        $DatabaseName = $Domain
        Write-Host "数据库名称未指定，使用默认值: $DatabaseName"
    }
    # 导出数据库sql文件🎈
    Export-MysqlFile -Server localhost -DatabaseName $DatabaseName -key $DatabaseKey -SqlFilePath $SqlFile -Verbose
    if(!$Permissive)
    {
        Write-Host "检查数据库大小是否异常"
        $SqlFileSize = Get-Item $SqlFile | Select-Object -ExpandProperty Length
        if ($SqlFileSize -lt 1MB)
        {
            Write-Host "数据库文件过小，请检查！确定没错,可以使用--permissive参数跳过此检查"
            return $False
        }
        
    }
    # Compress-Archive -Path $SqlFile -DestinationPath $SqlFileArchiveZip -Force
    # 打包站点目录


    if($ArchiveMode -eq '7z')
    {
        if(Test-CommandAvailability 7z)
        {
            $cmd1 = "7z a -t7z -mmt${Threads} $SqlFileArchive7z $SqlFile"
            $cmd2 = "7z a -t7z -mmt${Threads} $SitePackArchive7z $SiteDirecotry"
            $cmd1 | Invoke-Expression
            $cmd2 | Invoke-Expression
            
            $SitePackArchive = $SitePackArchive7z
            $SqlFileArchive = $SqlFileArchive7z
        }
    }
    elseif ($ArchiveMode -eq 'zip')
    {
        Write-Host "使用默认的zip打包方式"
        Compress-Archive -Path $SqlFile -DestinationPath $SqlFileArchiveZip -Force
        Compress-Archive -Path $SiteDirecotry -DestinationPath $SitePackArchiveZip -Force
        $SitePackArchive = $SitePackArchiveZip
        $SqlFileArchive = $SqlFileArchiveZip
    }
    elseif($ArchiveMode -eq 'tar')
    {
        if(Test-CommandAvailability 7z)
        {

            Write-Host "使用tar打包方式"
            7z a -ttar $SqlFileArchiveTar $SqlFile 
            7z a -ttar $SitePackArchiveTar $SiteDirecotry
            $SitePackArchive = $SitePackArchiveTar
            $SqlFileArchive = $SqlFileArchiveTar
        }
    }
    elseif($ArchiveMode -eq 'lz4')
    {
        Write-Host "使用lz4打包方式"
        Compress-Lz4Package -Path $SqlFile -OutputFile $SqlFileArchiveLz4 -Threads $Threads -NoTarExtension
        Compress-Lz4Package -Path $SiteDirecotry -OutputFile $SitePackArchiveLz4 -Threads $Threads -NoTarExtension
        $SitePackArchive = $SitePackArchiveLz4
        $SqlFileArchive = $SqlFileArchiveLz4
        Write-Debug $SitePackArchive -Debug
    }
    elseif($ArchiveMode -eq "zstd")
    {
        Write-Host "使用zstd打包方式"
        Compress-ZstdPackage -Path $SqlFile -OutputFile $SqlFileArchiveZstd -Threads $Threads -CompressionLevel $CompressionLevel -NoTarExtension
        Compress-ZstdPackage -Path $SiteDirecotry -OutputFile $SitePackArchiveZstd -Threads $Threads -CompressionLevel $CompressionLevel -NoTarExtension
        $SitePackArchive = $SitePackArchiveZstd
        $SqlFileArchive = $SqlFileArchiveZstd
        Write-Debug $SitePackArchive -Debug
    }
    else
    {
        Write-Error "不支持的打包方式: $ArchiveMode"
        return
    }
    # $SitePackArchive = Compress-Tar -Directory $SiteDirecotry 

    # 列出已经打包的文件
    Get-Item $SqlFileArchive  
    Get-Item $SitePackArchive
    # 移除数据库sql文件
    Remove-Item $SqlFile -Verbose
}
function Get-MoreSites
{
    <# 
    .SYNOPSIS
    根据指定url(域名列表)生成友站外链的html代码片段和sitemap.xml 片段,并输出对应的文件

    #>
    [CmdletBinding()]
    param (
        [string]$InputFile = "urls.txt",
        [string]$HtmlOutputFile = "$desktop/more.html",
        # 考虑到分割,所以这里仅指定SitemapBaseName,index++作为后缀
        [string]$SitemapBaseName = "$desktop/sitemap_more",
        [int]$MaxUrlsPerSitemap = 50000
        # [string]$SitemapIndexFile = "sitemap_index.xml",
        # [string]$BaseUrlForSitemaps = "https://yourdomain.com" 
    )

    if (-not (Test-Path $InputFile))
    {
        Write-Error "❌ 输入文件 '$InputFile' 不存在。"
        return
    }

    # 初始化内容
    $htmlContent = @()
    $sitemaps = @()
    $urlCount = 0
    $fileIndex = 1
    $currentXml = @()
    $domainSitemaps = @{}
    $simpleLinks = @()

    # XML 初始化
    $currentXml += '<?xml version="1.0" encoding="UTF-8"?>'
    $currentXml += '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'

    # 处理每个 URL
    Get-Content $InputFile | ForEach-Object {
        $url = $_.Trim()
        if ($url -match '^https?://([^/]+)')
        {
            $domain = $matches[1]
            $baseDomain = ($domain -split '\.')[-2..-1] -join '.'  # 提取主域

            # 构建 sitemap 链接
            $sitemapLink = "https://www.$baseDomain/sitemap_index.xml" 

            # 记录每个域名的sitemap
            if (-not $domainSitemaps.ContainsKey($baseDomain))
            {
                $domainSitemaps[$baseDomain] = $sitemapLink
            }

            # 简单链接列表
            $simpleLinks += "    <li><a href=`"$url`" target=`"_blank`" rel=`"noopener`">$url</a></li>"

            # XML 输出
            $currentXml += "    <url>"
            $currentXml += "        <loc>$sitemapLink</loc>"
            $currentXml += "        <changefreq>daily</changefreq>"
            $currentXml += "        <priority>1.0</priority>"
            $currentXml += "        <lastmod>$(Get-Date -Format yyyy-MM-dd)</lastmod>"
            $currentXml += "    </url>"

            $urlCount++
            if ($urlCount -ge $MaxUrlsPerSitemap)
            {
                $currentXml += '</urlset>'
                $xmlFileName = "$SitemapBaseName`_$fileIndex.xml"
                $currentXml | Out-File -FilePath $xmlFileName -Encoding utf8
                Write-Host "✅ 已生成 sitemap: $xmlFileName"
                $sitemaps += $xmlFileName

                # 重置
                $urlCount = 0
                $fileIndex++
                $currentXml = @()
                $currentXml += '<?xml version="1.0" encoding="UTF-8"?>'
                $currentXml += '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
            }
        }
    }

    # 写入最后一个未满的 sitemap 文件
    if ($urlCount -gt 0)
    {
        $currentXml += '</urlset>'
        $xmlFileName = "$SitemapBaseName`_$fileIndex.xml"
        $currentXml | Out-File -FilePath $xmlFileName -Encoding utf8
        Write-Host "✅ 已生成 sitemap: $xmlFileName"
        $sitemaps += $xmlFileName
    }

    # 生成HTML内容 - 简单链接列表
    # $htmlContent += '<h2>网站列表</h2>'
    $htmlContent += '<ul>'
    $htmlContent += $simpleLinks
    $htmlContent += '</ul>'
    $htmlContent += "`n`n"
    # 生成HTML内容 - JSON-LD结构化数据
    # $htmlContent += '<h2>sitemap JSON-LD</h2>'
    $htmlContent += '<script type="application/ld+json">'
    $htmlContent += @"
{
  "@context": "https://schema.org",
  "@type": "WebSite",
  "url": "/",
  "potentialAction": {
    "@type": "SiteMap",
    "target": [
"@

    $first = $true
    foreach ($sitemap in $domainSitemaps.Values)
    {
        if (-not $first)
        {
            $htmlContent += ","
        }
        $htmlContent += "      `"$sitemap`""
        $first = $false
    }

    $htmlContent += @"
    ]
  }
}
"@
    $htmlContent += '</script>'

    # 生成HTML内容 - 站点地图链接部分
    $htmlContent += '<h2>XML maps</h2>'
    $htmlContent += '<div class="footer-sitemaps">'
    # $htmlContent += '  <h3>maps</h3>'
    $htmlContent += '  <ul>'
    
    foreach ($domain in $domainSitemaps.Keys)
    {
        $sitemapUrl = $domainSitemaps[$domain]
        $displayName = ($domain -split '\.')[0] -replace '-|_', ' '  # 美化显示名称
        $displayName = (Get-Culture).TextInfo.ToTitleCase($displayName.ToLower())
        $htmlContent += "    <li><a href=`"$sitemapUrl`">$displayName XML maps</a></li>"
    }
    
    $htmlContent += '  </ul>'
    $htmlContent += '</div>'

    # 写入 HTML 文件
    $htmlContent | Out-File -FilePath $HtmlOutputFile -Encoding utf8
    Write-Host "✅ 已生成 HTML 链接文件: $HtmlOutputFile"
}
function Confirm-WpEnvironment
{
    <# 
    .SYNOPSIS
    检查部署本地wordpress所需要的环境
    .DESCRIPTION
    检查必要的环境变量是否配置,以及取值是否有效
    检查指定程序是否可以成功调用
    #>
    [cmdletbinding()]
    param (
        
    )
    Write-Verbose "检查wordpress本地建站部署所需的环境"
    #检查密钥类的环境变量是否配置
    if($env:MySqlKey_LOCAL)
    {
        Write-Host "MySqlKey_LOCAL: $env:MySqlKey_LOCAL"
    }
    else
    {
        Write-Host "请配置环境变量: MySqlKey_LOCAL" -ForegroundColor Red
    }
    $Dirs = @{
        pys                 = $env:PYS
        woo_df              = $env:WOO_DF
        locoy_spider_data   = $env:LOCOY_SPIDER_DATA
        phpstudy_extensions = $env:phpstudy_extensions
        nginx_conf_dir      = $env:nginx_conf_dir
    }
    
    # 检查上述变量(目录)是否存在,不存在则报错并退出
    foreach ($var in $Dirs.Keys)
    {
        Write-Debug "正在检测环境变量: $var"
        if (-not $Dirs[$var])
        {
            Write-Error "❌ 缺少必要环境变量:[ $var]"
            return $false
        }
        else 
        {
            if (-not (Test-Path $Dirs[$var]))
            {
                
                Write-Error "❌ 环境变量[ $var ]指定的目录不存在"
                return $false
            }
            else
            {
                Write-Verbose "环境变量[ $var ]指定的目录存在: $Dirs[$var]" -Verbose
            }
        }
    }
    # 检查多值环境变量
    $multiValueVars = @{
        # psmodulepath = $env:PsModulePath #能够运行此函数,此变量一定是配好了的,用不着此函数检查此环境变量
        pythonpath = $env:PYTHONPATH
    }
    Write-Debug "正在检测环境变量: $var`n============="
    foreach ($var in $multiValueVars.Keys)
    {
        Write-Debug "正在检测环境变量: $var`n***********"
        if (-not $multiValueVars[$var])
        {
            Write-Error "❌ 缺少必要环境变量:[ $var]"
            return $false
        }

    }
    
    # 检查基本命令行软件(mysql,nginx,php)是否存在且可以直接调用
    $cmds = @(
        'mysql',
        'nginx'
        # 'php'
    )
    $cmds | ForEach-Object {
        if(!(Test-CommandAvailability $_))
        {
            Write-Error "❌ 缺少[$_]命令行软件"
            return $false
        }
        else
        {
            Write-Host "✅ 检测到 $_ 命令行软件:$(Get-Command $_)"
        }

    }
    # 检查mysql及其密码是否搭配
    $res = mysql -uroot -p"$env:MySqlKey_LOCAL" -P 3306 -e "use mysql;show tables;"
    $res = ($res -join "`n")
    Write-Debug $res.ToString()
    if($LASTEXITCODE)
    {
        Write-Error "❌ MySql数据库密码错误"
        return $false
    }
    else
    {
        Write-Host "✅ MySql数据库密码正确"
    }

}
function Get-XpCgiPort
{
    <# 
    .SYNOPSIS
    查询xp.cn_cgi监听的端口信息
    如果指定端口,则优先使用指定的端口查询相关进程(通常为9000以上的端口)

    .DESCRIPTION
    获取xp.cn_cgi进程端口,并返回包含端口属性的对象

    #>
    [cmdletbinding()]
    param (
        [alias('xpCgiProcess')]
        [parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        $Process,
        # 指定端口的优先级更高,如果希望以进程监听端口优先,则显示指定此参数为$null
        $ByPort = '900*'
    )
    # $p = Get-NetTCPConnection | Where-Object { $_ -like '*900*' };
    if($ByPort)
    {
        Write-Warning "ByPort is fast,but may not accurate!"
        $ports_info = Get-NetTCPConnection | Where-Object { $_.LocalPort -like $ByPort } # | Select-Object -First 1
        Write-Host "$($ports_info|Out-String)"
        Write-Host "反向校验相关进程尝试找出是否名为xp.cn_cgi"
        # $ports_info | ForEach-Object {
        foreach ($port_info in $ports_info)
        {
            $p = (Get-Process -Id $port_info.OwningProcess)
            if( $p.ProcessName -eq 'xp.cn_cgi' )
            {
                Write-Verbose "找到满足条件的进程:name=$($p.ProcessName),id=$($p.Id),port=$($port_info.LocalPort)"
                return $port_info
            }
            else
            {
                Write-Verbose "进程:name=$($p.ProcessName),id=$($p.Id),port=$($port_info.LocalPort) 不满足条件"
            }
        }

    }
    else
    {

        if($Process)
        {
            Write-Verbose "通过管道传入xp.cn_cgi进程对象" -Verbose
            $xpCgiProcess = $Process
        }
        else
        {
            Write-Verbose "检查xp.cn_cgi进程是否已经存在..."
            $xpCgiProcess = Get-Process *xp.cn_cgi* -ErrorAction SilentlyContinue
        }
        # $xpCgiProcess = Get-Process *xp.cn_cgi* -ErrorAction SilentlyContinue
        if($xpCgiProcess)
        {
            Write-Verbose "xp.cn_cgi进程已经存在!" -Verbose
            Write-Verbose "$($xpCgiProcess | Out-String)" -Verbose
            # 考虑到有的情况下会运行多个xp.cn_cgi进程,这里需要遍历进程
            $xpCgiProcess = @($xpCgiProcess)
            if($xpCgiProcess.Count -gt 1)
            {
                Write-Warning "检测到多个xp.cn_cgi进程,将找出第一个可用进程信息..." 
            }
            $i = 0
            $info = $null
            foreach ($Process in $xpCgiProcess)
            {
                Write-Verbose "进程[$i]信息: ID=$($Process.Id), Name=$($Process.ProcessName)" -Verbose
                $item = Get-NetTCPConnection | Where-Object { $_.OwningProcess -eq $Process.Id } | Select-Object LocalAddress, LocalPort, State, OwningProcess
                
                # if($i -eq 0) #部分进程无法查询到监听端口,第一个进程不够可靠,可能是空的
                if($item)
                {
                    $info = $item
                    Write-Host "查询到第一个监听端口的xp_cn.cgi进程信息:"
                    Write-Host $info
                    # 查询到第一个后跳出循环(节约时间)
                    break
                }
                
                $i += 1
            }
            # $info = Get-NetTCPConnection | Where-Object { $_.OwningProcess -eq $xpCgiProcess.Id } | Select-Object LocalAddress, LocalPort, State, OwningProcess #| Out-String
            # Write-Host "现有进程信息:`n $info"
        }
        else
        {
            Write-Error "xp.cn_cgi进程尚不存在"
        }
        if($info)
        {
            
            return $info
        }
        else
        {
            return $False
        }
    }

}

function Stop-phpCgi
{
    <# 
    .SYNOPSIS
    主要针对小皮工具箱中xp.cn_cgi进程重启切换端口监听端口时使用
    停止php_cgi进程,释放php_cgi占用的端口(通常为9000+端口)
    .DESCRIPTION
    如果仅仅强制重启xp.cn_cgi进程(切换监听端口),可能会因为先前的php_cgi进程监听别的端口而导致一些更改不会生效
    这里实现php_cgi进程清理,清理相关端口占用和干扰

    .NOTES
    # 查看php-cgi进程(注意和xp.cn_cgi进程不同)
     ps php-cgi

    NPM(K)    PM(M)      WS(M)     CPU(s)      Id  SI ProcessName
    ------    -----      -----     ------      --  -- -----------
        19    37.87     122.96       4.78   30636   1 php-cgi
        14     6.66      19.93       0.02   39592   1 php-cgi
    #>
    [cmdletbinding()]
    param()
    $phpCgiProcess = Get-Process php-cgi -ErrorAction SilentlyContinue
    if($phpCgiProcess)
    {
        Write-Verbose "正在停止php_cgi进程..."
        $res = $phpCgiProcess | Stop-Process -Force -Verbose -PassThru
        Write-Verbose "php_cgi进程已全部停止"
        return $res
    }
    else
    {
        Write-Verbose "php_cgi进程不存在"
    }
    Write-Warning "php-cgi进程清理后,相关服务会在需要的时候尝试重新请求创建php-cgi进程(比如刷新网页后触发),这个过程可能需要一些时间(通常很快),请重试并等待..."
    Write-Host "900*系列端口占用信息:"
    $status = netstat -ano | findstr :900*
    Write-Host $status
}
function Start-XpCgi
{
    <# 
    .SYNOPSIS
    启动xp.cn_cgi进程

    .DESCRIPTION
    启动xp.cn_cgi进程,并检查进程是否启动成功
    此过程会打印进程监听的端口信息和进程信息(如果启动成功,则返回进程对象)

    .PARAMETER XpCgiPath
    xp.cn_cgi进程路径,默认值为"$env:PHPSTUDY_HOME/COM/xp.cn_cgi.exe"

    .PARAMETER PhpPath
    php-cgi.exe路径,默认值为"$env:php_home\php-cgi.exe"
    .PARAMETER CgiPort
    xp.cn_cgi进程端口,默认值为9002,虽然可以指定端口并更改监听端口为指定端口
    但是这不总是推荐值,建议参考小皮配置文件xp.ini中的配置

    .PARAMETER CgiArgs
    xp.cn_cgi进程参数,默认值为"1+16"
    .NOTES
    系统可能有多个xp.cn_cgi进程,get-process 可能会查到多个进程(数组),使用返回结果时需要注意数据类型
    .EXAMPLE
    Start-XpCgi

    .EXAMPLE
    Start-XpCgi -XpCgiPath "D:\PHPSTUDY_HOME\COM\xp.cn_cgi.exe" 

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        $XpCgiPath = "$env:PHPSTUDY_HOME/COM/xp.cn_cgi.exe",
        $phpCgiPath = "$env:php_home\php-cgi.exe",
        $CgiPort = 9002,
        $CgiArgs = "1+16",
        # 如果已经存在xp.cn_cgi进程,是否关闭后重新启动(发生更改的情况下通常要一并重启nginx使得更改生效)
        [switch]$Force
    )
    Write-Host "检查xp.cn_cgi进程是否已经存在..."
    $xpCgiProcess = Get-Process *xp.cn_cgi* -ErrorAction SilentlyContinue
    if($xpCgiProcess)
    {
        Write-Host "xp.cn_cgi进程已经存在"
        # $info = Get-NetTCPConnection | Where-Object { $_.OwningProcess -eq $xpCgiProcess.Id } | Select-Object LocalAddress, LocalPort, State, OwningProcess | Out-String
        $info = Get-XpCgiPort -ByPort 900*
        Write-Host "现有进程信息:`n $info"
        if($Force)
        {
            Write-Host "准备关闭已有的xp.cn_cgi进程..."
            $xpCgiProcess | Stop-Process -Force -Verbose
            Write-Host "准备重新启动xp.cn_cgi进程..."
            Write-Warning "注意: 重新启动xp.cn_cgi进程后,请根据情况(是否修改了nginx配置)考虑是否重启nginx,以便让vhost连接到新的CGI进程端口上!"
        }
        else
        {
            # 直接返回现有进程信息(可能是进程对象或进程数组)
            return $xpCgiProcess
        }
    }
    else
    {
        Write-Host "xp.cn_cgi进程尚不存在,准备启动..."
    }
    # 创建并启动xp.cn_cgi进程
    $cmd = "$XpCgiPath  $phpCgiPath $CgiPort $CgiArgs"
    Write-Host "启动xp.cn_cgi进程: $cmd"
    # $cmd | Invoke-Expression
    # 使用start-process启动进程(隐藏窗口)
    Start-Process -FilePath $XpCgiPath -ArgumentList "$phpCgiPath $CgiPort $CgiArgs" -NoNewWindow -Verbose
    Write-Host "CGI进程检查..."
    $info = Get-XpCgiPort -ByPort '900*'
    Write-Host "现有进程端口监听信息:`n $info"

    Write-Warning "清理php-cgi进程占用的端口..."
    Stop-phpCgi -Verbose

    return Get-Process *xp.cn_cgi*
}
function Deploy-WpSitesLocal
{
    <# 
    .SYNOPSIS
    批量部署本地Wordpress网站
    从已有的模板中拷贝网站根目录和数据到新的域名,包括数据库的导入和修改,并且配置对应站的nginx.htaccess文件和conf文件

    .PARAMETER Table
    包含表格信息的配置文本文件,默认格式为每行包含[域名,用户名,模板名],以空格分隔

    .PARAMETER WpSitesTemplatesDir
    本地Wordpress网站[模板]目录,脚本将会从这个目录下面拷贝模板站目录到指定位置(MyWpSitesHomeDir),默认值为"$env:USERPROFILE/Desktop/wp_sites_templates"

    .PARAMETER MyWpSitesHomeDir
    本地各个Wordpress网站根目录聚集的目录,用来保存从WpSitesTemplatesDir拷贝的网站目录,这里保存的各个网站根目录,是之后装修的对象,默认值为"$env:USERPROFILE/Desktop/my_wp_sites"

    .PARAMETER DBKey
    mysql密码

    .PARAMETER NginxVhostsDir
    nginx配置文件目录

    .PARAMETER NginxVhostConfigTemplate
    nginx配置文件模板

    .PARAMETER SiteImageDirRelative
    网站图片目录相对路径

    .PARAMETER CsvDir
    csv数据输出目录,如果不存在,将会创建该目录

    .PARAMETER Confirm
    确认提示,默认值为$false

    #>
    [cmdletbinding(SupportsShouldProcess)]
    param (
        # 主要参数
        $Table = "$desktop/my_table.conf",
        $WpSitesTemplatesDir = $wp_sites,
        $MyWpSitesHomeDir = "$Desktop/my_wp_sites",
        # 数据库文件(sql文件所在目录)
        $SqlFileDir = "$WpSitesTemplatesDir/base_sqls",
        # 可以配置环境变量来设置
        $CgiPort = "$env:CgiPort", 
        # 一般不需要更改的参数
        $TableStructure = "Domain,User,Template",
        $DBKey = $env:MySqlKey_LOCAL,
        $NginxVhostsDir = "$env:nginx_vhosts_dir", # 例如:C:\phpstudy_pro\Extensions\Nginx1.25.2\conf\vhosts
        $NginxConfDir = "$env:nginx_conf_dir",
        $NginxVhostConfigTemplate = "$scripts/Config/nginx_vhost_template.conf",
        $NginxConfigTemplate = "$scripts/Config/nginx_template.conf",
        $NginxHtaccessTemplate = "$scripts/Config/nginx.htaccess",
        # nginx.exe所在目录的完整路径(如果Path中的%nginx_home%没有被正确解析,可以指定完整路径)
        # $NginxHome="",
        $SiteImageDirRelative = "wp-content/uploads/2025",
        $CsvDir = "$Desktop/data_output",
        # 部分行为强制(比如xp.cn_cgi已经存在时,是否强制重启,可以重置监听端口)
        [switch]$Force
    )
    Write-Debug $table
    Write-Debug $WpSitesTemplatesDir
    Write-Debug $MyWpSitesHomeDir
    Write-Debug $DBKey
    # 配置文件规范化
    $content = Get-Content $table -Raw
    # 列数检查(空白字符作为列分隔符)
    foreach ($line in $content.Split("`n"))
    {
        if($line -match '^\s*#')
        {
            continue
        }
        $parts = $line.Trim() -split '\s+'
        Write-Debug "parts: $parts" -Debug
        $n = $parts.Length
        if($n -gt 1 -and $n -lt 3)
        {
            Write-Error "Invalid table structure: '[$line]'. Please check the table file.(columns: $n < 3)"
            return $parts
        }
    }
    $content = $content -replace 'https://', 'http://' -replace 'www.', '' -replace 'http://(.*)com', { $_.Value.ToLower() } 
    
    $content | Set-Content $Table -Verbose -Force
    # debug
    # return $content
    # 检查关键目录
    if(!(Test-Path $WpSitesTemplatesDir))
    {
        Write-Error "Wordpress templates directory not found: $WpSitesTemplatesDir"
        return
    }

    if(!(Test-Path $NginxVhostsDir))
    {
        Write-Error "Nginx conf directory not found: $NginxVhostsDir"
        return 
    }
    New-Item -ItemType Directory -Path $MyWpSitesHomeDir -ErrorAction SilentlyContinue -Verbose
    # 覆盖小皮nginx配置文件(nginx.conf)
    if((Test-Path $NginxConfigTemplate) -and $NginxConfDir)
    {
        Copy-Item -Path $NginxConfigTemplate -Destination $NginxConfDir\nginx.conf -Verbose -Force
    }
    else
    {
        Write-Error "Nginx Path Environment Variable not found or invalid: [$NginxConfigTemplate] or [$NginxConfDir]"
        return $False
    }
    # 部署前检查或启动必要的服务(nginx,mysql,xp.cn_cgi)
    Start-XpNginx
    Start-Service MySQL* -Verbose -ErrorAction SilentlyContinue
    
    if($CgiPort)
    {
        # 确保xp.cn_cgi进程启动(如果已经存在nginx进程,则返回进程对象)
        $cgi = Start-XpCgi -CgiPort $CgiPort -Force:$Force 
        if(!$cgi)
        {
            Write-Error "xp.cn_cgi进程启动失败,请检查相关配置和日志"
            return $False
        }
        $cgiExist = Get-XpCgiPort -ByPort 900*
        $portExsit = $cgiExist.LocalPort
        if($portExsit -and ($portExsit -ne $CgiPort))
        {
            Write-Warning "指定的CgiPort端口[$CgiPort]和现有进程监听的端口[$portExsit]不一致,以指定值[$CgiPort]进行部署配置文件"
            Write-Host "如果和指定端口不一致,可以考虑追加-Force参数重新启动CGI服务,让其监听指定端口(如果端口未被占用的话)" 
        }
    }
    # 如果未指定CgiPort,则尝试自动获取CGI服务监听的端口(如果相关进程没有启动,则先启动进程)
    if(!$CgiPort)
    {
        Write-Warning "未指定CgiPort,也没有配置CgiPort环境变量,建议检查xp.ini中的端口指示(注意php版本对应,通常为9000系列端口),并配置环境变量"
        Get-Content $phpstudy_ini
        Write-Warning "现在尝试扫描现有xp_cgi进程监听的端口号..."
        $CgiPort = $Cgi | Get-XpCgiPort -ByPort 900* | Select-Object -ExpandProperty LocalPort
        Write-Host "CGI服务已启动,注意当前进程监听的端口: $CgiPort " -ForegroundColor Cyan
    }
 
    # 检查nginx/mysql服务是否正常运行
    $nginx_status = Get-Process nginx
    $mysqld_status = Get-Process mysqld
    if(!$nginx_status)
    {
        Write-Error "Nginx服务未正常启动" 
        return
    }
    if(!$mysqld_status)
    {
        Write-Error "Mysql服务未正常启动" 
        return
    }

    # $rows = Get-DomainUserDictFromTable -Table $table -Structure $TableStructure

    # 始终不提示确认，即使用户没指定 -Confirm:$false
    if (-not $PSBoundParameters.ContainsKey('Confirm'))
    {
        $ConfirmPreference = 'None'
    }

    # 解析批量表格中的各条待处理任务🎈
    # $rows = Get-Content $table | Where-Object { $_ -notmatch "^\s*#" } | ForEach-Object { $l = $_ -split '\s+'; @{'domain' = ($l[0] | Get-MainDomain); 'user' = $l[1]; 'template' = $l[2] } }
    $rows = Get-DomainUserDictFromTableLite -Table $table
    # 利用write-output将结果输出到控制台,方便查看
    Write-Output $rows | Format-Table
    Write-Warning "Please check the parameter table list above,especially the domain and template name!" -WarningAction Inquire
    # Pause
    $order = 1
    # 逐条数据解析出各个参数,并处理任务🎈
    foreach ($row in $rows)
    {
        $domain = $row.Domain
        $template = $row.Template
        $title = $row.Title
        $removeMall = $row.RemoveMall
        Write-Debug "Processing domain: [$domain], template: [$template],with title: [$title],mall remove: [$removeMall]"

        $path = "$WpSitesTemplatesDir/$template"
        $destination = "$MyWpSitesHomeDir/$domain"
        # 这里要加一层域名验证
        if ($domain -and $domain -like "*.*" -and $domain.trim() -notlike "www\.*")
        {
            Write-Verbose "processing domain: [$domain]" -Verbose
        }
        else
        {
            Write-Error "Invalid domain name: [$domain]. Please check the table file: $table" -WarningAction Stop
            Pause
            # exit #会导致shell窗口直接关闭,不推荐使用exit
            return $False
        }
        # 检查目标路径是否已经存在已经覆盖处理
        if(Test-Path $destination)
        {
            Write-Verbose "Removing $destination(Enter 'A' to Continue)" -Verbose 
            Remove-Item $destination -Force -Recurse -Confirm:$Confirm
        }
        # Pause
        # Copy-Item -Path $path/* -Destination $destination  -Force 
        # Copy-Item -Path $path -Destination $MyWpSitesHomeDir -Force -Recurse -WhatIf:$WhatIfPreference 
        # 使用robocopy多线程拷贝
        $robocopyLog = "$env:TEMP/$(Get-Date -Format 'yyyyMMdd')robocopy.log"
        # Write-Verbose "Use robocopy to copy files from $path to $destination "
        Copy-Robocopy -Source $path -Destination $destination -Force -Recurse -LogFile $robocopyLog -Threads 32
        # 根据需要移除mallpay🎈
        if($removeMall)
        {
            Remove-Item "$destination/wp-content/plugins/mallpay" -Force -Recurse -Verbose #-WhatIf:$WhatIfPreference
        }
        $template_temp = "$MyWpSitesHomeDir/$template"
        if(Test-Path $template_temp)
        {

            Move-Item -Path $template_temp -Destination $destination -Force -Verbose -WhatIf:$WhatIfPreference
        }
        # 修改wp-config.php配置文件以及robots文件🎈
        $wp_config = "$destination/wp-config.php"
        Write-Debug $wp_config
        if (Test-Path $wp_config)
        {
            # 更新wp-config.php文件
            $s = Get-Content $wp_config -Raw
            Write-Debug "modify the wp-config.php file : the db name"
            $ns = $s -replace "(define\(\s*'DB_NAME')(.*)\)", "`$1,'$domain')" -replace "(define\(\s*'DB_PASSWORD')(.*)\)", "`$1,'$DBKey')"
            # Write-output $ns
            $ns > $wp_config

            # 更新robots.txt文件
            $robots = "$destination/robots.txt"
            Write-Verbose "Update the robots.txt file [$robots]"
            Update-WpSitesRobots -Path $robots -Domain $domain
            # 显式复制wordpress的nginx.htaccess文件(包含伪静态配置),
            # 理论上会自动把模板站中的对应文件一同复制,但是个别情况复制的文件内容为空,
            # 且考虑到统一覆盖的便利性,这里将nginx.htaccess文件(内容)放到一个固定的位置,然后统一读取和复制此文件到目标位置
            Copy-Item -Path $NginxHtaccessTemplate -Destination $destination/nginx.htaccess -Force -Verbose 
            # 配置本地网站对应的nginx.conf文件(比如使用小皮的nginx环境)
            $tpl = "$NginxVhostConfigTemplate"
            Write-Debug $tpl
            if (!(Test-Path $tpl))
            {
                Write-Error "nginx tpl.conf file not found in path: $NginxVhostConfigTemplate"
                # return 
            }
            else
            {
                # 配置本地站点根目录对应的nginx配置文件
                $tpl_content = Get-Content $tpl -Raw
                $tpl_content = $tpl_content -replace "domain.com", $domain #"`"$domain`"" 
                $tpl_content = $tpl_content -replace "CgiPort", $CgiPort
                $nginx_target = "$NginxVhostsDir/${domain}_80.conf"
                $tpl_content > $nginx_target #对于https协议,则为 _443.conf
                Write-Debug "nginx 配置内容将被写入到文件:[ $nginx_target]" -Debug
                Write-Debug $tpl_content 
            }
         
            Write-Warning "please restart nginx service to apply the new nginx.conf file!🎈"
            # 导出后续步骤要用到的命令行,创建对应的目录(如果没有的话)
            $CsvDirHome = "$CsvDir/$domain"
            $ImgDir = "$destination/$SiteImageDirRelative"
            New-Item -ItemType Directory -Path $CsvDirHome -ErrorAction SilentlyContinue -Verbose
            
            $script = @"
# =========[($order)    http://$domain/login  ]:[ cd  $destination  ]=>[图片目录: explorer $destination\wp-content\uploads\2025 ]==========


# 下载图片
python $pys\image_downloader.py -c -n -R auto -k  -rs 1000 800  --output-dir $ImgDir --dir-input $CsvDirHome -F -ps pwsh -w 5 -U curl 

# 导入产品数据到数据库
python $pys\woo_uploader_db.py --update-slugs  --csv-path $CsvDirHome --img-dir $ImgDir --db-name $domain --max-workers 20

# 打包网站
Get-WpSitePacks -SiteDirecotry $destination -Mode zstd


"@| Get-PathStyle -Style posix -KeepColon2Slash

            
            # 更新计数器$order
            $order++
            Write-Host $scripts
            $scripts_dir = "$MyWpSitesHomeDir"
            $script_path = "$scripts_dir/scripts_$(Get-Date -Format "yyyyMMdd").ps1"
            "" >> $script_path
            # 检查是否重复写入
            if (Get-Content $script_path | Select-String -Pattern $domain)
            {
                Write-Warning "This site [$domain] already exist in the script file,ignore it!"
            }
            else
            {

                $script >> $script_path
            }
            Write-Host "Script has been saved to: $script_path" -ForegroundColor Cyan
        }
        else
        {
            Write-Error "wp-config.php file not found in $destination"
            Pause
        }
        # 导入数据库并执行基础的修改
        $sqlFile = "$SqlFileDir/$template.sql"
        
        Import-MysqlFile -Server localhost -key $DBKey -SqlFilePath $sqlFile -DatabaseName $domain -Verbose:$verbosePreference
        Update-WpUrl -Server localhost -key $DBKey -NewDomain $domain -OldDomain $template -protocol http -Verbose:$VerbosePreference
        Update-WpTitle -Server localhost -key $DBKey -NewTitle $title -DatabaseName $domain -Verbose:$VerbosePreference
        
        # 修改(追加当前域名映射新行)到hosts文件(127.0.0.1  $domain)
        Add-NewDomainToHosts -Domain $domain


    }

    # 可以考虑定期清理hosts文件!
    Write-Debug "Modify hosts file [$hosts]"
    # 重启(重载)nginx服务器(如果重载不能生效,请使用-Force参数强制重启)
    
    Restart-Nginx -Force:$Force
    # 打开输出的脚本
    Start-Process $script_path
}
function Deploy-WpSitesOnline
{
    <# 
    .SYNOPSIS
    部署空网站到宝塔面板服务器线上环境
    .DESCRIPTION
    核心步骤是调用python脚本来执行部署
    .NOTES
    注意,使用前请配置各个服务器的ssh免密登录 
    
    #>
    [CmdletBinding()]
    param(
        # 解析当前批次域名要部署到的服务器(使用定义在配置文件中的服务器名称来指定,比如server1,server2,...)
        [alias('Host', 'Server', 'Ip')]
        $HostName ,
        # 当前批次域名要绑定到哪个cloudflare账号(账号名字定义在)
        [alias('Account')]
        $CfAccount = "account1",

        # 要部署的网站在宝塔中的总目录(宝塔总目录,默认为/www/wwwroot)
        [alias('wwwroot')]
        $SitesHome = "/www/wwwroot",

        # 本批次要部署的网站域名表
        [alias('Table')]$FromTable = "$Desktop/table.conf",

        # 域名绑定cf后解析cf返回的查询结果来传递给spaceship更新域名的nameservers的中间表格
        [alias('DomainTable')]$ToTable = "$Desktop/domains_nameservers.csv",

        # 记录spaceship账号信息的配置文件路径
        $SpaceshipConfig = "$spaceship_config",
        # 记录cf账号和密钥信息的配置文件路径
        $CfConfig = "$cf_config",
        # 记录服务器账号信息的配置文件路径
        $ServerConfig = "$server_config",

        # 基础等待时间(秒),默认0秒
        $WaitTimeBasic = 0,
        # 最大重试次数,默认20
        $MaxRetryTimes = 20,
        # 重试间隔时间(秒),默认30秒
        $RetryGap = 30,
        [switch]$Onebyone

    
    )
    # 读取cf配置文件,确定要使用的cf账号(根据cf账号和密钥设置当前cf相关环境变量)
    # $config = Get-Content $CfConfig | ConvertFrom-Json
    # $account = $config."accounts"."$CfAccount"
    # Set-CFCredentials -ApiKey $account.cf_api_key -ApiEmail $account.cf_api_email
    Set-CFCredentials -CfConfig $CfConfig -Account $CfAccount
    Get-ChildItem env:cf*
    # 解析服务器配置
    $serversConfig = Get-Content $ServerConfig | ConvertFrom-Json
    $servers = $serversConfig.servers
    $hst = $servers."$HostName".ip
    Write-Verbose "Deploy to server: $HostName,IP:$hst"


    # 添加域名解析到cf(第一步执行)
    Add-CFZoneDNSRecords -AddRecordAtOnce -IP $hst -Parallel:(!$Onebyone) -Domains $FromTable
    # 从待部署域名列表更新spaceship域名的nameservers(cf添加后立即执行spaceship的nameservers更新)
    Get-CFZoneNameServersTable -FromTable $FromTable
    # 更新spaceship的nameservers
    Update-SSNameServers -Config $SpaceshipConfig -Table $ToTable
    # 让cf立即检查域名的激活
    Add-CFZoneCheckActivation -Account $CfAccount -ConfigPath $CfConfig -Table $FromTable
    
    # 配置cf域名解析,邮箱转发和代理保护(位置1)
    Add-CFZoneConfig -CfConfig $CfConfig -Account $CfAccount -Table $FromTable -Ip $hst
    # 创建宝塔空站点
    Deploy-BatchSiteBTOnline -Server $HostName -ServerConfig $ServerConfig -Table $FromTable -SitesHome $SitesHome 
    # 上传本批次域名列表到对应服务器上
    Push-ByScp -Server $HostName -Path $FromTable -Destination /www/site_table.conf
    # 重启nginx 
    Restart-NginxOnHost -HostName $hst
    # 等待环节
    Write-Warning "等待2到5分钟让cf激活域名保护(不保证成功,大多数情况下可以),后续检查是否全部激活,否则循环等待,每次$RetryGap 秒,最多等待$MaxRetryTimes 轮"
    if($WaitTimeBasic)
    {
        write-warning"基础等待时间$WaitTimeBasic 秒"
    }
    # Start-SleepWithProgress -Seconds $WaitTimeBasic
    $retryTimes = $MaxRetryTimes
    # 记录域名检查次数(查询域名激活的次数)
    $checkTimes = 0
    $domainsInfo = Get-CFZoneInfoFromTable -Json -Table $FromTable | ConvertFrom-Json
    $domainCount = $domainsInfo.Count
    $domainTotal = $domainCount
    # 检查域名激活状态
    while ($True )
    {
        $checkTimes += 1
        Write-Verbose "Checking domain activation status($checkTimes)"

        
        $domainsInfo = $domainsInfo | ForEach-Object {
            $item = $_
            if ($item.status -ne "active")
            {
                Write-Warning "Domain $($item.Zone) is not active($($item.status)), please wait or check it."
            }
        }
        $inactiveDomains = $domainsInfo.Zone
        $inactiveCount = $domainsInfo.Count
        $activeCount = $domainTotal - $inactiveCount
        Write-Verbose "active: $activeCount;inactive: $inactiveCount" -Verbose

        if($activeCount -eq $domainTotal)
        {
            Write-Host "All domains are active" -ForegroundColor Green
            return $True
        }
        else
        {
            Write-Host "There are $inactiveCount domains is not active, please wait for $RetryGap seconds and retry" -ForegroundColor Cyan
            
            
            $completed = [math]::Round($activeCount / $domainTotal * 100, 2)
            Write-Progress -Activity "Waiting for domain activation" -Status "There are $activeCount / $domainTotal domains active  ($completed% completed)" -PercentComplete $completed 
            if($retryTimes -eq 0)
            {
                Write-Error "Max retry times  exhuasted, exit"
                return $False
            }
            else
            {
                Write-Host "Remanining retry times: $retryTimes"
            }

        }
        # 计算下一轮需要查询的域名(本轮未激活的域名)
        $domainsInfo = $inactiveDomains | ForEach-Object { flarectl --json zone info --zone $_ | ConvertFrom-Json }
        Start-SleepWithProgress $RetryGap
        $retryTimes--
    }
    # 配置cf域名解析,邮箱转发和代理保护(位置2,暂时使用位置1)
    # Add-CFZoneConfig
}
function Get-CFAccountsCodeDF
{
    <# 
    .SYNOPSIS
        获取已配置的可用的cf账号代号(名字)列表
        注意代号是cf账号(邮箱)的简写,例如account1,a1,甚至直接使用数字编号1,1-1,2-1等
    .DESCRIPTION
        读取DF约定格式的cf_config.json配置文件中的特定属性并获取cf账号列表
        返回powershell数组
    .NOTES
        如果json文件结构有变,可能要更新此代码以正确读取账号列表
    .EXAMPLE
        #⚡️[Administrator@CXXUDESK][~\Desktop][18:22:38] PS >
        Get-CFAccountsCodeDF

        account1
        account2
        account2-1
        account3
        account4
    #>
    param (
        $CfConfig = "$cf_config"
    )
    $config = Get-Content $CfConfig | ConvertFrom-Json
    return $config.accounts.psobject.properties.name
    
}
function Get-ServerList
{
    <# 
    .SYNOPSIS
        读取服务器配置(json文件)
    .DESCRIPTION
        读取服务器配置(json文件),返回服务器列表
        返回的数据是powershell的PSObject对象(数组),可以方便地遍历服务器

    .NOTES
        如果json文件结构有变,可能要更新此代码以正确读取服务器配置列表
    #>
    param(
        [alias('Config', "ServerConfig")]$Path = "$server_config",
        # 跳过前若干个服务器(比如特殊用途的服务器),设为0表示返回全部服务器
        $Skip = 1
    )
    $config = Get-Content $Path | ConvertFrom-Json
    # Write-Output $config
    $servers = $config.servers.PSObject.Properties.Value
    # Write-Output $servers
    if($Skip -eq 1)
    {
        Write-Warning "Skipping the first $Skip server."
    }
    return $servers[$Skip..($servers.Length - 1)]
    
}
function Update-WpFunctionsphpOnServers
{
    <# 
    .SYNOPSIS
    批量更新服务器上的Wordpress函数文件
    .PARAMETER Path
    函数文件路径,默认值为"$wp_plugins/functions.php"
    .PARAMETER Target
    上传文件到目标目录,默认值为"/www/"
    .PARAMETER ServerConfig
    服务器配置文件路径,默认值为"$server_config"
    #>
    param (
        $Path = "$wp_plugins/functions.php",
        $BashScript = '/www/sh/wp-functions-update/update_wp_functions.sh',
        # 注意,Target目录在远程服务器上应该存在,否则scp上传会失败(scp不会创建缺失的中间路径目录),-r选在跟也不会帮助你创建缺失起始目录
        $RemoteDirectory = "/www/",
        $WorkingDirectory = "/www/wwwroot,/wwwdata/wwwroot",
        $ServerConfig = $server_config
    )
    $servers = Get-ServerList -Path $ServerConfig
    $servers.ip | ForEach-Object {
        Write-Host "Updating functions.php to $_"
        # Push-ByScp -Server $_ -SourcePath $Path -TargetPath $Target  -Verbose
        scp -r $Path root@"$_":$RemoteDirectory
        $remoteFunctionsFile = "$RemoteDirectory/functions.php"
        ssh root@$_ "bash $BashScript --src $remoteFunctionsFile --workdir $WorkingDirectory"
    } 
    
}
function Get-WpOrdersByEmailOnServers
{
    param (
        [Alias('Email')]$Path = "$desktop/emails.txt",
        $ServerConfig = $server_config,
        $scriptPath = "/www/sh/check_order_email.sh"
        
    )
    $servers = Get-ServerList -Path $ServerConfig
    foreach ($server in $servers)
    {
        $ip = $server.ip
        Write-Host "Getting orders from $($ip)"
        $fileName = Split-Path $Path -Leaf
        $fileOnServer = "/www/$fileName"
        # Get-WpOrdersByEmail -Email $Path -Server $server
        $mysql = $server.mysql

        $user = $mysql.root_localhost
        $password = $mysql.root_password
        # $port = $mysql.port
        
        Write-Host "Check orders on $ip with user:$user,password:$password"
        Write-Host "Email file: $fileOnServer on server"

        scp -r $Path root@"$ip":/www/


        ssh root@$ip "cat -n $fileOnServer && bash $scriptPath -f $fileOnServer -o /www/found_orders.txt -u $user -p '$password'"
    }
    foreach ($server in $servers.ip)
    {
        ssh root@$server "cat /www/found_orders.txt"
    }
    
}
function Update-WpPluginsDFOnServers
{
    <# 
    .SYNOPSIS
    批量更新服务器上的Wordpress插件目录
    读取配置文件中的服务器列表,然后逐个服务器执行相同的处理
    #>
    param(
        # 本地插件目录路径🎈
        [parameter(ParameterSetName = 'Path')]
        [Alias('Path')]
        $PluginPath ,
        $WorkingDirectory = "/www/wwwroot,/wwwdata/wwwroot",
        # 插件名称(服务器上插件路径的最后一级目录名)
        [parameter(ParameterSetName = 'Name')]
        $PluginName,
        $WhiteList = "",
        $BlackList = "",
        # 删除插件
        [parameter(ParameterSetName = 'Name')]
        [switch]$RemovePlugin,

        $ServerConfig = $server_config
    )

    if($WhiteList -and $BlackList)
    {
        Write-Error "WhiteList and BlackList can not be used together!"
    }
    elseif($WhiteList)
    {
        Write-Verbose "Using WhiteList...(only update plugins of sites(domain) in WhiteList)"
        if (@($WhiteList).Count -gt 1)
        {
            Write-Verbose "There are more than one WhiteList, merging them..."
            $mergeFile = "$desktop/WhiteList-$(Get-DateTimeNumber -Format "yyyyMMddHH" ).txt"
            Get-Content $WhiteList -Raw | Out-File $mergeFile -Verbose
        }
        else
        {
            $mergeFile = $WhiteList
        }
        $domainListParam = "-WhiteList $mergeFile"
    }
    elseif($BlackList)
    {
        
        Write-Verbose "Using BlackList...(skip updating plugins of sites(domain) in BlackList)"
        if (@($BlackList).Count -gt 1)
        {
            Write-Verbose "There are more than one BlackList, merging them..."
            $mergeFile = "$desktop/BlackList-$(Get-DateTimeNumber -Format "yyyyMMddHH" ).txt"
            Get-Content $BlackList -Raw | Out-File $mergeFile -Verbose
        }
        else
        {
            $mergeFile = $BlackList
        }
        $domainListParam = "-BlackList $mergeFile"
    }

    $servers = Get-ServerList -Path $ServerConfig
    # Write-Host "servers:$servers"
    # return $servers
    $servers.ip | ForEach-Object {
        if($PSCmdlet.ParameterSetName -eq 'Path')
        {
            
            Write-Host "Updating plugins to $_"
            "Update-WpPluginsDFOnServer -server $_ -WorkingDirectory '$workingDirectory' -PluginPath $PluginPath $domainListParam" | Invoke-Expression
        }
        elseif($PSCmdlet.ParameterSetName -eq 'Name' -and $RemovePlugin)
        {
            Write-Host "remove plugins[$PluginName] in $_"
            "Update-WpPluginsDFOnServer -server $_ -WorkingDirectory '$workingDirectory' -PluginName $PluginName -RemovePlugin $domainListParam" | Invoke-Expression
        }
    }
}
function Update-WpSitesRobots
{
    <# 
    .SYNOPSIS
    更新Wordpress网站robots.txt文件
    主要是修改(追加)sitemap地址到robots.txt文件中,适配对应的域名
    #>
    [CmdletBinding()]
    param(
        $Path,
        $Domain
    )
    
    "`n" >> $Path
    "Sitemap: https://www.$Domain/sitemap_index.xml" >> $Path
    "Sitemap: https://www.$Domain/sitemap_more.xml" >> $Path
    "Sitemap: https://www.$Domain/sitemap_new.xml" >> $Path

}
function Update-WpTitle
{
    <# 
    .SYNOPSIS
    更新Wordpress网站的标题
     #>
    [cmdletbinding()]
    param(

        [parameter(Mandatory = $true)]
        $DatabaseName ,
        [parameter(Mandatory = $true)]
        [alias('Title')]
        $NewTitle,
        # 以下参数继承自 Import-MysqlFile 
        $Server = "localhost",
        # $SqlFilePath,
        $MySqlUser = "root",
        [Alias('MySqlKey')]$key = $env:MySqlKey_LOCAL
    )
    $key = Get-MysqlKeyInline $key
    #  mysql -h localhost -u root  -p15a58524d3bd2e49 -e  "use 1.de;  UPDATE wp_options SET option_value = `'1.de.titlex`' WHERE option_name = `'blogname`';"
    $cmd = " mysql -h $Server -u $MySqlUser $key -e " + " `"use $DatabaseName; UPDATE wp_options SET option_value = '$NewTitle' WHERE option_name = 'blogname';`"" 
    Write-Warning $cmd
    $cmd | Invoke-Expression

}
function Update-WpUrl
{

    <# 
    .SYNOPSIS
    更新 WordPress 数据库中的站点地址
    .DESCRIPTION
    一般用于网站迁移,需要修改数据库中的站点地址,一般需要修改wp_options表中的'home'和'siteurl'选项

    
    #>
    [cmdletbinding(SupportsShouldProcess)]
    param(
        [parameter(Mandatory = $true)]
        $OldDomain,
        [parameter(Mandatory = $true)]
        $NewDomain,
        $DatabaseName = $NewDomain,
        # 以下参数继承自 Import-MysqlFile 
        $Server = "localhost",
        # $SqlFilePath,
        $MySqlUser = "root",
        [Alias('MySqlKey')]$key = $env:DF_MySqlKey,
        [Alias('WWW')][switch]$Start3w,
        $protocol = "https"
        
    )
    if ($Start3w)
    {
        # 将domain.com,http(s)://domain.com,http(s)://www.domain.com统一规范化为$protocol://www.domain.com
        $NewUrl3w = $NewDomain.Trim() -replace '^(https?://)?(www\.)?', "${protocol}://www."
        Write-Verbose "Change:[$NewDomain] to:[$NewUrl3w]" -Verbose
        $new = $NewUrl3w
    }
    else
    {
        # 将domain.com,http(s)://domain.com,http(s)://www.domain.com统一规范化为$protocol://newdomain.com
        $new = $NewDomain.Trim() -replace '^(https?://)?(www\.)?', "${protocol}://"
    }
    $Olds = 'http', 'https' | ForEach-Object { $_ + '://' + ($OldDomain.Trim()) }
    Write-Verbose "Updating WordPress database:[$DatabaseName] from [$OldDomain] to [$NewDomain]" -Verbose
    $sql = ""
    foreach ($old in $Olds)
    {
        
    
        $url_var_sql = @"
-- 定义旧域名和新域名变量

--
/* 
修改下面的变量,注意带上[http(s)://+域名或ip],其他做法容易翻车
 */
SET
    @old_domain = CONVERT(
        '$Old' USING utf8mb4
    ) COLLATE utf8mb4_unicode_520_ci;

SET
    @new_domain = CONVERT(
        '$New' USING utf8mb4
    ) COLLATE utf8mb4_unicode_520_ci;

"@ 
        $replace_sql = @'
-- 更新 wp_options 表中的 'home' 和 'siteurl' 选项

UPDATE wp_options
SET
    option_value =
REPLACE (
        option_value,
        @old_domain,
        @new_domain
    )
WHERE
    option_name IN ('home', 'siteurl');

'@
        $sql += ($url_var_sql + $replace_sql)
    }
    #     $common = @'
    # -- 更新 wp_options 表中的 'home' 和 'siteurl' 选项

    # UPDATE wp_options
    # SET
    #     option_value =
    # REPLACE (
    #         option_value,
    #         @old_domain,
    #         @new_domain
    #     )
    # WHERE
    #     option_name IN ('home', 'siteurl');

    # -- 更新 wp_posts 表中的 'post_content' 和 'guid' 字段
    # UPDATE wp_posts
    # SET
    #     post_content =
    # REPLACE (
    #         post_content,
    #         @old_domain,
    #         @new_domain
    #     ),
    #     guid =
    # REPLACE (
    #         guid,
    #         @old_domain,
    #         @new_domain
    #     );

    # -- 更新 wp_comments 表中的 'comment_content' 和 'comment_author_url' 字段
    # UPDATE wp_comments
    # SET
    #     comment_content =
    # REPLACE (
    #         comment_content,
    #         @old_domain,
    #         @new_domain
    #     ),
    #     comment_author_url =
    # REPLACE (
    #         comment_author_url,
    #         @old_domain,
    #         @new_domain
    #     );

    # ALTER TABLE `wp_terms`
    # CHANGE `name` `name` VARCHAR(8000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NULL DEFAULT NULL;

    # ALTER TABLE `wp_terms`
    # CHANGE `slug` `slug` VARCHAR(8000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT '';
    # '@
    $sqlPath = "$env:TEMP/update-wp-url.sql"
    $sql | Out-File $sqlPath
    Write-Verbose $sql 
    
    Import-MysqlFile -Server $Server -SqlFilePath $sqlPath -MySqlUser $MySqlUser -key $key -DatabaseName $DatabaseName 

}
function Update-WpPluginsDFOnServer
{
    <# 
.SYNOPSIS
    建议配置免密登录，避免每次都输入密码(ssh 密钥注册)
    
.DESCRIPTION
    这里直接上传插件文件夹(你需要手动解压,插件可能是zip或者tar.gz)
    也可以添加逻辑来支持上传压缩文件(todo)
    或者指定目录后,添加一个压缩成zip/7z的命令,然后推送到服务器上,最后调用解压和目录复制逻辑
.NOTES
注意黑名单或白名单文本的换行符(LF),对于(CRLF)需要小心,可能会有意外的效果,这取决于服务器端的脚本实现(update_wp_plugin.sh)
.EXAMPLE
Update-WpPluginsDF -PluginPath C:\share\df\wp_sites\wp_plugins_functions\price_pay\mallpay 
#>
    [cmdletbinding()]
    param(

        [Alias('hst', 'Ip')]$server ,               # 服务器IP地址
        $Username = "root"        ,      # 服务器用户名
        # $password = ""              # 服务器密码（不推荐明文存储,配置ssh密钥登录更安全）
        
        # 本地插件目录路径🎈
        [parameter(ParameterSetName = 'Path')]
        $PluginPath ,  
        # 插件名称(服务器上插件路径的最后一级目录名)
        [parameter(ParameterSetName = 'RemoveByName')]
        $PluginName,
        
        $RemoteDirectory = "/www"       , # 服务器目标目录
        # 工作目录,可以指定多个(通过逗号分隔,最终用引号包裹),尤其对于多个硬盘的服务器比较有用
        $WorkingDirectory = "/www/wwwroot,/wwwdata/wwwroot",
        $BashScript = "/www/sh/wp-plugin-update/update_wp_plugin.sh",
        $WhiteList = "",
        $BlackList = "",
        # 移除插件而非安装(更新)插件
        [parameter(ParameterSetName = 'RemoveByName')]
        [switch]$RemovePlugin,
        [switch]$Dry
    )
    

    function Get-DomainListParam
    {
        <# 
        .SYNOPSIS
        黑白名单文件参数构造和上传
        #>
        param(
            $DomainList,
            [ValidateSet('WhiteList', 'BlackList')]$ListType
        )
        Write-Verbose "Using $ListType ...(only update plugins of sites(domain) in $ListType)"
        Write-Verbose "Uploading [$DomainList] file to server[$server]..." -Verbose
        scp -r $DomainList $username@${server}:"$remoteDirectory" 
        $domainListName = Split-Path -Leaf $DomainList
        $DomainListPathRemote = "$remoteDirectory/$domainListName"
        if($ListType -eq "BlackList")
        {
            $domainListParam = " --blacklist $DomainListPathRemote "
        }
        else
        {
            $domainListParam = " --whitelist $DomainListPathRemote "
        }
        return $domainListParam
    }
    # 执行高性能的bash脚本
    $basicCmd = " ssh $username@$server bash $bashScript --workdir $workingDirectory "
    $dryRunParam = if($Dry) { "--dry-run" }else { "" }
    if($WhiteList -and $BlackList)
    {
        Write-Error "WhiteList and BlackList can not be used together!"
        return $False
    }
    elseif($WhiteList)
    {
       
        $domainListParam = Get-DomainListParam $WhiteList -ListType "WhiteList"
    }
    elseif($BlackList)
    {

        $domainListParam = Get-DomainListParam $BlackList -ListType BlackList
    }
    if($PSCmdlet.ParameterSetName -eq 'Path')
    {
        $plugin_dir_name = (Split-Path $PluginPath -Leaf) # 🎈
        $plugin_dir = "$remoteDirectory/$plugin_dir_name"  # 服务器目标插件目录🎈
        # 上传文件到服务器
        Write-Verbose "Uploading file to server[$server]..." -Verbose
        scp -r $PluginPath $username@${server}:"$remoteDirectory" 
        
        
        Write-Verbose "Executing updating script...(this need several seconds, please wait...)" -Verbose
        # 执行PHP脚本
        # ssh $username@$server "php $remoteDirectory/$phpScript $remoteDirectory $plugin_dir "

        $cmd = " $basicCmd --source $plugin_dir $domainListParam $dryRunParam " 
    }
    elseif($PSCmdlet.ParameterSetName -eq 'RemoveByName' -and $RemovePlugin)
    {
        # bash update_wp_plugin.sh --remove mallpay --whitelist whitelist.conf
        $cmd = " $basicCmd --remove $PluginName $domainListParam  $dryRunParam " 
    }
    
    Write-Verbose "Executing command: $cmd" -Verbose
    Start-Sleep 2
    $cmd | Invoke-Expression
    Write-Verbose "Done." -Verbose
    
}
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
        # Write-Host $values[1..10]
        $values | ForEach-Object { 
            # Write-Host "Moving file: $SourceDir/$_ to $Destination"

            Move-Item -Path $SourceDir/$_ -Destination $Destination -Verbose -ErrorAction SilentlyContinue # -Confirm
        }
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
function Deploy-WpServerDF
{
    <# 
    .SYNOPSIS
    利用screen部署WordPress到DF1服务器,将任务推到后台运行,运行中途允许你使用screen -r $user命令查看运行状态
    所有任务结束后会自动退出screen(自动移除)

    服务器上应该预先执行:
    ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /deploy.sh
    这样可以用/deploy.sh来方便指定部署脚本所在位置
    #>
    param (
        # [ValidateSet('zsh', 'zw', 'xcx')]
        $Server,
        $User,
        $Directory = "/srv/uploads/uploader/files",
        $DBUser = "root",
        $ServerUser = 'root',
        $DBKey = $env:MySqlKey_LOCAL


    )
    ssh ${ServerUser}@$Server "screen -dmS $user bash -c ' chmod +x /deploy.sh;/deploy.sh --pack-root $Directory --user-dir $user --db-user $DBUser --db-pass $DBKey  ;screen -XS $user quit ;exec bash'"
    # 检查此时的screen任务
    $tips = "ssh ${ServerUser}@$server 'screen -ls $user'"
    $tips | Invoke-Expression
    Write-Verbose "running command:  $tips to check screen tasks." -Verbose
    
}
function Get-XXXShopifyProductJsonUrl-Archived
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
            
            $hst = ([System.Uri]$Uri).Host
            $proxyRotation = @($null) + $Proxies
            $maxAttemptsPerEngine = [math]::Min($Retries, $proxyRotation.Count)

            # 1. 智能尝试：优先使用缓存的成功配置
            if ($Cache.ContainsKey($hst))
            {
                $cachedConfig = $Cache[$hst]
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
                        $Cache[$hst] = @{ Engine = 'Iwr'; Proxy = $currentProxy }
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
                            $Cache[$hst] = @{ Engine = 'Curl'; Proxy = $currentProxy }
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
        $Pattern = "2025",
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
function Backup-WpBaseSql
{
    <# 
    .SYNOPSIS
    更新本地wordpress模板站的mysql数据库文件
    .DESCRIPTION
    $Range = @(1, 2, 4, 6, 7),
    $Country = @('us', 'fr', 'de', 'es', 'it')
    .EXAMPLE
    PS> update-WpBaseSql -Range 1,2,4,6,7 -Country us,fr,de,es,it
    #>
    param(
        $Range = @(1, 2, 4, 6, 7),
        $Country = @('us', 'uk', 'fr', 'de', 'es', 'it')
    )
    foreach($c in $Country)
    {
        $Range | ForEach-Object { Export-MysqlFile -DatabaseName "$_.${c}" -key $env:MySqlKey_LOCAL -SqlFilePath C:\sites\wp_sites\base_sqls\$_.${c}.sql }
    }
    
}
function Deploy-Wp
{
    <# 
.SYNOPSIS
对宝塔自动部署本地已有的wordpress模板网站进行快速建站
每次可以建一个站,批量建站(可以配置一个列表,然后将脚本循环运行)
.DESCRIPTION
该脚本可以快速部署本地已有的wordpress模板网站,并自动配置数据库,域名,网站根目录以及伪静态等信息

这里有两个任务需要注意:
1.生成批量宝塔批量建站语句和对应数据库创建语句
    (后续需要手动配置伪静态和ssl证书绑定,其中伪静态也可以通过此脚本批量配置,
    但是证书的申请和绑定需要逐个手动操作,尤其是证书的申请难以自动化分配,这是唯一的遗憾)
2.解压网站根目录和数据库sql还原;并且自动配置权限,所有者配置,修改配置文件以及数据库中的url(域名)相关值

.PARAMETER Table
指定表格数据,可以是自动模式(默认),从文件读取,或者直接输入多行字符串
例如:
www.domain1.com	zw	3.fr
www.domain2.com	zw	4.de


.PARAMETER SpiderTeam
指定你的采集队伍人员姓名及其对应映射的名字缩写或代号,文件可以手动指定,也可以配置到powershell环境
.PARAMETER Structure
指定你粘贴的表格型数据的各列含义,尤其是前两列Domain和User不要动,尤其是User,是翻译名字的关键,
后面我预设了TemplateDomain和DeployMode这两列,
这两个分别用来指定改站点的旧域名(本地模板使用的本地域名),以及部署模式(是重新打包站点根目录以及导出最新数据库部署,还是利用已有的备份数据进行部署)
第4列之后可以为空,但是前三列比较重要

上述4个预设的列是按照高度规范的模板站根目录和数据库命名才能够达到的最简单配置
如果你的本地模板站根目录和数据库名字不同,甚至不同模板的根目录不在同一级存放站点的总目录下,那么需要配置的参数就比较多了

本文的本地模板规范是:所有有模板统一放在一个总目录下`sites`下,其每一个子目录表示一个模板;
所有模板的数据库名字和根目录名字一样,并且采用的本地域名也是和根目录名字一样
例如我的第一套德国站模板,我将其根目录命名为1.de,同时本地域名和数据库名字也都是1.de;
这种设计大有好处,允许很多操作可批处理执行,而且是相对容易实现
.PARAMETER TableMode
指定表格数据输入方式,可以是自动模式(默认),从文件读取,或者直接输入多行字符串
.NOTES
约定:

配置路径建议(但不是必须)统一用`/`分隔,也就是正斜杠(slash),windows/linux都能识别正斜杠(反斜杠windows可以识别,linux不行)
路径(目录)末尾不要使用`/`结尾,这不利于我们手动拼接路径
对于powershell,双引号字符串具有差值计算功能,而单引号字符串不具有差值功能,不能随意替换,按需使用

# .NOTES
关于压缩和解压,这里推荐使用7z压缩,本地一般不会自带7z,你需要自己安装,可以到官网/联想应用商店下载安装包,或者通过scoop自动安装
如果实在不想要7z,这里也提供了zip方案来打包,但是体积可能是7z包的2到3倍,你需要传输更长时间
使用7z的好吃是压缩率高,一般服务器自带7z命令,7z命令行工具可以压缩和解压几乎所有常见压缩包,包括zip,唯一的问题是电脑或服务器不一定自带7z;
zip的优势则是通用性,尤其是一般设备都支持压缩/解压zip
# .Notes
补充说明:root用户执行此脚本引起的权限及其衍生问题(相关问题的解决方案(自动处理)已经包含在脚本中)
这里脚本默认使用的是root用户来执行操作,而由root用户操作的文件或目录权限可能对其他用户不友好,这潜在的可能引发许多问题
例如访问网站时遇到403(被拒绝访问);wordpress默认组件,比如ftp提示警告等等


为了这类问题,你有两类选择:
1.仍然使用root操作，但是操作完成后要将权限放宽(比如将网站根目录设置为755);
另外将网站目录所有者设置为web服务用户(比如宝塔创建的/www用户)
在wp-config.php中,根据需要你可以禁用ftp,添加define('FS_METHOD', 'direct');到合适位置(末尾附近)即可
2.尝试使用普通用户来操作,但是我没验证过是否能够有利于避免权限问题

参数:不是所有参数都是必要的,但是建议不要随意调整,尤其是参数相对顺序,尤其是存在前后引用顺序,例如参数B的默认取值引用了参数A的值,那么参数B如果放到参数A前面可能会引发错误的默认取值;除非你不用到参数B,那么参数B位置随意,甚至可以被删除!

其他:
推荐环境变量配置密码,简化调用和提高安全性

.TODO
==================
解决 链接关闭问题(等待太久就会出现链接关闭问题)
Performing the operation "scp -r C:\sites\wp_sites/1.de.7z root@$env:df_server1:/www/wwwroot" on target
"232.2x.1.202".
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):
Connection closed by 232.2x.1.202 port 22
C:\ProgramData\scoop\apps\openssh\current\scp.exe: Connection closed

=======================
数据库没有自动处理时手动操作如下

ssh登陆到服务器
# 创建数据库
mysql -u root -e 'CREATE DATABASE `dbname` ;' -p"YourPassword" #替换dbname为你的数据库名,YourPassword为你的数据库密码
# 导入数据库备份文件
mysql -u root dbname < /www/wwwroot/4.de.sql -p 

本地powershell执行(可以自行添加密码参数 -key)


#>
    [cmdletbinding(SupportsShouldProcess)]
    param(

        $Table = "$home/desktop/table.conf",
        [ValidateSet("Auto", "FromFile", "MultiLineString")]$TableMode = 'Auto',
        $Server = $env:DF_SERVER1,
        $MysqlUser = "rootx",
        $MysqlKey = "$env:df_mysqlkey",

        $Structure = "Domain,User,TemplateDomain,DeployMode",
        $StructureCore = "Domain,User",
        $SpiderTeam = $SpiderTeam,
        $RewriteRules = "$wp_migration/RewriteRules.LF.conf",
        [switch]$CheckParams,
        [switch]$DelayToRun
    )
    function Deploy-SiteToServer
    {
        <# 
.SYNOPSIS
部署本地wordpress模板网站到服务器
.DESCRIPTION

基于上述功能,迁移过程的基本逻辑:

[核心部分]
网站归属人员;$User
服务器站点正式域名;$Domain
本地模板站域名(本地旧域名);$TemplateDomain

[可以简化的部分]如果按照本文的方式组织本地模板,那么此脚本的方便程度达到最大化,否则你还需要配置下面几个关键参数

1.本地模板站目录:$SiteDir
2.本地模板站目录归档文件|压缩包路径(7z/zip文件,不存在时自动压缩生成):$SiteDirArchive
3.本地模板站数据库名字;$OldDbName
4.本地模板站数据库备份文件路径(sql文件,不存在时自动生成);$OldDbFile

=====================================================================
[一般不需要修改,但是你以修改的重要参数]
服务器站点总目录(作为上传文件的存放目录,宝塔下一般默认/www/wwwroot);$ServerSitesHome
    服务器站点根目录(自动构造);$ServerSiteRoot
    服务器端网站目录归档文件路径(自动构造):$ServerSiteDirArchive
    服务器端网站sql备份文件路径(自动构造):$ServerDbFile
服务器站点数据库名字(自动构造);$ServerDBName

[通信/传输工具和鉴权]这部分可以通过配置环境变量以及免密配置等操作省去填写,或者填写是一次性的,第一次使用需要配置,后面就可以不写

配置mysql命令行工具(path环境变量);
    ssh命令行工具一般自带不用配置
服务器ssh用户名密码/密钥免密
服务器mysql用户名密码/配置文件免密

------------------------------------------
[采集或建站人员字典]这也是一次性配置

在电脑某个路径下配置一个文件SpiderTeam.ps1,比如:
$SpiderTeam=C:\sites\wp_sites\SpiderTeam.ps1
内容格式举例:
$SiteOwnersDict = @{
    "郑五"             = "zw"
    "张三"            = "zs"
    DFTableStructure = "Domains,User"
}
return $SiteOwnersDict

# 我们可以通过命令行:
. $SpiderTeam #导入字典到命令行环境中

==========================================
[配置powershell模块]
运行此脚本需要安装powershell7和git并配置模块:(下面是一键部署,但是建议手动安装上述两个软件,自动部署会自定下载安装软件,但是速度不是那么稳定,主要用他来下载powershell的模块)

irm 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex

此命令行在powershell7或者windows 自带的powershell(v5)中都可以执行

参数文档说明(可能有滞后,仅供参考)
.PARAMETER User
网站所有者,一般是宝塔创建的用户,比如lyz

.PARAMETER domain
网站域名,比如deportealegria.com

.PARAMETER TemplateDomain
旧网站域名,比如本地模板使用的本地域名(上传到服务器后需要执行域名更新,修正为正式域名),也可以是其他情况下需要被替换的域名,比如6.es, local.com
.PARAMETER MysqlUser
服务器数据库用户名,一般是root

.PARAMETER ServerUser
服务器服务器用户名,一般是root

.PARAMETER Server
服务器服务器IP地址,比如192.168.1.1,但是这里将服务器ip配置到系统环境变量,这样调用方便,也更加安全优雅;
如果必要,你可以手动指定

.PARAMETER MysqlKey
服务器数据库密码,一般是宝塔创建的数据库密码,这里默认读取配置在环境变量中的数据库密码;
如果必要,你可以手动指定

.PARAMETER ServerSitesHome
服务器服务器总的网站目录,一般是/www/wwwroot,这个目录由宝塔默认创建
.PARAMETER user_sites_home
服务器服务器用户网站目录,一般是/www/wwwroot/$User,比如/www/wwwroot/lyz
这个目录在$ServerSitesHome下添加一级用户名目录,用于区分不同的建站人员,便于管理
.Parameter ServerUserDomainDir
用户网站域名目录,格式为"$ServerUserSitesHome/$domain",比如"/www/wwwroot/lyz/pasoadeporte.com"

.PARAMETER ServerSiteRoot
用户网站根目录,格式为"$ServerUserDomainDir/wordpress",比如"/www/wwwroot/lyz/pasoadeporte.com/wordpress"

.PARAMETER ServerWpConfigFile
wordpress配置文件路径,格式为"$ServerSiteRoot/wp-config.php",比如"/www/wwwroot/lyz/pasoadeporte.com/wordpress/wp-config.php"

.PARAMETER ServerDBName
服务器数据库名称,格式为"$User_$domain",比如"lyz_pasoadeporte.com"
.PARAMETER DeployMode
控制网站备份文件(分为两部分:
1.网站根目录打包文件(一般是7z压缩包)
2.数据库文件(一般是sql文件)

是否重新生成并覆盖旧备份(尝试找到并删除旧备份文件,然后重新打包站点根目录,导出数据库文件)

备份文件的存放位置有默认设置值,你也可以在脚本中覆盖它们

.PARAMETER OldDBName
本地数据库文件名,默认风格是和"$TemplateDomain"相同,比如"6.es"


.PARAMETER OldDbFile
本地数据库文件路径,该路径是导出sql后要存放的文件路径,也是读取已有数据库文件的路径

默认格式为"$base_sqls/$OldDBName.sql",
其中$base_sqls是存放数据库备份文件(.sql)的目录;
比如$base_sqls="c:/sites/wp_sites/base_sqls"
比如"c:/sites/wp_sites/base_sqls/6.es.sql"

.PARAMETER ServerDBFile
服务器数据库文件路径,该路径是从本地上传到服务器的数据库存放的位置
(上传到服务器是因为服务器上执行服务器自己的sql文件会比较快)
默认格式为"$ServerUserSitesHome/$OldDBName.sql",
比如"/www/wwwroot/lyz/6.es.sql"

.PARAMETER SiteDir
本地网站根目录,默认风格是"$wp_sites/$TemplateDomain",比如"c:/sites/wp_sites/6.es"
.PARAMETER ArchiveSuffix
用7z压缩本地网站目录,名字可以考虑用日期+时间来区分;
默认使用已有的压缩包,不加后缀
这个选项可以在DeployMode不启用的情况下,额外打包一个带有后缀的站根目录压缩包

#根据需要解开这行注释,这使你可以重新打包当前站点,而且不覆盖已有的备份文件,得到最新版本的压缩包
$ArchiveSuffix=".$(Get-Date -Format yyMMdd-hh)" 

.PARAMETER SiteDirArchive
本地网站根目录压缩包路径,默认是一个7z文件,名字是本地站点根目录同名
格式为"$SiteDir$ArchiveSuffix.7z",比如"c:/sites/wp_sites/6.es.7z"

.PARAMETER base_sqls
数据库备份文件存放路径,格式为"$base_sqls/$OldDBName.sql",比如"c:/sites/wp_sites/base_sqls/6.es.sql"


.PARAMETER BashFileName
文件上传到服务器后,需要修改配置文件,修改数据库必要内容(url)等操作
默认脚本名字为:wp_deploy.sh
注意这个脚本不应该包含CRLF,而应该处理为LF作为换行符
这里通过创建bash脚本,推送到服务器上,让服务器执行,可以减少不必要的麻烦

.PARAMETER BashScriptFile
控制本地生成的bash脚本存放的位置路径
默认格式为"$env:TEMP/$BashFileName",即存放到环境变量指定的临时文件目录Temp中
例如: C:\Users\Administrator\AppData\Local\Temp\wp_deploy.ps1

#>
        [CmdletBinding(SupportsShouldProcess)]
        param(


            #建站信息配置(服务器站点信息);这个部分有3个变量必须要要注意
            [alias('SiteOwner')]$User = "  lyz  ".trim(),

            [alias('FormalDomain', 'NewDomain')]$Domain = @"           

   DeporteAlegria.com  

"@,
            [alias("LocalDomain", "OldDomain", "Template")]$TemplateDomain = "    ".trim(),

            # 次要信息
  
            [alias('SSHUser')]$ServerUser = "root",
            $Server = $Server,
    
            # 本地模板网站根目录备份和导出
            # 🎈
            $SiteDir = "$wp_sites/$TemplateDomain",

            $ArchiveSuffix = "", 
            # $ArchiveSuffix=".$(Get-Date -Format yyMMdd-hh)" ,
            $ArchiveFormat = "7z",
            # 🎈
            $SiteDirArchive = "${SiteDir}${ArchiveSuffix}.${ArchiveFormat}",
   
            $SiteDirArchiveName = (Split-Path $SiteDirArchive -Leaf),
            $SiteArchiveBaseName = (Split-Path $SiteDirArchive -LeafBase),

            # 🎈
            [alias('LocalDBName')]$OldDBName = $TemplateDomain,
            # 🎈
            [alias('LocalDBFile')]$OldDbFile = "$base_sqls/$OldDBName.sql",
            # 配置目录体积界限(单位MB),超出这个范围的怀疑目录有问题
            $MinSize = 10,
            $MaxSize = 500,
            # 服务器网站目录和配置文件相关配置
            $ServerSitesHome = '/www/wwwroot',

            #格式例如: /www/wwwroot/lyz/pasoadeporte.com
            $ServerUserSitesHome = "$ServerSitesHome/$User",
        
            $ServerDBFile = "$ServerSitesHome/$OldDBName.sql",
            $ServerSiteDirArchive = "$ServerSitesHome/$SiteDirArchiveName",
            $ServerUserDomainDir = "$ServerUserSitesHome/$domain",

            # 下面的路径是根据7z的解压行为特点,自动构造的,一般不需要修改(压缩包将作为解压后的目录名,要更改名字,你根据此名来更改(mv))
            $ServerSitePack = "${ServerUserDomainDir}/SitePack",
            $ServerSiteDirExpanded = "${ServerSitePack}/$SiteArchiveBaseName",
            # 服务器数据库名称
            $ServerDBName = "${User}_${domain}",

            #格式例如: /www/wwwroot/lyz/pasoadeporte.com/wordpress
            $ServerSiteRoot = "$ServerUserDomainDir/wordpress",

            $ServerWpConfigFile = "$ServerSiteRoot/wp-config.php",
    

            #本地模板网站数据库信息;移除现有的版本(sql文件和7z压缩包),重新导出配套文件(部署最新版本)
            [validateset('Override', 'Lazy')]$DeployMode = 'Lazy',

    
    
            # 生成的bash脚本(要推送到服务器执行)
            $BashFileName = 'wp_deploy.sh',
            $BashScriptFile = "$env:TEMP/$BashFileName",

            # $SpiderTeam = $SpiderTeam,
            [switch]$CheckParams
        )

        $domain = $domain.ToLower().replace("www.", "") # .replace(".com", "").trim() + ".com"
        Write-Verbose "Params Check Mode is: $CheckParams" -Verbose

        if($CheckParams)
        {
            Write-Verbose "请检查如下关键目录是否配置正确(如果不正确,请回头修改参数;对于不存在的文件,脚本将尝试创建或生成!):" -Verbose

     

            Write-Host "网站归属人员: $User"
            Write-Host "网站域名: $Domain"
            Write-Host "本地模板站点域名(本地旧域名): $TemplateDomain"

            Write-Host "本地站点目录: $SiteDir"
            Write-Host "站点归档文件(压缩包)路径: $SiteDirArchive"
            Write-Host "本地模板数据库名称: $OldDBName"
            Write-Host "本地模板数据库备份sql文件路径: $OldDbFile"

            Write-Host "-----自动构造可自定义的重要参数------"
            Write-Host "服务器站点总目录: $ServerSitesHome"
            Write-Host "服务器站点根目录(例如域名目录domain.com的子目录wordpress): $ServerSiteRoot"
            Write-Host "服务器站点归档文件路径: $ServerSiteDirArchive"
            Write-Host "服务器数据库备份文件sql文件路径: $ServerDBFile"
        
            Write-Host "服务器数据库名称: $ServerDBName"

            Write-Host "-----通信鉴权组------"

            Write-Host "服务器服务器地址: $Server"
            Write-Host "MySQL密钥: $MysqlKey"
            Write-Host "服务器站点主目录: $ServerSitesHome"
            Write-Host "用户站点主目录: $ServerUserSitesHome"
            Write-Host "用户站点域名目录: $ServerUserDomainDir"
            Write-Host "站点(wp)配置文件路径: $ServerWpConfigFile"

            Write-Host "------备份和bash脚本文件上传位置组"

        
            Write-Host "站点归档文件名: $SiteDirArchiveName"
            Write-Host "站点归档文件基名: $SiteArchiveBaseName"
            Write-Host "站点归档解压后的默认名": $ServerSiteDirExpanded
        
            Write-Host "生成的Bash脚本文件名: $BashFileName"
            Write-Host "生成的Bash脚本文件路径: $BashScriptFile"
        }

        Pause

        # ====================================

        #处理备份文件(保险期间,下面的语句执行前,确保旧文件不再使用,或者做好了必要备份)
        if($DeployMode -eq 'Override')
        {
            # 移除旧文件
            Remove-Item $OldDbFile -ErrorAction SilentlyContinue -Verbose -Confirm
            Remove-Item $SiteDirArchive -ErrorAction SilentlyContinue -Verbose -Confirm
        
        }
        # 如果对应的备份文件不存在,则尝试重新生成
        if(!(Test-Path $SiteDirArchive))
        {
            #打包压缩本地网站目录(最新版本);使用7z打包压缩率高,上传服务器的速度快(要求你本地安装了7-zip,可以用scoop安装或其他方式安装)
            Write-Warning "${SiteDirArchive} does not exist,try to generate it..."
            if($ArchiveFormat -eq "7z")
            {

     
                if(Get-Command 7z -ErrorAction SilentlyContinue)
                {
                    # 判断该目录是否存在,以及初步判断该目录体积是否像一个正常的wp站,尤其是不是一个空站,
                    # 或者存在不必要的文件导致目录体积过大,应该暂时离开,进行排查
                    if(Test-Path $SiteDir)
                    {
                        Get-ChildItem $SiteDir | Select-Object fullname | Out-String | Write-Verbose 

                        # $size = Get-ItemSizeSorted $SiteDir
                        $list = Get-ChildItem $SiteDir | Select-Object -ExpandProperty fullname
                        Write-Host $list 
                        $sizeReportDetail = $size | Out-String
                        Write-Verbose "SiteDir size: $sizeReportDetail" -Verbose
                        $size = (Get-Size $siteDir -Unit MB).size
                        # Write-Host "SiteDir size: $($size|Out-String)"

                        if($size -gt $MaxSize -or $size -lt $MinSize)
                        {
                            Write-Error "SiteDir size is too large or too small, please check it first!"
                            exit
                
                        }
                        7z a -t7z $SiteDirArchive $SiteDir
                    }
                }
                else
                {
                    Write-Warning "7z(7-zip) command not found, please install 7-zip and add it to PATH"
                    if($PSCmdlet.ShouldProcess($SiteDir, "Generate zip archive"))
                    {
                        $ArchiveFormat = "zip"
                    }
                    else
                    {
                        exit
                    }
                }   
            }
            # 如果7z命令不存在,且用户愿意换用zip,则尝试使用zip打包压缩本地网站目录(默认使用powershell自带的Compress-Archive,有一定局限性,但是一般够用)
            if($ArchiveFormat -eq "zip")
            {
                Compress-Archive -Path $SiteDir -DestinationPath $SiteDirArchive -Force 
            
            }
    
        }if (!(Test-Path $OldDbFile))
        {
            #导出本地网站的对应数据库
            Write-Warning "${OldDbFile} does not exist,try to export it..." 
            New-Item -type directory -Path $base_sqls -Force -ErrorAction SilentlyContinue -Verbose
            Export-MysqlFile -DatabaseName $OldDBName -Server localhost -MySqlUser $MysqlUser -key $MysqlKey -SqlFilePath $OldDbFile
        }


        #将网站文件包上传到服务器
        Push-ByScp -Server $Server -User $ServerUser -Source $SiteDirArchive -DestinationPath $ServerSitesHome -Confirm
        # 将数据库备份文件上传到服务器
        Push-ByScp -Server $Server -User $ServerUser -Source $OldDbFile -DestinationPath $ServerSitesHome -Confirm

        # 解压网站文件包到服务器对应目录的命令行构造(不会立即执行!)
        if($ArchiveFormat -eq "7z")
        {

            $ExpandArchiveCmd = "7z x $ServerSiteDirArchive -o${ServerUserDomainDir}/SitePack -y"
            # 解压后的目录标记为:$ServerSiteDirExpanded
        }
        else
        {
            # 这里使用unzip解压zip,7z可用的话也可以解压zip
            $ExpandArchiveCmd = "unzip $ServerSiteDirArchive -d $ServerUserDomainDir/SitePack"
        }
        Write-Verbose "ExpandArchiveCmd: $ExpandArchiveCmd will be executed on server"

        # 通过ssh远程执行命令行(推荐放到bash脚本中执行)
        # ssh $ServerUser@$Server "7z x $ServerSiteDirArchive -o$ServerUserDomainDir -y"

        # =========================

        # 定义bash脚本
        $bash_script = @"

# 解压网站根目录到合适的位置(在服务器调用7z执行命令;目录不存在时,7z会自动创建)
if [ -d "$ServerSiteDirExpanded" ]; then
    echo "The directory already exists: [$ServerSiteDirExpanded]"
    echo "The size of the directory is: [`$(du -sh $ServerSiteDirExpanded)]"
    echo "update/Remove this directory and continue to expand the archive...?(y/n)"
    read -r response
    # 注意将bash中创建并引用的变量前dollar符号使用`转义(这里是powershell变量,bash变量的引用符号会被powershell解释掉,这不是我们想要的)
    # 从powershell中引用的变量则应该表留dollar符号
    echo "You choose: [`$response]"

    if [ "`$response" = "y" ]; then
        rm -r "$ServerSiteDirExpanded"
        echo "Directory removed, continue to expand the archive..."
        $ExpandArchiveCmd
    else
        echo "Use the exist directory directly!"
        # exit 1 #debug todo
    fi
 
else
    echo "The directory does not exist, continue to expand the archive..."
    $ExpandArchiveCmd
fi

# 删除旧的根目录(可能会遇到.user.ini文件标记导致无法删除,暂时不用此方案)
# rm -rf $ServerSiteRoot
# 判断站点根目录是否事先存在
if [ -d "$ServerSiteRoot" ]; then
    echo "The directory already exists: [$ServerSiteRoot]"
    echo "Try to remove this directory try its best..."
    # 忽略删除输出消息
    rm -rf "$ServerSiteRoot" > /dev/null 2>&1
    # 确保目标目录存在(如果已经存在mkdir也不会报错)
    mkdir diry/dirz -p -v

    echo "Try to move the expanded directory to the root directory..."
    mv "$ServerSiteDirExpanded"/* $ServerSiteRoot -f 

    # 网站根目录(比如wordpress)若已经存在(比如宝塔事先建好,那么你可以尝试尽可能移除或清空此目录内容,
    # 有的内部文件无法直接删除,导致原根目录无法删除),你可考虑将解压的内容移动到网站根目录)
    # 检查目录是否为空,如果非空则移动其中内容,否则删除空目录,以便重新解压 if [ -z "`$(ls -A "$DIR")" ]; then
    # if [ -z "`$(ls -A $ServerSiteDirExpanded)" ]; then
    #     echo "Warning: Directory is empty: [$ServerSiteDirExpanded]"
    #     rm -r "$ServerSiteDirExpanded" 
    # else
    # 移动现有非空站点根目录到指定位置(并重命名为wordpress)
    # fi 
else
    # 站点根目录事先不存在,直接将原站点解压目录移动(更名)为站点根目录
    # 移动站点根目录到指定位置(并重命名为wordpress)
    mv $ServerSiteDirExpanded $ServerSiteRoot -f
fi



# 将wp-config.php文件中的数据库信息修改为正式数据库的信息
sed -ri "s/(define\(\s*'DB_NAME',\s*')[^']+('\s*\))/\1$ServerDBName\2/"  $ServerWpConfigFile

# 清理临时目录🎈
rm -r ${ServerUserDomainDir}/SitePack

# 将上传到服务器的sql备份文件导入服务器的数据库中🎈
echo "Importing database backup file to server...🎈"
mysql -u$MysqlUser -p$MysqlKey -h localhost $ServerDBName < $ServerDBFile
"@ + @'

#sed配置强制使用https (这里使用sed 的行前插入指令i,在匹配到的指定前插入一段内容)

sed -ri "/\/\* That's all, stop editing! Happy publishing. \*/i \
define('FORCE_SSL_ADMIN', true);\n\
if (\$_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https') {\n\
\$_SERVER['HTTPS'] = 'on';\n\
}\n"
'@ + " $ServerWpConfigFile " + @"


# linux递归地更改: 将指定目录权限设置为755;更改目录所有者

chmod 755 $ServerUserDomainDir
chown www:www $ServerUserDomainDir

chmod -R 755 $ServerSiteRoot
chown -R www:www $ServerSiteRoot
"@

        # 转为LF风格shell文件
        $bash_script = $bash_script -replace "`r`n", "`n"


        $bash_script | Set-Content -NoNewline $BashScriptFile
        # Get-CRLFChecker -Path $BashScriptFile
        Write-Host "请检查bash脚本:`n=============================================="
        # Write-Host $bash_script 
        $bash_script | Get-ContentNL -AsString
        Write-Host "===================================================="
        if(!$PSCmdlet.ShouldProcess($BashScriptFile, "Continue?"))
        {
            exit
        }
        #将本地备份的数据库导入到服务器对应的数据库中(耗时比较久,可以考虑使用navicat来加速,或者寻找更高效的方法,比如上传sql文件到服务器,然后让服务器自己导入,写入上述bash脚本片段中)
        # Import-MysqlFile -server $Server -MySqlUser $MysqlUser -DatabaseName $ServerDBName -SqlFilePath $OldDbFile

        #推送伪静态配置文件到服务器
        Push-ByScp -Server $Server -User $ServerUser -Source $RewriteRules -DestinationPath "/www/server/panel/vhost/rewrite/$domain.conf" -Verbose -Confirm

        #将脚本推送到服务器去执行(每轮执行自动更新,无需确认)
        Push-ByScp -Server $Server -User $ServerUser -Source $BashScriptFile -DestinationPath $ServerSitesHome -Confirm:$false

        ssh $ServerUser@$Server "bash $ServerSitesHome/$BashFileName" 

        #修改服务器中对应数据库中域名为正式域名(url/domain)
        Update-WpUrl -Server $Server -MySqlUser $MysqlUser -key $MysqlKey -OldDomain $TemplateDomain -NewDomain $domain -DatabaseName $ServerDBName -Verbose -Start3w -protocol "https" -Confirm:$false

        # 通过ssh 直接执行bash脚本(不推荐,复制语句容易出问题)
        # $bash_script | ssh $ServerUser@$Server "bash -s"
    }
    function Start-Deploysites
    {
        <# 
    .SYNOPSIS
     批量部署网站到服务器(调度现有命令)
    #>
        param (
        
        )
        # 导入字典
        $SiteOwnersDict = . $SpiderTeam 
        Write-Verbose "Check SiteOwnerDict availibility" -Verbose
        Write-Verbose $SiteOwnersDict -Verbose
        # Pause
        # $Dict = $SiteOwnersDict.GetEnumerator()
        # $Dict
        # Write-Host "[$($Dict|Out-String)]" -ForegroundColor Cyan

        # 伪静态配置内容检查
        if(Test-Path $RewriteRules)
        {
            Get-CRLFChecker $RewriteRules
        
        }
        else
        {
            Write-Warning "RewriteRules file does not exist: [$RewriteRules], please check it first!"
            Pause
        }
        $res = Get-DomainUserDictFromTable -Table $Table -Structure $Structure -SiteOwnersDict $SiteOwnersDict -Verbose:$false
        # write-host $res
        Get-DictView -Dicts $res 
        # Pause
        # return $res

        Start-BatchSitesBuild -Server $Server -MySqlUser $MySqlUser -MySqlkey $MysqlKey -Table $Table -TableMode $TableMode -Structure $StructureCore -SiteOwnersDict $SiteOwnersDict -SiteRoot "wordpress" -ToClipboard -Verbose:$false
    
        foreach($item in @($res))
        {
            $DeployMode = $item.DeployMode
            Write-Host "sturcture:[$structure]" -ForegroundColor Cyan
            if(!$DeployMode)
            {
                $DeployMode = 'Lazy'
            }
            Write-Verbose "DeployMode: [$DeployMode]" -Verbose
            # if($PSCmdlet.ShouldProcess($item.Domain, "Deploy to server"))
            # {
            # }
            Deploy-SiteToServer -User $item.User -domain $item.Domain -TemplateDomain $item.TemplateDomain -DeployMode $DeployMode -CheckParams:$checkParams
        }
    }
    # 是否立即执行脚本
    if(!$DelayToRun)
    {
        start-Deploysites
    }
}