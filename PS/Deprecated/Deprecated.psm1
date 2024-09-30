
function Deploy-StartupSoftwareAndServices-Deprecated
{
    <# 
    .SYNOPSIS
    部署开机启动
    #>
    param (
        [ValidateSet('user', 'system')]$Scope = 'user',
        [switch]$Force
    )
    $p = ''
    switch ($Scope)
    {
        'user' { $p = "$env:Appdata\Microsoft\windows\Start Menu\programs\Startup" }
        'system' { $p = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp' }
        Default {}
    }

    $p = Join-Path -Path $p -ChildPath 'startup.lnk'
    $target = "$PSScriptRoot\..\Startup\Startup.lnk"
    # 如果系统只有一个分区时,可以用硬链接(优先)
    try
    {

        New-Item -ItemType HardLink -Path $p -Value $target  
    }
    catch
    {

        #否则使用复制配置文件的方式来实现(发生变更时需要重新部署(调用本函数))
        Copy-Item $target $p -Verbose -Force
    }
}

function Restart-Process-Deprecated
{
   
    <#
.SYNOPSIS
    重启指定的进程。
    这是一个啰嗦的版本,作为反面教材
.DESCRIPTION
    该函数用于重启指定的进程。它可以根据进程的名称、ID 或直接传递的进程对象来停止和重新启动进程。
    特别适用于需要重启 Windows 资源管理器 (explorer.exe) 的情况。

.PARAMETER Name
    要重启的进程的名称（不包括扩展名）。例如：'explorer'。

.PARAMETER Id
    要重启的进程的 ID。

.PARAMETER InputObject
    要重启的进程对象。

.EXAMPLE
    Restart-Process -Name 'explorer'
    该示例将重启 Windows 资源管理器。

.EXAMPLE
    Restart-Process -Id 1234
    该示例将重启进程 ID 为 1234 的进程。

.EXAMPLE
    Get-Process -Name 'explorer' | Restart-Process
    该示例将重启通过管道传递的进程对象。

.NOTES
    作者: cxxu1375
#>

    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param (
        [Parameter(ParameterSetName = 'ByName', ValueFromPipelineByPropertyName = $true, Mandatory = $true, Position = 0, HelpMessage = 'Enter the name of the process to restart.')]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName = $true, Mandatory = $true, Position = 0, HelpMessage = 'Enter the ID of the process to restart.')]
        [int]$Id,

        [Parameter(ParameterSetName = 'ByInputObject', Mandatory = $true, ValueFromPipeline = $true, HelpMessage = 'Enter the process object to restart.')]
        [System.Diagnostics.Process]$InputObject
    )

    process
    {
        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'ByName')
            {
                # 获取并停止进程通过名称
                $process = Get-Process -Name $Name -ErrorAction Stop
                Stop-Process -Name $Name -Force -ErrorAction Stop
                
                # 重启进程
                Start-Process -FilePath "$Name"
                
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ById')
            {
                # 通过ID获取进程
                $process = Get-Process -Id $Id -ErrorAction Stop
                Stop-Process -Id $Id -Force -ErrorAction Stop
                
                # 重启进程
                Start-Process -FilePath "$($process.Path)"
                
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ByInputObject')
            {
                # 停止传递的进程对象
                Stop-Process -Id $InputObject.Id -Force -ErrorAction Stop
               
                
                # 重启进程
                Start-Process -FilePath "$($InputObject.Path)"
                
            }
            Write-Verbose "Performing the operation 'restart-process' on target '$($process.Path)'"
        }
        catch
        {
            Write-Error "Failed to restart process. $_"
        }
    }
}

