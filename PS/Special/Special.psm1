
function Register-AlistStartup
{
    <# 
   .SYNOPSIS
   windows用户注册alist(cli版)服务计划任务的注册,实现开机自启动
   .DESCRIPTION
   请根据需要修改下面的$FilePath路径中的alist.exe部分，否则不起作用,其余部分可以不改动
   .EXAMPLE
   #使用方法
    # 注册alist计划任务(默认的计划任务名为StartupAlist，启动角色为System,修改为自己当前用户账户也是可以的)

    Register-AlistStartup 
    # 其他相关命令
    # 检查计划任务
    Get-ScheduledTask -TaskName startupalist
    #移除计划任务
    Unregister-ScheduledTask -TaskName startupalist # -Confirm:$false

   #>
    param(
        $TaskName = 'StartupAlist',
        $UserId = 'System',
        $FilePath = ' C:\exes\alist\alist.exe  ', #修改为自己的alist程序 路径👺
        $Directory #alist的起始目录
    )

    if (!$Directory)
    {

        $Directory = Split-Path -Path $FilePath -Parent
    }
    # 输出目录路径

    $action = New-ScheduledTaskAction -Execute $FilePath -Argument 'server' -WorkingDirectory $Directory
    # 定义触发器
    $trigger = New-ScheduledTaskTrigger -AtStartup
    # 任务执行主体设置(以System身份运行,且优先级最高,无论用户是否登陆都运行,适合于后台服务，如aria2，chfs，alist等)
    $principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType ServiceAccount -RunLevel Highest
    # 这里的-UserId 可以指定创建者;但是注意,任务创建完毕后,不一定能够立即看Author(创建者)字段的信息,需要过一段时间才可以看到,包括taskschd.msc也是一样存在滞后

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    # 创建计划任务
    Register-ScheduledTask -TaskName $TaskName -Action $action `
        -Trigger $trigger -Settings $settings -Principal $principal
    
}

