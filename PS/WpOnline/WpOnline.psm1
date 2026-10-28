<#
WpOnline 模块:WordPress 线上运维(建站上线/插件/订单/远程更新)。
从 WordPress.psm1 迁入: WordPress 只留本地建站与总入口 Deploy-Wp,线上运维归此模块;
调用方命令名不变(自动发现同名模块)。
#>

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
        # 网站域名表在服务器上的路径
        $RemoteSiteTable = '/www/site_table.conf',

        # 域名绑定cf后解析cf返回的查询结果来传递给spaceship更新域名的nameservers的中间表格
        [alias('DomainTable')]$ToTable = "$Desktop/domains_nameservers.csv",
        # proxy_pass 的风格,是否带上协议名
        [ValidateSet('http', 'https', 'auto', '')]
        $Scheme = 'auto',
        # 反代模式,关乎反代服务器上的routes.map的路径构造.(base对应的Scheme为'http',而tenants对应于'')
        [ValidateSet('base', 'tenants')]
        $ReverseMode = 'tenants',
        # 服务器管理员id (注意要和反代服务器上的配置一致,否则无法正确写入routes.map)
        # 配置方式: Set-EnvVar -EnvVar SERVER_ADMIN_ID -NewValue xcx # 此处xcx为管理员id
        $AdminId = $env:SERVER_ADMIN_ID,
        # 适用于反代的hostmap
        [alias('HostMap')]$RoutesMap = "$Desktop/routes.map.conf",
        $ReverseNginxConfDir = "",# 例如/etc/nginx,缺失将尝试从配置文件中获取.
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
        [switch]$Onebyone,
        # 本地调试模式:跳过所有联网操作(scp/ssh/CF API/宝塔 API/激活等待循环),
        # 只跑本地逻辑(配置解析/routes.map 生成/路径计算)并列出本来要执行的操作,适合排查本地处理逻辑和效果
        [switch]$LocalDebug

    
    )
    # 让python使用utf-8编码,防止在powershell后台作业中(由receive-job接收的)输出非英文字符乱码
    $env:PYTHONUTF8 = 1
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # 设置控制台输出编码为 UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  
    # 解析服务器配置
    $serversConfig = Get-Content $ServerConfig | ConvertFrom-Json
    $servers = $serversConfig.servers
    Write-Verbose "Get Server $servers"
    $server = $HostName # 例如 server1
    # server name -> server ip
    $serverObj = $servers."$HostName"
    $HostName = $serverObj.ip

    # 计算反代服务器的ip(如果有的话,没有则发出警告,并设置为普通ip)
    $reverse = $serverObj.ip_reverse
    if (!$reverse)
    {
        Write-Warning "No reverse server ip found,use normal ip instead!"
        $reverse = $HostName
    }
    Write-Verbose "Deploy to server: $server,IP:$HostName [IP reverse:$reverse]"
    # 计算域名-ip映射表(适用于nginx反代map上下文)
    # $hostmap=
    $items = Get-DomainUserDictFromTableLite -Table $FromTable
    Write-Verbose "Get domain-ip mapping table from table.conf,save result to $RoutesMap"
    # proxy_pass 前缀修正(注意:不要回写 $Scheme 形参,其 ValidateSet 只认 http/https/auto/'',派生值 'http://' 会触发 MetadataError;用 $SchemePrefix)
    Write-Verbose "Scheme initial value: [$Scheme]."
    if ($Scheme -ne 'auto')
    {
        if ($Scheme)
        {
            $SchemePrefix = $Scheme + "://"
        }
        else
        {
            $SchemePrefix = ""
        }
    }
    else
    {
        if ($ReverseMode -eq 'base')
        {
            $SchemePrefix = "http://"
        }
        else
        {
            $SchemePrefix = ""
        }
    }
    Write-Verbose "Scheme prefix for proxy_pass: [$SchemePrefix]"
    # 先清空旧文件
    Write-Output "" > $RoutesMap 
    foreach ($item in $items)
    {
        # 检查ip是否合法
        if (!(Test-IsIPAddress -IP $item.ip))
        {
            Write-Error "Invalid ip address: $($item.ip)" -ErrorAction Stop
            # continue
        }
        $line = ".$($item.domain) ${SchemePrefix}$($item.ip);"
        $line | Tee-Object -Append -FilePath $RoutesMap 
    }
    Convert-CRLF -InputObject $RoutesMap -To LF -Replace
    $vps = Get-ServerList -Vps | Where-Object { $reverse -in $_.ips }
    # 计算远程vps的routes.maps.conf的路径
    if ($ReverseNginxConfDir)
    {
        Write-Verbose "Use $ReverseNginxConfDir specified by command line parameter."
    }
    else
    {
        $reverseNginxConfDir = $vps.nginx.prefix 
    }
    # 反代服务器上routes.map.conf的路径判断
    if ($ReverseMode -eq 'base')
    {

        $remoteRoutesMap = "$ReverseNginxConfDir/gateway/maps/routes.map.conf"
    }
    elseif ($ReverseMode -eq 'tenants')
    {
        if (!$AdminId)
        {
            throw "Please specify admin id for tenants mode!" 
        }
        $remoteRoutesMap = "$ReverseNginxConfDir/tenants/${AdminId}/routes.map"
    }
    Write-Host "Adding routes map to reverse server: $reverse on path:[$remoteRoutesMap]"
    # 删除所有会话前面可能残留的job(调试模式不启动任何 job,也不碰会话现有 job)
    if (-not $LocalDebug)
    {
        Get-Job | Remove-Job -Verbose
    }

    # 后台运行vps 的routes.map.conf更新合并任务.
    if ($LocalDebug)
    {
        Write-Host "[LocalDebug] 跳过:UpdateRoutesMap(scp $RoutesMap 到 ${reverse}:~/routes.map.conf + ssh 合并到 $remoteRoutesMap + nginx -t/reload)"
    }
    else
    {
        Start-ThreadJob -Name "UpdateRoutesMap" -ScriptBlock {
            param(
                $vps,
                $reverse,
                $RoutesMap,
                $remoteRoutesMap
            )
            # 将域名-ip映射表上传到远程vps(内容追加到配置文件末尾)
            ## 使用标准收入的情况下不能使用ssh的 -n
            # Get-Content -Raw $RoutesMap| ssh -T "$($vps.ssh.user)@$reverse"  -p $vps.ssh.port "sudo tee -a $remoteRoutesMap " 
            ## 更可靠的方式是使用编写合适的脚本,放在服务器上,调用其脚本不冗余且安全的将map文件并入到原map中.
            $vpsUser = $vps.ssh.user
            $vpsPort = $vps.ssh.port
            Write-Verbose "从配置文件中获取vps的登录用户名和端口号: [vpsUser=($vpsUser), vpsPort=($vpsPort)]" -Verbose
            # 容错处理
            if (!$vpsUser) { $vpsUser = "root" }
            if (!$vpsPort) { $vpsPort = "22" }
            Write-Verbose "本轮使用vps的登录用户名和端口号: [vpsUser=($vpsUser), vpsPort=($vpsPort)]" -Verbose
            # 上传map文件
            scp -P $vpsPort $RoutesMap "$vpsUser@${reverse}:~/routes.map.conf"
            if ($LASTEXITCODE -ne 0)
            {
                Write-Warning "[UpdateRoutesMap] SCP 传输文件失败！退出码: $LASTEXITCODE。将跳过后续的 Nginx 配置合并。"
                # return # 结束当前任务，不再执行后面的 ssh
            }
            # 将新map合并到原map中
            ssh -Tn "$vpsUser@${reverse}" -p $vpsPort (@"
    # 确保目标文件存在,否则创建空文件(建议在脚本中实现安全检查)
    bash ~/sh/nginx_conf/merge_routes_map.sh -a $remoteRoutesMap -b ~/routes.map.conf --add ;
    tail  $remoteRoutesMap |nl; 
    nginx -t && nginx -s reload 
"@| Convert-CRLF -To LF

            )

        } -ArgumentList $vps, $reverse, $RoutesMap, $remoteRoutesMap
    } # end else(非调试模式才起 UpdateRoutesMap job)

    # return "debuging"

    # 读取cf配置文件,确定要使用的cf账号(根据cf账号和密钥设置当前cf相关环境变量)
    # $config = Get-Content $CfConfig | ConvertFrom-Json
    # $account = $config."accounts"."$CfAccount"
    # Set-CFCredentials -ApiKey $account.cf_api_key -ApiEmail $account.cf_api_email
    Set-CFCredentials -CfConfig $CfConfig -Account $CfAccount
    Get-ChildItem env:cf*


    # START SERIAL (串行,各步骤内局部并行,如果线程过多导致api错误(429),尤其是cloudflare api,则考虑降低线程数或者减少任务中的网站域名数量,分批部署)
    if ($LocalDebug)
    {
        Write-Host "[LocalDebug] 跳过:Add-CFZoneDNSRecords(域名解析到 $reverse)"
        Write-Host "[LocalDebug] 跳过:Get-CFZoneNameServersTable(写 $ToTable)"
    }
    else
    {
        # 添加域名解析到cf(第一步执行)
        Add-CFZoneDNSRecords -AddRecordAtOnce -IP $reverse -Parallel:(!$Onebyone) -Domains $FromTable 
        # 从待部署域名列表更新spaceship域名的nameservers(cf添加后立即执行spaceship的nameservers更新)
        Get-CFZoneNameServersTable -FromTable $FromTable
    }
    # 更新spaceship的nameservers(后续的CFZoneActivation依赖于此域名DNS配置)
    # Update-SSNameServers -Config $SpaceshipConfig -Table $ToTable
    # END SERIAL

    # START JOBS
    if ($LocalDebug)
    {
        Write-Host "[LocalDebug] 跳过:CFZoneActivation(spaceship 更新 + CF 激活检查)"
        Write-Host "[LocalDebug] 跳过:CFZoneConfig(CF 解析/邮箱转发/代理保护)"
        Write-Host "[LocalDebug] 跳过:DeployBTSites(宝塔建空站)"
    }
    else
    {
        # 让cf立即检查域名的激活
        # Add-CFZoneCheckActivation -Account $CfAccount -ConfigPath $CfConfig -Table $FromTable
        Start-ThreadJob -Name "CFZoneActivation" -ScriptBlock {
            <# 
        实验性局部串行,此小节包含两个任务(需要串行)
        #>
            param (
                # part1
                $Account, $ConfigPath, $Table,
                # part2
                $SpaceshipConfig, $ToTable, $spaceshipScript
        
            )
            $OutputEncoding = [System.Text.Encoding]::UTF8
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            # part1
            Write-Host "[START TIME:$(Get-DateTime)]Update-SSNameServers..."
            Update-SSNameServers -Config $SpaceshipConfig -Table $ToTable -script $spaceshipScript
            Write-Host "[END TIME::$(Get-DateTime)]Update-SSNameServers done."
            # part2
            Write-Host "[START TIME:$(Get-DateTime)]CFZoneActivation..."
            Add-CFZoneCheckActivation `
                -Account $Account `
                -ConfigPath $ConfigPath `
                -Table $Table
            Write-Host "[END TIME::$(Get-DateTime)]CFZoneActivation done."
        } -ArgumentList $CfAccount, $CfConfig, $FromTable , $SpaceshipConfig, $ToTable , "$pys/spaceship_api/update_nameservers.py" -ThrottleLimit 5

        # 配置cf域名解析,邮箱转发和代理保护(位置1)
        # Add-CFZoneConfig -Account $CfAccount -CfConfig $CfConfig -Table $FromTable -Ip $reverse
        Start-ThreadJob -Name "CFZoneConfig" -ScriptBlock {  
            param ($Account, $CfConfig, $Table, $script, $Ip)
            $OutputEncoding = [System.Text.Encoding]::UTF8
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            Write-Host "[START TIME:$(Get-DateTime)]CFZoneConfig..."
            Add-CFZoneConfig `
                -Account $Account `
                -CfConfig $CfConfig `
                -Table $Table `
                -script $Script `
                -Ip $Ip
            Write-Host "[END TIME::$(Get-DateTime)]CFZoneConfig done."
        } -ArgumentList $CfAccount, $CfConfig, $FromTable, "$pys/cf_api/cloudflare_dns_tool.py", $reverse
    
        # 创建宝塔远程空站点创建
        # Deploy-BatchSiteBTOnline -Server $HostName -ServerConfig $ServerConfig -Table $FromTable -SitesHome $SitesHome 
        # 后台运行远程站点创建
        Start-ThreadJob -ScriptBlock { 
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $server = $using:server
            Write-Host "[START TIME:$(Get-DateTime)][$server]Deploying sites on BT online..."
            Deploy-BatchSiteBTOnline -Script "$using:pys/bt_api/create_sites.py" -Server $server -ServerConfig $using:ServerConfig -Table $using:FromTable -SitesHome $using:SitesHome 
            Write-Host "[END TIME::$(Get-DateTime)]Deploying sites on BT online done."
        } -Name "DeployBTSites"
    } # end else(非调试模式才起 CFZoneActivation/CFZoneConfig/DeployBTSites 三个 job)
    # return "debug..."
    # Receive-Job

    # 上传本批次域名列表到对应服务器上
    # Push-ByScp -Server $HostName -Path $FromTable -Destination $RemoteSiteTable
   
    if ($LocalDebug)
    {
        Write-Host "[LocalDebug] 跳过:job 等待/Receive-Job(无 job 启动)"
    }
    else
    {
        Write-Host "等待所有后台作业完成..."
        $jobs = Get-Job
        # 等待1~2秒在查看作业启动状态,看看各个任务的启动情况(这不会阻塞后台job的运行,可以放心等待)
        Start-Sleep 2
        Write-Host "$($jobs|Out-String)"

        $jobs | Receive-Job -Wait 
    }
    # END JOBS
    
    if ($LocalDebug)
    {
        # 调试小结:本地产物一次看清,不碰网络直接返回
        Write-Host "========== [LocalDebug] 本地逻辑执行完毕,以下操作均已跳过 =========="
        Write-Host "server=$server,DeployIP=$HostName,reverseIP=$reverse"
        Write-Host "remoteRoutesMap=$remoteRoutesMap"
        $mapLines = @(Get-Content -LiteralPath $RoutesMap)
        Write-Host "routes.map($RoutesMap):共 $($mapLines.Count) 行,预览前 5 行:"
        $mapLines | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
        Write-Host "跳过项:UpdateRoutesMap(scp/ssh)/Set-CFCredentials 除外见上/Add-CFZoneDNSRecords/Get-CFZoneNameServersTable/CFZoneActivation/CFZoneConfig/DeployBTSites/Update-NginxVhostOnHost/激活等待循环"
        Write-Host "======================================================================"
        return 'LocalDebugDone'
    }
    # 重启nginx 
    Update-NginxVhostOnHost -HostName $HostName -FromTable $FromTable
    # 等待环节
    Write-Warning "等待2到5分钟让cf激活域名保护(不保证成功,大多数情况下可以),后续检查是否全部激活,否则循环等待,每次$RetryGap 秒,最多等待$MaxRetryTimes 轮"
    if($WaitTimeBasic)
    {
        Write-Warning "基础等待时间$WaitTimeBasic 秒"
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
        $domainsInfo = Get-CFZoneInfoFromTable -Domains $inactiveDomains -Json | ConvertFrom-Json
        Start-SleepWithProgress $RetryGap
        $retryTimes--
    }
    # 配置cf域名解析,邮箱转发和代理保护(位置2,暂时使用位置1)
    # Add-CFZoneConfig
}
function Update-NginxVhostOnHost
{
    <# 
.SYNOPSIS
更新nginx配置(插入公共配置)
上传最近批次的网站域名表
调用相应脚本,维护指定服务器上的[建站日期表]
重启指定主机的Nginx服务配置

默认仅重载nginx配置
强制可以杀死nginx进程再启动nginx

.NOTES
强烈建议配置ssh免密登录


#>
    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [alias('Host', 'Server', 'Ip')]
        $HostName ,
        $User = 'root',
        [alias('Table')]$FromTable = "$Desktop/table.conf",
        # 网站域名表在服务器上的路径
        $RemoteSiteTable = '/www/site_table.conf',
        [switch]$Force

    )
    # 更新各个网站vhost的配置(宝塔nginx vhost配置文件路径)
    # 注意linux上的bash脚本片段的换行符风格为LF,windows平台编写的bash命令行片段这里需要额外处理.
    $LF = "`n"
    $cmds = @"
