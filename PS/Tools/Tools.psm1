function Get-CxxuPsModuleVersoin
{
    param (
        
    )
    Get-RepositoryVersion -Repository $scripts
    
}
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
    # 判断$Path是否为一个目录,如果是,则使用-C
    if (Test-Path $Path -PathType Container)
    {
        $Dir=$Path.Trim('/').Trim('\')
        if ($InDirectory)
        {
            $exp = "tar -c $v -f $OutputFile -C $Dir * "
            
        }
        else
        {
            $exp = "tar -c $v -f $OutputFile -C $Dir/.. $(Split-Path $Path -Leaf) "
        }
    }
    else
    {
        $fileBaseName = Split-Path -Path $Path -Leaf 
        $exp = "tar -c $v -f $OutputFile  -C $parentDir  $fileBaseName "
    }
    Write-Verbose "执行: [$exp]" -Verbose
    Invoke-Expression $exp
    Write-Verbose "打包完成，输出文件: $OutputFile" -Verbose
    return $OutputFile
}
function Get-Lz4Package
{
    [cmdletbinding()]
    param (
        $Path,
        # $OutputDirectory = "./",
        $OutputFile = "",
        $Threads = 16,
        [switch]$NoTarExtension
    )
    Write-Verbose "正在打包目录(目标lz4): $Path " -Verbose
    $dirName = Split-Path $Path -Leaf

    $DefaultOutputDir = [Environment]::GetFolderPath("Desktop")
    $TarExtensionField = if ($NoTarExtension) { "" }else { ".tar" }
    $OutputFileTar = "$DefaultOutputDir/${dirName}${TarExtensionField}"
    $TempTar = "$DefaultOutputDir/${dirName}.tar"
    if ($OutputFile -eq "")
    {
        Write-Debug "输出文件名未指定，使用默认值: ${dirName}.tar"
        Write-Debug "默认存放路径为桌面:$DefaultOutputDir" 
    }
    $OutputFile = "$OutputFileTar.lz4"

    Compress-Tar -Directory $Path -OutputFile $TempTar

    # 若lz4.exe存在,则使用lz4压缩
    Write-Warning "请确保lz4.exe存在于环境变量PATH中,并且版本高于1.10才能支持多线程"
    lz4.exe -T"$Threads" $TempTar $OutputFile
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

    lz4 -T"$Threads" -d $Path $temp; 
    Write-Verbose "Expand Tar: [$temp] to [$OutputDirectory]" -Verbose
    tar -xvf $temp -C $OutputDirectory
}
function Get-7zCommand
{
    param (
    )
    $Have7z = Get-Command 7z -ErrorAction SilentlyContinue
    if (! $Have7z)
    {
        Write-Host "7z命令行工具未找到,请安装7z命令行工具,或者将其添加到环境变量PATH中"
        exit
    }
    return $Have7z
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
        [ValidateSet('zip', '7z', 'tar', 'lz4','zstd')]
        [alias('Mode')]
        $ArchiveMode = 'lz4',
        $Threads = 16

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
    $key = Get-MysqlKeyInline -Key $DatabaseKey
    $SqlFile = "$OutputDir/${Domain}.sql"
    $SqlFileArchiveZip = "$SqlFile.zip"
    $SqlFileArchive7z = "$SqlFile.7z"
    $SqlFileArchiveTar = "$SqlFile.tar"
    $SqlFileArchiveLz4 = "$SqlFile.tar.lz4"
    # 站点根目录
    $SitePackArchiveZip = "$OutputDir/${Domain}.zip"
    $SitePackArchive7z = "$OutputDir/${Domain}.7z"
    $SitePackArchiveTar = "$OutputDir/${Domain}.tar"
    $SitePackArchiveLz4 = "$OutputDir/${Domain}.tar.lz4"

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
    Export-MysqlFile -Server localhost -DatabaseName $DatabaseName -key $key -SqlFilePath $SqlFile -Verbose
    # Compress-Archive -Path $SqlFile -DestinationPath $SqlFileArchiveZip -Force
    # 打包站点目录


    if($ArchiveMode -eq '7z')
    {
        if(Get-7zCommand)
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
        if(Get-7zCommand)
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
        Get-Lz4Package -Path $SqlFile -OutputFile $SqlFileArchiveLz4 -Threads $Threads -NoTarExtension
        Get-Lz4Package -Path $SiteDirecotry -OutputFile $SitePackArchiveLz4 -Threads $Threads -NoTarExtension
        $SitePackArchive = $SitePackArchiveLz4
        $SqlFileArchive = $SqlFileArchiveLz4
    }
    else
    {
        Write-Error "不支持的打包方式: $ArchiveMode"
        return
    }
    # $SitePackArchive = Compress-Tar -Directory $SiteDirecotry 

    # 列出已经打包的文件
    Get-Item $OutputDir/$SqlFileArchive  
    Get-Item $OutputDir/$SitePackArchive
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
function Get-CsvTailRows-Archived
{
    <#
.SYNOPSIS
    提取CSV文件的表头和从第k行到最后一行的数据，并将其保存到指定输出文件中。

.DESCRIPTION
    该脚本读取输入的CSV文件，提取文件的表头（第一行）和指定的第k行到最后一行的数据，
    然后将提取的内容保存到指定的输出文件中。
    
.PARAMETER InputFile
    输入的CSV文件路径。
    
.PARAMETER OutputFile
    输出的CSV文件路径。
    
.PARAMETER StartRow
    提取的数据从第几行开始，k行。第一行为1。

.EXAMPLE
    .\Extract-CsvRows.ps1 -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartRow 5
    从`C:\path\to\input.csv`文件中提取表头和第5行到最后一行的数据，并将其保存到`C:\path\to\output.csv`。

.NOTES
    文件使用UTF-8编码进行读写，确保CSV文件的格式正确。
#>

    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile, # 输入的CSV文件路径

        [Parameter(Mandatory = $true)]
        [string]$OutputFile, # 输出的CSV文件路径

        [Parameter(Mandatory = $true)]
        [int]$StartRow          # 第k行，从1开始
    )

    # 确保StartRow是有效的
    if ($StartRow -lt 1)
    {
        Write-Error "StartRow 必须大于或等于1"
        return
    }

    # 读取CSV文件
    try
    {
        $data = Import-Csv -Path $InputFile
    }
    catch
    {
        Write-Error "读取CSV文件失败: $_"
        return
    }

    # 提取表头行
    $header = $data | Select-Object -First 0

    # 提取从第$StartRow行到最后一行的数据
    $rows = $data | Select-Object -Skip ($StartRow - 1)

    # 保存表头行和提取的行到新的输出文件
    try
    {
        # 输出表头行
        $header | Export-Csv -Path $OutputFile -NoTypeInformation -Force
        # 输出从第$StartRow行开始的数据行
        $rows | Export-Csv -Path $OutputFile -NoTypeInformation -Append -Force
    }
    catch
    {
        Write-Error "保存CSV文件失败: $_"
    }

    Write-Host "处理完成，结果已保存为!(默认所在目录和源文件${InputFile})同目录: $(Resolve-Path $OutputFile)"
    Get-CsvPreview $rows
}
function Get-CsvPreview
{
    param (
        $csv,
        $FirstLineNumbers = 3,
        $propertyNames = @("SKU", "Name")
    )
    $res = $csv | Select-Object -Property $propertyNames | Select-Object -First $FirstLineNumbers | Format-Table ; 

    # Write-Host "....";
    if($csv.count -gt $FirstLineNumbers)
    {
        Write-Output $res
        $last = $csv | Select-Object -Property $propertyNames | Select-Object -Last 1 | Format-Table -HideTableHeaders
        Write-Host "...." 
        Write-Output $last
    }
    else
    {
        Write-Output $res
    }
    Write-Host "Totol lines:$($csv.count)"
}
function Get-CsvTailRows
{
    <#
.SYNOPSIS
    提取 CSV 文件的表头和从第 k 行到最后一行的数据，并将其保存到指定输出文件中。

.DESCRIPTION
    该函数读取输入的 CSV 文件，提取文件的表头（第一行）以及指定起始行号（k）到最后一行的数据，
    然后将提取的内容保存到指定的输出文件中。注意：函数采用 UTF-8 编码读写文件。

.PARAMETER InputFile
    输入的 CSV 文件路径。

.PARAMETER OutputFile
    输出的 CSV 文件路径。

.PARAMETER StartRow
    提取数据的起始行号（第一行为 1）。

.EXAMPLE
    Get-CsvTailRows -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartRow 5
#>

    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputFile,

        [Parameter(Mandatory = $true)]
        [int]$StartRow,

        [switch]$ShowInExplorer
        
    )

    if ($StartRow -lt 1)
    {
        Write-Error "StartRow 必须大于或等于 1"
        return
    }

    # 使用 Import-Csv 读取 CSV 文件 (Import-Csv: 读取 CSV 文件，将每一行转换为对象)
    try
    {
        $data = Import-Csv -Path $InputFile -Encoding UTF8
    }
    catch
    {
        Write-Error "读取 CSV 文件失败: $_"
        return
    }

    # 读取表头行 (Header)：直接从文件中获取第一行文本
    try
    {
        $headerLine = Get-Content -Path $InputFile -Encoding UTF8 -TotalCount 1
    }
    catch
    {
        Write-Error "读取表头失败: $_"
        return
    }

    # 根据 StartRow 提取数据行 (Data Rows)
    try
    {
        if ($StartRow -eq 1)
        {
            # 若从第一行开始，则直接用 Import-Csv 获取所有数据
            $rows = $data
        }
        else
        {
            # 注意：CSV 文件第一行为表头，故数据行实际从第二行开始
            $rows = Import-Csv -Path $InputFile -Encoding UTF8 | Select-Object -Skip ($StartRow - 1)
        }
    }
    catch
    {
        Write-Error "提取数据行失败: $_"
        return
    }

    # 保存数据到输出文件 (Exporting Data)
    try
    {
        # 先写入表头行
        Set-Content -Path $OutputFile -Value $headerLine -Encoding UTF8 -Force
        # 追加数据行（使用 Export-Csv 会自动添加表头，因此这里使用 -Append 参数，并关闭类型信息）
        $rows | Export-Csv -Path $OutputFile -NoTypeInformation -Append -Encoding UTF8 -Force
    }
    catch
    {
        Write-Error "保存 CSV 文件失败: $_"
        return
    }

    $fileDir = Split-Path (Resolve-Path $OutputFile)
    Write-Host "处理完成，结果已保存到: $(Resolve-Path $OutputFile)"
    Write-Host ($fileDir)
    $rows | Select-Object -First 3 | Select-Object -Property SKU, Name | Format-Table  ; 
    Write-Host "....";
    Write-Host "Totol data lines:$($rows.count-1)"

    # 配置是否自动用资源文件管理打开csv所在文件夹
    if ($ShowInExplorer)
    {
        explorer "$fileDir"
        # Start-Job -ScriptBlock { Start-Sleep 1; explorer "$using:fileDir" }
    }
    
}

