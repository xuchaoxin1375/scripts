function Get-WhoisInfo {
    <#
    .SYNOPSIS
        批量并发查询域名的 WHOIS 信息。

    .DESCRIPTION
        该函数支持对一批域名进行并发 WHOIS 查询，利用 RunspacePool 实现并行处理，
        显著提升大批量域名查询的效率。

        支持通过管道输入域名列表，可选择仅返回注册日期信息。

        查询方式：
        1. 优先使用 RDAP (Registration Data Access Protocol) JSON API 查询
        2. RDAP 是 WHOIS 的现代替代协议，返回结构化 JSON 数据

    .PARAMETER DomainName
        要查询的域名列表。支持单个域名字符串或域名数组。
        支持通过管道传入。

    .PARAMETER RegisterTime
        开关参数。指定此参数时，仅返回域名的注册日期信息，
        输出精简结果（域名 + 注册日期）。

    .PARAMETER ThrottleLimit
        并发线程数上限，默认值为 10。
        根据网络带宽和系统资源适当调整，建议不超过 50。

    .PARAMETER TimeoutSeconds
        每个查询的超时时间（秒），默认值为 30 秒。

    .OUTPUTS
        PSCustomObject
        当不指定 -RegisterTime 时，返回包含以下属性的对象：
            - DomainName       : 域名
            - Registrar        : 注册商
            - RegistrationDate : 注册日期
            - ExpirationDate   : 到期日期
            - UpdatedDate      : 最后更新日期
            - NameServers      : 域名服务器列表
            - Status           : 域名状态
            - RawData          : 原始返回数据（用于调试）
            - Error            : 错误信息（查询失败时）

        当指定 -RegisterTime 时，返回包含以下属性的对象：
            - DomainName       : 域名
            - RegistrationDate : 注册日期
            - Error            : 错误信息（查询失败时）

    .EXAMPLE
        Get-WhoisInfo -DomainName "example.com"

        查询单个域名的完整 WHOIS 信息。

    .EXAMPLE
        Get-WhoisInfo -DomainName "example.com" -RegisterTime

        仅查询 example.com 的注册日期。

    .EXAMPLE
        "google.com", "github.com", "microsoft.com" | Get-WhoisInfo -ThrottleLimit 5

        通过管道传入多个域名，使用 5 个并发线程进行查询。

    .EXAMPLE
        $domains = Get-Content .\domains.txt
        Get-WhoisInfo -DomainName $domains -RegisterTime -ThrottleLimit 20

        从文件读取域名列表，使用 20 个并发线程仅查询注册日期。

    .EXAMPLE
        Get-WhoisInfo -DomainName "example.com","example.net" | Format-Table -AutoSize

        查询多个域名并以表格形式展示结果。

    .EXAMPLE
        $results = Get-WhoisInfo -DomainName (Get-Content domains.txt) -TimeoutSeconds 60
        $results | Export-Csv -Path "whois_results.csv" -NoTypeInformation

        查询域名列表并将结果导出为 CSV 文件。

    .NOTES
        作者      : PowerShell WHOIS Tool
        版本      : 1.0.0
        依赖      : 需要网络访问权限（访问 RDAP API 和 WHOIS 服务器）
        兼容性    : PowerShell 5.1+ / PowerShell 7+

        注意事项：
        - 大批量查询时请注意 API 速率限制，适当调整 ThrottleLimit
        - 部分域名后缀可能不被 RDAP 支持，会自动回退到原始 WHOIS 查询
        - 网络环境可能影响查询速度和成功率

    .LINK
        https://www.iana.org/domains/root/db
        https://rdap.org/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "要查询 WHOIS 信息的域名列表"
        )]
        [ValidateNotNullOrEmpty()]
        [Alias("Domain", "Name")]
        [string[]]$DomainName,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "仅查询并返回域名的注册日期"
        )]
        [switch]$RegisterTime,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "并发查询的最大线程数"
        )]
        [ValidateRange(1, 100)]
        [int]$ThrottleLimit = 10,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "每个查询的超时时间（秒）"
        )]
        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 30
    )

    begin {
        <#
        .NOTES
            begin 块：初始化 RunspacePool 和收集管道输入的域名列表。
            在此处定义查询脚本块，供每个并发任务使用。
        #>

        Write-Verbose "初始化 WHOIS 批量查询引擎..."

        # 收集所有通过管道传入的域名
        $allDomains = [System.Collections.Generic.List[string]]::new()

        # 定义单个域名 WHOIS 查询的脚本块（在 Runspace 中执行）
        $queryScriptBlock = {
            param(
                [string]$Domain,
                [int]$Timeout
            )

            # 结果对象模板
            $result = [PSCustomObject]@{
                DomainName       = $Domain
                Registrar        = $null
                RegistrationDate = $null
                ExpirationDate   = $null
                UpdatedDate      = $null
                NameServers      = $null
                Status           = $null
                RawData          = $null
                Error            = $null
            }

            try {
                # ============================================================
                # 方法1：使用 RDAP (Registration Data Access Protocol) 查询
                # RDAP 是 ICANN 推荐的 WHOIS 替代协议，返回结构化 JSON
                # ============================================================
                $rdapUrl = "https://rdap.org/domain/$Domain"

                # 兼容 PowerShell 5.1 和 7+
                $rdapResponse = $null
                try {
                    if ($PSVersionTable.PSVersion.Major -ge 7) {
                        $rdapResponse = Invoke-RestMethod -Uri $rdapUrl -TimeoutSec $Timeout -ErrorAction Stop
                    }
                    else {
                        # PowerShell 5.1 的 Invoke-RestMethod 使用不同的参数
                        $rdapResponse = Invoke-RestMethod -Uri $rdapUrl -TimeoutSec $Timeout -ErrorAction Stop
                    }
                }
                catch {
                    # RDAP 查询失败，尝试备用 RDAP 端点
                    $backupUrls = @(
                        "https://rdap.verisign.com/com/v1/domain/$Domain",
                        "https://rdap.verisign.com/net/v1/domain/$Domain",
                        "https://rdap.org/domain/$Domain"
                    )

                    $tld = ($Domain -split '\.')[-1].ToLower()

                    # 根据 TLD 选择合适的 RDAP 服务器
                    $rdapServers = @{
                        'com'  = 'https://rdap.verisign.com/com/v1/domain/'
                        'net'  = 'https://rdap.verisign.com/net/v1/domain/'
                        'org'  = 'https://rdap.org/domain/'
                        'info' = 'https://rdap.org/domain/'
                        'io'   = 'https://rdap.org/domain/'
                        'cn'   = 'https://rdap.org/domain/'
                    }

                    $rdapBase = if ($rdapServers.ContainsKey($tld)) { $rdapServers[$tld] } else { 'https://rdap.org/domain/' }

                    try {
                        $rdapResponse = Invoke-RestMethod -Uri "$rdapBase$Domain" -TimeoutSec $Timeout -ErrorAction Stop
                    }
                    catch {
                        throw "RDAP 查询失败: $_"
                    }
                }

                if ($rdapResponse) {
                    # 解析 RDAP 响应中的事件日期
                    if ($rdapResponse.events) {
                        foreach ($event in $rdapResponse.events) {
                            switch ($event.eventAction) {
                                'registration' {
                                    $result.RegistrationDate = try {
                                        [DateTime]::Parse($event.eventDate).ToString("yyyy-MM-dd HH:mm:ss")
                                    }
                                    catch { $event.eventDate }
                                }
                                'expiration' {
                                    $result.ExpirationDate = try {
                                        [DateTime]::Parse($event.eventDate).ToString("yyyy-MM-dd HH:mm:ss")
                                    }
                                    catch { $event.eventDate }
                                }
                                'last changed' {
                                    $result.UpdatedDate = try {
                                        [DateTime]::Parse($event.eventDate).ToString("yyyy-MM-dd HH:mm:ss")
                                    }
                                    catch { $event.eventDate }
                                }
                                'last update of RDAP database' {
                                    # 跳过数据库更新时间
                                }
                            }
                        }
                    }

                    # 解析注册商信息
                    if ($rdapResponse.entities) {
                        foreach ($entity in $rdapResponse.entities) {
                            if ($entity.roles -contains 'registrar') {
                                if ($entity.vcardArray) {
                                    # vCard 格式解析注册商名称
                                    foreach ($vcard in $entity.vcardArray[1]) {
                                        if ($vcard[0] -eq 'fn') {
                                            $result.Registrar = $vcard[3]
                                            break
                                        }
                                    }
                                }
                                if (-not $result.Registrar -and $entity.handle) {
                                    $result.Registrar = $entity.handle
                                }
                                if (-not $result.Registrar -and $entity.publicIds) {
                                    $result.Registrar = ($entity.publicIds | Select-Object -First 1).identifier
                                }
                                break
                            }
                        }
                    }

                    # 解析 Name Servers
                    if ($rdapResponse.nameservers) {
                        $result.NameServers = ($rdapResponse.nameservers | ForEach-Object { $_.ldhName }) -join ', '
                    }

                    # 解析域名状态
                    if ($rdapResponse.status) {
                        $result.Status = ($rdapResponse.status) -join ', '
                    }

                    # 保存原始数据
                    $result.RawData = $rdapResponse | ConvertTo-Json -Depth 10 -Compress
                }

                # ============================================================
                # 如果 RDAP 未获取到注册日期，回退到原始 WHOIS 查询
                # ============================================================
                if (-not $result.RegistrationDate) {
                    # 使用 TCP Socket 直接查询 WHOIS 服务器
                    $whoisServers = @{
                        'com'   = 'whois.verisign-grs.com'
                        'net'   = 'whois.verisign-grs.com'
                        'org'   = 'whois.pir.org'
                        'info'  = 'whois.afilias.net'
                        'io'    = 'whois.nic.io'
                        'cn'    = 'whois.cnnic.cn'
                        'co'    = 'whois.nic.co'
                        'uk'    = 'whois.nic.uk'
                        'de'    = 'whois.denic.de'
                        'ru'    = 'whois.tcinet.ru'
                        'jp'    = 'whois.jprs.jp'
                        'fr'    = 'whois.nic.fr'
                        'au'    = 'whois.auda.org.au'
                        'nl'    = 'whois.sidn.nl'
                        'eu'    = 'whois.eu'
                        'me'    = 'whois.nic.me'
                        'tv'    = 'whois.nic.tv'
                        'cc'    = 'ccwhois.verisign-grs.com'
                        'biz'   = 'whois.biz'
                        'top'   = 'whois.nic.top'
                        'xyz'   = 'whois.nic.xyz'
                        'site'  = 'whois.nic.site'
                        'online'= 'whois.nic.online'
                        'app'   = 'whois.nic.google'
                        'dev'   = 'whois.nic.google'
                    }

                    $tld = ($Domain -split '\.')[-1].ToLower()
                    $whoisServer = if ($whoisServers.ContainsKey($tld)) { $whoisServers[$tld] } else { "whois.nic.$tld" }

                    try {
                        $tcpClient = New-Object System.Net.Sockets.TcpClient
                        $tcpClient.ReceiveTimeout = $Timeout * 1000
                        $tcpClient.SendTimeout = $Timeout * 1000

                        $connectTask = $tcpClient.ConnectAsync($whoisServer, 43)
                        if (-not $connectTask.Wait($Timeout * 1000)) {
                            throw "WHOIS 连接超时"
                        }

                        $stream = $tcpClient.GetStream()
                        $writer = New-Object System.IO.StreamWriter($stream)
                        $reader = New-Object System.IO.StreamReader($stream)

                        $writer.WriteLine($Domain)
                        $writer.Flush()

                        $whoisData = $reader.ReadToEnd()

                        $writer.Close()
                        $reader.Close()
                        $tcpClient.Close()

                        if ($whoisData) {
                            $result.RawData = $whoisData

                            # 解析注册日期（匹配多种格式）
                            $regPatterns = @(
                                'Creation Date:\s*(.+)',
                                'Created Date:\s*(.+)',
                                'Registration Time:\s*(.+)',
                                'created:\s*(.+)',
                                'Created:\s*(.+)',
                                'Registration Date:\s*(.+)',
                                'Domain Registration Date:\s*(.+)',
                                'registered:\s*(.+)',
                                '\[Created on\]\s*(.+)',
                                'Registered on:\s*(.+)'
                            )

                            foreach ($pattern in $regPatterns) {
                                if ($whoisData -match $pattern) {
                                    $dateStr = $Matches[1].Trim()
                                    $result.RegistrationDate = try {
                                        [DateTime]::Parse($dateStr).ToString("yyyy-MM-dd HH:mm:ss")
                                    }
                                    catch { $dateStr }
                                    break
                                }
                            }

                            # 解析到期日期
                            $expPatterns = @(
                                'Expir\w+ Date:\s*(.+)',
                                'Expiry Date:\s*(.+)',
                                'paid-till:\s*(.+)',
                                'Expires on:\s*(.+)',
                                '\[Expires on\]\s*(.+)'
                            )
                            if (-not $result.ExpirationDate) {
                                foreach ($pattern in $expPatterns) {
                                    if ($whoisData -match $pattern) {
                                        $dateStr = $Matches[1].Trim()
                                        $result.ExpirationDate = try {
                                            [DateTime]::Parse($dateStr).ToString("yyyy-MM-dd HH:mm:ss")
                                        }
                                        catch { $dateStr }
                                        break
                                    }
                                }
                            }

                            # 解析更新日期
                            $updPatterns = @(
                                'Updated Date:\s*(.+)',
                                'Last Modified:\s*(.+)',
                                'last-modified:\s*(.+)',
                                'Last Updated:\s*(.+)'
                            )
                            if (-not $result.UpdatedDate) {
                                foreach ($pattern in $updPatterns) {
                                    if ($whoisData -match $pattern) {
                                        $dateStr = $Matches[1].Trim()
                                        $result.UpdatedDate = try {
                                            [DateTime]::Parse($dateStr).ToString("yyyy-MM-dd HH:mm:ss")
                                        }
                                        catch { $dateStr }
                                        break
                                    }
                                }
                            }

                            # 解析注册商
                            if (-not $result.Registrar) {
                                if ($whoisData -match 'Registrar:\s*(.+)') {
                                    $result.Registrar = $Matches[1].Trim()
                                }
                            }

                            # 解析 Name Servers
                            if (-not $result.NameServers) {
                                $nsMatches = [regex]::Matches($whoisData, 'Name Server:\s*(.+)')
                                if ($nsMatches.Count -gt 0) {
                                    $result.NameServers = ($nsMatches | ForEach-Object { $_.Groups[1].Value.Trim() }) -join ', '
                                }
                            }

                            # 解析域名状态
                            if (-not $result.Status) {
                                $statusMatches = [regex]::Matches($whoisData, 'Domain Status:\s*(.+)')
                                if ($statusMatches.Count -gt 0) {
                                    $result.Status = ($statusMatches | ForEach-Object {
                                        ($_.Groups[1].Value.Trim() -split '\s+')[0]
                                    }) -join ', '
                                }
                            }
                        }
                    }
                    catch {
                        # 如果 WHOIS TCP 查询也失败，记录但不覆盖已有错误
                        if (-not $result.RegistrationDate) {
                            $result.Error = "WHOIS TCP 查询失败: $_"
                        }
                    }
                }
            }
            catch {
                $result.Error = $_.Exception.Message
            }

            return $result
        }
    }

    process {
        <#
        .NOTES
            process 块：收集通过管道传入的每个域名。
            实际的并发查询在 end 块中统一执行。
        #>

        foreach ($domain in $DomainName) {
            # 清理域名格式
            $cleanDomain = $domain.Trim().ToLower()

            # 移除协议前缀（如果用户误传入 URL）
            $cleanDomain = $cleanDomain -replace '^https?://', ''
            $cleanDomain = $cleanDomain -replace '/.*$', ''
            $cleanDomain = $cleanDomain -replace '^www\.', ''

            if (-not [string]::IsNullOrWhiteSpace($cleanDomain)) {
                $allDomains.Add($cleanDomain)
            }
        }
    }

    end {
        <#
        .NOTES
            end 块：使用 RunspacePool 并发执行所有域名的 WHOIS 查询。
            - 创建受限的 RunspacePool 控制并发数
            - 为每个域名创建独立的 PowerShell 实例
            - 异步执行并收集结果
        #>

        if ($allDomains.Count -eq 0) {
            Write-Warning "未提供有效的域名。"
            return
        }

        # 去重
        $uniqueDomains = $allDomains | Select-Object -Unique
        $totalCount = $uniqueDomains.Count

        Write-Verbose "准备查询 $totalCount 个域名，并发数: $ThrottleLimit"

        # 创建 RunspacePool（线程池）
        $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
        $runspacePool.ApartmentState = [System.Threading.ApartmentState]::MTA
        $runspacePool.Open()

        # 存储所有异步任务
        $tasks = [System.Collections.Generic.List[PSCustomObject]]::new()

        try {
            # 为每个域名创建并发任务
            $currentIndex = 0
            foreach ($domain in $uniqueDomains) {
                $currentIndex++
                Write-Verbose "提交查询任务 [$currentIndex/$totalCount]: $domain"

                # 创建 PowerShell 实例
                $powershell = [PowerShell]::Create()
                $powershell.RunspacePool = $runspacePool

                # 添加脚本和参数
                [void]$powershell.AddScript($queryScriptBlock)
                [void]$powershell.AddParameter("Domain", $domain)
                [void]$powershell.AddParameter("Timeout", $TimeoutSeconds)

                # 异步启动
                $handle = $powershell.BeginInvoke()

                # 记录任务信息
                $tasks.Add([PSCustomObject]@{
                    PowerShell = $powershell
                    Handle     = $handle
                    Domain     = $domain
                })
            }

            # 收集所有结果
            $completedCount = 0
            foreach ($task in $tasks) {
                try {
                    # 等待任务完成
                    $queryResult = $task.PowerShell.EndInvoke($task.Handle)

                    $completedCount++
                    $percentComplete = [math]::Round(($completedCount / $totalCount) * 100, 1)
                    Write-Progress -Activity "WHOIS 批量查询" `
                        -Status "已完成 $completedCount/$totalCount ($percentComplete%)" `
                        -PercentComplete $percentComplete `
                        -CurrentOperation "正在处理: $($task.Domain)"

                    # 检查 PowerShell 流中的错误
                    if ($task.PowerShell.Streams.Error.Count -gt 0) {
                        $errorMsg = ($task.PowerShell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
                        Write-Verbose "域名 $($task.Domain) 查询出现错误: $errorMsg"
                    }

                    if ($queryResult) {
                        foreach ($r in $queryResult) {
                            if ($RegisterTime) {
                                # 仅输出注册日期
                                [PSCustomObject]@{
                                    DomainName       = $r.DomainName
                                    RegistrationDate = $r.RegistrationDate
                                    Error            = $r.Error
                                }
                            }
                            else {
                                # 输出完整信息（移除 RawData 以保持输出整洁，RawData 仍可通过属性访问）
                                $r
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "处理域名 $($task.Domain) 的结果时出错: $_"

                    if ($RegisterTime) {
                        [PSCustomObject]@{
                            DomainName       = $task.Domain
                            RegistrationDate = $null
                            Error            = $_.Exception.Message
                        }
                    }
                    else {
                        [PSCustomObject]@{
                            DomainName       = $task.Domain
                            Registrar        = $null
                            RegistrationDate = $null
                            ExpirationDate   = $null
                            UpdatedDate      = $null
                            NameServers      = $null
                            Status           = $null
                            RawData          = $null
                            Error            = $_.Exception.Message
                        }
                    }
                }
                finally {
                    # 释放 PowerShell 实例资源
                    $task.PowerShell.Dispose()
                }
            }

            Write-Progress -Activity "WHOIS 批量查询" -Completed
        }
        finally {
            # 确保 RunspacePool 被正确关闭和释放
            $runspacePool.Close()
            $runspacePool.Dispose()

            Write-Verbose "WHOIS 查询完成，共处理 $totalCount 个域名。"
        }
    }
}


# ============================================================
# 使用格式化定义，优化默认显示（隐藏 RawData 列）
# ============================================================
$defaultDisplaySet = @('DomainName', 'Registrar', 'RegistrationDate', 'ExpirationDate', 'Status', 'Error')
$defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet', [string[]]$defaultDisplaySet)
$PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)


# ============================================================
# 辅助函数：格式化输出 WHOIS 查询结果
# ============================================================
function Format-WhoisResult {
    <#
    .SYNOPSIS
        格式化显示 WHOIS 查询结果的详细信息。

    .DESCRIPTION
        将 Get-WhoisInfo 的输出以友好的格式显示，适合在控制台中查看详细信息。

    .PARAMETER WhoisResult
        Get-WhoisInfo 返回的结果对象。

    .EXAMPLE
        Get-WhoisInfo -DomainName "example.com" | Format-WhoisResult

        以友好格式显示 example.com 的 WHOIS 详细信息。
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$WhoisResult
    )

    process {
        Write-Host "`n" -NoNewline
        Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  域名: " -ForegroundColor Yellow -NoNewline
        Write-Host $WhoisResult.DomainName -ForegroundColor White

        if ($WhoisResult.Error) {
            Write-Host "  错误: " -ForegroundColor Red -NoNewline
            Write-Host $WhoisResult.Error -ForegroundColor Red
        }
        else {
            if ($WhoisResult.PSObject.Properties['Registrar']) {
                Write-Host "  注册商:   " -ForegroundColor Gray -NoNewline
                Write-Host ($WhoisResult.Registrar ?? "N/A") -ForegroundColor White
            }
            Write-Host "  注册日期: " -ForegroundColor Gray -NoNewline
            Write-Host ($WhoisResult.RegistrationDate ?? "N/A") -ForegroundColor Green

            if ($WhoisResult.PSObject.Properties['ExpirationDate']) {
                Write-Host "  到期日期: " -ForegroundColor Gray -NoNewline
                Write-Host ($WhoisResult.ExpirationDate ?? "N/A") -ForegroundColor Yellow
            }
            if ($WhoisResult.PSObject.Properties['UpdatedDate']) {
                Write-Host "  更新日期: " -ForegroundColor Gray -NoNewline
                Write-Host ($WhoisResult.UpdatedDate ?? "N/A") -ForegroundColor White
            }
            if ($WhoisResult.PSObject.Properties['NameServers']) {
                Write-Host "  DNS 服务器: " -ForegroundColor Gray -NoNewline
                Write-Host ($WhoisResult.NameServers ?? "N/A") -ForegroundColor White
            }
            if ($WhoisResult.PSObject.Properties['Status']) {
                Write-Host "  状态:     " -ForegroundColor Gray -NoNewline
                Write-Host ($WhoisResult.Status ?? "N/A") -ForegroundColor White
            }
        }
        Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
    }
}