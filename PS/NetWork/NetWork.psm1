
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
    $switch = ($status -eq 'on') ? 'yes':'no'
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
    $switch = ($status -eq 'on') ? 'yes':'no'
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