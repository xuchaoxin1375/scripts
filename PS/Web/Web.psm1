<#
Web 模块:网络/HTTP 服务/nginx 站点/域名/下载相关(从 Tools.psm1 迁入)。
#>

function Test-UrlOrHostAvailability
{
    [CmdletBinding(DefaultParameterSetName = 'FromFile')]
    param (
        [parameter(Mandatory = $true, ParameterSetName = 'FromFile')]
        $Path,
        [parameter(Mandatory = $true, ParameterSetName = 'FromUrls')]
        $Urls,
        $UserAgent = $agent,
        $Method = 'Head',
        $TimeOutSec = 30
    )
    
    # 分被检查读入的数据行是否为空或者注释行(过滤掉这些行)
    if($PSCmdlet.ParameterSetName -eq 'FromFile' )
    {
        $Urls = Get-Content $Path
    }

    @($Urls) | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $_ -notmatch '^\s*#' } |
    ForEach-Object -Parallel {
        # 设置 TLS（支持 HTTPS）
        # [System.Net.ServicePointManager]::SecurityProtocol = 
        # [System.Net.SecurityProtocolType]::Tls12 -bor  
        # [System.Net.SecurityProtocolType]::Tls13
        
        $url = $_
        $uri = $null
        
        # 提取 Host
        try
        {
            $uri = [System.Uri]$url
            if (-not $uri.Scheme -in @('http', 'https'))
            {
                $uri = $null
            }
        }
        catch
        {
            # 无效 URL,可能确实协议部分(比如http(s))
        }
    
        $hostName = if ($uri) { $uri.Host } else { $url }
        # 定义要返回的数据对象的原型
        $result = [ordered]@{
            Host              = $url
            ResolvedHost      = $hostName
            StatusCode        = $null
            StatusDescription = $null
            Error             = $null
        }
    
        try
        {
            # 发送head请求轻量判断网站的可用性(但是有些网站不支持Head请求,会引起报错,后面会用get请求重试)
            $TimeOutSec = $using:TimeOutSec
            $UserAgent = $using:UserAgent
            $Method = $using:Method
            $response = Invoke-WebRequest -Uri $url -UserAgent $UserAgent -Method $Method -TimeoutSec $TimeOutSec -ErrorAction Stop -SkipCertificateCheck -Verbose:$VerbosePreference
            # 填写返回数据对象中对应的字段
            $result.StatusCode = $response.StatusCode
            $result.StatusDescription = $response.StatusDescription
        }
        catch
        {
            # 如果异常类型是 WebCmdletWebResponseException, 尝试 fallback 到 GET
            if ($_.Exception.GetType().Name -eq 'WebCmdletWebResponseException')
            {
                $resp = $_.Exception.Response
                $result.StatusCode = $resp.StatusCode.value__
                $result.StatusDescription = $resp.StatusDescription
            }
            else
            {
                $result.Error = $_.Exception.Message -replace '\r?\n', ' ' -replace '^\s+|\s+$', ''
            }
        }
        # 将字典类型指定为PSCustomObject类型返回
        [PSCustomObject]$result
    
    } -ThrottleLimit 32 |
    Select-Object Host, ResolvedHost, StatusCode, StatusDescription,
    @{ Name = "Remark"; Expression = {
            if ($_.Error) { "❌ $($_.Error)" }
            elseif ($_.StatusCode -ge 200 -and $_.StatusCode -lt 300) { "✅ OK" }
            elseif ($_.StatusCode -ge 400) { "🔴 Failed ($($_.StatusCode))" }
            else { "🟡 Other ($($_.StatusCode))" }
        }
    } 
}

