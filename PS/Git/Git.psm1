
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
                Write-Host 'Mode:Silent', "`$LinkNumber=$LinkNumber" -ForegroundColor Blue
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
    # Write-Host $Url -ForegroundColor Blue
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