#START
bash /update_nginx_vhosts_conf.sh -d /www/server/panel/vhost/nginx --days 1 -M 1 
bash /www/sh/nginx_conf/update_nginx_vhosts_log_format.sh -d /www/server/panel/vhost/nginx 
bash /www/sh/update_user_ini.sh
python3 /www/sh/nginx_conf/maintain_nginx_vhosts.py maintain -d -k first
#END(basic parts)
"@+ $LF
    $pushSiteTable = {
        # 使用 $using: 修饰符访问父作用域的变量
        param(
            [string]$HostName,
            [string]$Path,
            [string]$Destination
        )
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        Write-Host "[START TIME:$(Get-DateTime)]Pushing site table to server..."
        Push-ByScp -Server $HostName -Path $Path -Destination $Destination -Verbose
        Write-Host "[END TIME::$(Get-DateTime)]Pushing site table to server done."
    }
    $PushSiteTableJob = Start-ThreadJob -ScriptBlock $pushSiteTable -ArgumentList $HostName, $FromTable, $RemoteSiteTable -Name "PushSiteTableJob"
    # 这里使用后台作业意义不是很大,但是后续可能变更到其他命令中故而保留此写法(需要等待上传完毕再执行shell调用.)
    Receive-Job -Job $PushSiteTableJob -Wait -Verbose
    # return "debug"
    # 维护服务器上的建站日期表(可以丢到后台运行)
    # $maintain = "python3 /www/sh/nginx_conf/maintain_nginx_vhosts.py maintain -d -k first"
    # Write-Verbose "维护域名列表[  $maintain ]"
    # ssh root@$HostName $maintain
    if ($Force)
    {
        # ssh $User@$HostName " pkill -9 nginx ; nginx "
        $cmds += "pkill -9 nginx  " + $LF
    }
    $cmds += "nginx -t && nginx -s reload " + $LF
    # 方案1
    # ssh $User@$HostName ($cmds -replace "`r", "")
    # 方案2
    $cmdsLF = $cmds | Convert-CRLF -To LF 
    # 添加结尾标记,防止pwsh管道符传递命令行片段末尾追加的\r\n(CRLF)造成干扰
    $cmdsLF = $cmdsLF + "#END(all)"
    Write-Host "执行命令行: [$cmdsLF]"
    $cmdsLF | ssh $User@$HostName "bash"
    # $cmdsLF | ssh $User@$HostName "cat -A"

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
        $Skip = 1,
        # 仅列出VPS服务器
        [switch]$VpsOnly
    )
    $config = Get-Content $Path | ConvertFrom-Json
    if($VpsOnly)
    {
        $vpsSet = $config.vps.vps_set.PSObject.Properties.Value
        return $vpsSet
    }
    else
    {

        # Write-Output $config
        $servers = $config.servers.PSObject.Properties.Value
        # Write-Output $servers
        if($Skip -eq 1)
        {
            Write-Warning "Skipping the first $Skip server."
        }
    }
    return $servers[$Skip..($servers.Length - 1)]
    
}

function Update-WpAllPluginPackagesOnServers
{
    <# 
    更新所有服务器上的所有wp插件包(仅上传并解压到公共目录(/www/下),并不执行额外执行覆盖到网站插件目录的操作)
    如果网站是用符号链接引入插件的,则相应的网站插件相当于被自动更新(替换)
    #>
    param()
    Write-Host "Only update plugins packages..."
    Get-ChildItem $wp_plugins -Directory -Exclude archived | ForEach-Object {
        Write-Host "Processing [$_]"
        Update-WpPluginsDFOnServers -PluginPath $_ -JustUpload
    }

}

