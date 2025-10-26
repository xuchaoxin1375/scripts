[toc]



## abstract

windows系统上,小皮工具箱提供了一个可以快捷切换开发环境(比如服务器和数据库软件版本),使得用户可以通过GUI的方式管理和配合软件

不过,图形界面虽然对于手动操作方便,但是对于频繁移除和创建项目或者需要大批量创建试验项目则不够方便,尤其是小皮对于批量网站管理的图形界面支持力度不够,相对简陋,灵活性欠佳

这种情况下,了解一下小皮工具箱内部的工作原理,可以为我们实现批量操作和自动化提供思路

> 本文部分内容仅为推测,可能不是很准确,仅供参考

## 小皮的进程和服务

```powershell
#⚡️[Administrator@CXXUDESK][~\Desktop][12:25:48] PS >
 ps *phpStudy*|select name,CommandLine

Name           CommandLine
----           -----------
phpStudyServer C:\phpstudy_pro\COM\phpStudyServer.exe  -install
phpStudyServer
phpstudy_pro   "C:\phpstudy_pro\COM\phpstudy_pro.exe"

# 使用命令  ps *php*|select *|ft #查看更多
ps *php*|select *|ft
```

杀死小皮相关进程

```powershell
ps *phpstudy*|kill -Verbose -Force -ErrorAction SilentlyContinue
```



### 服务

phpstudysrv服务可能和小皮开机自启有关

但是工具箱中的开机自启设置有时候会失灵,可靠性不佳

```powershell
#⚡️[Administrator@CXXUDESK][~\Desktop][10:56:08] PS >
 gsv phpstudy*

Status   Name               DisplayName
------   ----               -----------
Stopped  phpStudySrv        phpstudy服务

#⚡️[Administrator@CXXUDESK][~\Desktop][10:58:17] PS >
 gsv phpstudy*|select *

UserName            : LocalSystem
Description         : phpstudy进程服务
DelayedAutoStart    : False
BinaryPathName      : C:\phpstudy_pro\COM\phpStudyServer.exe -SCM
StartupType         : Automatic
Name                : phpStudySrv
RequiredServices    : {}
CanPauseAndContinue : False
CanShutdown         : False
CanStop             : False
DisplayName         : phpstudy服务
DependentServices   : {}
MachineName         : .
ServiceName         : phpStudySrv
ServicesDependedOn  : {}
StartType           : Automatic
ServiceHandle       : Microsoft.Win32.SafeHandles.SafeServiceHandle
Status              : Stopped
ServiceType         : Win32OwnProcess
Site                :
Container           :
```

## phpstudy_pro\COM目录下的重点文件

### xp.ini

小皮的服务类软件(apache,nginx,php-cgi)多版本管理记录在里面,例如,我安装过的几个php版本,以及apache和nginx相关信息

```ini
#⚡️[Administrator@CXXUDESK][C:\phpstudy_pro\COM][11:15:58] PS >
 cat .\xp.ini
[General]
Apache2.4.39=C:/phpstudy_pro/Extensions/Apache2.4.39/bin/httpd.exe|
xp.cn_cgi9003=C:/phpstudy_pro/COM/xp.cn_cgi.exe|../Extensions/php/php5.6.9nts/php-cgi.exe 9003 1+16
xp.cn_cgi9002=C:/phpstudy_pro/COM/xp.cn_cgi.exe|../Extensions/php/php7.4.3nts/php-cgi.exe 9002 1+16
xp.cn_cgi9001=C:/phpstudy_pro/COM/xp.cn_cgi.exe|../Extensions/php/php8.0.2nts/php-cgi.exe 9001 1+16
Nginx1.25.2=C:/phpstudy_pro/Extensions/Nginx1.25.2/nginx.exe|
xp.cn_cgi9005=C:/phpstudy_pro/COM/xp.cn_cgi.exe|../Extensions/php/php8.2.9nts.bak/php-cgi.exe 9005 1+16
```

