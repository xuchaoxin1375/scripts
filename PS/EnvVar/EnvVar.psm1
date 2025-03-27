class EnvVar
{
    <# Define the class. Try constructors, properties, or methods. #>
    # [int]$Number
    [string]$Scope
    [string]$Name
    [string]$Value
    [String]  ToString()
    {
        return "$($this.Scope) $($this.Name) $($this.Value)"
    }
}

# Example usage:
# Clear-EnvironmentVariables -Scope "User"
# Clear-EnvironmentVariables -Scope "System"

function Get-EnvList
{
    <# 
    .SYNOPSIS
    列出所有用户环境变量[系统环境变量|全部环境变量(包括用户和系统共有的环境变量)|用户和系统合并后的无重复键的环境变量]
    获取
    .LINK
    相关api文档
    https://learn.microsoft.com/zh-cn/dotnet/api/system.environment.getenvironmentvariables?view=net-8.0
    .LINK
    想要查看的枚举值类型文档
    https://learn.microsoft.com/zh-cn/dotnet/api/system.environmentvariabletarget?view=net-8.0
    #>
    <# 
    .EXAMPLE
    > Get-EnvList -Scope U

    Scope Name             Value
    ----- ----             -----
    User  TMP              C:\Users\cxxu\AppData\Local\Temp
    User  Path             C:\Users\cxxu\AppData\Local\Microsoft\WindowsApps;…
    User  TEMP             C:\Users\cxxu\AppData\Local\Temp
    User  OneDriveConsumer C:\Users\cxxu\OneDrive
    User  OneDrive         C:\Users\cxxu\OneDrive
    .EXAMPLE
    > Get-EnvList

    Scope  Name                            Value
    -----  ----                            -----
    Combin OneDriveConsumer                C:\Users\cxxu\OneDrive
    Combin CommonProgramFiles(x86)         C:\Program Files (x86)\Common Files
    Combin POSH_INSTALLER                  manual
    Combin POSH_SHELL_VERSION              7.4.1
    Combin USERPROFILE                     C:\Users\cxxu
    Combin PROCESSOR_REVISION              8e0b

    #>
    [ OutputType([EnvVar[]])]
    [CmdletBinding(SupportsPaging)]
    param(
        #one of [User|Machine|Detail|Combin] abbr [U|M|D|C]
        [validateset('User', 'Machine', 'Combined')]
        $Scope = 'Combined'
    )
    switch -Wildcard ($Scope)
    {
        'U*'
        {
            $envs = [Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::User)
            #从hastable简化为hashtableEnumerator (包含键值对Name,Value)
            # $envUser=$envUser.GetEnumerator() 

        }
        'M*'
        { 
            $envs = [Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
  
        }
        'C*'
        { 
            $envs = [Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process) 
        }
        default
        {
            $envs = [Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process) 
        }
    }
    Write-Debug "envs=$envs"
    # $env_detail=$envUser,$envMachine

    $envs = $envs.GetEnumerator() | ForEach-Object {
        [EnvVar]@{
            Scope = $Scope
            Name  = $_.Name
            Value = $_.Value
            
        }
    }



    #以下是可选操作
    # $res = $res.GetEnumerator() 
    #| Select-Object -ExpandProperty Name
    
    return $envs
    
}

function Get-EnvVar
{
    <# 
    .SYNOPSIS
    查询指定环境变量的值,或者查询所有环境变量(可以指定用户变量或系统变量或者全部变量)
    .DESCRIPTION
    用$env:var查询环境变量时,通常对于用户和系统都用的环境变量,显示用户的值而不显示系统的值
    但是对于$env:path,会将用户和系统的值合并在一起显示,而不仅仅显示用户的值,是一个特殊的环境变量,
    毕竟系统要扫描Path指定的所有目录

    函数是对[Get-EnvList]的封装扩展,使得调用比较方便,支持统配模糊匹配环境变量名
    如果需要正则匹配,将-like改为-match
    如果需要检查变量值(匹配),直接用Get-EnvList 配合 |where{}查找
    #>
    <# 
    .EXAMPLE
    > get-EnvVar -scope U |ft -AutoSize -wrap

    Number Scope Name             Value
    ------ ----- ----             -----
        1 User  TMP              C:\Users\cxxu\AppData\Local\Temp
        2 User  Path             C:\Users\cxxu\AppData\Local\Microsoft\Window
                                sApps;C:\Users\cxxu\scoop\shims;C:\Users\cxx
                                u\AppData\Local\Programs\oh-my-posh\bin;
        3 User  TEMP             C:\Users\cxxu\AppData\Local\Temp
        4 User  OneDriveConsumer C:\Users\cxxu\OneDrive
        5 User  OneDrive         C:\Users\cxxu\OneDrive

    .EXAMPLE
    > get-EnvVar -scope D -key t*mp

    Number Scope   Name Value
    ------ -----   ---- -----
        1 User    TMP  C:\Users\cxxu\AppData\Local\Temp
        2 User    TEMP C:\Users\cxxu\AppData\Local\Temp
        3 Machine TEMP C:\WINDOWS\TEMP
        4 Machine TMP  C:\WINDOWS\TEMP
    .EXAMPLE
    > get-EnvVar -scope D -key t*mp |sort Name

    Number Scope   Name Value
    ------ -----   ---- -----
        2 User    TEMP C:\Users\cxxu\AppData\Local\Temp
        3 Machine TEMP C:\WINDOWS\TEMP
        1 User    TMP  C:\Users\cxxu\AppData\Local\Temp
        4 Machine TMP  C:\WINDOWS\TEMP
    .EXAMPLE
    > get-EnvVar -scope User

    Number Scope Name             Value
    ------ ----- ----             -----
        1 User  TMP              C:\Users\cxxu\AppData\Local\Temp
        2 User  Path             C:\Users\cxxu\AppData\Local\Microsoft\Windo…
        3 User  TEMP             C:\Users\cxxu\AppData\Local\Temp
        4 User  OneDriveConsumer C:\Users\cxxu\OneDrive
        5 User  OneDrive         C:\Users\cxxu\OneDrive
    #>
    [OutputType([EnvVar[]])]
    # [OutputType([IndexObject], ParameterSetName = 'Count')]
    [CmdletBinding(SupportsPaging)]
    param(
        #env var name
        [Alias('Name', 'Key')]$EnvVar = '*',

        #one of [User|Machine|Detail|Combin] abbr [U|M|D|C]
        #Detail:show env in both user and machine
        #Combin:show env in user and machine merge(only user value if both have the env var)
        [validateset('User', 'Machine', 'Combined')]
        $Scope = 'Combined',

        # 已废弃:是否统计环境变量的取值个数,例如Path变量
        # 可以使用Format-IndexObject来进行计数展示处理
        # [parameter(ParameterSetName = 'Count')]
        [switch][alias('PrintAsCountView')]$Count
        # [switch]$PassThru
        
    )
    $res = Get-EnvList -Scope $Scope | Where-Object { $_.Name -like $EnvVar }
    # Write-Host $res -ForegroundColor Magenta
    
    #统计环境变量个数
    if ($Count)
    {
        #方案1
        #清理并规范化环境变量取值
        $value = (Remove-RedundantSemicolon $res.value) -split ';'
        $res = $value | Format-DoubleColumn
        #方案2
        # $res | Format-EnvItemNumber
       
    }
    return $res
   
}

class IndexObject
{
    $index
    $Value
    <# Define the class. Try constructors, properties, or methods. #>
}


function Get-EnvPath
{
    <# 
    .SYNOPSIS
    获取Path环境变量,支持用户变量，系统变量和进程级环境变量
    .DESCRIPTION
    默认获取当前进程级别的Path环境变量,融合了用户级别和系统级别的环境变量
    默认对结果做了升序排序,如果需要其他排序,可以使用管道符进行排序
    注意返回的是一个数组,而且每个元素是自定义class IndexObject的实例
    .EXAMPLE
    直接调用,以一个表格的形式显示,但类型是一个数组，而不是表格对象,保留了后续处理的潜力
    PS>  Get-EnvPath
    Index Value
    ----- -----
        1 %exes%
        2 C:\Program Files\Microsoft VS Code\bin
        3 C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Scoop Apps
        4 C:\ProgramData\scoop\apps\gsudo\current
        5 C:\ProgramData\scoop\apps\miniconda3\current\Li
    .EXAMPLE
    排序和重新排序可以这么做
    Get-EnvPath|select -ExpandProperty Value|sort Value -Descending|Format-DoubleColumn
    
    Index Value
    ----- -----
        1 %exes%
        2 C:\WINDOWS\System32\OpenSSH\
        3 C:\WINDOWS\system32
        4 C:\WINDOWS
        5 C:\Users\cxxu\scoop\shims
    #>
    [OutputType([IndexObject[]])]
    param(
        [ValidateSet('user', 'machine', 'process')]$scope = 'process',
        [switch]$NoSort
    )
    switch -Wildcard ($scope)
    {
        'U*'
        {
            # $Path = [System.Environment]::GetEnvironmentVariable('Path', 'User')
            $path = Get-EnvVarRawValue -EnvVar 'Path' -Scope 'User'
        }
        'M*'
        {
            # $Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
            $path = Get-EnvVarRawValue -EnvVar 'Path' -Scope 'Machine'
        }
        Default
        {
            # $Path = [System.Environment]::GetEnvironmentVariable('Path', 'Process')
            $path = Get-EnvVarRawValue -EnvVar 'Path' -Scope 'Process'
        }
    }

    $value = $Path -split ';' | Format-DoubleColumn
    if (!$NoSort)
    {
        $value = $value.value | Sort-Object | Format-DoubleColumn
    }
    return $value
}

function Remove-RedundantSemicolon
{
    <# 
    .SYNOPSIS
    #清理可能多余的分号,包括首位多出的分号,或者相邻元素见多余的分号和空格
    .EXAMPLE
    PS C:\repos\scripts\PS\Test> remove-RedundantSemicolon ";;env1;env2;  ; env3"
    env1;env2;env3
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        $Values
    )
    begin
    {

    }
    process
    {
        $res = @()
        foreach ($value in $Values)
        {

            # 匹配一个或多个';'并且跟随0个或多个空格
            $Value = $Value -replace ';[;\s]*', ';'
            $Value = $Value.trim(';')
            
            Write-Debug $Value

            $res += $value
            # $res | Format-Table

        }
        return $res
        
    }
    end
    {
        
    }

}

