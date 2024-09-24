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
    $isContinue = $PSCmdlet.ShouldProcess($FilePath, 'Remove file(by Remove-CxxuFile)')
    if ($isContinue)
    {
        # 实际删除文件的代码
        Write-Host "Remove file: $FilePath" -ForegroundColor Red
        Remove-Item -Path $FilePath 
    }
    write-host "Task End:$(Get-Date)" -ForegroundColor Blue
}