
function Get-LatestWindowsTerminalLink
{
    <# 
    .SYNOPSIS
    从github获取windows terminal 最新稳定版下载链接(下载的是安装包,msixbundle格式的),次函数可能有时效性
    .EXAMPLE
    $link = Get-LatestWindowsTerminalLink
    Get-SpeedUpUri $link
    #输出的链接用用下载器加速下载(IDM或者浏览器自带下载器)
#>
    param(
        [switch]$speedUpLink
    )
    # Define the GitHub API URL for the Windows Terminal repository
    $apiUrl = 'https://api.github.com/repos/microsoft/terminal/releases'

    # Send a request to the GitHub API to get the releases
    $response = Invoke-RestMethod -Uri $apiUrl -Headers @{'User-Agent' = 'PowerShell' }

    # Filter out pre-release versions and sort releases by the created date
    $stableReleases = $response | Where-Object { -not $_.prerelease } | Sort-Object { $_.created_at } -Descending

    # Get the latest stable release
    $latestRelease = $stableReleases[0]

    # Find the asset that is an .msixbundle
    $asset = $latestRelease.assets | Where-Object { $_.browser_download_url -like '*.msixbundle' }

    if ($asset)
    {
        # Output the download URL
        return $asset.browser_download_url
    }
    else
    {
        Write-Error 'No .msixbundle asset found in the latest stable release.'
    }
    $link = Get-LatestWindowsTerminalLink
    if ($speedUpLink)
    {
        $link = Get-SpeedUpUri $link
    }
    return $link
}


function Install-Scoop
{
    
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    # or shorter

    curl_b -useb get.scoop.sh | Invoke-Expression
    Write-Output 'if failed ,please try the proxy to reconnect the https://get.scoop'
}


function Push-ByScp
{
    <# 
.SYNOPSIS
使用scp命令上传文件到服务器


#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [alias("HostName")]
        $Server,

        [alias("ScpUser")]
        $User = 'root',
        [alias("Path")]
        $SourcePath,

        [alias('TargetPath', 'Target')]
        $DestinationPath = $env:DF_SERVER1
    )
    $expression = "scp -r '$SourcePath' '$User@${Server}:$DestinationPath'"
    Write-Host $expression 
    # Pause
    if($PSCmdlet.ShouldProcess($server, $expression))
    {

        Invoke-Expression "$expression"
    }
    
}
function scp_to_ali
{
    <# 
    .Example
    scp_to_Ali .\pets.txt ~
    _____
    PS C:\repos\blogs\linuxCommandsTutor> scp_to_Ali .\pets.txt ~
    cxxu@12x.xx.x.7's password:
    pets.txt
    #>
    param (
        $source,
        $tarPath_opt = '~',
        $options_opt = '-r'
    )
    scp $options_opt $source "$cxxuAli`:$tarPath_opt" 
}
function scp_from_ali

