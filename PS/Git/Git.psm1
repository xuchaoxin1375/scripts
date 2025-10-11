
# 可用列表检查 https://yishijie.gitlab.io/ziyuan/
$global:github_mirror = "https://gh-proxy.com"
# Set-Variable -Name github-mirror -Value "https://gh-proxy.com"  -Scope Global

$GithubMirrors = @(

    # '' #空字符串收尾
)
$GithubMirrorsTest = @(

    # ''#收尾
)

$GithubMirrorsInString = @'
# 注意,如果你的浏览器使用了代理,那么部分镜像站会和代理冲突,所以可能命令行中测试可以访问的链接在浏览器中确打不开镜像站,可以关闭代理或换个浏览器后重新验证该镜像站的可用性
#搜集到的链接可以用gpt进行修改,将链接包裹引号(指令:为这些链接分别添加引号);或者自己粘贴到文件文件中然后编写脚本转换为数组格式

'https://gh-proxy.com/',
'https://github.moeyy.xyz', # Moeyy - 提供 GitHub 文件的加速下载功能
'https://ghproxy.cc',
'https://ghproxy.net', # GitHub Proxy by GitHub99 - 提供 GitHub 文件的加速下载和克隆服务 #和用户自己的代理可能发生冲突
'https://mirror.ghproxy.com',

'https://ghproxy.com/bad/demo', #虚假镜像,用来测试代码是否能够正确处理不可用的镜像链接
'https://ghproxy.homeboyc.cn/',
'https://gh-proxy.com/',
'https://ghps.cc/',
'https://ghproxy.net/',
'https://github.moeyy.xyz/',
'https://gh.ddlc.top/',
'https://slink.ltd/',
'https://gh.con.sh/',
'https://hub.gitmirror.com/',
'https://sciproxy.com/',
'https://cf.ghproxy.cc/',
'https://gh.noki.icu/',
'https://gh.ddlc.top',
'https://github.ur1.fun/',
https://sciproxy.com/
'https://gh.noki.icu/',
"https://sciproxy.com/"
'https://slink.ltd/'

'@

$GithubMirrorsInString = $GithubMirrorsInString -replace '#.*', ' ' -replace '[",;\n\r]', ' ' -replace "'" , ' ' -replace '\s+', ' '

$GithubMirrorsInString = $GithubMirrorsInString -split ' ' #去重等操作留到后面一起处理

