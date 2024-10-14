
function Enable-SSHPubkeyAuthentication
{

    <# 
    .SYNOPSIS
    在SSH server端运行本代码
    启用公钥认证和AuthorizedKeysFile指定,从而允许授权公钥文件指定的公钥拥有者登录到ssh Server
    
    本函数需要配合其他代码才能达到预期的免密登录效果(需要客户端的公钥文件,无法整合到此脚本中)

    .DESCRIPTION
    这是一个简易版的配置sshd_config文件的脚本,如果达不到预期效果,请查阅其他文档资料
    本函数在修改原sshd_config文件前执行了备份,因此您可以找回默认值
    .NOTES
    ssh server除了运行本代码,还需要创建或修改 authorized_keys 文件(通常在ssh server端的某个用户家目录下.ssh中)
    #>
    
    $sch = 'C:\ProgramData\ssh' #sshd_config文件所在目录
    $sshd_config = "$sch\sshd_config" #原配置文件
    Get-Content $sshd_config #看一眼源文件内容
    Copy-Item $sshd_config $sch\sshd_config.bak #备份配置文件,以防万一
    
    $config = @'
    PubkeyAuthentication  yes
    AuthorizedKeysFile 	.ssh/authorized_keys
    Subsystem	 sftp 	sftp-server.exe
'@ #向sshd_config文件写入新的内容(覆盖性)
    $config > $sshd_config
    #重新检查新内容(特别是行内配置项目的空格)
    Get-Content $sshd_config 
    #重启ssh服务以生效配置
    Restart-Service sshd
}

#调用本函数
# Enable-PubkeyAuthentication

#在Client 端运行,会输出一段脚本,再复制到server端运行所得到的脚本
function Get-SSHPubKeysAdderScripts
{
    param(
        [switch]$PassThru
    )
    if (!$pubkeys)
    {
        Write-Error 'Please run pre-executing above commands first!'
        Write-Error '请先执行预执行命令,然后重试'
        return
    }
    $pubkey_content = Get-Content $pubkey #该值同上述指定


    $script = '$pubkey=' + "'$pubkey_content'" + @'

$authorized_keys='~/.ssh/authorized_keys'
if(Test-Path $authorized_keys){

type $authorized_keys #查看修改前的授权公钥文件
}else{
    new-item -Path $authorized_keys -ItemType File -force
    Write-Verbose "No $authorized_keys exist, create it!"
}
$pubkey >> $authorized_keys
type $authorized_keys #查看修改后的授权公钥文件
#重启ssh服务以生效配置
Restart-Service sshd
'@ 
    Write-Host $script -ForegroundColor Blue
    if ($PassThru)
    {

        return $script
    }
}
#调用并执行上述逻辑
# Get-SSPubKeysAdderScripts

function Get-SSHPubKeysPushScripts
{
    #适用于仅对一台主机进行免密登录的情况;否则其他方法更合适
    if (!$pubkeys)
    {
        Write-Error 'Please run pre-executing above commands first!'
        Write-Error '请先执行预执行命令,然后重试'
        return
    }

    $s = "$env:userprofile/desktop/script.txt"

    @'
    #填写server:
    #局域网内启用网络发现的话可以直接用server计算机名(server上执行hostname获取),比较方便,但是更通用的是使用server的ip地址(执行ipconfig,可能有好几个地址,找出ip地址,通常是192开头的)
    #如果是云服务器,一般具有公网ip,可以直接用ip地址即可

    $user='    ' #ssh client要以 ssh server 上的哪一个用户身份登录(例如server上有个UserDemo用户)
    $server='    '  #例如192.168.1.111或者'redmibookpc'
    $user=$user.trim()
    $server=$server.trim()
    scp $pubkey $user@${Server}:$authorized_keys

    #查看执行的scp命令行内容
    "scp $pubkey $user@${Server}:$authorized_keys"

    #重启ssh服务以生效配置
    Restart-Service sshd
'@ > $s
    notepad $s
}
# Get-SSPubKeysPushScripts

