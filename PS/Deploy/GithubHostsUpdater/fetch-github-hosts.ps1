
# $github_mirror = 'https://gh-proxy.com' #加速镜像站,可能会失效,也可能是部分时段失效,需要注意更新维护
Invoke-RestMethod 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy.psm1' | Invoke-Expression
# get functions or commands about mirror operations!
Get-Command *mirror* 
#check commands usage (syntax)
Get-Command Get-AvailableGithubMirrors -Syntax #use this is enough in general cases
Get-Command Get-SelectedMirror -Syntax
$github_mirror = Get-SelectedMirror   

function Update-GithubHosts-Archive
{
    <# 
    .SYNOPSIS
    函数会修改hosts文件，从github520项目获取快速访问的hosts
    .DESCRIPTION
    需要用管理员权限运行
    原项目提供了bash脚本,这里补充一个powershell版本的,这样就不需要打开git-bash
    .Notes
    与函数配套的,还有一个Deploy-GithubHostsAutoUpdater,它可以向系统注册一个按时执行此脚本的自动任务(可能要管理员权限运行),可以用来自动更新hosts
    .NOTES
    可以将本函数放到powershell模块中,也可以当做单独的脚本运行
    .LINK
    https://github.com/521xueweihan/GitHub520
    .LINK
    https://gitee.com/xuchaoxin1375/scripts/tree/main/PS/Deploy
    #>
    [CmdletBinding()]
    param (
        # 可以使用通用的powershell参数(-verbose)查看运行细节
        $hosts = 'C:\Windows\System32\drivers\etc\hosts',
        $remote = 'https://raw.hellogithub.com/hosts',
        # 如果原站不可用,考虑访问github,用加速站获取文件
        [switch]$UseLink2,
        $mirror = $github_mirror, #加速镜像站可能会失效,需要注意更新维护(https://ghproxy.link/)
        $remote_github_raw = 'https://raw.githubusercontent.com/521xueweihan/GitHub520/refs/heads/main/hosts',

        $UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.66 Safari/537.36'
    )
    # 创建临时文件
    # $tempHosts = New-TemporaryFile

    # 定义 hosts 文件路径和远程 URL
    Write-Warning "if failed,please use `-UseLink2` option to retry!"
    # 定义正则表达式
    $reg = '(?s)# GitHub520 Host Start.*?# GitHub520 Host End'


    # 读取 hosts 文件并删除指定内容,再追加新内容
    # $content = (Get-Content $hosts) 
    $content = Get-Content -Raw -Path $hosts
    # Write-Host $content
    #debug 检查将要替换的内容

    #查看将要被替换的内容片段是否正确
    # $content -match $reg
    $res = [regex]::Match($content, $reg)
    Write-Verbose '----start----'
    Write-Verbose $res[0].Value
    Write-Verbose '----end----'

    # return 
    $content = $content -replace $reg, ''

    # 追加新内容到$tempHosts文件中
    # $content | Set-Content $tempHosts
    #也可以这样写:
    #$content | >> $tempHosts 

    # 下载远程内容并追加到临时文件

    ## 根据需要修改$remote链接
    # $NewHosts = New-TemporaryFile
    if ($UseLink2)
    {
        $remote = $mirror + $remote_github_raw
        Write-Verbose $remote
    }

    $New = Invoke-WebRequest -Uri $remote -UseBasicParsing -UserAgent $UA #New是一个网络对象而不是字符串
    
    $New = $New.ToString() #清理头信息
    #移除结尾多余的空行,避免随着更新,hosts文件中的内容有大量的空行残留
       
    # 将内容覆盖添加到 hosts 文件 (需要管理员权限)
    # $content > $hosts
    $content.TrimEnd() > $hosts
    ''>> $hosts #使用>>会引入一个换行符(设计实验:$s='123',$s > example;$s >> example就可以看出引入的换行),
    # 这里的策略是强控,即无论之前Github520的内容和前面的内容之间隔了多少个空格,
    # 这里总是移除多余(全部)空行,然后手动插入一个空行,再追加新内容(Gith520 hosts)
    $New.Trim() >> $hosts

    
    Write-Verbose $($content + $NewContent)
    # 刷新配置
    ipconfig /flushdns
    
}
Update-GithubHosts-Archive