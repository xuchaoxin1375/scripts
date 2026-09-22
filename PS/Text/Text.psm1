<#
Text 模块:文本/编码/markdown/格式化相关(从 Tools.psm1 迁入)。
#>

function Get-LineDataFromMultilineString
{
    <# 
    .SYNOPSIS
    将多行字符串按行分割，并返回数组
    对于数组输入也可以处理
    .EXAMPLE
    Get-LineDataFromMultilineString -Data @"
    line1
    line2
    "@

    #>
    [cmdletbinding(DefaultParameterSetName = "Trim")]
    param (
        $Data,
        [parameter(ParameterSetName = "Trim")]
        $TrimPattern = "",
        [parameter(ParameterSetName = "NoTrim")]
        [switch]$KeepLine
    )
    # 统一成字符串处理
    $Data = @($Data) -join "`n"

    $lines = $Data -split "`r?`n|," 
    if(!$KeepLine)
    {
        $lines = $lines | ForEach-Object { $_.trim($TrimPattern) }
    }
    return $lines
    
}

function Get-DictView
{
    <# 
    .SYNOPSIS
    以友好的方式查看字典的取值或字典数组中每个字典的取值
    .EXAMPLE
    $array = @(
        @{ Name = "Alice"; Age = 25; City = "New York" },
        @{ Name = "Bob"; Age = 30; City = "Los Angeles" },
        @{ Name = "Charlie"; Age = 35; City = "Chicago" }
    )

    Get-DictView -Dicts $array

    #>
    param (
        [alias("Dict")]$Dicts
    )
    Write-Host $Dicts
    # $Dicts.Gettype()
    # $Dicts.Count
    # $Dicts | Get-TypeCxxu
    $i = 1
    foreach ($dict in @($Dicts))
    {
        Write-Host "----- Dictionary$($i++) -----"
        # Write-Output $dict
        # 遍历哈希表的键值对
        foreach ($key in $dict.Keys)
        {
            Write-Host "$key : $($dict[$key])"
        }
        Write-Host "----- End of Dictionary$($i-1) -----`n"
    }
}

function Remove-TitleOrderFromMarkdownTitle
{
    <# 
    .SYNOPSIS
    移除Markdown标题中的序号部分

    ## 一、...
    ### 1.[x] ...

    #>
    [CmdletBinding()]
    param(
        $Path,
        $CodeBlockLang = "Bash",
        [switch]$RemoveEmptyLines 
    )
    $Content = Get-Content -Path $Path -Raw
    $CRLFS = "(\r?\n)*"
    # $CRLF_PLUS = "(\r?\n)+"
    $LF = "`n"
    if($CodeBlockLang)
    {
        $p1 = ("$CodeBlockLang" + $CRLFS + '(\s*)' + '```' + "\s*")
        $p2 = ('```' + $CodeBlockLang.ToLower() + $LF)
        # Write-Verbose "p1:[$p1],p2:[$p2]"
        Write-Verbose "'$p1','$p2'"
        $content = $content -replace $p1 , $p2
    }
    # $content | ForEach-Object {
    #     $_ -replace '(#+ )(\d{1,2}\.\d{1,2}|\S、)', '$1' -split "`r?`n" 
    # } 

    $content = $content -replace '(#+ )(\d{1,2}\.\d{0,2}|\S、)', '$1' 
    # $content | Out-File $Path -Encoding UTF8
    if ($RemoveEmptyLines)
    {
        # $Content = $Content -split $CRLF_PLUS | Where-Object { $_.Trim() } 
        
        $content = $content -replace '[\s\n]*\n', "`n"
    }
    $content | Out-File $Path -Encoding UTF8
    return $content
}

function Rename-FileName
{
    [CmdletBinding()]
    param(
        $Path,
        [alias('RegularExpression')]$Pattern,
        [alias('Substitute')]$Replacement
    )
    
    Get-ChildItem $Path | ForEach-Object { 
        # 无后缀(扩展名)的文件基名
        # $leafBase = (Split-Path -LeafBase $_).ToString()
        # 包含扩展名的文件名
        $name = $_.Name
        $newName = $name -replace $Pattern, $Replacement
        Rename-Item -Path $_ -NewName $newName -Verbose 
    }

}

