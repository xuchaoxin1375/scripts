[toc]



## asbtact



## 配置本地shopify中转站点

小皮新建一个空站,比如`wp.test`(推荐用这个名字,可以避免修改的麻烦),然后记住这个站的路径(建议发送快捷方式到桌面)

### 配置脚本

修改`config.py`中的目录为你自己的目录

### 配置domains.xlsx

利用shopify检测脚本将一组网站中的shopify找出,然后整理到domains.xlsx中

使用get_shopify_table.py(todo)将拿到的一组数据的表格处理转换得到一个domains.xlsx,包含4列内容(主要关心前两列:site,folder)

## 检查某个json采集对应的原页面链接

- 这种方式采集内容想要找到原链接不是很方便,可以借助google来找
  - 搜索关键:`域名`+`产品名称或图片名称`

