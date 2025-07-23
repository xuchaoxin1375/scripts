[toc]

## abstract

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
PS> py C:\Users\Administrator\Desktop\localhost\get_htmls_from_urls_multi_thread.py .\L1.txt  -p http://localhost:8800 -o links 
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

