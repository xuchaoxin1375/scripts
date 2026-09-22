<#
PsDebug 模块:PowerShell 内省/诊断/调试辅助(管道/源码/权限/日志)。
从 Pwsh.psm1 迁入: Pwsh 只留模块加载脚手架,内省调试类归此模块;
调用方命令名不变(自动发现同名模块),Deploy/Link/Git 等跨模块调用走自动加载。
#>

function Head
{
    param (

        $file,
        $number = 10
    )
    
    Get-Content $file -head $number | ForEach-Object { '{0,-5} {1}' -f $_.ReadCount, $_ }
}

function Tail
{
    param (
        $file,
        $number = 10
    )
    # catn $file | Select-Object -Last $number
    Get-Content $file -head $number | ForEach-Object { '{0,-5} {1}' -f $_.ReadCount, $_ }
    
}
function Get-TypeCxxu
{
    
    <#
    .SYNOPSIS
    Get-TypeCxxu用来获取输入对象的类型信息
    .DESCRIPTION
    Get-TypeCxxu是一个用来获取输入对象的类型信息的函数,它接受一个输入对象,并返回一个包含对象的类型信息的对象
    .PARAMETER InputObject
    要获取类型信息的输入对象
    .INPUTS
    可以通过管道传递输入对象
    .OUTPUTS
    Return a custom object that contains information about the type of the input object
    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> "abc"|Get-TypeCxxu

    Name   FullName      BaseType      UnderlyingSystemType
    ----   --------      --------      --------------------
    String System.String System.Object System.String

    .EXAMPLE
    PS [C:\Users\cxxu\Desktop]> Get-TypeCxxu -InputObject "abc"

    Name   FullName      BaseType      UnderlyingSystemType
    ----   --------      --------      --------------------
    String System.String System.Object System.String
    .NOTES

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        $InputObject
    )

    process
    {
        if ($InputObject)
        {
            $typeInfo = $InputObject.GetType()
         
            $output = $typeInfo | Select-Object Name, fullname, BaseType, UnderlyingSystemType
            return $output
        }
    }
}
function Get-ParametersList
{
    param(
        [parameter(ValueFromPipeline = $true)]
        [string]$Name
    )
    process
    {
        Get-Command $Name | Select-Object -ExpandProperty Parameters | Select-Object -ExpandProperty Keys
    }
}

function Test-SudoAvailability
{
    <# 
    .SYNOPSIS
    返回当前系统内是否有sudo命令可以调用(如果可以调用,那么可以在函数中自动地临时地切换到管理员模式运行命令)
    .DESCRIPTION
    # sudo命令自windows 11 24h2后可以从设置中启用;或者通过安装第三方模块获得sudo命令(比如scoop install gsudo)

    #>
    $res = Get-Command -Name sudo -ErrorAction SilentlyContinue 
    return $res
}

function Get-PathType
{
    <# 
    .SYNOPSIS
    判断输入的路径是绝对路径还是相对路径,无论这个路径是否存在
    .EXAMPLE
    PS[BAT:69%][MEM:26.27% (8.33/31.70)GB][11:47:30]
    # [~\Desktop]
    PS> Get-PathType "./script"
    RelativePath

    PS[BAT:69%][MEM:26.22% (8.31/31.70)GB][11:47:33]
    # [~\Desktop]
    PS> Get-PathType "C:\script"
    FullPath

    PS[BAT:69%][MEM:26.22% (8.31/31.70)GB][11:47:36]
    # [~\Desktop]
    PS> Get-PathType "C:/script"
    FullPath

    PS[BAT:69%][MEM:26.18% (8.30/31.70)GB][11:47:45]
    # [~\Desktop]
    PS> Get-PathType "/script"
    FullPath

    PS[BAT:69%][MEM:26.18% (8.30/31.70)GB][11:47:50]
    # [~\Desktop]
    PS> Get-PathType "/script"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # 判断是否为绝对路径

    # ^\/ 和 ^/ 在匹配字符串开始的斜杠(/)时都是有效的，尤其是在处理Unix/Linux风格的文件路径时。不过，在不同编程环境或工具中，可能会有细微的差别需要考虑。

    if ($Path -match '^[A-Za-z]:[\\/]|^\/') # ^[A-Za-z]:\ 匹配windows的绝对路径 ^/或^\/ 匹配Unix/Linux的绝对路径
    {
        Write-Output 'FullPath'
    }
    else
    {
        Write-Output 'RelativePath'
    }
}


