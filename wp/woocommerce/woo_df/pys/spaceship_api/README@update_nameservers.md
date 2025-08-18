[toc]



## 用法说明

### spaceship鉴权配置文件说明

json中配置spaceship的密钥,以及你的常用或默认域名服务器,比如cloudflare提供的域名服务器,比如`jeremy.ns.cloudflare.com`,`aitana.ns.cloudflare.com`,一般填写两个作为默认

```json
{
    "api_key": "your_short_api_key",
    "api_secret": "your_secret_long_string",
    "nameserver1": "your_ns1",
    "nameserver2": "your_ns2",
    "take": 100,
    "skip": 0,
    "order_by": "expirationDate"
}
```

### 配置需要更改域名服务器的文件

这种文件(表格形式的数据)可以采用多种格式,比如excel,csv,conf,txt甚至可以省略后缀名

其中csv和excel都可以设置表头,约定为`domain`,`nameserver1`,`nameserver2`共3列,这种表格是完整和准确的域名配置表格

此外,可以用普通文本文件(一行一个域名,作为`domain`列),然后从上述json文件中读取默认nameservers,分别设置为`nameserver1`,`nameserver2`

#### 专用格式域名配置文件

以csv为例(csv文件可以用office/wps表格程序,通常是excel打开和编辑,可以得到直观的表格视图,由于都是英文字符,一般不用担心乱码)

也可以用vscode配合CSV Edit插件来查看和编辑,设置用记事本也可以编辑

```csv
domain,nameserver1,nameserver2
stad.com,aitana.ns.cloudflare.com,jeremy.ns.cloudflare.com 
mar.com,,
art.com,,

```

等价数据在excel中形如

| domain   | nameserver1              | nameserver2              |
| -------- | ------------------------ | ------------------------ |
| stad.com | aitana.ns.cloudflare.com | jeremy.ns.cloudflare.com |
| mar.com  |                          |                          |
| art.com  |                          |                          |

空的单元格的取值nameservers将从json配置文件中读取默认值

此外,还允许更加一般的文本文件格式

```conf
stadtmarkt24.com     ... ...
markenmarktde.com ... ...
artisan-pro24.com ...
```

甚至

```
https://hausdeh.com	zw	2.de
https://gswahl.com	zw	2.de
https://den.com	xx	2.de
```

总之,只要第一列是url或者域名(主域名.顶级域名)的格式即可,带上协议名也是允许的,`update_nameservers.py`都能够正确解析出域名列,填充到`domain`列中,然后根据json中配置的默认值,构造出完整的dataframe对象

## 执行命令行示例用例🎈

```powershell
python .\update_nameservers.py -d C:\Users\Administrator\Desktop\table.conf -c C:\sites\wp_sites\spaceship_config.json  
```

可以配置默认路径值从而简化命令行,从而缩短成无参数调用

```
PS> py .\update_nameservers.py 
```

执行输出示例

```bash
#⚡️[Administrator@CXXUDESK][C:\repos\scripts\wp\woocommerce\woo_df\pys\spaceship_api][22:12:58][UP:25.35Days]
PS> python .\update_nameservers.py -d C:\Users\Administrator\Desktop\table.conf -c C:\sites\wp_sites\spaceship_config.json   
               domain               nameserver1               nameserver2
0     hsch.com  aitana.ns.cloudflare.com  jeremy.ns.cloudflare.com
1     guwahl.com  aitana.ns.cloudflare.com  jeremy.ns.cloudflare.com
2     daren.com  aitana.ns.cloudflare.com  jeremy.ns.cloudflare.com
3   luarts.com  aitana.ns.cloudflare.com  jeremy.ns.cloudflare.com
4      aupfr.com  aitana.ns.cloudflare.com  jeremy.ns.cloudflare.com
5        spofr.com  aitana.ns.cloudflare.com  jeremy.ns.cloudflare.com
6   arpro24.com  aitana.ns.cloudflare.com  jeremy.ns.cloudflare.com
7  oce.com  aitana.ns.cloudflare.com  jeremy.ns.cloudflare.com

hsch.com after {'provider': 'custom', 'hosts': ['aitana.ns.cloudflare.com', 'jeremy.ns.cloudflare.com']}
guwahl.com after {'provider': 'custom', 'hosts': ['aitana.ns.cloudflare.com', 'jeremy.ns.cloudflare.com']}
...
```

或者配置默认值后的无参数调用(输出是一样的)

```powershell
#⚡️[Administrator@CXXUDESK][C:\repos\scripts\wp\woocommerce\woo_df\pys\spaceship_api][22:35:36][UP:25.36Days]
PS> py .\update_nameservers.py 
...
```

