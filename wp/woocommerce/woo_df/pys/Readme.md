[toc]



## abstract

这个目录存放用户直接运行的脚本,上一层目录存放的py文件大多是模块,通常不用关心

**模块相关的详细的文档参考上一级目录中的各个Readme@..md**



## 命令预览(总结)🎈

为了查阅方便,将总结放到头部,第一次运行请查看[安装依赖]一节

如果没有特殊提示,请始终在powershell(pwsh7)中运行命令,否则会失败



### 一批数据导出CSV文件的命令(一切始于导出的csv)

> 导出的csv数量关系到要申请的域名的数量,导出过程中会移除不规范的数据或者同名同图片链接的数据,直接估计采集器中的采集数量是不可靠的!
>
> 将csv的数量除以6或者7,至少是6,得到的结果就是这批数据要申请的域名数量,因为下载图片以及图片质量检查人为移除过程中通常有损耗
>
> 然后就可以去构思域名填写表格并批量部署本地站点了

导出csv 输出路径的参数`--output-dir`;

> 导出的时候千万要注意语言/国家

### woo_get_csv.py

其中`-f .jpg`表明,当图片url后缀不是白名单图片类型,就会默认加上后缀`.jpg`

而产品描述的长度如果过短可能是采集到`<br>`这种标签,可以通过`-dl`指定一个最短描述字符串长度(比如取10),描述长度低于此长度的产品会被丢弃)

```powershell
python $pys\woo_get_csv.py -f .webp --start-id  $start_id --end-id $end_id  --language-country $language --output-dir $output_dir --sku-suffix $sku_suffix -dl 10
```

> 再次强调,导出的时候千万注意对应的国家,涉及到默认产品分类(面包屑)分配词语的单词所属语种,使用`--language-country`或者缩写`-C`来指定,比如美国用`US`,德国`DE`,...

#### 跳过导出尚未采集完毕的任务(-E)

如果要排除区间中的个别任务,则追加使用`-E`选项指定编号(多个编号逗号隔开)字符串`"a,b,.."`,就可以排除任务编号`a,b,...`;

> 如果一批网站采集中有几个数据量很大或者限制你线程数1采集很慢拖了很久,那么这几个就给他标记起来暂时跳过导出,不必等他们采集完,因为有些网站图片链接可能会过期,尽快把已经有的数据导出并下载图片也不用担心这周可以建站的数量不够!

#### 严格去重复(-R)

将产品名相同的产品视为重复,去重只保留一个(即便图片链接不同也移除掉),可以使用`-R`

默认情况下产品名和图片链接同时相同才会视为重复,可以尽可能保留更多的产品数据

### 导出csv命令模板🎈

例如:

- 导出采集器中任务id范围为`354-378`的所有采集到的数据,并且这批数据是同类产品(户外),比如都是**美国**(US)市场,导出的csv存放到指定目录:桌面的`outdoor_us_0711`目录中(后缀0711表示导出的日期是7月11号)

- 并且,如果遇到图片链接后缀难以判断出图片类型时,将图片名称使用默认后缀扩展名`.webp`(即便图片实际上是其他编码格式也没关系,这不影响浏览器的显示)
- 命令行如下(对上面的选项进行了缩写,比如`-s`和`--start-id`等价)

```powershell
$type='  品类  '.trim()
$country='  国家代号(US/DE/FR/ES/IT/...)  '.trim()
$start=
$end=
$exclude='0' #如果需要排除,将0修改为你需要的id(多个id用逗号分隔)
python $pys\woo_get_csv.py -f .webp -s $start -e $end  -C $country -E $exclude -o "$desktop/$type-$country-$(date -format MMdd-hh-mm-ss)-[$start-$end]-E[$exclude]" -dl 10
```

---

##### 普通导出示例🎈🎈

例如,导出397~448区间中的任务,跳过446号任务(通常是因为采集任务没有结束或者已知数据有问题要跳过),使用了`-R`表示严格去重复

等到被上一轮排除的446任务id结束采集,就可以单独导出(可以在输出路径追加单独导出的id编号)



```powershell
$type=' 书籍  '.trim()
$country='  UK '.trim()
$start=992
$end=994
$exclude='0' 
python $pys\woo_get_csv.py -f .webp -s $start -e $end -E $exclude -C $country  -o "$desktop/$type-$country-$(get-date -format MMdd-hh-mm-ss)-[$start-$end]-E[$exclude]" -dl 10 -nad
```



