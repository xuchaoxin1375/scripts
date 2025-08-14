[toc]



## abstract

基于python的图片下载器,集成curl的下载方式(python有时候下不动,需要`curl`下,或者`powershell`调用`iwr`(`invoke-webrequest`的缩写)下载)



## 多线程图片下载器

### 特性

- 多线程并发下载，提高下载效率
- 自动识别和处理各种图片链接格式
- 支持自定义图片文件名
- 提供详细的下载统计和日志记录
- 支持命令行调用和作为模块导入使用
- 支持下载失败重试
- 自动创建输出目录
- 自动从URL或Content-Type推断图片格式

### url分隔符说明

url的分隔符不能随便取,比如逗号是不可靠的,有的url中本身包含逗号,例如:

- https://img1.baidu.com/it/u=2620377681,912957102&fm=253&fmt=auto&app=138&f=JPEG?w=764&h=500

目前使用的分隔符包括空格(可以多个连续空白字符)或者`>`号

### 主要文件结构

我将创建以下文件：

1. `img_downloader.py` - 主要的下载模块
2. `README.md` - 使用文档
3. `requirements.txt` - 依赖项列表

### 实现代码 imgdown.py

- 详见模块代码[imgdown.py](imgdown.py)



## 使用方法



### 作为命令行工具使用

基本用法：

```bash
python img_downloader.py -i urls.txt -o ./images
```

其中，`urls.txt`是包含图片URL的文本文件，每行一个URL。



### 使用powershell调用python脚本和下载(deprecated)

```
Get-WpImages [[-Path] <Object>] [[-Directory] <Object>] 
```

其中第一个参数`-Path`指定包含url的文件(比如csv所在目录)

第二个参数是图片要下载到哪个目录下

## 完整参数说明🎈

有两种方式

请在脚本所在目录,运行如下命令查看用法

```bash
python img_downloader.py -h
```

或者用绝对路径引用此脚本

```powershell
python C:\repos\scripts\wp\woocommerce\woo_df\image_downloader.py -h
```

### 测试下载指定的图片链接🎈

首先找到下不动的链接,检查浏览器是否能够打开该图片

如果打不开,或者使用了防护(比如cloudflare,人机验证等),那么脚本很难成功下载,这部分就跳过(下载失败会自动跳过,其他图片继续下载)

```powershell
py $pys\image_downloader.py -O -U curl -i https://www.crosshop.eu/images/img_export/prodotti/NY+02457.jpg 
```

将要测试的链接紧跟再`-i`参数后面(保留空格)

### 指定文件名下载🎈

如果需要为每个图片指定文件名，可以使用 `-n` 参数，并准备一个包含文件名和URL对的文本文件，格式为：

```
filename1.jpg http://example.com/image1.jpg
filename2.png https://example.com/image2.png
```

然后执行：

```bash
python img_downloader.py -i name_url_pairs.txt -o ./images -n
```

### 作为模块导入使用

```python
from imgdown import ImageDownloader

# 创建下载器实例;配置重试次数
downloader = ImageDownloader(max_workers=10, timeout=30, retry_times=2)

```

直接针对链接

```python
# 创建下载器实例;配置重试次数
downloader = ImageDownloader(max_workers=10, timeout=30, retry_times=2)
# 下载URL列表
urls = [
    'https://gips2.baidu.com/it/u=1651586290,17201034&fm=3028&app=3028&f=JPEG&fmt=auto&q=100&size=f600_800',
    'https://img1.baidu.com/it/u=2620377681,912957102&fm=253&fmt=auto&app=138&f=JPEG?w=764&h=500',
    'http://example.com/image3.gif'
]
stats = downloader.download(urls, output_dir='./images')
```

另一类用法

```python
# 创建下载器实例;配置重试次数
downloader = ImageDownloader()
# 使用自定义文件名下载
name_url_pairs = [
    ('custom_name1.jpg', 'https://gips2.baidu.com/it/u=1651586290,17201034&fm=3028&app=3028&f=JPEG&fmt=auto&q=100&size=f600_800'),
    ('custom_name2.png', 'https://img1.baidu.com/it/u=2620377681,912957102&fm=253&fmt=auto&app=138&f=JPEG?w=764&h=500'),
    ('custom_name3.gif', 'http://example.com/image3.gif')
]
stats = downloader.download_with_names(name_url_pairs, output_dir='./images')


```



### 高级配置

`ImageDownloader` 类支持以下初始化参数：

- `max_workers`: 最大工作线程数（默认: 10）
- `timeout`: 下载超时时间，单位秒（默认: 30）
- `retry_times`: 下载失败重试次数（默认: 3）
- `user_agent`: 自定义User-Agent
- `verify_ssl`: 是否验证SSL证书（默认: True）

