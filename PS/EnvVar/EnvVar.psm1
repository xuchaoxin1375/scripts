function Clear-EnvVar
{
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

# Example usage:
# Clear-EnvironmentVariables -Scope "User"
# Clear-EnvironmentVariables -Scope "System"
function Format-EnvItemNumber
{
    <#
    .SYNOPSIS 
    辅助函数,用于将Get-EnvList(或Get-EnvVar)的返回值转换为带行号的表格
    如果放在脚本(.ps1)中要放在Get-EnvList之前
    如果放在模块(.psm1)中,则位置可以随意一点
     #>
    param(
        $EnvVars,
        #是否显式传入Scope
        [switch]$Scope
    )
    $res = for ($i = 0; $i -lt $EnvVars.Count; $i++)
    {
        [PSCustomObject]@{
            'Number' = $i + 1
            'Scope'  = $Scope ? $EnvVars[$i].Scope :'Default'
            'Name'   = $EnvVars[$i].Name
            'Value'  = $EnvVars[$i].Value
        }
    }
    return $res
}

function Get-EnvList
{
    <# 
    .SYNOPSIS
    列出所有用户环境变量[系统环境变量|全部环境变量(包括用户和系统共有的环境变量)|用户和系统合并后的无重复键的环境变量]
    获取

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
    param(
        #one of [User|Machine|Detail|Combin] abbr [U|M|D|C]
        [validateset('User', 'Machine', 'U', 'M', 'Detail', 'D', 'Combin', 'C')]
        $Scope = 'C'
    )
    $env_user = [Environment]::GetEnvironmentVariables('User')
    $env_machine = [Environment]::GetEnvironmentVariables('Machine')
    $envs = [System.Environment]::GetEnvironmentVariables()
    # $env_detail=$env_user,$env_machine

    $envs = $envs.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            Scope = 'Combin'
            Name  = $_.Name
            Value = $_.Value
            
        }
    }
    $env_user = $env_user.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            Scope = 'User'
            Name  = $_.Name
            Value = $_.Value
        }
    }

    $env_machine = $env_machine.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            Scope = 'Machine'
            Name  = $_.Name
            Value = $_.Value
        }
    }

    # 合并两个数组
    $env_detail = $env_user + $env_machine

    # 输出结果
    # $combinedEnvs | Format-Table -AutoSize -Property Scope, Name, Value


    # switch基本用法
    # switch ($Scope) {
    #     {$_ -eq 'User'} { $res=$env_user }
    #     {$_ -eq 'Machine'} { $res=$env_machine }
    #     Default {$res=$envs}
    # }
    # switch高级用法
    switch -Wildcard ($Scope)
    {
        'U*' { $res = $env_user }
        'M*' { $res = $env_machine }
        'D*' { $res = $env_detail }
        'C*' { $res = $envs }
        Default { $res = $envs }
    }
    #以下是可选操作
    # $res = $res.GetEnumerator() 
    #| Select-Object -ExpandProperty Name
    
    return $res
    
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
    param(
        #env var name
        [Alias('Name', 'EnvVar')]$Key = '*',

        #one of [User|Machine|Detail|Combin] abbr [U|M|D|C]
        #Detail:show env in both user and machine
        #Combin:show env in user and machine merge(only user value if both have the env var)
        [validateset('User', 'Machine', 'U', 'M', 'Detail', 'D', 'Combin', 'C')]
        $Scope = 'C',
        #是否统计环境变量的取值个数,例如Path变量
        [switch]$Count = $false
        
    )
    $res = Get-EnvList -Scope $Scope | Where-Object { $_.Name -like $Key }

    #统计环境变量个数
    $res = Format-EnvItemNumber -EnvVars $res -Scope 
    # Write-Output $res
    if ($Count)
    {
        $res = $res.value -split ';' | catn
    }
    return $res
}

function Get-EnvPath
{
    $env:Path -split ';' | catn
}

function Remove-RedundantSemicolon
{
    <# 
    .SYNOPSIS
        #清理可能多余的分号
    .EXAMPLE
    PS>Remove-RedundantSemicolon ";;env1;env2;  ; env3"
    env1;env2; env3
    #>
    param (
        $String
    )
    $String = $String -replace '(;+)\s*;', '$1'

    return $String.trim(';')
}

