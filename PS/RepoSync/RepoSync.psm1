<#
RepoSync 模块:多仓库同步/开发环境同步(推送/更新/脚手架)。
从 Basic.psm1 迁入: Basic 只留通用小工具与查询,仓库同步类归此模块;
调用方命令名不变(自动发现同名模块);B 档 5.1 可用。
#>

function Install-SubModules
{
    foreach ($s in @('backup', 'deploy', 'wifi'))
    {
        $expression = "$PSScriptRoot\$s.ps1"
        . $expression
        Write-Host "$expression"
    }
}


function update_functions
{

    <# 
    .SYNOPSIS
    # 刷新Basic的函数集
    #>

    
    # 使用import-module命令导入模块来刷新,由于上下文的问题,必须要在shell中直接调用,函数调用不能达到效果
    # Import-Module Basic -Force
    #事实上,.psm1中有的东西错误会被跳过执行,并且不会报错;而.ps1中的东西如果有错,直接无法运行,例如将函数function关键字写错了,后者报错,前者不报错;而在使用import-Module显式导入 .psm1的模块时,如果模块中有错误代码,就会报错
    
    #>
    
    #psm1模块无法像.ps1一样直接在powershell中运行(虽然可以创建一个硬链接别名后缀该为.ps1),但是仍然有上下文问题
    # . $scripts\PS\Basic\update_functions.ps1

    #不知为何,刷新后提示符样式变为PS,这里考虑用posh手动美化样式
    Write-Host '👺run' -NoNewline
    Write-Host ' Import-Module Basic -Force '-NoNewline -BackgroundColor Green
    Write-Host "manully please!`n"
}





function vscodeExtListExport
{
    param(
        $fileName = "vscode_list_extt$(Get-Date)"
    )
    code --list-extensions >> $fileName
}

function Push-ReposesConfiged
{
    <# 
    .SYNOPSIS
    将常用仓库,比如笔记和脚本配置上传到云端

    .DESCRIPTION
    仓库依赖于powershell环境变量,可以在这里做一次导入判断处理
    本函数一般不会直接调用,而是配合其他函数调用
    #>
    [CmdletBinding()]
    param(
        $repoDirs = ""

        # $repoDirs = $CommonRepos,
        # $CxxuRepos = $CxxuRepos,
        # $CxxuComputers = $CxxuComputers
    )
    #记录当前路径
    Push-Location
    # 将相关配置变量导入到当前shell中
    Update-PwshEnvIfNotYet -Mode Vars
    # 执行仓库目录处理
    if(!$repoDirs)
    {
        $repoDirs = $CommonRepos + $CxxuRepos
        # Write-Verbose $repoDirs
        Write-Verbose $repoDirs.GetEnumerator() -Verbose
    }

    #如果是主PC,则执行云端同步操作(push)
    Write-Host 'try to push the reposes...' -BackgroundColor Yellow
    # 获取repos目录下所有子目录路径
    # $repoDirs = Get-ChildItem -Path $repos -Directory
    # if(Test-CxxuComputer)
    # {
    #     $repoDirs += $CxxuRepos
    # }

    # $repoDirs #指定配置需要同步的仓库目录
  
    # git 不支持多线程并行,所以只能够串行(用不上-parallel参数)
    foreach ($repoDir in $repoDirs)
    {
        # 切换到当前仓库目录
        $p = "$repos/$repoDir"
        Set-Location -Path $p
        Write-Host $P -ForegroundColor Magenta
        # 执行任务
        if (Test-Path -Path '.git')
        {
            # 每次对单个仓库执行更新操作
            gitUpdateReposSimply
        }
        Write-SeparatorLine

        # Get-Location
        # Get-ChildItem | Select-Object -First 3

        # 可选：恢复至原始工作目录，如果你希望脚本执行完毕后回到原始目录
        # Pop-Location
    }

    # 恢复当前路径
    Pop-Location
    # Set-Location $home/desktop
    Write-Verbose "current location is:$(Get-Location)"
    # 如果不需要Pop-Location，这里可以添加注释掉的部分，以便始终回到脚本初始目录
    #Push-Location $initialLocation

}
function Push-ReposesConfigedFromMainPC
{   
    Update-PwshEnvIfNotYet -Mode Vars

    # 检查环境,如果没有则导入环境变量,则导入,否则无法准确判断当前主机是否为主PC
    if (!(Test-MainPC))
    {
        # 如果不是MainPC,则不需要执行同步操作,防止辅PC的版本污染
        Write-Host 'This is not MainPC, do nothing...' -BackgroundColor Yellow
        return $False
    }

    Push-ReposesConfiged
}

