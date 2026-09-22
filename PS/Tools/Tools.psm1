function Get-PSConsoleHostHistory
{
    <# 
    .SYNOPSIS
    读取powershell上运行的历史命令行并返回
    可以配合其他过滤工具来查找命令
    .EXAMPLE
    PS> Get-PSConsoleHostHistory|sls group

    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=df_server1
    mysql --defaults-group-suffix=remote1
    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=_df_server1
    mysql --defaults-group-suffix=_df_server1
    mysql --defaults-group-suffix=_df_server1
    mysql --defaults-group-suffix=_df_server1
    Get-PowershellConsoleHostHistory|sls group
    Get-PSConsoleHostHistory|sls group
    .EXAMPLE
    PS> Get-PSConsoleHostHistory|sls mysql.*default |Get-ContentNL -AsString
    1:mysql --defaults-group-suffix=_remote1
    2:mysql --defaults-group-suffix=df_server1
    3:mysql --defaults-group-suffix=remote1
    4:mysql --defaults-group-suffix=_remote1
    5:mysql --defaults-group-suffix=_df_server1
    6:mysql --defaults-group-suffix=_df_server1
    7:mysql --defaults-group-suffix=_df_server1
    8:mysql --defaults-group-suffix=_df_server1
    9:mysqld --install MySQL55 --defaults-file="C:\phpstudy_pro\Extensions\MySQL5.5.29\my.ini"
    .EXAMPLE
    #⚡️[Administrator@CXXUDESK][~\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine][9:43:35][UP:3.54Days]
    PS> Get-PSConsoleHostHistory|sls mysql.*default

    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=df_server1
    mysql --defaults-group-suffix=remote1
    mysql --defaults-group-suffix=_remote1
    mysql --defaults-group-suffix=_df_server1
    #>
    $res = Get-Content $PSConsoleHostHistory
    return $res
}

function Get-CxxuPsModuleVersion
{
    param (
        
    )
    Get-RepositoryVersion -Repository $scripts
    
}



function Test-CommandAvailability
{
    <# 
    .SYNOPSIS
    测试命令是否可用,并根据gcm的测试结果给出提示,在命令不存在的情况下不报错,而是给出提示
    主要简化gcm命令的编写
    .DESCRIPTION
    命令行程序可用的情况下,想要获取其路径,可以访问返回结果的.Source属性
    .PARAMETER CommandName
    命令名称
    
    .EXAMPLE
    # 测试命令不存在
    PS> Test-CommandAvailability 7zip
    WARNING: The 7zip is not available. Please install it or add it to the environment variable PATH.
    .EXAMPLE
    # 测试命令存在
    PS> Test-CommandAvailability 7z

    CommandType     Name                                               Version    Source
    -----------     ----                                               -------    ------
    Application     7z.exe                                             0.0.0.0    C:\ProgramData\scoop\shims\7z.exe
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (! $command)
    {
        Write-Verbose "The $CommandName is not available. Please try a another similar name or install it or add it to the environment variable PATH."
        return $null
    }
    return $command
}




 
function Start-SleepWithProgress
{
    <# 
    .SYNOPSIS
    显示进度条等待指定时间
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Seconds
    )
    if($Seconds -le 0)
    {
        Write-Warning "The sleep time seconds is $Seconds,jump sleep!"
        return $False
    }
    else
    {
        Write-Host "Waiting for $Seconds seconds..."
    }
    for ($i = 0; $i -le $Seconds; $i++)
    {
        $percentComplete = ($i / $Seconds) * 100
        # 保留2位小数
        $percentComplete = [math]::Round($percentComplete, 2)
        Write-Progress -Activity "Waiting..." -Status "$i seconds elapsed of $Seconds ($percentComplete%)" -PercentComplete $percentComplete
        Start-Sleep -Seconds 1
    }

    Write-Progress -Activity "Waiting..." -Completed
}