##### 单独导出



```powershell
$type='  demo  '.trim()
$country='  UK '.trim()
$start=901
$end=$start 
$exclude='0'
python $pys\woo_get_csv.py -f .webp -s $start -e $end -E $exclude -C $country  -o "$desktop/$type-$country-$(get-date -format MMdd-hh-mm-ss)-[$start-$end]-E[$exclude]" -dl 10 -nad # 
```

```powershell
$type='    '.trim()
$country='  US '.trim()
$start=965
$end=$start
$exclude='0'
python $pys\woo_get_csv.py -f .webp -s $start -e $end -E $exclude -C $country  -o "$desktop/$type-$country-$(get-date -format MMdd-hh-mm-ss)-[$start-$end]-E[$exclude]" -dl 10 -nad

```

#### 图片名后缀时间戳对齐导出🎈

> 分析现有的某个图片,观察其中的[国家代号-时间戳]后缀部分,例如:`SK0789145-US20251019-210314-0.webp`,提取关键信息:`US20251019-210314`(最后的`-0.webp`部分不要),将其作为`-k`选项的参数进行导出

```powershell
$type=' ...  '.trim()
$country='  ... '.trim()
$start=
$end=
$exclude='0' 
python $pys\woo_get_csv.py -f .webp -s $start -e $end -E $exclude -C $country  -o "$desktop/$type-$country-$(get-date -format MMdd-hh-mm-ss)-[$start-$end]-E[$exclude]" -dl 10 -nad -k US20251019-210314
```

输出示例:

```
Preview of C:\Users\Administrator\Desktop\家居生活-US-1020-06-32-37-[765-765]-E[793]\p1.csv(total lines:1641):
                           SKU                             Images Categories
0  SK0000001-US20251019-210314  SK0000001-US20251019-210314-0.jpg  Furniture
1  SK0000002-US20251019-210314  SK0000002-US20251019-210314-0.jpg  Furniture
2  SK0000003-US20251019-210314  SK0000003-US20251019-210314-0.jpg  Furniture
3  SK0000004-US20251019-210314  SK0000004-US20251019-210314-0.jpg  Furniture
4  SK0000005-US20251019-210314  SK0000005-US20251019-210314-0.jpg  Furniture
```



#### 统计产品数量🎈

使用`-count`选项(开关)

```powershell
$type='  统计  '.trim()
$country='  US '.trim()
$start=641
$end=676
$exclude='0'
python $pys\woo_get_csv.py -f .webp -s $start -e $end -E $exclude -C $country  -o "$desktop/$type-$country-$(date -format MMdd-hh-mm-ss)-[$start-$end]-E[$exclude]"  -count
```



---

### 批量创建本地wp站点(nginx站点)

批量创建本地站点只需要一个命令,关键是配置文件



> 可以在vscode中安装个powershell插件,有高亮显示

```powershell
# 批量复制站点并创建对应的目录(第一次使用前请查看对应文档)
Deploy-WpSitesLocal

```

运行完毕后,桌面(默认路径)会生成一份`script...ps1`文件(同一天生成的本地站点配套的命令行会写入到同一个文件中,默认放在桌面的配置文件`my_wp_sites`目录中),同时还会生成一个目录`data_ouput`

#### 配置文件my_table.conf

每个本地站点通过域名分割,和创建的table(默认查找桌面的文件`my_table.conf`)文件中的域名是对应的

my_table.conf中的内容示例:

```
https://lebenlshop.com	采集员1	2.de
https://wundeshop.com	采集员1	7.de
```

#### 输出目录my_wp_sites

执行完`deploy-wpsitelocal`命令后,最重要的本地模板站根目录集中存放在`my_wp_sites`目录下(默认位于桌面)

```powershell
#⚡️[Administrator@CXXUDESK][~\Desktop\my_wp_sites][23:38:50][UP:17.41Days]
PS> tree_lsd -depth_opt 1
 .
├── ...
├──  lebenlshop.com
└──  wundeshop.com
├──  scripts_....ps1
```

这里还附带一个脚本,同一天执行的批量本地建站生成的配套脚本会存放到同一份`scripts_....ps1`中

### 本地建站三部曲命令行模板🎈

