
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
    $expression = "scp -v -r '$SourcePath' '$User@${Server}:$DestinationPath'"
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
        # dll 外置并排版本(~/.cxxu/bin/<哈希>/CxxuPredictor.dll + current.txt 指针;
        # 文件名保持 CxxuPredictor.dll 不变,模块名才正确;目录按版本隔离):
        # 仓库源从不被加载→git pull 不受锁限制;新版本只新增目录、从不覆盖旧文件→复制不受锁限制;
        # 入口只按指针静默装载(旧版照常使用,无警告);psd1 已去 RootModule,按名装不出 predictor,必须走这里
        if ($env:PsPredictor -notmatch '^(False|0|No|Off)$')
        {
            $cxxuBinDir = Join-Path (Join-Path $HOME '.cxxu') 'bin'
            $cxxuLiveDll = $null
            $ptrFile = Join-Path $cxxuBinDir 'current.txt'
            if (Test-Path -LiteralPath $ptrFile)
            {
                $hashDir = Get-Content -LiteralPath $ptrFile -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($hashDir)
                {
                    $cand = Join-Path (Join-Path $cxxuBinDir "$hashDir".Trim()) 'CxxuPredictor.dll'
                    if (Test-Path -LiteralPath $cand) { $cxxuLiveDll = $cand }
                }
            }
            if (-not $cxxuLiveDll)
            {
                # 指针缺失或损坏:退回最新的版本目录,再退回旧单文件(迁移兼容)
                $best = Get-ChildItem -LiteralPath $cxxuBinDir -Directory -ErrorAction SilentlyContinue |
                    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'CxxuPredictor.dll') } |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($best) { $cxxuLiveDll = Join-Path $best.FullName 'CxxuPredictor.dll' }
                else
                {
                    $legacy = Join-Path $cxxuBinDir 'CxxuPredictor.dll'
                    if (Test-Path -LiteralPath $legacy) { $cxxuLiveDll = $legacy }
                }
            }
            if ($cxxuLiveDll)
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
    同步或卸载 CxxuPredictor 活件。
    .DESCRIPTION
    活件采用并排版本存放（~/.cxxu/bin/<哈希>/CxxuPredictor.dll，文件名不变以保证模块名正确），
    由 current.txt 指针指定当前版本目录。同步时只新增目录、从不覆盖旧文件，
    因此不受文件锁限制，在任何会话中执行都成功；入口 loader 按指针装载，
    旧会话继续使用旧版本，新会话使用新版本。
    本命令适用于：首次安装时生成活件、手动修复不一致、本地重新编译后分发、卸载活件（-Uninstall）。
    日常版本更新请使用 Update-ReposesConfiged（拉取后自动调用本命令同步）。
    生效条件：同步完成后必须重新打开终端，当前会话内存中的旧代码才会替换
    （.NET 程序集不随模块卸载而卸载）。
    .EXAMPLE
    Sync-CxxuPredictor
    .EXAMPLE
    Sync-CxxuPredictor -Uninstall
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 卸载活件：删除指针与全部版本文件（被会话锁定的文件删不掉，会报告并给出路）
        [switch]$Uninstall,
        # 卸载时若有其他会话锁定文件：先关闭其他会话再重试（未保存的变量会丢失；重定向会话中拒绝执行）
        [switch]$Force
    )
    $repoDll = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'CxxuPredictor') 'CxxuPredictor.dll'
    $binDir = Join-Path (Join-Path $HOME '.cxxu') 'bin'
    $ptrFile = Join-Path $binDir 'current.txt'
    if ($Uninstall)
    {
        $vers = @(Get-ChildItem -LiteralPath $binDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'CxxuPredictor.dll') })
        $legacyDll = Join-Path $binDir 'CxxuPredictor.dll'
        if (-not $vers.Count -and -not (Test-Path -LiteralPath $legacyDll) -and -not (Test-Path -LiteralPath $ptrFile))
        {
            Write-Host '活件不存在，无需卸载。'
            return
        }
        if ($PSCmdlet.ShouldProcess($binDir, '删除指针与全部活件版本'))
        {
            if ($Force)
            {
                if ([Console]::IsOutputRedirected)
                {
                    Write-Warning '-Force 不能在重定向会话（agent/CI/管道）中关闭其他会话，请在交互终端中执行。'
                    return
                }
                if ($PSCmdlet.ShouldProcess('其他 pwsh 会话（含未保存的变量）', '全部关闭后重试删除（变量会丢失）'))
                {
                    Get-Process pwsh -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
                        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                    }
                }
                else { return }
            }
            $left = @()
            foreach ($d in $vers) { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue; if (Test-Path -LiteralPath $d.FullName) { $left += $d.Name } }
            Remove-Item -LiteralPath $legacyDll -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $legacyDll) { $left += 'CxxuPredictor.dll' }
            Remove-Item -LiteralPath $ptrFile -Force -ErrorAction SilentlyContinue
            Remove-Module CxxuPredictor -ErrorAction SilentlyContinue
            if ($left.Count)
            {
                Write-Warning "以下版本仍被会话锁定，未能删除：$($left -join ', ')。请关闭持有会话后重新执行，或换用干净会话（裸 pwsh -NoProfile）删除。"
            }
            else { Write-Host '活件已删除。若彻底停用，请将 $env:PsPredictor 持久化为 False，否则下次同步或更新时活件会被重新安装。' }
        }
        return
    }
    if (-not (Test-Path -LiteralPath $repoDll))
    {
        Write-Warning "仓库源不存在($repoDll)，请先确认仓库状态。"
        return
    }
    $repoHash = (Get-FileHash -LiteralPath $repoDll -Algorithm SHA256).Hash.Substring(0, 8)
    $targetDir = Join-Path $binDir $repoHash
    $targetPath = Join-Path $targetDir 'CxxuPredictor.dll'
    $pointed = Get-Content -LiteralPath $ptrFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pointed) { $pointed = "$pointed".Trim() } else { $pointed = '' }
    if (($pointed -eq $repoHash) -and (Test-Path -LiteralPath $targetPath))
    {
        Write-Host "活件已是最新版本[$repoHash]，无需同步。"
        return
    }
    if ($PSCmdlet.ShouldProcess($targetPath, "新增活件版本[$repoHash]并更新指针"))
    {
        if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        # 同哈希即同内容：目录已存在则跳过复制（被锁定的旧版本从不触碰）
        if (-not (Test-Path -LiteralPath $targetPath)) { Copy-Item -LiteralPath $repoDll -Destination $targetPath -Force -ErrorAction Stop }
        $tmpPtr = "$ptrFile.tmp"
        Set-Content -LiteralPath $tmpPtr -Value $repoHash -Encoding utf8NoBOM -NoNewline
        Move-Item -LiteralPath $tmpPtr -Destination $ptrFile -Force
        # 回收非当前版本目录与旧扁平文件（被锁定的跳过，下次再收）
        Get-ChildItem -LiteralPath $binDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $repoHash } | ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        Get-ChildItem -LiteralPath $binDir -Filter 'CxxuPredictor.*.dll' -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
        Write-Host "活件已同步[$repoHash]。当前会话内存中仍是旧代码，请重新打开终端使新代码生效。"
    }
}