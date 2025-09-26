[toc]

## abstract

采集403的网站难度不一

需要注意的是,即便采集了数据,也要考虑图片是否能够下载,尤其是有人机验证的情况下,如果采集可以采集,那么图片下载方面使用采集器下载应该也没问题,但是如果单独下载图片链接,可能会比较麻烦

这种情况下使用火车头下载或许会比较有优势

如果网站的cloudflare的保护不高,即便你当前的网络访问该网站资源需要人机验证,那么考虑可能是ip不干净或被cf列入异常ip,你可以尝试更换代理(ip,特别是小众的代理服务,可能比专门的代理服务的ip更加好用)来访问网站或下载图片,这种方案的成功率不错

### 请求头方案(cookie+ua+refer)

对于403的网站,首先尝试简单的方案,就是cookie方案

部分网站使用cloudflare的防护类型允许通过cookie+ua+referer的方案来获取访问权限

首先使用浏览器访问该网站(目的是进行第一次人机验证),然后打开浏览器开发者工具中的网络(重载网页以获取cookie等数据),复制出来其中的cookie,ua,referer

如果网站配置的cloudflare防护中配置了有效期(比如通过第一次人机验证后,需要再次人机验证的时间间隔)你可能只能采集到一部分数据

> 这种修改UA的方案(修改为google爬虫或者较新的浏览器UA)还可以让火车头通过"浏览器已过期(Your browser is out of date.)"的错误

### 使用curl方案

- 通过伪装普通浏览器来下载网页,总体流程和下面的无头浏览器方案类似



### 无头浏览器方案(playwright)

- 本文介绍如何采集常见的容易报403错误的网站
  1. 本文暂时仅讨论存在站点地图,但是火车头无法采集站点地图(sitemap)的时候会403的方案(并且这里的方案也不能保证可以解决所有此类型的网站)
  2. 另一类是没有站点地图,而且采集器首页打开就会403,这种难度最大,暂时不讨论
- 通常,防护做得比较好的网站,站点地图也会有,所以本文的情况对于很对403的情况都适用,但是还要注意图片的下载,这种防护比较好的站通常也只是对网站页面防护得比较严格(需要使用浏览器特征的方式访问),而图片资源虽然也有一定的防护,但是防护级别相对没有那么高(否则过多的验证和判断他们网站的加载速度可能会进一步降低),也就是说,图片通常是可以下载的,而且像curl,或者python脚本中的基本请求方法配合代理和UA,一般总能找到下载图片的方案

- 这种比较难采集的站步骤会繁琐一些,但是逻辑还是清晰的,本文尽可能清晰地描述操作步骤,并且举例说明,给出配套的工具
- 暂时以命令行操作为主,流程比较固定

### 批量下载xml或gz(sitemap gz)

```powershell
# 配置两个参数
$domain='it.e-mossa.eu';#采集目标站点
$links='$desktop\linkx.txt';#包含gz或.xml链接的文本文件

#调用curl下载gz或xml到指定目录中
$dir=$localhost/$domain; #要下载保存的目录🎈(建议是桌面的localhost目录,可以用$localhost代替)
New-Item -ItemType Directory -Path $dir;
cd $dir;
cat $links |%{curl -O $_ }
```

如果下载的是gz,那么可能是压缩包(也可能不是),如果是压缩包,需要批量压缩

如果curl下载不动gz,则考虑使用浏览器(playwright下载)

#### 批量解压gz

在下载的gz目录`$dir`中执行解压命令(这里使用7z解压,windows10+也自带tar命令,也能打包gzip压缩格式但是无法解压gzip)