function Get-CsvTailRowsGUI
{

    # 加载 Windows Forms 和 Drawing 程序集 (Assembly)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # 建立 GUI 窗体 (Form)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "CSV 行提取工具"      # 窗体标题 (Window Title)
    $form.Size = New-Object System.Drawing.Size(500, 250)
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = New-Object System.Drawing.Size(400, 200)  # 设置最小尺寸

    # 输入文件标签
    $labelInput = New-Object System.Windows.Forms.Label
    $labelInput.Location = New-Object System.Drawing.Point(10, 20)
    $labelInput.Size = New-Object System.Drawing.Size(80, 20)
    $labelInput.Text = "输入文件:"          # “Input File”
    # 锚定于左上角，不随窗体尺寸变化 (Anchor to Top, Left)
    $labelInput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($labelInput)

    # 输入文件文本框
    $textBoxInput = New-Object System.Windows.Forms.TextBox
    $textBoxInput.Location = New-Object System.Drawing.Point(100, 20)
    $textBoxInput.Size = New-Object System.Drawing.Size(280, 20)
    # 锚定于上、左、右，使其宽度随窗体宽度变化 (Anchor to Top, Left, Right)
    $textBoxInput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($textBoxInput)

    # 输入文件浏览按钮
    $buttonBrowseInput = New-Object System.Windows.Forms.Button
    $buttonBrowseInput.Location = New-Object System.Drawing.Point(390, 18)
    $buttonBrowseInput.Size = New-Object System.Drawing.Size(75, 23)
    $buttonBrowseInput.Text = "浏览"          # “Browse”
    # 锚定于上、右 (Anchor to Top, Right)
    $buttonBrowseInput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($buttonBrowseInput)

    # 输出文件标签
    $labelOutput = New-Object System.Windows.Forms.Label
    $labelOutput.Location = New-Object System.Drawing.Point(10, 60)
    $labelOutput.Size = New-Object System.Drawing.Size(80, 20)
    $labelOutput.Text = "输出文件:"          # “Output File”
    $labelOutput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($labelOutput)

    # 输出文件文本框
    $textBoxOutput = New-Object System.Windows.Forms.TextBox
    $textBoxOutput.Location = New-Object System.Drawing.Point(100, 60)
    $textBoxOutput.Size = New-Object System.Drawing.Size(280, 20)
    $textBoxOutput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($textBoxOutput)

    # 输出文件浏览按钮
    $buttonBrowseOutput = New-Object System.Windows.Forms.Button
    $buttonBrowseOutput.Location = New-Object System.Drawing.Point(390, 58)
    $buttonBrowseOutput.Size = New-Object System.Drawing.Size(75, 23)
    $buttonBrowseOutput.Text = "浏览"         # “Browse”
    $buttonBrowseOutput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($buttonBrowseOutput)

    # 起始行号标签
    $labelStartRow = New-Object System.Windows.Forms.Label
    $labelStartRow.Location = New-Object System.Drawing.Point(10, 100)
    $labelStartRow.Size = New-Object System.Drawing.Size(120, 20)
    $labelStartRow.Text = "要截取的起始行号:"         # “Start Row”
    $labelStartRow.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($labelStartRow)

    # 起始行号文本框
    $textBoxStartRow = New-Object System.Windows.Forms.TextBox
    # 将文本框的位置稍作调整，避开标签 (位置 X 值等于标签宽度 + 10)
    $textBoxStartRow.Location = New-Object System.Drawing.Point(130, 110)
    $textBoxStartRow.Size = New-Object System.Drawing.Size(100, 20)
    $textBoxStartRow.Text = "2"             # 默认值
    $textBoxStartRow.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($textBoxStartRow)

    # 执行按钮
    $buttonExecute = New-Object System.Windows.Forms.Button
    $buttonExecute.Location = New-Object System.Drawing.Point(100, 160)
    $buttonExecute.Size = New-Object System.Drawing.Size(75, 23)
    $buttonExecute.Text = "执行"            # “Execute”
    # 锚定于左下角 (Anchor to Bottom, Left)
    $buttonExecute.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($buttonExecute)

    # 退出按钮
    $buttonCancel = New-Object System.Windows.Forms.Button
    $buttonCancel.Location = New-Object System.Drawing.Point(200, 160)
    $buttonCancel.Size = New-Object System.Drawing.Size(75, 23)
    $buttonCancel.Text = "退出"            # “Exit”
    $buttonCancel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($buttonCancel)

    # 为“浏览”输入文件按钮添加事件处理
    $buttonBrowseInput.Add_Click({
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "CSV 文件 (*.csv)|*.csv|所有文件 (*.*)|*.*"
            if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
            {
                $textBoxInput.Text = $openFileDialog.FileName
            }
        })

    # 为“浏览”输出文件按钮添加事件处理
    $buttonBrowseOutput.Add_Click({
            $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveFileDialog.Filter = "CSV 文件 (*.csv)|*.csv|所有文件 (*.*)|*.*"
            if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
            {
                $textBoxOutput.Text = $saveFileDialog.FileName
            }
        })

    # 为“执行”按钮添加事件处理
    $buttonExecute.Add_Click({
            $inputFile = $textBoxInput.Text
            $outputFile = $textBoxOutput.Text
            $startRow = $textBoxStartRow.Text

            # 简单的输入检查
            if ([string]::IsNullOrEmpty($inputFile) -or -not (Test-Path $inputFile))
            {
                [System.Windows.Forms.MessageBox]::Show("请输入有效的输入文件路径！", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            if ([string]::IsNullOrEmpty($outputFile))
            {
                [System.Windows.Forms.MessageBox]::Show("请输入有效的输出文件路径！", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            if (-not [int]::TryParse($startRow, [ref]$null))
            {
                [System.Windows.Forms.MessageBox]::Show("起始行号必须为整数！", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            $startRowInt = [int]$startRow

            try
            {
                Get-CsvTailRows -InputFile $inputFile -OutputFile $outputFile -StartRow $startRowInt
                [System.Windows.Forms.MessageBox]::Show("CSV 提取完成！", "信息", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            catch
            {
                [System.Windows.Forms.MessageBox]::Show("执行过程中发生错误：" + $_.Exception.Message, "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })

    # 为“退出”按钮添加事件处理
    $buttonCancel.Add_Click({
            $form.Close()
        })

    # 显示窗体
    [void]$form.ShowDialog()
}

function Set-CFCredentials
{
    <# 
    .SYNOPSIS
    设置cloudflare API的授权信息(临时地)
    如果要长期有效或者简便起见,可以通过系统界面来设置环境变量
    例如:

    $env:CF_API_TOKEN = "your_api_token"
    或者传统的
    $env:CF_API_KEY = "your_api_key"
    #>
    param (
        [string]$ApiToken,
        [string]$ApiKey,
        [string]$ApiEmail
    )
    
    if ($ApiToken)
    {
        $env:CF_API_TOKEN = $ApiToken
        Write-Output "Cloudflare API Token 已配置"
    }
    elseif ($ApiKey -and $ApiEmail)
    {
        $env:CF_API_KEY = $ApiKey
        $env:CF_API_EMAIL = $ApiEmail
        Write-Output "Cloudflare API Key 和 Email 已配置"
    }
    else
    {
        Write-Error "请提供 API Token 或 API Key + Email"
    }
}
function Get-CFZoneID
{
    <# 
    # todo
    #>
    [CmdletBinding()]
    param (
        [alias("Zone")][string]$Domain, # 要查询的域名
        [string]$Email = $env:CF_API_EMAIL, # Cloudflare 账户 Email
        [string]$APIKey = $env:cf_api_key # Cloudflare 全局 API Key
    )
    $env:CF_API_EMAIL = $env:CF_API_EMAIL
    $env:cf_api_key = $env:cf_api_key
    Write-Verbose "Domain: $Domain" 
    Write-Verbose "Email: $Email" 
    Write-Verbose "APIKey: $APIKey" 
    # 执行 flarectl 命令获取域名列表
    $output = flarectl zone list 
    $output = $output | Out-String
    $zoneRecords = $output -split "`r?`n" | Where-Object { $_.Trim() }
    Write-Verbose "$output"
    # 查找对应的 Zone ID
    $zoneRecord = $zoneRecords | Where-Object { $_ -match $Domain }
    # Write-Host $zoneRecord
    Write-Verbose "[$zoneRecord]"

    $zoneID = $zoneRecord -replace '^\s*(\w+).*', '$1'
    # | ForEach-Object { ($_ -split '\s+')[0] }

    # Write-Verbose "ZoneID: $zoneID"

    # 返回 Zone ID
    if ($zoneID)
    {
        Write-Output $zoneID
    }
    else
    {
        Write-Output "Error: Zone ID for '$Domain' not found!"
    }
}
function Get-CFDnsInfoOfZone
{
    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline = $true)]
        $Domain
    )
    process
    {
        Write-Verbose "processing domain: $Domain"
        $item = flarectl.exe dns list --zone $Domain
        return $item + "`n"
    }
}
function Add-CFZoneDNSRecords
{
    <# 
    .SYNOPSIS
    利用cloudflare API设置域名的DNS记录
    这里通过flarectl命令行工具来操作
    
    默认情况下(不使用额外参数),此命令会尝试从读取到的域名列表添加cloudflare账户中,但是dns不会默认立即添加,除非使用-AddRecordAtOnce参数
    此外,如果你的cloudflare验证了你的账号对dns的所有权,那么你可以利用此函数的-AddRecordOnly参数,添加dns记录到对应的域名解析记录

    .DESCRIPTION
    你需要配置环境变量才能够以简洁的方式使用flarectl命令行工具
    根据授权方式不同,有不同的配置api key/api token
    例如使用传统的api key
    配置两个环境变量:
    CF_API_EMAIL
    CF_API_KEY

    .NOTES
    如果没有安装flarectl工具,请到官网或者github对应项目下载(可执行文件只在个别release中提供,请耐心寻找)
    cloudflare推荐使用新式地api token,而非旧式的api key,因此如果你要使用api key,可能更不容易找到入口
    api key的形式是否被启用,请查看cloudflare的官方文档
    如果没有被弃用,可以参考如下链接到你的cloudflare账号中找到设置入口
    https://dash.cloudflare.com/profile/api-tokens    
    注意,查看global api token的权限,可能会让你输入cloudflare的登录密码(如果你是使用google账号登录的,
    那么可能需要退出登录,回到cloudflare登入页面,输入邮箱(google gmial),然后点击忘记密码,
    这可以让你通过google邮箱来设定/重置你的密码,即便你从未设置过密码)

    默认清空下,函数添加三条A类记录
    #>
    [CmdletBinding()]
    param (
        # 
        $Domains,
        # 使用私人模式DF
        [switch]$Common,
        $Type = 'A' ,
        [alias('IP', 'Content')]
        $Value = $env:DF_SERVER1
        ,
        # $DefaultDNSRecord = $true,
        $RecordNames = @("www", "*"),
        [switch]$No2LDDomain,
        # 考虑到安全性,分为两个步骤(添加域名,然后你更该域名供应商管理面板更新dns,最后回到cloudflare进行域名的dns记录(ip解析)添加)
        # 第一遍运行不带下面参数的命令;第二遍运行带$AddRecordAtOnce参数的命令

        # 添加完域名后,是否立即添加对应的DNS记录(默认不添加)
        [switch]$AddRecordAtOnce,
        # 仅添加域名的DNS记录,不检查域名是否被添加(如果域名尚未被添加到cloudflare,那么添加dns记录就会失败跳过)
        [switch]$AddRecordOnly
    )
   
    if(Test-Path $Domains)
    {
        $Domains = Get-Content $Domains -Raw
    }
    if(!$Common)
    {
        Write-Host "Mode:$DF"
        $res = Get-DomainUserDictFromTable -Table $Domains
        $Domains = $res | ForEach-Object { $_.Domain }
    }
    Write-Host "Domains: $Domains"
    Pause
    $Domains | ForEach-Object {
     
        $domain = $_.ToLower()
        if(!$AddRecordOnly)
        {

            Write-Verbose "尝试创建域名[$domain] (如果不存在的话)..."
            flarectl zone create --zone "$domain" *> $null # 创建域名
        }
        
        Write-Verbose "Setting DNS record for domain: $domain" 
        if ($type -eq "MX")
        {
            # 比较少用
            $priority = $record
            Write-Output "Adding MX record: $domain -> $value (Priority: $priority)"
            flarectl dns create --zone "$domain" --name "$domain" --type "$type" --content "$value" --priority "$priority"
        }
        else
        {
            if($AddRecordAtOnce -or $AddRecordOnly)
            {

                # 常用类型
                # 一次性添加两条:一条*和$domain;记得启用代理选项保护ip
                if(!$No2LDDomain)
                {
                    $RecordNamesForIt = $RecordNames.clone()
                    $RecordNamesForIt += $domain
                }
                
                $RecordNamesForIt | ForEach-Object {
                    Write-Host "Adding DNS record: $domain|$_ -> $value ($type)"
                    flarectl dns create --zone "$domain" --name $_ --type "$type" --content "$value" --proxy
                }
                
                # Pause
                # flarectl dns create --zone "$domain" --name "*" --type "$type" --content "$value"
            }
        }
    }

}
function Add-CFZoneConfig
{
    <# 
    .SYNOPSIS
    利用cloudflare API配置cloudflare账户(包括ssl加密方式(灵活)等并且配置邮箱转发和安全选项启用)
    #>
    param(

    )
    python $pys/cf_config_api.py configure
}
function Add-CFZoneCheckActivation
{
    <# 
    .SYNOPSIS
    利用请求cf检查域名的激活状态
    .Description
    核心步骤是调用flarectl 命令行工具来执行检查
    具体的命令为:
    flarectl zone check --zone <domain>
    但是这个命令在运行过程中可能会报错,但是实际测试下来应该是有效果,所以不用管这些错误,用将该命令的输出重定向到$null,也就是不管输出
    而为了查看执行进度,使用write-host来输出域名,这样可以看到执行的进度
    #>
    [CmdletBinding()]
    param (
        $Table = "$desktop/table.conf"   
    )
    Get-Content $Table | ForEach-Object { ($_ -split '\s+')[0] | Get-MainDomain } | ForEach-Object { flarectl zone check --zone $_ *> $null; Write-Host $_ }
}
function Get-CFZoneInfoFromTable
{
    <# 
    .SYNOPSIS
    查询cloudflare中的域名信息
    从表格中获取域名列表,并获取对应的域名,从而获取相应的信息,比如激活状态等
    #>
    [CmdletBinding()]
    param(
        [alias('Domain')]$Table = "$home/desktop/table.conf"
    )
    Write-Host $Table
    $info = Get-DomainUserDictFromTable -Table $Table 
    $info | ForEach-Object { $_.domain } | ForEach-Object { flarectl zone info $_ }
}
function Get-CFDNSDomains
{
    <# 
    .SYNOPSIS
    查询cloudflare中的域名信息,获取当前账号分配的DNS服务器的域名,用来替换域名供应商的域名服务器
    
    #>
    param (
        
    )
    
}
function Export-NewCSVFile
{
    param (

        # [parameter(parametersetname = "SKU")]
        $StoppedSku = $StoppedSku,
 
        # 默认sku的对齐位数为7位数(不够的前头补零)
        $DigitBits = 7,
        $CsvDirectory,
        $OutputDirectory
    )
    # $StoppedSku = $StoppedSku -replace '.*?(0.*\d+).*', '$1' #从sk...U提取出数字(整数),例如45316
    $StoppedSku = $StoppedSku -replace '.*?(\d+).*', '$1' #从SK...U提取出数字(整数),例如45316
    Write-Verbose $StoppedSku -Verbose
    $StoppedSku = "{0:D$DigitBits}" -f [int]$StoppedSku #补齐位数到$DigitBits位数
    Write-Verbose "StoppedSku: $StoppedSku" -Verbose
    # # 开始处理
    $p_num = [int]($StoppedSku.Substring(0, 3)) + 1 #第几个文件出现断点,如果是分割为1000每条记录,则是SubString(0,2)
    $start_row = [int]($StoppedSku.Substring(3)) #开始分割的所在行号

    Write-Verbose "start_row: $start_row" -Verbose
    $p_name = "p$($p_num)"
    
    # 需要被截取的文件名字例如,假设你的文件名字类似于_pro_p5.csv; 
    $filename = "${Prefix}${p_name}.csv" 
    $inputfile = "$CsvDirectory\$filename".trim('\')  
    Test-Path $inputfile -PathType Leaf -ErrorAction Stop #检查文件是否存在
    Write-Host "Processing csv file: $inputfile"
    Write-Verbose "Number of spilting position:$start_row" -Verbose
    # $filename = ".\${p_name}.csv" # 简化方案:# ".\${p_name}.csv"
    
    Get-CsvTailRows -InputFile $inputfile -OutputFile "$OutputDirectory\${p_name}_${StoppedSku}+.csv" -StartRow $start_row -ShowInExplorer:$ShowInExplorer

    Write-Host "$("`n"*3)"
}
function Export-CsvSplitFiles
{
    <# 
    .SYNOPSIS
    将 CSV 文件平均分割成多个较小的 CSV 文件，如果无法平均，则余数放到最后一个文件中。

    .PARAMETER InputFile
    需要分割的 CSV 文件路径。

    .PARAMETER OutputDirectory
    输出分割后 CSV 文件的目录。

    .PARAMETER Numbers
    需要分割的文件数量（默认为 10）。

    .EXAMPLE
    Export-CsvSplitFiles -InputFile "C:\data\largefile.csv" -OutputDirectory "C:\data\split" -Numbers 5

    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        # [Parameter(Mandatory = $true)]
        [string]$OutputDirectory = "",

        [int]$Numbers = 10
    )
    if ($OutputDirectory -eq "")
    {
        $OutputDirectory = Split-Path $InputFile
    }

    # 确保输入文件存在
    if (-not (Test-Path $InputFile))
    {
        Write-Error "输入文件 $InputFile 不存在。"
        return
    }

    # 确保输出目录存在
    if (-not (Test-Path $OutputDirectory))
    {
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    }

    # 读取 CSV 文件
    $data = Import-Csv -Path $InputFile
    $totalRows = $data.Count

    if ($totalRows -eq 0)
    {
        Write-Error "CSV 文件没有数据。"
        return
    }

    # 计算每个文件应包含的行数
    $rowsPerFile = [math]::Ceiling($totalRows / $Numbers)

    # 分割数据并写入文件
    for ($i = 0; $i -lt $Numbers; $i++)
    {
        $start = $i * $rowsPerFile
        if ($start -ge $totalRows)
        {
            break
        }

        $end = [math]::Min($start + $rowsPerFile, $totalRows)
        $splitData = $data[$start..($end - 1)]

        # 生成文件名
        $fileBaseName = Split-Path $InputFile -LeafBase
        Write-Host $fileBaseName

        $outputFile = Join-Path -Path $OutputDirectory -ChildPath ("${fileBaseName}_split_{0}_$($start+1)-$end.csv" -f ($i + 1))

        # 导出 CSV
        $splitData | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

        Write-Host "已生成文件: $outputFile"
    }

    Write-Host "CSV 文件分割完成，输出目录: $OutputDirectory"
}

function Export-NewCSVFilesFromSKU
{
    <# 
    .DESCRIPTION
    # 以每分csv文件10000行记录为单位分割文件为例
    # 假设你发现断点为SK0045316-U ,那么你就将这个字符串中的数字45316记住或复制出来,或者直接粘贴这个SK0045316-U这个字符串也行,粘贴到以下变量中

    .PARAMETER StoppedSku
    #几万数据量
    $StoppedSku = "SK0045316-U" ,
    #十几万数据量
    $StoppedSku="SK0147823-U" 

    .PARAMETER CsvDirectory
    # csv目录的填写可选(填写csv文件所在目录,如果你运行脚本所在工作目录就是命令行工作目录,则不需要填写,否则请填写
    # 例如"C:\Users\Administrator\Downloads\pro_csv\fr1\outinfo")
    # $CsvDirectory = "C:\Users\Administrator\Downloads\pro_csv\fr1\outinfo"
    # $CsvDirectory = "C:\Users\Administrator\Downloads\pro_csv\outinfo"

    .Example

    #>
    <# 


    #>
    [cmdletbinding()]
    param(
        # $StoppedSku_list = @( "" ) ,
        #支持配置多个批处理,比如:"SK0049823-U, SK0019823-U, SK0029823-U"
        # $StoppedSku = "", 
        [String[]]$StoppedSku = @"
SK0006953-U
SK0016921-U
SK0027225-U
SK0037182-U
SK0045216-U
SK0053924-U
    
"@
        ,
        $CsvDirectory = "C:\Users\Administrator\Downloads\pro_csv\outinfo" ,
        # $Prefix = "_pro_",
        #简化后可以置为空串""
        $Prefix = "",
        $OutputDirectory = $CsvDirectory,
        [switch]$ShowInExplorer
    )

    #无论用户输入的是逗号分割的字符串,还是本身就是一个数组,都转化为数组统一处理
    # 然后转为字符串输出以便使用-replace等方法提取sku
    $StoppedSku = @($StoppedSku) -join ','
    Write-Host "StoppedSkuString: $StoppedSku"
    $StoppedSku_list = $StoppedSku.trim() -replace ',', "`n" -replace ' ', ""
    # Write-Host "[$StoppedSku_list]"
    foreach ($sku in $StoppedSku_list)
    {
        Write-Host "((`n$sku`n))"
    }
    $StoppedSku_list = -split $StoppedSku_list 
    # Write-Host "[$StoppedSku_list]"
    
    # return $StoppedSku_list
    foreach ($sku in $StoppedSku_list)
    {
        Write-Host "[[$sku]]"
        Export-NewCSVFile -StoppedSku $sku -OutputDirectory $OutputDirectory -CsvDirectory $CsvDirectory 
    }
    
    Pause 
}
function Export-NewCSvFromRange
{
    <#
    .SYNOPSIS
    从CSV文件中截取中间片段(第m行到第n行),将选中的区间保存为新文件。

    .DESCRIPTION
    该函数允许用户从指定的CSV文件中截取一段数据（从第m行到第n行），并将截取的数据保存为一个新的CSV文件。
    默认情况下，截取操作是左闭右开的（即包含起始行，但不包含结束行）。可以通过-IncludeEnd参数来改变为闭区间（即包含起始行和结束行）。
    如果仅提供 StartRow 参数，则返回从 StartRow 到文件末尾的所有行。

    .PARAMETER Path
    指定要处理的CSV文件的路径。

    .PARAMETER StartRow
    指定截取的起始行号（从0开始计数）。

    .PARAMETER EndRow
    指定截取的结束行号（从0开始计数）。如果未提供，则默认截取到文件末尾。

    .PARAMETER IncludeEnd
    如果指定此参数，截取操作将包含结束行（闭区间）。默认情况下，不包含结束行（左闭右开）。

    .PARAMETER Output
    指定新CSV文件的输出路径。如果未指定，则使用默认路径。

    .EXAMPLE
    Export-NewCSvFromRange -Path "data.csv" -StartRow 10 -EndRow 20
    从"data.csv"文件中截取第10行到第19行（不包括第20行），并将结果保存为新的CSV文件。

    .EXAMPLE
    Export-NewCSvFromRange -Path "data.csv" -StartRow 10 -EndRow 20 -IncludeEnd
    从"data.csv"文件中截取第10行到第20行（包括第20行），并将结果保存为新的CSV文件。

    .EXAMPLE
    Export-NewCSvFromRange -Path "data.csv" -StartRow 10
    从"data.csv"文件中截取第10行到文件末尾，并将结果保存为新的CSV文件。


    #>
    [CmdletBinding(DefaultParameterSetName = 'Range')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(parameterSetName = 'StartToEnd')]
        [int]$StartRow,

        [Parameter(parameterSetName = 'StartToEnd')]
        [int]$EndRow = "",
        [parameter(ParameterSetName = 'Range')]
        $Range,

        [string]$Output = ""
    )

    # 检查输入文件是否存在
    if (-not (Test-Path -Path $Path))
    {
        Write-Error "文件不存在: $Path"
        return
    }

    # 导入CSV文件
    try
    {
        $csv = Import-Csv -Path $Path
    }
    catch
    {
        Write-Error "无法导入CSV文件: $_"
        return
    }

    # 获取总行数(不包括表头行)
    $totalRows = $csv.Count
    if($PSCmdlet.ParameterSetName -eq 'Range')
    {

        $range = @($Range)
        Write-Warning $range.Count
        # Write-Host "[$($range[0])]"
        if($range.Count -eq 2)
        {
            $StartRow = $range[0]
            $EndRow = $range[1]
        }
        elseif($range.Count -eq 1)
        {
            $StartRow = $range[0]
        }
    }
    
    # Write-Verbose $Range.GetEnumerator() 
    Write-Verbose "startRow: $StartRow, endRow: $EndRow"
    # 验证 StartRow 是否合法
    if ($StartRow -lt 1 -or $StartRow -gt $totalRows)
    {
        Write-Error "StartRow 超出范围。文件[$Path]行数限制:有效范围为 1 到 $($totalRows)"
        return
    }

    # 如果未提供 EndRow，则设置为最后一行
    # if (-not $PSBoundParameters.ContainsKey('EndRow'))
    if(!$Endrow)
    {
        $EndRow = $totalRows
    }
    else
    {
        # 验证 EndRow 是否合法
        if ($EndRow -lt $StartRow -or $EndRow -gt $totalRows)
        {
            Write-Error "EndRow 超出范围或小于 StartRow。有效范围为 $StartRow 到 $($totalRows)"
            return
        }
    }
    # 计算实际索引范围
    $StartIndex = $StartRow - 1
    $EndIndex = $EndRow - 1

    # $EndIndex = [math]::Min($EndIndex, $totalRows - 1)

    # 截取指定范围的行
    $selectedRows = $csv[$StartIndex..$EndIndex]

    # 获取表头
    try
    {
        $headerLine = Get-Content -Path $Path -Encoding UTF8 -TotalCount 1
        Write-Verbose $headerLine
    }
    catch
    {
        Write-Error "读取表头失败: $_"
        return
    }

    # 如果未指定输出文件路径，生成默认路径
    if (-not $Output)
    {
        Write-Verbose "未指定输出文件路径，使用默认路径。"
        
        $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $outputDirectory = Split-Path -Path $Path
        Write-Verbose "OutputDirectory: $outputDirectory"

        $Output = Join-Path -Path $outputDirectory -ChildPath "${fileBaseName}_${StartRow}-${EndRow}.csv"
        $fullPath = [System.IO.Path]::GetFullPath( $Output)
        Write-Verbose "Output: [$fullPath]"
    }

    # 写入新文件
    try
    {
        # 写入表头
        Set-Content -Path $Output -Value $headerLine -Encoding UTF8 -Force
        # Pause
        # 写入选定的行
        if ($selectedRows.Count -gt 0)
        {
            $selectedRows | Export-Csv -Path $Output -Append -Force -NoTypeInformation -Encoding UTF8
        }
    }
    catch
    {
        Write-Error "写入文件失败: $_"
        return
    }
    Get-CsvPreview $selectedRows

    Write-Output "新的CSV文件已保存到: [$fullPath]"
}

function Get-CsvRowsByPercentage
{
    <#
.SYNOPSIS
    提取CSV文件的表头和从指定百分比位置到最后一行的数据，并将其保存到指定输出文件中。

.DESCRIPTION
    该脚本读取输入的CSV文件，提取表头（第一行）和指定百分比位置到最后一行的数据，
    然后将提取的内容保存到指定的输出文件中。

.PARAMETER InputFile
    输入的CSV文件路径。

.PARAMETER OutputFile
    输出的CSV文件路径。

.PARAMETER StartPercentage
    提取数据开始的百分比，例如 80 表示提取最后 20% 的数据。

.EXAMPLE
    .\Extract-CsvRows.ps1 -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartPercentage 80
    从`C:\path\to\input.csv`文件中提取表头和最后20%的数据，并将其保存到`C:\path\to\output.csv`。

.NOTES
    - 文件使用UTF-8编码进行读写。
    - 百分比值应在 0-100 之间。
#>

    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile, # 输入的CSV文件路径

        # [Parameter(Mandatory=$true)]
        [string]$OutputFile, # 输出的CSV文件路径

        [Parameter(Mandatory = $true)]
        [int]$StartPercentage   # 提取开始的百分比位置 (0-100)
    )

    # 验证百分比范围
    if ($StartPercentage -lt 0 -or $StartPercentage -gt 100)
    {
        Write-Error "StartPercentage 必须在 0 到 100 之间。"
        return
    }

    # 读取CSV文件
    try
    {
        $data = Import-Csv -Path $InputFile
    }
    catch
    {
        Write-Error "读取CSV文件失败: $_"
        return
    }

    # 获取总行数
    $totalRows = $data.Count

    if ($totalRows -eq 0)
    {
        Write-Error "输入文件没有数据。"
        return
    }

    # 计算起始行号
    $startRow = [math]::Ceiling($totalRows * ($StartPercentage / 100.0))

    # 提取表头行
    $header = $data | Select-Object -First 0

    # 提取从起始行到最后一行的数据
    $rows = $data | Select-Object -Skip ($startRow - 1)

    # 保存表头行和提取的行到新的输出文件
    try
    {
        # 输出表头行
        $header | Export-Csv -Path $OutputFile -NoTypeInformation -Force
        # 输出提取的数据行
        $rows | Export-Csv -Path $OutputFile -NoTypeInformation -Append -Force
    }
    catch
    {
        Write-Error "保存CSV文件失败: $_"
    }

    Write-Host "处理完成，结果已保存到: $OutputFile"
}

# 调用示例
# Extract-CsvRows -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartPercentage 80

# 调用示例
# Extract-CsvRows -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartRow 5
function Set-OpenWithVscode
{
    <# 
    .SYNOPSIS
    设置 VSCode 打开方式为默认打开方式。
    .DESCRIPTION
    直接使用powershell的命令不是很方便
    这里通过创建一个临时的reg文件,然后调用reg import命令导入
    支持添加右键菜单open with vscode 
    也支持移除open with vscode 菜单
    你可以根据喜好设置标题,比如open with Vscode 或者其他,open with code之类的名字
    .EXAMPLE
    简单默认参数配置
    Set-OpenWithVscode

    .EXAMPLE
    完整的参数配置
    Set-OpenWithVscode -Path "C:\Program Files\Microsoft VS Code\Code.exe" -MenuName "Open with VsCode"
    .EXAMPLE
    移除右键vscode菜单
    PS> Set-OpenWithVscode -Remove
    #>
    <# 
    .NOTES
    也可以按照如下格式创建vscode.reg文件，然后导入注册表

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\*\shell\VSCode]
    @=$MenuName
    "Icon"="C:\\Program Files\\Microsoft VS Code\\Code.exe"

    [HKEY_CLASSES_ROOT\*\shell\VSCode\command]
    @="$PathWrapped \"%1\""

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\Directory\shell\VSCode]
    @=$MenuName
    "Icon"="C:\\Program Files\\Microsoft VS Code\\Code.exe"

    [HKEY_CLASSES_ROOT\Directory\shell\VSCode\command]
    @="$PathWrapped \"%V\""

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode]
    @=$MenuName
    "Icon"="C:\\Program Files\\Microsoft VS Code\\Code.exe"

    [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode\command]
    @="$PathWrapped \"%V\""

    #>

    [CmdletBinding(DefaultParameterSetName = "Add")]
    param (
        [parameter(ParameterSetName = "Add")]
        $Path = "C:\Program Files\Microsoft VS Code\Code.exe",
        [parameter(ParameterSetName = "Add")]
        $MenuName = "Open with VsCode",
        [parameter(ParameterSetName = "Remove")]
        [switch]$Remove
    )
    Write-Verbose "Set [$Path] as Vscode Path(default installation path)" -Verbose
    # 定义 VSCode 安装路径
    #debug
    # $Path = "C:\Program Files\Microsoft VS Code\Code.exe"
    $PathForWindows = ($Path -replace '\\', "\\")
    $PathWrapped = '\"' + $PathForWindows + '\"' # 由于reg添加右键打开的规范,需要得到形如此的串 \"C:\\Program Files\\Microsoft VS Code\\Code.exe\"
    $MenuName = '"' + $MenuName + '"' # 去除空格

    # 将注册表内容作为多行字符串保存
    $AddMenuRegContent = @"
    Windows Registry Editor Version 5.00
   
       [HKEY_CLASSES_ROOT\*\shell\VSCode]
       @=$MenuName
       "Icon"="$PathForWindows" 
   
       [HKEY_CLASSES_ROOT\*\shell\VSCode\command]
       @="$PathWrapped \"%1\""
   
       Windows Registry Editor Version 5.00
   
       [HKEY_CLASSES_ROOT\Directory\shell\VSCode]
       @=$MenuName
       "Icon"="$PathForWindows" 
   
       [HKEY_CLASSES_ROOT\Directory\shell\VSCode\command]
       @="$PathWrapped \"%V\""
   
       Windows Registry Editor Version 5.00
   
       [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode]
       @=$MenuName
       "Icon"="$PathForWindows" 
   
       [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode\command]
       @="$PathWrapped \"%V\""
"@  
    $RemoveMenuRegContent = @"
    Windows Registry Editor Version 5.00

[-HKEY_CLASSES_ROOT\*\shell\VSCode]

[-HKEY_CLASSES_ROOT\*\shell\VSCode\command]

[-HKEY_CLASSES_ROOT\Directory\shell\VSCode]

[-HKEY_CLASSES_ROOT\Directory\shell\VSCode\command]

[-HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode]

[-HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode\command]
"@
    $regContent = $AddMenuRegContent
    # if ($Remove)
    if ($PSCmdlet.ParameterSetName -eq "Remove")
    {
        # 执行 reg delete 命令删除注册表文件
        Write-Verbose "Removing VSCode context menu entries..."
        $regContent = $RemoveMenuRegContent

    }
    # 检查 VSCode 是否安装在指定路径
    elseif (Test-Path $Path)
    {
          
        Write-Verbose "The specified VSCode path exists. Proceeding with registry creation."
    }
    else
    {
        Write-Host "The specified VSCode path does not exist. Please check the path."
        Write-Host "use -Path to specify the path of VSCode installation."
    }

    Write-Host "Creating registry entries for VSCode:"
    
    
    # 创建临时 .reg 文件路径
    $tempRegFile = [System.IO.Path]::Combine($env:TEMP, "vs-code-context-menu.reg")
    # 将注册表内容写入临时 .reg 文件
    $regContent | Set-Content -Path $tempRegFile
    
    # Write-Host $AddMenuRegContent
    Get-Content $tempRegFile
    # 删除临时 .reg 文件
    # Remove-Item -Path $tempRegFile -Force

    # 执行 reg import 命令导入注册表文件
    try
    {
        reg import $tempRegFile
        Write-Host "Registry entries for VSCode have been successfully created."
    }
    catch
    {
        Write-Host "An error occurred while importing the registry file."
    }
    Write-Host "Completed.Refresh Explorer to see changes."
}

function Get-LineDataFromMultilineString
{
    <# 
    .SYNOPSIS
    将多行字符串按行分割，并返回数组
    对于数组输入也可以处理
    .EXAMPLE
    Get-LineDataFromMultilineString -Data @"
    line1
    line2
    "@

    #>
    [cmdletbinding(DefaultParameterSetName = "Trim")]
    param (
        $Data,
        [parameter(ParameterSetName = "Trim")]
        $TrimPattern = "",
        [parameter(ParameterSetName = "NoTrim")]
        [switch]$KeepLine
    )
    # 统一成字符串处理
    $Data = @($Data) -join "`n"

    $lines = $Data -split "`r?`n|," 
    if(!$KeepLine)
    {
        $lines = $lines | ForEach-Object { $_.trim($TrimPattern) }
    }
    return $lines
    
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
function Get-DictView
{
    <# 
    .SYNOPSIS
    以友好的方式查看字典的取值或字典数组中每个字典的取值
    .EXAMPLE
    $array = @(
        @{ Name = "Alice"; Age = 25; City = "New York" },
        @{ Name = "Bob"; Age = 30; City = "Los Angeles" },
        @{ Name = "Charlie"; Age = 35; City = "Chicago" }
    )

    Get-DictView -Dicts $array

    #>
    param (
        [alias("Dict")]$Dicts
    )
    Write-Host $Dicts
    # $Dicts.Gettype()
    # $Dicts.Count
    # $Dicts | Get-TypeCxxu
    $i = 1
    foreach ($dict in @($Dicts))
    {
        Write-Host "----- Dictionary$($i++) -----"
        # Write-Output $dict
        # 遍历哈希表的键值对
        foreach ($key in $dict.Keys)
        {
            Write-Host "$key : $($dict[$key])"
        }
        Write-Host "----- End of Dictionary$($i-1) -----`n"
    }
}
function Get-DomainUserDictFromTable
{
    <# 
    .SYNOPSIS
    解析从 Excel 粘贴的 "域名" "用户名" 简表，并根据提供的字典翻译用户名。

    .NOTES
    示例字典：
    $SiteOwnersDict = @{
        "郑" = "zw"
        "李" = "lyz"
    }

    示例输入：
    $Table = @"
    www.d1.com    郑
    www.d2.com    李

    "@

    示例输出：
    @{
        Domain = "www.d1.com"
        User   = "zw"
    },
    @{
        Domain = "www.d2.com"
        User   = "lyz"
    }
    #>
    [CmdletBinding()]
    param(
        # 包含域名和用户名的多行字符串
        [Alias("DomainLines")]
        # 检查输入的参数是否为文件路径,如果是尝试解析,否则视为多行字符串表格输入
        [string]$Table = @"
www.d1.com    郑
www.d2.com    李

"@,
        [ValidateSet("Auto", "FromFile", "MultiLineString")]
        $TableMode = 'Auto',
        # 表结构，默认是 "域名,用户名"
        $Structure = $SiteOwnersDict.DFTableStructure,

        # 用户名转换字典
        $SiteOwnersDict = $siteOwnersDict
    )
    if (!$SiteOwnersDict )
    {
        Write-Warning "用户名转换字典缺失"
        
    }
    else
    {
        Write-Host "$SiteOwnersDict"
        # 谨慎使用write-output和孤立表达式,他们会在函数结束时加入返回值一起返回,导致不符合预期的情况
        #检查siteOwnersDict
        Write-Verbose "SiteOwnersDict:"
        # $dictParis = $SiteOwnersDict.GetEnumerator()
    }
    if($VerbosePreference)
    {

        Get-DictView -Dicts $SiteOwnersDict
    }


    # 解析表头结构
    $columns = $Structure -split ','
    $structureFieldsNumber = $columns.Count
    Write-Debug "structureFieldsNumber:[$structureFieldsNumber]"

    # 解析行数据
    if($TableMode -in @('Auto', 'FromFile') -and (Test-Path $Table))
    {
        Write-Host "Try parse table from file:[$Table]" -ForegroundColor Cyan
        $Table = Get-Content $Table -Raw
    }
    else
    {
        # 读取多行字符串表格
        Write-Host "parsing table from multiline string" -ForegroundColor Cyan
        Write-Warning "If the lines are not separated by comma,space,semicolon,etc,it may not work correctly! check it carefully "

    }


    # $Table = $Table -replace '(?:https?:\/\/)?(?:www\.)?([a-zA-Z0-9-]+(?:\.[a-zA-Z]{2,})+)', '$1 '
    $Table = $Table -replace '\b(?:https?:\/\/)?([\w.-]+\.[a-zA-Z]{2,})(?:\/|\s|$)', '$1 '
    
    Write-Verbose "`n$Table" 
    # 按换行符拆分,并且过滤掉空行
    $lines = $Table -split "`r?`n" | Where-Object { $_ -match "\S" -and $_ -notmatch "^\s*#" }
    Write-Verbose "valid line number: $($lines.Count)"

    # 尝试数据分隔处理(尤其是针对行内没有空格的情况,这里尝试为其添加分隔符)
    $lines = $lines -replace '([\u4e00-\u9fa5]+)', ' $1 ' -replace '(Override|Lazy)', ' $1 '
    # 根据常用的分隔符将行内划分为多段
    $lines = @($lines)
    Write-Verbose "Query the the number of line parts with the max parts..."
    $maxLinePartsNumber = 0
    foreach ($line in $lines)
    {
        Write-Debug "line:[$line]"

        $linePartsNumber = ($line -split "\s+|,|;" | Where-Object { $_ }).Count
        Write-Debug "number of line parts: $($linePartsNumber)"
        if ($linePartsNumber -gt $maxLinePartsNumber)
        {
            $maxLinePartsNumber = $linePartsNumber
        }
        
    }

    Write-Verbose "Query result:$maxLinePartsNumber"

    $fieldsNumber = [Math]::Min($structureFieldsNumber, $maxLinePartsNumber)
    Write-Verbose "The number of fields of the dicts will be generated is: $fieldsNumber"
    $result = [System.Collections.ArrayList]@()

    foreach ($line in $lines)
    {
        # 拆分每一行（假设使用制表符或多个空格分隔）
        $parts = $line.Trim() -split "\s+"
        # $parts = $line.Trim()

        # if ($parts.Count -ne $structureFieldsNumber)
        # {
        #     Write-Warning "$line does not match the expected structure:[$structure],pass it,Check it!"
        #     continue
        # }
        $entry = @{}
        # 构造哈希表
        for ($i = 0; $i -lt $fieldsNumber; $i++)
        {
            Write-Verbose $columns[$i]
            if($columns[$i] -eq "User")
            {
                # Write-Verbose
                $UserName = $parts[$i]
                $NameAbbr = $SiteOwnersDict[$parts[$i]]
                Write-Verbose "Try translate user: $UserName=> $NameAbbr"
                if($NameAbbr)
                {

                    $parts[$i] = $NameAbbr
                }
                else
                {
                    Write-Error "Translate user name [$UserName] failed,please check the dictionary"
                    Pause
                    exit
                }
            }
            $entry[$columns[$i]] = $parts[$i]
        }
        # 查看当前行生成的字典
        # $DictKeyValuePairs = $entry.GetEnumerator() 
        # Write-Verbose "dict:$DictKeyValuePairs"
        # $entry = @{
        #     $columns[0] = $parts[0]
        #     $columns[1] = $SiteOwnersDict[$parts[1]] ?? $parts[1]  # 如果字典里没有，就保留原用户名
        # }

        # 当前字典插入到数组中
        # $result += $entry
        $result.Add($entry) >$null
    }
    Write-Verbose "$($result.Count) dicts was generated."
    
    # Get-DictView $result

    return $result
}



function Get-BatchSiteBuilderLines
{
    <# 
    .SYNOPSIS
    获取批量站点生成器的生成命令行(宝塔面板专用)
    
    仅处理单个用户的站点,如果要处理多个用户,请在外部调用此函数并做额外处理

    功能比较基础,暂时只接收域名列表(字符串),不处理专门格式的输入数据,否则会导致错误解析

    .DESCRIPTION
    格式说明
    批量格式：域名|根目录|FTP|数据库|PHP版本
    
    案例： bt.cn,test.cn:8081|/www/wwwroot/bt.cn|1|1|56


    最简单的站点:
    域名|1|0|0|0

    1.   域名参数：多个域名用 , 分割
    2.   根目录参数：填写 1 为自动创建，或输入具体目录
    3.   FTP参数：填写 1 为自动创建，填写 0 为不创建
    4.   数据库参数：填写 1 为自动创建，填写 0 为不创建
    5.   PHP版本参数：填写 0 为静态，或输入PHP具体版本号列如：56、71、74

    如需添加多个站点，请换行填写

    .NOTES
    domain1.com
    domain2.com
    domain3.com

    #>
    <# 
    .EXAMPLE
    #测试命令行

Get-BatchSiteBuilderLines  -user zw -Domains @"
            domain1.com
            domain2.com
            domain3.com
"@
#回车执行

    .EXAMPLE
    单行字符串内用逗号分割域名,生成批量建站语句
    PS> Get-BatchSiteBuilderLines -user zw "a.com,b.com"
    a.com,*.a.com   |/www/wwwroot/zw/a.com  |0|0|84
    b.com,*.b.com   |/www/wwwroot/zw/b.com  |0|0|84
    .EXAMPLE
    命令行中输入域名字符串构成的数组作为-Domains参数值;
    使用 SiteRoot参数来指明网站根目录(域名目录下的子目录,根据需要指定或不指定)
    在命令行中,字符串数组中的字符串可以不用引号包裹,而且数组也可以不用@()来包裹(如果要用@()包裹字符串,那么反而需要你对每个数组元素用引号包裹)
    PS> Get-BatchSiteBuilderLines -Domains a.com,b.com -SiteRoot wordpress
    a.com,*.a.com   |/www/wwwroot/a.com/wordpress   |0|0|74
    b.com,*.b.com   |/www/wwwroot/b.com/wordpress   |0|0|74

    .EXAMPLE
    使用@()数组作为Domains的参数值,这时候要为每个字符串用引号包裹,否则会报错
    PS> Get-BatchSiteBuilderLines -user zw @(
    >> 'a.com'
    >> 'b.com')
    a.com,*.a.com   |/www/wwwroot/zw/a.com  |0|0|84
    b.com,*.b.com   |/www/wwwroot/zw/b.com  |0|0|84

    #> 
    [CmdletBinding()]
    param (
        # 使用多行字符串,相比于直接使用字符串,在脚本中可以省略去引号的书写
        [Alias("Domain")]$Domains = @"
domain1.com
www.domain2.com
"@,
        $Table = "",
        #网站根目录,例如 wordpress 
        $SiteRoot = "",
        [switch]$SingleDomainMode,
        # 三级域名,默认为`*`,常见的还有`www`
        $LD3 = "*,www"    ,
        [Alias("SiteOwner")]$User,
        # php版本,默认为74(兼容一些老的php插件)
        $php = 74
    )

    $domains = @($domains) -join "`n"

    # 统一成字符串处理
    $domains = $domains.trim() -split "`r?`n|," | Where-Object { $_.Length }
    $lines = [System.Collections.ArrayList]@()

    # $domains = $domains -replace "`r?`n", ";"
    # $domains = $domains -replace "`n", ";"

    # Write-Verbose $domains
    Write-Verbose "$($domains.Length)" 

    foreach ($domain in $domains)
    {
        Write-Verbose "[$domain]"
        $domain = $domain.Trim() -replace 'www\.', ""
        # 注意trimEnd('/')而不是trim('/')开头的`/`是linux根目录,要保留的!
        $site = "/www/wwwroot/$user/$domain/$siteRoot".TrimEnd('/') 
        $ld3domain = $LD3 -split "," 
        Write-Verbose "ld3domain:[$ld3domain]"
        $ld3domain = $ld3domain | ForEach-Object { "$_.$domain" } 
        $ld3domain = $ld3domain -join ","
        $line = "$domain,$ld3domain`t|$site `t|0|0|$php" -replace "//", "/" 
       
        $line = $line.Trim() 
        Write-Verbose $line 
        $lines.Add($line) > $null
    }

    # $lines | Set-Clipboard
    # Write-Host "`nlines copied to clipboard!" -ForegroundColor Cyan
    return $lines
}

function Get-BatchSiteDBCreateLines
{
    <# 
    .SYNOPSIS
    获取批量站点数据库创建命令行
    .DESCRIPTION
    默认生成两种命令行,一种是可以直接在shell中执行,另一种是保存到sql文件中,最后调用mysql命令行来执行
    第一种使用起来简单,但是开销大,而且构造语句的过程中相对比较麻烦,需要考虑powershell对特殊字符的解释
    第二种命令简短,而且符号包裹更少,运行开销较小,理论上比第一种快;但是powershell对于mysql命令行执行
    sql文件也相对麻烦,需要用一些技巧

    #>
    [CmdletBinding()]
    param (
        [Alias("Domain")]$Domains = @"
domain1.com
domain2.com
"@,
        # 指明网站的创建或归属者,涉及到网站数据库名字和网站根目录的区分
        [Alias("SiteOwner")]$User,
        # 单域名模式:每次调用此函数指输入一个配置行(一个站点的配置信息);
        # 适合与Start-BatchSiteBuilderLine-DF的Table参数配合使用
        [switch]$SingleDomainMode,
        #可以配置系统环境变量 df_server,可以是ip或域名
        $Server = $env:DF_SERVER1, 
        # 对于wordpress,一般使用utf8mb4_general_ci
        $collate = 'utf8mb4_general_ci',
        $MySqlUser = "root",

        # 置空表示不输出sql文件(如果不想要生成sql文件，请指定此参数并传入一个空字符串""作为参数)
        # 在非单行模式(SingleDomainMode)下,默认生成的sql文件名为 BatchSiteDBCreate-[User].sql
        # 否则$User参数生成的SqlFile里的语句可能包含多个用户名,建议手动指定文件路径参数,
        # 而且文件名应该更有概括性,比如将$User用当前时间代替
        $SqlFilePath = "$home\Desktop\BatchSiteDBCreate-$User.sql",
        
        [Parameter(ParameterSetName = "UseKey")]
        # 控制是否使用明文mysql密码
        $MySqlkey = $env:DF_MysqlKey,
        [parameter(ParameterSetName = "UseKey")]
        [switch]$UseKey
    )
    $domains = @($domains) -join "`n"
    $domains = $domains.trim() -split "`r?`n|," | Where-Object { $_.Length }

    # $lines = [System.Collections.ArrayList]@()
    # $sqlLines = [System.Collections.ArrayList]@()
    $ShellLines = New-Object System.Collections.Generic.List[string]
    $sqlLines = New-Object System.Collections.Generic.List[string]
        
    $password = ""
    if($PSCmdlet.ParameterSetName -eq "UseKey")
    {
            
        if($UseKey -and $MySqlkey)
        {
            $password = " -p$MySqlkey"
        }
            
    }
        
    Write-Verbose "读取的域名规范化(移除多余的空白和`www.`,使数据库名字结构统一)" 
    # 默认处理的是非单行模式,也就是认为Domain参数包含了一组域名配置,逐个解析
    # 如果是单行模式也没关系,上面的处理将$domains确保数组化
    # 这里将试图生成两种语句:一种是适合于shell中直接执行mysql语句;另一种是适合保存到sql文件中的普通sql语句
    foreach ($domain in $domains)
    {
        $domain = $domain.Trim() -replace "www\.", "" 

        $ShellLine = "mysql -u$mysqlUser -h $Server $password -e 'CREATE DATABASE ``${User}_$domain`` CHARACTER SET utf8mb4 COLLATE $collate;' "
        $sqlLine = 'CREATE DATABASE ' + " ``${User}_$domain`` CHARACTER SET utf8mb4 COLLATE $collate;"
            
        Write-Verbose $ShellLine
        Write-Verbose $sqlLine

        $ShellLines.Add($ShellLine) > $null
        $sqlLines.Add($sqlLine) > $null
            
        # 两组前后分开处理,但是合并返回
        # $ShellLines = $ShellLines + $sqlLine
        # $lines = $ShellLines.AddRange($sqlLines) 
            
        # $lines = @($ShellLines, $sqlLines)
            
        # $line | Invoke-Expression
    }
    # 是否将sql语句写入到文件
    if($SqlFilePath)
    {
        Write-Verbose "Try add sqlLine:`n`t[$sqlLines]`nto .sql file:`n`t[$SqlFilePath]" 
        # 根据是否使用单行模式来决定是:追加式写入或覆盖式创建/写入
        if($SingleDomainMode)
        {
            $sqlLines >> $SqlFilePath
        }
        else
        {

            $sqlLines | Out-File $SqlFilePath -Encoding utf8   
        }
    }
    return $sqlLines
    
}
function Get-BatchSiteBuilderLinesFromTable
{
    [CmdletBinding()]
    param(
        $Table = "$Desktop/table.conf",
        $Structure = "Domain,User",
        $SiteOwnersDict = $SiteOwnersDict,
        $SiteRoot = "wordpress"
    )

    Write-Verbose "You use tableMode!(Read parameters from table string or file only!)" 

    $dicts = Get-DomainUserDictFromTable -Table $Table -Structure $Structure -SiteOwnersDict $SiteOwnersDict  
    # Write-Debug "dicts: $dicts"
    # Get-DictView @($dicts)

    foreach ($dict in $dicts)
    {
        Write-Verbose $dict.GetEnumerator() #-Verbose
        # $dictplus = @{}

        # $dictJson = $dict | ConvertTo-Json | ConvertFrom-Json
        # $dictJson.PSObject.properties | ForEach-Object {
        #     $dictplus[$_.Name] = $_.Value
        # }
            
        $dictplus = $dict.clone()

        $dictplus.add("SiteRoot", $siteRoot)

        Write-Debug "dictplus:$($dictplus.GetEnumerator())" 

        $BtLine = Get-BatchSiteBuilderLines @dictplus
        $siteExpressions += $BtLine + "`n"
            

        # Pause 
    }
    $siteExpressions | Set-Clipboard
    Write-Verbose "scripts written to clipboard!`n" -Verbose
    return $siteExpressions
    
}
function Start-BatchSitesBuild
{
    <# 
    .SYNOPSIS
    组织调用批量建站的命令
    .NOTES
    生成的sql文件位于桌面(可以自动执行)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Alias("SiteOwner")]$User,
        $Domains,
        $Server = $env:DF_SERVER1, 
        $MySqlUser = "root",
        [Alias("Key")]$MySqlkey = "",
        $SqlFileDir = "$home/desktop",
        $SqlFilePath = "$sqlFileDir/BatchSiteDBCreate-$user.sql",
        # 读取表格形式的数据,可以从文件中读取多行表格数据,每行一个配置,列间用空格或逗号分隔
        $Table = "",
        # 域名后追加的网站根目录,比如wordpress
        $SiteRoot = "wordpress",
        [ValidateSet("Auto", "FromFile", "MultiLineString")]$TableMode = 'Auto',

        $SiteOwnersDict = $SiteOwnersDict,
        # $Structure = "Domain,Owner,OldDomain"
        $Structure = $DFTableStructure,
        # 是否将批量建站语句自动输出到剪切板
        [switch]$ToClipboard,
        [switch]$KeepSqlFile
        # [switch]$TableMode
    )

    # 处理域名参数

    # 获取宝塔建站语句
    $siteExpressions = ""
    $dbExpressions = ""
    if($Table)
    {
        Write-Verbose "You use tableMode!(Read parameters from table string or file only!)" 

        $dicts = Get-DomainUserDictFromTable -Table $Table -Structure $Structure -SiteOwnersDict $SiteOwnersDict -TableMode $TableMode
        # Write-Debug "dicts: $dicts"
        Get-DictView @($dicts)

        # 在Table输入模式下,你需要在生成sql文件之前,移除旧sql文件(如果有的话)
        # 生成的sql文件名带有日期(可能包含多个用户的新建数据库的语句)
        $SqlFilePath = "$sqlFileDir/BatchSiteDBCreate-$(Get-Date -Format 'yyyy-MM-dd-hh').sql"

        # Remove-Item $SqlFilePath -Verbose -ErrorAction SilentlyContinue -Confirm

        foreach ($dict in $dicts)
        {
            Write-Verbose $dict.GetEnumerator() #-Verbose
            # $dictplus = @{}

            # $dictJson = $dict | ConvertTo-Json | ConvertFrom-Json
            # $dictJson.PSObject.properties | ForEach-Object {
            #     $dictplus[$_.Name] = $_.Value
            # }
            
            $dictplus = $dict.clone()

            $dictplus.add("SiteRoot", $siteRoot)

            Write-Debug "dictplus:$($dictplus.GetEnumerator())" -Debug

            $BtLine = Get-BatchSiteBuilderLines @dictplus
            $siteExpressions += $BtLine + "`n"
            
            $dbLine = Get-BatchSiteDBCreateLines @dict -SingleDomainMode -SqlFilePath "" #关闭写入文件,采用返回值模式
            $dbExpressions += $dbLine + "`n"

            # Pause 
        }
    }
    else
    {

        $siteExpressions = Get-BatchSiteBuilderLines -SiteOwner $user -Domains $domains
        $dbExpressions = Get-BatchSiteDBCreateLines -Domains $domains -SiteOwner $user
    }
    # 查看宝塔建站语句|写入剪切板
    Write-Host $siteExpressions
    if($ToClipboard)
    {
        $siteExpressions | Set-Clipboard
    }
    $dbExpressions.Trim() | Set-Content $SqlFilePath -Encoding utf8 -NoNewline

    Write-Host "[$sqlfilepath] will be executed!..."
    # Get-Content $sqlfilepath | Get-ContentNL -AsString 
    $SqlLinesTable = Get-Content $sqlfilepath | Format-DoubleColumn | Out-String
    # Write-Host $SqlLinesTable -ForegroundColor Cyan
    Write-Verbose $SqlLinesTable -Verbose

    Write-Warning "Please Check the sql lines,especially the siteOwner is exactly what you want!"
    # Pause

    Write-Output $dbExpressions
    # Pause

    # foreach ($line in $dbExpressions)
    # {
    #     $line | Invoke-Expression
    # }
    Write-Warning "Running the sql file (by cmd /c ... ),wait a moment please..."

    # 执行sql导入前这里要求用户确认
    Import-MysqlFile -Server $Server -MySqlUser $MySqlUser -key $MySqlkey -SqlFilePath $SqlFilePath -Confirm:$confirm 

    if(! $KeepSqlFile)
    {
        Remove-Item $SqlFilePath -Force -Verbose
    }
}
function Get-PSConsoleHostHistory
{
    <# 
    .SYNOPSIS
    读取powershell上运行的历史命令行并返回
    可以配合其他过滤工具来查找命令
    .EXAMPLE
    PS> Get-PSConsoleHostHistory|sls group

    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=df_server1
    mysql --defaults-group-suffix=remote1
    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=_df_server1
    mysql --defaults-group-suffix=_df_server1
    mysql --defaults-group-suffix=_df_server1
    mysql --defaults-group-suffix=_df_server1
    Get-PowershellConsoleHostHistory|sls group
    Get-PSConsoleHostHistory|sls group
    .EXAMPLE
    PS> Get-PSConsoleHostHistory|sls mysql.*default |Get-ContentNL -AsString
    1:mysql --defaults-group-suffix=_remote1
    2:mysql --defaults-group-suffix=df_server1
    3:mysql --defaults-group-suffix=remote1
    4:mysql --defaults-group-suffix=_remote1
    5:mysql --defaults-group-suffix=_df_server1
    6:mysql --defaults-group-suffix=_df_server1
    7:mysql --defaults-group-suffix=_df_server1
    8:mysql --defaults-group-suffix=_df_server1
    9:mysqld --install MySQL55 --defaults-file="C:\phpstudy_pro\Extensions\MySQL5.5.29\my.ini"
    .EXAMPLE
    #⚡️[Administrator@CXXUDESK][~\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine][9:43:35][UP:3.54Days]
    PS> Get-PSConsoleHostHistory|sls mysql.*default

    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=df_server1
    mysql --defaults-group-suffix=remote1
    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=_df_server1
    #>
    $res = Get-Content $PSConsoleHostHistory
    return $res
}
function Get-MysqlDbInfo
{
    <# 
    .SYNOPSIS
    获取mysql数据库信息
    .DESCRIPTION
    默认判断数据库是否存在
    如果表存在,可以指定是否显示数据库中的表
    .NOTES
    如果你不想要输出超过一定长度,那么可以配合管道符|select -First n 使用,例如n取5时,显示前5行输出

    .example
    #⚡️[Administrator@CXXUDESK][C:\sites\wp_sites_cxxu\2.fr\wp-content\plugins][23:13:34][UP:7.62Days]
    PS> Get-MysqlDbInfo -Name 1.fr -Server localhost -ShowTables -Verbose |select -First 5
    VERBOSE: check 1.fr database on [localhost]
    VERBOSE: mysql -h localhost -u root  -e "SHOW DATABASES LIKE '1.fr';"
    Database '1.fr' exist! ...
    VERBOSE: mysql -h localhost -u root  -e "SHOW TABLES FROM ``1.fr``;"
    VERBOSE: Show tables in 1.fr database....
    Tables_in_1.fr
    wp_actionscheduler_actions
    wp_actionscheduler_claims
    wp_actionscheduler_groups
    wp_actionscheduler_logs
    #>
    [cmdletbinding()]
    param (
        [alias('DatabaseName')]$Name,
        $Server = 'localhost',
        [Alias("P")]$Port = 3306,
        $MySQLUser = 'root',
        $key = "",
        [switch]$ShowTables
    )
    $key = Get-MysqlKeyInline $key
    $db_name_inline = "'$Name'"
    $CheckDBCmd = "mysql -h $Server -P $Port -u $MySQLUser $key -e `"SHOW DATABASES LIKE $db_name_inline;`""
    Write-Verbose "check [$Name] database on [$Server]"
    Write-Verbose $CheckDBCmd 
    $res = $CheckDBCmd | Invoke-Expression

    if ($res -match $Name)
    {
        Write-Host "Database '$Name' exist! ..."
        if($ShowTables)
        {
            $ShowTablesCmd = "mysql -h $Server -P $Port -u $MySQLUser $key -e `"SHOW TABLES FROM ````$Name````;`""
            Write-Verbose $ShowTablesCmd 

            Write-Verbose "Show tables in $Name database...." -Verbose
            $ShowTablesCmd | Invoke-Expression
        }
    }
    else
    {
        Write-Warning "Database '$Name' Does not exist!"
      
    }
    return $res
}
function Import-MysqlFile
{
    <# 
    .SYNOPSIS
    向指定mysql服务器导入mysql文件(运行sql文件)
    
    .PARAMETER server
    写入操作对于数据库影响较大,因此此命令设计为你必须要指定主机(mysql服务器,比如本地(localhost),或则远程的某个服务)
    .PARAMETER SqlFilePath
    要导入的sql文件路径
    .PARAMETER MySqlUser
    mysql用户名,默认为root
    .PARAMETER key
    mysql密码
    你也可以不指定密码,而在mysql中配置文件(比如my.ini或my.cnf)中设置密码,实现免手动指定密码操作数据库
    默认为读取环境变量DF_MysqlKey,指定此参数时,会以你的输入为准,但是这不安全

    .PARAMETER DatabaseName
    如果你指定此参数,那么命令会认为你想要将sql文件导入到指定数据库名
    默认为"",表示你想要执行的语句(sql文件)不要求你后期指定数据库名字,
    例如,你的sql是一些查询数据库基本信息的语句,或者是创建数据库的语句,你不需要在命令行中指定一个数据库
 
    数据库名字;数据库sql导入有两大类,一类不需要指定数据库就可以直接执行的sql;一类是针对特定数据库执行的sql
    例如某份sql中是一批数据库创建语句,那么你不需要指定某个数据库名直接就可以执行(如果要创建的数据库已经存在,mysql会提示你对应的数据库已经存在)
    而有的sql是数据库的备份sql文件,你应该指定一个数据库名称,然后执行导入操作;
    一般而言,这两类数据库sql不能混放在同一个sql文件中

    .EXAMPLE
    Import-MysqlFile -server localhost -SqlFilePath "C:\Users\admin\Desktop\test.sql" -MySqlUser root -key "123456" -DatabaseName "test"
    .EXAMPLE
    #⚡️[Administrator@CXXUDESK][~\Desktop][20:50:51][UP:3.52Days]
    PS> Import-MysqlFile -server localhost -DatabaseName 6.fr -SqlFilePath C:\sites\wp_sites_cxxu\base_sqls\6.es.sql
    VERBOSE: File exist!
    cmd /c " mysql -u root -h localhost -p15a58524d3bd2e49 6.fr < `"C:\sites\wp_sites_cxxu\base_sqls\6.es.sql`" "
    mysql: [Warning] Using a password on the command line interface can be insecure.
    .NOTES
    可以配置默认导入主机和用户等信息
    导入的文件路径是必填的

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        $Server = "localhost",
        $MySqlUser = "root",
        [Alias("MySqlKey")]$key = $env:MySqlKey_LOCAL,
        [alias("File", "Path")]$SqlFilePath,
        [parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [alias("Name")]$DatabaseName = "",
        [alias("P")]$Port = 3306,
        [switch]$Force
    )
    begin
    {
        
        $key = Get-MysqlKeyInline $key
    }
    process
    {
   
        if(Test-Path $SqlFilePath)
        {
        
            Write-Verbose "Use Mysql server host: $Server"
            Write-Verbose "Sql File exist!" 

            # 如果数据库不存在,则提示创建数据库
            # $db_name_inline_creater = "````$DatabaseName````"
            # $db_name_inline = "'$DatabaseName'"
            # Write-Verbose "$databaseName"
            # Write-Verbose "$db_name_inline"

            # Pause

            # 查询数据库是否存在
            # $CheckDBCmd = "mysql -h $Server -u $MySQLUser $key -e `"SHOW DATABASES LIKE $db_name_inline;`""
            # $CreateDBCmd = "mysql -h $Server -u $MySQLUser $key -e `"CREATE DATABASE $db_name_inline_creater;`""
        
            # Write-Verbose $CheckDBCmd -Verbose
            # Write-Verbose $CreateDBCmd -Verbose
        
            # return 

            # $DBExists = Invoke-Expression $CheckDBCmd
            if(!$DatabaseName )
            {
                Write-Warning "You did not specify the database name!"
                # write-warning "The sql file path Leafbase name will be the default database name!"
                # $DatabaseName = Split-Path $SqlFilePath -LeafBase
            }
            # 如果用户指定了数据库名称,则检查该数据库是否已经存在,并给出测试结果;否则认为要导入的sql不需要事先指定数据库名字
            if($DatabaseName)
            {

                $DBExists = Get-MysqlDbInfo -Name $DatabaseName -Server $Server -Port $Port -MySQLUser $MySqlUser -key $key
            
                if(!$DBExists)
                {
                
                    # Write-Host "数据库不存在!"
                    if($PSCmdlet.ShouldProcess($Server, "Create Database: $DatabaseName ?"))
                    {
                    
                        # Invoke-Expression $CreateDBCmd
                        New-MysqlDB -Name $DatabaseName -Server $Server -Port $Port -MySqlUser $MySqlUser -MysqlKey $key -Confirm:$false
                    }
                }
                else
                {
                    # Get-MysqlDbDescription -Name $DatabaseName -Server $Server
                    Get-MysqlDbInfo -Name $DatabaseName -Server $Server -Port $Port -key $key -ShowTables | Select-Object -First 5
                }
            }
            # 忽略执行失败的sql,强制继续执行剩余sql(比如批量切换数据库中各个表的引擎,部分表无法顺利切换,可以利用-f跳过错误的部分)
            $ForceSql = if($Force) { "-f" } else { "" }
            $expression = "cmd /c `" mysql -h $Server -P $Port -u $MySqlUser  $key $ForceSql $DatabaseName < ```"$SqlFilePath```" `""
            Write-Verbose $expression 

        
            if($Force -or -not $Confirm)
            {
                $ConfirmPreference = "None" 
                # cmd /c $expression
            }
            if($PSCmdlet.ShouldProcess($Server, $expression))
            {

                Invoke-Expression $expression
            }
        }
    }
}
function Remove-MysqlDB
{
    <# 
    .SYNOPSIS
    删除指定的mysql数据库
    .DESCRIPTION
    删除指定的mysql数据库尤其是批量删除通常是一个危险操作,这里使用风险缓解的询问措施(将影响级别调整到'High',默认情况下会要求用户输入确认以继续执行相关操作)
    .EXAMPLE
    从文件中读取数据库名,并删除数据库
    $dbs=Get-DomainUserDictFromTableLite |select -ExpandProperty domain
    通过管道服务的形式,将数据库名数组中指定的数据库传递给Remove-MysqlDB命令逐个进行移除
    $dbs|Remove-MysqlDB  -Force
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param (
        $Server = "localhost",
        $MySqlUser = "root",
        [Alias("MySqlKey")]$key = $env:MySqlKey_LOCAL,
        [alias("P")]$Port = 3306,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [alias("Name")]
        $DatabaseName,
        [switch]$Force
    )
    begin
    {
        Write-Verbose "Use Mysql server host: $Server"
        Write-Verbose "start remove database $DatabaseName"
        $key = Get-MysqlKeyInline $key
    }
    process
    {

        # DROP DATABASE [IF EXISTS] database_name;
        $command = " mysql -u$MySqlUser -h $Server -P $Port $key -e 'DROP DATABASE IF EXISTS ``$DatabaseName`` ; ' "  
        Write-Verbose $command 
        if($Force -and -not $Confirm)
        {
            $ConfirmPreference = "None"
        }
        if($PSCmdlet.ShouldProcess($DatabaseName, "Remove Database $DatabaseName ?"))
        {
            
            # 将mysql的执行输出丢弃
            Invoke-Expression $command *> $null
            
        }
        Write-Verbose "Database $DatabaseName has been tried to be removed!" -Verbose
    }
    
}
function Remove-MysqlIsolatedDB
{
    <# 
    .SYNOPSIS
  网站根目录不存在的网站配套的mysql数据库删除
  .NOTES
  这是一个特定专用函数
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $SitesDir = $my_wp_sites
    )
    $domains = Get-DomainUserDictFromTableLite | Select-Object -ExpandProperty domain
    $toBeRemoveNames = [System.Collections.Generic.List[string]]::new()
    # 检查对应网站根目录是否存在
    foreach ($domain in $domains)
    {
        $site_root = "$SitesDir/$domain"
        if(Test-Path $site_root)
        {
            Write-Host "网站根目录存在: $site_root"
        }
        else
        {
            <# Action when all if and elseif conditions are false #>
            Write-Host "网站根目录不存在: $site_root,将被移除同名数据库"
            $toBeRemoveNames.Add($domain)
        }
    }
    $toBeRemoveNames | Remove-MysqlDB 
}
function Export-MysqlFile
{
    <# 
    .synopsis
    导出mysql数据库到文件
    .DESCRIPTION
    #>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [alias('Name')]$DatabaseName,    
        $OutputDir = $base_sqls,
        $SqlFilePath = "$OutputDir/$DatabaseName.sql",

        $Server = "localhost",
        [alias("P")]$Port = 3306,
        $MySqlUser = "root",
        $key = $env:MySqlKey_LOCAL,
        [switch]$Force,
        # 默认执行备份,使用此选项禁用备份
        [switch]$Backup

    )
    begin
    { 
        Write-Verbose "Use Mysql server host: $Server"
        Write-Verbose "Start Export database $DatabaseName "
    }
    process
    {
        if(Test-Path $SqlFilePath)
        {
            Write-Warning "File already exist!New files will override the old ones!"
            if($Backup)
            {
                # 执行备份
                Write-Verbose "try to rename the old file!(as .bak);" -Verbose

                Rename-Item $SqlFilePath "$SqlFilePath.bak.$(Get-Date -Format 'yyyyMMdd-hhmmss')" -Force:$Force -Verbose
                # try
                # {
                Write-Verbose "The old file has been renamed to $SqlFilePath.bak" -Verbose
                # }
                # catch
                # {
                #     Write-Warning "Failed to rename the old file!(because the $SqlFilePath.bak is also already exist !)"
                #     Write-Warning "Please check and move the file path or delete the old file manually if it will no longer be used."
                #     return
                # }
            }
        }

        $expression = "  mysqldump   -h $Server -P $Port -u $MySqlUser -p$key '$DatabaseName' > $SqlFilePath "
        Write-Verbose $expression
        Invoke-Expression $expression
    }
}

