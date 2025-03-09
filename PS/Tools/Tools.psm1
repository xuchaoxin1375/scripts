function Get-CxxuPsModuleVersoin
{
    param (
        
    )
    Get-RepositoryVersion -Repository $scripts
    
}

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
    $row | Select-Object -First 3 | Format-Table ; Write-Host "....";
    Write-Host "Totol lines:$($row.count)"
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

    #⚡️[Administrator@CXXUDESK][C:\repos\LocoySpider\数据处理\csv上传中断处理][21:37:47][UP:2.99Days]
    PS> .\Get-NewCsvFiles.ps1 -Prefix ""

    正在处理文件: C:\Users\Administrator\Downloads\pro_csv\outinfo\p3.csv
    VERBOSE: 分割行号为:9823
    VERBOSE: StartRow:9823
    处理完成，结果已保存到: C:\Users\Administrator\Downloads\pro_csv\outinfo\p3_SK0029823-U+.csv
    C:\Users\Administrator\Downloads\pro_csv\outinfo

    SKU         Name
    ---         ----
    SK0029823-U Paquet de tissus viscose 382
    SK0029824-U Paquet de tissus viscose 381
    SK0029825-U Paquet de tissus viscose 383

    ....
    Totol data lines:177
    #>
    <# 


    #>
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

# 调用示例
# Extract-CsvRows -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartPercentage 80

# 调用示例
# Extract-CsvRows -InputFile "C:\path\to\input.csv" -OutputFile "C:\path\to\output.csv" -StartRow 5
function Set-OpenWithVscode
{
    <# 
    .SYNOPSIS
    设置 VSCode 打开方式为默认打开方式。
    .DESCRIPTION
    直接使用powershell的命令不是很方便
    这里通过创建一个临时的reg文件,然后调用reg import命令导入
    支持添加右键菜单open with vscode 
    也支持移除open with vscode 菜单
    你可以根据喜好设置标题,比如open with Vscode 或者其他,open with code之类的名字
    .EXAMPLE
    简单默认参数配置
    Set-OpenWithVscode

    .EXAMPLE
    完整的参数配置
    Set-OpenWithVscode -Path "C:\Program Files\Microsoft VS Code\Code.exe" -MenuName "Open with VsCode"
    .EXAMPLE
    移除右键vscode菜单
    PS> Set-OpenWithVscode -Remove
    #>
    <# 
    .NOTES
    也可以按照如下格式创建vscode.reg文件，然后导入注册表

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\*\shell\VSCode]
    @=$MenuName
    "Icon"="C:\\Program Files\\Microsoft VS Code\\Code.exe"

    [HKEY_CLASSES_ROOT\*\shell\VSCode\command]
    @="$PathWrapped \"%1\""

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\Directory\shell\VSCode]
    @=$MenuName
    "Icon"="C:\\Program Files\\Microsoft VS Code\\Code.exe"

    [HKEY_CLASSES_ROOT\Directory\shell\VSCode\command]
    @="$PathWrapped \"%V\""

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode]
    @=$MenuName
    "Icon"="C:\\Program Files\\Microsoft VS Code\\Code.exe"

    [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode\command]
    @="$PathWrapped \"%V\""

    #>

    [CmdletBinding(DefaultParameterSetName = "Add")]
    param (
        [parameter(ParameterSetName = "Add")]
        $Path = "C:\Program Files\Microsoft VS Code\Code.exe",
        [parameter(ParameterSetName = "Add")]
        $MenuName = "Open with VsCode",
        [parameter(ParameterSetName = "Remove")]
        [switch]$Remove
    )
    Write-Verbose "Set [$Path] as Vscode Path(default installation path)" -Verbose
    # 定义 VSCode 安装路径
    #debug
    # $Path = "C:\Program Files\Microsoft VS Code\Code.exe"
    $PathForWindows = ($Path -replace '\\', "\\")
    $PathWrapped = '\"' + $PathForWindows + '\"' # 由于reg添加右键打开的规范,需要得到形如此的串 \"C:\\Program Files\\Microsoft VS Code\\Code.exe\"
    $MenuName = '"' + $MenuName + '"' # 去除空格

    # 将注册表内容作为多行字符串保存
    $AddMenuRegContent = @"
    Windows Registry Editor Version 5.00
   
       [HKEY_CLASSES_ROOT\*\shell\VSCode]
       @=$MenuName
       "Icon"="$PathForWindows" 
   
       [HKEY_CLASSES_ROOT\*\shell\VSCode\command]
       @="$PathWrapped \"%1\""
   
       Windows Registry Editor Version 5.00
   
       [HKEY_CLASSES_ROOT\Directory\shell\VSCode]
       @=$MenuName
       "Icon"="$PathForWindows" 
   
       [HKEY_CLASSES_ROOT\Directory\shell\VSCode\command]
       @="$PathWrapped \"%V\""
   
       Windows Registry Editor Version 5.00
   
       [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode]
       @=$MenuName
       "Icon"="$PathForWindows" 
   
       [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode\command]
       @="$PathWrapped \"%V\""
"@  
    $RemoveMenuRegContent = @"
    Windows Registry Editor Version 5.00

[-HKEY_CLASSES_ROOT\*\shell\VSCode]

[-HKEY_CLASSES_ROOT\*\shell\VSCode\command]

[-HKEY_CLASSES_ROOT\Directory\shell\VSCode]

[-HKEY_CLASSES_ROOT\Directory\shell\VSCode\command]

[-HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode]

[-HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode\command]
"@
    $regContent = $AddMenuRegContent
    # if ($Remove)
    if ($PSCmdlet.ParameterSetName -eq "Remove")
    {
        # 执行 reg delete 命令删除注册表文件
        Write-Verbose "Removing VSCode context menu entries..."
        $regContent = $RemoveMenuRegContent

    }
    # 检查 VSCode 是否安装在指定路径
    elseif (Test-Path $Path)
    {
          
        Write-Verbose "The specified VSCode path exists. Proceeding with registry creation."
    }
    else
    {
        Write-Host "The specified VSCode path does not exist. Please check the path."
        Write-Host "use -Path to specify the path of VSCode installation."
    }

    Write-Host "Creating registry entries for VSCode:"
    
    
    # 创建临时 .reg 文件路径
    $tempRegFile = [System.IO.Path]::Combine($env:TEMP, "vs-code-context-menu.reg")
    # 将注册表内容写入临时 .reg 文件
    $regContent | Set-Content -Path $tempRegFile
    
    # Write-Host $AddMenuRegContent
    Get-Content $tempRegFile
    # 删除临时 .reg 文件
    # Remove-Item -Path $tempRegFile -Force

    # 执行 reg import 命令导入注册表文件
    try
    {
        reg import $tempRegFile
        Write-Host "Registry entries for VSCode have been successfully created."
    }
    catch
    {
        Write-Host "An error occurred while importing the registry file."
    }
    Write-Host "Completed.Refresh Explorer to see changes."
}

