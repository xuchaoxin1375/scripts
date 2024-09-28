


# # 创建补全功能
$EnvCompletorScript = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $cursorPosition)
    # # 注册补全功能说明： https://learn.microsoft.com/zh-cn/powershell/module/microsoft.powershell.core/register-argumentcompleter?view=powershell-7.4#-scriptblock
    # # https://learn.microsoft.com/zh-cn/powershell/module/microsoft.powershell.core/about/about_functions_argument_completion?view=powershell-7.4#argumentcompleter-attribute
    # param(
    #     $commandName, 
    #     $parameterName,
    #     $wordToComplete,
    #     $commandAst,
    #     # $fakeBoundParameters
    #     $cursorPosition
    # )

    # 获取所有环境变量
    $envVars = [System.Environment]::GetEnvironmentVariables()

    # 根据输入的字母过滤环境变量
    $filteredEnvVars = $envVars.Keys | Where-Object { $_ -like "$wordToComplete*" }
    
    # 返回补全结果
    # $res = $filteredEnvVars | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    $res = foreach ($ev in $filteredEnvVars)
    {
        # 方案1:(相对独立)
        # $value = Get-Item env:\$ev | Select-Object -ExpandProperty Value
        # $value = $value -split ';' | Format-DoubleColumn | Out-String
        #方案2:(依赖于外部定义的函数，如Get-EnvVar)
        #主要一定要将命令的结果转换为字符串，否则无法被后续的completionResult正确处理
        $value = Get-EnvVar -EnvVar $ev -Count | Out-String #-Scope User 
        <# 
            有两种构造函数重载
            System.Management.Automation.CompletionResult new(string completionText, string listItemText, System.Management.Automation.CompletionResultType resultType, string toolTip)
        
            System.Management.Automation.CompletionResult new(string completionText)
            #>
        [System.Management.Automation.CompletionResult]::new($ev, $ev, 'ParameterValue', $value)
    }
    return $res
}
# Register-ArgumentCompleter -CommandName add-envvar -ParameterName EnvVar -ScriptBlock $EnvCompletorScript
# Register-ArgumentCompleter -CommandName Get-envvar -ParameterName EnvVar -ScriptBlock $EnvCompletorScript

function Set-ArgumentCompleter
{
    param (
    )
    # Import-Module ArgumentCompletion

    $EnvVarCmds = Get-Command -Module EnvVar | Select-Object -ExpandProperty Name 
    foreach ($cmd in $EnvVarCmds)
    {

        Register-ArgumentCompleter -CommandName $cmd -ParameterName EnvVar -ScriptBlock $EnvCompletorScript
    }
    
}