function Format-FileSize
{
    param([long]$Size)
    
    if ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size / 1GB) }
    if ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size / 1MB) }
    if ($Size -gt 1KB) { return "{0:N2} KB" -f ($Size / 1KB) }
    return "$Size B"
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

function Show-UnicodeConverterWindow
{
    <#
    .SYNOPSIS
        显示一个图形界面窗口，用于Unicode、HTML和转义字符的编码和解码。

    .DESCRIPTION
        该函数创建一个Windows Forms图形界面，允许用户输入文本并将其编码或解码为不同的格式，
        包括Unicode (\uXXXX)、HTML实体 (&#xxxx;) 和常见的转义字符序列。

    .PARAMETER None
        此函数没有参数。

    .EXAMPLE
        Show-UnicodeConverterWindow
        打开Unicode转换器窗口。

    .NOTES
        功能特性:
        - 支持多种编码/解码模式:
          * 自动检测 (Auto Detect)
          * JavaScript Unicode (\uXXXX)
          * HTML实体 (&#xxxx; 和 &#xXXXX;)
          * 混合模式 (JS+HTML)
          * 常见转义字符 (\n, \t, \r, \", \', \\ 等)
        - 实时预览转换结果
        - 支持窗口大小调整
        - 只读输出区域，防止意外修改

    .LINK
        https://en.wikipedia.org/wiki/List_of_XML_and_HTML_character_entity_references
        https://en.wikipedia.org/wiki/Unicode

    .INPUTS
        None - 此函数不接受管道输入。

    .OUTPUTS
        None - 此函数不返回值，而是显示一个交互式窗口。
    #>
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Unicode / HTML / 转义字符 编解码"
    $form.Size = New-Object System.Drawing.Size(880, 640)
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = New-Object System.Drawing.Size(620, 470)
    $form.AutoScaleMode = "Font"

    # 模式标签
    $labelMode = New-Object System.Windows.Forms.Label
    $labelMode.Text = "模式:"
    $labelMode.Location = New-Object System.Drawing.Point(20, 20)
    $labelMode.Size = New-Object System.Drawing.Size(60, 25)

    # 模式下拉框（新增 Mix 和 Common）
    $comboBoxMode = New-Object System.Windows.Forms.ComboBox
    $comboBoxMode.Location = New-Object System.Drawing.Point(80, 20)
    $comboBoxMode.Size = New-Object System.Drawing.Size(200, 25)
    $comboBoxMode.DropDownStyle = "DropDownList"
    $comboBoxMode.Items.AddRange(@(
            "Auto (Detect)",
            "JS (\uXXXX)",
            "HTML",
            "Mix (JS+HTML)",
            "Common (\n, \t, etc.)"
        ))
    $comboBoxMode.SelectedIndex = 0  # 默认 Auto

    # 输入区域
    $labelInput = New-Object System.Windows.Forms.Label
    $labelInput.Text = "输入文本:"
    $labelInput.Location = New-Object System.Drawing.Point(20, 60)
    $labelInput.Size = New-Object System.Drawing.Size(100, 20)

    $textBoxInput = New-Object System.Windows.Forms.TextBox
    $textBoxInput.Multiline = $true
    $textBoxInput.ScrollBars = "Vertical"
    $textBoxInput.Font = New-Object System.Drawing.Font("Consolas", 10)
    $textBoxInput.Location = New-Object System.Drawing.Point(20, 85)
    $textBoxInput.Size = New-Object System.Drawing.Size(820, 140)
    $textBoxInput.Anchor = "Top, Left, Right"

    # 按钮
    $buttonDecode = New-Object System.Windows.Forms.Button
    $buttonDecode.Text = "解码"
    $buttonDecode.Location = New-Object System.Drawing.Point(290, 240)
    $buttonDecode.Size = New-Object System.Drawing.Size(100, 32)

    $buttonEncode = New-Object System.Windows.Forms.Button
    $buttonEncode.Text = "编码"
    $buttonEncode.Location = New-Object System.Drawing.Point(470, 240)
    $buttonEncode.Size = New-Object System.Drawing.Size(100, 32)

    # 输出区域
    $labelOutput = New-Object System.Windows.Forms.Label
    $labelOutput.Text = "输出结果:"
    $labelOutput.Location = New-Object System.Drawing.Point(20, 290)
    $labelOutput.Size = New-Object System.Drawing.Size(100, 20)

    $textBoxOutput = New-Object System.Windows.Forms.TextBox
    $textBoxOutput.Multiline = $true
    $textBoxOutput.ReadOnly = $true
    $textBoxOutput.ScrollBars = "Vertical"
    $textBoxOutput.Font = New-Object System.Drawing.Font("Consolas", 10)
    $textBoxOutput.BackColor = [System.Drawing.Color]::WhiteSmoke
    $textBoxOutput.Location = New-Object System.Drawing.Point(20, 315)
    $textBoxOutput.Size = New-Object System.Drawing.Size(820, 170)
    $textBoxOutput.Anchor = "Top, Left, Right, Bottom"

    # ✅ 修复 Resize 事件
    $form.add_Resize({
            $w = $form.ClientSize.Width
            $h = $form.ClientSize.Height
            $textBoxInput.Width = $w - 40
            $textBoxOutput.Width = $w - 40
            $textBoxOutput.Height = $h - 340
            $centerX = ($w - 220) / 2
            $buttonDecode.Left = $centerX - 55
            $buttonEncode.Left = $centerX + 55
        })

    # ========== 核心解码函数 ==========
    function Get-DecodeText
    {
        param([string]$Text, [string]$Mode)

        if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

        switch ($Mode)
        {
            "JS (\uXXXX)"
            {
                $result = $Text
                while ($result -match '\\u([0-9a-fA-F]{4})')
                {
                    $char = [char][Convert]::ToInt32($matches[1], 16)
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                return $result
            }

            "HTML"
            {
                $result = $Text
                # 先处理十六进制
                while ($result -match '&#x([0-9a-fA-F]+);')
                {
                    $char = [char][Convert]::ToInt32($matches[1], 16)
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                # 再处理十进制
                while ($result -match '&#(\d+);')
                {
                    $char = [char][int]$matches[1]
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                return $result
            }

            "Mix (JS+HTML)"
            {
                $result = $Text
                # 先解 JS
                while ($result -match '\\u([0-9a-fA-F]{4})')
                {
                    $char = [char][Convert]::ToInt32($matches[1], 16)
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                # 再解 HTML（十进制和十六进制）
                while ($result -match '&#x([0-9a-fA-F]+);')
                {
                    $char = [char][Convert]::ToInt32($matches[1], 16)
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                while ($result -match '&#(\d+);')
                {
                    $char = [char][int]$matches[1]
                    $result = $result -replace [regex]::Escape($matches[0]), $char
                }
                return $result
            }

            "Common (\n, \t, etc.)"
            {
                $result = $Text
                # 注意：必须按顺序，避免干扰（如先处理 \\）
                $result = $result -replace '\\\\', '\'        # \\ → \
                $result = $result -replace '\\"', '"'         # \" → "
                $result = $result -replace "\\'", "'"         # \' → '
                $result = $result -replace '\\n', "`n"        # \n → 换行
                $result = $result -replace '\\r', "`r"        # \r → 回车
                $result = $result -replace '\\t', "`t"        # \t → 制表符
                $result = $result -replace '\\b', "`b"        # \b → 退格
                $result = $result -replace '\\f', "`f"        # \f → 换页
                return $result
            }

            default
            {
                # Auto 模式由调用方处理，此处不触发
                return $Text
            }
        }
    }

    # ========== 编码函数（仅 JS/HTML） ==========
    function Get-EncodeText
    {
        param([string]$Text, [string]$Mode)

        if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

        if ($Mode -eq "JS (\uXXXX)")
        {
            -join ($Text.ToCharArray() | ForEach-Object {
                    $code = [int]$_
                    if ($code -le 0xFFFF)
                    {
                        "\u{0:x4}" -f $code
                    }
                    else
                    {
                        $high = 0xD800 + (($code - 0x10000) -shr 10)
                        $low = 0xDC00 + (($code - 0x10000) -band 0x3FF)
                        "\u{0:x4}\u{1:x4}" -f $high, $low
                    }
                })
        }
        elseif ($Mode -eq "HTML")
        {
            -join ($Text.ToCharArray() | ForEach-Object { "&#$( [int]$_ );" })
        }
        else
        {
            throw "Unsupported encode mode: $Mode"
        }
    }

    # ========== Auto 检测 ==========
    function Get-EncodingMode
    {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

        $jsCount = ([regex]::Matches($Text, '\\u[0-9a-fA-F]{4}')).Count
        $htmlCount = ([regex]::Matches($Text, '&#x[0-9a-fA-F]+;|&#\d+;')).Count

        if ($jsCount -eq 0 -and $htmlCount -eq 0)
        {
            return $null
        }

        if ($jsCount -ge $htmlCount)
        {
            return "JS (\uXXXX)"
        }
        else
        {
            return "HTML"
        }
    }

    # ========== 按钮事件 ==========
    $buttonDecode.Add_Click({
            $inputText = $textBoxInput.Text
            if ([string]::IsNullOrWhiteSpace($inputText))
            {
                $textBoxOutput.Text = ""
                return
            }

            $mode = $comboBoxMode.SelectedItem

            if ($mode -eq "Auto (Detect)")
            {
                $detected = Get-EncodingMode -Text $inputText
                if ($null -eq $detected)
                {
                    $textBoxOutput.Text = $inputText
                }
                else
                {
                    $result = Get-DecodeText -Text $inputText -Mode $detected
                    $textBoxOutput.Text = $result
                }
            }
            else
            {
                $result = Get-DecodeText -Text $inputText -Mode $mode
                $textBoxOutput.Text = $result
            }
        })

    $buttonEncode.Add_Click({
            $inputText = $textBoxInput.Text
            if ([string]::IsNullOrWhiteSpace($inputText))
            {
                $textBoxOutput.Text = ""
                return
            }

            $mode = $comboBoxMode.SelectedItem

            if ($mode -notin @("JS (\uXXXX)", "HTML"))
            {
                [System.Windows.Forms.MessageBox]::Show(
                    "编码仅支持 'JS' 或 'HTML' 模式。",
                    "模式不支持",
                    "OK",
                    "Warning"
                )
                return
            }

            try
            {
                $result = Get-EncodeText -Text $inputText -Mode $mode
                $textBoxOutput.Text = $result
            }
            catch
            {
                $textBoxOutput.Text = "编码错误: $($_.Exception.Message)"
            }
        })

    # 添加控件
    $form.Controls.AddRange(@(
            $labelMode, $comboBoxMode,
            $labelInput, $textBoxInput,
            $buttonDecode, $buttonEncode,
            $labelOutput, $textBoxOutput
        ))

    [void]$form.ShowDialog()
}

function Get-CharCount
{
    <#
.SYNOPSIS
    计算字符串中指定字符出现的次数。

.DESCRIPTION
    Get-CharCount 函数通过比较原字符串和移除指定字符后的字符串长度差，来计算指定字符在输入字符串中出现的次数。

.PARAMETER InputString
    需要检查的输入字符串。

.PARAMETER Char
    需要计算出现次数的字符。

.EXAMPLE
    Get-CharCount -InputString "Hello World" -Char "l"
    返回值为 3，因为字符 "l" 在 "Hello World" 中出现了 3 次。

.EXAMPLE
    Get-CharCount -InputString "PowerShell" -Char "e"
    返回值为 2，因为字符 "e" 在 "PowerShell" 中出现了 2 次。

.INPUTS
    System.String
    可以通过管道传递字符串。

.OUTPUTS
    System.Int32
    返回指定字符在输入字符串中出现的次数。

.NOTES
    函数通过计算原字符串长度与移除指定字符后字符串长度的差值来确定字符出现次数。
#>
    param(
        [string]$InputString,
        [string]$Char
    )
    return $InputString.Length - ($InputString.Replace($Char, "")).Length
}

function regex_tk_tool
{
    $p = Resolve-Path "$PSScriptRoot/../../pythonScripts/regex_tk_tool.py"
    Write-Verbose "$p"
    python $p
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
