[toc]



## abstract

基于python的图片下载器,集成curl的下载方式(python有时候下不动,需要curl下,或者powershell调用invoke-webrequest下载)



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

## 主要文件结构

我将创建以下文件：

1. `img_downloader.py` - 主要的下载模块
2. `README.md` - 使用文档
3. `requirements.txt` - 依赖项列表

## 实现代码

### imgdown

- 详见模块代码[imgdown.py](imgdown.py)



## 使用方法

### 作为命令行工具使用

基本用法：

```bash
python img_downloader.py -i urls.txt -o ./images
```

其中，`urls.txt`是包含图片URL的文本文件，每行一个URL。

### 完整参数说明

有两种方式

请在脚本所在目录,运行如下命令查看用法

```bash
python img_downloader.py -h
```

或者用绝对路径引用此脚本

```powershell
python C:\repos\scripts\wp\woocommerce\woo_df\image_downloader.py -h
```



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

通过绝对路径的方式来调用脚本

```bash
py C:\repos\scripts\wp\woocommerce\woo_df\pys\image_downloader.py -c -n -R auto -k -d .\csvy\ -o ./ccc -O
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



### 配置代理 python命令行环境代理

部分网站的图片直接下不动,需要走代理

如果是powershell下,打开cfw/verge,可以赋值代理环境变量下载图片

得到的命令行形如:(配置临时生效,如果要长期生效,需要修改用户或系统级环境变量)

```powershell
$env:HTTP_PROXY="http://127.0.0.1:7897"; $env:HTTPS_PROXY="http://127.0.0.1:7897"
```



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

您可以根据需要进一步扩展此下载器，例如添加代理支持、更多的自定义选项或集成到其他项目中。

​        

## 细节

### 会话对象

**初始化会话**：

```python
self.session = requests.Session()
```



- **会话管理**：创建一个`requests.Session`对象，用于管理HTTP会话。
- **持久连接**：`requests.Session`会保持连接的持久性，这意味着在同一个会话中进行多次请求时，可以重用TCP连接，从而提高性能。
- **会话级别的配置**：你可以在这个会话对象上设置一些会话级别的配置，如默认的请求头、Cookie、超时时间等。

### 设置默认请求头

```python
self.session.headers.update(self.headers)
```



- **自定义User-Agent**：通过`self.headers`中的`"User-Agent"`键值对，设置自定义的User-Agent。这可以模拟不同的浏览器或客户端，有时可以避免被某些网站的反爬虫机制阻止。
- **其他请求头**：除了User-Agent，你还可以在`self.headers`中设置其他请求头信息（如`Accept`、`Accept-Language`等），这些信息可以帮助服务器更好地处理你的请求。
- **一致性**：在同一个会话中，所有请求都会使用相同的请求头，除非你在特定请求中覆盖这些头信息。

### 示例

假设你的`self.headers`如下：

```python
self.headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"}
```



那么在初始化会话并更新请求头后，所有通过这个会话发起的请求都会包含这个自定义的User-Agent。

```python
self.session = requests.Session()
self.session.headers.update(self.headers)

# 发起一个请求
response = self.session.get('https://example.com/image.jpg')
```



在这个例子中，`response`的请求会自动包含`self.headers`中定义的User-Agent。

### 总结

- **初始化会话**：创建一个持久化的HTTP会话对象。
- **设置默认请求头**：确保所有请求使用相同的自定义请求头，提高请求的一致性和可能的性能优化。

这样做有助于提高代码的可维护性和性能，同时也确保了请求的一致性。

## urlparse模块的使用

[urllib.parse --- 将 URL 解析为组件 — Python 3.13.3 文档](https://docs.python.org/zh-cn/3.13/library/urllib.parse.html)

`urlparse` 是 Python 标准库中的一个模块，用于解析 URL 字符串为组件（如协议、域名、路径、参数等），便于对 URL 进行分析和操作。它在 Python 2 中是 `urlparse` 模块，在 Python 3 中被整合到 `urllib.parse` 模块中。

在 **Python 3** 中，你应该使用：

```python
from urllib.parse import urlparse
```

---

### 🧩 基本用法

- `urlparse(urlstring, scheme='', allow_fragments=True)`

#### 参数说明：
- `urlstring`: 需要解析的 URL 字符串。
- `scheme`: 默认协议（如果 URL 中没有指定的话）。
- `allow_fragments`: 是否允许 URL 片段（即 `#xxx` 部分）。

