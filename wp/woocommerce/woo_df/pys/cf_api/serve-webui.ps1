<#
.SYNOPSIS
  Cloudflare DNS WebUI 服务：启动 / 状态 / 重启 / 停止 / 日志查看（Hidden 后台，不占 shell）。
.DESCRIPTION
  对标 frontend_design/serve-preview.ps1 的管理模型，适配 Python FastAPI（start_web_ui.py + uvicorn）：
  Start-Process -WindowStyle Hidden 后台拉起，shell 立即返回；排障看 webui.log（--log-file 追加，>512KB 转 .1）。
  启动逻辑：端口空闲直接拉起并即时反馈进度；已是本服务则复用不重起；
  被别的程序占用则询问新端口，直接回车自动顺延找空闲端口。
  停止按端口精确匹配进程，不影响本机其他 python 进程。
  安全沿用 start_web_ui.py：默认仅 127.0.0.1；绑 0.0.0.0（-Lan）无口令拒绝启动。
.PARAMETER Status
  快查：端口空闲还是被谁占（进程 PID + 端口探活 + meta 标注）。
.PARAMETER Restart
  先停本端口服务再起（换 start_web_ui.py / webui/backend 代码后用它生效）。
  外部访问/配置默认保持现状：之前是 -Lan 就继续 0.0.0.0，仅本机就继续 127.0.0.1；
  显式加 -Lan 切到局域网分享，加 -NoLan 切回仅本机（两者互斥）。
  配置（-Config）与代理（-Proxy/-ProxyFile/-ProxyMode）同样保持现状，除非显式传入覆盖。
  口令永不落盘：-Restart 默认复用进程命令行里的旧口令（仅内存重组新命令行），
  显式 -Password 优先，环境变量 CF_WEB_PASSWORD 次之；三者皆无且目标为 0.0.0.0 则拒绝。
.PARAMETER Stop
  停掉本端口的 WebUI 服务。
.PARAMETER Port
  端口号，默认 8600。被占用时的处理见 .DESCRIPTION。
.PARAMETER Lan
  局域网分享：--host 0.0.0.0，必须配口令（-Password 或 CF_WEB_PASSWORD），否则拒绝启动。
  与 -NoLan 互斥；和 -Restart 组合即重启时切换到局域网。
.PARAMETER NoLan
  切回仅本机访问（--host 127.0.0.1）。
  与 -Lan 互斥；和 -Restart 组合即重启时关闭外部访问；单独启动时无需显式传（默认即仅本机）。
.PARAMETER Config
  账号配置文件（默认与 start_web_ui.py 同口径：CF_CONFIG_PATH 环境变量，否则桌面 deploy_configs/cf_config.csv）。
  -Restart 不传即沿用当前进程的 --config。
.PARAMETER Bind
  显式绑定地址（等价 --host），与 -Lan/-NoLan 互斥；一般只用 -Lan/-NoLan 即可。
.PARAMETER Password
  WebUI 口令（等价 --password）。命令行可见，优先用环境变量 CF_WEB_PASSWORD；
  不传则复用当前进程命令行里的旧口令（-Restart 时），再无则看环境变量。
.PARAMETER Proxy
  出口代理（可多次传，等价 -P/--proxy，仅驻内存）。-Restart 不传即沿用当前值。
.PARAMETER ProxyFile
  代理文件（等价 --proxy-file）。-Restart 不传即沿用当前值。
.PARAMETER ProxyMode
  多代理调度（round-robin/sticky/failover）。空串表示沿用当前值。
.PARAMETER Logs
  看服务日志（webui.log 末尾，默认 50 行；-Lines 改行数）。服务是 Hidden 启动，排障看这里。
.PARAMETER Lines
  配合 -Logs，指定看最后几行。
.EXAMPLE
  .\serve-webui.ps1
  启动 8600（已在跑则复用；被别人占则询问，回车自动换端口）。
.EXAMPLE
  .\serve-webui.ps1 -Status
  快查 8600：进程在不在、端口通不通、meta 通不通。
.EXAMPLE
  .\serve-webui.ps1 -Restart
  重启 8600（配置/绑定/代理保持现状，口令复用旧值或环境变量）。
.EXAMPLE
  .\serve-webui.ps1 -Restart -Lan -Password secret
  重启并绑定 0.0.0.0 对外分享（无口令会拒绝）。
