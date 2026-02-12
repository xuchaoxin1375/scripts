[toc]

## abstract

运行在linux上的脚本以及相关配置

相关命令行以ubuntu/debian系为例

## 美化shell(提高命令行的易用性)

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
sudo apt install p7zip-full p7zip-rar lz4 zstd unzip git rsync -y #获取7z命令(完整安装)
sudo apt install parallel #并行执行命令的工具
```

### 宝塔基础环境

通常是LNMP,外带一个fail2ban(不是必须的,但是网站数量较多时基本得配上增强防御力)

## 代码下载和管理

通过git下载代码,对于使用定时自动解压的用户,个别文件需要创建服务器专属的自定义版本,避免代码更新导致的覆盖和丢失.

### git 获取或更新脚本代码(初次拉取代码)🎈

这里使用浅克隆提高速度并节约资源

> 如果之前git clone过旧版本,或者想要重新clone,移除掉现有目录 `/repos/scripts`
>
> 

```bash
#! /bin/bash
script_root='/repos/scripts'
if [[ -d "$script_root" ]]; then { echo 'The target dir is already exist! remove old dir...' ; sudo rm "$script_root" -rf ; } ; fi
# rm /repos/scripts -rf 
git clone --depth  1 https://gitee.com/xuchaoxin1375/scripts.git "$script_root"

# 配置更新代码的脚本的符号链接
ln -s /repos/scripts/wp/woocommerce/woo_df/sh /www/sh -fv
# 使用简短的更新代码仓库的命令(记得检查fail2ban)
bash /www/sh/update_repos.sh -g # 如果追加使用-f会覆盖/www/server/nginx/conf/nginx.conf
# 向bash,zsh配置文件导入常用的shell函数,比如wp命令行等
bash /www/sh/shellrc_addition.sh
```

如果仅更新脚本仓库,则可以

```bash
git fetch origin
git reset --hard origin/main
git pull
```

### 脚本保护|自定义脚本(注意!)

`/update_repos.sh`会处理`/www/sh/`和`/www/server/nginx/conf`这些关键目录,如果你修改了代码仓库中的脚本,那么修改会丢失.

> 总之,修改过的脚本都要额外创建文件实现当前服务器或自己的专属版本,不曾使用或没修改过的文件就不用管理保持默认.

典型的例子是

- 部署脚本`deploy_wp_full.sh`和`deploy_wp_schd.sh`
- 备份脚本`backup_sites/backup_sites_from_source_dir.sh`

不建议服务器管理员直接使用或原地修改`/www/sh/`目录下的这两个文件.(如果没用到上述脚本,就不用管它们)

正确的做法是分被创建属于当前服务器的专属版本(不同人员管理的服务器网站目录结构可能不同,需要自定义)

例如当前服务器记为`s1`,则可以分别取名`deploy_wp_full_s1.sh`,`deploy_wp_schd_s1.sh`,也可以加入管理员的名字缩写,参考模板修改或重写是和当前服务器的版本.

这样即便代码更新覆盖也不会导致自定义修改的版本丢失.

最后要注意定时任务`crontab`中使用的脚本要是服务器专属的(另见crontab配置一节)

```ini
# 不同服务器管理员要维护自己的网站结构修改自己的定时部署/解压脚本,文件名可能形如deploy_wp_schd_s1.sh
*/30 * * * * bash /www/sh/deploy_wp_schd.sh
```



## 其他工具配置

### wordpress相关工具

wp-cli命令行工具 [WP-CLI | WP-CLI | WP-CLI](https://wp-cli.org/zh-cn/#安装)

一键安装wp-cli命令行

```bash
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
php wp-cli.phar --info
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
wp --info

