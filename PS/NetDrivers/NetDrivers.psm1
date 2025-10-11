
function Get-PSNetDriveList
{
    <# 
    .SYNOPSIS
    封装Get-PSDrive获取网络驱动器列表,但是并不如net use来的直观,而且对于挂载的某些网络磁盘会暂时性卡死,导致响应速度不出来或者要等很久

    #>
    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot -like '\\*' }
}

function Mount-AlistLocalhostDrive
{
    param(
        $DriveLetter = 'L',
        # Retry Interval if mapping failed;if Successed,this value will not be used
        $Interval = 8
    )
    #根据需要自行修改盘符和端口号
    # net use W: http://localhost:5244/dav /p:yes /savecred
    Mount-NetDrive -host 'localhost' -DriveLetter $DriveLetter -Port '5244'

    if (!$?)
    {

        Write-Host 'Mapping failed, wait a while before mapping. You can check if the Alist service is working properly first' -ForegroundColor Red
        # Start-AlistHomePage
        Write-Host "try again after ${Interval}s... enter stop auto retry! "
        Start-Sleep $Interval
        #递归调用来重试
        Mount-AlistLocalhostDrive

    }
    #检查映射结果
    net use
    
}
function Mount-NetDrive
{
    <# 
    .SYNOPSIS
    挂载http链接形式的网络驱动器,通常用于局域网挂载
    这里是对net use 的一个封装,而Powershell 的New-PSDrive命令并不那么好用,链接识别有一定问题和局限性
    如果是挂载Smb共享文件夹的话，还可以直接用New-SmbMapping命令(这里密码是明文密码,所以隐蔽性不足,
    且挂载后需要重启资源管理器),其次再考虑New-PsDrive

    .DESCRIPTION
    为了方便省事,这里记住密码，不用每次都输入密码
    net use W: "http://$Server:5244/dav" /p:yes /savecred 
    目前已知New-PSDrive有挂载问题是,报错如下
    New-PSDrive: The specified drive root "\\192.168.1.178:5244\dav" either does not exist, or it is not a folder.

    .EXAMPLE
    挂载Webdav为W盘，Server使用ip地址,不使用User参数(等待net use 主动向你索取凭证),而使用Remember 参数记住凭证
    PS C:\Users\cxxu\Desktop> Mount-NetDrive -Server 192.168.1.198 -DriveLetter W -WebdavMode -Port 5244  -Remember
    Enter the user name for '192.168.1.198': admin
    Enter the password for 192.168.1.198:
    The command completed successfully.

    Drive W: successfully mapped to http://192.168.1.198:5244/dav
    New connections will be remembered.


    Status       Local     Remote                    Network

    -------------------------------------------------------------------------------
    

    OK           N:        \\cxxuredmibook\share     Microsoft Windows Network
    Disconnected Q:        \\redmibookpc\share       Microsoft Windows Network
                W:        \\192.168.1.198@5244\dav  Web Client Network
    The command completed successfully.
    .EXAMPLE
    #挂载SMB共享文件夹,使用Server主机名,直接使用User参数指定用户名
   PS C:\Users\cxxu\Desktop> Mount-NetDrive -Server cxxuredmibook -DriveLetter N -SmbMode
 -User smb -Verbose
    Enter password For smb: *
    Enter shared folder(Directory) BaseName(`share` is default):
    VERBOSE: \\cxxuredmibook\share
    The command completed successfully.

    Drive N: successfully mapped to \\cxxuredmibook\share
    New connections will be remembered.


    Status       Local     Remote                    Network

    -------------------------------------------------------------------------------
    

    OK           N:        \\cxxuredmibook\share     Microsoft Windows Network
    Disconnected Q:        \\redmibookpc\share       Microsoft Windows Network
    The command completed successfully.

    .EXAMPLE
    #挂载Webdav为W盘,Server使用ip地址,使用User参数直接指定用户名
    PS C:\Users\cxxu\Desktop> Mount-NetDrive -Server 192.168.1.198 -DriveLetter W -WebdavMode -Port 5244 -User admin
    Enter password For admin: ****
    The command completed successfully.

    Drive W: successfully mapped to http://192.168.1.198:5244/dav
    New connections will be remembered.


    Status       Local     Remote                    Network

    -------------------------------------------------------------------------------
    

    OK           N:        \\cxxuredmibook\share     Microsoft Windows Network
    Disconnected Q:        \\redmibookpc\share       Microsoft Windows Network
                W:        \\192.168.1.198@5244\dav  Web Client Network
    The command completed successfully.
    .EXAMPLE
    挂载一个smb文件夹,并且记住凭证
    PS> Mount-NetDrive -Server CxxuColorful -DriveLetter X -SmbMode -Remember
    Enter shared folder(Directory) BaseName(`share` is default):
    \\CxxuColorful\share
    命令成功完成。

    Drive X: successfully mapped to \\CxxuColorful\share
    会记录新的网络连接。


    状态       本地        远程                      网络

    -------------------------------------------------------------------------------
    不可用       F:        \\Front\share             Microsoft Windows Network
    OK           X:        \\CxxuColorful\share      Microsoft Windows Network
    .NOTES
    挂载共享文件(smb)可以直接用powershell的New-SmbMapping命令
    PS C:\repos\configs> New-SmbMapping -LocalPath 'F:' -RemotePath '\\User-2023GQTEXW\Share' -Persistent 1

    Status Local Path Remote Path
    ------ ---------- -----------
    OK     F:         \\User-2023GQTEXW\Share
    #>
    [CmdletBinding()]
    param(
        # 可以用于webdav链接中ip地址填充,也可以用于共享文件夹
        # 比如用于共享文件夹的链接,比如\\192.168.1.178\share,或者在启用网络发现的情况下使用计算机名来构建访问链接,例如:\\User-2023GQTEXW\Share
        [string]$Server = 'localhost',
        
        # 挂载的分区盘符
        [string]$DriveLetter = 'M',

        [parameter(ParameterSetName = 'CompleteUri')]
        [string]$CompleteUri = '',

        # 挂载模式(对于smb模式，可以用powershell的New-SmbMapping函数)
        # [ValidateSet('Smb', 'Webdav', 'Others')]$Mode = 'Smb',
        [parameter(ParameterSetName = 'Smb')]
        [switch]$SmbMode,
        [parameter(ParameterSetName = 'WebDav')]
        [switch]$WebdavMode,
        [parameter(ParameterSetName = 'Others')]
        [switch]$OthersMode,


        # Alist 默认端口库
        [parameter(ParameterSetName = 'WebDav')]
        [string]$Port = '5244',
        # 用户名是可选的,如果您使用匿名登录不上,才考虑使用此参数,密码会在执行后要求你填入,这样密码不会明文显示在命令行中
        [string]$User = '',
        
        #是否记住凭证(和 -User 一起使用时可能会有冲突!)
        [switch]$Remember,

        [switch]$Persistent

    )

    # Write-Host "Net Drive Mode: $Mode" -ForegroundColor Magenta

    $credString = ''#默认没有凭证,匿名访问/挂载
    # 如果提供了用户,则要求用户输入密码(这样密码不会在命令行中明文显示)
    if ($User)
    {
        # 利用powershell的凭据获取惯例用法
        $password = Read-Host "Enter password For $User" -AsSecureString #前面已经有$User参数,这里只需要再读取密码
        #将$User和获取的$password组合起来转换为PSCredential
        $credential = New-Object System.Management.Automation.PSCredential ($User, $Password)

        #考虑到某些命令行工具无法直接使用PsCredential,所以要利用转换方法把凭据转换为明文来引用(但是不打印出来)
        $plainCred = $credential.GetNetworkCredential()

        #组建成凭据明文字符串,以便net use等命令行使用
        $credString = $plainCred.UserName + ' ' + $plainCred.Password

        #  $credString
        #  $plainCred.User $plainCred.Password
        # return $credential
    }
    # 构造URI(if语句可以类似于三元运算符来使用)
    $Uri = if ($CompleteUri)
    {
        $CompleteUri 
    }
    else
    {  
        
        if ($SmbMode)
        {
            $ShareDir = Read-Host 'Enter shared folder(Directory) BaseName(`share` is default)'
            $ShareDir = if ($ShareDir) { $ShareDir } else { 'share' }
            "\\${Server}\$ShareDir" 
            
        }
        elseif ($WebdavMode)
        {
            "http://${Server}:${Port}/dav"
        }
        elseif ($OthersMode)
        {
            'otherMode'
        }
        
    } 

    $Uri 

    # 构造net use命令参数
    $netUseArguments = "${DriveLetter}: $uri"
    #考虑到可能需要用户名和密码,必要时添加凭据字符串
    if ($credString -ne '')
    {
        $netUseArguments += " /user:$credString"
    }

    # 是否记住凭据
    if ($Remember)
    {
        $netUseArguments += '  /savecred'
    }
    if ($Persistent)
    {
        $netUseArguments += '  /persistent:yes'
    }

    # 映射网络驱动器
    $expression = "net use $netUseArguments"
    #  'check expression:' 
    #  $expression  #正常的连接形如:net use N: \\cxxuredmibook\share /user:smb 1

    # return 


    Invoke-Expression $expression

    # 检查映射结果
    if ($LASTEXITCODE -eq 0)
    {
        Write-Host "Drive ${DriveLetter}: successfully mapped to $uri"
    }
    else
    {
        Write-Error "Failed to map drive ${DriveLetter}: with error code $LASTEXITCODE"
    }

    # 显示现有映射
    net use
}