function Get-MemoryCapacity-Deprecated
{
    [CmdletBinding()]
    param (
        [ValidateSet('B', 'KB', 'MB', 'GB', 'TB')]
        [string]$Unit = ''
    )

    # 获取总内存
    $totalMemory = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory

    # 根据指定的单位计算内存大小
    switch ($Unit)
    {
        'B' { $memoryValue = $totalMemory; $memoryUnit = 'B' }
        'KB' { $memoryValue = [math]::Round($totalMemory / 1KB, 2); $memoryUnit = 'KB' }
        'MB' { $memoryValue = [math]::Round($totalMemory / 1MB, 2); $memoryUnit = 'MB' }
        'GB' { $memoryValue = [math]::Round($totalMemory / 1GB, 2); $memoryUnit = 'GB' }
        'TB' { $memoryValue = [math]::Round($totalMemory / 1TB, 2); $memoryUnit = 'TB' }
        default
        {
            # 默认以表格形式输出所有单位
            $memoryInBytes = $totalMemory
            $memoryInKB = [math]::Round($totalMemory / 1KB, 2)
            $memoryInMB = [math]::Round($totalMemory / 1MB, 2)
            $memoryInGB = [math]::Round($totalMemory / 1GB, 2)
            $memoryInTB = [math]::Round($totalMemory / 1TB, 2)
            
            $outputTable = @(
                @{Value = $memoryInBytes; Unit = 'B' },
                @{Value = $memoryInKB; Unit = 'KB' },
                @{Value = $memoryInMB; Unit = 'MB' },
                @{Value = $memoryInGB; Unit = 'GB' },
                @{Value = $memoryInTB; Unit = 'TB' }
            ) | ForEach-Object { [PSCustomObject]$_ }

            # 输出表格
            $outputTable | Format-Table -AutoSize
            return
        }
    }

    # 输出指定单位的内存大小
    [PSCustomObject]@{
        Value = $memoryValue
        Unit  = $memoryUnit
    }
}