```

### python脚本用到的依赖安装

> todo:使用虚拟环境优化python及其依赖包的安装和管理

```bash
#安装pip
apt install pip
```

```bash
# 执行此代码之前确保专用代码仓库已经克隆到设备上.
pip install -r /repos/scripts/wp/woocommerce/woo_df/requirements_linux.txt
```

ubuntu24+版本对于python pip安装依赖包更加严格,可能无法直接通过pip安装

可以使用`venv`模块或者`miniforge`来创建python环境,不过这在运行python脚本前就需要选择/切换python环境.

### 批量添加站点基础准备

#### api key

- 面板设置中启用api,设置合适的ip白名单,(填写服务器配置`server_config.json`的时候只要填写到端口为止,端口后的串不要写入)
- 及时申请好cloudflare账号,并且获取全局key

### 服务器相关组件安装和配置(宝塔)🎈



### fail2ban

- fail2ban自动防御(需要手动安装),并且补全符号链接

  ```bash
  ln -s /www/server/panel/pyenv/bin/fail2ban-regex /usr/bin/fail2ban-regex -v
  ln -s /www/server/panel/pyenv/bin/fail2ban-testcases /usr/bin/fail2ban-testcases -v
  ```



#### mysql

- 关闭二进制日志文件备份功能,节约空间和资源消耗
- 调整mysql性能参数(使用宝塔预设的方案128G~256G或更高,尤其注意`max_connections`不应该低于1000)
- 设置数据库登录密码和私有管理员配置

##### 检查当前用户和所有用户

```bash
#查看当前数据库用户是什么
select user();
```

```bash
mysql> select user,host from mysql.user;
+------------------+-----------+
| user             | host      |
+------------------+-----------+
...
| mysql.infoschema | localhost |
| mysql.session    | localhost |
| mysql.sys        | localhost |
| root             | localhost |
+------------------+-----------+
```



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

##### mysql免密登录配置

通过配置`.my.cnf`文件,写入登录信息

```ini
[client]
user = your_username
password = your_password
host = localhost
port=3306
```

也可以通过重定向写入文件,例如

```bash
echo "[client]
user = root
password = 15a58524d3bd2e49
host = localhost
port=3306" >> ~/.my.cnf
```

验证:
直接在终端输入mysql,看是否可以登录到mysql shell.

#### 测试mysql在脚本中的连通性

`mysqlshow`命令可以在脚本中用来检查数据库的连通性.但是系统可能不自带.

```bash
apt install mysql-client-core-8.0 
```



#### php

- 设置脚本内存限制(1G)
- php性能调整(并发方案128G),几个进程数1000,100,100,300:
- 加速插件opcache



### 配置检查

正式部署网站之前,尤其是拉取代码或覆盖脚本后,一定要即使检查配置,包括nginx配置.



### 配置系统时间为北京时间

```bash
sudo timedatectl set-timezone Asia/Shanghai
```

### 修改主机名🎈

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

## ssh服务端口更改(可选但是推荐)

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
$target="user@your_server_host" #例如 root@$env:DF_SERVER4

$pubkey=Get-Content ~/.ssh/id_ed25519.pub
ssh $target "mkdir -p ~/.ssh && echo '$pubkey' >> ~/.ssh/authorized_keys"
# 初次运行需要输入服务器ssh对应user用户的密码
```

通常上述操作配合默认的ssh配置已经足够了,如果不行,可能是其他sshd配置的问题.

### 重启ssh服务(按需)

根据需要如果发生了sshd配置修改,则要重启服务生效.如果没有就不需要重启服务

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

# 修改2个地方: -b参数为备份服务器(ip); -d参数指定要备份服务上的目录,主要是"server?"为对应的目录(比如server1,server2,...)
30 22 * * * bash /www/sh/backup_sites/backup_site_pkgs.sh -s /srv/uploads/uploader/files -b <backupIp> -d /www/wwwroot/xcx/server? #修改"server?"值为具体情况

# 不同服务器管理员要维护自己的网站结构修改自己的定时部署/解压脚本,文件名可能形如deploy_wp_schd_s1.sh
*/30 * * * * bash /www/sh/deploy_wp_schd.sh


# 通用部分(各个服务器共同的定时维护任务脚本)

# */30 * * * * pkill -9 nginx;nginx
0 0 */2 * * bash /www/sh/clean_logs.sh
0 3 * * * bash /www/sh/nginx_conf/update_cf_ip_configs.sh
50 23 * * 0 bash /www/sh/remove_deployed_sites.sh
*/2 * * * * bash /www/sh/run-all-wp-cron.sh

## python脚本(适合复杂逻辑维护任务)
0 0 * * * python3 /www/sh/nginx_conf/maintain_nginx_vhosts.py update -m old >> /var/log/maintain_nginx_vhosts.log 2>&1