function Get-UrlFromMarkdownUrl
{
    param(
        $Urls
    )
    $Urls = $Urls -replace '\[.*?\]\((.*)\)', '$1' -split "`r?`n" | Where-Object { $_ }
    return $Urls
}
function Get-CRLFChecker
{
    <# 
    .SYNOPSIS
    将问文本文件中的回车符,换行符都显示出来
    .DESCRIPTION
    多行文本将被视为一行,CR,LF(\r,\n)将被显示为[CR],[LF]
    #>
    param (
        $Path,
        [switch]$ConvertToLFStyle
    )
    $raw = Get-Content $Path -Raw
    $isCRLFStyle = $raw -match "`r"
    if($isCRLFStyle)
    {
        Write-Host "The file: [$Path] is CRLF style file(with carriage char)!"
    }
    else
    {
        Write-Host "The file: [$Path] is LF style file(without carriage char)!"

    }

    $res = $raw -replace "`n", "[LF]" -replace "`r", "[CR]"
    
    if($ConvertToLFStyle)
    {
        $fileName = Split-Path $Path -LeafBase
        $fileDir = Split-Path $Path -Parent
        $fileExtension = Split-Path $Path -Extension
        
        # 移除CR回车符
        $res = $raw -replace "`r", ""
        
        $LFFile = "$fileDir/$fileName.LF$fileExtension"
        $res | Out-File $LFFile -Encoding utf8 -NoNewline
        
        Write-Verbose "File has been converted to LF style![$LFFile]" -Verbose
        $res = $res -replace "`n", "[LF]"
    }
    $res | Select-String -Pattern "\[CR\]|\[LF\]" -AllMatches 
}
function Get-SiteMapIndexUrls
{
    <# 
    .SYNOPSIS
    获取指定列表中的网站地图的urls
    
    .PARAMETER DomainLists
    指定网站地图的urls,可以是一个文件

    #>
    [CmdletBinding()]
    param (
        $DomainLists
    )
    Get-Content $DomainLists | ForEach-Object { "`t$_`t https://$_/sitemap_index.xml " } | Get-ContentNL -AsString 
}
function Get-MainDomain
{
    <#
    .SYNOPSIS
    获取主域名
    从给定的 URL 中提取二级域名和顶级域名部分（即主域名），忽略协议 (http:// 或 https://) 和子域名（如 www.、xyz. 等）
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Url
    )

    process
    {
        # 去除协议部分（http:// 或 https://）
        $hostPart = ($Url -replace '^[a-zA-Z0-9+.-]+://', '') -split '/' | Select-Object -First 1

        # 分割域名部分
        $parts = $hostPart -split '\.' | Where-Object { $_ }

        # 处理简单情况（例如 domain.com 或 www.domain.com）
        if ($parts.Count -ge 2)
        {
            return "$($parts[-2]).$($parts[-1])"
        }

        return $null
    }
}
function Move-ItemFromCsvPathFields
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

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        $Path,
        $Fields = 'Images',
        
        $SourceDir,
        [Alias('TargetDir')]$Destination
    )
    # $csv = Import-Csv $CsvPath
    process
    {
        Write-Verbose "Processing file: $Path" -Verbose
        Import-Csv $Path | Select-Object -ExpandProperty 'Images' | ForEach-Object { Move-Item -Path $SourceDir/$_ -Destination $Destination }
    }

}
function Restart-Nginx
{
    <# 
    .SYNOPSIS
    重启Nginx
    为了提高重启的成功率,这里会检查nginx的vhosts目录中的相关配置关联的各个目录是否都存在,如果不存在,则会移除相应的vhosts配置文件(避免因此而重启失败)
    Approve-NginxValidVhostsConf -NginxConfDir $NginxConfDir
    #>
    [CmdletBinding()]
    param(

        $nginx_home = $env:NGINX_HOME,
        $NginxConfDir = $env:nginx_conf_dir
    
    )
    Write-Debug "nginx_home: $nginx_home"
    if (!$nginx_home)
    {
        Write-Warning "Nginx home directory was not set , please set the environment variable NGINX_HOME to your nginx home directory!"
    }
    $item = Get-Item -Path "$nginx_home/nginx.exe".Trim("/").Trim("\") -ErrorAction Stop
    Write-Debug "nginx.exe path:$($item.FullName)"
    $nginx_availibity = Get-Command nginx -ErrorAction SilentlyContinue
    if(!$nginx_availibity)
    {
        Write-Warning "Nginx is not found in your system,please install (if not yet) and configure it(nginx executable dir) to Path environment!"
    }
    Write-Verbose "Restart Nginx..." -Verbose
    
    # Approve-NginxValidVhostsConf
    Approve-NginxValidVhostsConf -NginxConfDir $NginxConfDir

    Write-Verbose "Nginx.exe -s reload" -Verbose
    Start-Process -WorkingDirectory $nginx_home -FilePath "nginx.exe" -ArgumentList "-s", "reload" -Wait -NoNewWindow
    Write-Verbose "Nginx.exe -s stop" -Verbose

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

function Get-PortAndProcess
{
    <# 
    .SYNOPSIS
    获取指定端口号的进程信息,支持通配符(字符串)
    .DESCRIPTION
    如果需要后续使用得到的信息,配合管道符select使用即可
    .EXAMPLE
    PS> Get-PortAndProcess 900*

    LocalAddress LocalPort RemoteAddress RemotePort  State OwningProcess ProcessName
    ------------ --------- ------------- ----------  ----- ------------- -----------
    127.0.0.1         9002 0.0.0.0                0 Listen         18908 xp.cn_cgi
    #>
    param (
        $Port
    )
    $res = Get-NetTCPConnection | Where-Object { $_.LocalPort -like $Port } | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess, @{Name = 'ProcessName'; Expression = { (Get-Process -Id $_.OwningProcess).Name } } 
    return $res
    
}
function Approve-NginxValidVhostsConf
{
    <# 
    .SYNOPSIS
    扫描nginx vhosts目录中的各个站点配置文件(尤其是所指的站点路径)是否存在(有效)
    如果无效,则会将对应的vhosts中的站点配置文件移除,从而避免nginx启动或重载而受阻
    #>
    [CmdletBinding()]
    param(
        $NginxConfDir = "$env:nginx_conf_dir" # 例如:C:\phpstudy_pro\Extensions\Nginx1.25.2\conf\vhosts
    )
    $vhosts = Get-ChildItem $NginxConfDir -Filter "*.conf" 
    Write-Verbose "Checking vhosts in $NginxConfDir" -Verbose
    foreach ($vhost in $vhosts)
    {
        $root_info = Get-Content $vhost | Select-String root | Select-Object -First 1
        # 计算vhost配置文件中的站点根路径(如果不存在时跳过处理此配置)
        if($root_info)
        {
            $root_info = $root_info.ToString().Trim()    
            $root = $root_info -replace '.*"(.+)".*', '$1'
            if(!$root)
            {
                Write-Warning "vhost: $($vhost.Name) root path is empty!" -WarningAction Continue
                # 处理下一个
                continue
            }
        }
        else
        {
            continue
        }
        # 根据得到的root路径来判断站点根目录是否存在
        if(Test-Path $root)
        {
            Write-Verbose "vhost: $($vhost.Name) root path: $root is valid(exist)!"  
        }
        else
        {
            Write-Warning "vhost: $($vhost.Name) root path: $root is invalid(not exist)!" -WarningAction Continue
            Remove-Item $vhost.FullName -Force -Verbose
            # Write-Host "Removed invalid vhost file: $($vhost.FullName)" -ForegroundColor Red
            # if($PSCmdlet.ShouldProcess("Remove vhost file: $($vhost.FullName)"))
            # {
            # }
        }
    }

}
function Get-DomainUserDictFromTableLite
{
    <# 
    .SYNOPSIS
    简单地从约定的配置文本(包含多列数据,每一列用空白字符隔开)中提取各列(字段)的数据


    #>
    param(
        # [Parameter(Mandatory = $true)]
        [Alias('Path')]$Table = "$env:USERPROFILE/Desktop/my_table.conf"
    )
    Get-Content $Table | Where-Object { $_ -notmatch "^\s*#" } | ForEach-Object { 
        $l = $_ -split '\s+'
        @{'domain'     = ($l[0] | Get-MainDomain);
            'user'     = $l[1];
            'template' = $l[2] 
        } 
    }
}
function Remove-LineInFile
{
    <# 
    .SYNOPSIS
    将指定文件中包含特定模式的行删除
    .DESCRIPTION
    例如,可以删除hosts文件中包含特定域名的行
    .PARAMETER Path
    文件路径,例如系统hosts文件
    .PARAMETER Pattern
    要删除的行的模式
    # .PARAMETER Inplace
    # 是否直接修改文件,默认为false,即只打印删除的行
    .PARAMETER Encoding
    文件编码,默认为utf8

    .EXAMPLE
    PS> Remove-LineInFile -Path $hosts -Pattern whh123.com -Debug
    开始处理文件: C:\WINDOWS\System32\drivers\etc\hosts
    DEBUG: Removed line: 127.0.0.1  whh123.com
    WARNING: modify file: C:\WINDOWS\System32\drivers\etc\hosts,using -Inplace parameter (encoding: utf8)

    Confirm
    Continue with this operation?
    [Y] Yes  [A] Yes to All  [H] Halt Command  [S] Suspend  [?] Help (default is "Y"):
    
    #>
    [CmdletBinding()]
    param (
        $Path,
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        $Pattern,
        [switch]$Inplace,
        $Encoding = 'utf8'
    )
    begin
    {
        if (!(Test-Path $Path))
        {
            Write-Error "文件不存在: $Path"
            return
        }
        else
        {
            Write-Host "开始处理文件: $Path"
            $lines = Get-Content $Path
            # 转换为可变列表
            $lineList = [System.Collections.Generic.List[string]]$lines
        }
    }
    process
    {

        foreach ($line in $lines)
        {
            if ($line -match $Pattern)
            {
                $lineList.Remove($line) > $null
                Write-Debug "Removed line: $line"
            }
        }
    }
    end
    {
    
        # 将结果写回文件中
        # if($Inplace)
        # {
        # }

        Write-Warning "modify file: ${Path},using -Inplace parameter (encoding: $Encoding)" -WarningAction Inquire

        $lineList | Out-File "${Path}" -Encoding $Encoding

        # else
        # {
        #     Write-Debug "To modify the $Path file, please use the -Inplace parameter."
        # }
    }
    
}
function Rename-FileName
{
    [CmdletBinding()]
    param(
        $Path,
        [alias('RegularExpression')]$Pattern,
        [alias('Substitute')]$Replacement
    )
    
    Get-ChildItem $Path | ForEach-Object { 
        # 无后缀(扩展名)的文件基名
        # $leafBase = (Split-Path -LeafBase $_).ToString()
        # 包含扩展名的文件名
        $name = $_.Name
        $newName = $name -replace $Pattern, $Replacement
        Rename-Item -Path $_ -NewName $newName -Verbose 
    }

}
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
    param(
        $Table = "$desktop/my_table.conf",
        $SitesDir = $my_wp_sites,
        $NginxConfDir = "$env:nginx_conf_dir"
    )
    $domains = Get-DomainUserDictFromTableLite -Table $Table | Select-Object -ExpandProperty domain
    # Write-Host $domains
    $msg = $domains | Format-DoubleColumn | Out-String
    Write-Verbose $msg -Verbose
    Write-Warning "准备并行删除相关本地站点,配套配置和数据库" -WarningAction Inquire
    # 多线程删除网站根目录
    $jobs = @()
    foreach ($domain in $domains)
    {
        $siteRoot = "$SitesDir/$domain"
        $job = Start-ThreadJob -Name "Remove:$domain" -ScriptBlock {
            param($Path)
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            # Remove-RobocopyMirEmpty -Path $Path  -Confirm:$false -Verbose
            Write-Host "Removed site root: $Path" 
        } -ArgumentList $siteRoot
        $jobs += $job
    }
    $jobs | Wait-Job
    $jobs | Receive-Job
    $jobs | Remove-Job
    # 尝试删除数据库及其相关配置
    Remove-MysqlIsolatedDB -SitesDir $SitesDir
    Approve-NginxValidVhostsConf -NginxConfDir $NginxConfDir
    $domains | Remove-LineInFile -Path $hosts -Debug
    
}


function Get-FileFromUrl
{
    <#
    .SYNOPSIS
    高效地批量下载指定的URL资源。
    .DESCRIPTION
    使用 PowerShell 7+ 的 ForEach-Object -Parallel 特性，实现轻量级、高效率的并发下载。
    自动处理现代网站所需的TLS 1.2/1.3安全协议，并提供更详细的错误报告。
    .PARAMETER Url
    通过管道接收一个或多个URL。
    .PARAMETER InputFile
    指定包含URL列表的文本文件路径（每行一个URL）。此参数不能与通过管道传递的Url同时使用。
    .PARAMETER OutputDirectory
    指定资源下载的目标目录。默认为当前用户的桌面。
    .PARAMETER Force
    如果目标文件已存在，则强制覆盖。默认不覆盖。
    .PARAMETER UserAgent
    自定义HTTP请求的User-Agent。默认为一个通用的浏览器标识，以避免被服务器屏蔽。
    .PARAMETER ThrottleLimit
    指定最大并发线程数。默认为5。
    .EXAMPLE
    # 示例 1: 从文件读取URL列表并下载
    PS> Get-FileFromUrl -InputFile "C:\temp\urls.txt" -OutputDirectory "C:\Downloads"

    # 示例 2: 通过管道传递URL
    PS> "https://example.com/file1.zip", "https://example.com/file2.zip" | Get-FileFromUrl

    # 示例 3: 从文件读取，并设置并发数为10，同时强制覆盖已存在的文件
    PS> Get-Content "urls.txt" | Get-FileFromUrl -ThrottleLimit 10 -Force
    #>
    [CmdletBinding(DefaultParameterSetName = 'UrlInput')]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'UrlInput')]
        [string[]]$Url,

        [Parameter(Mandatory = $true, ParameterSetName = 'FileInput')]
        [string]$InputFile,

        [Parameter()]
        [string]$OutputDirectory = "$env:USERPROFILE\Desktop",

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [string]$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',

        [Parameter()]
        [int]$ThrottleLimit = 5
    )

    begin
    {
        # 1. 关键修复：强制使用TLS 1.2/1.3协议，解决 "WebClient request" 错误
        # 这是解决您问题的核心代码。
        try
        {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12, [System.Net.SecurityProtocolType]::Tls13
        }
        catch
        {
            Write-Warning "无法设置 TLS 1.3，继续使用 TLS 1.2。这在旧版 .NET Framework 中是正常的。"
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        }


        # 2. 优化：如果输出目录不存在，则创建它
        if (-not (Test-Path -Path $OutputDirectory))
        {
            Write-Verbose "正在创建输出目录: $OutputDirectory"
            New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
        }

        # 3. 优化：整合URL输入源
        $urlList = switch ($PSCmdlet.ParameterSetName)
        {
            'FileInput' { Get-Content -Path $InputFile }
            'UrlInput' { $Url }
        }
        # 过滤掉空行
        $urlList = $urlList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        Write-Host "准备下载 $($urlList.Count) 个文件，最大并发数: $ThrottleLimit..." -ForegroundColor Green
    }

    process
    {
        # 4. 核心改进：使用 ForEach-Object -Parallel 替代 Start-Job
        # 它更轻量、启动更快，资源消耗远低于为每个任务启动一个新进程的 Start-Job。
        # 注意：此功能需要 PowerShell 7 或更高版本。
        $urlList | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            # 在并行脚本块中，必须使用 $using: 来引用外部作用域的变量
            $currentUrl = $_
            $ErrorActionPreference = 'Stop' # 确保 try/catch 在线程中能可靠捕获错误

            try
            {
                # 从URL解析文件名，并进行URL解码
                $fileName = [System.Uri]::UnescapeDataString(($currentUrl | Split-Path -Leaf))
                if ([string]::IsNullOrWhiteSpace($fileName))
                {
                    # 如果URL以'/'结尾或无法解析文件名，则生成一个唯一文件名
                    $fileName = "file_$([guid]::NewGuid())"
                    Write-Warning "URL '$currentUrl' 未包含有效文件名，已自动保存为 '$fileName'。"
                }

                $outputPath = Join-Path -Path $using:OutputDirectory -ChildPath $fileName

                if (Test-Path -Path $outputPath -PathType Leaf)
                {
                    if ($using:Force)
                    {
                        # 使用线程ID标识输出，方便调试
                        Write-Host "[线程 $($([System.Threading.Thread]::CurrentThread.ManagedThreadId))] 强制覆盖旧文件: $outputPath" -ForegroundColor Yellow
                        Remove-Item -Path $outputPath -Force
                    }
                    else
                    {
                        Write-Warning "[线程 $($([System.Threading.Thread]::CurrentThread.ManagedThreadId))] 跳过已存在的文件: $fileName"
                        return # 跳出当前循环，继续下一个
                    }
                }

                Write-Host "[线程 $($([System.Threading.Thread]::CurrentThread.ManagedThreadId))] -> 开始下载: $currentUrl"

                # 5. 现代化改进：使用 Invoke-WebRequest 替代老旧的 WebClient
                # Invoke-WebRequest 是现代的、功能更强大的下载工具。
                Invoke-WebRequest -Uri $currentUrl -OutFile $outputPath -UserAgent $using:UserAgent

                Write-Host "[线程 $($([System.Threading.Thread]::CurrentThread.ManagedThreadId))] ✅ 下载成功: $fileName" -ForegroundColor Cyan
            }
            catch
            {
                # 6. 错误处理改进：提供更详细的错误信息
                $errorMessage = "[线程 $($([System.Threading.Thread]::CurrentThread.ManagedThreadId))] ❌ 下载失败: $currentUrl"
                if ($_ -is [System.Net.WebException])
                {
                    $response = $_.Exception.Response
                    if ($null -ne $response)
                    {
                        $statusCode = [int]$response.StatusCode
                        $statusDescription = $response.StatusDescription
                        # 输出具体的HTTP错误码，如 404 Not Found, 403 Forbidden
                        $errorMessage += " - 错误原因: HTTP $statusCode ($statusDescription)"
                    }
                    else
                    {
                        # 网络层面的问题，如DNS解析失败
                        $errorMessage += " - 错误原因: $($_.Exception.Message)"
                    }
                }
                else
                {
                    # 其他类型的错误
                    $errorMessage += " - 错误原因: $($_.Exception.Message)"
                }
                Write-Error $errorMessage
            }
        }
    }

    end
    {
        Write-Host "🎉 所有下载任务已处理完毕。" -ForegroundColor Green
    }
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

    .PARAMETER NginxConfDir
    nginx配置文件目录

    .PARAMETER NginxConfTemplate
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
        $NginxConfDir = "$env:nginx_conf_dir", # 例如:C:\phpstudy_pro\Extensions\Nginx1.25.2\conf\vhosts
        $NginxConfTemplate = "$scripts/Config/nginx_template.conf",
        $NginxHtaccessTemplate = "$scripts/Config/nginx.htaccess",
        # nginx.exe所在目录的完整路径(如果Path中的%nginx_home%没有被正确解析,可以指定完整路径)
        # $NginxHome="",
        $SiteImageDirRelative = "wp-content/uploads/2025",
        $CsvDir = "$Desktop/data_output"
    )
    Write-Debug $table
    Write-Debug $WpSitesTemplatesDir
    Write-Debug $MyWpSitesHomeDir
    Write-Debug $DBKey
    Get-Content $table
    # 检查关键目录
    if(!(Test-Path $WpSitesTemplatesDir))
    {
        Write-Error "Wordpress templates directory not found: $WpSitesTemplatesDir"
        return
    }

    if(!(Test-Path $NginxConfDir))
    {
        Write-Error "Nginx conf directory not found: $NginxConfDir"
        return 
    }
    New-Item -ItemType Directory -Path $MyWpSitesHomeDir -ErrorAction SilentlyContinue -Verbose
    # 启动必要的服务
    Restart-Nginx 
    # Restart-Service 
    # 检查nginx和mysql服务是否正常运行
    $nginx_status = Get-Process nginx
    $mysqld_status = Get-Process mysqld
    if(!$nginx_status)
    {
        Write-Host "Nginx服务未正常启动" -ForegroundColor Red
        return
    }
    if(!$mysqld_status)
    {
        Write-Host "Mysql服务未正常启动" -ForegroundColor Red
        return
    }

    # $rows = Get-DomainUserDictFromTable -Table $table -Structure $TableStructure

    # 始终不提示确认，即使用户没指定 -Confirm:$false
    if (-not $PSBoundParameters.ContainsKey('Confirm'))
    {
        $ConfirmPreference = 'None'
    }
    if(!$CgiPort)
    {
        # $CgiPort = 9000
        $Info = Get-PortAndProcess -Port 900* 
        Write-Host $Info
        $CgiPort = $Info | Select-Object -First 1 -ExpandProperty LocalPort -ErrorAction Stop
        Write-Host $CgiPort
        Write-Debug "CgiPort environment variable not set, Try auto get port value $CgiPort"
    }
    # 解析批量表格中的各条待处理任务
    # $rows = Get-Content $table | Where-Object { $_ -notmatch "^\s*#" } | ForEach-Object { $l = $_ -split '\s+'; @{'domain' = ($l[0] | Get-MainDomain); 'user' = $l[1]; 'template' = $l[2] } }
    $rows = Get-DomainUserDictFromTableLite -Table $table
    # 利用write-output将结果输出到控制台,方便查看
    Write-Output $rows
    Write-Warning "Please check the parameter table list above,especially the domain and template name!" -WarningAction Inquire
    # Pause

    # 逐条数据解析出各个参数,并处理任务
    foreach ($row in $rows)
    {
        $domain = $row.Domain
        $template = $row.Template

        $path = "$WpSitesTemplatesDir/$template"
        $destination = "$MyWpSitesHomeDir/$domain"
        # 这里要加一层域名验证
        if ($domain -and $domain -like "*.*")
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
        $template_temp = "$MyWpSitesHomeDir/$template"
        if(Test-Path $template_temp)
        {

            Move-Item -Path $template_temp -Destination $destination -Force -Verbose -WhatIf:$WhatIfPreference
        }

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
            # $tpl = "$NginxConfDir/tpl.conf"
            $tpl = "$NginxConfTemplate"
            Write-Debug $tpl
            if (!(Test-Path $tpl))
            {
                Write-Error "nginx tpl.conf file not found in path: $NginxConfTemplate"
                # return 
            }
            else
            {
                # 配置本地站点根目录对应的nginx配置文件
                $tpl_content = Get-Content $tpl -Raw
                $tpl_content = $tpl_content -replace "domain.com", $domain #"`"$domain`"" 
                $tpl_content = $tpl_content -replace "CgiPort", $CgiPort
                $nginx_target = "$NginxConfDir/${domain}_80.conf"
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
# =========[http://$domain]:[$destination]=============
python $pys\image_downloader.py -c -n -R auto -k  -rs 1000 800  --output-dir $ImgDir --dir-input $CsvDirHome -w 5 -U curl

python $pys\woo_uploader_db.py --update-slugs  --csv-path $CsvDirHome --img-dir $ImgDir --db-name $domain 

Get-WpSitePacks -SiteDirecotry $destination


"@
            Write-Host $scripts
            $scripts_dir = "$MyWpSitesHomeDir"
            $script_path = "$scripts_dir/scripts_$(Get-Date -Format "yyyyMMdd").ps1"
            $script >> $script_path
            Write-Host "Script has been saved to: $script_path" -ForegroundColor Cyan
        }
        else
        {
            Write-Error "wp-config.php file not found in $destination"
            Pause
        }
        # 导入数据库并执行基础的修改
        Import-MysqlFile -Server localhost -key $DBKey -SqlFilePath "$SqlFileDir/$template.sql" -DatabaseName $domain  
        Update-WpUrl -Server localhost -key $DBKey -NewDomain $domain -OldDomain $template -protocol http  
        
        # 修改(追加当前域名映射新行)到hosts文件(127.0.0.1  $domain)
        Add-NewDomainToHosts -Domain $domain


    }

    # 可以考虑定期清理hosts文件!
    Write-Debug "Modify hosts file [$hosts]"
    # 重启(重载)nginx服务器
    
    Restart-Nginx -Debug
}

