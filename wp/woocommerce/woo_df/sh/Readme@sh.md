[toc]



## abstract

运行在linux上的脚本以及相关配置

相关命令行以ubuntu/debian系为例

### 服务器上需要事先安装的东西👺

包括压缩包解压工具等,如果有就跳过

假设服务器为ubuntu

```bash
sudo apt install p7zip-full p7zip-rar lz4 zstd unzip git -y #获取7z命令(完整安装)
sudo apt install parallel #并行执行命令的工具
```

wp-cli命令行工具 [WP-CLI | WP-CLI | WP-CLI](https://wp-cli.org/zh-cn/#安装)

```bash
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
php wp-cli.phar --info
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
wp --info

```



### git 获取或更新脚本代码

这里使用浅克隆提高速度并节约资源

```bash
git clone --depth 1 https://gitee.com/xuchaoxin1375/scripts.git /repos/scripts

# 配置更新代码的脚本的符号链接
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/sh -fv
# 使用简短的更新代码仓库的命令
bash /www/sh/update_repos.sh
# 向bash,zsh配置文件导入常用的shell函数,比如wp命令行等
bash /www/sh/shellrc_addition.sh
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

> 新服务器上不要直接用,尤其注意修改备份命令的的参数

```bash
# 修改-b参数为备份服务器(ip),修改"server?"为对应的目录(比如s1,s2,...)
30 22 * * * bash /www/sh/backup_sites/backup_site_pkgs.sh -s /srv/uploads/uploader/files -b "backupIp" -d /www/wwwroot/xcx/"server?"
0 0 */2 * * bash /www/sh/clean_logs.bash
0 3 * * * bash /www/sh/nginx_conf/update_cf_ip_configs.sh
50 23 * * 0 bash /www/sh/remove_deployed_sites.sh
*/30 * * * * bash /www/sh/deploy_wp_schd.sh
*/2 * * * * bash /www/sh/run-all-wp-cron.sh
# */30 * * * * pkill -9 nginx;nginx
```

注意脚本`deploy_wp_schd.sh`这个脚本的可执行权限(每次更新代码,上面的代码会尝试自动修改这些文件的可执行权限)

利用系统的crontab定时执行wp-cron,这里的脚本利用了`wp-cli`命令行工具来触发,而不需要通过http链接触发,执行后有日志文件(记得定期删除(todo))

[Linux crontab 命令 ](https://www.runoob.com/linux/linux-comm-crontab.html)

## nginx配置

### 总配置nginx.conf

文件位置:`$sh\nginx_conf\nginx.conf`

服务器中文件位置:`/www/sh/nginx_conf/nginx.conf`

如果将仓库中的`nginx.conf`配置文件覆盖调用原配置文件(比如使用符号链接将文件从仓库位置指向到nginx配置文件路径)是一个有风险的行为

此外,在宝塔中,如果还用了免费防火墙(作者:民国三年一场雨)可能会和限流配置的片段产生冲突,目前看来这个防火墙功能很弱,效果不佳,不太有用,需要nginx限流配置或拦截非法请求的可以自己编写nginx配置,更加灵活

### 公共配置文件com.conf

对于宝塔用户,可以在`/www/server/nginx/conf`目录下创建一个`com.conf`的配置文件

> 在相关配套脚本的作用下,会在创建站点的时候一并往站点的vhost目录(`/www/server/panel/vhost/nginx/`目录下的`<domain.xxx>.conf`)下配置文件插入一行引用此`com.conf`的指令

下面是基本`com.conf`的基本指令内容,可以根据需要统一在这个配置文件中修改;

每次有需求修改完成后需要重载nginx配置才能逐渐生效`nginx -t && nginx -s reload` (如果语法有误,会报错,如果通过检测,就会重载配置)

为网站插入公用nginx配置片段的批量处理脚本:`/www/sh/nginx_conf/update_nginx_vhosts_conf.sh`

基础的公用配置(完整版)存放在`/www/sh/nginx_conf/com.conf`文件中