function Update-WpFunctionsphpOnServer
{
    <# 
    .SYNOPSIS
    更新指定服务器上的Wordpress函数文件
    .PARAMETER Path
    本地的functions.php文件路径,默认值为"$wp_plugins/functions.php"

    #>
    [cmdletbinding()]
    param (
        $Server,
        $Path = "$wp_plugins/functions.php",
        $BashScript = '/www/sh/wp-functions-update/update_wp_functions.sh',
        # 注意,Target目录在远程服务器上应该存在,否则scp上传会失败(scp不会创建缺失的中间路径目录),-r选在跟也不会帮助你创建缺失起始目录
        $RemoteDirectory = "/www",
        $RemoteName = "",
        # 需要检索functions.php替换路径的项目目录,尤其是多磁盘的情况
        $WorkingDirectory = "/www/wwwroot,/wwwdata/wwwroot",
        $ServerConfig = $server_config,
        [ValidateSet('copy', 'symlink')]
        $InstallMode = 'copy',
        # 仅更新文件不立即部署(可以供定时任务搭配使用)
        [switch]$NoDeploy

    )
    if($RemoteName -eq "")
    {
        $RemoteName = Get-Item $Path | Select-Object -ExpandProperty Name
    }
    # 管道流向外部程序的数据设置为UTF-8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # 设置控制台输出编码为 UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    Write-Host "Updating $RemoteName to $Server ..."
    $RemoteDirectory = $RemoteDirectory
    Write-Host "Uploading $RemoteName to $Server ..."
    $remoteFunctionsFile = "$RemoteDirectory/$RemoteName"
    scp -r $Path root@"$Server":$remoteFunctionsFile

    # 调用服务器上的部署执行脚本
    if ($NoDeploy)
    {
        Write-Host "Skipping deploying..."
        return
    }
    else
    {
        ssh -Tn root@$Server "bash $BashScript --src $remoteFunctionsFile --workdir $WorkingDirectory --install-mode $InstallMode"
    }
        
        

    # Write-Output "检查更新状态:服务器上的版本(日期)是否正确更新(正确部署依赖于部署脚本):"

    # ssh -Tn root@$Server "echo -n `"[`$(hostname)]:`" ; stat -c %y $RemoteDirectory/$RemoteName"
    # Write-Output "检查服务器上的部署脚本是否存在."
    # ssh -Tn root@$Server "if [ -f $BashScript ]; then echo '[$(hostname)]:存在'; else echo '[$(hostname)]:不存在'; fi"
  
    Write-Output "检查更新状态:服务器上的版本(日期)是否正确更新(正确部署依赖于部署脚本):"
    ssh -Tn root@$Server "echo -n `"[`$(hostname)]:`"  ;printf '%s' `"[`$(stat -c %y $remoteFunctionsFile)]`"; if [ -f $BashScript ]; then echo '$BashScript 存在'; else echo '[ERROR]:$BashScript 不存在'; fi"

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
        # 要推送上去的脚本文件(functions文件)
        $Path = "$wp_plugins/functions.php",
        $BashScript = '/www/sh/wp-functions-update/update_wp_functions.sh',
        # 注意,Target目录在远程服务器上应该存在,否则scp上传会失败(scp不会创建缺失的中间路径目录),-r选在跟也不会帮助你创建缺失起始目录
        $RemoteDirectory = "/www",
        $RemoteName = "",
        $WorkingDirectory = "/www/wwwroot,/wwwdata/wwwroot",
        $ServerConfig = $server_config,
        [ValidateSet('copy', 'symlink')]
        $InstallMode = 'copy',
        # 仅更新文件不立即部署(可以供定时任务搭配使用)
        [switch]
        $NoDeploy,
        $Threads = 10
    )
    $servers = Get-ServerList -Path $ServerConfig
    if($RemoteName -eq "")
    {
        $RemoteName = Get-Item $Path | Select-Object -ExpandProperty Name
    }
    # 管道流向外部程序的数据设置为UTF-8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # 设置控制台输出编码为 UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $servers.ip | ForEach-Object -Parallel {
        $RemoteDirectory = $using:RemoteDirectory
        $WorkingDirectory = $using:WorkingDirectory
        $RemoteName = $using:RemoteName
        $NoDeploy = $using:NoDeploy
        $BashScript = $using:BashScript
        $InstallMode = $using:InstallMode
        
        $remoteFunctionsFile = "$RemoteDirectory/$RemoteName"
        
        # Push-ByScp -Server $_ -SourcePath $Path -TargetPath $Target  -Verbose
        
        Write-Host "Updating $RemoteName to ${_}:$remoteFunctionsFile ..." 
        scp -r $using:Path root@"$_":$remoteFunctionsFile # -v 详细输出

        if ($NoDeploy)
        {
            Write-Host "Skipping deploying on $_ ..."
            return
        }
        else
        {

            ssh -Tn root@$_ "bash $BashScript --src $remoteFunctionsFile --workdir $WorkingDirectory --install-mode $InstallMode"
        }
        
        
    } -ThrottleLimit $Threads

    Write-Output "检查更新状态:服务器上的版本(日期)是否正确更新(正确部署依赖于部署脚本):"
    $servers.ip | ForEach-Object -Parallel { 
        $RemoteDirectory = $using:RemoteDirectory
        $RemoteName = $using:RemoteName
        $NoDeploy = $using:NoDeploy
        $BashScript = $using:BashScript
        $remoteFunctionsFile = "$RemoteDirectory/$RemoteName"
        
        # ssh -Tn root@$_ "echo -n `"[`$(hostname)]:`" ; stat -c %y $RemoteDirectory/$RemoteName"
        ssh -Tn root@$_ "echo -n `"[`$(hostname)]:`" ; printf '%s' `"[`$(stat -c %y $remoteFunctionsFile)]`"; if [ -f $BashScript ]; then echo '$BashScript 存在'; else echo '[ERROR]:$BashScript 不存在'; fi"

    } -ThrottleLimit $Threads
    
}
function update-WpSqlOnServers
{
    <# 
    .SYNOPSIS
    批量更新服务器上的Wordpress数据库
    .PARAMETER Path
    数据库文件路径
    .PARAMETER Target
    上传文件到目标目录,默认值为"/www/"
    .PARAMETER ServerConfig
    服务器配置文件路径,默认值为"$server_config"
    #>
    [cmdletbinding()]
    param (
        $Path = "$Desktop/wp_batch.sql",
        $BashScript = '/www/sh/mysql/mysql_db_batch_runner.sh',
        # 注意,Target目录在远程服务器上应该存在,否则scp上传会失败(scp不会创建缺失的 intermediate paths),-r选在跟也不会帮助你创建缺失起始目录
        $RemoteDirectory = "/www",
        $ServerConfig = $server_config,
        $Threads = 10,
        $ThreadsOnSqlUpdate = 10
    
    )
    $servers = Get-ServerList -Path $ServerConfig
    $filename = Split-Path $Path -Leaf
    # 管道流向外部程序的数据设置为UTF-8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # 设置控制台输出编码为 UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $servers.ip | ForEach-Object -Parallel {
        Write-Host "Running sql to $_"
        # Push-ByScp -Server $_ -SourcePath $Path -TargetPath $Target  -Verbose
        $RemoteDirectory = $using:RemoteDirectory
        # scp 推送文件到服务器
        scp -r $using:Path root@"$_":$RemoteDirectory
        $remoteSqlFile = "$RemoteDirectory/$using:filename"
        # ssh远程调用
        ssh -Tn root@$_ "bash $using:BashScript -f $remoteSqlFile -j $using:ThreadsOnSqlUpdate  "
    } -ThrottleLimit $Threads
}

function Get-WpOrdersByEmailOnServers
{
    <# 
    根据订单邮箱到服务器中查询相关订单
    .PARAMETER Input
    输入被查询的邮箱列表,可以指定文件或直接输入邮箱字符串(多行字符串)
    代码会判断输入是否为文件路径,如果是文件路径则读取文件内容,否则直接将收入保存到文件中,然后统一按照解析文件的路径处理.
    注意,此操作会将emails.txt上传到相关服务器中.
    #>
    param (
        [Alias('Email', 'Path')]$Inputs = "$desktop/emails.txt",
        $ServerConfig = $server_config,
        # 指定服务器IP,多个用逗号隔开
        $ServerIPNameWhiteList = @(),
        [switch]$OnlyGetResult,
        $WorkingDirectory = '/www/',
        $scriptPath = "/www/sh/check_order_email.sh",
        $foundResultFileName = "found_orders.csv",
        $log = "$desktop/orders.log"
        
    )
    $servers = Get-ServerList -Path $ServerConfig
    $jobs = @()
    if(-not $OnlyGetResult)
    {
        $Path = "$desktop/emails.txt"
        if(Test-Path $Inputs)
        {
            Write-Verbose "Input source is a file,nothing more to do."
        }
        else
        {
            Write-Warning "Input source is not a file,write-output to file:[$Path]"
            $Inputs | Set-Content $Path 
        }
        foreach ($server in $servers)
        {
            $ip = $server.ip
            if ( $ServerIPNameWhiteList -and $ip -notin $ServerIPNameWhiteList)
            {
                Write-Warning "Skip server:[$ip],which is not in the white list:[$ServerIPNameWhiteList]"
                continue
            }
            Write-Host "Getting orders from $($ip)"
            $fileName = Split-Path $Path -Leaf
            $fileOnServer = "$WorkingDirectory/$fileName"
            # Get-WpOrdersByEmail -Email $Path -Server $server
            $mysql = $server.mysql

            $user = $mysql.root_localhost
            $password = $mysql.root_password
            # $port = $mysql.port
        
            Write-Host "Check orders on $ip with mysql user:$user,mysql password:$password"
            Write-Host "Email file: $fileOnServer on server"

            # scp -r $Path root@"$ip":$WorkingDirectory
            $jobs += Start-ThreadJob -ScriptBlock {
                param($WorkingDirectory, $Path, $ip, $fileOnServer, $scriptPath, $user, $password, $log, $foundResultFileName)
                # 强制让当前 PowerShell 线程以 UTF-8 处理输入输出,否则容易出现乱码(尤其是非英文字符)
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                Write-Output "START TIME: [$(Get-DateTime)] on $ip"
                Write-Host "start push file to server $ip..." 
                scp -r $Path root@"$ip":$WorkingDirectory
                Write-Host "start query orders on server $ip..." 
                # 使用ssh 的-n选项让后台作业能够顺利退出(否则可能需要手动输入输入回车回到前台.)
                # 相关选项:-n关闭 STDIN,-T禁止分配伪终端（TTY）
                ssh -n -T root@$ip "cat -n $fileOnServer && bash $scriptPath -f $fileOnServer -o /www/$foundResultFileName -u $user -p '$password'" 
                Write-Host "END TIME: $(Get-DateTime) on $ip"
            } -ArgumentList $WorkingDirectory, $Path, $ip, $fileOnServer, $scriptPath, $user, $password, $log, $foundResultFileName

        }
        Write-Host "Waiting for jobs to complete..."
        Start-Sleep 2
        $jobs | Get-Job
        Write-Host "checking logs..." 
        # Get-Content $log -wait &
        $jobs | Receive-Job -Wait | Tee-Object $log
        # while ($jobs.Status -contains 'Running')
        # {
        #     $jobs | Receive-Job | Tee-Object $log -Append
        #     Start-Sleep -Milliseconds 500
        # }
        # foreach ($job in $jobs)
        # {
        #     $job | Wait-Job | Receive-Job -Wait -Verbose
        # }
        # $jobs | Remove-Job 
    }
    Write-Host "--------[Getting results...]---------"
    foreach ($server in $servers.ip)
    {
        # if ( $ServerIPNameWhiteList -and $ip -notin $ServerIPNameWhiteList)
        # {
        #     Write-Warning "Skip server:[$ip],which is not in the white list:[$ServerIPNameWhiteList]"
        #     continue
        # }
        $jobs += Start-ThreadJob -script { ssh root@$using:server "cat $using:WorkingDirectory/$using:foundResultFileName" }
    }
    # $localRes = "$desktop/found_orders_all_servers@$(Get-DateTimeNumber).csv"
    $localRes = "$desktop/found_orders_all_servers.csv"
    $uniqueRes = "$desktop/found_orders_unique_all_servers.csv"
    $jobs | Receive-Job -Wait | Tee-Object -FilePath $localRes
    # 创建临时文件
    $tmp = New-TemporaryFile
    # 将csv中重复的行删除
    Get-Content $localRes | Sort-Object -Unique -Descending | Set-Content -Path $tmp -Encoding utf8
    Move-Item -Path $tmp -Destination $localRes -Force -Verbose
    # 清理临时文件
    if(Test-Path $tmp)
    {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }

    Write-Verbose "执行以下命令去除email重复的行" -Verbose
    Import-Csv $localRes | Sort-Object -Property email -Unique | Export-Csv -Path $uniqueRes -NoTypeInformation -Encoding utf8
    Write-Host "open result file ..."
    Start-Process $uniqueRes
}
function Update-Servers
{
    <# 
    .SYNOPSIS
    批量运行:在服务器上执行某个命令行,例如运行服务器上的某个脚本(bash 命令行)
    默认执行代码更新操作;
    
    采用线程池的方式对所有服务器执行相同的命令行
    .NOTES
    使用ssh -n -T root@$server "command line"的方式执行命令行
    .PARAMETER ServerConfig
    服务器配置文件路径
    .PARAMETER Cmd
    要执行的命令行
    .PARAMETER Threads
    线程数
    .PARAMETER WorkingDirectory
    工作目录
    .EXAMPLE
    # 重载nginx配置
    Update-Servers -Cmd 'nginx -t && nginx -s reload ' -Verbose

    #>
    [CmdletBinding()]
    param (
        $ServerConfig = $server_config,
        $WorkingDirectory = '/www/',
        [Alias('Script')]
        $Cmd = "bash /update_repos.sh -c",
        $Threads = 5
    )
    $servers = Get-ServerList -Path $ServerConfig
    $jobs = @()
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # 设置控制台输出编码为 UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    foreach ($server in $servers.ip)
    {
        $jobs += Start-ThreadJob -script { ssh -nT root@$using:server "cd $using:WorkingDirectory &&  $using:cmd" } -ThrottleLimit $Threads
    }
    Start-Sleep 1
    # $jobs | Get-Job
    $jobs | Receive-Job -Wait
    
}
function Push-ServerItem
{
    <# 
    .SYNOPSIS
    上传同一文件/目录到多个服务器的相同目录下.
    #>
    [CmdletBinding()]
    param (
        $Path,
        $Destination = '/www',
        $ServerConfig = $server_config,
        $Threads = 5
    )
    $servers = Get-ServerList -Path $ServerConfig
    $servers | ForEach-Object -Parallel { 
        $cmd = "scp -r '$using:Path' root@$($_.ip):$using:Destination"
        Write-Host "Executing: $cmd" 
        $cmd | Invoke-Expression
        Write-Host "Finished: on server $($_.ip)"
    } -ThrottleLimit $Threads
    
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

        # 服务器IP地址
        [Alias('hst', 'Ip')]$server ,               
        # 服务器用户名
        $Username = "root"        ,      
        # 服务器密码（不推荐明文存储,配置ssh密钥登录更安全）
        # $password = ""              
        
        # 本地插件目录路径🎈
        [parameter(ParameterSetName = 'Path')]
        [Alias('Path')]
        $PluginPath ,  
        # 仅上传插件文件夹到服务器指定目录并解压,不执行其他操作(例如安装等)
        [parameter(ParameterSetName = 'Path')]
        [switch]$JustUpload, 
        # 插件名称(服务器上插件路径的最后一级目录名)
        [parameter(ParameterSetName = 'RemoveByName')]
        [Alias('Name')]
        $PluginName,
        
        $RemoteDirectory = "/www"       , # 服务器目标目录
        # 工作目录,可以指定多个(通过逗号分隔,最终用引号包裹),尤其对于多个硬盘的服务器比较有用
        $WorkingDirectory = "/www/wwwroot,/wwwdata/wwwroot",
        $BashScript = "/www/sh/wp-plugin-update/update_wp_plugin.sh",
        $WhiteList = "",
        $BlackList = "",
        [ValidateSet('symlink', 'copy')]
        $InstallMode = "symlink",
        # 列表模式(默认自动,仅更新已安装过的插件,manual:指定网站名单,full:所有网站都安装(更新)插件)
        [validateSet('auto', 'manual', 'full')]
        $ListMode = "auto",
        # 移除插件而非安装(更新)插件
        [parameter(ParameterSetName = 'RemoveByName')]
        [switch]$RemovePlugin,
        [switch]$Dry
    )
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # 设置控制台输出编码为 UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    # 计算要操作的网站名单(白名单/黑名单)
    function Get-DomainListParam
    {
        <# 
        .SYNOPSIS
        内部专用函数.
        黑白名单文件参数构造,包含目标网站名单上传操作
        #>
        [CmdletBinding()]
        param(
            $DomainList,
            [ValidateSet('WhiteList', 'BlackList')]$ListType
        )
        Write-Verbose "Using $ListType ...(only update plugins of sites(domain) in $ListType)"
        Write-Verbose "Uploading [$DomainList] file to server[$server]..." -Verbose
        # 上传网站名单文件(为例兼容性,这里使用scp命令而不用包装命令push-byscp)
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
    
    if($WhiteList -and $BlackList)
    {
        Write-Error "WhiteList and BlackList can not be used together!"
        return $False
    }
    elseif($WhiteList)
    {
        Write-Verbose "获取白名单参数,并上传白名单文件..."
        $domainListParam = Get-DomainListParam $WhiteList -ListType "WhiteList"
    }
    elseif($BlackList)
    {
        Write-Verbose "获取黑名单参数,并上传黑名单文件..."
        $domainListParam = Get-DomainListParam $BlackList -ListType "BlackList"
    }
    
    # 构造bash脚本命令行(插件安装/更新)
    $basicCmd = " ssh -Tn $username@$server bash $bashScript --workdir $workingDirectory --list-mode $ListMode "
    $dryRunParam = if($Dry) { "--dry-run" }else { "" }
    # 计算插件参数
    if($PSCmdlet.ParameterSetName -eq 'Path')
    {
        $plugin_dir_name = (Split-Path $PluginPath -LeafBase) # 计算插件名称,将作为插件压缩包的名称(如果已经是压缩包,则需要压缩包名称和被压缩目录名一致)
        # 计算插件目录压缩成zip后的文件路径
        $zipFile = "$wp_plugins/$plugin_dir_name.zip"
        $remoteZipFile = "$remoteDirectory/$plugin_dir_name.zip"
        $remotePluginDir = "$remoteDirectory/$plugin_dir_name"  # 服务器目标插件目录🎈

        # 将插件文件夹统一处理为zip包(如果输入路径已经是压缩包文件,则跳过压缩处理)
        if(Test-Path $PluginPath -PathType Container)
        {
            Write-Verbose "Remove existing zip file if exists: [$zipFile]..." 
            Remove-Item $zipFile -ErrorAction SilentlyContinue -Verbose
            Compress-Archive -Path $PluginPath -DestinationPath $zipFile
            # Write-Warning "Plugin name: [$plugin_dir_name],please ensure it is correct then continue. " -WarningAction Inquire 
        }
        else
        {
            $zipFile = $PluginPath
            Write-Verbose "Plugin path is already a file, using it directly: [$zipFile]..."
        }

        # 上传插件压缩包到服务器
        Write-Verbose "Uploading file [$zipFile] to server[$server]..." -Verbose
        scp -r $zipFile $username@${server}:"$remoteDirectory" 
        
        Write-Verbose "expanding zip file to [$remotePluginDir]..."
        # 覆盖式解压(-o选项),-d 指定解压目录(extract directory)
        ssh -Tn $username@$server "unzip -o $remoteZipFile -d $remoteDirectory"
        if($JustUpload)
        {
            return $True
        }
        
        Write-Verbose "Executing updating script...(this need several seconds, please wait...)" -Verbose
        # 构造替换脚本
        $cmd = " $basicCmd --source $remotePluginDir $domainListParam $dryRunParam --install-mode $InstallMode ;" 
    }
    elseif($PSCmdlet.ParameterSetName -eq 'RemoveByName' -and $RemovePlugin)
    {
        # bash update_wp_plugin.sh --remove mallpay --whitelist whitelist.conf
        $cmd = " $basicCmd --remove $PluginName $domainListParam  $dryRunParam " 
    }
    
    Write-Verbose "Executing command: $cmd" -Verbose
    Start-Sleep 2
    if(!$JustUpload)
    {
        $cmd | Invoke-Expression
        ssh -Tn $username@$server "bash /www/sh/update_user_ini.sh "
    }
    Write-Verbose "Done." -Verbose
    
}
function Update-WpPluginsDFOnServers
{
    <# 
    .SYNOPSIS
    批量更新服务器上的Wordpress插件目录
    读取配置文件中的服务器列表,然后逐个服务器执行相同的处理
    .EXAMPLE
    安装插件
    Update-WpPluginsDFOnServers -PluginPath "$wp_plugins/mallpay"  -WhiteList "whitelist.conf" 
    .EXAMPLE
    删除插件
    Update-WpPluginsDFOnServers -PluginName "wp-linkpayment-v2" -RemovePlugin 
    #>
    param(
        # 本地插件目录路径🎈
        [parameter(ParameterSetName = 'Path')]
        [Alias('Path')]
        $PluginPath ,
        [parameter(ParameterSetName = 'Path')]
        [switch]$JustUpload,
        $WorkingDirectory = "/www/wwwroot,/wwwdata/wwwroot",
        $RemoteDirectory = "/www",# 上传到服务器的指定目录下
        # 插件名称(服务器上插件路径的最后一级目录名)
        [parameter(ParameterSetName = 'Name')]
        $PluginName,
        # 插件安装模式
        [ValidateSet('symlink', 'copy')]
        $InstallMode = "symlink",
        # 获取网站列表的方式(默认自动,仅更新已安装过的插件,manual:指定网站名单,full:所有网站都安装(更新)插件)
        [validateSet('auto', 'manual', 'full')]
        $ListMode = "auto",
        # ListMode = "manual"情况下,指定名单文件才有效
        $WhiteList = "",
        $BlackList = "",
        # 删除插件
        [parameter(ParameterSetName = 'Name')]
        [switch]$RemovePlugin,
        [switch]$Dry,
        $ServerConfig = $server_config,
        $Threads = 10
    )
    $OutputEncoding = [System.Text.Encoding]::UTF8
    # 设置控制台输出编码为 UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Write-Warning "[Threads]: $Threads(线程池worker数,每批次最多操作数量有限,如果有更多服务器,将在下一批次中处理,或者调高线程数)"
    if ($BlackList -or $WhiteList)
    {
        Write-Host "Using ListMode: manual (BlackList or WhiteList used. ListMode auto set to manual.) $ListMode -> manual"

        $ListMode = "manual"
    }
    if($WhiteList -and $BlackList)
    {
        Write-Error "WhiteList and BlackList can not be used together!"
    }
    elseif($WhiteList)
    {
        Write-Verbose "Using WhiteList...(only update plugins of sites(domain) in WhiteList)"
        # 白名单文件可能有多个(用户可以指定多个名单文件,数组),将他们合并到一个文件中方便处理
        if (@($WhiteList).Count -gt 1)
        {
            Write-Verbose "There are more than one WhiteList, merging them..."
            $mergeFile = "$desktop/WhiteList-$(Get-DateTimeNumber -Format "yyyyMMddHH" ).txt"
            Get-Content $WhiteList -Raw | Out-File $mergeFile -Verbose
            # 更新白名单文件
            $WhiteList = $mergeFile
        }
    }
    elseif($BlackList)
    {
        # 和白名单类似的处理手法
        Write-Verbose "Using BlackList...(skip updating plugins of sites(domain) in BlackList)"
        if (@($BlackList).Count -gt 1)
        {
            Write-Verbose "There are more than one BlackList, merging them..."
            $mergeFile = "$desktop/BlackList-$(Get-DateTimeNumber -Format "yyyyMMddHH" ).txt"
            Get-Content $BlackList -Raw | Out-File $mergeFile -Verbose
            # 更新黑名单文件
            $BlackList = "$mergeFile"
        }
 
    }

    $servers = Get-ServerList -Path $ServerConfig
    # Write-Host "servers:$servers"
    # return $servers
    $currentSet = $PSCmdlet.ParameterSetName
    if($currentSet -eq 'Path')
    {
        $plugin_dir_name = (Split-Path $PluginPath -LeafBase) # 计算插件名称,将作为插件压缩包的名称(如果已经是压缩包,则需要压缩包名称和被压缩目录名一致)
        # 计算插件目录压缩成zip后的文件路径
        $zipFile = "$wp_plugins/$plugin_dir_name.zip"
        
        # 将插件文件夹统一处理为zip包(如果输入路径已经是压缩包文件,则跳过压缩处理)
        if(Test-Path $PluginPath -PathType Container)
        {
            Write-Verbose "Remove existing zip file if exists: [$zipFile]..." 
            Remove-Item $zipFile -ErrorAction SilentlyContinue -Verbose
            Compress-Archive -Path $PluginPath -DestinationPath $zipFile
            # Write-Warning "Plugin name: [$plugin_dir_name],please ensure it is correct then continue. " -WarningAction Inquire 
            $PluginPath = $zipFile
        }
    }
    # $servers.ip | ForEach-Object -Parallel { #不支持ArgumentList
    $jobs = @()
    foreach ($server in $servers.ip)
    { 
    
        $jobs += Start-ThreadJob {
            param(
                $server,
                $currentSet,
                $WorkingDirectory,
                $RemoteDirectory,
                $PluginPath,
                $WhiteList,
                $BlackList,
                $InstallMode,
                $ListMode,
                $RemovePlugin,
                $PluginName,
                $JustUpload,
                $Dry
            )
            if($currentSet -eq 'Path')
            {
            
                Write-Host "Updating plugins to $server"
                # params=@ {
                #     Server=$server
                #     WorkingDirectory=$WorkingDirectory
                #     PluginPath=$PluginPath
                #     InstallMode=$InstallMode
                #     JustUpload=$JustUpload
                # }
                Update-WpPluginsDFOnServer -server $server -WorkingDirectory $workingDirectory -RemoteDirectory $RemoteDirectory -ListMode $ListMode -PluginPath $PluginPath -InstallMode $InstallMode -JustUpload:$JustUpload -WhiteList $WhiteList -BlackList $BlackList -Dry:$Dry
            }
            elseif($currentSet -eq 'Name' -and $RemovePlugin)
            {
                Write-Host "remove plugins[$PluginName] in $server"
                Update-WpPluginsDFOnServer -server $server -WorkingDirectory $workingDirectory -RemoteDirectory $RemoteDirectory -ListMode $ListMode -PluginName $PluginName -RemovePlugin -WhiteList $WhiteList -BlackList $BlackList -Dry:$Dry
            } 
        } -ArgumentList $server, $currentSet, $WorkingDirectory, $RemoteDirectory, $PluginPath, $WhiteList, $BlackList, $InstallMode, $ListMode, $RemovePlugin, $PluginName, $JustUpload , $Dry -ThrottleLimit $Threads
    } 
    # Start-Sleep 1
    $jobs | Receive-Job -Wait
    if($PluginPath)
    {

        # 计算插件名:
        $PluginName = Split-Path -Leaf $PluginPath # 例如wp-card.zip
        Write-Output "检查更新状态:服务器上的版本(日期)都正确更新:"
        $servers.ip | ForEach-Object -Parallel { 
            ssh -Tn root@$_ "echo -n `"[`$(hostname)]:`" ; stat -c %y $using:RemoteDirectory/$using:PluginName"
        } -ThrottleLimit $Threads
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

function ConvertTo-LinuxTextFile
{
    <#
    .SYNOPSIS
    把文本文件规范化为 Linux 约定：UTF-8 无 BOM、LF 换行、结尾有换行符。

    .DESCRIPTION
    读取时按 BOM 识别 UTF-8 与 UTF-16，没有 BOM 时按 UTF-8 严格解码；写入固定为 UTF-8 无 BOM。
    CRLF 与单独的 CR 都转换为 LF；非空文件缺少结尾换行时补一个，空文件保持为空。
    供 Push-FileToServers 的 -Linuxify 使用，也可单独调用处理待上传的文本文件。

    .PARAMETER Path
    源文件路径，支持相对路径，按当前 PowerShell 位置解析。

    .PARAMETER Destination
    规范化结果的输出路径，支持相对路径；允许与 -Path 相同，此时为原地规范化。

    .EXAMPLE
    ConvertTo-LinuxTextFile -Path ./update-cron.cron -Destination ./out/update-cron

    把本地模板规范化到另一个文件，原文件保持不变。

    .EXAMPLE
    ConvertTo-LinuxTextFile -Path ./update_wp_functions.sh -Destination ./update_wp_functions.sh

    原地规范化；覆盖原文件前应先提交到版本库或另行备份。

    .EXAMPLE
    $tmp = Join-Path $env:TEMP 'probe.txt'
    ConvertTo-LinuxTextFile -Path ./crlf.txt -Destination $tmp
    [System.IO.File]::ReadAllBytes($tmp)[-1]

    检查结果末字节，应为 10（LF）。

    .INPUTS
    None.

    .OUTPUTS
    None. 本命令不向成功流输出对象，结果只体现在目标文件上。

    .NOTES
    GBK/ANSI 编码的文件无法按 UTF-8 解码，命令会报错并提示转换方式。
    不要对二进制文件使用本命令；内容包含 NUL 字节时会直接报错。
    文件已符合规范时不会改变字节内容，可重复执行。

    .LINK
    Push-FileToServers
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,
        [Parameter(Mandatory, Position = 1)]
        [string]$Destination
    )

    $sourcePath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $targetPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)

    $targetDirectory = Split-Path -Parent $targetPath
    if ($targetDirectory -and -not (Test-Path -LiteralPath $targetDirectory))
    {
        throw "目标目录不存在: $targetDirectory；请先创建该目录，或改用已存在的路径。"
    }

    $bytes = [System.IO.File]::ReadAllBytes($sourcePath)
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    {
        $offset = 3
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)
    {
        $offset = 2
        $encoding = New-Object System.Text.UnicodeEncoding($false, $false, $true)
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF)
    {
        $offset = 2
        $encoding = New-Object System.Text.UnicodeEncoding($true, $false, $true)
    }
    else
    {
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    }

    try
    {
        $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch
    {
        throw "无法解码 $sourcePath：内容不是有效的 UTF-8 或 UTF-16 文本。若文件是 GBK/ANSI 编码，请先另存为 UTF-8，或执行 iconv -f GBK -t UTF-8 后再试。"
    }

    if ($text.IndexOf([char]0) -ge 0)
    {
        throw "无法处理 $sourcePath：内容包含 NUL 字节，看起来是二进制文件。"
    }

    $text = $text -replace "`r`n", "`n" -replace "`r", "`n"
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n"))
    {
        $text += "`n"
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($targetPath, $text, $utf8NoBom)
}

function Push-FileToServers
{
    <#
    .SYNOPSIS
    把同一个本地文件批量推送到多台服务器的同一路径，可选按 Linux 文本规范处理。

    .DESCRIPTION
    前置条件：已为目标机配置 root 免密登录；目标目录存在，或加 -CreateDirectory。
    执行者：当前会话通过 scp 上传、ssh 落地，按 -ThrottleLimit 并发处理多台机器。
    善后：无需额外操作；重复执行时，内容与权限已一致的机器直接跳过。

    每台目标机固定两次连接：一次 scp 上传到 /tmp，一次 ssh 完成比对、备份、原子替换与写后校验。
    远端命令在同一个会话内先比对 SHA-256 与权限，一致则直接跳过并清理临时文件，避免重复写入。
    命令以 LF 下发、只用单引号与 POSIX 语法，目标机登录 shell 为 bash、zsh 或 sh 都能执行。
    执行过程中直接向控制台输出进度：先打印目标数量与并发度，每台开始时输出一行，完成时输出状态、权限与耗时，最后输出汇总行。
    每行都以本地时间 `yyyy-MM-dd HH:mm:ss` 开头，便于事后与目标机日志对齐。
    进度写主机流而不是成功流，结果对象照常返回，可继续用管道处理。

    并发按 -ThrottleLimit 从队列取目标机启动作业：优先用 ThreadJob（PowerShell 7 自带，5.1 需另装 ThreadJob 模块），
    缺装时退回 Start-Job 进程级作业，两条路径都可在 5.1 与 7 上并发；-ThrottleLimit 1 时不建作业，直接顺序调用。

    .PARAMETER Path
    本地文件路径。

    .PARAMETER RemotePath
    目标机上的完整路径，例如 /etc/cron.d/update-cron。

    .PARAMETER Server
    目标机列表，元素可以是 IP、主机名或 user@host；不带用户名的元素按 root 处理。省略时读取 Get-ServerList 的 ip 字段。

    .PARAMETER ServerConfig
    服务器配置文件路径，仅在省略 -Server 时使用。

    .PARAMETER Skip
    读取服务器清单时跳过的开头条目数，默认 1，与 Update-Servers 的默认行为一致；显式传入 -Server 时本参数无效。

    .PARAMETER ThrottleLimit
    同时处理的目标机数量，默认 10，取值范围 1 到 64；设为 1 时按顺序执行。

    .PARAMETER Linuxify
    按 Linux 文本文件处理：去掉 UTF-8 BOM、把 CRLF 转成 LF、补齐结尾换行。二进制文件不要加此开关。

    .PARAMETER Mode
    目标文件权限，默认 0644；可执行脚本用 0755。

    .PARAMETER Owner
    目标文件属主，默认 root。

    .PARAMETER Group
    目标文件属组，默认 root。

    .PARAMETER Backup
    覆盖前把旧文件复制到 -BackupDirectory，文件名带时间戳。

    .PARAMETER BackupDirectory
    备份目录，默认 /var/backups。

    .PARAMETER CreateDirectory
    目标目录不存在时先创建。

    .EXAMPLE
    Push-FileToServers -Path ./work/update-cron.cron -RemotePath /etc/cron.d/update-cron -Linuxify

    推送定时任务文件：去掉 BOM 与 CR，落地为 644 root root，默认 10 台并发。

    .EXAMPLE
    Push-FileToServers -Path ./update_wp_functions.sh -RemotePath /www/sh/wp-functions-update/update_wp_functions.sh -Linuxify -Mode 0755 -Backup

    推送脚本并保留可执行位，同时备份旧版本。

    .EXAMPLE
    Push-FileToServers -Path ./hosts.txt -RemotePath /www/hosts.txt -Server 192.0.2.10,192.0.2.11 -ThrottleLimit 1 -WhatIf

    只查看将要执行的操作，不连接目标机；-ThrottleLimit 1 表示顺序执行。

    .NOTES
    结果按服务器清单顺序输出，便于逐台核对；并发完成顺序不影响结果顺序。
    首次连接目标机前需先手工 ssh 一次，接受 host key 并确认免密登录可用；本命令使用 BatchMode=yes，不会弹出密码提示。
    本命令只负责文件落地，不检查目标机是否存在重复的定时任务等业务冲突。
    远端命令未执行到清理语句时（例如解析失败或连接中断），已上传的临时文件会留在 /tmp，可用 rm -f /tmp/push-file-* 清理。
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [ValidatePattern('^/[A-Za-z0-9_./-]+$')]
        [string]$RemotePath,

        [string[]]$Server,

        $ServerConfig = $server_config,

        [int]$Skip = 1,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 10,

        [switch]$Linuxify,

        [ValidatePattern('^[0-7]{3,4}$')]
        [string]$Mode = '0644',

        [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')]
        [string]$Owner = 'root',

        [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')]
        [string]$Group = 'root',

        [switch]$Backup,

        [ValidatePattern('^/[A-Za-z0-9_./-]+$')]
        [string]$BackupDirectory = '/var/backups',

        [switch]$CreateDirectory
    )

    $source = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath

    # /etc/cron.d 中带点号的文件会被 run-parts 跳过，落地前先拦下这类目标
    $leaf = Split-Path -Leaf $RemotePath
    $parent = $RemotePath.Substring(0, $RemotePath.LastIndexOf('/'))
    if ($parent -eq '/etc/cron.d' -and $leaf.Contains('.'))
    {
        throw "目标文件 $leaf 含点号，/etc/cron.d 中这类文件会被 run-parts 跳过；请改用不含点号的名称，例如 $($leaf.Split('.')[0])。"
    }

    if (-not $Server)
    {
        $Server = @(Get-ServerList -Path $ServerConfig -Skip $Skip | ForEach-Object { $_.ip } | Where-Object { $_ })
    }
    if (-not $Server -or $Server.Count -eq 0)
    {
        throw "没有可用的目标机；请用 -Server 指定，或检查 Get-ServerList 的配置。"
    }

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("push-file-" + [guid]::NewGuid().ToString('N'))
    try
    {
        if ($Linuxify)
        {
            ConvertTo-LinuxTextFile -Path $source -Destination $tempFile
        }
        else
        {
            [System.IO.File]::Copy($source, $tempFile, $true)
        }
        $localHash = (Get-FileHash -LiteralPath $tempFile -Algorithm SHA256).Hash.ToLower()
        # stat -c %a 不输出前导零，0644 与 644 表示同一权限，比较前统一为无前导零形式
        $statMode = $Mode.TrimStart('0')
        if ($statMode -eq '')
        {
            $statMode = '0'
        }
        $expectedMode = "$statMode $Owner $Group"

        $context = [pscustomobject]@{
            RemotePath   = $RemotePath
            LocalHash    = $localHash
            ExpectedMode = $expectedMode
            Total        = $Server.Count
        }

        # 远端脚本：比对、备份、原子替换、写后回显，全部在一次 ssh 会话内完成。
        # 脚本内只用单引号，且所有路径都由参数校验保证不含空白与通配符，因此变量保持不加引号的用法：
        # 双引号会随 Windows 命令行解析变形，单引号不会；换行符由下方统一规范为 LF。
        $scriptTemplate = @'
target='__TARGET__'
tmp='__TMP__'
if [ -f $target ]; then
  h=$(sha256sum $target | cut -d' ' -f1)
  m=$(stat -c %a $target)
  u=$(stat -c %U $target)
  g=$(stat -c %G $target)
  if [ x$h = x__HASH__ ] && [ x$m = x__SMODE__ ] && [ x$u = x__OWNER__ ] && [ x$g = x__GROUP__ ]; then
    rm -f $tmp
    echo SKIPPED $h $m $u $g
    exit 0
  fi
fi
__MKDIR____BACKUP__install -m __PMODE__ -o __OWNER__ -g __GROUP__ $tmp $target.tmp && mv -f $target.tmp $target || { rm -f $tmp; exit 1; }
rm -f $tmp
echo UPDATED $(sha256sum $target | cut -d' ' -f1) $(stat -c %a $target) $(stat -c %U $target) $(stat -c %G $target)
'@

        $mkdirStep = ''
        if ($CreateDirectory)
        {
            $mkdirStep = "mkdir -p '$parent'`n"
        }
        $backupStep = ''
        if ($Backup)
        {
            $backupPath = "bk='$BackupDirectory/$leaf.'" + '$(date +%Y%m%d-%H%M%S)'
            $backupStep = @(
                "mkdir -p '$BackupDirectory'"
                $backupPath
                'if [ -f $target ]; then cp -p $target $bk; fi'
            ) -join "`n"
            $backupStep += "`n"
        }

        # 单台目标机的全部动作集中在这一个脚本块里，顺序执行与并行走同一份逻辑
        $work = {
            param($Item, $Context)

            # Windows PowerShell 5.1 在 ErrorActionPreference=Stop 时会把原生命令的 stderr 变成终止错误，
            # 这里降为 Continue，失败统一由退出码判断，避免单台失败中断整批
            $ErrorActionPreference = 'Continue'

            $result = [pscustomobject]@{
                Index   = $Item.Index
                Server  = $Item.Target
                Remote  = $Context.RemotePath
                Status  = 'Pending'
                Mode    = ''
                Message = ''
            }

            # 单台失败只记录状态并跳出，不影响其余目标机
            do
            {
                $uploadOutput = & scp -q -o BatchMode=yes -o ConnectTimeout=10 $Item.LocalFile "$($Item.Target):$($Item.RemoteTemp)" 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    $result.Status = 'Failed'
                    $result.Message = "上传失败: " + (($uploadOutput | Out-String).Trim())
                    break
                }

                $output = & ssh -nT -o BatchMode=yes -o ConnectTimeout=10 $Item.Target $Item.RemoteCmd 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    $result.Status = 'Failed'
                    $result.Message = "写入失败: " + (($output | Out-String).Trim())
                    break
                }

                $line = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^(SKIPPED|UPDATED) ' } | Select-Object -Last 1)
                if ($line.Count -eq 0)
                {
                    $result.Status = 'Failed'
                    $result.Message = "未取得目标文件状态: " + (($output | Out-String).Trim())
                    break
                }

                $parts = $line[0] -split '\s+'
                $result.Mode = ($parts[2..4] -join ' ')
                if ($parts[0] -eq 'SKIPPED')
                {
                    $result.Status = 'Skipped'
                    $result.Message = '内容与权限已一致'
                }
                elseif ($parts[1] -eq $Context.LocalHash -and $result.Mode -eq $Context.ExpectedMode)
                {
                    $result.Status = 'Updated'
                    $result.Message = '已写入并校验通过'
                }
                else
                {
                    $result.Status = 'Failed'
                    $result.Message = "写后校验不通过：hash=$($parts[1]) 权限=$($result.Mode)，期望 $($Context.ExpectedMode)"
                }
            }
            while ($false)

            return $result
        }

        $results = @()
        $queue = @()
        $createdJobs = @()
        $index = 0
        foreach ($item in $Server)
        {
            $target = "$item"
            if ($target -notmatch '@')
            {
                $target = "root@$target"
            }

            if (-not $PSCmdlet.ShouldProcess("$target`:$RemotePath", '推送文件'))
            {
                $results += [pscustomobject]@{
                    Index   = $index
                    Server  = $target
                    Remote  = $RemotePath
                    Status  = 'WhatIf'
                    Mode    = ''
                    Message = '未连接目标机'
                }
                $index++
                continue
            }

            $remoteTemp = "/tmp/push-file-" + [guid]::NewGuid().ToString('N').Substring(0, 12)
            $remoteCmd = $scriptTemplate
            $remoteCmd = $remoteCmd.Replace('__TARGET__', $RemotePath)
            $remoteCmd = $remoteCmd.Replace('__TMP__', $remoteTemp)
            $remoteCmd = $remoteCmd.Replace('__HASH__', $localHash)
            $remoteCmd = $remoteCmd.Replace('__SMODE__', $statMode)
            $remoteCmd = $remoteCmd.Replace('__PMODE__', $Mode)
            $remoteCmd = $remoteCmd.Replace('__OWNER__', $Owner)
            $remoteCmd = $remoteCmd.Replace('__GROUP__', $Group)
            $remoteCmd = $remoteCmd.Replace('__MKDIR__', $mkdirStep)
            $remoteCmd = $remoteCmd.Replace('__BACKUP__', $backupStep)
            # 远端 shell 不把 CR 当空白：CRLF 会让 then、fi、} 等标记失效，脚本必须以 LF 下发
            $remoteCmd = ($remoteCmd -replace "`r`n", "`n") -replace "`r", ''

            Write-Verbose "排队推送 $target`:$RemotePath"
            $queue += [pscustomobject]@{
                Index      = $index
                Target     = $target
                LocalFile  = $tempFile
                RemoteTemp = $remoteTemp
                RemoteCmd  = $remoteCmd
            }
            $index++
        }

        # 进度行统一由调用方输出：作业方式的 runspace 里 Write-Host 不会实时冒泡到控制台
        $announceStart = {
            param($Item, $Total)
            Write-Host ("[{0}] [{1}/{2}] {3} 开始" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ($Item.Index + 1), $Total, $Item.Target)
        }
        $announceDone = {
            param($Result, $Total, $Seconds)
            $detail = $Result.Mode
            if ($Result.Status -eq 'Failed')
            {
                $detail = ($Result.Message -split "`n")[0]
            }
            if ($detail.Length -gt 120)
            {
                $detail = $detail.Substring(0, 120) + '…'
            }
            $color = switch ($Result.Status)
            {
                'Updated' { 'Green' }
                'Skipped' { 'DarkGray' }
                default { 'Red' }
            }
            Write-Host ("[{0}] [{1}/{2}] {3} {4} {5}（{6:N1} 秒）" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ($Result.Index + 1), $Total, $Result.Server, $Result.Status, $detail, $Seconds) -ForegroundColor $color
        }

        if ($queue.Count -gt 0)
        {
            $total = $queue.Count
            $throttle = [Math]::Max(1, [Math]::Min($ThrottleLimit, $total))
            $modeText = if ($throttle -gt 1) { "并发 $throttle" } else { '顺序执行' }
            Write-Host ("[{0}] 推送 {1} 台 → {2}（{3}）" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $total, $RemotePath, $modeText)
            $batchClock = [System.Diagnostics.Stopwatch]::StartNew()

            if ($throttle -le 1)
            {
                foreach ($item in $queue)
                {
                    & $announceStart $item $total
                    $clock = [System.Diagnostics.Stopwatch]::StartNew()
                    $result = & $work $item $context
                    $clock.Stop()
                    & $announceDone $result $total $clock.Elapsed.TotalSeconds
                    $results += $result
                }
            }
            else
            {
                # ThreadJob 5.1 需另行安装，缺装时退回进程级后台作业，功能一致但每台多一次进程启动
                $threadJob = Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue
                if (-not $threadJob)
                {
                    Write-Verbose "未检测到 ThreadJob 模块，改用后台作业（独立进程）执行；安装 ThreadJob 可减少启动开销。"
                }

                $workText = $work.ToString()
                $running = @()
                $entries = @{}
                $next = 0
                while ($next -lt $total -or $running.Count -gt 0)
                {
                    while ($next -lt $total -and $running.Count -lt $throttle)
                    {
                        $item = $queue[$next]
                        $next++
                        & $announceStart $item $total
                        $scriptBlock = [scriptblock]::Create($workText)
                        if ($threadJob)
                        {
                            $job = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList $item, $context
                        }
                        else
                        {
                            $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $item, $context
                        }
                        $createdJobs += $job
                        $entries[$job.Id] = [pscustomobject]@{
                            Item  = $item
                            Clock = [System.Diagnostics.Stopwatch]::StartNew()
                        }
                        $running += $job
                    }

                    $completed = @($running | Wait-Job -Any)
                    foreach ($job in $completed)
                    {
                        if ($job.State -eq 'Running' -or $job.State -eq 'NotStarted')
                        {
                            continue
                        }

                        $entry = $entries[$job.Id]
                        $received = @(Receive-Job -Job $job)
                        $entry.Clock.Stop()
                        $result = $received | Select-Object -First 1
                        if (-not $result -or -not $result.PSObject.Properties['Status'])
                        {
                            $reason = $job.ChildJobs[0].JobStateInfo.Reason
                            $message = if ($reason) { $reason.Message } else { ($received | Out-String).Trim() }
                            $result = [pscustomobject]@{
                                Index   = $entry.Item.Index
                                Server  = $entry.Item.Target
                                Remote  = $RemotePath
                                Status  = 'Failed'
                                Mode    = ''
                                Message = "作业异常: $message"
                            }
                        }

                        & $announceDone $result $total $entry.Clock.Elapsed.TotalSeconds
                        $results += $result
                        $entries.Remove($job.Id)
                        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                        $running = @($running | Where-Object { $_.Id -ne $job.Id })
                    }
                }
            }
        }

        $results = @($results | Sort-Object -Property Index)

        $failed = @($results | Where-Object { $_.Status -eq 'Failed' })
        if ($batchClock)
        {
            $batchClock.Stop()
            $updated = @($results | Where-Object { $_.Status -eq 'Updated' }).Count
            $skipped = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count
            Write-Host ("[{0}] 完成：共 {1} 台，更新 {2}，跳过 {3}，失败 {4}，用时 {5:N1} 秒" -f `
                    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $results.Count, $updated, $skipped, $failed.Count, $batchClock.Elapsed.TotalSeconds)
        }
        foreach ($item in $failed)
        {
            Write-Warning "$($item.Server) 失败：$($item.Message)"
        }
        if ($failed.Count -gt 0)
        {
            Write-Warning "共 $($results.Count) 台，失败 $($failed.Count) 台；失败机器可用 -WhatIf 复核后再重试。"
        }
        return $results
    }
    finally
    {
        # 中断或异常退出时停掉本轮创建的后台作业，不碰调用方自己的作业
        if ($createdJobs)
        {
            $createdJobs | Remove-Job -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $tempFile)
        {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue -WhatIf:$false
        }
    }
}
function Deploy-CronFile
{
    <#
    .SYNOPSIS
    批量部署一份受管 cron 文件：预检、按时区选模板、落地、校验与汇总。

    .DESCRIPTION
    前置条件：目标机已配置 root 免密登录，已安装并运行 cron，模板引用的脚本已部署到目标机。
    执行者：当前会话逐台 SSH 预检，落地阶段调用 Push-FileToServers 完成上传与安装；单台失败不中断整批。
    善后：无需额外操作；重复执行时内容与权限一致的机器直接跳过。

    与仓库 update-cron/deploy.sh 行为对齐：预检 root 权限、目标目录、依赖文件、cron 服务与重复任务条目，
    支持按目标机系统时区在 cron.cst 与 cron.utc 之间选择，写入前备份，写后由 Push-FileToServers 校验哈希与权限。
    每台目标机三次连接：预检、上传、安装；用 -TemplateDirectory 自动选模板时再加一次时区探测。
    进度行带本地时间，结果按清单顺序返回，Status 取 Deployed、Skipped、Checked、Removed、Failed、WhatIf。

    .PARAMETER Template
    模板文件，与 -TemplateDirectory 二选一，-Remove 时不需要。

    .PARAMETER TemplateDirectory
    存放 cron.cst 与 cron.utc 的目录，按目标机系统时区选择模板；无法识别的时区判为失败。

    .PARAMETER RemotePath
    受管文件路径，默认 /etc/cron.d/update-cron，文件名不能含点号。

    .PARAMETER BackupDirectory
    备份目录，默认 /var/backups/<受管文件名>。

    .PARAMETER Require
    下发前要求目标机存在的文件，可传多个；路径不能含空白。

    .PARAMETER AllowExisting
    跳过重复任务条目检查，仅在确认不会重复执行时使用。

    .PARAMETER Check
    只校验受管文件的内容与权限，不写入。

    .PARAMETER Remove
    备份后删除受管文件，不需要模板。

    .PARAMETER FailOnError
    处理完成后若存在失败机器则抛出异常，供脚本或 CI 判定。

    .PARAMETER ThrottleLimit
    推送阶段的并发度，默认 10，取值 1 到 64；预检始终逐台执行。设为 1 时全程顺序执行。

    .EXAMPLE
    Deploy-CronFile -Template ./work/update-cron.cron -Require /www/functions4.php

    按清单逐台预检并部署，已是最新的目标机跳过。

    .EXAMPLE
    Deploy-CronFile -TemplateDirectory ./work/templates -WhatIf

    只打印将执行的动作，不连接目标机。

    .EXAMPLE
    Deploy-CronFile -Check -Template ./work/update-cron.cron -FailOnError

    校验全部目标机，存在不一致时抛异常。

    .NOTES
    -Server 省略时读取 Get-ServerList 的 ip 字段并跳过开头 1 条。
    与 deploy.sh 的差别：不解析 hosts.txt，-WhatIf 不读取远端状态；其余预检与写入语义一致。
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$Template,

        [string]$TemplateDirectory,

        [ValidatePattern('^/[A-Za-z0-9_./-]+$')]
        [string]$RemotePath = '/etc/cron.d/update-cron',

        [ValidatePattern('^/[A-Za-z0-9_./-]+$')]
        [string]$BackupDirectory,

        [string[]]$Require,

        [switch]$AllowExisting,

        [string[]]$Server,

        $ServerConfig = $server_config,

        [int]$Skip = 1,

        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 10,

        [ValidatePattern('^[0-7]{3,4}$')]
        [string]$Mode = '0644',

        [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')]
        [string]$Owner = 'root',

        [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')]
        [string]$Group = 'root',

        [switch]$Check,

        [switch]$Remove,

        [switch]$FailOnError
    )

    # Windows PowerShell 5.1 在 ErrorActionPreference=Stop 时会把原生命令的 stderr 变成终止错误，
    # 这里降为 Continue，失败统一由退出码判断，避免单台失败中断整批
    $ErrorActionPreference = 'Continue'

    if ($Check -and $Remove)
    {
        throw '-Check 与 -Remove 不能同时使用。'
    }
    if ($Template -and $TemplateDirectory)
    {
        throw '-Template 与 -TemplateDirectory 只能给一个。'
    }
    if (-not $Remove -and -not $Template -and -not $TemplateDirectory)
    {
        throw '需要 -Template 或 -TemplateDirectory；只删除时用 -Remove。'
    }

    $leaf = Split-Path -Leaf $RemotePath
    $parent = $RemotePath.Substring(0, $RemotePath.LastIndexOf('/'))
    if ($parent -eq '/etc/cron.d' -and $leaf.Contains('.'))
    {
        throw "目标文件 $leaf 含点号，/etc/cron.d 中这类文件会被 run-parts 跳过；请改用不含点号的名称。"
    }
    if (-not $BackupDirectory)
    {
        $BackupDirectory = "/var/backups/$leaf"
    }

    $requireList = @()
    foreach ($item in @($Require))
    {
        if (-not $item)
        {
            continue
        }
        if ($item -notmatch '^/[^\s]+$')
        {
            throw "依赖路径必须是不含空白的绝对路径: $item"
        }
        $requireList += $item
    }

    $templateMap = @{}
    if ($Template)
    {
        $templateMap['forced'] = (Resolve-Path -LiteralPath $Template -ErrorAction Stop).ProviderPath
    }
    elseif ($TemplateDirectory)
    {
        $dir = (Resolve-Path -LiteralPath $TemplateDirectory -ErrorAction Stop).ProviderPath
        $cst = Join-Path $dir 'cron.cst'
        $utc = Join-Path $dir 'cron.utc'
        foreach ($p in @($cst, $utc))
        {
            if (-not (Test-Path -LiteralPath $p))
            {
                throw "模板目录缺少 $(Split-Path -Leaf $p): $dir"
            }
        }
        $templateMap['cst'] = $cst
        $templateMap['utc'] = $utc
    }

    if (-not $Server)
    {
        $Server = @(Get-ServerList -Path $ServerConfig -Skip $Skip | ForEach-Object { $_.ip } | Where-Object { $_ })
    }
    if (-not $Server -or $Server.Count -eq 0)
    {
        throw '没有可用的目标机；请用 -Server 指定，或检查 Get-ServerList 的配置。'
    }

    $statMode = $Mode.TrimStart('0')
    if ($statMode -eq '')
    {
        $statMode = '0'
    }
    $expectedMode = "$statMode $Owner $Group"

    # 把模板转成 LF、算哈希、提取 .php 与 .sh 基名；同一模板只处理一次
    $prepare = {
        param($TemplatePath)
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("cron-deploy-" + [guid]::NewGuid().ToString('N') + '.cron')
        ConvertTo-LinuxTextFile -Path $TemplatePath -Destination $temp
        $hash = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLower()
        $patterns = @()
        foreach ($line in [System.IO.File]::ReadAllLines($temp))
        {
            if ($line -match '^\s*(#|$)')
            {
                continue
            }
            foreach ($match in [regex]::Matches($line, '\S+\.(?:php|sh)'))
            {
                $patterns += [System.IO.Path]::GetFileName($match.Value)
            }
        }
        [pscustomobject]@{
            Path     = $TemplatePath
            Temp     = $temp
            Hash     = $hash
            Patterns = @($patterns | Sort-Object -Unique)
        }
    }

    # 远端按行读取的名单走 base64，避免空参数与引号问题；空名单用 '-' 占位
    $encodeLines = {
        param($Lines)
        $list = @($Lines | Where-Object { $_ })
        if ($list.Count -eq 0)
        {
            return '-'
        }
        $text = ($list -join "`n") + "`n"
        return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($text))
    }

    $runRemote = {
        param($Target, $ScriptText)
        # 5.1 在 Stop 下会把 ssh 的 stderr 变成终止错误，这里固定为 Continue，失败看退出码
        $ErrorActionPreference = 'Continue'
        $text = ($ScriptText -replace "`r`n", "`n") -replace "`r", ''
        $output = & ssh -nT -o BatchMode=yes -o ConnectTimeout=10 $Target $text 2>&1
        [pscustomobject]@{
            Code   = $LASTEXITCODE
            Output = @($output | ForEach-Object { "$_" })
        }
    }

    $timezoneScript = @'
set -u
tz=
if command -v timedatectl >/dev/null 2>&1; then
  tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
fi
if [ -z $tz ] && [ -r /etc/timezone ]; then
  tz=$(cat /etc/timezone 2>/dev/null || true)
fi
if [ -z $tz ] && [ -L /etc/localtime ]; then
  tz=$(readlink -f /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
fi
echo TZ=$tz
'@

    # 只在远端用单引号与 POSIX 语法：Windows PowerShell 5.1 传参时会吃掉双引号
    $precheckScript = @'
set -eu
target=__TARGET__
allow_existing=__ALLOW__
patterns_b64=__PATTERNS__
requires_b64=__REQUIRES__
target_dir=__PARENT__

[ $(id -u) -eq 0 ] || { echo 需要 root 权限 >&2; exit 1; }
[ -d $target_dir ] || { echo 目标目录不存在: $target_dir >&2; exit 1; }
for c in install mktemp sha256sum stat base64; do
  command -v $c >/dev/null 2>&1 || { echo 缺少命令: $c >&2; exit 1; }
done

if [ $requires_b64 != - ]; then
  rl=$(mktemp)
  printf '%s' $requires_b64 | base64 -d > $rl
  while IFS= read -r f; do
    if [ -z $f ]; then continue; fi
    [ -f $f ] || { rm -f $rl; echo 缺少文件: $f >&2; exit 1; }
  done < $rl
  rm -f $rl
fi

cron_ok=0
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null || systemctl is-active --quiet cronie 2>/dev/null; then
    cron_ok=1
  fi
fi
if [ $cron_ok -eq 0 ] && (pgrep -x cron >/dev/null 2>&1 || pgrep -x crond >/dev/null 2>&1 || pgrep -x cronie >/dev/null 2>&1); then
  cron_ok=1
fi
if [ $cron_ok -eq 0 ]; then
  echo cron 服务未运行，请先启动 cron、crond 或 cronie >&2
  exit 1
fi

if [ $allow_existing -eq 0 ] && [ $patterns_b64 != - ]; then
  pf=$(mktemp)
  out=$(mktemp)
  printf '%s' $patterns_b64 | base64 -d > $pf
  if crontab -l >/dev/null 2>&1; then
    crontab -l 2>/dev/null | grep -nF -f $pf > $out 2>/dev/null || true
    if [ -s $out ]; then
      echo root crontab 中已存在引用下列脚本的条目: >&2
      cat $out >&2
      echo 请先备份并删除旧条目，确认后重试，或用 -AllowExisting 跳过 >&2
      rm -f $pf $out
      exit 2
    fi
  fi
  for f in /etc/crontab /etc/cron.d/*; do
    if [ ! -f $f ]; then continue; fi
    if [ $f = $target ]; then continue; fi
    case $(basename $f) in .*) continue ;; esac
    grep -nF -f $pf $f > $out 2>/dev/null || true
    if [ -s $out ]; then
      echo 文件 $f 中已存在引用下列脚本的条目: >&2
      cat $out >&2
      echo 请先删除旧条目，或用 -AllowExisting 跳过 >&2
      rm -f $pf $out
      exit 2
    fi
  done
  rm -f $pf $out
fi

if [ -f $target ]; then
  hash=$(sha256sum $target | awk '{print $1}')
  mode=$(stat -c '%a %U %G' $target)
  echo STATE=PRESENT HASH=$hash MODE=$mode
else
  echo STATE=MISSING
fi
'@

    $statusScript = @'
if [ -f __TARGET__ ]; then
  sha256sum __TARGET__
  stat -c '%a %U %G' __TARGET__
else
  echo MISSING
fi
'@

    $removeScript = @'
set -eu
target=__TARGET__
backup_dir=__BACKUP__
name=__LEAF__

[ $(id -u) -eq 0 ] || { echo 需要 root 权限 >&2; exit 1; }

if [ -f $target ]; then
  mkdir -p $backup_dir
  cp -p $target $backup_dir/$name.removed.$(date +%Y%m%d-%H%M%S)
  rm -f $target
  echo REMOVED
else
  echo MISSING
fi
'@

    $records = @()
    $prepared = @{}
    $pushGroups = @{}
    $temps = @()
    $total = $Server.Count
    $index = 0
    $clock = [System.Diagnostics.Stopwatch]::StartNew()

    try
    {
        foreach ($item in $Server)
        {
            $target = "$item"
            if ($target -notmatch '@')
            {
                $target = "root@$target"
            }
            $index++

            $record = [pscustomobject]@{
                Index    = $index
                Server   = $target
                Status   = 'Pending'
                Mode     = ''
                Timezone = ''
                Template = ''
                Message  = ''
            }
            $records += $record

            if (-not $PSCmdlet.ShouldProcess("$target`:$RemotePath", '部署 cron 文件'))
            {
                $record.Status = 'WhatIf'
                $record.Message = '未连接目标机'
                Write-Host ("[{0}] [{1}/{2}] {3} WhatIf 未连接目标机" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $index, $total, $target) -ForegroundColor DarkGray
                continue
            }

            Write-Host ("[{0}] [{1}/{2}] {3} 预检" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $index, $total, $target) -ForegroundColor DarkGray

            if ($Remove)
            {
                $scriptText = $removeScript.Replace('__TARGET__', $RemotePath).Replace('__BACKUP__', $BackupDirectory).Replace('__LEAF__', $leaf)
                $remote = & $runRemote $target $scriptText
                if ($remote.Code -ne 0)
                {
                    $record.Status = 'Failed'
                    $record.Message = (@($remote.Output) -join ' ').Trim()
                }
                elseif (@($remote.Output | Where-Object { $_ -eq 'REMOVED' }).Count -gt 0)
                {
                    $record.Status = 'Removed'
                    $record.Message = '已备份并删除'
                }
                else
                {
                    $record.Status = 'Skipped'
                    $record.Message = '目标文件不存在'
                }
                Write-Host ("[{0}] [{1}/{2}] {3} {4} {5}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $index, $total, $target, $record.Status, $record.Message)
                continue
            }

            $key = 'forced'
            if (-not $Template)
            {
                $remote = & $runRemote $target $timezoneScript
                $tzLine = @($remote.Output | Where-Object { $_ -match '^TZ=' } | Select-Object -Last 1)
                if ($remote.Code -ne 0 -or $tzLine.Count -eq 0)
                {
                    $record.Status = 'Failed'
                    $record.Message = '无法获取系统时区'
                    continue
                }
                $tz = "$($tzLine[0])".Substring(3).Trim()
                $record.Timezone = $tz
                $key = ''
                if ($tz -match '^(Asia/Shanghai|Asia/Chongqing|Asia/Harbin|PRC)$')
                {
                    $key = 'cst'
                }
                elseif ($tz -match '^(UTC|Etc/UTC|Etc/GMT|Etc/GMT\+0|Etc/GMT-0|GMT|UCT|Zulu)$')
                {
                    $key = 'utc'
                }
                if (-not $key)
                {
                    $record.Status = 'Failed'
                    $record.Message = "不支持的时区 $tz，请用 -Template 指定模板"
                    continue
                }
            }

            $templatePath = $templateMap[$key]
            if (-not $prepared.ContainsKey($templatePath))
            {
                $prepared[$templatePath] = & $prepare $templatePath
                $temps += $prepared[$templatePath].Temp
            }
            $tpl = $prepared[$templatePath]
            $record.Template = Split-Path -Leaf $templatePath

            if ($Check)
            {
                $remote = & $runRemote $target $statusScript.Replace('__TARGET__', $RemotePath)
                $lines = @($remote.Output | Where-Object { $_.Trim() })
                if ($remote.Code -ne 0)
                {
                    $record.Status = 'Failed'
                    $record.Message = (@($remote.Output) -join ' ').Trim()
                }
                elseif ($lines.Count -eq 1 -and $lines[0].Trim() -eq 'MISSING')
                {
                    $record.Status = 'Failed'
                    $record.Message = '目标文件不存在'
                }
                elseif ($lines.Count -ge 2)
                {
                    $remoteHash = ($lines[0].Trim() -split '\s+')[0]
                    $remoteMode = $lines[$lines.Count - 1].Trim()
                    $record.Mode = $remoteMode
                    if ($remoteHash -ne $tpl.Hash)
                    {
                        $record.Status = 'Failed'
                        $record.Message = '内容与模板不一致'
                    }
                    elseif ($remoteMode -ne $expectedMode)
                    {
                        $record.Status = 'Failed'
                        $record.Message = "权限或属主不符合要求: $remoteMode"
                    }
                    else
                    {
                        $record.Status = 'Checked'
                        $record.Message = '内容与权限一致'
                    }
                }
                else
                {
                    $record.Status = 'Failed'
                    $record.Message = '未取得目标文件状态: ' + (@($remote.Output) -join ' ').Trim()
                }
                Write-Host ("[{0}] [{1}/{2}] {3} {4} {5}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $index, $total, $target, $record.Status, $record.Message)
                continue
            }

            $scriptText = $precheckScript.Replace('__TARGET__', $RemotePath)
            $scriptText = $scriptText.Replace('__PARENT__', $parent)
            $scriptText = $scriptText.Replace('__ALLOW__', $(if ($AllowExisting) { '1' } else { '0' }))
            $scriptText = $scriptText.Replace('__PATTERNS__', (& $encodeLines $tpl.Patterns))
            $scriptText = $scriptText.Replace('__REQUIRES__', (& $encodeLines $requireList))

            $remote = & $runRemote $target $scriptText
            if ($remote.Code -eq 2)
            {
                $record.Status = 'Failed'
                $record.Message = '已存在重复任务条目'
                foreach ($line in @($remote.Output | Where-Object { $_.Trim() }))
                {
                    Write-Warning "$target $line"
                }
                continue
            }
            if ($remote.Code -ne 0)
            {
                $record.Status = 'Failed'
                $record.Message = (@($remote.Output) -join ' ').Trim()
                continue
            }

            $stateLine = @($remote.Output | Where-Object { $_ -match '^STATE=' } | Select-Object -Last 1)
            if ($stateLine.Count -eq 0)
            {
                $record.Status = 'Failed'
                $record.Message = '未取得目标文件状态: ' + (@($remote.Output) -join ' ').Trim()
                continue
            }

            $stateText = "$($stateLine[0])"
            if ($stateText -match '^STATE=PRESENT HASH=(\S+) MODE=(.+)$')
            {
                $remoteHash = $Matches[1]
                $remoteMode = $Matches[2].Trim()
                $record.Mode = $remoteMode
                if ($remoteHash -eq $tpl.Hash -and $remoteMode -eq $expectedMode)
                {
                    $record.Status = 'Skipped'
                    $record.Message = '内容与权限已一致'
                    Write-Host ("[{0}] [{1}/{2}] {3} Skipped 内容与权限已一致" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $index, $total, $target) -ForegroundColor DarkGray
                    continue
                }
            }

            $record.Message = '待推送'
            if (-not $pushGroups.ContainsKey($templatePath))
            {
                $pushGroups[$templatePath] = @()
            }
            $pushGroups[$templatePath] += $target
        }

        foreach ($templatePath in @($pushGroups.Keys))
        {
            $targets = @($pushGroups[$templatePath])
            $tpl = $prepared[$templatePath]
            $pushed = @(Push-FileToServers -Path $tpl.Temp -RemotePath $RemotePath -Server $targets -Linuxify -Mode $Mode -Owner $Owner -Group $Group -Backup -BackupDirectory $BackupDirectory -ThrottleLimit $ThrottleLimit)
            foreach ($pushResult in $pushed)
            {
                $record = $records | Where-Object { $_.Server -eq $pushResult.Server } | Select-Object -First 1
                if (-not $record)
                {
                    continue
                }
                switch ($pushResult.Status)
                {
                    'Updated' {
                        $record.Status = 'Deployed'
                        $record.Message = '已写入并校验通过'
                    }
                    'Skipped' {
                        $record.Status = 'Skipped'
                        $record.Message = '内容与权限已一致'
                    }
                    default {
                        $record.Status = 'Failed'
                        $record.Message = $pushResult.Message
                    }
                }
                $record.Mode = $pushResult.Mode
            }
        }
    }
    finally
    {
        foreach ($tempFile in $temps)
        {
            if ($tempFile -and (Test-Path -LiteralPath $tempFile))
            {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        $clock.Stop()
    }

    $deployed = @($records | Where-Object { $_.Status -eq 'Deployed' }).Count
    $skipped = @($records | Where-Object { $_.Status -eq 'Skipped' }).Count
    $failed = @($records | Where-Object { $_.Status -eq 'Failed' })

    Write-Host ("[{0}] 完成：共 {1} 台，部署 {2}，跳过 {3}，失败 {4}，用时 {5:N1} 秒" -f `
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $records.Count, $deployed, $skipped, $failed.Count, $clock.Elapsed.TotalSeconds)
    foreach ($item in $failed)
    {
        Write-Warning "$($item.Server) 失败：$($item.Message)"
    }
    if ($failed.Count -gt 0 -and $FailOnError)
    {
        throw "共 $($records.Count) 台，失败 $($failed.Count) 台。"
    }
    return $records
}