function Update-SSNameServers
{
    <# 
    .SYNOPSIS
    调用Python脚本更新Spaceship域名的DNS服务器信息
    .DESCRIPTION
    核心步骤是调用python脚本来执行更新
    .NOTES
    PS> py .\update_nameservers.py -h
    usage: update_nameservers.py [-h] [-d DOMAINS_FILE] [-c CONFIG] [--dry-run] [-v]

    批量更新SpaceShip域名的Nameservers

    options:
    -h, --help            show this help message and exit
    -d DOMAINS_FILE, --domains-file DOMAINS_FILE
                            域名和nameserver配置文件路径 (csv/xlsx/conf)
    -c CONFIG, --config CONFIG
                            SpaceShip API配置文件路径 (json)
    --dry-run             仅预览将要修改的内容,不实际提交API
    -v, --verbose         显示详细日志
    
    .EXAMPLE

    # Set-CFCredentials -CfAccount account2
    # Get-CFZoneNameServersTable -FromTable $desktop/table-s2.conf
    # Update-SSNameServers -Table $desktop/domains_nameservers.csv -Verbose
    #>`
        [CmdletBinding()]
    param (
        $Table = "$desktop/domains_nameservers.csv",
        $Config = "$spaceship_config",
        $script = "$pys/spaceship_api/update_nameservers.py",
        $Threads = 8
    )
    python $script -f $Table -c $Config -w $Threads
    
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
        [alias("Mode")]
        $TableMode = 'Auto',
        # 表结构，默认是 "域名,用户名"
        $Structure = $SiteOwnersDict.DFTableStructure,

        # 用户名转换字典
        $SiteOwnersDict = $siteOwnersDict,
        [switch]$KeepWWW
    )
    if (!$SiteOwnersDict )
    {
        Write-Warning "用户名转换字典缺失"
        
    }
    else
    {
        # Write-Host "$SiteOwnersDict"
        Get-DictView $SiteOwnersDict
        # 谨慎使用write-output和孤立表达式,他们会在函数结束时加入返回值一起返回,导致不符合预期的情况
        #检查siteOwnersDict
        # Write-Verbose "SiteOwnersDict:"
        # $dictParis = $SiteOwnersDict.GetEnumerator()
    }
    if($VerbosePreference)
    {

        Get-DictView -Dicts $SiteOwnersDict
    }


    # 解析表头结构
    $columns = $Structure -split ','
    $structureFieldsNumber = $columns.Count
    Write-Verbose "structureFieldsNumber:[$structureFieldsNumber]:{$columns}" -Verbose

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
    # 将网站url->域名
    # $Table = $Table -replace '\b(?:https?://)?([\w.-]+\.[a-z-A-Z]{2,})(?:/|\s)(?:[^\w])', '$1 '
    $Table = $Table -replace '(?:https?://)(?:w*\.)([\w.-]+(\.[\w.-]+)+)(?:/?)\s+', '$1 '
    if(!$KeepWWW)
    {
        $Table = $Table -replace 'www\.', ''
    }
    
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

function Get-UrlFromMarkdownUrl
{
    param(
        $Urls
    )
    $Urls = $Urls -replace '\[.*?\]\((.*)\)', '$1' -split "`r?`n" | Where-Object { $_ }
    return $Urls
}

function Get-MainDomain
{
    <#
    .SYNOPSIS
    获取主域名
    从给定的 URL 中提取二级域名和顶级域名部分（即主域名），忽略协议 (http:// 或 https://) 和子域名（如 www.、xyz. 等）
    执行域名规范化:(todo)
    如果某个域名存在大写字母,则抛出警告
    将域名中的所有字母转换为小写(对于写入vhosts文件比较关键)
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
            $resRaw = "$($parts[-2]).$($parts[-1])"
            # 如果存在大写字母,则抛出警告
            if ($resRaw -cmatch '[A-Z]')
            {
                Write-Warning "原域名字符串包含大写字母:[$resRaw]"
            }
            $resNormalized = $resRaw.ToLower().Trim()
            Write-Warning "已执行域名规范化(小写化字母):[$resRaw] -> [$resNormalized]"
            
            return $resNormalized
        }

        return $null
    }
}

