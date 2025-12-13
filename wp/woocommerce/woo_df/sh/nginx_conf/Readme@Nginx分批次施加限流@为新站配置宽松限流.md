[toc]



## abstract

考虑到新的站需要被主流搜索引擎爬虫尽快爬取收录,而老站需要防止过多爬虫导致服务器负载过高的两方面不同的需要,这里将相关的nginx配置分成两部分.

方案设计以每次尽可能少改动(文件数量)为目标,完成上述任务的自动化.

- 一部分是老站点和新站点都应该引入(include)的安全性配置,主要是防止敏感文件被访问或者被特殊路径被爆破,这部分比如取名为`com.conf`
- 另一部分是限流,老站点限流严格一些,可以保护数据安全,也可以降低爬虫对服务器早成的过大负担,需要引入限流配置比如`limit_rate.conf`;而新站点则在上线1~2周内开放爬虫,少量限流或者不限流;等1~2周之后引入严格的限流配置文件

现在问题在于新站变成老站这个过程如何检测和判定,并且判定之后使用执行什么动作(脚本)

bash和python脚本均可实现此任务,不过考虑到任务具有一定的复杂度,尤其是日期时间计算,使用python门槛会比较低

### 确定网站的创建时间

关键是使用可靠的方式判断一个站大概创建在什么时候,这样其他计算和工作就可以展开

网站创建时间不需要很精准,误差在1个小时甚至24小时都没关系,因此,只要能够记录网站创建的日志(年月日)即可(时分秒不是必须的)

确定网站创建日期的基本方案有2种:

- 每次创建网站的时候,顺便维护一个**建站日期表**,比如使用一个csv格式的文本文件(`SITE_BIRTH_CSV`),包含两个字段(或可选的第三个字段):域名,创建日期;(`domain,birth_time,status`)

  ```csv
  domain,birth_time,status
  domain1.com,2025-10-10 18:07:17,young
  domain2.com,2025-11-04 18:07:17,young
  ```

  其中status可以让各个站的状态(新/老)更直观.

- 利用系统的文件系统,`stat`命令查看文件的创建日期(`birth_time`),这个方案容易受到一些文件操作的影响,从而可靠性不佳

  ```bash
  $ stat domain1.com.conf
    File: install_panel.sh
    Size: 59199           Blocks: 120        IO Block: 4096   regular file
  Device: 252,1   Inode: 185860108   Links: 1
  Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
  Access: 2025-09-27 08:35:31.104942416 +0800
  Modify: 2025-09-23 15:49:37.000000000 +0800
  Change: 2025-09-27 08:35:31.073942797 +0800
   Birth: 2025-09-27 08:35:30.890945044 +0800
  ```

  此外,find命令不提供birth_time的过滤选项,如果使用文件修改时间,则日期的可靠性会更低

- 还可以在建站的时候向各个网站的配置文件插入一行注释(包含建站日期),这样每次网站的建站日期行,但是可靠性仍然不如单独一个建站日期表,这体现在独立性上

  ```nginx
      #CUSTOM-CONFIG-START(2025-10-10 18:07:17)
      include /www/server/nginx/conf/com.conf;
  	include /www/server/nginx/conf/limit_rate.conf;
      #CUSTOM-CONFIG-END
  ```

  

## 方案

每次建站,我们都默认为新站的配置文件(vhost)中的`.conf`插入默认严格的配置:`com.conf`以及其他限流相关的配置(比如`limits.conf`)

无论是什么语句块,自定义的引入语句块总是约定以"`#CUSTOM-CONFIG-START`"开头,并以"`#CUSTOM-CONFIG-END`"结束,方便定位

我们简称这种引入语句块为"**自定义语句块**",并且总是将自定义语句块插入到标记`"#CERT-APPLY-CHECK--START"`前面

---



```nginx
server
{
    listen 80;
    server_name domain1.com www.domain1.com *.domain1.com;
    index index.php index.html index.htm default.php default.htm default.html;
    root /www/wwwroot/cjq/domain1.com/wordpress;
...插入自定义块
    #CUSTOM-CONFIG-START
    include /www/server/nginx/conf/com.conf;
	include /www/server/nginx/conf/limit_rate.conf;
    #CUSTOM-CONFIG-END
    
....其余内容
    #CERT-APPLY-CHECK--START
```

---



现在,我们以建站日期表的方案为例.

扫描表格中距扫描动作发生时达到指定时长`DAYS`(比如14天)的记录(获取对应的域名列表,这意味着将要被检查和操作的网站配置文件数量控制在较新的站中,老站配置文件不用处理,除非有历史遗留站点需要额外处理)

然后,将插入的导入语句修改为仅包含基础公用配置`com.conf`

> 一种简单的方案是直接把原来插入的自定义语句块整个替换为新的语句块,当然,直接将不需要的导入语句替换为空也是可以的

- 如果是2周内的(视为新站),则不对其插入限流配置,仅检查其是否引入了通用安全配置

- 可选操作:如果是2周以上(视为老站),则为其检查是否完整完整引用了通用安全配置和严格限流配置,如果没有,则为其引入(历史遗留站点)

### 自定义nginx配置文件的引入语句块🎈

修改`/www/server/panel/vhost/nginx `目录下的各个网站的配置文件`.conf`

通用安全配置的引入语句(记为块A)

```nginx
    #CUSTOM-CONFIG-START
    include /www/server/nginx/conf/com.conf;
    #CUSTOM-CONFIG-END
```

严格限流配置的引入语句(记为块B)

```nginx
    #CUSTOM-CONFIG-START
    include /www/server/nginx/conf/com.conf;
	include /www/server/nginx/conf/limit_rate.conf;
    #CUSTOM-CONFIG-END
```



### 基本思路

- 检查自定义配置标记`"#CUSTOM"`,如果有,则说明之前插入过相关自定义配置(通常是`com.conf`),例如A或B;
  - 根据配置文件的最后改动时间与2周比较,从而决定将标记的自定义语句块替换为A块或者B块中的1个,比如移除现有块,然后覆盖新块
- 如果没有检测到"`#CUSTOM`"标记,则认为这是一个新建的站点,为其插入语句块A即可

最后,将编写好的处理脚本保存为脚本文件

定期运行此脚本检查各个网站的配置文件,执行恰当的维护

