[toc]



## 采集数据的发布|导出csv文件

为什么导出csv文件? 因为csv比excel更加容易被打开,只需要一个记事本,并且兼容各种数据导入和导出方式,woocommerce自带的上传方式就是csv/txt,脚本方式也容易读取和利用csv中的数据

> 用excel打开csv有破坏文件的风险,可能出现乱码,因此,尽量不要用这类软件,vscode+csv插件或者libreoffice是直接打开csv的推荐选项,但是这些不是必须的(如果是excel文件,则你得安装wps/office,或者上传到在线文档中打开)

`woo_get_csv.py`负责的任务,可以检查数据以及导出csv文件

### db3数据库文件中的重点字段

1. 产品名称

2. 产品价格

3. 产品图片

4. 产品描述

5. 产品面包屑

6. 品牌

7. 产品型号

8. 属性值1

9. PageUrl


#### 热销分类词

产品分类根据经验来看不是那么重要,但是没有分类会让网站也没显得单调

在导出时(woo_get_csv.py),可以指定一个语言/国家参数,会自动为没有分类的产品分配一个通用分类名

以美国为例,可设置`New Arrival`,`Best Sellers`,`Promotion`

```python
    """
    US = [
        "New Arrival",
        "Best Sellers",
        "Promotion",
        # "Flash Deal",
        # "Best Value",
        # "Editor's Pick",
        # "Today’s Special",
    ]
    UK = [
        "New In",
        "Best Seller",
        "Special Offer",
        # "Flash Sale",
        # "Great Value",
        # "Top Picks",
        # "Today’s Deal",
    ]
    IT = [
        "Novità",
        "Più venduti",
        "Offerta speciale",
        # "Offerta lampo",
        # "Miglior valore",
        # "Scelti per te",
        # "Offerta del giorno",
    ]
    DE = [
        "Neuheiten",
        "Bestseller",
        "Sonderangebot",
        # "Blitzangebot",
        # "Top Preis",
        # "Empfehlung",
        # "Angebot des Tages",
    ]
    ES = [
        "Novedades",
        "Más vendido",
        "Promoción",
        # "Oferta flash",
        # "Mejor valor",
        # "Selección",
        # "Oferta del día",
    ]
    FR = [
        "Nouveautés",
        "Meilleures ventes",
        "Promotion",
        # "Vente flash",
        # "Bon plan",
        # "Notre sélection",
        # "Offre du jour",
    ]
```




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



## 去重算法细节说明

> 使用pandas库可以轻松完成去重复任务,下面是手工设计去重代码的方案说明

检查**产品图片**(通常指的是**图片链接(url)**),方便起见,下面统称**图片**)和**产品名**同时重复的情况下,移除掉重复的产品的算法中我们使用字典(或其子类)这类数据结构来实现(为了便于讨论,称此结构的实例为`d`)

> 这数据结构的帮助下，我们可以快速统计/判断一个产品的图片是否已经出现过
>

假设数据库中有图片相同的几个产品数据,这几个产品的名称分被为(A,B,B,C,A),方便起见,分别称第1个和第2个B为$B_{1},B_{2}$

这里有两个名为B的产品,它们此时被认为是同一个产品,我们的理想结果是去除掉第2或第3个产品(只保留其中1个)

---

在遍历并统计产品数据的时候,字典键值对(key-value)中的`key`是图片url(记为`x`),`value`应该存储什么?

如果仅存储**产品名**,是不行的,例如先遍历图片链接为`x`的产品A,然后比较同图片的产品$B_{1}$会顺利保留下来(因为A和B不同)

遍历到$B_{2}$时,`d[x]`的取值仍然是A,比较$B_{2}$时会认为$B_{2}$和A不同,就保留产品$B_{2}$对应的产品,然而$B_{1}=B_{2}$,因此我们并没有完成去重任务,即便是`d[x]`从A被替换为B,那么后续仅能过滤掉B,后面出现的A无法过滤掉

---

这种做法只能处理重复最多不超过1次的情况,或者(A,A,A,...)这种简单的情况

如果要更改完整和正确的处理重复产品,需要将`value`设计为一个容器,比如是另一个字典(查重快),或者列表(直观,但是查重效率略逊一筹)

### 代码中python字典的注意事项(维护时要小心)

为了提高检索速度,代码中大量使用了字典以及字典的方法

而为了协调采集器采集到的数据(字段为中文,比如`"产品描述"`这类的)

而导出为csv我们又需要英文字段,比如`Description`;因此遍历字典或数据库读取的Row对象时,要警惕错误的字段引用,会导致修改的字段出现偏差或不符合预期,比如更新产品分类,DBProductField,和CSVProductField要区分好

这些枚举值定义在专门的python模块中

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

### logging调试性能不佳🎈

> 目前这个是主要原因之一(尤其如果采集的数据很多不规范,打印的内容越多,越卡顿)

相比于print,logging的info,这类调用性能不佳,代码中要合理使用避免被日志信息的计算和存储拖慢速度

如果不是调试阶段,请不要使用debug,甚至info这类也要酌情使用,部分情况下,如果logging打印太多(可能是导入到本地文件)