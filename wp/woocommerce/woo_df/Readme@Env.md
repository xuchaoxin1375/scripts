[toc]

## 配置通用的环境变量



### python依赖包安装

查看woo_df目录下的requirements.txt,根据该文件的要求进行安装依赖

在这之前,建议将pip源更换为国内加速源,比如清华源,执行以下命令即可配置(powershell或者cmd/bash都可以)

```bash
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
```

安装依赖的命令为:

```bash
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple #修改pip源
$env:PYTHONIOENCODING="utf-8" #在powershell中配置临时变量,解决gbk编码问题(包含中文的情况)
pip install -r "$woo_df\requirements.txt" #注意修改requirements.txt的路径为你自己的实际路径(如果遇到编码报错(gbk)则注释或移除对应的中文)🎈
```

- 注意:具体的requirements.txt路径根据自己的实际情况指定,尤其是当前工作目录会影响到指定目录值


- 或者可以使用拖转文件的方式或指定绝对路径的方式来指定requirements.txt文件都可以

### magic库的检查(可选)

- 上面的安装依赖操作可能无法一次性顺利安装magic库,可以考虑使用其他库代替或者关闭此功能(需要调整代码)

```python
#⚡️[Administrator@CXXUDESK][C:\Share\df\wp_sites\wp_migration][11:49:13][UP:17.08Days]
PS> ipython
Python 3.12.7 | packaged by Anaconda, Inc. | (main, Oct  4 2024, 13:17:27) [MSC v.1929 64 bit (AMD64)]
Type 'copyright', 'credits' or 'license' for more information
IPython 8.31.0 -- An enhanced Interactive Python. Type '?' for help.

In [1]: import magic

In [2]: magic.libmagic
Out[2]: <CDLL 'C:\ProgramData\scoop\apps\miniconda3\current\Lib\site-packages\magic\libmagic\libmagic.dll', handle 7ffa0b140000 at 0x27dff8c99d0>

In [3]:
```



### 适用于windows系统的环境变量配置

下面采用命令行`setx`的方式配置,用户也可以选择使用系统的图形界面配置环境变量

例如,配置采集器的数据存储路径(建议使用powershell运行)

> ###喜欢使用D盘的注意按需更改""中的值(强烈建议不要设置D盘,diskmgmt删除该盘,然后扩展C盘,尤其总共不足1TB的情况下便于管理)

```cmd
# 创建常用软件目录
New-Item -ItemType Directory -Path C:/exes

# 基础环境变量配置
setx PYTHONPATH2 @"
C:\repos\scripts\wp\woocommerce\woo_df;
C:\repos\scripts\wp\woocommerce\woo_df\pys\bt_api;
C:\repos\scripts\wp\woocommerce\woo_df\pys\cf_api;
C:\repos\scripts\wp\woocommerce\woo_df\pys\spaceship_api;
"@
setx PYS C:\repos\scripts\wp\woocommerce\woo_df\pys
setx WOO_DF C:\repos\scripts\wp\woocommerce\woo_df
setx PsModulePath C:/repos/scripts/PS
setx exes C:/exes


# 辅助环境变量配置(D盘用户注意按需更改),还有软件版本也要注意(日后如果更新软件,或其他导致目录变更的情况,要注意修改环境变量(使用gui方案))
setx LOCOY_SPIDER_DATA "C:\火车采集器V10.27\Data" #🎈
setx phpstudy_extensions "C:\phpstudy_pro\extensions"
setx nginx_conf_dir "C:\phpstudy_pro\Extensions\Nginx1.25.2\conf\vhosts"
# setx nginx_home "C:\phpstudy_pro\extensions\Nginx1.25.2"

# 根据情况修改本地mysql密码🎈
setx MySqlKey_LOCAL "  "
```

将引号中的路径替换为你的采集对应的路径

> ### 请等待所有命令执行完毕,等到shell能够继续相应的回车键为止!

配置完以后关闭所有命令行窗口,以及vscode窗口(如果有用到vscode的话)再重新打开才会生效	

其他可选配置(spaceship_api模块)

```powershell
 Add-EnvVar -Name pythonpath -NewValue $pys/spaceship_api
```



### 环境自检

然后执行以下powershell命令检查是否可以通过检查🎈

```powershell
Confirm-WpEnvironment

```



## 配置软件目录到Path环境变量

备份环境变量

执行以下命令进行环境备份和导出

例如,将环境变量导出为csv文件到桌面(方便查看)

```powershell
Backup-EnvsByPwsh $desktop

```

或者导出为注册表备份(更加方便恢复)

```powershell
Backup-EnvsRegistry -Dir $desktop 

```



### mysql.exe

找到mysql.exe所在目录,然后将此目录添加到path环境变量中

下面的**powershell**命令行仅供参考(注意路径的修改,运行需要一点时间,请耐心等待)

```powershell

$MYSQL_BIN_HOME = "C:\phpstudy_pro\extensions\MySQL5.7.26\bin"
# setx MYSQL_BIN_HOME $MYSQL_BIN_HOME
[Environment]::SetEnvironmentVariable("MYSQL_BIN_HOME", $MYSQL_BIN_HOME, [EnvironmentVariableTarget]::User)

$newPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User) + ";%MYSQL_BIN_HOME%"

[Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)

```

### nginx.exe

```powershell
$nginx_home = "C:\phpstudy_pro\extensions\Nginx1.25.2"
setx nginx_home $nginx_home
#Add-EnvVar -EnvVar Path -NewValue '%nginx_home%' 
Add-EnvVar -EnvVar Path -NewValue $nginx_home

#如果使用了小皮,并且xp.cn_cgi.exe接管进程的端口监听的端口建议配置一下
setx CgiPort 9001 # 可能是9001或者9002

```

### 端口查询

使用如下powershell命令查询相关信息

```powershell
$p=Get-NetTCPConnection |?{$_ -like '*900*'};$p;ps -Id $p.OwningProcess
ps -Id $p.OwningProcess

```

例如:我查询到的是9002端口,所属进程是`xp.cn_cgi`

```powershell
PS> $p=Get-NetTCPConnection |?{$_ -like '*900*'};$p;ps -Id $p.OwningProcess

LocalAddress                        LocalPort RemoteAddress                       RemotePort State       AppliedSetting OwningProcess
------------                        --------- -------------                       ---------- -----       -------------- -------------
127.0.0.1                           9002      0.0.0.0                             0          Listen                     18908

Id      : 18908
Handles : 94
CPU     : 0.015625
SI      : 1
Name    : xp.cn_cgi
```

## 检查配置🎈

检查mysql.exe是否能够访问,并且看看是否能够登录到交互shell中

```powershell
mysql -uroot  -proot -P 3306 -p"$env:mysqlkey_local"
```

例如我们查询已经存在的数据库"show databases; ",或者查看内置的`mysql`中的表

```powershell
mysql -uroot -p"$env:MySqlKey_LOCAL" -P 3306 -e "use mysql;show tables;"
```

如果顺利,会输出:

```powershell
PS> mysql -uroot  -P 3306 -e "show databases;" #配置了免密登录的话可以不用指定-h,-p参数
mysql: [Warning] Using a password on the command line interface can be insecure.
+--------------------+
| Database           |
+--------------------+
| information_schema |
```

如果有ERROR,说明密码错误,检查环境变量`mysqlkey_local`配置是否有误