function Get-EnvVarRawValue
{
    <# 
    .SYNOPSIS
    从相应的注册表中读取指定环境变量的取值
    .DESCRIPTION

    # 不会自动转换或丢失%var%形式的Path变量提取
        # 采用reg query命令查询而不使用Get-ItemProperty 查询注册表, 因为Get-ItemProperty 会自动转换或丢失%var%形式的变量
        # 注册表这里也可以区分清楚用户级别和系统级别的环境变量
    #>
    [CmdletBinding()]
    param (
        [Alias('Name', 'Key')]$EnvVar = 'new', 
        [ValidateSet('Machine', 'User', 'Process')]
        $Scope = 'User'
    )
    $currentValue = [System.Environment]::getenvironmentvariable($EnvVar, $Scope)
    if ($CurrentValue)
    {
        if ($scope -eq 'User' -or $scope -eq 'Process')
        {

            $CurrentValueUser = reg query 'HKEY_CURRENT_USER\Environment' /v $EnvVar
            $currentValue = $CurrentValueUser
        }
        if ($scope -eq 'Machine' -or $scope -eq 'Process')
        {
            $currentValueMachine = reg query 'HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' /v $EnvVar
            $currentValue = $currentValueMachine

        }
        if ($Scope -eq 'process')
        {

            #recurse
            $U = Get-EnvVarRawValue -EnvVar $EnvVar -Scope 'User'
            $M = Get-EnvVarRawValue -EnvVar $EnvVar -Scope 'Machine'
            $currentValue = (@($U , $M) -join ';') -split ';' | Select-Object -Unique | Remove-RedundantSemicolon
            return $currentValue
            # $CurrentValue = $CurrentValueUser + $currentValueMachine
        }
        $CurrentValue = @($CurrentValue) -join '' #确保$CurrentValue是一个字符串
        # $CurrentValue -match 'Path\s+REG_EXPAND_SZ\s+(.+)'
        # $mts = [regex]::Matches($CurrentValue, $pattern)
        # return $mts
        if (

            $CurrentValue -match 'REG.*SZ\s+(.+)'

        )
        {

            $CurrentValue = $Matches[1] | Remove-RedundantSemicolon
            # 规范化
        }
    }
    if ($VerbosePreference)
    {
        Write-Verbose "RawValue of [$EnvVar]:"
        Write-Host ($currentValue -split ';' | Format-DoubleColumn | Out-String)
    }
    # 返回的是一个字符串,而不是;分隔的字符串数组
    return $currentValue 
}

