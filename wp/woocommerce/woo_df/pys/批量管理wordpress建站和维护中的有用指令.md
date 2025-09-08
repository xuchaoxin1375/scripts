[toc]





## 管理wordpress过程中的有用指令🎈

使用powershell(跨平台的版本:pwsh)方案执行以下任务,记录备用

### 批量重命名wps-hide-login目录

例如,为`wps-hide-login.bak`(临时被禁用的插件)重命名为`wps-hide-login`的命令行:

```powershell
Get-ChildItem . -Recurse -Depth 5 -filter 'wps-hide-login.bak' -Directory|%{Rename-Item $_ -NewName ($_ -replace '\.bak$','' ) -Verbose}
```

### 批量查询插件状态信息

```powershell
ls -path $wp_sites/*.* -Directory|% -Parallel {write-host "$_";wp plugin status woocommerce --path=$_} -ThrottleLimit 32
```



### 批量激活wp网站插件

首先扫描出所有wordpress站的根目录



### 批量激活wp插件

#### windows

例如,激活`wps-hide-login`插件

首先`cd`到所有网站所在的总目录,然后扫描各个站点根目录(根据情况修改管道符前面的命令)

或者使用`--path`参数更优雅

```powershell
#⚡️[Administrator@CXXUDESK][C:\sites\wp_sites][14:41:03][UP:6.97Days]
PS> ls *.* -Directory|%{cd $_;wp plugin activate wps-hide-login ;cd -}

```

#### linux

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

### 更新插件

#### 更新单个插件

```powershell
#⚡️[Administrator@CXXUDESK][C:\sites\wp_sites\1.us][18:08:38][UP:19.15Days]
PS> wp plugin update woocommerce
Enabling Maintenance mode...
Downloading update from https://downloads.wordpress.org/plugin/woocommerce.10.1.2.zip...
Unpacking the update...
Installing the latest version...
Removing the old version of the plugin...
Plugin updated successfully.
Disabling Maintenance mode...
+-------------+-------------+-------------+---------+
| name        | old_version | new_version | status  |
+-------------+-------------+-------------+---------+
| woocommerce | 9.8.2       | 10.1.2      | Updated |
+-------------+-------------+-------------+---------+
Success: Updated 1 of 1 plugins.
```



#### 批量更新插件

比如批量更新woocommerce这个核心电商插件

更新本地模板为例

```powershell
ls -path $wp_sites/*.* -Directory|%{wp plugin update woocommerce --path=$_ }
```

或者使用更高效的并行更新:

```powershell
ls -path $wp_sites/*.* -Directory|% -Parallel {wp plugin update woocommerce --path=$_ } -ThrottleLimit 5
```

> 并行更新对于打印的中文内容可能会乱码,这不重要,提示success就行

### 主题

#### 检查多余主题

```powershell
ls -path $wp_sites/*.* -Directory|% -Parallel {wp theme list --path=$_ } -ThrottleLimit 16
```



#### 更新主题

> 有时核心插件更新会更新一些模板文件(比如woocommerce更新引起的模板文件更新),这时可能需要你更新最新主题来兼容最新版本的woocommerce插件带来的变化

##### 在线更新主题

这里仅作记录,通常建议使用离线更新,更快速也更统一

```powershell
ls -path $wp_sites/*.* -Directory|% -Parallel {wp theme update --all --path=$_ } -ThrottleLimit 5
```

服务器端

```powershell
# pwsh
$wp_sites='/www/wwwroot/*/*.com/wordpress'
get-childitem -path $wp_sites -Directory|% -Parallel {sudo -u www wp theme update --all  --path=$_ } -ThrottleLimit 10
```

```powershell
$wp_sites='/www/wwwroot/*/*.com/wordpress'
get-childitem -path $wp_sites -Directory|% -Parallel {sudo -u www wp theme list  --path=$_ } -ThrottleLimit 32
```

##### 离线更新主题

相比于在线更新下载新的主题包覆盖旧的主题,这种方案依赖于wp代码完整,尤其是主题中的相关代码(functions.php)没有错误,否则更新是会收到阻碍,报警甚至崩溃无法实现更新

即便是有些主题的高级版(收费版)可能会关联到插件的更新,通常也可以单独更新插件,而不是必须要在线更新主题

而且为了更快的加载,保持模板的轻量化,我们使用免费主题就已经足够满足业务的需要

离线更新主要步骤如下:为了便于讨论,假设当期使用主题记为x主题

- 在本地更新主题x(可以命令行更新,或者进入后台更新,或者安装包更新),这一步可以用在线更新的方式进行,但只需要一次,这只是为了获取最新的主题文件
- 然后将主题目录(比如wordpress站根目录wp-content/themes/x)复制出来编辑(比如我们的业务需要将主题中的`functions.php`重命名为init.php后放到主题目录下的`inc`子目录下,然后将我们专用的`functions.php`覆盖到主题x的目录下)
- 最后把这个编辑好的主题目录包覆盖回所有同主题的模板中去,即可即可实现批量模板的主题更新
  - 这一步要小心,尤其是你的所有模板站中使用了不止x这个主题,如果把x主题覆盖到y主题,就是错误的
  - 推荐的流程是,扫描(定位)出所有使用了x主题的模板中x主题的目录,然后分别覆盖这些x主题目录即可

例如更新astra主题包,这里假设老的astra版本(4.8)要用4.11版本覆盖更新(新包位置设为`/www/wwwroot/themes_astra_4.11/astra/`)

```powershell
#扫描出所有astra目录(可以通过查看$ts变量来确定扫描出来的路径是否正确)
$ts=Get-ChildItem /www/wwwroot/*/*.com/wordpress/wp-content/themes/astra |select -ExpandProperty FullName
#遍历所有astra目录,然后用最新包中的内容覆盖老astra目录中的内容即可
$ts|%{cp /www/wwwroot/themes_astra_4.11/astra/* $_ -v -rf} 
```



### 更新wordpress核心

windows端

```powershell
ls -path $wp_sites/*.* -Directory|% -Parallel {wp core update  --path=$_ } -ThrottleLimit 32
```

服务器端

```powershell
# pwsh
$wp_sites='/www/wwwroot/*/*.com/wordpress'
get-childitem -path $wp_sites -Directory|% -Parallel {sudo -u www wp core update  --path=$_ } -ThrottleLimit 32
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