function Set-SSHServerInit
{
    <# 
    初始化ssh server 端的sshd服务
    包括初次启动服务，以及开机自启动设置,防火墙设置以及验证
    #>
    # Start the sshd service
    Start-Service sshd

    # OPTIONAL but recommended:
    Set-Service -Name sshd -StartupType 'Automatic'

    # Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
    if (!(Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Select-Object Name, Enabled))
    {
        Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    }
    else
    {
        Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
    }
}
function Set-SSHClientInit
{ 
    <# 
    .SYNOPSIS
    利用global变量,将Get-SSHPubKeysAdderScripts中想要定义的变量能够在函数内传达到函数外
    这样就整合并代替了以下命令
    Get-SSHPreRunPubkeyVarsScript|iex ;Get-SSHPubKeysAdderScripts -PassThru|scb
    
    #>
    param (
        
    )
    $authorized_keys = '~/.ssh/authorized_keys'
    $pubkeys = "$home\.ssh\id_*pub"
    #查看公钥文件
    $pubkeys = Get-ChildItem $pubkeys

    if ($pubkeys.count -lt 1)
    {
        Write-Warning 'No ssh key pairs found, please Continuewith the guide New-SSHKeyPairs !'
        New-SSHKeyPairs
        $pubkeys = Get-ChildItem $pubkeys
    }
    # $pubkeys
    #兼容多个的情况,默认选择其中的第一个
    $pubkey = $pubkeys[0]

    Set-Variable -Name authorized_keys -Value $authorized_keys -Scope Global
    Set-Variable -Name pubkey -Value $pubkey -Scope Global

    Get-SSHPubKeysAdderScripts -PassThru | Set-Clipboard
    
}
function Get-SSHPreRunPubkeyVarsScript
{
    <# 
    .SYNOPSIS
    生成一段预执行脚本,创建相关文件(公钥等)的路径变量,便于后续引用
    .DESCRIPTION
    用法说明:首先执行以下命令行
    Get-SSHPreRunPubkeyVarsScript|iex 

    #client 再执行以下两个函数中的一个即可,以获得一段创建**授权公钥文件**(authorized_keys)的脚本
    Get-SSHPubKeysAdderScripts #方案1
    # Get-SSHPubKeysPushScripts #方案2
    .EXAMPLE
    PS> Get-SSHPreRunScript|iex #将脚本输出并调用执行
    #>
    $script = @'
    #ssh Client端执行:详情查看帮助
    #使用说明和流程简述(受限于变量作用域限制难以直接整合,手动执行):
    # Get-SSHPreRunPubkeyVarsScript|iex ;Get-SSHPubKeysAdderScripts -PassThru|scb

    $authorized_keys = '~/.ssh/authorized_keys'
    $authorized_keys = "$env:userprofile/.ssh/authorized_keys"
    $pubkeys = "$home\.ssh\id_*pub"
    #查看公钥文件
    $pubkeys = Get-ChildItem $pubkeys
    $pubkeys
    #兼容多个的情况,默认选择其中的第一个
    $pubkey = $pubkeys[0]

    write-host $pubkey
    
'@
    
    Write-Host $pubkey
    # Write-Host $script -ForegroundColor Blue
    # $script | Invoke-Expression -Verbose #外部脚本无法访问
    return $script

}
# Get-SSHPreRunScript|iex #将脚本输出并调用执行