function Set-Owner
{
    <# 
    .SYNOPSIS
    设置指定目录或文件的所有者
    .EXAMPLE
    默认将所有者设置为当前用户,域和用户名定义在VarSet1中,如果不导入,可以通过[System.Environment]::UserDomainName,[System.Environment]::UserName  或者简单通过$env:ComputerName和whoami命令获取
    #>

    param(
        # 设置目录路径
        $Path = '.',
        # 新所有者
        $NewOwner = $UserName,
        #domain
        $domain = $UserDomainName

    )

    # check the admin permission
    if (! (Test-AdminPermission))
    {
        Write-Error 'You need to have administrator rights to run this script.'
        return 
    }

    $NewOwner = "$domain\$NewOwner"
    # 获取当前 ACL
    $acl = Get-Acl -Path $Path

    # 创建新所有者的 NTAccount 对象
    $newOwnerAccount = New-Object System.Security.Principal.NTAccount($newOwner)

    # 设置新的所有者
    $acl.SetOwner($newOwnerAccount)

    # 应用修改后的 ACL
    Set-Acl -Path $Path -AclObject $acl

    # 检查新的所有者是否设置成功
    return (Get-Acl -Path $Path)
}

function Grant-PermissionToPath
{
    <# 
    .SYNOPSIS
    可以清除某个目录的访问控制权限,并设置权限,比如让任何人都可以完全控制的状态
    这是一个有风险的操作;建议配合其他命令使用,比如清除限制后再增加约束
    .DESCRIPTION
    设置次函数用来清理发生权限混乱的文件夹,可以用来做共享文件夹的权限控制强制开放
    .EXAMPLE
    PS [C:\]> Grant-PermissionToPath -Path C:/share1 -ClearExistingRules
    True
    True
    已成功将'C:/share1'的访问权限设置为允许任何人具有全部权限。
    .PARAMETER Path
    需要执行访问控制权限修改的目录
    .PARAMETER Group
    指定文件夹要授访问权限给那个组,结合Permission参数,指定该组对Path具有则样的访问权限
    默认值为:'Everyone'
    .PARAMETER Permission
    增加/赋于新的访问控制权限,可用的合法值参考:https://learn.microsoft.com/zh-cn/dotnet/api/system.security.accesscontrol.filesystemrights?view=net-8.0
    .PARAMETER ClearExistingRules
    清空原来的访问控制规则
    .NOTES
    需要管理员权限,相关api参考下面连接
    .LINK
     相关AIP文档:https://learn.microsoft.com/zh-cn/dotnet/api/system.security.accesscontrol.filesystemaccessrule?view=net-8.0
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        $Group = 'Everyone',
        # 指定下载权限
        $permission = 'FullControl',

        [switch]$ClearExistingRules

    )

    try
    {
        # 获取目标目录的当前 ACL
        $acl = Get-Acl -Path $Path

        # 创建允许“任何人（Everyone）”具有“完全控制”权限的新访问规则
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Group,
            $permission, 
            'ContainerInherit, ObjectInherit',
            'None',
            'Allow'
        )
        # 也可以考虑用icacls命令来做
        # cmd /c ' icacls $Path  /grant cxxu:(OI)(CI)F  /T '

        if ($ClearExistingRules)
        {
            # 如果指定了清除现有规则，则先移除所有现有访问规则
            $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
        }

        # 添加新规则到 ACL
        $acl.SetAccessRule($rule)

        # 应用修改后的 ACL 到目标目录
        Set-Acl -Path $Path -AclObject $acl

        Write-Host 'Permission settings completed!'
    }
    catch
    {
        Write-Error "Permission setting failed: $_"
    }
}





function Get-PipelineInput
{
    <# 
   .SYNOPSIS
   
   MrToolkit 模块包含一个名为 Get-MrPipelineInput 的函数。 此 cmdlet 可用于轻松确定接受管道输入的命令参数、接受的对象类型，以及是按值还是按属性名称接受管道输入。 
   .LINK
   https://learn.microsoft.com/zh-cn/powershell/scripting/learn/ps101/04-pipelines?view=powershell-7.4#finding-pipeline-input-the-easy-way
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [System.Management.Automation.WhereOperatorSelectionMode]$Option = 'Default',

        [ValidateRange(1, 2147483647)]
        [int]$Records = 2147483647
    )

    (Get-Command -Name $Name).ParameterSets.Parameters.Where({
            $_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName
        }, $Option, $Records).ForEach({
            [pscustomobject]@{
                ParameterName                   = $_.Name
                ParameterType                   = $_.ParameterType
                ValueFromPipeline               = $_.ValueFromPipeline
                ValueFromPipelineByPropertyName = $_.ValueFromPipelineByPropertyName
            }
        })
}
function Get-SourceCode
{
    <# 
    .SYNOPSIS
    查看Powershell当前环境下某个命令(通常是自定义的函数)的源代码
    .DESCRIPTION
    为例能够更方便地查看,在函数外面配置了本函数的Register-ArgumentCompleter 自动补全注册语句
    这样在输入命令名后按Tab键,就能自动补全命令名,然后按Tab键再次,就能查看命令的源代码

    .EXAMPLE
    PS>Get-CommandSourceCode -Name prompt

        if ($Env:CONDA_PROMPT_MODIFIER) {
            # 将conda当前激活的环境名打印出来(不带换行,便于和原来的拼接起来)
            $Env:CONDA_PROMPT_MODIFIER | Write-Host -NoNewline
        }
        CondaPromptBackup;

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Get-Command $Name | Select-Object -ExpandProperty ScriptBlock

}

