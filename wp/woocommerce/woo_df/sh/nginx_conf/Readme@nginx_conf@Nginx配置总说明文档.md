[toc]

# abstract

介绍 `nginx`配置文件(.conf)以及配套的其他辅助文件和配置文件管理脚本(shell脚本文件);

内容(用途)涵盖两方面:反代和限流.

- 反代:利用轻量服务器或者vps,搭建为专用的反向代理服务器(反代网关),用来保护和隐藏后端服务器ip,基础功能包括将所有请求正确地路由到对应的后端服务器,并返回内容给客户端.(暂不涉及扩展功能,例如缓存加速和负载均衡.)
- 限流:防止或缓解恶意爆破和爬虫代理的负面影响,尤其是服务器流量负载控制和基础的安全路径访问限制

起初使用的是原版nginx,后来为了满足更复杂的需求,引入openresty(功能增强版nginx),来实现动态处理,尤其是实现js挑战的反爬和防御功能.

# 反代

为了提高后端服务器的隐蔽性,我们引入反向代理,基于nginx,并且适配多个情况(版本):

1. 单个ip的vps为一个后端服务器反代
2. 单个ip的vps为多个后端服务器反代
3. 多个ip的vps为相应数量的后端服务器反代

其中第1种情况配置最简单,第3种资源消耗较多(需要多个ip),但也相对简单,都可以**一键配置**;

>  这两种方案在反代服务器上都可以一次性配置,后续后端添加网站也不用关心.

第2种资源消耗最少,但是配置也相对复杂(主要体现在需要服务器管理员需要自行提供路由映射文件(`routes.map.conf`),并且在后续添加新站点时需要更新维护映射表,也就是`routes.map.conf`)

### 前提要求和注意事项

- 性能要求:要求很低,单核心的vps足够
  - 但是如果要用宝塔的话,安装软件,例如nginx可能会比较卡)
  - 如果不用宝塔的话,资源监控可以用`htop,btop,top`,文件编辑用vim或nano
  - 磁盘要求也低,定期清理日志(每天清理一次即可)
- linux系统(推荐ubuntu/debian,但不是必须的.)
- 安装nginx或openresty,前者最简单,可以考虑包管理器直接安装,或者通过脚本安装最新版本的nginx,如果用宝塔也可以考虑宝塔安装,但是安装速度慢.
  - 通过标准安装(系统包管理器或脚本安装)的默认配置路径是`/etc/nginx`,日志`/var/log/nginx`,其他情况自行修改部署脚本相关路径参数(如果要手动配置也要确保路径对应实际情况.)
  
  - ```bash
    curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/tool_installer/install_nginx_ubt.sh -o ~/inu.sh && sudo bash ~/inu.sh
    ```
  
    

### 相关文档

包含各种情况下反代的部署脚本和日志清理定时任务说明

