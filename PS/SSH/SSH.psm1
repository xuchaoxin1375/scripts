
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

Enable-SSHPubkeyAuthentication

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
    Write-Host $script -ForegroundColor Cyan
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
    .SYNOPSIS
    初始化ssh server 端的sshd服务
    包括初次启动服务，以及开机自启动设置,防火墙设置以及验证
    .DESCRIPTION
    使用-Confirm选项来缓解风险
    #>
    # Start the sshd service
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $ruleName = 'OpenSSH-Server-In-TCP',
        $ruleDisplayName = 'OpenSSH Server (sshd)'
    )

    if (Get-Service sshd -ErrorAction SilentlyContinue)
    {

        Start-Service sshd -Confirm:$false
        
        # OPTIONAL but recommended:
        Set-Service -Name sshd -StartupType 'Automatic' -Confirm:$false
    }
    else
    {

        Write-Warning 'sshd service does not exist! Install OpenSSH before using this function!'

        Write-Host 'for example,use scoop install openssh,follow the script:'
        Write-Host @'
scoop install openssh # -g 可以选择全局安装,需要管理员权限
$p=scoop which sshd ;$dir=Split-Path $p;cd $dir; & .\install-sshd.ps1

'@
     
        if (Get-Command scoop -ErrorAction SilentlyContinue)
        {
            #检查是否通过scoop安装了openssh，如果没有就安装
            $res = Get-Command sshd -ErrorAction SilentlyContinue
            if ($res)
            {
                $p = $res | Select-Object -ExpandProperty Source
                if ($p -like '*scoop*')
                {

                    Write-Verbose 'sshd is installed by scoop' -Verbose
                }

            }
            else
            {

                scoop install openssh # -g 可以选择全局安装,需要管理员权限
            }
            $p = scoop which sshd ; $dir = Split-Path $p; Set-Location $dir; & .\install-sshd.ps1
        }
        # return 
    }

    # Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
  

    $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue 
    $res = $rule | Select-Object Name, Enabled

    if (!$res)
    {
        Write-Output "Firewall Rule $ruleName does not exist, creating it..."
        
    }
    else
    {
        Write-Output "Firewall rule $ruleName has been created.Try reset it..."
        $continue = $PSCmdlet.ShouldProcess($ruleName, 'Reset Firewall Rule')
        if ($continue)
        {
            Remove-NetFirewallRule -Name $ruleName -Verbose
            # Set-SSHServerInit
        }
        else
        {
            return
        }
    }
    New-NetFirewallRule -Name $ruleName -DisplayName $ruleDisplayName -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Verbose
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

    Get-SSHPubKeysAdderScripts -PassThru | Set-Clipboard #将脚本内容输出到剪切板中
    Write-Warning "if the clipboard content is not complete,please re-run the command!"
    
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
    if (Get-Command $value )
    {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $value -PropertyType String -Force
    }else{
        Write-Host "Can't find $value,try another shell"
    }
        
}

