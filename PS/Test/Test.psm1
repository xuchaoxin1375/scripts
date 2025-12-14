<#
.SYNOPSIS
    批量测试主机连通性与 HTTP 状态码。

.DESCRIPTION
    Test-HostBatch 支持从文件或管道读取主机名或 URL，自动提取主机，
    并行执行 ICMP Ping 和（如果是 URL）HTTP HEAD/GET 请求，返回结构化结果。

.PARAMETER InputFile
    包含主机或 URL 的文本文件路径（每行一个）。

.PARAMETER InputObject
    通过管道传入的字符串数组（支持管道）。

.PARAMETER ThrottleLimit
    并行线程数，默认 32。

.PARAMETER TimeoutSeconds
    HTTP 请求和 Ping 的超时时间（秒），默认 10。

.PARAMETER Method
    HTTP 请求方法，可选 HEAD（默认）、GET。

.PARAMETER NoStatus
    静默模式，不输出进度信息。

.EXAMPLE
    Test-HostBatch -InputFile .\urls.txt
    测试文件中所有地址的 Ping 和 HTTP 状态码。

.EXAMPLE
    "google.com", "https://httpbin.org/status/404" | Test-HostBatch
    通过管道传入。

.EXAMPLE
    Test-HostBatch -InputFile .\urls.txt | Export-Csv report.csv -Encoding UTF8 -NoTypeInformation
    导出完整报告。

.OUTPUTS
    PSCustomObject，包含：
    - Host           : 原始输入
    - ResolvedHost   : 解析出的主机名
    - PingStatus     : "Up" / "Down"（ICMP）
    - PingLatency    : ICMP 延迟（ms）
    - IsHttpUrl      : 是否为 HTTP/HTTPS
    - StatusCode     : HTTP 状态码（如 200, 404）
    - StatusDescription : 状态描述（如 OK, Not Found）
    - Error          : 错误信息

.NOTES
    要求：PowerShell 7+
    HTTP 请求默认使用 HEAD 方法（节省带宽），失败时自动 fallback 到 GET。