.EXAMPLE
  .\serve-webui.ps1 -Restart -NoLan
  重启并切回仅本机。
.EXAMPLE
  .\serve-webui.ps1 -Port 8601 -Status
  查别的端口（Status/Stop/Restart 均可与 -Port 组合）。
.EXAMPLE
  .\serve-webui.ps1 -Ports
  列出本机所有 WebUI 服务（任意端口：PID/绑定/配置/入口；只读，不碰进程）。
.EXAMPLE
  .\serve-webui.ps1 -RestartAll
  重启本机所有 WebUI 服务（逐个按当前模式保持，约 1s/个）。
.EXAMPLE
  .\serve-webui.ps1 -Logs -Lines 100
  看服务日志末尾 100 行（排障用）。
.INPUTS
  无（交互式端口询问从控制台读取；管道输入按“回车=自动选端口”处理）。
.OUTPUTS
  中文状态文本。退出码：0 正常；1 启动失败（5 秒未就绪）；2 参数无效（端口/配置/口令缺失）。
.NOTES
  要求 PowerShell 5.1+，Python 3.9+ 且已装 fastapi/uvicorn。
  约定：参数用单横线；Hidden 进程不保证跨会话存活，每次先 -Status 确认。
.LINK
  webui/README.md
#>

#Requires -Version 5.1
param([switch]$Status, [switch]$Restart, [switch]$RestartAll, [switch]$Stop, [switch]$Ports, [switch]$Lan, [switch]$NoLan, [switch]$Logs, [int]$Lines = 50, [int]$Port = 8600, [string]$Config = '', [string]$Bind = '', [string]$Password = '', [string[]]$Proxy = @(), [string]$ProxyFile = '', [string]$ProxyMode = '')

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptBound = $PSBoundParameters
$START_PY = Join-Path $here 'start_web_ui.py'
$LOG_FILE = Join-Path $here 'webui.log'

function Get-DefaultConfig {
  if ($env:CF_CONFIG_PATH -and $env:CF_CONFIG_PATH.Trim()) { return $env:CF_CONFIG_PATH.Trim() }
  return 'C:/Users/Administrator/Desktop/deploy_configs/cf_config.csv'
}

function Test-BindFree([int]$Port) {
  $l = $null
  try {
    $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Port)
    $l.Start()
    return $true
  } catch { return $false }
  finally { if ($l) { $l.Stop() } }
}

function Test-TcpPort([int]$Port, [int]$Ms = 200) {
  $c = New-Object Net.Sockets.TcpClient
  try {
    $r = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
    return $r.AsyncWaitHandle.WaitOne($Ms)
  } catch { return $false } finally { $c.Close() }
}

function Test-PortBusy([int]$Port) {
  if (-not (Test-BindFree $Port)) { return $true }
  return (Test-TcpPort $Port 200)
}

