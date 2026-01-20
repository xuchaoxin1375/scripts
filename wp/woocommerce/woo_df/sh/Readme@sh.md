[toc]

## abstract

运行在linux上的脚本以及相关配置

相关命令行以ubuntu/debian系为例

## 美化shell

参考[linux@提高shell命令行环境易用性@终端美化@国内网络环境友好一条龙美化(ohmyzsh)_oh my zsh 卸载-CSDN博客](https://blog.csdn.net/xuchaoxin1375/article/details/120999508?sharetype=blogdetail&sharerId=120999508&sharerefer=PC&sharesource=xuchaoxin1375&spm=1011.2480.3001.8118)

## shell配置文件环境预定义

写入一些便于使用的shell配置,比如常用别名和函数,以及预定义变量

```bash
loading pre-defined variables...
Loading pre-defined aliases...
Configs shell configs already exists in /root/.zshrc, skipping insertion...
Configs shell configs already exists in /root/.bashrc, skipping insertion...
Loading additional shell config and functions...
```

具体要写入的配置通过一个脚本管理:`/www/sh/shellrc_addition.sh`,这里面统筹管理外部配置,包括专门定义变量的 `shell_vars.sh`,专门定义别名的 `shell_alias.sh`,当然将来可能还有更多东西

不过共同点是使用source命令导入配置,并且要安排好顺序

一定要注意,这些shell脚本的换行符(`LF`)不要选择 `CRLF`,这容易导致解析错误 `\r...`

## 服务器上需要事先安装的东西👺

包括压缩包解压工具等,如果有就跳过

### linux基础软件包

假设服务器为ubuntu,一键安装命令行

```bash
sudo apt install p7zip-full p7zip-rar lz4 zstd unzip git -y #获取7z命令(完整安装)
sudo apt install parallel #并行执行命令的工具
```

#### wordpress相关

wp-cli命令行工具 [WP-CLI | WP-CLI | WP-CLI](https://wp-cli.org/zh-cn/#安装)

一键安装wp-cli命令行

```bash
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
php wp-cli.phar --info
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
wp --info

```

#### python脚本用到的依赖安装

> todo:使用虚拟环境优化python及其依赖包的安装和管理

```bash
#安装pip
apt install pip
```

```bash
 pip install -r /repos/scripts/wp/woocommerce/woo_df/requirements_linux.txt
```



### 批量添加站点基础准备

#### api key

- 面板设置中启用api,设置合适的ip白名单,(填写服务器配置`server_config.json`的时候只要填写到端口为止,端口后的串不要写入)
- 及时申请好cloudflare账号,并且获取全局key

### 服务器相关组件安装和配置

- LNMP套件(php7.4)

- fail2ban自动防御(需要手动安装),并且补全符号链接

  ```bash
  ln -s /www/server/panel/pyenv/bin/fail2ban-regex /usr/bin/fail2ban-regex -v
  ln -s /www/server/panel/pyenv/bin/fail2ban-testcases /usr/bin/fail2ban-testcases -v
  ```

#### mysql

- 关闭二进制日志文件备份功能,节约空间和资源消耗
- 调整mysql性能参数(使用宝塔预设的方案128G~256G或更高,尤其注意`max_connections`不应该低于1000)
- 设置数据库登录密码和私有管理员配置

##### 初次登录或修改mysql密码

对于宝塔用户,简单方案就是登录宝塔,数据库设置中获取密码或者修改密码

如果已经登录mysql(root),也可以通过sql语句修改mysql root的密码

```sql
-- 登录mysql root用户,并且修改为新密码(网站链接数据库的凭据届时将使用此新密码,此mysql root用户"不"开放远程登录!)
-- 注意:mysql8+使用caching_sha2_password
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY 'your_new_password';
```

创建私有可远程登录的mysql 管理员账号

```sql


-- 创建一个新的私有root管理员级别的用户(开放远程登录),比如root_private
-- !注意下面两行共[两个地方]用户名都要修改,密码不要和上面的一样,建议更复杂!
CREATE USER 'root_private'@'%' IDENTIFIED BY 'your_root_private_password';
GRANT ALL PRIVILEGES ON *.* TO 'root_private'@'%' WITH GRANT OPTION;

FLUSH PRIVILEGES;
-- END
```

首尾:建议重启mysqld服务,防止某些配置没有生效

```bash
systemctl restart mysqld
```

##### 防火墙配置

如果要远程登录mysql(私有管理员用户)首先要检查防火墙是否放行对应端口(通常是3306)

```bash
ufw allow 3306
```

检查:

```bash
ufw status |grep 3306
```

##### 检查mysql用户情况

```sql
# 查看全部mysql用户列表
select user,host from mysql.user;
# 查看当前用户
select user();
```

举例说明

```sql
mysql> select user,host from mysql.user;
+------------------+-----------+
| user             | host      |
+------------------+-----------+
| root_private     | %         |
| mysql.infoschema | localhost |
| mysql.session    | localhost |
| mysql.sys        | localhost |
| root             | localhost |
+------------------+-----------+
5 rows in set (0.00 sec)
```



#### php:

- 设置脚本内存限制(1G)
- php性能调整(并发方案128G),几个进程数1000,100,100,300:
- 加速插件opcache

### git 获取或更新脚本代码(初次拉取代码)🎈

这里使用浅克隆提高速度并节约资源

> 如果之前git clone过旧版本,或者想要重新clone,移除掉现有目录 `/repos/scripts`

```bash
#! /bin/bash
script_root='/repos/scripts'
if [[ -d "$script_root" ]]; then { echo 'The target dir is already exist! remove old dir...' ; sudo rm "$script_root" -rf ; } ; fi
# rm /repos/scripts -rf 
git clone --depth  1 https://gitee.com/xuchaoxin1375/scripts.git "$script_root"

# 配置更新代码的脚本的符号链接
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/sh -fv
# 使用简短的更新代码仓库的命令
bash /www/sh/update_repos.sh -g
# 向bash,zsh配置文件导入常用的shell函数,比如wp命令行等
bash /www/sh/shellrc_addition.sh
```

如果仅更新脚本仓库,则可以

```bash
git fetch origin
git reset --hard origin/main
git pull
```

#### 配置检查

拉取代码后,一定要即使检查配置,包括nginx配置



### 配置系统时间为北京时间

```bash
sudo timedatectl set-timezone Asia/Shanghai
```

### 修改主机名

```bash
sudo hostnamectl set-hostname "NewHostName"
#重载日志服务(否则许多日志还是使用旧主机名,例如:/var/log/auth.log)
systemctl restart rsyslog
```



### 配置shell脚本可执行权限(可选)

> 这部分已经在上面的代码克隆命令中执行过了,放在这里仅供参考

```bash
# 这里配置脚本文件(.sh)的可执行属性
chmod +x /repos/scripts/wp/woocommerce/woo_df/sh/*
# 让指定目录下所有脚本文件(.sh)可执行
find /repos/scripts/wp/woocommerce/woo_df/sh/ -type f \( -name "*.sh" -o -name "*.bash" \) -exec chmod +x {} \;

# 配置单个脚本可执行属性
#chmod +x /repos/scripts/wp/woocommerce/woo_df/sh/deploy_wp_full.sh

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

对于sftp,可以创建一个专门用来上传文件到指定文件夹的用户 `uploader`

对于webdav可以使用 `openlist`来部署相关服务

现在介绍sftp的方案,运行脚本创建 `uploader`用户和 `/srv/uploads/uploader/files`目录,并授予 `uploader`读写此目录的权限

```bash
bash /www/sh/adduser_uploader.sh
```

### 查看代码部署脚本源码(可选)

文件位置:`$woo_df\sh\update_repos.sh`

查看完整代码:

```powershell
cat $sh\update_repos.sh
```

## ssh服务端口更改

```bash
# 检查文件是否存在且Port行存在(默认检查Port 22片段)
grep -C 5 'Port 22' /etc/ssh/sshd_config 
```



```bash
OldPort=22
Port=2222 #自行更改
#(使用i命令原地修改文件并保存)
# sed  -i -nE "s/#?(Port $OldPort)/Port $Port/"  /etc/ssh/sshd_config 
#更安全的方案生成.bak备份,同时兼容行开头的空白和注释)
sed -i.bak -nE "s/^[[:space:]]*#?Port $OldPort[[:space:]]*$/Port $Port/" /etc/ssh/sshd_config

# 检查修改:
grep -C 5 'Port ' /etc/ssh/sshd_config 
```

### 服务端防火墙配置

```bash
#ubuntu
sudo ufw allow 22022
# 关闭原来的端口,例如22
sudo ufw deny 22
```

状态检查:`ufw status`,配合grep可以过滤出你感兴趣的端口.

### 客户端默认配置更改

例如修改默认登录端口

```powershell
notepad ~\.ssh\config
```



## 配置免密登录

[ssh免密登录配置@上传公钥到ssh server](https://blog.csdn.net/xuchaoxin1375/article/details/120733071?sharetype=blogdetail&sharerId=120733071&sharerefer=PC&sharesource=xuchaoxin1375&spm=1011.2480.3001.8118)

windows上,虽然没有自带ssh-copy-id工具,可以通过powershell+ssh调用服务器上的shell工具的方式实现

```bash
$pubkey=Get-Content ~/.ssh/id_ed25519.pub
ssh root@"your_server_host" "mkdir -p ~/.ssh && echo '$pubkey' >> ~/.ssh/authorized_keys"

```



### 重启ssh服务

```bash
sudo systemctl restart ssh
```



## 定时自动任务crontab🎈

使用 `crontab -e`选择编辑器编辑自动任务,添加以下内容(可以自定义执行时间)

如果不清楚crontab,可以参考[Linux crontab 命令 ](https://www.runoob.com/linux/linux-comm-crontab.html)

> 新服务器上不要直接用,尤其注意修改备份命令的参数
>
> 其他服务器管理员可能不需要全部的自动任务,按需选择使用

```bash
# 需要针对每个服务修改的部分

# 修改2个地方: -b参数为备份服务器(ip); -d参数指定要备份服务上的目录,主要是"server?"为对应的目录(比如s1,s2,...)
30 22 * * * bash /www/sh/backup_sites/backup_site_pkgs.sh -s /srv/uploads/uploader/files -b <backupIp> -d /www/wwwroot/xcx/server? #修改"server?"值为具体情况


# 通用部分(各个服务器共同的定时维护任务脚本)

# */30 * * * * pkill -9 nginx;nginx
0 0 */2 * * bash /www/sh/clean_logs.sh
0 3 * * * bash /www/sh/nginx_conf/update_cf_ip_configs.sh
50 23 * * 0 bash /www/sh/remove_deployed_sites.sh
*/30 * * * * bash /www/sh/deploy_wp_schd.sh
*/2 * * * * bash /www/sh/run-all-wp-cron.sh

## python脚本(适合复杂逻辑维护任务)
0 0 * * * python3 /www/sh/nginx_conf/maintain_nginx_vhosts.py update -m old >> /var/log/maintain_nginx_vhosts.log 2>&1


```

注意脚本 `deploy_wp_schd.sh`这个脚本的可执行权限(每次更新代码,上面的代码会尝试自动修改这些文件的可执行权限)

利用系统的crontab定时执行wp-cron,这里的脚本利用了 `wp-cli`命令行工具来触发,而不需要通过http链接触发,执行后有日志文件(记得定期删除(todo))

## nginx配置

### 总配置nginx.conf

文件位置:`$sh\nginx_conf\nginx.conf`

服务器中文件位置:`/www/sh/nginx_conf/nginx.conf`

如果将仓库中的 `nginx.conf`配置文件覆盖调用原配置文件(比如使用符号链接将文件从仓库位置指向到nginx配置文件路径)是一个有风险的行为

此外,在宝塔中,如果还用了免费防火墙(作者:民国三年一场雨)可能会和限流配置的片段产生冲突,目前看来这个防火墙功能很弱,效果不佳,不太有用,需要nginx限流配置或拦截非法请求的可以自己编写nginx配置,更加灵活

### 公共配置文件com.conf

对于宝塔用户,可以在 `/www/server/nginx/conf`目录下创建一个 `com.conf`的配置文件

> 在相关配套脚本的作用下,会在创建站点的时候一并往站点的vhost目录(`/www/server/panel/vhost/nginx/`目录下的 `<domain.xxx>.conf`)下配置文件插入一行引用此 `com.conf`的指令

下面是基本 `com.conf`的基本指令内容,可以根据需要统一在这个配置文件中修改;

每次有需求修改完成后需要重载nginx配置才能逐渐生效 `nginx -t && nginx -s reload` (如果语法有误,会报错,如果通过检测,就会重载配置)

为网站插入公用nginx配置片段的批量处理脚本:`/www/sh/nginx_conf/update_nginx_vhosts_conf.sh`

基础的公用配置(完整版)存放在 `/www/sh/nginx_conf/com.conf`文件中

## nginx 日志文件过多问题🎈

如果服务器上运行很多网站(数百个),可能会遇到如下格式报错

```bash
nginx: [emerg] open() "/www/wwwlogs/xxx.com.error.log" failed (24: Too many open files)
```

方案不唯一,这里提供一个方案,如果不行请参考其他方法

### 修改系统级 limits.conf

适用于非 systemd 或传统 init,systemd的系统经过试验应该也可以,如果不行请使用其他方案

1. 编辑 `/etc/security/limits.conf`：

   ```bash
   sudo vi /etc/security/limits.conf
   ```

   如果你习惯其他编辑器也可以,比如nano,vim,msedit或者vscode远程编辑

   如果用宝塔面板这类工具也可以在浏览器中编辑
2. 添加以下行（假设 Nginx 以 `www-data` 或 `nginx` 用户运行，根据实际情况调整）：

   ```conf
   * soft nofile 65536
   * hard nofile 65536
   root soft nofile 65536
   root hard nofile 65536
   nginx soft nofile 65536
   nginx hard nofile 65536
   ```

   > 同时确保 PAM 启用了 limits（大多数现代系统默认启用）。
   >

关闭当前终端链接,然后新开终端链接刷新环境(否则上述修改可能无效!)

在新的终端会话中重载nginx配置

## 配置限流

1. 清理免费防火墙(建议清理,很鸡肋,防止和自定义防火墙冲突)
2. git clone 代码目录得到/www/sh;(如果有古老版本的代码仓库目录 `/repos/scripts`,可以手动清理掉)
3. 覆盖同个目录(/www/server/nginx/conf)下的2个conf文件 `com.conf`和 `nginx.conf`
4. 运行同个目录下的两个.sh脚本
   - `update_nginx_vhosts_conf.sh`(作用是向 `/www/server/panel/vhost/nginx`里的各个站的.conf插入include ...com.conf),
   - `update_cf_ip_configs.sh`(需要配置定期运行拉取cf公布的ip列表,可借助corntab定期运行)
5. 增大打开的文件数量限制(针对站点多的服务器),方法之一是修改 `/etc/security/limits.conf` 文件
6. 新开一个终端(让上一步修改生效),重启nginx

## 终端文本编辑器

- nano或msedit,后者虽然更加易用,但是目前稳定性不如前者,且需要手动安装
- vim或neovim,强大的编辑器,这里简单添加一些默认配置来提高使用体验

只要您的配置文件使用 **Vim Script (VimL)**，它在 Vim 和 Neovim 之间就是高度兼容的。只有涉及到各自独有的高级功能或编程语言（Lua）时，兼容性才会出现问题。

```bash
FILES
       ~/.config/nvim/init.lua  User-local nvim Lua configuration file.

       ~/.config/nvim           User-local nvim configuration directory.  See also XDG_CONFIG_HOME.

       $VIM/sysinit.vim         System-global nvim configuration file.

       $VIM                     System-global nvim runtime directory
```

配置项目存放在`vimrc.vim`中.