```powershell

# =========[(1)    http://xit.com/login  ]:[ cd  C:\Users\Administrator\Desktop/my_wp_sites/xit.com  ]=>[图片目录: explorer C:\Users\Administrator\Desktop/my_wp_sites/xit.com\wp-content\uploads\2025 ]==========


# 下载图片(可以在构思域名前提前下载,分配好csv就可以创建临时域名开始下载,比如1.com,2.com,...)
python C:\repos/scripts/wp/woocommerce/woo_df/pys\image_downloader.py -c -n -R auto -k  -rs 1000 800  --output-dir C:\Users\Administrator\Desktop/my_wp_sites/xit.com/wp-content/uploads/2025 --dir-input C:\Users\Administrator\Desktop/data_output/xit.com -F -ps pwsh -w 5 -U curl 

# 导入产品数据到数据库
python C:\repos/scripts/wp/woocommerce/woo_df/pys\woo_uploader_db.py --update-slugs  --csv-path C:\Users\Administrator\Desktop/data_output/xit.com --img-dir C:\Users\Administrator\Desktop/my_wp_sites/xit.com/wp-content/uploads/2025 --db-name xit.com --max-workers 20

# 打包网站
Get-WpSitePacks -SiteDirecotry C:\Users\Administrator\Desktop/my_wp_sites/xit.com -Mode zstd



```

此外还有配套的清理旧站点命令行`Remove-WpSitesLocal`

下载图片(可以在构思域名前提前下载,分配好csv就可以创建临时域名开始下载,比如1.com,2.com,...)

```powershell
$domain="4.com"
python $pys\image_downloader.py -c -n -R auto -k  -rs 1000 800  --output-dir $my_wp_sites/$domain/wp-content/uploads/2025 --dir-input $Desktop/data_output/$domain -ps pwsh -w 5 -U curl 
```



#### 输出目录data_output

此外,还会生成对应的`data_output`,内部含有`my_table.conf`中配置的域名文件夹,将导出的csv文件分配(移动)到对应的目录中(每个域名文件夹中存放6份~7份csv)

这个步骤需要手动分配!

例如

```powershell
#⚡️[Administrator@CXXUDESK][~\Desktop\data_output][23:30:54][UP:17.4Days]
PS> tree_lsd
 .
├──  lebenlshop.com
│   ├──  p1+.csv
│   ├──  p1.csv
│   ├──  p2+.csv
│   ├──  p2.csv
│   ├──  p3+.csv
│   ├──  p3.csv
│   └──  p4.csv
└──  wundeshop.com
    ├──  p4+.csv
    ├──  p5+.csv
    ├──  p5.csv
    ├──  p6+.csv
    ├──  p6.csv
    ├──  p7.csv
    └──  p8.csv
```



## 服务器上下载图片和导入数据

> 服务器上的代码和本地的是同一套(通过/update_repos.sh更新同步代码),可以为数据补充提供类似的本地建站的操作方法

少数情况下需要补数据的情况下,可以讲csv上传到合适的目录下,然后调用对应的脚本进行下载图片到指定目录下(这个过程和本地建站中的图片下载环节十分相似)

我以网站`xcx`用户要对网站`test.com`补充数据为例(具体路径根据具体情况进行调整和修改),主要是csv目录路径`--dir-input`和图片保存输出路径`--output-dir `

```bash
python3 /repos/scripts/wp/woocommerce/woo_df/pys/image_downloader.py -c -n -R auto -k  -rs 1000 800  --output-dir /www/wwwroot/xcx/test.com/wordpress/wp-content/uploads/2025 --dir-input /srv/uploads/uploader/files/xcx/test.com\ -w 10 
```

仍然可以通过`-U curl`选择curl下载引擎

等图片下载完毕后,可以导入新的产品数据(csv)到网站数据库中

```bash
python3 /repos/scripts/wp/woocommerce/woo_df/pys/woo_uploader_db.py --update-slugs  --csv-path /srv/uploads/uploader/files/xcx/test.com --img-dir /www/wwwroot/xcx/test.com/wordpress/wp-content/uploads/2025 --db-name xcx_test.com --max-workers 20 --db-password <yourpassword> --db-host localhost
```

如果提示`root@127.0.0.1`access deny,可以尝试创建一个`root@127.0.0.1`的用户



### 清理本地已经上线站点🎈

网站上传并解压上线后,就可以删除本地网站相关的目录和配置

配套的命令为