function Test-Http200([int]$Port, [int]$TimeoutSec = 3) {
  try { (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port/" -TimeoutSec $TimeoutSec).StatusCode -eq 200 }
  catch { $false }
}

function Get-Meta([int]$Port, [string]$Token = '') {
  try {
    $h = @{}
    if ($Token) { $h['X-Auth-Token'] = $Token }
    return (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port/api/v1/meta" -Headers $h -TimeoutSec 3 | ConvertFrom-Json)
  } catch { return $null }
}

function Find-WebUI([int]$Port) {
  Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" |
    Where-Object { $_.CommandLine -match 'start_web_ui\.py' -and $_.CommandLine -match "--port\s+$Port(\s|$|[""'])" }
}

function Split-CmdArgs([string]$Cmd) {
  $tokens = @()
  $cur = ''
  $q = ''
  for ($i = 0; $i -lt $Cmd.Length; $i++) {
    $c = [string]$Cmd[$i]
    if ($q -ne '') {
      if ($c -eq $q) { $q = '' } else { $cur += $c }
    } elseif ($c -eq '"' -or $c -eq "'") { $q = $c }
    elseif ($c -match '\s') { if ($cur -ne '') { $tokens += $cur; $cur = '' } }
    else { $cur += $c }
  }
  if ($cur -ne '') { $tokens += $cur }
  return $tokens
}

function Parse-Arg([string]$Cmd, [string]$Name) {
  $t = Split-CmdArgs $Cmd
  for ($i = 0; $i -lt $t.Count - 1; $i++) {
    if ($t[$i] -eq ("--" + $Name)) { return $t[$i + 1] }
  }
  return ''
}

function Parse-ArgAll([string]$Cmd, [string]$Name) {
  $out = @()
  $t = Split-CmdArgs $Cmd
  for ($i = 0; $i -lt $t.Count - 1; $i++) {
    if ($t[$i] -eq ("--" + $Name) -or $t[$i] -eq '-P') {
      if ($Name -eq 'proxy' -or $t[$i] -eq ("--" + $Name)) { $out += $t[$i + 1] }
    }
  }
  return $out
}

function Get-ServerDetail([int]$Port) {
  $procs = @(Find-WebUI $Port)
  if (-not $procs.Count) { return $null }
  $cmd = $procs[0].CommandLine
  $cfg = Parse-Arg $cmd 'config'
  $hst = Parse-Arg $cmd 'host'
  $pwd = Parse-Arg $cmd 'password'
  $pm = Parse-Arg $cmd 'proxy-mode'
  $pf = Parse-Arg $cmd 'proxy-file'
  $px = @(Parse-ArgAll $cmd 'proxy')
  # -P 短选项与 --proxy 同义：Parse-ArgAll 已合并两者，去掉模式/文件误命中
  $px = @($px | Where-Object { $_ -and $_ -ne $pm -and $_ -ne $pf })
  return [pscustomobject]@{
    Pid = $procs[0].ProcessId
    Port = $Port
    Config = $cfg
    Host = if ($hst) { $hst } else { '127.0.0.1' }
    HasPassword = [bool]($cmd -match '--password')
    Password = $pwd
    Proxy = $px
    ProxyFile = $pf
    ProxyMode = $pm
    CommandLine = $cmd
  }
}

function Find-FreePort([int]$From) {
  $p = $From + 1
  while ($p -lt 65535) {
    if (-not (Test-PortBusy $p)) { return $p }
    $p++
  }
  throw '65535 以内无可用端口'
}

function Stop-WebUI([int]$Port) {
  $procs = @(Find-WebUI $Port)
  if (-not $procs.Count) { echo "端口 $Port 没有 WebUI 服务进程。"; return }
  $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; echo "已停 PID $($_.ProcessId)" }
}

function Get-LanIps {
  try {
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
      Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
      Select-Object -ExpandProperty IPAddress -Unique | Sort-Object
    return @($ips)
  } catch { return @() }
}

function Resolve-Password([string]$Explicit, [string]$OldFromCmd) {
  if ($Explicit) { return $Explicit }
  if ($env:CF_WEB_PASSWORD -and $env:CF_WEB_PASSWORD.Trim()) { return $env:CF_WEB_PASSWORD.Trim() }
  if ($OldFromCmd) { return $OldFromCmd }
  return ''
}

function Show-Endpoints([int]$Port, [string]$HostName, [string]$Cfg, [string]$Token = '') {
  $m = Get-Meta $Port $Token
  $bind = if ($HostName -eq '0.0.0.0') { '0.0.0.0（局域网可达，需口令）' } else { '127.0.0.1（仅本机）' }
  Write-Host "本机：http://localhost:$Port/  http://127.0.0.1:$Port/"
  Write-Host "绑定：$bind"
  Write-Host "配置：$Cfg"
  if ($m) {
    $auth = if ($m.requires_auth) { '需口令（X-Auth-Token）' } else { '未设口令（仅本机可访问）' }
    Write-Host "服务：WebUI 版本 $($m.version)  $auth"
    if ($m.proxy -and $m.proxy.count) { Write-Host "代理：模式=$($m.proxy.mode) 数量=$($m.proxy.count)（仅驻内存）" }
  } else {
    Write-Host '服务：HTTP 已通，但 /api/v1/meta 未返回（设了口令未传 Token 属正常，刚启动也在此列）。'
  }
  if ($HostName -eq '0.0.0.0') {
    $hips = Get-LanIps
    if ($hips.Count) {
      Write-Host '局域网（直发同事，需口令）：'
      foreach ($ip in $hips) { Write-Host "  http://${ip}:$Port/" }
      Write-Host '防火墙：对方首次访问可能弹窗，点允许；或放行 $Port/tcp 入站。'
    } else {
      Write-Host '局域网：未发现可用 IPv4（检查 Wi-Fi/网线是否连接）。'
    }
  }
  Write-Host "自检：http://localhost:$Port/api/v1/meta"
  Write-Host "日志：.\serve-webui.ps1 -Logs -Port $Port"
  Write-Host "停止：.\serve-webui.ps1 -Stop -Port $Port"
}

function Start-WebUI([int]$Port, [string]$HostName, [string]$Cfg, [string]$Token, [string[]]$Proxies, [string]$ProxyFileArg, [string]$ProxyModeArg) {
  $t0 = Get-Date
  if ($Port -lt 1 -or $Port -gt 65535) { echo "端口无效：$Port"; exit 2 }
  if (-not $HostName) { $HostName = '127.0.0.1' }
  if (-not $Cfg) { $Cfg = Get-DefaultConfig }
  if (-not (Test-Path $Cfg)) { echo "配置文件不存在: $Cfg（-Config 指定正确路径，或设 CF_CONFIG_PATH）"; exit 2 }
  if (-not (Test-Path $START_PY)) { echo "启动入口缺失: $START_PY"; exit 2 }
  if ($HostName -notin @('127.0.0.1', 'localhost', '::1') -and -not $Token) {
    echo '对外监听（0.0.0.0）必须设置口令：-Password <pwd> 或环境变量 CF_WEB_PASSWORD，已拒绝启动'
    exit 2
  }
  Write-Host "正在检查端口 $Port …"
  if (Test-PortBusy $Port) {
    Write-Host "端口 $Port 有监听，确认是谁的服务…"
    if ((Test-Http200 $Port) -and @(Find-WebUI $Port).Count) {
      $d = Get-ServerDetail $Port
      Write-Host "已在运行，直接用：http://localhost:$Port/"
      Show-Endpoints $Port $d.Host $d.Config $Token
      return
    }
    Start-WebUI (Resolve-Conflict $Port) $HostName $Cfg $Token $Proxies $ProxyFileArg $ProxyModeArg
    return
  }
  if (Get-Command python -ErrorAction SilentlyContinue) { $py = 'python' }
  else { echo '未找到 python（需 Python 3.9+ 且装 fastapi/uvicorn）'; exit 2 }
  Write-Host "端口 $Port 空闲，正在拉起 WebUI …"
  $pyArgs = @('-u', 'start_web_ui.py', '--host', $HostName, '--port', "$Port", '--config', $Cfg, '--log-file', $LOG_FILE)
  if ($Token) { $pyArgs += @('--password', $Token) }
  foreach ($u in $Proxies) { if ($u) { $pyArgs += @('--proxy', $u) } }
  if ($ProxyFileArg) { $pyArgs += @('--proxy-file', $ProxyFileArg) }
  if ($ProxyModeArg) { $pyArgs += @('--proxy-mode', $ProxyModeArg) }
  $proc = Start-Process $py -ArgumentList $pyArgs -WorkingDirectory $here -WindowStyle Hidden -PassThru
  Write-Host ("启动请求已发送 (PID " + $proc.Id + ")，等待端口就绪") -NoNewline
  $ready = $false
  for ($i = 0; $i -lt 20; $i++) {
    if (Test-TcpPort $Port 250) { $ready = $true; break }
    Write-Host -NoNewline '.'
  }
  Write-Host ''
  if ($ready -and (Test-Http200 $Port)) {
    $sec = '{0:N1}' -f ((Get-Date) - $t0).TotalSeconds
    Write-Host "已启动：http://localhost:$Port/（用时 ${sec}s，PID $($proc.Id)，日志 webui.log）"
    Show-Endpoints $Port $HostName $Cfg $Token
    return
  }
  Write-Host "启动失败：PID $($proc.Id) 未在 5 秒内就绪。看日志：.\serve-webui.ps1 -Logs -Port $Port"
  exit 1
}

function Read-PortInput {
  Write-Host '输入新端口（直接回车则自动顺延找空闲端口）: ' -NoNewline
  try {
    if ([Console]::IsInputRedirected) { return [Console]::In.ReadLine() }
    return Read-Host
  } catch { return '' }
}

function Resolve-Conflict([int]$Port) {
  Write-Host "端口 $Port 已被别的服务占用（不是本 WebUI 服务）。"
  $in = Read-PortInput
  if ([string]::IsNullOrWhiteSpace($in)) {
    $free = Find-FreePort $Port
    Write-Host "自动选择空闲端口：$free"
    return $free
  }
  if ($in -notmatch '^\d+$' -or [int]$in -lt 1 -or [int]$in -gt 65535) {
    echo "端口无效：$in"; exit 2
  }
  return [int]$in
}

function Show-Status([int]$Port) {
  if (-not (Test-PortBusy $Port)) { echo "端口 $Port：空闲（服务没起）。看全机：.\serve-webui.ps1 -Ports"; return }
  $http = Test-Http200 $Port
  $procs = @(Find-WebUI $Port)
  if ($procs.Count) { $procs | ForEach-Object { echo "进程：PID $($_.ProcessId) [$($_.CommandLine)]" } }
  if ($http -and $procs.Count) {
    $d = Get-ServerDetail $Port
    $tok = Resolve-Password $Password $d.Password
    echo "端口 $Port：WebUI 正常（200），绑定 $($d.Host)，入口 http://localhost:$Port/"
    echo "配置：$($d.Config)"
    $m = Get-Meta $Port $tok
    if ($m) {
      $auth = if ($m.requires_auth) { '需口令' } else { '未设口令' }
      echo "自检：/api/v1/meta 通（版本 $($m.version)，$auth）"
    } else {
      echo '自检：/api/v1/meta 未返回（设了口令但未传 Token 属正常；传 -Password 后再查可看详情）。'
    }
    if ($d.Host -eq '0.0.0.0') {
      $hips = Get-LanIps
      foreach ($ip in $hips) { echo "局域网：http://${ip}:$Port/（需口令）" }
    } else {
      echo "外部访问：仅本机（加 -Lan 重启后分享：.\serve-webui.ps1 -Restart -Lan -Port $Port）"
    }
  }
  elseif ($http) { echo "端口 $Port：通（200）但不是本 WebUI 服务（可能是别的程序）" }
  else { echo "端口 $Port：被占用但 HTTP 不通（非 WebUI 服务或刚启动）" }
}

function Get-ServerList {
  try {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" |
      Where-Object { $_.CommandLine -match 'start_web_ui\.py' })
  } catch { Write-Host "查进程失败：$($_.Exception.Message)"; return }
  foreach ($p in $procs) {
    $cmd = $p.CommandLine
    $port = $null
    if ($cmd -match '--port\s+(\d+)') { $port = [int]$Matches[1] }
    if ($null -eq $port) { continue }
    $cfg = Parse-Arg $cmd 'config'
    $hst = Parse-Arg $cmd 'host'
    if (-not $hst) { $hst = '127.0.0.1' }
    [pscustomobject]@{ Pid = $p.ProcessId; Port = $port; Host = $hst; Config = $cfg }
  }
}

function Show-Servers {
  $servers = @(Get-ServerList)
  if (-not $servers.Count) {
    echo '本机暂无 WebUI 服务进程。'
    if (-not (Test-PortBusy $Port)) { echo '端口 8600：空闲。启动：.\serve-webui.ps1' }
    else { echo '端口 8600：被占用（不是 WebUI 服务）。细查：.\serve-webui.ps1 -Status' }
    return
  }
  echo "本机 WebUI 服务（共 $($servers.Count) 个）："
  foreach ($s in $servers) {
    $net = if (Test-Http200 $s.Port) { 'HTTP 通' } else { 'HTTP 不通（刚起或已僵死）' }
    $where = if ($s.Host -eq '0.0.0.0') { '局域网可达' } else { '仅本机' }
    echo "PID $($s.Pid) · 端口 $($s.Port) · $where · http://localhost:$($s.Port)/ · $net · 配置 $($s.Config)"
  }
  echo '细查某端口：.\serve-webui.ps1 -Port <端口> -Status ；停某端口：.\serve-webui.ps1 -Port <端口> -Stop'
}

function Restart-AllServers {
  $servers = @(Get-ServerList)
  if (-not $servers.Count) { echo '本机暂无 WebUI 服务进程，无需重启。'; return }
  echo "将重启 $($servers.Count) 个 WebUI 服务（模式保持）："
  $fail = 0
  foreach ($s in $servers) {
    $d = Get-ServerDetail $s.Port
    $h = $d.Host; $c = $d.Config
    $tok = Resolve-Password '' $d.Password
    echo "--- 端口 $($s.Port)（PID $($s.Pid)，绑定 $h）"
    Stop-WebUI $s.Port; Start-Sleep 1
    Start-WebUI $s.Port $h $c $tok $d.Proxy $d.ProxyFile $d.ProxyMode
    if (-not (Test-Http200 $s.Port)) { echo "端口 $($s.Port)：重启后未就绪，手动检查：.\serve-webui.ps1 -Port $($s.Port) -Status"; $fail++ }
  }
  if ($fail) { echo "完工：$fail 个未就绪。"; exit 1 }
  echo "完工：$($servers.Count) 个全部就绪。"
}

function Show-Logs([int]$Lines) {
  if (-not (Test-Path $LOG_FILE)) { echo '暂无日志（服务没运行过，或日志被删）。先 .\serve-webui.ps1 启动一次。'; return }
  Get-Content $LOG_FILE -Tail $Lines
}

if ($Lan -and $NoLan) { echo '-Lan 与 -NoLan 互斥：二选一。'; exit 2 }
if ($Bind -and ($Lan -or $NoLan)) { echo '-Bind 与 -Lan/-NoLan 互斥：指定其一即可。'; exit 2 }
if ($Logs) { Show-Logs $Lines; exit 0 }
if ($Ports) { Show-Servers; exit 0 }
if ($RestartAll) { Restart-AllServers; exit 0 }
if ($Status) { Show-Status $Port; exit 0 }
if ($Stop) { Stop-WebUI $Port; exit 0 }
if ($Restart) {
  $cur = Get-ServerDetail $Port
  $oldHost = if ($cur) { $cur.Host } else { '' }
  $oldCfg = if ($cur) { $cur.Config } else { '' }
  $oldPwd = if ($cur) { $cur.Password } else { '' }
  $oldPx = if ($cur -and $cur.Proxy) { $cur.Proxy } else { @() }
  $oldPf = if ($cur) { $cur.ProxyFile } else { '' }
  $oldPm = if ($cur) { $cur.ProxyMode } else { '' }
  if ($Lan) { $targetHost = '0.0.0.0' }
  elseif ($NoLan) { $targetHost = '127.0.0.1' }
  elseif ($scriptBound.ContainsKey('Bind') -and $Bind) { $targetHost = $Bind }
  elseif ($oldHost) { $targetHost = $oldHost }
  else { $targetHost = '127.0.0.1' }
  if ($scriptBound.ContainsKey('Config') -and $Config) { $targetCfg = $Config }
  elseif ($oldCfg) { $targetCfg = $oldCfg }
  else { $targetCfg = Get-DefaultConfig }
  if ($scriptBound.ContainsKey('Proxy') -and $Proxy.Count) { $targetPx = $Proxy }
  else { $targetPx = $oldPx }
  if ($scriptBound.ContainsKey('ProxyFile')) { $targetPf = $ProxyFile }
  else { $targetPf = $oldPf }
  if ($scriptBound.ContainsKey('ProxyMode')) { $targetPm = $ProxyMode }
  else { $targetPm = $oldPm }
  $targetPwd = Resolve-Password $Password $oldPwd
  if (-not $cur) { Write-Host '当前模式问不到（服务没在跑或刚停），按显式参数/默认值重启；要分享加 -Lan。' }
  else { Write-Host "外部访问：$targetHost（配置 $targetCfg，代理 $($targetPx.Count) 个，模式保持）" }
  Stop-WebUI $Port; Start-Sleep 1; Start-WebUI $Port $targetHost $targetCfg $targetPwd $targetPx $targetPf $targetPm; exit 0
}
if ($Lan) { $startHost = '0.0.0.0' } elseif ($NoLan) { $startHost = '127.0.0.1' } elseif ($Bind) { $startHost = $Bind } else { $startHost = '127.0.0.1' }
if ($scriptBound.ContainsKey('Config') -and $Config) { $startCfg = $Config } else { $startCfg = Get-DefaultConfig }
$startPwd = Resolve-Password $Password ''
if ($scriptBound.ContainsKey('ProxyMode')) { $startPm = $ProxyMode } else { $startPm = '' }
Start-WebUI $Port $startHost $startCfg $startPwd $Proxy $ProxyFile $startPm
