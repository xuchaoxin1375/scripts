
function Add-Extension
{
    <# 
    为满足匹配模式的文件添加后缀(扩展名)
    #>
    param(
        $pattern,
        $extension
    )
    Get-ChildItem | Where-Object { $_.Name -match $pattern } |
    ForEach-Object { rename $_.Name -NewName "$($_.Name).$extension" }
}