可以使`gzip`命令(windows可以下载git获取git中的gzip.exe工具,然后使用`gzip -d -S .gzip`(如果后缀不是`.gz`而是`.gzip`,或者`gzip -d .gz`)

```powershell
ls *gz|%{7z x $_ }
# 移除gz文件
rm *.gz
#将目录汇总的xml文件列入到一个maps.xml中
Get-UrlListFromDir . -hst localhost -LocTagMode > maps.xml



```

根据上述步骤,查看本地localhost的服务中对应链接是否可以访问(如果可以,说明`maps.xml`的url构造正确)

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

### 利用无头浏览器playwright下载

### 下载最深一级的产品站点地图

```powershell
#⚡️[Administrator@CXXUDESK][~\Desktop\localhost\esd.equipment][14:19:34][UP:21.02Days]
PS> python C:\Users\Administrator\Desktop\localhost\get_htmls_from_urls_multi_thread.py .\L1.txt  -p http://localhost:8800 -o links 
开始下载 25 个URL到目录: links\20250723_142014
设置: 超时=30s, 延迟=1.0-3.0s
并发数=3, 重试次数=3, 浏览器窗口模式=隐藏
代理配置: http://localhost:8800
[INIT] 总URL数: 25, 待下载: 25, 已下载: 0
[CONFIG] 使用代理服务器: http://localhost:8800
[1/25] 成功下载: https://esd.equipment/media/sitemap/sitemap_esd_de-1-2.xml -> links\20250723_142014\esd.equipment\media_sitemap_sitemap_esd_de-1-2.xml.html
[2/25] 成功下载: https://esd.equipment/media/sitemap/sitemap_esd_de-1-3.xml -> links\20250723_142014\esd.equipment\media_sitemap_sitemap_esd_de-1-3.xml.html
[3/25] 成功下载: https://esd.equipment/media/sitemap/sitemap_esd_de-1-4.xml -> links\20250723_142014\esd.equipment\media_sitemap_sitemap_esd_de-1-4.xml.html
[4/25] 成功下载: https://esd.equipment/media/sitemap/sitemap_esd_de-1-5.xml -> links\20250723_142014\esd.equipment\media_sitemap_sitemap_esd_de-1-5.xml.html
[5/25] 成功下载: https://esd.equipment/media/sitemap/sitemap_esd_de-1-6.xml -> links\20250723_142014\esd.equipment\media_sitemap_sitemap_esd_de-1-6.xml.html
[6/25] 成功下载: https://esd.equipment/media/sitemap/sitemap_esd_de-1-7.xml -> links\20250723_142014\esd.equipment\media_sitemap_sitemap_esd_de-1-7.xml.html
[7/25] 成功下载: https://esd.equipment/media/sitemap/sitemap_esd_de-1-8.xml -> links\20250723_142014\esd.equipment\media_sitemap_sitemap_esd_de-1-8.xml.html
```

## 下载站点地图🎈

被cloudflare保护的网站的站点(不妨称这种站为X站)地图(sitemap.xml通常被cloudflare保护,普通的采集器可能仍然无法采集(403错误))

如果测试X站的某个具体的页面可以被无头浏览器下载(比如playwright的脚本下载),那么这个站基本就可确定可以使用此无头浏览器脚本方案来下载网站的网页原码到本地采集(图片一般使用curl+代理+UA模拟可以下载下来,再次也可以用无头浏览器下载)

### 站点地图的层次

不同网站站点地图层次不一,但是做了反爬的站一般是大站,往往有2级甚至更多的站点地图层次

如果只有一级,可以跳过L1.xml或L1.urls的获取,直接进行获取最深一级站点地图

### 下载或保存第一级站点地图(L1.xml和L1.urls)

例如某个具有多级站点地图的网站www.speedingparts.de,其第一级站点地图是一些gz链接

```http
https://www.speedingparts.de/sitemap.xml
```

浏览器打开第一级站点地图,然后保存到本地,比如保存为桌面的`L1.xml`或者桌面中`Localhost`目录下的`L1.xml`

然后尝试使用`Get-UrlFromSitemap`命令尝试解析出来其中的url,这个命令将总级站点地图中的各个子集站点地图url抽出来

```powershell
PS> Get-UrlFromSitemap C:\Users\Administrator\Desktop\localhost\L1.xml
Pattern to match URLs: <loc>(.*?)</loc>
Processing sitemap at path: C:\Users\Administrator\Desktop\localhost\L1.xml [C:\Users\Administrator\Desktop\localhost\L1.xml]
https://www.speedingparts.de/sitemap_categories_de.1.xml.gz
https://www.speedingparts.de/sitemap_galleries_de.1.xml.gz
https://www.speedingparts.de/sitemap_products_de.1.xml.gz
https://www.speedingparts.de/sitemap_products_de.2.xml.gz
https://www.speedingparts.de/sitemap_products_de.3.xml.gz
...
```

又比如

```powershell
PS> Get-UrlFromSitemap .\catalog.xml
Pattern to match URLs: <loc>(.*?)</loc>
Processing sitemap at path: .\catalog.xml [C:\Users\Administrator\Desktop\localhost\0822\catalog.xml]
https://www.trodo.it/site_map/sitemap_prod_1.xml
https://www.trodo.it/site_map/sitemap_prod_10.xml
https://www.trodo.it/site_map/sitemap_prod_100.xml
https://www.trodo.it/site_map/sitemap_prod_101.xml
....
#也有可能是一些.gz文件的链接,同样下载下来
```

但是不一定能够顺利解析出来url,如果不行,可以通过火车头访问localhost本地站点中的L1.xml文件采集这些一级url,然后选择导出url

如果命令行解析成功,则可以通过`> L1.urls`保存这些解析出来的url

```powershell
Get-UrlFromSitemap C:\Users\Administrator\Desktop\localhost\L1.xml > $localhost\L1.urls
```

然后根据需要可以剔除或保留其中我们认为和产品也相关的站点地图,其他无关的可以删除

从一级url(L1.urls)中的链接下载站点子集地图(更具体的站点地图)

#### 使用curl下载🎈

```powershell
# 配置两个参数
$domain='www.speedingparts.de';#采集目标站点
$links="$localhost\L1.urls";#包含gz或.xml链接的文本文件

#调用curl下载gz或xml到指定目录中
$dir="$localhost\$domain"; #要下载保存的目录🎈(建议是桌面的localhost目录,可以用$localhost代替)
New-Item -ItemType Directory -Path $dir -ErrorAction SilentlyContinue ;

cd $dir;
cat $links |%{curl -L -O $_ -A $agent} # 使用-L选项追踪301等跳转,提高抓取能力;使用-A 选项提供伪装用户的浏览器UA,可以绕过一些基础的反爬设置

```



#### 使用playwright下载

下载这些站点地图(或其压缩包),和下载产品网页类似,也可以调用浏览器下载站点地图文件或其压缩包(共用一个下载脚本)

```powershell
PS C:\Users\Administrator\Desktop\localhost> py .\get_htmls_from_urls_multi_thread.py .\sitemap_urls.txt -p http://localhost:8800 -c 5   
开始下载 106 个URL到目录: downloads\20250822_211603
设置: 超时=30s, 延迟=1.0-3.0s
并发数=5, 重试次数=3, 浏览器窗口模式=隐藏  
代理配置: http://localhost:8800
[INIT] 总URL数: 106, 待下载: 106, 已下载: 0
[CONFIG] 使用代理服务器: http://localhost:8800
[2/106] 成功下载: https://www.trodo.it/site_map/sitemap_prod_10.xml -> downloads\20250822_211603\www.trodo.it\site_map_sitemap_prod_10.xml.html
[5/106] 成功下载: https://www.trodo.it/site_map/sitemap_prod_102.xml -> downloads\20250822_211603\www.trodo.it\site_map_sitemap_prod_102.xml.html
[3/106] 成功下载: https://www.trodo.it/site_map/sitemap_prod_100.xml -> downloads\20250822_211603\www.trodo.it\site_map_sitemap_prod_100.xml.html
[4/106] 成功下载: https://www.trodo.it/site_map/sitemap_prod_101.xml -> downloads\20250822_211603\www.trodo.it\site_map_sitemap_prod_101.xml.html
[1/106] 成功下载: https://www.trodo.it/site_map/sitemap_prod_1.xml -> downloads\20250822_211603\www.trodo.it\site_map_sitemap_prod_1.xml.html
[9/106] 成功下载: https://www.trodo.it/site_map/sitemap_prod_106.xml -> downloads\20250822_211603\www.trodo.it\site_map_sitemap_prod_106.xml.html
[6/106] 成功下载: https://www.trodo.it/site_map/sitemap_prod_103.xml -> downloads\20250822_211603\www.trodo.it\site_map_sitemap_prod_103.xml.html
```





### 解析各个子级站点地图中的url

可以用脚本(命令行)解析,或者用采集器来解析

> 和上一节类似,如果`Get-UrlfromSitemap`解析不出来或者报错,可以用采集器来解析并导出

解析各个底层站点地图中包含的产品url,分别保存到.txt文件中(每个txt文件都是包含一系列url的文本文件,每行一个url)

首先将工作目录cd到站点地图所在的目录,否则找不到文件

> 例如上例中`~\Desktop\localhost\www.speedingparts.de`

```powershell
# 首先将工作目录cd到站点地图所在的目录,否则找不到文件
$sitemap_pattern = '*xml*' #可以根据你下载的站点地图文件名更改

$i = 1; 
Get-ChildItem $sitemap_pattern| ForEach-Object {
    Get-UrlFromSitemap -Path $_ > "X$i.txt"; 
    $i += 1 
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

## 下载产品页html

各个网页的url->html文件

### curl

这种方案下载能力相对弱一些,但是操作简单一些

```powershell
ls *.txt |%{Get-HtmlFromLinks -Path $_ -OutputDir htmls -Threads 10 }
```

> 暂时不支持断点进度恢复,重新下载会丢失进度!

### python调用playwright方案下载

如果curl方案下不动,则可以尝试无头浏览器方案

将下载保存目录下的所有txt传递给脚本进行下载

```powershell
ls *txt|%{py C:\Users\Administrator\Desktop\localhost\get_htmls_from_urls_multi_thread.py $_  -p http://localhost:8800 -o links -c 2 -d 2-5}
```

## 本地html文件编成xml文件(local_urls.txt)

将下载好的html文件组织到一个文本文件中(编制索引),从而让采集器能够通过对应本地url读取这个索引文本文件,获取所有(本地)产品页链接以进行后续内容采集

下面以前面下载的网站`www.speedingparts.de`为例,假设html文件都保存在`$localhost\www.speedingparts.de\htmls`目录下

在编制成本地网站(localhost)的url前,我们可以先运行试探命令,构造出来的url看看是否符合需要(注意最后的`-Preview`选项)

```powershell
Get-UrlsListFileFromDir -Path $localhost\www.speedingparts.de\htmls -LocTagMode -Hst localhost -Output $localhost/www.speedingparts.de/local_urls.txt
```

得到的预览格式比如`预览url格式: <loc>http://localhost:80/www.speedingparts.de/htmls/-10-female-o-ring-aluminum-weld-bung.html-202509242047-1952.html</loc>`,检查并访问其中的http链接,如果路径正确就可以去掉`-Preview`参数正式生成

否则说明路径片段有误,需要手动指定`-HtmlDirSegment`参数指定新的url中间片段.

例如指定中间路径为`CustomDirSeg/htmls-dir`,效果如下

```powershell
Get-UrlsListFileFromDir -Path $localhost\www.speedingparts.de\htmls -LocTagMode -Hst localhost -Output $localhost/www.speedingparts.de/local_urls.txt -htmlDirSegment CustomDirSeg/htmls-dir -Preview
预览url格式: <loc>http://localhost:80/CustomDirSeg/htmls-dir/-10-female-o-ring-aluminum-weld-bung.html-202509242047-1952.html</loc>
```

最理想的情况下是该命令正确猜测你的html文件存放路径,就不需要指定`-HtmlDirSegment`参数

## 源码和url匹配

下载到本地的源码使用浏览器预览往往样式丢失,排版不如原网站渲染出来的直观

因此通常我先打开源站的某个一个产品页,然后拷贝该页面的链接中的尾部(url中的最后一个`/`之后的部分)

然后vscode打开保存html文件的目录,将这个名字到`local_urls.txt`中搜索,找到本地版本的url,在采集器中采集此产品

## 脚本参数



