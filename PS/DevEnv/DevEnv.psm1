<#
DevEnv 模块:语言工具链与编辑器开箱(Python/conda/C++/编辑器/补全栈)。
从 Deploy.psm1 迁入: Deploy 回归新机收尾本义,语言工具链归此模块;
调用方命令名不变(自动发现同名模块)。
#>

function Install-BasicSoftwares
{
    param (
        $Mirror
    )
    New-Item -ItemType 'directory' -Path "$env:USERPROFILE\scoop\buckets\scoop-cn\bucket"
    New-Item -ItemType 'directory' -Path "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\7-zip"
    New-Item -ItemType 'directory' -Path "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git"
    # 7zip软件资源
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/bucket/7zip.json -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\bucket\7zip.json"
    #注册7-zip的右键菜单等操作
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/7-zip/install-context.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\7-zip\install-context.reg"
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/7-zip/uninstall-context.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\7-zip\uninstall-context.reg"
 
    # git软件资源
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/bucket/git.json -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\bucket\git.json"
      
    #注册git右键菜单等操作
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/git/install-context.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git\install-context.reg"
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/git/uninstall-context.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git\uninstall-context.reg"
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/git/install-file-associations.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git\install-file-associations.reg"
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/scripts/git/uninstall-file-associations.reg -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\scripts\git\uninstall-file-associations.reg"
    #注册aria2
    Invoke-RestMethod -Uri $mirror/https://raw.githubusercontent.com/duzyn/scoop-cn/master/bucket/aria2.json -OutFile "$env:USERPROFILE\scoop\buckets\scoop-cn\bucket\aria2.json"
  
    # 安装时注意顺序是 7-Zip, Git, Aria2
    # 基础软件可以考虑全局安装(所有用户可以用,这需要管理员权限)
    scoop install scoop-cn/7zip -g
    scoop install scoop-cn/git -g
    # scoop install scoop-cn/aria2 -g
    
}

function Deploy-Python
{
    New-Junction -Path $env:APPDATA\python -Target $env:pythonPacks_Home_Conv
}
# function Deploy-vscodeDoubleSystem{

# }

function Deploy-CppVscodeThere
{
    param(
        $path = '.vscode'
    )
    if (!(Test-Path '.vscode'))
    {
        # Get-ChildItem $configs\CppVscodeConfig\
        mkdir .vscode
        
    }
    cpFVR $configs\CppVscodeConfig\* .vscode
    Write-SeparatorLine
    Write-Output "@path=$path"

}

function Deploy-PipConfig
{
    <# 
    .SYNOPSIS
    配置pip的国内加速源
    .NOTES 
    提供的镜像可能不是最新的,如果不可用,请联网搜索获取可用镜像url.
    #>
    param (
        $Mirror = "https://mirrors.ustc.edu.cn/pypi/simple"
    )
    pip config set global.index-url $mirror
    $config = "$env:APPDATA/pip/pip.ini"
    if(Test-Path $config)
    {
        Get-Content $config
    }
    pip config list
    # 1. 定义哈希表 (使用 @{ } 语法)
    $pypi_mirrors = @{
        Tencent = "https://mirrors.cloud.tencent.com/pypi/simple/"
        Aliyun  = "https://mirrors.aliyun.com/pypi/simple/"
        PKU     = "https://mirrors.pku.edu.cn/pypi/web/simple"
        ZJU     = "https://mirrors.zju.edu.cn/pypi/web/simple"
        NJU     = "https://mirror.nju.edu.cn/pypi/web/simple"
        TUNA    = "https://pypi.tuna.tsinghua.edu.cn/simple"
        USTC    = "https://mirrors.ustc.edu.cn/pypi/simple"
    }

    # 2. 直接输出整个哈希表
    Write-Warning "如果镜像不可用或被限流403,可以更换镜像."
    Write-Host "当前使用的镜像:[$Mirror]"
    
    return $pypi_mirrors
}

function Deploy-UvConfig
{
    <# 
    .SYNOPSIS
    部署uv的全局配置;
    自动判断系统平台,创建不同的路径的配置文件(uv.toml)
    # 国内高校源聚合列表:https://help.mirrorz.org/pypi/
    # 其他企业平台自行搜索
    #>
    param (
        $Path = "~/.config/uv/uv.toml",
        $Mirror = "https://mirrors.aliyun.com/pypi/simple/"
    )
    $uvConfig = @"
[[index]]
url = `"$Mirror`"
default = true
"@

    # 5.1 无 $IsWindows 自动变量:用 PSEdition 兜底(Desktop 即 Windows),排雷未来降档
    if (($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true))
    {
        $Path = "$env:AppData\uv\uv.toml"
        New-Item -ItemType File -Path $Path -Force -Verbose
    }
    $uvConfig | Set-Content $Path -Verbose
    Write-Host "检查配置文件内容:"
    Get-Content $Path
    # 其他源:
    # $pypi_tencent="https://mirrors.cloud.tencent.com/pypi/simple/"
    # $pypi_pku="https://mirrors.pku.edu.cn/pypi/web/simple"
    # $pypi_zju="https://mirrors.zju.edu.cn/pypi/web/simple"
    # $pypi_nju="https://mirror.nju.edu.cn/pypi/web/simple"
    # $pypi_aliyun="http://mirrors.aliyun.com/pypi/simple/"
    # 1. 定义哈希表 (使用 @{ } 语法)
    $pypi_mirrors = @{
        Tencent = "https://mirrors.cloud.tencent.com/pypi/simple/"
        Aliyun  = "https://mirrors.aliyun.com/pypi/simple/"
        PKU     = "https://mirrors.pku.edu.cn/pypi/web/simple"
        ZJU     = "https://mirrors.zju.edu.cn/pypi/web/simple"
        NJU     = "https://mirror.nju.edu.cn/pypi/web/simple"
        USTC    = "https://mirrors.ustc.edu.cn/pypi/simple"
    }

    # 2. 直接输出整个哈希表
    Write-Warning "如果镜像不可用或被限流403,可以更换镜像."
    Write-Host "当前使用的镜像:[$Mirror]"
    
    return $pypi_mirrors

    
}
function Deploy-AndroidStudio_depends
{
    param (
        
    )
    Write-Output "gradle_user_home `\n; androidDepends"
    # if (Test-Path $env:androidDepends)
}





