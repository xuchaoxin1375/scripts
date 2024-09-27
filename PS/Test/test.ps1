# 创建示例文件夹和文件
function New-TestFiles
{
    $path = 'C:\TestShouldProcess'
    New-Item -ItemType Directory -Path $path -Force
    1..3 | ForEach-Object { 
        New-Item -ItemType File -Path "$path\file$_.txt" -Force
    } 
    # Get-ChildItem $path
}
Write-Host 'Creating/Reseting test files...'
New-TestFiles

function Remove-TestFiles
{
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$Path = 'C:\TestShouldProcess',
        
        [switch]$Force
    )

    # 如果指定了Force且没有指定Confirm,则禁用确认提示
    if ($Force -and -not $Confirm)
    {
        $ConfirmPreference = 'None'
    }

    $files = Get-ChildItem -Path $Path -File # -Filter '*.txt'
    
    # 这两个y/N to all是给shouldcontinue用的,它们要定义在循环外部而不是内部
    # 并且两个变量而不是给shouldprocess用的,shouldprocess自己内部会处理用户的输入
    # 当shouldprocess接收到用户给出的y/N to all,在循环时会自动跳过再次确认环节(是自动处理),外部不会接受到用户输入的选项
    # 而对于shouldContinue,要实现yes to all ,需要传入对应的变量,而且是[ref]类型的
    $yesToAll = $false
    $noToAll = $false
    foreach ($file in $files)
    {

        # Force开关的含义和Confirm开关的含义可以说是相反的
        # 用户可能会同时使用-Force 或 -Confirm ,这看起来是不合理的参数组合,但是对于命令不了解的用户发生这种事是可能的
        # 实际上使用-confirm:$false 正是Force想要表达的含义,只是为了帮助用户更容易操作,提供了Force选项
        # 在这种情况下,我们可以让-confirm选项占主导(-confirm 选项默认就是-confirm:$true)
        if ($Force -and -not $Confirm)
        {
            $ConfirmPreference = 'None'
            # 将消息确认级别设置为关闭,就shouldprocess不会再提示了，而是直接执行操作
        }
        if ( $PSCmdlet.ShouldProcess($file.Name, 'Remove file'))
        {
            $continueRemoval = $true
            # 为了演示更高精度的控制,这里使用了ShouldContinue 进行二次确认
            # 如果没有指定Force,则使用ShouldContinue进行额外确认,否则跳过shouldcontinue确认环节
            if (-not $Force)
            {
                # $shouldcontinue二次确认
                # yesToAll和noToAll可以由shouldprocess时就确认
                $continueRemoval = $PSCmdlet.ShouldContinue(
                    "Are you sure you want to remove $($file.Name)?",
                    'Removing file(by should continue)', 
                    [ref]$yesToAll,
                    [ref]$noToAll
                )
                # 如果用户选择了y/n ToAll,那么相应的变量会发生更改,下一次就不会在询问了
                Write-Host "yesToAll: $yesToAll, noToAll: $noToAll"
            }
            
            if ($continueRemoval)
            {
                Remove-Item -Path $file.FullName -Force # -confirm:$false
                Write-Output "Removed file: $($file.Name)"
            }
        }
    }
}