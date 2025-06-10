[toc]

## 图片压缩模块

- 支持PNG、JPG压缩和WEBP格式转换,分辨率调整(等比例缩放)

- 通常将jpg,png转换为webp会有较好的效果，尤其是png->webp的效果最明显

- 支持命令行参数调用和程序化调用

- ...

  

## linux服务器部署代码🎈



### 安装python和pip

以ubuntu为例,通常自带python,但是pip可能不可以用

现在建议使用python3.11以上的版本,连同pip一起安装

```bash
# 更新系统包索引
sudo apt update
sudo apt install -y software-properties-common

# 添加 deadsnakes 仓库
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update

# 安装 Python 3.12
sudo apt install -y python3.12

# 可选：设置 python3 默认版本为 3.12（慎用）
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# 检查安装成功
python3.12 --version

# 有些情况下 pip 需要单独安装
sudo apt install -y python3.12-venv python3.12-dev

# 手动安装 pip（如果缺失）
curl -sS https://bootstrap.pypa.io/get-pip.py | sudo python3.12
python3.12 -m pip --version

```

#### 安装python依赖包

> 对于国内网络环境,建议配置国内源(比如清华源)来加速依赖包的下载(国外的服务器本身就有加速效果,可以不用配置)

```cmd
# 通常对本地windows系统配置下面这条命令即可(服务器不用配)
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
```

---

然后根据情况,执行下面的某一条pip命令

对于linux系统

```bash
pip install -r /repos/scripts/wp/woocommerce/woo_df/requirements_linux.txt
```

对于windows系统

```bash
pip install -r C:\repos\scripts\wp\woocommerce\woo_df\requirements.txt
```



### 安装git

系统一般自带,如果不存在,使用以下命令行安装

```bash
sudo apt install git

```



### 第一次获取代码

将代码克隆到默认目录下`/repos/scripts`的git命令行

```bash
git clone https://gitee.com/xuchaoxin1375/scripts.git /repos/scripts

```

之后不需要再执行此命令,如果要更行代码,执行以下命令

### 配置环境变量

根据自己的情况选择配置命令行(通常默认bash)

#### 对于bash

```bash
 echo 'export PYTHONPATH="/repos/scripts/wp/woocommerce/woo_df:$PYTHONPATH"' >> ~/.bashrc
```

#### 对于zsh

```bash
 echo 'export PYTHONPATH="/repos/scripts/wp/woocommerce/woo_df:$PYTHONPATH"' >> ~/.zshrc
```



### 更新代码

```bash
cd /repos/scripts
git pull origin main

```

获取最新版本

```bash
[oh-my-zsh] Random theme 'junkfood' loaded
#( 05/30/25@ 7:35AM )( root@wnx0020303 ):~
   cd /repos/scripts
#( 05/30/25@ 7:35AM )( root@wnx0020303 ):/repos/scripts@main✔
   git pull origin main
```



## linux压缩服务器上的图片🎈



### 推荐的命令行和参数

主要针对老方法(api上传的图片未经过处理的情况),以及其他未压缩过图片的站点

参数序列`-R auto -p -F  -O -W  -k -A -r 1000 800 `

- 批量压缩多个目录,可以使用`-I`指定包含这些要压缩的目录的文本文件
- 跳过小图压缩,可以使用`-T`;小图压缩节约的空间比较有限,如果为了快速,可以考虑跳过小图,比如50KB以上才压缩);或者二压缩也可以考虑使用`-T`来针对性处理大图(比如版本更新,支持分辨率缩小,这时候二次运行建议使用`-T`)

linux服务器上的命令(测试单个链接)

```bash

python3 /repos/scripts/wp/woocommerce/woo_df/pys/image_compresser.py   -R auto -p -F  -O -W  -k -A -r 1000 800 -i "替换此串为要被处理路径" . 
```

### 批量对指定站点目录压缩

使用包含目录列表的文件作为输入

```bash
python3 /repos/scripts/wp/woocommerce/woo_df/pys/image_compresser.py   -R auto -p -F  -O -W  -k  -A -r 1000 800 -I "/www/wwwroot/pys/test_compress.txt"
```