function Add-EnvVar
{
    <# 
.SYNOPSIS
添加环境变量(包括创建新变量及其取值,为已有变量添加取值),并且立即更新所作的更改
这里我们利用$expression | Invoke-Expression等方法来手动立即更新当前powershell上下文的环境变量,实现不需要重启更新环境变量
虽然本函数能够刷新当前powershell上下文的环境变量,但是其他shell进程却不会跟着刷新,可以手动调用Update-EnvVarFromSysEnv来更新当前shell的环境变量

当对一个已经存在变量添加值时,会在头部插入新值;(有些时候末尾会带有分号,导致查询出来的值可能存在2个来连续的分号)
这时候可以判断移除最后一个分号,然后再添加新值,头插方式也行
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
    [CmdletBinding()]
    param (
        
        [Alias('Name','Key')]$EnvVar = 'new',
        [Alias('Value')]$NewValue = (Get-Date).ToString(),
        [switch]$ResolveNewValue,

        # choose User or Machine,the former is default(no need for Administrator priviledge)
        # the Machine scope need Administrator priviledge
        [ValidateSet('Machine', 'User')]
        $Scope = 'User',

        [switch]$Query = $false
    )
    # 同步环境变量
    Update-EnvVarFromSysEnv -Scope $Scope
    # 先获取当前用户或机器级别的环境变量值
    $CurrentValue = [Environment]::GetEnvironmentVariable($EnvVar, $Scope)

    #查询当前值,能够区分不同Scope的环境变量(例如用户变量和系统变量都有Path,如果只想插入一个新值到用户Path,就要用上述方法访问)
 
    # $CurrentValue = "`$env:$EnvVar" | Invoke-Expression #无法区分用户和系统的path变量

    # 添加新路径到现有 Path
    #如果使用了ResolveNewValue参数，将NewValue转换为完整的路径
    if ($ResolveNewValue)
    {
        $NewValue = (Resolve-Path $NewValue).Path
        Write-Verbose "Resolved NewValue: $NewValue"
    }
    #$CurrentValue如果没有提前设置值,则返回null,而不是'',不能用$CurrentValue -ne '' 判断是否新变量,直接用$CurrentValue 即可
    $NewValueFull = $CurrentValue  ? "$NewValue;$CurrentValue" : $NewValue 
    # Write-Output $NewValue
    
    # 查看即将进行的更改,如果启用了$V或$Query,则会打印出更改的表达式,如果是后者还会进一步询问
    if ($V -or $Query)
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
            $Log | Format-List 
        }
        else
        {
            $Log | Format-Table -Wrap -AutoSize | Out-String #| Write-Host -ForegroundColor Green
        }
        
        
    }
    if ($Query)
    {
        
        $replay = Read-Host -Prompt 'Enter y to continue,else exit '
        if ($replay -ne 'y')
        {
            return
        }
    }
    # 设置 Scope 级别的 Path 环境变量
    $NewValueFull = Remove-RedundantSemicolon $NewValueFull
    [Environment]::SetEnvironmentVariable($EnvVar, $NewValueFull, $Scope)

    # 刷新当前shell的环境变量
    $env_left = "`$env:$EnvVar"
    $NewValueRefresh = $NewValueFull
    #检查,要对path特殊处理
    if ($EnvVar -eq 'Path')
    {
        $CurrentValue = $env:Path  
        # $env:Path -split ';' |Write-Host -ForegroundColor Blue
        $NewValueRefresh = Remove-RedundantSemicolon "$NewValue;$CurrentValue"
    }
    $expression = "$env_left = '$NewValueRefresh'" 
    $expression | Invoke-Expression
    # return $NewValue
    # Write-Verbose "$($env_left)=`n$($NewValueFull -split ';' | Out-String)" # -BackgroundColor Yellow
    $res = [PSCustomObject]@{
        Name  = $EnvVar
        Value = $NewValueFull -split ';' | Out-String 
    }
    return $res | Format-Table -AutoSize -Wrap

}


function Clear-EnvValue
{
    <# 
    .SYNOPSIS
    清理环境变量中多余的分号
    注意对于系统级的变量需要使用管理员运行
    本质是调用Add-EnvVar 添加一个空字符串来清理
    
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
        
        $EnvVar = '',
        
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
        Write-Host "No [$EnvVar] was found! Nothing to Remove."
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
        $EnvVar = '',
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
    param(

        $Scope = 'Combin'
    )
    $envs = [System.Environment]::GetEnvironmentVariables($Scope)
    # 扫描所有的注册表中已有的环境变量,将其同步到当前powershell中,防止在不同shell中操作环境变量导致的不一致性
    $envs.GetEnumerator() | Where-Object { $_.Key -notin 'Path', 'PsModulePath' } 
    | ForEach-Object {
        # Write-Output "$($_.Name)=$($_.Value)"
        $env_left = "`$env:$($_.Name)"
        $expressoin = "$env_left='$($_.Value)'"
        $CurrentValue = $env_left | Invoke-Expression
        if ($CurrentValue -ne $_.Value)
        {
            # Write-Host "$env_left from `n`t[$(Invoke-Expression($env_left))] `n=TO=> `n`t [$($_.Value)]" -BackgroundColor Magenta
            $expressoin | Invoke-Expression
        }
    }
}