function Get-BatchSiteBuilderLines
{
    <# 
    .SYNOPSIS
    获取批量站点生成器的生成命令行(宝塔面板专用)
    .DESCRIPTION
    格式说明
    批量格式：域名|根目录|FTP|数据库|PHP版本
    
    案例： bt.cn,test.cn:8081|/www/wwwroot/bt.cn|1|1|56


    最简单的站点:
    域名|1|0|0|0

    1.   域名参数：多个域名用 , 分割
    2.   根目录参数：填写 1 为自动创建，或输入具体目录
    3.   FTP参数：填写 1 为自动创建，填写 0 为不创建
    4.   数据库参数：填写 1 为自动创建，填写 0 为不创建
    5.   PHP版本参数：填写 0 为静态，或输入PHP具体版本号列如：56、71、74

    如需添加多个站点，请换行填写

    .NOTES
    domain1.com
    domain2.com
    domain3.com

    .EXAMPLE
    #测试命令行

Get-BatchSiteBuilderLines  -user zw -domains @"
            domain1.com
            domain2.com
            domain3.com
"@
#回车执行


    .EXAMPLE
    执行结果
    #⚡️[Administrator@CXXUDESK][~\Desktop][9:21:52][UP:4.66Days]
    PS> Get-BatchSiteBuilderLines  -user zw -domains @"
    >>     domain1.com
    >>     domain2.com
    >>     domain3.com
    >> "@
    domain1.com,*.domain1.com       |/www/wwwroot/zw/domain1.com    |0|0|84
    domain2.com,*.domain2.com       |/www/wwwroot/zw/domain2.com    |0|0|84
    domain3.com,*.domain3.com       |/www/wwwroot/zw/domain3.com    |0|0|84
    .EXAMPLE
    #⚡️[Administrator@CXXUDESK][~\Desktop][9:22:07][UP:4.66Days]
    PS> Get-BatchSiteBuilderLines  -domains @"
    >>     domain1.com
    >>     domain2.com
    >>     domain3.com
    >> "@
    domain1.com,*.domain1.com       |/www/wwwroot/domain1.com       |0|0|84
    domain2.com,*.domain2.com       |/www/wwwroot/domain2.com       |0|0|84
    domain3.com,*.domain3.com       |/www/wwwroot/domain3.com       |0|0|84
    #>
    [CmdletBinding()]
    param (
        $domains = @"
domain1.com
domain2.com
"@,
        $LD3 = "*"    ,
        $user,
    
        $php = 84
    )
    $domains = $domains.trim() -split "`r?`n" | Where-Object { $_.Length }
    $lines = [System.Collections.ArrayList]@()
    # $domains = $domains -replace "`r?`n", ";"
    # $domains = $domains -replace "`n", ";"
    # Write-Verbose $domains
    Write-Verbose "$($domains.Length)" 

    foreach ($domain in $domains)
    {
        Write-Verbose "[$domain]"
        $domain = $domain.Trim()
        $line = "$domain,$LD3.$domain`t|/www/wwwroot/$user/$domain`t|0|0|$php" -replace "//", "/" 
        $line = $line.Trim()
        Write-Host $line
        $lines.Add($line) > $null
    }
    $lines | Set-Clipboard
}

function Start-HTTPServer
{
    <#
    .SYNOPSIS
    启动一个简单的HTTP文件服务器

    .DESCRIPTION
    将指定的本地文件夹作为HTTP服务器的根目录,默认监听在8080端口

    .PARAMETER Path
    指定要作为服务器根目录的本地文件夹路径

    .PARAMETER Port
    指定HTTP服务器要监听的端口号,默认为8080

    .EXAMPLE
    Start-SimpleHTTPServer -Path "C:\Share" -Port 8000
    将C:\Share文件夹作为根目录,在8000端口启动HTTP服务器

    .EXAMPLE
    Start-SimpleHTTPServer
    将当前目录作为根目录,在8080端口启动HTTP服务器
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path,
        
        [Parameter(Position = 1)]
        [int]$Port = 8080
    )

    Add-Type -AssemblyName System.Web
    try
    {
        # 验证路径是否存在
        if (-not (Test-Path $Path))
        {
            throw "指定的路径 '$Path' 不存在"
        }

        # 创建HTTP监听器
        $Listener = New-Object System.Net.HttpListener
        $Listener.Prefixes.Add("http://+:$Port/")

        # 尝试启动监听器
        try
        {
            $Listener.Start()
        }
        catch
        {
            throw "无法启动HTTP服务器,可能是权限不足或端口被占用: $_"
        }

        Write-Host "HTTP服务器已启动:"
        Write-Host "根目录: $Path"
        Write-Host "地址: http://localhost:$Port/"
        Write-Host "按 Ctrl+C 停止服务器(可能需要数十秒的时间,如果等不及可以考虑关闭掉对应的命令行窗口)"

        while ($Listener.IsListening)
        {
            # 等待请求
            $Context = $Listener.GetContext()
            $Request = $Context.Request
            $Response = $Context.Response
            
            # URL解码请求路径
            $DecodedPath = [System.Web.HttpUtility]::UrlDecode($Request.Url.LocalPath)
            $LocalPath = Join-Path $Path $DecodedPath.TrimStart('/')
            
            # 设置响应头，支持UTF-8
            $Response.Headers.Add("Content-Type", "text/html; charset=utf-8")
            
            # 处理目录请求
            if ((Test-Path $LocalPath) -and (Get-Item $LocalPath).PSIsContainer)
            {
                $LocalPath = Join-Path $LocalPath "index.html"
                if (-not (Test-Path $LocalPath))
                {
                    # 生成目录列表
                    $Content = Get-DirectoryListing $DecodedPath.TrimStart('/') (Get-ChildItem (Join-Path $Path $DecodedPath.TrimStart('/')))
                    $Buffer = [System.Text.Encoding]::UTF8.GetBytes($Content)
                    $Response.ContentLength64 = $Buffer.Length
                    $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
                    $Response.Close()
                    continue
                }
            }

            # 处理文件请求
            if (Test-Path $LocalPath)
            {
                $File = Get-Item $LocalPath
                $Response.ContentType = Get-MimeType $File.Extension
                $Response.ContentLength64 = $File.Length
                
                # 添加文件名编码支持
                $FileName = [System.Web.HttpUtility]::UrlEncode($File.Name)
                $Response.Headers.Add("Content-Disposition", "inline; filename*=UTF-8''$FileName")
                
                $FileStream = [System.IO.File]::OpenRead($File.FullName)
                $FileStream.CopyTo($Response.OutputStream)
                $FileStream.Close()
            }
            else
            {
                # 返回404
                $Response.StatusCode = 404
                $Content = "404 - 文件未找到"
                $Buffer = [System.Text.Encoding]::UTF8.GetBytes($Content)
                $Response.ContentLength64 = $Buffer.Length
                $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
            }

            $Response.Close()
        }
    }
    finally
    {
        if ($Listener)
        {
            $Listener.Stop()
            $Listener.Close()
        }
    }
}

