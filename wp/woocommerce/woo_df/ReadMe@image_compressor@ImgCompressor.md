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

本文配套的图片压缩命令行基本用例,具体可以查看`image_compressor.py`的使用帮助

不过大多数情况下不需要自己编写压缩命令行,本地建站时会生成好配套的命令行

```bash
PS> py C:\repos\scripts\wp\woocommerce\woo_df\pys\image_compressor.py -i .\y.jpg -o y2.avif
skip_format:[]
压缩白名单: ('jpg', 'jpeg', 'png', 'webp', 'heic', 'tif', 'tiff', 'bmp', 'gif', 'avif')
target fmt:[]
2025-09-06 16:54:57,916 - imgcompressor - INFO - 开始压缩: ['.\\y.jpg']
2025-09-06 16:54:57,916 - imgcompressor - INFO - 输入格式:.jpg
2025-09-06 16:54:57,916 - imgcompressor - DEBUG - 原始文件大小: 3522498
仅提供了输出路径:[y2.avif]
输出文件: y2.avif
2025-09-06 16:54:57,916 - imgcompressor - INFO - 输出格式:.avif
2025-09-06 16:54:57,930 - imgcompressor - DEBUG - 临时文件: y2.tmp.avif
2025-09-06 16:54:59,079 - imgcompressor - INFO - 保存临时文件: y2.tmp.avif
存储模式:remove_original:False 格式变化: jpg -> avif
处理后的文件体积变小,覆盖原文件: y2.avif
2025-09-06 16:54:59,080 - imgcompressor - INFO - ('✅', '体积变化(-): -62.36%', '原始大小: 3439.94KB, ', '压缩后: 1294.80KB, ', '压缩成功: .\\y.jpg -> y2.avif\n', '压缩参数: quality=70', '分辨率变化:(4096, 2656)->(4096, 2656) ; 分辨率限制:None')
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



## clone代码

> 更完整的介绍参考仓库首页的介绍.

```shell
# linux服务器上的代码拉取:
bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh) -U # -F -R

```



## linux服务器配置环境🎈



### python和pip

#### 直接安装

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

#### 使用环境管理安装

新系统(例如ubuntu24)对于直接的pip install会发出警告并终止安装.

考虑使用miniforge(conda)+uv pip的组合来管理python.

具体的做法参考 [Readme@服务器环境配置流程和迁移指南.md](sh\Readme@服务器环境配置流程和迁移指南.md) 中python环境一节

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
pip install -r $woo_df/requirements_linux.txt
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





### 配置环境变量🎈

根据自己的情况选择配置命令行(通常默认bash)

> 注意,执行下面的代码后,要记得刷新配置文件,否则不会生效;最简单的方案就是source ~/.bashrc; source ~/.zshrc;
> 或者再开一个bash/zsh会话

#### 对于bash

```bash
 echo 'export PYTHONPATH="/repos/scripts/wp/woocommerce/woo_df:$PYTHONPATH"' >> ~/.bashrc
```

#### 对于zsh

```bash
 echo 'export PYTHONPATH="/repos/scripts/wp/woocommerce/woo_df:$PYTHONPATH"' >> ~/.zshrc
```



## 原地压缩@压缩服务器上的图片🎈



### 推荐的命令行和参数

主要针对老方法(api上传的图片未经过处理的情况),以及其他未压缩过图片的站点

参数序列`-R auto -p -F -O -W -k -A `

对于需要批量压缩多个目录,可以使用`-I`指定包含这些要压缩的目录的文本文件(即,指定目录白名单)

此外白名单中的条目支持文件路径和目录路径(也就是说图片路径和包含图片的目录路径都是支持的)

> 脚本遍历每个给定的路径,如果识别到的路径是图片文件,直接压缩,否则尝试找到指定目录路径中下的图片进行处理)

#### 跳过小图压缩|针对性压缩大图

在基础参数组合的基础上,追加`-T `并指定一个**整数**(表示KB数,**对于占用不小于该数值的图片才处理**)

- 小图压缩节约的空间比较有限,如果为了快速,可以考虑跳过小图,比如50KB以上才压缩);
- 或者二次运行压缩也可以考虑使用`-T`来针对性处理大图(比如压缩脚本版本更新,对大图的压缩策略做了优化,这时候考虑再运行一次压缩处理,配合使用`-T`跳过小图处理.)

例如,我使用某个查找脚本(比如linux系统上的find,支持按照复杂的条件查找,比如图片大小,修改时间等筛选出一批需要压缩的文件)

> 虽然本文提供的脚本也支持基本的大小过滤和格式过滤,但是使用专门的工具会更灵活,能满足更加复杂的需求;
>
> ```shell
> 例如,跳过指定格式的图片(jpg/png/webp/...)压缩,多个格式用逗号分隔 (default: None)
> -s, --skip-format SKIP_FORMAT
>                         
> ```
>
> 

#### 测试单个图片压缩

```bash

