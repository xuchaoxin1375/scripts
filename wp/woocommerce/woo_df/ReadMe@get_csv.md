[toc]



## 采集数据的发布|导出csv文件

为什么导出csv文件? 因为csv比excel更加容易被打开,只需要一个记事本,并且兼容各种数据导入和导出方式,woocommerce自带的上传方式就是csv/txt,脚本方式也容易读取和利用csv中的数据

> 用excel打开csv有破坏文件的风险,可能出现乱码,因此,尽量不要用这类软件,vscode+csv插件或者libreoffice是直接打开csv的推荐选项,但是这些不是必须的(如果是excel文件,则你得安装wps/office,或者上传到在线文档中打开)

- woo_get_csv.py负责的任务,可以检查数据以及导出csv文件


### 相关枚举值或者csv字段名参考

以代码中的定义为准,可能会增加或修改/删除

```python
SKU = "SKU"
NAME = "Name"
CATEGORIES = "Categories"
REGULAR_PRICE = "Regular price"
SALE_PRICE = "Sale price"

IMAGES = "Images"
img_URL = "ImagesUrl"
ATTRIBUTE_VALUES = "Attribute 1 value(s)"
TAGS = "Tags"
DESCRIPTION = "Description"
PAGE_URL = "PageUrl"

ATTRIBUTE_NAME = "Attribute 1 name"
```

## 性能说明

- 通常而言,对于采集得比较规范的数据,导出速度是比较快的,性能随着数据量的增大而衰减的曲线是缓慢的

  - 数据规范的情况下,导出一个站的数据也就3秒左右,50w的数据也不过2分钟内
  - 但是最坏的情况下,5万的数据可能要好几分钟


### 大量正则计算

> 这部分应该不是主要原因

- 如果采集的数据中包含大量不规范内容(主要是属性值,如果采集不当,这部分取值的合法性判断会话比较多的时间)

  - 代码中的统计和分类采用的是字典(哈希表),性能随着数据规模的衰减应该是缓慢的
  - 而更可能导致导出速度慢(时间长),主要耗时逻辑在于采用了正则表达式的相关代码段,正则引擎频繁计算会消耗大量的cpu资源,不仅导出变慢,而且会让计算机变卡顿

- 读者如果发现导出过程中很慢,电脑变卡,既有可能是采集过程中采到了很多非法属性值(如果是一大段源码更是糟糕)

- 另一方面就是产品描述中过滤邮箱和url的正则代码,也可能造成导出事件变长(这个部分的代码容易通过开关控制)

  - ```python
    update_products(self, dbs, process_attribute=False, sku_suffix=None, strict_mode=False)
    ```


### 大量重复的图片名或者图片链接

这部分最有可能会导致哈希表发生哈希冲突导致性能急剧下降!

### 分类分配会占用一些时间

- 合并小分类,分配热销词,也会消耗一些时间

### logging调试性能不佳

相比于print,logging的info,这类调用性能不佳,代码中要合理使用避免被日志信息的计算和存储拖慢速度