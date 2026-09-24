
param(
    # 开发模式:从脚本所在目录拷贝 AutoFetch/fetch-github-hosts,不从远程下载(未推送时本地测试用)
    [switch]$Dev
)
function Register-GithubHostsAutoUpdater-Archive
{
    [CmdletBinding()]
    param(
        # 开发模式:从脚本所在目录拷贝,不从远程下载(未推送时本地测试用)
        [switch]$Dev
    )
    #设置执行策略
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy bypass -Force

    # $GHU = 'C:\GUH'
    $GHU = "$env:SystemDrive\GUH"
    if (! (Test-Path $GHU) )
    { 
        # mkdir $GHU
        New-Item -ItemType Directory $GHU -Verbose
    }

    $files = ('AutoFetch.ps1', 'fetch-github-hosts.ps1')
    if ($Dev)
    {
        Write-Host '[Register-GithubHostsAutoUpdater]:Dev mode, copy local files.' -ForegroundColor Yellow
        $files | ForEach-Object {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $_) -Destination (Join-Path $GHU $_) -Force -Verbose
        }
    }
    else
    {
        # 中央镜像优先,失败回直连(与 Deploy-GithubHostsAutoUpdater 同策略,不再只走 gitee)
        $ghuMirror = if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }
        $ghuRawBase = 'https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/GithubHostsUpdater'
        $files | ForEach-Object {
            try
            {
                Invoke-RestMethod "$ghuMirror/$ghuRawBase/$_" > $GHU\$_
            }
            catch
            {
                Invoke-RestMethod "$ghuRawBase/$_" > $GHU\$_
            }
            # $home\desktop\$_
        }
    }

  
    #调用它(可以传参,也可以不传,使用默认参数) #号后面是传参示例
    #这里使用windows自带的powershell足够了,如果有需要的话可以检测使用pwsh(powershell7+)
    $pwshAvailability = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshAvailability)
    {
        # 优先尝试使用pwsh来执行
        Set-Alias powershell pwsh 
    }
    powershell -File "$GHU\AutoFetch.ps1 "  # -File $GHU\fetch-github-hosts.ps1 -shell powershell

}
#组织调用相关函数
Register-GithubHostsAutoUpdater-Archive -Dev:$Dev

#初次启动相应的任务
Start-ScheduledTask -TaskName Update-Githubhosts

#检查部署效果
Start-Sleep 5 #等待5秒钟，让更新操作完成
# 检查hosts文件修改情况(上一次更改时间)
$hosts = 'C:\Windows\System32\drivers\etc\hosts'
Get-ChildItem $hosts | Select-Object LastWriteTime #查看hosts文件更新时间(最有一次写入时间),文件内部的更新时间是hosts列表更新时间而不是文件更新时间
Get-Content $hosts | Select-Object -Last 5 #查看hosts文件的最后5行信息
Notepad $hosts # 外部打开记事本查看整个hosts文件