function Add-NewDomainToHosts
{
    <# 
    .SYNOPSIS
    添加域名映射到hosts文件中
    .DESCRIPTION
    如果hosts文件中已经存在该域名的映射,则不再添加,否则添加到文件末尾
    #>
    param (
        [parameter(Mandatory = $true)]
        $Domain,
        $Ip = "127.0.0.1",
        [switch]$Force
    )
    # $hsts = Get-Content $hosts
    # if ($hsts| Where-Object { $_ -match $domain }){}
    $exist = Select-String -Path $hosts -Pattern $domain
    if ($exist -and !$Force)
    {
        Write-Verbose "Domain [$domain] already exist in hosts file!" -Verbose
    }
    else
    {

        "$Ip  $domain" >> $hosts
    }
    return Select-String -Path $hosts -Pattern $domain 
}


function Get-HtmlFromLinks
{
    <# 
    .SYNOPSIS
    TODO
    # 测试调用
    Get-HtmlFromLinks -Path ame_links.txt -OutputDir amex
    #>
    param (
        [parameter(Mandatory = $true)]
        $Path,
        [parameter(Mandatory = $true)]
        $OutputDir,
        $Agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", 
        $TimeGap = 1
    )
    $i = 1
    $Path = Get-Item $Path | Select-Object -ExpandProperty FullName
    New-Item -ItemType Directory -Name $OutputDir -Force -Verbose -ErrorAction SilentlyContinue
    Get-Content $Path | ForEach-Object {
        $file = "$OutputDir/$(($_ -split "/")[-1]).html"
        curl.exe -A $Agent `
            -L $_ `
            -o $file
    
        # $s>"ames/$(($_ -split "/")[-1]).html"
        Write-Host "Downloaded($i): $_ "
        $i++
        Start-Sleep $TimeGap
    }

    $result_file_dir = (Split-Path $Path -Parent).ToString()
    $result_file_name = (Split-Path $Path -LeafBase).ToString() + '@local_links.txt'
    Write-Verbose "Result file: $result_file_dir\$result_file_name" -Verbose
    $output = "$result_file_dir\$result_file_name"

    # 生成本地页面url文件列表
    # Get-ChildItem $OutputDir | ForEach-Object { "http://localhost:5500/$OutputDir/$(Split-Path $_ -Leaf)" } | Out-File -FilePath "$output"
    # Get-UrlListFromDir -
    # 采集 http[参数] -> http[参数1]
}
function Start-GoogleIndexSearch
{
    <# 
    .SYNOPSIS
    使用谷歌搜索引擎搜索指定域名的相关网页的收录情况
    
    需要手动点开tool,查看收录数量
    如果没有被google收录,则查询结果为空
    
    .DESCRIPTION
    #>
    param (
        $Domains,
        # 等待时间毫秒
        $RandomRange = @(1000, 3000)
    )
    $domains = Get-LineDataFromMultilineString -Data $Domains 
    foreach ($domain in $domains)
    {
        
        $cmd = "https://www.google.com/search?q=site:$domain"
        Write-Host $cmd
        $randInterval = [System.Random]::new().Next($RandomRange[0], $RandomRange[1])
        Write-Verbose "Waiting $randInterval ms..."
        Start-Sleep -Milliseconds $randInterval

        Start-Process $cmd
    
    }
    
}
function Get-MysqlKeyInline
{
    <# 
    .SYNOPSIS
    将mysql密码转换为-p参数形式,便于嵌入到mysql命令行中,例如key为123456,则返回-p123456
    .EXAMPLE
    PS C:\repos\scripts> $key=Get-MysqlKeyInline -Key "123456"
    PS C:\repos\scripts> $key
        -p123456
    #>
    param (
        $Key = ''
    )
    if($key)
    {
        return " -p$key"
    }
    else
    {
        return ""
    }

    
}
function New-MysqlDB
{
    <# 
    .SYNOPSIS
    创建mysql数据库
    .DESCRIPTION
    如果数据库不存在,则创建数据库,否则提示数据库已存在
    使用-Confirm参数,可以提示用户确认是否创建数据库,更加适合测试阶段

    .PARAMETER Name
    数据库名称
    .PARAMETER Server
    数据库服务器地址
    .PARAMETER CharSet
    数据库字符集,默认为utf8mb4
    .PARAMETER Collate
    数据库排序规则,默认为utf8mb4_general_ci
    #>
    <# 
   .EXAMPLE
   #⚡️[Administrator@CXXUDESK][C:\sites\wp_sites_cxxu\2.fr\wp-content\plugins][23:19:09][UP:7.62Days]
    PS> Import-MysqlFile -Server localhost -SqlFilePath C:\sites\wp_sites_cxxu\base_sqls\2.de.sql -DatabaseName c.d -Confirm -Verbose
    VERBOSE: Use Mysql server host: localhost
    VERBOSE: Sql File exist!
    VERBOSE: check c.d database on [localhost]
    VERBOSE: mysql -h localhost -u root  -e "SHOW DATABASES LIKE 'c.d';"
    WARNING: Database 'c.d' Does not exist!

    Confirm
    Are you sure you want to perform this action?
    Performing the operation "Create Database: c.d ?" on target "localhost".
    [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):
    VERBOSE:  mysql -uroot -h localhost -e 'CREATE DATABASE `c.d` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci; show databases like "c.d";'
    +----------------+
    | Database (c.d) |
    +----------------+
    | c.d            |
    +----------------+
    VERBOSE: check c.d database on [localhost]
    VERBOSE: mysql -h localhost -u root  -e "SHOW DATABASES LIKE 'c.d';"
    Database 'c.d' exist! ...
    Database (c.d)
    c.d
    VERBOSE: cmd /c " mysql -u root -h localhost  c.d < `"C:\sites\wp_sites_cxxu\base_sqls\2.de.sql`" "

    Confirm
    Are you sure you want to perform this action?
    Performing the operation "cmd /c " mysql -u root -h localhost  c.d <
    `"C:\sites\wp_sites_cxxu\base_sqls\2.de.sql`" "" on target "localhost".
    [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        $Name,
        $Server = 'localhost',
        [alias("P")]$Port = 3306,
        [alias("User")]$MySqlUser = 'root',
        $MysqlKey = '',
        $CharSet = 'utf8mb4',
        $Collate = "utf8mb4_general_ci"
    )
    $key = Get-MysqlKeyInline -Key $MysqlKey

    $command = " mysql -u$MySqlUser -h $Server -P $Port $key -e 'CREATE DATABASE ``$Name`` CHARACTER SET $CharSet COLLATE $collate; show databases like `"$Name`";' "  
    Write-Verbose $command 

    # 提示用户输入
    # $userInput = Read-Host "Do you want to remove the database $Name? (Y/N)"
    # $userInput = $userInput.ToLower()
    # 判断用户输入是否为空（即回车）
    # if ([string]::IsNullOrEmpty($userInput) -or $userInput -eq 'y'){
    # 用户按了回车，继续执行后续代码            
    # }
    # else
    # {
    #     # 用户输入了其他内容，取消执行后续代码
    #     Write-Host "取消执行后续代码。"
    #     exit
    # }
        
    if($pscmdlet.ShouldProcess($Server, "Create Database $Name ?"))
    {
        Invoke-Expression $command
        Get-MysqlDbInfo -Name $Name -Server $Server -Port $Port -MySQLUser $MySqlUser -key $MysqlKey 
    }
    
    
}

function Start-HTTPServer
{
    <#
    .SYNOPSIS
    启动一个简单的HTTP文件服务器

    .DESCRIPTION
    将指定的本地文件夹作为HTTP服务器的根目录,默认监听在8080端口

    .PARAMETER Path
    指定要作为服务器根目录的本地文件夹路径

    .PARAMETER Port
    指定HTTP服务器要监听的端口号,默认为8080

    .EXAMPLE
    Start-SimpleHTTPServer -Path "C:\Share" -Port 8000
    将C:\Share文件夹作为根目录,在8000端口启动HTTP服务器

    .EXAMPLE
    Start-SimpleHTTPServer
    将当前目录作为根目录,在8080端口启动HTTP服务器
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path,
        
        [Parameter(Position = 1)]
        [int]$Port = 8080
    )

    Add-Type -AssemblyName System.Web
    try
    {
        # 验证路径是否存在
        if (-not (Test-Path $Path))
        {
            throw "指定的路径 '$Path' 不存在"
        }

        # 创建HTTP监听器
        $Listener = New-Object System.Net.HttpListener
        $Listener.Prefixes.Add("http://+:$Port/")

        # 尝试启动监听器
        try
        {
            $Listener.Start()
        }
        catch
        {
            throw "无法启动HTTP服务器,可能是权限不足或端口被占用: $_"
        }

        Write-Host "HTTP服务器已启动:"
        Write-Host "根目录: $Path"
        Write-Host "地址: http://localhost:$Port/"
        Write-Host "按 Ctrl+C 停止服务器(可能需要数十秒的时间,如果等不及可以考虑关闭掉对应的命令行窗口)"

        while ($Listener.IsListening)
        {
            # 等待请求
            $Context = $Listener.GetContext()
            $Request = $Context.Request
            $Response = $Context.Response
            
            # URL解码请求路径
            $DecodedPath = [System.Web.HttpUtility]::UrlDecode($Request.Url.LocalPath)
            $LocalPath = Join-Path $Path $DecodedPath.TrimStart('/')
            
            # 设置响应头，支持UTF-8
            $Response.Headers.Add("Content-Type", "text/html; charset=utf-8")
            
            # 处理目录请求
            if ((Test-Path $LocalPath) -and (Get-Item $LocalPath).PSIsContainer)
            {
                $LocalPath = Join-Path $LocalPath "index.html"
                if (-not (Test-Path $LocalPath))
                {
                    # 生成目录列表
                    $Content = Get-DirectoryListing $DecodedPath.TrimStart('/') (Get-ChildItem (Join-Path $Path $DecodedPath.TrimStart('/')))
                    $Buffer = [System.Text.Encoding]::UTF8.GetBytes($Content)
                    $Response.ContentLength64 = $Buffer.Length
                    $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                    $Response.Close()
                    continue
                }
            }

            # 处理文件请求
            if (Test-Path $LocalPath)
            {
                $File = Get-Item $LocalPath
                $Response.ContentType = Get-MimeType $File.Extension
                $Response.ContentLength64 = $File.Length
                
                # 添加文件名编码支持
                $FileName = [System.Web.HttpUtility]::UrlEncode($File.Name)
                $Response.Headers.Add("Content-Disposition", "inline; filename*=UTF-8''$FileName")
                
                $FileStream = [System.IO.File]::OpenRead($File.FullName)
                $FileStream.CopyTo($Response.OutputStream)
                $FileStream.Close()
            }
            else
            {
                # 返回404
                $Response.StatusCode = 404
                $Content = "404 - 文件未找到"
                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($Content)
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
            }

            $Response.Close()
        }
    }
    finally
    {
        if ($Listener)
        {
            $Listener.Stop()
            $Listener.Close()
        }
    }
}

function Start-HTTPServerBG
{
    param (
        # 默认shell为windows powershell,如果安装了powershell7+ (即pwsh)可以用pwsh代替;
        # 默认情况下,需要将Start-HTTPServer写入到powershell配置文件中或者powershell的自动导入模块中,否则Start-HTTPServerBG命令不可用,导致启动失败
        # $shell = "powershell",
        $shell = "pwsh", #个人使用pwsh比较习惯
        $path = "$home\desktop",
        $Port = 8080
    )
    Write-Verbose "try to start http server..." -Verbose
    # $PSBoundParameters 
    $params = [PSCustomObject]@{
        shell = $shell
        path  = $path
        Port  = $Port
    }
    Write-Output $params #不能直接用Write-Output输出字面量对象,会被当做字符串输出
    # Write-Output $shell, $path, $Port
    # $exp = "Start-Process -WindowStyle Hidden -FilePath $shell -ArgumentList { -c Start-HTTPServer -path $path -port $Port } -PassThru"
    # Write-Output $exp
    # $ps = $exp | Invoke-Expression
    
    # $func = ${Function:Start-HTTPServer} #由于Start-HttpServer完整代码过于分散,仅仅这样写不能获得完整的Start-HTTPServer函数
    $ps = Start-Process -WindowStyle Hidden -FilePath $shell -ArgumentList "-c Start-HTTPServer -path $path -port $Port" -PassThru
    #debug start-process语法
    # $ps = Start-Process -FilePath pwsh -ArgumentList "-c", "Get-Location;Pause "

    return $ps
    
}
function Get-DirectoryListing
{
    param($RelativePath, $Items)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Index of /$RelativePath</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; }
        tr:hover { background-color: #f5f5f5; }
        a { text-decoration: none; color: #0066cc; }
        .size { text-align: right; }
        .date { white-space: nowrap; }
    </style>
</head>
<body>
    <h1>Index of /$RelativePath</h1>
    <table>
        <tr>
            <th>名称</th>
            <th class="size">大小</th>
            <th class="date">修改时间</th>
        </tr>
"@

    if ($RelativePath)
    {
        $html += "<tr><td><a href='../'>..</a></td><td></td><td></td></tr>"
    }

    # 分别处理文件夹和文件，并按名称排序
    $Folders = $Items | Where-Object { $_.PSIsContainer } | Sort-Object Name
    $Files = $Items | Where-Object { !$_.PSIsContainer } | Sort-Object Name

    # 先显示文件夹
    foreach ($Item in $Folders)
    {
        $Name = $Item.Name
        $LastModified = $Item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        $EncodedName = [System.Web.HttpUtility]::UrlEncode($Name)
        
        $html += "<tr><td><a href='$EncodedName/'>$Name/</a></td><td class='size'>-</td><td class='date'>$LastModified</td></tr>"
    }

    # 再显示文件
    foreach ($Item in $Files)
    {
        $Name = $Item.Name
        $Size = Format-FileSize $Item.Length
        $LastModified = $Item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        $EncodedName = [System.Web.HttpUtility]::UrlEncode($Name)
        
        $html += "<tr><td><a href='$EncodedName'>$Name</a></td><td class='size'>$Size</td><td class='date'>$LastModified</td></tr>"
    }

    $html += @"
    </table>
    <footer style="margin-top: 20px; color: #666; font-size: 12px;">
        共 $($Folders.Count) 个文件夹, $($Files.Count) 个文件
    </footer>
</body>
</html>
"@

    return $html
}

function Format-FileSize
{
    param([long]$Size)
    
    if ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size / 1GB) }
    if ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size / 1MB) }
    if ($Size -gt 1KB) { return "{0:N2} KB" -f ($Size / 1KB) }
    return "$Size B"
}

function Get-MimeType
{
    param([string]$Extension)
    
    $MimeTypes = @{
        ".txt"  = "text/plain; charset=utf-8"
        ".ps1"  = "text/plain; charset=utf-8"
        ".py"   = "text/plain; charset=utf-8"
        ".htm"  = "text/html; charset=utf-8"
        ".html" = "text/html; charset=utf-8"
        ".css"  = "text/css; charset=utf-8"
        ".js"   = "text/javascript; charset=utf-8"
        ".json" = "application/json; charset=utf-8"
        ".jpg"  = "image/jpeg"
        ".jpeg" = "image/jpeg"
        ".png"  = "image/png"
        ".gif"  = "image/gif"
        ".pdf"  = "application/pdf"
        ".xml"  = "application/xml; charset=utf-8"
        ".zip"  = "application/zip"
        ".md"   = "text/markdown; charset=utf-8"
        ".mp4"  = "video/mp4"
        ".mp3"  = "audio/mpeg"
        ".wav"  = "audio/wav"
    }
    
    # return $MimeTypes[$Extension.ToLower()] ?? "application/octet-stream"
    $key = $Extension.ToLower()
    if ($MimeTypes.ContainsKey($key))
    {
        return $MimeTypes[$key]
    }
    return "application/octet-stream"
}

function Get-CharacterEncoding
{

    <# 
    .SYNOPSIS
    显示字符串的字符编码信息,包括Unicode编码,UTF8编码,ASCII编码
    .DESCRIPTION
    利用此函数来分析给定字符串中的各个字符的编码,尤其是空白字符,在执行空白字符替换时,可以排查出不可见字符替换不掉的问题
    .EXAMPLE
    PS> Get-CharacterEncoding -InputString "  0.46" | Format-Table -AutoSize

    Character UnicodeCode UTF8Encoding AsciiCode
    --------- ----------- ------------ ---------
            U+0020      0x20                32
              U+00A0      0xC2 0xA0          N/A
            0 U+0030      0x30                48
            . U+002E      0x2E                46
            4 U+0034      0x34                52
            6 U+0036      0x36                54
    #>
    param (
        [string]$InputString
    )
    $utf8 = [System.Text.Encoding]::UTF8

    $InputString.ToCharArray() | ForEach-Object {
        $char = $_
        $unicode = [int][char]$char
        $utf8Bytes = $utf8.GetBytes([char[]]$char)
        $utf8Hex = $utf8Bytes | ForEach-Object { "0x{0:X2}" -f $_ }
        $ascii = if ($unicode -lt 128) { $unicode } else { "N/A" }

        [PSCustomObject]@{
            Character    = $char
            UnicodeCode  = "U+{0:X4}" -f $unicode
            UTF8Encoding = ($utf8Hex -join " ")
            AsciiCode    = $ascii
        }
    }
}




function Get-CharacterEncodingsGUI
{
    # 加载 Windows Forms 程序集
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # 定义函数
    function Get-CharacterEncoding
    {
        param (
            [string]$InputString
        )
        $utf8 = [System.Text.Encoding]::UTF8

        $InputString.ToCharArray() | ForEach-Object {
            $char = $_
            $unicode = [int][char]$char
            $utf8Bytes = $utf8.GetBytes([char[]]$char)
            $utf8Hex = $utf8Bytes | ForEach-Object { "0x{0:X2}" -f $_ }
            $ascii = if ($unicode -lt 128) { $unicode } else { "N/A" }

            [PSCustomObject]@{
                Character    = $char
                UnicodeCode  = "U+{0:X4}" -f $unicode
                UTF8Encoding = ($utf8Hex -join " ")
                AsciiCode    = $ascii
            }
        }
    }

    # 创建主窗体
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "字符编码实时解析"
    $form.Size = New-Object System.Drawing.Size(800, 600)
    $form.StartPosition = "CenterScreen"

    # 创建输入框
    $inputBox = New-Object System.Windows.Forms.TextBox
    $inputBox.Location = New-Object System.Drawing.Point(10, 10)
    $inputBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $inputBox.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12)
    $inputBox.Multiline = $true
    $inputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $inputBox.WordWrap = $true
    $inputBox.Size = New-Object System.Drawing.Size(760, 60)
    $form.Controls.Add($inputBox)

    # 创建结果显示框
    $resultBox = New-Object System.Windows.Forms.TextBox
    $resultBox.Location = New-Object System.Drawing.Point(10, ($inputBox.Location.Y + $inputBox.Height + 10)) # 使用数值计算位置
    $resultBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $resultBox.Multiline = $true
    $resultBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $resultBox.ReadOnly = $true
    $resultBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $resultBox.Size = New-Object System.Drawing.Size(760, ($form.ClientSize.Height - ($inputBox.Location.Y + $inputBox.Height + 20)))
    $form.Controls.Add($resultBox)

    # 动态调整输入框高度
    $inputBox.Add_TextChanged({
            $lineCount = $inputBox.Lines.Length
            $fontHeight = $inputBox.Font.Height
            $padding = 10
            $newHeight = ($lineCount * $fontHeight) + $padding

            # 限制最小和最大高度
            $minHeight = 60
            $maxHeight = 200
            $inputBox.Height = [Math]::Min([Math]::Max($newHeight, $minHeight), $maxHeight)

            # 调整结果框位置和高度
            $resultBox.Top = $inputBox.Location.Y + $inputBox.Height + 10
            $resultBox.Height = $form.ClientSize.Height - $resultBox.Top - 10
        })

    # 实时解析事件
    $inputBox.Add_TextChanged({
            $inputText = $inputBox.Text
            if (-not [string]::IsNullOrEmpty($inputText))
            {
                $result = Get-CharacterEncoding -InputString $inputText | Format-Table | Out-String
                $resultBox.Text = $result
            }
            else
            {
                $resultBox.Clear()
            }
        })

    # 窗体大小调整事件
    $form.Add_SizeChanged({
            $inputBox.Width = $form.ClientSize.Width - 20
            $resultBox.Width = $form.ClientSize.Width - 20
            $resultBox.Height = $form.ClientSize.Height - $resultBox.Top - 10
        })

    # 显示窗口
    [void]$form.ShowDialog()
}
function Get-UrlListFromDir
{
    <# 
    .SYNOPSIS
    列出指定目录下的所有html文件,构造合适成适合采集的url链接列表,并输出到文件
    #>
    [cmdletbinding()]
    param(
        # html文件所在路径
        $Path,
        $Hst = "local",
        $Port = "80",
        # Url中的路径部分(也可以先输出,然后根据结果调整html所在位置)
        $UrlPath = "",
        # 输出文件路径(如果不指定,则默认输出到$Path的同级别目录下)
        $Output = "",
        [switch]$LocTagMode
    )
    if(Test-Path -Path $Path -PathType Container)
    {
        $DirBaseName = Split-Path $Path -Leaf
    }
    else
    {
        Write-Error "Path [$Path] does not exist or is not a directory!"
        return
    }
    # 生成本地页面url文件列表
    $res = Get-ChildItem $Path | ForEach-Object { 
        $url = "http://${hst}:${Port}/$DirBaseName/$(Split-Path $_ -Leaf)" 
        if($LocTagMode)
        {
            $url = "<loc>$url</loc>"
        }
        $url
    } 
    if(!$Output)
    {
        $Output = "$Path/../$(Split-Path $Path -Leaf).txt"
    }
    $res | Out-File -FilePath "$output"
    Write-Verbose "Output to file: $output" -Verbose
    # 采集 http[参数] -> http[参数1]
    # 预览前10行
    $preview = Get-Content $output | Select-Object -First 10 | Out-String
    Write-Verbose "Preview: $preview" -Verbose
    return $res    
}


function regex_tk_tool
{
    $p = Resolve-Path "$PSScriptRoot/../../pythonScripts/regex_tk_tool.py"
    Write-Verbose "$p"
    python $p
}
function Get-RepositoryVersion
{
    <# 
    通过git提交时间显示版本情况
    #>
    param (
        $Repository = './'
    )
    $Repository = Resolve-Path $Repository
    Write-Verbose "Repository:[$Repository]" -Verbose
    Write-Output $Repository
    Push-Location $Repository
    git log -1
    Pop-Location
    # Set-Location $Repository
    # git log -1 
    # Set-Location -

    # git log -1 --pretty=format:'%h - %an, %ar%n%s'
    
}
function Set-Defender
{
    . "$PSScriptRoot\..\..\cmd\WDC.bat"
}
function Get-UrlFromSitemap
{
    <# 
    .SYNOPSIS
    从站点地图（sitemap）文件中提取URL。
    
    .DESCRIPTION
    该函数读取sitemap文件，并使用正则表达式提取其中的URL。它可以通过管道接收输入，并支持指定URL的匹配模式。
    
    .PARAMETER Path
    指定sitemap文件(.xml文件)的路径。该参数支持从管道或通过属性名称从管道接收输入。
    
    
    .PARAMETER UrlPattern
    指定用于匹配URL的正则表达式模式。默认值为"<loc>(.*?)</loc>"，这是针对大多数sitemap.xml文件中URL格式的通用模式。
    
    .EXAMPLE
    Get-UrlFromSitemap -Path "C:\sitemap.xml"
    从C:\sitemap.xml文件中提取URL，默认使用"<loc>(.*?)</loc>"作为匹配模式。
    
    .EXAMPLE
    # 从管道接收sitemap文件路径
    "C:\sitemap.xml" | Get-UrlFromSitemap -UrlPattern "<url>(.*?)</url>"
    从C:\sitemap.xml文件中提取URL，使用"<url>(.*?)</url>"作为匹配模式。

    .EXAMPLE
    # 从多个sitemap文件中提取URL，并将结果输出到文件
    PS> ls Sitemap*.xml|Get-UrlFromSitemap |Out-File links.1.txt
    Pattern to match URLs: <loc>(.*?)</loc>
    Processing sitemap at path: C:\sites\wp_sites\local\maps\Sitemap1.xml [C:\sites\wp_sites\local\maps\Sitemap1.xml]
    Processing sitemap at path: C:\sites\wp_sites\local\maps\Sitemap2.xml [C:\sites\wp_sites\local\maps\Sitemap2.xml]

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        $Path,
        $UrlPattern = "<loc>(.*?)</loc>"
    )
    begin
    {
        Write-Host "Pattern to match URLs: $UrlPattern" -ForegroundColor Cyan
    }
    process
    {
        $abs = Get-Item $Path | Select-Object -ExpandProperty FullName
        Write-Host "Processing sitemap at path: $Path [$abs]"

        $content = Get-Content $Path -Raw
        $ms = [regex]::Matches($content, $UrlPattern)
        $ms | ForEach-Object { $_.Groups[1].Value }
    }
}
function Format-IndexObject
{
    <# 
    .SYNOPSIS
    将数组格式化为带行号的表格,第一列为Index(如果不是可以自行select调整)，其他列为原来数组中元素对象的属性列
    .DESCRIPTION
    可以和轻量的Format-DoubleColumn互补,但是不要同时使用它们
    #>
    <# 
    .EXAMPLE
    PS> Get-EnvList -Scope User|Format-IndexObject

    Indexi Scope Name                     Value
    ------ ----- ----                     -----
        1 User  MSYS2_MINGW              C:\msys64\ucrt64\bin
        2 User  NVM_SYMLINK              C:\Program Files\nodejs
        3 User  powershell_updatecheck   LTS
        4 User  GOPATH                   C:\Users\cxxu\go
        5 User  Path                     C:\repos\scripts;...
    #>
    param (
        [parameter(ValueFromPipeline)]
        $InputObject,
        $IndexColumnName = 'Index_i'
    )
    begin
    {
        $index = 1
    }
    process
    {
        foreach ($item in $InputObject)
        {
            # $e=[PSCustomObject]@{
            #     Index = $index
           
            # }
            $item | Add-Member -MemberType NoteProperty -Name $IndexColumnName -Value $index -ErrorAction Break
            $index++
            Write-Debug "$IndexColumnName=$index"
        
            # 使用get-member查看对象结构
            # $item | Get-Member
            $item | Select-Object *
        }
    }
}

function Format-EnvItemNumber
{
    <#
    .SYNOPSIS 
    辅助函数,用于将Get-EnvList(或Get-EnvVar)的返回值转换为带行号的表格
 
     #>
    [OutputType([EnvVar[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [envvar[]] $Envvar,
        #是否显式传入Scope
        $Scope = 'Combined'
    )
    # 对数组做带序号（index）的枚举操作,经常使用此for循环
    begin
    {
        $res = @()
        $index = 1
    }
    process
    {
        # for ($i = 0; $i -lt $Envvar.Count; $i++)
        # {
        #     # 适合普通方式调用,不适合管道传参(对计数不友好,建议用foreach来遍历)
        #     Write-Debug "i=$i" #以管道传参调用本函数是会出现不正确计数,$Envvar总是只有一个元素,不同于不同传参,这里引入index变量来计数
        # } 

        foreach ($env in $Envvar)
        {
            # $env = [PSCustomObject]@{
            #     'Number' = $index 
            #     'Scope'  = $env.Scope
            #     'Name'   = $Env.Name
            #     'Value'  = $Env.Value
            # }
      
            $value = $env | Select-Object -ExpandProperty value 
            $value = $value -split ';' 
            Write-Debug "$($value.count)"
            $tb = $value | Format-DoubleColumn
            $separator = "-End OF-$index-[$($env.Name)]-------------------`n"
            Write-Debug "$env , index=$index"
            $index++
            $res += $tb + $separator
        }
    }
    end
    {
        Write-Debug "count=$($res.count)"
        return $res 
    }
}
function Format-DoubleColumn
{

    <# 
    .SYNOPSIS
    将数组格式化为双列,第一列为Index，第二列为Value,完成元素计数和展示任务
    .DESCRIPTION
    支持管道符,将数组通过管道符传递给此函数即可
    还可以进一步传递结果给Format-table做进一步格式化等操作,比如换行等操作
    #>
    <# 
    .EXAMPLE
    $array = @("Apple", "Banana", "Cherry", "Date", "Elderberry")
    $array | Format-DoubleColumn | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$InputObject
    )

    begin
    {
        $index = 1

    }

    process
    {
        # Write-Debug "InputObject Count: $($InputObject.Count)"
        # Write-Debug "InputObject:$inputObject"
        foreach ($item in $InputObject)
        {
            [PSCustomObject]@{
                Index = $index
                Value = $item
            }
            $index++
        }
    }
}
function Set-ExplorerSoftwareIcons
{
    <# 
    .SYNOPSIS
    本命令用于禁用系统Explorer默认的计算机驱动器以外的软件图标,尤其是国内的网盘类软件(百度网盘,夸克网盘,迅雷,以及许多视频类软件)
    也可以撤销禁用
    .PARAMETER Enabled
    是否允许软件设置资源管理器内的驱动器图标
    使用True表示允许
    使用False表示禁用(默认)
    .NOTES
    使用管理员权限执行此命令
    .NOTES
    如果软件是为全局用户安装的,那么还需要考虑HKLM,而不是仅仅考虑HKCU
    ls 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\'
    #>
    <# 
    .EXAMPLE
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled True
    refresh explorer to check icons
    #禁用其他软件设置资源管理器驱动器图标
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled False
    refresh explorer to check icons
    .EXAMPLE
    显示设置过程信息
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled True -Verbose
    # VERBOSE: Enabled Explorer Software Icons (allow Everyone Permission)
    refresh explorer to check icons
    .EXAMPLE
    显示设置过程信息,并且启动资源管理器查看刷新后的图标是否被禁用或恢复
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled True -Verbose -RefreshExplorer
    VERBOSE: Enabled Explorer Software Icons (allow Everyone Permission)
    refresh explorer to check icons
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled False -Verbose -RefreshExplorer
    VERBOSE: Disabled Explorer Software Icons (Remove Everyone Group Permission)
    refresh explorer to check icons

    #>
    [CmdletBinding()]
    param (
        [ValidateSet('True', 'False')]$Enabled ,
        [switch]$RefreshExplorer
    )
    $pathUser = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'
    $pathMachine = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'
    function Set-PathPermission
    {
        param (
            $Path
        )
        
        $acl = Get-Acl -Path $path -ErrorAction SilentlyContinue
    
        # 禁用继承并删除所有继承的访问规则
        $acl.SetAccessRuleProtection($true, $false)
    
        # 清除所有现有的访问规则
        $acl.Access | ForEach-Object {
            # $acl.RemoveAccessRule($_) | Out-Null
            $acl.RemoveAccessRule($_) *> $null
        } 
    
    
        # 添加SYSTEM和Administrators的完全控制权限
        $identities = @(
            'NT AUTHORITY\SYSTEM'
            # ,
            # 'BUILTIN\Administrators'
        )
        if ($Enabled -eq 'True')
        {
            $identities += @('Everyone')
            Write-Verbose "Enabled Explorer Software Icons [$path] (allow Everyone Permission)"
        }
        else
        {
            Write-Verbose "Disabled Explorer Software Icons [$path] (Remove Everyone Group Permission)"
        }
        foreach ($identity in $identities)
        {
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
    
        # 应用新的ACL
        Set-Acl -Path $path -AclObject $acl # -ErrorAction Stop
    }
    foreach ($path in @($pathUser, $pathMachine))
    {
        Set-PathPermission -Path $path *> $null
    }
    Write-Host 'refresh explorer to check icons'    
    if ($RefreshExplorer)
    {
        explorer.exe
    }
}

function Get-StylePathByDotNet
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
        [string]$Path,

        [ValidateSet("Windows", "Linux")]
        [string]$Style = "windows"
    )

    # 1. 先获取完整路径，确保是绝对路径（可处理 .、..）
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
function Get-StylePath
{
    [CmdletBinding()]
    param(
        [string]$Path,

        [ValidateSet("Windows", "Linux")]
        [string]$Style = "Windows"
    )

    # 去掉左右多余空格
    $normalizedPath = $Path.Trim()

    switch ($Style)
    {
        "Windows"
        {
            # 替换所有正斜杠为反斜杠
            $convertedPath = $normalizedPath -replace '/', '\'
        }
        "Linux"
        {
            # 替换所有反斜杠为正斜杠
            $convertedPath = $normalizedPath -replace '\\', '/'
        }
    }
    Write-Verbose "convert process: $path -> $convertedPath"
    return $convertedPath
}


