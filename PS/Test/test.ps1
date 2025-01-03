# $url = "https://example.com/download/file.txt"
$url = "https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v2.0.2/Clash.Verge_2.0.2_x64-setup.exe"
$response = Invoke-WebRequest -Uri $url -Method Get
$fileName = $response.Headers["Content-Disposition"] | Select-String -Pattern "filename=(.*)"
$fileName = $fileName.Matches[0].Groups[1].Value
Write-Host "File name: $fileName"