{
    param(
        $from_user_hostname = "cxxu@$AliCloudServerIP",
        $source_opt = '~/linuxShellScripts',
        $Destination_opt = $env:desktop

    )
    # 可以不用引号/加号,直接拼接变量为字符串!
    scp -r $from_user_hostname`:$source_opt $Destination_opt
}
function Copy-ItemWithVerbose
{
    [CmdletBinding(DefaultParameterSetName = 'Path', SupportsShouldProcess = $true)]
    param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Path')]
        [Alias('FullName')]
        [string[]]$Path,

        [Parameter(Position = 1, Mandatory = $true)]
        [string]$Destination,

        [switch]$Recurse,
        [switch]$Force
    )

    process
    {
        foreach ($item in $Path)
        {
            if ($PSCmdlet.ShouldProcess($item, "Copy to $Destination"))
            {
                Copy-Item -Path $item -Destination $Destination -Recurse:$Recurse -Force:$Force -Verbose
            }
        }
    }
}



function predictNo
{
    param (
        
    )
    Set-PSReadLineOption -PredictionSource None
}

function tree_pwsh
{
    # Closure function
    <# 
    .synopsis
    本函数支持遍历目录和文件
    也可以选择仅遍历目录而部列出文件
    通过缩进来表示嵌套层次关系
    支持指定最大遍历深度;指定为0时,表示不限制深度
    .example
    recurseClosure -traverseType d -maxDepth 3

    recurseClosure -traverseType a -maxDepth 3 -path C:\repos\scripts\linuxShellScripts\
    排除关键字示例(可以修改-eq为-like / -match 来支持通配符或正则表达式)
    recurseTree -exclude "node_modules"  -maxDepth 0 |sls -Pattern "Rand.*"
    #>

    # 参数置顶原则
    param(
        $traverseType = '',
        $path = './',
        $maxDepth = '2',
        $exclude = ''
    )
    
    $depth = 1
    $times = 0
    function listRecurse
    {
        <# 遍历所有子目录 #>
        param(
            $traverseType = '',
            $path = ''
        )
        # Write-Output "`tpath=$path"
        if ($traverseType -eq 'd')
        {
            $lst = (Get-ChildItem -Directory $path)
        }
        else
        {
            $lst = (Get-ChildItem $path)

        }

        # 子目录数目len
        $len = $lst.Length
        $times++

        #每一层处理都是都是一重循环O(n)
    
        # 遍历子目录
        <# 注意需要添加对文件的判断,否则在对文件调用本函数的时候,会陷入死循环(无法进入深层目录) #>
        $lst | ForEach-Object {
            $len--
            # Write-Output "`t`t remain times :len=$len";
            if ($_.BaseName -like $exclude)
            {
                # pass it
            }
            else
            {

                # 打印每个子目录及其深度
                # 无树干的前缀字符串(简洁版)
                # $indent = "`t" * ($depth - 1)
                # 如果想要画出所有的枝干,需要在intend这段字符串做改进(不单单是合适数量的制表符.)
                # 总之,每一行可能有多个`|`:第n层的条目,需要有n条树干线(而且,同一行的内容只能够一次性打印完,)
                # 所以,我们应该计算并安排好每一行的前缀字符串(树干线)

                # 带树干的字符串:│ ├ ─  └ ─ |
                $indent_tree = "│`t" * ($depth - 1) + '│'
                # 打印路径
                # $pathNameRelative = $_.baseName
                $pathNameRelative = $_.Name
                Write-Output "$indent_tree`──($depth)$($pathNameRelative)"

                if ((Get-Item $_) -is [system.io.directoryinfo] )
                {
                    # 打印树干
                    # 其实还要考虑要求打印的深度的截至
                    if (@(Get-ChildItem $_).Count -gt 0  )
                    {
                        # Write-Output @(Get-ChildItem $_).Count
                        # $branch = '|' + "`t" * ($depth - 1) + '  \____.'
                        $branch = $indent_tree + '  ├────'
                        # $branch = $indent_tree 

                        if ($depth -eq $maxDepth)

                        {
                            <# Action to perform if the condition is true #>
                            $branch += '......'
                        }
                        $branch
                    }

                    $depth++
                    # write
                    # 对子目录继续深挖,(做相同的调用)
                    if ($depth -le $maxDepth -or $maxDepth -eq 0)
                    {
                        listRecurse -path $_.FullName -traverseType $traverseType
                    }
                    $depth--
                }
                # Write-Output "$depth"
                # Start-Sleep -Milliseconds 1000
            }
        } 
    }   

    listRecurse -traverseType $traverseType -path $path
    # listRecurse

}
function tr_py
{
    <# don't place any other statments before the param() #>
    param (
        $dirName = '.\',
        $depth = 1
    )
    EnvironmentRequireTips
    py $scripts\pythonScripts\tree_pyScript.py $dirName $depth
    
}
function mvExcludeFolder
{
    <# 
    .Example
    ls *pic* |foreach {if ($_.Name -ne "picturebeds") {mv -v $_ .\pictureBeds\ }}
     #>
    param(
        $pattern,
        $target_excludeDir
    )
    Get-ChildItem $pattern -Exclude $target_excludeDir | Move-Item -Verbose -Destination $target_excludeDir
    # | ForEach-Object { if ($_.Name -ne $target_excludeDir) { Move-Item -v $_ $target_excludeDir } }
}