function Set-OpenWithVscode
{
    <# 
    .SYNOPSIS
    设置 VSCode 打开方式为默认打开方式。
    .DESCRIPTION
    直接使用powershell的命令不是很方便
    这里通过创建一个临时的reg文件,然后调用reg import命令导入
    支持添加右键菜单open with vscode 
    也支持移除open with vscode 菜单
    你可以根据喜好设置标题,比如open with Vscode 或者其他,open with code之类的名字
    .EXAMPLE
    简单默认参数配置
    Set-OpenWithVscode

    .EXAMPLE
    完整的参数配置
    Set-OpenWithVscode -Path "C:\Program Files\Microsoft VS Code\Code.exe" -MenuName "Open with VsCode"
    .EXAMPLE
    移除右键vscode菜单
    PS> Set-OpenWithVscode -Remove
    #>
    <# 
    .NOTES
    也可以按照如下格式创建vscode.reg文件，然后导入注册表

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\*\shell\VSCode]
    @=$MenuName
    "Icon"="C:\\Program Files\\Microsoft VS Code\\Code.exe"

    [HKEY_CLASSES_ROOT\*\shell\VSCode\command]
    @="$PathWrapped \"%1\""

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\Directory\shell\VSCode]
    @=$MenuName
    "Icon"="C:\\Program Files\\Microsoft VS Code\\Code.exe"

    [HKEY_CLASSES_ROOT\Directory\shell\VSCode\command]
    @="$PathWrapped \"%V\""

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode]
    @=$MenuName
    "Icon"="C:\\Program Files\\Microsoft VS Code\\Code.exe"

    [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode\command]
    @="$PathWrapped \"%V\""

    #>

    [CmdletBinding(DefaultParameterSetName = "Add")]
    param (
        [parameter(ParameterSetName = "Add")]
        $Path = "C:\Program Files\Microsoft VS Code\Code.exe",
        [parameter(ParameterSetName = "Add")]
        $MenuName = "Open with VsCode",
        [parameter(ParameterSetName = "Remove")]
        [switch]$Remove
    )
    Write-Verbose "Set [$Path] as Vscode Path(default installation path)" -Verbose
    # 定义 VSCode 安装路径
    #debug
    # $Path = "C:\Program Files\Microsoft VS Code\Code.exe"
    $PathForWindows = ($Path -replace '\\', "\\")
    $PathWrapped = '\"' + $PathForWindows + '\"' # 由于reg添加右键打开的规范,需要得到形如此的串 \"C:\\Program Files\\Microsoft VS Code\\Code.exe\"
    $MenuName = '"' + $MenuName + '"' # 去除空格

    # 将注册表内容作为多行字符串保存
    $AddMenuRegContent = @"
    Windows Registry Editor Version 5.00
   
       [HKEY_CLASSES_ROOT\*\shell\VSCode]
       @=$MenuName
       "Icon"="$PathForWindows" 
   
       [HKEY_CLASSES_ROOT\*\shell\VSCode\command]
       @="$PathWrapped \"%1\""
   
       Windows Registry Editor Version 5.00
   
       [HKEY_CLASSES_ROOT\Directory\shell\VSCode]
       @=$MenuName
       "Icon"="$PathForWindows" 
   
       [HKEY_CLASSES_ROOT\Directory\shell\VSCode\command]
       @="$PathWrapped \"%V\""
   
       Windows Registry Editor Version 5.00
   
       [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode]
       @=$MenuName
       "Icon"="$PathForWindows" 
   
       [HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode\command]
       @="$PathWrapped \"%V\""
"@  
    $RemoveMenuRegContent = @"
    Windows Registry Editor Version 5.00

[-HKEY_CLASSES_ROOT\*\shell\VSCode]

[-HKEY_CLASSES_ROOT\*\shell\VSCode\command]

[-HKEY_CLASSES_ROOT\Directory\shell\VSCode]

[-HKEY_CLASSES_ROOT\Directory\shell\VSCode\command]