#### 返回值：

返回一个 `ParseResult` 对象，包含以下属性：

| 属性名     | 含义                          |
| ---------- | ----------------------------- |
| `scheme`   | 协议（如 http、https）        |
| `netloc`   | 网络位置（域名/IP + 端口）    |
| `path`     | 路径部分                      |
| `params`   | 路径参数（较少使用）          |
| `query`    | 查询参数（即 `?` 后面的内容） |
| `fragment` | 片段标识（即 `#` 后面的部分） |

---

### 📌 示例代码：

```python
from urllib.parse import urlparse

url = "https://www.example.com:8080/path/to/page?name=value&key=123#section-2"
parsed = urlparse(url)

print("Scheme:", parsed.scheme)
print("Netloc:", parsed.netloc)
print("Path:", parsed.path)
print("Params:", parsed.params)
print("Query:", parsed.query)
print("Fragment:", parsed.fragment)
```

#### 输出结果：
```
Scheme: https
Netloc: www.example.com:8080
Path: /path/to/page
Params: 
Query: name=value&key=123
Fragment: section-2
```

---

### 🔁 反向操作：将解析后的结果组合成 URL

可以使用 `urlunparse()` 将 `ParseResult` 或元组重新组合为 URL：

```python
from urllib.parse import urlunparse

data = ('https', 'www.example.com:8080', '/path/to/page', '', 'name=value&key=123', 'section-2')
url = urlunparse(data)
print(url)
```

输出：
```
https://www.example.com:8080/path/to/page?name=value&key=123#section-2
```

---

### 🧠 补充说明：

- 如果你只想获取查询参数部分，并进一步解析键值对，可以配合 `parse_qs()` 或 `parse_qsl()` 使用：

```python
from urllib.parse import parse_qs

query = parsed.query
params = parse_qs(query)
print(params)
```

输出：
```
{'name': ['value'], 'key': ['123']}
```

---

### 🚫 注意事项：

- `urlparse` 不会验证 URL 的合法性，只负责解析格式。
- 对于相对路径或不完整的 URL，可以传入默认 `scheme` 来辅助解析。

---

如果你正在处理网络爬虫、API 请求解析或链接提取任务，`urlparse`（或 Python 3 的 `urllib.parse.urlparse`）是非常实用的工具。

## url百分号解码🎈

