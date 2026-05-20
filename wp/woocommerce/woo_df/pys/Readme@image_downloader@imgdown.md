[toc]



## abstract

基于 Python 实现的高性能分布式图片下载器，集成了**基础多线程下载**与**高级防防爬浏览器对抗**双轨制方案。支持在多层防爬防火墙（如 Cloudflare 人机验证）环境下，通过单页面预热与 Cookies/Profile 会话持久化复用，保障图片的高效、无损下载。系统支持命令行（CLI）、JSON 配置文件（多级参数合并）以及作为 Python 模块无缝导入使用。

### 特性

- **支持命令行与模块化调用**：提供功能齐备的 CLI 参数接口，亦可轻松嵌入任何 Python 业务流中。
- **高并发并发双轨制下载**：
  - **基础多线程方案**：内置 `request`, `curl`, `cffi`, `iwr`（PowerShell Invoke-WebRequest），适合无防爬轻量站点，极速下载。
  - **高级浏览器方案**：基于 `Scrapling (Stealthy)` 与 `Playwright` 物理级浏览器指纹对抗，包含cloudflare 求解器方案。
- **配置优先级多级合并系统**：支持 `-S config.json` 参数文件一键加载，合并策略完美遵循：`默认值 < JSON 配置 < 命令行显式指定参数`。
- **智能预热与会话持久化**：独创渐进式单页面预热（`--warmup`），首个任务验证通过后高并发 Page 共享 Cookies；配合 `-Z` 可持久化 Profile 终生受益。
- **极致响应的 Ctrl+C 中断**：在底层注入系统信号抢占式处理器（`signal.signal`），实现 1 毫秒级单次按键瞬间强退，绝无挂起。
- **智能图片压缩与等比例缩放**：集成伴侣组件，智能检测图片大小（如超出 100KB）并自动等比例缩小（`-rs`）和无损转换为 WebP 压缩格式。
- **安全过滤与增量去重**：自动对比输出目录下的同名文件，默认进行增量去重，避免重复下载。

### 关于图片url检索分隔符说明

url的分隔符不能随便取,比如逗号是不可靠的,有的url中本身包含逗号,例如:

- https://img1.baidu.com/it/u=2620377681,912957102&fm=253&fmt=auto&app=138&f=JPEG?w=764&h=500

目前使用的分隔符包括空格(可以多个连续空白字符)或者`>`号

### 相关代码文件结构

项目核心架构由以下文件组成，分工明确，解耦良好：

* [image_downloader.py](image_downloader.py) - **应用总主入口**：负责多级命令行与 JSON 配置文件联合参数解析、输入数据预筛选、增量去重和业务层总调度。
* [imgdown.py](imgdown.py) - **下载流控制器**：负责多线程线程池（基础方案）和单浏览器实例异步队列批量 Page 调度（浏览器方案）的管理中心。
* [downbyscrapling.py](downbyscrapling.py) - **强混淆浏览器引擎**：基于 Scrapling 物理级混淆，负责会话冷启动预热、多 Page 共享凭据和断点防爬拦截。
* [downbybrowser.py](downbybrowser.py) - **标准浏览器引擎**：基于标准 Playwright 流程的浏览器批量下载框架。
* [imgcompressor.py](imgcompressor.py) - **高性能图片处理器**：负责对下载下来的原始文件进行等比例分辨率缩放及智能 WebP 压制。
* [image_downloader.json](image_downloader.json) - **标准参数配置文件**：包含常见建站下载参数对等的 JSON 模板。

---

## 使用方法

### 作为命令行工具使用

基本用法：(通过`-h`或`--help`打印使用帮助)

```bash
python image_downloader.py -i urls.txt -o ./images
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
python image_downloader.py -h
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
python image_downloader.py -i name_url_pairs.txt -o ./images -n
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

在启用日志记录的情况下,下载器会自动记录日志到控制台和 `img_downloader.log` 文件。





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
python image_downloader.py -i urls.txt -o ./downloaded_images -w 5
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
python image_downloader.py -i name_url_pairs.txt -o ./downloaded_images -n
```

### 作为模块导入使用

