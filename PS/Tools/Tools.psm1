function Get-CxxuPsModuleVersoin
{
    param (
        
    )
    Get-RepositoryVersion -Repository $scripts
    
}



function Test-CommandAvailability
{
    <# 
    .SYNOPSIS
    测试命令是否可用,并根据gcm的测试结果给出提示,在命令不存在的情况下不报错,而是给出提示
    主要简化gcm命令的编写
    .DESCRIPTION
    命令行程序可用的情况下,想要获取其路径,可以访问返回结果的.Source属性
    .PARAMETER CommandName
    命令名称
    
    .EXAMPLE
    # 测试命令不存在
    PS> Test-CommandAvailability 7zip
    WARNING: The 7zip is not available. Please install it or add it to the environment variable PATH.
    .EXAMPLE
    # 测试命令存在
    PS> Test-CommandAvailability 7z

    CommandType     Name                                               Version    Source
    -----------     ----                                               -------    ------
    Application     7z.exe                                             0.0.0.0    C:\ProgramData\scoop\shims\7z.exe
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (! $command)
    {
        Write-Warning "The $CommandName is not available. Please try a another similar name or install it or add it to the environment variable PATH."
        return $null
    }
    return $command
}



function Restart-NginxOnHost
{
    <# 
.SYNOPSIS
更新nginx配置(插入公共配置)
调用相应脚本,维护指定服务器上的[建站日期表]
重启指定主机的Nginx服务配置

默认仅重载nginx配置
强制可以杀死nginx进程再启动nginx

.NOTES
强烈建议配置ssh免密登录


#>
    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline = $true)]
        [alias('Host', 'Server', 'Ip')]
        $HostName = $env:DF_SERVER1,
        [alias("ScpUser")]$User = 'root',
        [switch]$Force

    )
    # 更新各个网站vhost的配置(宝塔nginx vhost配置文件路径)
    ssh $User@$HostName @"
    bash /update_nginx_vhosts_conf.sh -d /www/server/panel/vhost/nginx --days 1 
"@
    
    # bash /www/sh/nginx_conf/update_nginx_vhosts_log_format.sh -d /www/server/panel/vhost/nginx 

    # 维护服务器上的建站日期表(可以丢到后台运行)
    $maintain = "python3 /www/sh/nginx_conf/maintain_nginx_vhosts.py maintain -d -k first"
    Write-Verbose "维护域名列表[  $maintain ]"
    ssh root@$HostName $maintain
    if ($Force)
    {
        ssh $User@$HostName " pkill -9 nginx ; nginx "
    }
    else
    {
        ssh $User@$HostName "nginx -t && nginx -s reload"
    }

}
# Get-Content ./urls.txt | Where-Object { $_.Trim() } | ForEach-Object -Parallel { $hostname = $_; Invoke-WebRequest $_ | Select-Object StatusCode, StatusDescription, @{Name = 'Host'; Expression = { $hostname } } } -ThrottleLimit 500

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
    #>
    [CmdletBinding()]
    param (
        $Table = "$desktop/domains_nameservers.csv",
        $Config = "$spaceship_config",
        $Threads = 8
    )
    python $pys/spaceship_api/update_nameservers.py -f $Table -c $Config -w $Threads
    
}


function ssh-copy-id-ps
{   
    param(
        [string]$userAtMachine, 
        $args
    )
    $publicKey = "$ENV:USERPROFILE/.ssh/id_rsa.pub"
    if (!(Test-Path "$publicKey"))
    {
        Write-Error "ERROR: failed to open ID file '$publicKey': No such file"            
    }
    else
    {
        & Get-Content "$publicKey" | ssh $args $userAtMachine "umask 077; test -d .ssh || mkdir .ssh ; cat >> .ssh/authorized_keys || exit 1"      
    }
}