function New-SSHKeyPairs
{
    param (
        # dsa |ecdsa | ecdsa-sk | ed25519 | ed25519-sk | rsa
        [ValidateSet('dsa', 'ecdsa', 'ecdsa-sk', 'ed25519', 'ed25519-sk', 'rsa')]$TypeOfKey = 'ed25519'
    )
    ssh-keygen -t $TypeOfKey -C '838808930@qq.com'
    
}
function Deploy-SSHVersionWin32Zip
{
    <# 
    .SYNOPSIS
    为win10以上的设备部署OpenSSH(win32版本)
    虽然win32版本的openssh支持win7,但是由于win7上的powershell版本太低,所以无法执行本脚本(无法直接解压压缩包)
    因此本脚本仅支持安装了powershell 5以上的设备(仅在powershell7(支持win8.1以上)上通过测试,poweshell5尚未实际测试)
    除此之外,其他语句我在win7自带的powershell v2 上测试通过

    .DESCRIPTION   
    如果是win7使用不了问题不大,按照官方文档指南一步步执行也不难,代码片段都写好了的,只需要跳转一下路径即可
    或者使用 msi方式安装(后续可能会出GUI的安装包)
    #>
    param (
        [Alias('OpenSSHReleaseFilePath')]$file = '',
        $DefaultPath = '~/downloads/Openssh*.zip'
    )
    Write-Host 'Run this command in an elevated Powershell console!(otherwise the script will be failed to run ) !' -ForegroundColor Magenta
    $OpenSSH_home = 'C:\program files\OpenSSH'
    # 使用管理员权限powershell窗口执行以下命令#In an elevated Powershell console, run the following
    # $file = '~/downloads/Openssh*.zip' #这个目录改为您自己下载的ssh包所在路径
    if (! $file)
    {
        $file = $DefaultPath
        #统一文件名
        $file = Get-ChildItem $file; 
        $file = $file[0];
        # $OpensshZip = "$($file.Directory)/OpenSSH.zip"
        # Move-Item $file $opensshZip
    }
    else
    { 
        Write-Host 'You pass the Path of the OpenSSh Release File!'  
    }
    # 解压:
    #win7(难以在不安装其他命令的情况下直接用命令行解压zip)
    # 7z x $file -o$OpenSSH_home #如果安装了7zip

    #win10之后的系统(至少要powershell 5才支持Expand-Archive命令)
    Expand-Archive -Path $file -DestinationPath $OpenSSH_home -Verbose
    #检查是否解压成功及其解压结果
    Get-ChildItem $OpenSSH_home

    #$install_script = "$OpenSSH_Home/install-sshd.ps1"
    $install_script_dir = (Get-ChildItem "$OpenSSH_Home/Openssh-win*/")[0]
    $install_script = "$install_script_dir/install-sshd.ps1"
    powershell.exe -ExecutionPolicy Bypass -File $install_script
    #Open the firewall for sshd.exe to allow inbound SSH connections

    # New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

    #Note: New-NetFirewallRule is for Windows 2012 and above servers only. If you're on a client desktop machine (like Windows 10) or Windows 2008 R2 and below, try:
    #为了兼容性,这里用老式命令(后续的命令在win7的powershell(v2)也能够顺利执行)
    netsh advfirewall firewall add rule name=sshd dir=in action=allow protocol=TCP localport=22

    #Start sshd (this will automatically generate host keys under %programdata%\ssh if they don't already exist)

    net start sshd
    #To setup this service to auto-start:
    Set-Service sshd -StartupType Automatic

    #To config default shell (use powershell as default):
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShellCommandOption -Value '/c' -PropertyType String -Force

}

function Set-SSHDefaultShell
{
    param(
        #shell建议选择pwsh或powershell,默认为pwsh;
        [validateset('pwsh', 'pwsh_scoop', 'powershell', 'cmd')]$Shell = 'pwsh',
        $ShellFullPath #优先级高
    )
    if ($ShellFullPath)
    {
        $value = $ShellFullPath
    }
    elseif ($shell -eq 'pwsh')
    {

        #powershell 7+的安装方式有多重
        $value = 'C:\Program Files\powershell\7\pwsh.exe' 
        # $value ='C:\ProgramData\scoop\apps\powershell\current\pwsh.exe'
    }
    elseif ($shell -eq 'pwsh_scoop')
    {

        #powershell 7+的安装方式有多重
        # $value = 'C:\Program Files\powershell\7\pwsh.exe' 
        $value = 'C:\ProgramData\scoop\apps\powershell\current\pwsh.exe'
    }
    elseif ($Shell -eq 'powershell')
    {
        # $value = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        $value = 'powershell.exe' 
    }
    elseif ($Shell -eq 'cmd')
    {
        #默认行为,可以直接不修改,但是考虑到可能从其他shell更改回cmd,这里要保留
        # $value = 'cmd.exe'
        $value = 'C:\Windows\System32\cmd.exe'
    }
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $value -PropertyType String -Force
        
}