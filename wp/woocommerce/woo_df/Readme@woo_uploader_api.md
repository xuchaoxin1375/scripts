[toc]

## abstract

- 这是woo_uploader.py的文档

## 前提条件

### 准备好可用的wp站

- 无论是本地(http用于测试开发)还是正式站(https正式部署),都要确保相应网站服务都正常
- 尤其是本地,如果重启了计算机,网站服务可能被停掉了,你需要启用他们,比如通过小皮建站,那么请检查小皮工具箱中的相关组件是否正常工作,被测试的网站能否正常打开
- 一定要确保后台可以进入(部分情况下首页打得开,但是后台打不开,api也是无法工作的)

### 首先需要安装python

通过pip安装库

1. woocommerce
   `pip install woocommerce`
2. 如果下不动,可以先将pip 源换为国内源提供加速下载,加速下载换源命令如下(在powershell中运行下面两个命令行):

```powershell
$mirror = 'https://pypi.tuna.tsinghua.edu.cn/simple'
pip config set global.index-url $mirror
pip install woocommerce
```

3. 推荐安装notebook

`pip install notebook`

- 这个库可以提供交互式的python环境,可以方便的进行数据处理和可视化分析

### woocommerce 鉴权 密钥/key

- 请事先准备好要上传的站点的 URL、Consumer Key 和 Consumer Secret
- 注意,正式上传建议设置为https协议,否则可能会导致鉴权失败

#### 检查鉴权是否成功

调用`wc.get_product_count()`方法或者`wc.get_system_status()`方法检查

### 链接测试代码段🎈

```python
from woodf import WC

protocal = "http"  # 协议,一般是https(适用于正式上传),http(适用于本地脚本调试/开发)
domain = "wp.com"  # 域名
url = f"{protocal}://{domain}"  # 不要有多余的路径
consumer_key = "ck_d27091399219c406fb6f420f498aecfb8e6fe812"
consumer_secret = "cs_5bbfa3135dd9ff605f920f8c888b3036e0a69ec7"

wc = WC(
    api_consumer_key=consumer_key,
    api_consumer_secret=consumer_secret,
    api_url=url,
    timeout=30,
)
# 检查woo鉴权和链接(返回-1表示链接失败)
wc.get_product_count()
 
```



## 代码设计说明

### 代码文档或注释完整性检查

- 可以借助ai检查哪些函数或方法的用法或者参数解释缺失,比如使用deepseek全文分析,得出需要完善的文档位置

### 功能

接入woocommerce python api中常用的部分,并对其进行封装,使其更加易于使用,`wc`对象支持但不限于以下功能:
- 查找产品(根据:名称/分类名/sku/id查找)
     - 可以自行接查阅api文档,获得更多查询方法,WC类继承了Woo API,所以可以直接用get/post/put/delete请求方法)
- 从数据库拉取现有分类/商品
- 进度读档/断点续传
- 批量创建分类
- 批量删除产品
- 批量删除分类
- 批量上传产品/更新产品
- 对于上传成功/失败的产品分被缓存到WC实例的容器中
- 增加连接池防止windows套接字缓存耗尽导致断网甚至重启(developing)
- 添加csv文件产品记录sku排序统一编号(developing)

### 进度读档|断点续传|进度恢复🎈

#### 通用读档

脚本一般不会中断,普通的产品数据上传超时抛出的异常会被脚本自动捕获并记录,然后继续上传不会轻易中断

> 只有在网络彻底掉线或者频繁不稳定累计大量错误,以及更加严重的不可抗错误(比如断电/硬件损坏/系统故障死机)情况下才会终止执行

断点续传的需求主要为上述特殊情况服务

目前的思路是:利用对应的api请求网站数据库中的所有已经存在的商品数据缓存到本地;然后本地会将读取的csv数据和缓存的产品数据进行sku对比,如果正在尝试上传的产品的sku在缓存中能够查找到,那么此产品就会被跳过上传

上传模式由wc的相应方法的参数控制,详情查看代码中的函数的文档

#### 本地读档|从Log文件恢复

> 原理:使用此代码上传的站,被意外中断的产品上传会被记录到wc对象的对应成员中,可以将上传的每一条产品写入到一个文件中,方便我们恢复(这种方法读档和恢复上传的速度更快)

方法和参数示例

```python
wc.process_csvs(files,upload_mode="resume_from_database",log_file=r"C:\repos\DF_LocoySpider\data_process\woocommerce\csv_dir\log\upload@wp.com@20250410-04-36-28.csv")
```
注意,日志文件是一个.log文件,不是目录或文件夹,否则会报错(pemission denied)

### 代码设计

引入线程池,并且设计为池中池的并发模式(并发处理多个csv文件),上传速度快,但是占用服务器资源也高

上传模式有多种:

- 批上传:
  - 目前主要的上传方式,对于进度反馈和请求数量的一个折中
- 逐条数据上传:
  - 这种方法每个产品数据都会发送一个请求,效率比较低,但是上传进度的反馈很及时
  - 设置线程指标(max_workers),达到的并发数理论最高为 max_workers的平方(各级池中多于worker数的任务会进入等待队列)

如果同时上传多个站的数据,则线程数设置为1比较稳,开高可能导致系统缓冲区资源不足导致断网

## 传输情况分析与最佳实践

- 对于纯净空站的传输比较简单,直接上传(调用`wc.process_csvs(files)`)
- 对于已经存在数据的站(比如历史遗留老站),假设你已经整理了还未上传的csv(比如经过切割)上传仍然也是比较简单的,
  - 建议先将已有**分类**缓存下来(调用`wc`对象的`prepare_categories`方法)其取值可以为(True/False)),然后再上传产品
  - 为了尽可能兼容非纯净站的上传,默认情况下,`wc.process_csvs(files)`会为你调用此方法,因此一般情况下不需要你手动处理
- 利用此python代码上传数据到非纯净站(删除全部产品的空产品站)你大概有以下选择:
  - 直接重传(已经有的产品会提示**Failed**,在本代码中,这不是太值得关注的消息,不应该归属为错误(**error**),而是一种操作结果
    - 遇到没有上传过的产品会上传的)
  - 调用`wc.fetch_existing_products()`方法,可以为你从服务器数据库上拉取已经上传的产品数据
    - 但是这个过程可能是比较耗时的,特别是woocommerce api目前只能分页获取产品数据,限制每次(页)获取最大产品数量为100,这对于有数万个产品的站来说,获取所有产品数据是令人沮丧的事情,幸运的是,结合多线程等技术,可以并发获取产品,来提高获取产品的速度,但是要注意服务器是否能够承受住压力(不建议将线程数设置得过高,建议不超过20,但是具体你可以自己测,我某次测试的例子:10线程的情况下,获取1.8W数据耗时3分钟)
  - 还可以使用`upload_mode="update_if_exist"`在产品已经存在或有残留未清干净的情况下直接覆盖已有产品
    - 但是要注意已经上传的图片存两遍占用空间
  - 最后,你当然可以选择清空整个站,然后重新上传,但这不是推荐选项

-----------------

## 基本用法:

### vscode+notebook

