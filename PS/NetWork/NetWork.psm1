
function Set-NetworkDiscovery
{
    <#
    .SYNOPSIS
        设置网络网络发现
    .EXAMPLE
        PS> Set-NetworkDiscovery -state on
    .EXAMPLE
        PS> Set-NetworkDiscovery -state off
    #>
    
    param(
        [ValidateSet('on', 'off')]
        [string]
        $status = 'on'
    )
    if ($status -eq 'on') { $switch = 'yes' } else { $switch = 'no' }
    # Write-Host $switch

    #对于英文系统
    netsh advfirewall firewall set rule group="Network Discovery" new enable=$switch 
    #对于中文系统
    netsh advfirewall firewall set rule group="网络发现" new enable=$switch 

}

function Set-NetworkFileAndPrinterSharing
{
    <#
    .SYNOPSIS
        设置文件和打印机共享
    .EXAMPLE
        PS> Set-NetworkFileAndPrinterSharing -state on
    .EXAMPLE
        PS> Set-NetworkFileAndPrinterSharing -state off
    #>
    
    param(
        [ValidateSet('on', 'off')]
        [string]
        $status = 'on'
    )
    if ($status -eq 'on') { $switch = 'yes' } else { $switch = 'no' }
    # Write-Host $switch
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=$switch
    netsh advfirewall firewall set rule group="文件和打印机共享" new enable=$switch

}

function Get-SmbSessionMainInfo
{
    param (
        
    )
 

    Get-SmbSession | Select-Object ClientComputerName, ClientUserName
    
}

function pushToAndroid
{
    param (
        $path,
        $DestinationPath_opt = "$downloadM"
    )
    adb push $path $DestinationPath_opt
}

function upload_pubKey
{
    param(
        $source = "$env:sshPub"
        , 
        $user_host = "cxxu@$AlicloudServerIp"
        ,
        $target = '~/.ssh/authorized_keys'
    )
    scp $source "$user_host`:$target"
}


function https3w_start
{
    param(
        $domain
    )
    Start-Process $domain
}


function Set-HostsFile
{
    Write-Host 'entering administrator mode...'
    Write-Host 'try to open hosts file(by vscode...)'
    # Get-AdministratorPrivilege
    sudo c $hosts
}

function NetWorkAccessbility
{
    curl_b -v $baidu
}
function curlBD
{
    curl_b $baidu
}
function pingBD
{
    param (

        $site = $baidu
    )
    ping $site
}
function pingGG
{
    param (
        $domain = $google
    )
    Write-Host $domain
    ping $domain
}

function uploadPicMarkdown
{
    param (
        $path = ' '
    )
    if ($path -eq ' ')
    {
        Write-Host 'try to upload pictures from clipboard(the default behaviour)'
    }
    $resLink = picgo upload $path | Select-Object -Last 1 
    # Set-Clipboard $resLink
    $markdownPicLink = "![🥰$(Get-Date)]($resLink)"
    Write-Host $markdownPicLink
    Set-Clipboard $markdownPicLink
    Write-Host "🎶🎶🎶`n$resLink"
}

