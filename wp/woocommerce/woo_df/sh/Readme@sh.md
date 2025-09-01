[toc]



## abstract

运行在linux上的脚本以及相关配置

相关命令行以ubuntu/debian系为例

### 服务器上需要事先安装的东西

包括压缩包解压工具等,如果有就跳过

假设服务器为ubuntu

```bash
sudo apt install p7zip-full p7zip-rar -y #获取7z命令(完整安装)
```



### 获取或更新脚本代码

```bash
git clone --depth 1 https://gitee.com/xuchaoxin1375/scripts.git /repos/scripts
```

如果仅更新脚本仓库,则可以

```bash
git fetch origin
git reset --hard origin/main
git pull
```



### 配置系统时间为北京时间



```bash
sudo timedatectl set-timezone Asia/Shanghai
```

### 配置可执行权限

```bash
# 这里配置脚本文件(.sh)的可执行属性
chmod +x /repos/scripts/wp/woocommerce/woo_df/sh/*
# 让指定目录下所有脚本文件(.sh)可执行
find /repos/scripts/wp/woocommerce/woo_df/sh/ -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;

# 配置单个脚本可执行属性
#chmod +x /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh

```



### 配置符号链接

```bash
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /deploy.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh /www/wwwroot/deploy_wp_full.sh -f
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/sh -f
 

```



### 部署wp网站

```bash
$ /deploy.sh --help
用法: /deploy.sh [选项]
选项:
  --pack-root DIR   设置压缩包根目录 (默认: /srv/uploads/uploader/files)
  --db-user USER    设置数据库用户名 (默认: root)
  --db-pass PASS    设置数据库密码
  --user-dir DIR    仅处理指定用户目录
  --help            显示此帮助信息

```

### 创建文件上传专用权限用户

文件上传方案有不少,比如sftp,webdav,后者会更现代化一些,前者支持的软件会更广泛一些

对于sftp,可以创建一个专门用来上传文件到指定文件夹的用户`uploader`

对于webdav可以使用`openlist`来部署相关服务

现在介绍sftp的方案,运行脚本创建`uploader`用户和`/srv/uploads/uploader/files`目录,并授予`uploader`读写此目录的权限

```bash
bash /www/sh/adduser_uploader.sh
```



## 综合脚本

为了方便期间,将脚本组织成一个脚本文件`update_repos.sh`,下面有两段代码

较长的完整代码第一次运行后,之后就可以用简化版本

### 简化版本🎈

!第一次运行需要完整版本,之后可以运行以下命令更新代码

```bash
bash /www/sh/update_repos.sh 
```

或者直接

```bash
/update_repos.sh
```



### 完整版本

文件位置:`$woo_df\sh\update_repos.sh`

查看完整代码:

```powershell
cat $sh\update_repos.sh
```



## 定时自动任务crontab🎈

使用`crontab -e`选择编辑器编辑自动任务,添加以下内容(可以自定义执行时间)

```bash
0 0 */2 * * bash /www/sh/clean_logs.bash
0 3 * * * bash /www/sh/nginx_conf/update_cf_ip_configs.sh
0 0 * * 0 bash /www/sh/remove_deployed_sites.sh
# */30 * * * * pkill -9 nginx;nginx
0 * * * * bash /www/sh/deploy_wp_schd.sh
*/2 * * * * bash /www/sh/run-all-wp-cron.sh
```

注意脚本`deploy_wp_schd.sh`这个脚本的可执行权限(每次更新代码,上面的代码会尝试自动修改这些文件的可执行权限)

利用系统的crontab定时执行wp-cron,这里的脚本利用了`wp-cli`命令行工具来触发,而不需要通过http链接触发,执行后有日志文件