[Python 交互窗口](https://code.visualstudio.com/docs/python/jupyter-support-py)

- 在vscode+jupyter notebook中运行,可以提供交互体验,提供更高的灵活性和可观察性

### 命令行运行python脚本

- 用命令行执行python文件更加简单,但是灵活性不如vscode
  - 一般情况下,注意代码中要解开末尾的注释(wc.process_csvs()方法的调用代码)
  - 也可以添加/插入其他代码,比如手动调用/获取已经上传的产品:`wc.fetch_existing_products()`

```python
#实例化 WC 客户端

wc=WC()

#获取现有产品信息

wc.fetch_existing_products()
print(wc.existing_products)

#获取现有分类信息

wc.fetch_existing_categories()
print(wc.existing_categories)
exit()

#删除category(产品分类)

print(wc.delete_categories(mode="all"))

#删除指定分类(但是不删除产品)

wc.delete_categories(category_name='Cat1')
exit()
```

### 上传模式

1. "try_create_only"默认值
   表示仅尝试创建新产品,如果产品已存在不更新产品;

2. "update_if_exist",
    当直接创建产品失败时,尝试更新已有产品;
3. "jump_if_exist",🎈(默认)
    当直接创建产品失败时,跳过当前产品;
4. "resume_from_database",会尝试读取站点数据库数据并缓存必要数据,然后转到执行"jump_if_exist"继续执行
    此模式通用性强,但是性能不是最好的,适用于以下情况:
    1. 向已经存在数据的站使用此代码上传
    2. 尝试从上次脚本中断的地方继续上传产品;
5. "resume_from_log_file",会尝试读取日志文件并缓存必要数据,然后转到执行"jump_if_exist"继续执行,
    效果和"resume_from_database"类似,速度更快:
    1. 要求该站点上次上传是是用此脚本上传才有效,部分情况下准确度比from_database低
    2. 需要指定日志路径



### 灵活的批量操作

#### 删除指定sku的产品

```python
#配置需要删除的sku(可以在libreoffice中筛选,通过脚本构造sku字符串)
prouducts_sku=['SK0011138-U','SK0011139-U','SK0011140-U']
for sku in prouducts_sku:
    wc.delete_product(sku=sku)
```

## 对于无后缀图片的上传的支持

- 一般来说,wordpress+woocommerce不支持无后缀的图片,但是经过查阅资料,本文的模块添加了(图片)文件类型猜测特性
- 但目前仅支持将图片下载到本地数据库直插产品数据的上传方式,如果是通过传统api调用上传的方式仍然受限于url链接后缀格式的限制
- 由于图片后缀的格式的确定需要依赖于图片url,所以摆在我们眼前的方案有:(无论哪种,最终我们的csv中的Images中的图片名字要带有后缀)
  - 采集的时候,借助python插件或者C#代码段及时处理掉
  - 前期不管,等到采集到数据库中后统一集中发送请求查询文件类型(这种方案看起来比较繁琐,而且容易造成导出的时候为了请求和计算图片文件扩展名类型而拖慢导出速度)

## FAQ🎈

### 常见错误类型🎈

由于以下几类原因:

- 协议配置不当

- csv目录配置

- 网站设置不当(https/证书/伪静态/**固定链接**设置等相关配置)


> 比如没有绑定证书(虽然cloudflare这种服务商启用代理服务后,可能会让你的网站自带https访问属性,但是这种方式经过试验暂时不是很稳定,因此仍然建议用专门的证书绑定(手动或者自动都可以)))

### 固定链接设置

- 经过试验,固定链接不能随便设置,一般推荐使用**文章名**(日期和名称型本地测试发现api无法工作,走https的上线站似乎可以)

- 固定链接结构

  朴素
  http://wp.com/?p=123


  日期和名称型
  http://wp.com/2025/05/19/sample-post/


  月份和名称型
  http://wp.com/2025/05/sample-post/


  数字型
  http://wp.com/archives/123


  文章名
  http://wp.com/sample-post/


  自定义结构

### 具体类型

1. **Failed to resolve domain (11001)**:

   域名解析错误,可能和网站部署的方式有关,如果没有证书,或者证书不正确,或者cloudflare设置的加密模式不当(灵活模式/完全模式,目前看来完全模式比较稳,默认情况下大多都是完全模式)

   ```bash
   Failed to resolve 'domain.com'([Errno 11001]getaddrinfo failed)
   ```

   也让同事帮忙测试一下,如果别人可以连上,而自己却不行,则你可以尝试修改DNS为常用dns,比如8.8.8.8或1.1.1.1(修改方法可以百度);或者重启一下计算机

   

2. **JSONDecodeError** :

   > 调用api时爆出html源码片段或404
   >
   > 这种错误的原因,是python尝试将api调用返回的Response,但是如果由于配置不当或者网络不稳定,造成返回的Response数据不完整不正确,调用Response对象的json()就会爆出JsonDecodeError异常(简单讲就是在一个不正常的对象上调用json()导致异常)

   - 伪静态没有设置正确
   - 证书没有绑定
   - 固定链接

3. **FileNotFoundError** :提供的产品数据文件路径错误,或者相对路径无法被正确识别(使用绝对路径比较稳妥)

4. **ConnectionError**:由于目标计算机积极拒绝，无法连接

   这可能是你的网站没有正常运行,尤其是本地测试的计算机重启后,要检查相关组件(比如apache/nginx,mysql)是否正常启动,网站是否能够正常访问)

   ```http
   ConnectionError: HTTPConnectionPool(host='wp.com', port=80): Max retries exceeded with url:... (Caused by NewConnectionError('<urllib3.connection.HTTPConnection object at 0x000002B42AC6A9F0>: Failed to establish a new connection: [WinError 10061] 由于目标计算机积极拒绝，无法连接。'))
   ```

   

### http/https协议选择错误

- 这种错误一般是正式上传的url链接协议没有切换为`https`,可能导致鉴权失败

### 常见响应错误

这里主要讨论在woo api鉴权成功的情况下,由于wp站数据库不干净或者其他原因(比如图片远程镜像失败的情况)

#### woocommerce_rest_product_not_created

可能是wp数据库之间上传过其他产品(尤其是从成品站导出二次利用为模板,如果产品清空(比如使用不完整的产品清理sql语句),就可能导致如下错误的出现)

```bash
Failed to create product: ('L’UGS (SK0091068-U) que vous tentez d’insérer est déjà en cours de traitement', 'woocommerce_rest_product_not_created')
```

这种情况下，可以运行完整清理sql语句以解决问题(相应的sql存放在共享文件夹中)

#### duplicated_sku

当前上传的产品的sku已经存在于产品库中,通常是重复上传或者断点恢复继续上传的第一批(batch)会可能出现

> 关于恢复上传会提示duplicated,可能是上传异常中断前的一批数据发送/上传,但是还没有来得及接收响应,从而导致日志文件没有记录中断前上传的最后一批数据的记录,会导致重复上传一点点数据(这不要紧,重复的sku产品会自动跳过)

### 系统缓冲区空间不足或队列已满🎈

 [WinError 10055] 由于系统缓冲区空间不足或队列已满，不能执行套接字上的操作

解决方案:(包括但是不限于此处列举的,并且不保证都有效,这个错误比较底层)

> 可能是请求过于密集,导致资源来不及回收

- 尝试将线程数(worker)改小或者batch_size改大
- 添加sleep时间
- 添加连接池
- 修改系统注册表



## http响应码参考

错误代码通常用于标识特定的问题或错误状态。在HTTP请求中，最常见的错误代码是HTTP状态码，它们由三位数字组成，用于表示请求的结果。以下是一些常见的HTTP状态码及其含义：

- **1xx (信息性状态码)**：
  - 100 (Continue)：客户端应继续请求。
  - 101 (Switching Protocols)：服务器同意客户端的转换请求。
- **2xx (成功状态码)**：
  - 200 (OK)：请求已成功。
  - 201 (Created)：请求已成功，并创建了新的资源。
  - 204 (No Content)：请求成功，但没有资源返回。
- **3xx (重定向状态码)**：
  - 301 (Moved Permanently)：请求的资源已被永久移动到新URL。
  - 302 (Found)：请求的资源已被临时移动到新URL。
  - 304 (Not Modified)：请求的资源未修改，可以使用缓存。
- **4xx (客户端错误状态码)**：
  - 400 (Bad Request)：服务器无法理解请求。
  - 401 (Unauthorized)：请求需要用户认证。
  - 403 (Forbidden)：服务器理解请求，但拒绝执行。
  - 404 (Not Found)：请求的资源不存在。
  - 408 (Request Timeout)：请求超时。
- **5xx (服务器错误状态码)**：
  - 500 (Internal Server Error)：服务器内部错误。
  - 502 (Bad Gateway)：网关或代理服务器从上游服务器接收到了无效的响应。
  - 503 (Service Unavailable)：服务器当前无法处理请求，通常由于过载或维护。
  - 504 (Gateway Timeout)：网关或代理服务器超时，未及时从上游服务器接收响应。



## TODO LIST

1. 使用logging模块记录日志或者支持并发的concurrent_log_handler模块
2. 支持上传产品时,自动下载远程图片并保存到本地,并将本地图片路径加入到产品数据中
3. 改进文档排版
4. 支持命令行模式
6. 使用多线程的方式来查询所有产品或分类(借助page参数(offset))
7. 移除产品数量为空的分类    ...

## 枚举值(上传模式)

利用枚举值类来代替代替手动合法性判断:

```python
# upload_mode 取值合法性判断
allowed_modes = {
    "try_create_only",
    "update_if_exist",
    "jump_if_exist",
    "resume_from_database",
    "resume_from_log_file",
}
if upload_mode not in allowed_modes:
    raise ValueError(
        f"Invalid upload_mode '{upload_mode}'. "
        f"Expected one of: {', '.join(allowed_modes)}."
    )
```



## 异常捕获

可以考虑对api操作的调用方法使用try...except处理,为了程序不因为某些个特定产品上传超时或失败就让整个程序崩溃停止

我们有必要做异常处理,目前采用简单的捕捉`Exception`异常(虽然不够细致,但是最能满足业务需求)

下面是更加细致异常捕获的版本参考,不保证捕获所有异常,程序可能会因为特殊异常崩溃

```Python

    except TimeoutError as e:
                self.report_error_of_upload(name,sku,f"Timeout:{e}")
            except ConnectTimeout as e:
                self.report_error_of_upload(name,sku,f"Timeout:{e}")
            except ReadTimeout as e:
                self.report_error_of_upload(name,sku,f"Timeout:{e}")
            except Timeout as e:
                self.report_error_of_upload(name,sku,f"Timeout:{e}")
            except RequestException as e:
                self.report_error_of_upload(name,sku,f"Timeout:{e}")
```
## 用户需要配置的参数说明

```python

# 配置说明:

# CSV:从指定文件夹(目录)中扫描出csv文件,并将文件名加入到列表中🎈
#   将此参数引号内的值改为你的csv文件所在目录路径
#   取值可以是相对路径,也可以是绝对路径!
#   例如:
#   CSV_DIR = r"C:\Users\Administrator\Downloads\it\0 331\test"
#   CSV_DIR = r"C:\Users\Administrator\Downloads\it\0331\current"

# MAX_WORKERS:设置线程池的最大并发数
#   默认2,可以根据服务器性能调整
#   细化:允许设置csv文件上传worker数和单份csv内的worker数

# UPLOAD_MODE:上传模式
#   默认模式:"try_create_only"
#   其他"update_if_exist",表示如果产品存在,则更新,否则创建

# TIME_OUT:控制超时阈值
#   不要设置太低,容易触发超时导致链接失败问题,也不应该设置过大,容易被失效产品拖慢导入速度(一般不要超过30秒)
```