function Set-ProgramToOpenWithList-deprecated
{
    <# 
    .SYNOPSIS
    Set the Program to the Open with Program list or the Program list popup when the user want to open a file with a strange file extension
    The administrator permission is required.
    .NOTES
    The function is not to set the default apps to open a specific file 
    but this function will help the action which set the defualt app to open the files with a specific extension more convenient
    .EXAMPLE
    #⚡️[C:\repos\scripts]
    PS> Set-ProgramToOpenWithList -Program pwsh7 -Path $pwsh7_home\pwsh.exe

        Hive: \HKEY_CLASSES_ROOT\Applications\pwsh7\shell\open

    Name                           Property
    ----                           --------
    command                        (default) : "C:\Program Files\powershell\7\pwsh.exe" "%1"

    #>
    param (
        # 程序名字
        [Parameter(Mandatory = $true)]
        $Program,
        # [Parameter(Mandatory = $true)]
        # $ProgramNameInList,
        #程序所在路径
        [Parameter(Mandatory = $true)]
        $Path

    )
    
    $regPath = "Microsoft.PowerShell.Core\Registry::\HKEY_CLASSES_ROOT\Applications\$Program\shell\open\command "
    New-Item $regPath -Value "`"$Path`" `"%1`"" -Force
}
function Deploy-SmbSharing-Deprecated
{

    
    <# 
    .SYNOPSIS
    #功能:快速创建一个可用的共享文件夹,能够让局域网内的用户访问您的共享文件夹
    # 使用前提要求:需要使用管理员权限窗口运行powershell命令行窗口
    .EXAMPLE
    # 指定共享名称为ShareDemo，其他参数默认:共享目录为C:\Share，权限为Change，用户为ShareUser，密码为1
    PS> Deploy-SmbSharing -ShareName ShareDemo -SmbUser ShareUser -password 1
    .NOTES
    访问方式共享文件夹的方式参考其他资料 https://cxxu1375.blog.csdn.net/article/details/140139320
    #>
    param(
        # 指定一个目录作为共享文件夹
        $Path = 'C:\Share', #推荐尽可能短的目录(可以自定义,但是层级不宜深)
        $ShareName = 'Share', #如果您之前有过共享文件夹,并且名字也是Share,那么就需要修改名字
        $Permission = 'Change', #合法的值有:Read,Change,Full 权限从低到高 分别是只读(Read),可读可写(change),完全控制(full)
        # 指定专门用来访问共享文件夹的用户(这不是必须的,您可以用自己的用户和密码,但是不适合把自己的私人账户密码给别人访问,所以推荐建立一个专门的用户角色用于访问共享文件夹)
        $SmbUser = 'Smb', #如果本地已经有该用户，那么建议改名
        # [SecureString] $SmbUserKey = '1' #密码可以改,但是建议尽可能简单,默认为1
        $SmbUserKey = '1'
    )
    #启用文件共享功能以及网络发现功能(后者是为了方便我们免ip访问,不是必须的)

    Enable-NetworkDiscoveyAndSharing

    $exist = (Test-Path $Path)
    if (! $exist)
    {
        mkdir $Path
    }
   
    New-SmbSharingReadme
  
    # "$Path\A Readme File@This is a shared folder! Place anything here to share with others.txt"


    # 创建共享文件夹
    "New-SmbShare -Name $ShareName -Path $Path -${Permission}Access 'Everyone'" | Invoke-Expression #这里赋予任意用户修改权限(包含了可读权限和修改权限)

    $res = glu -Name "$SmbUser" -ErrorAction Ignore
    if (! $res)
    {
        # 权限要求:需要使用管理员权限窗口运行命令
        #方案1:使用net user 命令来创建带密码新用户(不要求安全性的共享凭证账户)
        net user $SmbUser $SmbUserKey /add /expires:never #这里添加的用户是永不过期的，更多参数查看官网文档

        #方案2:使用powershell方案来创建带密码新用户(
        # $SmbUserKey = Read-Host "Enter password For $SmbUser" -AsSecureString
        # 使用windows自带的powershell执行New-LocalUser不会报错,部分windows版本可能会报错,所以这里添加了一个导入语句,根据需要来添加或者移除(注释掉)这一行导入语句)
        # Import-Module microsoft.powershell.localaccounts -UseWindowsPowerShell
        # New-LocalUser -Name $SmbUser -Password $SmbUserKey -AccountNeverExpires 

    }

    
}
function Set-FolderFullControlForEveryone-Deprecated
{
    <# 
    .SYNOPSIS
    将NTFS文件系统上的某个文件夹的访问控制权限设置为所有人具有全部控制权限
    本函数的路径是一个目录路径而不是一个文件路径,否则会报错

    这个操作对应的GUI操作是右键需要修改的文件夹,然后设置它的访问权限,包括允许访问的用户及其相应的访问权限种类
    .DESCRIPTION
    这么操作通常仅在访问被设置文件夹的用户是受信任的情况执行,例如在家里创建共享文件夹时，遇到权限问题时,可以使用这个命令简化操作
    .EXAMPLE
    # 使用示例
    # Set-FullControlForEveryone -Path 'C:\repos\scripts'
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )


    # 获取目录/文件的当前访问控制列表对象
    $acl = Get-Acl -Path $Path

    Write-Verbose 'Origin Acl:'
    $info = $acl | Format-List | Out-String
    
    Write-Verbose $info 

    # 创建一个新的访问规则，赋予Everyone组完全控制权
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'Everyone',
        'FullControl',
        'ContainerInherit, ObjectInherit',
        'None',
        'Allow'
    )

    # 将新的访问规则添加到访问控制列表中
    $acl.SetAccessRule($accessRule)

    try
    {
        
        # 将修改后的访问控制列表应用到目录
        Set-Acl -Path $Path -AclObject $acl
    }
    catch
    {
        Write-Error 'Please ensure the path is an exist directory!'
    }

    Write-Verbose 'Modified Acl:'
    $res = Get-Acl -Path $Path | Format-List | Out-String
    Write-Verbose $res

}
function Get-IPAddressV4-Deprecated
{
    <# 
   .SYNOPSIS
   Get ip address,get ipv4 mainly nowadays
   In the feature, the function may be to update to return ipv6
   #>
    $str = arp -a | Select-String '---' | Select-Object -First 1
    # eg:$str = 'Interface: 192.168.1.178 --- 0x3'

    # 使用正则表达式匹配IP地址模式
    $ipAddress = [regex]::Match($str, '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b').Value

    # 输出提取出的IP地址
    return $ipAddress
}

