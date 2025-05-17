
function wifi_disconnect
{
    Write-Output '🎆🎆尝试断开当前wifi'
    netsh wlan disconnect
}
function wifiList
{
    Write-Output 'list the current wifi signals...'
    netsh wlan show networks
}
function wifiList_forceByDisconnect_SudoFirst
{
    <# 
    .synopsis
    务必使用管理员权限运行,否则结果依然不可靠!!!
    #>
    if ($(Test-AdminPermission) -eq $False)
    {
        Write-Output '🤣Ops!please try anagin by @Administrator privilege'
        return $False
    }
    else
    {
        Write-Output '😁the current environment is @Administrator privilege'
    }

    Write-Output 'get the current working NIC informations...'
    # netsh wlan show interfaces | Select-String Name
    $Name = (netsh wlan show interfaces | Select-String Name).ToString() -replace '(Name.*):(.*)', '$2'; $Name = $Name.Trim()
    Write-Output "the Name=$Name"
    Write-Output '正在关闭无线网卡(disabling the wlan interface...'
    netsh interface set interface name=$Name admin=disable
    Write-Output 'waiting for the enable operation complete...'
    #需要等待几秒,以便网卡关闭顺利执行(相对耗时,根据自己的情况来调整)
    # Start-Sleep(3)
    # timer_tips
    Write-Output 'try to enable the interface again ...'
    #重新启动WLAN网卡
    netsh interface set interface name=$Name admin=enable
    Write-Output 'waiting for the enable operation complete...'
    Start-Sleep(0.5)
    Write-Output 'list the current wifi signals...'
    # netsh wlan show networks
    netsh wlan show networks | Select-String ssid
    Write-Output 'the current connected network is:'
    netsh wlan show interfaces | Select-String ^\s*ssid
    
    ping www.baidu.com | Select-Object -First 6
}
function wifi_wlan_connect
{
    param(
        $ssid = 'ZJGSU-Student'
    )
    Write-Output "try connecting to wifi ssid:$ssid"
    netsh wlan connect name=$ssid
}
function wifi_wlan_reconnect_to
{
    param(
        $ssid = 'ZJGSU-Student'
    )
    Write-Output 'try disconnect current wifi🎈...'
    netsh wlan disconnect
    Write-Output "try connect to $ssid"
    netsh wlan connect name=$ssid
} 
function wifi_reconnect_and_test
{
    param(
        $ssid = ''
    )
    wifi_wlan_connect -ssid "$ssid"
    timer_tips 2
    NetWorkAccessbility
}