```python
#导入下载器
from imgdown import ImageDownloader

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



## 进阶功能与开发维护指南 (2026.05) 

针对现代电商/网络站点日益严苛的防爬和人机验证（如 Cloudflare 等），我们对下载器进行了一次里程碑式的重构与升级，集成了基于物理级浏览器对抗、凭证持久化、配置混合合并以及瞬时响应中断等前沿特性。

---

### 1. 防屏蔽/人机挑战利器：Scrapling 强力浏览器模式 (`-U scrapling`/`-U scr`)

除了传统的快速下载方法（`request`, `curl`, `cffi` 等），我们引入了基于 Playwright + `Stealthy` 双层指纹对抗的强力浏览器方案：
* **启用方法**：命令行指定 `-U scr` 或 `-U scrapling`。
* **特点**：全自动模拟真实硬件指纹、滑动轨迹、浏览器请求头，是突破 Cloudflare 盾牌、登录阻挡的首选引擎。

---

### 2. 渐进式单页面预热机制 (`-W` / `--warmup`)

如果在多并发状态下直接启动 10 个浏览器窗口，它们会在同一时刻全部遭遇人机挑战，导致重复验证且极易触发风控。
* **设计原理**：开启 `--warmup` 后，脚本会首先挑出 **首个真正需要网络下载的任务**（跳过已存在于本地的文件，哪怕第一个链接已被过滤也会智能顺延），以**单窗口、单页面**方式进行“冷启动”预热并完成首张图片的下载。
* **成果复用**：当首张图成功通过人机挑战并下载后，系统再瞬间解锁由 `-w` 指定的高并发通道（通过 Page 复用机制），**共享已获取的 Cookies、登录 Session 和网络缓存**，大幅提高效率并实现了 0 干扰下载。

---

### 3. 安全凭证与浏览器配置持久化 (`-Z` / `--user-data-dir`)

配合浏览器方案时，支持指定 `-Z <路径>` 传入您的浏览器持久化配置目录：
```bash
python image_downloader.py -U scr -W -Z C:/temp/scrapling/imgdown ...
```
* **效果**：浏览器会将验证通过的 cookies、网站授权数据落盘保存。在不同次的下载任务启动间，**可完美复用上一次通过人机验证的成果**，实现“一次通过，长期免验证”。

---

### 4. 多级参数混合配置系统 (`-S` / `--config`)

随着参数日渐丰富，您可以通过 `-S <JSON路径>` 从 JSON 配置文件中读取全部参数组合（我们也为您生成了完备的对等 `image_downloader.json`），其具备最符合开发直觉的**多级覆盖机制**：

$$\text{argparse 内置默认值} < \text{JSON 配置文件指定值} < \text{终端命令行显式指定参数（最高优先级）}$$

* **工作流说明**：底层解析器首先提取 `-S`，并临时对所有 argparse 默认参数执行 `SUPPRESS` 抑制；接着，将用户在终端中**显式输入**的参数（如命令行临时追加的 `--workers 10`）提为最高优先级覆盖 JSON 配置。这使您可以将常用配置固化在 JSON 中，且保留在终端随时进行局部参数微调的超高灵活性。

---

### 5. 秒级响应 Ctrl+C 中断与强退保障

在常规多线程与异步循环中，`KeyboardInterrupt`（Ctrl+C）极易遭遇套接字 I/O 阻塞或 `ThreadPoolExecutor` 的线程守护锁挂起，产生多按、长按仍无法退出控制台的通病。

我们进行了底层深度干预，实现了**三层防卡死机制**：
1. **异步层抛出**：协程下载器中的捕获块不再吞掉 `KeyboardInterrupt`，而是完成安全取消后将其重新向上传递。
2. **线程池非阻塞**：ThreadPool 被重构为非 contextmanager 手动控制，一旦捕获中断，立即取消全部挂起任务，调用 `executor.shutdown(wait=False)` 绝不挂起主线程。
3. **原生信号抢先拦截**：在 `image_downloader.py` 入口点注册了系统级 `signal.signal(signal.SIGINT)` 监听器。它在 `asyncio` 事件循环前拦截键盘信号，瞬时调用 `os._exit(1)`。
   * **效果**：无论程序目前处于何种大规模并发下载、浏览器交互状态下，**只需按下 1 次 Ctrl+C，即可在 1 毫秒内瞬间无卡卡退**并交还控制台。

---

### 6. 开发者维护与调度分发规范 🛠️

在对本套工具进行后续维护或横向扩展时，请注意以下内核分发设计：
* **调度统一收归**：所有的浏览器或混淆浏览器引擎（无论是 `scrapling`, `browser`, `scr`, `bro`, `pro`, `playwright`, `play` 等任何别名）全部统一注册于 `BROSWER_DOWNLOADER` 中。
* **多路分发防走样**：`imgdown.py` 的入口分发模块会严密判断 `self.download_method not in BROSWER_DOWNLOADER`。所有浏览器方法**严禁分流进入多线程 ThreadPoolExecutor 块**，必须严格收拢在单浏览器实例下的 `batch_download()` 中，由异步队列 `asyncio.Queue` 配合 `AsyncStealthySession` 进行安全的并发 Page 管理，避免造成并发启动多浏览器致使底层资源死锁。

​        