python3 $pys/image_compressor.py   -R auto -p -F -O -W -k -A -r 1000 800 -i "替换此串为要被处理路径" . 
```

如果要保留分辨率压缩,可以取消上述命令行中的`-r 1000 800`;

#### 批量指定目录压缩

使用包含目录列表的文件作为输入.

> 注意考虑广告图的分辨率不要动.`-r 1000 800`仅针对普通产品图片.

简单处理,就是不使用`-r 1000 800`(部分情况下压缩效果没那么好)

稍微精细,但是步骤多一点,也可以考虑分步:

> 如果广告图规律性不强,就不要自动化区分,但是格式一般是png的情况下才会比较占用空间.
>
> 基于这个事实,一个这种的方案是分成两批处理:
>
> - 使用`find`寻找需要处理的png图片,对这部分图片到处理不使用`-r 1000 800`;
>
> - 其他格式(可以用find找出所有非png图片,或压缩脚本的`-s png`),对这部分图片使用`-r 1000 800`;

直接指定顶层目录可能会很慢,考虑使用find过滤出根据具体的目录,例如:

```bash
# 计算相对路径
find /data  -mindepth 3 -maxdepth 5 -type d -path '*/wp-content/uploads/202*' > img_dirs_to_compress.txt
# 但是更推荐绝对路径
find -L /www/wwwroot/  -mindepth 5 -maxdepth 5  -type d -path '*/wp-content/uploads' -print0 | xargs -I % -0  realpath % |tee  img_dirs_to_compress.txt | nl
```

> 更加具体的,可以指定白名单网站域名,检索图片目录,例如:
>

```bash
# 将所有符合条件的目录存入数组
mapfile -t dirs < <(find -L /www/wwwroot/ -mindepth 5 -maxdepth 5 -type d -path '*/wordpress/wp-content/uploads')

# 指定站点名称白名单,扫描这些网站中需要处理的目录(uploads)
cnt=1
result="img_dirs_to_compress.txt"
[[ -e $result ]] && rm "$result" -rf # 清空旧内容
while IFS= read -r pattern; do
    for dir in "${dirs[@]}"; do
        if [[ "$dir" == *"/$pattern/wordpress/wp-content/uploads" ]]; then
            echo "[$((cnt++))]:Processing [$pattern] -> $dir"
            echo "$dir" >> "$result"
        fi
    done
done < "img_dirs.txt"

```



```bash
# 计算要压缩到路径,保存到白名单"img_dirs_to_compress.txt",
## 从白名单指定,并且执行分辨率处理(默认10线程,可以酌情开高,例如32,64)
python3 $pys/image_compressor.py   -R auto -p -F  -O -W  -k  -A -w 64 -I "img_dirs_to_compress.txt"  -T 50 # -r 1000 800 

# 直接指定一个目录,从该目录递归扫描处理,不执行分辨率处理,跳过50KB以下的图片的处理
python3 $pys/image_compressor.py   -R auto -p -F  -O -W  -k  -A -w 64 -i /www/wwwroot/.../wp-content/uploads/  -T 50
```

### 设置为后台长期运行(终端复用器)

为了防止ssh长期链接中断导致压缩任务被以外停止,建议使用screen这类终端复用器让压缩任务能够更稳定的在后台运行.

```bash
# 创建或者进入image-compress 会话
screen -d -R image-compress
# 启动python环境(如果使用conda来管理python环境管理的话)
conda activate main
# 启动压缩任务.
python3 $pys/image_compressor.py   -R auto -p -F  -O -W  -k  -A -w 64 -I "img_dirs_to_compress.txt"  -T 50
```



#### 案例:扫描所有网站里的大图并压缩

现在,假设我想要找出所有的站点中指定目录下的大小超过`300k`的png图片,然后对它们进行针对性压缩(譬如压缩广告图画质,但对于广告图不要轻易调整其分辨率尺寸)

不妨使用find命令查找并输出目标文件列表

> 假设当前目录为`/www/`找到的文件列表会输出到`imgs.txt`文件中

```bash
#!/bin/bash
cd /www/
ROOT="/www/wwwroot"

find "$ROOT" \
  -path "*/wordpress/wp-content/uploads/2025/*.png" \
  -size +300k \
  -type f \
  | tee imgs.txt