```powershell
Remove-WpSitesLocal 
```

> 注意,网站上线后,数据库,根目录,系统hosts,服务器软件配置(nginx中的vhosts中的conf文件需要对应删除以保持系统环境的干净)
>
> 尤其是系统hosts文件,如果上线后还留有本地站点hosts配置,可能会因为缓存影响到网站的部分元素加载异常,比如首页广告图不显示等问题,上述命令将自动清理这些残留;
>
> 清理过程需要一定的时间(大量图片小文件删除需要时间),个别环节需要用户交互确认删除





### 每个站要单独执行的命令行步骤

使用上面的本地批量建站会**自动**生成下面格式的命令行

> 当然也可以**手动修改**下面的命令行,如果确实需要手动编辑,则建议复制下面的命令行保存为文本文件(后缀改为`.ps1`),然后用vscode编辑

下面几个命令分步执行,不要连着执行(仅供参考)

```powershell


# 下载并处理图片(下载过程中或者下载完毕要抽查看看是否有破图或者不完整的图,如果比较多要警惕)--image-mode {NAME_FROM_SKU,NAME_FROM_URL,NAME_AS_URL}
python $pys\image_downloader.py -c -n -R auto -k  -rs 1000 800  --output-dir $output_dir --dir-input $dir_input

# 导入产品数据到数据库中
python $pys\woo_uploader_db.py --update-slugs  --csv-path $csv_path --img-dir $img_dir --db-name $domain_db 

# 打包成压缩包(如果安装了7z,还支持更多种格式,默认打包成zip)
Get-WpSitePacks -SiteDirecotry $site_dir
```



### 关于下图

图片下载情况比较复杂,有些顺利的可以用上述默认选项,如果下载不顺利，可以用其他选项来修改下载策略,比如使用代理,使用不同的下载引擎(curl,iwr)

例如,windows下载图片

```powershell
python $pys\image_downloader.py -c -n -R auto -k  -rs 1000 800  --output-dir $desktop\my_wp_sites\wild-ridgegear.com\wp-content\uploads\2025 --dir-input $Desktop\data_output\wild-ridgegear.com
```

或者windwos由于ip或者代理不行,或者想要节约代理流量,可以把任务委托到服务器上去下载(只要把包含图片链接的文件比如csv上传到服务器上,然后管理员调用下载命令行进行下载任务)

```bash
python3 /repos/scripts/wp/woocommerce/woo_df/pys/image_downloader.py -c -n -R auto -k  -rs 1000 800  -o images -d . -U curl -w 1 
```

这里从`-o`开始是根据情况指定,比如`-w 1`针对比反爬验证的情况,下载比较慢

#### 测试图片下载🎈

如果有一个网站很难采集,或者访问容易人机验证(或403),可以考虑打开一个产品,然后产品图片链接,用测试命令行测试一下看看能否下载

不行的话换一下代理,或者更换下载引擎(-U curl或iwr)

例如:

```powershell
python $pys\image_downloader.py -i 'https://img95.699pic.com/photo/50076/2408.jpg_wh860.jpg' -O -o $desktop
```

会下载测试链接`https://img95.699pic.com/photo/50076/2408.jpg_wh860.jpg`到桌面

#### 打开图片链接时遇到cloudflare的人机验证

这种图片受到防护,但是也未必下不动,可以尝试多更换代理后重试



#### 要保存的图片名过长导致下载失败

在导出数据到csv文件时候,可以选择导出模式(主要是图片模式),

```bash
--image-mode {NAME_FROM_SKU,NAME_FROM_URL,NAME_AS_URL,NAME_MIX}
```

如果使用`NAME_FROM_SKU`,文件名最为规整,问题最少;(但是缺少了原url中包含的文件名信息)

如果使用`NAME_MIX`或`NAME_FROM_URL`,由于涉及到截取url中的路径文件名,可能遇到许多细节问题.

在windows系统中,默认情况下文件名的最大长度允许260个字符左右,少数图片链接中的文件名很长(超过了这个上限,即便图片链接没有做反爬或防盗,也无法保存下来,除非把保存的文件名缩短)

考虑到这个问题,在导出csv的过程中为图片链接将要保存的文件名做了长度限制,仅截取其中的前100个字符,防止因为文件名过长导致文件无法下载和创建成功!