$GithubMirrors = $GithubMirrors + $GithubMirrorsTest + $GithubMirrorsInString
$GithubMirrors = $GithubMirrors | Where-Object { $_ }#移除空串
$GithubMirrors = $GithubMirrors | ForEach-Object { $_.trim('/') } | Sort-Object #统一链接风格(去除末尾的`/`如果有的话)
$GithubMirrors = $GithubMirrors | Select-Object -Unique # Get-Unique #移除重复条目(注意get-Unique要求被处理数组是有序的,否则无效,可以用select -unique更通用)



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
    Write-Debug "Test links linearly...🎈" -Debug
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
    #>
    [CmdletBinding()]
    param (
        $Mirrors = $GithubMirrors,
        $TimeOutSec = 6,
        $ThrottleLimits = 16
        # $First = 5
    )
    Write-Debug "Test links parallel...🎈" -Debug
    # 检查镜像测试命令是否可用
    Get-Command Test-MirrorAvailability
    $s = Get-Command Test-MirrorAvailability | Out-String
    Write-Host $s -ForegroundColor Cyan
    # 如果不是powershell 7报错
    if ($host.Version.Major -lt 7)
    {
        Throw 'PowerShell 7 or higher is required to run parallel foreach!'
        # return 
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

    $availableMirrors = $mirs #.ToArray()
    if ($availableMirrors.Count -eq 0)
    {
        throw 'No mirrors are available!'
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
    .DESCRIPTION
    如果及时正确相应,将链接打印为绿色,否则打印为红色
    #>
    [CmdletBinding()]
    param (
        [string]$Url,
        $TimeoutSec = 6
    )

    try
    {
        # 使用 Invoke-WebRequest 检查可用性
        # 方案1
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Head -TimeoutSec $TimeOutSec -ErrorAction Stop
        $availability = $response.StatusCode -eq 200

        #方案2
        # $response = Test-Connection -ComputerName "gh-proxy.com" -Count 1
        # $availability = $response
        
    }
    catch
    {
        $availability = $false
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
    Write-Warning "$Url : $availability"
    Write-Host "$Url : $availability" -ForegroundColor Cyan
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
    https://ghproxy.link/
    https://github-mirror.us.kg/
    https://github.com/hunshcn/gh-proxy/issues/116
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

        $availableMirrors = Test-LinksLinearly -Mirrors $Mirrors -TimeOutSec $TimeOutSec -First $First -Verbose:$VerbosePreference
        # 对于pwsh7直接使用Teset-LinksParallel有点问题(部署完毕后才会正常使用),暂时不知道为什么,估计是pwsh7的bug
        # 目前windows powershell 5.1和powershell 7都可以正常线性方案(因此暂时注释掉下面的分支判断代码)
        # if ($Linearly ) #-or $PSVersion -lt 7
        # {
        #     #简单起见,这里仅简单调用 Test-LinksLinearly的Frist参数集语法,而不做分支判断
        #     $availableMirrors = Test-LinksLinearly -Mirrors $Mirrors -TimeOutSec $TimeOutSec -First $First -Verbose:${VerbosePreference}
        # }
        # else
        # {
        
        #     $availableMirrors = Test-LinksParallel -Mirrors $Mirrors -TimeOutSec $TimeOutSec -ThrottleLimits $ThrottleLimits 
        # }
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

function Get-SelectedMirror
{
    <# 
    .SYNOPSIS
    让用户选择可用的镜像连接,允许选择多个,逗号隔开
    .NOTES
    包含单个字符串的数组被返回时会被自动解包,这种情况下会是一个字符串
    如果确实需要外部接受数组,那么可以在外部使用@()来包装返回结果即可
    .EXAMPLE
    PS C:\repos\scripts> Get-SelectedMirror         
Checking available Mirrors...
         https://demo.testNew.com.
         https://gh.ddlc.top
...

Available Mirrors:
 0: Use No Mirror
 1: https://gh.ddlc.top
 2: https://ghps.cc
 3: https://gh.con.sh
 4: https://gh.noki.icu
 5: https://slink.ltd
 6: https://github.moeyy.xyz
 7: https://ghproxy.homeboyc.cn

Select the number(s) of the mirror you want to use [0~15] ?(default: 1): 1,3,5
Selected mirror:[ 
        https://gh.ddlc.top
        https://gh.con.sh
        https://slink.ltd
]
https://gh.ddlc.top
https://gh.con.sh
https://slink.ltd
PS C:\repos\scripts>
    #>
    [CmdletBinding()]
    param (
        
        $Default = 1, # 默认选择第一个(可能是响应最快的)
        [switch]$Linearly,
        [switch]$Silent # 是否静默模式,不询问用户,返回第$Default个链接($Default默认为1)
    )
    $Mirrors = Get-AvailableGithubMirrors -PassThru -Linearly:$Linearly

    $res = @()
    if (!$Silent)
    {
        # 交互模式
        $numOfMirrors = $Mirrors.Count
        $range = "[0~$($numOfMirrors-1)]"
        $num = Read-Host -Prompt "Select the number(s) of the mirror you want to use $range ?(default: $default)"
        # $mirror = 'https://mirror.ghproxy.com'
        # if($num.ToCharArray() -contains ','){
        # }

        $numStrs = $num -split ',' | Where-Object { $_.Trim() } | Get-Unique #转换为数组(自动去除空白字符)
        # 如果$num是一个空字符串(Read-Host遇到直接回车的情况),那么$numStrs会是$null
        if (!$numStrs )
        {
            Write-Host 'choose the Default 1'
            # $n = $default
            $res += $Default
        }
        else
        {
            foreach ($num in $numStrs)
            {
                $n = $num -as [int] #可能是数字或者空$null
                if ($VerbosePreference)
                {
            
                    Write-Verbose "`$n=$n"
                    Write-Verbose "`$num=$num"
                    Write-Verbose "`$numOfMirrors=$numOfMirrors"
                }
   
                #  如果输入的是空白字符,则默认设置为0
                # if ( $num.trim().Length -eq 0)
       
                if ($n -notin 0..($numOfMirrors - 1))
                {
                    Throw " Input a number within the range! $range"
                }
                else
                {
                    # 合法的序号输入，插入到$res
                    $res += $n
                }
            }
        }
    }
    elseif ($Silent)
    {
        # Silent模式下默认选择第1个镜像
        $res += $default
    }
    # 抽取镜像
    $mirrors = $Mirrors[$res] #利用pwsh的数组高级特性
    # Write-Host $mirrors -ForegroundColor cyan
    $mirrors = @($mirrors) #确保其为数组
    
    # 用户选择了一个合法的镜像代号(0表示不使用镜像)
    Write-Host 'Selected mirror:[ ' # -NoNewline
    foreach ($mir in $mirrors)
    {
        Write-Host "`t$mir" -BackgroundColor Gray -NoNewline
        Write-Host ''

    }
    # Write-Host "$($Mirrors[$n])" -BackgroundColor Gray -NoNewline
    Write-Host ']'#打印一个空行

    # 包含单个字符串的数组被返回时会被自动解包,这种情况下会是一个字符串
    #如果却是需要外部接受数组,那么可以在外部使用@()来包装返回结果即可
    return $mirrors
    # return [array]$Mirrors
    # return $res

}

function gitbook
{
    ELA
    Set-Location docs/00_课堂文档
    py -m http.server

}

function gitAdd
{
    param(
        $item = '.'
    )
    git add $item
    Write-SeparatorLine
    gitS
}

function git_clone_shallow
{
    param (

        $gitUrl
    )
    Write-Output "clone with `n @--depth 1 `n --fileter=blob:none `n $gitUrl"
    git clone --depth 1 --filter=blob:none $gitUrl
}
function gitUpdateReposSimply
{
    param (
        $comment = "general update project $(Get-Date)",
        $remote_repo = 'origin',
        $branch = 'main'
    )
    git add .
    git commit -m $comment
    Write-SeparatorLine '---'
    Write-Output 'checking remote repository...'
    git remote -v
    # timer_tips 2
    Write-Output "🎈try to push to $remote_repo $branch..."
    git push $remote_repo $branch
    Write-SeparatorLine '😎'
    git status
    Write-SeparatorLine '>'
    Write-Output "@comment=`"$comment`""
    Write-Output "@branch=$branch"  
}

function Remove-GitImagesFromHistory
{
    <#
.SYNOPSIS
    从 Git 仓库历史中彻底移除图片文件（如 jpg、png、gif 等）。

.DESCRIPTION
    此函数会查找指定扩展名的图片文件，先从当前索引移除，再用 git-filter-repo 从历史中彻底删除，并可选择自动提交和强制推送。

.PARAMETER Extensions
    要移除的图片扩展名数组，默认支持常见图片格式。

.PARAMETER Commit
    是否自动提交移除操作，默认 $true。

.PARAMETER Push
    是否自动强制推送到远程仓库，默认 $false。

.EXAMPLE
    Remove-GitImagesFromHistory

.EXAMPLE
    Remove-GitImagesFromHistory -Extensions @('*.jpg','*.png') -Push $true

.NOTES
    需先安装 git-filter-repo。操作前请备份仓库！
#>
    [CmdletBinding()]
    param(
        [string[]]$Extensions = @('*.jpg', '*.jpeg', '*.png', '*.gif', '*.svg', '*.ico', '*.webp'),
        [switch]$NoCommit,
        [switch]$Push 
    )

    # 1. 查找所有图片文件
    $imgFiles = Get-ChildItem -Recurse -Include $Extensions -File | Select-Object -ExpandProperty FullName

    if (-not $imgFiles)
    {
        Write-Host "未找到图片文件。"
        return
    }

    # 2. 用 git rm --cached 移除索引中的图片文件
    # 注意重复执行会提示错误:
    foreach ($file in $imgFiles)
    {
        git rm --cached "$file"
    }

    # 3. 提交更改(默认提交)
    if (!$NoCommit)
    {
        git commit -m "Remove image files from repository"
    }

    # 4. 构建 git filter-repo 参数
    $filterArgs = @()
    foreach ($ext in $Extensions)
    {
        $filterArgs += "--path-glob"
        $filterArgs += $ext
    }
    $filterArgs += "--invert-paths"

    # 5. 执行 git filter-repo
    # 自动安装 git-filter-repo（如未安装）
    # Write-Host "正在尝试用 git-filter-repo 移除历史中的图片文件..."
    # if (-not (Get-Command 'git-filter-repo' -ErrorAction SilentlyContinue))
    # {
    #     Write-Host "未检测到 git-filter-repo，正在尝试自动安装..."
    #     pip install git-filter-repo
    # }
    # git filter-repo @filterArgs --force

    # 6. 强制推送到远程仓库
    if ($Push)
    {
        git push origin --force --all
        git push origin --force --tags
        Write-Host "已强制推送到远程仓库。"
    }
    else
    {
        Write-Host "本地历史已清理，如需同步请手动强制推送。"
    }
}

function Set-GitProxy
{
    <# 
    .synopsis
    打开或者关闭gitconfig的关于http,https的proxy的全局配置;操作完成后查看配置文件
    这里主要配置不需要认证信息的情况
    .DESCRIPTION
    # 设置 HTTP 代理
    git config --global http.proxy 'http://proxy-user:proxy-password@proxy-host:proxy-port'
    # 或者，如果你不需要认证信息
    git config --global http.proxy 'http://proxy-host:proxy-port'

    # 设置 HTTPS 代理
    git config --global https.proxy 'https://proxy-user:proxy-password@proxy-host:proxy-port'
    # 或者，如果你不需要认证信息
    git config --global https.proxy 'https://proxy-host:proxy-port'
    .example
     Set-GitProxy -status off
    .example
     Set-GitProxy -status on
    .example
    Set-GitProxy -status on -port 1099
    #>
    param(
        [ValidateSet('on', 'off')]    
        $status = 'on',
        $port = '10801',
        $serverhost = 'http://localhost'

    )
    $socket = "$serverhost`:$port"
    if ($status -eq 'on')
    {

        git config --global http.proxy $socket
        git config --global https.proxy $socket
    }
    elseif ($status -eq 'off')
    {   
        git config --global --unset http.proxy
        git config --global --unset https.proxy
    }
    
    Get-Content "$home/.gitconfig" | Select-String '[http|https].proxy'
    # write-host (git config --global http.proxy)

}
function Get-SpeedUpUrl
{
    <# 
    .SYNOPSIS
    链接修改(包括拼接或替换加速域名),主要以拼接的方式来加速(比较方便)
    
    .DESCRIPTION 
    比如,可以用于github资源下载加速,通过在源链接前面追加加速镜像链接来提高下载速度
    调用外部的加速镜像测试函数,获取可用网站列表(能够响应,不保证一定可用),支持用户自主选择加速的镜像
    可以选择多个镜像(逗号分隔),此时会返回对应数量的镜像加速后的链接

    .NOTES
    如果是其他替换域名的方式,可以修改实现代码,这里隐藏获取链接的方式
    .EXAMPLE
    获取加速修改后的链接(默认为追加头域名)
    PS C:\> Get-SpeedUpUrl -Url https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip
    https://hub.fgit.cf/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip
    另一种方式
    PS C:\> Get-SpeedUpUrl -Url https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip -Option InsteadOf
    https://hub.fgit.cf/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip
    .EXAMPLE
    加速下载github release
    PS C:\Users\cxxu\Desktop> $link=Get-SpeedUpUrl https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip

    PS C:\Users\cxxu\Desktop> Invoke-WebRequest -Url $link

    StatusCode        : 200
    StatusDescription : OK

    #>
    param (
        # 被加速的链接,比如github release 的链接,或githubusercontent的链接;至于能不能够加速需要看源是否支持,比较好的源都支持
        $Url,
        # 源可能会失效,默认的源可能会失效,可以找找新的源
        $Prefix = '', #https://mirror.ghproxy.com/

        # 其他通过替换域名的方式加速
        $OriginDomain = 'github.com',
        #替换成加速域名
        $InsteadOf = 'hub.fgit.cf',
        $LinkNumber = 1,
        [validateSet('Prefix', 'InsteadOf')]$Option = 'Prefix',
        [switch]$NotToClipboard,
        [switch]$Silent
       
    )

    switch ($Option)
    {
        'Prefix'
        { 
            $res = @()
            if ($Silent)
            {
                Write-Host 'Mode:Silent', "`$LinkNumber=$LinkNumber" Cyan
                $Urls = Get-AvailableGithubMirrors -PassThru #$urls第一个是空字符串,表示不用镜像
                $Urls[1.. ($LinkNumber)] | ForEach-Object { 
                    $prefix = $_; 
                    $speedUrl = "$prefix/$Url" 
                    Write-Verbose $SpeedUrl  
                    $res += $speedUrl
                }
            }
            else
            {
                # $prefix = Get-AvailableGithubMirrors
                $prefixes = @(Get-SelectedMirror ) 
                foreach ($prefix in $prefixes)
                {

                    $speedUrl = "$prefix/$Url" 
                    Write-Verbose $SpeedUrl  
                    $res += $speedUrl
                }
            }
        }
        'InsteadOf'
        {
            $Url = $Url -replace $OriginDomain, $InsteadOf 
        }
        Default {}
    }
    # Write-Host $Url Cyan
    if (! $NotToClipboard)
    {
        $res | Set-Clipboard
    }
    return  $res
}
function Invoke-GithubResourcesSpeedup
{
    <# 
    .SYNOPSIS
    这是一个封装了Get-SpeedUpUrl的下载GitHub资源的函数。
    支持管道符输入(注意要是字符串才能传过管道符,可以用引号包裹)

    支持指定Aria2多线程下载(默认尝试调用,不可用的话则尝试用invoke-webrequest下载)
    .Notes
    aria2c 设置UA
    -U, --user-agent=<USER_AGENT>¶
    Set user agent for HTTP(S) downloads. Default: aria2/$VERSION, $VERSION is replaced by package version.
    .EXAMPLE
    PS> Invoke-GithubResourcesSpeedup -Url https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip
    Download from: https://mirror.ghproxy.com/https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip
    .EXAMPLE
    PS> 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip'|Invoke-GithubResourcesSpeedup

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [string]$Directory = "$env:USERPROFILE/Downloads",
        # $FileName = '', 
        [validateset('aria2c', 'webrequest')]
        $Downloader = 'webrequest', #aria2c和aria2的意思一样
        $Threads = 16
    
    )

    Begin
    {
        # 检查Get-SpeedUpUrl函数是否存在
        if (-not (Get-Command Get-SpeedUpUrl -ErrorAction SilentlyContinue))
        {
            throw 'Get-SpeedUpUrl function is not found. Please define it before using Invoke-GithubResourcesSpeedup.'
        }
        $UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.66 Safari/537.36'
        
    }

    Process
    {
        # 调用Get-SpeedUpUrl函数获取加速后的Url
        # Write-Host "debug:[$Url]"
        $speedUpUrl = Get-SpeedUpUrl -Url $Url
        # 使用Invoke-WebRequest下载文件
        Write-Host 'Download from:' $speedUpUrl
        # 默认使用powershell自带命令下载(aria2c 线程数设置太多可能会下不动)
        if ($Downloader -eq 'WebRequest')
        {
            # Invoke-WebRequest -Uri $speedUpUrl -OutFile $Directory
            Invoke-WebRequest -Uri $speedUpUrl -OutFile $Directory -UserAgent $UA

        }
        elseif ($downloader -like 'aria2*')
        {
            # $Aria2Availability = Get-Command aria2* -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1 | Select-Object -ExpandProperty Source | Split-Path -LeafBase #防止找到多个aria2c,这里使用select -First 1来指定其中的第一个
            $Aria2Availability = Get-Command aria2c -ErrorAction SilentlyContinue
            if ($Aria2Availability)
            {
                Write-Verbose "Aria2c is available!"
                # $downloader = $Aria2Availability
            }
            
            $expression = "aria2c  $SpeedUpUrl -d $Directory  -s $Threads -x 16 -k 1M --user-agent='$UA'"  
            # if ($VerbosePreference)
            # {
            #     $expression += ' --console-log-level=info ' #输出内容很长
            # }
            # 如果指定了文件名,则将文件下载为指定的文件名,否则默认名字
            # $expression = ($FileName) ? ($expression + " -o $FileName"): $expression
            #以Verbose的风格显示aria2c下载命令行
            Write-Verbose $expression -Verbose

            $expression | Invoke-Expression
        }
        # 检查下载结果
        Get-ChildItem "$Directory" | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    }
}

# 你现在可以这样使用这个函数：
# 'https://github.com/user/repo/file.zip' | Invoke-GithubResourcesSpeedup
# 或者
# Invoke-GithubResourcesSpeedup -Url 'https://github.com/user/repo/file.zip'
# function Get-SpeedUpGithubRaw

# {
#     <# 
#     .SYNOPSIS
#     借助FastGit等替换域名的加速的情形
#     优先使用Get-SpeedUpUrl ,该函数更加通用，除非故障
#     github似乎已经改版了raw.githubusercontent.com,可能会改为其他的
#     #>
#     param (
#         $Url,
#         $InsteadOfGithubRaw = 'raw.fgit.cf',
#         $OriginDomainGithubRaw = 'raw.githubusercontent.com'
#     )
#     $Url = $Url -replace $OriginDomainGithubRaw, $InsteadOfGithubRaw
#     return $Url
# }

function Update-CodeiumVScodeExtension
{
   
    <# 
    .SYNOPSIS
    加速下载并更新vscode中codeium插件
    当打开vscode时codeium自动更新下载了一些内容后下不动了,或者太慢了,就可以关闭vscode,然后执行本函数

    .DESCRIPTION
    如果你使用的是scoop install vscode (当前用户安装),那么可以考虑使用以下命令来重定向extension目录
    new-item -itemtype SymbolicLink -Path $home/.vscode/extensions -Target $home\scoop\persist\vscode\data\extensions
    或者指定参数$vscodeExtensions来指定目录extensions目录的位置,将codeium包下载到合适的位置
    #>
    param(
        [ValidateSet('aria2c', 'default')]$Downloader = 'aria2c',
        $Threads = 32,
        #通过scoop安装的vscode(为当前用户安装的extension路径) $home\scoop\persist\vscode\data\extensions;
        # 如果是全局安装,就把$home换为$Env:ProgramData (全局安装有权限写入问题,导致配置无法保存,因此通常不使用此方案安装!)
        $vscodeExtensions = '~\.vscode\extensions'
    )

    $codeiumExtensionPath = (Resolve-Path "$vscodeExtensions\codeium*")
    #ls $vscodeExtensions\codeium*
    $lastVersionItem = Resolve-Path $codeiumExtensionPath | Sort-Object -Property Name | Sort-Object -Descending | Select-Object -First 1

    $Name = $lastVersionItem | Select-Object -ExpandProperty Path
    $v = $Name | Set-Clipboard -PassThru #打印最新版本并且复制版本号到剪切板,形如 `codeium.codeium-1.8.40`
    $versionNumber = ("$v" -split '-')[1] #版本好字符串,形如1.8.40
    Write-Host $versionNumber -background Magenta

    # $release_page_Url = "https://github.com/Exafunction/codeium/releases/tag/language-server-v$versionNumber"
    $Url = "https://github.com/Exafunction/codeium/releases/download/language-server-v$versionNumber/language_server_windows_x64.exe.gz"

    $speedUrl = Get-SpeedUpUrl $Url
    Write-Host $speedUrl -BackgroundColor Blue
    #invoke-webrequest $speedUrl
    $desktop = "$env:userprofile\desktop"
    $fileName = 'language_server_windows_x64.exe.gz'
    $f = "$desktop\$fileName"
    if ( -not (Test-Path $f))
    { 
        switch ($Downloader)
        {
            'aria2c'
            { 

                # 使用-s 参数默认是5个线程,这里通过参数$threads来设置线程数,默认值设置为32
                aria2c $speedUrl -d $desktop -o $fileName -s $Threads; break
            }
            'default'
            {

                Invoke-WebRequest -Url $speedUrl -OutFile $f; break
            }
            Default
            {
                
            }
        }
    }

    #$serverDir="$desktop\codeium_lsw"
    $serverDir = Resolve-Path "$lastVersionItem\dist\*"
    $serverDir = Get-ChildItem "$lastVersionItem\dist\*" -Directory | Where-Object { $_.Name.Length -ge 10 }
    7z x $f -o"$serverDir"

    #清理文件
    Remove-Item $f -Verbose 
    Remove-Item "$serverDir/*.download"

    #是否重启vscode
    $continue = Confirm-UserContinue -Description 'Restart vscode'
    $process = Get-Process -Name code -ErrorAction SilentlyContinue
    Write-Host $process

    $process = Get-Process -Name code*
    $process | Format-Table
    if ($continue)
    {
        # Get-Process code | Stop-Process
        # $process | Restart-Process -Verbose #重启后导致大量进程被启动
        $process | Stop-Process -Force -Verbose
        & code #启动默认code界面
        
    }

    

}



function gitconfigEdit
{
    c $env:userProfile\.gitconfig
}
function git_initial_email_name
{
    git config --global user.email '838808930@qq.com'
    git config --global user.name 'cxxu'
}

function gitLogGraphSingleLine
{
    #is there a decorate Option seems does not matter.
    git log --all --decorate --oneline --graph
}

function gitLogGraphDetail
{
    git log --graph --all
}

function gitS
{
    git status
}

function gitNoRepeatValidate
{
    # for oldVersion git in windows
    param (
        $time = 100000
    )
    git config --global credential.helper "cache --timeout $time"
}

function checkGitReports
{
    param (
        
    )
    py $scripts\pythonScripts\checkGitReports.py
}


function gctm
{
    param([String]$CommentStr)
    git commit -m $CommentStr
}
