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
    从远程仓库拉取最新的配置覆盖本地版本
    .DESCRIPTION
    如果本地在$repos目录下，那么会从github clone到$repos目录中

    #>
    [CmdletBinding()]
    param(
        # $repoDirs = '',
        $repoDirs = $CommonRepos,
        $RepoSource = 'github',
        $CxxuRepos = $CxxuRepos,
        # $Proxy = "http://127.0.0.1:8800",
        $Proxy = "",
        # 默认读取GlobalConfig中的配置,也可以通过命令行覆盖这个列表(传入$env:ComputerName就可以临时地获取拉取CxxuRepos仓库的权限)
        $CxxuComputers = $CxxuComputers,
        [switch]$Force
    )
    #记录当前路径
    Push-Location

    # 导入环境变量(当前么有导入过),以便本函数确定默认值,即哪些仓库需要同步
    Update-PwshEnvIfNotYet -Mode Vars
    $repoDirs = if ($reposDirs) { $reposDirs } else { $CommonRepos }
    
    Write-Verbose "$repoDirs will be try to update." -Verbose
    # 获取repos目录下所有子目录路径
    # $repoDirs = Get-ChildItem -Path $repos -Directory
    
    $repoDirs = $CommonRepos
    if(Test-CxxuComputer)
    {
        $repoDirs += $CxxuRepos
    }

    foreach ($repoDir in $repoDirs)
    {

        $P = Join-Path -Path $repos -ChildPath $repoDir
        # Set-Location $repos
        Write-Verbose $P
        if (!(Test-Path $P))
        {
            $gitUrl = "https://${RepoSource}.com/xuchaoxin1375/$repoDir" #.Trim('\\')
            $Path = "$repos/$repoDir"
            Write-Verbose "[$giturl] will be cloned to [$Path] !" -Verbose
            git -c http.proxy="$Proxy" -c https.proxy="$Proxy" clone --depth=1 $gitUrl $Path 
            continue

        }
        # 切换到当前仓库目录
        Set-Location -Path "$repos/$repoDir"
        Write-Host "$repos/$repoDir" 

        # 执行任务
        if (Test-Path -Path '.git')
        {
            # 如果副设备上的仓库被污染，执行清空,然后强制拉取
            # 假设每个仓库的主分支为main(而不是master或其他)
            # git fetch origin
            if ($Force)
            {

                git -c http.proxy="$Proxy" -c https.proxy="$Proxy" reset --hard origin/main 
            }
            git -c http.proxy="$Proxy" -c https.proxy="$Proxy" pull origin main 
            # 上述命令对于不会引起冲突的文件或目录不造成影响,只有和云端仓库冲突的文件或目录才会被移除更改
            # 如果想要完全一样,那么执行以下清理命令(清除未跟踪的文件或目录)
            # git clean -fd

            Write-Host "$reposDir was try to updated." -ForegroundColor Cyan
    
        }

    }

    # 恢复当前路径
    Pop-Location
    # Set-Location $home/desktop
    Write-Verbose "current location is:$(Get-Location)"

    # scripts 仓库若含 dll 变更:同步活件(并排版本只新增目录,不受锁限制,任何会话都可执行)并提示重开;
    # 跨模块调用加守卫(无 Sync 命令则跳过,不硬依赖 TerminalTools)
    $scriptsDir = Join-Path $repos 'scripts'
    if ((Test-Path -LiteralPath (Join-Path $scriptsDir '.git')) -and (Get-Command Sync-CxxuPredictor -ErrorAction SilentlyContinue))
    {
        $repoDll = Join-Path $scriptsDir 'PS\CxxuPredictor\CxxuPredictor.dll'
        $binDir = Join-Path (Join-Path $HOME '.cxxu') 'bin'
        $liveDll = $null
        $ptrF = Join-Path $binDir 'current.txt'
        if (Test-Path -LiteralPath $ptrF)
        {
            $hd = Get-Content -LiteralPath $ptrF -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hd) { $cd = Join-Path (Join-Path $binDir "$hd".Trim()) 'CxxuPredictor.dll'; if (Test-Path -LiteralPath $cd) { $liveDll = $cd } }
        }
        $needsSync = $true
        if ((Test-Path -LiteralPath $repoDll) -and $liveDll)
        {
            $needsSync = (Get-FileHash -LiteralPath $repoDll -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $liveDll -Algorithm SHA256).Hash
        }
        if ($needsSync)
        {
            Sync-CxxuPredictor
            Write-Host 'scripts 仓库含 dll 变更：活件已同步，当前会话内存中仍是旧代码，请重新打开终端再执行 init（纯文本变更执行 ipmox 即可）。'
        }
    }

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