另一方面,图片名中如果包含`%`这类特殊符号,虽然可能下载成功,但是wordpress站中图片会显示不出来(图片链接无效,为404),这个细节问题在脚本中也做了相应的处理

### 单独压缩图片🎈

可以选择单独压缩已有的图片

命令

```powershell
python $pys\image_compressor.py 
```

基本参数

```py
-R auto -p -F  -O -k -f webp  -r 1000 800  -i
```

> 如果需要额外压缩图片,可以单独使用`image_compress.py`来压缩,详情另见上一级目录中的对应的readme文档

例如:

```powershell
python $pys\image_compressor.py -R auto -p -F  -O -k -f webp  -r 1000 800  -s webp -i .  #默认压缩当前目录,跳过webp图片的压缩(对于混合目录一般压缩过另一半没压缩的情况)
```

-   [ReadMe@image_compressor@Imgcompressor.md](..\ReadMe@image_compressor@Imgcompressor.md) 


### 查看命令行帮助

查看帮助(选项含义不清楚的可以使用`-h`参数,上述命令都支持这个选项和方式来获取命令行的选项说明),例如

```powershell
python $pys\woo_get_csv.py -h
```



## 安装依赖(第一次使用必看)🎈

第一次使用,需要先安装依赖,打开命令行窗口,执行:

```powershell
pip install -r $woo_df/requirements.txt

```

配置环境变量(另见本仓库其他说明文档)

 [Readme@Env.md](..\Readme@Env.md) 



## 主要步骤和细节



### 本地wordpress站点批量复制🎈

节约篇幅,详情另见它文 [ReadMe@Deploy-WpSitesLocal.md](..\ReadMe@Deploy-WpSitesLocal.md) 



### 导出csv

- 将`$start`和`$end`替换为采集器中的你需要导出的数据的对应任务的id
- 将`$language`替换为你这批数据对应的语言/国家代号(可以是国家代码['US', 'UK', 'IT', 'DE', 'ES', 'FR'])

```powershell
python $pys\woo_get_csv.py -s $start -e $end -C $language
```

详情查看帮助命令行:

```powershell
python $pys\woo_get_csv.py -h
```



### 图片下载

把下面的代码片段复制到一个空的记事本或者vscode新建一个编辑页面,填写必要的内容,然后粘贴到powershell窗口中运行

```powershell
#将路径填写到引号中,两侧多余的空格可以保留,方便填写(确保python命令存在并可以运行)
$o="       ".trim() #表示下载的图片保存位置(输出目录output_dir)
$d="       ".trim() #表示导出的csv文件所在目录
python $pys\image_downloader.py -c -n -R auto -k  -o $o -d $d

```

> 对于我们的业务,需要关心的参数有两个

- 一个是`-o`,表示图片下载要保存到哪个目录下(通常建议填写网站的专门存放文件图片的目录,例如`....\1.de\wp-content\uploads\2025`)
- `-d`表示网站的csv文件所在目录,即使用`woo_get_csv.py`导出的csv文件所在目录

这种目录下面可能还有月份细分,我们简单起见,就不管月份,直接将文件放到年份的目录下(模板根目录下的`wp-content\uploads\2025`)

```powershell
#⚡️[Administrator@CXXUDESK][C:\sites\wp_sites\1.de\wp-content\uploads\2025][9:47:42][UP:16.9Days]
PS> ls

    Directory: C:\sites\wp_sites\1.de\wp-content\uploads\2025

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d----            2025/3/5    10:12                01
d----            2025/3/5    10:12                02
d----           2025/3/31    13:53                03
d----           2025/4/22    16:16                04
d----            2025/5/7    15:11                05
```

#### FAQ 和已知问题

解决进程占用的问题,可以考虑使用sleep,延迟一些防止操作冲突

```bash
ERROR:imgcompressor:处理图片失败: [WinError 32] 另一个程序正在使用此文件，进程无法访问。: 'C:\\Users\\Administrator\\Desktop/my_wp_sites/summitandsea24.com/wp-content/uploads/2025\\HHA_Nytryx_Pro_X119_1.tmp.webp' -> 'C:\\Users\\Administrator\\Desktop/my_wp_sites/summitandsea24.com/wp-content/uploads/2025\\HHA_Nytryx_Pro_X119_1.webp'
```

#### curl 错误

