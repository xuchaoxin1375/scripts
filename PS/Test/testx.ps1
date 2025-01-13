function Get-CharacterEncoding
{

    <# 
    .SYNOPSIS
    显示字符串的字符编码信息，包括 Unicode 编码、UTF8 编码、ASCII 编码和 HTML 实体编码
    .DESCRIPTION
    利用此函数来分析给定字符串中的各个字符的编码，尤其是空白字符，在执行空白字符替换时，可以排查出不可见字符替换不掉的问题
    .EXAMPLE
    PS> Get-CharacterEncoding -InputString "  0.46" | Format-Table -AutoSize

    Character UnicodeCode UTF8Encoding AsciiCode HtmlEntity
    --------- ----------- ------------ --------- ----------
            U+0020      0x20                32     &nbsp;
              U+00A0      0xC2 0xA0          N/A    &nbsp;
            0 U+0030      0x30                48     0
            . U+002E      0x2E                46     .
            4 U+0034      0x34                52     4
            6 U+0036      0x36                54     6
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

        # 计算 HTML 实体编码
        $htmlEntity = if ($unicode -ge 128) { "&#$unicode;" } else { $char }

        [PSCustomObject]@{
            Character    = $char
            UnicodeCode  = "U+{0:X4}" -f $unicode
            UTF8Encoding = ($utf8Hex -join " ")
            AsciiCode    = $ascii
            HtmlEntity   = $htmlEntity
        }
    }
}
