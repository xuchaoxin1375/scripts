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

function Deploy-CompletionStack
{
    <#
    .SYNOPSIS
    新机一键补全栈:PSFzf/CompletionPredictor 模块 + fzf/zoxide 二进制 + 版本门(+可选 PSCompletions)。
    .DESCRIPTION
    Test-PsEnvReadiness 只读体检,本函数动手补:缺的模块直装,二进制有 scoop 就装、无则给命令;
    pwsh 不够 7.5 只警告不停手(CxxuPredictor 用不上,其它照常);-WhatIf 空跑看动作,零副作用。
    自研 CxxuPredictor 随仓库零安装,不在这里装。装完开新终端跑 init,首跑自建缓存。
    .EXAMPLE
    Deploy-CompletionStack -WhatIf
    .EXAMPLE
    Deploy-CompletionStack -IncludePSCompletions
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # 按需装 PSCompletions(70+ 命令补全,延迟加载;默认不装)
        [switch]$IncludePSCompletions,
        # 跳过 fzf/zoxide 二进制(已装/不用)
        [switch]$SkipBinaries
    )

    if ($PSVersionTable.PSVersion -lt [version]'7.5')
    {
        if (($IsMacOS -eq $true)) { Write-Warning 'pwsh 版本低于 7.5:CxxuPredictor(net9 dll)用不上,其它补全照常;建议 brew upgrade --cask powershell 到 7.5+' }
        else { Write-Warning 'pwsh 版本低于 7.5:CxxuPredictor(net9 dll)用不上,其它补全照常;建议 Update-PowerShell 到 7.5+' }
    }
    foreach ($mod in @('PSFzf', 'CompletionPredictor'))
    {
        if (Get-Module -ListAvailable $mod)
        {
            Write-Verbose "$mod 已有,跳过"
            continue
        }
        if ($PSCmdlet.ShouldProcess($mod, '安装 PS 模块'))
        {
            Confirm-ModuleInstalled -ModuleName $mod -Install
        }
    }
    if ($IncludePSCompletions -and -not (Get-Module -ListAvailable PSCompletions))
    {
        if ($PSCmdlet.ShouldProcess('PSCompletions', '安装 PS 模块(可选)'))
        {
            Confirm-ModuleInstalled -ModuleName PSCompletions -Install
        }
    }
    if (-not $SkipBinaries)
    {
        foreach ($bin in @('fzf', 'zoxide'))
        {
            if (Get-Command $bin -ErrorAction SilentlyContinue)
            {
                Write-Verbose "$bin 已有,跳过"
                continue
            }
            if (Get-Command scoop -ErrorAction SilentlyContinue)
            {
                if ($PSCmdlet.ShouldProcess($bin, 'scoop 安装二进制'))
                {
                    scoop install $bin
                }
            }
            elseif (Get-Command brew -ErrorAction SilentlyContinue)
            {
                if ($PSCmdlet.ShouldProcess($bin, 'brew 安装二进制'))
                {
                    brew install $bin
                }
            }
            else
            {
                Write-Warning "$bin 缺失且无包管理器:Windows 先装 scoop(Deploy-ScoopByGithubMirrors)再 scoop install $bin;macOS 跑 brew install $bin"
            }
        }
    }
    Write-Host '补全栈就绪:开新终端跑 init,首跑自建缓存(Ctrl+R/z);开关 $env:PsFzf/$env:PsZoxide'
    # 用户配置模板兜底(新机一键装后就有文件可改;已存在则 no-op;-WhatIf 下只显示意图)
    if (Get-Command New-CxxuConfigTemplate -ErrorAction SilentlyContinue) { New-CxxuConfigTemplate }
}

