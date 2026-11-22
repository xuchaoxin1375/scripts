<#
TestLinks 模块:GitHub 镜像站可用性测试(曾与 Git.psm1 重复,现收敛到此,自包含数据源)。
原 Deploy/TestLinks.psm1 因目录名与模块名不一致无法被自动发现,现为规范模块目录。
#>
# 数据源 $GithubMirrors 与 Test-Links*/Get-AvailableGithubMirrors 曾在 Git.psm1 有重复定义,已收敛到此

# 镜像站数据源(从 Git.psm1 迁入,与测试函数同模块,自包含)
# 2026-11-22 本机实测(raw/git/archive/release,5s 超时;Release 前 256KiB 小样本):
# gh-proxy.org(约 109KB/s) / ghfast.top / ghfile.geekertao.top 四类可用;
# ghproxy.net / v4.gh-proxy.org / cors.isteed.cc 仅 raw。
# 已剔除:gh-proxy.com(403,转发层拒绝;首页仍 200) / cdn.crashmc.com(跨域重定向到 cdn.akaere.online) /
# gh.noki.icu(503) /
# gh.zwy.one(超时) / ghproxy.cxkpro.top(429) / git.yylx.win(超时) /
# gh.xxooo.cf(DNS) / ghproxy.cc(证书) / hub.gitmirror.com(DNS) /
# github.moeyy.xyz(停服) / gh.llkk.cc(超时) / ghproxy.link(返回 HTML) /
# slink.ltd(内容与源不一致) / mirror.ghproxy.com / cf.ghproxy.cc(SSL) /
# ghproxy.homeboyc.cn / gh.h233.eu.org(403) / github.akams.cn(404,非前缀式) /
# ghps.cc / github.ur1.fun(402) / gh.ddlc.top / gh.con.sh
# 新候选先用 Test-MirrorAvailability 或 Get-FastestGithubMirror 验证再入库;顺序即线性测试顺序(快的在前)
$global:github_mirror = "https://gh-proxy.org"
# Set-Variable -Name github-mirror -Value "https://gh-proxy.org"  -Scope Global

$GithubMirrors = @(

    # '' #空字符串收尾
)
$GithubMirrorsTest = @(

    # ''#收尾
)

$GithubMirrorsInString = @'
https://gh-proxy.org/,
https://ghfast.top/,
https://ghfile.geekertao.top/,
https://ghproxy.net/,
https://v4.gh-proxy.org/,
https://cors.isteed.cc/,
'@

$GithubMirrorsInString = $GithubMirrorsInString -replace '#.*', ' ' -replace '[",;\n\r]', ' ' -replace "'" , ' ' -replace '\s+', ' '

$GithubMirrorsInString = $GithubMirrorsInString -split ' ' #去重等操作留到后面一起处理

$GithubMirrors = $GithubMirrors + $GithubMirrorsTest + $GithubMirrorsInString
$GithubMirrors = $GithubMirrors | Where-Object { $_ }#移除空串
$GithubMirrors = $GithubMirrors | ForEach-Object { $_.trim('/') }#统一链接风格(去除末尾的`/`如果有的话)
$GithubMirrors = $GithubMirrors | Select-Object -Unique #移除重复条目(保序去重,顺序即线性测试顺序,快的在前;不要 Sort-Object 打乱)


