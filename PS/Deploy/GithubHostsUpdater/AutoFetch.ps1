
param(
    $File = "$PSScriptRoot\fetch-github-hosts.ps1",
    [ValidateSet('pwsh', 'powershell')]$shell = 'powershell',
    [switch]$verbose
)
function Deploy-GithubHostsAutoUpdater
{
    <# 
    .SYNOPSIS
    向系统注册自动更新GithubHosts的计划任务
    .DESCRIPTION
    如果需要修改触发器，可以自行在源代码内调整，或者参考Microsoft相关文档；也可以使用taskschd.msc 图形界面来创建或修改计划任务

    .NOtes
    移除计划任务：
    unregister-ScheduledTask -TaskName  Update-GithubHosts
    #>
    [CmdletBinding()]
    param (
        
        [ValidateSet('pwsh', 'powershell')]$shell = 'powershell',
        # 需要执行的更新脚本位置
        $File = '' #自行指定
    )
    # 检查参数情况
    Write-Verbose 'Checking parameters ...'
    $PSBoundParameters | Format-Table   

    # 开始注册
    Write-Host 'Registering...'
    Start-Sleep 3
    # 定义计划任务的基本属性
    if (! $File)
    {
    
        $File = "$PSScriptRoot\fetch-github-hosts.ps1" #自行修改为你的脚本保存目录(我将其放在powershell模块中,可以用$PSScriptRoot来指定目录)
       
        # $File = 'C:\repos\scripts\PS\Deploy\fetch-github-hosts.ps1' #这是绝对路径的例子(注意文件名到底是横杠（-)还是下划线(_)需要分清楚
    }

    $action = New-ScheduledTaskAction -Execute $shell -Argument " -ExecutionPolicy ByPass -NoProfile -WindowStyle Hidden -File $File"
    # 定义两个触发器
    $trigger1 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
    $trigger2 = New-ScheduledTaskTrigger -AtStartup
    # 任务执行角色设置
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    # 创建计划任务
    Register-ScheduledTask -TaskName 'Update-githubHosts' -Action $action -Trigger $trigger1, $trigger2 -Settings $settings -Principal $principal
}
Deploy-GithubHostsAutoUpdater -File $File -shell $shell -Verbose:$verbose