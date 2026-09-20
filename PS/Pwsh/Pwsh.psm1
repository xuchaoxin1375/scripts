

function Confirm-ModuleInstalled
{
    <# 
    .SYNOPSIS
    判断检查指定模块是否已经安装可用,如果不可用则尝试安装该模块(使用comfirm动作包装)

    #>
    [cmdletbinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]
        [alias('ModuleName')]$Name, 
        [ValidateSet('CurrentUser', 'AllUsers')]$Scope = 'CurrentUser',
        [switch]$Install,
        [switch]$Import
    )
    $moduleAvailability = Get-Module -ListAvailable -Name $name #查询一个要几十毫秒
    if ($moduleAvailability)
    {
        Write-Verbose "Module $Name is already installed"
    }
    elseif($Install)
    {
        if($PSCmdlet.ShouldProcess($Name, 'Install Module'))
        {
        
            try
            {
                Install-Module -Name $Name -Scope $Scope -Force -ErrorAction Stop
                $moduleAvailability = Get-Module -ListAvailable -Name $name #再次查询
            }
            catch
            {
                Write-Warning "Install-Module 失败: $($_.Exception.Message)"
                return $False
            }
        }
    }
    else
    {
        return $False
    }
    if($moduleAvailability -and $Import)
    {
        Import-Module $Name
    }
    return $True


}
function Set-PsExtension
{
    <# 
.SYNOPSIS
是否启用额外的相关扩展
.DESCRIPTION
检查环境变量extent,如果取值为True,那么指导用户安装或启用相应的模块
否则跳过不处理这部分扩展内容
#>
    [CmdletBinding(DefaultParameterSetName = 'PsExtension')]
    param (
        [parameter(ParameterSetName = 'PsExtension')]
        # 要安装的模块列表
        #按照实用性排序
        $modules = @(

            # 补全模块
            'CompletionPredictor'
            # 'PsCompletions' #这里导入此模块会报错(可能有冲突,请在其他位置导入此模块)
            
            # 目录跳转
            # 'ZLocation' 使用更加强大和通用的zoxide替代(跨平台高性能方案,无需通过powershell导入)
            # 'z'
            
            # 美化模块
            # 'Terminal-Icons' #速度较慢,不默认启用
        ),
        # 安装模块的范围
        [ValidateSet('CurrentUser', 'AllUsers')]$Scope = 'CurrentUser',
        
        # 是否启用额外的相关扩展
        # 出于加载速度和轻便性考虑，不默认启用这部分扩展功能
        [parameter(ParameterSetName = 'Switch')]
        [ValidateSet('On', 'Off')]
        [parameter(Position = 0)]
        $Switch = 'Off'
    )
    if ($PSCmdlet.ParameterSetName -eq 'Switch')
    {

        if ($Switch -eq 'Off')
        {
            
            Write-Verbose 'Skip pwsh extension functions!' -Verbose
            Set-EnvVar -Name 'PsExtension' -NewValue 'False'
        }
        elseif ($Switch -eq 'On')
        {
            
            Set-EnvVar -Name 'PsExtension' -NewValue 'True'
        }
    }
    elseif ($env:PsExtension -eq 'True')
    {

        # scoop 相关
        # Invoke-Expression (&scoop-search --hook)
        # 检查模块是否已经安装,必要时安装对应的模块
        $i = 0
        $count = $modules.Count
        $report = @()
        # $AvailableModules = Get-Module -ListAvailable #性能不佳，不做-Name的话会耗费几百毫秒
        foreach ($module in $modules)
        {
            # 检查指定模块是否可用,如果不可用则尝试安装该模块(使用comfirm动作包装)
            Confirm-ModuleInstalled -Name $module -Scope $Scope -Install

            # Write-Verbose "Importing module $module" -Verbose
            # $moduleAvailability | Import-Module 
            # 执行导入操作
            # Import-Module $module 
            $res = Measure-Command { 
                Import-Module $module -Verbose:$false
            }
            
            #显示进度条(顶层 Id,不再挂 ParentId 0:init 已无父进度条,悬空父引用会导致残留)
            $completed = [math]::Round($i++ / $count * 100, 1)
            # Start-Sleep -Milliseconds 500
            Write-Progress -Activity 'Importing Modules... ' -Id 1 -Status " $module progress: $completed %" -PercentComplete $completed

            #准备报告导入情况信息 
            $time = [int]$res.TotalMilliseconds
            $res = [PSCustomObject]@{
                Module = $module
                time   = $time
            }
            $report += $res
        }

        $totalTime = $report | Measure-Object -Property time -Sum | Select-Object -ExpandProperty Sum
        # 准备视图
        $report = $report | Sort-Object -Descending time # | Format-Table #| Out-String 
        
        
        Write-Progress -Activity 'Importing Modules... ' -Id 1 -Completed
        if ($InformationPreference)
        {
            # Write-Host $report
            Write-Output $report

            Write-Verbose "Time Of importing modules: $($totalTime)" -Verbose
        }
        # return $report
        #其他模块导入后的提示信息
        # Write-Host -Foreground Green "`n[ZLocation] knows about $((Get-ZLocation).Keys.Count) locations.`n"
    }
    
}
function Add-CxxuPsModuleToProfile