function pow
{
    [CmdletBinding()]
    param(
        [double]$base,
        [double]$exponent
    )
    return [math]::pow($base, $exponent)
}

# function invoke-aria2Downloader
# {
#     param (
#         $url,
#         [Alias('spilit')]
#         $s = 16,
        
#         [Alias('max-connection-per-server')]
#         $x = 16,

#         [Alias('min-split-size')]
#         $k = '1M'
#     )
#     aria2c -s $s -x $s -k $k $url
    
# }

function Set-ScreenResolutionAndOrientation-AntiwiseClock
{ 
    <#  :cmd header for PowerShell script
    @   set dir=%~dp0
    @   set ps1="%TMP%\%~n0-%RANDOM%-%RANDOM%-%RANDOM%-%RANDOM%.ps1"
    @   copy /b /y "%~f0" %ps1% >nul
    @   powershell -NoProfile -ExecutionPolicy Bypass -File %ps1% %*
    @   del /f %ps1%
    @   goto :eof
    #>

    <# 
    .Synopsis 
        Sets the Screen Resolution of the primary monitor 
    .Description 
        Uses Pinvoke and ChangeDisplaySettings Win32API to make the change 
    .Example 
        Set-ScreenResolutionAndOrientation         
        
    URL: http://stackoverflow.com/questions/12644786/powershell-script-to-change-screen-orientation?answertab=active#tab-top
    CMD: powershell.exe -ExecutionPolicy Bypass -File "%~dp0ChangeOrientation.ps1"
#>

    $pinvokeCode = @" 

using System; 
using System.Runtime.InteropServices; 

namespace Resolution 
{ 

    [StructLayout(LayoutKind.Sequential)] 
    public struct DEVMODE 
    { 
       [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]
       public string dmDeviceName;

       public short  dmSpecVersion;
       public short  dmDriverVersion;
       public short  dmSize;
       public short  dmDriverExtra;
       public int    dmFields;
       public int    dmPositionX;
       public int    dmPositionY;
       public int    dmDisplayOrientation;
       public int    dmDisplayFixedOutput;
       public short  dmColor;
       public short  dmDuplex;
       public short  dmYResolution;
       public short  dmTTOption;
       public short  dmCollate;

       [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
       public string dmFormName;

       public short  dmLogPixels;
       public short  dmBitsPerPel;
       public int    dmPelsWidth;
       public int    dmPelsHeight;
       public int    dmDisplayFlags;
       public int    dmDisplayFrequency;
       public int    dmICMMethod;
       public int    dmICMIntent;
       public int    dmMediaType;
       public int    dmDitherType;
       public int    dmReserved1;
       public int    dmReserved2;
       public int    dmPanningWidth;
       public int    dmPanningHeight;
    }; 

    class NativeMethods 
    { 
        [DllImport("user32.dll")] 
        public static extern int EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode); 
        [DllImport("user32.dll")] 
        public static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags); 

        public const int ENUM_CURRENT_SETTINGS = -1; 
        public const int CDS_UPDATEREGISTRY = 0x01; 
        public const int CDS_TEST = 0x02; 
        public const int DISP_CHANGE_SUCCESSFUL = 0; 
        public const int DISP_CHANGE_RESTART = 1; 
        public const int DISP_CHANGE_FAILED = -1;
        public const int DMDO_DEFAULT = 0;
        public const int DMDO_90 = 1;
        public const int DMDO_180 = 2;
        public const int DMDO_270 = 3;
    } 



    public class PrmaryScreenResolution 
    { 
        static public string ChangeResolution() 
        { 

            DEVMODE dm = GetDevMode(); 

            if (0 != NativeMethods.EnumDisplaySettings(null, NativeMethods.ENUM_CURRENT_SETTINGS, ref dm)) 
            {

                // swap width and height
                int temp = dm.dmPelsHeight;
                dm.dmPelsHeight = dm.dmPelsWidth;
                dm.dmPelsWidth = temp;

                // determine new orientation based on the current orientation
                switch(dm.dmDisplayOrientation)
                {
                    case NativeMethods.DMDO_DEFAULT:
                        //dm.dmDisplayOrientation = NativeMethods.DMDO_270;
                        //2016-10-25/EBP wrap counter clockwise
                        dm.dmDisplayOrientation = NativeMethods.DMDO_90;
                        break;
                    case NativeMethods.DMDO_270:
                        dm.dmDisplayOrientation = NativeMethods.DMDO_180;
                        break;
                    case NativeMethods.DMDO_180:
                        dm.dmDisplayOrientation = NativeMethods.DMDO_90;
                        break;
                    case NativeMethods.DMDO_90:
                        dm.dmDisplayOrientation = NativeMethods.DMDO_DEFAULT;
                        break;
                    default:
                        // unknown orientation value
                        // add exception handling here
                        break;
                }


                int iRet = NativeMethods.ChangeDisplaySettings(ref dm, NativeMethods.CDS_TEST); 

                if (iRet == NativeMethods.DISP_CHANGE_FAILED) 
                { 
                    return "Unable To Process Your Request. Sorry For This Inconvenience."; 
                } 
                else 
                { 
                    iRet = NativeMethods.ChangeDisplaySettings(ref dm, NativeMethods.CDS_UPDATEREGISTRY); 
                    switch (iRet) 
                    { 
                        case NativeMethods.DISP_CHANGE_SUCCESSFUL: 
                            { 
                                return "Success"; 
                            } 
                        case NativeMethods.DISP_CHANGE_RESTART: 
                            { 
                                return "You Need To Reboot For The Change To Happen.\n If You Feel Any Problem After Rebooting Your Machine\nThen Try To Change Resolution In Safe Mode."; 
                            } 
                        default: 
                            { 
                                return "Failed To Change The Resolution"; 
                            } 
                    } 

                } 


            } 
            else 
            { 
                return "Failed To Change The Resolution."; 
            } 
        } 

        private static DEVMODE GetDevMode() 
        { 
            DEVMODE dm = new DEVMODE(); 
            dm.dmDeviceName = new String(new char[32]); 
            dm.dmFormName = new String(new char[32]); 
            dm.dmSize = (short)Marshal.SizeOf(dm); 
            return dm; 
        } 
    } 
} 