function Register-PsUxLazyLoad
{
    <#
    .SYNOPSIS
    体验件延迟加载:OnIdle 装 PSFzf(Ctrl+T/R)、zoxide(缓存)与自研命令名 predictor,注册即返回,启动零开销。
    .DESCRIPTION
    默认启用;$env:PsFzf/$env:PsZoxide 置 'False'/'0'/'No'/'Off' 可各关一个;
    -Now 立即执行(测试/非 idle 主机用,不受重定向门限制)。Tab 与预测补全都不动。
    .EXAMPLE
    Register-PsUxLazyLoad -Now
    #>
    [CmdletBinding()]
    param(
        [switch]$Now
    )
    $loadAction = {
        # 已触发即摘掉自己。用 $global: 标记位而不用 try/catch 探路:
        # terminating 错误抛出即进 $Error 记账,catch 只能止显示止不住记账。
        if ($global:PsUxOnIdleRegistered)
        {
            $global:PsUxOnIdleRegistered = $false
            try { Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction Stop } catch { }
        }
        # PSFzf:只接管 Ctrl+T(文件)/Ctrl+R(历史),Tab 留给 MenuComplete
        if ($env:PsFzf -notmatch '^(False|0|No|Off)$' -and (Get-Module -ListAvailable PSFzf))
        {
            # -Global:函数内 import 默认装成嵌套模块(Get-Module 列不出),强制顶层
            Import-Module PSFzf -Global -ErrorAction SilentlyContinue
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -ErrorAction SilentlyContinue
        }
        # 自研命令名 predictor(模糊+严格通配,import 时建表约百毫秒,放 idle 里无感)
        # 用它不用 CompletionPredictor 补命令名:后者源码级跳过 CommandName token(见 §19)
        # 守护进程用不上 predictor:置 $env:PsPredictor='False' 即跳过(开关风格同 PsFzf/PsZoxide);
        # 守护启动链(Start-StartupBgProcesses/定时任务)负责置位,交互会话默认开启
        # dll 外置($HOME/.cxxu/bin):仓库版从不被加载→git pull 永不撞锁;
        # 入口只静默装载(不对比不警告,旧版也照用):版本检查/同步全收归手动 Sync-CxxuPredictor
        # (旧逻辑每次入口算哈希+试图同步,被咬住就 Warning 刷屏,现默认关闭);psd1 已去 RootModule,
        # 按名装不出 predictor,必须走这里
        if ($env:PsPredictor -notmatch '^(False|0|No|Off)$')
        {
            $cxxuLiveDll = Join-Path (Join-Path (Join-Path $HOME '.cxxu') 'bin') 'CxxuPredictor.dll'
            if (Test-Path -LiteralPath $cxxuLiveDll)
            {
                # 按路径装载(-Global 防嵌套)
                Import-Module $cxxuLiveDll -Global -ErrorAction SilentlyContinue
            }
        }
        # zoxide:init 输出缓存到文件,只有二进制更新才重建(仿 conda 缓存套路)
        if ($env:PsZoxide -notmatch '^(False|0|No|Off)$')
        {
            $zoxideBin = (Get-Command zoxide -ErrorAction SilentlyContinue).Source
            if ($zoxideBin)
            {
                $cache = Join-Path $HOME '.zoxide_init_cache.ps1'
                if ((-not (Test-Path -LiteralPath $cache)) -or
                    ((Get-Item -LiteralPath $zoxideBin).LastWriteTimeUtc -gt (Get-Item -LiteralPath $cache).LastWriteTimeUtc))
                {
                    (& $zoxideBin init powershell | Out-String) | Set-Content -LiteralPath $cache
                }
                . $cache | Out-Null
            }
        }
    }
    if ($Now)
    {
        & $loadAction | Out-Null
        return
    }
    # 重定向下(agent/CI/管道)没有交互,不注册(显式 -Now 不受此限)
    $consoleInteractive = try { -not [Console]::IsOutputRedirected } catch { $false }
    if (-not $consoleInteractive) { return }
    if (($env:PsFzf -match '^(False|0|No|Off)$') -and ($env:PsZoxide -match '^(False|0|No|Off)$'))
    {
        return
    }
    if ($global:PsUxOnIdleRegistered) { return }
    Register-EngineEvent PowerShell.OnIdle -Action $loadAction | Out-Null
    $global:PsUxOnIdleRegistered = $true
}
function Sync-CxxuPredictor
{
    <#
    .SYNOPSIS
    手动同步 CxxuPredictor 活件:仓库源 dll → ~/.cxxu/bin(按哈希对比,不同才拷)。
    .DESCRIPTION
    入口 loader 只静默装载(旧版照用,无警告),版本检查/同步全靠本命令手动跑。
    活件被其它 pwsh 咬住拷不过去:默认给手动步骤;-Force 关其它会话后重试(变量会丢,只给确信的人用)。
    同步后当前会话内存里还是旧代码(.NET 程序集不随模块卸载),重开终端才生效。
    .EXAMPLE
    Sync-CxxuPredictor
    .EXAMPLE
    Sync-CxxuPredictor -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 活件被咬住时:关其它 pwsh 会话后重试(变量会丢;重定向拒绝)
        [switch]$Force
    )
    $repoDll = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'CxxuPredictor') 'CxxuPredictor.dll'
    $liveDll = Join-Path (Join-Path (Join-Path $HOME '.cxxu') 'bin') 'CxxuPredictor.dll'
    if (-not (Test-Path -LiteralPath $repoDll))
    {
        Write-Warning "仓库无源 dll($repoDll):先确认仓库状态。"
        return
    }
    $liveDir = Split-Path $liveDll -Parent
    if (-not (Test-Path -LiteralPath $liveDir)) { New-Item -ItemType Directory -Path $liveDir -Force | Out-Null }
    $repoHash = (Get-FileHash -LiteralPath $repoDll -Algorithm SHA256).Hash.Substring(0, 8)
    if (Test-Path -LiteralPath $liveDll)
    {
        $liveHash = (Get-FileHash -LiteralPath $liveDll -Algorithm SHA256).Hash.Substring(0, 8)
        if ($repoHash -eq $liveHash)
        {
            Write-Host "活件已是最新[$repoHash],无事可做。"
            return
        }
    }
    else
    {
        $liveHash = '(无活件)'
    }
    try
    {
        Copy-Item -LiteralPath $repoDll -Destination $liveDll -Force -ErrorAction Stop
        Write-Host "活件已同步($liveHash → $repoHash):当前会话内存仍是旧代码,重开终端生效。"
    }
    catch
    {
        if (-not $Force)
        {
            Write-Warning "活件被咬住拷不过去(其它 pwsh 正用着旧版):先关其它 pwsh 再跑本命令,或加 -Force 代劳;本次照用旧版。"
            return
        }
        if ([Console]::IsOutputRedirected)
        {
            Write-Warning '-Force 拒绝在重定向/agent 会话里关其它会话:请交互运行。'
            return
        }
        if ($PSCmdlet.ShouldProcess('其它 pwsh 会话(含未保存变量)', '全部关闭后重试同步(变量会丢失!)'))
        {
            Get-Process pwsh -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
            try
            {
                Copy-Item -LiteralPath $repoDll -Destination $liveDll -Force -ErrorAction Stop
                Write-Host "活件已同步($liveHash → $repoHash):当前会话内存仍是旧代码,重开终端生效。"
            }
            catch
            {
                Write-Warning '重试仍失败:看上面错误处理,本次照用旧版。'
            }
        }
    }
}