```

注意脚本 `deploy_wp_schd.sh`这个脚本的可执行权限(每次更新代码,上面的代码会尝试自动修改这些文件的可执行权限)

利用系统的crontab定时执行wp-cron,这里的脚本利用了 `wp-cli`命令行工具来触发,而不需要通过http链接触发,执行后有日志文件(记得定期删除(todo))

## nginx配置

### 总配置nginx.conf

下载的代码仓库中相关文件位置:`$sh\nginx_conf\nginx.conf`(`nginx_nginx.conf`或`nginx_openresty.conf`,根据服务器的nginx版本来选用,部署脚本会自动选择,并映射到服务器中文件位置:`/www/sh/nginx_conf/nginx.conf`,不需要过于关心)

如果将仓库中的 `nginx.conf`配置文件覆盖调用原配置文件(比如使用符号链接将文件从仓库位置指向到nginx配置文件路径)是一个有风险的行为

此外,在宝塔中,如果还用了免费防火墙(作者:民国三年一场雨)可能会和限流配置的片段产生冲突,目前看来这个防火墙功能很弱,效果不佳,不太有用,需要nginx限流配置或拦截非法请求的可以自己编写nginx配置,更加灵活

### 公共配置文件`com_...conf`系列

对于宝塔用户,可以在 `/www/server/nginx/conf`目录下创建一个 `com.conf`的配置文件

> 建议服务器管理员在创建站点的时候一并往站点的vhost目录(`/www/server/panel/vhost/nginx/`目录下的 `<domain.xxx>.conf`)下配置文件插入一行引用此 `com.conf`的指令

每次有需求修改完成后需要重载nginx配置才能逐渐生效 `nginx -t && nginx -s reload` (如果语法有误,会报错,如果通过检测,就会重载配置)

为网站插入公用nginx配置片段的批量处理脚本:`/www/sh/nginx_conf/update_nginx_vhosts_conf.sh`,通过`-h`选项获取使用帮助

### nginx 日志文件过多问题🎈

如果服务器上运行很多网站(数百个),可能会遇到如下格式报错

```bash
nginx: [emerg] open() "/www/wwwlogs/xxx.com.error.log" failed (24: Too many open files)
```

方案不唯一,这里提供一个方案,如果不行请参考其他方法

修改系统级 limits.conf的方案

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

## 配置限流🎈

> 执行之前老用户注意备份自己自定义的脚本,详情参考"脚本保护"一节

1. 清理/卸载宝塔的免费防火墙(这个东西很鸡肋,容易和自定义nginx配置冲突),如果没安装可以跳过此步骤

2. 通过前面的"**代码下载**"一节提供的命令行片段将所需的代码目录下载到服务器上(已经操作过则跳过此步骤),确保已经得到目录`/www/sh`;(如果有古老版本的代码仓库目录 `/repos/scripts`,可以手动清理掉)

3. 创建/覆盖配置目录

   - 运行`/update_repos.sh -g -f` 这个命令会处理:
     - 将`/www/sh`脚本目录中的脚本更新到最新,里面包含许多服务器管理脚本,`/www/sh/nginx_conf/`这个目录包含`nginx`配置管理脚本
     - 并在服务器上的nginx配置目录`/www/server/nginx/conf`中创建所需的文件(主要是一些`.conf`,还可能包括`html`文件)

4. 初次部署需要注意:有两个.sh脚本比较重要

   脚本1:`update_cf_ip_configs.sh`(需要配置定期运行拉取cf公布的ip列表,可借助corntab定期运行,一般不要手动运行)

   脚本2:`update_nginx_vhosts_conf.sh`(初次部署使用,为已有的站做处理,后期新建的站可以定期执行一遍,或者每次建站绑定一个步骤执行此脚本.)

   为了让更新的nginx配置生效,需要将自定义配置片段(通常是`include ...`指令)插入到`/www/server/panel/vhost/nginx/`目录下的各个网站的`.conf`文件中,这个过程执行一个命令就可以

   > (下面这个脚本有丰富的选项和用法,这里仅提供最简单粗暴的用法,详情使用`-h`选项查看用法帮助)

   ```bash
   bash /www/sh/nginx_conf/update_nginx_vhosts_conf.sh -m old --force
   ```

   为了简化说明,这里不细说对新/老站点做分批限流,而是将所有站都做同样的处理.

其他:

1. 增大打开的文件数量限制(针对站点多的服务器),前面的章节已经提到过,方法之一是修改 `/etc/security/limits.conf` 文件,改完新开一个终端(让上一步修改生效),然后重启nginx

## 反爬

这里反爬也包括一部分的反骚扰(恶意请求,例如大量请求后马上断开状态码为499的骚扰请求).

基本效果是,请求产品页或shop页面,要求客户端执行一段javascript代码,使得一些简单的脚本工具(比如单纯的curl或python脚本)无法直接爬取或发送有效请求,会遇到403错误,需要借助浏览器才能访问.

高级爬虫(调用浏览器仍然可以访问,虽然无法彻底杜绝爬虫,单也增加了爬虫的成本)

目前的实现方案是基于openresty(nginx增强版),通过包含lua脚本的配置实现一些校验功能.

部署也很简单,基本实现脚本自动化:

- 将nginx版本切换到openresty,上述代码下载环节都执行完毕.
- 注意保护自定义脚本(备份或重命名),执行`/update_repos.sh -g -f`,这会检测你是否安装openresty,然后修改相关的配置文件,重启nginx即可

更多细节参考`/www/sh/nginx_conf/`中的其他文档文件(`.md`文件)

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

## 配置logchart

为了方便分析某个服务器上的流量以及限流策略效果(合理性和全面性),这里提供了一个日志分析页面(`log.php`),此页面带有日志可视化图表分析功能.和本文提供的nginx日志配置格式是配套的(这里假设用户已经克隆了[代码仓库](https://gitee.com/xuchaoxin1375/scripts)),否则可能无法分析.

对于宝塔用户,可以按如下步骤配置:

- 检查nginx配置文件(使用专属的日志格式),并确保对应的日志文件存在(spider.log),其他的可选(比如warn.log,all.log)

- 创建目录和文件符号链接

  ```bash
  logchart_root=/www/wwwroot/logchart/
  mkdir -p "$logchart_root"
  ln  /www/wwwlogs/{warn,spider,all}.log "$logchart_root" -fv
  ln  /repos/scripts/wp/logchart/* "$logchart_root" -fv
  ```

- cdn配置(cloudflare)

  - 可以登录网站用GUI配置,在指定域名下增加一个DNS记录绑定到指定ip(包含logchart站的ip)
  - 也可以用api或者flarectl配置

- 服务器上配置logchart网站配置

  - 设置对应的网站和域名
  - `.user.ini`里面如果有路径限制可能导致无法访问分析页面,可以酌情清空或删除(注意系统标志位可能导致无法直接`rm`删除)

## 网站迁移

### 备份/还原

获取最新版本备份:仓库中提供了配套脚本(目录`/www/sh/backup_sites/`下)

- 导出脚本`backup_sites_from_source_dir.sh`,可以相对灵活地将服务器上指定或者全部的网站导出到合适的目录下
  - 这个脚本功能是重要的，即便是备份服务器拥有全部备份,仍然是不可靠的,备份服务器主要是为了防止原服务器出现故障而做的解决方案.(最大的变数在于数据库软件之间版本的不同,因此尽量使用版本相近的数据库,不过简单的数据库(例如wordpress)一般不需要担心)
  - 但是备份服务器本身也可能会宕机甚至被意外破坏而不再可用,最坏情况下是不可恢复(尽管这是小概率事件),这时候求就需要从原服务器上重新导出可用(可以恢复)的备份,然后迁移到新到备份服务器上存储,只有这样才能尽可能提高可用性
  - 此外,理想情况下应该是定期更新网站备份包,因为网站的插件和functions.php是可能变化的(不过我们可以通过批量更新插件的方式来兜底),最重要的还是某些产品需要下架,如果使用之前的备份包,这些需要下架的产品又会重新上架(细心一点的话就是每次被下架产品的站都标记处理来,然后针对这些站做备份包的更新)
  - 关于是否支持多线程:考虑到备份大压缩包基本上都是跑满带宽,设计并行备份意义不是很大.不过后来发现,`rsync`在更新压缩包而不是全新上传的情况在,速度会明显变慢.出于现象,有几个方案优化:
    - 仍然使用rsync,但是增加并行设计,让几个压缩包同时传输
    - 或者直接在rsync任务启动前,计算哪些包将要备份,事先在服务器`s`上将对应的包删除
    - 使用其他传输工具.
- 传输脚本`backup_site_pkgs.sh`,调用`rsync`将文件备份(增量镜像的方式)到专门的备份服务器

为了描述方便,假设要执行任务:

服务器`a`的站迁移到服务器`b`:由于我们有一台备份服务器`s`,理想情况下,每天自动将服务器`a`上新增的网站压缩包完整的备份到`s`;但是可能有例外出现,例如某次更新脚本(包含了错误的修改)导致备份功能故障,或者备份服务器`s`恰好在备份时故障,就可能有些站没有备份到服务器`s`,为了保证备份服务器拥有`a`所有站的完整备份,此外,为了节约服务器空间,每周末都会定时清理网站压缩包,如果刚好有错过了清理前的传输(备份到`s`)

我们需要计算一下哪些站需要备份(这种漏掉的站一般不多)

```bash
# 在备份服务器上统计特定目录下的备份包,得到已经备份到网站(域名)列表
# 列出指定服务器备份目录中的压缩包,并保存到文本文件中(domain.com.sql.zst和domain.com.zst)
find /www/wwwroot/xcx/s4-1 -name '*zst' -printf "%f\n" > result.txt
# 读取文本文件中的网站备份包名
mapfile -t dms < result.txt
# 将文本文件中的网站压缩包文件去除后缀,提取域名,然后排序去重复,
for d in "${dms[@]}"; do
    # echo "${d%.com*}.com"
    if [[ ${d} = *sql.zst ]];then
        echo "${d%.sql.zst}"
    # elif [[ ${d%.com*} ]];then
    #     echo "${d%.com*}"
    fi
done | sort > domains.txt
# 如果domains.txt中的文件数量不是偶数,说明至少有站点备份不完整(比如缺失了数据库包或者根目录包)
nl domains.txt
# wc -l < domains.txt

cat domains.txt | uniq > backuped.txt
# 列出整理好的域名列表(均已备份)
nl backuped.txt
```

下载或拷贝文件内容,粘贴到需要检查备份的服务器上(目标服务器,例如服务器`a`),保存对应的文本文件(`dms_backuped.txt`)

将目标服务器上的所有网站域名的列表(可以从登记的表格中拷贝,或者自己扫描处理来)并保存为文本文件(`dms_all.txt`)

```bash
#移除相关文件中多余的空格
sed 's/^[[:space:]]*//;s/[[:space:]]*$//' dms*.txt
# 使用grep计算差集
grep -Fxvf dms_backuped.txt dms_all.txt > need_backup.conf
# 计算待备份网站数量
wc -l need_backup.conf