function Test-LinksLinearly
{
    <# 
    .SYNOPSIS
    线性地(串行地)测试链接是否能够在指定时间内响应,为powershell5 设计
    .NOTES
    链接数量多的话会造成测试时间很长,尽量使用并行方案(Test-LinksParallel,pwsh7 与 5.1 都支持),
    或者考虑设置小的$timeoutSec=1
    #>
    [cmdletbinding(DefaultParameterSetName = 'First')]
    param (
        $Mirrors = $GithubMirrors,
        $TimeOutSec = 6,
        [parameter(ParameterSetName = 'First')]
        $First = 5,
        [parameter(ParameterSetName = 'All')]
        [Alias('Full')]
        [switch]
        $All
    )
    $availableMirrors = @()
    Write-Debug 'Test links linearly...'
    foreach ($mirror in $Mirrors)
    {
        # $Mirrors | ForEach-Object {
        # $mirror = $_

        # Write-Verbose "Testing $mirror..."
        if (Test-MirrorAvailability -Url $mirror -TimeoutSec $TimeOutSec)
        {
            Write-Verbose "$mirror is available "
            Write-Host "`t $mirror" -ForegroundColor Green
            # 插入到数组中(这里如果foreach用了-parallel,就会导致无法访问外部的$availableMirros)
            $availableMirrors += $mirror
        }
        else
        {
            Write-Verbose "$mirror is not available "
            Write-Host "`t $mirror " -ForegroundColor Red
        }

        if ($pscmdlet.ParameterSetName -eq 'First')
        {

            if (($availableMirrors.Count -ge $First))
            {
                break #在foreach-object中会直接停止函数的运行,而使用传统foreach则是正常的
            }
        }
    } 
    if ($availableMirrors.Count -eq 0)
    {
        Write-Warning 'all mirrors are timeout! but there may be some mirrors are available,try to choose one manually...'

        $availableMirrors = $Mirrors
    }
    return $availableMirrors
}

function Test-LinksConcurrently
{
    <#
    .SYNOPSIS
    用 runspace 池并发测试镜像可用性,为 Windows PowerShell 5.1 提供并行能力。
    .DESCRIPTION
    5.1 没有 ForEach-Object -Parallel,但 runspace 池在 5.1/7 都可用。
    每个 runspace 注入 Test-MirrorAvailability 的源码后独立探测,结果按原列表顺序返回。
    单个探测受 -TimeOutSec 约束;等待时再留 2 秒余量,超时即 Stop,避免个别站点拖住整体。
    #>
    [CmdletBinding()]
    param (
        $Mirrors = $GithubMirrors,
        $TimeOutSec = 6,
        $ThrottleLimits = 16
    )
    $probeSrc = ${function:Test-MirrorAvailability}.ToString()
    $limit = [Math]::Max(1, [int]$ThrottleLimits)
    $pool = [runspacefactory]::CreateRunspacePool(1, $limit)
    $jobs = @()
    try
    {
        $pool.Open()
        $index = 0
        foreach ($mirror in $Mirrors)
        {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript(@'
param($Mirror, $TimeOutSec, $ProbeSrc, $Index)
. ([scriptblock]::Create($ProbeSrc))
[pscustomobject]@{
    Index     = $Index
    Mirror    = $Mirror
    Available = [bool](Test-MirrorAvailability -Url $Mirror -TimeoutSec $TimeOutSec)
}
'@).AddArgument($mirror).AddArgument($TimeOutSec).AddArgument($probeSrc).AddArgument($index)
            $jobs += [pscustomobject]@{
                Handle = $ps.BeginInvoke()
                PS     = $ps
            }
            $index += 1
        }

        $results = @()
        # 单探测自身有 -TimeOutSec;整体再留 2 秒余量,超时直接 Stop,避免个别站点拖住整体
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeOutSec + 2)
        foreach ($job in $jobs)
        {
            $remainingMs = [int](($deadline - [DateTime]::UtcNow).TotalMilliseconds)
            $completed = $false
            if ($remainingMs -gt 0)
            {
                $completed = $job.Handle.AsyncWaitHandle.WaitOne($remainingMs)
            }
            if (-not $completed)
            {
                # 已完成的即使过了截止时间也要收结果,不能白白丢掉
                if ($job.Handle.IsCompleted)
                {
                    $completed = $true
                }
                else
                {
                    Write-Verbose 'Mirror probe timed out in runspace, skip it.'
                    try { $job.PS.Stop() } catch { }
                    continue
                }
            }
            try
            {
                $out = $job.PS.EndInvoke($job.Handle)
                foreach ($item in $out)
                {
                    if ($item -is [pscustomobject] -and $item.PSObject.Properties['Mirror'])
                    {
                        $results += $item
                    }
                }
            }
            catch
            {
                Write-Verbose "Mirror probe failed: $($_.Exception.Message)"
            }
            finally
            {
                $job.PS.Dispose()
            }
        }

        $availableMirrors = @()
        foreach ($item in ($results | Sort-Object Index))
        {
            if ($item.Available)
            {
                Write-Verbose "$($item.Mirror) is available "
                Write-Host "`t $($item.Mirror)" -ForegroundColor Green
                $availableMirrors += $item.Mirror
            }
            else
            {
                Write-Verbose "$($item.Mirror) is not available "
                Write-Host "`t $($item.Mirror) " -ForegroundColor Red
            }
        }
        return $availableMirrors
    }
    finally
    {
        foreach ($job in $jobs)
        {
            if ($job.PS)
            {
                try { $job.PS.Dispose() } catch { }
            }
        }
        try { $pool.Close() } catch { }
        try { $pool.Dispose() } catch { }
    }
}

