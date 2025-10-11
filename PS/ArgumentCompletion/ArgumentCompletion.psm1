


# # 创建补全功能
function Get-EnvVarCompleter
{
    <# 
    .SYNOPSIS
    创建环境变量补全功能

    .DESCRIPTION
    提供综合环境的变量提示和补全,对于User,Machine都有定义的情况下,优先提示User级别的变量的取值
    对于Path这类特殊变量,取值会是User,Machine的综合取值
    .EXAMPLE
    Register-ArgumentCompleter -CommandName Get-EnvVar -ParameterName EnvVar -ScriptBlock ${Function:Get-EnvVarCompleter}

    .LINK
    # # 注册补全功能说明： https://learn.microsoft.com/zh-cn/powershell/module/microsoft.powershell.core/register-argumentcompleter?view=powershell-7.4#-scriptblock
    .LINK
    #  https://learn.microsoft.com/zh-cn/powershell/module/microsoft.powershell.core/about/about_functions_argument_completion?view=powershell-7.4#argumentcompleter-attribute
 #>
    param(
        $commandName, 
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameters
        # $cursorPosition
    )

    # 获取所有环境变量
    
    #根据Scope过滤环境变量
    if ($fakeBoundParameters.containskey('Scope'))
    {
        # $fileteredEnvVars = $envVars.Keys | Where-Object { $_ -like "$wordToComplete*" -and $_ -like "*$($fakeBoundParameters.Scope)*" }
        $Scope = $fakeBoundParameters.Scope
    }
    else
    {
        # $envVars = [System.Environment]::GetEnvironmentVariables()
        # $envVars = $envVars.Keys 
        # $envVars = Get-EnvList | Select-Object -ExpandProperty Name
        $Scope = 'Combined' #默认为Combined范围
    }
    # $Scope = 'Combined'
    $envVars = Get-EnvList -Scope $Scope | Select-Object -ExpandProperty Name
    # 根据输入的字母过滤环境变量
    $filteredEnvVars = $envVars | Where-Object { $_ -like "$wordToComplete*" }
    
    # 返回补全结果
    # $res = $filteredEnvVars | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    $res = foreach ($ev in $filteredEnvVars)
    {
        # 方案1:(相对独立)
        # $value = Get-Item env:\$ev | Select-Object -ExpandProperty Value
        # $value = $value -split ';' | Format-DoubleColumn | Out-String
        #方案2:(依赖于外部定义的函数，如Get-EnvVar)
        #主要一定要将命令的结果转换为字符串，否则无法被后续的completionResult正确处理
        if ($Scope -ne 'Combined')
        {

            $value = (Get-EnvVarRawValue -Scope $Scope -EnvVar $ev ) -split ';' #这里尝试使用原汁原味格式显示%var%的中间变量(暂时仅支持User和Machine范围)
        }
        else
        {
            $value = (Get-EnvVar -Scope $Scope -EnvVar $ev | Select-Object -ExpandProperty Value) -split ';'
        }
        # 考虑到当$value的值过长会影响terminal的现实效果(窗口过小会空白,最大化后窗口补全才行);

        $Limit = 5 #限制补全的候选值的最大行数
        $count = $value.count
        if ($count -gt $Limit)
        {

            # 这里限制补全的候选值的tooltip内容最大长度(不超过$Limit行)
            $value = $value | Format-DoubleColumn | Select-Object -First $Limit | Out-String 
            $value = $value.Trim()
            # $value += '......'
            $value += "`n---[$Limit/$count]---"
        }
        else
        {
            $value = $value | Format-DoubleColumn | Out-String
        }
        <# 
            有两种构造函数重载
            System.Management.Automation.CompletionResult new(string completionText, string listItemText, System.Management.Automation.CompletionResultType resultType, string toolTip)
        
            System.Management.Automation.CompletionResult new(string completionText)
            #>
        [System.Management.Automation.CompletionResult]::new($ev, $ev, 'ParameterValue', $value)
    }
    return $res
}

function Set-ArgumentCompleter
{
    <# 
    .SYNOPSIS
    批量为适配了补全器的命令注册ArgumentCompleter
    .DESCRIPTION
    本模块集为EnvVar等模块内的命令适配了补全器
    批量注册器的一个重要条件是具有相同的参数名字,并且有相同的含义,补全效果才是匹配的
    #>
    param (
    )
    # Import-Module ArgumentCompletion
    # 获取命令名字
    $EnvVarCmds = Get-Command -Module EnvVar | Select-Object -ExpandProperty Name 
    # foreach ($cmd in $EnvVarCmds)
    $EnvVarCmds | ForEach-Object {
        $cmd = $_
        Register-ArgumentCompleter -CommandName $cmd -ParameterName EnvVar -ScriptBlock ${Function:Get-EnvVarCompleter}
    }
    
}