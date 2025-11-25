
function Get-CsvTailRows-Archived
{
    <#
.SYNOPSIS
    提取CSV文件的表头和从第k行到最后一行的数据，并将其保存到指定输出文件中。

.DESCRIPTION
    该脚本读取输入的CSV文件，提取文件的表头（第一行）和指定的第k行到最后一行的数据，
    然后将提取的内容保存到指定的输出文件中。
    
.PARAMETER InputFile
    输入的CSV文件路径。
    
.PARAMETER OutputFile
    输出的CSV文件路径。
    
.PARAMETER StartRow
    提取的数据从第几行开始，k行。第一行为1。

.EXAMPLE
    .\Extract-CsvRows.ps1 -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartRow 5
    从`C:\path\to\input.csv`文件中提取表头和第5行到最后一行的数据，并将其保存到`C:\path\to\output.csv`。

.NOTES
    文件使用UTF-8编码进行读写，确保CSV文件的格式正确。
#>

    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile, # 输入的CSV文件路径

        [Parameter(Mandatory = $true)]
        [string]$OutputFile, # 输出的CSV文件路径

        [Parameter(Mandatory = $true)]
        [int]$StartRow          # 第k行，从1开始
    )

    # 确保StartRow是有效的
    if ($StartRow -lt 1)
    {
        Write-Error "StartRow 必须大于或等于1"
        return
    }

    # 读取CSV文件
    try
    {
        $data = Import-Csv -Path $InputFile
    }
    catch
    {
        Write-Error "读取CSV文件失败: $_"
        return
    }

    # 提取表头行
    $header = $data | Select-Object -First 0

    # 提取从第$StartRow行到最后一行的数据
    $rows = $data | Select-Object -Skip ($StartRow - 1)

    # 保存表头行和提取的行到新的输出文件
    try
    {
        # 输出表头行
        $header | Export-Csv -Path $OutputFile -NoTypeInformation -Force
        # 输出从第$StartRow行开始的数据行
        $rows | Export-Csv -Path $OutputFile -NoTypeInformation -Append -Force
    }
    catch
    {
        Write-Error "保存CSV文件失败: $_"
    }

    Write-Host "处理完成，结果已保存为!(默认所在目录和源文件${InputFile})同目录: $(Resolve-Path $OutputFile)"
    Get-CsvPreview $rows
}
function Get-CsvPreview
{
    param (
        $csv,
        $FirstLineNumbers = 3,
        $propertyNames = @("SKU", "Name")
    )
    $res = $csv | Select-Object -Property $propertyNames | Select-Object -First $FirstLineNumbers | Format-Table ; 

    # Write-Host "....";
    if($csv.count -gt $FirstLineNumbers)
    {
        Write-Output $res
        $last = $csv | Select-Object -Property $propertyNames | Select-Object -Last 1 | Format-Table -HideTableHeaders
        Write-Host "...." 
        Write-Output $last
    }
    else
    {
        Write-Output $res
    }
    Write-Host "Totol lines:$($csv.count)"
}
function Get-CsvTailRows
{
    <#
.SYNOPSIS
    提取 CSV 文件的表头和从第 k 行到最后一行的数据，并将其保存到指定输出文件中。

.DESCRIPTION
    该函数读取输入的 CSV 文件，提取文件的表头（第一行）以及指定起始行号（k）到最后一行的数据，
    然后将提取的内容保存到指定的输出文件中。注意：函数采用 UTF-8 编码读写文件。

.PARAMETER InputFile
    输入的 CSV 文件路径。

.PARAMETER OutputFile
    输出的 CSV 文件路径。

.PARAMETER StartRow
    提取数据的起始行号（第一行为 1）。

.EXAMPLE
    Get-CsvTailRows -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartRow 5
#>

    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        [Parameter(Mandatory = $true)]
        [string]$OutputFile,

        [Parameter(Mandatory = $true)]
        [int]$StartRow,

        [switch]$ShowInExplorer
        
    )

    if ($StartRow -lt 1)
    {
        Write-Error "StartRow 必须大于或等于 1"
        return
    }

    # 使用 Import-Csv 读取 CSV 文件 (Import-Csv: 读取 CSV 文件，将每一行转换为对象)
    try
    {
        $data = Import-Csv -Path $InputFile -Encoding UTF8
    }
    catch
    {
        Write-Error "读取 CSV 文件失败: $_"
        return
    }

    # 读取表头行 (Header)：直接从文件中获取第一行文本
    try
    {
        $headerLine = Get-Content -Path $InputFile -Encoding UTF8 -TotalCount 1
    }
    catch
    {
        Write-Error "读取表头失败: $_"
        return
    }

    # 根据 StartRow 提取数据行 (Data Rows)
    try
    {
        if ($StartRow -eq 1)
        {
            # 若从第一行开始，则直接用 Import-Csv 获取所有数据
            $rows = $data
        }
        else
        {
            # 注意：CSV 文件第一行为表头，故数据行实际从第二行开始
            $rows = Import-Csv -Path $InputFile -Encoding UTF8 | Select-Object -Skip ($StartRow - 1)
        }
    }
    catch
    {
        Write-Error "提取数据行失败: $_"
        return
    }

    # 保存数据到输出文件 (Exporting Data)
    try
    {
        # 先写入表头行
        Set-Content -Path $OutputFile -Value $headerLine -Encoding UTF8 -Force
        # 追加数据行（使用 Export-Csv 会自动添加表头，因此这里使用 -Append 参数，并关闭类型信息）
        $rows | Export-Csv -Path $OutputFile -NoTypeInformation -Append -Encoding UTF8 -Force
    }
    catch
    {
        Write-Error "保存 CSV 文件失败: $_"
        return
    }

    $fileDir = Split-Path (Resolve-Path $OutputFile)
    Write-Host "处理完成，结果已保存到: $(Resolve-Path $OutputFile)"
    Write-Host ($fileDir)
    $rows | Select-Object -First 3 | Select-Object -Property SKU, Name | Format-Table  ; 
    Write-Host "....";
    Write-Host "Totol data lines:$($rows.count-1)"

    # 配置是否自动用资源文件管理打开csv所在文件夹
    if ($ShowInExplorer)
    {
        explorer "$fileDir"
        # Start-Job -ScriptBlock { Start-Sleep 1; explorer "$using:fileDir" }
    }
    
}