"@ 

    Add-Type $pinvokeCode -ErrorAction SilentlyContinue 
    [Resolution.PrmaryScreenResolution]::ChangeResolution() 
}


# Set-ScreenResolutionAndOrientation

function Set-PythonPipSource
{
    param (
        $mirror = 'https://pypi.tuna.tsinghua.edu.cn/simple'
    )
    pip config set global.index-url $mirror
    $config = "$env:APPDATA/pip/pip.ini"
    if(Test-Path $config)
    {
        Get-Content $config
    }
    pip config list
}
function Get-MsysSourceScript
{
    <# 
    .SYNOPSIS
    获取更新msys2下pacman命令的换源脚本,默认换为清华源
    
    .NOTES
    将输出的脚本复制到剪切板,然后粘贴到msys2命令行窗口中执行
    #>
    param (

    )
    $script = { sed -i 's#https\?://mirror.msys2.org/#https://mirrors.tuna.tsinghua.edu.cn/msys2/#g' /etc/pacman.d/mirrorlist* }
    
    return $script.ToString()
}
function Set-CondaSource
{
    param (
        
    )
    
    #备份旧配置,如果有的话
    if (Test-Path "$userprofile\.condarc")
    {
        Copy-Item "$userprofile\.condarc" "$userprofile\.condarc.bak"
    }
    #写入内容
    @'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  msys2: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  bioconda: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  menpo: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch-lts: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  simpleitk: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  deepmodeling: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/
'@ >"$userprofile\.condarc"

    Write-Host 'Check your conda config...'
    conda config --show-sources
}
function Deploy-WindowsActivation
{
    # Invoke-RestMethod https://massgrave.dev/get | Invoke-Expression

    Invoke-RestMethod https://get.activated.win | Invoke-Expression
}
function Get-BeijingTime
{
    # 获取北京时间的函数
    # 通过API获取北京时间
    $url = 'http://worldtimeapi.org/api/timezone/Asia/Shanghai'
    $response = Invoke-RestMethod -Uri $url
    $beijingTime = [DateTime]$response.datetime
    return $beijingTime
}
function Enable-WindowsUpdateByDelay
{
    $reg = "$PsScriptRoot\..\..\registry\windows-updates-unpause.reg" | Resolve-Path
    Write-Host $reg
    & $reg
}
function Disable-WindowsUpdateByDelay
{
    $reg = "$PsScriptRoot\..\..\registry\windows-updates-pause.reg" | Resolve-Path
    Write-Host $reg
    & $reg
}
function Get-BootEntries
{
    
    chcp 437 >$null; cmd /c bcdedit | Write-Output | Out-String -OutVariable bootEntries *> $null


    # 使用正则表达式提取identifier和description
    $regex = "identifier\s+(\{[^\}]+\})|\bdevice\s+(.+)|description\s+(.+)"
    $ms = [regex]::Matches($bootEntries, $regex)
    # $matches


    $entries = @()
    $ids = @()
    $devices = @()
    $descriptions = @()
    foreach ($match in $ms)
    {
        $identifier = $match.Groups[1].Value
        $device = $match.Groups[2].Value
        $description = $match.Groups[3].Value

        if ($identifier  )
        {
            $ids += $identifier
        }
        if ($device)
        {
            $devices += $device
        }
        if ( $description )
        {
            $descriptions += $description
        }

    }
    foreach ($id in $ids)
    {
        $entries += [PSCustomObject]@{
            Identifier  = $id
            device      = $devices[$ids.IndexOf($id)]
            Description = $descriptions[$ids.IndexOf($id)]
        }
    }

    Write-Output $entries
}
function Get-WindowsVersionInfoOnDrive
{
    <# 
    .SYNOPSIS
    查询安装在指定盘符的Windows版本信息,默认查询D盘上的windows系统版本

    .EXAMPLE
    $driver = "D"
    $versionInfo = Get-WindowsVersionInfo -Driver $driver

    # 输出版本信息
    $versionInfo | Format-List

    #>
    param (
        # [Parameter(Mandatory = $true)]
        [string]$Driver = "D"
    )

    # 确保盘符格式正确
    if (-not $Driver.EndsWith(":"))
    {
        $Driver += ":"
    }

    try
    {
        # 加载指定盘符的注册表
        reg load HKLM\TempHive "$Driver\Windows\System32\config\SOFTWARE" | Out-Null

        # 获取Windows版本信息
        $osInfo = Get-ItemProperty -Path 'HKLM:\TempHive\Microsoft\Windows NT\CurrentVersion'

        # 创建一个对象保存版本信息
        $versionInfo = [PSCustomObject]@{
            WindowsVersion = $osInfo.ProductName
            OSVersion      = $osInfo.DisplayVersion
            BuildNumber    = $osInfo.CurrentBuild
            UBR            = $osInfo.UBR
            LUVersion      = $osInfo.ReleaseId
        }

        # 卸载注册表
        reg unload HKLM\TempHive | Out-Null

        # 返回版本信息
        return $versionInfo
    }
    catch
    {
        Write-Error "无法加载注册表或获取信息，请确保指定的盘符是有效的Windows安装盘符。"
    }
}