function Update-ReposesConfiged
{
    <#
    .SYNOPSIS
    批量更新常用仓库:按名单选择源域名,$CommonRepos 走 GitHub 加速镜像,其余仓库走 gitee。

    .DESCRIPTION
    依次处理 $CommonRepos 中的仓库;当前主机在 CxxuComputers 名单内时追加 $CxxuRepos。
    目录不存在时执行浅克隆(--depth=1);已存在的 git 仓库先校正 origin 地址,再拉取当前分支。
    镜像与代理只作用于 git 的网络访问,不修改工作区内容;需要丢弃本地改动并对齐远端时使用 -Force。

    源域名优先级(加速前缀仅对 github 源生效):
    - -RepoSource github|gitee :本次强制所有仓库使用该源。
    - auto(默认):$CommonRepos 内的仓库走 github,其余仓库走 gitee。
    - $PrivateRepos 名单内的仓库按 gitee 处理,即使在 $CommonRepos 中也不走镜像。
    已存在的仓库若 origin 指向本账号同名仓库,会改写为当前规则对应的主机;SSH 与自定义远端不改写。
    gitee 源关闭交互式凭据询问,凭据未配置时快速失败,不阻塞批量更新。

    加速前缀(仅 github 源使用):
    - -NoMirror 或 -GithubMirror '' :直连 https://github.com。
    - -GithubMirror <前缀> :使用指定加速前缀。
    - 未指定时读 $env:PsGithubMirror。
    - 以上都没有时使用默认前缀 https://gh-proxy.com。
    加速镜像只能代理公开仓库,私有仓库经镜像会得到 401;镜像失败后自动改为直连重试。
    私有仓库名单优先级:
    - -PrivateRepos <名称> :本次指定名单(别名 -DirectRepos)。
    - $env:PsPrivateRepos :以逗号、分号或空白分隔的仓库名。
    - $PrivateRepos :环境变量导入的全局名单,默认在 GlobalConfig.conf 中定义。

    代理优先级:
    - -NoProxy :本次不传入代理参数,也不读取代理环境变量。
    - -Proxy <地址> :使用指定代理。
    - 未指定时依次读 $env:HTTPS_PROXY、$env:HTTP_PROXY、$env:ALL_PROXY(兼容小写形式),取第一个非空值。
    - 都没有时不传代理参数。
    未显式指定代理时,git 自身的代理配置(如 http.proxy)仍会生效。

    .PARAMETER RepoDirs
    要更新的仓库目录名(相对 $repos),可传多个。省略时处理 $CommonRepos,当前主机属于
    CxxuComputers 时追加 $CxxuRepos;显式传入时只处理这些目录,不再追加。

    .PARAMETER RepoSource
    仓库源域名:auto(默认)、github 或 gitee。auto 时 $CommonRepos 内的仓库走 github,
    其余仓库走 gitee;显式传入 github/gitee 时本次所有仓库都使用该源。
    加速前缀只对 github 生效,且只用于公开仓库。

    .PARAMETER GithubMirror
    GitHub 加速前缀,例如 https://gh-proxy.com。默认读 $env:PsGithubMirror,未设置或为空时用
    https://gh-proxy.com;传空字符串表示直连。仅对按名单走 github 的仓库生效。已存在仓库的
    origin 若指向本账号同名仓库,会改为当前前缀对应的地址,使后续拉取沿用同一配置;镜像仅用于
    公开仓库下载,推送地址设为直连 GitHub(保留 gitee 等其他推送地址),不影响 Push-ReposesConfiged。

    .PARAMETER NoMirror
    强制直连 GitHub,忽略 -GithubMirror 与 $env:PsGithubMirror。

    .PARAMETER PrivateRepos
    私有仓库目录名,按 gitee 源处理且不经过加速镜像,即使出现在 $CommonRepos 中。
    省略时读 $env:PsPrivateRepos,再读 $PrivateRepos;显式传入时只使用本次传入的名单。

    .PARAMETER Proxy
    代理地址,例如 http://127.0.0.1:7897。未指定时按环境变量顺序自动识别。

    .PARAMETER NoProxy
    本次不传入代理参数,忽略 -Proxy 与代理环境变量。

    .PARAMETER CxxuRepos
    额外仓库目录名列表,仅在当前主机属于 CxxuComputers 时追加。默认读 $CxxuRepos。

    .PARAMETER CxxuComputers
    主机名名单。显式传入时用它替代 $CxxuComputers 判断当前主机,可传 $env:ComputerName
    临时放开 $CxxuRepos 的更新;仅在未显式指定 -RepoDirs 时生效。

    .PARAMETER Force
    拉取前执行 git fetch,再执行 git reset --hard origin/<当前分支>。会丢弃该仓库已跟踪
    文件的本地未提交改动;未跟踪文件不受影响。

    .EXAMPLE
    Update-ReposesConfiged
    按默认镜像和自动识别的代理更新全部配置仓库。

    .EXAMPLE
    Update-ReposesConfiged -NoMirror
    GitHub 源的仓库直连,用于镜像不可用或需要核对原始远端。

    .EXAMPLE
    Update-ReposesConfiged -RepoSource github
    本次强制所有仓库走 GitHub(经默认镜像),用于确认某个仓库只在 GitHub 托管。

    .EXAMPLE
    Update-ReposesConfiged -GithubMirror 'https://ghfast.top' -Proxy 'http://127.0.0.1:7897'
    使用指定加速镜像,并通过本地代理访问。

    .EXAMPLE
    Update-ReposesConfiged -RepoDirs 'scripts' -Force
    只更新 scripts 仓库,并丢弃该仓库已跟踪文件的本地未提交改动。

    .NOTES
    需要 git 已安装并在 PATH 中。单个仓库失败不会中断其余仓库,结束时汇总失败项并给出处理建议;
    scripts 仓库含 dll 变更时自动同步活件并提示重新打开终端。
    #>
    [CmdletBinding()]
    param(
        [Alias('RepoNames')]
        [string[]]$RepoDirs = @(),
        [ValidateSet('auto', 'github', 'gitee')]
        [string]$RepoSource = 'auto',
        [Alias('Mirror')]
        [string]$GithubMirror,
        [switch]$NoMirror,
        [Alias('DirectRepos')]
        [string[]]$PrivateRepos = @(),
        [string]$Proxy,
        [switch]$NoProxy,
        [string[]]$CxxuRepos = @(),
        [string[]]$CxxuComputers = @(),
        [switch]$Force
    )

    $succeeded = 0
    $failures = @()
    $skipped = @()

    #记录当前路径
    Push-Location
    try
    {
        # 导入环境变量(当前没有导入过),以便本函数确定默认值,即哪些仓库需要同步
        Update-PwshEnvIfNotYet -Mode Vars

        # init 可能把 scoop 版 git 加入 PATH,因此导入环境后再检查
        if (-not (Get-Command git -ErrorAction SilentlyContinue))
        {
            Write-Warning '未找到 git,无法更新仓库。请先安装 Git for Windows,并确认 git 在 PATH 中。'
            return
        }

        if ([string]::IsNullOrWhiteSpace($repos))
        {
            Write-Warning '未读取到仓库根目录 $repos。请先执行 init 导入环境变量,然后重试。'
            return
        }
        if (-not (Test-Path -LiteralPath $repos))
        {
            New-Item -ItemType Directory -Path $repos -Force | Out-Null
        }

        # 解析加速前缀:显式参数优先,-NoMirror 优先级最高;是否使用由各仓库的源域名决定
        $mirrorPrefix = ''
        if (-not $NoMirror)
        {
            if ($PSBoundParameters.ContainsKey('GithubMirror'))
            {
                $mirrorPrefix = [string]$GithubMirror
            }
            elseif (-not [string]::IsNullOrWhiteSpace($env:PsGithubMirror))
            {
                $mirrorPrefix = [string]$env:PsGithubMirror
            }
            else
            {
                $mirrorPrefix = 'https://gh-proxy.com'
            }
            if ([string]::IsNullOrWhiteSpace($mirrorPrefix))
            {
                $mirrorPrefix = ''
            }
            else
            {
                $mirrorPrefix = ([string]$mirrorPrefix).Trim().TrimEnd('/')
            }
        }

        # 解析 GitHub 优先名单:auto 模式下 $CommonRepos 内的仓库走 github,其余走 gitee
        # 注意:Get-Variable -ValueOnly 会把数组作为单个对象输出,须先存入变量再 @() 展开
        $githubVar = Get-Variable -Name CommonRepos -Scope Global -ValueOnly -ErrorAction SilentlyContinue
        if ($null -eq $githubVar)
        {
            $githubVar = $CommonRepos
        }
        $githubNames = @($githubVar |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ([string]$_).Trim() } |
            Select-Object -Unique)

        # 解析私有仓库名单:按 gitee 处理,且不经过加速镜像
        $privateNames = @()
        if ($PSBoundParameters.ContainsKey('PrivateRepos'))
        {
            $privateNames = @($PrivateRepos)
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:PsPrivateRepos))
        {
            $privateNames = @(([string]$env:PsPrivateRepos) -split '[,;\s]+')
        }
        else
        {
            $privateVar = Get-Variable -Name PrivateRepos -Scope Global -ValueOnly -ErrorAction SilentlyContinue
            if ($null -ne $privateVar)
            {
                $privateNames = @($privateVar)
            }
        }
        $privateNames = @($privateNames |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { ([string]$_).Trim() } |
            Select-Object -Unique)

        # 解析代理:显式参数优先,-NoProxy 优先级最高,否则读环境变量
        $proxyUrl = ''
        if (-not $NoProxy)
        {
            if ($PSBoundParameters.ContainsKey('Proxy'))
            {
                $proxyUrl = [string]$Proxy
            }
            else
            {
                $proxyUrl = @(
                    $env:HTTPS_PROXY, $env:https_proxy,
                    $env:HTTP_PROXY, $env:http_proxy,
                    $env:ALL_PROXY, $env:all_proxy
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Select-Object -First 1
            }
            if ([string]::IsNullOrWhiteSpace($proxyUrl))
            {
                $proxyUrl = ''
            }
            else
            {
                $proxyUrl = ([string]$proxyUrl).Trim()
            }
        }
        $gitNetworkArgs = @()
        if ($proxyUrl)
        {
            $gitNetworkArgs = @('-c', "http.proxy=$proxyUrl", '-c', "https.proxy=$proxyUrl")
        }

        # 解析仓库列表:显式 -RepoDirs 覆盖默认集合
        if ($PSBoundParameters.ContainsKey('RepoDirs'))
        {
            $targetNames = @($RepoDirs)
        }
        else
        {
            $targetNames = @($CommonRepos)
            $cxxuList = if ($CxxuRepos.Count -gt 0)
            {
                @($CxxuRepos)
            }
            else
            {
                $cxxuVar = Get-Variable -Name CxxuRepos -Scope Global -ValueOnly -ErrorAction SilentlyContinue
                if ($null -ne $cxxuVar) { @($cxxuVar) } else { @() }
            }
            $isCxxuComputer = if ($PSBoundParameters.ContainsKey('CxxuComputers'))
            {
                Test-CxxuComputer -CxxuComputers $CxxuComputers
            }
            else
            {
                Test-CxxuComputer
            }
            if ($isCxxuComputer)
            {
                $targetNames += $cxxuList
            }
        }
        $targetNames = @($targetNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($targetNames.Count -eq 0)
        {
            Write-Warning '没有需要更新的仓库:请检查 $CommonRepos 或 -RepoDirs。'
            return
        }

        $mirrorDisplay = if ($mirrorPrefix) { $mirrorPrefix } else { '直连' }
        $proxyDisplay = if ($proxyUrl) { $proxyUrl } else { '未指定' }
        $privateDisplay = if ($privateNames.Count -gt 0) { $privateNames -join '、' } else { '无' }
        $githubDisplay = if ($githubNames.Count -gt 0) { $githubNames -join '、' } else { '无' }
        $sourceDisplay = if ($RepoSource -eq 'auto') { 'auto(CommonRepos→github,其余→gitee)' } else { $RepoSource }
        Write-Verbose "仓库源:$sourceDisplay;GitHub 名单:$githubDisplay;加速镜像:$mirrorDisplay;私有仓库:$privateDisplay;代理:$proxyDisplay"

        foreach ($repoName in $targetNames)
        {
            $repoPath = Join-Path -Path $repos -ChildPath $repoName
            $isPrivate = $privateNames -contains $repoName

            # 源域名:显式 -RepoSource 优先;auto 时 $PrivateRepos 与 $CommonRepos 之外的仓库走 gitee,
            # $CommonRepos 内的仓库走 github。origin 主机不参与判断,已存在仓库按本规则统一迁移
            # 注意变量名不能与参数 $RepoSource 只差大小写:PowerShell 变量名不区分大小写
            if ($RepoSource -ne 'auto')
            {
                $repoSourceName = $RepoSource
            }
            elseif ($isPrivate)
            {
                $repoSourceName = 'gitee'
            }
            elseif ($githubNames -contains $repoName)
            {
                $repoSourceName = 'github'
            }
            else
            {
                $repoSourceName = 'gitee'
            }

            $directUrl = "https://$repoSourceName.com/xuchaoxin1375/$repoName.git"
            # 私有仓库无法经公开镜像拉取,镜像只用于公开的 github 仓库
            $repoMirrorPrefix = if ($mirrorPrefix -and $repoSourceName -eq 'github' -and -not $isPrivate) { $mirrorPrefix } else { '' }
            $targetUrl = if ($repoMirrorPrefix) { "$repoMirrorPrefix/$directUrl" } else { $directUrl }
            # 镜像与 gitee 源关闭交互式凭据询问,避免批量更新停在输入处
            $noPrompt = [bool]$repoMirrorPrefix -or ($repoSourceName -eq 'gitee')

            Write-Host "==> $repoName" -ForegroundColor Cyan

            if (-not (Test-Path -LiteralPath $repoPath))
            {
                Write-Host "克隆:$targetUrl"
                $previousPrompt = $env:GIT_TERMINAL_PROMPT
                if ($noPrompt)
                {
                    $env:GIT_TERMINAL_PROMPT = '0'
                }
                try
                {
                    & git @gitNetworkArgs clone --depth=1 $targetUrl $repoPath
                }
                finally
                {
                    $env:GIT_TERMINAL_PROMPT = $previousPrompt
                }
                $clonedWithMirror = ($LASTEXITCODE -eq 0 -and $repoMirrorPrefix)
                if ($LASTEXITCODE -ne 0 -and $repoMirrorPrefix)
                {
                    Write-Warning ("经镜像克隆 $repoName 失败(退出码 $LASTEXITCODE),改为直连重试。" +
                        "若确认其为私有仓库,请加入 `$PrivateRepos 或 -PrivateRepos。")
                    # 克隆失败可能残留半成品目录,清理后再试直连
                    if (Test-Path -LiteralPath $repoPath)
                    {
                        Remove-Item -LiteralPath $repoPath -Recurse -Force
                    }
                    & git @gitNetworkArgs clone --depth=1 $directUrl $repoPath
                    $clonedWithMirror = $false
                }
                if ($LASTEXITCODE -eq 0)
                {
                    # 加速镜像只用于下载:推送地址改回直连,避免 Push-ReposesConfiged 走只读镜像失败
                    if ($clonedWithMirror)
                    {
                        & git -C $repoPath remote set-url --push origin $directUrl
                    }
                    $succeeded++
                    Write-Host "[$repoName] 克隆完成。" -ForegroundColor Green
                }
                else
                {
                    $failures += $repoName
                    Write-Warning "[$repoName] 克隆失败(退出码 $LASTEXITCODE)。"
                }
                continue
            }

            if (-not (Test-Path -LiteralPath (Join-Path $repoPath '.git')))
            {
                $skipped += $repoName
                Write-Warning "[$repoName] 目录已存在但不是 git 仓库,已跳过。如需纳入更新,请手动移走该目录后重试。"
                continue
            }

            Push-Location -LiteralPath $repoPath
            try
            {
                # 校正 origin:仅改写指向本账号同名仓库的 http(s) 地址,SSH 与自定义远端不动
                $originUrl = [string](& git remote get-url origin 2>$null)
                $originMatches = $originUrl -match '^https?://' -and
                    $originUrl -match ('xuchaoxin1375/' + [regex]::Escape($repoName) + '(?:\.git)?/?$')
                if ($LASTEXITCODE -eq 0 -and $originMatches)
                {
                    if ($originUrl.TrimEnd('/') -ne $targetUrl)
                    {
                        & git remote set-url origin $targetUrl
                        Write-Verbose "已更新 origin:$originUrl -> $targetUrl"
                    }
                    # github 源:镜像只用于下载,推送地址统一为直连 GitHub(保留 gitee 等其他推送地址);
                    # gitee 源不动 pushurl,避免清掉有意配置的多路推送
                    if ($repoSourceName -eq 'github')
                    {
                        $pushUrls = @(& git remote get-url --push --all origin 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        $mirrorPushUrls = @($pushUrls | Where-Object { $_ -match '/https?://github\.com/' })
                        if ($mirrorPushUrls.Count -gt 0)
                        {
                            $keepPushUrls = @($pushUrls | Where-Object { $_ -notmatch '/https?://github\.com/' })
                            if ($keepPushUrls -notcontains $directUrl)
                            {
                                $keepPushUrls = @($directUrl) + $keepPushUrls
                            }
                            # 先清空 pushurl 再重建,避免 set-url 只替换首项而留下重复项
                            & git config --unset-all remote.origin.pushurl 2>$null
                            & git remote set-url --push origin $keepPushUrls[0]
                            for ($i = 1; $i -lt $keepPushUrls.Count; $i++)
                            {
                                & git remote set-url --add --push origin $keepPushUrls[$i]
                            }
                        }
                    }
                }

                # 使用仓库当前分支,无法判断时回退 main(兼容旧仓库)
                $branch = [string](& git rev-parse --abbrev-ref HEAD 2>$null)
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch) -or $branch -eq 'HEAD')
                {
                    $branch = 'main'
                }
                $branch = $branch.Trim()

                $exitCode = 0
                if ($Force)
                {
                    Write-Host "强制对齐:origin/$branch"
                    $previousPrompt = $env:GIT_TERMINAL_PROMPT
                    if ($noPrompt)
                    {
                        $env:GIT_TERMINAL_PROMPT = '0'
                    }
                    try
                    {
                        & git @gitNetworkArgs fetch origin $branch
                        $exitCode = $LASTEXITCODE
                    }
                    finally
                    {
                        $env:GIT_TERMINAL_PROMPT = $previousPrompt
                    }
                    $fetchRef = "origin/$branch"
                    if ($exitCode -ne 0 -and $repoMirrorPrefix)
                    {
                        Write-Warning ("经镜像拉取 $repoName 失败(退出码 $exitCode),改为直连重试。" +
                            "若确认其为私有仓库,请加入 `$PrivateRepos 或 -PrivateRepos。")
                        & git @gitNetworkArgs fetch $directUrl $branch
                        $exitCode = $LASTEXITCODE
                        $fetchRef = 'FETCH_HEAD'
                    }
                    if ($exitCode -eq 0)
                    {
                        & git @gitNetworkArgs reset --hard $fetchRef
                        $exitCode = $LASTEXITCODE
                    }
                }
                else
                {
                    Write-Host "拉取:origin/$branch"
                    $previousPrompt = $env:GIT_TERMINAL_PROMPT
                    if ($noPrompt)
                    {
                        $env:GIT_TERMINAL_PROMPT = '0'
                    }
                    try
                    {
                        & git @gitNetworkArgs pull origin $branch
                        $exitCode = $LASTEXITCODE
                    }
                    finally
                    {
                        $env:GIT_TERMINAL_PROMPT = $previousPrompt
                    }
                    if ($exitCode -ne 0 -and $repoMirrorPrefix)
                    {
                        Write-Warning ("经镜像拉取 $repoName 失败(退出码 $exitCode),改为直连重试。" +
                            "若确认其为私有仓库,请加入 `$PrivateRepos 或 -PrivateRepos。")
                        & git @gitNetworkArgs pull $directUrl $branch
                        $exitCode = $LASTEXITCODE
                    }
                }

                if ($exitCode -eq 0)
                {
                    $succeeded++
                    $action = if ($Force) { '已强制对齐远端' } else { '拉取完成' }
                    Write-Host "[$repoName] $action。" -ForegroundColor Green
                }
                else
                {
                    $failures += $repoName
                    Write-Warning "[$repoName] 更新失败(退出码 $exitCode)。"
                }
            }
            finally
            {
                Pop-Location
            }
        }

        Write-Host ''
        if ($failures.Count -eq 0)
        {
            Write-Host "更新完成:成功 $succeeded 个仓库,跳过 $($skipped.Count) 个。" -ForegroundColor Green
        }
        else
        {
            Write-Warning ("更新完成:成功 $succeeded 个,失败 $($failures.Count) 个($($failures -join '、')),跳过 $($skipped.Count) 个。" +
                '镜像不可用时改用 -NoMirror 或 -GithubMirror <其他镜像>;名单规则不适用时用 -RepoSource github|gitee 覆盖本次源;' +
                'gitee 私有仓库需先配置凭据;网络受限时加 -Proxy <代理地址> 后重试。')
        }

        # scripts 仓库若含 dll 变更:同步活件(并排版本只新增目录,不受锁限制,任何会话都可执行)并提示重开;
        # 跨模块调用加守卫(无 Sync 命令则跳过,不硬依赖 TerminalTools)
        $scriptsDir = Join-Path $repos 'scripts'
        if (($targetNames -contains 'scripts') -and (Test-Path -LiteralPath (Join-Path $scriptsDir '.git')) -and (Get-Command Sync-CxxuPredictor -ErrorAction SilentlyContinue))
        {
            $repoDll = Join-Path $scriptsDir (Join-Path 'PS' (Join-Path 'CxxuPredictor' 'CxxuPredictor.dll'))
            $repoPs51Dll = Join-Path $scriptsDir (Join-Path 'PS' (Join-Path 'CxxuPredictor' (Join-Path 'ps51' 'CxxuPredictor.dll')))
            $binDir = Join-Path (Join-Path $HOME '.cxxu') 'bin'
            $ps51Dir = Join-Path $binDir 'ps51'
            $liveDll = $null
            $ptrF = Join-Path $binDir 'current.txt'
            if (Test-Path -LiteralPath $ptrF)
            {
                $hd = Get-Content -LiteralPath $ptrF -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($hd) { $cd = Join-Path (Join-Path $binDir "$hd".Trim()) 'CxxuPredictor.dll'; if (Test-Path -LiteralPath $cd) { $liveDll = $cd } }
            }
            $livePs51Dll = $null
            $ps51PtrF = Join-Path $ps51Dir 'current.txt'
            if (Test-Path -LiteralPath $ps51PtrF)
            {
                $hd = Get-Content -LiteralPath $ps51PtrF -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($hd) { $cd = Join-Path (Join-Path $ps51Dir "$hd".Trim()) 'CxxuPredictor.dll'; if (Test-Path -LiteralPath $cd) { $livePs51Dll = $cd } }
            }
            $needsNet9Sync = $true
            if ((Test-Path -LiteralPath $repoDll) -and $liveDll)
            {
                $needsNet9Sync = (Get-FileHash -LiteralPath $repoDll -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $liveDll -Algorithm SHA256).Hash
            }
            $needsPs51Sync = $false
            if ((($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true)) -and (Test-Path -LiteralPath $repoPs51Dll))
            {
                if (-not $livePs51Dll) { $needsPs51Sync = $true }
                else { $needsPs51Sync = (Get-FileHash -LiteralPath $repoPs51Dll -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $livePs51Dll -Algorithm SHA256).Hash }
            }
            $needsSync = $needsNet9Sync -or $needsPs51Sync
            # 自编译活件保持不动：标记为 local 且活件哈希与标记一致时，更新也不碰指针（否则会把可用活件换回仓库源）
            $keepLocal = $false
            if ($liveDll)
            {
                $mk = Get-Content -LiteralPath (Join-Path $binDir 'local-build.txt') -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($mk -match 'src=local' -and $mk -match 'hash=([0-9A-Fa-f]{8})')
                {
                    $liveHash8 = try { (Get-FileHash -LiteralPath $liveDll -Algorithm SHA256).Hash.Substring(0, 8) } catch { '' }
                    if ($liveHash8 -eq $Matches[1]) { $keepLocal = $true }
                }
            }
            if ($keepLocal)
            {
                if ($needsPs51Sync)
                {
                    Sync-CxxuPredictor -Ps51Only
                    Write-Host 'net9 活件是本地自编译版本，保持不动；5.1 Tab 活件已按仓库源同步。'
                }
                else
                {
                    Write-Host '活件是本地自编译版本，保持不动（想跟进仓库源：重编后执行 Sync-CxxuPredictor -DllPath 再同步）。'
                }
            }
            elseif ($needsSync)
            {
                Sync-CxxuPredictor
                Write-Host 'scripts 仓库含 dll 变更：活件已同步，当前会话内存中仍是旧代码，请重新打开终端再执行 init（纯文本变更执行 ipmox 即可）。'
            }
        }
    }
    finally
    {
        # 恢复当前路径
        Pop-Location
    }

    Write-Verbose "current location is:$(Get-Location)"

    #启动新的powershell窗口,使得新的配置生效
    # Start-Process pwsh
}

function pipUpdateIntegration
{
    param (
        
    )
    python -m pip install --upgrade pip
}


# testing...

function status { git status }
