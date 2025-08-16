function Demo
{
    param(
        [string]$Name,
        [int]$Age
    )

    Write-Host "0.绑定到的参数:"
    Write-Output "Name = $Name"
    Write-Output "Age = $Age"

    Write-Output "1.`$args (未绑定参数): $args"
    Write-Output "2.`$PSBoundParameters (绑定参数哈希): $($PSBoundParameters.GetEnumerator()|Out-String)"
    Write-Output "3.`$MyInvocation (调用上下文): $($MyInvocation.Line)"
    # 检查管道输入
    if($input)
    {
        Write-Output "4.管道输入:"
        $i=1
        foreach($item in $input)
        {
            Write-Host "pipe input item($i):$item"
            $i++
        }
    }
}

# 调用(其中显式参数-Name和Alice对应,而第二个参数30隐式绑定到Age参数,最后多出来的`-Extra X`不会绑定到函数Demo中声明的任何参数,会被$args参数所捕获)
#例1
Demo -Name Alice 30 -Extra "X"
#例2
'a','b','c'|Demo -Name Alice 30 -Extra "X"