[Linux crontab 命令 ](https://www.runoob.com/linux/linux-comm-crontab.html)

## nginx配置

### 总配置nginx.conf

文件位置:`$woo_df\sh\nginx_conf\nginx.conf`

服务器中原文件位置:`/www/sh/nginx_conf/nginx.conf`

### 公共配置文件com.conf

对于宝塔用户,可以在`/www/server/nginx/conf`目录下创建一个`com.conf`的配置文件

> 在相关配套脚本的作用下,会在创建站点的时候一并往站点的vhost目录(`/www/server/panel/vhost/nginx/`目录下的`<domain.xxx>.conf`)下配置文件插入一行引用此`com.conf`的指令

下面是基本`com.conf`的基本指令内容,可以根据需要统一在这个配置文件中修改;

每次有需求修改完成后需要重载nginx配置才能逐渐生效`nginx -t && nginx -s reload` (如果语法有误,会报错,如果通过检测,就会重载配置)

为网站插入公用nginx配置片段的批量处理脚本:`/www/sh/nginx_conf/update_nginx_vhosts_conf.sh`

基础的公用配置(完整版)存放在`/www/sh/nginx_conf/com.conf`文件中



## 一些有用的指令🎈

使用powershell(跨平台的pwsh)方案执行以下任务,记录备用

### 批量重命名wps-hide-login目录

例如,为`wps-hide-login.bak`(临时被禁用的插件)重命名为`wps-hide-login`的命令行:

```powershell
Get-ChildItem . -Recurse -Depth 5 -filter 'wps-hide-login.bak' -Directory|%{Rename-Item $_ -NewName ($_ -replace '\.bak$','' ) -Verbose}
```

### 批量激活wp网站插件

首先扫描出所有wordpress站的根目录

#### 本地windows端

### 批量激活插件

例如,激活`wps-hide-login`插件

首先`cd`到所有网站所在的总目录,然后扫描各个站点根目录(根据情况修改管道符前面的命令)

```powershell
#⚡️[Administrator@CXXUDESK][C:\sites\wp_sites][14:41:03][UP:6.97Days]
PS> ls *.* -Directory|%{cd $_;wp plugin activate wps-hide-login ;cd -}

```

详细步骤:

- 为了获取插件名以便设置(启用/禁用/更新),可以使用`wp plugin list`命令行列出所有插件的标准名字

```bash
$ sudo -u www wp plugin list
+---------------------------------------+----------+-----------+-----------------+----------------+-------------+
| name                                  | status   | update    | version         | update_version | auto_update |
+---------------------------------------+----------+-----------+-----------------+----------------+-------------+
| astra-addon                           | active   | available | 4.8.14          | 4.11.6         | off         |
| clowns-discount                       | active   | none      | Current Version |                | off         |
| mallpay                               | active   | none      | 2.0             |                | off         |
| elementor                             | active   | available | 3.27.7          | 3.31.1         | off         |
| elementor-pro                         | active   | available | 3.27.4          | 3.30.0         | off         |
| paypal-online-payment-for-woocommerce | active   | none      | 1.1.0           |                | off         |
| astra-pro-sites                       | inactive | available | 4.4.11          | 4.4.34         | off         |
| wp-card-tpay                          | active   | none      | 1.2             |                | off         |
| woocommerce                           | active   | available | 9.6.2           | 10.0.4         | off         |
| wps-hide-login                        | inactive | available | 1.9.17.1        | 1.9.17.2       | off         |
| wordpress-seo                         | active   | available | 25.2            | 25.6           | off         |
| yunzipaycc-for-woocommerce            | active   | none      | 1.0.0           |                | off         |
| custom-shortcodes                     | must-use |           |                 |                | off         |
+---------------------------------------+----------+-----------+-----------------+----------------+-------------+
```



- 扫描所有网站根目录

  ```powershell
  $dirs=Get-ChildItem -Recurse -Directory -Depth 2 -Path */wordpress |select -ExpandProperty FullName;$dirs
  
  ```

- 并行激活

  ```bash
  $dirs|% -Parallel {cd $_;sudo -u www wp plugin activate wps-hide-login } -ThrottleLimit 10
  ```

### 批量停用并卸载插件

```powershell
#⚡️[Administrator@CXXUDESK][~\Desktop][11:33:02][UP:1.88Days]
PS> ls -path $wp_sites/*.* -Directory|%{wp plugin uninstall 'plugin_name' --deactivate  --path=$_ }
```

这里使用`wp plugin uninstall <plugin_name> --deactivate  --path=..`来完整移除插件(`--deactivate`表示如果插件还未被停用时,先停用再删除,如果被卸载的插件仍然活跃,会卸载失败)

默认情况下,插件目录也会被删除,除非使用`--skip-delete`选项保留目录(通常也没有这个需求)

此外`wp plugin delete `也不常用,因为这个命令仅仅删除插件目录,但是其他痕迹会保留

### 移除wp-content/uploads目录中多余的目录

假设我的所有网站都放在目录`$wp_sites`下,那么下面的语句可以删除uploads目录中指定的`itemname`目录

```powershell
ls -Recurse -Directory -Filter <itemname> -Depth 3|?{$_.FullName -like '*wp-content\uploads\*'}|Remove-Item -Verbose
```



### 检查语言包

假设当前目录为某个wordpress根目录,查看该站中的已安装的语言可以这么做:

查看已经安装(但是尚未启用)的核心语言包

```powershell
#⚡️[Administrator@CXXUDESK][C:\sites\wp_sites\2.es]
PS> wp language core list --format=json | ConvertFrom-Json | Where-Object { $_.status -eq "installed" }|ft

language english_name            native_name             status    update    updated
-------- ------------            -----------             ------    ------    -------
de_DE    German                  Deutsch                 installed available 2025-08-13 20:50:37
en_US    English (United States) English (United States) installed none
fr_FR    French (France)         Français                installed none      2025-07-22 21:56:43
zh_CN    Chinese (China)         简体中文                installed none      2025-07-29 06:55:14

```

多余的语言包会占用额外的空间,通常我们保留该网站面向的业务市场语言,以及后台管理员习惯的语言就行了

如果是英语市场,则其他语言可以全部移除(中文可以酌情保留,便于web后台操作)

例如,如果上述模板是一个西班牙语的,那么其他语言可以酌情删除(英语可能删不掉)

查看已经安装(但是尚未启用)以及已经被激活启用的语言包

```powershell

#⚡️[Administrator@CXXUDESK][C:\sites\wp_sites\2.es][15:26:54][UP:2.04Days]
PS> wp language core list --format=json | ConvertFrom-Json | Where-Object { $_.status -ne 'uninstalled' }|ft

language english_name            native_name             status    update updated
-------- ------------            -----------             ------    ------ -------
en_US    English (United States) English (United States) installed none
es_ES    Spanish (Spain)         Español                 active    none   2025-07-09 10:04:44
zh_CN    Chinese (China)         简体中文                installed none   2025-07-29 06:55:14
```

​	

### 禁用wp定时任务wp-cron

powershell批量修改本地wp站点的`wp-config.php`（也可以考虑尝试wp-cli配置）

```bash

using namespace System.Collections.Generic
$configs = Get-ChildItem $wp_sites/*.* -Depth 2 -File -Filter wp-config.php | Select-Object -ExpandProperty FullName 

$configs | ForEach-Object {
    
    #修改单个wp-config.php内容(不立刻回写)
    # $Path = ".\wp-config.php"
    $Path = $_
    $strList = [System.Collections.Generic.List[string]]::new()
    Get-Content $Path | ForEach-Object { 
        if( $_ -match '.*Add any custom.*')
        {
            $t = $_ + @"

define('DISABLE_WP_CRON', true);#禁用wp-cron任务,使用系统定时任务代替

"@
        }
        else { $t = $_ } 
        $strList.Add($t)

    } 
    $strList | Set-Content -Path $Path -Encoding UTF8 -Force 
}
```