{
    <# 
    .SYNOPSIS
    将此模块集推荐的自动加载工作添加到powershell的配置文件$profile中
    .DESCRIPTION
    写入位置为$profile;
    在vscode中,情况和普通终端管理器(例如windows terminal)中有所不同,尤其是如果用户启用了powershell extension terminal时;
    建议不要使用这个特殊的交互式shell,powershell extension用其服务于powershell语言服务器,提供语法检查等功能,而不适合用于交互式使用;
    在这个shell环境下,$profile取值和vscode相关.
    可以考虑使用powershell.integratedConsole.startInBackground此选项会从终端列表中隐藏powershell extension terminal;
    
    .PARAMETER ProfileLevel
    默认情况下写入的是$Profile.CurrentUserCurrentHost
    您也可以选择其他等级的配置,例如最大作用等级$Profile.AllUsersAllHosts
    .Notes
    注意,为所有用户设置需要管理员权限
    .NOTES
    如果要移除,则建议通过编辑对应级别的$Profile来移除相关语句
    比如 移除命令p
     #>
    param (
        $ProfileLevel = $Profile
    )
    # 确保文件存在
    New-Item -ItemType File -Path $ProfileLevel -Force -Verbose -ErrorAction SilentlyContinue
    $pf = $ProfileLevel
    Update-PwshEnvIfNotYet
    '# AutoRun commands from CxxuPsModules' + " $(Get-Date)" >> $pf
    Get-Content $scripts/config/core_ps_profile.ps1 >>$pf #向配置文件追加内容
    '# End AutoRun commands from CxxuPsModules' >> $pf
}
function Add-CxxuPsModuleToEnvVar
{
    <# 
    .SYNOPSIS
    在调用此函数前需要你配置好环境变量
    或者修改$env:PsmodulePath=";$CxxuPsModulePath"
    .DESCRIPTION
    默认仅为当前用户的psmodulepath添加此模块集的路径,部分情况下,比如通过nsudo使用trustedInstaller权限的pwsh窗口中,是不访问用户级别的环境变量的,你需要将$CxxuPsModulePath添加到系统级别的PsModulePath路径中才有效
    使用次函数方便这个过程
    或者在删除了$CxxuPsModulePath后重新设置的时候调用一下把路径加回去
    .EXAMPLE
    Add-EnvVar PSModulePath $env:PSModulePath -Scope Machine 
    #>
    param (
        [ValidateSet('Machine', 'User')]$Scope = 'User'
    )
    # $CxxuPsModulePath = "../$PsScriptRoot"
    $CxxuPsModulePath = $env:CxxuPsModulePath 
    Write-Host 'CxxuPsModulePath:' $CxxuPsModulePath
    Add-EnvVar -EnvVar PsModulePath -NewValue $CxxuPsModulePath -Verbose -Scope $Scope
    
}
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
function New-ModuleByCxxu
{
    param(
        $ModuleName
    )
    Update-PwshEnvIfNotYet -Mode Vars
    
    $ModuleDir = "$PS\$ModuleName"
    mkdir $ModuleDir
    New-Item "$ModuleDir\$ModuleName.psm1"

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
function Import-ModuleForce
{
    <# 
    .SYNOPSIS
    只重载仓库内已加载模块(白名单即本意:刷新我改过的模块,变量不丢);第三方/系统模块一律不动,仍配合 iex 在当前作用域执行
    #>
    [CmdletBinding()]
    param (
        # [switch]$PassThru
    )

    # 白名单根:本函数所在模块的上级目录(即 PS/ 仓库目录),自举不依赖外部变量
    $repoRoot = Split-Path -Parent $PSScriptRoot

    # 获取当前已经加载且位于仓库内的模块(动态模块 Path 为空,天然排除)
    $modules = Get-Module | Where-Object {
        $_.Path -and $_.Path.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -ExpandProperty Name

    $res = @()
    foreach ($module in $modules)
    {
        # 纵深防御:import 有副作用的仍跳过(黑名单,和白名单叠加)
        # completion:注册补全的模块谨慎重载;predictor:运行时注册+缓存表由加载器一次性建好,裸重载只恢复注册不恢复表,会静默放空
        # conda:Conda.psm1 每次 import 都 Rename-Item prompt 为 CondaPromptBackup 再包一层(ChangePs1 缺省真),裸重载=每轮多一层 prompt
        if ($module -like '*completion*' -or $module -like '*predictor*' -or $module -like '*conda*')
        { 
            Write-Warning "Skipping $module"
            continue 
        }
        Remove-Module $module -ErrorAction SilentlyContinue -Force

        # Import-Module $module -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        $exp = "Import-Module $module -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue"
        $res += $exp
        Write-Verbose "Imported $module "
    }
    # if ($PassThru)
    # {

    #     return $res -join "`n"
    # }
    return $res -join "`n"
}
function ipmof
{
    <# 
    .SYNOPSIS
    作为Import-ModuleForce的别名
    由于同一个会话下,powershell无法自动更新已经导入但发生变化的模块,这时候用户有两个选择:
    重新执行pwsh,或者使用ipmo(Import-Module) 配合-Force参数强制重载相应的模块
    前者重载得彻底,但是会无法继承父级会话中的环境,比如定义的变量在新开的pwsh中无法访问,而且开销比较大,速度慢
    后者一种方法更加轻量,由于不会创建新的pwsh进程,不会造成环境变量丢失,但是一个个检查模块然后重新加载对于开发者来说不方便
    为此编写了此函数,可以直接重载仓库内(PS/ 路径下)已经加载了的模块,方便了这一个刷新变更了的模块的过程
    .NOTES
    一个有意思的现象是,如果自动导入模块的路径$PsModulePath下的模块如果在当前powershell会话中没有加载,例如某个函数x在模块test中
    而当前shell环境没有调用x,也没有调用模块test中的任意函数,或定义的东西,此时对此摸块做了更改后,不需要刷新,在当前会话shell中调用test的变更的内容是自动更新的,也就是说会自动刷新
    可以重载已经加载了的模块,对于开发测试powershell模块很有用
    .Notes
    本函数调用要配合iex,效果比较稳定,如果你的模块比价简单,那么可以更改import-ModuleForce内部让其直接执行强制导入
    .EXAMPLE
    重载已经加载了的模块:
    ipmof|iex
    .ExAMPLE
    Import-ModuleForce -verbose|iex

    #>
    param (
    )
    # Import-Module PSReadLine -Force
    # prompt=$originalPromptScript
    Import-ModuleForce
    # $currentPromptScript = $function:prompt
    # Write-Verbose "[[$currentPromptScript]]" -Verbose
    # Set-Item -Path Function:prompt -Value $currentPromptScript
    
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

function Get-PsProfilesPath
{
    <# 
    .SYNOPSIS
    获取所有的$profile级别文件路径,即便文件不存在
    #>
    [CmdletBinding()]
    param(
        # 是否只返回存在文件
        [switch]$ExistOnly
    )
    $profiles = @(
        $profile.CurrentUserCurrentHost,
        $profile.CurrentUserAllHosts,
        $profile.AllUsersCurrentHost,
        $profile.AllUsersAllHosts
    )
    if ($ExistOnly)
    {
        $profiles = $profiles | Where-Object { Test-Path $_ }
    }
    return $profiles
}
 
function Remove-PsProfiles
{
    $profiles = Get-PsProfilesPath
    foreach ($pf in $profiles)
    {
        Remove-Item -Force -Verbose $pf -ErrorAction SilentlyContinue
    }
}


function Confirm-PsVersion
{
    <# 
    .SYNOPSIS
    如果当前版本高于指定版本，则返回当前版本对象，否则返回$False
    直接抛出版本过低的提示错误有点过头了
    #>
    param (
        $Major = 7,
        $Minor = 0,
        $Build = 0

    )
    $version = $host.Version
    if ($Version.Major -ge $Major -and $Version.Minor -ge $Minor -and $Version.Build -ge $Build)
    {
        # $res = $True
        # Write-Host 
        return $Version
    }
    else
    {
        # $res = $false
        Write-Host "Powershell version is lower than $Major.$Minor.$Build" -ForegroundColor Red
        return $False
    }
    # return $res
    
}

function Install-ScoopByLocalProxy
{
    param (
        [ValidateSet('Default', 'Proxy')]$Method = 'Default'
    )
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser # Optional: Needed to run a remote script the first time
    switch ($Method)
    {
        'Default'
        { 
            Write-Host 'Installing scoop in default channel...'
        }
        'Proxy'
        {
            Set-Proxy -Status on
            Write-Host 'Installing scoop in proxy channel...'
            Get-ProxyEnvVarSettings
        }
        default {}
    }
    Invoke-Expression (New-Object net.webclient).downloadstring('https://get.scoop.sh')
    
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
function Operators_Comparison_pwsh
{
    help about_Comparison_Operators
}
function  Operators_Logical_pwsh
{
    help about_Logical_Operators
}



function Update-PowerShellLegacy
{
   
    Write-Output '@maybe you need to try severial times!...'
    Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI"
}

function Get-LatestPowerShellDownloadUrl
{
    param(
        [ValidateSet('msi', 'zip')]$PackageType = 'msi'
    )
    $releasesUrl = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    $releaseInfo = Invoke-RestMethod -Uri $releasesUrl -Headers @{ 'User-Agent' = 'PowerShell-Script' }

    Write-Host "Trying to get latest PowerShell ${PackageType}..."
    foreach ($asset in $releaseInfo.assets)
    {
        if ($asset.name -like "*win-x64.${PackageType}")
        {
            return $asset.browser_download_url
        }
    }
    throw 'No suitable installer found in the latest release.'
}

# 更新 PowerShell 并显示当前版本
# Update-Powershell
function Update-PowerShell
{
    try
    {
        $downloadUrl = Get-LatestPowerShellDownloadUrl
        # 替换为加速链接(配合IDM发挥效果)
        $downloadUrl = Get-SpeedUpUri $downloadUrl
        
        Write-Host $downloadUrl -ForegroundColor Cyan
        $installerPath = "$env:userprofile\Downloads\pwsh7Last.msi"

        Write-Host "Downloading PowerShell installer from $downloadUrl..."
        # Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        # 使用aria2下载
        aria2c.exe $downloadUrl -d $env:userprofile\Downloads -o 'pwsh7Last.msi'

        Write-Host 'Installing PowerShell...'
        Start-Process $installerPath
    }
    catch
    {
        Write-Host "An error occurred: $_"
        return
    }

    # 获取当前 PowerShell 版本
    $currentVersion = $PSVersionTable.PSVersion
    Write-Host "Current PowerShell version: $currentVersion"
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
function Remove-RobocopyMirEmpty
{
    <# 
    .SYNOPSIS
    使用 RoboCopy 多线程快速删除文件夹及其内容。

    .DESCRIPTION
    此函数利用 RoboCopy 的 /mir 参数和多线程能力快速删除文件夹及其所有内容。
    比传统的 Remove-Item 或 cmd 的 rd/del 命令在处理大量文件时更高效。

    .PARAMETER Path
    指定要删除的文件夹路径。支持相对路径和绝对路径。

    .PARAMETER ThreadCount
    指定 RoboCopy 使用的线程数。默认值为 32，可根据系统性能调整。

    .PARAMETER WhatIf
    显示将要执行的操作，但不实际执行删除。

    .PARAMETER Confirm
    在执行删除前提示确认。

    .EXAMPLE
    Remove-RobocopyMirEmpty -Path "C:\LargeFolder"
    删除 C:\LargeFolder 及其所有内容。

    .EXAMPLE
    Remove-RobocopyMirEmpty -Path ".\TempFiles" -ThreadCount 64 -WhatIf
    模拟使用64个线程删除当前目录下的 TempFiles 文件夹。

    .NOTES
    文件名: Remove-RobocopyMirEmpty.ps1
    日期: $(Get-Date -Format 'yyyy-MM-dd')

    .LINK
    https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if (-not (Test-Path -Path $_ -PathType Container))
                {
                    throw "路径 '$_' 不存在或不是文件夹"
                }
                $true
            })]
        [string]$Path,

        [Parameter()]
        [ValidateRange(1, 128)]
        [int]$ThreadCount = 32,
        $logFile = "C:/temp/robocopy_mir_empty.log"
    )

    begin
    {
        # 创建临时空目录
        $emptyDir = Join-Path -Path $env:TEMP -ChildPath "RoboCopyEmpty_$(New-Guid)"
        $null = New-Item -Path $emptyDir -ItemType Directory -Force
    }

    process
    {
        try
        {
            $fullPath = Convert-Path -Path $Path 
            

            if ($PSCmdlet.ShouldProcess($fullPath, "删除文件夹及其所有内容"))
            {
                Write-Verbose "正在使用 RoboCopy 删除文件夹: $fullPath (线程数: $ThreadCount)"
                
                # 执行 RoboCopy 删除操作
                $robocopyArgs = @(
                    "'$emptyDir'"
                    "'$fullPath'"
                    "/mir"          # 镜像空目录
                    "/mt:$ThreadCount" # 多线程
                    "/E" #递归处理

                    "/log:'$logFile'"
                    # "/nfl"          # 不记录文件名
                    # "/ndl"          # 不记录目录名
                    # "/njh"          # 无作业头
                    # "/njs"          # 无作业摘要
                    # "/ns"           # 无大小
                    # "/nc"          # 无类别
                )
                $argsStr = $robocopyArgs -join "  "
                # $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
                $cmd = "Robocopy.exe $argsStr" 
                Write-Verbose $cmd -Verbose

                $cmd | Invoke-Expression

                if ($process.ExitCode -ge 8)
                {
                    Write-Warning "RoboCopy 完成但可能有错误 (退出代码: $($process.ExitCode))"
                }
                else
                {
                    Write-Verbose "RoboCopy 成功完成 (退出代码: $($process.ExitCode))"
                }

                # 删除空文件夹
                Remove-Item -Path $fullPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch
        {
            Write-Error "删除文件夹时出错: $_"
            throw
        }
    }

    end
    {
        # 清理临时空目录
        if (Test-Path -Path $emptyDir)
        {
            Remove-Item -Path $emptyDir -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}
function Copy-Robocopy
{
    <# 
    .Synopsis
    对多线程复制工具Robocopy的简化使用封装,使更加易于使用,语法更加接近powershell命令
    默认启用多线程复制,如果需要递归,需要手动启用-Recurse选项
    .DESCRIPTION
    - 帮助用户更加容易的使用robocopy的核心功能(多线程复制和递归复制),作为常规copy命令的一个补充
    - 而简单的单文件复制一般用普通的copy命令就足够方便快捷了
    如果需要输出日志,使用LogFile参数指定日志文件
    .EXAMPLE
    #robocopy 原生用法常见语法用例举例
    #1:将复制过程的输出重定向到指定文件中(始终推荐使用LOG参数指定日志输出,经验表明,日志输出到屏幕会对性能有重大影响(可达10倍以上))
    PS> Robocopy.exe .\7.us\ .\rb1 /E /B /MT:8  /LOG:07091121
      日志文件: C:\sites\wp_sites\07091121

    #2: 适用于从网络复制的场景,增加更多参数(重试,详细日志级别等)
    robocopy C:\source\folder\path\ D:\destination\folder\path\ /E  /MT:32  /ZB /R:5 /W:5 /V /LOG:C:\log\robocopy.log
    
    参数	含义	推荐用途
    /E	复制所有子目录，包括空目录	确保完整复制整个目录结构
    /V	显示详细信息（包括跳过文件）	调试或审计用
    /MT[:n]	多线程复制（默认 8，最大 128）	提升 I/O 性能
    /ZB :: 使用可重新启动模式；如果拒绝访问，请使用备份模式。(效果是/Z /B)
        使用可重启模式 + 强制权限访问	网络复制 + 克服锁定文件(需要管理员权限才能访问某些受保护的系统文件)
    /R:n	失败重试次数（默认 1000000）	控制失败后的尝试次数
    /W:n	重试等待时间（秒）	避免频繁失败冲击资源

    .ExAMPLE
    PS C:\Users\cxxu\Desktop> copy-Robocopy -Source .\dir4 -Destination .\dir1\ -Recurse
    The Destination directory name is different from the Source directory name! Create the Same Name Directory? {Continue? [y/n]} : y
    Executing: robocopy ".\dir4" ".\dir1\dir4"  /E /MT:16 /R:1 /W:1

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        #第一批参数
        [Parameter(Mandatory = $true, Position = 0)]
        $Source,

        [Parameter(Mandatory = $true, Position = 1)]
        $Destination,

        [Parameter(Position = 2)]
        [string[]]$Files = '',
        [int]$Threads = 16, #默认是8
        [switch]$Recurse,
        # 控制失败时重试的次数和时间间隔(一般不用重试,基本上都是权限问题或者符号所指的连接无法访问或找不到)
        $Retry = 1,
        $Wait = 1,
        [string]$LogFile = "",
        $LogPreviewEncodings = 'ansi',
        # 不询问直接执行所有步骤
        [switch]$Force,

        # 第二批
        $ExcludeDirs = '',
        $ExcludeFiles = '',
        [switch]$RecurseWithoutEmptyDirs,
        [switch]$ContinueIfbroken,

        # 第三批
        [switch]$Mirror,

        [switch]$Move,

        [switch]$NoOverwrite,

        [switch]$V,

        [string[]]$OtherArgumentList
    )
    if(!$LogFile)
    {
        Write-Warning "No LogFile specified, the output will be displayed on the console and the speed will be affected seriously!"
        Write-Warning "Stop and restart with -LogFile <logFilePath> is recommended!(such as '-LogFile C:\log\robocopy.log')" -WarningAction Inquire
    }
    # Construct the robocopy command
    # 确保source和destination都是目录
    if (Test-Path $Source -PathType Leaf)
    {
        throw 'Source must be a Directory!'
    }if (Test-Path $Destination -PathType Leaf)
    {
        throw 'Destination must be a Directory!'
    }

    Write-Host 'checking directory name...'
    #向用户展示参数设置🎈
    # $PSBoundParameters  
    # 注意,$source和$destination在函数参数定义时不可以定为String类型,会导致Get-PsIOItemInfo返回值无法正确赋值
    Write-Debug "Source: $Source"
    Write-Debug "Destination: $Destination"
    if($Files)
    {
        Write-Debug "Files: $Files"
    }
    # $Source = Get-PsIOItemInfo $Source
    # $destination = Get-PsIOItemInfo $Destination

    # 检查目录名是否相同(basename)
    # $SN = $source.name
    # $DN = $Destination.name
    $SN = Split-Path -Path $Source -Leaf
    $DN = Split-Path -Path $Destination -Leaf

    Write-Verbose "$SN,$DN" 
    if ($Force -and !$Confirm)
    {
        $ConfirmPreference = 'none'
    }
    # if ($SN -ne $DN)
    # {
    #     # Write-Verbose "$($Source.name) -ne $($destination.name)"

    #     $msg = 'The Destination directory name is different from the Source directory name! Create the Same Name Directory?'
    #     # $continue = Confirm-UserContinue -Description 
    #     $continue = $PSCmdlet.ShouldProcess($Destination, $msg)
    #     if ($continue)
    #     {
    #         $Destination = Join-Path $Destination $SN
    #         Write-Verbose "$Destination" -Verbose
    #     }
    # }

    #debug
    # return
    $robocopyCmd = "robocopy `"$Source`" `"$Destination`" $Files"

    if ($Mirror)
    {
        $robocopyCmd += ' /MIR'
    }

    if ($Move)
    {
        $robocopyCmd += ' /MOVE'
    }

    if ($NoOverwrite)
    {
        $robocopyCmd += ' /XN /XO /XC'
    }

    if ($Verbose)
    {
        $robocopyCmd += ' /V'
    }

    if ($LogFile)
    {
        $robocopyCmd += " /LOG:`"$LogFile`""
    }

    # if ($Threads -gt 1)
    # {
    #     $robocopyCmd += " /MT:$Threads"
    # }
    if ($OtherArgumentList)
    {
        $robocopyCmd += ' ' + ($OtherArgumentList -join ' ')
    }
    if ($Recurse)
    {
        $robocopyCmd += ' /E'
    }
    # if ($ContinueIfbroken)
    # {
    #     $robocopyCmd += ' /Z'
    # }
    if ($RecurseWithoutEmptyDirs)
    {
        $robocopyCmd += ' /S'
    }if ($ExcludeDirs)
    {
        $robocopyCmd += " /XD $ExcludeDirs"
    }if ($ExcludeFiles)
    {
        $robocopyCmd += " /XF $ExcludeFiles"
    }

    # 默认使用(每个参数前有一个空格分割)
    $robocopyCmd += " /MT:$Threads"
    #默认启用自动重连(断点续传)
    $robocopyCmd += ' /ZB' 
    # 重试次数和间隔限制
    $robocopyCmd += " /R:$Retry /W:$Wait"


    if($PSCmdlet.ShouldProcess($Destination, "Executing: $robocopyCmd"))
    {

        Invoke-Expression $robocopyCmd
        
    }
    
    Write-Verbose "Set LogPreviewEncodings to Preview log in specified way(utf-8,ansi,gbk,etc)" -Verbose
    # 预览日志总结
    if($LogFile -and (Test-Path $LogFile))
    {
        Get-Content $logFile -Encoding $LogPreviewEncodings | Select-Object -Last 13
    }
}

function Sync-ModuleManifest
{
    <#
    .SYNOPSIS
    偷懒同步:把 .psm1 里新增的函数自动补进 .psd1 的 FunctionsToExport(只增不减)。
    .DESCRIPTION
    改完 .psm1 后跑 Sync-ModuleManifest <模块名> -Reload,新函数即可调用,免手改 manifest。
    不指定模块名则处理全部自有模块(只打印有变化的+汇总;批量重载跳过 Prompt 防嵌套)。
    只追加缺失项(按 .psm1 定义顺序),从不删除;GUID/版本/其它字段原样保留,换行原样保留。
    .EXAMPLE
    Sync-ModuleManifest Mock -Reload
    .EXAMPLE
    Sync-ModuleManifest -Reload
    #>
    [CmdletBinding()]
    param(
        # 不指定 = 全部自有模块(PS/ 下有同名 .psm1 的目录;Tab 补全模块名)
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $pwshMod = Get-Module Pwsh | Select-Object -First 1
            if (-not $pwshMod) { return }
            $root = Split-Path $pwshMod.ModuleBase -Parent
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -like "$wordToComplete*" -and
                    (Test-Path -LiteralPath (Join-Path $_.FullName ($_.Name + '.psm1'))) } |
                ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new(
                        $_.Name, $_.Name, 'ParameterValue', "同步 $($_.Name) 的 manifest") }
        })]
        $Name,
        [switch]$Reload,
        # 批量内部递归用:静默(有变化才由调用方汇总打印)并返回结果对象
        [switch]$Quiet
    )
    if (-not $Name)
    {
        $psRoot = Split-Path $PSScriptRoot -Parent
        $targets = @(Get-ChildItem -LiteralPath $psRoot -Directory | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName ($_.Name + '.psm1')) } |
            Select-Object -ExpandProperty Name | Sort-Object)
        $results = @(foreach ($n in $targets) { Sync-ModuleManifest -Name $n -Quiet })
        $changedMods = @($results | Where-Object { -not $_.Failed -and $_.Added.Count -gt 0 })
        $failedMods = @($results | Where-Object { $_.Failed })
        foreach ($r in $changedMods)
        {
            Write-Host "$($r.Module) 已追加 $($r.Added.Count) 个: $($r.Added -join ', ')"
        }
        foreach ($f in $failedMods)
        {
            Write-Warning "$($f.Module): $($f.Failed)"
        }
        if ($Reload -and $changedMods.Count -gt 0)
        {
            foreach ($r in $changedMods)
            {
                if ($r.Module -eq 'Prompt')
                {
                    Write-Warning 'Prompt 有变更已同步文件,跳过重载(防提示符嵌套),请重进 shell'
                    continue
                }
                Import-Module $r.Module -Force -DisableNameChecking -Global
                foreach ($m in $r.Added)
                {
                    if (-not (Get-Command $m -ErrorAction SilentlyContinue))
                    {
                        Write-Warning "$m 同步后仍不可调用(请检查函数体是否有语法错)"
                    }
                }
            }
        }
        $okCount = $targets.Count - $changedMods.Count - $failedMods.Count
        Write-Host "同步完成:共 $($targets.Count) 个模块,$($changedMods.Count) 个有追加,$($failedMods.Count) 个失败,${okCount} 个已同步"
        return
    }
    $n = $Name
    $mod = Get-Module -ListAvailable $n | Select-Object -First 1
    if (-not $mod)
    {
        $msg = "找不到模块 ${n}(PSModulePath 自动发现无此模块)"
        if ($Quiet) { Write-Warning $msg; return [PSCustomObject]@{ Module = $n; Failed = $msg; Added = @() } }
        Write-Error $msg
        return
    }
    $psm1 = Join-Path $mod.ModuleBase "$n.psm1"
    $psd1 = Join-Path $mod.ModuleBase "$n.psd1"
    if (-not (Test-Path -LiteralPath $psm1))
    {
        $msg = "缺少 $psm1(目录名/模块名/psm1 基名必须一致)"
        if ($Quiet) { Write-Warning $msg; return [PSCustomObject]@{ Module = $n; Failed = $msg; Added = @() } }
        Write-Error $msg
        return
    }
    if (-not (Test-Path -LiteralPath $psd1))
    {
        $msg = "缺少 $psd1(本函数只做同步,不新建 manifest)"
        if ($Quiet) { Write-Warning $msg; return [PSCustomObject]@{ Module = $n; Failed = $msg; Added = @() } }
        Write-Error $msg
        return
    }
    # 块注释感知解析(与对账脚本同规则):先去 <#...#> 块,再取行首 function
    $noBlock = [regex]::Replace((Get-Content -LiteralPath $psm1 -Raw), '<#.*?#>', '', 'Singleline')
    $defined = @($noBlock -split "`r?`n" | ForEach-Object {
        if ($_ -cmatch '^function\s+([\w-]+)\s*(\{|\(|$|#)') { $Matches[1] }
    } | Select-Object -Unique)
    $exported = @(Import-PowerShellDataFile -LiteralPath $psd1 | Select-Object -ExpandProperty FunctionsToExport)
    $missing = @($defined | Where-Object { $_ -notin $exported })
    $orphan = @($exported | Where-Object { $_ -notin $defined })
    foreach ($o in $orphan)
    {
        Write-Warning "${n}: $o 在 manifest 中但 .psm1 里没有定义(只提醒,不删除)"
    }
    if ($missing.Count -eq 0)
    {
        if (-not $Quiet) { Write-Host "${n} 已同步(导出 $($exported.Count) 个,无新增)" }
    }
    else
    {
        # 文本级追加:换行/其它内容原样保留,只动 FunctionsToExport 数组尾
        $raw = Get-Content -LiteralPath $psd1 -Raw
        $eol = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
        $lines = @($raw -split "`r?`n")
        $start = -1
        for ($k = 0; $k -lt $lines.Count; $k++)
        {
            if ($lines[$k] -match 'FunctionsToExport\s*=\s*@\(') { $start = $k; break }
        }
        $end = -1
        for ($k = $start + 1; $k -lt $lines.Count; $k++)
        {
            if ($lines[$k] -match '^\s*\)') { $end = $k; break }
        }
        if ($start -lt 0 -or $end -lt 0)
        {
            $msg = "$psd1 里找不到 FunctionsToExport 数组(模板被改过?请手改)"
            if ($Quiet) { Write-Warning $msg; return [PSCustomObject]@{ Module = $n; Failed = $msg; Added = @() } }
            Write-Error $msg
            return
        }
        # manifest 受限语言不认数组尾逗号(@('a',) 非法):新增项只有非末项带逗号;
        # 前一项若无逗号则补(模板末项本就没有);空数组(@( 后直接 ))则不动前行。
        $prev = $end - 1
        while ($prev -gt $start -and $lines[$prev] -match '^\s*$') { $prev-- }
        if ($lines[$prev] -notmatch '@\($' -and $lines[$prev] -notmatch ',\s*(#.*)?$')
        {
            $lines[$prev] += ','
        }
        $add = @()
        for ($m = 0; $m -lt $missing.Count; $m++)
        {
            $suffix = if ($m -eq $missing.Count - 1) { '' } else { ',' }
            $add += "        '$($missing[$m])'$suffix"
        }
        $newLines = @($lines[0..($end - 1)] + $add + $lines[$end..($lines.Count - 1)])
        [IO.File]::WriteAllText($psd1, ($newLines -join $eol), [Text.UTF8Encoding]::new($false))
        if (-not $Quiet) { Write-Host "${n} 已追加 $($missing.Count) 个: $($missing -join ', ')" }
    }
    if ($Reload)
    {
        # -Global:在模块函数内 Import-Module 默认装成嵌套模块(Get-Module 列不出),强制顶层
        Import-Module $n -Force -DisableNameChecking -Global
        foreach ($m in $missing)
        {
            if (-not (Get-Command $m -ErrorAction SilentlyContinue))
            {
                Write-Warning "$m 同步后仍不可调用(请检查函数体是否有语法错)"
            }
        }
    }
    if ($Quiet)
    {
        return [PSCustomObject]@{ Module = $n; Failed = $null; Added = @($missing) }
    }
}