[urllib.parse --- 将 URL 解析为组件 unquote — Python  文档](https://docs.python.org/zh-cn/3.13/library/urllib.parse.html#urllib.parse.unquote)

`unquote` 是 Python 中 `urllib.parse` 模块提供的一个函数，常用于解码 URL 编码（也称作百分号编码）的字符串。在 URL 中，某些特殊字符需要进行编码以确保传输安全，例如空格会被编码成 `%20`。

### 主要功能

- 将 URL 编码的字符串转换回原始字符串。
- 解码规则是将 `%xx` 替换为对应的字节值，例如 `%3F` 被替换为 `?`。

当你遇到一个包含`%`的url时,通常是特殊字符被编码成`%xx`的形式,人类难以直接阅读,你可以使用`unquote`将`%xx`解码回人类可读的字符

例如你需要根据一个url链接获取改url代表的资源的名称,如果url中有%编码就不容易阅读,因此可以考虑对其进行解码

### 语法

```
python

urllib.parse.unquote(string, encoding='utf-8', errors='replace')
```

### 参数说明

1. **string**: 需要解码的字符串。
2. **encoding**: 输入字符串使用的编码，默认是 `'utf-8'`。
3. **errors**: 处理解码失败时的方式，默认是 `'replace'`，也可以选择 `'strict'` 或 `'ignore'`。

### 返回值

返回解码后的字符串。

### 示例代码

```python
pythonfrom urllib.parse import unquote

encoded_str = "Hello%21%20World%3F"
decoded_str = unquote(encoded_str)
print(decoded_str)  # 输出: Hello! World?
```

又比如:

```python
from urllib.parse import unquote

encoded = "https://www.example.com/search?q=%E5%92%96%E5%95%A1%E6%9C%BA"
decoded = unquote(encoded)
print(decoded)  # 输出: https://www.example.com/search?q=咖啡机
# 这里%E5%92%96%E5%95%A1%E6%9C%BA人类难以直接阅读,将其解码后,得到"咖啡机"
```



### 常见用途

1. 解析 URL 查询参数时，去除 URL 编码。
2. 处理从网页表单提交的数据，这些数据通常会经过 URL 编码。
3. 在构建 API 请求时，对服务器返回的 URL 编码字符串进行解码。

### 注意事项

- 如果输入字符串中包含无效的百分比编码（如 `%zz`），`unquote` 默认会尝试用替代字符处理，具体行为由 `errors` 参数决定。
- 如果编码格式不是 UTF-8，需要手动指定 `encoding` 参数。

## 探测请求头|http head请求

**发送一个 HTTP HEAD 请求**来检查目标图片 URL 是否存在和可访问，而不实际下载整个文件。

### 相关代码片段

#### 发送head请求

```python
head_response = self.session.head(
    url=url, timeout=self.timeout, verify=self.verify_ssl
)
```

- **`self.session.head(...)`**：使用 `requests.Session()` 发送一个 **HEAD 请求** 到指定的 `url`。
- **`timeout=self.timeout`**：设置请求超时时间（单位为秒），防止程序卡死。
- **`verify=self.verify_ssl`**：控制是否验证 SSL 证书。若为 `False`，则忽略 HTTPS 证书错误（适用于测试环境或自签名证书）。

> HEAD 请求只会获取响应头（headers），而不会下载响应体（body），因此非常高效，适合用于探测资源是否存在。

---

#### 根据相应决定异常抛出行为

```python
head_response.raise_for_status()
```

- 这个方法会根据 HTTP 响应状态码判断是否抛出异常：
  - 如果返回的状态码是 2xx（如 200 OK），不会抛出异常。
  - 如果是 4xx 或 5xx 错误（例如 404、500），就会抛出 `HTTPError` 异常，进入 `except` 分支。

---

### 🧠 在你的代码中起到的作用

在 `_download_single_image()` 方法中：

1. **提前检查链接有效性**：
   - 避免对无效链接进行大文件下载，节省时间和带宽。
   - 提高用户体验，在真正下载前就知道这个链接可能有问题。

2. **配合重试机制**：
   - 如果 HEAD 请求失败，会触发重试逻辑（最多尝试 `retry_times` 次）。
   - 重试之间有短暂延迟，避免瞬间大量请求导致被封 IP。

3. **日志记录与统计**：
   - 如果最终 HEAD 请求都失败了，则记录为“下载失败”，并计入统计。

---

### ✅ 示例说明

假设你要下载这张图片：

```python
url = "https://example.com/image.jpg"
```

执行：

```python
head_response = self.session.head(url, timeout=30, verify=False)
head_response.raise_for_status()
```

可能出现的情况：

| 状态码 | 含义                   | raise_for_status() 行为 |
| ------ | ---------------------- | ----------------------- |
| 200    | 成功，资源存在         | 不抛异常                |
| 404    | 文件不存在             | 抛出 HTTPError          |
| 500    | 服务器内部错误         | 抛出 HTTPError          |
| 超时   | 未收到响应（非状态码） | 抛出 Timeout 异常       |

---

### 📝 总结

| 行为                           | 说明                                           |
| ------------------------------ | ---------------------------------------------- |
| 使用 `head()`                  | 只请求头部信息，不下载内容，快速检查资源可用性 |
| 设置 `timeout` 和 `verify_ssl` | 控制安全性和稳定性                             |
| `raise_for_status()`           | 自动抛错，简化异常处理                         |
| 结合 `try-except` 和重试机制   | 增强网络健壮性                                 |

---

### 💡 跳过head试探请求

如果你希望进一步提高性能，可以跳过 HEAD 请求（尤其在批量下载时），直接开始 GET 请求并用 `response.headers` 获取信息。HEAD 请求虽然轻量，但仍然是一个完整的 HTTP 请求。

## 文件路径和扩展名处理splitext

`os.path.splitext()` 是 Python 标准库 `os.path` 模块中的一个函数，用于**将文件路径分割为「文件名主体」和「扩展名」两部分**。

---

### 🧩 函数定义：

```python
os.path.splitext(path)
```

#### 参数说明：
- `path`: 一个字符串形式的文件路径（可以是相对路径或绝对路径）。

#### 返回值：
返回一个 **元组 `(root, ext)`**：
- `root`: 文件主体（不带扩展名的部分）
- `ext`: 扩展名（包含点号`.`）

---

### ✅ 典型用法示例：

```python
import os

# 示例路径
path = "/home/user/documents/report.txt"

# 使用 splitext 分割文件名
root, ext = os.path.splitext(path)

print("Root:", root)   # 输出: /home/user/documents/report
print("Ext:", ext)     # 输出: .txt
```

---

### 🔁 反向拼接：使用 `os.path` 的其他函数

如果你想把文件名和扩展名重新组合起来，可以用 `os.path.join()`：

```python
new_path = os.path.join(root, "backup" + ext)
print(new_path)  # 输出: /home/user/documents/report/backup.txt
```

---

### 📌 注意事项：

#### 1. **只分割最后一个点号**

```python
os.path.splitext("image.version.jpg")
# 返回: ('image.version', '.jpg')
```

只会按最后一个 `.` 分割，不会影响前面的点号。

#### 2. **没有扩展名时，返回空字符串**

```python
os.path.splitext("/path/to/file")
# 返回: ('/path/to/file', '')
```

#### 3. **路径中含多个点号也没问题**

```python
os.path.splitext("data.tar.gz")
# 返回: ('data.tar', '.gz')
```

> ⚠️ 如果你希望处理 `.tar.gz`、`.tar.bz2` 等复合后缀，可以考虑使用 `pathlib.Path`（见下文）。

---

### 🆕 更现代的方式：使用 `pathlib.Path`

Python 3.4+ 推荐使用 `pathlib` 模块，更面向对象、功能更强。

```python
from pathlib import Path

p = Path("data.tar.gz")

print(p.stem)   # data.tar （去掉最后一个扩展名）
print(p.suffix) # .gz

# 多层扩展名处理
print(p.suffixes)  # ['.tar', '.gz']
print(p.with_suffix(''))  # data.tar （去掉最后一个后缀）
```

---

### ✅ 实际应用场景

#### 场景1：批量重命名文件，保留原扩展名

```python
import os

filename = "photo.jpg"
root, ext = os.path.splitext(filename)
new_filename = f"resized_{root}{ext}"
print(new_filename)  # resized_photo.jpg
```

#### 场景2：筛选特定类型的文件（如 `.txt`）

```python
import os

for file in os.listdir("."):
    if os.path.isfile(file):
        _, ext = os.path.splitext(file)
        if ext == ".txt":
            print("文本文件:", file)
```

---

### 🧠 总结

| 功能                 | 方法                                               |
| -------------------- | -------------------------------------------------- |
| 分割文件名和扩展名   | `os.path.splitext("file.txt") → ('file', '.txt')`  |
| 获取不含扩展的文件名 | `root = os.path.splitext(filename)[0]`             |
| 添加/替换扩展名      | `newname = root + ".bak"`                          |
| 更强大的扩展名处理   | 使用 `pathlib.Path().suffix`, `.stem`, `.suffixes` |

---

如果你正在写脚本、批量处理文件或开发工具类程序，`os.path.splitext()` 是一个非常实用的小工具。当然，在 Python 3 中推荐优先使用 `pathlib` 来进行更简洁的操作。
