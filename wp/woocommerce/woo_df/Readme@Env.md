[toc]

## 配置通用的环境变量

适用于windows系统的环境变量配置

下面采用命令行`setx`的方式配置,用户也可以选择使用系统的图形界面配置环境变量

例如,配置采集器的数据存储路径(建议使用powershell运行)

> 喜欢使用D盘的注意按需更改""中的值

```cmd
setx PYTHONPATH C:\repos\scripts\wp\woocommerce\woo_df
setx PYS C:\repos\scripts\wp\woocommerce\woo_df\pys
setx WOO_DF C:\repos\scripts\wp\woocommerce\woo_df

# 根据情况修改本地mysql密码
setx MySqlKey_LOCAL "  "
# D盘用户注意按需更改,还有软件版本也要注意(日后如果更新软件,或其他导致目录变更的情况,要注意修改环境变量(使用gui方案))
setx LOCOY_SPIDER_DATA "C:\火车采集器V10.27\Data"
setx phpstudy_extensions "C:\phpstudy_pro\extensions"
setx nginx_conf_dir "C:\phpstudy_pro\Extensions\Nginx1.25.2\conf\vhosts"
# setx nginx_home "C:\phpstudy_pro\extensions\Nginx1.25.2"


```

将引号中的路径替换为你的采集对应的路径

> ### 请等待所有命令执行完毕,等到shell能够继续相应的回车键为止!

配置完以后关闭所有命令行窗口,以及vscode窗口(如果有用到vscode的话)再重新打开才会生效	

### 配置软件目录到Path环境变量

### mysql.exe

找到mysql.exe所在目录,然后将此目录添加到path环境变量中

下面的**powershell**命令行仅供参考

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
Add-EnvVar -EnvVar Path -NewValue '%nginx_home%' 
setx CgiPort 9000 #如果使用了小皮,并且xp.cn_cgi.exe接管进程的端口监听的端口建议配置一下
```

使用如下powershell命令查询相关信息

```powershell
$p=Get-NetTCPConnection |?{$_ -like '*900*'};$p;ps -Id $p.OwningProcess
```

例如我查询到的是9002端口,所属进程是`xp.cn_cgi`

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

