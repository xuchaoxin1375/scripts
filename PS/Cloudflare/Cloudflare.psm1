

function Set-CFCredentials
{
    <# 
    .SYNOPSIS
    设置cloudflare API的授权信息(临时地)
    这对于有多个账号需要切换的场景比较有用
    如果要长期有效或者简便起见,可以考虑在环境变量中配置相应名字的环境变量
    例如:
    $env:CF_API_TOKEN = "your_api_token"
    或者传统的
    $env:CF_API_KEY = "your_api_key"
    
    .EXAMPLE 
    Set-CFCredentials -CfAccount account2
    .EXAMPLE
    Set-CFCredentials -CfAccount account2 -CfConfig $deploy_configs/cf_config.json
    .NOTES
    查看可以用的cfaccount名字,可以打开cf_config.json文件查看
    cat $cf_config
    .Notes
    部分情况下,此命令修改CF相关环境变量会失败,如果出现这种情况,请手动设置环境变量,或者新开一个powershell窗口再试
    #>
    [CmdletBinding(DefaultParameterSetName = 'FromFile')]
    param (
        [parameter(ParameterSetName = 'FromCliToken')]
        [string]$ApiToken,
        [parameter(ParameterSetName = 'FromCliKey')]
        [string]$ApiKey,
        [parameter(ParameterSetName = 'FromCliToken')]
        [parameter(ParameterSetName = 'FromCliKey')]
        [string]$ApiEmail,
        [parameter(ParameterSetName = 'FromFile')]
        $CfConfig = "$deploy_configs/cf_config.json",

        # [parameter(ParameterSetName = 'FromFile', Mandatory = $true)]
        [alias("Account")]
        $CfAccount
    )
    if($PSCmdlet.ParameterSetName -eq 'FromFile')
    {
        $config = Get-Content $CfConfig | ConvertFrom-Json
        $account = $config."accounts"."$CfAccount"
        $Apikey = $account.cf_api_key
        $ApiEmail = $account.cf_api_email
        $ApiToken = $account.cf_api_token
        
        # 检查 CfAccount 是否存在于配置文件中(账号代号可用性检查)
        $availableCfAccountCodes = Get-CFAccountsCodeDF
        if ($CfAccount -notin $availableCfAccountCodes)
        {
            Write-Error "请检查你的输入,没有对应的CfAccount: $CfAccount"
            Write-Host "可用的CfAccount代码有: $availableCfAccountCodes"
            return $false
        }
    }
    if ($ApiToken)
    {
        # 切换为 token 认证时清理可能残留的 key/email,避免认证参数取值歧义
        Remove-Item Env:CF_API_KEY -ErrorAction SilentlyContinue
        Remove-Item Env:CLOUDFLARE_API_KEY -ErrorAction SilentlyContinue
        Remove-Item Env:CF_API_EMAIL -ErrorAction SilentlyContinue
        Remove-Item Env:CLOUDFLARE_EMAIL -ErrorAction SilentlyContinue
        $env:CF_API_TOKEN = $ApiToken
        $env:CLOUDFLARE_API_TOKEN = $ApiToken
        $global:CLOUDFLARE_API_TOKEN = $ApiToken
        Write-Host "Cloudflare API Token 已配置($env:CF_API_TOKEN)"

        Write-Host "CLOUDFLARE_API_TOKEN = $ApiToken"

        # 测试配置信息是否能成功获取信息
        curl.exe "https://api.cloudflare.com/client/v4/user/tokens/verify" -H "Authorization: Bearer $ApiToken" 
    
    }
    if ($ApiKey -and $ApiEmail)
    {
        # 切换为 key/email 认证时清理可能残留的 token,避免认证参数取值歧义
        Remove-Item Env:CF_API_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:CLOUDFLARE_API_TOKEN -ErrorAction SilentlyContinue
        $global:CLOUDFLARE_API_TOKEN = $null
        # 
        $env:CF_API_EMAIL = $ApiEmail
        $env:CLOUDFLARE_EMAIL = $ApiEmail
        $global:CLOUDFLARE_EMAIL = $ApiEmail
        
        $env:CF_API_KEY = $ApiKey
        $env:CLOUDFLARE_API_KEY = $ApiKey
        $global:CLOUDFLARE_API_KEY = $ApiKey
        

        Write-Output "Cloudflare API Key 和 Email 已配置:($env:CF_API_EMAIL)&($env:CF_API_KEY)"

        # 测试配置信息是否能成功获取信息(统一走 curl,不再依赖 flarectl)
        Write-Host "Testing curl command..."
        $userInfo = curl https://api.cloudflare.com/client/v4/user -H "X-Auth-Email: $CLOUDFLARE_EMAIL" -H "X-Auth-Key: $CLOUDFLARE_API_KEY"
        $userID = ($userInfo | ConvertFrom-Json).result.id

        
        $env:ACCOUNT_ID = $userID
        $global:ACCOUNT_ID = $userID
        # 打印配置信息,也可以供bash复制粘贴使用
        Write-Host @"
        CLOUDFLARE_EMAIL = $ApiEmail
        CLOUDFLARE_API_KEY = $ApiKey
        ACCOUNT_ID = $userID
        
        CLOUDFLARE_API_TOKEN = $ApiToken      
"@
    }
    else
    {
        Write-Error "请提供 API Token 或 API Key + Email"
    }
    return $userInfo
}
function Get-CFZoneID
{
    <# 
    .SYNOPSIS
    查询指定域名在 Cloudflare 账号中的 Zone ID。
    .DESCRIPTION
    调用 cloudflare_dns_tool.py 的查找模式(-f/--json --quiet),从结果中提取 zone_id。
    认证优先取当前环境变量(由 Set-CFCredentials 设置),否则回退到配置文件。
    #>
    [CmdletBinding()]
    param (
        [alias("Zone")][string]$Domain, # 要查询的域名
        [string]$Email = $env:CF_API_EMAIL, # Cloudflare 账户 Email
        [string]$APIKey = $env:CF_API_KEY, # Cloudflare 全局 API Key
        $CfConfig = "$cf_config",
        $script = "$pys/cf_api/cloudflare_dns_tool.py"
    )
    Write-Verbose "Domain: $Domain"
    Write-Verbose "Email: $Email"
    Write-Verbose "APIKey: $APIKey"

    $authArgs = @()
    if ($env:CF_API_TOKEN) { $authArgs = @('-t', $env:CF_API_TOKEN) }
    elseif ($Email -and $APIKey) { $authArgs = @('-e', $Email, '-k', $APIKey) }
    else { $authArgs = @('--config', $CfConfig) }

    $raw = python $script -f $Domain --json --quiet @authArgs | Out-String
    $data = $null
    try { $data = $raw | ConvertFrom-Json } catch { Write-Warning "解析查询结果失败: $raw"; return $null }
    $results = @($data.results)
    $zoneID = ""
    if ($results.Count -gt 0) { $zoneID = $results[0].zone.zone_id }

    if ($zoneID)
    {
        Write-Output $zoneID
    }
    else
    {
        Write-Output "Error: Zone ID for '$Domain' not found!"
    }
}
function Get-CFZoneDnsInfo
{
    <# 
    .SYNOPSIS
    获取域名的DNS信息(调用 cloudflare_dns_tool.py --list-dns)。
    #>
    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline = $true)]
        $Domain,
        [switch]$Json
    )
    process
    {
        Write-Verbose "processing domain: $Domain"
        $authArgs = @()
        if ($env:CF_API_TOKEN) { $authArgs = @('-t', $env:CF_API_TOKEN) }
        elseif ($env:CF_API_EMAIL -and $env:CF_API_KEY) { $authArgs = @('-e', $env:CF_API_EMAIL, '-k', $env:CF_API_KEY) }
        $jsonArg = @()
        if ($Json) { $jsonArg = @('--json', '--quiet') }
        $item = python "$pys/cf_api/cloudflare_dns_tool.py" --list-dns $Domain @jsonArg @authArgs | Out-String
        return $item + "`n"
    }
}