function Start-HTTPServerBG
{
    param (
        # 默认shell为windows powershell,如果安装了powershell7+ (即pwsh)可以用pwsh代替;
        # 默认情况下,需要将Start-HTTPServer写入到powershell配置文件中或者powershell的自动导入模块中,否则Start-HTTPServerBG命令不可用,导致启动失败
        # $shell = "powershell",
        $shell = "pwsh", #个人使用pwsh比较习惯
        $path = "$home\desktop",
        $Port = 8080
    )
    Write-Verbose "try to start http server..." -Verbose
    # $PSBoundParameters 
    $params = [PSCustomObject]@{
        shell = $shell
        path  = $path
        Port  = $Port
    }
    Write-Output $params #不能直接用Write-Output输出字面量对象,会被当做字符串输出
    # Write-Output $shell, $path, $Port
    # $exp = "Start-Process -WindowStyle Hidden -FilePath $shell -ArgumentList { -c Start-HTTPServer -path $path -port $Port } -PassThru"
    # Write-Output $exp
    # $ps = $exp | Invoke-Expression
    
    # $func = ${Function:Start-HTTPServer} #由于Start-HttpServer完整代码过于分散,仅仅这样写不能获得完整的Start-HTTPServer函数
    $ps = Start-Process -WindowStyle Hidden -FilePath $shell -ArgumentList "-c Start-HTTPServer -path $path -port $Port" -PassThru
    #debug start-process语法
    # $ps = Start-Process -FilePath pwsh -ArgumentList "-c", "Get-Location;Pause "

    return $ps
    
}
function Get-DirectoryListing
{
    param($RelativePath, $Items)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Index of /$RelativePath</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { text-align: left; padding: 8px; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; }
        tr:hover { background-color: #f5f5f5; }
        a { text-decoration: none; color: #0066cc; }
        .size { text-align: right; }
        .date { white-space: nowrap; }
    </style>
</head>
<body>
    <h1>Index of /$RelativePath</h1>
    <table>
        <tr>
            <th>名称</th>
            <th class="size">大小</th>
            <th class="date">修改时间</th>
        </tr>
"@

    if ($RelativePath)
    {
        $html += "<tr><td><a href='../'>..</a></td><td></td><td></td></tr>"
    }

    # 分别处理文件夹和文件，并按名称排序
    $Folders = $Items | Where-Object { $_.PSIsContainer } | Sort-Object Name
    $Files = $Items | Where-Object { !$_.PSIsContainer } | Sort-Object Name

    # 先显示文件夹
    foreach ($Item in $Folders)
    {
        $Name = $Item.Name
        $LastModified = $Item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        $EncodedName = [System.Web.HttpUtility]::UrlEncode($Name)
        
        $html += "<tr><td><a href='$EncodedName/'>$Name/</a></td><td class='size'>-</td><td class='date'>$LastModified</td></tr>"
    }

    # 再显示文件
    foreach ($Item in $Files)
    {
        $Name = $Item.Name
        $Size = Format-FileSize $Item.Length
        $LastModified = $Item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        $EncodedName = [System.Web.HttpUtility]::UrlEncode($Name)
        
        $html += "<tr><td><a href='$EncodedName'>$Name</a></td><td class='size'>$Size</td><td class='date'>$LastModified</td></tr>"
    }

    $html += @"
    </table>
    <footer style="margin-top: 20px; color: #666; font-size: 12px;">
        共 $($Folders.Count) 个文件夹, $($Files.Count) 个文件
    </footer>
</body>
</html>
"@

    return $html
}

function Format-FileSize
{
    param([long]$Size)
    
    if ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size / 1GB) }
    if ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size / 1MB) }
    if ($Size -gt 1KB) { return "{0:N2} KB" -f ($Size / 1KB) }
    return "$Size B"
}

function Get-MimeType
{
    param([string]$Extension)
    
    $MimeTypes = @{
        ".txt"  = "text/plain; charset=utf-8"
        ".ps1"  = "text/plain; charset=utf-8"
        ".py"   = "text/plain; charset=utf-8"
        ".htm"  = "text/html; charset=utf-8"
        ".html" = "text/html; charset=utf-8"
        ".css"  = "text/css; charset=utf-8"
        ".js"   = "text/javascript; charset=utf-8"
        ".json" = "application/json; charset=utf-8"
        ".jpg"  = "image/jpeg"
        ".jpeg" = "image/jpeg"
        ".png"  = "image/png"
        ".gif"  = "image/gif"
        ".pdf"  = "application/pdf"
        ".xml"  = "application/xml; charset=utf-8"
        ".zip"  = "application/zip"
        ".md"   = "text/markdown; charset=utf-8"
        ".mp4"  = "video/mp4"
        ".mp3"  = "audio/mpeg"
        ".wav"  = "audio/wav"
    }
    
    # return $MimeTypes[$Extension.ToLower()] ?? "application/octet-stream"
    $key = $Extension.ToLower()
    if ($MimeTypes.ContainsKey($key))
    {
        return $MimeTypes[$key]
    }
    return "application/octet-stream"
}

function Get-CharacterEncoding
{

    <# 
    .SYNOPSIS
    显示字符串的字符编码信息,包括Unicode编码,UTF8编码,ASCII编码
    .DESCRIPTION
    利用此函数来分析给定字符串中的各个字符的编码,尤其是空白字符,在执行空白字符替换时,可以排查出不可见字符替换不掉的问题
    .EXAMPLE
    PS> Get-CharacterEncoding -InputString "  0.46" | Format-Table -AutoSize

    Character UnicodeCode UTF8Encoding AsciiCode
    --------- ----------- ------------ ---------
            U+0020      0x20                32
              U+00A0      0xC2 0xA0          N/A
            0 U+0030      0x30                48
            . U+002E      0x2E                46
            4 U+0034      0x34                52
            6 U+0036      0x36                54
    #>
    param (
        [string]$InputString
    )
    $utf8 = [System.Text.Encoding]::UTF8

    $InputString.ToCharArray() | ForEach-Object {
        $char = $_
        $unicode = [int][char]$char
        $utf8Bytes = $utf8.GetBytes([char[]]$char)
        $utf8Hex = $utf8Bytes | ForEach-Object { "0x{0:X2}" -f $_ }
        $ascii = if ($unicode -lt 128) { $unicode } else { "N/A" }

        [PSCustomObject]@{
            Character    = $char
            UnicodeCode  = "U+{0:X4}" -f $unicode
            UTF8Encoding = ($utf8Hex -join " ")
            AsciiCode    = $ascii
        }
    }
}




function Get-CharacterEncodingsGUI
{
    # 加载 Windows Forms 程序集
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # 定义函数
    function Get-CharacterEncoding
    {
        param (
            [string]$InputString
        )
        $utf8 = [System.Text.Encoding]::UTF8

        $InputString.ToCharArray() | ForEach-Object {
            $char = $_
            $unicode = [int][char]$char
            $utf8Bytes = $utf8.GetBytes([char[]]$char)
            $utf8Hex = $utf8Bytes | ForEach-Object { "0x{0:X2}" -f $_ }
            $ascii = if ($unicode -lt 128) { $unicode } else { "N/A" }

            [PSCustomObject]@{
                Character    = $char
                UnicodeCode  = "U+{0:X4}" -f $unicode
                UTF8Encoding = ($utf8Hex -join " ")
                AsciiCode    = $ascii
            }
        }
    }

    # 创建主窗体
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "字符编码实时解析"
    $form.Size = New-Object System.Drawing.Size(800, 600)
    $form.StartPosition = "CenterScreen"

    # 创建输入框
    $inputBox = New-Object System.Windows.Forms.TextBox
    $inputBox.Location = New-Object System.Drawing.Point(10, 10)
    $inputBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $inputBox.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 12)
    $inputBox.Multiline = $true
    $inputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $inputBox.WordWrap = $true
    $inputBox.Size = New-Object System.Drawing.Size(760, 60)
    $form.Controls.Add($inputBox)

    # 创建结果显示框
    $resultBox = New-Object System.Windows.Forms.TextBox
    $resultBox.Location = New-Object System.Drawing.Point(10, ($inputBox.Location.Y + $inputBox.Height + 10)) # 使用数值计算位置
    $resultBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $resultBox.Multiline = $true
    $resultBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $resultBox.ReadOnly = $true
    $resultBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $resultBox.Size = New-Object System.Drawing.Size(760, ($form.ClientSize.Height - ($inputBox.Location.Y + $inputBox.Height + 20)))
    $form.Controls.Add($resultBox)

    # 动态调整输入框高度
    $inputBox.Add_TextChanged({
            $lineCount = $inputBox.Lines.Length
            $fontHeight = $inputBox.Font.Height
            $padding = 10
            $newHeight = ($lineCount * $fontHeight) + $padding

            # 限制最小和最大高度
            $minHeight = 60
            $maxHeight = 200
            $inputBox.Height = [Math]::Min([Math]::Max($newHeight, $minHeight), $maxHeight)

            # 调整结果框位置和高度
            $resultBox.Top = $inputBox.Location.Y + $inputBox.Height + 10
            $resultBox.Height = $form.ClientSize.Height - $resultBox.Top - 10
        })

    # 实时解析事件
    $inputBox.Add_TextChanged({
            $inputText = $inputBox.Text
            if (-not [string]::IsNullOrEmpty($inputText))
            {
                $result = Get-CharacterEncoding -InputString $inputText | Format-Table | Out-String
                $resultBox.Text = $result
            }
            else
            {
                $resultBox.Clear()
            }
        })

    # 窗体大小调整事件
    $form.Add_SizeChanged({
            $inputBox.Width = $form.ClientSize.Width - 20
            $resultBox.Width = $form.ClientSize.Width - 20
            $resultBox.Height = $form.ClientSize.Height - $resultBox.Top - 10
        })

    # 显示窗口
    [void]$form.ShowDialog()
}


