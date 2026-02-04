
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
        $LD3 = "www,*"    ,
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
function Write-Highlighted
{
    <# 
    .SYNOPSIS
    高亮显示文本中的指定模式
    .DESCRIPTION
    默认将匹配到的模式用ANSI转义码高亮显示(黑底白字),但是最终的显示效果还和终端软件的显示配置有关
    .PARAMETER Text
    要高亮显示的文本
    .PARAMETER Pattern
    要高亮显示的模式(正则表达式)

    .EXAMPLE
    高亮(黑底红字)显示https片段
    Write-Highlighted "This is a http(https) link: https://www.demo.com" -Pattern https?
    This is a http(https) link: https://www.demo.com
    .EXAMPLE
    $text=cat $home\.condarc -raw 
    Write-Highlighted -Text $text -Pattern "https" 

    #>
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Text,
        [parameter(Mandatory = $true)]
        [string]$Pattern,
        $ForegroundColorCode = '31',
        $BackgroundColorCode = '40'
    )
    
    begin
    {

        $RESET = "`e[0m"
    }
    process
    {
        
        # 使用 ANSI 转义码高亮
        $highlighted = $Text -replace "($Pattern)", "`e[${ForegroundColorCode};${BackgroundColorCode}m`$1${RESET}"
        Write-Host $highlighted
    }

}




function Get-CRLFChecker
{
    <# 
    .SYNOPSIS
    判断文本文件是的换行风格(如果是CRLF则返回true,否则返回false)
    CRLF (Carriage Return + Line Feed)

    可选的,将回车符(\r)和换行符(\n)分被用[CR]和[LF]标记出来并打印(这不属于返回值的一部分)

    .PARAMETER Path
    文件路径
    .PARAMETER ConvertToLFStyle
    是否将回车符\r转为换行符\n
    .PARAMETER Replace
    是否将回车符\r转为换行符\n,并保存到原文件中(需要ConvertToLFStyle参数启用的情况下才会生效)
    
    .DESCRIPTION
    多行文本将被视为一行,CR,LF(\r,\n)将被显示为[CR],[LF]

    .EXAMPLE
     Get-CRLFChecker $scripts/ps/tools/tools.psm1 
     Get-CRLFChecker $sh/shell_vars.sh

    .EXAMPLE
    # 将readme.md文件中的回车符\r移除(保留换行符\n),使得文本文件LF化
    Get-CRLFChecker .\readme.md 
    .EXAMPLE
    批量处理多个文件(借助ls和管道符)
    ls *.sh | Get-CRLFChecker 
    
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        $InputObject,
        [switch]$ViewCRLF
        
    )
    process
    {
        if(Test-Path $InputObject)
        {
            # $InputObject = Get-Content $InputObject -raw
            $Path = $InputObject
            # 读取文件的方式是关键,读取使用Raw方式读取,否则结果因为分割会丢失`\r`
            $raw = Get-Content $Path -Raw
        }
        else
        {
            $raw = $InputObject
        }
        $isCRLFStyle = $raw -match "`r"
        
        if($isCRLFStyle)
        {
            Write-Verbose "The file: [$Path] is CRLF style file(with carriage char)!"

        }
        else
        {
            Write-Verbose "The file: [$Path] is LF style file(without carriage char)!"
            
        }
        if($ViewCRLF)
        {

            # 将回车,换行符替换为可见的标记,便于用户查看
            $res = $raw -replace "`n", "[LF]" -replace "`r", "[CR]"
            # $res | Select-String -Pattern "\[CR\]|\[LF\]" -AllMatches 
            $res | Write-Highlighted -Pattern "\[CR\]|\[LF\]"
        }
        return $isCRLFStyle
    }
}
function Convert-CRLF
{
    <# 
    .SYNOPSIS
    将CRLF(回车换行)转为LF(换行)
    反之亦然,默认情况下转换为LF
    .DESCRIPTION
    批量处理可以借助通用的for循环,也可以借助ls 通配符+管道符实现

    .PARAMETER Path
    文件路径
    .PARAMETER Replace
    是否将CRLF转为LF,并保存到原文件中

    .EXAMPLE
    将指定文件转换为LF并使用[LF]标记换行符位置
     Convert-CRLF -InputObject .\my_table.conf -To LF |Get-CRLFChecker -ViewCRLF 
    .EXAMPLE
    通过cat -raw读取文件,并将CRLF转为LF,再将结果用重定向的方式写入另一个文件另存(注意`-raw`选项是不可少的)
    cat .\my_table.conf -Raw | Convert-CRLF > my_table.LF.conf  
    .EXAMPLE
    批量处理多个文件(借助ls和管道符)
    ls -Recurse *.sh | Convert-CRLF -Replace  -Quiet
    
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Path')]
        [string]$InputObject,
        [ValidateSet('CRLF', 'LF')]
        [string]$To = 'LF',
        # 如果输入是个文件,可以选择是否替将换行符更换后直接替换原文件
        [switch]$Replace,
        [switch]$Quiet
    )

    process
    {
        $text = ""
        if(Test-Path $InputObject)
        {
            $path = $InputObject
            $fileName = Split-Path $Path -LeafBase
            $fileDir = Split-Path $Path -Parent
            $fileExtension = Split-Path $Path -Extension

            $text = Get-Content $Path -Raw
        }
        else
        {
            $text = $InputObject
        }
            
        if ($To -eq 'LF')
        {
            # 移除CR回车符
            $res = $text -replace "`r", ""
        }
        elseif ($To -eq 'CRLF')
        {
            $res = $text -replace "`n", "`r`n"
        }
        
        if($Replace)
        {
            if($fileName)
            {
                # 写入经过LF化的新内容到新文件中
                $ToStyleFile = "$fileDir/$fileName.${To}$fileExtension"
                $res | Out-File $ToStyleFile -Encoding utf8 -NoNewline
                Write-Verbose "File has been converted to [$To] style![$ToStyleFile]" 
            }
            Write-Verbose "Replace the file: [$Path] with [$TO] style file: [$ToStyleFile]"
            # 可选备份
            # Move-Item $Path "$Path.bak" -Force -Verbose
            # 覆盖原文件(LF化)
            Move-Item $ToStyleFile $Path -Force 
            Write-Host "File [$Path] has been processed!"
        }
        # 准备适合用户审阅的输出格式的字符串
        # $resDisplay = $res -replace "`n", "[LF]"
        # $res = $resDisplay
        if(!$Quiet)
        {
            return $res 
        }
    }
    
}
function Deploy-BatchSiteBTOnline
{
    <# 
        .SYNOPSIS
    批量部署空站点到宝塔面板(借助宝塔api和python脚本)
    #>
    param(

        $Server,
        $Script = "$pys/bt_api/create_sites.py",
        $SitesHome = '/www/wwwroot',
        $ServerConfig = "$server_config",
        $Table = "$desktop/table.conf"
    )
    python $Script -c $ServerConfig -s $Server -f $Table -r -w $SitesHome
}