#也可以计算交集(供参考)
# grep -Fxf dms_all.txt dms_backuped.txt|nl
```

备份(从服务器导出)

```bash
bash ./backup_sites/backup_sites_from_source_dir.sh --whitelist-site need_backup.conf  --parallel  
```

备份完毕后,检查`crontab -l`中的备份传输的行,形如:

```bash
bash /www/sh/backup_sites/backup_site_pkgs.sh -s /srv/uploads/uploader/files -b ... -d /www/wwwroot/...
```

将包都备份到服务器`s`中

#### 从备份服务器拉取包

假设现在服务器`b`要拉取一部分服务器`s`的包进行还原部署.

> ```bash
> rsync [选项] 源路径 目标路径
> ```
>
> 传输方向有2个:(根据需要可以对调两个路径)
>
> - 本地路径->远程路径
> - 远程路径->本地路径
>
> 关于**远程路径**:形如`remote_full_path="$user"@"$remote_host":"$remote_path"`

登录服务器`b`,执行如下格式的命令

```bash
user="root" #默认root
# 远程主机
remote_host=""
# 本地路径
local_path=""
# 远程路径
remote_path=""

#准备
authority="$user"@"$remote_host"
remote_full_path="$authority":"$remote_path"

mkdir -p "$local_path"

rsync -avP --size-only "$remote_full_path" "$local_path" 
```

准备解压:**移动**从备份服务器拉取到的包到指定待解压目录下,然后就可以利用部署脚本进行部署(导入网站).

```bash
# 注意末尾的 / 确保只匹配目录
# 如果要指定人员目录,将*改为人员目录名
for dir_path in "$uploader_files"/*/; do
    # 移除末尾的 / 以便构造字符串
    dir_name=$(basename "$dir_path")
    user_pack_home="$uploader_files/$dir_name"
    
    # 构造新字符串
    from_backupsrv="$user_pack_home/from_backupsrv/deployed"
    [[ -d "$from_backupsrv" ]] && mv "$from_backupsrv"/* "$user_pack_home" -v
done
```

合并备份服务器中的备份包(合并前确保已经所有站都迁移完毕,否则后续还要重新挑选未迁移的站)

```bash
base="/www/wwwroot/xcx"
#从服务器1合并(移动)服务器2,分别定义两个目录
s1="s4-1"
s2="s1"
for user in "$base"/$s1/*/;
do
	user_dir=$(basename "$user")
