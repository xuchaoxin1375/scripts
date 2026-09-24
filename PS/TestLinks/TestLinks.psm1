<#
TestLinks 模块:GitHub 镜像站可用性测试(曾与 Git.psm1 重复,现收敛到此,自包含数据源)。
原 Deploy/TestLinks.psm1 因目录名与模块名不一致无法被自动发现,现为规范模块目录。
#>
# 数据源 $GithubMirrors 与 Test-Links*/Get-AvailableGithubMirrors 曾在 Git.psm1 有重复定义,已收敛到此

# 镜像站数据源(从 Git.psm1 迁入,与测试函数同模块,自包含)
# 2026-09-24 本机实测可用(取 readme.md 与 TestLinks.psm1 的 raw 文件,12~15s 超时):
# gh-proxy.com / gh-proxy.org / v4.gh-proxy.org / ghproxy.net / ghfast.top /
# ghproxy.cxkpro.top / cors.isteed.cc / ghfile.geekertao.top / gh.noki.icu /
# gh.xxooo.cf / gh.zwy.one / git.yylx.win / cdn.crashmc.com
# 已剔除:ghproxy.cc / mirror.ghproxy.com / github.moeyy.xyz(停服) /
# sciproxy.com / cf.ghproxy.cc(SSL 失败) / gh.llkk.cc(超时) /
# ghproxy.homeboyc.cn / gh.h233.eu.org(403) / github.akams.cn(404,非前缀式) /
# hub.gitmirror.com(DNS) / ghps.cc / github.ur1.fun(402) /
# gh.ddlc.top / gh.con.sh / slink.ltd(返回内容与源文件不一致,不可靠)
# 新候选先用 Test-MirrorAvailability 逐个验证再入库;顺序即线性测试顺序(快的在前)
$global:github_mirror = "https://gh-proxy.com"
# Set-Variable -Name github-mirror -Value "https://gh-proxy.com"  -Scope Global

$GithubMirrors = @(

    # '' #空字符串收尾
)
$GithubMirrorsTest = @(

    # ''#收尾
)

$GithubMirrorsInString = @'
https://gh-proxy.com/,
https://gh-proxy.org/,
https://v4.gh-proxy.org/,
https://ghproxy.net/,
https://ghfast.top/,
https://ghproxy.cxkpro.top/,
https://cors.isteed.cc/,
https://ghfile.geekertao.top/,
https://gh.noki.icu/,
https://gh.xxooo.cf/,
https://gh.zwy.one/,
https://git.yylx.win/,
https://cdn.crashmc.com/',
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
    链接数量多的话会造成测试时间很长,尽量使用并行方案(pwsh7),或者考虑设置小的$timeoutSec=1
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

function Test-LinksParallel
{
    <#
    .SYNOPSIS
    为powershell 7+设计的并行测试链接是否能够在指定时间内响应
    .NOTES
    powershell5 没有 ForEach-Object -Parallel,自动退居二线走串行测试
    (与 Test-LinksLinearly -All 等价,调用方无需再分支)。
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
    # 5.1 先分流:退居二线走串行(此处 Write-Debug 不带 -Debug,5.1 非交互下 -Debug 会抛)
    if ($host.Version.Major -lt 7)
    {
        Write-Warning 'PowerShell 7 or higher is required for parallel foreach! Falling back to linear test...'
        return @(Test-LinksLinearly -Mirrors $Mirrors -TimeOutSec $TimeOutSec -All)
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
    }
    if (-not $availability)
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
        $psVersion = $host.Version.Major 
        # 默认尝试并行测试
        if ($psVersion -lt 7 -and !$Linearly)
        {

            Write-Host 'PowerShell 7 or higher is required to run parallel foreach!' -ForegroundColor Red
            Write-Host 'Testing Links Linearly...'
            $Linearly = $true
        }
        if ($Linearly ) #-or $PSVersion -lt 7
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
