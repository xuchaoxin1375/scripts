[toc]

## 说明

- 此模块内包含了关于部署powershell7模块的脚本文件等内容
- 关于快速部署此powershell7模块集(及其所在仓库),这里创建的专用脚本文件为 `Deploy-CxxuPsModules.ps1`

- 这里着重介绍如何快速部署此项目

## 部署方法

- 拷贝下面提供的代码(两个版本选择其中一个,优先使用第一个),然后粘贴到powershell7窗口中回车运行

### 简短版👺

```powershell
$url = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'
$scripts = Invoke-RestMethod $url
$scripts | Invoke-Expression
#尝试执行默认的安装行为,如果失败(很可能是没有安装Git,这时候需要手动下载仓库文件包),尝试手动调用Deploy-CxxuPsModule函数,并使用合适的参数,尝试离线安装
Install-CxxuPsModules 


```



### 备用方案版

如果您遇到报错或者失败,则重新粘贴执行,并且切换方案码(code)(下面内置了3个方案)

```powershell
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force
$mirror = 'https://github.moeyy.xyz' #如果采用github方案，那么推荐使用加速镜像来下载脚本文件，如果此镜像不可用，请自行搜搜可用镜像，然后替换此值即可
#默认使用国内平台 gitee加速
$url1 = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'
$url2= 'https://raw.gitcode.com/xuchaoxin1375/Scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'
#国外Github平台
$url3 = "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1"
$urls = @($url1, $url2,$url3)
$code = Read-Host "Enter the Deploy Scheme code [0..$($urls.Count-1)](default:1)"
$code = $code -as [int]
if(!$code){
	$code=1 #默认选择第一个链接(数组索引0)
}

$scripts = Invoke-RestMethod $urls[$code]

$scripts | Invoke-Expression

Install-CxxuPsModules 

```



### 补充说明

- Notes:如果上述代码执行顺利,部署时间5秒钟左右即可完成

- 如果不顺利,比如报错,那么尝试调整`Deploy-CxxuPsModules`函数的调用参数,具体参数参考函数用法文档

  - > 可选的,在变量`$scripts`保存了部署脚本的内容,您可以粘贴到文本编辑器或代码编辑器中查看和调整


## 默认方案执行失败解决方案

- 在失败的情况下,您有两种方案可以提高成功率(通常都是百分百成功,甚至不需要你的计算机直接连接互联网):
  1. 下载并安装Git软件(如果是便携版,需要手动配置环境变量Path),此软件可以从联想应用商店等应用市场下载,安装完成git后关闭所有powershell终端窗口,打开新powershell7窗口,然后重新尝上述脚本(这种方案最简单,代码也不用改)
  2. 另一种方案不依赖于Git,你需要到项目的仓库(gitee/gitcode/github)中人一一个在线网站上下载项目的压缩包(体积很小),然后复制下载到的包的路径,使用适合的参数调用`Deploy-CxxuPsModules`重新安装,下面的演示环节演示了此方式的部署过程(注意,gitee,gitcode等平台下载项目的压缩包需要你登录,github可以不登录,但是不一定下的下来,因此我推荐登录国内平台然后顺利下载)

- 无参数直接调用部署函数版本要求你已经安装git,以下版本尝试从github下载本仓库包(版本可能滞后),如果你不想安装git可以尝试指定`Mode`选择离线安装以下方案
  - Gitee下载源代码也可以,但是需要登陆才能获取下载链接
  - Github虽然慢,也可能连不上,但是仓库很小,能连上的话不会下载太久



## 操作演示(分步骤离线安装)

```powershell
PS C:\ProgramData\scoop\apps\powershell\current> cd
PS C:\Users\cxxu> $url = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'
>> $scripts = Invoke-RestMethod $url
>> $scripts | Invoke-Expression
>> #尝试执行默认的安装行为,如果失败(很可能是没有安装Git,这时候需要手动下载仓库文件包),尝试手动调用Deploy-CxxuPsModule函数,并使用合适的参数,尝试离线安装
PS C:\Users\cxxu> Install-CxxuPsModules^C#假设这一步报错或者遇到失败(如果是目录名冲突,那么您可在调用`Deploy-CxxuPsModules`时使用路径RepoPath参数新指定取值,或者使用Force选项)
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

- 这个例子中,我从gitee仓库下载了仓库压缩包,存放的位置为`C:\Users\cxxu\Desktop\scripts-main.zip`,并且指定了将项目解压到`C:\tmp\CxxuPS`



## 使用语法查看命令

```powershell
help Deploy-CxxuPsModules -full
```

- 如果离线方案下载不下来,那么考虑git方案下载

  - [联想应用商店 (lenovo.com)](https://lestore.lenovo.com/search?k=git),在此网站可以快速下载git (for windows);然后重新执行此脚本进行安装
