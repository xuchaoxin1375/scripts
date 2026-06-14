<# 
.SYNOPSIS
部署CxxuPsModules

.DESCRIPTION

这里会尝试通过在线仓库导入 Deploy-GitForWindows 模块,会引入一些外部命令;
如果本地调整此脚本时,注意在线仓库中的版本可能不是最新的.
也可以考虑用本地导入的方式暂时代替默认的导入在线版本.
.NOTES
本地开发测试命令行参考: 
$scripts="C:/repos/scripts"
. $scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Dev # 默认无参数

#>
[CmdletBinding()]
param(
    # 仓库源
    [validateSet('gitee', 'github')]
    $RepoSource = 'gitee',
    $GithubMirror = 'https://gh-proxy.com',
    # 适用于开发(维护调整)的测试模式
    [switch]$Dev
    # [switch]$Force
)
Write-Host "[Deploy-CxxuPsModules]:开始运行CxxuPsModules部署脚本(来源:${RepoSource})..."
# 导入 Deploy-GitForWindows 命令(适合独立部署用户使用),分开放置确保灵活性
if($Dev)
{
    # 测试版:
    . $Scripts/PS/Deploy/Deploy-GitForWindows.ps1 -RepoSource $RepoSource
}
else
{
    # 正式版:
    $dgwUrl = "https://${RepoSource}.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-GitForWindows.ps1"
    # github镜像
    if ($RepoSource -eq 'github' -and $GithubMirror)
    {
        $dgwUrl = "$GithubMirror/$dgwUrl" 
        Write-Verbose "GithubMirror:[$GithubMirror]" -ForegroundColor Cyan 
    }

    Write-Host "拉取Deploy-GitForWindows 命令:[$dgwUrl]..."
    Invoke-RestMethod $dgwUrl > ~/dgw.ps1
    ~/dgw.ps1 -RepoSource $RepoSource -Verbose
}
function Get-CxxuPsModulePackage
{
    <# 
    .SYNOPSIS
    Github目前允许用户没有登录的情况下开源仓库包
    当主要方案无法成功下载部分代码时,尝试用github等其他的线路来下载
    #>
    [CmdletBinding()]
    param(
        $Directory = "$home/Downloads/CxxuPsModules",
        $url = 'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main',
        $outputFile = "scripts-$( Get-Date -Format 'yyyy-MM-dd--hh-mm-ss').zip"
    )
    $urls = @(
        'https://gitcode.net/xuchaoxin1375/scripts/-/archive/SourceCodePackage/scripts-SourceCodePackage.zip',
        'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main'
    )
    $index = 0
    foreach ($url in $urls)
    {

        Write-Host "${index}:[${url}]" -ForegroundColor cyan
        $index++
    }
    $UrlCode = Read-Host "Enter the Deploy Scheme code [0..$($urls.Count-1)](default:0)"
    if ($UrlCode.Trim() -eq '') { $UrlCode = 0 }
    $url = $urls[$UrlCode]
    if (!(Test-Path $Directory))
    {
        New-Item -ItemType Directory -Path $Directory -Verbose
    }
    $PackgePath = "$Directory/$outputFile"
    Write-Verbose "Downloading [$url] to $PackgePath" -Verbose
    Invoke-WebRequest -Uri $url -OutFile $PackgePath -Verbose
    return $PackgePath
}





 

#交互脚本
# $continue = Read-Host 'Install the CxxuPSModules in Default Parameters?
# [Input y to continue,n to exit and use your customized parameters to install it](y/n)'
# if ($continue)
# {
#     Deploy-CxxuPsModules -Verbose
# }
function Remove-CxxuPsModulesEnvVars
{
    <# 
    .SYNOPSIS
    供调试时使用
    移除CxxuPsModules的环境变量设置,包括PsModulePath,CxxuPsModulePath,Path中相关的设置,便于恢复相关的环境变量到初始状态

    #>
    param (
        
    )

    Remove-EnvVar -EnvVar CxxuPsModulePath
    Remove-EnvVarValue -EnvVar Path -ValueToRemove 'C:\PortableGit\bin' 
    Remove-EnvVarValue -EnvVar Path -ValueToRemove "$env:systemDrive\powershell\7"
    
}
# 调用函数执行安装(配置默认行为)
Deploy-CxxuPsModules -RepoSource $RepoSource -Verbose -Confirm