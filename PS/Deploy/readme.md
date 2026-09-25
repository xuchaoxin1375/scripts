[toc]

## 说明

- 此模块内包含了关于部署powershell7模块的脚本文件等内容
  - 关于快速部署此powershell7模块集(及其所在仓库),这里创建的专用脚本文件为 `Deploy-CxxuPsModules.ps1`
  - 这里着重介绍如何快速部署此项目

- 虽然模块是为powershell7(pwsh)编写的,但是一键部署脚本是支持在windows powershell(v5)上运行和启动的,也就是说,部署脚本允许你后安装pwsh

## 部署本仓库的方法

- 拷贝下面提供的代码(两个版本选择其中一个,优先使用第一个),然后粘贴到powershell7窗口中回车运行

### 简短版👺

- 尝试执行默认的安装行为,如果失败
  - 很可能是没有安装Git,这时候需要手动下载仓库文件包
  - 或者尝试手动下载仓库包，调用 `Deploy-CxxuPsModule`函数,并使用合适的参数,尝试离线安装

```powershell
$mirror = if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' }
$url = "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1"
$scripts = Invoke-RestMethod $url
$scripts | Invoke-Expression
# Deploy-CxxuPsModules
```

### 一行搞定👺

下面虽然提供了更短的方案,可以一行搞定,但是为了便于审查,使用上面的多行版本会更推荐,比如方便我们引用`$url`以及`$scripts`进行其他操作

```powershell
Invoke-Expression (Invoke-RestMethod 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1')

```

或者

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex
```

> 默认镜像 `gh-proxy.com` 若不可用,先换一个可用镜像(跑 `Get-AvailableGithubMirrors` 测速,或见
> `PS/TestLinks/TestLinks.psm1` 头部实测列表),再把上面链接中的镜像前缀替换掉即可;
> gitee 只留兼容(`https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1`),
> 但 `irm|iex` 常被拦截,不再推荐.

### 轻量部署（仅 Windows PowerShell 5.1，免 git 免 pwsh）

新机器只有 v5 时，在 `powershell.exe` 里存下脚本再加 `-Light` 跑：无 git 不提示安装、直走离线包下载（codeload + 中央镜像静默，不弹窗选源），落 `PSModulePath`（追加不覆盖），结尾不装 pwsh、改写 5.1 专属 profile，重开 `powershell.exe` 跑 `init` 即用（B 档可用范围与禁区见 `PS/docs/Feature-Guide.md §13`）。

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1' > ~/dcp.ps1
~/dcp.ps1 -Light
```

### 开发模式（用本地最新代码，不拉远程）

未推送到远程时，用本地代码测部署效果：仓库内直接运行一键脚本并加 `-Dev`（仓库根从脚本位置自动推导，marker 文件不存在则警告并回退远端；4 个一键脚本通用：`Deploy-CxxuPsModules`、`Deploy-GitForWindows`、`Deploy-Pwsh7Portable`、`Register-GithubHostsAutoUpdater`）。

```powershell
C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Dev # 可叠 -Light -WhatIf（注意脚本尾部有真实调用）
```



### 备用方案版

如果您遇到报错或者失败,则重新粘贴执行,并且切换方案码(code)(下面内置了3个方案)

```powershell
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force
$mirror = if ($env:PsGithubMirror) { ([string]$env:PsGithubMirror).TrimEnd('/') } else { 'https://gh-proxy.com' } #github加速镜像,不可用就换一个(见 PS/TestLinks/TestLinks.psm1 头部实测列表)
#默认使用 github + 加速镜像;gitee 只留兼容
$url1 = "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1"
$url2 = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'
#国外Github平台直连(不走镜像,不一定连得上)
$url3 = 'https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1'
$urls = @($url1, $url2,$url3)
$code = Read-Host "Enter the Deploy Scheme code [0..$($urls.Count-1)](default:1)"
$code = $code -as [int]
if(!$code){
	$code=1 #默认选择第一个链接(数组索引0)
}

$scripts = Invoke-RestMethod $urls[$code]

$scripts | Invoke-Expression

# Deploy-CxxuPsModules 

```

### 补充说明

- Notes:如果上述代码执行顺利,部署时间5秒钟左右即可完成
- 如果不顺利,比如报错,那么尝试调整 `Deploy-CxxuPsModules`函数的调用参数,具体参数参考函数用法文档

  - > 可选的,在变量 `$scripts`保存了部署脚本的内容,您可以粘贴到文本编辑器或代码编辑器中查看和调整
    >

## 默认方案执行失败解决方案

- 在失败的情况下,您有两种方案可以提高成功率(通常都是百分百成功,甚至不需要你的计算机直接连接互联网):

  1. 下载并安装Git软件(如果是便携版,需要手动配置环境变量Path),此软件可以从联想应用商店等应用市场下载,安装完成git后关闭所有powershell终端窗口,打开新powershell7窗口,然后重新尝上述脚本(这种方案最简单,代码也不用改)
  2. 另一种方案不依赖于Git,你需要到项目的仓库(gitee/github)中任选一个在线网站上下载项目的压缩包(体积很小),然后复制下载到的包的路径,使用适合的参数调用 `Deploy-CxxuPsModules`重新安装,下面的演示环节演示了此方式的部署过程(注意,gitee 等国内平台下载仓库压缩包可能需要登录;github 免登录但直连不一定通,不通就换加速镜像前缀后下载,例如 `https://gh-proxy.com/https://github.com/xuchaoxin1375/scripts/archive/refs/heads/main.zip`)