function Test-LinksParallel
{
    <#
    .SYNOPSIS
    并行测试链接是否能够在指定时间内响应。
    .NOTES
    powershell 7+ 使用 ForEach-Object -Parallel;Windows PowerShell 5.1
    自动改走 runspace 池(Test-LinksConcurrently),两边都是并发探测。
    并行 runspace 看不到父作用域函数,这里用 $using: 把
    Test-MirrorAvailability 的定义注入进去,否则全部误判为不可用。
    #>
    [CmdletBinding()]
    param (
        $Mirrors = $GithubMirrors,
        $TimeOutSec = 6,
        $ThrottleLimits = 16
        # $First = 5
    )
    # 5.1 分流:ForEach-Object -Parallel 不可用,改走 runspace 池(仍然并发)
    if ($host.Version.Major -lt 7)
    {
        Write-Verbose 'PowerShell 5.1: use runspace pool for parallel mirror check.'
        return @(Test-LinksConcurrently -Mirrors $Mirrors -TimeOutSec $TimeOutSec -ThrottleLimits $ThrottleLimits)
    }
    Write-Debug 'Test links parallel...'
    # 检查镜像测试命令是否可用(断言存在,不污染成功流)
    if (-not (Get-Command Test-MirrorAvailability -ErrorAction Ignore))
    {
        throw 'Test-MirrorAvailability not found! Import TestLinks module first.'
    }
    $availableMirrors = @()
    # 为了能够让$TimeOutSec能够被传递到子进程,这里使用了$env:来扩大其作用域
    # $env:TimeOutSec = $TimeOutSec
    # powershell提供了更好的方式访问并行scriptblock外的变量,使用$using: 这个关键字
    #然而这个关键字引用的变量无法更改(只读),可以考虑用.Net线程安全容器,或者用$env:来实现共享局部环境变量
    # $Envbak = $env:StopLoop
    # $env:StopLoop = 0
    # 创建线程安全容器(队列)
    $mirs = [System.Collections.Concurrent.ConcurrentQueue[Object]]::new()
    # 并行 runspace 继承不了父作用域函数,把定义以字符串传进去再装上
    # (注:$using: 不能直接传 ScriptBlock,会报 "cannot be a script block",传字符串)
    $probeSrc = ${function:Test-MirrorAvailability}.ToString()
    # $mirs.Enqueue('First_Demo')
    # Write-Host $mirs
    # 并行执行链接测试
    $Mirrors | ForEach-Object -Parallel {
        # if ([int]$env:StopLoop)
        # {
        #     return
        # }
        # Write-verbose $_
        #引用外部变量,并且赋值给简化的临时变量,方便后续引用(直接在-Parallel中引用外部变量是不合期望的)
        $mirs = $using:mirs
        $TimeOutSec = $using:TimeOutSec
        ${function:Test-MirrorAvailability} = $using:probeSrc
        # $First = $using:First
        #  并行方案里用First参数指定前n个意义不大,而且会让代码变得复杂
        # Write-Verbose "mirs.cout=$($mirs.Count)" -Verbose
        # if ($mirs.Count -ge $First)
        # {
        #     # Write-Host $First
        #     Write-Verbose "The available links enough the $First !" -Verbose
        #     return
        # }
         

        $mirror = $_
        # Write-Debug "`$TimeOutSec=$env:TimeOutSec" -Debug #parallel 参数$DebugPreference无法起作用
        # 测试链接是否可用
        if (Test-MirrorAvailability -Url $mirror -TimeoutSec $TimeOutSec)
        {
            Write-Host "`t $_" -ForegroundColor Green
            # Write-Output $mirror

            #写入队列
            $mirs.Enqueue($mirror)
            # 查看$mirs队列长度
            # $mirs.Count, $mirs

        }
        else
        {
            Write-Verbose "$mirror is not available "
            Write-Host "`t $mirror." -ForegroundColor Red
        }

    } -ThrottleLimit $ThrottleLimits

    # 队列出队为数组(不要直接返回队列对象,调用方按数组索引取镜像)
    $availableMirrors = @($mirs.ToArray())
    if ($availableMirrors.Count -eq 0)
    {
        Write-Warning 'No mirrors are available!'
        return @()
    }
    return $availableMirrors
}