function regex_tk_tool
{
    $p = Resolve-Path "$PSScriptRoot/../../pythonScripts/regex_tk_tool.py"
    Write-Verbose "$p"
    python $p
}
function Get-RepositoryVersion
{
    <# 
    通过git提交时间显示版本情况
    #>
    param (
        $Repository = './'
    )
    $Repository = Resolve-Path $Repository
    Write-Verbose "Repository:[$Repository]" -Verbose
    Write-Output $Repository
    Push-Location $Repository
    git log -1
    Pop-Location
    # Set-Location $Repository
    # git log -1 
    # Set-Location -

    # git log -1 --pretty=format:'%h - %an, %ar%n%s'
    
}
function Set-Defender
{
    . "$PSScriptRoot\..\..\cmd\WDC.bat"
}
function Format-IndexObject
{
    <# 
    .SYNOPSIS
    将数组格式化为带行号的表格,第一列为Index(如果不是可以自行select调整)，其他列为原来数组中元素对象的属性列
    .DESCRIPTION
    可以和轻量的Format-DoubleColumn互补,但是不要同时使用它们
    #>
    <# 
    .EXAMPLE
    PS> Get-EnvList -Scope User|Format-IndexObject

    Indexi Scope Name                     Value
    ------ ----- ----                     -----
        1 User  MSYS2_MINGW              C:\msys64\ucrt64\bin
        2 User  NVM_SYMLINK              C:\Program Files\nodejs
        3 User  powershell_updatecheck   LTS
        4 User  GOPATH                   C:\Users\cxxu\go
        5 User  Path                     C:\repos\scripts;...
    #>
    param (
        [parameter(ValueFromPipeline)]
        $InputObject,
        $IndexColumnName = 'Index_i'
    )
    begin
    {
        $index = 1
    }
    process
    {
        foreach ($item in $InputObject)
        {
            # $e=[PSCustomObject]@{
            #     Index = $index
           
            # }
            $item | Add-Member -MemberType NoteProperty -Name $IndexColumnName -Value $index -ErrorAction Break
            $index++
            Write-Debug "$IndexColumnName=$index"
        
            # 使用get-member查看对象结构
            # $item | Get-Member
            $item | Select-Object *
        }
    }
}

