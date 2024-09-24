[toc]

## 说明

- 此模块内包含了其他关于部署powershell模块的脚本文件等内容
- 关于快速部署此模块集(及其所在仓库),这里创建的专用脚本文件为 `Deploy-CxxuPsModules.ps1`

### 用户使用方法

- 运行一下命令行进行部署

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

  ```

### 精简版

```powershell
$url = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'
$scripts = Invoke-RestMethod $url
$scripts | Invoke-Expression
#尝试执行默认的安装行为,如果失败(很可能是没有安装Git,这时候需要手动下载仓库文件包),尝试手动调用Deploy-CxxuPsModule函数,并使用合适的参数,尝试离线安装
Install-CxxuPsModules 


```

或者写在一行里面

```powershell
$url = 'https://raw.gitcode.com/xuchaoxin1375/Scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1';$scripts = Invoke-RestMethod $url;$scripts | Invoke-Expression

```

### 使用语法查看命令

```powershell
help Deploy-CxxuPsModules -full
```

- 如果离线方案下载不下来,那么考虑git方案下载

  - [联想应用商店 (lenovo.com)](https://lestore.lenovo.com/search?k=git),在此网站可以快速下载git (for windows);然后重新执行此脚本进行安装
