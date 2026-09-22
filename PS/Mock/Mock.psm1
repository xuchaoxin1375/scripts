# function Get-RandomFiles
# {
#     param(
        
#         $FileNumber = 3,
#         $contentLength = 10
#     )
#     # 指定文件夹路径和文件名

 

#     # 生成随机内容并写入文件
#     1..$contentLength | ForEach-Object { [char]([byte](Get-Random -Minimum 0 -Maximum 256)) } | Out-File -FilePath (Join-Path $folderPath $fileName) -Encoding ascii
# }

function Get-RandomString
{
    param(
        # [Parameter(Mandatory = $true)]
        [ValidateSet('Numeric', 'AlphaLower', 'AlphaUpper', 'AlphaAny', 'PrintableChars', 'PunctuationCn')]
        [string]$Mode = 'AlphaAny',
        # [Parameter(Mandatory = $true)]
        [int]$Length = 10
    )

    $charSet = @()
    # 字符集自包含(此前依赖会话预定义的 $numericChars 等外部变量,干净会话必空；有预定义则尊重调用方)
    if ($null -eq $numericChars) { $numericChars = 48..57 }
    if ($null -eq $alphaCharsLower) { $alphaCharsLower = 97..122 }
    if ($null -eq $alphaCharsUpper) { $alphaCharsUpper = 65..90 }
    if ($null -eq $printableChars) { $printableChars = 33..126 }
    if ($null -eq $cjkPunctuationArray) { $cjkPunctuationArray = @('，', '。', '！', '？', '；', '：', '“', '”', '‘', '’', '（', '）', '【', '】', '《', '》', '、') }
    switch ($Mode)
    {
        'Numeric' { $charSet = $numericChars }
        'AlphaLower' { $charSet = $alphaCharsLower }
        'AlphaUpper' { $charSet = $alphaCharsUpper }
    }
    if ($charSet)
    {

        $res = ($charSet | ForEach-Object { [char]$_ } | Get-Random -Count $Length) -join ''
    }
    else
    {

        # [string]::Join('', ($charSet | ForEach-Object { $_ } | Get-Random -Count $Length))
        switch ($Mode)
        {
            'AlphaAny' { $charSet = $printableChars }
            'PunctuationCn' { $charSet = $cjkPunctuationArray }
        }
        $res = ($charSet | Get-Random -Count $Length) -join ''
    }
    return $res
}

function New-GrowFile
{
    param(
        $Path,    
        $Lines = 20,
        $GapTime = 1
    )
    # 设置计数器
    $count = 0
    
    # 开始一个循环，持续10秒
    while ($count -lt $lines)
    {
        # 生成随机行并写入文件
        Get-RandomString | Tee-Object $Path -Append
        
        # 延迟1秒
        Start-Sleep -Seconds $GapTime
    
        # 计数器递增
        $count++
    }
}