#	echo $user_dir
	from_dir=$base/$s1/$user_dir/deployed
	target_dir="$base/$s2/$user_dir/deployed"
	for pkg in "$from_dir"/* ;do
		#预览检查(重要!)
#		echo "$pkg -> $target_dir"
		mv "$pkg" "$target_dir" -v
    done
done
```

```
	for pkg in $p/deployed/* ;do
		echo "$pkg -> $target_dir"
    done
```



### 宝塔站点重叠

通过如下命令可以查看后缀带有`_80`的网站配置文件

> (这大概率是你通过宝塔(api)重复创建了同名网站,比如之前已经创建过domain.com这个站,然后又执行了一遍,就会得到`domain.com_80`),此外,还会体现在nginx目录中出现了`domain.com_80.conf`配置文件.
>
> 当然这种情况可能是两个站都指向同一个网站目录.我们可以在面板中查找`_80`过滤出这些网站,然后批量勾选,删除网站.(注意不要勾选站点目录!除非你确实发现不需要.)

> todo:改进宝塔api调用方式:在创建指定域名站点时,现检查有无同名站点存在.

```bash
 ls /www/server/panel/vhost/nginx/*_80.conf
```

### 控制并发部署解压的线程数

建议解压线程不要超过10个,否则部分逻辑可能执行不完整或者出现意料之外的错误.

### 批量移动包到指定目录

根据域名列表,将指定域名的压缩包组从`user/deployed`目录移动到user/目录

```bash
#假设当前是用户目录:.../user/deployed
sites=(
domain1.com 
domain2.com 
...
)

for site in "${sites[@]}" ;do mv "$site"*zst .. ;done
```



### 站点检查

无论是采用什么方案,迁移部署完后都要检查是否可以正常打开,尤其是过渡并发部署导致的一些潜在问题.

检查前,可以将原服务器上相关网站根目录的父目录(甚至祖先目录)重命名,然后观察迁移后的站是否可以访问,防止访问到旧服务器上的网站版本.

可能出现的故障:

- 数据库链接失败(可能是因为`wp-config.php`修改代码在大量并发解压部署中不够稳健)
- 如果部分站点迁移后异常卡顿,可以考虑重启数据库服务



### 无缝迁移(cdn端设置)

这里不涉及负载均衡,仅讨论简单的将一批网站从服务器a迁移到服务器b尽可能减少中断时间的方案

这里以cloudflare为例.

假设服务器a由于某种原因需要重装,那么你可以将服务器a的站在服务器b上部署(解压和导入各方面都设置完毕,仅差一步cdn域名解析设置)

使用cloudflare api,将被迁移到网站的dns解析ip从服务器更改为服务器b的ip即可,断连时间片相对短暂.

> 仓库中已经配备了对应的脚本,可以灵活地实现需求.
>
> `$pys/cf_update_dns_ip.py`

或者直接将这批网站添加到另一个cloudflare账号(转移),这可能需要重新分配证书,可能导致一段时间的网站断连,步骤上也更多,所以迁移花费的时间会更长一些.