function Start-AlistHomePage
{
    Start-Process 'http://localhost:5244'
    #也可以用curl http://localhost:5244 |select -head 5 来检查服务是否启动 
}
function Start-AliyundrivePage
{
    param(
        $cloudDrive = 'AliyunDrive'
        #default value is `AliyunDrive`,other cloud driver may be BaiduDrive and so on
    )
    Start-Process "http://localhost:5244/$cloudDrive" 
}

function Remove-NetDrive
{
    <#
    .SYNOPSIS
    This function removes a network drive mapping.

    .DESCRIPTION
    This function uses the `net use` command to remove a network drive mapping. The drive letter to be removed is specified as a parameter. If no drive letter is provided, the default is 'M'.

    .PARAMETER DriverLetter
    The drive letter of the network drive to be removed. Default is 'M'.


    .EXAMPLE
    Remove-NetDrive -DriverLetter 'Z'

    This command removes the network drive mapping associated with the drive letter 'Z'.

    .NOTES
    This function does not require administrative privileges to remove a network drive mapping.
    #>
    param (
        $DriverLetter = 'M'
    )
    net use "${DriverLetter}:" /delete
    #检查移除结果
    net use
}


function Start-ChfsServer
{
    [CmdletBinding()]
    param (
        [validateset('Vbs', 'Pwsh')]$StartOptoin = 'Pwsh'
    )
    
    if (!$chfs_home)
    {
        <# Action to perform if the condition is true #>
        Update-PwshEnvIfNotYet -Mode Env
    }
    # 切换到chfs的根目录
    Set-Location $chfs_home
    $chfs = "$chfs_home\chfs.exe"
    
    Write-Verbose 'Starting chfs... '
    Write-Verbose $chfs 

    if ($StartOptoin -eq 'Vbs')
    {

        #方法1:使用vbs脚本启动chfs服务
        '.\startup.vbs' | Invoke-Expression
    }
    else
    {

        #方法2:使用pwsh脚本启动chfs服务
    
        # 需要将$chfs_home配置到Path中(使用powershell别名不管用),或者使用绝对路径
        # Start-Process -WindowStyle Hidden -FilePath chfs -ArgumentList "-file $chfs_home\chfs.ini" -PassThru
    
        Start-ProcessHidden -File $chfs -ArgumentList "-file $chfs_home\chfs.ini" 

    }
    # 等待1秒让服务起来后检查
    Start-Sleep 1
    $p = Get-Process -Name chfs -ErrorAction SilentlyContinue
    return $p

}
function Start-AlistServer
{
    [CmdletBinding()]
    param (
        [validateset('Vbs', 'Pwsh')]$StartOptoin = 'Pwsh'
    )
    Update-PwshEnvIfNotYet  
    # 进入到alist的根目录,在根目录作为工作目录启动alist服务👺
    Set-Location $alist_home
    

    if ($StartOptoin -eq 'Vbs')
    {
        # 方案1：使用vbs脚本启动alist服务,安全性较差,适用于老系统(比如win10以前,win11之后的某个版本将不在支持vbs)
        '.\startup.vbs' | Invoke-Expression
    }
    else
    {

        #方案2:使用pwsh脚本启动alist服务
        Start-ProcessHidden -File './alist.exe' -ArgumentList 'server' #依赖于前面跳转到alist家目录动作配合,不能单独直接使用
        # 这里为了避免启动其他目录下的`alist`,所以用了`./alist`来强调指定的目录下的alist.exe
        Write-Verbose 'alist server start by pwsh process!'
        Start-Process -WindowStyle Hidden -File 'alist.exe' -ArgumentList 'server' #日志文件请根据alist config.json中的配置提示位置
         

        # 等待一秒后检查进程服务是否启动(调用者shell会话中检查)
    }
    Start-Sleep 1
    $p = Get-Process alist -ErrorAction 'SilentlyContinue' 
    # 可以直接将进程返回(如果创建成功的话)
    return $p
}