# 注册参数补全，使其用于 Get-CommandSourceCode 的 Name 参数
Register-ArgumentCompleter -CommandName Get-CommandSourceCode -ParameterName Name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    # 搜索所有可能的命令以便于补全
    $commands = Get-Command -Name "$wordToComplete*" | ForEach-Object { $_.Name }
    
    # 返回补全结果
    $commands | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}


function Confirm-UserContinue
{
    <# 
    .SYNOPSIS
    该函数提示用户输入y（表示继续）或n（表示停止）。
    .DESCRIPTION
    基于用户的输入，函数将返回一个布尔值：$true如果用户输入y，$false如果用户输入n。
    .EXAMPLE
    您可以直接在PowerShell脚本中调用这个Confirm-UserContinue函数，并根据返回值来执行不同的逻辑。例如：

    $continue = Confirm-UserContinue -Description "Do you want to proceed? "
    if ($continue) {
        Write-Host "User chose to continue."
        # 放置继续执行的代码
    } else {
        Write-Host "User chose to stop."
        # 放置停止执行的代码
    }
    这段代码首先会提示用户是否要继续，然后根据用户的输入执行相应的代码块。如果用户输入y，则执行继续的逻辑；如果用户输入n，则执行停止的逻辑。
    .EXAMPLE
    PS C:\repos\scripts> Confirm-UserContinue -Description 'Destription about the event to continue or not'
    Destription about the event to continue or not {Continue? [y/n]} : y
    True

    PS>Confirm-UserContinue -Description 'Destription about the event to continue or not' 
    Destription about the event to continue or not {Continue? [y/n]} : N
    False
    #>
    param (
        $Description = '',
        [string]$QuestionTail = ' {Continue? [y/n]} '
    )
    $PromptMessage = $Description + $QuestionTail
    # Write-Host $PromptMessage Cyan
    while ($true)
    {
        $in = Read-Host -Prompt $PromptMessage

        switch ($in.ToLower())
        {
            'y' { return $true }
            'n' { return $false }
            default
            {
                Write-Host "Invalid input. Please enter 'y' for yes or 'n' for no."
            }
        }
    }
}
function Write-PsDebugLog
{
    <# 
    .SYNOPSIS
    调用本函数会向指定的日志文件中写入日志
    .DESCRIPTION
    函数日志包括调用词日志的函数的名字,以及函数所属的模块,调用发生的时间,以及需要追加说明的内容
    这些信息不回自动生成,需要用户自己填写,可以有选择性的填写
    #>
    param (
        [string]$FunctionName = '',
        [string]$ModuleName = ' ',
        [string]$Time ,
        $LogFilePath,
        $Comment
    )
    $PSBoundParameters
    if (! $Time)
    {
        $Time = Get-Time -TimeStap yyyyMMddHHmmssfff
        # "$(Get-Date -Format 'yyyy-MM-dd--HH-mm-ss-fff')"
    }
    if (! $LogFilePath)
    {
        #对于System这类账户使用桌面路径无效,可以考虑段路径C:\tmp或C:\Log,可以提前创建好
        if (!(Test-Path 'C:\Log'))
        {
            mkdir 'C:\Log'
        }
        $logFilePath = "c:\Log\Log`@${FunctionName}_$Time.txt"
        Write-Host $LogFilePath
        # $logFilePath = Join-Path -Path ([Environment]::GetFolderPath('Desktop')) -ChildPath "Log_$FunctionName_$Time.txt"
    }
    $logContent = "Function Name: $FunctionName`nModule Name: $ModuleName`nCall Time: $Time `n" + "comments: $Comment"

    Set-Content -Path $logFilePath -Value $logContent
    return $logContent
}
function Start-CodeSSh
{
    <# 
    .SYNOPSIS
    命令行中启动vscode的ssh远程连接,进行远程编程或文件管理
    .PARAMETER Server
    远程服务器的名称(可以主机名)或ip地址
    .PARAMETER Path
    需要打开的目录,默认是用户的主目录
    例如'/www/wwwroot/xcx/tissuschic.com/wordpress'
    .EXAMPLE
    linux主机的ip地址为192.168.1.111;并且配置了ssh免密登录(上传了公钥),可以直接使用如下命令进行远程编程或文件管理:
    比如我要编辑网站demosite.com根目录,就可以用以下命令打开
    
    PS> Start-CodeSSh -Server 192.168.1.111 -Path /www/wwwroot/xcx/demosite.com/wordpress

    #>
    param (

        #根据查询到的ip地址,创建变量
        $Editor = 'code',
        $Server = 'localhost',
        # $Path="/home/" #需要打开的目录
        $Path = $home,
        $Port = ""
    )
    # code --folder-uri "vscode-remote://ssh-remote+$Server/$Path"
    $cmd = "$Editor --folder-uri vscode-remote://ssh-remote+$Server/$Path"
    Invoke-Expression $cmd
}