function Deploy-Typora
{
    <# 
    .SYNOPSIS
    导入部分typora配置
    .DESCRIPTION
    部署typora:包括主题以及快捷键配置导入
    可选的老版本typora破解补丁打入
    可选设置markdown文件的默认打开方式(调用assoc和ftype命令进行设置,这会改动注册表)


    .Parameter TyporaHome
    指定typora安装目录
    .Parameter InstalledByBrew
    指定typora是否是通过brew安装的
    .Notes
    可能需要管理员权限运行
    细节设置(自动保存,关闭语法检查,选择指定主题等不会还原需要手动选择)
    .Notes
    部署需要在具有pwshEnv环境的命令行下执行,否则会先导入环境变量,然后进行下一步
    如果使用的版本是已经自带激活的,就可以不使用PatchWinmm开关导入补丁,避免多余的副作用
    .Notes
    较新版本的typroa设置选项中提供了资源管理器右键菜单选项,可以右键新建markdown文件(md)
    https://support.typora.io/New-File-in-Context/
    typora安装版可能会注册打开方式:
        Typora.markdown="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.md="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.mdown="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.mkd="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.mmd="C:\Program Files\Typora\Typora.exe" "%1"
        Typora.text="C:\Program Files\Typora\Typora.exe" "%1"

    有的魔改版本提供了注册了格式关联,右键菜单打开方式的bat脚本
    但是注意,如果是用户创建的通过typora打开指定目录的快捷方式
    (这里头的打开方式已经被写死在快捷方式的属性中,不会受markdown本体打开方式设置的影响),
    尤其是对于安装了多个不同版本的typora的环境下

    .EXAMPLE
    为通过scoop安装的typora进行部署
    Deploy-Typora -TyporaHome $scoop_home\apps\typora\current
    #>
    [CmdletBinding(DefaultParameterSetName = 'windows')]
    param(
        # [switch]$InstalledByScoop,

        # typora安装目录下的主题和配置文件(包含快捷键等)
        $TyporaHome = "$scoop_home\apps\typora\current",# for windows
        $TyporaConfig = "$home\AppData\Roaming\typora\conf", # for windows
        # 其他
        [parameter(ParameterSetName = 'windows')]
        [switch]$PatchWinmm,
        [parameter(ParameterSetName = 'windows')]
        [switch]$OpenWithTypora,

        [parameter(ParameterSetName = 'macos')]
        [switch]$InstallByBrew
    )

    # Write-Host 'close the typora to apply the settings!'
        
    # check any typora process to kill
    

    if (Get-Process -Name 'typora' -ErrorAction SilentlyContinue)
    {
        Write-Host "The process 'typora' exists."
        $reply = Read-Host -Prompt "press enter 'y' to continue"

        if ($reply -eq 'y')
        {

            Stop-Process -Name 'typora'
        
        }
        else
        {
            Write-Host 'The operation canceled!'
            return
        }
    }
    else
    {
        Write-Host "The process 'typora' does not exist."
    }
    
    Write-Host 'continue to deploy...' -BackgroundColor Yellow

    # 5.1 无 $IsWindows 自动变量:用 PSEdition 兜底(Desktop 即 Windows),排雷未来降档
    if (($PSEdition -eq 'Desktop') -or ($IsWindows -eq $true))
    {
        # 导入专门的环境变量
        Update-PwshEnvIfNotYet
        # 要求管理员权限
        Confirm-AdminPermission

        # 开始建立链接(使用symboliclink支持跨分区的链接文件夹和文件通吃)

        # 设置注册.md扩展名为文件类型MarkdownFile
        # 这里的.md是标准markdown文件的扩展名,而MarkdownFile是可以宽松自定义的名字，也可以是别的名字,但是要注意在后面的ftype命令中使用同一个文件类型名字
        cmd /c assoc .md=MarkdownFile 


        # 注册Markdown文件的打开方式(其中MarkdownFile是上面assoc命令设置的文件类型名)🎈
        # 这个命令不会设置默认打开方式,只是注册了打开方式,除非此前没有其他程序注册打开方式
        if($OpenWithTypora)
        {

            cmd /c ftype MarkdownFile=$TyporaHome\Typora.exe %1 
            # 如果要取消,可以使用下面的命令:(=后面留空即可),但是可能不会完全取消,需要检查是否有同地位的注册语句关联相同后缀,设置后可以用新的值覆盖
            cmd /c ftype MarkdownFile= 

        }

        $items = @($Typora_Themes , $TyporaConfig)
        # 移除原有的相关目录,以便能够创建新的符号链接
        $items | ForEach-Object {
            if(Test-Path $_)
            {
                Remove-Item -Path $_ -Recurse -Force -Verbose
            }
        } 
    }


    
    # 按照原来的位置创建新的符号链接
    # $items | ForEach-Object {
    # } 
    $Typora_Themes_backup = "$configs/Typora/themes"
    $TyporaConfig_backup = "$configs/Typora/conf"
    if($InstallByBrew)
    {
        $TyporaHome = "$HOME/Library/Application Support/abnerworks.Typora/themes"
        Move-Item $TyporaHome "${TyporaHome}.bak"
        # 配置快捷键等.
        # $TyporaConfig=""
        New-Item -ItemType SymbolicLink -Path $TyporaHome -Target $Typora_Themes_backup -Verbose

    }
    else
    {
        # windows 方案
        New-Item -ItemType SymbolicLink -Path $Typora_Themes -Target $Typora_Themes_backup -Force -Verbose
        New-Item -ItemType SymbolicLink -Path $TyporaConfig -Target $TyporaConfig_backup -Force -Verbose
    }
        
    # New-Item -ItemType SymbolicLink -Path $TyporaConfig -Target $TyporaConfig_backup -Force -Verbose
    if($PatchWinmm)
    {
            
        $winmm = "$TyporaHome\winmm.dll"
        $patcher = "$configs\typora\winmm.dll"
        # 打入破解补丁(替换winmm.dll)不一定对所有版本通用(最高1.9.5)
        New-Item -ItemType SymbolicLink -Path $winmm -Value $patcher -Force
    }

    
    $Note = @'
    The basic settings need you to manually set(the config.json just provide the advanced part settings
         the themes settings need you to chose manually , too; 
         It will be provide in the appearance->themes dropdown
    just set the preference->markdown->math formula checkboxes!
         after that , restart the typora to apply the settings!
'@
    Write-Host $Note -ForegroundColor Magenta
}
#下面这三个+ 函数是用来启用网络共享和网络发现的并部署带有使用说明文档的共享文件夹
#还需要外部的一个Grant-PermissionToPath函数


function Deploy-GitConfig
{
    <# 
    .SYNOPSIS
    使用hardlink强制将git配置文件用$configs中的配置取代
    #>
    Update-PwshEnvIfNotYet -Mode Vars
    # 使用硬链接会有权限问题,这里用复制文件的方式代替
    $t = "$scripts\config\.gitconfig" # "$configs\user\.gitconfig"
    $p = "$home\.gitconfig"
    # Copy-Item $t $p -Force -Verbose
    # 使用符号链接支持跨分区
    New-Item -ItemType SymbolicLink -Path $p -Value $t -Verbose -Force
}
function Deploy-VsCodeSettings_depends
{
    <# redifine the extensions path to D district #>
    if (!([Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544'))
    {

        Write-Output 'current powershell run without administrator privilege!;请手动打开管理模式的terminal.'
        return
    }
    if (Test-Path $env:vscode_Depends)
    {
        Write-Output 'you run the script after vscode have been installed!,this will remote the old home to create the coresponding symbolic link!'
        Remove-Item $env:vscode_Depends
    }
    Write-Output 'pre-set the directory as a symbolic link to D partition.. '
    Write-Output 'sleep for 3 senconds for you to think of it whether to stop...'
    # when you debug,you can set the time longer(such as 10 seconds)
    countdown 10
    Write-Output "repointer the software location:$env:vscode_home->$env:vscode_Home_D "
    New-Junction $env:vscode_home $env:vscode_Home_D
    # assure the New-Junction could run successfully
    Write-Output "New-Junction $env:vscode_Depends $env:vscode_Depends_D"
    if (
        !(Test-Path $env:vscode_Depends_D)
    )
    {
        # 读取键盘输入(read input by read-host)
        $Inquery = Read-Host -Prompt "there is not $env:vscode_Depends_D ; to create the corresponding directory, enter 'y' to continue😎('N' to exit the process!)  "
        if ($Inquery -eq 'y')
        {
            mkdir $env:vscode_Depends_D
        }
        else
        {
            return
        }
    }
        
    New-Junction $env:vscode_Depends $env:vscode_Depends_D
    #deploy the settings
    cpFVR $configs\vscodeSettings\* $env:vscodeConfHome
}

function Deploy-WtSettings
{
    <# 
    .SYNOPSIS
    部署windows terminal的配置文件
    
    .EXAMPLE
    #Admin[pwsh][cxxu1375@CXXU][~][16:58:16]
 Deploy-WtSettings -InstalledByScoop -WtScoopConfig C:\scoop\apps\windows-terminal\current\settings\settings.json
VERBOSE: Performing the operation "Create Symbolic Link" on target "Destination: C:\scoop\apps\windows-terminal\current\settings\settings.json".

    Directory: C:\scoop\apps\windows-terminal\current\settings

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
la---           2026/6/14    16:58              0 settings.json -> C:\repos\scripts\config\wtConf.json
    .Notes
    PS [C:\repos\scripts]> gv wt*

    Name                           Value
    ----                           -----
    wtConf_Home                    C:\Users\cxxu\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalEnabled
    wtConf_Home_Pattern            C:\Users\cxxu\AppData\Local\Packages\Microsoft.WindowsTerminal_*\LocalEnabled
    wtPortableConf_Home            C:\Users\cxxu\AppData\Local\Microsoft\Windows Terminal
    wtStoreConf_Home_Pattern       C:\Users\cxxu\AppData\Local\Packages\Microsoft.WindowsTerminal_*\LocalEnabled
    #>
    [CmdletBinding()]
    param(
        #指定是否为免安装版本的windows terminal
        # $Portable = '' 
        [switch]$Portable,
        [switch]$InstalledByScoop,
        $WtScoopConfig = "$scoop_global\apps\windows-terminal\current\settings\settings.json",
        [switch]$Force
    )
    Update-PwshEnvIfNotYet -Mode Vars
    # 备份的配置文件路径
    $ConfigBackup = "$scripts\config\wtConf.json"
    $WtConfig = "$wtConf_Home\settings.json"
    $WtPortableConfig = "$wtPortableConf_Home\settings.json"
    if ($Force)
    {
        $items = @($WtConfig, $WtPortableConfig)
        
        $items | ForEach-Object { 
            if ((Test-Path $_))
            {

                Remove-Item -Path $_ -Force -Verbose 
            }
        }
    }
    # 根据不同版本的wt,部署配置文件
    if ($Portable)
    {
        # Copy-Item -Path $ConfigBackup -Destination $WtPortableConfig -Verbose -Force
        New-Item -ItemType SymbolicLink -Path $WtPortableConfig -Target $ConfigBackup -Verbose -Force
    }
    elseif ($InstalledByScoop)
    {
        # Copy-Item -Path $ConfigBackup -Destination $WtPortableConfig -Verbose -Force
        if(Test-Path $WtScoopConfig)
        {
            Write-Verbose "$WtScoopConfig exist"
        }
        else
        {
            $WtScoopConfig = "$scoop_home\apps\windows-terminal\current\settings\settings.json"
            Write-Verbose "$wtScoopConfig does not exist,try another candidate path:[$wtScoopConfig]"

        }
        New-Item -ItemType SymbolicLink -Path $WtScoopConfig -Target $ConfigBackup -Verbose -Force
    }
    else
    {
        # 部署安装版的配置文件👺
        New-Item -ItemType SymbolicLink -Path $WtConfig -Value $ConfigBackup -Force -Verbose
    }
}

function Deploy-MiniforgeConfig
{
    <# 
    .SYNOPSIS
    设置miniforge的配置文件;

    优先使用conda(miniforge的conda命令已经采用mamba求解器加速,国内各镜像源主要提供的是对conda命令的支持)
    mamba命令在虚拟环境激活后作为兼容项存在.但是不建议混用.

    修改默认环境存放位置,例如~/.conda/envs
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("conda", "mamba", "all")]
        $Mode = "conda",
        
        $Condabin = "",
        [Alias('Override')]
        [ValidateSet('Copy', 'SymbolicLink', 'Hardlink', 'Junction', '')]
        $OverrideMode = ""
    )
    # 从本代码仓库中预设的conda配置文件进行配置部署.
    $condarcBak = "$Scripts/config/miniforge/.condarc"
    $mambarcBak = "$Scripts/config/miniforge/.mambarc"
    $condaAvailability = Get-Command conda -ErrorAction SilentlyContinue
    # 准备环境变量condabin
    $condabinScoop = "$scoop_apps/miniforge/current/condabin"
    if(!$Condabin)
    {
        $Condabin = $condabinScoop
    }
    if(Test-Path $Condabin)
    {
        # 如果condabinScoop路径存在,则添加到环境变量中.
        Write-Host "[condabin]:路径${condabin}存在."
        #注意避免重复添加(add-envvar命令已经实现避免重复的逻辑)
        # Add-EnvVar Path $condabinScoop -Verbose
        # Get-EnvPath
        # 临时添加到Path
        if($env:Path -notlike "*Condabin*")
        {
            Write-Host "Add temp ${condabin} to PATH temporarily."
            $env:path = "${Condabin};$env:path"
        }
        else
        {
            Write-Host "Condabin path has already been added to Path."
        }
        $env:path -split ';'

    }
    else
    {
        Write-Warning "The [$Condabin] does not exist!"
    }
    # 默认选择
    if($Mode -eq "conda")
    {

        if($condaAvailability )
        {
            if($OverrideMode)
            {
                if($OverrideMode -eq 'Copy')
                {
                    Copy-Item $condarcBak ~/.condarc -Force -Verbose
                }
                else
                {

                    New-Item -ItemType $OverrideMode -Path ~/.condarc -Value $condarcBak -Verbose -Force
                }
                
            }
            else
            {
                
                # 设置安全的环境存放目录
                conda config --add envs_dirs ~/.conda/envs
                # 关闭自动激活conda环境
                conda config --set auto_activate_base false
                # 显示通道url
                conda config --set show_channel_urls yes
                # 设置镜像加速
                conda config --add channels conda-forge
            }
            # 更新镜像配置后清理缓存
            conda clean -i
            # 检查相关配置文件位置:
            conda config --show-source
        }
        else
        {
            Write-Error "[Conda] is not available."
        }
    }
    # deprecated
    if($Mode -eq "mamba")
    {
        if($OverrideMode)
        {
            if($OverrideMode -eq 'Copy')
            {
                Copy-Item $mambarcBak ~/.mambarc -Force -Verbose
            }
            else
            {

                New-Item -ItemType $OverrideMode -Path ~/.mambarc -Value $mambarcBak -Verbose -Force
            }
            # 避免和.condarc中的custom_channels的影响,使用mamba的情况下移除掉~/.condarc,不要混用.
            # 反之,conda不受~/.mambarc的影响,因此可以不用清除.
            Remove-Item ~/.condarc -Verbose -ErrorAction SilentlyContinue
            mamba clean -i
            return
        }
        # 计算mamba路径
        $mambaAvailability = Get-Command mamba -ErrorAction SilentlyContinue
        if ($mambaAvailability)
        {
            
            Get-Command mamba | Select-Object Source
            # 列出配置文件
            mamba config sources
            # 配置channel
            mamba config append channels conda-forge
            # mamba专用通道字段:
            
            # 将mamba专属配置写入到`~/.mambarc`中
            # 移除旧值,防止重叠
            # mamba config get mirrored_channels # 
            # mamba config remove-key mirrored_channels #移除
            
            # 添加mirrored_channels(mamba专用字段)
            $existed = Select-String -Path ~/.mambarc -Pattern 'mirrored_channels:'
            $mc = @"
mirrored_channels:
  conda-forge:
    - https://mirrors.ustc.edu.cn/anaconda/cloud/conda-forge

"@  # 保留一个换行符,防止粘连
            if(! $existed)
            {
                $mc | Add-Content "$env:USERPROFILE/.mambarc"
            }
            # 设置默认的虚拟环境存放位置.
            mamba config append envs_dirs ~/.conda/envs
            # 自动导入mamba环境(便于mamba activate等命令生效.)
            mamba shell init --shell powershell --root-prefix=~/.local/share/mamba
            # end
            # 更新镜像配置后清理缓存
            mamba clean -i
            # 检查配置结果
            mamba config list
        }
        else
        {
            Write-Warning "[Mamba] is not available now"
            Write-Warning "Try add [condabin] path to your system environment variable 'Path'."
            # Write-Warning "Run following command (in powershell) to get [mamba] localtion:"
            # Write-Host "`t conda init # if not yet "
            # Write-Host "`t conda activate"
            # Write-Host "`t Get-Command mamba | Select-Object Source"
            Write-Warning "Run mamba on a new shell session:"
            Write-Host "`t mamba activate"

        }
    }
    # deprecated
    if($Mode -eq "all")
    {
        if($OverrideMode)
        {
            if($OverrideMode -eq 'Copy')
            {
                Copy-Item $condarcBak ~/.condarc -Force -Verbose
                Copy-Item $mambarcBak ~/.mambarc -Force -Verbose
            }
            else
            {

                New-Item -ItemType $OverrideMode -Path ~/.condarc -Value $condarcBak -Verbose -Force
                New-Item -ItemType $OverrideMode -Path ~/.mambarc -Value $mambarcBak -Verbose -Force
            }
        }
    }
    Write-Host "检查配置文件内容:..."
    Get-Content ~/.condarc 
    Get-Content ~/.mambarc -ErrorAction SilentlyContinue
}

function Get-CxxuProxyUrl
{
    # 读取代理环境变量：调用方显式 -Proxy 优先，这里只负责环境变量。
    # 大小写都认，顺序 HTTPS > HTTP > ALL，取第一个非空值。
    foreach ($name in @('HTTPS_PROXY', 'https_proxy', 'HTTP_PROXY', 'http_proxy', 'ALL_PROXY', 'all_proxy'))
    {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value))
        {
            return $value.Trim()
        }
    }
    return ''
}

