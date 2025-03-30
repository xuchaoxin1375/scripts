function Export-NewCSvFromRange
{
    <#
    .SYNOPSIS
    从CSV文件中截取中间片段(第m行到第n行),将选中的区间保存为新文件。

    .DESCRIPTION
    该函数允许用户从指定的CSV文件中截取一段数据（从第m行到第n行），并将截取的数据保存为一个新的CSV文件。
    默认情况下，截取操作是左闭右开的（即包含起始行，但不包含结束行）。可以通过-IncludeEnd参数来改变为闭区间（即包含起始行和结束行）。
    如果仅提供 StartRow 参数，则返回从 StartRow 到文件末尾的所有行。

    .PARAMETER Path
    指定要处理的CSV文件的路径。

    .PARAMETER StartRow
    指定截取的起始行号（从0开始计数）。

    .PARAMETER EndRow
    指定截取的结束行号（从0开始计数）。如果未提供，则默认截取到文件末尾。

    .PARAMETER IncludeEnd
    如果指定此参数，截取操作将包含结束行（闭区间）。默认情况下，不包含结束行（左闭右开）。

    .PARAMETER Output
    指定新CSV文件的输出路径。如果未指定，则使用默认路径。

    .EXAMPLE
    Export-NewCSvFromRange -Path "data.csv" -StartRow 10 -EndRow 20
    从"data.csv"文件中截取第10行到第19行（不包括第20行），并将结果保存为新的CSV文件。

    .EXAMPLE
    Export-NewCSvFromRange -Path "data.csv" -StartRow 10 -EndRow 20 -IncludeEnd
    从"data.csv"文件中截取第10行到第20行（包括第20行），并将结果保存为新的CSV文件。

    .EXAMPLE
    Export-NewCSvFromRange -Path "data.csv" -StartRow 10
    从"data.csv"文件中截取第10行到文件末尾，并将结果保存为新的CSV文件。


    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [int]$StartRow,

        [Parameter(Mandatory = $false)]
        [int]$EndRow = "",



        [string]$Output = ""
    )

    # 检查输入文件是否存在
    if (-not (Test-Path -Path $Path))
    {
        Write-Error "文件不存在: $Path"
        return
    }

    # 导入CSV文件
    try
    {
        $csv = Import-Csv -Path $Path
    }
    catch
    {
        Write-Error "无法导入CSV文件: $_"
        return
    }

    # 获取总行数(不包括表头行)
    $totalRows = $csv.Count

    # 验证 StartRow 是否合法
    if ($StartRow -lt 1 -or $StartRow -gt $totalRows)
    {
        Write-Error "StartRow 超出范围。有效范围为 1 到 $($totalRows)"
        return
    }

    # 如果未提供 EndRow，则设置为最后一行
    # if (-not $PSBoundParameters.ContainsKey('EndRow'))
    if(!$Endrow)
    {
        $EndRow = $totalRows - 1
    }
    else
    {
        # 验证 EndRow 是否合法
        if ($EndRow -lt $StartRow -or $EndRow -gt $totalRows)
        {
            Write-Error "EndRow 超出范围或小于 StartRow。有效范围为 $StartRow 到 $($totalRows)"
            return
        }
    }



    # 计算实际索引范围
    $StartIndex = $StartRow - 1
    $EndIndex = $EndRow - 1

    # $EndIndex = [math]::Min($EndIndex, $totalRows - 1)

    # 截取指定范围的行
    $selectedRows = $csv[$StartIndex..$EndIndex]

    # 获取表头
    try
    {
        $headerLine = Get-Content -Path $Path -Encoding UTF8 -TotalCount 1
    }
    catch
    {
        Write-Error "读取表头失败: $_"
        return
    }

    # 如果未指定输出文件路径，生成默认路径
    if (-not $Output)
    {
        $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $outputDirectory = Split-Path -Path $Path
        $Output = Join-Path -Path $outputDirectory -ChildPath "${fileBaseName}[${StartRow}-${EndRow}].csv"
    }

    # 写入新文件
    try
    {
        # 写入表头
        Set-Content -Path $Output -Value $headerLine -Encoding UTF8 -Force

        # 写入选定的行
        if ($selectedRows.Count -gt 0)
        {
            $selectedRows | ConvertTo-Csv -NoTypeInformation -Encoding UTF8  | Add-Content -Path $Output -Encoding UTF8
        }
    }
    catch
    {
        Write-Error "写入文件失败: $_"
        return
    }

    # 输出预览
    Write-Host "截取的行范围: $StartIndex 至 $EndIndex" -ForegroundColor Green
    Write-Host "表头: $headerLine" -ForegroundColor Cyan
    Write-Host "前几行数据预览:" -ForegroundColor Yellow
    $selectedRows | Select-Object -First 5 | Format-Table -AutoSize

    Write-Output "新的CSV文件已保存到: $Output"
}