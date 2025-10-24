[toc]

## 图片压缩模块

- 支持PNG、JPG压缩和WEBP格式转换,分辨率调整(等比例缩放)

- 通常将jpg,png转换为webp会有较好的效果，尤其是png->webp的效果最明显

- 支持命令行参数调用和程序化调用

- ...


### 图片格式选择

现代化图片格式主要有webp和avif,它们分别诞生于2010年和2019年,最大的特点是前者兼容性很好,后者在文件体积的压制上有优势

综合考虑之下,目前我们选择webp作为首选的图片格式

实验表明,即便下载到的图片已经是webp或者avif,它们都可以进一步被本文配套的代码进一步压缩,因此代码默认情况下不会跳过webp,avif图片的处理,对于webp图片,会尝试压缩成更小的webp,对于avif图片,则会转换成webp

> 需要注意的是,avif由于相对较新,许多软件不支持,windows10系统需要安装对应的功能扩展包才能查看,而honeyview这类看图软件也无法打开avif图片;
>
> 此外,在python代码中,处理avif格式的图片需要显式`import pillow_avif`  # 必须导入以启用 AVIF 支持(但无需调用)
>
> 不过虽然webp图片相对于avif更加容易被打开(特别是软件不是很新的情况下),但对于ltsc这类精简版的windows系统默认的看图软件是可能需要安装webp功能扩展才能查看

单从这套代码压缩同一个jpg图片(x.jpg->x.webp以及x.jpg->x.avif),压缩成webp格式可以节约的磁盘占用更加显著,因此我们用webp

### 特性说明

- 此模可以压缩绝大多数图片,甚至可以将gif转换并压缩成图片

  - 支持的常见格式包括(但不限于):

    ```python
    SUPPORT_IMAGE_FORMATS_NAME = (
        "jpg",
        "jpeg",
        "png",
        "webp",
        "heic",
        "tif",
        "tiff",
        "bmp",
        "gif",
        "avif"
    )
    ```

  - 具体的格式可通过以下python代码查询(通过修改`comutils.py`文件可以增加更多格式,但是现在的格式配置几乎满足所有常见图片格式需求,基本不用改动)
  
    ```python
    from comutils import SUPPORT_IMAGE_FORMATS_NAME
    print(SUPPORT_IMAGE_FORMATS_NAME)
    ```
  
    
  
- 然而,个别情况会压缩失败,不过这可能是图片本身不完整(因为下载过程中发生错误),或者下载的是个破图,都会导致压缩失败
  - 这其中有一些图片虽然python的PIL库无法直接正确处理,但是可考虑用其他专门的图片处理程序来压缩(比如xnconvert,但是我们主要还是用python压缩,它更灵活,压缩速度更快,而且跨平台,只有在极端情况下会压缩不了)
  - 总之可以互补两种方式,先用python处理图片(而且可以边下边压缩,会保存成webp格式),剩下的图片(如果比较多)可以尝试用xnconvert来处理

### 基本用例

本文配套的图片压缩命令行基本用例,具体可以查看`image_compresser.py`的使用帮助

不过大多数情况下不需要自己编写压缩命令行,本地建站时会生成好配套的命令行

```bash
PS> py C:\repos\scripts\wp\woocommerce\woo_df\pys\image_compresser.py -i .\y.jpg -o y2.avif
skip_format:[]
压缩白名单: ('jpg', 'jpeg', 'png', 'webp', 'heic', 'tif', 'tiff', 'bmp', 'gif', 'avif')
target fmt:[]
2025-09-06 16:54:57,916 - imgcompresser - INFO - 开始压缩: ['.\\y.jpg']
2025-09-06 16:54:57,916 - imgcompresser - INFO - 输入格式:.jpg
2025-09-06 16:54:57,916 - imgcompresser - DEBUG - 原始文件大小: 3522498
仅提供了输出路径:[y2.avif]
输出文件: y2.avif
2025-09-06 16:54:57,916 - imgcompresser - INFO - 输出格式:.avif
2025-09-06 16:54:57,930 - imgcompresser - DEBUG - 临时文件: y2.tmp.avif
2025-09-06 16:54:59,079 - imgcompresser - INFO - 保存临时文件: y2.tmp.avif
存储模式:remove_original:False 格式变化: jpg -> avif
处理后的文件体积变小,覆盖原文件: y2.avif
2025-09-06 16:54:59,080 - imgcompresser - INFO - ('✅', '体积变化(-): -62.36%', '原始大小: 3439.94KB, ', '压缩后: 1294.80KB, ', '压缩成功: .\\y.jpg -> y2.avif\n', '压缩参数: quality=70', '分辨率变化:(4096, 2656)->(4096, 2656) ; 分辨率限制:None')
```



### 移除破图或假图

将不超过200B的图片删除的命令行(powershell中运行)

> 我把大小很小的图片视为破图或者假图,通常这些图片是下载过程中服务器返回假图

```powershell
ls -File |where{$_.Length -le 200}|rm -Verbose
```

如果为了提高准确性,可以进一步制定格式

```powershell
ls -File *jpg |where{$_.Length -le 200}|rm -Verbose
```



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

### 安装python依赖

> 对于国内网络环境,建议配置国内源(比如清华源)来加速依赖包的下载(国外的服务器本身就有加速效果,可以不用配置)
>
> windows和linux系统有各自的依赖版本(个别库在不同系统上有名称差别)

