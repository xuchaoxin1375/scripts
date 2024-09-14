
$depth = 0
$times = 0
function listRecurse
{
    <# 遍历所有子目录 #>
    param(
        $pathType = 'f',
        $path = 'd:/repos/blogs/neep/408'
    )
    # Write-Output "`tpath=$path"
    if ($pathType -eq 'd')
    {
        $lst = (Get-ChildItem -Directory $path)
    }
    else
    {
        $lst = (Get-ChildItem $path)

    }

    # 子目录数目len
    $len = $lst.Length
    $times++;

    #每一层处理都是都是一重循环O(n)
    
    # 遍历子目录
    <# 注意需要添加对文件的判断,否则在对文件调用本函数的时候,会陷入死循环(无法进入深层目录) #>
    $lst | ForEach-Object {
        $len--;
        # Write-Output "`t`t remain times :len=$len";
        # 打印每个子目录
        $indent = "`t" * $depth
        Write-Output "$indent $depth $($_.FullName)"
        # Write-Output "depth=$depth"
        if ((Get-Item $_) -is [system.io.directoryinfo] )
        {
            $depth++
            # write
            # 对子目录继续深挖,(做相同的调用)
            listRecurse -path $_.FullName -pathType $pathType
            $depth--
        }
        # Write-Output "$depth"
        # Start-Sleep -Milliseconds 1000

    } 
}   

listRecurse -pathType d 