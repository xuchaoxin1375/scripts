[toc]

## 批量下载xml或gz(sitemap gz)👺

有两类方案,或者混合使用两种方案

## 可视化方案

- 利用采集器将站点地图中的连接采集下来(如果有多语言的记得过滤出来产品相关的链接(比如包含Product的链接))
- 导出采集器中采集到的网址到一个文本文件
- 复制出来文本文件中的链接,然后有若干方案下载
  - 使用motrix或者freedownloadmanager(fdm),可以批量下载或者从文件导入链接下载
  - 用浏览器插件(随便一个可以网页或https链接批量打开/多开的插件),将文本文件中的链接粘贴到插件中打开这些链接,浏览器就会下载这些压缩包(比如gzip,gz等)
- 然后将这些文件放到一个统一的目录中,比如用被采集网站的域名命名,然后用7z批量打开和解压

## 命令行方案及其相关命令

批量下载(获取url中的资源,比如下载html或则文件,gz文件等)

### 从站点地图(xml)抽取url

包括多级站点地图,比如抽取gz资源的url,或子级站点地图url

> 也可以用采集器可视化操作提取url.

方案有两类:可以用脚本(命令行)解析(倾向于不同的xml抽取到各自对应的url集合文件txt中),或者用采集器来解析(倾向于聚合到同一个txt)

这里通常用shell方案,用不上playwright,因为此步骤要被解析的内容已经下载到本地了

抽出的url列表保存到文本文件,后缀可以命名为`.urls`或`.urls.txt`,如果是gz文件的url,可以更具体为`.gz.urls`或`.gz.urls.txt`

> 和上一节类似,如果命令`Get-UrlfromSitemap`解析不出来或者报错,可以用采集器来解析并导出

解析各个底层站点地图中包含的产品url,分别保存到`.txt`文件中(每个txt文件都是包含一系列url的文本文件,每行一个url)

**首先将工作目录cd到站点地图所在的目录**,否则找不到文件

> 例:`~\Desktop\localhost\www.speedingparts.de`

```powershell
# 首先将工作目录cd到站点地图所在的目录,否则找不到文件
$sitemap_pattern = '*xml*' #可选修改:可以根据你下载的站点地图文件名更改
```



#### 单个抽取

```powershell
Get-UrlFromSitemap -Path .\toms.xml > toms.gz.urls

```

#### 批量从xml文件中抽取url



```powershell
# 首先将工作目录cd到站点地图所在的目录,否则找不到文件或者文件错误
$sitemap_pattern = '*xml*' #可选修改:可以根据你下载的站点地图文件名更改

$i = 1; 
Get-ChildItem $sitemap_pattern| ForEach-Object {
	$url_file="X$i.txt"
	Get-UrlFromSitemap -Path $_ > $url_file ; 
    $i += 1 
    $path= gi $url_file
    write-host $path.fullname -ForegroundColor Green
}
```

例如运行后:

```powershell
#⚡️[Administrator@CXXUDESK][~\Desktop\localhost\www.speedingparts.de][16:06:44][UP:1.07Days]
PS> Get-ChildItem $sitemap_pattern| ForEach-Object {
>>     Get-UrlFromSitemap -Path $_ > "X$i.txt";
>>     $i += 1
>> }
Pattern to match URLs: <loc>(.*?)</loc>
Processing sitemap at path: C:\Users\Administrator\Desktop\localhost\www.speedingparts.de\sitemap_categories_de.1.xml.gz [C:\Users\Administrator\Desktop\localhost\www.speedingparts.de\sitemap_categories_de.1.xml.gz]
Pattern to match URLs: <loc>(.*?)</loc>
Processing sitemap at path: C:\Users\Administrator\Desktop\localhost\www.speedingparts.de\sitemap_galleries_de.1.xml.gz [C:\Users\Administrator\Desktop\localhost\www.speedingparts.de\sitemap_galleries_de.1.xml.gz]
Pattern to match URLs: <loc>(.*?)</loc>
Processing sitemap at path: C:\Users\Administrator\Desktop\localhost\www.speedingparts.de\sitemap_manufacturers.1.xml.gz [C:\Users\Administrator\Desktop\localhost\www.speedingparts.de\sitemap_manufacturers.1.xml.gz]
Pattern to match URLs: <loc>(.*?)</loc>
Processing sitemap at path: C:\Users\Administrator\Desktop\localhost\www.speedingparts.de\sitemap_products_de.1.xml.gz
```