[-HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode]

[-HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode\command]
"@
    $regContent = $AddMenuRegContent
    # if ($Remove)
    if ($PSCmdlet.ParameterSetName -eq "Remove")
    {
        # 执行 reg delete 命令删除注册表文件
        Write-Verbose "Removing VSCode context menu entries..."
        $regContent = $RemoveMenuRegContent

    }
    # 检查 VSCode 是否安装在指定路径
    elseif (Test-Path $Path)
    {
          
        Write-Verbose "The specified VSCode path exists. Proceeding with registry creation."
    }
    else
    {
        Write-Host "The specified VSCode path does not exist. Please check the path."
        Write-Host "use -Path to specify the path of VSCode installation."
    }

    Write-Host "Creating registry entries for VSCode:"
    
    
    # 创建临时 .reg 文件路径
    $tempRegFile = [System.IO.Path]::Combine($env:TEMP, "vs-code-context-menu.reg")
    # 将注册表内容写入临时 .reg 文件
    $regContent | Set-Content -Path $tempRegFile
    
    # Write-Host $AddMenuRegContent
    Get-Content $tempRegFile
    # 删除临时 .reg 文件
    # Remove-Item -Path $tempRegFile -Force

    # 执行 reg import 命令导入注册表文件
    try
    {
        reg import $tempRegFile
        Write-Host "Registry entries for VSCode have been successfully created."
    }
    catch
    {
        Write-Host "An error occurred while importing the registry file."
    }
    Write-Host "Completed.Refresh Explorer to see changes."
}

function Get-RepositoryVersion
{
    <# 
    通过git提交时间显示版本情况
    #>
    param (
        $Repository = './'
    )
    $Repository = Resolve-Path $Repository
    Write-Verbose "Repository:[$Repository]" -Verbose
    Write-Output $Repository
    Push-Location $Repository
    git log -1
    Pop-Location
    # Set-Location $Repository
    # git log -1 
    # Set-Location -

    # git log -1 --pretty=format:'%h - %an, %ar%n%s'
    
}


function pow
{
    [CmdletBinding()]
    param(
        [double]$base,
        [double]$exponent
    )
    return [math]::pow($base, $exponent)
}

# function invoke-aria2Downloader
# {
#     param (
#         $url,
#         [Alias('spilit')]
#         $s = 16,
        
#         [Alias('max-connection-per-server')]
#         $x = 16,

#         [Alias('min-split-size')]
#         $k = '1M'
#     )
#     aria2c -s $s -x $s -k $k $url
    
# }


function Get-MsysSourceScript
{
    <# 
    .SYNOPSIS
    获取更新msys2下pacman命令的换源脚本,默认换为清华源
    
    .NOTES
    将输出的脚本复制到剪切板,然后粘贴到msys2命令行窗口中执行
    #>
    param (

    )
    $script = { sed -i 's#https\?://mirror.msys2.org/#https://mirrors.tuna.tsinghua.edu.cn/msys2/#g' /etc/pacman.d/mirrorlist* }
    
    return $script.ToString()
}

function Set-CondaSource
{
    param (
        
    )
    
    #备份旧配置,如果有的话
    if (Test-Path "$userprofile\.condarc")
    {
        Copy-Item "$userprofile\.condarc" "$userprofile\.condarc.bak"
    }
    #写入内容
    @'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  msys2: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  bioconda: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  menpo: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch-lts: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  simpleitk: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  deepmodeling: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/
'@ >"$userprofile\.condarc"

    Write-Host 'Check your conda config...'
    conda config --show-sources
}


function Get-BeijingTime
{
    # 获取北京时间的函数
    # 通过API获取北京时间
    $url = 'http://worldtimeapi.org/api/timezone/Asia/Shanghai'
    $response = Invoke-RestMethod -Uri $url
    $beijingTime = [DateTime]$response.datetime
    return $beijingTime
}

