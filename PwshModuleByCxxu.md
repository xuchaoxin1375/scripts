[toc]

# abstract

本仓库内的PS模块是powershell的模块集合

包含了许多实用的powershell函数


## 本模块设计风格与配置说明

- 本**模块集**经过历次迭代,最终将所有自动导入运行的语句封装为若干函数并分散到几个模块中,比如`init`模块,`pwsh`模块
  - 配合模块自动导入(将模块路径添加到环境变量`$psModulePath`中),而`$profile`中可以只保留了一个语句调用 `init`函数(或者其他简洁的逻辑)
  - `init`函数定义在 `Init.psm1`模块中
- 这么做的一个好处在于编辑 `$profile`往往需要管理员权限(尤其是`$PROFILE.AllUsersAllHosts`,这是一个全局文件),而且如果有不同版本的powershell想要加载同一个**配置文件**就不方便
  - 另一方面,powershell支持自动加载模块,而且这个过程灵活快速,不会影响启动powershell的时间
  - 因此,应该尽量模块化配置

### 经典的开源模块posh-git参考学习

- [Git - Git 在 PowerShell 中使用 Git (git-scm.com)](https://git-scm.com/book/zh/v2/附录-A%3A-在其它环境中使用-Git-Git-在-PowerShell-中使用-Git)

## 如何载入模块集PS👺

- 分为三个步骤配置
  1. 克隆本项目(如果不需要powershell模块以外的目录,可以提取`PS`出来,其他的删除即可
  2. 检查powershell版本(推荐安装powershell 7+,以下简称为`pwsh`)
  3. 配置环境变量`PsModulePath`(以便自动导入模块)
  4. 创建并配置pwsh的配置文件,即`profile.ps1`文件

## 软件准备👺

安装**powershell7**和**git**

前者是必备,后者是推荐(便于更新模块版本)

都可以利用加速镜像下载,或者使用国内的应用商店(联想应用商店,可以在线下载,或者火绒应用商店),虽然版本可能不是最新的,但是可以让模块运行起来

### 检查powershell版本

- 本模块集主要为`powershell 7`开发(简记为`pwsh`)，而非系统自带的`powershell`(v5)

  - ```powershell
    PS[BAT:79%][MEM:32.65% (10.35/31.70)GB][17:18:40]
    # [C:\repos\scripts]
     $PSVersionTable
    
    Name                           Value
    ----                           -----
    PSVersion                      7.4.2
    PSEdition                      Core
    GitCommitId                    7.4.2
    OS                             Microsoft Windows 10.0.22631
    Platform                       Win32NT
    PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0…}
    PSRemotingProtocolVersion      2.3
    SerializationVersion           1.1.0.1
    WSManStackVersion              3.0
    ```

- 其中PSVersion字段第一个数字表示powershell大版本

- 虽然也部分支持powershell v5,但是为了获得最好的兼容性和可用性,建议使用powershell v7

#### 下载powershell 7

- [powershell7下载和安装@powershell下载加速@国内镜像加速下载安装包-CSDN博客](https://cxxu1375.blog.csdn.net/article/details/140461455)

## 自动部署(一键运行脚本)👺👺

```powershell

function Test-DirectoryEmpty
{
    <# 
    .SYNOPSIS
    判断一个目录是否为空目录
    .PARAMETER directoryPath
    要检查的目录路径
    .PARAMETER CheckNoFile
    如果为true,递归子目录检查是否有文件
    #>
    param (
        [string]$directoryPath,
        [switch]$CheckNoFile
    )

    if (-Not (Test-Path -Path $directoryPath))
    {
        throw "The directory path '$directoryPath' does not exist."
    }
    if ($CheckNoFile)
    {

        $itemCount = (Get-ChildItem -Path $directoryPath -File -Recurse | Measure-Object).Count
    }
    else
    {
        $items = Get-ChildItem -Path $directoryPath
        $itemCount = $items.count
    }
    return $itemCount -eq 0
}
function Get-CxxuPsModulePackage
{
    [CmdletBinding()]
    param(
        $Directory = "$home/Downloads/CxxuPsModules",
        $url = 'https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main',
        $outputFile = "scripts-$( Get-Date -Format 'yyyy-MM-dd--hh-mm-ss').zip"
    )
    $PackgePath = "$Directory/$outputFile"
    Write-Verbose "Downloading $url to $PackgePath"
    Invoke-WebRequest -Uri $url -OutFile $PackgePath 
    return $PackgePath
}
function Deploy-CxxuPsModules
{
    <# 
    .SYNOPSIS
    一键部署CxxuPsModules，将此模块集推荐的自动加载工作添加到powershell的配置文件$profile中
    请使用powershell7部署
    .EXAMPLE
    直接调用,不是用参数,适合第一次部署
    deploy-CxxuPsModules
    .EXAMPLE
    使用在线方案,从默认的gitee仓库克隆下载(要求预先安装Git软件)
    PS C:\Users\cxxu > deploy-CxxuPsModules -Mode FromRemoteGit -RepoPath C:/TestPsM -Verbose
    Mode:Clone From Remote repository:[gitee]
    VERBOSE: https://gitee.com/xuchaoxin1375/scripts.git
    VERBOSE: C:/TestPsM
    Cloning into 'C:/TestPsM'...
    remote: Enumerating objects: 430, done.
    remote: Counting objects: 100% (238/238), done.
    remote: Compressing objects: 100% (206/206), done.
    remote: Total 430 (delta 72), reused 82 (delta 1), pack-reused 192
    Receiving objects: 100% (430/430), 1004.73 KiB | 659.00 KiB/s, done.
    Resolving deltas: 100% (80/80), done.

    Name         Value
    ----         -----
    PsModulePath C:/TestPsM\PS
                C:\Users\cxxu\Desktop\TestPsy\PS
                C:\Users\cxxu\scoop\modules
    .EXAMPLE
    从远程的Github仓库下载zip包,并解压到指定目录(如果本地已经有包,则优先使用本地的包)
    
    PS C:\Users\cxxu\scoop\apps\powershell\current> deploy-CxxuPsModules -Mode FromPackage -RepoPath C:/TestDirPs -PackagePath $home/desktop  -Verbose
    VERBOSE: Downloading https://codeload.github.com/xuchaoxin1375/scripts/zip/refs/heads/main to C:\Users\cxxu/Downloads/CxxuPsModules/scripts-2024-09-19--09-05-42.zip
    VERBOSE: Requested HTTP/1.1 GET with 0-byte payload
    VERBOSE: Received HTTP/1.1 response of content type application/zip of unknown size
    VERBOSE: File Name: scripts-2024-09-19--09-05-42.zip
    Mode:Expanding local pacakge:[C:\Users\cxxu/Downloads/CxxuPsModules/scripts-2024-09-19--09-05-42.zip]
    C:\TestDirPs\scripts-main C:/TestDirPs/scripts
    VERBOSE: Performing the operation "Remove Directory" on target "C:\TestDirPs\scripts-main".

    Name         Value
    ----         -----
    PsModulePath C:/TestDirPs\PS
                C:\Users\cxxu\scoop\modules

    #>
    [CmdletBinding()]
    param(
        # 模块集所在仓库的存放目录
        $RepoPath = "$env:systemdrive/repos/scripts",
        # 添加到环境变量中的路径
        $NewPsPath = "$RepoPath\PS",
        [ValidateSet('Gitee,Github')]$Source = 'gitee',
        $PackagePath = "$home/Downloads/CxxuPsModules/scripts*.zip",
        # 选择部署模式:如果选择FromPackage,则仅尝试查找本地包,如果没有,则通过下载模块集包到本地,然后执行安装(不保证成功下载)
        # 如果选择默认的Default,则依次检查本地包是否存在,如果不存在,则尝试通过克隆的方式下载(要求已经安装git)
        [ValidateSet('Default', 'FromPackage', 'FromRemoteGit')]$Mode = 'Default'
    )
        
    if ($host.Version.Major -lt 7)
    {
        Throw 'Please use powershell7 to deploy CxxuPsModules!'
    }
    
    # 路径准备
    # $NewPsPath = $NewPsPathPattern | Invoke-Expression
    # 检查路径占用
    if (Test-Path $RepoPath)
    {
        Write-Host "$($RepoPath) already exists!"
        if (! (Test-DirectoryEmpty $RepoPath ))
        {
            Write-Host "The directory [$RepoPath] is not empty,please choose another path!" -ForegroundColor Red
            Throw 'Try another path(RepoPath)! OR delete or rename(backup) the exist directory!'
            # $RepoPath = Read-Host -Prompt 'Input new path (Ctrl+C to exit)'
            # Write-Verbose "Updated RepoPath to [$RepoPath]"
            # # $newPsPath = "$RepoPath\PS"
            # $NewPsPath = $NewPsPathPattern | Invoke-Expression
            # Write-Verbose "Updated newPsPath to [$newPsPath]"
        }
        New-Item -ItemType Directory $RepoPath -Verbose
    }
    # if (!(Test-Path $RepoPath))
    # {
    #     New-Item -ItemType Directory $RepoPath -Verbose
    # }

    #模式及其代码准备
    $RemoteGitCloneScript = { 
        Write-Host "Mode:Clone From Remote repository:[$source]" -ForegroundColor Blue
        $GitCmdAvailability = Get-Command git -ErrorAction SilentlyContinue
        if (!$GitCmdAvailability)
        {
            Throw 'Git is not available on your system,please install it first!'
        }
        $url = "https://${Source}.com/xuchaoxin1375/scripts.git"
        Write-Verbose $url
   
        Write-Verbose $RepoPath
        #克隆仓库
        # git 支持指定一个不存在的目录作为克隆目的地址,所以可以不用检查目录是否存在并手动创建
        git clone $url $RepoPath 
    }
    $LocalScript = {
        Write-Host "Mode:Expanding local pacakge:[$PackagePath]" -ForegroundColor Green
        # $RepoPathParentDir = Split-Path $RepoPath -Parent
        # 指定要解压到的目录,如果不存在Expand-archive会自动创建相应的目录
        # 获取本地已下载的可用的最新版本
        #利用Desceding将最新的排在前面
        $files = Get-ChildItem $PackagePath | Sort-Object -Property LastWriteTime -Descending 
        $PackagePath = @($files)[0]
        # 解压到合适的目录下
        Expand-Archive -Path $PackagePath -DestinationPath $RepoPath -Force
        
        $rawPath = Get-ChildItem "$RepoPath/scripts*" -Directory | Select-Object -First 1
        $newPath = "$RepoPath/scripts"

        Write-Host @($rawPath, $newPath  ) -ForegroundColor Blue

        Move-Item $rawPath/* $RepoPath -Force
        #移除空目录(如果上述步骤顺利的话)
        Remove-Item $rawPath -Verbose #如果非空,会警报用户
        # Rename-Item $rawPath $newPath -Verbose
    }
    if ($Mode -eq 'Default')
    {

        if ((Test-Path $PackagePath))
        {
            & $LocalScript
        }
        else
        {
            
            & $RemoteGitCloneScript
        }
    }
    elseif ($Mode -eq 'FromPackage')
    {
        # 自动调用默认的下载行为
        # 您也可以手动调用Get-CxxuPsModulePackage下载包到指定位置,然后通过外部传递包的目录
        $PackagePath = Get-CxxuPsModulePackage
        & $LocalScript
    }
    elseif ($Mode -eq 'FromRemoteGit')
    {
        & $RemoteGitCloneScript
    }
 
    # $RepoPath = 'C:\repos\scripts\PS' #这里修改为您下载的模块所在目录,这里的取值作为示范
    $env:PSModulePath = ";$NewPsPath" #为了能够调用CxxuPSModules中的函数,这里需要这么临时设置一下
    Add-EnvVar -EnvVar PsModulePath -NewValue $newPsPath -Verbose #这里$RepoPath上面定义的(默认是User作用于,并且基于User的原有取值插入新值)
    # 你也可以替换`off`为`LTS`不完全禁用更新但是降低更新频率(仅更新LTS长期支持版powershell)
    [System.Environment]::SetEnvironmentVariable('powershell_updatecheck', 'LTS', 'user')

    #添加基础环境自动执行任务到$profile中
    # Add-CxxuPsModuleToProfile

    #检查模块设置效果
    Start-Process -FilePath pwsh -ArgumentList '-noe -c p'
}
#调用函数 (详情可以参考代码内文档)
deploy-CxxuPsModules

```

### 用法文档

- 将上述代码粘贴到powershell7窗口中,回车执行
- 通过help命令来查看帮助

```powershell
help Deploy-CxxuPsModules -Full
```

### 运行说明

- 无参数直接调用部署函数版本要求你已经安装git,以下版本尝试从github下载本仓库包(版本可能滞后),如果你不想安装git可以尝试指定`Mode`选择离线安装以下方案
  - Gitee下载源代码也可以,但是需要登陆才能获取下载链接
  - Github虽然慢,也可能连不上,但是仓库很小,能连上的话不会下载太久
- 如果下面方案不行,那么只好下载git,然后运行其他Mode方案,比如无参数,或者手动下载包,然后通过参数`PackagePath`来指定包的位置进行部署

```powershell
deploy-CxxuPsModules -Mode FromPackage -Verbose 
```



## 手动部署

### 下载或者克隆仓库到本地(二选一)

您有两种方式使用本仓库

一种是直接从仓库网站下载按钮提供的下载压缩包选项下载下来,另一种是用git 工具克隆本在线仓库

#### 下载仓库压缩包直接使用

- 虽然使用git 可以方便管理代码仓库,但是对于非专业人士这不是必须的
- 仅仅使用本仓库可以直接下载压缩包(可能需要注册登录网站的账号才能够下载),然后解压到自己选定的目录
  - [ 本仓库Scripts下载ZIP (gitee.com)](https://gitee.com/xuchaoxin1375/scripts/repository/archive/main.zip)

#### git方案克隆使用

- 安装git 

  - [Git - Downloads (git-scm.com)](https://git-scm.com/downloads)
    - 这里的连接是github release的链接,您可以使用加速镜像站获取加速下载的连接:[GitHub 文件加速 - Moeyy](https://moeyy.cn/gh-proxy)
  - 或者直接从镜像站加速下载:[CNPM Binaries Mirror (npmmirror.com)](https://registry.npmmirror.com/binary.html?path=git-for-windows/)

- 本仓库发布在gitee,您可以在仓库主页面点击克隆按钮获得连接

  - 相关仓库:

    ```http
    https://gitee.com/xuchaoxin1375/scripts.git
    ```

- 在您的计算机执行`git clone` 命令即可



### 配置环境变量👺

如果您的电脑只有一个用户的话,那么使用用户级别的变量配置就足够了

#### 临时启用模块

假设你克隆了本项目,并且希望在正式修改环境变量(永久化)之前就能够使用本模块集中的模块,那么可以简单执行形如一下的语句(这种方法是临时生效,如果你打开新的powershell或者调用`pwsh`创建新shell进程,就会失效)

```powershell
$p="C:\repos\scripts\PS" #这里修改为您下载的模块所在目录,这里的取值作为示范
$env:PSModulePath=";$p"
```

- 然后,您可以(临时地)执行`Deploy-EnvsByPwsh`这类方法,将您之前使用`backup-EnvsByPwsh`备份的环境变量导入到当前系统中

- 这种方法非常适合于双系统用户,并且使用过模块中提供的环境变量备份函数,如果是初次使用本项目的用户,这种方法不是很有用

- 事实上,如果你配置正确,那么这时候已经可以调用模块中的相关函数了,例如,您可以执行`init`看看shell会返回什么内容

- 其次,可以追加执行

  ```powershell
  add-EnvVar -EnvVar PsModulePath -NewValue $p -Verbose #这里$p上上面定义的
  ```

#### 持久化添加

- 查看后续章节详解

## 持久化添加到环境变量

- 以下操作会(间接)修改注册表

### 方案1

采用临时配置,然后调用本模块集中的持久化变量配置命令,让配置持久化

```powershell
$p="C:\repos\scripts\PS" #这里修改为您下载的模块所在目录,这里的取值作为示范
$env:PSModulePath=";$p"
add-EnvVar -EnvVar PsModulePath -NewValue $p -Verbose #这里$p上上面定义的
```

如果还需要设置为系统级环境变量(对所有用户生效),那么追加执行以下内容(需要管理员权限)

> 下面的语句不可以独立执行，依赖于上铺垫

```powershell
add-EnvVar -EnvVar PsModulePath -NewValue $p -Verbose  -Scope Machine
```

操作演示:

```powershell
PS> Add-EnvVar -EnvVar psmodulePath -NewValue $p -Scope Machine -Verbose

Name         Value
----         -----
psmodulePath C:\repos\scripts\ps
             C:\Program Files\WindowsPowerShell\Modules
             C:\Windows\system32\WindowsPowerShell\v1.0\Modules
```



### 方案2

#### 用户级变量配置

- 对于第一次使用本模块集的用户,执行以下powershell语句配置

  - ```powershell
    #👺注意以下自己实际存放模块的路径(建议和我同一个路径省事)
    $ThisModuleSetPath="C:\repos\scripts\PS" 
    #这里末尾不要有多余的`\`,容易造成异常(windows解析环境变量不是很鲁棒,
    #可能在某天的某个时刻突然间无法正确解析了,因此尽量遵循windows的规范或者模仿自带的环境变量取值)
    
    $FullPsModulePath="$ThisModuleSetPath;$env:PsModulePath"
    #直接修改了当前shell上下文的`$env:PsModulePath`
    $env:PSModulePath=$FullPsModulePath
    #将修改应用到注册表中
    setx PSModulePath $FullPsModulePath
    ```

  - 这一步默认**仅修改用户级别的环境变量**

#### 系统级变量配置

- 如果需要修改**机器级别的环境变量**(系统环境变量),请使用**管理员权限**,配合选项`/M`即**追加执行**:

  ```powershell
  setx PSModulePath $ThisModuleSetPath /M
  ```

  - 默认情况下，系统环境变量中没有`PsModulePath`这个变量

  - 上述的追加语句会创建一个系统级变量,并且赋值为本模块存放路径,而用户级环境变量中的`PsModulePath`不变化

- 您可以选择增强:将系统级变量赋于完整的`PsModulePath`所有相关路径(尽管这个环境变量我们一般只关心自己的模块所在位置,默认值主要是很对windows powershel v5,不太有存在感)

  ```powershell
  setx PSModulePath $FullPsModulePath /M
  ```

## 设置powershell执行策略(按需执行)

- 如果您遇到执行模块中的函数报错(尤其是自带的powershell v5),请尝试执行一下命令,然后重试

  - ```POWERSHELL
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
    ```

- 或者在开发者选项中配置相关内容



## 配置 `$Profile`自动初始化(可选)👺

### 自动配置

```powershell
Add-CxxuPsModuleToProfile
```

- 上述语句将为您的`$profile`文件添加适当的内容,以便自动导入基本环境(调用前提是你已经正确完成模块自动导入路径的配置)

- 详细使用说明可以通过

  ```powershell
  help Add-CxxuPsModuleToProfile -full
  ```

  进行查看

### 手动配置

- 如果您不在意加载powershell的那几秒钟,可以将`init`函数的调用配置到`$profile`文件中

  ```powershell
  'init' > $profile
  ```

  

- 此外,本项目还提供了一个折衷的方案,仅导入最常用的powershell变量和别名

  ```powershell
  'p'>$profile
  ```

- 配置很短,可以直接手打或者粘贴运行

### 全局配置(为所有用户配置)

- 如果需要所有用户自动导入,则需要以**管理员权限**来执行:

  - ```powershell
    $exp='init' #完整的导入预定义的变量和别名
    #或者响应更快的折衷方案
    $exp='p' #p是为了简单而设置的短名函数,导入基本常用的模块,比如Terminal-icons,PSReadLine配置和少量预定义变量和别名,以及设置平衡的prompt样式;追加执行`ue`,可以将变量更新到`init`级别的完整导入
    $exp>$PROFILE.AllUsersAllHosts
    
    ```

- 使用powershell初始化函数`init`会带来明显的shell变化

  - shell的提示符(prompt)会发生变化

  - shell中的环境变量会发生变换,引入了许多变量,提供命令行启动软件等别名配置

    

### 补充 变量$Profile说明

- ```powershell
  PS C:\repos\scripts> $PROFILE|select *
  
  AllUsersAllHosts       : C:\Program Files\PowerShell\7\profile.ps1
  AllUsersCurrentHost    : C:\Program Files\PowerShell\7\Microsoft.PowerShell_profile.ps1
  CurrentUserAllHosts    : C:\Users\cxxu\Documents\PowerShell\profile.ps1
  CurrentUserCurrentHost : C:\Users\cxxu\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
  Length                 : 67
  ```

- 该输出的左列表示可用的属性,右侧列表示属性的取值

- 通常使用属性会更加方便,而且会使得相关脚本更加易于维护和鲁棒.

## 响应性能说明

- powershell本身相比于其他shell的启动速度是明显慢的,如果载入过程中有过多的任务,会导致加速速度更慢
- 因此本模块集采用了灵活的设计,通过自动导入来降低载入速度的影响
- 默认情况下,配置好自动导入模块路径到`$PsModulePath`后,powershell的启动速度不会受到影响,只有当调用模块中的少数耗时函数或者环境导入函数,才会占用明显的时间,例如`init`函数,或者`p`函数
- 相同配置下,在windows10下的载入速度可能比win11要快

### 自动导入效果举例

#### 测试1

- ```
  PowerShell 7.4.5
  Setting basic environment in current shell...
  Loading personal and system profiles took 890ms.
  
  init Memory Info
  PS🌙[BAT:98%][MEM:50.61% (7.78/15.37)GB][11:05:41]
  # [cxxu@BEFEIXIAOXINLAP][<W:192.168.1.77>][~\scoop\apps\powershell\current]
  PS>
  
  ```

  运行环境:

  ```cmd
  PS> Get-SystemInfo
  ---------------------------
  系统核心配置信息:
  ---------------------------
  CPU 信息
  名称: AMD Ryzen 7 4800U with Radeon Graphics
  核心数量: 8
  逻辑处理器数量: 16
  最大主频: 1800 MHz
  
  内存信息
  制造商: Samsung
  容量: 8 GB
  速度: 3200 MHz
  制造商: Samsung
  容量: 8 GB
  速度: 3200 MHz
  
  磁盘信息
  型号: WDC PC SN730 SDBPNTY-512G-1101
  大小: 476.94 GB
  类型: Fixed hard disk media
  
  操作系统信息
  系统: Microsoft Windows 11 专业版
  版本: 10.0.22631
  架构: 64 位
  上次启动时间: 20240919075427.500000+480
  
  主板信息
  制造商: LENOVO
  型号: LNVNB161216
  序列号: PF24BC6V
  
  显卡信息
  名称: AMD Radeon(TM) Graphics
  显存: 0.5 GB
  驱动版本: 27.20.11028.10001
  ---------------------------
  ```


#### 测试2

```powershell
PowerShell 7.4.5
Setting basic environment in current shell...
Loading personal and system profiles took 512ms.

init Memory Info
PS🌙[BAT:78%][MEM:25.2% (8/31.7)GB][12:05:41]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.177>][~\scoop\apps\powershell\current]
PS>
```



```powershell
PS🌙[BAT:80%][MEM:20.46% (6.49/31.71)GB][11:27:39]
# [cxxu@CXXUCOLORFUL][<W:192.168.1.154>][C:\ProgramData\scoop\apps\powershell\current]
PS> Get-ComputerCoreHardwareInfo
---------------------------
系统核心配置信息:
---------------------------
CPU 信息
名称: 12th Gen Intel(R) Core(TM) i7-12700H
核心数量: 14
逻辑处理器数量: 20
最大主频: 2300 MHz

内存信息
内存总容量: 32 GB
制造商: Crucial Technology
容量: 16 GB
速度: 4800 MHz
制造商: Crucial Technology
容量: 16 GB
速度: 4800 MHz

磁盘信息
型号: SOLIDIGM SSDPFKNU010TZ
大小: 953.86 GB
类型: Fixed hard disk media

操作系统信息
系统: Microsoft Windows 11 Pro
版本: 10.0.26100
架构: 64-bit
上次启动时间: 20240919112358.500000+480

主板信息
制造商: COLORFUL
型号: P15 23
序列号: NKV250RNDWK000003K01154

显卡信息
名称: Microsoft Basic Display Adapter
显存: 0 GB
驱动版本: 10.0.26100.1
名称: Intel(R) Iris(R) Xe Graphics
显存: 2 GB
驱动版本: 32.0.101.5768
-----------------------
```



# 常用设置参考

## 模块刷新和重新导入👺

在 PowerShell 中，你可以通过重新导入单个模块、重新导入所有模块，或者在当前 PowerShell 会话中启动一个新实例来实现对模块的更新。以下是这几种方法的对比：

### 1. 单独重新导入某个模块
   - **使用场景**: 仅对特定模块进行了修改或更新。
   - **方法**: 使用 `Remove-Module` 和 `Import-Module` 或直接使用 `Import-Module -Force`。

     - 例如:

       ```powershell
       ipmo Test -Force #impo是import-module的缩写
       ```

       

   - **优点**:
     - **精确性**: 只重新加载被修改的模块，效率较高。
     - **性能**: 仅重新加载一个模块，消耗的资源较少。
     - **会话状态保留**: 保留当前 PowerShell 会话的所有状态和变量，不会影响其他已加载的模块。
   - **缺点**:
     - **局部更新**: 只更新一个模块，如果有多个模块依赖，需要手动更新所有相关模块。

### 2. 重新导入所有模块
   - **使用场景**: 你对多个模块进行了修改，或者希望确保所有模块都加载的是最新版本。
   - **方法**: 循环遍历当前已加载的模块，并使用 `Import-Module -Force` 重新导入它们。
   - **优点**:
     - **完整性**: 确保所有已加载模块都重新加载最新版本。
   - **缺点**:
     - **性能开销**: 重新加载所有模块可能需要更多的时间和资源，尤其是在模块较多或较大的情况下。
     - **复杂性**: 实现起来较复杂，尤其是在模块依赖关系复杂的情况下。

### 3. 在当前 PowerShell 会话中新建一个 PowerShell 实例
   - **使用场景**: 你希望彻底刷新当前环境中的所有模块或需要测试一个全新的环境。
   - **方法**: 在当前 PowerShell 中运行 `powershell` 启动一个新实例。
   - **优点**:
     - **环境重置**: 新实例中所有模块都会从头加载，确保所有模块都是最新版本，类似于在全新环境中运行脚本。
     - **无干扰**: 不会受到当前会话的状态、变量或依赖关系的影响。
   - **缺点**:
     - **性能开销**: 启动一个新的 PowerShell 实例可能需要额外的时间和资源。
     - **多层嵌套**: 可能导致多个 PowerShell 实例嵌套运行，增加复杂性。
     - **独立性**: 新实例与当前会话是独立的，因此当前会话中的状态、变量、函数等不会自动继承到新实例中。

### 总结对比

| 方法                 | 操作复杂度 | 性能开销 | 适用场景                     | 缺点                         |
| -------------------- | ---------- | -------- | ---------------------------- | ---------------------------- |
| 单独重新导入某个模块 | 低         | 低       | 只对单个模块进行了修改       | 只能更新单个模块             |
| 重新导入所有模块     | 中         | 中       | 多个模块需要更新             | 操作复杂，影响整个会话       |
| 新建 PowerShell 实例 | 低         | 高       | 需要彻底刷新环境或测试新环境 | 增加复杂性，当前状态不会继承 |

### 结论

- **单独重新导入模块** 更适合在你仅修改了一个模块且希望保持当前 PowerShell 会话状态的情况下使用。
- **重新导入所有模块** 是在多个模块有修改时的更彻底方案，但操作较为复杂。
- **新建 PowerShell 实例** 则适合需要完全独立的环境测试或彻底刷新所有模块的情况，代价是可能会消耗更多的资源。

## 禁用powershell更新检查

[about_Update_Notifications - PowerShell | Microsoft Learn](https://learn.microsoft.com/zh-cn/powershell/module/microsoft.powershell.core/about/about_update_notifications?view=powershell-7.4)

```powershell
[System.Environment]::SetEnvironmentVariable('powershell_updatecheck','off','user')
```

你也可以替换`off`为`LTS`不完全禁用更新但是降低更新频率(仅更新LTS长期支持版powershell)

执行完毕后关闭所有powershell和终端窗口,然后重新打开终端检查效果(不在通知你powershell版本过期要更新的通知)

# 补充

## 检查配置结果(可选)

### 列出本模块集中的模块

您可以通过以下命令来判断模块是否安装或设置成功,并且那些模块是可用的

```powershell
$path='*\ps\*' #可以修改为你的存放目录
Get-Module -ListAvailable|?{$_.ModuleBase -like $path}|select Name,ModuleBase
```

```powershell
PS> Get-Module -ListAvailable|?{$_.ModuleBase -like '*\ps\*'}|select Name,ModuleBase

Name                             ModuleBase
----                             ----------
Aliases                          C:\repos\scripts\PS\Aliases
backup                           C:\repos\scripts\PS\backup
Basic                            C:\repos\scripts\PS\Basic
Browser                          C:\repos\scripts\PS\Browser
Calendar                         C:\repos\scripts\PS\Calendar
colorSettings                    C:\repos\scripts\PS\colorSettings
CommentBasedHelpDocumentExamples C:\repos\scripts\PS\CommentBasedHelpDocumentExamples
ConstantStrings                  C:\repos\scripts\PS\ConstantStrings
ControlPanel                     C:\repos\scripts\PS\ControlPanel
....
....
...
```



### 检查PsModulePath环境变量

- 推荐还是关闭所有终端,然后**重启启动终端**,并检查 `PSModulePath`的值,执行以下语句:

  - `$env:PSModulePath -split ';'`

- 或者带有统计信息的版本:

- ```bash
  $res=$env:PSModulePath -split ";" ;echo $res,">>>>count:$($res.Count) `n"
  ```

- 例如

  ```bash
  PS[BAT:79%][MEM:35.42% (11.23/31.70)GB][17:32:53]
  # [C:\repos\scripts]
   $res=$env:PSModulePath -split ";" ;echo $res,">>>>count:$($res.Count) `n" |sls 'PS'
   
  C:\Users\cxxu\Documents\PowerShell\Modules
  C:\Program Files\PowerShell\Modules
  c:\program files\powershell\7\Modules
  C:\Users\cxxu\scoop\modules
  C:\repos\scripts\PS\
  C:\Program Files\WindowsPowerShell\Modules
  C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules
  >>>>count:7
  ```


- 如果是老用户,并且对环境变量做过备份,那么在新电脑或者重置过的电脑上导入备份过的环境变量即可(前提是本仓库或模块集路径没有发生改变,否则仍然要执行上述配置语句

### 模块配置效果检查👺

### 检查初始化函数

- 您可以在powershell输入 `init`来测试本模块是否可以正常加载:

- ```powershell
  PS C:\repos\scripts> init
  updating envs!
          VarSet1
          VarSet2
          VarStrings
          VarSet3
          VarAndroid
          VarFiles
  updating aliases!
          functions
          shortcuts
  loading psReadLines & keyHandler!(common)
  loading psReadLines & keyHandler!(advanced)
  ...
  ```



## 模块的基本使用

- 您现在可以直接调用模块中提供的函数

- 我们以`Info`模块为例,您不需要手动导入`Info`,即`Import-module Info`不需要手动执行,就可以调用其中的函数

- 查看`Info`模块中的函数

- ```powershell
  PS[BAT:98%][MEM:37.91% (12.02/31.70)GB][11:13:10]
  # [C:\repos\scripts]
  PS> gcm -Module Info
  
  CommandType     Name                                               Version    Source
  -----------     ----                                               -------    ------
  Function        Get-BIOSInfo                                       0.0        Info
  Function        Get-DiskDriversInfo                                0.0        Info
  Function        Get-LocalGroupOfUser                               0.0        Info
  Function        Get-MatherBoardInfo                                0.0        Info
  Function        Get-MaxMemoryCapacity                              0.0        Info
  Function        Get-MemoryChipInfo                                 0.0        Info
  Function        Get-MemoryUseRatio                                 0.0        Info
  Function        Get-MemoryUseInfoCached                           0.0        Info
  Function        Get-MemoryUseSummary                               0.0        Info
  Function        Get-ProcessPath                                    0.0        Info
  Function        Get-ScreenResolution                               0.0        Info
  Function        Get-SystemInfoBasic                                0.0        Info
  Function        Get-UserHostName                                   0.0        Info
  Function        ResourceMonitor                                    0.0        Info
  
  ```

- 例如执行其中的查看主板信息的函数`Get-BiosInfo`:

  - ```powershell
    
    PS C:\Users\cxxu\Desktop> gmo info
    
    PS C:\Users\cxxu\Desktop> get-biosinfo
    
    BIOS Version:              INSYDE Corp. 1.07.10COLO2, 2024/4/26
    ```

    

### 初始化powershell环境

- 如果模块路径设置正确,那么可以执行`init`进行初始化,这样您的powershell的环境会导入许多预置变量,它们大多是我自己使用的变量,比如各个软件的所在目录,您可以自己删除或添加或修改相关变量以及路径

- 尽管导入预置变量可以提供方便,但是对powershell的载入速度有很大的影响,甚至可能打到2秒以上

- 所以我们可以根据需要来决定是否总是自动导入所有预设的变量,模块`Init`中设置了一个`init`函数,调用它后可以载入自定义的环境变量(仅限powershell内使用,cmd无法访问)

- ```powershell
  PS C:\Users\cxxu\Desktop> init
  updating envs!
          VarSet1
          VarSet2
          VarStrings
          VarSet3
          VarAndroid
          VarFiles
  updating aliases!
          functions
          shortcuts
  loading psReadLines & keyHandler!(common)
  loading psReadLines & keyHandler!(advanced)
  
  2024/7/16 22:20:39
  
  PS[BAT:98%][MEM:37.70% (11.95/31.70)GB][12:00:57]
  # [~\Desktop]
  PS> gmo
  
  ModuleType Version    PreRelease Name                                ExportedCommands
  ---------- -------    ---------- ----                                ----------------
  Script     0.0                   Aliases                             Set-PwshAlias
  Script     0.0                   Basic                               {add_en_us_keyb…
  Binary     7.0.0.0               CimCmdlets                          {Get-CimAssocia…
  Script     0.0                   Conda                               {Enter-CondaEnv…
  Script     0.0                   info                                {Get-BIOSInfo, …
  Script     0.0                   Init                                {Set-PSReadLine…
  Manifest   7.0.0.0               Microsoft.PowerShell.Management     {Add-Content, C…
  Manifest   7.0.0.0               Microsoft.PowerShell.Utility        {Add-Member, Ad…
  Script     2.3.5                 PSReadLine                          {Get-PSReadLine…
  Script     0.0                   Pwsh                                {Enable-PoshGit…
  Script     0.0                   PwshVar                             Update-PwshVars
  Script     0.0                   TaskSchdPwsh                        {Get-LastUpdate…
  
  ```
  
- 您可以创建一个主powershell窗口,这个窗口里手动执行`init`,然后主要操作在这个窗口里进行

- 其他窗口为了提高加载速度,就不需要自动执行`init`来提高加载速度,但是模块中的函数还是可以使用的,只是变量不能够访问了



## 安装第三方模块🎈

- 如果本地缺少一些模块,则执行会报错(您需要**注意下载这些模块**,或者注释掉相应启用代码而不安装)
- `Set-ExecutionPolicy -Scope CurrentUser bypass`

#### Terminal-icons

- [devblackops/Terminal-Icons: A PowerShell module to show file and folder icons in the terminal (github.com)](https://github.com/devblackops/Terminal-Icons)

- 安装命令

  - `Install-Module -Name Terminal-Icons -Repository PSGallery`

    ```
    PS C:\Users\cxxu\Desktop> Install-Module -Name Terminal-Icons -Repository PSGallery
    
    Untrusted repository
    You are installing the modules from an untrusted repository. If you trust this repository, change its
    InstallationPolicy value by running the Set-PSRepository cmdlet. Are you sure you want to install the modules from
    'PSGallery'?
    [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "N"): A
    PS C:\Users\cxxu\Desktop>
    ```

#### posh模块

- [Home | Oh My Posh](https://ohmyposh.dev/)
- 例如,对于windows系统,有多种方式安装

#### posh-git模块

- [GitHub - dahlbyk/posh-git: A PowerShell environment for Git](https://github.com/dahlbyk/posh-git?tab=readme-ov-file#installation)

- ...

### 配置需要开机自启的软件

- ```powershell
  $sttartup_user="$env:AppData\Microsoft\windows\Start Menu\programs\Startup"
  #target值修改为本项目的PS下的startup.lnk的路径
  $target="C:\repos\scripts\PS\Startup\startup.lnk"
  
  -HardLink -Path $startup_user -target  C:\repos\scripts\PS\Startup\startup.lnk
  ```

  



## 加载和执行顺序👺

- **模块的扫描**优先于**配置文件**(`$PROFILE`)的加载和执行.

## 报错排查

- 有时编辑(修改)模块失误会导致导入模块的过程中出现一些报错信息
  - 例如:函数的参数列表末尾有多余的逗号(通常发生在修改函数原型的时候)
  - 字符串没有闭合
- 技巧:
  - 使用vscode配合powershell extension来检查一些语法错误(终端选项卡附近的问题选项卡 `problem`)
  - 在配置 `importer_pwsh`模块注释掉可能出问题的模块来排除是哪个模块除了问题
  - 直接运行可能导致问题的模块,如果没有报错,说明该模块没有语法错误(但仍然可能有逻辑错误)

## 开机自启动配置👺



- ```powershell
  Deploy-AutoTasks
  ```

  

- 备用方式:`hard -path startup.ps1 -Target C:\repos\scripts\PS\startup\startup.ps1`

### 同名命令竞争

- 有这么一种可能的场景

  - 假设我们设置了一个`startup.ps1`脚本文件放置到`shell:startup`目录下,希望它能够在shell处于任意工作目录下都能

  - 并且假设这个脚本内调用了一个`startup`命令

- 问题在于这里的startup可能被哪些东西响应,或者哪一个会优先抢占响应,以及如何可能发生歧义的避免响应
  - 比如我要设置文件共享服务`chfs`开机自启,我创建了一个chfs家目录(记为`$chfs_home`中创建了`startup.vbs`,并且`$chfs_home`添加到了`Path`环境变量中)
  - 也就是说,命令行窗口内可以直接访问到chfs家目录中的可执行文件,包括`chfs.exe`,以及我为其配置的`startup.vbs`这个启动脚本文件
  - 推荐的做法是
    - 将启动的脚本修改的更加具体一些,比如这个脚本文件仅仅负责启动`chfs`,那么就取名为`startup_chfs.vbs`
    - 或者你觉得`startup.vbs`本身就在`chfs`家目录下,不需要再次强调脚本名字,那么可以在脚本内设置一些提示语句,这样万一出现不符合预期的`startup`响应,也可以发现问题
    - 对于powershell中的函数,对其命名尽量符合`Verb-Noun`的规范,比如`startup`函数就不要仅仅命名为`startup`,可以改为`Start-StartupTasks`,取别名为`StartupPS`

#### 命令冲突检查

例如我的环境中有多个可能响应`startup`命令调用的命令或脚本

我们可以用`gcm startup`来查询哪一个会从竞争中胜出

```powershell
PS [C:\Users\cxxu\Desktop]> gcm startup|fl

Name            : startup.vbs
CommandType     : Application
Definition      : C:\exes\chfs\startup.vbs
Extension       : .vbs
Path            : C:\exes\chfs\startup.vbs
FileVersionInfo : File:             C:\exes\chfs\startup.vbs
```

查询所有相关的命令:使用通配符

```powershell
PS [C:\Users\cxxu\Desktop]> gcm startup*

CommandType     Name                                               Version    Source
-----------     ----                                               -------    ------
Function        startup                                            0.0        Startup
Function        startup_register                                   0.0        Basic
Application     startup.vbs                                        0.0.0.0    C:\exe…

```

## powershell中的命令类型

```powershell
PS> gcm -CommandType Alias
Alias           Application     Configuration   Filter          Script
All             Cmdlet          ExternalScript  Function
```

在 PowerShell 中，`CommandType` 用于指定命令的类型。PowerShell 支持多种命令类型，主要包括以下几种：

1. **Alias**（别名）：表示 PowerShell 中的命令别名。
2. **Function**（函数）：表示 PowerShell 脚本中定义的函数。
3. **Cmdlet**：表示由 PowerShell 提供的命令，通常是 .NET 类。
4. **Script**：表示脚本文件 (.ps1)。
5. **Application**：表示外部可执行程序。  外部可执行程序(比如`.exe`文件,`.vbs`文件)
6. **Filter**：表示过滤器函数。
7. **Configuration**：表示 DSC（Desired State Configuration）脚本。
8. **Workflow**：表示工作流脚本。

下面是一个 PowerShell 示例，展示如何使用 `Get-Command` 及 `CommandType` 获取不同类型的命令：

这些 `CommandType` 提供了在 PowerShell 中更细化和有针对性的命令管理和调用方式。

### Path@PathExt环境变量和Application类型的命令

- [关于环境变量|PathExt|Path - PowerShell | Microsoft Learn](https://learn.microsoft.com/zh-cn/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.4#path-information)

在命令行中,部分path路径中的文件后缀若在`PathExt`环境变量中有定义,那么可以不用打出扩展名,就可以打开或者执行;

`PathExt`中的后缀不是一成不变的,安装了别的软件后会往里面添加值

`Path`,`PathExt`为我们提供了一定的便利,但也潜在地会引发某些命令行内调用冲突

PathExt和Path结合后的效果可以表现为:

- 假设路径`C:\exes`被添加到了`Path`路径中,意味着`exes`目录中的可执行文件(后缀扩展名存在于`PathExt`环境变量中)就能在命令行中直接访问,而不需要指定具体的可执行文件路径
- Path中的可执行文件只有在命令行的开头才会被系统搜索到,在作为参数时仍然需要指定具体的路径

```cmd
PS> $env:PATHEXT
.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC;.PY;.PYW;.CPL
```



## 初次运行执行的配置

* ```powershell
  #信任PSGallery仓库中的模块
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
  
  ```

## powershell模块集的兼容性👺

早期本模块集合对powershell5提供基本的支持,但是随着版本的迭代,对windows自带的windows powershell(v5)的支持变得非常有限,几乎不可用;

目前暂无对于powershell v5的适配计划

因为windows powershell 自带的版本是v5或v5.1,对于许多语言特性是缺失的

- 例如无法使用三元运算符,如果模块中的函数使用了三元运算,那么会导致该函数无法使用,进一步导致这个模块无法被windows powershell所识别!
- 如果为了考虑兼容性,模块应该尽量避免使用三元运算符,而使用if/else来代替

- 此外,windows powershell 对于代码排版以及**编码**和powershell 7 之后的版本也存在不同(windows powershell可能会因为编码的问题将注释中的字符错误识别为要执行的命令,导致执行失败)


## FAQ

### 高级权限或特殊用户身份运行powershell时使用模块

- 部分情况下,比如使用nsudo启动的powershell或者system用户身份(比如计划任务指定system用户来指定启动任务时,常规的powershell模块自动导入将会不可用)
- 这种情况下,您可以使用`gmo -listavailable`来查看
- 要解决此问题,我们有变通的方法:`$env:psModulePath+=";C:\repos\scripts\ps"`这个方式可以临时将指定目录下的powershell模块(集)导入到该powershell环境中



### powershell变量作用域

- [关于作用域 - PowerShell | Microsoft Learn](https://learn.microsoft.com/zh-cn/powershell/module/microsoft.powershell.core/about/about_scopes)