function Get-CxxuDownloadUrls
{
    # 有代理时直连优先（代理就是加速通道）；无代理时镜像优先、直连回退。
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Mirror,
        [string]$ProxyUrl
    )
    if ([string]::IsNullOrWhiteSpace($Mirror)) { $Mirror = 'https://gh-proxy.com' }
    # 只有 GitHub 域才套镜像；本地/其他站点直接走原地址，避免无意义的前缀请求。
    if ($Url -notmatch '^https?://(?:github\.com|raw\.githubusercontent\.com|codeload\.github\.com|api\.github\.com)/')
    {
        return @($Url)
    }
    $mirrorUrl = $Mirror.TrimEnd('/') + '/' + $Url
    if ([string]::IsNullOrWhiteSpace($ProxyUrl)) { return @($mirrorUrl, $Url) }
    return @($Url, $mirrorUrl)
}

function Get-CxxuDepsMirrorAsset
{
    <#
    .SYNOPSIS
    返回 scripts-deps 转存仓库里固定版本的资产地址；没有对应架构时返回 $null。
    .DESCRIPTION
    版本固定在下方 $table：上游发布新版本后，先跑 PS/Deploy/Sync-GithubDepsMirror.ps1 转存，
    再同步改这里的 Tag 与文件名。转存仓库只做原样转存，不自动跟随上游。
    下载前缀默认 https://github.com/xuchaoxin1375/scripts-deps/releases/download，
    可用 $env:PsDepsMirror 整体替换（自建镜像/测试）；置为 off 表示不用转存仓库。
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        # X64 | Arm64
        [ValidateSet('X64', 'Arm64')][string]$Arch = 'X64'
    )
    $base = $env:PsDepsMirror
    if ($base -and $base -match '^(off|none|false|0)$') { return $null }
    if ([string]::IsNullOrWhiteSpace($base))
    {
        $base = 'https://github.com/xuchaoxin1375/scripts-deps/releases/download'
    }

    # 版本钉子：改这里的同时要保证转存仓库已有对应 Release。
    $table = @{
        argc               = @{ Tag = 'argc-v1.24.0'; X64 = 'argc-v1.24.0-x86_64-pc-windows-msvc.zip' }
        yq                 = @{ Tag = 'yq-v4.54.2'; X64 = 'yq_windows_amd64.exe' }
        fzf                = @{ Tag = 'fzf-v0.75.0'; X64 = 'fzf-0.75.0-windows_amd64.zip' }
        zoxide             = @{ Tag = 'zoxide-v0.10.0'; X64 = 'zoxide-0.10.0-x86_64-pc-windows-msvc.zip' }
        'argc-completions' = @{ Tag = 'argc-completions-main-20261022'; X64 = 'argc-completions-main-19b70387.zip' }
    }
    $entry = $table[$Name]
    if (-not $entry) { return $null }
    $asset = $entry[$Arch]
    if (-not $asset) { return $null }
    return [pscustomobject]@{
        Name  = $Name
        Tag   = $entry.Tag
        Asset = $asset
        Url   = ($base.TrimEnd('/') + '/' + $entry.Tag + '/' + $asset)
    }
}

function Invoke-CxxuDownload
{
    # 依次尝试候选地址；都失败才抛错。5.1 需要显式开 TLS 1.2。
    # -Proxy 显式指定代理；未指定时读取代理环境变量，-NoProxy 强制直连。
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$Proxy,
        [switch]$NoProxy
    )
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    $proxyUrl = ''
    if (-not $NoProxy)
    {
        if (-not [string]::IsNullOrWhiteSpace($Proxy)) { $proxyUrl = $Proxy.Trim() }
        else { $proxyUrl = Get-CxxuProxyUrl }
    }
    $mirror = $env:PsGithubMirror
    if (-not $mirror) { $mirror = 'https://gh-proxy.com' }
    $candidates = @(Get-CxxuDownloadUrls -Url $Url -Mirror $mirror -ProxyUrl $proxyUrl)
    $last = $null
    for ($i = 0; $i -lt $candidates.Count; $i++)
    {
        try
        {
            Write-Verbose ("下载源 {0}/{1}:{2}" -f ($i + 1), $candidates.Count, $candidates[$i])
            $params = @{
                Uri             = $candidates[$i]
                OutFile         = $OutFile
                UseBasicParsing = $true
                TimeoutSec      = 300
            }
            if ($proxyUrl) { $params.Proxy = $proxyUrl }
            Invoke-WebRequest @params
            return
        }
        catch
        {
            $last = $_
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            if ($i -lt ($candidates.Count - 1))
            {
                Write-Host ("  当前源不可用，回退下一个：{0}" -f $_.Exception.Message)
            }
        }
    }
    throw "下载失败: $Url ($($last.Exception.Message))"
}

function Get-CxxuLatestRelease
{
    # GitHub API；有代理时直连优先，否则先镜像再直连。
    param(
        [string]$Repo,
        [string]$Proxy,
        [switch]$NoProxy
    )
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    $proxyUrl = ''
    if (-not $NoProxy)
    {
        if (-not [string]::IsNullOrWhiteSpace($Proxy)) { $proxyUrl = $Proxy.Trim() }
        else { $proxyUrl = Get-CxxuProxyUrl }
    }
    $url = "https://api.github.com/repos/$Repo/releases/latest"
    $mirror = $env:PsGithubMirror
    if (-not $mirror) { $mirror = 'https://gh-proxy.com' }
    # API 直连优先（多数网络可用且响应快），失败再走镜像；有代理时直连也自动经过代理。
    $candidates = @($url, ($mirror.TrimEnd('/') + '/' + $url))
    $params = @{ TimeoutSec = 30 }
    if ($proxyUrl) { $params.Proxy = $proxyUrl }
    $last = $null
    foreach ($candidate in $candidates)
    {
        $params.Uri = $candidate
        try { return Invoke-RestMethod @params }
        catch { $last = $_ }
    }
    throw "查询最新 release 失败: $Repo ($($last.Exception.Message))"
}

function Invoke-CxxuDownloadBatch
{
    <#
    .SYNOPSIS
    并发下载多个文件（runspace 池，5.1 与 7 都可用）。
    .DESCRIPTION
    每项独立按镜像/直连与代理候选回退；单项失败不影响其他项。
    默认最多 4 个并发，任务少或加 -Sequential 时退回串行。
    .EXAMPLE
    Invoke-CxxuDownloadBatch -Tasks @(
        @{ Label = '仓库'; Url = 'https://example.com/a.zip'; OutFile = "$env:TEMP\a.zip" }
    )
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Tasks,
        [string]$Proxy,
        [switch]$NoProxy,
        [switch]$Sequential,
        [int]$ThrottleLimit = 4
    )
    if (-not $Tasks -or $Tasks.Count -eq 0) { return @() }
    $proxyUrl = ''
    if (-not $NoProxy)
    {
        if (-not [string]::IsNullOrWhiteSpace($Proxy)) { $proxyUrl = $Proxy.Trim() }
        else { $proxyUrl = Get-CxxuProxyUrl }
    }
    $mirror = $env:PsGithubMirror
    if (-not $mirror) { $mirror = 'https://gh-proxy.com' }

    $prepared = @()
    foreach ($task in $Tasks)
    {
        $dir = Split-Path -Parent $task.OutFile
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $prepared += [pscustomobject]@{
            Task = $task
            Urls = @(Get-CxxuDownloadUrls -Url $task.Url -Mirror $mirror -ProxyUrl $proxyUrl)
        }
    }

    $runOne = {
        param($Task, $Urls, $ProxyUrl)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
        $last = $null
        foreach ($candidate in $Urls)
        {
            try
            {
                $params = @{
                    Uri             = $candidate
                    OutFile         = $Task.OutFile
                    UseBasicParsing = $true
                    TimeoutSec      = 300
                }
                if ($ProxyUrl) { $params.Proxy = $ProxyUrl }
                Invoke-WebRequest @params
                $sw.Stop()
                return [pscustomobject]@{
                    Label   = $Task.Label
                    OutFile = $Task.OutFile
                    Ok      = $true
                    Source  = $candidate
                    Seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
                    Error   = ''
                }
            }
            catch
            {
                $last = $_
                Remove-Item -LiteralPath $Task.OutFile -Force -ErrorAction SilentlyContinue
            }
        }
        $sw.Stop()
        return [pscustomobject]@{
            Label   = $Task.Label
            OutFile = $Task.OutFile
            Ok      = $false
            Source  = ''
            Seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
            Error   = $last.Exception.Message
        }
    }

    if ($Sequential -or $prepared.Count -eq 1)
    {
        $results = @()
        foreach ($item in $prepared)
        {
            $result = & $runOne $item.Task $item.Urls $proxyUrl
            $results += $result
            if ($result.Ok) { Write-Host ("  {0} 完成（{1:N1} 秒）" -f $result.Label, $result.Seconds) }
            else { Write-Warning ("{0} 下载失败：{1}" -f $result.Label, $result.Error) }
        }
        return $results
    }

    $limit = [Math]::Max(1, [Math]::Min($ThrottleLimit, $prepared.Count))
    $pool = [runspacefactory]::CreateRunspacePool(1, $limit)
    $jobs = @()
    $results = @()
    try
    {
        $pool.Open()
        foreach ($item in $prepared)
        {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($runOne.ToString()).AddArgument($item.Task).AddArgument($item.Urls).AddArgument($proxyUrl)
            $jobs += [pscustomobject]@{
                Label  = $item.Task.Label
                PS     = $ps
                Handle = $ps.BeginInvoke()
            }
        }
        # 完成一项收一项，边收边提示；不设总超时，单项由 Invoke-WebRequest 的 300 秒兜底
        $pending = New-Object System.Collections.ArrayList
        foreach ($job in $jobs) { [void]$pending.Add($job) }
        while ($pending.Count -gt 0)
        {
            for ($i = $pending.Count - 1; $i -ge 0; $i--)
            {
                $job = $pending[$i]
                if (-not $job.Handle.IsCompleted) { continue }
                $pending.RemoveAt($i)
                try
                {
                    $out = @($job.PS.EndInvoke($job.Handle))
                    if ($out.Count -eq 0) { throw '下载任务没有返回结果' }
                    foreach ($item in $out)
                    {
                        if ($item -is [pscustomobject] -and $item.PSObject.Properties['Label'])
                        {
                            $results += $item
                            if ($item.Ok) { Write-Host ("  {0} 完成（{1:N1} 秒）" -f $item.Label, $item.Seconds) }
                            else { Write-Warning ("{0} 下载失败：{1}" -f $item.Label, $item.Error) }
                        }
                    }
                }
                catch
                {
                    $fail = [pscustomobject]@{
                        Label   = $job.Label
                        OutFile = ''
                        Ok      = $false
                        Source  = ''
                        Seconds = 0
                        Error   = $_.Exception.Message
                    }
                    $results += $fail
                    Write-Warning ("{0} 下载失败：{1}" -f $job.Label, $fail.Error)
                }
                finally
                {
                    $job.PS.Dispose()
                }
            }
            if ($pending.Count -gt 0) { Start-Sleep -Milliseconds 200 }
        }
    }
    catch
    {
        Write-Warning ("并发下载不可用，改为串行：{0}" -f $_.Exception.Message)
        foreach ($job in $jobs) { try { $job.PS.Dispose() } catch { } }
        $doneLabels = @($results | ForEach-Object { $_.Label })
        foreach ($item in $prepared)
        {
            if ($doneLabels -contains $item.Task.Label) { continue }
            $result = & $runOne $item.Task $item.Urls $proxyUrl
            $results += $result
            if ($result.Ok) { Write-Host ("  {0} 完成（{1:N1} 秒）" -f $result.Label, $result.Seconds) }
            else { Write-Warning ("{0} 下载失败：{1}" -f $result.Label, $result.Error) }
        }
    }
    finally
    {
        foreach ($job in $jobs)
        {
            if ($job.PS) { try { $job.PS.Dispose() } catch { } }
        }
        try { $pool.Close() } catch { }
        try { $pool.Dispose() } catch { }
    }
    return $results
}

