[toc]



## 采集数据发布和上传脚本使用说明



### 文件说明

这里有若干文件,代码是`python`代码

其中:

- comutils.py
- woodf.py
- wooenums.py
- woosqlitedb.py
- filenamehandler.py
- ...

这些没有下划线的py文件是模块,它们不直接使用

而`woo_get_csv.py`和`woo_uploader.py`是我们直接使用的两个脚本

分别用来导出/处理采集数据,以及上传产品数据到wp站

```bash
PS> tree_lsd
 .
├──  __pycache__
├──  archives
│   ├──  logging.ipynb
│   ├──  woo_uploader.py
│   └──  woo_uploader_dev.py
├──  comutils.py
├──  ReadMe.md
├──  woo_get_csv.py
├──  woo_uploader.py
├──  woodf.py
├──  wooenums.py
└──  woosqlitedb.py

```

### python依赖包安装🎈

查看woo_df目录下的requirements.txt,根据该文件的要求进行安装依赖

在这之前,建议将pip源更换为国内加速源,比如清华源,执行以下命令即可配置(powershell或者cmd/bash都可以)

```bash
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
```

安装依赖的命令为:

```bash
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple #修改pip源
pip install -r ".\woo_df\requirements.txt" #注意修改requirements.txt的路径为你自己的实际路径🎈
```

- 注意:具体的requirements.txt路径根据自己的实际情况指定,尤其是当前工作目录会影响到指定目录值


- 或者可以使用拖转文件的方式或指定绝对路径的方式来指定requirements.txt文件都可以

### magic库的检查

- 上面的安装依赖操作可能无法一次性顺利安装magic库,可以考虑使用其他库代替或者关闭此功能(需要调整代码)
- 优化:todo

```python
#⚡️[Administrator@CXXUDESK][C:\Share\df\wp_sites\wp_migration][11:49:13][UP:17.08Days]
PS> ipython
Python 3.12.7 | packaged by Anaconda, Inc. | (main, Oct  4 2024, 13:17:27) [MSC v.1929 64 bit (AMD64)]
Type 'copyright', 'credits' or 'license' for more information
IPython 8.31.0 -- An enhanced Interactive Python. Type '?' for help.

In [1]: import magic

In [2]: magic.libmagic
Out[2]: <CDLL 'C:\ProgramData\scoop\apps\miniconda3\current\Lib\site-packages\magic\libmagic\libmagic.dll', handle 7ffa0b140000 at 0x27dff8c99d0>

In [3]:
```

## 向桌面添加脚本|模块所在目录

打开powershell 7(pwsh),执行以下命令行

### 添加符号链接(junction)

```powershell
New-Item -ItemType Junction -Path "$desktop/woo_df" -Target $scripts/wp/woocommerce/woo_df -Verbose
```

这里的`$desktop/woo_df`也可以替换成你喜欢的位置,默认会再桌面生成`woo_df`符号

### 添加快捷方式(shortcut)

也可以添加快捷方式

```powershell
New-Shortcut -Path $desktop\woo_df -TargetPath  $scripts\wp\woocommerce\woo_df  -Verbose -Force
```

## 脚本集功能设计说明

- 考虑到当前的woocommerce产品上传脚本有两类方案(保守的api上传和直接的数据库直插方法)
- 其中数据库直插方法暂时要求**图片下载到本地**,而csv文件中的`Images`字段存放图片的名字
  - 下载图片的时机有两种
    1. 一种是采集器采集过程中直接下载;
    2. 另一种方式是采集时不下载,推迟到导出csv后下载(扫描csv中的每一行数据的图片url链接进行下载)
  - 第一种方式比较直白,第二种方式则将下载任务处理的更加灵活,这里讨论第二种,并且实现它
    - 在代码中设置一个开关选项`img_as_name`
      - 2-A:取值为`True`表示导出的csv文件中的`Images`字段存储的是图片名字(这可以是自定义的有规律的名字,比如取值为产品的sku,多图则sku_1,sku_2,...)
        - 图片链接要存放到其他字段中
        - 利用图片下载代码或工具按行处理,每一行数据中的图片链接下载保存的图片的名字根据`Images`中给定的那样保存到指定的目录
      - 2-B:如果设置为`False`,表示导出的csv文件将适用于传统的api上传方式,`Images`字段存放的是图片链接url
    - 现在的导出csv代码基于第二种2-B的情况设计,为了方便起见,可以在2-A的情况下,将2-B的csv做调整
      - 或者,修改CSVProductFields枚举中返回的字段对应关系
