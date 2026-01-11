

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
    TODO:添加flarectl 读取环境变量后返回用户信息与指定账号对比检验

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
        $CfAccount,
        # 测试配置信息有效性测试方案
        [ValidateSet('Curl', 'Flarectl')]
        $TestBy = 'Curl'
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
        # 
        $env:CF_API_EMAIL = $ApiEmail
        $env:CLOUDFLARE_EMAIL = $ApiEmail
        $global:CLOUDFLARE_EMAIL = $ApiEmail
        
        $env:CF_API_KEY = $ApiKey
        $env:CLOUDFLARE_API_KEY = $ApiKey
        $global:CLOUDFLARE_API_KEY = $ApiKey
        

        Write-Output "Cloudflare API Key 和 Email 已配置:($env:CF_API_EMAIL)&($env:CF_API_KEY)"

        # 测试配置信息是否能成功获取信息
        # 方案1:curl
        if($TestBy -eq 'Curl')
        {
            Write-Host "Testing curl command..."
            $userInfo = curl https://api.cloudflare.com/client/v4/user -H "X-Auth-Email: $CLOUDFLARE_EMAIL" -H "X-Auth-Key: $CLOUDFLARE_API_KEY"
            $userID = ($userInfo | ConvertFrom-Json).result.id
            
        }
        elseif($TestBy -eq 'Flarectl')
        {
            # 方案2 flarectl
            Write-Debug "相关环境变量取值:CF_API_EMAIL=$env:CF_API_EMAIL; CF_API_KEY=$env:CF_API_KEY"
            if(Get-Command flarectl -ErrorAction SilentlyContinue)
            {
                Write-Host "Testing connection by flarectl command..."
                # flarectl user info 
                $userInfo = flarectl --json user info 
                $userID = $userInfo | ConvertFrom-Json | Select-Object -ExpandProperty id
            }
            else
            {
                Write-Warning "flarectl command not found in PATH. Please ensure flarectl is installed and available in your system PATH."
            }
        }

        
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
function Get-CFZoneDnsInfo
{
    <# 
    .SYNOPSIS
    获取域名的DNS信息
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
        $j = if($json) { '--json' }else { '' }
        $item = flarectl.exe $j dns list --zone $Domain 
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

    .EXAMPLE
    Set-CFCredentials -Account account3-1
    Add-CFZoneDNSRecords -Domains .\table-s3.conf -Parallel -Verbose -Debug

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
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # 
        [alias('Table')]
        $Domains = "$Desktop\table.conf",
        # 默认使用私人模式DF,启用Common开关变成通用模式
        [switch]$Common,
        # 域名添加模式
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
    if($Parallel)
    {

    
        $Domains | ForEach-Object -Parallel {
     
            $domain = $_.ToLower()
            Write-Host "正在处理域名:$_"
            Write-Host "当前CF账号(环境变量)信息:$env:CF_API_EMAIL"
            # 默认情况下总是尝试先创建域名(无论是否已经存在),使用AddRecordOnly参数时则不创建域名
            if(!$using:AddRecordOnly)
            {

                Write-Host "尝试创建域名[$domain] (如果不存在的话)..."
                flarectl zone create --zone "$domain" 
                # flarectl zone create --zone "$domain" *> $null # 创建域名
            }
        
            $value = $using:Value
            $Type = $using:Type
            Write-Host "Set DNS record for domain: $domain" 
            Write-Host "add type:$type; value:$value; domain:$domain"
            if($using:AddRecordAtOnce -or $using:AddRecordOnly)
            {

                # 常用类型DNS记录的添加
                # 一次性添加两条:一条*和$domain;记得启用代理选项保护ip
                if(!$using:No2LDDomain)
                {
                    $RecordNamesForIt = ($using:RecordNames).clone()
                    $RecordNamesForIt += $domain
                }
                
                Write-Host "Record names to add: $RecordNamesForIt"
                foreach ($item in $RecordNamesForIt)
                {
                    Write-Host "Adding DNS record[$(Get-DateTime)]: $domain|$item -> $value ($type)"
                    # continue
                    # 调用flarectl命令行工具,并将运行结果保存到变量$res中
                    $cmd = "flarectl --json dns create --zone $domain --name $item --type $type --content $value --proxy "
                    Write-Host "Starting cmd:[ $cmd ]"
                    $res = $cmd | Invoke-Expression 
                    Write-Host $res
                    Write-Host "Add $domain done!"
                }
                
          
            }
        } -ThrottleLimit 5
    }
    else
    {
        # 串行添加
        $Domains | ForEach-Object {
     
            $domain = $_.ToLower()
            Write-Host "正在处理域名:$_"
            # 默认情况下总是尝试先创建域名(无论是否已经存在),使用AddRecordOnly参数时则不创建域名
            if(!$AddRecordOnly)
            {

                Write-Host "尝试创建域名[$domain] (如果不存在的话)..."
                flarectl zone create --zone "$domain" 
                # flarectl zone create --zone "$domain" *> $null # 创建域名
            }
        
            Write-Host "Set DNS record for domain: $domain" 
            if ($type -eq "MX")
            {
                # 比较少用
                $priority = $record
                Write-Host "Adding MX record: $domain -> $value (Priority: $priority)"
                $res = flarectl dns create --zone "$domain" --name "$domain" --type "$type" --content "$value" --priority "$priority" --proxy 
                Write-Host $res
            }
            else
            {
                if($AddRecordAtOnce -or $AddRecordOnly)
                {

                    # 常用类型DNS记录的添加
                    # 一次性添加两条:一条*和$domain;记得启用代理选项保护ip
                    if(!$No2LDDomain)
                    {
                        $RecordNamesForIt = $RecordNames.clone()
                        $RecordNamesForIt += $domain
                    }
                
               
                    foreach ($item in $RecordNamesForIt)
                    {
                        Write-Host "Adding DNS record: $domain|$item -> $value ($type)"
                        $res = flarectl --json dns create --zone "$domain" --name "$item" --type "$type" --content "$value" --proxy true
                        Write-Host $res
                    }

                }
            }
        }
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
        $script = "$pys/cf_api/cf_config_api.py",
        $Table = "$desktop/table.conf"
    )
    Write-Host "正在配置cloudflare域名邮箱转发和安全选项开关..."
    Write-Output $PSBoundParameters
    Get-DomainUserDictFromTableLite -Table $Table
    Write-Verbose "调用python脚本cf_config_api.py设置域名配置..."

    python $script configure -c $CfConfig -f $Table -a $Account -ip $ip
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
        $Account = "account2",
        $Table = "$desktop/table.conf",
        $ConfigPath = "$cf_config"
    )
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $account = $config."accounts"."$Account"
    Set-CFCredentials -ApiKey $account.cf_api_key -ApiEmail $account.cf_api_email -CfAccount $Account
    # 查看当前的环境变量
    # Get-ChildItem env:cf*

    Get-Content $Table | Where-Object { $_.Trim() } | ForEach-Object { ($_.trim() -split '\s+')[0] | Get-MainDomain } | ForEach-Object -Parallel { flarectl zone check --zone $_ *> $null; Write-Host $_ } -ThrottleLimit 5
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
        [alias('Domain')]$Table = "$home/desktop/table.conf",
        [switch]$Json,
        [alias('Threads')]$ThrottleLimit = 5
    )
    Write-Host $Table
    $info = Get-DomainUserDictFromTable -Table $Table 
    $jsonFormat = if($Json) { "--json" } else { "" }
    $res = $info | ForEach-Object { $_.domain } | ForEach-Object -Parallel { 
        $item = "flarectl $using:JsonFormat zone info $_" | Invoke-Expression 
        Write-Host $item 
        Write-Output $item
    } -ThrottleLimit $ThrottleLimit
    return $res
}
function Get-CFZoneNameServersTable
{
    <# 
    .SYNOPSIS
    读取cloudflare命令行工具flarectl的输出中的域名信息(json格式),并获取域名对应的name servers,并保存到表格中(csv文件)
    此转换的过程会为flarectl返回的json做如下处理:
    1.转换为pscustomobject
    2.解析'name servers'属性,并添加nameserver1和nameserver2两个属性
    3.保存到带有3列(zone,nameserver1,nameserver2)的表格中csv文件中,这个格式可以和配套的spaceship_api脚本配合使用,实现精准的域名服务器更改
    #>
    [CmdletBinding()]
    param (
        $FromTable = "$Desktop\table.conf",
        $ToTable = "$Desktop\domains_nameservers.csv",
        $Threads = 5
    )
    Write-Debug "CF account:[$env:CF_API_EMAIL]"
    $j = Get-CFZoneInfoFromTable -Table $FromTable -Json -Threads $Threads | ConvertFrom-Json  # | Select-Object 'zone', 'name servers'
    $res = $j | ForEach-Object -Parallel {
        $nameservers = $_.'Name Servers' -split ','
        $nameserver1, $nameserver2 = $nameservers[0].trim(), $nameservers[1].trim()
        # Write-Host $nameservers
        $_ | Add-Member -Name 'domain' -Value $_.'Zone' -MemberType NoteProperty
        $_ | Add-Member -Name 'nameserver1' -Value $nameserver1 -MemberType NoteProperty
        $_ | Add-Member -Name 'nameserver2' -Value $nameserver2 -MemberType NoteProperty
        Write-Output $_
    } -ThrottleLimit 5
    $core = $res | Select-Object 'domain', 'nameserver1', 'nameserver2' 
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