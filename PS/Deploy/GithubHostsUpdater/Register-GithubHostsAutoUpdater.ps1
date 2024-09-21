
function Register-GithubHostsAutoUpdater-Archive
{
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
    $files | ForEach-Object {
        Invoke-RestMethod https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/GithubHostsUpdater/$_ > $GHU\$_
        # $home\desktop\$_ 
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
Register-GithubHostsAutoUpdater-Archive