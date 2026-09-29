# Web UI smoke test: start server in background, probe pages, cleanup.
param(
    [int]$Port = 18080,
    [int]$WaitSeconds = 25
)

$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$proc = Start-Process -FilePath "python" -ArgumentList @("start_web_ui.py", "--port", "$Port") -WorkingDirectory $dir -PassThru
try {
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $ok = $false
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 3
            if ($resp.StatusCode -eq 200 -and $resp.Content -match "Cloudflare DNS") { $ok = $true; break }
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    if (-not $ok) { throw "index probe failed" }
    $static = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/static/app.js" -UseBasicParsing -TimeoutSec 5
    if ($static.StatusCode -ne 200) { throw "static probe failed" }
    $meta = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/meta" -UseBasicParsing -TimeoutSec 5
    if ($meta.StatusCode -ne 200) { throw "meta probe failed" }
    $api = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/jobs" -UseBasicParsing -TimeoutSec 5
    if ($api.StatusCode -ne 200) { throw "api probe failed" }
    Write-Output "WEB_SMOKE_OK"
} finally {
    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