function Add-CFZoneDNSRecords
{
    <# 
    .SYNOPSIS
    利用cloudflare API设置域名的DNS记录
    这里调用 cloudflare_dns_tool.py(--add-domain / --add-record)操作
    
    默认情况下(不使用额外参数),此命令会尝试从读取到的域名列表添加cloudflare账户中,但是dns不会默认立即添加,除非使用-AddRecordAtOnce参数
    此外,如果你的cloudflare验证了你的账号对dns的所有权,那么你可以利用此函数的-AddRecordOnly参数,添加dns记录到对应的域名解析记录

    .DESCRIPTION
    认证优先取当前环境变量(由 Set-CFCredentials 设置),否则回退到配置文件
    根据授权方式不同,有不同的配置api key/api token
    例如使用传统的api key
    配置两个环境变量:
    CF_API_EMAIL
    CF_API_KEY

    .EXAMPLE
    Set-CFCredentials -Account account3-1
    Add-CFZoneDNSRecords -Domains .\table-s3.conf -Parallel -Verbose -Debug

    .NOTES
    -Parallel 参数保留以兼容旧调用,但实现为串行调用 Python 工具(工具自带限流与重试)
    cloudflare推荐使用新式地api token,而非旧式的api key,因此如果你要使用api key,可能更不容易找到入口
    api key的形式是否被启用,请查看cloudflare的官方文档
    如果没有被弃用,可以参考如下链接到你的cloudflare账号中找到设置入口
    https://dash.cloudflare.com/profile/api-tokens    
    注意,查看global api token的权限,可能会让你输入cloudflare的登录密码(如果你是使用google账号登录的,
    那么可能需要退出登录,回到cloudflare登入页面,输入邮箱(google gmial),然后点击忘记密码,
    这可以让你通过google邮箱来设定/重置你的密码,即便你从未设置过密码)

    默认清空下,函数添加三条A类记录
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # 
        [alias('Table')]
        $Domains = "$Desktop\table.conf",
        # 默认使用私人模式DF,启用Common开关变成通用模式
        [switch]$Common,
        # 域名添加模式(todo提供内部判断,根据IP类型自动选择类型)
        $Type = 'A' ,
        [alias('IP', 'Content')]
        $Value
        ,
        # $DefaultDNSRecord = $true,
        $RecordNames = @("www", "*"),
        [switch]$No2LDDomain,
        # 考虑到安全性,分为两个步骤(添加域名,然后你更该域名供应商管理面板更新dns,最后回到cloudflare进行域名的dns记录(ip解析)添加)
        # 第一遍运行不带下面参数的命令;第二遍运行带$AddRecordAtOnce参数的命令

        # 添加完域名后,是否立即添加对应的DNS记录(默认不添加)
        [switch]$AddRecordAtOnce,
        # 仅添加域名的DNS记录,不检查域名是否被添加(如果域名尚未被添加到cloudflare,那么添加dns记录就会失败跳过)
        [switch]$AddRecordOnly,
        # 允许同名 A/AAAA 多值(同一主机名多个 IP);默认关闭,同名只保留一条
        [switch]$AllowMultiValue,
        # 强制执行,不进行确认
        [switch]$Parallel,
        [switch]$Force
    )
   
    if(Test-Path $Domains)
    {
        $Domains = Get-Content $Domains -Raw
    }
    if(!$Common)
    {
        Write-Host "Mode:DF"
        $res = Get-DomainUserDictFromTable -Table $Domains
        $Domains = $res | ForEach-Object { $_.Domain }
    }
    # 遍历检查解析出来的域名
    # $domains | ForEach-Object {
        
    #     Write-Host "Domains: $_"
    # }
    Write-Host "Domains: $Domains"

    $msg = $Domains | Format-DoubleColumn | Out-String
    Write-Host $msg
    # pause

    if ($Force -and -not $Confirm) #或 if ($Force -and !$Confirm)
    {
        # 将消息确认级别设置为关闭,即将询问偏好设置为低,让用户不需要再交互确认后续的动作,直接执行
        $ConfirmPreference = 'None'
    }
    if($PSCmdlet.ShouldProcess("Cloudflare DNS Records", "Add DNS records for domains"))
    {
        Write-Host "start add dns records..."
    }
    else
    {
        Write-Host "Skipped"
        return
    }
    # 统一走 cloudflare_dns_tool.py:逐个域名创建 zone(可选)并添加 DNS 记录。
    # Python 工具自带限流与重试,这里保持串行,避免外部再叠加并发。
    $authArgs = @()
    if ($env:CF_API_TOKEN) { $authArgs = @('-t', $env:CF_API_TOKEN) }
    elseif ($env:CF_API_EMAIL -and $env:CF_API_KEY) { $authArgs = @('-e', $env:CF_API_EMAIL, '-k', $env:CF_API_KEY) }
    else { $authArgs = @('--config', "$cf_config") }
    $multiArgs = @()
    if ($AllowMultiValue) { $multiArgs = @('--allow-multi-value') }

    foreach ($domainItem in $Domains)
    {
        $domain = "$domainItem".ToLower()
        Write-Host "正在处理域名:$domain"
        $addArgs = @()
        if (!$AddRecordOnly) { $addArgs += @('--add-domain', $domain) } else { $addArgs += @('-z', $domain) }

        if ($AddRecordAtOnce -or $AddRecordOnly)
        {
            $recordNamesForIt = @($RecordNames)
            if (!$No2LDDomain) { $recordNamesForIt += $domain }
            Write-Host "Record names to add: $recordNamesForIt"
            foreach ($item in $recordNamesForIt)
            {
                Write-Host "Adding DNS record: $domain|$item -> $Value ($Type)"
                if ($Type -eq 'MX')
                {
                    $addArgs += @('--add-record', "${item}:MX:$Value", '--no-proxied')
                }
                else
                {
                    $addArgs += @('--add-record', "${item}:${Type}:$Value")
                }
            }
        }

        python "$pys/cf_api/cloudflare_dns_tool.py" @addArgs @authArgs @multiArgs
    }
}

