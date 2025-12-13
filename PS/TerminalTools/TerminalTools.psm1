
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
        $Server,

        [alias("ScpUser")]
        $User='root',
        [alias("Path")]
        $SourcePath,

        [alias('TargetPath','Target')]
        $DestinationPath=$env:DF_SERVER1
    )
    $expression = "scp -r $SourcePath $User@${Server}:$DestinationPath"
    Write-Host $expression 
    # Pause
    if($PSCmdlet.ShouldProcess($server, $expression))
    {

        Invoke-Expression $expression
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