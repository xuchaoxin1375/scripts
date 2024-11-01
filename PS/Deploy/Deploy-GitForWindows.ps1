function Deploy-GitForwindows
{
    <# 
    .SYNOPSIS
    帮助windows系统用户一键部署Git for Windows
    .DESCRIPTION
    部署方案有多种,可以自动操作,如果失败,可以尝试分步骤操作
    此函数提供了灵活的参数组合供用户选择,理想情况下使用无参数版本就可以了
    但是无参数其实依赖于预设的默认参数,资源链接可能会过时,这种情况下需要用户自行寻找资源链接,然后使用相应的参数选项传递给此函数

    #>
    
    [CmdletBinding(DefaultParameterSetName = 'Online')]
    param(
        # 使用镜像加速下载git release文件
        [parameter(ParameterSetName = 'Online')]
        #如果不是用mirror,可以指定其为空字符串''
        $mirror = 'https://ghp.ci',
        # 注意区分这url是一个自解压文件还是压缩包文件
        # url可以是从git for windows 的二进制文件镜像站提供的文件下载链接(网页中右键复制指定文件的链接即可,注意是Portable版本的(一般后缀为.7z.exe),而不是普通的安装版)
        [parameter(ParameterSetName = 'Online')]
        $url = 'https://github.com/git-for-windows/git/releases/download/v2.46.2.windows.1/PortableGit-2.46.2-64-bit.7z.exe',

        [parameter(ParameterSetName = 'PackagePath')]
        # 出来上述指定提供链接的方法来下载,还可以自己手动下载,然后将保存的路径作为$PackagePath的取值来调用函数部署Git
        $PackagePath ,
        [switch]$InstallByGiteeScoop,
        
        $Path = 'C:\PortableGit',
        [switch]$IgnoreCache
    )
    Write-Verbose 'Try to get the lastest version of git portable version...'
    $latestRelease = Invoke-WebRequest -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Method Get | ConvertFrom-Json
    if ($latestRelease)
    {
        
        $LastUrls = $latestRelease.assets | Where-Object { $_.name -like '*PortableGit*' } | Select-Object -ExpandProperty browser_download_url
        $url = @($LastUrls) | Where-Object { $_ -like '*64*' } | Select-Object -First 1
    }
    else
    {
        
        Write-Warning 'Get the lastest version failed.Use default version link'
    }

    if ($InstallByGiteeScoop)
    {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

        Invoke-WebRequest -useb scoop.201704.xyz | Invoke-Expression

        scoop install git  #为当前用户安装,如果全局需要管理员权限
    }

    # 用New-Item的-force参数,即便路径已经存在,也不会报错(如果已经存在此目录,内部的也不会被覆盖(移除))
    New-Item -ItemType Directory $Path -Verbose -Force # -ErrorAction SilentlyContinue
    if ( $PSCmdlet.ParameterSetName -eq 'PackagePath' )
    {
        $Package = $PackagePath
    }
    else
    {

        $Package = "$Path\PortableGit.7z.exe"
        if ($IgnoreCache -or !(Test-Path $Package))
        {
            $url = "${mirror}/${url}".Trim('/')
            Write-Host "Downloading [$url] to $Package" -ForegroundColor Blue
            Invoke-WebRequest -Uri $url -OutFile $Package -Verbose
        }
        
    }
    # Write-Host "$Package  exist!" 
    # $Package = "$home/downloads/PortableGit.7z.exe"
    # 静默安装(默认解压到$Pacakge所在目录的PortableGit子目录)
    # & $Package -y #这种做法会抛到后台进程去执行安装,前台继续执行,可能会引发顺序命令顺序问题
    Write-Host 'Installing PortableGit...(it may take a while)' -ForegroundColor Blue

    Start-Process "$Package" -ArgumentList '-y' -Wait #使用Start-Process命令执行安装,配合-wait参数等待安装完成再执行后续内容
    #将目录转移到专门的目录下
    # Move-Item $Path\PortableGit "$env:SystemDrive\" -Verbose -Force
    Move-Item $Path\PortableGit\* "$path" -Verbose -Force
    # Expand-Archive -Path $Package -DestinationPath $Path 

    # 临时地(在当前powershell会话内,让git命令可以在任意目录下调用),如果需要后续任意目录下调用，需要添加git.exe所在目录到环境变量Path
    $GitBin = "$Path\bin"
    $env:Path = "$GitBin;$env:path" #临时添加到当前会话的Path变量中(如果需要添加到User或Machine级环境变量,建议把$env:Path替换为更准确的对应级别的变量值,防止污染)
    Write-Verbose 'Check the first value of the environment variable Path:' -Verbose
    $env:path -split ';' | Select-Object -First 1
    
    # 向系统注册git所在路径
    $UserPath = [System.Environment]::GetEnvironmentVariable('path', 'user') <# -split ';' #>
    
    #不会自动转换或丢失%var%形式的Path变量提取
    #采用reg query命令查询而不使用Get-ItemProperty 查询注册表,因为Get-ItemProperty 会自动转换或丢失%var%形式的Path变量
    $RawPathValue = reg query 'HKEY_CURRENT_USER\Environment' /v Path
    $RawPathValue = @($RawPathValue) -join '' #确保$RawPathValue是一个字符串
    # $RawPathValue -match 'Path\s+REG_EXPAND_SZ\s+(.+)'
    $RawPathValue -match 'Path\s+REG.*SZ\s+(.+)'
    $UserPath = $Matches[1] 
    Write-Verbose "Path value of [$env:Username] `n$($UserPath -split ';' -join "`n")" -Verbose
    # 将Git所在目录插入到系统环境变量Path中(这里仅操作User级别,不需要管理权限)
    $NewUserPath = "$GitBin;$UserPath"
    [System.Environment]::SetEnvironmentVariable('Path', $NewUserPath, 'user')
    
    #检查命令可用性
    Get-Command git | Format-List *
    # 可以选择列出潜在的所有git版本
    Get-Command git.exe* | Select-Object Name, Source, CommandType, Version
}

#检查当前命令是否可用
Get-Command Deploy-GitForwindows -Syntax