```cmd
# 通常对本地windows系统配置下面这条命令即可(服务器不用配)
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
```

---

然后根据情况,执行下面的某一条pip命令

#### 对于linux系统

```bash
pip install -r /repos/scripts/wp/woocommerce/woo_df/requirements_linux.txt
```

如果pip不存在,请自行查阅资料并安装

例如ubuntu系统

```bash
# 1. 更新包列表
sudo apt update

# 2. 安装 pip for Python 3
sudo apt install python3-pip

# 3. （可选）设置别名
echo 'alias pip=pip3' >> ~/.bashrc
source ~/.bashrc

# 4. （可选）升级 pip
pip3 install --upgrade pip

# 5. （推荐）安装虚拟环境支持
sudo apt install python3-venv
```



#### 对于windows系统

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

### 配置环境变量🎈

根据自己的情况选择配置命令行(通常默认bash)

> 注意,执行下面的代码后,要记得刷新配置文件,否则不会生效;最简单的方案就是source ~/.bashrc;source ~/.zshrc;
> 或者再开一个bash/zsh会话

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



## 原地压缩@压缩服务器上的图片🎈



### 推荐的命令行和参数

主要针对老方法(api上传的图片未经过处理的情况),以及其他未压缩过图片的站点

参数序列`-R auto -p -F  -O -W  -k -A -r 1000 800 `

- 批量压缩多个目录,可以使用`-I`指定包含这些要压缩的目录的文本文件
- 跳过小图压缩,可以使用`-T`;小图压缩节约的空间比较有限,如果为了快速,可以考虑跳过小图,比如50KB以上才压缩);或者二压缩也可以考虑使用`-T`来针对性处理大图(比如版本更新,支持分辨率缩小,这时候二次运行建议使用`-T`)

linux服务器上的命令(测试单个链接)

```bash

python3 /repos/scripts/wp/woocommerce/woo_df/pys/image_compresser.py   -R auto -p -F  -O -W  -k -A -r 1000 800 -i "替换此串为要被处理路径" . 
```

如果要保留分辨率压缩,可以取消上述命令行中的`-r 1000 800`

### 批量对指定站点目录压缩

使用包含目录列表的文件作为输入

```bash
python3 /repos/scripts/wp/woocommerce/woo_df/pys/image_compresser.py   -R auto -p -F  -O -W  -k  -A -r 1000 800 -I "/www/wwwroot/pys/test_compress.txt"
```

### 跳过小图压缩|针对性压缩大图

- 同上,追加`-T `并指定一个整数(表示KB数,对于不小于该大小的图片才处理)

不过,也可以支持更灵活的指定方式,可以配合`-I`选项通过一个文本文件来批量指定需要压缩的图片文件或者包含图片文件的目录(也就是说文件路径和目录路径都是支持的,如果脚本遍历每个路径,如果识别到的路径是图片文件,直接压缩,否则尝试找到指定目录路径中下的图片进行处理)

例如,我使用某个查找脚本(比如linux系统上的find,支持按照复杂的条件查找,比如图片大小,修改时间等筛选出一批需要压缩的文件)

> 虽然本文提供的脚本也支持基本的大小过滤和格式过滤,但是使用专门的工具会更灵活,能满足更加复杂的需求

#### 案例:扫描所有网站里的大图并压缩

现在,假设我想要找出所有的站点中指定目录下的大小超过300k的png图片,然后对它们进行针对性压缩

不妨使用find命令查找并输出目标文件列表

> 假设当前目录为`/www/`找到的文件列表会输出到`imgs.txt`文件中

```bash
#!/bin/bash
cd /
ROOT="/www/wwwroot"

find "$ROOT" \
  -path "*/wordpress/wp-content/uploads/2025/*.png" \
  -size +300k \
  -type f \
  | tee imgs.txt
```

如果网站和文件数量很多,上述过程可能需要几分钟

```bash
python3 /repos/scripts/wp/woocommerce/woo_df/pys/image_compresser.py   -R auto -p -F  -O -W  -k -w 64 -T 200 -I imgs.txt 
```

如果图片数量多,并且破图多,上述脚本可能会需要比较长时间处理(注意,如果要控制图片分辨率,可以使用`-r`,不过如果要压缩的包含网站首页广告图,就要注意分辨率不能轻易调小,可能导致位置观感不佳)

### 清除宝塔中mysql二进制日志文件

宝塔中首页数据库配置mysql,里面的二进制日志功能会占用大量磁盘,可以考虑关闭,然后用下面的命令移除掉这些备份文件

```bash
cd /www/server/data
rm  mysql-bin.0* -v
```

### 清除wc-import目录

对于早期用wp后台自带的woocommerce 上传csv的方式导入产品,会将csv文件上传到服务器,这些文件会占用空间,建议删除掉

执行以下脚本进行扫描和删除

```bash
#!/bin/bash

# 查找并删除所有 wp-content/uploads/wc-imports 目录
find /www/wwwroot/ -type d -path "*/wp-content/uploads/wc-imports" -print -exec rm -rf {} +

echo "所有 wp-content/uploads/wc-imports 目录已删除。"
```



## windows本地压缩

下面用的参数和选项针对我们的业务配置的

需要的软件环境一样,python和git,缺少的分别安装即可(联想应用商店可以快速下载git和python)

### 配置python 模块环境变量

```cmd
setx PYTHONPATH C:\repos\scripts\wp\woocommerce\woo_df

```

利用git获取代码

```cmd
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

 