function rebootToOS
{
    Add-Type -AssemblyName PresentationFramework
    $bootEntries = Get-BootEntries
    $bootEntries = $bootEntries | ForEach-Object {
        [PSCustomObject]@{
            Identifier  = $_.Identifier
            Description = $_.Description + $_.device + "`n$($_.Identifier)" 
        } 
    }

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Reboot Utility (by @Cxxu)" Height="600" Width="450" WindowStartupLocation="CenterScreen"
        Background="White" AllowsTransparency="False" WindowStyle="SingleBorderWindow">
    <Grid>
        <Border Background="White" CornerRadius="10" BorderBrush="Gray" BorderThickness="1" Padding="10">
            <StackPanel>
                <TextBlock Text="Select a system to reboot into (从列表中选择重启项目):" Margin="10" FontWeight="Bold" FontSize="14"/>
                <ListBox Name="BootEntryList" Margin="10" Background="LightBlue" BorderThickness="0">
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <Border Background="LightGray" CornerRadius="10" Padding="5" Margin="5">
                                <TextBlock Text="{Binding Description}" Margin="5,0,0,0"/>
                            </Border>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>
                <Button Name="RebootButton" Content="Reboot | 点击重启" Margin="10" HorizontalAlignment="Center" Width="140" Background="#FF2A2A" Foreground="White" FontWeight="Bold" Cursor="Hand">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Background" Value="#FF2A2A"/>
                            <Setter Property="Foreground" Value="White"/>
                            <Setter Property="FontWeight" Value="Bold"/>
                            <Setter Property="Cursor" Value="Hand"/>
                            <Style.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="#FF5555"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </Button.Style>
                </Button>
                <Button Name="RebootToBios" Content="Restart to BIOS" Width="200" Height="30" Margin="10" HorizontalAlignment="Center" Background="#FF2A2A" Foreground="White" FontWeight="Bold" Cursor="Hand">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Background" Value="#FF2A2A"/>
                            <Setter Property="Foreground" Value="White"/>
                            <Setter Property="FontWeight" Value="Bold"/>
                            <Setter Property="Cursor" Value="Hand"/>
                            <Style.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="#FF5555"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </Button.Style>
                </Button>
                <TextBlock HorizontalAlignment="Center" Margin="10">
                    <Hyperlink Name="iReboot">iReboot</Hyperlink>
                </TextBlock>
                <TextBlock HorizontalAlignment="Center" Margin="10">
                    <Hyperlink Name="EasyBCD">EasyBCD</Hyperlink>
                </TextBlock>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@

    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # 重启到指定系统获取控件
    $listBox = $window.FindName("BootEntryList")
    $button = $window.FindName("RebootButton")
    # 其他控件
    $RebootToBios = $window.FindName("RebootToBios")
    $iReboot = $window.FindName("iReboot")
    $EasyBCD = $window.FindName("EasyBCD")

    # 填充ListBox
    $listBox.ItemsSource = $bootEntries

    # 定义重启按钮点击事件
    $button.Add_Click({
            $selectedEntry = $listBox.SelectedItem
            if ($null -ne $selectedEntry)
            {
                $identifier = $selectedEntry.Identifier
                $confirmReboot = [System.Windows.MessageBox]::Show(
                    "Are you sure you want to reboot to $($selectedEntry.Description)?", 
                    "Confirm Reboot", 
                    [System.Windows.MessageBoxButton]::YesNo, 
                    [System.Windows.MessageBoxImage]::Warning
                )
                if ($confirmReboot -eq [System.Windows.MessageBoxResult]::Yes)
                {
                    Write-Output "Rebooting to: $($selectedEntry.Description) with Identifier $identifier"
                    cmd /c bcdedit /bootsequence $identifier
                    Write-Host "Rebooting to $($selectedEntry.Description) after 3 seconds! (close the shell to stop/cancel it)"
                    Start-Sleep 3
                    shutdown.exe /r /t 0
                }
            }
            else
            {
                [System.Windows.MessageBox]::Show("Please select an entry to reboot into.", "No Entry Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            }
        })

    # 定义关机按钮点击事件
    $RebootToBios.Add_Click({
            $confirmShutdown = [System.Windows.MessageBox]::Show(
                "Are you sure you want to shutdown and restart?", 
                "Confirm Shutdown", 
                [System.Windows.MessageBoxButton]::YesNo, 
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($confirmShutdown -eq [System.Windows.MessageBoxResult]::Yes)
            {
                Write-Output "Executing shutdown command"
                Start-Process "shutdown.exe" -ArgumentList "/fw", "/r", "/t", "0"
            }
        })

    # 定义链接点击事件
    $iReboot.Add_Click({
            Start-Process "https://neosmart.net/iReboot/?utm_source=EasyBCD&utm_medium=software&utm_campaign=EasyBCD iReboot"
        })

    $EasyBCD.Add_Click({
            Start-Process "https://neosmart.net/EasyBCD/"
        })

    # 显示窗口
    $window.ShowDialog()
}


function Set-TaskBarTime
{
    <# 
    .SYNOPSIS
    sShortTime：控制系统中短时间,不显示秒（例如 HH:mm）的显示格式，HH 表示24小时制（H 单独使用则表示12小时制）。
    sTimeFormat：控制系统的完整时间格式(长时间格式,相比于短时间格式增加了秒数显示)
    .EXAMPLE
    #设置为12小时制,且小时为个位数时不补0
     Set-TaskBarTime -TimeFormat h:mm:ss 
     .EXAMPLE
    #设置为24小时制，且小时为个位数时不补0
     Set-TaskBarTime -TimeFormat H:mm:ss
     .EXAMPLE
    #设置为24小时制，且小时为个位数时补0
     Set-TaskBarTime -TimeFormat HH:mm:ss
    #>
    param (
        # $ShortTime = 'HH:mm',
        $TimeFormat = 'H:mm:ss'
    )
    Set-ItemProperty -Path 'HKCU:\Control Panel\International' -Name 'sShortTime' -Value $ShortTime
    Set-ItemProperty -Path 'HKCU:\Control Panel\International' -Name 'sTimeFormat' -Value $TimeFormat

    
}
function Sync-SystemTime
{
    <#
    .SYNOPSIS
        同步系统时间到 time.windows.com NTP 服务器。
    .DESCRIPTION
        使用 Windows 内置的 w32tm 命令同步本地系统时间到 time.windows.com。
        同步完成后，显示当前系统时间。
        w32tm 是 Windows 中用于管理和配置时间同步的命令行工具。以下是一些常用的 w32tm 命令和参数介绍：

        常用命令
        w32tm /query /status
        显示当前时间服务的状态，包括同步源、偏差等信息。
        w32tm /resync
        强制系统与配置的时间源重新同步。
        w32tm /config /manualpeerlist:"<peers>" /syncfromflags:manual /reliable:YES /update
        配置手动指定的 NTP 服务器列表（如 time.windows.com），并更新设置。
        w32tm /query /peers
        列出当前配置的时间源（NTP 服务器）。
        w32tm /stripchart /computer:<target> /dataonly
        显示与目标计算机之间的时差，类似 ping 的方式。
        注意事项
        运行某些命令可能需要管理员权限。
        确保你的网络设置允许访问 NTP 服务器。
        适用于 Windows Server 和 Windows 客户端版本。
    .NOTES
        需要管理员权限运行。
    .EXAMPLE
    # 调用函数
    # Sync-SystemTime
    #>
    try
    {
        # 配置 NTP 服务器
        w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:YES /update
        
        # 同步时间
        w32tm /resync

        # 显示当前时间
        $currentTime = Get-Date
        Write-Output "当前系统时间: $currentTime"
    }
    catch
    {
        Write-Error "无法同步时间: $_"
    }
}

function Update-SystemTime
{
    # 获取北京时间的函数
   

    # 显示当前北京时间
    $beijingTime = Get-BeijingTime
    Write-Output "当前北京时间: $beijingTime"

    # 设置本地时间为北京时间（需要管理员权限）
    # Set-Date -Date $beijingTime
}
function Update-DataJsonLastWriteTime
{
    param (
        $DataJson = $DataJson
    )
    Update-Json -Key LastWriteTime -Value (Get-Date) -DataJson $DataJson
}
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
function Update-Json
{
    <# 
    .SYNOPSIS
    提供创建/修改/删除JSON文件中的配置项目的功能
    #>
    [CmdletBinding()]
    param (
        [string]$Key,
        [string]$Value,
        [switch]$Remove,
        [string][Alias('DataJson')]$Path = $DataJson
    )
    
    # 如果配置文件不存在，创建一个空的JSON文件
    if (-not (Test-Path $Path))
    {
        Write-Verbose "Configuration file '$Path' does not exist. Creating a new one."
        $emptyConfig = @{}
        $emptyConfig | ConvertTo-Json -Depth 32 | Set-Content $Path
    }

    # 读取配置文件
    $config = Get-Content $Path | ConvertFrom-Json

    if ($Remove)
    {
        if ($config.PSObject.Properties[$Key])
        {
            $config.PSObject.Properties.Remove($Key)
            Write-Verbose "Removed '$Key' from '$Path'"
        }
        else
        {
            Write-Verbose "Key '$Key' does not exist in '$Path'"
        }
    }
    else
    {
        # 检查键是否存在，并动态添加新键
        if (-not $config.PSObject.Properties[$Key])
        {
            $config | Add-Member -MemberType NoteProperty -Name $Key -Value $Value
        }
        else
        {
            $config.$Key = $Value
        }
        Write-Verbose "Updated '$Key' to '$Value' in '$Path'"
    }

    # 保存配置文件
    $config | ConvertTo-Json -Depth 32 | Set-Content $Path
}

function Convert-MarkdownToHtml
{
    <#
    .SYNOPSIS
    将Markdown文件转换为HTML文件。

    .DESCRIPTION
    这个函数使用PowerShell内置的ConvertFrom-Markdown cmdlet将指定的Markdown文件转换为HTML文件。
    它可以处理单个文件或整个目录中的所有Markdown文件。

    .PARAMETER Path
    指定要转换的Markdown文件的路径或包含Markdown文件的目录路径。

    .PARAMETER OutputDirectory
    指定生成的HTML文件的输出目录。如果不指定，将在原始文件的同一位置创建HTML文件。

    .PARAMETER Recurse
    如果指定，将递归处理子目录中的Markdown文件。

    .EXAMPLE
    Convert-MarkdownToHtml -Path "C:\Documents\sample.md"
    将单个Markdown文件转换为HTML文件。

    .EXAMPLE
    Convert-MarkdownToHtml -Path "C:\Documents" -OutputDirectory "C:\Output" -Recurse
    将指定目录及其子目录中的所有Markdown文件转换为HTML文件，并将输出保存到指定目录。

    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $false)]
        [switch]$Recurse
    )

    begin
    {
        function Convert-SingleFile
        {
            param (
                [string]$FilePath,
                [string]$OutputDir
            )

            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
            $outputPath = if ($OutputDir)
            {
                Join-Path $OutputDir "$fileName.html"
            }
            else
            {
                [System.IO.Path]::ChangeExtension($FilePath, 'html')
            }

            try
            {
                $html = ConvertFrom-Markdown -Path $FilePath | Select-Object -ExpandProperty Html
                $html | Out-File -FilePath $outputPath -Encoding utf8
                Write-Verbose "Successfully converted $FilePath to $outputPath"
            }
            catch
            {
                Write-Error "Failed to convert $FilePath. Error: $_"
            }
        }
    }

    process
    {
        if (Test-Path $Path -PathType Leaf)
        {
            # 单个文件
            Convert-SingleFile -FilePath $Path -OutputDir $OutputDirectory
        }
        elseif (Test-Path $Path -PathType Container)
        {
            # 目录
            $mdFiles = Get-ChildItem -Path $Path -Filter '*.md' -Recurse:$Recurse
            foreach ($file in $mdFiles)
            {
                Convert-SingleFile -FilePath $file.FullName -OutputDir $OutputDirectory
            }
        }
        else
        {
            Write-Error "The specified path does not exist: $Path"
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
function Get-Json
{
    <#
.SYNOPSIS
    Reads a specific property from a JSON string or JSON file. If no property is specified, returns the entire JSON object.

.DESCRIPTION
    This function reads a JSON string or JSON file and extracts the value of a specified property. If no property is specified, it returns the entire JSON object.

.PARAMETER JsonInput
    The JSON string or the path to the JSON file.

.PARAMETER Property
    The path to the property whose value needs to be extracted, using dot notation for nested properties.
.EXAMPLE
从多行字符串(符合json格式)中提取JSON属性
#从文件中读取并通过管道符传递时需要使用-Raw选项,否则无法解析json
PS> cat "$home/Data.json" -Raw |Get-Json

ConnectionName IpPrompt
-------- --------
         xxx
 
PS> cat $DataJson -Raw |Get-Json -property IpPrompt
xxx

.EXAMPLE
    Get-Json -JsonInput '{"name": "John", "age": 30}' -Property "name"

    This command extracts the value of the "name" property from the provided JSON string.

.EXAMPLE
    Get-Json -JsonInput "data.json" -Property "user.address.city"

    This command extracts the value of the nested "city" property from the provided JSON file.

.EXAMPLE
    Get-Json -JsonInput '{"name": "John", "age": 30}'

    This command returns the entire JSON object.

.NOTES
    Author: Your Name
    Date: YYYY-MM-DD
#>

    [CmdletBinding()]
    param (
        [Parameter(   ValueFromPipeline = $true)]
        [Alias('DataJson', 'JsonFile', 'Path', 'File')]$JsonInput = $DataJson,

        [Parameter(Position = 0)]
        [string][Alias('Property')]$Key
    )

    # 读取JSON内容

    $jsonContent = if (Test-Path $JsonInput)
    {
        Get-Content -Path $JsonInput -Raw | ConvertFrom-Json
    }
    else
    {
        $JsonInput | ConvertFrom-Json
    }
    # Write-Host $jsonContent

     

    # 如果没有指定属性，则返回整个JSON对象
    if (-not $Key)
    {
        return $jsonContent
    }

    # 提取指定属性的值
    try
    {
        # TODO
        $KeyValue = $jsonContent | Select-Object -ExpandProperty $Key
        # Write-Verbose $KeyValue
        return $KeyValue
    }
    catch
    {
        Write-Error "Failed to extract the property value for '$Key'."
    }
}


function Get-JsonItemCompleter
{
    param(
        $commandName, 
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameters
        # $cursorPosition
    )
    if ($fakeBoundParameters.containskey('JsonInput'))
    {
        $Json = $fakeBoundParameters['JsonInput']
    
    }
    else
    {
        $Json = $DataJson
    }
    $res = Get-Content $Json | ConvertFrom-Json
    $Names = $res | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    $Names = $Names | Where-Object { $_ -like "$wordToComplete*" }
    foreach ($name in $Names)
    {
        $value = $res | Select-Object $name | Format-List | Out-String
        # $value = Get-Json -JsonInput $Json $name |Out-String
        if (! $value)
        {
            $value = 'Error:Nested property expand failed'
        }

        [System.Management.Automation.CompletionResult]::new($name, $name, 'ParameterValue', $value.ToString())
    }
}
function Add-PythonAliasPy
{
    <# 
    .SYNOPSIS
    为当前用户添加Python的别名py
    .PARAMETER pythonPath
    指定Python的路径(可执行程序的完整路径)，如果为空，则默认使用当前用户的python.exe路径
    #>
    param(
        $pythonPath = ""
    )
    if($pythonPath -eq "")
    {

        $pythonPath = Get-Command python | Select-Object -ExpandProperty Source
    }
    $dir = Split-Path $pythonPath -Parent
    setx Path $dir
    $env:path = $env:path + ";" + $dir
    New-Item -ItemType HardLink -Path $dir/py.exe -Value $pythonPath -Force -Verbose -ErrorAction SilentlyContinue
}
Register-ArgumentCompleter -CommandName Get-Json -ParameterName Key -ScriptBlock ${function:Get-JsonItemCompleter}
