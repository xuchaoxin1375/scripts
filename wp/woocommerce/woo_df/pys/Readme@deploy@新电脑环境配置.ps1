
# 新电脑环境部署

# 下载火车头采集器: 
## 官网
https://locoy.com/download
# 10.28版本下载链接
https://www.locoy.com/LocoySpider_V10.28_Build20250507.zip

# 配置powershell环境🎈
#方案1: 手动安装powershell和git软件,然后执行以下语句快速部署基本powershell(pwsh)
git clone https://gitee.com/xuchaoxin1375/scripts.git C:/repos/scripts #
$p="C:\repos\scripts\PS" #这里修改为您下载的模块所在目录,这里的取值作为示范
$env:PSModulePath=";$p"
Add-EnvVar -EnvVar PsModulePath -NewValue $p -Verbose #这里$p上上面定义的
Add-CxxuPsModuleToProfile
pwsh #启动一个新pwsh会话查看效果


#方案2: 一键安装方案(不稳定,容易失败)
Invoke-RestMethod 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1' | Invoke-Expression
Add-CxxuPsModuleToProfile

<# # 浏览器插件(适用于Edge和Chrome浏览器):浏览器扩展程序:
下载来源:
edge: https://microsoftedge.microsoft.com/addons/Microsoft-Edge-Extensions-Home
chrome: https://microsoftedge.microsoft.com/addons/Microsoft-Edge-Extensions-Home

adguard (广告过滤插件)
shopify hunter (shopify 站点识别和产品数量统计插件)
proxyify (蝙蝠代理插件)
沉浸式翻译
划词翻译

 #>
# 配置scoop for cn user🎈
Deploy-ScoopForCNUser -InstallBasicSoftwares -UseGiteeForkAndBucket -InstallForAdmin
#让scoop安装的软件可以在开始菜单中搜索到并且命令行中可以通过名字启动软件(尤其是gui软件)
Deploy-ScoopStartMenuAppsStarter 
# 安装额外的scoop bucket (如果失败,重新运行,并且在选择镜像链接的时候换一个(而不是默认回车))
Add-ScoopBuckets 
# 利用scoop安装常用软件
## 安装windows terminal
scoop install windows-terminal 
scoop install snipaste
scoop install ditto 
# scoop install 7zip-zstd #(直接安装可能报错)
scoop install spc/7zip-zstd #依赖于额外的scoop bucket(spc)
# 压缩和打包文件
scoop install zstd
scoop install lz4
# 代理软件
scoop install clash-verge-rev # 小猫咪飞机场代理软件
# 资源监控软件
scoop install trafficmonitor #状态栏资源和流量监控(建议直接从exes分享,而不是scoop安装部署插件比较麻烦)
scoop install liberationMono-NF -g # 推荐的字体，可以让终端显示更多的符号

# 安装完vscode,可选的配置右键vscode打开文件夹
Invoke-RestMethod https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Tools/Tools.psm1 | Invoke-Expression ; 
Set-OpenWithVscode
# 可选部分:(可能会失败)

# 设置winget
winget source remove winget  #移除默认源（太慢）
winget source add winget https://mirrors.ustc.edu.cn/winget-source #添加国内科大源
winget source list


# 安装专业的卸载器
winget install HiBitSoftware.HiBitUninstaller --scope machine