function Test-MirrorAvailability
{
    <#
    .SYNOPSIS
    测试指定链接是否在规定时间内相应
    .NOTES
    此函数主要用来辅助Test-LinksLinearly和Test-LinksParallel调用
    部分镜像站不支持 HEAD(回 502/403),HEAD 失败会再试一次 GET(只取根地址,不下载文件),
    两次都失败才判为不可用。
    .DESCRIPTION
    如果及时正确相应,将链接打印为绿色,否则打印为红色
    #>
    [CmdletBinding()]
    param (
        [string]$Url,
        $TimeoutSec = 15
    )

    $availability = $false
    try
    {
        # 使用 Invoke-WebRequest 检查可用性
        # 方案1:HEAD 轻量探测(部分镜像站不支持 HEAD,会回 502/403 之类)
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Head -TimeoutSec $TimeOutSec -ErrorAction Stop
        $availability = $response.StatusCode -eq 200
    }
    catch
    {
        $availability = $false
        # 超时/DNS/连接失败再试 GET 只是白等一倍时间;只有服务器明确回了非 200 才值得换 GET 重试
        $skipGet = $false
        $ex = $_.Exception
        while ($ex)
        {
            $typeName = $ex.GetType().FullName
            if (($ex -is [System.Net.WebException] -and $ex.Status -ne 'ProtocolError') -or
                $typeName -eq 'System.Threading.Tasks.TaskCanceledException' -or
                $typeName -eq 'System.Net.Http.HttpRequestException')
            {
                $skipGet = $true
                break
            }
            $ex = $ex.InnerException
        }
    }
    if (-not $availability -and -not $skipGet)
    {
        try
        {
            # 方案1补:HEAD 不通再试 GET(只探根地址,不下载文件)
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Get -TimeoutSec $TimeOutSec -ErrorAction Stop
            $availability = ($response.StatusCode -ge 200) -and ($response.StatusCode -lt 300)
        }
        catch
        {
            $availability = $false
        }
    }
    if ($VerbosePreference)
    {

        if ($availability)
        {

            Write-Host "Mirror $Url is available" -ForegroundColor Green
        }
        else
        {

            Write-Host "Mirror $Url is not available" -ForegroundColor Red
        }
    }
    return   $availability
}