function Get-CsvTailRowsGUI
{

    # 加载 Windows Forms 和 Drawing 程序集 (Assembly)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # 建立 GUI 窗体 (Form)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "CSV 行提取工具"      # 窗体标题 (Window Title)
    $form.Size = New-Object System.Drawing.Size(500, 250)
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = New-Object System.Drawing.Size(400, 200)  # 设置最小尺寸

    # 输入文件标签
    $labelInput = New-Object System.Windows.Forms.Label
    $labelInput.Location = New-Object System.Drawing.Point(10, 20)
    $labelInput.Size = New-Object System.Drawing.Size(80, 20)
    $labelInput.Text = "输入文件:"          # “Input File”
    # 锚定于左上角，不随窗体尺寸变化 (Anchor to Top, Left)
    $labelInput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($labelInput)

    # 输入文件文本框
    $textBoxInput = New-Object System.Windows.Forms.TextBox
    $textBoxInput.Location = New-Object System.Drawing.Point(100, 20)
    $textBoxInput.Size = New-Object System.Drawing.Size(280, 20)
    # 锚定于上、左、右，使其宽度随窗体宽度变化 (Anchor to Top, Left, Right)
    $textBoxInput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($textBoxInput)

    # 输入文件浏览按钮
    $buttonBrowseInput = New-Object System.Windows.Forms.Button
    $buttonBrowseInput.Location = New-Object System.Drawing.Point(390, 18)
    $buttonBrowseInput.Size = New-Object System.Drawing.Size(75, 23)
    $buttonBrowseInput.Text = "浏览"          # “Browse”
    # 锚定于上、右 (Anchor to Top, Right)
    $buttonBrowseInput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($buttonBrowseInput)

    # 输出文件标签
    $labelOutput = New-Object System.Windows.Forms.Label
    $labelOutput.Location = New-Object System.Drawing.Point(10, 60)
    $labelOutput.Size = New-Object System.Drawing.Size(80, 20)
    $labelOutput.Text = "输出文件:"          # “Output File”
    $labelOutput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($labelOutput)

    # 输出文件文本框
    $textBoxOutput = New-Object System.Windows.Forms.TextBox
    $textBoxOutput.Location = New-Object System.Drawing.Point(100, 60)
    $textBoxOutput.Size = New-Object System.Drawing.Size(280, 20)
    $textBoxOutput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($textBoxOutput)

    # 输出文件浏览按钮
    $buttonBrowseOutput = New-Object System.Windows.Forms.Button
    $buttonBrowseOutput.Location = New-Object System.Drawing.Point(390, 58)
    $buttonBrowseOutput.Size = New-Object System.Drawing.Size(75, 23)
    $buttonBrowseOutput.Text = "浏览"         # “Browse”
    $buttonBrowseOutput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $form.Controls.Add($buttonBrowseOutput)

    # 起始行号标签
    $labelStartRow = New-Object System.Windows.Forms.Label
    $labelStartRow.Location = New-Object System.Drawing.Point(10, 100)
    $labelStartRow.Size = New-Object System.Drawing.Size(120, 20)
    $labelStartRow.Text = "要截取的起始行号:"         # “Start Row”
    $labelStartRow.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($labelStartRow)

    # 起始行号文本框
    $textBoxStartRow = New-Object System.Windows.Forms.TextBox
    # 将文本框的位置稍作调整，避开标签 (位置 X 值等于标签宽度 + 10)
    $textBoxStartRow.Location = New-Object System.Drawing.Point(130, 110)
    $textBoxStartRow.Size = New-Object System.Drawing.Size(100, 20)
    $textBoxStartRow.Text = "2"             # 默认值
    $textBoxStartRow.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($textBoxStartRow)

    # 执行按钮
    $buttonExecute = New-Object System.Windows.Forms.Button
    $buttonExecute.Location = New-Object System.Drawing.Point(100, 160)
    $buttonExecute.Size = New-Object System.Drawing.Size(75, 23)
    $buttonExecute.Text = "执行"            # “Execute”
    # 锚定于左下角 (Anchor to Bottom, Left)
    $buttonExecute.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($buttonExecute)

    # 退出按钮
    $buttonCancel = New-Object System.Windows.Forms.Button
    $buttonCancel.Location = New-Object System.Drawing.Point(200, 160)
    $buttonCancel.Size = New-Object System.Drawing.Size(75, 23)
    $buttonCancel.Text = "退出"            # “Exit”
    $buttonCancel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $form.Controls.Add($buttonCancel)

    # 为“浏览”输入文件按钮添加事件处理
    $buttonBrowseInput.Add_Click({
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "CSV 文件 (*.csv)|*.csv|所有文件 (*.*)|*.*"
            if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
            {
                $textBoxInput.Text = $openFileDialog.FileName
            }
        })

    # 为“浏览”输出文件按钮添加事件处理
    $buttonBrowseOutput.Add_Click({
            $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveFileDialog.Filter = "CSV 文件 (*.csv)|*.csv|所有文件 (*.*)|*.*"
            if ($saveFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
            {
                $textBoxOutput.Text = $saveFileDialog.FileName
            }
        })

    # 为“执行”按钮添加事件处理
    $buttonExecute.Add_Click({
            $inputFile = $textBoxInput.Text
            $outputFile = $textBoxOutput.Text
            $startRow = $textBoxStartRow.Text

            # 简单的输入检查
            if ([string]::IsNullOrEmpty($inputFile) -or -not (Test-Path $inputFile))
            {
                [System.Windows.Forms.MessageBox]::Show("请输入有效的输入文件路径！", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            if ([string]::IsNullOrEmpty($outputFile))
            {
                [System.Windows.Forms.MessageBox]::Show("请输入有效的输出文件路径！", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            if (-not [int]::TryParse($startRow, [ref]$null))
            {
                [System.Windows.Forms.MessageBox]::Show("起始行号必须为整数！", "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            $startRowInt = [int]$startRow

            try
            {
                Get-CsvTailRows -InputFile $inputFile -OutputFile $outputFile -StartRow $startRowInt
                [System.Windows.Forms.MessageBox]::Show("CSV 提取完成！", "信息", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            catch
            {
                [System.Windows.Forms.MessageBox]::Show("执行过程中发生错误：" + $_.Exception.Message, "错误", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        })

    # 为“退出”按钮添加事件处理
    $buttonCancel.Add_Click({
            $form.Close()
        })

    # 显示窗体
    [void]$form.ShowDialog()
}
function Export-NewCSVFile
{
    param (

        # [parameter(parametersetname = "SKU")]
        $StoppedSku = $StoppedSku,
 
        # 默认sku的对齐位数为7位数(不够的前头补零)
        $DigitBits = 7,
        $CsvDirectory,
        $OutputDirectory
    )
    # $StoppedSku = $StoppedSku -replace '.*?(0.*\d+).*', '$1' #从sk...U提取出数字(整数),例如45316
    $StoppedSku = $StoppedSku -replace '.*?(\d+).*', '$1' #从SK...U提取出数字(整数),例如45316
    Write-Verbose $StoppedSku -Verbose
    $StoppedSku = "{0:D$DigitBits}" -f [int]$StoppedSku #补齐位数到$DigitBits位数
    Write-Verbose "StoppedSku: $StoppedSku" -Verbose
    # # 开始处理
    $p_num = [int]($StoppedSku.Substring(0, 3)) + 1 #第几个文件出现断点,如果是分割为1000每条记录,则是SubString(0,2)
    $start_row = [int]($StoppedSku.Substring(3)) #开始分割的所在行号

    Write-Verbose "start_row: $start_row" -Verbose
    $p_name = "p$($p_num)"
    
    # 需要被截取的文件名字例如,假设你的文件名字类似于_pro_p5.csv; 
    $filename = "${Prefix}${p_name}.csv" 
    $inputfile = "$CsvDirectory\$filename".trim('\')  
    Test-Path $inputfile -PathType Leaf -ErrorAction Stop #检查文件是否存在
    Write-Host "Processing csv file: $inputfile"
    Write-Verbose "Number of spilting position:$start_row" -Verbose
    # $filename = ".\${p_name}.csv" # 简化方案:# ".\${p_name}.csv"
    
    Get-CsvTailRows -InputFile $inputfile -OutputFile "$OutputDirectory\${p_name}_${StoppedSku}+.csv" -StartRow $start_row -ShowInExplorer:$ShowInExplorer

    Write-Host "$("`n"*3)"
}
function Export-CsvSplitFiles
{
    <# 
    .SYNOPSIS
    将 CSV 文件平均分割成多个较小的 CSV 文件，如果无法平均，则余数放到最后一个文件中。

    .PARAMETER InputFile
    需要分割的 CSV 文件路径。

    .PARAMETER OutputDirectory
    输出分割后 CSV 文件的目录。

    .PARAMETER Numbers
    需要分割的文件数量（默认为 10）。

    .EXAMPLE
    Export-CsvSplitFiles -InputFile "C:\data\largefile.csv" -OutputDirectory "C:\data\split" -Numbers 5

    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        # [Parameter(Mandatory = $true)]
        [string]$OutputDirectory = "",

        [int]$Numbers = 10
    )
    if ($OutputDirectory -eq "")
    {
        $OutputDirectory = Split-Path $InputFile
    }

    # 确保输入文件存在
    if (-not (Test-Path $InputFile))
    {
        Write-Error "输入文件 $InputFile 不存在。"
        return
    }

    # 确保输出目录存在
    if (-not (Test-Path $OutputDirectory))
    {
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    }

    # 读取 CSV 文件
    $data = Import-Csv -Path $InputFile
    $totalRows = $data.Count

    if ($totalRows -eq 0)
    {
        Write-Error "CSV 文件没有数据。"
        return
    }

    # 计算每个文件应包含的行数
    $rowsPerFile = [math]::Ceiling($totalRows / $Numbers)

    # 分割数据并写入文件
    for ($i = 0; $i -lt $Numbers; $i++)
    {
        $start = $i * $rowsPerFile
        if ($start -ge $totalRows)
        {
            break
        }

        $end = [math]::Min($start + $rowsPerFile, $totalRows)
        $splitData = $data[$start..($end - 1)]

        # 生成文件名
        $fileBaseName = Split-Path $InputFile -LeafBase
        Write-Host $fileBaseName

        $outputFile = Join-Path -Path $OutputDirectory -ChildPath ("${fileBaseName}_split_{0}_$($start+1)-$end.csv" -f ($i + 1))

        # 导出 CSV
        $splitData | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

        Write-Host "已生成文件: $outputFile"
    }

    Write-Host "CSV 文件分割完成，输出目录: $OutputDirectory"
}

function Export-NewCSVFilesFromSKU
{
    <# 
    .DESCRIPTION
    # 以每分csv文件10000行记录为单位分割文件为例
    # 假设你发现断点为SK0045316-U ,那么你就将这个字符串中的数字45316记住或复制出来,或者直接粘贴这个SK0045316-U这个字符串也行,粘贴到以下变量中

    .PARAMETER StoppedSku
    #几万数据量
    $StoppedSku = "SK0045316-U" ,
    #十几万数据量
    $StoppedSku="SK0147823-U" 

    .PARAMETER CsvDirectory
    # csv目录的填写可选(填写csv文件所在目录,如果你运行脚本所在工作目录就是命令行工作目录,则不需要填写,否则请填写
    # 例如"C:\Users\Administrator\Downloads\pro_csv\fr1\outinfo")
    # $CsvDirectory = "C:\Users\Administrator\Downloads\pro_csv\fr1\outinfo"
    # $CsvDirectory = "C:\Users\Administrator\Downloads\pro_csv\outinfo"

    .Example

    #>
    <# 


    #>
    [cmdletbinding()]
    param(
        # $StoppedSku_list = @( "" ) ,
        #支持配置多个批处理,比如:"SK0049823-U, SK0019823-U, SK0029823-U"
        # $StoppedSku = "", 
        [String[]]$StoppedSku = @"
SK0006953-U
SK0016921-U
SK0027225-U
SK0037182-U
SK0045216-U
SK0053924-U
    
"@
        ,
        $CsvDirectory = "C:\Users\Administrator\Downloads\pro_csv\outinfo" ,
        # $Prefix = "_pro_",
        #简化后可以置为空串""
        $Prefix = "",
        $OutputDirectory = $CsvDirectory,
        [switch]$ShowInExplorer
    )

    #无论用户输入的是逗号分割的字符串,还是本身就是一个数组,都转化为数组统一处理
    # 然后转为字符串输出以便使用-replace等方法提取sku
    $StoppedSku = @($StoppedSku) -join ','
    Write-Host "StoppedSkuString: $StoppedSku"
    $StoppedSku_list = $StoppedSku.trim() -replace ',', "`n" -replace ' ', ""
    # Write-Host "[$StoppedSku_list]"
    foreach ($sku in $StoppedSku_list)
    {
        Write-Host "((`n$sku`n))"
    }
    $StoppedSku_list = -split $StoppedSku_list 
    # Write-Host "[$StoppedSku_list]"
    
    # return $StoppedSku_list
    foreach ($sku in $StoppedSku_list)
    {
        Write-Host "[[$sku]]"
        Export-NewCSVFile -StoppedSku $sku -OutputDirectory $OutputDirectory -CsvDirectory $CsvDirectory 
    }
    
    Pause 
}
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
    [CmdletBinding(DefaultParameterSetName = 'Range')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(parameterSetName = 'StartToEnd')]
        [int]$StartRow,

        [Parameter(parameterSetName = 'StartToEnd')]
        [int]$EndRow = "",
        [parameter(ParameterSetName = 'Range')]
        $Range,

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
    if($PSCmdlet.ParameterSetName -eq 'Range')
    {

        $range = @($Range)
        Write-Warning $range.Count
        # Write-Host "[$($range[0])]"
        if($range.Count -eq 2)
        {
            $StartRow = $range[0]
            $EndRow = $range[1]
        }
        elseif($range.Count -eq 1)
        {
            $StartRow = $range[0]
        }
    }
    
    # Write-Verbose $Range.GetEnumerator() 
    Write-Verbose "startRow: $StartRow, endRow: $EndRow"
    # 验证 StartRow 是否合法
    if ($StartRow -lt 1 -or $StartRow -gt $totalRows)
    {
        Write-Error "StartRow 超出范围。文件[$Path]行数限制:有效范围为 1 到 $($totalRows)"
        return
    }

    # 如果未提供 EndRow，则设置为最后一行
    # if (-not $PSBoundParameters.ContainsKey('EndRow'))
    if(!$Endrow)
    {
        $EndRow = $totalRows
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
        Write-Verbose $headerLine
    }
    catch
    {
        Write-Error "读取表头失败: $_"
        return
    }

    # 如果未指定输出文件路径，生成默认路径
    if (-not $Output)
    {
        Write-Verbose "未指定输出文件路径，使用默认路径。"
        
        $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $outputDirectory = Split-Path -Path $Path
        Write-Verbose "OutputDirectory: $outputDirectory"

        $Output = Join-Path -Path $outputDirectory -ChildPath "${fileBaseName}_${StartRow}-${EndRow}.csv"
        $fullPath = [System.IO.Path]::GetFullPath( $Output)
        Write-Verbose "Output: [$fullPath]"
    }

    # 写入新文件
    try
    {
        # 写入表头
        Set-Content -Path $Output -Value $headerLine -Encoding UTF8 -Force
        # Pause
        # 写入选定的行
        if ($selectedRows.Count -gt 0)
        {
            $selectedRows | Export-Csv -Path $Output -Append -Force -NoTypeInformation -Encoding UTF8
        }
    }
    catch
    {
        Write-Error "写入文件失败: $_"
        return
    }
    Get-CsvPreview $selectedRows

    Write-Output "新的CSV文件已保存到: [$fullPath]"
}

function Get-CsvRowsByPercentage
{
    <#
.SYNOPSIS
    提取CSV文件的表头和从指定百分比位置到最后一行的数据，并将其保存到指定输出文件中。

.DESCRIPTION
    该脚本读取输入的CSV文件，提取表头（第一行）和指定百分比位置到最后一行的数据，
    然后将提取的内容保存到指定的输出文件中。

.PARAMETER InputFile
    输入的CSV文件路径。

.PARAMETER OutputFile
    输出的CSV文件路径。

.PARAMETER StartPercentage
    提取数据开始的百分比，例如 80 表示提取最后 20% 的数据。

.EXAMPLE
    .\Extract-CsvRows.ps1 -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartPercentage 80
    从`C:\path\to\input.csv`文件中提取表头和最后20%的数据，并将其保存到`C:\path\to\output.csv`。

.NOTES
    - 文件使用UTF-8编码进行读写。
    - 百分比值应在 0-100 之间。
#>

    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile, # 输入的CSV文件路径

        # [Parameter(Mandatory=$true)]
        [string]$OutputFile, # 输出的CSV文件路径

        [Parameter(Mandatory = $true)]
        [int]$StartPercentage   # 提取开始的百分比位置 (0-100)
    )

    # 验证百分比范围
    if ($StartPercentage -lt 0 -or $StartPercentage -gt 100)
    {
        Write-Error "StartPercentage 必须在 0 到 100 之间。"
        return
    }

    # 读取CSV文件
    try
    {
        $data = Import-Csv -Path $InputFile
    }
    catch
    {
        Write-Error "读取CSV文件失败: $_"
        return
    }

    # 获取总行数
    $totalRows = $data.Count

    if ($totalRows -eq 0)
    {
        Write-Error "输入文件没有数据。"
        return
    }

    # 计算起始行号
    $startRow = [math]::Ceiling($totalRows * ($StartPercentage / 100.0))

    # 提取表头行
    $header = $data | Select-Object -First 0

    # 提取从起始行到最后一行的数据
    $rows = $data | Select-Object -Skip ($startRow - 1)

    # 保存表头行和提取的行到新的输出文件
    try
    {
        # 输出表头行
        $header | Export-Csv -Path $OutputFile -NoTypeInformation -Force
        # 输出提取的数据行
        $rows | Export-Csv -Path $OutputFile -NoTypeInformation -Append -Force
    }
    catch
    {
        Write-Error "保存CSV文件失败: $_"
    }

    Write-Host "处理完成，结果已保存到: $OutputFile"
}