function Get-EnvVarExpandedValue
{
    <# 
    .SYNOPSIS
    获取当前用户或机器级别的环境变量值,并且取值是全展开的(将%var%替换为其真实值)
    .DESCRIPTION
    # 考虑到[environment]::getenvironmentvariable($envvar, $scope)的行为稳定性不足(有时候会丢失%var%形式取值,有事后又会保留%var%,这里的模式做显式解析,展开%var%)
    .NOTES
    内部调用.Net 的[Environment]::ExpandEnvironmentVariables(String)进行计算，
    当String形如%var%并且存在环境变量var,那么var会被展开，%会被消掉，如果var环境变量并不存在，那么会原路返回
    #>
    [CmdletBinding()]
    param (
        [Alias('Name', 'Key')]$EnvVar = 'new', 
        [ValidateSet('Machine', 'User')]
        $Scope = 'User'
    )
    $CurrentValue = [Environment]::GetEnvironmentVariable($EnvVar, $Scope)
    $currentValues = $CurrentValue.Trim(';') -split ';'
    $ExpandedValues = @()
    foreach ($item in $currentValues)
    {
        # Convert-Path $item
        $ExpandedValues += [Environment]::ExpandEnvironmentVariables($item)
    }
    # Write-Verbose "ExpandedValue: $ExpandedValues"
    if ($VerbosePreference)
    {
        Write-Verbose 'ExpandedValues:'
        # $ExpandedValues | Format-List | Out-String #每个值占一行地打印出来
        foreach ($value in $ExpandedValues)
        {
            Write-Verbose $value -Verbose
        }
    }
    return $ExpandedValues | Join-String -Separator ';'
}
function Add-EnvVar
{
    <# 
.SYNOPSIS
添加环境变量(包括创建新变量及其取值,为已有变量添加取值),并且立即更新所作的更改
这里我们利用$expression | Invoke-Expression等方法来手动立即更新当前powershell上下文的环境变量,实现不需要重启更新环境变量
虽然本函数能够刷新当前powershell上下文的环境变量,但是其他shell进程却不会跟着刷新,可以手动调用Update-EnvVarFromSysEnv来更新当前shell的环境变量
.DESCRIPTION
当对一个已经存在变量添加值时,会在头部插入新值;(有些时候末尾会带有分号,导致查询出来的值可能存在2个来连续的分号)
这时候可以判断移除最后一个分号,然后再添加新值,头插方式也行
.PARAMETER EnvVar
想要操作的环境变量名,可以是已经存在或者尚未存在的
在相关模块中为其设置了补全器支持
.PARAMETER NewValue
想要添加的新值或者初始化尚未存在的环境变量的值
.PARAMETER Scope 
想要添加的新环境变量的用户级别还是系统级别(默认为用户级别):User|Machine
.PARAMETER ExpandValue
是否展开变量值(仅适用于Path或者类似性质的变量(取值为一个或多个路径的字符串),其他类型的变量(比如OS版本等,不要使用此选项))
.PARAMETER ResolvePath
如果是路径,将变量值转换为绝对路径(如果原路径是相对路径的话,应该转换为绝对路径(使用此选项),否则环境变量分不清它)
如果是%var%类型的取值,则可以不用此选项,系统在需要的时候可以识别并展开
.PARAMETER Append
是否在原有值的末尾追加新值(默认插在头部)
.PARAMETER Sort
是否对(;)号分隔的环境变量取值按照字典顺序排序
.PARAMETER Force
不做询问直接执行(如果权限足够的话)
#>
    <# 
.EXAMPLE
PS BAT [10:58:25 PM] [C:\Users\cxxu\Desktop]
[🔋 100%] MEM:72.79% [5.71/xx] GB |> add-envVar -EnvVar new2 -NewValue v2
v2
.EXAMPLE
PS BAT [10:58:33 PM] [C:\Users\cxxu\Desktop]
[🔋 100%] MEM:72.74% [5.71/xx] GB |> add-envVar -EnvVar new2 -NewValue v3 -V
$env:new2 = 'v2;v3'
v2;v3
.EXAMPLE
以管理员权限运行powershell,可以配置系统级别的环境变量
PS BAT [11:16:24 PM] [C:\Users\cxxu\Desktop]
[🔋 100%] MEM:73.80% [5.79/xx] GB |> add-envVar -EnvVar new -NewValue v1 -Scope Machine
v1
.EXAMPLE
PS>(Get-EnvVar -Key Path -Scope U|select -ExpandProperty value) -split ';'
C:\Program Files\PowerShell\7
C:\Users\cxxu\scoop\shims
C:\Users\cxxu\AppData\Local\Programs\oh-my-posh\bin
C:\Users\cxxu\.dotnet\tools

PS>Add-EnvVar -EnvVar Path -Scope User -NewValue NewValueDemo
NewValueDemo;C:\Program Files\PowerShell\7;C:\Users\cxxu\scoop\shims;C:\Users\cxxu\AppData\Local\Programs\oh-my-posh\bin;C:\Users\cxxu\.dotnet\tools;
PS>(Get-EnvVar -Key Path -Scope U|select -ExpandProperty value) -split ';'
NewValueDemo
C:\Program Files\PowerShell\7
C:\Users\cxxu\scoop\shims
C:\Users\cxxu\AppData\Local\Programs\oh-my-posh\bin
C:\Users\cxxu\.dotnet\tools

#>
    <# 
.EXAMPLE
# 坚持特定的变量极其取值
可以看到下面的用户级别取值出现多余的分号(为了测试清理功能)
PS> Get-EnvVar -Scope User -EnvVar Path

Number Scope Name Value
------ ----- ---- -----
     1 User  Path ;;;%repos%;c:/repos/scripts;C:\PortableGit\bin;C:\Users…

以整洁的方式查看清理规范的环境变量取值
PS🌙[BAT:100%][MEM:51.92% (4.08/7.85)GB][18:23:59]
# [cxxu@CXXUREDMIBOOK][<W:192.168.1.46>][Win 11 专业版@24H2:10.0.26100.1297][~\Desktop]
PS> Get-EnvVar -Scope User -EnvVar Path -Count

Index Value
----- -----
    1 %repos%
    2 c:/repos/scripts
    3 C:\PortableGit\bin
    4 C:\Users\cxxu\scoop\apps\vscode\current\bin
    5 C:\Users\cxxu\AppData\Roaming\Microsoft\Windows\Start Menu\Programs…
    6 C:\Users\cxxu\scoop\apps\gsudo\current
    7 C:\Users\cxxu\scoop\shims
    8 C:/exes
    9 C:\exes\pcmaster
   10 C:\Users\cxxu\AppData\Local\Microsoft\WindowsApps
   11 C:\Users\cxxu\.dotnet\tools

#清理多余的符号(分号),并打印查询清理后的结果
#这里可以调用Get-Envvalue命令,也可以直接添加一个''值到Path
PS🌙[BAT:100%][MEM:52.11% (4.09/7.85)GB][18:24:07]
# [cxxu@CXXUREDMIBOOK][<W:192.168.1.46>][Win 11 专业版@24H2:10.0.26100.1297][~\Desktop]
PS> Clear-EnvValue  Path -Scope User
#或者Add-EnvVar -Scope User -EnvVar Path -NewValue '' 也可以触发清理并规范化变量值的操作

Index Value
----- -----
    1 %repos%
    2 %scripts%
    3 C:\PortableGit\bin
    4 C:\Users\cxxu\scoop\apps\vscode\current\bin
    5 C:\Users\cxxu\AppData\Roaming\Microsoft\Windows\Start Menu\Programs…
    6 C:\Users\cxxu\scoop\apps\gsudo\current
    7 C:\Users\cxxu\scoop\shims
    8 %exes%
    9 C:\exes\pcmaster
   10 C:\Users\cxxu\AppData\Local\Microsoft\WindowsApps
   11 C:\Users\cxxu\.dotnet\tools

#手动再次检查清理结果
PS🌙[BAT:100%][MEM:52.06% (4.09/7.85)GB][18:24:30]
# [cxxu@CXXUREDMIBOOK][<W:192.168.1.46>][Win 11 专业版@24H2:10.0.26100.1297][~\Desktop]
PS> Get-EnvVar -Scope User -EnvVar Path

Number Scope Name Value
------ ----- ---- -----
     1 User  Path %repos%;%scripts%;C:\PortableGit\bin;C:\Users\cxxu\scoo…


#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        
        [Alias('Name', 'Key')]$EnvVar = 'new',
        [Alias('Value')]$NewValue = (Get-Date).ToString(),
        [Alias('NewValueIsPath')][switch]$ResolveNewValue,

        # choose User or Machine,the former is default(no need for Administrator priviledge)
        # the Machine scope need Administrator priviledge
        [ValidateSet('Machine', 'User')]
        $Scope = 'User',
        [switch]$ExpandValue,
        [switch]$Append,
        [switch]$Sort,
        [switch]$Force

    )
    # 同步环境变量
    Update-EnvVarFromSysEnv -Scope $Scope -Verbose:$false
    # 先获取当前用户或机器级别的环境变量值(警告:使用$env:var方式获取的值可能会丢失%var%格式)
    $CurrentValue = [Environment]::GetEnvironmentVariable($EnvVar, $Scope)
    if ($ResolveNewValue)
    {

        # $NewValue = Convert-Path $NewValue #足够简单,但是无法兼容和解决$NewValue路径尚不存在的情况
        # 校准当前路径
        [System.IO.Directory]::SetCurrentDirectory((Get-Location))
        # 兼容绝对路径和相对路径地解析给定路径值(绝对路径也可以正确解析);
        # 如果要其他方法,需要判断是否为相对路径,然后再进行拼接{Join-Path -Path (Get-Location) -ChildPath ".\myfolder\mysubfolder"}
        $NewValueFullPath = [system.io.path]::GetFullPath($NewValue) #调用.net方法获取绝对路径
        Write-Verbose "[$NewValue] resolved to [$NewValueFullPath] "
        $NewValue = $NewValueFullPath
    }
    if ($ExpandValue)
    {
        if ($CurrentValue)
        {
            
            $ExpandedValues = Get-EnvVarExpandedValue -EnvVar $EnvVar -Scope $Scope -Verbose:$VerbosePreference
            # $continue = $PSCmdlet.ShouldProcess($EnvVar, 'ExpandValue')
            #这是一个危险操作,使用shouldcontinue询问
            $continue = $PSCmdlet.ShouldContinue($EnvVar, 'ExpandValue')
            if ($Force -or $continue)
            {
                $CurrentValue = $ExpandedValues -join ';' #确保是一个;分隔的字符串
            }
        }
     
    }
    else
    {
        # 默认行为,不会去展开%var%格式的值
        $CurrentValue = Get-EnvVarRawValue -EnvVar $EnvVar -Scope $Scope -Verbose:$VerbosePreference
    }
 
    #查询当前值,能够区分不同Scope的环境变量(例如用户变量和系统变量都有Path,如果只想插入一个新值到用户Path,就要用上述方法访问)
 
    # $CurrentValue = "`$env:$EnvVar" | Invoke-Expression #无法区分用户和系统的path变量

    # 添加新路径到现有 Path
    

    # 设置新值(现在还未经过清洗处理,不保证规范性)
    # 用户可以选择新值要插在头部还是接在尾部
    if ($Append)
    {
        $NewValueFull = "$CurrentValue;$NewValue"
    }
    else
    {

        $NewValueFull = "$NewValue;$CurrentValue"
    }
    # 变量取值规范化处理
    $NewValueFull = Remove-RedundantSemicolon $NewValueFull
    # return 
    # 提示待添加值是否已经存在于原值
    if ($NewValue -in $CurrentValue)
    {
        Write-Warning "Value $NewValue already exists in $EnvVar" 
    }


    if ($PSCmdlet.ShouldProcess($EnvVar, 'Get Unique Value'))
    {
        # 推荐用户清理重复值(不用着急预览,在最后更改前提示预览即可)
        
        $NewValueFull = $NewValueFull -split ';' | Select-Object -Unique | Join-String -Separator ';' #移除重复的项目

    }
    if ($Sort)
    {
        $NewValueFull = $NewValueFull | Sort-Object #对取值按顺序排序(可选)
    }
    #$CurrentValue如果没有提前设置值,则返回$null,而不是'',不能用$CurrentValue -ne '' 判断是否新变量,直接用$CurrentValue 即可
    # $NewValueFull = $CurrentValue  ? "$NewValue;$CurrentValue" : $NewValue 
    # $NewValueFull = if ($CurrentValue) { "$NewValue;$CurrentValue" } else { $NewValue } #可以避免多余的分号出现,不过即便出现也问题不大,我们还可以在最后使用清理逻辑进行规范化
    
 
    
    # 查看即将进行的更改,如果启用了$V或$Query,则会打印出更改的表达式,如果是后者还会进一步询问
    if ($VerbosePreference)
    {

        # Write-Host "`$env:$EnvVar From [$CurrentValue] TO [$NewValue]" -BackgroundColor green
        $Log = [PSCustomObject]@{
            EnvVar = $EnvVar;
            From   = $CurrentValue -split ';' | Out-String;
            To     = $NewValueFull -split ';' | Out-String
        } 
        #理论上可以不用Out-String,但是个别场景(比如后续的Read-Host)会导致输出顺序错乱,所以这里用Out-String强制渲染
        if ($EnvVar -eq 'Path')
        {
            # Path内容一般比较长,这里将其分行列表显示
            $Log | Format-List 
        }
        else
        {
            $Log | Format-Table -Wrap -AutoSize | Format-Table #| Write-Host -ForegroundColor Green
        }
        
        
    }
    if ($PSCmdlet.ShouldProcess("$env:COMPUTERNAME,Scope=$Scope", 'Add-EnvVar'))
    {
        
        
        # 设置 Scope 级别的 $EnvVar 环境变量
             
        #持久化添加到环境变量
        [Environment]::SetEnvironmentVariable($EnvVar, $NewValueFull, $Scope)
        
        # 刷新当前shell的环境变量
        #检查,要对path特殊处理

        if ($EnvVar -eq 'Path')
        {
            $CurrentValue = $env:Path  
            # $env:Path -split ';' |Write-Host Cyan
            $NewValueFull = Remove-RedundantSemicolon "$NewValue;$CurrentValue"
        }

        #方案1:比较繁琐,不够直接
        # $left = "`$env:$EnvVar"
        # $expression = "$left = '$NewValueFull'" 
        # $expression | Invoke-Expression
        Write-Debug "$($left)=`n$($NewValueFull -split ';' | Out-String)" # -BackgroundColor Yellow
        #方案2:比较推荐,使用set-item方法
        Set-Item -Path Env:\$EnvVar -Value $NewValueFull -Force -Confirm:$false -Verbose:$false

    }
    # return $res | Format-Table -AutoSize -Wrap
    # $res = Get-EnvVar $EnvVar -Scope $Scope -Count 
    # return $res

}