function Test-GitRemoteUrl
{
    <#
    .SYNOPSIS
    用 git ls-remote 探测加速前缀的 git 传输是否可用,带超时。
    .DESCRIPTION
    镜像首页或 raw 可用不代表 git 传输可用;这里直接请求目标仓库的 refs。
    超时或非零退出都返回 $false,不抛。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$TimeoutSec = 5
    )
    $out = [System.IO.Path]::GetTempFileName()
    $err = [System.IO.Path]::GetTempFileName()
    $oldPrompt = $env:GIT_TERMINAL_PROMPT
    try
    {
        $env:GIT_TERMINAL_PROMPT = '0'
        $p = Start-Process -FilePath 'git' -ArgumentList @('ls-remote', '--heads', $Url) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $p.WaitForExit($TimeoutSec * 1000))
        {
            try { $p.Kill() } catch { Write-Verbose "结束超时的 git 进程失败：$($_.Exception.Message)" }
            return $false
        }
        if ($p.ExitCode -ne 0 -or -not ((Get-Item -LiteralPath $out -ErrorAction SilentlyContinue).Length -gt 0)) { return $false }
        # 跨域重定向不当作可用:目标仓库路径会被转到未核验的第三方域名
        $errText = Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue
        if ($errText -match 'redirecting to (\S+)')
        {
            try
            {
                if (([uri]$matches[1]).Host -ne ([uri]$Url).Host) { return $false }
            }
            catch { return $false }
        }
        return $true
    }
    catch
    {
        return $false
    }
    finally
    {
        $env:GIT_TERMINAL_PROMPT = $oldPrompt
        Remove-Item -LiteralPath @($out, $err) -ErrorAction SilentlyContinue
    }
}

function Get-GithubMirrorCandidates
{
    <#
    .SYNOPSIS
    返回本次要探测的镜像候选:显式参数 > $env:PsGithubMirrorCandidates > 内置列表。
    .DESCRIPTION
    空字符串表示直连,调用方按空前缀处理;顺序即优先级,不做去重或排序。
    #>
    [CmdletBinding()]
    param(
        [string[]]$Mirrors
    )
    if ($Mirrors -and @($Mirrors).Count -gt 0) { return @($Mirrors) }
    if (-not [string]::IsNullOrWhiteSpace($env:PsGithubMirrorCandidates))
    {
        return @($env:PsGithubMirrorCandidates -split '[,;\s]+' | Where-Object { $_ })
    }
    return @($GithubMirrors)
}

function Get-FastestGithubMirror
{
    <#
    .SYNOPSIS
    按 git 传输的响应速度挑选镜像,结果在模块会话内缓存。
    .DESCRIPTION
    逐候选运行 git ls-remote --heads 计时;只有退出码 0 且有 refs 才算可用,
    超时与 HTTP 错误都不计入。$env:PsGithubMirror 设置时
    直接返回它,不探测。返回最快的前缀;全部不可用时返回 ''(直连)。
    .EXAMPLE
    Get-FastestGithubMirror -Detailed
    #>
    [CmdletBinding()]
    param(
        [string[]]$Mirrors,
        [string]$ProbeRepo = 'https://github.com/octocat/Hello-World.git',
        [int]$TimeoutSec = 5,
        [int]$CacheMinutes = 10,
        [int]$MaxCandidates = 4,
        [switch]$Force,
        [switch]$Detailed
    )
    if (-not [string]::IsNullOrWhiteSpace($env:PsGithubMirror))
    {
        $fixed = ([string]$env:PsGithubMirror).TrimEnd('/')
        if ($Detailed) { return [pscustomobject]@{ Mirror = $fixed; Source = 'env'; Results = @() } }
        return $fixed
    }
    if (-not $Force -and $null -ne $script:FastestMirrorCache -and ((Get-Date) - $script:FastestMirrorCacheAt).TotalMinutes -lt $CacheMinutes)
    {
        if ($Detailed) { return [pscustomobject]@{ Mirror = $script:FastestMirrorCache; Source = 'cache'; Results = @() } }
        return $script:FastestMirrorCache
    }
    $candidates = @(Get-GithubMirrorCandidates -Mirrors $Mirrors | Select-Object -First $MaxCandidates)
    $results = foreach ($candidate in $candidates)
    {
        $mirror = ([string]$candidate).TrimEnd('/')
        if (-not $mirror) { continue }
        $url = "$mirror/$ProbeRepo"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $ok = Test-GitRemoteUrl -Url $url -TimeoutSec $TimeoutSec
        $sw.Stop()
        [pscustomobject]@{ Mirror = $mirror; Ok = [bool]$ok; Milliseconds = $sw.ElapsedMilliseconds }
    }
    $best = $results | Where-Object { $_.Ok } | Sort-Object Milliseconds | Select-Object -First 1
    $mirror = if ($best) { $best.Mirror } else { '' }
    $script:FastestMirrorCache = $mirror
    $script:FastestMirrorCacheAt = Get-Date
    if ($Detailed) { return [pscustomobject]@{ Mirror = $mirror; Source = 'probe'; Results = @($results); Checked = Get-Date } }
    return $mirror
}