在下载并解析完成后,工作目录中会有一些`.txt`文件,里面包含的是产品页链接的话,就可以进行下一步操作

### 批量下载gz或.xml文件的url资源

方案有2种:

使用curl下载或无头浏览器下载(比如playwright)

#### curl方案

```bash
# 配置两个参数
$domain='toms';#采集目标站点
$links="$localhost\toms.gz.urls";#包含gz或.xml链接的文本文件

#调用curl下载gz或xml到指定目录中
$dir="$localhost\$domain"; #要下载保存的目录🎈(建议是桌面的localhost目录,可以用$localhost代替)
New-Item -ItemType Directory -Path $dir -ErrorAction SilentlyContinue ;

cd $dir;
cat $links |%{curl -L -k -A $agent  -O $_ } # 使用-L选项追踪301等跳转,提高抓取能力;使用-A 选项提供伪装用户的浏览器UA,可以绕过一些基础的反爬设置

```

配置代理:可以使用curl的`-x`选项指定,例如

```powershell
#
cat $links |%{curl -L -k -A $agent -x http://localhost:10808  -O $_ }
```

或者使用`set-proxy -port 10808`这种方式指定代理,然后重新尝试

如果下载的是gz,那么可能是压缩包(也可能不是),如果是压缩包,需要批量压缩

如果curl下载不动gz,则考虑使用浏览器(playwright下载)

#### playwright

```powershell
$domain='demo.com' #修改为待采集网站的域名
ls *txt|%{python $localhost/get_html.py $_ -o $domain/htmls -p $localhost\proxies.conf --allow-direct -c 3 -r 1 -t 120 -d 1-3 }
```

例如

```powershell
$domain='nissanwholesaledirect.com'
ls nissan*txt|%{python $localhost/get_html.py $_ -o $domain/htmls -p $localhost\proxies.conf --allow-direct -c 3 -r 1 -t 120 -d 1-3 }
```



### 批量解压

使用命令:`Expand-GzFile`(调用`7z x`解压)

用例

```powershell
ls *gz|Expand-GzFile
# 查看当前目录
ls
# 移除gz文件
rm *gz -confirm
# 查看最终结果
ls 
```



批量解压gz:

