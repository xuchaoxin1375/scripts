
function Confirm-Restart
{
    # 询问用户是否重启
    $userInput = Read-Host 'Do you want to restart the computer? (y/n)'
    
    # 根据用户输入处理逻辑
    switch ($userInput.ToLower())
    {
        'y'
        {
            # 用户确认重启
            Write-Host 'Restarting the computer...(After 3 seconds,you can press Ctrl+C to cancel!)' -ForegroundColor Red
            # 使用 Restart-Computer cmdlet 重启计算机
            # 添加 -Force 参数强制关闭运行的应用程序
            # -Confirm:$false 避免再次确认
            
            # Start-Sleep 3
            $time = 3
            1..$time | ForEach-Object { Write-Host $($time - $_ + 1); Start-Sleep 1 }
            
            Restart-Computer -Force -Confirm:$false
            break
        }
        default
        {
            # 用户输入了其他内容，不重启
            Write-Host 'No action taken. The computer will not restart.' -ForegroundColor Blue
        }
    }
}

# 调用函数
# Confirm-Restart

function Get-CredentialGuardStatus
{
    param (

    )
    $res = (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard).SecurityServicesRunning
    Write-Host 'The Value 1 means Credential Guard is enabled; Value 0 means it is disabled.' -ForegroundColor blue
    Write-Host 'The result is: ' -NoNewline -ForegroundColor Magenta
    return $res
}
function Disable-CredentialGuard
{
    <# 
    .SYNOPSIS
    本命令行用于禁用Credential Guard
    .NOTES
    需要使用管理员权限窗口来运行,因为这涉及到修改注册表
    否则会抛出权限不足的异常
    #>
    param (
    )


    # 设置注册表项以禁用Credential Guard相关设置

    # 第一个注册表路径和值
    $regPath1 = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $regName1 = 'LsaCfgFlags'
    $regValue1 = 0

    # 第二个注册表路径和值
    $regPath2 = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
    $regName2 = 'LsaCfgFlags'
    $regValue2 = 0



    # 设置第一个注册表项
    New-ItemProperty -Path $regPath1 -Name $regName1 -Value $regValue1 -PropertyType DWord -Force  

    # 设置第二个注册表项
    New-ItemProperty -Path $regPath2 -Name $regName2 -Value $regValue2 -PropertyType DWord -Force 

    Write-Host '请重启计算机以使更改生效。'

    $reply = Read-Host -Prompt "Enter 'y' to Restart Computer now [y/n]"
    if ($reply -eq 'y')
    {
        Restart-Computer
    }
    
}


# 禁用VBS并删除指定的注册表项
function Disable-VBS
{
    try
    {
        # 删除注册表项 EnableVirtualizationBasedSecurity
        Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity' -ErrorAction Stop
        Write-Host 'Successfully removed EnableVirtualizationBasedSecurity registry key.'

        # 删除注册表项 RequirePlatformSecurityFeatures
        Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'RequirePlatformSecurityFeatures' -ErrorAction Stop
        Write-Host 'Successfully removed RequirePlatformSecurityFeatures registry key.'

        # 提示用户即重启设备
        Confirm-Restart
    }
    catch
    {
        Write-Error "An error occurred: $_"
    }
}

# 调用函数禁用VBS
# Disable-VBS