function Invoke-RemoteSSH0
{
    <# 
    .SYNOPSIS
    对sshpass的一个简单包装,读取指定位置的密码文件,并执行ssh登录
    .NOTES
    优先尝试密钥免密登录,如果失败则回退到sshpass密码登录
    对于没有条件配置密钥验证的客户端设备,使用sshpass进行密码输入实现验证自动化
    #>
    [CmdletBinding()]
    param (
        # 服务器编号(可用范围取决于服务器数量)
        [parameter(Mandatory = $true)]
        $ServerID,
        $Path = "$server_config"
    )

    $servers = Get-ServerList -Skip 0
    $server = $servers[$ServerID] # 列表中的编号纠正
    $ip = $server.ip
    $user = $server.ssh.user
    $port = $server.ssh.port
    $password = $server.ssh.password
    $authority = "$user@$ip"

    # ===== 第一步：尝试密钥免密登录 =====
    # 使用 BatchMode=yes 进行探测：
    #   - 禁止任何交互式提示（密码、passphrase等）
    #   - 如果密钥认证可用，ssh 会成功连接并执行 exit，返回码为 0
    #   - 如果密钥认证不可用，ssh 会立即失败，返回码非 0
    Write-Verbose "尝试密钥免密登录 ${authority}:$port ..."
    ssh -o BatchMode=yes `
        -o StrictHostKeyChecking=no `
        -o ConnectTimeout=5 `
        -p $port `
        $authority "exit" 2>$null

    if ($LASTEXITCODE -eq 0)
    {
        # 密钥认证可用，直接使用 ssh 连接（不经过 sshpass）
        Write-Verbose "密钥认证可用,直接SSH连接"
        ssh -o StrictHostKeyChecking=no -p $port $authority
    }
    else
    {
        # 密钥认证不可用，回退到 sshpass 密码登录
        Write-Verbose "密钥认证不可用,回退到sshpass密码登录"

        if (-not (Test-CommandAvailability 'sshpass'))
        {
            Write-Error "sshpass 未安装且密钥认证不可用,无法连接"
            return
        }

        if ([string]::IsNullOrWhiteSpace($password))
        {
            Write-Error "密码为空且密钥认证不可用,无法连接"
            return
        }

        # 使用 PreferredAuthentications 强制密码认证，避免认证方式冲突
        # 使用 PubkeyAuthentication=no 明确禁用密钥认证，防止 sshpass 与密钥认证争抢
        sshpass -v -p "'$password'" ssh `
            -o StrictHostKeyChecking=no `
            -o PubkeyAuthentication=no `
            -o PreferredAuthentications=password, keyboard-interactive `
            -p $port `
            $authority
    }
}

function Invoke-RemoteSSH
{
    <# 
    .SYNOPSIS
    对sshpass的一个简单包装,读取指定位置的密码文件,并执行ssh登录
    .NOTES
    优先尝试密钥免密登录,如果失败则回退到sshpass密码登录
    对于没有条件配置密钥验证的客户端设备,使用sshpass进行密码输入实现验证自动化
    .PARAMETER Mode
    指定登录模式:
      Auto        - (默认) 先尝试密钥,失败回退sshpass
      Key         - 仅使用密钥免密登录
      Password    - 仅使用sshpass密码登录
      Interactive - 仅使用ssh原生交互式密码输入(手动输入密码)
    .PARAMETER PassDelivery
    密码传递方式:
      Env    - (默认) 环境变量传递,规避shell转义
      File   - 临时文件传递,最安全
      Direct - 命令行参数传递,密码含特殊字符时可能失败
    .EXAMPLE
    Invoke-RemoteSSH -ServerID 0 -Debug
    自动模式连接,并显示调试信息(完整命令行、密码分析等)
    .EXAMPLE
    Invoke-RemoteSSH -ServerID 2 -Mode Password -PassDelivery File -Debug
    强制sshpass密码登录,用临时文件传密码,同时查看调试信息
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingPlainTextForPassword', 'PassDelivery',
        Justification = 'This parameter is an enumeration value of the password delivery method, not the password itself')]
    param (
        [parameter(Mandatory = $true)]
        $ServerID,
        $Port = '',
        [ValidateSet('Auto', 'Key', 'Password', 'Interactive')]
        [string]$Mode = 'Auto',

        [ValidateSet('Direct', 'Env', 'File')]
        [string]$PassDelivery = 'Env',

        $Path = "$server_config"
    )

    $servers = Get-ServerList -Skip 0
    $server = $servers[$ServerID]
    $ip = $server.ip
    $user = $server.ssh.user
    $port = if($Port) { $Port }else { $server.ssh.port }
    $password = $server.ssh.password
    $authority = "$user@$ip"

    # ===== 辅助函数：输出调试信息 =====
    function Write-DebugCommand
    {
        param([string]$Label, [string[]]$CommandArgs, [string]$Note = '')

        Write-Debug ''
        Write-Debug "===== $Label ====="
        Write-Debug "目标: $authority : $port"
        Write-Debug "命令: $($CommandArgs -join ' ')"

        if ($Note)
        {
            Write-Debug "备注: $Note"
        }

        if (-not [string]::IsNullOrWhiteSpace($password))
        {
            $masked = if ($password.Length -le 2) { '***' }
            else { "$($password[0])$('*' * ($password.Length - 2))$($password[-1])" }
            Write-Debug "密码(脱敏): $masked  长度: $($password.Length)"

            $specialChars = [regex]::Matches($password, '[^a-zA-Z0-9]') |
            ForEach-Object { $_.Value } | Sort-Object -Unique
            if ($specialChars.Count -gt 0)
            {
                Write-Debug "密码含特殊字符: $($specialChars -join ' ')"
                Write-Debug "提示: 若Direct方式失败,请尝试 -PassDelivery Env 或 File"
            }
        }
        Write-Debug "===== END ====="
    }

    # ===== 密钥登录探测 =====
    function Test-KeyAuth
    {
        Write-Verbose "探测密钥免密登录 ${authority}:$port ..."
        $probeArgs = @(
            '-o', 'BatchMode=yes',
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'ConnectTimeout=5',
            '-p', $port,
            $authority,
            'exit'
        )
        Write-DebugCommand '密钥探测' (@('ssh') + $probeArgs)
        ssh @probeArgs 2>$null
        return ($LASTEXITCODE -eq 0)
    }

    # ===== 密钥登录 =====
    function Connect-ByKey
    {
        $sshArgs = @(
            '-o', 'StrictHostKeyChecking=no',
            '-p', $port,
            $authority
        )
        Write-DebugCommand '密钥登录' (@('ssh') + $sshArgs)
        ssh @sshArgs
    }

    # ===== sshpass密码登录 =====
    function Connect-BySshpass
    {
        if (-not (Test-CommandAvailability 'sshpass'))
        {
            Write-Error "sshpass 未安装,无法使用密码登录"
            return
        }
        if ([string]::IsNullOrWhiteSpace($password))
        {
            Write-Error "密码为空,无法使用sshpass登录"
            return
        }

        $sshOpts = @(
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'PubkeyAuthentication=no',
            '-o', 'PreferredAuthentications=password,keyboard-interactive',
            '-o', 'NumberOfPasswordPrompts=1',
            '-p', $port,
            $authority
        )

        $tempFile = $null

        try
        {
            switch ($PassDelivery)
            {
                'Direct'
                {
                    $sshpassArgs = @('-v', '-p', $password) + @('ssh') + $sshOpts
                    Write-DebugCommand 'sshpass密码登录(Direct)' (@('sshpass') + $sshpassArgs) `
                        '密码通过命令行参数传递,特殊字符可能被shell转义导致失败'
                    sshpass @sshpassArgs
                }
                'Env'
                {
                    $env:SSHPASS = $password
                    $sshpassArgs = @('-v', '-e') + @('ssh') + $sshOpts
                    Write-DebugCommand 'sshpass密码登录(Env)' (@('sshpass') + $sshpassArgs) `
                        '密码通过环境变量SSHPASS传递,规避shell转义问题'
                    sshpass @sshpassArgs
                }
                'File'
                {
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    [System.IO.File]::WriteAllText($tempFile, $password)
                    if ($IsLinux -or $IsMacOS) { chmod 600 $tempFile }
                    $sshpassArgs = @('-v', '-f', $tempFile) + @('ssh') + $sshOpts
                    Write-DebugCommand 'sshpass密码登录(File)' (@('sshpass') + $sshpassArgs) `
                        "密码通过临时文件传递: $tempFile"
                    sshpass @sshpassArgs
                }
            }
        }
        finally
        {
            if ($env:SSHPASS) { Remove-Item Env:SSHPASS -ErrorAction SilentlyContinue }
            if ($tempFile -and (Test-Path $tempFile))
            {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # ===== 交互式密码登录 =====
    function Connect-ByInteractive
    {
        $sshArgs = @(
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'PubkeyAuthentication=no',
            '-o', 'PreferredAuthentications=password,keyboard-interactive',
            '-p', $port,
            $authority
        )
        Write-DebugCommand '交互式密码登录' (@('ssh') + $sshArgs) `
            '将由ssh直接提示输入密码,不经过sshpass'
        ssh @sshArgs
    }

    # ===== 主逻辑 =====
    Write-Debug "Mode=$Mode  PassDelivery=$PassDelivery"

    switch ($Mode)
    {
        'Key'
        {
            Write-Verbose "模式: 仅密钥登录"
            Connect-ByKey
        }
        'Password'
        {
            Write-Verbose "模式: 仅sshpass密码登录 (方式: $PassDelivery)"
            Connect-BySshpass
        }
        'Interactive'
        {
            Write-Verbose "模式: 交互式手动输入密码"
            Connect-ByInteractive
        }
        default
        {
            Write-Verbose "模式: 自动(先密钥后密码)"
            if (Test-KeyAuth)
            {
                Write-Verbose "密钥认证可用,直接SSH连接"
                Connect-ByKey
            }
            else
            {
                Write-Verbose "密钥认证不可用,回退到sshpass密码登录"
                Connect-BySshpass
            }
        }
    }
}


function Add-SSHkeyOnHost
{
    <# 
    .SYNOPSIS
    将当前用户SSH公钥添加到指定主机的authorized_keys文件中
    .DESCRIPTION
    使用此函数添加不会覆盖掉原文件,可以在不同设备上使用此函数向同一个服务器添加公钥
    .NOTES
    为了避免之前不规范添加文件末尾可能缺少换行符,可以使用 -PrefixNextLine 参数在公钥周围添加换行符,
    保证防止和之前的添加的公钥粘连
    .EXAMPLE
    PS> Add-SSHkeyOnHost -ComputerName 192.168.1.1 -UserName root
    #>
    [CmdletBinding()]
    param(
        $ComputerName,
        $UserName = 'root',
        $Type = 'ed25519',
        $Port = 22,
        [Alias('Winodws')][switch]$RemoteOSIsWindows,
        # 尽可能跳过ssh-keygen的生成确认环节.
        [switch]$Force,
        [switch]$PrefixNextLine
    )
    $authority = "$UserName@$ComputerName" 
    $keypath = "~/.ssh/id_$Type"
    $pubkey = Get-Content "${keypath}.pub"
    # START (密钥检查,如有需要生成密钥)
    if(Test-Path $keypath)
    {
        Write-Verbose "已存在${type}密钥"
    }
    else
    {
        if($Force)
        {

            ssh-keygen -t $Type -C "$env:COMPUTERNAME" -N '' -f "$HOME\.ssh\id_$Type" -q
        }
        else
        {
            
            ssh-keygen -t $Type -C "$env:COMPUTERNAME " # 或者用计算机名代替邮箱
        }
    }
    # END
    $pubkey = "$pubkey`n"
    if ($PrefixNextLine)
    {
        $pubkey = "`n$pubkey"
    }
    Write-Verbose "本次将添加公开密钥内容[$pubkey]到服务器[$ComputerName]($authority),by port=$port"
    if ($RemoteOSIsWindows)
    {
        Write-Warning "确保被链接服务器是windows系统(并且不是链接到wsl中且存在powershell),否则推送语句失效!"
        # $cmd="ssh $authority powershell -Command mkdir -p ~/.ssh ; Write-Output '${pubkey}' >> ~/.ssh/authorized_keys -v -p $port"
        # Write-Host "cmd=[$cmd]"
        ssh $authority -v -p $port "powershell.exe -noprofile -Nologo -NonInteractive -Command `" mkdir -p ~/.ssh ; echo '${pubkey}' >> ~/.ssh/authorized_keys`"" 
    }
    else
    {
        
        Write-Warning "确保被链接服务器是windows之外的系统(linux等系统),否则推送语句失效!"
        # && 针对于linux系统(windows不适用),这里使用';'代替'&&'
        ssh $authority -v -p $port "mkdir -p ~/.ssh && echo '${pubkey}' >> ~/.ssh/authorized_keys" 
    }
    # 初次运行需要输入服务器ssh对应user用户的密码
}