示例：

```python
downloader = ImageDownloader(
    max_workers=20,
    timeout=60,
    retry_times=5,
    user_agent='Custom User Agent',
    verify_ssl=False  # 不推荐在生产环境中禁用SSL验证
)
```

### 日志

下载器会自动记录日志到控制台和 `img_downloader.log` 文件。





## 使用示例🎈

### 通过绝对路径的方式来调用脚本

```bash
python C:\repos\scripts\wp\woocommerce\woo_df\pys\image_downloader.py -c -n -R auto -k -d .\csvy\ -o ./ccc 
```

从csv文件(`-c`),且这里输入的csv文件(或csv文件所在目录)格式都相同,其中有Images,ImagesUrl两列(`-n`解析图片链接和要保存的文件名)

`-R`是图片压缩参数,将图片进行压缩

`-k`表示压缩后删除掉源文件,仅保留压缩后的文件

`-d`表示输入的带有图片url链接的文件(比如csv文件)所在的目录

`-o`表示下载的图片要存放到哪个目录

`-O`表示如果指定的保存目录已经存在要下载的图片,则覆盖(重新下载处理,这主要用户测试),默认情况下(没有`-O`会跳过已经有或下载过的图片,避免重复下载)



### 准备URL列表文件

创建一个名为 `urls.txt` 的文本文件，每行包含一个图片URL：

```
https://example.com/image1.jpg
https://example.com/image2.png
https://example.com/image3.gif
```

### 命令行下载

```bash
python img_downloader.py -i urls.txt -o ./downloaded_images -w 5
```

### 指定文件名下载

创建一个名为 `name_url_pairs.txt` 的文本文件：

```
my_image1.jpg https://example.com/image1.jpg
my_image2.png https://example.com/image2.png
my_image3.gif https://example.com/image3.gif
```

然后执行：

```bash
python img_downloader.py -i name_url_pairs.txt -o ./downloaded_images -n
```

### 作为模块导入使用

```python
#导入下载器
from imgdownn import ImageDownloader

# 创建下载器实例
downloader = ImageDownloader(max_workers=10)

```

```python

# 下载URL列表
urls = [
    'https://example.com/image1.jpg',
    'https://example.com/image2.png',
    'https://example.com/image3.gif'
]
downloader.download(urls, output_dir='./downloaded_images')
```



### 配置代理 python命令行环境代理🎈

部分网站的图片直接下不动,需要走代理

如果是powershell下,打开cfw/verge,或者其他代理软件,可以赋值代理环境变量下载图片

得到的命令行形如:(配置临时生效,如果要长期生效,需要修改用户或系统级环境变量)

常用的端口为`8800`或`7897`

```powershell
$env:HTTP_PROXY="http://127.0.0.1:7897"; $env:HTTPS_PROXY="http://127.0.0.1:7897"
```

或者使用专门的powershell指令

```powershell
set-proxy -port <port>
```

例如`set-proxy -port 8800`回车执行,然后再执行图片下载命令

#### 自动化(todo)

自动切换网络代理环境可以在下载脚本中实现,等待后续更新!

### 命令行使用示例🎈

下面是预览版(2025年04月30日22时14分)的测试结果

测试仅使用少量图片达到演示效果即可

#### 读取csv文件(指定了图片链接和图片保存的名字)的方式下载图片

解析csv文件并下载是我们的主要方式,我们重点讨论

通常默认你使用的csv是本文提供的另一个脚本(woo_get_csv.py)导出的csv

```powershell
python c:\Share\df\LocoySpider\woocommerce\woo_df\imgdown.py  -c -n -i .\woo_df\csv_dir\p_test_img_downloader.csv
```



