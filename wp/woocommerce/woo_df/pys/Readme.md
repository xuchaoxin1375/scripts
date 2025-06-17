[toc]



## abstract

这个目录存放用户直接运行的脚本,上一层目录存放的py文件大多是模块,通常不用关心

**模块相关的详细的文档参考上一级目录中的各个Readme@..md**(如果是通过`git clone https://gitee.com/xuchaoxin1375/scripts.git C:/repos/scripts` ,则位于:`C:\repos\scripts\wp\woocommerce\woo_df`)



## 命令预览(总结)🎈

为了查阅方便,将总结放到头部,第一次运行请查看[安装依赖]一节

---

下面几个命令分步执行,不要连着执行

建议复制下面的命令行保存为文本文件(后缀改为`.ps1`),然后用vscode编辑

> 可以在vscode中安装个powershell插件,有高亮显示

```powershell
# 1导出csv 输出路径的参数--output-dir;此外,如果要排除区间中的个别任务,则追加使用-E选项指定编号(多个编号逗号隔开)字符串"a,b,..",就可以排除任务编号a,b,...
python $pys\woo_get_csv.py -fmt .webp --start-id  $start_id --end-id $end_id  --language-country $language --output-dir $output_dir --sku-suffix $sku_suffix 

# 2下载并处理图片(下载过程中或者下载完毕要抽查看看是否有破图或者不完整的图,如果比较多要警惕)--image-mode {NAME_FROM_SKU,NAME_FROM_URL,NAME_AS_URL}
python $pys\image_downloader.py -c -n -R auto -k  -rs 1000 800 --image-mode NAME_FROM_SKU --output-dir $output_dir --dir-input $dir_input

# 3导入产品数据到数据库中
python $pys\woo_uploader_db.py --update-slugs  --csv-path $csv_path --img-dir $img_dir --db-name $domain_db 

# 4打包成压缩包(如果安装了7z,还支持更多种格式,默认打包成zip)
Get-WpSitePacks -SiteDirecotry $site_dir
```

图片下载情况比较复杂,有些顺利的可以用上述默认选项,如果下载不顺利，可以用其他选项来修改下载策略,比如使用代理,使用不同的下载引擎(curl,iwr)

### 压缩图片

命令

```powershell
python $pys\image_compresser.py 
```

基本参数

```py
-R auto -p -F  -O -k -f webp  -r 1000 800  -i
```



> 如果需要额外压缩图片,可以单独使用`image_compress.py`来压缩,详情另见上一级目录中的对应的readme文档

```powershell
python $pys\image_compresser.py -R auto -p -F  -O -k -f webp  -r 1000 800  -s webp -i .  #默认压缩当前目录,跳过webp图片的压缩(对于混合目录一般压缩过另一半没压缩的情况)
```

-   [ReadMe@image_compresser@ImgCompresser.md](..\ReadMe@image_compresser@ImgCompresser.md) 


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

配置采集器的数据存储路径

```cmd
setx PYTHONPATH C:\repos\scripts\wp\woocommerce\woo_df
setx LOCOY_SPIDER_DATA "C:\火车采集器V10.27\Data"
setx PYS C:\repos\scripts\wp\woocommerce\woo_df\pys
setx WOO_DF C:\repos\scripts\wp\woocommerce\woo_df
setx MySqlKey_LOCAL ""

```

将引号中的路径替换为你的采集对应的路径

> ### 请等待所有命令执行完毕,等到shell能够继续相应的回车键为止!

配置完以后关闭所有命令行窗口,以及vscode窗口(如果有用到vscode的话)再重新打开才会生效	

### mysql配置到Path环境变量

找到mysql.exe所在目录,然后将此目录添加到path环境变量中



## 主要步骤

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



### 导入产品数据

```cmd
python $pys\woo_uploader_db.py -c $csv_path -i $img_dir 
```