> 在下载的gz目录`$dir`中执行解压命令(这里使用7z解压,windows10+也自带tar命令,也能打包gzip压缩格式但是无法解压gzip)
>
> 可以使`gzip`命令(windows可以下载git获取git中的gzip.exe工具,然后使用`gzip -d -S .gzip`(如果后缀不是`.gz`而是`.gzip`,或者`gzip -d .gz`)
>

解压完毕后得到一系列`.xml`文件,从这些文件中提取url(其他章节介绍过)



### 创建本地html文件的建议站点地图

使用`Get-UrlsListFileFromDir`命令将指定目录(路径)下的所有文件组织成一份本地的站点地图`sitemap.txt`便于采集器采集

用例:(指定)

```bash
Get-UrlsListFileFromDir -Path ./ -LocTagMode  -Output sitemap.txt
```

根据上述步骤,查看本地localhost的服务中对应链接是否可以访问(如果可以,说明`maps.xml`的url构造正确)

案例:

```powershell
#⚡️[Administrator@CXXUDESK][~\Desktop\localhost\toms][11:16:45] PS >
 Get-UrlsListFileFromDir -Path . -LocTagMode -htmlDirSegment toms -Output $localhost/toms.xmls.txt
VERBOSE: Output to file: C:\Users\Administrator\Desktop/localhost/toms.xmls.txt
访问本地站点地图链接形如: http://localhost:80/toms.xmls.txt
VERBOSE: Preview: <loc>http://localhost:80/toms/freshop_sitemap1.xml</loc>
<loc>http://localhost:80/toms/freshop_sitemap2.xml</loc>
<loc>http://localhost:80/toms/freshop_sitemap3.xml</loc>
```

该命令会提示生成的本地站点地图链接,例如上面的

```powershell
访问本地站点地图链接形如: http://localhost:80/toms.xmls.txt
```

访问此链接,如果显示出正确内容,就可以尝试采集了

### 测试采集

然后再检查`maps.xml`中的`<loc>`标签中的链接是否也可以访问(如果不能访问在检查`localhost`中对应的目录和站点地图文件`xml`文件路径是否正确)

```powershell
PS> curl http://localhost/it.e-mossa.eu/maps.xml
<loc>http://localhost:80/it.e-mossa.eu/maps.xml</loc>
<loc>http://localhost:80/it.e-mossa.eu/sitemap-https-2-1.xml</loc>
<loc>http://localhost:80/it.e-mossa.eu/sitemap-https-2-10.xml</loc>
<loc>http://localhost:80/it.e-mossa.eu/sitemap-https-2-2.xml</loc>
<loc>http://localhost:80/it.e-mossa.eu/sitemap-https-2-3.xml</loc>
<loc>http://localhost:80/it.e-mossa.eu/sitemap-https-2-4.xml</loc>
<loc>http://localhost:80/it.e-mossa.eu/sitemap-https-2-5.xml</loc>
<loc>http://localhost:80/it.e-mossa.eu/sitemap-https-2-6.xml</loc>
<loc>http://localhost:80/it.e-mossa.eu/sitemap-https-2-7.xml</loc>
<loc>http://localhost:80/it.e-mossa.eu/sitemap-https-2-8.xml</loc>
```

```powershell
curl http://localhost/it.e-mossa.eu/sitemap-https-2-1.xml
```

如果也有正常原码输出说明本地可以采集了,根据链接`http://localhost/it.e-mossa.eu/maps.xml`采集就行



## 完整案例

```powershell

# [Administrator@CXXUDESK][~\Desktop\localhost][11:47:40][UP:4.66Days]
PS> Get-UrlFromSitemap -Path .\fahrwerk-sitemap.xml > fahr.gz.urls
Pattern to match URLs: <loc>(.*?)</loc>
Processing sitemap at path: .\fahrwerk-sitemap.xml [C:\Users\Administrator\Desktop\localhost\fahrwerk-sitemap.xml]

# [Administrator@CXXUDESK][~\Desktop\localhost][11:48:14][UP:4.66Days]
PS> Get-SourceFromLinksList -Domain fahr.de -LinksFile .\fahr.gz.urls
正在下载: https://www.fahrwerkonline.de/sitemap/salesChannel-9d0e95af9be5423a91abe77013aecc49-2fbb5fe2e29a4d70aa5854ce7ce3e20b/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-4.xml.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  590k  100  590k    0     0   440k      0  0:00:01  0:00:01 --:--:--  440k
正在下载: https://www.fahrwerkonline.de/sitemap/salesChannel-9d0e95af9be5423a91abe77013aecc49-2fbb5fe2e29a4d70aa5854ce7ce3e20b/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-5.xml.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  686k  100  686k    0     0   511k      0  0:00:01  0:00:01 --:--:--  511k
正在下载: https://www.fahrwerkonline.de/sitemap/salesChannel-9d0e95af9be5423a91abe77013aecc49-2fbb5fe2e29a4d70aa5854ce7ce3e20b/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-7.xml.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  843k  100  843k    0     0   568k      0  0:00:01  0:00:01 --:--:--  569k
正在下载: https://www.fahrwerkonline.de/sitemap/salesChannel-9d0e95af9be5423a91abe77013aecc49-2fbb5fe2e29a4d70aa5854ce7ce3e20b/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-8.xml.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  543k  100  543k    0     0   409k      0  0:00:01  0:00:01 --:--:--  410k
正在下载: https://www.fahrwerkonline.de/sitemap/salesChannel-9d0e95af9be5423a91abe77013aecc49-2fbb5fe2e29a4d70aa5854ce7ce3e20b/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-6.xml.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  857k  100  857k    0     0   566k      0  0:00:01  0:00:01 --:--:--  566k
正在下载: https://www.fahrwerkonline.de/sitemap/salesChannel-9d0e95af9be5423a91abe77013aecc49-2fbb5fe2e29a4d70aa5854ce7ce3e20b/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-2.xml.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  364k  100  364k    0     0   284k      0  0:00:01  0:00:01 --:--:--  284k
正在下载: https://www.fahrwerkonline.de/sitemap/salesChannel-9d0e95af9be5423a91abe77013aecc49-2fbb5fe2e29a4d70aa5854ce7ce3e20b/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-1.xml.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  343k  100  343k    0     0   264k      0  0:00:01  0:00:01 --:--:--  264k
正在下载: https://www.fahrwerkonline.de/sitemap/salesChannel-9d0e95af9be5423a91abe77013aecc49-2fbb5fe2e29a4d70aa5854ce7ce3e20b/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-3.xml.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100  490k  100  490k    0     0   327k      0  0:00:01  0:00:01 --:--:--  328k

# [Administrator@CXXUDESK][~\Desktop\localhost][11:48:42][UP:4.66Days]
PS> cd .\fahr.de\

# [Administrator@CXXUDESK][~\Desktop\localhost\fahr.de][11:48:50][UP:4.66Days]
PS> Expand-GzFile -Path "*.gz"
VERBOSE: 成功解压: C:\Users\Administrator\Desktop\localhost\fahr.de\9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-1.xml
VERBOSE: 成功解压: C:\Users\Administrator\Desktop\localhost\fahr.de\9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-2.xml
VERBOSE: 成功解压: C:\Users\Administrator\Desktop\localhost\fahr.de\9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-3.xml
VERBOSE: 成功解压: C:\Users\Administrator\Desktop\localhost\fahr.de\9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-4.xml
VERBOSE: 成功解压: C:\Users\Administrator\Desktop\localhost\fahr.de\9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-5.xml
VERBOSE: 成功解压: C:\Users\Administrator\Desktop\localhost\fahr.de\9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-6.xml
VERBOSE: 成功解压: C:\Users\Administrator\Desktop\localhost\fahr.de\9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-7.xml
VERBOSE: 成功解压: C:\Users\Administrator\Desktop\localhost\fahr.de\9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-8.xml
# 移除gz文件
# [Administrator@CXXUDESK][~\Desktop\localhost\fahr.de][11:48:59][UP:4.66Days]
PS> rm *gz
# 查看结果
# [Administrator@CXXUDESK][~\Desktop\localhost\fahr.de][11:49:04][UP:4.66Days]
PS> ls

    Directory: C:\Users\Administrator\Desktop\localhost\fahr.de

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a---           2025/10/1    11:48       10357415 9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-
                                                  1.xml
-a---           2025/10/1    11:48       10534082 9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-
                                                  2.xml
-a---           2025/10/1    11:48       11431017 9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-
                                                  3.xml
-a---           2025/10/1    11:48       12100888 9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-
                                                  4.xml
-a---           2025/10/1    11:48       12417878 9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-
                                                  5.xml
-a---           2025/10/1    11:48       13333224 9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-
                                                  6.xml
-a---           2025/10/1    11:48       14053930 9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-
                                                  7.xml
-a---           2025/10/1    11:48        9320392 9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-
                                                  8.xml
```

编制本地站点地图

```bash
# [Administrator@CXXUDESK][~\Desktop\localhost\fahr.de][11:52:05][UP:4.66Days]
PS> Get-UrlsListFileFromDir -Path ./ -LocTagMode -Preview
预览url格式: <loc>http://localhost:80/fahr.de/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-1.xml</loc>

# [Administrator@CXXUDESK][~\Desktop\localhost\fahr.de][11:52:40][UP:4.66Days]
PS> Get-UrlsListFileFromDir -Path ./ -LocTagMode
VERBOSE: Output to file: ./../fahr.de.txt #注意输出文件的路径
VERBOSE: Preview: <loc>http://localhost:80/fahr.de/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-1.xml</loc>
<loc>http://localhost:80/fahr.de/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-2.xml</loc>
<loc>http://localhost:80/fahr.de/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-3.xml</loc>
<loc>http://localhost:80/fahr.de/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-4.xml</loc>
<loc>http://localhost:80/fahr.de/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-5.xml</loc>
<loc>http://localhost:80/fahr.de/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-6.xml</loc>
<loc>http://localhost:80/fahr.de/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-7.xml</loc>
<loc>http://localhost:80/fahr.de/9d0e95af9be5423a91abe77013aecc49-sitemap-www-fahrwerkonline-de-8.xml</loc>
```

现在,将`http://localhost/fahr.de.txt`这个链接填入采集器汇总,采集本地站中的第一级站点地图

## 后续下一步

获得了可以本地采集的站点地图(可以采集到所有产品链接),下一步另见它文(403类型采集)