function Format-EnvItemNumber
{
    <#
    .SYNOPSIS 
    辅助函数,用于将Get-EnvList(或Get-EnvVar)的返回值转换为带行号的表格
 
     #>
    [OutputType([EnvVar[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [envvar[]] $Envvar,
        #是否显式传入Scope
        $Scope = 'Combined'
    )
    # 对数组做带序号（index）的枚举操作,经常使用此for循环
    begin
    {
        $res = @()
        $index = 1
    }
    process
    {
        # for ($i = 0; $i -lt $Envvar.Count; $i++)
        # {
        #     # 适合普通方式调用,不适合管道传参(对计数不友好,建议用foreach来遍历)
        #     Write-Debug "i=$i" #以管道传参调用本函数是会出现不正确计数,$Envvar总是只有一个元素,不同于不同传参,这里引入index变量来计数
        # } 

        foreach ($env in $Envvar)
        {
            # $env = [PSCustomObject]@{
            #     'Number' = $index 
            #     'Scope'  = $env.Scope
            #     'Name'   = $Env.Name
            #     'Value'  = $Env.Value
            # }
      
            $value = $env | Select-Object -ExpandProperty value 
            $value = $value -split ';' 
            Write-Debug "$($value.count)"
            $tb = $value | Format-DoubleColumn
            $separator = "-End OF-$index-[$($env.Name)]-------------------`n"
            Write-Debug "$env , index=$index"
            $index++
            $res += $tb + $separator
        }
    }
    end
    {
        Write-Debug "count=$($res.count)"
        return $res 
    }
}
function Format-DoubleColumn
{

    <# 
    .SYNOPSIS
    将数组格式化为双列,第一列为Index，第二列为Value,完成元素计数和展示任务
    .DESCRIPTION
    支持管道符,将数组通过管道符传递给此函数即可
    还可以进一步传递结果给Format-table做进一步格式化等操作,比如换行等操作
    #>
    <# 
    .EXAMPLE
    $array = @("Apple", "Banana", "Cherry", "Date", "Elderberry")
    $array | Format-DoubleColumn | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$InputObject
    )

    begin
    {
        $index = 1

    }

    process
    {
        # Write-Debug "InputObject Count: $($InputObject.Count)"
        # Write-Debug "InputObject:$inputObject"
        foreach ($item in $InputObject)
        {
            [PSCustomObject]@{
                Index = $index
                Value = $item
            }
            $index++
        }
    }
}
function Set-ExplorerSoftwareIcons
{
    <# 
    .SYNOPSIS
    本命令用于禁用系统Explorer默认的计算机驱动器以外的软件图标,尤其是国内的网盘类软件(百度网盘,夸克网盘,迅雷,以及许多视频类软件)
    也可以撤销禁用
    .PARAMETER Enabled
    是否允许软件设置资源管理器内的驱动器图标
    使用True表示允许
    使用False表示禁用(默认)
    .NOTES
    使用管理员权限执行此命令
    .NOTES
    如果软件是为全局用户安装的,那么还需要考虑HKLM,而不是仅仅考虑HKCU
    ls 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\'
    #>
    <# 
    .EXAMPLE
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled True
    refresh explorer to check icons
    #禁用其他软件设置资源管理器驱动器图标
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled False
    refresh explorer to check icons
    .EXAMPLE
    显示设置过程信息
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled True -Verbose
    # VERBOSE: Enabled Explorer Software Icons (allow Everyone Permission)
    refresh explorer to check icons
    .EXAMPLE
    显示设置过程信息,并且启动资源管理器查看刷新后的图标是否被禁用或恢复
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled True -Verbose -RefreshExplorer
    VERBOSE: Enabled Explorer Software Icons (allow Everyone Permission)
    refresh explorer to check icons
    PS C:\Users\cxxu\Desktop> set-ExplorerSoftwareIcons -Enabled False -Verbose -RefreshExplorer
    VERBOSE: Disabled Explorer Software Icons (Remove Everyone Group Permission)
    refresh explorer to check icons

    #>
    [CmdletBinding()]
    param (
        [ValidateSet('True', 'False')]$Enabled ,
        [switch]$RefreshExplorer
    )
    $pathUser = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'
    $pathMachine = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace'
    function Set-PathPermission
    {
        param (
            $Path
        )
        
        $acl = Get-Acl -Path $path -ErrorAction SilentlyContinue
    
        # 禁用继承并删除所有继承的访问规则
        $acl.SetAccessRuleProtection($true, $false)
    
        # 清除所有现有的访问规则
        $acl.Access | ForEach-Object {
            # $acl.RemoveAccessRule($_) | Out-Null
            $acl.RemoveAccessRule($_) *> $null
        } 
    
    
        # 添加SYSTEM和Administrators的完全控制权限
        $identities = @(
            'NT AUTHORITY\SYSTEM'
            # ,
            # 'BUILTIN\Administrators'
        )
        if ($Enabled -eq 'True')
        {
            $identities += @('Everyone')
            Write-Verbose "Enabled Explorer Software Icons [$path] (allow Everyone Permission)"
        }
        else
        {
            Write-Verbose "Disabled Explorer Software Icons [$path] (Remove Everyone Group Permission)"
        }
        foreach ($identity in $identities)
        {
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
        }
    
        # 应用新的ACL
        Set-Acl -Path $path -AclObject $acl # -ErrorAction Stop
    }
    foreach ($path in @($pathUser, $pathMachine))
    {
        Set-PathPermission -Path $path *> $null
    }
    Write-Host 'refresh explorer to check icons'    
    if ($RefreshExplorer)
    {
        explorer.exe
    }
}
function pow
{
    [CmdletBinding()]
    param(
        [double]$base,
        [double]$exponent
    )
    return [math]::pow($base, $exponent)
}

# function invoke-aria2Downloader
# {
#     param (
#         $url,
#         [Alias('spilit')]
#         $s = 16,
        
#         [Alias('max-connection-per-server')]
#         $x = 16,

#         [Alias('min-split-size')]
#         $k = '1M'
#     )
#     aria2c -s $s -x $s -k $k $url
    
# }

Function Set-ScreenResolutionAndOrientation-AntiwiseClock
{ 
    <#  :cmd header for PowerShell script
    @   set dir=%~dp0
    @   set ps1="%TMP%\%~n0-%RANDOM%-%RANDOM%-%RANDOM%-%RANDOM%.ps1"
    @   copy /b /y "%~f0" %ps1% >nul
    @   powershell -NoProfile -ExecutionPolicy Bypass -File %ps1% %*
    @   del /f %ps1%
    @   goto :eof
    #>

    <# 
    .Synopsis 
        Sets the Screen Resolution of the primary monitor 
    .Description 
        Uses Pinvoke and ChangeDisplaySettings Win32API to make the change 
    .Example 
        Set-ScreenResolutionAndOrientation         
        
    URL: http://stackoverflow.com/questions/12644786/powershell-script-to-change-screen-orientation?answertab=active#tab-top
    CMD: powershell.exe -ExecutionPolicy Bypass -File "%~dp0ChangeOrientation.ps1"
#>

    $pinvokeCode = @" 

using System; 
using System.Runtime.InteropServices; 

namespace Resolution 
{ 

    [StructLayout(LayoutKind.Sequential)] 
    public struct DEVMODE 
    { 
       [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]
       public string dmDeviceName;

       public short  dmSpecVersion;
       public short  dmDriverVersion;
       public short  dmSize;
       public short  dmDriverExtra;
       public int    dmFields;
       public int    dmPositionX;
       public int    dmPositionY;
       public int    dmDisplayOrientation;
       public int    dmDisplayFixedOutput;
       public short  dmColor;
       public short  dmDuplex;
       public short  dmYResolution;
       public short  dmTTOption;
       public short  dmCollate;

       [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
       public string dmFormName;

       public short  dmLogPixels;
       public short  dmBitsPerPel;
       public int    dmPelsWidth;
       public int    dmPelsHeight;
       public int    dmDisplayFlags;
       public int    dmDisplayFrequency;
       public int    dmICMMethod;
       public int    dmICMIntent;
       public int    dmMediaType;
       public int    dmDitherType;
       public int    dmReserved1;
       public int    dmReserved2;
       public int    dmPanningWidth;
       public int    dmPanningHeight;
    }; 

    class NativeMethods 
    { 
        [DllImport("user32.dll")] 
        public static extern int EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode); 
        [DllImport("user32.dll")] 
        public static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags); 

        public const int ENUM_CURRENT_SETTINGS = -1; 
        public const int CDS_UPDATEREGISTRY = 0x01; 
        public const int CDS_TEST = 0x02; 
        public const int DISP_CHANGE_SUCCESSFUL = 0; 
        public const int DISP_CHANGE_RESTART = 1; 
        public const int DISP_CHANGE_FAILED = -1;
        public const int DMDO_DEFAULT = 0;
        public const int DMDO_90 = 1;
        public const int DMDO_180 = 2;
        public const int DMDO_270 = 3;
    } 



    public class PrmaryScreenResolution 
    { 
        static public string ChangeResolution() 
        { 

            DEVMODE dm = GetDevMode(); 

            if (0 != NativeMethods.EnumDisplaySettings(null, NativeMethods.ENUM_CURRENT_SETTINGS, ref dm)) 
            {

                // swap width and height
                int temp = dm.dmPelsHeight;
                dm.dmPelsHeight = dm.dmPelsWidth;
                dm.dmPelsWidth = temp;

                // determine new orientation based on the current orientation
                switch(dm.dmDisplayOrientation)
                {
                    case NativeMethods.DMDO_DEFAULT:
                        //dm.dmDisplayOrientation = NativeMethods.DMDO_270;
                        //2016-10-25/EBP wrap counter clockwise
                        dm.dmDisplayOrientation = NativeMethods.DMDO_90;
                        break;
                    case NativeMethods.DMDO_270:
                        dm.dmDisplayOrientation = NativeMethods.DMDO_180;
                        break;
                    case NativeMethods.DMDO_180:
                        dm.dmDisplayOrientation = NativeMethods.DMDO_90;
                        break;
                    case NativeMethods.DMDO_90:
                        dm.dmDisplayOrientation = NativeMethods.DMDO_DEFAULT;
                        break;
                    default:
                        // unknown orientation value
                        // add exception handling here
                        break;
                }


                int iRet = NativeMethods.ChangeDisplaySettings(ref dm, NativeMethods.CDS_TEST); 

                if (iRet == NativeMethods.DISP_CHANGE_FAILED) 
                { 
                    return "Unable To Process Your Request. Sorry For This Inconvenience."; 
                } 
                else 
                { 
                    iRet = NativeMethods.ChangeDisplaySettings(ref dm, NativeMethods.CDS_UPDATEREGISTRY); 
                    switch (iRet) 
                    { 
                        case NativeMethods.DISP_CHANGE_SUCCESSFUL: 
                            { 
                                return "Success"; 
                            } 
                        case NativeMethods.DISP_CHANGE_RESTART: 
                            { 
                                return "You Need To Reboot For The Change To Happen.\n If You Feel Any Problem After Rebooting Your Machine\nThen Try To Change Resolution In Safe Mode."; 
                            } 
                        default: 
                            { 
                                return "Failed To Change The Resolution"; 
                            } 
                    } 

                } 


            } 
            else 
            { 
                return "Failed To Change The Resolution."; 
            } 
        } 

        private static DEVMODE GetDevMode() 
        { 
            DEVMODE dm = new DEVMODE(); 
            dm.dmDeviceName = new String(new char[32]); 
            dm.dmFormName = new String(new char[32]); 
            dm.dmSize = (short)Marshal.SizeOf(dm); 
            return dm; 
        } 
    } 
} 

"@ 

    Add-Type $pinvokeCode -ErrorAction SilentlyContinue 
    [Resolution.PrmaryScreenResolution]::ChangeResolution() 
}


# Set-ScreenResolutionAndOrientation

function Set-PythonPipSource
{
    param (
        $mirror = 'https://pypi.tuna.tsinghua.edu.cn/simple'
    )
    pip config set global.index-url $mirror
}
function Get-MsysSourceScript
{
    <# 
    .SYNOPSIS
    获取更新msys2下pacman命令的换源脚本,默认换为清华源
    
    .NOTES
    将输出的脚本复制到剪切板,然后粘贴到msys2命令行窗口中执行
    #>
    param (

    )
    $script = { sed -i 's#https\?://mirror.msys2.org/#https://mirrors.tuna.tsinghua.edu.cn/msys2/#g' /etc/pacman.d/mirrorlist* }
    
    return $script.ToString()
}
function Set-CondaSource
{
    param (
        
    )
    
    #备份旧配置,如果有的话
    if (Test-Path "$userprofile\.condarc")
    {
        Copy-Item "$userprofile\.condarc" "$userprofile\.condarc.bak"
    }
    #写入内容
    @'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  msys2: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  bioconda: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  menpo: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch-lts: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  simpleitk: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  deepmodeling: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/
'@ >"$userprofile\.condarc"

    Write-Host 'Check your conda config...'
    conda config --show-sources
}
function Deploy-WindowsActivation
{
    # Invoke-RestMethod https://massgrave.dev/get | Invoke-Expression

    Invoke-RestMethod https://get.activated.win | Invoke-Expression
}
function Get-BeijingTime
{
    # 获取北京时间的函数
    # 通过API获取北京时间
    $url = 'http://worldtimeapi.org/api/timezone/Asia/Shanghai'
    $response = Invoke-RestMethod -Uri $url
    $beijingTime = [DateTime]$response.datetime
    return $beijingTime
}
function Enable-WindowsUpdateByDelay
{
    $reg = "$PsScriptRoot\..\..\registry\windows-updates-unpause.reg" | Resolve-Path
    Write-Host $reg
    & $reg
}
function Disable-WindowsUpdateByDelay
{
    $reg = "$PsScriptRoot\..\..\registry\windows-updates-pause.reg" | Resolve-Path
    Write-Host $reg
    & $reg
}
function Get-BootEntries
{
    
    chcp 437 >$null; cmd /c bcdedit | Write-Output | Out-String -OutVariable bootEntries *> $null


    # 使用正则表达式提取identifier和description
    $regex = "identifier\s+(\{[^\}]+\})|\bdevice\s+(.+)|description\s+(.+)"
    $ms = [regex]::Matches($bootEntries, $regex)
    # $matches


    $entries = @()
    $ids = @()
    $devices = @()
    $descriptions = @()
    foreach ($match in $ms)
    {
        $identifier = $match.Groups[1].Value
        $device = $match.Groups[2].Value
        $description = $match.Groups[3].Value

        if ($identifier  )
        {
            $ids += $identifier
        }
        if ($device)
        {
            $devices += $device
        }
        if ( $description )
        {
            $descriptions += $description
        }

    }
    foreach ($id in $ids)
    {
        $entries += [PSCustomObject]@{
            Identifier  = $id
            device      = $devices[$ids.IndexOf($id)]
            Description = $descriptions[$ids.IndexOf($id)]
        }
    }

    Write-Output $entries
}
function Get-WindowsVersionInfoOnDrive
{
    <# 
    .SYNOPSIS
    查询安装在指定盘符的Windows版本信息,默认查询D盘上的windows系统版本

    .EXAMPLE
    $driver = "D"
    $versionInfo = Get-WindowsVersionInfo -Driver $driver

    # 输出版本信息
    $versionInfo | Format-List

    #>
    param (
        # [Parameter(Mandatory = $true)]
        [string]$Driver = "D"
    )

    # 确保盘符格式正确
    if (-not $Driver.EndsWith(":"))
    {
        $Driver += ":"
    }

    try
    {
        # 加载指定盘符的注册表
        reg load HKLM\TempHive "$Driver\Windows\System32\config\SOFTWARE" | Out-Null

        # 获取Windows版本信息
        $osInfo = Get-ItemProperty -Path 'HKLM:\TempHive\Microsoft\Windows NT\CurrentVersion'

        # 创建一个对象保存版本信息
        $versionInfo = [PSCustomObject]@{
            WindowsVersion = $osInfo.ProductName
            OSVersion      = $osInfo.DisplayVersion
            BuildNumber    = $osInfo.CurrentBuild
            UBR            = $osInfo.UBR
            LUVersion      = $osInfo.ReleaseId
        }

        # 卸载注册表
        reg unload HKLM\TempHive | Out-Null

        # 返回版本信息
        return $versionInfo
    }
    catch
    {
        Write-Error "无法加载注册表或获取信息，请确保指定的盘符是有效的Windows安装盘符。"
    }
}

function rebootToOS
{
    Add-Type -AssemblyName PresentationFramework
    $bootEntries = Get-BootEntries
    $bootEntries = $bootEntries | ForEach-Object {
        [PSCustomObject]@{
            Identifier  = $_.Identifier
            Description = $_.Description + $_.device + "`n$($_.Identifier)" 
        } 
    }

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Reboot Utility (by @Cxxu)" Height="600" Width="450" WindowStartupLocation="CenterScreen"
        Background="White" AllowsTransparency="False" WindowStyle="SingleBorderWindow">
    <Grid>
        <Border Background="White" CornerRadius="10" BorderBrush="Gray" BorderThickness="1" Padding="10">
            <StackPanel>
                <TextBlock Text="Select a system to reboot into (从列表中选择重启项目):" Margin="10" FontWeight="Bold" FontSize="14"/>
                <ListBox Name="BootEntryList" Margin="10" Background="LightBlue" BorderThickness="0">
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <Border Background="LightGray" CornerRadius="10" Padding="5" Margin="5">
                                <TextBlock Text="{Binding Description}" Margin="5,0,0,0"/>
                            </Border>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>
                <Button Name="RebootButton" Content="Reboot | 点击重启" Margin="10" HorizontalAlignment="Center" Width="140" Background="#FF2A2A" Foreground="White" FontWeight="Bold" Cursor="Hand">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Background" Value="#FF2A2A"/>
                            <Setter Property="Foreground" Value="White"/>
                            <Setter Property="FontWeight" Value="Bold"/>
                            <Setter Property="Cursor" Value="Hand"/>
                            <Style.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="#FF5555"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </Button.Style>
                </Button>
                <Button Name="RebootToBios" Content="Restart to BIOS" Width="200" Height="30" Margin="10" HorizontalAlignment="Center" Background="#FF2A2A" Foreground="White" FontWeight="Bold" Cursor="Hand">
                    <Button.Style>
                        <Style TargetType="Button">
                            <Setter Property="Background" Value="#FF2A2A"/>
                            <Setter Property="Foreground" Value="White"/>
                            <Setter Property="FontWeight" Value="Bold"/>
                            <Setter Property="Cursor" Value="Hand"/>
                            <Style.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter Property="Background" Value="#FF5555"/>
                                </Trigger>
                            </Style.Triggers>
                        </Style>
                    </Button.Style>
                </Button>
                <TextBlock HorizontalAlignment="Center" Margin="10">
                    <Hyperlink Name="iReboot">iReboot</Hyperlink>
                </TextBlock>
                <TextBlock HorizontalAlignment="Center" Margin="10">
                    <Hyperlink Name="EasyBCD">EasyBCD</Hyperlink>
                </TextBlock>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@

    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # 重启到指定系统获取控件
    $listBox = $window.FindName("BootEntryList")
    $button = $window.FindName("RebootButton")
    # 其他控件
    $RebootToBios = $window.FindName("RebootToBios")
    $iReboot = $window.FindName("iReboot")
    $EasyBCD = $window.FindName("EasyBCD")

    # 填充ListBox
    $listBox.ItemsSource = $bootEntries

    # 定义重启按钮点击事件
    $button.Add_Click({
            $selectedEntry = $listBox.SelectedItem
            if ($null -ne $selectedEntry)
            {
                $identifier = $selectedEntry.Identifier
                $confirmReboot = [System.Windows.MessageBox]::Show(
                    "Are you sure you want to reboot to $($selectedEntry.Description)?", 
                    "Confirm Reboot", 
                    [System.Windows.MessageBoxButton]::YesNo, 
                    [System.Windows.MessageBoxImage]::Warning
                )
                if ($confirmReboot -eq [System.Windows.MessageBoxResult]::Yes)
                {
                    Write-Output "Rebooting to: $($selectedEntry.Description) with Identifier $identifier"
                    cmd /c bcdedit /bootsequence $identifier
                    Write-Host "Rebooting to $($selectedEntry.Description) after 3 seconds! (close the shell to stop/cancel it)"
                    Start-Sleep 3
                    shutdown.exe /r /t 0
                }
            }
            else
            {
                [System.Windows.MessageBox]::Show("Please select an entry to reboot into.", "No Entry Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            }
        })

    # 定义关机按钮点击事件
    $RebootToBios.Add_Click({
            $confirmShutdown = [System.Windows.MessageBox]::Show(
                "Are you sure you want to shutdown and restart?", 
                "Confirm Shutdown", 
                [System.Windows.MessageBoxButton]::YesNo, 
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($confirmShutdown -eq [System.Windows.MessageBoxResult]::Yes)
            {
                Write-Output "Executing shutdown command"
                Start-Process "shutdown.exe" -ArgumentList "/fw", "/r", "/t", "0"
            }
        })

    # 定义链接点击事件
    $iReboot.Add_Click({
            Start-Process "https://neosmart.net/iReboot/?utm_source=EasyBCD&utm_medium=software&utm_campaign=EasyBCD iReboot"
        })

    $EasyBCD.Add_Click({
            Start-Process "https://neosmart.net/EasyBCD/"
        })

    # 显示窗口
    $window.ShowDialog()
}


function Set-TaskBarTime
{
    <# 
    .SYNOPSIS
    sShortTime：控制系统中短时间,不显示秒（例如 HH:mm）的显示格式，HH 表示24小时制（H 单独使用则表示12小时制）。
    sTimeFormat：控制系统的完整时间格式(长时间格式,相比于短时间格式增加了秒数显示)
    .EXAMPLE
    #设置为12小时制,且小时为个位数时不补0
     Set-TaskBarTime -TimeFormat h:mm:ss 
     .EXAMPLE
    #设置为24小时制，且小时为个位数时不补0
     Set-TaskBarTime -TimeFormat H:mm:ss
     .EXAMPLE
    #设置为24小时制，且小时为个位数时补0
     Set-TaskBarTime -TimeFormat HH:mm:ss
    #>
    param (
        # $ShortTime = 'HH:mm',
        $TimeFormat = 'H:mm:ss'
    )
    Set-ItemProperty -Path 'HKCU:\Control Panel\International' -Name 'sShortTime' -Value $ShortTime
    Set-ItemProperty -Path 'HKCU:\Control Panel\International' -Name 'sTimeFormat' -Value $TimeFormat

    
}
function Sync-SystemTime
{
    <#
    .SYNOPSIS
        同步系统时间到 time.windows.com NTP 服务器。
    .DESCRIPTION
        使用 Windows 内置的 w32tm 命令同步本地系统时间到 time.windows.com。
        同步完成后，显示当前系统时间。
        w32tm 是 Windows 中用于管理和配置时间同步的命令行工具。以下是一些常用的 w32tm 命令和参数介绍：

        常用命令
        w32tm /query /status
        显示当前时间服务的状态，包括同步源、偏差等信息。
        w32tm /resync
        强制系统与配置的时间源重新同步。
        w32tm /config /manualpeerlist:"<peers>" /syncfromflags:manual /reliable:YES /update
        配置手动指定的 NTP 服务器列表（如 time.windows.com），并更新设置。
        w32tm /query /peers
        列出当前配置的时间源（NTP 服务器）。
        w32tm /stripchart /computer:<target> /dataonly
        显示与目标计算机之间的时差，类似 ping 的方式。
        注意事项
        运行某些命令可能需要管理员权限。
        确保你的网络设置允许访问 NTP 服务器。
        适用于 Windows Server 和 Windows 客户端版本。
    .NOTES
        需要管理员权限运行。
    .EXAMPLE
    # 调用函数
    # Sync-SystemTime
    #>
    try
    {
        # 配置 NTP 服务器
        w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:YES /update
        
        # 同步时间
        w32tm /resync

        # 显示当前时间
        $currentTime = Get-Date
        Write-Output "当前系统时间: $currentTime"
    }
    catch
    {
        Write-Error "无法同步时间: $_"
    }
}

function Update-SystemTime
{
    # 获取北京时间的函数
   

    # 显示当前北京时间
    $beijingTime = Get-BeijingTime
    Write-Output "当前北京时间: $beijingTime"

    # 设置本地时间为北京时间（需要管理员权限）
    # Set-Date -Date $beijingTime
}
function Update-DataJsonLastWriteTime
{
    param (
        $DataJson = $DataJson
    )
    Update-Json -Key LastWriteTime -Value (Get-Date) -DataJson $DataJson
}
function Test-DirectoryEmpty
{
    <# 
    .SYNOPSIS
    判断一个目录是否为空目录
    .PARAMETER directoryPath
    要检查的目录路径
    .PARAMETER CheckNoFile
    如果为true,递归子目录检查是否有文件
    #>
    param (
        [string]$directoryPath,
        [switch]$CheckNoFile
    )

    if (-Not (Test-Path -Path $directoryPath))
    {
        throw "The directory path '$directoryPath' does not exist."
    }
    if ($CheckNoFile)
    {

        $itemCount = (Get-ChildItem -Path $directoryPath -File -Recurse | Measure-Object).Count
    }
    else
    {
        $items = Get-ChildItem -Path $directoryPath
        $itemCount = $items.count
    }
    return $itemCount -eq 0
}
function Update-Json
{
    <# 
    .SYNOPSIS
    提供创建/修改/删除JSON文件中的配置项目的功能
    #>
    [CmdletBinding()]
    param (
        [string]$Key,
        [string]$Value,
        [switch]$Remove,
        [string][Alias('DataJson')]$Path = $DataJson
    )
    
    # 如果配置文件不存在，创建一个空的JSON文件
    if (-Not (Test-Path $Path))
    {
        Write-Verbose "Configuration file '$Path' does not exist. Creating a new one."
        $emptyConfig = @{}
        $emptyConfig | ConvertTo-Json -Depth 32 | Set-Content $Path
    }

    # 读取配置文件
    $config = Get-Content $Path | ConvertFrom-Json

    if ($Remove)
    {
        if ($config.PSObject.Properties[$Key])
        {
            $config.PSObject.Properties.Remove($Key)
            Write-Verbose "Removed '$Key' from '$Path'"
        }
        else
        {
            Write-Verbose "Key '$Key' does not exist in '$Path'"
        }
    }
    else
    {
        # 检查键是否存在，并动态添加新键
        if (-Not $config.PSObject.Properties[$Key])
        {
            $config | Add-Member -MemberType NoteProperty -Name $Key -Value $Value
        }
        else
        {
            $config.$Key = $Value
        }
        Write-Verbose "Updated '$Key' to '$Value' in '$Path'"
    }

    # 保存配置文件
    $config | ConvertTo-Json -Depth 32 | Set-Content $Path
}

function Convert-MarkdownToHtml
{
    <#
    .SYNOPSIS
    将Markdown文件转换为HTML文件。

    .DESCRIPTION
    这个函数使用PowerShell内置的ConvertFrom-Markdown cmdlet将指定的Markdown文件转换为HTML文件。
    它可以处理单个文件或整个目录中的所有Markdown文件。

    .PARAMETER Path
    指定要转换的Markdown文件的路径或包含Markdown文件的目录路径。

    .PARAMETER OutputDirectory
    指定生成的HTML文件的输出目录。如果不指定，将在原始文件的同一位置创建HTML文件。

    .PARAMETER Recurse
    如果指定，将递归处理子目录中的Markdown文件。

    .EXAMPLE
    Convert-MarkdownToHtml -Path "C:\Documents\sample.md"
    将单个Markdown文件转换为HTML文件。

    .EXAMPLE
    Convert-MarkdownToHtml -Path "C:\Documents" -OutputDirectory "C:\Output" -Recurse
    将指定目录及其子目录中的所有Markdown文件转换为HTML文件，并将输出保存到指定目录。

    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $false)]
        [switch]$Recurse
    )

    begin
    {
        function Convert-SingleFile
        {
            param (
                [string]$FilePath,
                [string]$OutputDir
            )

            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
            $outputPath = if ($OutputDir)
            {
                Join-Path $OutputDir "$fileName.html"
            }
            else
            {
                [System.IO.Path]::ChangeExtension($FilePath, 'html')
            }

            try
            {
                $html = ConvertFrom-Markdown -Path $FilePath | Select-Object -ExpandProperty Html
                $html | Out-File -FilePath $outputPath -Encoding utf8
                Write-Verbose "Successfully converted $FilePath to $outputPath"
            }
            catch
            {
                Write-Error "Failed to convert $FilePath. Error: $_"
            }
        }
    }

    process
    {
        if (Test-Path $Path -PathType Leaf)
        {
            # 单个文件
            Convert-SingleFile -FilePath $Path -OutputDir $OutputDirectory
        }
        elseif (Test-Path $Path -PathType Container)
        {
            # 目录
            $mdFiles = Get-ChildItem -Path $Path -Filter '*.md' -Recurse:$Recurse
            foreach ($file in $mdFiles)
            {
                Convert-SingleFile -FilePath $file.FullName -OutputDir $OutputDirectory
            }
        }
        else
        {
            Write-Error "The specified path does not exist: $Path"
        }
    }
}
function Measure-AlphabeticChars
{

    <#
    .SYNOPSIS
        Counts the number of alphabetic characters in a given string or array of strings.

    .DESCRIPTION
        This function takes a string or an array of strings and counts all the alphabetic characters (A-Z, a-z) in each string.
        It supports both pipeline input and direct parameter input.

    .PARAMETER InputString
        The string or array of strings in which to count the alphabetic characters.
    #>
    <# 
.EXAMPLE
    Measure-AlphabeticChars -InputString "Hello, World!"
    Output: 10

.EXAMPLE
    "Hello, World!" | Measure-AlphabeticChars
    Output: 10

.EXAMPLE
    Measure-AlphabeticChars -InputString @("Hello, World!", "PowerShell 7")
    Output: 10
            10

.EXAMPLE
    @("Hello, World!", "PowerShell 7") | Measure-AlphabeticChars
    Output: 10
            10

.NOTES
    Author: Your Name
    Date: Today's date
    #>


    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$InputString
    )

    process
    {
        foreach ($str in $InputString)
        {
            # Use regex to find all alphabetic characters and count them
            $ms = [regex]::Matches($str, '[a-zA-Z]')
            $ms.Count
        }
    }
}
function Get-Json
{
    <#
.SYNOPSIS
    Reads a specific property from a JSON string or JSON file. If no property is specified, returns the entire JSON object.

.DESCRIPTION
    This function reads a JSON string or JSON file and extracts the value of a specified property. If no property is specified, it returns the entire JSON object.

.PARAMETER JsonInput
    The JSON string or the path to the JSON file.

.PARAMETER Property
    The path to the property whose value needs to be extracted, using dot notation for nested properties.
.EXAMPLE
从多行字符串(符合json格式)中提取JSON属性
#从文件中读取并通过管道符传递时需要使用-Raw选项,否则无法解析json
PS> cat "$home/Data.json" -Raw |Get-Json

ConnectionName IpPrompt
-------- --------
         xxx
 
PS> cat $DataJson -Raw |Get-Json -property IpPrompt
xxx

.EXAMPLE
    Get-Json -JsonInput '{"name": "John", "age": 30}' -Property "name"

    This command extracts the value of the "name" property from the provided JSON string.

.EXAMPLE
    Get-Json -JsonInput "data.json" -Property "user.address.city"

    This command extracts the value of the nested "city" property from the provided JSON file.

.EXAMPLE
    Get-Json -JsonInput '{"name": "John", "age": 30}'

    This command returns the entire JSON object.

.NOTES
    Author: Your Name
    Date: YYYY-MM-DD
#>

    [CmdletBinding()]
    param (
        [Parameter(   ValueFromPipeline = $true)]
        [Alias('DataJson', 'JsonFile', 'Path', 'File')]$JsonInput = $DataJson,

        [Parameter(Position = 0)]
        [string][Alias('Property')]$Key
    )

    # 读取JSON内容

    $jsonContent = if (Test-Path $JsonInput)
    {
        Get-Content -Path $JsonInput -Raw | ConvertFrom-Json
    }
    else
    {
        $JsonInput | ConvertFrom-Json
    }
    # Write-Host $jsonContent

     

    # 如果没有指定属性，则返回整个JSON对象
    if (-not $Key)
    {
        return $jsonContent
    }

    # 提取指定属性的值
    try
    {
        # TODO
        $KeyValue = $jsonContent | Select-Object -ExpandProperty $Key
        # Write-Verbose $KeyValue
        return $KeyValue
    }
    catch
    {
        Write-Error "Failed to extract the property value for '$Key'."
    }
}


function Get-JsonItemCompleter
{
    param(
        $commandName, 
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameters
        # $cursorPosition
    )
    if ($fakeBoundParameters.containskey('JsonInput'))
    {
        $Json = $fakeBoundParameters['JsonInput']
    
    }
    else
    {
        $Json = $DataJson
    }
    $res = Get-Content $Json | ConvertFrom-Json
    $Names = $res | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    $Names = $Names | Where-Object { $_ -like "$wordToComplete*" }
    foreach ($name in $Names)
    {
        $value = $res | Select-Object $name | Format-List | Out-String
        # $value = Get-Json -JsonInput $Json $name |Out-String
        if (! $value)
        {
            $value = 'Error:Nested property expand failed'
        }

        [System.Management.Automation.CompletionResult]::new($name, $name, 'ParameterValue', $value.ToString())
    }
}

Register-ArgumentCompleter -CommandName Get-Json -ParameterName Key -ScriptBlock ${function:Get-JsonItemCompleter}