```

如果网站和文件数量很多,上述过程可能需要几分钟

```bash
python3 $pys/image_compressor.py   -R auto -p -F  -O -W  -k -w 64 -T 200 -I imgs.txt 
```

如果图片数量多,并且破图多,上述脚本可能会需要比较长时间处理

注意,如果要控制图片分辨率,可以使用`-r`,不过如果要压缩的包含网站首页广告图,就要注意分辨率不能轻易调小,可能导致位置观感不佳.

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



## windows本地压缩🎈

下面用的参数和选项针对我们的业务配置的

需要的软件环境一样,python和git,缺少的分别安装即可(联想应用商店可以快速下载git和python)

### 配置python 模块环境变量

```cmd
setx PYTHONPATH C:\repos\scripts\wp\woocommerce\woo_df

```

利用git获取代码

```cmd
git clone --recursive --depth 1 --shallow-submodules https://gitee.com/xuchaoxin1375/scripts.git C:/repos/scripts
setx PsModulePath C:/repos/scripts/PS

```

配置完上述内容,重启命令行窗口或者新开一个命令行窗口使其生效,如果有开启的vscode这种的也要重启窗口生效

### 批量压缩

如果需要集中批量压缩,可以使用如下参数(`-i`后面跟上需要处理的图片(文件夹)路径)

```bash
-R auto -p -F  -O -k -f webp  -r 1000 800  -i

```

```bash
#⚡️[Administrator@CXXUDESK][~\Desktop][14:50:16][UP:12.11Days]
PS> python C:\repos\scripts\wp\woocommerce\woo_df\pys\image_compressor.py   -R auto -p -F  -O -k -f webp  -r 1000 800  -i <imgs_demo_dir>
```

### 压缩指定目录中的jpg,png为webp🎈

可以配合powershell完成此任务

```powershell
ls *jpg,*png|% FullName > $home/jpn.txt ;
python C:\repos\scripts\wp\woocommerce\woo_df\pys\image_compressor.py   -R auto -p -F  -O -k -f webp  -r 1000 800  -I $home/jpn.txt

```

### 把指定目录中文件后缀为.jpg,.png的图片批量修改为.webp

定位到图片所在目录,然后可以在文件资源管理器地址栏中输入`pwsh`,执行:

```powershell
ls -File |Rename-Item -NewName {$_.Name -replace '\.jpg$','.webp' } -force

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

##  并发模型选择:线程池还是进程池

建议：**先保留线程池，不要直接切到进程池**。图片压缩通常是“磁盘 I/O + C 扩展编码/解码 + 少量 Python 调度”的混合任务，线程池往往更简单、更稳定、内存更省。只有在压测确认 CPU 被打满需求明显、线程池无法提升吞吐时，再考虑进程池。

## 核心判断

### 线程池更适合这些情况

核心任务:

```text
读取图片 -> resize/thumbnail -> save JPEG/WebP/PNG -> 写文件
```

