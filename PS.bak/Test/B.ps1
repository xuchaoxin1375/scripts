# 使用点运算符导入 A.ps1
. "./A.ps1"

# 现在可以调用 a 函数，但不会自动触发
Write-Output "Now in B.ps1"
a  # 手动调用 a 函数