function Clear-EnvVar
{
    <# 
    .SYNOPSIS
    删除环境变量,支持用户级和系统级
    .DESCRIPTION
    适合在需要导入环境变量时使用,是一个高风险的操作
    .NOTES
    使用前请做好备份(比如使用注册表来备份,或者Backup-EnvsByPwsh    Backup-EnvsRegistry两个函数进行备份)
    #>
    param (
        [ValidateSet('User', 'Machine')]
        [string]$Scope,
        [switch]$Refresh
    )

    # $Scope = if ($Scope -eq 'User') { 'User' } else { 'Machine' }

    function Clear-Variables
    {
        param ($Scope)
        $envVariables = [System.Environment]::GetEnvironmentVariables($Scope)
        # 遍历各个对象逐个移除(取值置空就是移除效果)
        foreach ($key in $envVariables.Keys)
        {
            [System.Environment]::SetEnvironmentVariable($key, $null, $Scope)
        }
        Write-Output "$Scope environment variables cleared."
    }

    Clear-Variables -scope $Scope

    <#   
    if ($Scope -eq 'User')
    {
        Clear-Variables -scope $Scope
    }
    elseif ($Scope -eq 'System')
    {
        # 修改系统级环境变量,需要管理员权限
        # 尝试启动管理与powershell(可以考虑直接调用前面定义的内部函数,提高代码复用率)
        Start-Process powershell -Verb RunAs -ArgumentList {
            # 参数由外部的-ArgumentList传入
            param ($Scope)
            $envVariables = [System.Environment]::GetEnvironmentVariables($Scope)
            foreach ($key in $envVariables.Keys)
            {
                [System.Environment]::SetEnvironmentVariable($key, '', $Scope)
            }
            Write-Output 'System environment variables cleared.'
        } -ArgumentList $Scope
        
    }
    #>
}
function Clear-EnvValue
{
    <# 
    .SYNOPSIS
    清理环境变量中多余的分号
    注意对于系统级的变量需要使用管理员运行
    .DESCRIPTION
    Add-envva 实现了环境变量取值的清洗功能,让不规范的取值(比如多余的分号)清除掉
    本质是调用Add-EnvVar 添加一个空字符串来触发清理,封装为新函数名更符合语义调用
    #>
    <# 
    .EXAMPLE
    [🔋 100%] MEM:34.16% [10.83/31.70] GB |> add-EnvVar env37 "val;;;val"
    $env:env37:
    val

    val

    PS BAT [14:43:24] [C:\Users\cxxu]
    [🔋 100%] MEM:34.16% [10.83/31.70] GB |> get-EnvVar env37

    Number Scope  Name  Value
    ------ -----  ----  -----
        1 Combin env37 val;;val

    PS BAT [14:43:27] [C:\Users\cxxu]
    [🔋 100%] MEM:34.15% [10.83/31.70] GB |> clear-EnvValue -EnvVar env37
    $env:env37:
    val
    val

    PS BAT [14:43:35] [C:\Users\cxxu]
    [🔋 100%] MEM:34.17% [10.83/31.70] GB |> get-EnvVar env37

    Number Scope  Name  Value
    ------ -----  ----  -----
        1 Combin env37 val;val
    #>
    param(
        $EnvVar = 'Path',
        [ValidateSet('Machine', 'User')]
        $Scope = 'User'
    )
    Add-EnvVar -EnvVar $EnvVar -NewValue '' -Scope $Scope 

}
function Remove-EnvVarValue
{
    <# 
    .SYNOPSIS
    删除环境变量中的指定值
    .DESCRIPTION
    注意指定Scope,这是必须的
    #>
    param (
        [string]$EnvVar,
        [string]$ValueToRemove,
        [validateset('Machine', 'User')]$Scope = 'User'
    )

    $CurrentValue = [Environment]::GetEnvironmentVariable($EnvVar, $Scope)

    if ( $CurrentValue )
    {
        $NewValue = ($CurrentValue -split ";") | Where-Object { $_ -ne $ValueToRemove } | Join-String -Separator ";"
        
        [Environment]::SetEnvironmentVariable($EnvVar, $NewValue, $Scope)
        if ($NewValue.Length -lt $CurrentValue.Length)
        {

            Write-Host "Removed [$ValueToRemove] from $EnvVar"
            # $res = [Environment]::GetEnvironmentVariable($EnvVar, $Scope) -split ';'
            # Write-Output $res
        }
        else
        {

            Write-Warning "[$ValueToRemove] does not exist in $EnvVar"
            # 用户可能拼写错误,尝试给出提示(如果存在合适的提示的话)
            $suggest = $CurrentValue -split ';' | Where-Object { $_ -like "*${ValueToRemove}*" }
            if ($suggest)
            {
                
                Write-Verbose "may be you want to try these available values: " -Verbose
                $suggest
            }

        }
    }
    else
    {
        Write-Warning "$EnvVar does not exist,no need to remove!"
        
        Write-Warning 'Or you can try another scope(User or Machine),User is default scope option'
    }
}
function Remove-EnvVar
{
    <# 
    .SYNOPSIS
    移除环境变量
    .EXAMPLE
    批量移除(借助Get-EnvVar 和管道符可以先做模糊匹配,然后通过foreach(%)循环删除,即便本函数暂不支持直接接受管道符输入):    
    Get-EnvVar new*|select name|%{Remove-EnvVar -EnvVar $_.Name}

    #>
    [cmdletbinding()]
    param (
        
        [Alias('Name', 'Key')] $EnvVar = '',
        
        # choose User or Machine,the former is default(no need for Administrator priviledge)
        # the Machine scope need Administrator priviledge
        [ValidateSet('Machine', 'User')]
        $Scope = 'User'
    )
    $CurrentValue = "`$env:$EnvVar" | Invoke-Expression 
    #虽然也可以考虑用Get-EnvVar -key $EnvVar|select value 查询当前值,但这不一定都是已经生效的值
    # 添加新路径到现有 Path
    #$CurrentValue如果没有提前设置值,则返回null,而不是'',不能用$CurrentValue -ne '' 判断是否新变量,直接用$CurrentValue 即可
    $NewValue = $CurrentValue  ? "$CurrentValue;$NewValue" : $NewValue 
    # Write-Output $NewValue
    
    # $expression = "`$env:$EnvVar = '$NewValue'" 
    #当前shell上下文中移掉该环境变量
    if (Get-EnvVar -Key $EnvVar -Scope $Scope)
    {
        # 设置 Scope 级别的 Path 环境$EnvVar变量为空,从而清除该环境变量(.Net检测到空字符串就移除掉该变量,而不仅仅设置为空字符串)
        [Environment]::SetEnvironmentVariable($EnvVar, '', $Scope)
        # if ("`$env:$EnvVar" | Invoke-Expression)
        Remove-Item env:$EnvVar -ErrorAction SilentlyContinue #无论当前环境是否存在$env:$EnvVar都执行移除操作,如果不存在会报错，这里用ErrorAction SilentlyContinue 来忽略错误

    }
    else
    {
        Write-Verbose "No [$EnvVar] was found! Nothing to Remove."
    }

}