并且每张图独立处理。这个场景里，线程池通常够用，因为文件读写属于阻塞 I/O，CPython 会在阻塞 I/O 周围释放 GIL；Python 官方文档也说明，GIL 会在读写文件等阻塞 I/O 操作周围释放。([Python documentation](https://docs.python.org/3/c-api/threads.html))

线程池还有几个优势：

| 维度                 | 线程池                                     |
| -------------------- | ------------------------------------------ |
| 启动成本             | 低                                         |
| 内存占用             | 低，共享进程内存                           |
| 数据传递             | 简单，不需要 pickle                        |
| 代码复杂度           | 低                                         |
| Windows/macOS 兼容性 | 更少坑                                     |
| 适合任务             | I/O 密集、Pillow 内部 C 代码占比较高的处理 |

Python 官方文档中，`ThreadPoolExecutor` 本质是用线程异步执行任务。([Python documentation](https://docs.python.org/3/library/concurrent.futures.html))

### 进程池更适合这些情况

切换到进程池的理由主要是：**你的压缩逻辑 CPU 密集，并且线程池无法充分利用多核 CPU**。

比如：

```text
大量高分辨率图片
复杂 resize/filter
逐像素 Python 逻辑
复杂格式转换
WebP/AVIF 等编码耗时明显
CPU 长时间接近单核瓶颈
```

`ProcessPoolExecutor` 使用多进程，可以绕开 GIL，但代价是函数和参数需要可 pickle，子进程需要能导入 `__main__`，而且在子进程任务里调用 Executor/Future 方法会导致死锁。([Python documentation](https://docs.python.org/3/library/concurrent.futures.html))

| 维度       | 进程池                                       |
| ---------- | -------------------------------------------- |
| 启动成本   | 高                                           |
| 内存占用   | 高，每个进程一份解释器和库状态               |
| 数据传递   | 需要 pickle，传大图对象/bytes 成本高         |
| 多核利用   | 好                                           |
| 稳定性隔离 | 单个 worker 崩溃影响较小                     |
| 适合任务   | CPU 密集、纯 Python 计算多、单张图处理耗时长 |

## 稳定性对比

**线程池稳定性更依赖代码本身是否线程安全。** 建议每个线程内部独立打开、处理、保存图片，不要多个线程共享同一个 `Image` 对象、文件句柄、全局 buffer 或临时文件名。

推荐模式：

```python
def compress_one(src_path, dst_path):
    from PIL import Image

    with Image.open(src_path) as im:
        im = im.convert("RGB")
        im.thumbnail((1920, 1920))
        im.save(dst_path, "JPEG", quality=85, optimize=True)
```

不推荐：

```python
# 不推荐：多个线程共享同一个 Image 对象
shared_img = Image.open("a.jpg")
```

**进程池的隔离性更好**：某个任务内存泄漏、native crash、异常污染全局状态时，影响通常局限在 worker 进程。但进程池也有自己的稳定性坑：必须正确关闭 pool，否则可能在退出时挂住；Python multiprocessing 文档明确提醒，进程池有内部资源，需要用上下文管理器或显式 close/terminate 管理。([Python documentation](https://docs.python.org/3/library/multiprocessing.html))

如果长期批处理大量图片，进程池可以设置 worker 处理一定任务数后重启。`multiprocessing.Pool` 有 `maxtasksperchild`，`ProcessPoolExecutor` 也有 `max_tasks_per_child`，可用于释放 worker 持有的资源。([Python documentation](https://docs.python.org/3/library/multiprocessing.html))

## 效率对比

### 线程池效率

优点：

线程创建成本低
没有跨进程序列化
传 path、配置、结果都很轻
对大量小文件更友好

缺点：

如果主要耗时是 Python 层 CPU 计算，GIL 会限制多核并行
线程数过多会造成磁盘竞争、上下文切换、内存峰值上升

### 进程池效率

优点：

CPU 密集任务可以真正并行
更容易吃满多核
适合单张图处理耗时较长的场景

缺点：

启动慢
内存高
大对象跨进程传输慢
Windows/macOS 下 spawn 模式成本更明显

所以使用进程池时，**不要把 PIL Image 对象或大 bytes 传给子进程**，只传文件路径和参数：

```python
# 推荐
pool.submit(compress_one, "input/a.jpg", "output/a.jpg")

# 不推荐
pool.submit(compress_image_object, image_object)
```

## 对 Pillow 的具体影响

不能简单认为“Pillow 一定适合线程”或“一定适合进程”。Pillow 很多底层工作在 C 代码里完成，但是否释放 GIL 取决于具体操作。Pillow 官方发布说明中就有单独记录过某些矩阵转换操作释放 GIL，这也侧面说明并不是所有操作都可以一概而论。([Pillow (PIL Fork)](https://pillow.readthedocs.io/en/stable/releasenotes/9.3.0.html))

实际建议是：

1. 没有逐像素 Python 循环：优先线程池
2. 有大量 Python 层循环/计算：优先进程池
3. 编码/resize 很重：两者都测，以吞吐和内存峰值为准

## 建议配置

### 线程池

```python
from concurrent.futures import ThreadPoolExecutor, as_completed
import os

workers = min(32, (os.cpu_count() or 4) * 4)

with ThreadPoolExecutor(max_workers=workers) as ex:
    futures = [ex.submit(compress_one, src, dst) for src, dst in tasks]
    for f in as_completed(futures):
        f.result()
```

适合：图片多、单张不太大、磁盘/网络 I/O 明显。

### 进程池

```python
from concurrent.futures import ProcessPoolExecutor, as_completed
import os

workers = os.cpu_count() or 4

if __name__ == "__main__":
    with ProcessPoolExecutor(max_workers=workers, max_tasks_per_child=200) as ex:
        futures = [ex.submit(compress_one, src, dst) for src, dst in tasks]
        for f in as_completed(futures):
            f.result()
```

适合：单张图处理很重、CPU 长时间高负载、线程池提速不明显。

## 结论

你的图片压缩脚本如果只是常规批量压缩，**不建议一开始换成进程池**。先用线程池，并控制并发数，通常更稳、更省内存、代码更简单。

建议按这个顺序优化：

```text
线程池 + 合理 max_workers
↓
确认没有共享 Image 对象/文件句柄
↓
压测 CPU、内存、磁盘 I/O
↓
如果 CPU 成为瓶颈，再切进程池
↓
进程池只传路径，不传图片对象
```

最终判断标准很简单：

- 线程池下 CPU 使用率不高，磁盘繁忙：继续线程池
- 线程池下单核瓶颈明显，多核吃不满：考虑进程池
- 进程池吞吐提升 < 20%，但内存明显增加：继续线程池
- 进程池吞吐提升明显且内存可接受：使用进程池
