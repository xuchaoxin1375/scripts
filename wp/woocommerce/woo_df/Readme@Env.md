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



## 适用于windows系统的环境变量配置



下面采用命令行`setx`的方式配置,用户也可以选择使用系统的图形界面配置环境变量

配置前建议先备份现有环境变量

### 备份环境变量

执行以下命令进行环境备份和导出

例如,将环境变量导出为csv文件到桌面(方便查看)

```powershell
Backup-EnvsByPwsh $desktop

```

或者导出为注册表备份(更加方便恢复)

```powershell
Backup-EnvsRegistry -Dir $desktop 

```

### 基础环境变量配置👺

例如,配置采集器的数据存储路径(建议使用powershell运行)

> ###喜欢使用D盘的注意按需更改""中的值(强烈建议不要设置D盘,diskmgmt删除该盘,然后扩展C盘,尤其总共不足1TB的情况下便于管理)

```cmd

```

将引号中的路径替换为你的采集对应的路径

>  请等待所有命令执行完毕,等到shell能够继续相应的回车键为止!👺



配置完以后关闭所有命令行窗口,以及vscode窗口(如果有用到vscode的话)再重新打开才会生效	

其他可选配置(spaceship_api模块)

```powershell
 Add-EnvVar -Name pythonpath -NewValue $pys/spaceship_api
```

### 配置软件目录到Path环境变量👺



### CgiPort配置🎈

#### 端口查询

使用如下powershell命令查询相关信息

```powershell
$p=Get-NetTCPConnection |?{$_ -like '*900*'};$p;ps -Id $p.OwningProcess
# ps -Id $p.OwningProcess #xp.cn_cgi进程

```

例如:我查询到的是9002端口(LocalPort),所属进程是`xp.cn_cgi`

```powershell
PS> $p=Get-NetTCPConnection |?{$_ -like '*900*'};$p; ps -Id $p.OwningProcess

LocalAddress                        LocalPort RemoteAddress                       RemotePort State       AppliedSetting OwningProcess
------------                        --------- -------------                       ---------- -----       -------------- -------------
127.0.0.1                           9002      0.0.0.0                             0          Listen                     18908

Id      : 18908
Handles : 94
CPU     : 0.015625
SI      : 1
Name    : xp.cn_cgi
```



```powershell

#如果使用了小皮,并且xp.cn_cgi.exe接管进程的端口监听的端口建议配置一下
# setx CgiPort 9001 # 可能是9001或者9002

```

### 添加Path变量备用方案:(可选)

```powershell
[Environment]::SetEnvironmentVariable("MYSQL_BIN_HOME", $MYSQL_BIN_HOME, [EnvironmentVariableTarget]::User)

$newPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User) + ";%MYSQL_BIN_HOME%"

[Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
```





### php命令行(可选)

```powershell
$PHP_HOME='C:\phpstudy_pro\Extensions\php\php7.4.3nts'
setx php_home $php_home
Add-EnvVar -EnvVar Path -NewValue $php_home
```

### 服务器环境相关变量模板(可选)

```bat
Add-EnvVar -EnvVar DF_SERVER1 -NewValue 192.168...
Add-EnvVar -EnvVar DF_SERVER2 -NewValue 192.168...
Add-EnvVar -EnvVar DF_SERVER3 -NewValue 192.168...
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

## 环境自检👺

然后执行以下powershell命令检查是否可以通过检查🎈

```powershell
Confirm-WpEnvironment

```