### 跳过小图压缩

- 同上,追加`-T `并指定一个整数(表示KB数,对于不小于该大小的图片才处理)

```bash
python3 /repos/scripts/wp/woocommerce/woo_df/pys/image_compresser.py   -R auto -p -F  -O -W  -k  -A -r 1000 800  -T -I "/www/wwwroot/pys/test_compress.txt" 
```

### 推荐的目录或文件磁盘占用分析工具

dust是一个开源的多线程的磁盘占用分析工具,功能丰富[bootandy/dust: A more intuitive version of du in rust](https://github.com/bootandy/dust)

对于ubuntu系统

```bash
cd ~
# 下载链接请到项目的release页面获取最新链接,下面的链接作为例子,下载后保存为dust.deb文件
wget -O dust.deb https://github.com/bootandy/dust/releases/download/v1.2.1/du-dust_1.2.1-1_amd64.deb
sudo dpkg -i dust.deb
rm dust.deb -v #移除安装包
#简单用例
dust .

```

#### 分析网站目录

```
dust /www/
```

### 清除宝塔中mysql二进制日志文件

宝塔中首页数据库配置mysql,里面的二进制日志功能会占用大量磁盘,可以考虑关闭,然后用下面的命令移除掉这些备份文件

```bash
cd /www/server/data
rm  mysql-bin.0* -v
```



## windows本地压缩

下面用的参数和选项针对我们的业务配置的

需要的软件环境一样,python和git,缺少的分别安装即可(联想应用商店可以快速下载git和python)

### 配置python 模块环境变量

```cmd
setx PYTHONPATH C:\repos\scripts\wp\woocommerce\woo_df

```

利用git获取代码

```
git clone https://gitee.com/xuchaoxin1375/scripts.git C:/repos/scripts
```

配置完上述内容,重启命令行窗口或者新开一个命令行窗口使其生效,如果有开启的vscode这种的也要重启窗口生效



如果需要集中批量压缩,可以使用如下参数(`-i`后面更上需要处理的图片(文件夹)路径)

```bash
-R auto -p -F  -O -k -f webp  -r 1000 800  -i

```

```bash
#⚡️[Administrator@CXXUDESK][~\Desktop][14:50:16][UP:12.11Days]
PS> py C:\repos\scripts\wp\woocommerce\woo_df\pys\image_compresser.py   -R auto -p -F  -O -k -f webp  -r 1000 800  -i C:\Users\Administrator\Pictures\imgs_demo
```



## FAQ

### 图片处理失败🎈

通常对于jpg,png,webp这三种最常见的格式有良好的兼容性

但是如果图片本身是不完整或者打开是一个破图,那么压缩通常会失败

> 在我们的业务中,产品图片下载后就会进行压缩,如果下载环节下载的图片是不正常的(比如使用图片查看器或者系统自带的照片程序或者浏览器看图渲染不出来或者不正常,说明问题很可能出现在下载环节)
>
> 图片下载的结果有几类,理想情况下图片下载成功(并且能够被打开和顺利渲染出来);
>
> 第二类是不理想的情况,比如直接下载不了(比如403等反爬行为);
>
> 另外还可能是伪成功的,下载器提示下载成功,对应的路径也确实出现了对应名字的文件,但是其体积是不正常的,比如只有0MB,这种情况下也算做下载失败的情况,需要你专门检查本地的文件是否正常
>
> 图片不正常可以考虑开代理(将代理的环境变量复制到powershell中),然后重新尝试(也可以用curl或者iwr 命令来测试单个图片连接)



## 图片分辨率调整

```python
# resampling filters (also defined in Imaging.h)
class Resampling(IntEnum):
    NEAREST = 0
    BOX = 4
    BILINEAR = 2
    HAMMING = 5
    BICUBIC = 3
    LANCZOS = 1
```

这段代码定义了一个名为`Resampling`的枚举类，它继承自`IntEnum`，表示图像重采样(缩放/变换)时使用的不同滤波方法。每种方法都有一个对应的整数值：

1. `NEAREST`(最近邻) = 0
   - 最简单的插值方法，直接取最近的像素值
   - 速度快但质量较低，可能出现锯齿
2. `BILINEAR`(双线性) = 2
   - 通过对周围4个像素进行线性加权计算
   - 质量较好，速度适中
3. `BICUBIC`(双三次) = 3
   - 使用周围16个像素进行三次插值
   - 质量更高但计算量更大
4. `LANCZOS`(兰索斯) = 1
   - 使用高质量的重采样滤波器
   - 能很好地保留细节但计算成本高
5. `BOX`(盒式) = 4
   - 简单的平均滤波器
   - 适用于缩小图像
6. `HAMMING`(汉明) = 5
   - 使用汉明窗函数
   - 平衡了振铃效应和锐度

 

## PIL库的简单介绍

在 Python 的 PIL（Pillow）库中，`Image.save()` 方法用于将图像保存到文件。

---

### 📌 基本语法：

```python
img.save(fp, format=None, **params)
```

---

### ✅ 参数说明：

| 参数名     | 类型                                        | 说明                                                         |
| ---------- | ------------------------------------------- | ------------------------------------------------------------ |
| `fp`       | 文件路径（字符串）或文件对象（file object） | 指定要保存的文件路径或已经打开的文件对象。例如 `'image.jpg'` 或 `open('image.png', 'wb')` |
| `format`   | 字符串（可选）                              | 强制指定保存的图像格式（如 `'PNG'`, `'JPEG'` 等）。如果不指定，会根据文件扩展名自动判断；如果没有扩展名或无法识别，则抛出异常。 |
| `**params` | 关键字参数                                  | 不同格式支持的额外参数，比如 JPEG 支持 `quality`、PNG 支配 `optimize` 和 `compress_level` 等 |

---

### 常见格式及其参数

### 1. **JPEG / JPG**

```python
img.save('output.jpg', 'JPEG', quality=85, optimize=True, progressive=True)
```

- `quality`: 图像质量，范围从 1（最差）到 95（最好），默认是 75。
- `optimize`: 是否优化颜色数，通常设为 `True` 可减小文件体积。
- `progressive`: 是否保存为渐进式 JPEG（网页加载更平滑）。

---

### 2. **PNG**

```python
img.save('output.png', 'PNG', optimize=True, compress_level=9)
```

- `optimize`: 是否尝试优化压缩（默认 `False`），设为 `True` 可能会增加处理时间但减小体积。
- `compress_level`: 压缩级别，0（无压缩）~9（最大压缩），默认是 6。

---

### 3. **GIF**

```python
img.save('output.gif', save_all=True, append_images=images[1:], loop=0, duration=100, disposal=2)
```

- `save_all`: 保存所有帧（用于多帧图像，如动图）
- `append_images`: 要追加保存的图像帧列表（必须是 Image 对象组成的列表）
- `loop`: 动画循环次数，0 表示无限循环
- `duration`: 每帧显示时间（毫秒）
- `disposal`: 如何处理帧之间的清除方式（0-3）

---

### 4. **TIFF**

```python
img.save('output.tiff', compression="tiff_deflate")
```

- `compression`: 压缩方式，可以是 `"none"`, `"tiff_lzw"`, `"tiff_deflate"` 等。

---

### 5. **WebP**

```python
img.save('output.webp', 'WEBP', quality=80, lossless=False)
```

- `quality`: 质量值（有损压缩时使用）
- `lossless`: 是否使用无损压缩（布尔值）

---

### 🔍示例代码

```python
from PIL import Image

# 打开图像
img = Image.open('input.jpg')

# 保存为 JPEG，设置质量为 90
img.save('output.jpg', 'JPEG', quality=90)

# 保存为 PNG，并启用压缩优化
img.save('output.png', 'PNG', optimize=True, compress_level=9)

# 保存为 GIF 动图
frames = [frame.convert('P') for frame in ImageSequence.Iterator(img)]
frames[0].save('animation.gif', save_all=True, append_images=frames[1:], duration=200, loop=0)
```

---

### 📚 官方文档参考

- Pillow 文档：https://pillow.readthedocs.io/en/stable/reference/Image.html#PIL.Image.Image.save

---

