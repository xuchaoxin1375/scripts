function Remove-CxxuFile
{
    #这里将confirmImpact设置为Medium
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    # 外部调用使用了`Whatif`或者`Confirm`参数时,都会调用`ShouldProcess`函数(当然,是我们手动调用$PsCmdlet自动变量对象的`ShouldProcess`函数,不然也不会凭空按照预定的格式向用户显示消息)
    # 此函数会返回一个布尔值，表示是否继续执行操作
    # 这里也可以把返回值赋值给一个变量,然后使用变量来决定是否继续执行操作,而不一定要写在if()的括号内

    # $isContinue = $PSCmdlet.ShouldProcess($FilePath, 'Remove file(by Remove-CxxuFile)')

    $isContinue = $PSCmdlet.ShouldProcess($FilePath)
    # What if: Performing the operation "Remove-CxxuFile" on target ".\1.txt". #这里调用的是单参数shouldProcess方法,指定的是本函数(action或operation自动引用本函数名)会对什么目标进行操作(这里的目标指定为函数的$FilePath参数)

    if ($isContinue)
    {
        # 实际删除文件的代码
        Write-Host "Remove file: $FilePath" -ForegroundColor Red
        Remove-Item -Path $FilePath 
    }
    Write-Host "Task End:$(Get-Date)" -ForegroundColor Blue
}

function Test-RequestConfirmationTemplate
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')] 
    param (
        [string]$Target = 'MyResource'
    )

    # Step 1: ShouldProcess prompts the user for confirmation
    if ($PSCmdlet.ShouldProcess($Target <# , 'Test-RequestConfirmationTemplate' #>))
    {

        # After ShouldProcess, you can call ShouldContinue for further confirmation
        $message = 'Continue with this operation?(by ShouldContinue)'
        $caption = 'Confirm'
        $shouldContinue = $PSCmdlet.ShouldContinue($message, $caption)
        
        if ($shouldContinue)
        {
            # If both confirmations are positive, perform the operation
            Write-Host "Operation on $Target confirmed and proceeding."
        }
        else
        {
            # If user cancels in the second confirmation
            Write-Host "Operation on $Target canceled by user."
        }
    }
    else
    {
        # If user cancels in the first confirmation
        Write-Host "Operation on $Target not confirmed."
    }
}

# 测试函数
Test-RequestConfirmationTemplate -Target 'MyResource'