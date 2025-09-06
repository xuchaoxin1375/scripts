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

### 无头浏览器方案(playwright)

- 本文介绍如何采集常见的容易报403错误的网站
  1. 本文暂时仅讨论存在站点地图,但是火车头无法采集站点地图(sitemap)的时候会403的方案(并且这里的方案也不能保证可以解决所有此类型的网站)
  2. 另一类是没有站点地图,而且采集器首页打开就会403,这种难度最大,暂时不讨论
- 通常,防护做得比较好的网站,站点地图也会有,所以本文的情况对于很对403的情况都适用,但是还要注意图片的下载,这种防护比较好的站通常也只是对网站页面防护得比较严格(需要使用浏览器特征的方式访问),而图片资源虽然也有一定的防护,但是防护级别相对没有那么高(否则过多的验证和判断他们网站的加载速度可能会进一步降低),也就是说,图片通常是可以下载的,而且像curl,或者python脚本中的基本请求方法配合代理和UA,一般总能找到下载图片的方案

- 这种比较难采集的站步骤会繁琐一些,但是逻辑还是清晰的,本文尽可能清晰地描述操作步骤,并且举例说明,给出配套的工具
- 暂时以命令行操作为主,流程比较固定

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

### 下载站点地图

被cloudflare保护的网站的站点(不放称这种站为X站)地图(sitemap.xml通常被cloudflare保护,普通的采集器可能仍然无法采集(403错误))

如果测试X站的某个具体的页面可以被无头浏览器下载(比如playwright的脚本下载),那么这个站基本就可确定可以使用此无头浏览器脚本方案来下载网站的网页原码到本地采集(图片一般使用curl+代理+UA模拟可以下载下来,再次也可以用无头浏览器下载)

可以使用命令行`Get-UrlFromSitemap .\total_catalog_products.xml`这个命令将总级站点地图中的各个子集站点地图url抽出来

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

将抽出来的子集站点地图url保存到一个文本文件中,比如`sitemap_urls.txt` (或`sitemap_gz.txt`)

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

```

```



### 解析站点地图中的url

可以用脚本(命令行)解析,或者用采集器来解析

解析各个底层站点地图中包含的产品url,分别保存到.txt文件中(每个txt文件都是包含一系列url的文本文件,每行一个url)

```powershell
PS> $i=1;ls *.xml.*|%{Get-UrlFromSitemap -Path  $_ > "X$i.txt";$i+=1 }
Pattern to match URLs: <loc>(.*?)</loc>
Processing sitemap at path: C:\Users\Administrator\Desktop\localhost\esd.equipment\xmls\media_sitemap_sitemap_esd_de-1-10.xml.html [C:\Users\Administrator\Desktop\localhost\esd.equipment\xmls\media_sitemap_sitemap_esd_de-1-10.xml.html]
Pattern to match URLs: <loc>(.*?)</loc>
Processing sitemap at path: C:\Users\Administrator\Desktop\localhost\esd.equipment\xmls\media_sitemap_sitemap_esd_de-1-11.xml.html [C:\Users\Administrator\Desktop\localhost\esd.equipment\xmls\media_sitemap_sitemap_esd_de-1-11.xml.html]
...
```

### 下载各个网页的url->html文件

将下载保存目录下的所有txt传递给脚本进行下载

```powershell
ls *txt|%{py C:\Users\Administrator\Desktop\localhost\get_htmls_from_urls_multi_thread.py $_  -p http://localhost:8800 -o links -c 2 -d 2-5}
```

### 本地html文件编成xml文件

将下载好的html文件组织到一个文本文件中(编制索引),从而让采集器能够通过对应本地url读取这个索引文本文件,获取所有(本地)产品页链接以进行后续内容采集

```powershell
Get-UrlListFromDir -Path .\part0-17\ -LocTagMode -Hst localhost -Output esd.equipment1.urls.txt
```

## 脚本参数