function Get-AvailableGithubMirrors
{
    <#
    .SYNOPSIS
    列出流行的或可能可用的 GitHub 加速镜像站。
    列表中的镜像站可能会过期，可用性不做稳定性和可用性保证。

    .DESCRIPTION
    这里采用了多线程的方式来加速对不同镜像链接的可用性进行检查
    并且更容易获取其中相应最快的可用的镜像站,这是通过串行检查无法直接达到的效果
    .EXAMPLE
    

    .NOTES
    推荐使用 aria2 等多线程下载工具来加速下载，让镜像加速效果更加明显。
 
    .LINK
    # 镜像站搜集和参考
    https://github.com/hunshcn/gh-proxy/issues/116
    # 内置列表 2026-09-24 本机实测,新候选先用 Test-MirrorAvailability 验证再入库
    #>
    [CmdletBinding()]
    param(
        $Mirrors = $GithubMirrors,
        $ThrottleLimits = 16,
        $TimeOutSec = 6,
        [switch]$ListView,
        [switch]$PassThru,
        [switch]$SkipCheckAvailability,
        # 是否启用串行地试探镜像可访问性(默认是并行试探)
        # [parameter(ParameterSetName = 'Serial')]
        [switch][Alias('Serial')]$Linearly,
        # [parameter(ParameterSetName = 'Serial')]
        $First = 5
    )
    
    Write-Host 'Checking available Mirrors...'
    $availableMirrors = $Mirrors
    # 检查可用的镜像列表
    if (!$SkipCheckAvailability)
    {
        # 默认并行测试(pwsh7 走 ForEach-Object -Parallel,5.1 走 runspace 池)
        if ($Linearly )
        {
            #简单起见,这里仅简单调用 Test-LinksLinearly的Frist参数集语法,而不做分支判断
            $availableMirrors = Test-LinksLinearly -Mirrors $Mirrors -TimeOutSec $TimeOutSec -First $First -Verbose:$VerbosePreference
        }
        else
        {

            $availableMirrors = Test-LinksParallel -Mirrors $Mirrors -TimeOutSec $TimeOutSec -ThrottleLimits $ThrottleLimits -Verbose:$VerbosePreference
        }
    }
    # 两条测试路径都没拿到可用镜像时,回退到原始列表(与串行路径行为一致),静默流程永不抛
    if (-not @($availableMirrors).Count)
    {
        Write-Warning 'all mirrors are timeout! but there may be some mirrors are available,try to choose one manually...'
        $availableMirrors = $Mirrors
    }

    # Start-Sleep $TimeOutSec
    # 显示可用的镜像
    Write-Host "`nAvailable Mirrors:"
    # 空白镜像保留(作为返回值)
    $availableMirrors = @('') + $availableMirrors

    # 按序号列举展示
    Write-Host ' 0: Use No Mirror' -NoNewline
    $index = 1
    $availableMirrors | ForEach-Object {
        # $index = [array]::IndexOf($availableMirrors, $_)
        # if($availableMirrors[$index] -eq ""){continue}
        if ($_.Trim())
        {

            Write-Host " ${index}: $_" -NoNewline
            $index += 1
        }
   
        
        Write-Host ''
    }

    if ($PassThru)
    {
        return $availableMirrors
    }
}