function Add-CxxuBinToPath
{
    # 把指定目录放进当前会话与用户 PATH；非 Windows 只改当前会话并提示。
    param([Parameter(Mandatory)][string]$BinDir)
    $parts = @($env:PATH -split [IO.Path]::PathSeparator)
    if ($parts -notcontains $BinDir)
    {
        $env:PATH = $BinDir + [IO.Path]::PathSeparator + $env:PATH
    }
    $isWindowsHost = if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { [bool]$IsWindows }
    else { ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT') }
    if (-not $isWindowsHost)
    {
        Write-Host ("提示：当前会话已加入 {0}；新终端需要把它写进 shell 配置，例如：export PATH=`"{0}:`$PATH`"" -f $BinDir)
        return
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userParts = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($userParts -notcontains $BinDir)
    {
        if (Get-Command Add-EnvVar -ErrorAction SilentlyContinue)
        {
            try { Add-EnvVar -EnvVar Path -NewValue $BinDir -Scope User -Force | Out-Null }
            catch { Write-Warning ("写入用户 PATH 失败：{0}；请手动加入 {1}" -f $_.Exception.Message, $BinDir) }
        }
        else
        {
            [Environment]::SetEnvironmentVariable('Path', ($BinDir + ';' + $userPath), 'User')
        }
    }
}

function Install-CxxuFuzzyBinaries
{
    <#
    .SYNOPSIS
    安装 fzf/zoxide 二进制：优先 scoop，其次 winget/brew，最后回退 GitHub release。
    .DESCRIPTION
    fzf 与 zoxide 都是单文件命令，scoop 在国内网络下不稳定时不必反复重试：
    未检测到代理时先试 scoop，再试 winget（Windows）或 brew（macOS）；
    设置了代理（-Proxy 或 HTTPS_PROXY/HTTP_PROXY）时直接下载，避免包管理器绕过代理。
    下载优先取 scripts-deps 转存仓库的固定版本（国内更稳），失败再回退上游 GitHub release；
    Windows 下并发下载、解压到 ~/.cxxu/bin，并把该目录加入用户 PATH。
    已存在的命令会跳过；失败只警告，不阻塞补全栈其他部分。
    #>
    [CmdletBinding()]
    param(
        [string]$Proxy = '',
        [switch]$NoProxy,
        [switch]$NoParallel,
        # 跳过 scripts-deps 转存仓库，直接走上游 release
        [switch]$NoMirror
    )

    $targets = @(
        [pscustomobject]@{
            Name = 'fzf'; Repo = 'junegunn/fzf'; Winget = 'junegunn.fzf'; Brew = 'fzf'
            Exe = 'fzf.exe'; Asset = '-windows_amd64\.zip$'; AssetArm = '-windows_arm64\.zip$'
        }
        [pscustomobject]@{
            Name = 'zoxide'; Repo = 'ajeetdsouza/zoxide'; Winget = 'ajeetdsouza.zoxide'; Brew = 'zoxide'
            Exe = 'zoxide.exe'; Asset = '-x86_64-pc-windows-msvc\.zip$'; AssetArm = '-aarch64-pc-windows-msvc\.zip$'
        }
    )
    $remaining = @($targets | Where-Object { -not (Get-Command $_.Name -ErrorAction SilentlyContinue) })
    if (-not $remaining.Count)
    {
        Write-Host '  fzf/zoxide 已存在，跳过'
        return
    }

    $proxyUrl = ''
    if (-not $NoProxy)
    {
        if (-not [string]::IsNullOrWhiteSpace($Proxy)) { $proxyUrl = $Proxy.Trim() }
        else { $proxyUrl = Get-CxxuProxyUrl }
    }
    $isWindowsHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT')
    $isMac = ($IsMacOS -eq $true)

    # 有代理时不走 scoop/winget：它们在 5.1 下不一定继承代理环境变量，直接下载更可控。
    if ($isWindowsHost -and -not $proxyUrl)
    {
        $hasScoop = [bool](Get-Command scoop -ErrorAction SilentlyContinue)
        foreach ($target in @($remaining))
        {
            if (-not $hasScoop) { break }
            Write-Host ("  使用 scoop 安装 {0} ..." -f $target.Name)
            try { scoop install $target.Name } catch { Write-Warning ("scoop 安装 {0} 失败：{1}" -f $target.Name, $_.Exception.Message) }
            if (Get-Command $target.Name -ErrorAction SilentlyContinue)
            {
                $remaining = @($remaining | Where-Object { $_.Name -ne $target.Name })
            }
        }
    }

    if ($isWindowsHost -and $remaining.Count)
    {
        $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
        $wingetLinks = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
        foreach ($target in @($remaining))
        {
            if (-not $hasWinget) { break }
            Write-Host ("  使用 winget 安装 {0} ..." -f $target.Name)
            try
            {
                & winget install --id $target.Winget -e --source winget --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "winget 退出码 $LASTEXITCODE" }
            }
            catch { Write-Warning ("winget 安装 {0} 失败：{1}" -f $target.Name, $_.Exception.Message) }
            if ((Test-Path -LiteralPath $wingetLinks) -and (($env:PATH -split ';') -notcontains $wingetLinks))
            {
                $env:PATH = $wingetLinks + ';' + $env:PATH
            }
            if (Get-Command $target.Name -ErrorAction SilentlyContinue)
            {
                $remaining = @($remaining | Where-Object { $_.Name -ne $target.Name })
            }
        }
    }

    if ($isMac -and $remaining.Count)
    {
        $hasBrew = [bool](Get-Command brew -ErrorAction SilentlyContinue)
        foreach ($target in @($remaining))
        {
            if (-not $hasBrew) { break }
            Write-Host ("  使用 brew 安装 {0} ..." -f $target.Name)
            try { brew install $target.Brew } catch { Write-Warning ("brew 安装 {0} 失败：{1}" -f $target.Name, $_.Exception.Message) }
            if (Get-Command $target.Name -ErrorAction SilentlyContinue)
            {
                $remaining = @($remaining | Where-Object { $_.Name -ne $target.Name })
            }
        }
    }

    if (-not $remaining.Count)
    {
        Write-Host '  fzf/zoxide 已就绪'
        return
    }
    if (-not $isWindowsHost)
    {
        $names = ($remaining | ForEach-Object { $_.Name }) -join '、'
        Write-Host ("  提示：未安装 {0}；请用 brew 或系统包管理器安装。" -f $names)
        return
    }

    # 最后回退：GitHub release 直接下载到 ~/.cxxu/bin，不依赖 scoop。
    $binDir = Join-Path (Join-Path $HOME '.cxxu') 'bin'
    $isArm = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
    $tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ('cxxu-fuzzy-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
    $tasks = @()
    try
    {
        foreach ($target in $remaining)
        {
            try
            {
                $mirror = $null
                if (-not $NoMirror -and -not $isArm)
                {
                    $mirror = Get-CxxuDepsMirrorAsset -Name $target.Name -Arch 'X64'
                }
                $url = ''
                if ($mirror)
                {
                    $url = $mirror.Url
                    Write-Host ("  {0}：使用 scripts-deps 固定版本 {1}" -f $target.Name, $mirror.Tag)
                }
                else
                {
                    $pattern = $target.Asset
                    if ($isArm) { $pattern = $target.AssetArm }
                    Write-Host ("  查询 {0} 最新 release ..." -f $target.Name)
                    $rel = Get-CxxuLatestRelease -Repo $target.Repo -Proxy $Proxy -NoProxy:$NoProxy
                    $asset = @($rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1)
                    if (-not $asset.Count) { throw "未找到匹配 $pattern 的 Windows 产物" }
                    $url = $asset[0].browser_download_url
                }
                $tasks += @{
                    Label   = $target.Name
                    Url     = $url
                    OutFile = (Join-Path $tmpRoot ($target.Name + '.zip'))
                    Target  = $target
                    Mirror  = [bool]$mirror
                }
            }
            catch
            {
                Write-Warning ("{0} 版本信息获取失败：{1}" -f $target.Name, $_.Exception.Message)
            }
        }
        if (-not $tasks.Count) { return }
        Write-Host ("  下载 {0} 项（{1}）" -f $tasks.Count, $(if ($proxyUrl) { '走代理' } else { '转存仓库优先，失败回退上游' }))
        $results = @(Invoke-CxxuDownloadBatch -Tasks $tasks -Proxy $Proxy -NoProxy:$NoProxy -Sequential:$NoParallel)

        # 转存仓库的固定地址失效时回退上游 release，避免钉死版本后装不上。
        foreach ($item in @($tasks | Where-Object { $_.Mirror }))
        {
            $done = @($results | Where-Object { $_.Label -eq $item.Label -and $_.Ok })
            if ($done.Count) { continue }
            Write-Host ("  {0}：scripts-deps 下载失败，回退上游 release" -f $item.Target.Name)
            try
            {
                $pattern = $item.Target.Asset
                if ($isArm) { $pattern = $item.Target.AssetArm }
                $rel = Get-CxxuLatestRelease -Repo $item.Target.Repo -Proxy $Proxy -NoProxy:$NoProxy
                $asset = @($rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1)
                if (-not $asset.Count) { throw "未找到匹配 $pattern 的 Windows 产物" }
                Invoke-CxxuDownload -Url $asset[0].browser_download_url -OutFile $item.OutFile -Proxy $Proxy -NoProxy:$NoProxy
                $results = @($results | Where-Object { $_.Label -ne $item.Label })
                $results += [pscustomobject]@{
                    Label = $item.Label; OutFile = $item.OutFile; Ok = $true
                    Source = $asset[0].browser_download_url; Seconds = 0; Error = ''
                }
            }
            catch { Write-Warning ("{0} 回退上游也失败：{1}" -f $item.Target.Name, $_.Exception.Message) }
        }
        $installed = 0
        foreach ($result in $results)
        {
            if (-not $result.Ok) { continue }
            $task = @($tasks | Where-Object { $_.Label -eq $result.Label })[0]
            $target = $task.Target
            try
            {
                $dir = Join-Path $tmpRoot ($target.Name + '-unzip')
                Expand-Archive -LiteralPath $result.OutFile -DestinationPath $dir -Force
                $exe = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter $target.Exe -File | Select-Object -First 1)
                if (-not $exe.Count) { throw ("压缩包内没有 {0}" -f $target.Exe) }
                if (-not (Test-Path -LiteralPath $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }
                Copy-Item -LiteralPath $exe[0].FullName -Destination (Join-Path $binDir $target.Exe) -Force
                Write-Host ("  {0} 已安装到 {1}" -f $target.Name, $binDir)
                $installed += 1
            }
            catch
            {
                Write-Warning ("{0} 安装失败：{1}" -f $target.Name, $_.Exception.Message)
            }
        }
        if ($installed -gt 0) { Add-CxxuBinToPath -BinDir $binDir }
    }
    finally
    {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Deploy-ArgcCompletions
{
    <#
    .SYNOPSIS
    部署 argc-completions：补全仓库 + argc.exe/yq.exe + 当前会话注册。
    .DESCRIPTION
    默认装到 ~/argc-completions（已存在则复用；可用 -Root 指定）。仓库与二进制优先取
    scripts-deps 转存仓库的固定版本（国内更稳，不查 release API），失败再回退上游 GitHub；
    缺少的仓库与二进制会并发下载（-NoParallel 可回到串行），每项分别按镜像/直连回退。
    显式 -Proxy 或设置 HTTPS_PROXY/HTTP_PROXY/ALL_PROXY 可走代理加速，-NoProxy 强制直连；
    -NoMirror 跳过转存仓库、直接走上游。
    下载后按“确认缺失项 → 解析并下载 → 安装 → 当前会话注册”输出进度与结果；
    任一步失败只警告，不影响其他补全，并在结尾汇总失败项。
    -SkipBinaries 只准备仓库，-Force 重新下载仓库与二进制。仓库就位后调用 Set-ArgcCompletions 装 Tab 桩。
    .EXAMPLE
    Deploy-ArgcCompletions -WhatIf
    .EXAMPLE
    Deploy-ArgcCompletions -Proxy http://127.0.0.1:7897
    .EXAMPLE
    Deploy-ArgcCompletions -Root D:\tools\argc-completions
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 安装目录;默认 ARGC_COMPLETIONS_ROOT > ~/argc-completions > C:\repos\argc-completions
        [string]$Root = '',
        # 只准备仓库,不下载 argc.exe/yq.exe
        [switch]$SkipBinaries,
        # 重新下载仓库与缺失二进制
        [switch]$Force,
        # 本次下载使用的代理；未指定时读取 HTTPS_PROXY/HTTP_PROXY/ALL_PROXY
        [string]$Proxy = '',
        # 强制直连，忽略 -Proxy 与代理环境变量
        [switch]$NoProxy,
        # 关闭并发下载，改为逐个下载
        [switch]$NoParallel,
        # 跳过 scripts-deps 转存仓库，直接走上游 GitHub
        [switch]$NoMirror
    )

    if (-not $Root)
    {
        $Root = $env:ARGC_COMPLETIONS_ROOT
        if (-not $Root)
        {
            foreach ($cand in @((Join-Path $HOME 'argc-completions'), 'C:\repos\argc-completions'))
            {
                if (Test-Path -LiteralPath (Join-Path $cand 'completions')) { $Root = $cand; break }
            }
        }
        if (-not $Root) { $Root = Join-Path $HOME 'argc-completions' }
    }
    $completions = Join-Path $Root 'completions'
    $bin = Join-Path $Root 'bin'
    $isWindowsHost = ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT')
    if (-not $isWindowsHost -and -not $SkipBinaries)
    {
        Write-Warning 'Deploy-ArgcCompletions 目前只自动下载 Windows 二进制；请按 Argc-Completions-Deploy.md 手动装 argc/yq'
        $SkipBinaries = $true
    }

    $deployStart = Get-Date
    $failed = New-Object System.Collections.ArrayList
    $canceled = $false
    $bashMissing = $false
    Write-Host ("argc-completions 部署开始：根目录 {0}" -f $Root)

    $repoExists = Test-Path -LiteralPath $completions
    $needRepo = (-not $repoExists) -or $Force
    $argcExe = Join-Path $bin 'argc.exe'
    $yqExe = Join-Path $bin 'yq.exe'
    $needArgc = (-not $SkipBinaries) -and ((-not (Test-Path -LiteralPath $argcExe)) -or $Force)
    $needYq = (-not $SkipBinaries) -and ((-not (Test-Path -LiteralPath $yqExe)) -or $Force)

    # 转存仓库固定版本：只有 x86_64 有转存；arm64 或 -NoMirror 直接走上游。
    $isArm = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
    $mirrorArch = 'X64'
    if ($isArm) { $mirrorArch = 'Arm64' }
    $repoMirror = $null
    $argcMirror = $null
    $yqMirror = $null
    if (-not $NoMirror)
    {
        $repoMirror = Get-CxxuDepsMirrorAsset -Name 'argc-completions' -Arch $mirrorArch
        $argcMirror = Get-CxxuDepsMirrorAsset -Name 'argc' -Arch $mirrorArch
        $yqMirror = Get-CxxuDepsMirrorAsset -Name 'yq' -Arch $mirrorArch
    }

    # 1) 计划：让 -WhatIf 与正常执行看到同一份动作清单
    Write-Host '步骤 1/4：确认缺失项'
    if ($needRepo)
    {
        if ($repoExists) { Write-Host '  仓库：已就位，按 -Force 重新下载覆盖（保留 bin）' }
        elseif ($repoMirror) { Write-Host ("  仓库：未找到，下载 scripts-deps 快照 {0}（失败回退 GitHub main）" -f $repoMirror.Tag) }
        else { Write-Host '  仓库：未找到，下载 GitHub main 压缩包' }
    }
    else { Write-Host '  仓库：已就位，复用；需要重新下载时加 -Force' }

    if ($SkipBinaries) { Write-Host '  二进制：按 -SkipBinaries 跳过' }
    else
    {
        if ($needArgc)
        {
            if ($argcMirror) { Write-Host ("  argc.exe：缺失或 -Force，取 scripts-deps 固定版本 {0}（失败回退上游）" -f $argcMirror.Tag) }
            else { Write-Host '  argc.exe：缺失或 -Force，下载上游最新 release' }
        }
        else { Write-Host '  argc.exe：已存在，跳过；更新加 -Force' }
        if ($needYq)
        {
            if ($yqMirror) { Write-Host ("  yq.exe：缺失或 -Force，取 scripts-deps 固定版本 {0}（失败回退上游）" -f $yqMirror.Tag) }
            else { Write-Host '  yq.exe：缺失或 -Force，下载上游最新 release' }
        }
        else { Write-Host '  yq.exe：已存在，跳过；更新加 -Force' }
    }

    if ($WhatIfPreference)
    {
        Write-Host '空跑结束：未做任何改动；去掉 -WhatIf 执行。'
        return
    }

    # 2) 解析地址：转存仓库优先（不查 API），缺失或 arm64 才查上游 release
    Write-Host '步骤 2/4：解析并下载缺失项'
    $arch = 'x86_64'
    $yqArch = 'amd64'
    if ($isArm) { $arch = 'aarch64'; $yqArch = 'arm64' }
    $argcUrl = ''
    $yqUrl = ''
    if ($needArgc)
    {
        if ($argcMirror) { $argcUrl = $argcMirror.Url }
        else
        {
            try
            {
                Write-Host '  查询 argc 最新 release ...'
                $rel = Get-CxxuLatestRelease -Repo 'sigoden/argc' -Proxy $Proxy -NoProxy:$NoProxy
                $asset = @($rel.assets | Where-Object { $_.name -match ('-' + $arch + '-pc-windows-msvc\.zip$') } | Select-Object -First 1)
                if (-not $asset.Count) { throw "未找到 $arch Windows 产物" }
                $argcUrl = $asset[0].browser_download_url
                Write-Host ("  argc 目标版本：{0}（{1}）" -f $rel.tag_name, $arch)
            }
            catch
            {
                Write-Warning ("argc.exe 版本信息获取失败：{0}；重新运行会重试" -f $_.Exception.Message)
                [void]$failed.Add('argc.exe')
            }
        }
    }
    if ($needYq)
    {
        if ($yqMirror) { $yqUrl = $yqMirror.Url }
        else
        {
            try
            {
                Write-Host '  查询 yq 最新 release ...'
                $rel = Get-CxxuLatestRelease -Repo 'mikefarah/yq' -Proxy $Proxy -NoProxy:$NoProxy
                $asset = @($rel.assets | Where-Object { $_.name -eq ('yq_windows_' + $yqArch + '.exe') } | Select-Object -First 1)
                if (-not $asset.Count) { throw "未找到 yq_windows_$yqArch.exe" }
                $yqUrl = $asset[0].browser_download_url
                Write-Host ("  yq 目标版本：{0}（{1}）" -f $rel.tag_name, $yqArch)
            }
            catch
            {
                Write-Warning ("yq.exe 版本信息获取失败：{0}；重新运行会重试" -f $_.Exception.Message)
                [void]$failed.Add('yq.exe')
            }
        }
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('cxxu-argc-' + [guid]::NewGuid().ToString('N'))
    $tasks = @()
    if ($needRepo)
    {
        $repoUrl = 'https://github.com/sigoden/argc-completions/archive/refs/heads/main.zip'
        if ($repoMirror) { $repoUrl = $repoMirror.Url }
        $tasks += @{
            Label   = '仓库'
            Url     = $repoUrl
            OutFile = (Join-Path $tempRoot 'repo.zip')
        }
    }
    if ($argcUrl) { $tasks += @{ Label = 'argc.exe'; Url = $argcUrl; OutFile = (Join-Path $tempRoot 'argc.zip') } }
    if ($yqUrl) { $tasks += @{ Label = 'yq.exe'; Url = $yqUrl; OutFile = ($yqExe + '.download') } }

    $proceed = $true
    if ($tasks.Count -gt 0)
    {
        $proceed = $PSCmdlet.ShouldProcess($Root, ('下载并安装 {0} 项缺失内容' -f $tasks.Count))
    }
    if (-not $proceed)
    {
        $canceled = $true
        Write-Host '  已取消下载'
    }
    elseif ($tasks.Count -gt 0)
    {
        if ($tasks.Count -gt 1 -and -not $NoParallel) { Write-Host ("  并发下载 {0} 项 ..." -f $tasks.Count) }
        else { Write-Host '  逐项下载 ...' }
        $results = @(Invoke-CxxuDownloadBatch -Tasks $tasks -Proxy $Proxy -NoProxy:$NoProxy -Sequential:$NoParallel)
        $byLabel = @{}
        foreach ($result in $results) { $byLabel[$result.Label] = $result }

        # 转存地址失效时回退上游：仓库回退 main 分支压缩包，二进制回退最新 release
        $mirrorLabels = @()
        if ($needRepo -and $repoMirror) { $mirrorLabels += '仓库' }
        if ($needArgc -and $argcMirror) { $mirrorLabels += 'argc.exe' }
        if ($needYq -and $yqMirror) { $mirrorLabels += 'yq.exe' }
        foreach ($label in $mirrorLabels)
        {
            $current = $byLabel[$label]
            if ($current -and $current.Ok) { continue }
            $task = @($tasks | Where-Object { $_.Label -eq $label })[0]
            Write-Host ("  {0}：scripts-deps 下载失败，回退上游" -f $label)
            try
            {
                if ($label -eq '仓库')
                {
                    $url = 'https://github.com/sigoden/argc-completions/archive/refs/heads/main.zip'
                }
                elseif ($label -eq 'argc.exe')
                {
                    $rel = Get-CxxuLatestRelease -Repo 'sigoden/argc' -Proxy $Proxy -NoProxy:$NoProxy
                    $asset = @($rel.assets | Where-Object { $_.name -match ('-' + $arch + '-pc-windows-msvc\.zip$') } | Select-Object -First 1)
                    if (-not $asset.Count) { throw "未找到 $arch Windows 产物" }
                    $url = $asset[0].browser_download_url
                }
                else
                {
                    $rel = Get-CxxuLatestRelease -Repo 'mikefarah/yq' -Proxy $Proxy -NoProxy:$NoProxy
                    $asset = @($rel.assets | Where-Object { $_.name -eq ('yq_windows_' + $yqArch + '.exe') } | Select-Object -First 1)
                    if (-not $asset.Count) { throw "未找到 yq_windows_$yqArch.exe" }
                    $url = $asset[0].browser_download_url
                }
                Invoke-CxxuDownload -Url $url -OutFile $task.OutFile -Proxy $Proxy -NoProxy:$NoProxy
                $byLabel[$label] = [pscustomobject]@{
                    Label = $label; OutFile = $task.OutFile; Ok = $true
                    Source = $url; Seconds = 0; Error = ''
                }
            }
            catch { Write-Warning ("{0} 回退上游也失败：{1}" -f $label, $_.Exception.Message) }
        }

        # 3) 安装仓库与二进制
        Write-Host '步骤 3/4：安装仓库与二进制'
        if ($needRepo)
        {
            $result = $byLabel['仓库']
            if ($result -and $result.Ok)
            {
                try
                {
                    $repoStart = Get-Date
                    $unzip = Join-Path $tempRoot 'repo-unzip'
                    Expand-Archive -LiteralPath $result.OutFile -DestinationPath $unzip -Force
                    $src = @(Get-ChildItem -LiteralPath $unzip -Directory | Select-Object -First 1)
                    if (-not $src.Count) { throw '压缩包结构异常' }
                    if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
                    # 保留已有 bin:二进制不随仓库覆盖
                    Get-ChildItem -LiteralPath $src[0].FullName -Force | Where-Object { $_.Name -ne 'bin' } | ForEach-Object {
                        Copy-Item -LiteralPath $_.FullName -Destination $Root -Recurse -Force
                    }
                    $zipMb = [Math]::Round((Get-Item -LiteralPath $result.OutFile).Length / 1MB, 1)
                    Write-Host ("  仓库完成：{0} MB，安装耗时 {1:N1} 秒" -f $zipMb, ((Get-Date) - $repoStart).TotalSeconds)
                }
                catch
                {
                    Write-Warning ("argc-completions 仓库安装失败：{0}" -f $_.Exception.Message)
                    [void]$failed.Add('仓库')
                }
            }
            elseif ($result) { [void]$failed.Add('仓库') }
            else { Write-Warning '仓库下载未执行'; [void]$failed.Add('仓库') }
        }

        if ($needArgc -and $argcUrl)
        {
            $result = $byLabel['argc.exe']
            if ($result -and $result.Ok)
            {
                try
                {
                    $unzip = Join-Path $tempRoot 'argc-unzip'
                    Expand-Archive -LiteralPath $result.OutFile -DestinationPath $unzip -Force
                    $exe = @(Get-ChildItem -LiteralPath $unzip -Recurse -Filter 'argc.exe' -File | Select-Object -First 1)
                    if (-not $exe.Count) { throw '压缩包内没有 argc.exe' }
                    if (-not (Test-Path -LiteralPath $bin)) { New-Item -ItemType Directory -Path $bin -Force | Out-Null }
                    Copy-Item -LiteralPath $exe[0].FullName -Destination $argcExe -Force
                    $ver = & $argcExe --argc-version 2>$null | Select-Object -First 1
                    Write-Host ("  argc.exe 完成：{0}" -f $ver)
                }
                catch
                {
                    Write-Warning ("argc.exe 安装失败：{0}；重新运行 Deploy-ArgcCompletions 会补齐" -f $_.Exception.Message)
                    [void]$failed.Add('argc.exe')
                }
            }
            elseif ($result) { [void]$failed.Add('argc.exe') }
        }

        if ($needYq -and $yqUrl)
        {
            $result = $byLabel['yq.exe']
            if ($result -and $result.Ok)
            {
                try
                {
                    Move-Item -LiteralPath $result.OutFile -Destination $yqExe -Force
                    $ver = & $yqExe --version 2>$null | Select-Object -First 1
                    if ($ver -match 'version\s+(\S+)') { $ver = $Matches[1] }
                    Write-Host ("  yq.exe 完成：{0}" -f $ver)
                }
                catch
                {
                    Write-Warning ("yq.exe 安装失败：{0}；重新运行 Deploy-ArgcCompletions 会补齐" -f $_.Exception.Message)
                    [void]$failed.Add('yq.exe')
                }
            }
            elseif ($result) { [void]$failed.Add('yq.exe') }
        }
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

    # 4) 当前会话:装 Tab 桩并注册;bash 路径无效会显著影响 argc 补全,提前告警
    Write-Host '步骤 4/4：当前会话注册'
    if (Test-Path -LiteralPath $completions)
    {
        if ($PSCmdlet.ShouldProcess($Root, '设置 argc 环境并注册当前会话'))
        {
            # 指定/新建的根优先于环境里已有的旧路径,否则 Set-ArgcCompletions 会探测到别处
            $env:ARGC_COMPLETIONS_ROOT = $Root
            $hasSet = [bool](Get-Command Set-ArgcCompletions -ErrorAction SilentlyContinue)
            $hasInit = [bool](Get-Command Initialize-ArgcCompletions -ErrorAction SilentlyContinue)
            if ($hasSet) { Set-ArgcCompletions }
            if ($hasInit)
            {
                Write-Host '  注册 Tab 补全（约 150-200ms）...'
                try { Initialize-ArgcCompletions -Force }
                catch
                {
                    Write-Warning ("argc 注册失败：{0}" -f $_.Exception.Message)
                    [void]$failed.Add('当前会话注册')
                }
            }
            else
            {
                Write-Warning '未找到 Initialize-ArgcCompletions（Init 模块未加载）；当前会话未注册，重开终端后按 Tab 生效'
                [void]$failed.Add('当前会话注册')
            }

            $argcExe = Join-Path $bin 'argc.exe'
            if (Test-Path -LiteralPath $argcExe)
            {
                $shell = & $argcExe --argc-shell-path 2>$null | Select-Object -First 1
                if (-not $shell -or -not (Test-Path -LiteralPath $shell))
                {
                    $bashMissing = $true
                    Write-Warning "argc 找不到可用的 bash（argc --argc-shell-path 返回 '$shell'）；Tab 参数补全会失败，装 Git for Windows 后重试"
                }
                $ver = & $argcExe --argc-version 2>$null | Select-Object -First 1
                if ($hasInit -and $global:PsArgcLoaded)
                {
                    $count = 0
                    if ($global:PsArgcScripts) { $count = $global:PsArgcScripts.Count }
                    Write-Host ("  已注册：{0}，{1} 个命令补全" -f $ver, $count)
                }
                elseif ($hasInit)
                {
                    Write-Warning '当前会话未注册 argc 补全：补全脚本缺失或 $env:PsArgc 已关闭；补齐后重开终端重试'
                    [void]$failed.Add('当前会话注册')
                }
            }
            else
            {
                Write-Warning "argc.exe 未就位：仓库已下载，但 Tab 参数补全需要 $bin\argc.exe"
                [void]$failed.Add('argc.exe')
            }
        }
        else { $canceled = $true; Write-Host '  已取消当前会话注册' }
    }
    else
    {
        Write-Warning "argc-completions 未就位：$Root 下没有 completions"
        [void]$failed.Add('仓库')
    }

    $elapsed = ((Get-Date) - $deployStart).TotalSeconds
    if ($failed.Count -gt 0)
    {
        Write-Warning ("argc-completions 部署未全部完成，失败项：{0}。重新运行 Deploy-ArgcCompletions 会补齐缺失项；网络问题可设置 `$env:PsGithubMirror 或代理后重试。" -f ($failed -join '、'))
    }
    elseif ($canceled)
    {
        Write-Warning 'argc-completions 部署已取消部分步骤，未做全部改动；需要时重新运行 Deploy-ArgcCompletions。'
    }
    else
    {
        Write-Host ("argc-completions 部署完成：总耗时 {0:N1} 秒；首次 Tab 时注册补全，新终端也会自动生效。" -f $elapsed)
    }
    if ($bashMissing)
    {
        Write-Warning 'bash 未就绪：argc 参数补全在 Tab 时会失败；安装 Git for Windows（或 scoop install git）后重试 Deploy-ArgcCompletions。'
    }
}

function Show-CarapaceEnableHint
{
    # 只打印启用方式，不修改 profile；加载由 init 按 PsCarapace 配置完成。
    Write-Host ''
    Write-Host '启用方式（不修改 profile）：'
    Write-Host '  Deploy-Carapace -Enable                     # 安装后直接启用（写入用户配置并立即加载）'
    Write-Host '  Deploy-Carapace -Bash                       # 安装后顺带接入 bash（Git Bash/Linux/macOS）'
    Write-Host '  Enable-CxxuComponent Carapace -Persist -Now  # 已安装时只启用组件'
    Write-Host '  Set-GitCompletionSource Carapace -Persist   # 让 carapace 接管 git/gitk'
    Write-Host '慢命令排除项写入 ~/.cxxu/config.psd1 的 PsCarapaceExcludes（逗号分隔）。'
    Write-Host '只启用 Carapace 时 git/gitk 仍归 git-completion；重开终端后 init 自动加载，-Now 已在当前会话加载。'
    Write-Host '旧版 profile 中的 carapace 片段请删除，避免重复注册。'
}

function Get-CxxuHostPlatform
{
    # 只读识别宿主 OS 与 CPU 架构，供跨平台二进制部署共用。
    # 不依赖 $env:OS：部分宿主/容器会清掉该变量，曾把 Windows 误判为非 Windows。
    $isWindowsHost = if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { [bool]$IsWindows }
    else { ($PSVersionTable.PSEdition -eq 'Desktop') -or ($env:OS -eq 'Windows_NT') }
    $isMacHost = if (Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue) { [bool]$IsMacOS } else { $false }
    $isLinuxHost = if (Get-Variable -Name IsLinux -ErrorAction SilentlyContinue) { [bool]$IsLinux } else { $false }

    $osName = if ($isWindowsHost) { 'windows' } elseif ($isMacHost) { 'darwin' } elseif ($isLinuxHost) { 'linux' } else { '' }
    if (-not $osName)
    {
        # 兜底：少数宿主不提供 $Is* 自动变量，用 uname 判定内核。
        $uname = Get-Command uname -ErrorAction SilentlyContinue
        if ($uname)
        {
            $kernel = (& $uname.Source -s 2>$null)
            if ($kernel -eq 'Darwin') { $osName = 'darwin' }
            elseif ($kernel -eq 'Linux') { $osName = 'linux' }
        }
    }
    if (-not $osName) { throw '无法识别当前操作系统；请改用系统包管理器安装该工具。' }

    $archRaw = ''
    try { $archRaw = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() } catch { }
    if (-not $archRaw) { $archRaw = $env:PROCESSOR_ARCHITECTURE }
    if (-not $archRaw)
    {
        $uname = Get-Command uname -ErrorAction SilentlyContinue
        if ($uname) { $archRaw = (& $uname.Source -m 2>$null) }
    }
    $archName = switch -Regex ([string]$archRaw)
    {
        '^(X64|AMD64|x86_64|amd64)$' { 'amd64' }
        '^(ARM64|aarch64|arm64)$' { 'arm64' }
        default { '' }
    }
    if (-not $archName) { throw ("不支持的处理器架构：{0}（仅支持 amd64/arm64）。" -f $archRaw) }

    [pscustomobject]@{
        OS        = $osName
        Arch      = $archName
        IsWindows = [bool]$isWindowsHost
    }
}

function Expand-CxxuReleaseArchive
{
    # 解压 GitHub Release 常见的 .zip / .tar.gz 到指定目录；调用方负责从解压结果中挑选文件。
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Destination))
    {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    if ($Path -match '\.tar\.gz$|\.tgz$')
    {
        $tar = Get-Command tar -ErrorAction SilentlyContinue
        if (-not $tar) { throw '未找到 tar，无法解压 .tar.gz；请安装 tar，或改用系统包管理器安装该工具。' }
        & $tar.Source -xzf $Path -C $Destination
        if ($LASTEXITCODE -ne 0) { throw ("tar 解压失败（退出码 {0}）：{1}" -f $LASTEXITCODE, $Path) }
    }
    elseif ($Path -match '\.zip$')
    {
        Expand-Archive -LiteralPath $Path -DestinationPath $Destination -Force
    }
    else
    {
        throw ("不支持的压缩包格式：{0}（仅支持 .zip 与 .tar.gz）。" -f $Path)
    }
}

function Invoke-CarapaceBashSetup
{
    # 调用仓库内 bash/carapace/setup.sh，把 carapace 接入 bash（Git Bash、Linux、macOS）。
    # 只写 rc 标记块；与 PowerShell 侧启用互不影响，失败只告警不抛错。
    param(
        # 写入登录 shell 读取的 rc（~/.bash_profile、~/.bash_login 或 ~/.profile）
        [switch]$Login,
        [switch]$WhatIf
    )

    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $setupSh = Join-Path $repoRoot 'bash/carapace/setup.sh'
    if (-not (Test-Path -LiteralPath $setupSh))
    {
        Write-Warning ("未找到 bash 接入脚本：{0}；请在仓库克隆目录执行 bash bash/carapace/setup.sh。" -f $setupSh)
        return
    }
    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if (-not $bash)
    {
        Write-Warning '未找到 bash：跳过 bash 接入；安装 Git for Windows（或发行版 bash）后重跑 Deploy-Carapace -Bash。'
        return
    }

    $bashArgs = @($setupSh)
    if ($Login) { $bashArgs += '--login' }
    $display = "bash $setupSh" + $(if ($Login) { ' --login' } else { '' })
    if ($WhatIf)
    {
        Write-Host ("[WhatIf] 执行：{0}" -f $display)
        return
    }

    Write-Host ''
    Write-Host ("接入 bash：{0}" -f $display)
    & $bash.Source @bashArgs
    if ($LASTEXITCODE -ne 0)
    {
        Write-Warning ("bash 接入脚本退出码 {0}：按上面的输出处理后重跑，或手工执行 {1}" -f $LASTEXITCODE, $display)
        return
    }

    $binInBash = @(& $bash.Source -c 'command -v carapace' 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not ($binInBash -join '').Trim())
    {
        Write-Warning 'bash 当前环境找不到 carapace：把安装目录加入 PATH（新终端生效），或设置 CARAPACE_BIN；再重开终端验证。'
    }
    Write-Host 'bash 侧已写入 rc 标记块：新开终端后执行 type _carapace_completer 验证。'
}

function Deploy-Carapace
{
    <#
    .SYNOPSIS
    安装 carapace 补全二进制（Windows/macOS/Linux），并打印启用方式（不自动修改 profile）。
    .DESCRIPTION
    carapace 是跨 shell 的外部 CLI 参数补全二进制，与 git-completion、argc-completions 并列。
    本命令从官方 GitHub Release 下载当前平台与架构的产物：Windows 为 zip，macOS/Linux 为 tar.gz；
    按同版本 checksums.txt 校验 SHA-256，解压 carapace 到目标目录并加入用户 PATH。
    完成后打印启用方式，不修改 profile；加载由 init 按 PsCarapace 配置完成，不设置 Tab 键绑定。
    加 -Enable 可在安装后直接启用 Carapace 组件并写入用户配置，当前会话立即加载。
    加 -Bash 会在安装后调用仓库内 bash/carapace/setup.sh，把同一二进制接入 bash：
    默认写非登录 shell 的 ~/.bashrc，加 -BashLogin 改写登录 shell 的 rc
    （~/.bash_profile、~/.bash_login 或 ~/.profile）。bash 侧与 PowerShell 侧互相独立，
    只写 rc 标记块，不修改 profile。未找到 bash 或 setup.sh 时只告警，不中断安装。
    默认查询最新 release；网络受限或需要可复现版本时用 -Version 指定版本号，可跳过 GitHub API。
    已存在 carapace 时默认跳过，-Force 重新下载覆盖；本地版本高于 -Version 时默认拒绝降级，
    确需降级加 -AllowDowngrade。下载失败可改用包管理器：Windows 用 scoop，macOS 用 brew，
    Linux 用发行版仓库或官方 .deb/.rpm/.apk。
    默认目录：Windows 为 ~/.cxxu/bin，其他平台为 ~/.local/bin；-Destination 与 -SkipPath 用于自定义目录或测试。
    .EXAMPLE
    Deploy-Carapace -Enable
    .EXAMPLE
    Deploy-Carapace -Bash
    .EXAMPLE
    Deploy-Carapace -Bash -BashLogin
    .EXAMPLE
    Deploy-Carapace -Version 1.8.2 -Proxy http://127.0.0.1:7897
    .EXAMPLE
    Deploy-Carapace -Destination "$HOME/.local/bin" -SkipPath -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 指定版本（可带 v 前缀）；留空查询最新 release
        [string]$Version = '',
        # 安装目录；留空时 Windows 用 ~/.cxxu/bin，其他平台用 ~/.local/bin
        [string]$Destination = '',
        # 本次下载使用的代理；未指定时读取 HTTPS_PROXY/HTTP_PROXY/ALL_PROXY
        [string]$Proxy = '',
        # 强制直连，忽略 -Proxy 与代理环境变量
        [switch]$NoProxy,
        # 不修改当前会话与用户 PATH（自行管理 PATH 时使用）
        [switch]$SkipPath,
        # 安装后启用 Carapace 组件并写入用户配置（当前会话立即加载）
        [switch]$Enable,
        # 安装后把 carapace 接入 bash（调用仓库内 bash/carapace/setup.sh，默认写 ~/.bashrc）
        [switch]$Bash,
        # 与 -Bash 配合：改写登录 shell 的 rc（~/.bash_profile、~/.bash_login 或 ~/.profile）
        [switch]$BashLogin,
        # 允许安装低于本地已装版本的 carapace
        [switch]$AllowDowngrade,
        # 已安装时也重新下载覆盖
        [switch]$Force
    )

    $platform = Get-CxxuHostPlatform
    if (-not $Destination)
    {
        $homeBin = if ($platform.IsWindows) { Join-Path $HOME '.cxxu' } else { Join-Path $HOME '.local' }
        $Destination = Join-Path $homeBin 'bin'
    }
    $binName = if ($platform.IsWindows) { 'carapace.exe' } else { 'carapace' }
    $archiveExt = if ($platform.IsWindows) { 'zip' } else { 'tar.gz' }

    $existing = Get-Command carapace -ErrorAction SilentlyContinue
    $existingVersion = ''
    if ($existing)
    {
        try
        {
            $existingOutput = @(& $existing.Source --version 2>&1)
            if ($LASTEXITCODE -eq 0) { $existingVersion = ($existingOutput -join ' ').Trim() }
        }
        catch { }
    }
    if ($existing -and -not $Force)
    {
        Write-Host ("carapace 已存在：{0}" -f $existing.Source)
        if ($existingVersion) { Write-Host ("版本：{0}" -f $existingVersion) }
        else { Write-Warning ("无法执行 {0} --version；可加 -Force 覆盖安装。" -f $existing.Source) }
        Write-Host '如需覆盖安装，加 -Force。'
        if ($Enable) { Enable-CxxuComponent -Id Carapace -Persist -Now -WhatIf:$WhatIfPreference }
        else { Show-CarapaceEnableHint }
        if ($Bash -or $BashLogin) { Invoke-CarapaceBashSetup -Login:$BashLogin -WhatIf:$WhatIfPreference }
        return
    }
    if ($Version -and $existingVersion -and -not $AllowDowngrade)
    {
        $installedMatch = [regex]::Match($existingVersion, '\d+\.\d+\.\d+')
        $requestedMatch = [regex]::Match($Version.TrimStart('v'), '^\d+\.\d+\.\d+')
        if ($installedMatch.Success -and $requestedMatch.Success)
        {
            $installed = [version]$installedMatch.Value
            $requested = [version]$requestedMatch.Value
            if ($requested -lt $installed)
            {
                throw ("本地已装 {0}，高于指定版本 {1}；确认要降级时加 -AllowDowngrade。" -f $installed, $requested)
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess('carapace', "安装到 $Destination"))
    {
        if ($Bash -or $BashLogin) { Invoke-CarapaceBashSetup -Login:$BashLogin -WhatIf }
        return
    }

    $rel = $null
    if ([string]::IsNullOrWhiteSpace($Version))
    {
        Write-Host '查询 carapace 最新 release ...'
        $rel = Get-CxxuLatestRelease -Repo 'carapace-sh/carapace-bin' -Proxy $Proxy -NoProxy:$NoProxy
        $tag = [string]$rel.tag_name
        $ver = $tag.TrimStart('v')
    }
    else
    {
        $ver = $Version.Trim().TrimStart('v')
        $tag = 'v' + $ver
    }
    if ($ver -notmatch '^\d+\.\d+\.\d+')
    {
        throw "无法识别的 carapace 版本号：$Version；请使用 1.8.2 这类三段版本。"
    }

    $assetName = "carapace-bin_${ver}_$($platform.OS)_$($platform.Arch).$archiveExt"
    $sumName = "carapace-bin_${ver}_checksums.txt"
    $baseUrl = "https://github.com/carapace-sh/carapace-bin/releases/download/$tag"
    $assetUrl = "$baseUrl/$assetName"
    $sumUrl = "$baseUrl/$sumName"
    if ($rel)
    {
        $releaseAsset = @($rel.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1)
        if (-not $releaseAsset.Count)
        {
            $available = @($rel.assets | Where-Object { $_.name -like "*_$($platform.OS)_*" } | ForEach-Object { $_.name })
            $availableText = if ($available.Count) { $available -join '、' } else { '无' }
            throw ("release {0} 中没有 {1}；当前平台可用产物：{2}" -f $tag, $assetName, $availableText)
        }
        $assetUrl = $releaseAsset[0].browser_download_url
        $sumAsset = @($rel.assets | Where-Object { $_.name -eq $sumName } | Select-Object -First 1)
        if ($sumAsset.Count) { $sumUrl = $sumAsset[0].browser_download_url }
    }

    $tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ('cxxu-carapace-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
    try
    {
        $archivePath = Join-Path $tmpRoot $assetName
        $sumPath = Join-Path $tmpRoot $sumName
        $pmHint = switch ($platform.OS)
        {
            'windows' { 'scoop install carapace-bin' }
            'darwin' { 'brew install carapace' }
            default { '发行版仓库，或官方 Release 的 .deb/.rpm/.apk' }
        }
        Write-Host ("下载 {0}（{1}）..." -f $assetName, $tag)
        try { Invoke-CxxuDownload -Url $assetUrl -OutFile $archivePath -Proxy $Proxy -NoProxy:$NoProxy }
        catch { throw ("下载 {0} 失败：{1}`n可改用包管理器：{2}。" -f $assetName, $_.Exception.Message, $pmHint) }
        Write-Host ("下载 {0} ..." -f $sumName)
        try { Invoke-CxxuDownload -Url $sumUrl -OutFile $sumPath -Proxy $Proxy -NoProxy:$NoProxy }
        catch { throw ("下载 {0} 失败：{1}`n可改用包管理器：{2}。" -f $sumName, $_.Exception.Message, $pmHint) }

        $sumText = [IO.File]::ReadAllText($sumPath)
        $match = [regex]::Match($sumText, '(?im)^([0-9a-f]{64})\s+\*?' + [regex]::Escape($assetName) + '\s*$')
        if (-not $match.Success)
        {
            throw ("校验文件中没有 {0} 的 SHA-256，停止安装。" -f $assetName)
        }
        $expected = $match.Groups[1].Value.ToLowerInvariant()
        $actual = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected)
        {
            throw ("SHA-256 不匹配：期望 {0}，实际 {1}。已停止安装。" -f $expected, $actual)
        }
        Write-Host '校验通过（SHA-256）'

        $unzip = Join-Path $tmpRoot 'unzip'
        Expand-CxxuReleaseArchive -Path $archivePath -Destination $unzip
        $exe = @(Get-ChildItem -LiteralPath $unzip -Recurse -Filter $binName -File | Select-Object -First 1)
        if (-not $exe.Count)
        {
            throw ("压缩包内没有 {0}，已停止安装。" -f $binName)
        }
        if (-not (Test-Path -LiteralPath $Destination))
        {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }
        $target = Join-Path $Destination $binName
        $staged = Join-Path $Destination ($binName + '.new')
        try
        {
            Copy-Item -LiteralPath $exe[0].FullName -Destination $staged -Force
            if (-not $platform.IsWindows)
            {
                $chmod = Get-Command chmod -ErrorAction SilentlyContinue
                if (-not $chmod) { throw '未找到 chmod，无法给 carapace 添加执行权限；请安装 coreutils 或手动执行 chmod +x。' }
                & $chmod.Source '+x' $staged
                if ($LASTEXITCODE -ne 0) { throw ("chmod +x 失败（退出码 {0}）：{1}" -f $LASTEXITCODE, $staged) }
            }
            if ($PSVersionTable.PSEdition -eq 'Core')
            {
                [System.IO.File]::Move($staged, $target, $true)
            }
            else
            {
                Move-Item -LiteralPath $staged -Destination $target -Force
            }
        }
        catch
        {
            Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
            throw
        }
        if (-not $SkipPath)
        {
            Add-CxxuBinToPath -BinDir $Destination
        }

        $output = @(& $target --version 2>&1)
        if ($LASTEXITCODE -ne 0)
        {
            throw ("carapace --version 退出码 {0}：{1}" -f $LASTEXITCODE, ($output -join ' '))
        }
        Write-Host ("carapace 已安装：{0}" -f $target)
        Write-Host ("版本：{0}" -f (($output -join ' ').Trim()))
        $resolved = Get-Command carapace -ErrorAction SilentlyContinue
        if (-not $resolved)
        {
            Write-Host ("当前会话未解析到 carapace；把 {0} 加入 PATH 后即可直接调用。" -f $Destination)
        }
        elseif ($resolved.Source -ne $target)
        {
            Write-Warning ("PATH 中仍先命中另一个 carapace：{0}。请确认 {1} 在它之前，或移除旧版本。" -f $resolved.Source, $Destination)
        }
        if ($Enable) { Enable-CxxuComponent -Id Carapace -Persist -Now -WhatIf:$WhatIfPreference }
        else { Show-CarapaceEnableHint }
        if ($Bash -or $BashLogin) { Invoke-CarapaceBashSetup -Login:$BashLogin -WhatIf:$WhatIfPreference }
    }
    finally
    {
        Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Deploy-CompletionStack
{
    <#
    .SYNOPSIS
    新机补全栈：默认只装仓库内核心层（CxxuCommand 内联预测 + CxxuTab Tab 补全），其余按需追加。
    .DESCRIPTION
    默认层不发起网络请求、不依赖仓库外组件：同步 net9 predictor 与 5.1 Tab 两套活件，
    并补建用户配置模板；Tab 补全默认开启（$env:PsTab 未显式关闭时首个 Tab 自动加载）。
    可选层用开关显式选择，避免新机默认下载一堆仓库外依赖：
    - -IncludeArgc：argc-completions 仓库 + argc.exe/yq.exe（并发下载，优先 scripts-deps 转存仓库）。
    - -IncludeFuzzy：PSFzf 模块 + fzf/zoxide 二进制（优先 scoop/winget/brew，失败回退转存仓库再回上游）。
    - -IncludePredictor：CompletionPredictor 模块（参数/路径内联预测）。
    - -IncludePSCompletions：PSCompletions 模块（命令参数补全库）。
    - -IncludeGitCompletion：git-completion 模块（git/gitk 的 Tab 补全，init 检测到后自动挂载）。
    - -All：一次选择以上全部；-SkipArgc / -SkipBinaries 仍可用于排除 argc 或二进制。
    国内网络不稳时，可先 Set-Proxy On（或设置 HTTPS_PROXY/HTTP_PROXY）再执行；
    下载会自动识别代理，也可用 -Proxy/-NoProxy 单次覆盖；-NoMirror 跳过转存仓库直接走上游。
    缺少可选组件只提示，不影响核心层。
    -WhatIf 空跑看动作，零副作用。装完开新终端跑 init。
    .EXAMPLE
    Deploy-CompletionStack -WhatIf
    .EXAMPLE
    Deploy-CompletionStack
    .EXAMPLE
    Deploy-CompletionStack -IncludeArgc -IncludeFuzzy -Proxy http://127.0.0.1:7897
    .EXAMPLE
    Deploy-CompletionStack -All -SkipBinaries
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 追加 argc-completions（仓库 + argc.exe/yq.exe，默认不装）
        [switch]$IncludeArgc,
        # 追加 PSFzf 模块与 fzf/zoxide 二进制（默认不装）
        [switch]$IncludeFuzzy,
        # 追加 CompletionPredictor 模块（默认不装）
        [switch]$IncludePredictor,
        # 追加 PSCompletions 模块（默认不装）
        [switch]$IncludePSCompletions,
        # 追加 git-completion 模块（默认不装；init 检测到后自动挂载 git/gitk 补全）
        [switch]$IncludeGitCompletion,
        # 等价于同时勾选以上全部 Include 开关
        [switch]$All,
        # 兼容旧参数：即使 -All/-IncludeArgc 也跳过 argc
        [switch]$SkipArgc,
        # 兼容旧参数：即使 -IncludeFuzzy 也跳过 fzf/zoxide 二进制
        [switch]$SkipBinaries,
        # argc-completions 安装目录（默认 ~/argc-completions；已存在则复用）
        [string]$ArgcRoot = '',
        # 本次下载使用的代理；未指定时读取 HTTPS_PROXY/HTTP_PROXY/ALL_PROXY
        [string]$Proxy = '',
        # 强制直连，忽略 -Proxy 与代理环境变量
        [switch]$NoProxy,
        # 关闭并发下载，改为逐个下载
        [switch]$NoParallel,
        # 跳过 scripts-deps 转存仓库，直接走上游 GitHub
        [switch]$NoMirror
    )

    if ($All)
    {
        $IncludeArgc = $true
        $IncludeFuzzy = $true
        $IncludePredictor = $true
        $IncludePSCompletions = $true
        $IncludeGitCompletion = $true
    }

    # 核心层:CxxuCommand(命令名分层模糊提示)与 CxxuTab 都随仓库分发,需要的是活件,不是安装模块
    # $coreReady:True=已同步;False=不可用;$null=WhatIf 只报告计划
    # $tabReady:同义,用于 5.1 只能发布 Tab 活件的分支
    $coreReady = $false
    $tabReady = $false
    $psVersionOk = $PSVersionTable.PSVersion -ge [version]'7.5'
    Write-Host '核心层：仓库内 CxxuCommand + CxxuTab（无网络、无仓库外依赖）'

    if (-not $psVersionOk)
    {
        if (($IsMacOS -eq $true)) { Write-Warning 'pwsh 版本低于 7.5：CxxuCommand 内联预测不可用，Tab 补全仍可用；建议 brew upgrade --cask powershell 到 7.5+' }
        else { Write-Warning 'pwsh 版本低于 7.5：CxxuCommand 内联预测不可用，Tab 补全仍可用；建议 Update-PowerShell 到 7.5+' }
    }

    if (Get-Command Sync-CxxuPredictor -ErrorAction SilentlyContinue)
    {
        # 5.1 新机也同步 net9 活件，之后开 7.5 直接有预测；只有 net9 自编译标记存在时才只同步 5.1 Tab 活件。
        $ps51Only = $false
        if (-not $psVersionOk)
        {
            $marker = Join-Path (Join-Path (Join-Path $HOME '.cxxu') 'bin') 'local-build.txt'
            if (Test-Path -LiteralPath $marker)
            {
                $markerText = Get-Content -LiteralPath $marker -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($markerText -match 'src=local') { $ps51Only = $true }
            }
        }
        if ($PSCmdlet.ShouldProcess('CxxuCommand/CxxuTab', '同步 predictor 与 Tab 活件'))
        {
            if ($ps51Only) { Sync-CxxuPredictor -Ps51Only }
            else { Sync-CxxuPredictor }
            if ($psVersionOk) { $coreReady = $true }
            else { $tabReady = $true }
        }
        else
        {
            if ($psVersionOk) { $coreReady = $null }
            else { $tabReady = $null }
        }
    }
    else
    {
        Write-Warning '未找到 Sync-CxxuPredictor（TerminalTools 未加载），无法生成 CxxuCommand 活件；可重开终端后重试'
    }

    # 可选层：只有显式 Include 才下载/安装仓库外依赖
    if ($IncludeArgc)
    {
        if ($SkipArgc) { Write-Host 'argc-completions：按 -SkipArgc 跳过' }
        else
        {
            Write-Host '可选层：argc-completions 参数补全'
            Deploy-ArgcCompletions -Root $ArgcRoot -Proxy $Proxy -NoProxy:$NoProxy -NoParallel:$NoParallel -NoMirror:$NoMirror -WhatIf:$WhatIfPreference
        }
    }

    if ($IncludeFuzzy)
    {
        Write-Host '可选层：PSFzf + fzf/zoxide'
        if (-not (Get-Module -ListAvailable PSFzf))
        {
            if ($PSCmdlet.ShouldProcess('PSFzf', '安装 PS 模块（可选）'))
            {
                Confirm-ModuleInstalled -ModuleName PSFzf -Install
            }
        }
        else { Write-Verbose 'PSFzf 已有，跳过' }

        if ($SkipBinaries) { Write-Host 'fzf/zoxide：按 -SkipBinaries 跳过' }
        elseif ($PSCmdlet.ShouldProcess('fzf/zoxide', '安装二进制（可选）'))
        {
            Install-CxxuFuzzyBinaries -Proxy $Proxy -NoProxy:$NoProxy -NoParallel:$NoParallel -NoMirror:$NoMirror
        }
    }

    if ($IncludePredictor -and -not (Get-Module -ListAvailable CompletionPredictor))
    {
        if ($PSCmdlet.ShouldProcess('CompletionPredictor', '安装 PS 模块（可选）'))
        {
            Confirm-ModuleInstalled -ModuleName CompletionPredictor -Install
        }
    }

    if ($IncludePSCompletions -and -not (Get-Module -ListAvailable PSCompletions))
    {
        if ($PSCmdlet.ShouldProcess('PSCompletions', '安装 PS 模块（可选）'))
        {
            Confirm-ModuleInstalled -ModuleName PSCompletions -Install
        }
    }

    if ($IncludeGitCompletion -and -not (Get-Module -ListAvailable git-completion))
    {
        if ($PSCmdlet.ShouldProcess('git-completion', '安装 PS 模块（可选）'))
        {
            Confirm-ModuleInstalled -ModuleName git-completion -Install
        }
    }

    if ($coreReady -eq $true) { Write-Host '核心 CxxuCommand：预测活件已就绪，新终端跑 init 生效（开关 $env:PsPredictor）' }
    elseif ($null -eq $coreReady) { Write-Host '核心 CxxuCommand：本次为空跑（-WhatIf），未同步活件；去掉 -WhatIf 执行' }
    elseif ($tabReady -eq $true) { Write-Host '核心 CxxuCommand：5.1 仅 Tab 补全，Tab 活件已就绪；重开终端后按 Tab 生效（开关 $env:PsTab）' }
    elseif ($null -eq $tabReady) { Write-Host '核心 CxxuCommand：本次为空跑（-WhatIf），未同步 5.1 Tab 活件；去掉 -WhatIf 执行' }
    else { Write-Host '核心 CxxuCommand：未就绪（内联预测需 pwsh 7.5+；5.1 Tab 需执行 Sync-CxxuPredictor）' }

    Write-Host '默认层只含仓库内活件；可选层按 -IncludeArgc/-IncludeFuzzy/-IncludePredictor/-IncludePSCompletions/-IncludeGitCompletion 追加（-All 全选）。'
    if (-not $IncludeArgc -and -not $IncludeFuzzy -and -not $IncludePredictor -and -not $IncludePSCompletions -and -not $IncludeGitCompletion)
    {
        Write-Host '未选择可选层：本次没有网络下载，也没有安装仓库外组件。'
    }
    if ($env:PsTab -match '^(False|0|No|Off)$') { Write-Warning 'PsTab 当前为关闭：Tab 补全不会加载；需要时 Enable-PsPlugin Tab -Persist' }
    if ($env:PsPredictor -match '^(False|0|No|Off)$') { Write-Warning 'PsPredictor 当前为关闭：命令名内联预测不会加载；需要时 Enable-PsPlugin Predictor -Persist' }
    if ($IncludeArgc -and ($env:PsArgc -match '^(False|0|No|Off)$')) { Write-Warning 'PsArgc 当前为关闭：argc 参数补全不会加载；需要时 Enable-PsPlugin Argc -Persist' }
    Write-Host '验收：pwsh 7.5+ 在 ListView 输 get-child；Tab 输 get-chi；参数输 nginx -<Tab>；git 输 git ch<Tab>；异常先跑 doctor。'
    if (($IncludeArgc -or $IncludeFuzzy -or $IncludePSCompletions -or $IncludeGitCompletion) -and -not $Proxy -and -not $NoProxy -and -not (Get-CxxuProxyUrl))
    {
        Write-Host '提示：国内网络下载不稳定时，可先 Set-Proxy On（或设置 HTTPS_PROXY）再重跑；下载会自动识别代理。'
    }
    # 用户配置模板兜底(新机一键装后就有文件可改;已存在则 no-op;-WhatIf 下只显示意图)
    if (Get-Command New-CxxuConfigTemplate -ErrorAction SilentlyContinue) { New-CxxuConfigTemplate }
}
