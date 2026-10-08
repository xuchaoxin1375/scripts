#Requires -Version 5.1
<#
.SYNOPSIS
  cf_api 统一验证入口（L2 全量）：后端单测/编译/lint、前端构建、
  API 冒烟、Playwright 视觉验收。步骤级 PASS/FAIL/SKIP＋汇总 JSON，
  任一步 FAIL 即非零退出码。不认“看过代码了”。
.Usage
  powershell -File tools/verify.ps1 [-Level L2] [-SkipVisual]
#>
param([string]$Level = 'L2', [switch]$SkipVisual)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Set-Location $root
$steps = New-Object System.Collections.ArrayList

function Add-Step([string]$name, [string]$status, [string]$detail) {
  [void]$steps.Add([pscustomobject]@{ name = $name; status = $status; detail = $detail })
  Write-Output ("[{0}] {1} {2}" -f $status, $name, $detail)
}

function Run-Step([string]$name, [string]$cmd) {
  try {
    $out = Invoke-Expression $cmd 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Add-Step $name 'PASS' 'exit=0' }
    else { Add-Step $name 'FAIL' ("exit=" + $LASTEXITCODE + " " + ($out | Select-Object -Last 5)) }
  } catch { Add-Step $name 'FAIL' $_.Exception.Message }
}

# 1-2 后端单测（行为不变，黄金用例不得修改；增量契约另见 test_webui_extra/test_db_migrate）
Run-Step 'backend-unittest' 'python -m unittest tests.test_cf_dns_reliability tests.test_webui tests.test_db_migrate tests.test_webui_extra'

# 3 编译检查
Run-Step 'backend-compile' 'python -m py_compile cloudflare_dns_tool.py start_web_ui.py webui/backend/app.py webui/backend/deps.py webui/backend/jobs.py webui/backend/validate.py webui/backend/engine_adapter.py webui/backend/db.py'

# 4 Ruff（缺失则 SKIP＋安装指引，不伪装通过）
if (Get-Command ruff -ErrorAction SilentlyContinue) {
  Run-Step 'backend-ruff' 'ruff check cloudflare_dns_tool.py tests/ webui/backend/'
} else { Add-Step 'backend-ruff' 'SKIP' '未安装：pip install ruff（批准后）' }

# 5 Pyright（缺失则 SKIP）
if (Get-Command pyright -ErrorAction SilentlyContinue) {
  Run-Step 'backend-pyright' 'pyright cloudflare_dns_tool.py'
} else { Add-Step 'backend-pyright' 'SKIP' '未安装 pyright' }

# 6 前端构建
Run-Step 'frontend-build' 'npm --prefix webui/frontend run build'

# 7 API 冒烟（含 dry_run 任务与日志断言）
try {
  powershell -File (Join-Path $here 'web_smoke.ps1') -Port 8601 | Out-Null
  if ($LASTEXITCODE -eq 0) { Add-Step 'api-smoke' 'PASS' 'SMOKE PASS' }
  else { Add-Step 'api-smoke' 'FAIL' ("exit=" + $LASTEXITCODE) }
} catch { Add-Step 'api-smoke' 'FAIL' $_.Exception.Message }

# 8 视觉验收（静态断言 + 真浏览器模拟；L0/L1 可 -SkipVisual 加速）
if ($SkipVisual) { Add-Step 'visual-accept' 'SKIP' '用户显式 -SkipVisual' }
else {
  try {
    python (Join-Path $root 'webui/frontend/tests/accept.py') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'static accept failed' }
    python (Join-Path $root 'webui/frontend/tests/browser_accept.py') | Out-Null
    if ($LASTEXITCODE -eq 0) { Add-Step 'visual-accept' 'PASS' 'VISUAL+BROWSER PASS' }
    else { Add-Step 'visual-accept' 'FAIL' ("exit=" + $LASTEXITCODE) }
  } catch { Add-Step 'visual-accept' 'FAIL' $_.Exception.Message }
}

# 9 空白错误（仅任务区跟踪文件；CRLF 按仓库治理用 cr-at-eol 豁免，
# 判定时对照 git diff 与 --ignore-cr-at-eol；仓内其他脏文件与本任务无关，不挡门禁）
Run-Step 'whitespace-tracked' 'git -c core.whitespace=cr-at-eol diff --check -- cloudflare_dns_tool.py start_web_ui.py tests/ tools/ examples/ legacy/'
$newFiles = @('webui/frontend/src/index.html', 'webui/frontend/dist/index.html',
  'webui/frontend/scripts/build.mjs', 'webui/frontend/package.json', 'webui/frontend/DESIGN.md', 'webui/TASKS.md',
  'webui/frontend/tests/accept.py', 'webui/frontend/tests/browser_accept.py', 'tools/verify.ps1', 'webui/README.md', 'webui/USAGE.md',
  'webui/backend/app.py', 'webui/backend/deps.py', 'webui/backend/jobs.py', 'webui/backend/validate.py',
  'webui/backend/engine_adapter.py', 'webui/backend/db.py', 'tests/test_webui_extra.py')
$bad = @()
foreach ($f in $newFiles) {
  $p = Join-Path $root $f
  if (Test-Path $p) {
    $n = 0
    foreach ($line in [System.IO.File]::ReadAllLines($p)) {
      $n++
      if ($line -match '[ \t]+$') { $bad += ("{0}:{1}" -f $f, $n) }
    }
  }
}
if ($bad.Count -eq 0) { Add-Step 'whitespace-new' 'PASS' '无尾随空白' }
else { Add-Step 'whitespace-new' 'FAIL' ($bad -join ',') }

$failed = @($steps | Where-Object { $_.status -eq 'FAIL' }).Count
$summary = [pscustomobject]@{
  level = $Level; total = $steps.Count; failed = $failed
  steps = $steps
  result = if ($failed -eq 0) { 'VERIFY PASS' } else { 'VERIFY FAIL' }
}
$tmp = Join-Path $env:TEMP 'cf_verify'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$summary | ConvertTo-Json -Depth 5 | Out-File (Join-Path $tmp 'last.json') -Encoding utf8
Write-Output ($summary | ConvertTo-Json -Depth 5)
if ($failed -eq 0) { exit 0 } else { exit 1 }