- 无参数直接调用部署函数版本要求你已经安装git,以下版本尝试从github下载本仓库包(版本可能滞后),如果你不想安装git可以尝试指定 `Mode`选择离线安装以下方案

  - Gitee下载源代码也可以,但是需要登陆才能获取下载链接
  - Github虽然慢,也可能连不上,但是仓库很小,能连上的话不会下载太久

## 操作演示(分步骤离线安装)

```powershell
PS C:\ProgramData\scoop\apps\powershell\current> cd
PS C:\Users\cxxu> $mirror = 'https://gh-proxy.com'
>> $url = "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1"
>> $scripts = Invoke-RestMethod $url
>> $scripts | Invoke-Expression
>> #尝试执行默认的安装行为,如果失败(很可能是没有安装Git,这时候需要手动下载仓库文件包),尝试手动调用Deploy-CxxuPsModule函数,并使用合适的参数,尝试离线安装
PS C:\Users\cxxu> Deploy-CxxuPsModules^C#假设这一步报错或者遇到失败(如果是目录名冲突,那么您可在调用`Deploy-CxxuPsModules`时使用路径RepoPath参数新指定取值,或者使用Force选项)
#如果是报红色错误,可以开始强力方案(1:下载git软件 2:下载项目压缩包离线安装)

#下面使用强力方案2来安装离线包(注意要在同一个shell窗口上下文下继续执行执行)
PS C:\Users\cxxu> deploy-cxxuPsModules -PackagePath C:\Users\cxxu\Desktop\scripts-main.zip -RepoPath C:\tmp\CxxuPS -Verbose

Key         Value
---         -----
PackagePath C:\Users\cxxu\Desktop\scripts-main.zip
RepoPath    C:\tmp\CxxuPS
Verbose     True


RepoPath      NewPsPath        Source PackagePath                            Mode    Force
--------      ---------        ------ -----------                            ----    -----
C:\tmp\CxxuPS C:\tmp\CxxuPS\PS gitee  C:\Users\cxxu\Desktop\scripts-main.zip Default False

Mode:Expanding local pacakge:[C:\Users\cxxu\Desktop\scripts-main.zip]
C:\tmp\CxxuPS\scripts-main C:\tmp\CxxuPS/scripts
VERBOSE: Performing the operation "Remove Directory" on target "C:\tmp\CxxuPS\scripts-main".

Name         Value
----         -----
PsModulePath C:\tmp\CxxuPS\PS
             C:\Users\cxxu\scoop\modules



Name             Value
----             -----
CxxuPsModulePath C:\tmp\CxxuPS\PS


```

- 这个例子中,我从gitee仓库下载了仓库压缩包,存放的位置为 `C:\Users\cxxu\Desktop\scripts-main.zip`,并且指定了将项目解压到 `C:\tmp\CxxuPS`

## 使用语法查看命令

```powershell
help Deploy-CxxuPsModules -full
```

## 部署临时使用CxxuPsModule Deploy模块

Deploy模块含有大量实用函数(基本上其他单独的deploy-xxx都能在Deploy模块中找到),但是内容较多,有可能被误杀;

建议使用powershell7来执行,powershell v5可能会不兼容或部分函数不兼容

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy.psm1'|iex

```

然后可以执行Deploy中存在的命令,例如Deploy-SmbSharing

```powershell
Deploy-SmbSharing

```

### 部署SmbSharing共享文件夹

部署smbsharing

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy.psm1'|iex
gcm Deploy-SmbSharing -syntax
# help Deploy-SmbSharing #执行这一行查看使用帮助,默认不执行直接部署配置
Deploy-SmbSharing -DisableSmbUserLogonLocally -Verbose -confirm:$false #使用$true会逐步向你询问确认

```

重置smbsharing:清理默认smb专用用户名和共享名称

```powershell
Remove-LocalUser smb
Remove-SmbShare share

```

### 部署ScoopForCnUser

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy.psm1'|iex
gcm Deploy-ScoopForCnUser -syntax
Deploy-ScoopForCNUser -UseGiteeForkAndBucket -InstallBasicSoftwares # -InstallForAdmin
Add-ScoopBuckets -Silent

```

### 查看可用的github_mirror加速镜像站

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy.psm1'|iex
# get functions or commands about mirror operations!
gcm *mirror* 
#check commands usage (syntax)
gcm Get-AvailableGithubMirrors -Syntax #use this is enough in general cases
gcm Get-SelectedMirror -Syntax
#choose a mirror which is available

$github_mirror = Get-SelectedMirror #choose default mirror
Write-Verbose $github_mirror -Verbose #check what mirror is chosen

```



## 部署powershell7的方法

- 安装powershell7的方式有很多,这里提供一个一键安装的方案,但是不保证有效
  
- 以下是部署脚本

  ```powershell
  irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-Pwsh7Portable.ps1'|iex
  ```

  - 安装过程中会提示你是否要删除安装包,根据需要选择是否删除即可
  - 不一定能够一次性成功,如果失败,您可以多尝试几次,或者检查该脚本的输出信息中的下载连接是否可用(比如粘贴到浏览器中手动尝试下载,如果可以下载,那么重试是有意义的,否则需要从别的地方下载便携版安装包放置到指定位置($env:temp)目录,这个目录可以通过poweshell打开或者资源管理器中地址栏输入`%temp%`打开,将包放置到里面,然后再次运行脚本进行部署)
  - 会自动为你配置环境变量(用户级别的Path),便于你后续直接从任意位置通过`pwsh`来启动powershell7

## 部署Git for windows🎈

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-GitForWindows.ps1'|iex
Deploy-GitForWindows -IgnoreCache

```