#>
function push1by1
{
    <# 
    .SYNOPSIS
    测试后台作业特性:边计算边返回内容,并且便于模拟耗时任务,时间可以通过参数自行指定
    每秒返回1个数字,默认返回10个数
    .PARAMETER Count
    运行时间,也是打印的数字数量(通常填正整数)
    .PARAMETER ShowProgress
    打印数字时显示总数,每个数的打印会以[$i/$Count]的格式打印,这种情况下,可以用来简单区分运行在不同后台作业的此函数
    .PARAMETER ShowDateTime
    打印日期时间
    .DESCRIPTION
    .NOTES
    可以考虑支持打印时间
    #>
    [cmdletBinding()]
    param(
        $Count = 10,
        $JobMark="",
        [switch]$ShowProgress,
        [switch]$ShowDateTime
    )
    if ($Count -and $Count.GetType().Name -match 'Int|Decimal|Double')
    {
        Write-Verbose "$Count 是数值类型 (通过名称匹配)"
    }
    else
    {
        Write-Output "[$Count] 不是数值类型"
        return $False
    }
    for ($i = 0; $i -lt $Count; $i++)
    {
        Start-Sleep 1
        $c = $i + 1
        if($ShowProgress)
        {
            $res = "[$c/$Count]"
        }else{
            $res = $c
        }
        if($ShowDateTime){
            $res="$res $(Get-Date -Format 'yyyy-MM-dd--HH-mm-ss.fff')"
        }
        if($JobMark){
            $res="[$JobMark]: $res"
        }
        Write-Output $res
        # return $i
    }
}
function Test-HostBatch
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string[]] $InputObject,

        [Parameter()]
        [string] $InputFile,

        [int] $ThrottleLimit = 32,

        [int] $TimeoutSeconds = 10,

        [ValidateSet('HEAD', 'GET')]
        [string] $Method = 'HEAD',

        [switch] $NoStatus
    )

    begin
    {
        $inputs = @()
        if ($InputFile)
        {
            if (-not (Test-Path $InputFile)) { throw "文件不存在: $InputFile" }
            $inputs += Get-Content -Path $InputFile -Encoding UTF8
        }
    }

    process
    {
        if ($null -ne $InputObject)
        {
            $inputs += $InputObject
        }
    }

    end
    {
        $inputs |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' -and $_ -notmatch '^\s*#' } |
        ForEach-Object -Parallel {
            # =============== ✅ 关键：启用 TLS 1.2 + 1.3 ===============
            [System.Net.ServicePointManager]::SecurityProtocol = 
            [System.Net.SecurityProtocolType]::Tls12 -bor 
            [System.Net.SecurityProtocolType]::Tls13

            $raw = $_
            $isHttp = $raw -match '^https?://.+'
            $hostname = $null

            $result = [ordered]@{
                Host              = $raw
                ResolvedHost      = $null
                PingStatus        = 'Down'
                PingLatency       = $null
                IsHttpUrl         = $isHttp
                StatusCode        = $null
                StatusDescription = $null
                Error             = $null
            }

            # --- 提取主机 ---
            if ($isHttp)
            {
                try
                {
                    $uri = [System.Uri]$raw
                    $hostname = $uri.Host
                    if (-not $uri.Port)
                    {
                        $port = if ($uri.Scheme -eq 'https') { 443 } else { 80 }
                    }
                    else
                    {
                        $port = $uri.Port
                    }
                }
                catch
                {
                    $result.Error = "无效 URL"
                    return [PSCustomObject]$result
                }
            }
            else
            {
                $hostname = $raw
            }

            if ([string]::IsNullOrEmpty($hostname))
            {
                $result.Error = "无法提取主机名"
                return [PSCustomObject]$result
            }
            $result.ResolvedHost = $hostname

            # --- ICMP Ping ---
            try
            {
                $ping = Test-Connection -TargetName $hostname -Count 1 -TimeoutSeconds $using:TimeoutSeconds -ErrorAction Stop
                $result.PingStatus = 'Up'
                $result.PingLatency = $ping.Latency
            }
            catch
            {
                $result.Error = "Ping 失败: $($_.Exception.Message)"
            }

            # --- HTTP(S) 状态码（使用 .NET 原生请求）---
            if ($isHttp)
            {
                $request = $null
                try
                {
                    $uri = [System.Uri]$raw
                    $request = [System.Net.WebRequest]::Create($uri)
                    $request.Method = $using:Method
                    $request.Timeout = $using:TimeoutSeconds * 1000
                    $request.AllowAutoRedirect = $true  # 可选：跟随重定向

                    # 忽略证书错误（仅测试环境）
                    if ($request -is [System.Net.HttpWebRequest])
                    {
                        $request.ServerCertificateValidationCallback = { $true }
                    }

                    $response = $request.GetResponse()
                    $result.StatusCode = $response.StatusCode.value__
                    $result.StatusDescription = $response.StatusDescription
                    $response.Close()
                }
                catch
                {
                    $ex = $_.Exception

                    # 👉 捕获 WebException 中的响应状态码
                    if ($ex -is [System.Net.WebException] -and $ex.Response)
                    {
                        $resp = $ex.Response
                        $status = $resp.StatusCode.value__
                        $desc = $resp.StatusDescription
                        $result.StatusCode = $status
                        $result.StatusDescription = $desc
                    }
                    else
                    {
                        $msg = $ex.Message -replace '\r?\n', ' '
                        if ($result.Error -eq $null)
                        {
                            $result.Error = "HTTP 错误: $msg"
                        }
                    }
                }
                finally
                {
                    if ($request -and $request.RequestUri.Scheme -eq 'https')
                    {
                        # 清理
                        $request.ServicePoint.CloseConnectionGroup("")
                    }
                }
            }

            [PSCustomObject]$result
        } -ThrottleLimit $ThrottleLimit |
        Select-Object Host, ResolvedHost, PingStatus, PingLatency, IsHttpUrl, StatusCode, StatusDescription, Error
    }
}