function Start-SleepWithProgress
{
    <# 
    .SYNOPSIS
    显示进度条等待指定时间
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Seconds
    )
    if($Seconds -le 0)
    {
        Write-Warning "The sleep time seconds is $Seconds,jump sleep!"
        return $False
    }
    else
    {
        Write-Host "Waiting for $Seconds seconds..."
    }
    for ($i = 0; $i -le $Seconds; $i++)
    {
        $percentComplete = ($i / $Seconds) * 100
        # 保留2位小数
        $percentComplete = [math]::Round($percentComplete, 2)
        Write-Progress -Activity "Waiting..." -Status "$i seconds elapsed of $Seconds ($percentComplete%)" -PercentComplete $percentComplete
        Start-Sleep -Seconds 1
    }

    Write-Progress -Activity "Waiting..." -Completed
}


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
    if($Force)
    {
        Write-Verbose "Force stop all nginx processes..." -Verbose
        $nginx_processes = Get-Process *nginx* -ErrorAction SilentlyContinue
        if($nginx_processes)
        {
            $nginx_processes | Stop-Process -Force -Verbose
            Write-Verbose "Start nginx.exe..." -Verbose
            $p = Start-Process -WorkingDirectory $nginx_home -FilePath "nginx.exe" -ArgumentList "-c", "$nginx_conf" -NoNewWindow # -PassThru
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
        Start-Process -WorkingDirectory $nginx_home -FilePath "nginx.exe" -ArgumentList "-s", "reload" -Wait -NoNewWindow
        Write-Verbose "Nginx.exe -s stop" -Verbose
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

function Approve-NginxValidVhostsConf
{
    <# 
    .SYNOPSIS
    扫描nginx vhosts目录中的各个站点配置文件是否有效(尤其是所指的站点路径)
    如果无效,则会将对应的vhosts中的站点配置文件移除,从而避免nginx启动或重载而受阻
    #>
    [CmdletBinding()]
    param(
        # 典型nginx配置文件路径:C:\phpstudy_pro\Extensions\Nginx1.25.2\conf\vhosts,
        [alias('NginxVhostsDir')]
        $NginxVhostConfDir = "$env:nginx_vhosts_dir" ,
        # 对于nginx服务器的网站,内部应该有标准文件(比如nginx.htaccess),如果要求是wordpress网站,内部要求有wp-config.php文件
        $KeyPath = "*.htaccess"
    )
    $vhosts = Get-ChildItem $NginxVhostConfDir -Filter "*.conf" 
    Write-Verbose "Checking vhosts in $NginxVhostConfDir" -Verbose
    foreach ($vhost in $vhosts)
    {
        $root_info = Get-Content $vhost | Select-String "\s*root\s+" | Select-Object -First 1
        Write-Debug "root line:[ $root_info ]" -Debug
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

            # 保险起见,再检查内部的nginx访问控制标准文件nginx.htaccess是否存在(部分情况下,目录没有移除干净或者被其他进程占用,这种情况下仅仅根据网站根目录是否存在是不够准确的,当然,此时系统内部可能积累了许多错误,建议重启计算机)
            if(Test-Path "$root/$KeyPath")
            {
                Write-Verbose "vhost: $($vhost.Name) $KeyPath exists in root path: $root"  
                $removeVhost = $falseget
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
    Get-Content $Table | Where-Object { $_.Trim() } | Where-Object { $_ -notmatch "^\s*#" } | ForEach-Object { 
        $l = $_ -split '\s+'
        $title = ($_ -split '\d+\.\w{1,5}')[-1].trim().TrimEnd('1') -replace '"', ''
        # 如果行以'\s+1'结尾,则返回$true
        $removeMall = if($_ -match '.*\s+1\s*$') { $true }else { $false }
        @{'domain'       = ($l[0] | Get-MainDomain);
            'user'       = $l[1];
            'template'   = $l[2] ;
            'title'      = $title;
            'removeMall' = $removeMall;
        } 
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

function Show-UnicodeConverterWindow
{
    <#
    .SYNOPSIS
        显示一个图形界面窗口，用于Unicode、HTML和转义字符的编码和解码。

    .DESCRIPTION
        该函数创建一个Windows Forms图形界面，允许用户输入文本并将其编码或解码为不同的格式，
        包括Unicode (\uXXXX)、HTML实体 (&#xxxx;) 和常见的转义字符序列。

    .PARAMETER None
        此函数没有参数。

    .EXAMPLE
        Show-UnicodeConverterWindow
        打开Unicode转换器窗口。

    .NOTES
        功能特性:
        - 支持多种编码/解码模式:
          * 自动检测 (Auto Detect)
          * JavaScript Unicode (\uXXXX)
          * HTML实体 (&#xxxx; 和 &#xXXXX;)
          * 混合模式 (JS+HTML)
          * 常见转义字符 (\n, \t, \r, \", \', \\ 等)
        - 实时预览转换结果
        - 支持窗口大小调整
        - 只读输出区域，防止意外修改

    .LINK
        https://en.wikipedia.org/wiki/List_of_XML_and_HTML_character_entity_references
        https://en.wikipedia.org/wiki/Unicode

    .INPUTS
        None - 此函数不接受管道输入。

    .OUTPUTS
        None - 此函数不返回值，而是显示一个交互式窗口。
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Unicode / HTML / 转义字符 编解码"
    $form.Size = New-Object System.Drawing.Size(880, 640)
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = New-Object System.Drawing.Size(620, 470)
    $form.AutoScaleMode = "Font"

    # 模式标签
    $labelMode = New-Object System.Windows.Forms.Label
    $labelMode.Text = "模式:"
    $labelMode.Location = New-Object System.Drawing.Point(20, 20)
    $labelMode.Size = New-Object System.Drawing.Size(60, 25)

    # 模式下拉框（新增 Mix 和 Common）
    $comboBoxMode = New-Object System.Windows.Forms.ComboBox
    $comboBoxMode.Location = New-Object System.Drawing.Point(80, 20)
    $comboBoxMode.Size = New-Object System.Drawing.Size(200, 25)
    $comboBoxMode.DropDownStyle = "DropDownList"
    $comboBoxMode.Items.AddRange(@(
            "Auto (Detect)",
            "JS (\uXXXX)",
            "HTML",
            "Mix (JS+HTML)",
            "Common (\n, \t, etc.)"
        ))
    $comboBoxMode.SelectedIndex = 0  # 默认 Auto

    # 输入区域
    $labelInput = New-Object System.Windows.Forms.Label
    $labelInput.Text = "输入文本:"
    $labelInput.Location = New-Object System.Drawing.Point(20, 60)
    $labelInput.Size = New-Object System.Drawing.Size(100, 20)

    $textBoxInput = New-Object System.Windows.Forms.TextBox
    $textBoxInput.Multiline = $true
    $textBoxInput.ScrollBars = "Vertical"
    $textBoxInput.Font = New-Object System.Drawing.Font("Consolas", 10)
    $textBoxInput.Location = New-Object System.Drawing.Point(20, 85)
    $textBoxInput.Size = New-Object System.Drawing.Size(820, 140)
    $textBoxInput.Anchor = "Top, Left, Right"

    # 按钮
    $buttonDecode = New-Object System.Windows.Forms.Button
    $buttonDecode.Text = "解码"
    $buttonDecode.Location = New-Object System.Drawing.Point(290, 240)
    $buttonDecode.Size = New-Object System.Drawing.Size(100, 32)

    $buttonEncode = New-Object System.Windows.Forms.Button
    $buttonEncode.Text = "编码"
    $buttonEncode.Location = New-Object System.Drawing.Point(470, 240)
    $buttonEncode.Size = New-Object System.Drawing.Size(100, 32)

    # 输出区域
    $labelOutput = New-Object System.Windows.Forms.Label
    $labelOutput.Text = "输出结果:"
    $labelOutput.Location = New-Object System.Drawing.Point(20, 290)
    $labelOutput.Size = New-Object System.Drawing.Size(100, 20)

    $textBoxOutput = New-Object System.Windows.Forms.TextBox
    $textBoxOutput.Multiline = $true
    $textBoxOutput.ReadOnly = $true
    $textBoxOutput.ScrollBars = "Vertical"
    $textBoxOutput.Font = New-Object System.Drawing.Font("Consolas", 10)
    $textBoxOutput.BackColor = [System.Drawing.Color]::WhiteSmoke
    $textBoxOutput.Location = New-Object System.Drawing.Point(20, 315)
    $textBoxOutput.Size = New-Object System.Drawing.Size(820, 170)
    $textBoxOutput.Anchor = "Top, Left, Right, Bottom"

    # ✅ 修复 Resize 事件
    $form.add_Resize({
            $w = $form.ClientSize.Width
            $h = $form.ClientSize.Height
            $textBoxInput.Width = $w - 40
            $textBoxOutput.Width = $w - 40
            $textBoxOutput.Height = $h - 340
            $centerX = ($w - 220) / 2
            $buttonDecode.Left = $centerX - 55
            $buttonEncode.Left = $centerX + 55
        })

    # ========== 核心解码函数 ==========
    function Decode-Text
    {
        param([string]$Text, [string]$Mode)

        if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

        switch ($Mode)
        {
            "JS (\uXXXX)"
            {
                $result = $Text
                while ($result -match '\\u([0-9a-fA-F]{4})')
                {
                    $char = [char][Convert]::ToInt32($matches[1], 16)
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                return $result
            }

            "HTML"
            {
                $result = $Text
                # 先处理十六进制
                while ($result -match '&#x([0-9a-fA-F]+);')
                {
                    $char = [char][Convert]::ToInt32($matches[1], 16)
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                # 再处理十进制
                while ($result -match '&#(\d+);')
                {
                    $char = [char][int]$matches[1]
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                return $result
            }

            "Mix (JS+HTML)"
            {
                $result = $Text
                # 先解 JS
                while ($result -match '\\u([0-9a-fA-F]{4})')
                {
                    $char = [char][Convert]::ToInt32($matches[1], 16)
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                # 再解 HTML（十进制和十六进制）
                while ($result -match '&#x([0-9a-fA-F]+);')
                {
                    $char = [char][Convert]::ToInt32($matches[1], 16)
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                while ($result -match '&#(\d+);')
                {
                    $char = [char][int]$matches[1]
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                return $result
            }

            "Common (\n, \t, etc.)"
            {
                $result = $Text
                # 注意：必须按顺序，避免干扰（如先处理 \\）
                $result = $result -replace '\\\\', '\'        # \\ → \
                $result = $result -replace '\\"', '"'         # \" → "
                $result = $result -replace "\\'", "'"         # \' → '
                $result = $result -replace '\\n', "`n"        # \n → 换行
                $result = $result -replace '\\r', "`r"        # \r → 回车
                $result = $result -replace '\\t', "`t"        # \t → 制表符
                $result = $result -replace '\\b', "`b"        # \b → 退格
                $result = $result -replace '\\f', "`f"        # \f → 换页
                return $result
            }

            default
            {
                # Auto 模式由调用方处理，此处不触发
                return $Text
            }
        }
    }

    # ========== 编码函数（仅 JS/HTML） ==========
    function Encode-Text
    {
        param([string]$Text, [string]$Mode)

        if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

        if ($Mode -eq "JS (\uXXXX)")
        {
            -join ($Text.ToCharArray() | ForEach-Object {
                    $code = [int]$_
                    if ($code -le 0xFFFF)
                    {
                        "\u{0:x4}" -f $code
                    }
                    else
                    {
                        $high = 0xD800 + (($code - 0x10000) -shr 10)
                        $low = 0xDC00 + (($code - 0x10000) -band 0x3FF)
                        "\u{0:x4}\u{1:x4}" -f $high, $low
                    }
                })
        }
        elseif ($Mode -eq "HTML")
        {
            -join ($Text.ToCharArray() | ForEach-Object { "&#$( [int]$_ );" })
        }
        else
        {
            throw "Unsupported encode mode: $Mode"
        }
    }

    # ========== Auto 检测 ==========
    function Detect-EncodingMode
    {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

        $jsCount = ([regex]::Matches($Text, '\\u[0-9a-fA-F]{4}')).Count
        $htmlCount = ([regex]::Matches($Text, '&#x[0-9a-fA-F]+;|&#\d+;')).Count

        if ($jsCount -eq 0 -and $htmlCount -eq 0)
        {
            return $null
        }

        if ($jsCount -ge $htmlCount)
        {
            return "JS (\uXXXX)"
        }
        else
        {
            return "HTML"
        }
    }

    # ========== 按钮事件 ==========
    $buttonDecode.Add_Click({
            $input = $textBoxInput.Text
            if ([string]::IsNullOrWhiteSpace($input))
            {
                $textBoxOutput.Text = ""
                return
            }

            $mode = $comboBoxMode.SelectedItem

            if ($mode -eq "Auto (Detect)")
            {
                $detected = Detect-EncodingMode -Text $input
                if ($null -eq $detected)
                {
                    $textBoxOutput.Text = $input
                }
                else
                {
                    $result = Decode-Text -Text $input -Mode $detected
                    $textBoxOutput.Text = $result
                }
            }
            else
            {
                $result = Decode-Text -Text $input -Mode $mode
                $textBoxOutput.Text = $result
            }
        })

    $buttonEncode.Add_Click({
            $input = $textBoxInput.Text
            if ([string]::IsNullOrWhiteSpace($input))
            {
                $textBoxOutput.Text = ""
                return
            }

            $mode = $comboBoxMode.SelectedItem

            if ($mode -notin @("JS (\uXXXX)", "HTML"))
            {
                [System.Windows.Forms.MessageBox]::Show(
                    "编码仅支持 'JS' 或 'HTML' 模式。",
                    "模式不支持",
                    "OK",
                    "Warning"
                )
                return
            }

            try
            {
                $result = Encode-Text -Text $input -Mode $mode
                $textBoxOutput.Text = $result
            }
            catch
            {
                $textBoxOutput.Text = "编码错误: $($_.Exception.Message)"
            }
        })

    # 添加控件
    $form.Controls.AddRange(@(
            $labelMode, $comboBoxMode,
            $labelInput, $textBoxInput,
            $buttonDecode, $buttonEncode,
            $labelOutput, $textBoxOutput
        ))

    [void]$form.ShowDialog()
}


function Get-CharCount
{
    <#
.SYNOPSIS
    计算字符串中指定字符出现的次数。

.DESCRIPTION
    Get-CharCount 函数通过比较原字符串和移除指定字符后的字符串长度差，来计算指定字符在输入字符串中出现的次数。

.PARAMETER InputString
    需要检查的输入字符串。

.PARAMETER Char
    需要计算出现次数的字符。

.EXAMPLE
    Get-CharCount -InputString "Hello World" -Char "l"
    返回值为 3，因为字符 "l" 在 "Hello World" 中出现了 3 次。

.EXAMPLE
    Get-CharCount -InputString "PowerShell" -Char "e"
    返回值为 2，因为字符 "e" 在 "PowerShell" 中出现了 2 次。

.INPUTS
    System.String
    可以通过管道传递字符串。

.OUTPUTS
    System.Int32
    返回指定字符在输入字符串中出现的次数。

.NOTES
    函数通过计算原字符串长度与移除指定字符后字符串长度的差值来确定字符出现次数。
#>
    param(
        [string]$InputString,
        [string]$Char
    )
    return $InputString.Length - ($InputString.Replace($Char, "")).Length
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

function Restart-OS
{
    <# 
    重启到指定系统或BIOS的图形界面
    #>
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

function Get-Json
{
    <#
.SYNOPSIS
    Reads a specific property from a JSON string or JSON file. If no property is specified, returns the entire JSON object.
    调用powershell中的ConvertFrom-Json cmdlet处理

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
    .DESCRIPTION
    如果是通过scoop安装的python,会尝试创建shims目录下python.shim的符号链接
    其余情况仅尝试创建python.exe的符号链接py.exe
    .PARAMETER pythonPath
    可选的,指定Python的路径(可执行程序的完整路径)，如果为空，则默认使用gcm命令尝试获取当前用户的python.exe路径
    #>
    [CmdletBinding()]
    param(
        $pythonPath = ""
    )
    if($pythonPath -eq "")
    {

        $pythonPath = Get-Command python | Select-Object -ExpandProperty Source

    }

    $PythonParentDir = Split-Path $pythonPath -Parent
    # 检查是否通过scoop安装python，需要特殊处理shim
    if($pythonPath -like "*scoop*")
    {
        Write-Verbose "检测当前python版本可能通过scoop安装的python，正在验证scoop可用性"
        if(Get-Command scoop -ErrorAction SilentlyContinue)
        {
            # Write-Host "scoop可用，正在获取python.exe真实路径"
            # $pythonPath = scoop which python
            New-Item -ItemType SymbolicLink -Path $PythonParentDir/py.shim -Target $PythonParentDir/python.shim -Verbose -Force
        }
    }
    # $PythonParentDir = Split-Path $pythonPath -Parent
    New-Item -ItemType SymbolicLink -Path $PythonParentDir/py.exe -Value $pythonPath -Force -Verbose -ErrorAction SilentlyContinue
}

Register-ArgumentCompleter -CommandName Get-Json -ParameterName Key -ScriptBlock ${function:Get-JsonItemCompleter}