- 对于多图采集,暂时未处理,可能会用`>`链接成一个字符串存储

## 采集数据的发布和处理|csv导出功能

- 为了节约篇幅,另见单独的说明: [ReadMe@woo_get_csv@woosqlitedb.md](ReadMe@woo_get_csv@woosqlitedb.md) 

## 上传数据到wordpress站

woo_uploader.py负责的任务,可以多线程或者按批上传数据到wp站

下面是详细文档(和此文档存放在同一个目录中)

-   [Readme@woo_uploader_api.md](Readme@woo_uploader_api.md) 
-   [Readme@woo_uploader_db.md](Readme@woo_uploader_db.md) 

## 脚本和模块的使用🎈

- 由于代码被拆分成多个文件,所以运行时,命令行的工作目录要定位到这些脚本文件的目录中

### 配置python环境变量🎈

- 将模块添加到环境变量可以解除该限制

  - 在windows系统上,可以通过一下命令行类配置python模块,从而使得相关模块全局可用

  - 例如,使用`setx PYTHONPATH "module_path"`(将引号内容替换为模块所在目录)

    ```bash
    PS> setx PYTHONPATH C:\repos\scripts\wp\woocommerce\woo_df\
    
    成功: 指定的值已得到保存。
    ```

    powershell也可以

    ```powershell
    [System.Environment]::SetEnvironmentVariable("PYTHONPATH", "C:\repos\scripts\wp\woocommerce\woo_df\", [System.EnvironmentVariableTarget]::Machine)
    ```


#### 从CxxuPwshModule仓库配置

部署git仓库(推荐方式)

> [scripts: 实用脚本集合,以powershell模块为主(针对powershell 7开发) 支持一键部署,改善windows下的shell实用体验](https://gitee.com/xuchaoxin1375/scripts)

1. 一键部署(已经部署过的可以跳过)

```powershell
irm 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex

```

2. 如果已经安装了git(和powershell7),那么直接执行:

   ```bash
   git clone https://gitee.com/xuchaoxin1375/scripts.git C:/repos/scripts
   ```

   

3. 然后可以执行以下语句(配置pythonpath环境变量)

```powershell
setx PYTHONPATH C:\repos\scripts\wp\woocommerce\woo_df
```

#### 检查配置

- 配置完后,请全新打开一个命令行(powershell/cmd),以便检查配置是否生效

- 如果成功,打开python交互模式,运行`import woo`不会报错,否则说明配置失败

  ```powershell
  #⚡️[cxxu@CXXUFIREBAT11][~\Desktop][23:21:06][UP:4.02Days]
  PS> ipython
  Python 3.12.3 | packaged by conda-forge | (main, Apr 15 2024, 18:20:11) [MSC v.1938 64 bit (AMD64)]
  Type 'copyright', 'credits' or 'license' for more information
  IPython 9.0.2 -- An enhanced Interactive Python. Type '?' for help.
  Tip: You can use `files = !ls *.png`
  
  In [1]: import woodf
                     woo_get_csv  woodf
                     woo_uploader wooenums
                     woocommerce  woosqlitedb
  
  ```


### 推荐用vscode使用脚本🎈

这不是必须的,但是可以提升使用体验,便于排查可能出现的问题

#### 推荐在vscode中使用,还可以配合插件

安装完本文提供的python的模块后,需要vscode安装插件

- [Python - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-python.python)



#### csv的查看和编辑以及数据统计分析插件

- [IntelliCode - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=VisualStudioExptTeam.vscodeintellicode)
- [Edit CSV - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=janisdd.vscode-edit-csv)
- [Jupyter - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter)
- [Data Wrangler - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.datawrangler)
- [Rainbow CSV - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=mechatroner.rainbow-csv)

### vscode中导包排序isort

[isort - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-python.isort)

利用快捷键`alt+shift+o`可以整理导入的包

使用`organize imports`指令也可以排序