function Start-XpNginx
{
    <# 
    .SYNOPSIS
    启动 Nginx 服务(phpstudy工具箱安装),如果已经存在nginx进程则直接返回

    #>
    [CmdletBinding()]
    param(
        $NginxHome = $env:NGINX_HOME,
        $NginxConf = $nginx_conf,
        $ErrorLog = "$env:TEMP/nginx_error.log",
        # 启动 Nginx 时尝试关闭已有进程然后启动
        [switch]$Force
    )
    Write-Debug "nginx_home: $nginx_home"
    if (!$nginx_home)
    {
        Write-Warning "Nginx home directory was not set , please set the environment variable NGINX_HOME to your nginx home directory!"
    }
    Write-Verbose "check existing nginx process..."
    $nginx_process = Get-Process -Name nginx -ErrorAction SilentlyContinue
    if($nginx_process)
    {
        Write-Host "nginx process already exists!"
        if($force)
        {
            Write-Host "kill nginx process and restart..."
            $nginx_process | Stop-Process -Force
        }
        else
        {
            return $nginx_process
        }
    }
    else
    {
        Write-Verbose "nginx process not exists yet, starting nginx..."
    }
    # 清理可能潜在的错误
    Approve-NginxValidVhostsConf -NginxVhostConfDir $env:nginx_vhosts_dir
    # 启动nginx前对配置文件语法检查
    $Test = Start-Process -FilePath nginx -ArgumentList "-p $NginxHome -c $NginxConf -t" -NoNewWindow -Wait -PassThru
    if ($Test.ExitCode -eq 0)
    {
        # 启动 Nginx(隐藏窗口)
        $proc = Start-Process -FilePath nginx -ArgumentList "-p $NginxHome -c $NginxConf" -PassThru -Verbose -RedirectStandardError $ErrorLog
        $exitCode = $proc.ExitCode
        # 如果进程退出代码不为 0（表示出错），或者错误日志有内容，则显示错误
        if ($exitCode -and $exitCode -ne 0 ) 
        {
            Write-Warning "Nginx 启动可能遇到错误"
            if((Test-Path $ErrorLog) -and (Get-Item $ErrorLog).Length -gt 0)
            {
                Get-Content $ErrorLog | Write-Error
                # 清空错误日志,避免下次误报
                Remove-Item $ErrorLog -Verbose
            }
        }
        else
        {
            Write-Host "Nginx 启动指令已发送。"
        }
        Write-Host "try start nginx process $($proc.Id)"
    }
    else
    {
        Write-Error "Nginx 配置检查失败，请查看上方错误信息。"
    }
    # Get-Process $Res.Id
    Write-Host "Wait for nginx to start and check process status..."
    Start-Sleep 1
    $resLive = Get-Process nginx
    if($resLive)
    {

        return $resLive
    }
    else
    {
        return $False
    }
    # $item = Get-Item -Path "$nginx_home/ngin
}

function Restart-XpPhpStudy
{
    param (
    )
    # Restart-Nginx -Force
    Start-XpNginx -Force
    Start-XpCgi -Force
    
}

