#Requires -Version 5.1
<#
.SYNOPSIS
  WebUI smoke test: start server, check meta/accounts/compat/SPA,
  submit a dry_run job, poll status/logs/failures, stop server.
  Uses a temp dummy config only. No real accounts touched.
  Usage: powershell -File tools/web_smoke.ps1 [-Port 8601]
#>
param([int]$Port = 8601)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$tmp = Join-Path $env:TEMP 'cf_web_smoke'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$cfg = Join-Path $tmp 'cf_config.json'
[System.IO.File]::WriteAllText($cfg, '{"accounts":{"smoke":{"cf_api_token":"dummy"}}}')

$proc = Start-Process python -ArgumentList @(
  (Join-Path $root 'start_web_ui.py'), '--port', "$Port", '--config', $cfg
) -PassThru -WindowStyle Hidden
try {
  $ok = $false
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $m = Invoke-RestMethod "http://127.0.0.1:$Port/api/v1/meta" -TimeoutSec 3
      if ($m.version) { $ok = $true; break }
    } catch { Start-Sleep -Seconds 1 }
  }
  if (-not $ok) { throw 'server not ready' }
  Write-Output ("meta ok version=" + $m.version)

  $a = Invoke-RestMethod "http://127.0.0.1:$Port/api/v1/accounts" -TimeoutSec 5
  if ($a.items.Count -lt 1) { throw 'no accounts' }
  if (($a.items | ConvertTo-Json) -match 'dummy') { throw 'secret not masked' }
  Write-Output 'accounts ok (masked)'

  $c = Invoke-RestMethod "http://127.0.0.1:$Port/api/meta" -TimeoutSec 5
  if (-not $c.version) { throw 'compat endpoint failed' }
  Write-Output 'compat ok'

  $wc = New-Object Net.WebClient
  $spaHtml = $wc.DownloadString("http://127.0.0.1:$Port/")
  if (-not $spaHtml -or $spaHtml -notmatch 'root') { throw 'SPA failed' }
  Write-Output 'spa ok'

  $body = @{
    mode = 'update'; accounts = @('smoke'); domains = @('example.com')
    new_content = '1.2.3.4'; record_type = 'auto'; dry_run = $true; speed = 'eco'
  } | ConvertTo-Json
  $job = Invoke-RestMethod "http://127.0.0.1:$Port/api/v1/jobs" -Method Post `
    -ContentType 'application/json' -Body $body -TimeoutSec 10
  Write-Output ("job submitted " + $job.job_id)
  Start-Sleep -Seconds 12
  $st = Invoke-RestMethod "http://127.0.0.1:$Port/api/v1/jobs/$($job.job_id)" -TimeoutSec 5
  $lg = Invoke-RestMethod "http://127.0.0.1:$Port/api/v1/jobs/$($job.job_id)/logs?limit=5" -TimeoutSec 5
  Write-Output ("job status=" + $st.status + " logs=" + $lg.total + " failures=" + $st.failure_count)
  if ($lg.total -lt 1) { throw 'empty job logs' }
  Write-Output 'SMOKE PASS'
} finally {
  if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
