"Wi-Fi","WLAN","*EtherNet*", "*以太网*" | ForEach-Object { 
    $p1 = Get-NetIPAddress -InterfaceAlias $_ -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, @{Name = "IPv4"; Expression = { $_.IPAddress } }
    $p2 = Get-NetIPAddress -InterfaceAlias $_ -AddressFamily IPv6 -ErrorAction SilentlyContinue | Select-Object IPAddress
    $p1|Add-Member -MemberType NoteProperty -Name "IPv6" -Value $p2.IPAddress -PassThru
}