function Restart-Nginx
{
    <# 
    .SYNOPSIS
    重启Nginx
    为了提高重启的成功率,这里会检查nginx的vhosts目录中的相关配置关联的各个目录是否都存在,如果不存在,则会移除相应的vhosts配置文件(避免因此而重启失败)
    Approve-NginxValidVhostsConf -NginxVhostConfDir $NginxVhostConfDir
    #>
    [CmdletBinding()]
    param(

        $nginx_home = $env:NGINX_HOME,
        $NginxVhostConfDir = $env:nginx_vhosts_dir,
        # 记录启动或重启nginx的错误日志,也可以考虑用临时文件:
        # $tempLog=New-TemporaryFile,用完删除防止堆积
        $Errorlog = "$env:TEMP/nginx_error.log",
        # 终止所有nginx进程后再重启
        [switch]$Force
    
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
    Approve-NginxValidVhostsConf -NginxVhostConfDir $NginxVhostConfDir
    # 打印hosts文件内容,确保hosts中的映射正确(防止被第三方网络工具修改后不能及时发现)
    Write-Warning "hosts file content:"
    Get-Content $hosts
    Write-Warning "Please ensure maps like '127.0.0.1 domain.com' exist and are not commented out."
    if($Force)
    {
        Write-Verbose "Force stop all nginx processes..." -Verbose
        $nginx_processes = Get-Process *nginx* -ErrorAction SilentlyContinue
        if($nginx_processes)
        {
            $nginx_processes | Stop-Process -Force -Verbose
            Write-Verbose "Start nginx.exe..." -Verbose
            Start-Process -WorkingDirectory $nginx_home -FilePath "nginx.exe" -ArgumentList "-c", "$nginx_conf" -NoNewWindow -RedirectStandardError $ErrorLog # -PassThru
            # 重新扫描nginx进程(而不是使用上面的Start-Process返回的进程对象,进程创建失败时,这不太准确)
            return Get-Process nginx*
            # Start-XpNginx 
        }
        else
        {
            Write-Verbose "No nginx processes found to stop." -Verbose
        }
    }
    else
    {

        Write-Verbose "Nginx.exe -s reload" -Verbose
        Start-Process -WorkingDirectory $nginx_home -FilePath "nginx.exe" -ArgumentList "-s", "reload" -Wait -NoNewWindow -RedirectStandardError $ErrorLog
        Write-Verbose "Nginx.exe -s stop" -Verbose
    }
    if(Test-Path $Errorlog)
    {
        $errorMsg = Get-Content $Errorlog 
        if($errorMsg)
        {
            Write-Error $errorMsg
            # 清空错误日志,避免下次误报
        }
        Remove-Item $Errorlog -Verbose
    }
   
}

function Get-ProcessOfPort
{
    <# 
    .SYNOPSIS
    获取监听指定端口号的进程信息,端口号的指定支持通配符(字符串)
    .DESCRIPTION
    默认查询状态处在正在"监听"的进程端口
    如果需要后续使用得到的信息,配合管道符select使用即可
    .EXAMPLE
    PS> Get-ProcessOfPort 900*

    LocalAddress LocalPort RemoteAddress RemotePort  State OwningProcess ProcessName
    ------------ --------- ------------- ----------  ----- ------------- -----------
    127.0.0.1         9002 0.0.0.0                0 Listen         18908 xp.cn_cgi
    .EXAMPLE
    #⚡️[Administrator@CXXUDESK][~\Desktop][14:24:50] PS >
    Get-ProcessOfPort -Port *80* -ProcessName quickservice*

    LocalAddress  : 127.0.0.1
    LocalPort     : 8800
    RemoteAddress : 0.0.0.0
    RemotePort    : 0
    State         : Listen
    OwningProcess : 16256
    ProcessName   : quickservice
    
    .EXAMPLE
    #⚡️[Administrator@CXXUDESK][~\Desktop][8:58:27] PS >
    Get-ProcessOfPort -ProcessName mysql*

    LocalAddress  : ::
    LocalPort     : 33060
    RemoteAddress : ::
    RemotePort    : 0
    State         : Listen
    OwningProcess : 5396
    ProcessName   : mysqld

   .EXAMPLE
    # 查询mysql进程中所有处于established状态的连接
    Get-ProcessOfPort -ProcessName mysql* -State '*establish*'

    #>
    param (
        $Port = "*",
        $State = 'Listen',
        $ProcessName = "*"
    )
    if(!$Port -and !$ProcessName)
    {
        Write-Warning "Port or ProcessName should be specified to filter process!"
        return $False
    }
    $res = Get-NetTCPConnection | Where-Object { $_.LocalPort -like $Port -and $_.State -like $State } | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess, @{Name = 'ProcessName'; Expression = { (Get-Process -Id $_.OwningProcess).Name } } | Where-Object { $_.ProcessName -like $ProcessName }
    return $res
    
}

function New-LocalSite
{
    <# 
.SYNOPSIS
本地新建一个空网站(基于nginx)
关键步骤是配置文件的创建和系统的hosts文件(本地dns)的映射添加
#>
    [CmdletBinding()]
    param(
        # 新站点的名称(域名,由于是本地站点,可以是一个简单的单词,不要求多级)
        $Name,
        # 网站根目录
        $SiteRoot ,
        # nginx可执行文件所在路径,放空则会尝试自行寻找Path中的nginx
        $NginxPath = "",
        # ngix安装目录(nginx可执行文件所在目录),例如c:/phpstudy_pro/extensions/nginx1.25.2
        $NginxHome = $nginx_home,
        # nginx vhosts所在目录,例如c:/phpstudy_pro/extensions/nginx1.25.2/conf/vhosts
        $NginxVhosts = $nginx_vhosts,
        # nginx总配置文件路径(不是目录),例如C:/phpstudy_pro/Extensions/Nginx1.25.2/conf/nginx.conf
        $NginxConf = $nginx_conf
    )
    # 优先查看用户给定的路径是否可用(不可用直接抛出异常结束执行).
    # 如果没有指定此参数从Path环境变量中查找nginx
    # $nginxAvailability=False
    if($NginxPath) #是否指定了路径,且是一个有效路径
    {
        if(Get-Command $NginxPath -ErrorAction Stop)
        {
            Write-Verbose "nginx路径存在..."
        }
     
    }
    else
    {
       
        # Write-Verbose "[$NginxPath]:nginx路径存在..."
        Write-Verbose "从Path中寻找nginx..."
        if(Get-Command nginx -ErrorAction Stop)
        {
            Write-Verbose "环境变量中的nginx路径存在..."
            $NginxPath = Get-Command nginx | Select-Object -ExpandProperty Source
        }
    }
    
    # 创建新站点的配置文件
    $conf = "$NginxVhosts/$Name.conf"
    Write-Host "Writing site vhost config..."

    $tpl = @'
server {
    listen 80;
    server_name $Name;
    # root ""; # 对于特殊用途,可以不使用root,而是直接让 Nginx 在内存中处理请求;
    location / {
        # 简单返回200和一个简单HTML类型的页面
        default_type text/html;
        return 200 "<html><body style='text-align:center;'><h1>200 OK</h1></body></html>";

        # try_files直接返回html文件
        # try_files $uri $uri/ /index.html;
    }

}

'@ 
    $tpl = $tpl -replace '\$Name', "$Name"
    if($SiteRoot)
    {
        # 将tpl中的# root "$root"; 行替换为启用行
        $tpl = $tpl -replace '# root "";' , "root `"$root`";"
    }
    $tpl > $conf
    # 写入到系统的hosts配置文件中
    # 5.1 无 $IsWindows 自动变量:用 PSEdition 兜底(Desktop 即 Windows),排雷未来降档
    if (($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true))
    {
        # 使用专门的外部命令修改hosts文件
        if (Get-Command Add-NewDomainToHosts -ErrorAction SilentlyContinue)
        {

            Add-NewDomainToHosts -Domain $Name
        }
        else
        {
            # 简单添加
            Write-Host "Adding [$name] to hosts file..."
            "127.0.0.1  $name" >> $hosts
        }
    }

    # 重启nginx
    # 方案1:要求配置好nginx所在目录到Path环境变量中,更简单:
    # nginx -p $nginx_home -c $nginx_conf -s reload

    # 方案2:使用start-process运行,更加灵活:
    # 构造命令参数列表
    $param_base = @("-p", $nginxhome, "-c", $nginxconf)
    $param_restart = $param_base + @("-s", "reload")
    $param_check = $param_base + @('-t')
    Start-Process -FilePath $NginxPath -ArgumentList $param_check -NoNewWindow -Wait
    Start-Process -FilePath "$NginxPath" -ArgumentList $param_restart -NoNewWindow -Wait
    Write-Host "执行完毕."

}

function Approve-NginxValidVhostsConf
{
    <# 
    .SYNOPSIS
    扫描nginx vhosts目录中的各个站点配置文件是否有效(尤其是所指的站点路径(网站根目录.))
    如果无效,则会将对应的vhosts中的站点配置文件移除,从而避免nginx启动或重载而受阻.
    #>
    [CmdletBinding()]
    param(
        # 典型nginx配置文件路径:C:\phpstudy_pro\Extensions\Nginx1.25.2\conf\vhosts,
        [alias('NginxVhostsDir')]
        $NginxVhostConfDir = "$env:nginx_vhosts_dir" ,
        # 对于nginx服务器的网站,内部应该有典型的标准文件(比如*.htaccess),
        # 如果要求是wordpress网站,内部要求有wp-config.php文件
        $KeyPath = "" # 默认为空,宽松处理,其他典型值:*.htaccess等
    )
    $vhosts = Get-ChildItem $NginxVhostConfDir -Filter "*.conf" 
    Write-Verbose "Checking vhosts in $NginxVhostConfDir" -Verbose
    foreach ($vhost in $vhosts)
    {
        $root_info = Get-Content $vhost | Select-String "\s*root\s+" | Select-Object -First 1
        Write-Debug "root line:[ $root_info ]" -Debug
        # 计算vhost配置文件中的站点根路径(如果不存在时跳过处理此配置)
        if($root_info -and $root_info -match '^\s*root')
        {
            $root_info = $root_info.ToString().Trim()    
            $root = $root_info -replace '.*"(.+)".*', '$1'
            if(!$root)
            {
                Write-Warning "vhost: $($vhost.Name) root path is empty!" -WarningAction Continue
                # 处理下一个
                continue
            }
            else
            {
                Write-Verbose "vhost: $($vhost.Name) root path:[ $root ]" -Verbose
            }

            # pause
        }
        else
        {
            continue
        }
        $removeVhost = $true
        # 根据得到的root路径来判断站点根目录是否存在
        if(Test-Path $root)
        {

            # $removeVhost = $false
            Write-Verbose "vhost: $($vhost.Name) root path: $root is valid(exist)!"  

            # 保险起见,再检查内部的访问控制标准文件例如*.htaccess是否存在
            # 这里引入的基于网站根目录的额外判断,是考虑到部分情况下,目录没有移除干净或者被其他进程占用,
            # 这种情况下仅仅根据网站根目录是否存合法是不够准确的,当然,此时系统内部可能积累了许多错误,建议重启计算机)
            if(! $KeyPath)
            {
                $removeVhost = $false
            }
            elseif( Test-Path "$root/$KeyPath")
            {
                Write-Verbose "vhost: $($vhost.Name) $KeyPath exists in root path: $root"  
                $removeVhost = $false
            }
            else
            {
                Write-Warning "vhost: $($vhost.Name) $KeyPath NOT exists in root path: $root!" -WarningAction Continue
            }
        }
        if($removeVhost)
        {
            Write-Warning "vhost:[ $($vhost.Name) ] root path:[ $root ] is invalid(not exist)!" -WarningAction Continue
            Remove-Item $vhost.FullName -Force -Verbose

        }
    }

}

function Test-IsIPAddress
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string]$IPAddress,

        [Parameter(Mandatory = $false)]
        [ValidateSet("v4", "v6", "Auto")]
        [string]$Type = "Auto"
    )

    # 初始化一个变量用于接收解析后的 IP 对象
    $parsedIP = $null
    if(! $IPAddress)
    {
        Write-Warning "[Test-IsIPAddress]: IPAddress is empty!"
    }
    else
    {
        Write-Verbose "[Test-IsIPAddress] Trying to parse IP address: [$IPAddress]"
    }
    # 使用 .NET 的 TryParse 方法尝试解析字符串
    if ([System.Net.IPAddress]::TryParse($IPAddress, [ref]$parsedIP))
    {
        
        # 根据指定的类型进行二次判断
        switch ($Type)
        {
            "v4"
            {
                # AddressFamily 为 InterNetwork 表示 IPv4
                return $parsedIP.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
            }
            "v6"
            {
                # AddressFamily 为 InterNetworkV6 表示 IPv6
                return $parsedIP.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6
            }
            "Auto"
            {
                # 自动判断模式下，只要解析成功就返回 True
                return $true
            }
        }
    }

    # 如果解析失败，直接返回 False
    return $false
}

function Get-DomainUserDictFromTableLite
{
    <# 
    .SYNOPSIS
    简单地从约定的配置文本(包含多列数据,每一列用空白字符隔开)中提取各列(字段)的数据
    .EXAMPLE
    文件内容假设包含如下内容
    
https://www.d1.com	人名	7.ca	Title1	1	4(192.168.1.1)
https://www.example.com	人名	7.ca	title2	1	A(192.168.1.1)
https://www.domain1.com	人名	1.fr	title3		
https://dm2.com	 人名	1.fr			FX192.168.1.4
https://dms3.com	 人名	3.fr
https://dms3.com	 行末无空格测试者	3.fr

    解析结果:

WARNING: 已执行域名规范化(小写化字母):[d1.com] -> [d1.com]

Name                           Value
----                           -----
user                           人名
domain                         d1.com
removeMall                     False
ip                             192.168.1.1
template                       7.ca
title                          Title1
WARNING: 已执行域名规范化(小写化字母):[example.com] -> [example.com]
user                           人名
domain                         example.com
removeMall                     False
ip                             192.168.1.1
template                       7.ca
title                          title2
WARNING: IP[] is empty!
WARNING: 已执行域名规范化(小写化字母):[domain1.com] -> [domain1.com]
user                           人名
domain                         domain1.com
removeMall                     False
ip
template                       1.fr
title                          title3
WARNING: 已执行域名规范化(小写化字母):[dm2.com] -> [dm2.com]
user                           人名
domain                         dm2.com
removeMall                     False
ip                             192.168.1.4
template                       1.fr
title
WARNING: IP[] is empty!
WARNING: 已执行域名规范化(小写化字母):[dms3.com] -> [dms3.com]
user                           人名
domain                         dms3.com
removeMall                     False
ip
template                       3.fr
title
    #>
    [CmdletBinding()]
    param(
        # [Parameter(Mandatory = $true)]
        [Alias('Path')]$Table = "$env:USERPROFILE/Desktop/table.conf"
    )
    Get-Content $Table | Where-Object { $_.Trim() } | Where-Object { $_ -notmatch "^\s*#" } | ForEach-Object { 
        $line = $_
        $lineArray = $_ -split '\s+'
        Write-Verbose "[$lineArray]" 
        # 计算域名(网站)对应的服务器ip
        $last = $lineArray[-1].trim()
        Write-Verbose "last field:[$last]"
        $ip = ""
        if ($last)
        {
            if (Test-IsIPAddress $last)
            {
                $ip = $last
            }
            else
            {
         
                $pattern = '(?<ip>(?:25[0-5]|2[0-4]\d|[01]?\d\d?)(?:\.(?:25[0-5]|2[0-4]\d|[01]?\d\d?)){3})'

                if ($last -match $pattern)
                {
                    # 直接通过 .ip 或者 ['ip'] 拿到命名组的值
                    
                    $ip = $Matches.ip
                }
            
                # 兼容 A192.168.1.1,A(192.168.1.1) 和2(192.168.1.1)
                if(!(Test-IsIPAddress $ip))
                {
                    Write-Warning "IP[$ip] parsing error!" 
                    
                }
                else
                {
                    Write-Verbose "line:[$line]" 
                    $line = $line.TrimEnd($last)
                }
            }
        }
        else
        {
            Write-Warning "IP[$ip] is empty!"
           
        }
        Write-Verbose "line:[$line]"
        # 计算标题,将模板名(例如1.us)作为分隔符,通常得到两段,取第二段(最后一段);移除末尾可能存在的记号1
        $title = ($line -split '\d+\.\w{1,5}')[-1].trim().TrimEnd('1') -replace '"', ''
        # 如果行以'\s+1'结尾,则返回$true
        $removeMall = if($_ -match '.*\s+1\s*$') { $true }else { $false }
        @{'domain'       = ($lineArray[0] | Get-MainDomain);
            'user'       = $lineArray[1];
            'template'   = $lineArray[2] ;
            'title'      = $title;
            'ip'         = $ip;
            'removeMall' = $removeMall;
        } 
    }
}

function Get-DomainRoutesMaps
{
    <# 
    .SYNOPSIS
    将站点登记表中网站域名及其所属的后端服务器信息提取处理来,并生成nginx的路由映射配置文件(例如vhosts/route.conf)
    第二列的形式采用ip还是http://ip (协议名称)可以通过选项控制
    #>
    param(
        [Alias('Table')]
        $FromTable = "$Desktop/table.conf",
        # proxy_pass 的风格,是否带上协议名
        [ValidateSet('http', 'https', '')]
        $Scheme = '',

        [Parameter(Mandatory = $true)]
        [Alias('Output')]
        $RoutesMap
        
    )
    if ($Scheme)
    {
        $Scheme += "://"
    }
    $items = Get-DomainUserDictFromTableLite -Table $FromTable
    Write-Verbose "Get domain-ip mapping table from table.conf,save result to $RoutesMap"
    # 先清空旧文件
    Clear-Content $RoutesMap 
    foreach ($item in $items)
    {
        $line = ".$($item.domain) ${Scheme}$($item.ip);"
        $line | Tee-Object -Append -FilePath $RoutesMap 
    }
    Convert-CRLF -InputObject $RoutesMap -To LF -Replace
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

function Add-NewDomainToHosts
{
    <# 
    .SYNOPSIS
    添加域名映射到hosts文件中
    .DESCRIPTION
    如果hosts文件中已经存在该域名的映射,则不再添加,否则添加到文件末尾
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        $Domain,
        $Ip = "127.0.0.1",
        [switch]$Force
    )
    # $hsts = Get-Content $hosts
    # if ($hsts| Where-Object { $_ -match $domain }){}
    $checkExist = { Select-String -Path $hosts -Pattern "\b$domain\b" }
    $exist = & $checkExist
    if ($exist -and !$Force)
    {
        
        Write-Warning "Domain [$domain] already exist in hosts file!" 
    }
    else
    {
        Write-Host "Adding [$domain] to hosts file..."
        "$Ip  $domain" >> $hosts
    }
    # return Select-String -Path $hosts -Pattern $domain 
    return & $checkExist
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
