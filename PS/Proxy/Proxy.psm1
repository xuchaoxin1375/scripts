function  Get-ProxyEnvVarSettings
{
    if ($env:http_proxy -or $env:https_proxy)
    {
        Write-Host "`$env:http_proxy=$env:http_proxy" -ForegroundColor DarkBlue
        Write-Host "`$env:https_proxy=$env:https_proxy" -ForegroundColor DarkYellow
    }
    elseif ($env:all_proxy)
    {
        Write-Host "`$env:all_proxy=$env:all_proxy" -ForegroundColor DarkCyan
    }
    else
    {
        Write-Host 'no proxy settings'
    }
    
}
function Get-ProxySystemSettings
{
    <# 
    .SYNOPSIS
    获取系统代理设置
    .DESCRIPTION
    通过查看注册表来获取系统代理设置,可供代理环境检查
    .PARAMETER Full
    是否获取完整的注册表信息,默认只获取核心的代理设置
    #>
    param (
        [switch]$Full
    )
    $InternetProxyRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

    $info = Get-ItemProperty -Path $InternetProxyRegPath 
    $core = $info | Select-Object proxyEnable, proxyServer, ProxyOverride 
    $res = if($Full) { $info }else { $core }
    return $res

}
function Set-ProxySystemSettings
{
    <# 
    .SYNOPSIS
    设置系统代理
    .DESCRIPTION
    通过设置注册表来设置系统代理
    .PARAMETER ProxyEnabled
    是否启用代理,1表示启用,0表示禁用
    .PARAMETER Proxy
    完整的代理地址,例如http://localhost:7890
    .NOTES
    此函数允许修改系统代理的三个参数,取值例如:
    ProxyEnable   : 1
    ProxyServer   : 127.0.0.1:7890
    ProxyOverride : <local>;localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172
                    .20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*
                    ;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*
    #>
    param (
        [ValidateSet(0, 1)]$ProxyEnabled = 1,

        [parameter(Mandatory = $true)]
        $Proxy,
        $ProxyOverride = ''
     
    )
    $InternetProxyRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $InternetProxyRegPath -Name ProxyEnable -Value $ProxyEnabled
    Set-ItemProperty -Path $InternetProxyRegPath -Name ProxyServer -Value $Proxy
    if($ProxyOverride)
    {
        Set-ItemProperty -Path $InternetProxyRegPath -Name ProxyOverride -Value $ProxyOverride
    }
}
function Test-Proxy
{
    param (
        $TestLink = 'www.google.com'
    )

    $Envs = @(
    
        "`$env:http_proxy=$env:http_proxy",
        "`$env:https_proxy=$env:https_proxy"    
    )
    $Envs | Format-Table

    Write-Output "Use curl(invoke-webRequset) $TestLink to test the environment! "
    $res = Invoke-WebRequest $TestLink | Select-Object StatusCode
    
    $res | Format-Table
    if ($res.StatusCode -eq 200)
    {
        Write-Host 'proxy is available!'
    }
    
}
function Set-Proxy
{
   
    <# 
    .synopsis
    通过配置环境变量来设置powershell的代理(自动识别$env:http_proxy和$env:https_proxy)
    我们可以配置临时的环境变量,也可以配置永久的环境变量,这里用临时的就足够了

    准确的说,这里配置的是http,https两种协议的代理,并且局限于当前的powershell环境

    通过配置$env:http_proxy和$env:https_proxy,只能让cmdlet走代理,有些应用不受上述配置项目的影响,例如ping,仍然无法走代理
    而curl在powershell中invoke-webRequset,是可以走代理的

    如果想要ping也能走代理,就需要其他方案,例如cfw中安装服务模式并且启用tun;
    或者再其他设备配置代理,例如android设备安装every proxy将代理环境分享给其他设备,从底层走代理(这和局域网内系统代理有区别)
    这对于vscode中许多插件的下载加速是有用的,例如codeium插件
    .EXAMPLE
    PS> Set-Proxy On -TestProxyAvailable
    use curl(invoke-webRequset) google to test the environment! ...

    StatusCode
    ----------
        200

    proxy is available!
    $env:http_proxy=http://localhost:7897
    $env:https_proxy=http://localhost:7897

    PS🌙[BAT:80%][MEM:37.4% (11.86/31.71)GB][21:16:35]
    # [cxxu@CXXUCOLORFUL][<W:192.168.1.178>][C:\repos\scripts]{Git:main}
    PS> Set-Proxy Off

    #>
    param(
        [ValidateSet('On', 'Off')]$Status = 'On',
        #开关选项,默认不使用该选项,表示开启代理,使用该选项表示关闭代理
        $Port = '7897',
        #这里假设走本地提供的代理服务,或者localhost通常就是127.0.0.1,如果是其他服务器,可以自己修改
        $Server = 'http://localhost',
        [switch]$TestProxyAvailable

    )
    $socket = "$Server`:$port"
    # Write-Output $socket

    # 启用代理
    if ($Status -eq 'On')
    {
        
        Set-Item Env:http_proxy $socket  # 代理地址
        Set-Item Env:https_proxy $socket # 代理地址
        #也可用$env:https_proxy = $socket;$env:http_proxy = $socket代替上述set-item的用法
        #注意set-item和set-variable 是不同的

        if ($TestProxyAvailable)
        {

            Test-Proxy
        }
        return @(
    
            "`$env:http_proxy=$env:http_proxy",
            "`$env:https_proxy=$env:https_proxy"    
        )
    }
    elseif ($Status -eq 'Off' -or $status -eq '')
    {   
        Remove-Item Env:http_proxy
        Remove-Item Env:https_proxy
    }
    
}