常见错误码22可能对应多种可能,具体的http错误需要看`curl: (22) ...error:`,常见的是404或者403,前者说明图片过期了,后者需要注意,可能是ip被静止,可以考虑更换节点,降低线程数(比如2线程)

```bash
curl: (22) The requested URL returned error: 404

2025-06-26 08:36:26,919 - imgdown - ERROR - curl 执行失败，错误码: 22
ERROR:imgdown:curl 执行失败，错误码: 22
```

也有28这类错误

### 导入产品数据

```cmd
python $pys\woo_uploader_db.py -c $csv_path -i $img_dir 
```

## 常见问题@FAQ

### 网站上线后首页广告图无法显示

如果装修的时候确实设置了首页广告图通常在其他设备浏览器可以看到显示是正常的

装修网站所用的浏览器可能会因为原来的站被删除,但是hosts中仍然配置了本地站的映射,导致浏览上线的网站(https)中广告图(仍然是http链接,而且优先读取缓存过的图片资源,但是实际位置被删除从而显示为空)

办法有两类:

- 移除hosts文件中对应的域名解析(使用`Remove-WpSiteLocal`可以自动处理)
- 修改根目录中的模板中css路径

### 本地网站打不开(502/503)👺

#### 502

- 502错误可能是因为nginx(或小皮转发端口)的服务端口配置不正确,使用命令查询(通常是9001或9002),也可以分被尝试这两个端口(修改对应的vhosts文件conf配置,并且重启nginx来生效修改)

  ```powershell
   $p=Get-NetTCPConnection |?{$_ -like '*900*'};$p;ps -Id $p.OwningProcess|ft
   ps -Id $p.OwningProcess|ft
   
  ```


如果小皮的转发端口(`xp.cn_cgi.exe`监听的端口)发生变化,并且你打算批量修改vhost,可以用vscode打开nginx的vhosts目录,然后使用`ctrl+shift+h`搜索旧端口然后批量替换为新端口

注意，端口修改后需要重启nginx;如果仍然打不开,先试试强制刷新ctrl+F5,还不行则建议用新的浏览器(比如隐私模式或者其他浏览器打开,关闭代理避免感染),清空浏览器数据代价太大,不建议轻易这么做

> 虽然本地批量建站默认情况下会尝试扫描端口并自动配置端口,但是这个方法不完全可靠,上述批量修改的方法作为备用,一般很少需要改动

#### 503

- 503错误通常是代理软件引起的错误,需要正确配置
  - 默认情况下,不建议开启代理软件的系统代理设置,浏览器中代理配置(比如proxyify插件中切换到关闭选项,暂时不走代理看看是不是代理引起的)
  - 例如Quik Q,在设置->高级设置->启动以下开关:(如果已经都设置了相应开关,则重启该软件然后再次检查能否访问本地站)
    1. 系统hosts优先
    2. 断连优化
    3. 代理规则配置127.0.0.1
    4. 不自动开机系统代理(关键)
    5. 网络异常时断开链接
  - 类似的小猫咪代理通常不会影响本地站的访问,但是也可能出bug,可能需要重启小猫咪,同时要保证对应的线路延迟检测不是error

### 本地站点打不开或则总是跳转到https链接

由于操作系统(windows)或者小皮工具箱的bug,可能会遇到本地站点创建结束后(没有报错)却打不开

即便不绕过小皮新建站点,使用小皮创建的本地站点也可能打不开,会尝试跳转到公网



这种情况下可以尝试ping一下本地站点的域名,如果ping的结果不是`127.0.0.1`,说明系统内部可能有错误,可以尝试重启,但是不一定有用

例如我本地用小皮建了一个`1.de`的本地站点,通常正常情况下,小皮新建完站点后会同步修改系统`hosts`文件(C:/WINDOWS/System32/drivers/etc/hosts)

首先尝试检查`hosts`文件,看看127.0.0.1 相关行是否存在,并且检查是否被被意外注释掉(#开头会导致映射失效)

```powershell
PS> ping 1.de

正在 Ping 1.de [83.243.59.78] 具有 32 字节的数据:
来自 83.243.59.78 的回复: 字节=32 时间=203ms TTL=49
来自 83.243.59.78 的回复: 字节=32 时间=202ms TTL=49
```

这意味着网站可能无法打开

但是浏览器中情况又有一定的区别,可能可以打开本地站点

可以尝试更改DNS服务器(命令行中输入ncpa.cpl打开设置入口)