function Set-EnvVar
{
    <# 
    .SYNOPSIS
    将已有的环境变量值做修改(增/改/删)
    .DESCRIPTION
    如果只希望对已有的环境变量添加一个值,例如Path变量追加一个取值,则使用Add-EnvVar处理
    如果想要编辑多个值的变量,例如修改Path变量(删除它的一个路径值),这类情况建议打开gui操作
    当然本命令也是可以改的,但是在终端CLI中处理字符串却不会比GUI容易执行这类修改


    .EXAMPLE
    #将new3这个环境变量设置为v3p,无论原来的值是多少(如果原来没有这个环境变量,则新添加一个环境变量)
    Set-EnvVar -EnvVar new3 -NewValue v3p
    .EXAMPLE
    PS>Set-EnvVar -EnvVar new3 -NewValue v3R
    v3R
    PS>$env:new3
    v3R
    PS>Set-EnvVar -EnvVar new3 -NewValue v3S
    v3S
    PS>$env:new3
    v3S
    .EXAMPLE
    PS>$env:new100
    PS>Set-EnvVar -EnvVar new100 -NewValue v100
    v100
    PS>$env:new100
    v100
    .EXAMPLE
    #移除环境变量
    PS>Set-EnvVar -EnvVar new100 -NewValue ''
    PS>$env:new100
    PS>
    #>
    [CmdletBinding()]
    param (                                
        [Alias('Key', 'Name')]$EnvVar = '',
        [alias('Value')]$NewValue = 'NewValue',
        $Scope = 'User'
    )
    #移除旧值(如果旧值非空的话)
    Remove-EnvVar -EnvVar $EnvVar -Scope $Scope
    #添加新值
    Add-EnvVar -EnvVar $EnvVar -NewValue $NewValue -Scope $Scope 
}
function Get-EnvCountedValues
{
    <# 
    .SYNOPSIS
    以管道符的方式,接受从Get-EnvVar envvar获得的结果,统计取多个值的环境变量envvar的所有取值并列出

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [PSCustomObject]$InputObject
    )

    process
    {
        $inputObject.value -split ';' | catn
    }
}