function Start-Aria2Rpc
{ 
    <# 
    .SYNOPSIS
    启动Aria2 rpc服务
    .DESCRIPTION
    如果启动成功,会返回进程信息,否则返回空
    如果启动失败,则通过直接执行aria2c --conf-path=$ConfPath来检查是否是配置文件存在问题导致启动失败
    .EXAMPLE
    PS> aria2rpc
    Environment  have been Imported in the current powershell!

    NPM(K)    PM(M)      WS(M)     CPU(s)      Id  SI ProcessName
    ------    -----      -----     ------      --  -- -----------
        5     0.49       2.39       0.00   11048   1 aria2c

    #>
    [CmdletBinding()]
    param (
        $ConfPath = ''
    )
    #debuging
    $log = 'C:\Log\log.txt'
    if (-not (Test-Path $log))
    {

        New-Item -Path $log -ItemType File -Force
    }
    Update-PwshEnvIfNotYet
    # 进入到aria2的根目录(使得兼容性更强,包括计划任务system 也可以通过start-processHidden来启动)
    Set-Location $aria2_home
    # $aria2conf = '~/.aria2/aria2.conf'

    if (!$ConfPath)
    {
        $ConfPath = "$configs\aria2.conf"
    }
    # "ConfPath:$ConfPath">>$log
    # $s = { aria2c --conf-path=$ConfPath }
    
    # 启动Aria2 rpc引擎
    #检查默认下载目录由配置文件指定
    # Write-PsDebugLog -FunctionName 'Start-Aria2Rpc' -ModuleName 'NetDrive' -comment "before start aria2c $ConfPath []"
    "$PsEnvMode">$log

    # Get-Command aria2* >> $log
    # $aria2 = 'aria2c' #'C:\exes\aria2\aria2c.exe' #如果直接用字符串`aria2c`会报错(工作目录找不到aria2c而报错),通过重定向输出来检查这一点
    Start-ProcessHidden -FilePath aria2c -ArgumentList "--conf-path=$ConfPath" -Verbose:$VerbosePreference -PassThru *>> $log
    # Start-ProcessHidden -scriptBlock { Update-PwshEnvIfNotYet; aria2c --conf-path=$ConfPath } -PassThru *>> $log
    # Write-PsDebugLog -FunctionName 'Start-Aria2Rpc' -ModuleName 'NetDrive' -comment 'after start aria2c'  -LogFilePath 'C:\Log\log.txt'
    # 检查相关进程是否存在
    # Get-Process aria2*
    $p = Get-Process aria2* -ErrorAction 'SilentlyContinue' 

    return $p
}