function Start-PwshInit-deprecated
{
    param(
        # [ValidateSet('Fast', 'Full')]$Mode = 'Fast',
        [switch]$NewPwsh 
    )
    if ($NewPwsh)
    {
        Write-Host 'Start New Pwsh ... ', "`n" -ForegroundColor Magenta 
        # pwsh -c 无法传入自定义函数的参数,只有自带的cmdlet才能用参数
        pwsh -noe -c { Set-CommonInit }
    }
    Set-CommonInit
    
}

function Get-EnvVarsDeprecated
{
    <#
    .SYNOPSIS
    查询指定的环境变量是否存在,若存在显示其值(键值对)

    .DESCRIPTION
    支持列出所有用户环境变量(不含系统变量);反之亦然(通过参数Scope和List控制);
    在这列表的情况下,对于用户和系统都有的变量,则先显示用户配置的值
    (如果想知道某个变量是否既有系统值又由用户值来控制,可以使用Get-EnvValue来查询)

    本函数其实是对Get-EnvVar的简单封装
    另一个相关的获取用户或系统环境变量值的函数是Get-EnvUser(用户独占变量),Get-EnvMachine;两者获取更加隐蔽的环境变量
    通常我们关系系统属性(SystemPropertiesAdvanced.exe)中可以设置和查看的那些环境变量

    利用where-object,可以筛选出想要的的环境变量及其值(在这里可以应用-like等模糊通配匹配,-match用于正则匹配,也可以对值进行模糊匹配而非变量名匹配);总这,这相当于对 ls env:<pattern>或ls env:<pattern> |where{<expresiion>}的扩展(可以选择尽在用户变量中搜索),虽然一般后者已经足够用了

    如果环境变量值比较长,或者有多个值无法完全显示出来,可以使用format-table -wrap参数,使其自动换行而不用省略号
    (这个wrap功能就不继承到Get-EnvVar了,就是常规的通用的管道符格式化操作)    
    也可以使用export-csv(epcsv)将结果导出到csv文件,可以用专门的工具比如excel打开/查找,当然也可以当纯粹的备份环境变量

    .EXAMPLE
    PS BAT [10:15:22 AM] [C:\Users\cxxu\Desktop]
    [🔋 100%] MEM:74.88% [5.88/xx] GB |> Get-EnvVars|?{$_.Name -like 'p*h'}  
    Name                           Value
    ----                           -----
    Path                           C:\Program Files\PowerShell\7;C:\Users\cx…
    POSH_THEMES_PATH               C:\Program Files (x86)\oh-my-posh\themes
    PSModulePath                   C:\Users\cxxu\Documents\PowerShell\Module…
    
    .EXAMPLE
    [🔋 100%] MEM:72.77% [5.71/xx] GB |> Get-EnvVars|?{$_.Name -like 'p*h'} |ft -wrap

    Name                           Value
    ----                           -----
    Path                           C:\Program Files\PowerShell\7;C:\Users\cxxu\AppData\Roaming\Python\Python312\Scripts;C:\Program
                                Files\PowerShell\7;C:\Program Files\Python312\Scripts\;C:\Program Files\Python312\;C:\Program Files\Eclipse Adoptium\jdk-2
                                1.0.1.12-hotspot\bin;C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;C:\WINDOWS\System32\WindowsPowerShell\v1.0\;
    POSH_THEMES_PATH               C:\Program Files (x86)\oh-my-posh\themes
    PSModulePath                   C:\Users\cxxu\Documents\PowerShell\Modules;C:\Program Files\PowerShell\Modules;c:\program
                                files\powershell\7\Modules;C:\Program
                                Files\WindowsPowerShell\Modules;C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules;C:\repos\scripts\PS;
                        
    .EXAMPLE
    PS BAT [10:15:31 AM] [C:\Users\cxxu\Desktop]
    [🔋 100%] MEM:74.92% [5.88/xx] GB |> Get-EnvVars |select Name,Value|epcsv -path ./envs.csv
    .EXAMPLE
    从csv文件导入到powershell显示,可以指定-Wrap等参数显示完整的长值(换行)
    PS BAT [10:28:16 AM] [C:\Users\cxxu\Desktop]
    [🔋 100%] MEM:72.82% [5.72/xx] GB |> Import-Csv .\envs.csv |ft -AutoSize 

    Name                            Value
    ----                            -----
    ALLUSERSPROFILE                 C:\ProgramData
    APPDATA                         C:\Users\cxxu\AppData\Roaming
    CommonProgramFiles              C:\Program Files\Common Files
    CommonProgramFiles(x86)         C:\Program Files (x86)\Common Files
    CommonProgramW6432              C:\Program Files\Common Files
    COMPUTERNAME                    CXXUWIN
    .EXAMPLE
    > Get-EnvVars -Scope M|where{$_.Name -like 'p*h'}

    Name                           Value
    ----                           -----
    Path                           C:\Program Files\PowerShell\7;C:\Users\cx…
    POSH_THEMES_PATH               C:\Program Files (x86)\oh-my-posh\themes
    PSModulePath                   C:\Users\cxxu\Documents\PowerShell\Module…

     #>
    param(
        #环境变量名字符串(不支持正则和模糊),如果需要,请配合管道符和where-object使用模糊匹配
        #事实上Key 可以不用,一般在熟悉的变量时用-key
        #只用管道符和where来查询也是可以的,先用Get-EnvVars -scope [A|M|U]|where{$BooleanExpression} ,这样返回的结果是foramt-table 格式的(两列);不指定-Scope 时默认从融合结果中查找
        $Key = '*',
        $Scope = 'A',
        #list all env for scope
        [switch]$List

    )
    
    #如果没有指定key(或为默认`*`),则认为是要列出所有的环境变量,将$List 设置为真
    $List = $key -eq '*'? $true : $List
    if ($List)
    {
    
        $envs = Get-ChildItem env: 
        $envs_scope_list = $envs | Where-Object { Get-EnvValue -Key $_.Name -Scope $Scope }
        return $envs_scope_list
    }
    else
    {
        return Get-EnvValue -Key $Key -Scope $Scope
    }
}
function Get-PSDirItem-Deprecated
{
    <# 
    .SYNOPSIS
    获取指定目录的IO.directoryinfo对象，而不是子目录中的条目列表
    这个函数已经被启用,请使用Get-PsIOItemInfo 来代替,后者可以处理目录也可以处理文件路径
    .Description
    获取子目录的Powershell目录对象(DirectoryInfo),而不是子目录中的条目列表
    这个函数可帮助检查某个目录(默认为当前目录)中的子目录的DirectoryInfo信息,
    不同于PathInfo(可以用rvpa解析到,但是包含的信息比较少)
    .Notes
    本函数仅处理目录路径(而不处理文件路径)

    例如:DirectroyInfo,FileInfo包括:Name,FullName,LinkType,Target等有用信息
    这个方法不能为我们创建一个不存在的路径的目录型路径对象信息(DirenctoryInfo)
    .DESCRIPTION
    可以取别名为 Get-DirectoryInfo
    .EXAMPLE
    PS>get-PSDirItem -SubDirectory  '.\zh-CN\'
    C:\Windows\System32\zh-CN

        Directory: C:\Windows\System32

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    d---s           2024/5/15    11:53                zh-CN
    .EXAMPLE
    PS>Get-PSDirItem -SubDirectory '.\Saved Games\' -Directory .
    C:\Users\cxxu\Saved Games

        Directory: C:\Users\cxxu

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    d-r--            2024/4/5    11:08                Saved Games
    
    #>
    param (
        [Alias('D')]$Directory = '.',
        [Alias('S')]$SubDirectory
    )
    

    $p = Join-Path -Path $Directory -ChildPath $SubDirectory
    # 判错逻辑可以不写,如果有错直接抛出错误即可,告诉用户输入的路径是有误的
    # $exist = Test-Path $p
    # $p=$exist ? (Resolve-Path $p) : ''
    $p = Resolve-Path $p
    $p = $p.Path.Trim('\') #字符串类型
    Write-Host $p -ForegroundColor Blue

    $allItems = Get-ChildItem "$p/.."
    # Write-Host $allItems

    $res = $allItems | Where-Object { $_.FullName -eq $p }
    return $res
    
}