function Update-EnvVarFromSysEnv
{
    <# 
    .SYNOPSIS
    更新所有环境变量的修改(包括添加新值/移除已有值/修改值),并且能够指出那些环境变量被修改了以及修改前后是什么样的
    可以手动调用来刷新当前shell的环境变量

    👺鉴于Path变量的特殊性,本函数不会处理Path变量;并且PsModulePath和Path有类似的特点,也应该跳过不处理

    😊本函数本身不会修改[Environment]中的环境变量,即不会影响系统保存的环境变量,无论是用户级还是系统,只更新当前shell中的环境变量

    对于多个shell窗口同时发生修改环境变量的情形时很有用,当然如果您习惯用GUI修改环境变量,本方法也可以将您的修改同步到当前shell(除了Path变量外)

    通常调用Set-EnvVar 或Add-EnvVar 更改var环境变量时,会自动更新当前shell的var环境变量($env:var查询到的值)
    但是如果在多个不同的shell窗口内分别调用了Set-EnvVar或Add-EnvVar,那么可能会造成变量信息的不一致
    为了避免这种情况,可以调用此函数更新所有shell的环境变量
    注意本函数以[Environment]对象中存储的环境变量信息为准,如果当前shell的环境变量不同于[Environment]中查询到的那样,则会更新为[Environment]中查询到的值

    如果当前shell有不存在于[Environment]中的环境变量,则认为是改shell环境的临时环境变量,调用本函数并不会更改或影响到这些变量
    这些情况是存在的,有些场合下我们只需要创建临时的环境变量而不需要写入系统保存

    默认读取的是User级别的环境变量
    .#>
    [CmdletBinding()]
    param(

        $Scope = 'Combined'
    )
    $envs = [System.Environment]::GetEnvironmentVariables($Scope)
    # 扫描所有的注册表中已有的环境变量,将其同步到当前powershell中,防止在不同shell中操作环境变量导致的不一致性
    $envs.GetEnumerator() | Where-Object { $_.Key -notin 'Path', 'PsModulePath' } 
    | ForEach-Object {
        # Write-Output "$($_.Name)=$($_.Value)"
        $left = "`$env:$($_.Name)"
        $expressoin = "$left='$($_.Value)'"
        $CurrentValue = $left | Invoke-Expression
        if ($CurrentValue -ne $_.Value)
        {
            # Write-Host "$left from `n`t[$(Invoke-Expression($left))] `n=TO=> `n`t [$($_.Value)]" -BackgroundColor Magenta
            $expressoin | Invoke-Expression
        }
    }
}
