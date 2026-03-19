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

这些没有下划线的py文件是**模块**,通常它们不直接使用

而`woo_get_csv.py`和`woo_uploader_..py`是我们可以直接在命令行中调用的两个脚本

分别用来导出/处理采集数据,以及上传产品数据到wp站

## 脚本和代码



### 脚本集功能设计说明

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

### 各个脚本的使用说明

详情见专门的文档: [Readme.md](pys\Readme.md) 

建站人员使用的命令行说明: [Readme@建站命令行说明.md](pys\Readme@建站命令行说明.md) (提供设计思路和现有脚本的基本运行流程)

## 采集数据的发布和处理|csv导出功能

- 为了节约篇幅,另见单独的说明: [ReadMe@woo_get_csv@woosqlitedb.md](ReadMe@woo_get_csv@woosqlitedb.md) 

## 上传数据到wordpress站

woo_uploader.py负责的任务,可以多线程或者按批上传数据到wp站

下面是详细文档(和此文档存放在同一个目录中),共有两种方案,一种走api(速度相对慢),另一种是db(直接将本地数据导入到wordPress数据库中,是主力方案)

-   [Readme@woo_uploader_api.md](Readme@woo_uploader_api.md) 
-   [Readme@woo_uploader_db.md🎈](Readme@woo_uploader_db.md) 

## 脚本和模块环境配置和使用🎈

- 由于代码被拆分成多个文件,所以运行时,命令行的工作目录要定位到这些脚本文件的目录中
- 为了更加方便使用,需要配置一些环境变量

### 配置环境变量🎈

详情查看: [Readme@Env.md](Readme@Env.md) 

### 配置powershell7+模块🎈

从CxxuPwshModule仓库配置命令行环境

部署git仓库(推荐方式)

> [scripts: 实用脚本集合,以powershell模块为主(针对powershell 7开发) 支持一键部署,改善windows下的shell实用体验](https://gitee.com/xuchaoxin1375/scripts)

一键部署(已经部署过的可以跳过)

```powershell
irm 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex

```

### 直接克隆/强制覆盖代码🎈

前提:已经安装了git(和powershell7),那么直接执行(记得最后一行要回车):

```powershell
git clone --recursive --depth 1 --shallow-submodules https://gitee.com/xuchaoxin1375/scripts.git C:/repos/scripts
setx PsModulePath C:/repos/scripts/PS

```

最后,启动一个全新的powershell窗口,将如下执行自动环境导入的语句运行

```powershell
Add-CxxuPsModuleToProfile #今后将自动加载powershell环境


```



## 检查配置(可选但是推荐)🎈

- 配置完后,请全新打开一个命令行(powershell/cmd),以便检查配置是否生效


### python环境检查

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

### powershell(pwsh)环境检查

观察命令行提示符是否为带时间样式的提示符

```powershell
#⚡️[Administrator@CXXUDESK][~\Desktop][17:42:24][UP:28.16Days]
PS>
```

而不是只有`PS >`







## 向桌面添加脚本|模块所在目录🎈

打开powershell 7(pwsh),执行以下命令行

- `$woo_df`变量对应的是模块目录
- `$pys`变量对应的是用户脚本目录

### 添加符号链接(junction)

```powershell
New-Item -ItemType Junction -Path "$desktop/pys" -Target $pys -Verbose
New-Junction C:/pys -Target $pys
New-Junction C:/woo_df -Target $woo_df 
```

这里的`$desktop/pys`也可以替换成你喜欢的位置,默认会再桌面生成`pys`符号

### 添加快捷方式(shortcut)

也可以添加快捷方式

```powershell
New-Shortcut -Path "$desktop/pys" -TargetPath  $pys  -Verbose -Force
```



## 推荐vscode编辑器🎈

这不是必须的,但是可以提升使用体验,便于排查可能出现的问题

使用vscode编辑配置文件(.conf,.json,.ps1,py)等文件体验比普通的传统文本编辑器要好,不仅有高亮,还有代码排版对齐和错误检查(json)等功能,另外对于csv文件的查看和编辑也提供了支持(配合相应的插件)

#### 推荐在vscode中使用,还可以配合插件

安装完本文提供的python的模块后,需要vscode安装插件

- [Python - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-python.python)



#### csv的查看和编辑以及数据统计分析插件

注意,csv默认打开方式建议设置为`Text Editor (Built-in)`

- [Edit CSV - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=janisdd.vscode-edit-csv)
- [Jupyter - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter)
- [Data Wrangler - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.datawrangler)
- [Rainbow CSV - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=mechatroner.rainbow-csv)

### html预览和微http服务器插件

[Live Preview - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-vscode.live-server)

### ai插件

还有一些ai辅助插件,编写一些脚本可以提供方便,起草脚本框架,修改或改进代码错误,编写测试用例等

- [IntelliCode - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=VisualStudioExptTeam.vscodeintellicode)

- [GitHub Copilot Chat - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat) 有免费额度
- [Lingma - Alibaba Cloud AI Coding Assistant - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=Alibaba-Cloud.tongyi-lingma)
- [Fitten Code: Faster and Better AI Assistant - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=FittenTech.Fitten-Code) 具有上下文更改联动提示

### 其他

[Path Autocomplete - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ionutvmi.path-autocomplete)

[PowerShell - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell)

### vscode中导包排序isort

[isort - Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-python.isort)

利用快捷键`alt+shift+o`可以整理导入的包

使用`organize imports`指令也可以排序

