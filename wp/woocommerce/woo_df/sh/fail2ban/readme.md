[toc]



## fail2ban自定义配置文件说明

这里有3个目录`action.d`,`filter.d`,`jail.d` ,分被用于存放fail2ban中`action,filter,jail`三中角色的自定义配置文件.

这些目录中的配置文件承担的角色不同,并且**不能独立工作**,需要依赖于fail2ban安装自带的`/etc/fail2ban`目录中内置的基础模板

fail2ban的使用主要是`jail`(监狱,理解为**封禁规则**)的定义

而封禁规则(jail)的定义包括两个部分:

- 定义违禁行为(filter)
- 定义违禁后要执行的制裁操作(action)

### filter

本仓库中存放到配置包括针对防御恶意请求导致的404,499,444响应码的记录,我们对此类ip进行封禁

filter配置比较简单,直接将本仓库预设的几个`filter.d`下的文件复制到`/etc/fail2ban/filter.d/`

如果有的filter配置用不上,也不会影响fail2ban的工作

```bash
cp /www/sh/fail2ban/filter.d/* /etc/fail2ban/filter.d/ -fv
```



### action配置

如果你的网站没有cdn(比如不使用cloudflare代理保护,则配置fail2ban相对简单,这里的配置文件不是针对此类情况编写的)

我们主要讨论对接了cloudflare的情况,这时候需要对接封禁ip的api,才能够使fail2ban封禁生效,首先配置action

fail2ban的模板配置文件为我们考虑到这个需求,在`/etc/fail2ban/action.d`中的众多预设配置中,有一份基础的`cloudflare.conf`

如果你只用到1个cloudflare账号,那么可以在`/etc/fail2ban/action.d`目录中新建一个`cloudflare.local`,然后针对性填写cloudflare的api密钥和账号邮箱

```ini
# cloudflare.local
[Init]

# 不要有多余的引号,这反而会影响配置的解析(填写的时候注意顺序,key和email不要反了)
cftoken = YOUR_CF_API_KEY

cfuser = YOUR_CF_EMAIL



```

这样fail2ban会认识此文件,当你在某个jail节点中的`action`属性取值引用`cloudflare`时,fail2ban能够帮你整合模板自带的`cloudflare.conf`和你创建的`cloudflare.local`,这样就对接了cloudflare指定账号中的api

但是有时候,用户的服务器用了多个cloudflare账号来代理不同批的网站,这样仅仅靠1个`cloudflare.local`就不够用

不过如果要在配置的几个账号间实现的效果类似,则任务也不会太复杂

以上面的相同需求为例(除了要配置多个cloudflare账号这点有所不同)我们仍然借助fail2ban自带的`cloudflare.conf`,不过这次我们将其显式的通过`[INCLUDES]`将其引用.

然后创建几个cloudflare相关的名字的文件,比如`cloudflare1.local`(这里后缀推荐`.local`,表示这个是用户自己创建的配置文件)

比如把下面的内容保存到一个基本文件`cloudflare-basic-action.conf`

```ini
# 引用 fail2ban自带action模板中的cloudflare.conf 文件,并填写你的 Cloudflare API Key 和 Email
[INCLUDES]
before = cloudflare.conf

[Init]

# 不要有多余的引号,这反而会影响配置的解析(填写的时候注意顺序,key和email不要反了)
cftoken = YOUR_CF_API_KEY

cfuser = YOUR_CF_EMAIL



```

例如,你用要配置2个cloudflare账号,则复制上述内容到2个自建文本文件`cloudflare1.local`,`cloudflare2.local`

```bash
#复制命令行参考
$cf_basic='/www/sh/fail2ban/action.d/cloudflare-basic-action.conf'
# 根据需要复制对应数量文件(注意编号)
cp $cf_basic /etc/fail2ban/action.d/cloudflare1.local
cp $cf_basic /etc/fail2ban/action.d/cloudflare2.local
```

> 当然,使用可视化编辑器或工具进行操作也是可以的,注意新文件的文件名编排的可读性

和filter类似,多复制进来的用不到的配置文件一般也不会影响到fail2ban的工作,需要被在jail的action中引用才会工作

此外起作用的前提是分别根据cloudflare账号的密钥和邮箱,替换模板中的占位符

### jail

jail(定义完整的封禁规则)的配置很关键,可以在`/etc/fail2ban/jail.local`中定义你需要的jail(filter和action的自定义组合以及其他控制ip封禁等操作的参数)

不过jail也可以在`/etc/fail2ban/jail.d/`目录下创建单独的`jail`配置文件

本仓库中的`nginx-cf-warn.conf`提供了若干简单的示例`jail`节点配置,但是通常应该根据具体服务器调整必要的内容,尤其是action的引用这一块