function Get-IPAddressMainInfo
{
    <# 
    .SYNOPSIS
    按网卡分组列出计算机上的IP地址,一般一个网卡上有一个ipv4地址和一个ipv6地址,但可能更多
    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> Get-NetIPAddress |group -Property InterfaceAlias|sort Name

    Count Name                      Group
    ----- ----                      -----
        2 Bluetooth Network Connec… {fe80::6692:33af:a97a:fe2%7, 169.254.134.242}
        2 Ethernet                  {fe80::88bf:2fcf:a049:335c%22, 169.254.21.122}
        2 Local Area Connection* 1  {fe80::5006:155d:e384:f3e2%6, 169.254.136.6}
        2 Local Area Connection* 2  {fe80::4569:8dca:ec45:64c0%17, 192.168.137.1}
        2 Loopback Pseudo-Interfac… {::1, 127.0.0.1}
        2 Tailscale                 {fe80::2f4c:2c3e:13e9:1c81%5, 169.254.83.107}
        2 vEthernet (Default Switc… {fe80::2783:ed62:4b9a:c308%24, 172.27.176.1}
        2 VMware Network Adapter V… {fe80::c538:5a79:d7bf:35de%4, 192.168.174.1}
        2 VMware Network Adapter V… {fe80::6a9a:3215:bace:cd81%20, 192.168.37.1}
        4 Wi-Fi                     {fe80::602a:eb89:bc9c:22bf%3, 240e:379:3fa1:100:a548:a4e1:78ca:27d0, 240e:379:3fa1:100:38d1:ed54:77d5:9710, 192.168.1.178}
    #>
    Get-NetIPAddress | Group-Object -Property InterfaceAlias | Sort-Object Name
}

function Get-IPAddressOfPhysicalAdapter
{
    <#
    .SYNOPSIS
    列出计算机上的物理网络适配器的IP地址(包括传统的Ethernet和Wi-Fi网络适配器)
    .DESCRIPTION
    中英文系统下两类适配器的名字有所不同,ethernet对应以太网,而wi-fi对应WLAN
    通常一台笔记本至少有一个网络适配器,如果是轻薄本可能只有一个无线网络适配器,如果有2个适配器,那么他们也可以同时联网
    但是一般只有其中的一个可以进行网络传输,另一个几乎闲着(例如windows,优先使用跃点数少的那一条网卡线路,而不是连接速率最快的那一条)
    调节跃点数可能可以均衡连个网卡;
    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> Get-IPAddressOfPhysicalAdapter -AddressFamily IPv4

    InterfaceAlias IPAddress
    -------------- ---------
    Ethernet       169.254.21.122
    Wi-Fi          192.168.1.178

    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> Get-IPAddressOfPhysicalAdapter -AddressFamily IPv6

    InterfaceAlias IPAddress
    -------------- ---------
    Ethernet       fe80::88bf:2fcf:a049:335c%22
    Wi-Fi          fe80::602a:eb89:bc9c:22bf%3
    Wi-Fi          240e:379:3fa1:100:a548:a4e1:78ca:27d0
    Wi-Fi          240e:379:3fa1:100:38d1:ed54:77d5:9710
    #>
    param(
        [validateset('IPv4', 'IPv6')]$AddressFamily = 'IPv4'
    )
    foreach ($name in @('ethernet', 'wi-fi', 'WLAN', '以太网'))
    {
        Get-NetIPAddress -InterfaceAlias $name -AddressFamily $AddressFamily `
            -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, IPAddress
    }
}
function Get-NetAdapterMainInfo
{
    <# 
    .SYNOPSIS
    获取当前计算机上的网卡的主要信息
    .DESCRIPTION
    您或许想要排序,这没问题,只需要后面用管道符号|引入Sort 命令即可

    .EXAMPLE
    
    PS C:\repos\scripts> Get-NetAdapterMainInfo|Sort-Object status -Descending

    Name                          InterfaceDescription                       MacAddress        Status
    ----                          --------------------                       ----------        ------
    Local Area Connection* 2      Microsoft Wi-Fi Direct Virtual Adapter #2  32-F6-EF-07-2E-61 Up
    Tailscale                     Tailscale Tunnel                                             Up
    VMware Network Adapter VMnet1 VMware Virtual Ethernet Adapter for VMnet1 00-50-56-C0-00-01 Up
    VMware Network Adapter VMnet8 VMware Virtual Ethernet Adapter for VMnet8 00-50-56-C0-00-08 Up
    Wi-Fi                         Intel(R) Wi-Fi 6E AX211 160MHz             30-F6-EF-07-2E-61 Up
    Bluetooth Network Connection  Bluetooth Device (Personal Area Network)   30-F6-EF-07-2E-65 Disconnected
    Ethernet                      Realtek PCIe GbE Family Controller         D4-93-90-34-16-69 Disconnected
    #>
    Get-NetAdapter | Select-Object Name, InterfaceDescription, MacAddress, Status | Sort-Object name
}

function code_proxy
{
    $dirName = '.'
    code $dirName --proxy-pac-url=http://127.0.0.1:1083/proxy.pac
}
# function cdb{
#     cd -
# }



# function predict {
#     Set-PSReadLineOption -PredictionSource History # 设置预测文本来源为历史记A
# }