```powershell
#⚡️[Administrator@CXXUDESK][C:\Share\df\LocoySpider\woocommerce][22:10:33][UP:8.52Days]
PS> python c:\Share\df\LocoySpider\woocommerce\woo_df\imgdown.py  -c -n -i .\woo_df\csv_dir\p_test_img_downloader.csv
2025-04-30 22:10:39,900 - root - INFO - welcome to use image downloader!
2025-04-30 22:10:39,901 - root - INFO - 开始下载 3 张图片到 ./images
2025-04-30 22:10:41,287 - root - INFO - 成功下载: https://medias.yves-rocher.fr/medias/?context=bWFzdGVyfGltYWdlc3w0ODAxN3xpbWFnZS9qcGVnfHN5c19tYXN0ZXIvaW1hZ2VzL2gzMC9oYTgvOTg2NTM5MzM0MDQ0NnxjNDY5Zjc2OTdhMDkyODc0OGRkNjVjNDUwNWNmYmFiMWQ2NWQxZjlhMzFkNzg0NGJmMWQ1N2I2MWE5MzBmNzcw&twic=v1/resize=1200/background=white -> ./images\SK0000001-IT-1.jpg (36599 字节)
2025-04-30 22:10:43,054 - root - INFO - 文件已存在,覆盖模式:False，跳过: ./images\SK0000001-IT-0.jpg
2025-04-30 22:10:43,759 - root - INFO - 成功下载: https://www.zooservice.it/5454-large_default/shampoo-petter-250ml-glicine.jpg -> ./images\SK0000002-IT-0.jpg (28571 字节)
2025-04-30 22:10:43,761 - root - INFO - ==================================================
2025-04-30 22:10:43,761 - root - INFO - 下载统计摘要:
2025-04-30 22:10:43,762 - root - INFO - 总计: 3 张图片
2025-04-30 22:10:43,762 - root - INFO - 成功: 3 张图片
2025-04-30 22:10:43,762 - root - INFO - 失败: 0 张图片
2025-04-30 22:10:43,763 - root - INFO - 跳过: 0 张图片
2025-04-30 22:10:43,763 - root - INFO - 耗时: 3.86 秒
2025-04-30 22:10:43,763 - root - INFO - ==================================================
```

仅解析链接下载

```powershell
#⚡️[Administrator@CXXUDESK][C:\Share\df\LocoySpider\woocommerce][22:30:32][UP:8.53Days]
PS> python c:\Share\df\LocoySpider\woocommerce\woo_df\imgdown.py  -c  -i .\woo_df\csv_dir\p_test_img_downloader.csv
2025-04-30 22:32:02,326 - root - INFO - welcome to use image downloader!
2025-04-30 22:32:02,328 - root - INFO - 开始下载 3 张图片到 ./images
2025-04-30 22:32:02,886 - root - INFO - 成功下载: https://medias.yves-rocher.fr/medias/?context=bWFzdGVyfGltYWdlc3w0ODAxN3xpbWFnZS9qcGVnfHN5c19tYXN0ZXIvaW1hZ2VzL2gzMC9oYTgvOTg2NTM5MzM0MDQ0NnxjNDY5Zjc2OTdhMDkyODc0OGRkNjVjNDUwNWNmYmFiMWQ2NWQxZjlhMzFkNzg0NGJmMWQ1N2I2MWE5MzBmNzcw&twic=v1/resize=1200/background=white -> ./images\1b402c5017a83dbde91f6a85ef0b92c3.jpg (36599 字节)
2025-04-30 22:32:03,257 - root - INFO - 文件已存在,，跳过: ./images\shampoo-petter-250ml-glicine.jpg
2025-04-30 22:32:03,351 - root - INFO - 成功下载: https://www.zooservice.it/5456-large_default/shampoo-petter-250ml-pino.jpg -> ./images\shampoo-petter-250ml-pino.jpg (29152 字节)
2025-04-30 22:32:03,351 - root - INFO - ==================================================
2025-04-30 22:32:03,352 - root - INFO - 下载统计摘要:
2025-04-30 22:32:03,352 - root - INFO - 总计: 3 张图片
2025-04-30 22:32:03,352 - root - INFO - 成功: 2 张图片
2025-04-30 22:32:03,352 - root - INFO - 跳过: 1 张图片
2025-04-30 22:32:03,352 - root - INFO - 失败: 0 张图片
2025-04-30 22:32:03,352 - root - INFO - 耗时: 1.02 秒
2025-04-30 22:32:03,352 - root - INFO - ==================================================
```

## 无后缀扩展名的图片url下载🎈

```

https://medias.yves-rocher.fr/medias/?context=bWFzdGVyfGltYWdlc3w0ODAxN3xpbWFnZS9qcGVnfHN5c19tYXN0ZXIvaW1hZ2VzL2gzMC9oYTgvOTg2NTM5MzM0MDQ0NnxjNDY5Zjc2OTdhMDkyODc0OGRkNjVjNDUwNWNmYmFiMWQ2NWQxZjlhMzFkNzg0NGJmMWQ1N2I2MWE5MzBmNzcw&twic=v1/resize=1200/background=white
https://target.scene7.com/is/image/Target/GUEST_6c8cad53-1980-4e8f-ab19-6730ff673ac0
https://target.scene7.com/is/image/Target/GUEST_558f70b0-1039-41b7-aeb7-fdba3ecba42a
```



## 总结

这个多线程图片下载器具有以下优点：

1. **功能完备**：支持多线程下载、自定义文件名、下载统计和日志记录
2. **兼容性强**：能处理各种图片链接格式，自动推断图片类型
3. **易用性高**：支持命令行调用和作为模块导入使用
4. **可扩展性好**：代码结构清晰，易于扩展和维护
5. **健壮性强**：包含错误处理、重试机制和详细日志



​        
