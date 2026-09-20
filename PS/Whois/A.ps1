$p = 1
function print_default_parameter
{
    param (
        $v = $p
    )
    Write-Host $v
    
}
# 定义函数 a
function a
{
    Write-Output "This is function a from A.ps1"
}

# 判断是否直接调用 A.ps1
if ($MyInvocation.PSCommandPath -eq $MyInvocation.MyCommand.Path)
{
    # 如果是直接运行 A.ps1，则调用 a 函数
    a
}