- [Code/server/nginx/反向代理配置实战 · xuchaoxin1375/blogs - 码云 - 开源中国](https://gitee.com/xuchaoxin1375/blogs/tree/main/Code/server/nginx/反向代理配置实战)

本仓库用户,定时任务(crontab):

- `cf_realip.conf`配置的更新.
- 清理日志可以参考如下配置:

> 配置前后都建议要验证一下,运行bash命令后是否执行了清理,可以执行`df -h`查看磁盘占用情况

```bash
# 默认扫描常见路径下日志:/var/log/nginx,/www/wwwlogs
0 0 * * * bash ~/sh/clean_reverse_server_logs.sh >> ~/clean_log_actions.log 2>&1

```

更新`cf_realip.conf`

```bash
# 每天凌晨3点更新cf_realip.sh,并重载nginx.(路径适用于ubuntu/debian vps)

# 如果是标准安装(nginx配置根目录为/etc/nginx/的情况)
0 3 * * * bash /etc/nginx/update_cf_ip_configs.sh -s /etc/nginx/conf.d/cf-realip.conf

# 如果nginx通过宝塔安装:
0 3 * * * bash /www/server/nginx/conf/update_cf_ip_configs.sh -s /www/server/panel/vhost/nginx/cf-realip.conf
```



# 限流

## 文件说明

- 带有js字样的是为js挑战准备的,包括 `.conf`和 `.html`
  - `com_js_signed.conf`针对于openresty编写,原版nginx不能使用,其他 `com_...conf`兼容原版nginx
- 主配置文件:
  - `nginx_nginx.conf`,适用于原版的主配置,部署时用来替换 `nginx.conf`
  - `nginx_openresty.conf`

## 注意事项

- 搜索引擎的爬虫可以带来流量,因此在封锁或防御恶意爬虫时也要检测和验证google/bing爬虫能否顺利抓取页面,检验方法有许多:
  - 使用js挑战后,通常服务器负载会因为普通爬虫脚本无法爬取核心内容(数据库查询次数降低)而负载降低;但是如果负载降低过头(比如始终低于10%,那么就要怀疑是不是规则没写好,导致爬虫抓取的是挑战页面而没有访问到真正的页面(没有数据库查询)
  - 另一方面是检查日志(nginx/openresty),但是注意日志格式中要包含 `$body_bytes_sent `(默认会包含的),如果爬虫没有抓取到真正的页面,那么会发现日志中的 `bytes`大小很小(通常不足10kB(10000B)),并且大量请求的bytes都一样大,这就是爬虫抓取的是挑战页面的征兆

### 服务器类型

> 下面两种方案要使用的部署方式略有不同,请服务器管理员根据自己的服务器情况做调整.

1. 常规的标准cdn代理保护服务器
2. 增强的隐蔽ip+cdn代理保护服务器(反向代理的ip)

## 配置步骤

1. 清理/卸载宝塔的免费防火墙(这个东西很鸡肋,容易和自定义nginx配置冲突),如果没安装可以跳过此步骤

2. 通过"**代码下载**"(仓库中Readme@sh.md)一节提供的命令行片段将所需的代码目录下载到服务器上(已经操作过则跳过此步骤),确保已经得到目录 `/www/sh`;(如果有古老版本的代码仓库目录 `/repos/scripts`,可以手动清理掉)

   一键部署(单行部署,github和gitee 方式2选1,后者适合国内,但是可能要登录.)

   > 方便起见,这里默认用github.

   ```bash
   # 标准方案
   # github
   bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh) -F -R -U
   # gitee
   bash <(curl -SfL https://raw.giteeusercontent.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/update_repos.sh)  -F -R -U
   
   ```
   
   > 其中 `-F`(相当于`-g -f`),会覆盖 `nginx`的主配置文件(nginx.conf),酌情使用,如果不想覆盖,可以移除 `-F`
   >
   > 对于反向代理ip的服务器,请使用额外的`-R`选项.如果服务器本身IP适合直接暴露(比如对cdn可见),则可以考虑移除`-R`
   >
   > `-U`会向你的shell(bash和zsh)的配置文件插入一些易用的环境变量,别名和shell函数,并更改bash的prompt样式,相较于默认样式更美观.如果不需要这部分功能,可以考虑移除`-U`.
   
   上述步骤顺利执行的情况下只是完成一部分,限流并不会生效,直到vhosts配置更新.(对于服务器迁移的情况,需要尤为注意).
   
3. 创建/覆盖配置目录

   - 运行 `bash /update_repos.sh -g -f` 这个命令会处理:
     - 将 `/www/sh`脚本目录中的脚本更新到最新.(里面包含许多服务器管理脚本,`/www/sh/nginx_conf/`这个目录包含 `nginx`配置管理脚本)
     - 并在服务器上的nginx配置目录 `/www/server/nginx/conf`中创建所需的文件(主要是一些 `.conf`,还可能包括 `html`文件)

4. 更新vhosts配置(关键步骤)

为了让更新的nginx配置生效,需要将自定义配置片段(通常是 `include ...`指令)插入到 `/www/server/panel/vhost/nginx/`目录下的各个网站的 `.conf`文件中,这个过程执行一个命令就可以

> (下面这个脚本有丰富的选项和用法,这里仅提供最简单粗暴的用法,详情使用 `-h`选项查看用法帮助)

```bash
bash /www/sh/nginx_conf/update_nginx_vhosts_conf.sh -m old --force
```

为了简化说明,这里不细说对新/老站点做分批限流,而是将所有站都做同样的处理.

### 从普通nginx迁移到openresty

分两类情况:

1. 如果用户尚未部署本代码(没有下载过),那么从nginx切换到openresty后,执行上述流程即可;

> 对于宝塔用户,在面板中将nginx切换到openresty版本(可能有几个变体可选,具体版本号不做特殊要求,任意选择);

2. 如果已经使用普通nginx,并且也已经使用本代码仓库的配置代码,则需要注意:

- 版本切换会重置 `nginx.conf`及其所在目录的其他配置文件,此时nginx暂时无法启动,需要用户重新执行脚本部署:

  > 因为使用本代码后,各个站点的vhost中的配置(`/www/server/panel/vhost/nginx`)引用的文件会因为版本切换而清空;
  >
  > 因此需要重新运行部署脚本创建所需的文件;
  >
  > 一般只需要再跑一遍`bash /update_repos.sh -g -f`

### 选择工作模式(js挑战/限流)

暂时没有让两者同时工作,用户需要二选一;

> 如果要同时生效,需要修改`com_js_signed.conf`文件;
>
> 将`com_limit_rate.conf`中的语句添加到"**受保护页面**"的上下文中,但注意`try_files $uri $uri/ /index.php?$args;`这个语句不要一起带过去,`com_js_signed.conf`中已经有了;也可以参考`com_js_429.conf`中最终的内容.



---

### 定期执行的脚本

初次部署需要注意:有两个shell脚本比较重要

- 脚本1:`update_cf_ip_configs.sh`(需要配置定期运行拉取cf公布的ip列表,可借助corntab定期运行,一般不要手动运行)

```bash
# 这一行加入到crontab中
0 3 * * * bash /www/sh/nginx_conf/update_cf_ip_configs.sh
```

- 脚本2:`update_nginx_vhosts_conf.sh`(初次部署使用,为已有的站做处理,后期新建的站可以定期执行一遍,或者每次建站绑定一个步骤执行此脚本.)

其他:

- 增大打开的文件数量限制(针对站点多的服务器),前面的章节已经提到过,方法之一是修改 `/etc/security/limits.conf` 文件,改完新开一个终端(让上一步修改生效),然后重启nginx

### 日志设置和检查效果

为了方便观察所有网站的日志,首先要把nginx日志都聚集到统一个日志文件中,并且可以根据我们感兴趣的日志进行聚合;

例如,将所有被允许的(白名单)的爬虫(googlebot,bingbot,....)的访问日志(对服务器上的所有网站的访问日志)聚合到 `/www/wwwlogs/spider.log`中;

也可以额外将所有访问日志(包括普通用户和任何爬虫)聚合到 `all.log`中

这样分析整个服务器所有站的搜索引擎爬虫就看 `spider.log`即可;

分析所有网站的访问日志就看 `all.log`即可(spider.log是all.log的一个子集)

另外,仓库还提供了一个 `qps.sh`脚本,可以分析约定格式的日志,计算出服务器承受的流量(每秒的QPS)

将nginx日志设置为约定的格式很简单(如果要还原默认也很简单),利用下面的脚本直接批量设置:

```bash
bash /www/sh/nginx_conf/update_nginx_vhosts_log_format.sh  # --dry-run
```

如果把上面命令的 `#`去掉,可以预览效果而不真正执行;

执行完毕后,重启nginx(执行 `nginx -t && nginx -s reload`),让更改生效;

---

接下来就可以检查日志了,例如:

```bash
# 传统的限流(针对大量google,bing等爬虫)
# 有没有生效就运行下面的,看看有没有429相关的访问日志出来:
tail -f /www/wwwlogs/spider.log | grep --line-buffered '429 ' | nl

# 如果要看任何爬虫的请求而不仅仅429,用这个:
tail -f /www/wwwlogs/spider.log|nl

```

```bash
# 针对客户端检测(主要防止恶意脚本大量请求)的日志
tail -f /www/wwwlogs/all.log|grep challenge --line-buffered|nl

```

### 日志定期清理

将日志聚合后,`spider.log`和 `all.log`文件体积的增长速度是比较快的,建议定期清理,创建对应的自动任务(比如创建 `clean_logs.sh`定义清理规则);然后在 `crontab`中添加定期运行此清理脚本.

## js挑战配置文件说明

针对原版nginx(后续简称为nginx)编写的配置在openresty上都可以直接使用,反之,为openresty编写的配置不能在原版使用.

这里还有一份单独的文档:`js_challenge_signed.md`,里面描述的更加细节也比较技术性,这里简单说明.

js挑战的正式版配置(`js_challenge`)出来之前,有过简化版或者设计简陋的版本:

- `com_js_naive.conf`这个版本支持nginx(原版),但是cookie容易被提取和盗用,没有额外的html文件美化js挑战页面,但是内容简单易懂,兼容性强.仍然有一定的防御作用和使用价值.
- `com_js_plus.conf`这个也是基于原版nginx做的,不过增加了专门的挑战页面过渡更自然,看起来更加美观,但是受限于原版nginx的功能,和上面最初版本有类似的问题.
- `com_js_signed_fake.conf`,是引入openresty的雏形版本,相比于上面的版本,在cookie防盗用方面有所增强,但是有设计缺陷,cookie的获取没有强制浏览器(其他非浏览器客户端第一次请求会被要求验证,但是仍然分发cookie,如果客户端请求时保存cookie并在第二次请求时携带,则仍然可以请求成功)
- `com_js_signed.conf`,修复上面的非浏览器客户端能够间接访问的问题,要求客户端执行js才能获取最终有效的凭据,并考虑了主流爬虫的放行和反向校验(避免被简单的user-agent伪装成搜索引擎而轻易绕过js挑战)