function Add-CFZoneConfig
{
    <# 
    .SYNOPSIS
    利用cloudflare API配置cloudflare账户(包括ssl加密方式(灵活)等并且配置邮箱转发和安全选项启用)
    目前只要cloudflare账户添加了域名(即便还没有验证和激活),也可以进行此环节的配置
    #>
    [CmdletBinding()]
    param(
        $Account,
        $Ip = "",
        $CfConfig = "$cf_config",
        $script = "$pys/cf_api/cloudflare_dns_tool.py",
        $Table = "$desktop/table.conf"
    )
    Write-Host "正在配置cloudflare域名邮箱转发和安全选项开关..."
    Write-Output $PSBoundParameters
    Get-DomainUserDictFromTableLite -Table $Table
    Write-Verbose "调用python脚本cloudflare_dns_tool.py(provision模式)设置域名配置..."

    # 仅在提供值时附加可选参数,避免空账号/空IP传给 argparse
    $selectArgs = @()
    if ($Account) { $selectArgs = @('--select-account', $Account) }
    $ipArgs = @()
    if ($Ip) { $ipArgs = @('--server-ip', $Ip) }

    python $script --provision --provision-table $Table --config $CfConfig @selectArgs @ipArgs --no-activation
}
function Add-CFZoneCheckActivation
{
    <# 
    .SYNOPSIS
    检查表格中域名的 Cloudflare 激活状态
    .DESCRIPTION
    调用 cloudflare_dns_tool.py --list-zones 读取各 zone 状态并打印。
    认证优先取当前环境变量(由 Set-CFCredentials 设置),否则回退配置文件。
    #>
    [CmdletBinding()]
    param (
        $Account = "account2",
        $Table = "$desktop/table.conf",
        $ConfigPath = "$cf_config"
    )
    Write-Host "Account format is: account[x[-y]]"
    Set-CFCredentials -CfConfig $ConfigPath -CfAccount $Account

    $info = Get-CFZoneInfoFromTable -Table $Table
    foreach ($item in @($info))
    {
        Write-Host "$($item.Zone): $($item.status)"
    }
}
function Get-CFZoneInfoFromTable
{
    <# 
    .SYNOPSIS
    查询cloudflare中的域名信息
    从表格(或 -Domains 传入的域名)获取域名列表,调用 cloudflare_dns_tool.py --list-zones 获取信息,
    返回对象含 Zone / status / ID / 'Name Servers' 字段(兼容旧的 flarectl 输出形状)。
    #>
    [CmdletBinding()]
    param(
        [alias('Domain')]$Table = "$home/desktop/table.conf",
        [string[]]$Domains,
        [switch]$Json,
        [alias('Threads')]$ThrottleLimit = 5,
        $script = "$pys/cf_api/cloudflare_dns_tool.py"
    )
    $targets = @()
    if ($Domains)
    {
        $targets = @($Domains)
    }
    else
    {
        $targets = @(Get-DomainUserDictFromTable -Table $Table | ForEach-Object { $_.domain })
    }

    $authArgs = @()
    if ($env:CF_API_TOKEN) { $authArgs = @('-t', $env:CF_API_TOKEN) }
    elseif ($env:CF_API_EMAIL -and $env:CF_API_KEY) { $authArgs = @('-e', $env:CF_API_EMAIL, '-k', $env:CF_API_KEY) }

    $tmp = [IO.Path]::GetTempFileName()
    try
    {
        python $script --list-zones --zone-status all --zones-output $tmp @authArgs | Out-Null
        $rows = @(Import-Csv -Path $tmp)
    }
    finally
    {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }

    $targetSet = @{}
    foreach ($d in $targets) { $targetSet["$d".Trim().ToLower()] = $true }

    $res = @()
    foreach ($row in $rows)
    {
        if (!$targetSet.ContainsKey("$($row.name)".Trim().ToLower())) { continue }
        $res += [pscustomobject]@{
            Zone           = $row.name
            status         = $row.status
            ID             = $row.zone_id
            'Name Servers' = ($row.nameservers -replace ';', ',')
        }
    }

    if ($Json)
    {
        if ($res.Count -eq 0) { return '[]' }
        return ($res | ConvertTo-Json)
    }
    return $res
}
function Get-CFZoneNameServersTable
{
    <# 
    .SYNOPSIS
    读取域名信息并提取 name servers,保存到 3 列(domain,nameserver1,nameserver2)的 csv 文件中
    该格式可与配套的 spaceship_api 脚本配合使用,实现精准的域名服务器更改
    #>
    [CmdletBinding()]
    param (
        $FromTable = "$Desktop\table.conf",
        $ToTable = "$Desktop\domains_nameservers.csv",
        $Threads = 5
    )
    Write-Debug "CF account:[$env:CF_API_EMAIL]"
    $j = @(Get-CFZoneInfoFromTable -Table $FromTable -Threads $Threads)
    $core = foreach ($zoneInfo in $j)
    {
        $nameservers = "$($zoneInfo.'Name Servers')" -split ','
        [pscustomobject]@{
            domain      = $zoneInfo.Zone
            nameserver1 = "$($nameservers[0])".Trim()
            nameserver2 = "$($nameservers[1])".Trim()
        }
    }
    $core | Export-Csv -Path $ToTable -NoTypeInformation -Encoding utf8 -Force
    Write-Host "Name servers table has been saved to $ToTable"
    return $core
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