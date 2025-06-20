[toc]





## 本地wordpress站点批量复制🎈

- 这包括网站根目录的复制,模板数据库的导入以及配置文件的修改,使用的服务器是nginx(1.25版本,其他版本类似,但是要改个别地方) (apache暂不支持)

### 模板中的nginx.htaccess检查

- 通常这个文件是模板中自带的,但是如果你的模板站能够打开首页但是进入不了shop,或菜单页面或者任何产品详情页面,则应该是伪静态的配置问题

- 对于采用nginx作为服务器的情况,目前我们的做法是在站点根目录中放置包含以下内容的`nginx.htaccess`的文件

  ```bash
  location / {
      try_files $uri $uri/ /index.php?$args;
  }
  ```

  

### 配置环境

查看环境变量配置文档 [Readme@Env.md](..\Readme@Env.md) ,将尚未配置的命令行修改成用户自己的实际情况,然后分别执行,这样可以让命令的调用更加简单,少写许多参数

批量复制站点的命令使用起来很简单,命令是用powershell写的,需要安装pwsh(7)和相应的模块(已经安装过的可以跳过此步骤)

[scripts: 实用脚本集合,以powershell模块为主(针对powershell 7开发) 支持一键部署,改善windows下的shell实用体验](https://gitee.com/xuchaoxin1375/scripts)

> 推荐使用git命令快速部署

### 命令行🎈

最简单的使用方式就是配合默认配置,就是在桌面创建一个`my_table.conf`配置文件,然后命令行会在桌面创建`my_wp_sites`用来存放本地的wordpress站点根目录

在这种情况下,只需要直接调用powershell命令`deploy-wpsiteslocal`而不需要带参数

```powershell
Deploy-WpSitesLocal
```

如果需要更加个性化指定参数(完整的参数有不少,包括可以指定nginx相关的目录),可以使用`help Deploy-WpSitesLocal`获取帮助,常用的参数有:

- Table <Object>
  包含表格信息的配置文本文件,默认格式为每行包含[域名,用户名,模板名],以空格分隔

- WpSitesTemplatesDir <Object>
  本地Wordpress网站[模板]目录,脚本将会从这个目录下面拷贝模板站目录到指定位置(MyWpSitesHomeDir)

- MyWpSitesHomeDir <Object>
  本地各个Wordpress网站根目录聚集的目录,用来保存从WpSitesTemplatesDir拷贝的网站目录,这里保存的各个网站根目
  录,是之后装修的对象

更加完整的帮助请运行`help Deploy-WpSitesLocal`查看

```powershell
help Deploy-WpSitesLocal
```

### FAQ

理论上使用本文提供的批量部署脚本,部署结束后,就可以直接访问站点(旨在尽可能绕开小皮实现批量本地建站)

- 如果不行,先尝试重启小皮中的`nginx`服务,如果有报错的根据提示解决报错(通常是某个站由于被移动或者删除而其配置找不到了,导致不能顺利重启服务),然后新开一个浏览器隐私模式,用http链接访问本地网站
- 如果还是不行,可以考虑重置小皮的nginx配置为默认配置,然后重试
- 最后如果还是不行,暂退一步,用小皮普通的建站方法,即根据网站根目录创建对应的网站,然后重试访问本地网站