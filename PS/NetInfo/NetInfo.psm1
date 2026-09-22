<#
NetInfo 模块:网络连接与 IP 信息(连接名/IP 格式化/prompt 供数)。
从 Info.psm1 迁入(2026-09-22):曾短暂进 NetWork,但其 Json 运行时依赖会顶掉 Prompt 的 5.1 垫片,故独立留 7;
调用方命令名不变(自动发现同名模块)。
#>

function Get-NetConnectionInfo
{
    <# 
    .SYNOPSIS
    返回当前所链接wifi的名字(如果连上了的话)
    #>
    [CmdletBinding()]
    param(
        # [switch]$WriteToEnv,
        $EnvName = 'ConnectionName'
        # [switch]$CheckUpdateEnvConnectionName
    )
    # 老式方法:netsh (不推荐)
    # $wifiProfile = netsh wlan show interfaces | Select-String '^\s+Profile\s+:\s+(.*)$'
    # $ConnectionName = $wifiProfile.Matches[0].Groups[1].Value.Trim()

    $Name = (Get-NetConnectionProfile).Name
    return $Name
}

function Update-NetConnectionInfo
{
    <# 
    .SYNOPSIS
    检测网络间接信息(连接名,比如wifi名字或者以太网名字)
    从DataJson中尝试读取相关信息,如果和当前检测到的信息内容不对应,那么认为链接发生了变化,需要更新连接名称(ConnectionName)

    此更新进程不会检查ip地址是否变化,只会在需要时更新连接名(顺便重置ip地址)
    也就是说,只要网络连接没有发生变换,那么dataJson文件就不会被此进程更改,指示定时读取里面的数据和当前的实际情况进行对比来检测网络状态变换以及更新对应的ip地址,供其他进程使用,比如Prompt显示ip地址
    #>
    [CmdletBinding()]
    param (
        $DataJson = $DataJson,
        $connectionName = 'ConnectionName',
        $Interval = 6
    )
    # 注:此处曾有 Write-Host $DataJson 调试输出(每次守护进程启动都会向控制台吐一行路径),已删除
    # 守护进程用不上 predictor:经 -Command/-c 起来的后台会话关掉它(交互会话手动调不受影响)
    if (@([Environment]::GetCommandLineArgs()) -match '^-(?i:c|command)$')
    {
        $env:PsPredictor = 'False'
    }
    while ($true)
    {
        $Name = @(Get-Json -Key $ConnectionName -dataJson $DataJson -ErrorAction SilentlyContinue)
        $newName = @(Get-NetConnectionInfo)
        if ($VerbosePreference)
        {

            # "Name: $Name, NewName: $newName"
            [PSCustomObject]@{
                Name    = $Name
                NewName = $newName
            } | Format-Table
        }

        # 排序并转换为字符串
        $NameValue = ($Name | Sort-Object) -join ','
        $NewNameValue = ($NewName | Sort-Object) -join ','
        # $res = $newName -eq $Name
        $res = $NameValue -eq $NewNameValue
        if (!$res)
        {
            Write-Host "Name changed: $NameValue -> $NewNameValue" -ForegroundColor Magenta
            # 修改数据文件
            Update-Json -Key $connectionName -Value $NewNameValue -Path $DataJson
            Get-IpAddressFormated -dataJson $DataJson # 重新获取IP 
            Update-DataJsonLastWriteTime -DataJson $DataJson
                    
        }
        else
        {
            Write-Host "Name not changed: $NameValue" -ForegroundColor Green
        }
          
        Start-Sleep $Interval
    }
}
# prompt 高频调用时的会话级记忆(文件缓存由守护进程维护,此处只兜底文件未命中;含 $null 也缓存以避免反复全量枚举)
$script:IpFormatedCache = @{ Value = $null; Time = [datetime]::MinValue }
function Get-IpAddressFormated
{
    <# 
    .SYNOPSIS
    获取接入网络的物理网卡的地址(ipv4),比如WI-FI的IP地址,或者Ethernet的ip地址
    .DESCRIPTION
    函数主要由Get-IPAddressForPrompt调用,也可以手动调用刷新IP缓存信息
    .NOTES
    这是一个耗时函数,如果直接用于Prompt,大幅增加加载时间,因此引入了缓存机制


    #>
    [CmdletBinding(DefaultParameterSetName = 'Cache')]
    param (
        [ValidateSet('Up', 'Disconnected', 'All')]$Status = 'up',
        [parameter(ParameterSetName = 'Cache')]
        # 是否优先读取环境变量缓存中的IP地址
        [switch]$Cache,
        # 是否强制置空缓存(不会触发重新计算)
        [switch]$Clear,
        $dataJson = $DataJson,
        # 会话内记忆秒数:文件缓存未命中(守护进程未跑/新文件)时,避免每回车都全量枚举网卡(单次可达上秒)
        $TTLSeconds = 60
        # 是否重新计算并更新缓存
        # [parameter(ParameterSetName = 'Update')]
        # [switch]$UpdateIfWifiChange
    )
    # $ips = Get-IPAddressOfPhysicalAdapter
    #一般我们只对物理网卡比较感兴趣,并且我们只需名字和IP地址
    if ($Clear)
    {
        # $env:IpPrompt = $null
        Update-Json -Key IpPrompt -Value '' -DataJson $DataJson
        # 或者 remove-item env:/IpPrompt
        $env:ClearIpPrompt = 1
        return
    }
    if ($Cache)
    {

        # 尝试直接读取环境变量中的ip信息,并直接返回
    
        # return $env:IpPrompt
        # $s = Get-EnvVar -Key IpPrompt | Select-Object -ExpandProperty Value
        $s = Get-Json -JsonInput $DataJson -Key IpPrompt
        return  $s
    }
    
    # 会话级记忆:文件缓存未命中时,连续 prompt 只算一次(网络切换由守护进程写文件,文件命中不受 TTL 影响)
    $expired = ($script:IpFormatedCache.Time -eq [datetime]::MinValue) -or `
        (([datetime]::UtcNow - $script:IpFormatedCache.Time).TotalSeconds -ge $TTLSeconds)
    if (-not $expired -and $null -ne $script:IpFormatedCache.Value)
    {
        return $script:IpFormatedCache.Value
    }

    $adapters = Get-NetAdapter -Physical
    if ($Status -ne 'All')
    {
        $adapters = $adapters | Where-Object { $_.Status -eq $Status }
    }

    # return $adapters

    # 一次性取全量 IPv4,内存中按 InterfaceIndex 配对(原逐网卡调用 Get-NetIPAddress,网卡多时成倍变慢)
    $ipTable = @{}
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $ipTable.ContainsKey($_.InterfaceIndex)) { $ipTable[$_.InterfaceIndex] = @() }
        $ipTable[$_.InterfaceIndex] += $_.IPAddress
    }

    if ($VerbosePreference)
    {
        $adapters | Format-Table
    }

    $s = ''
    foreach ($adapter in ($adapters | Select-Object Name, Status, InterfaceIndex))
    {
        # if ($adapters)
        # $s += ("[$($ip.InterfaceAlias) : $($ip.IpAddress)]")
        $ips = $ipTable[$adapter.InterfaceIndex]
        $s += ("<$($adapter.Name[0]):$ips>")
    }
    # $ip = Get-IPAddressOfPhysicalAdapter | Select-Object -First 1 | Select-Object -ExpandProperty ipaddress
    # 将ip信息写入到环境变量保存起来,以便后续访问
    Write-Verbose $s
    # 写入环境变量
    # Set-EnvVar -EnvVar IpPrompt $s *> $null
    Update-Json -Key IpPrompt -Value $s -DataJson $dataJson
    $script:IpFormatedCache = @{ Value = $s; Time = [datetime]::UtcNow }

    return $s

}

function Get-IpAddressForPrompt
{
    <# 
    .SYNOPSIS
    由于重新计算ip地址是十分耗时的过程,建议用一个后台进程来更新
    而另一个进程直接读取后台进程算好的ip即可
        
    .DESCRIPTION
    测试方式:可以用路由器的wifi信号和手机wifi热点信号分别链接,然后分别测试刷新方法
    #>
    param (
        # $Interval = 3600 , #比如距离上次更新时间超过一小时后再更新它
        [switch]$KeepUpdate
    )
    # Update-PwshEnvIfNotYet -Mode core
    Update-PwshEnvIfNotYet -Mode Core
    # 确保需要的Json文件存在(屏蔽返回值,此前漏出的路径字符串会污染调用方输出)
    Confirm-DataJson | Out-Null

    $IpPrompt = Get-Json -Key IpPrompt -ErrorAction SilentlyContinue
    if (!$IpPrompt -and !$env:ClearIpPrompt)
    {
        # 文件缓存未命中:即时计算并直接返回(原计算完丢弃,首屏无 IP 还白白耗时;
        # 计算函数自带 60s 会话记忆 + 写文件,连续渲染不会反复枚举网卡)
        $IpPrompt = Get-IpAddressFormated -dataJson $DataJson
    }
    # 去除潜在可能出现的重复情况
    # $IpPrompt
    return $IpPrompt
}

