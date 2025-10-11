"""
从LocoySpider数据库中获取产品数据并保存为woocommerce能够接受的csv文件
"""

# %%
import logging
import os
from datetime import datetime
from logging import info
from pathlib import Path
import sys

# from random import random
from comutils import check_iterable  # , parse_dbs_from_str
from wooenums import ImageMode, EnumItRc, LanguagesHotSale
from woosqlitedb import SQLiteDB

# 确保日志目录存在
LOG_DIR = "./log"
LOG_FILE = f"{LOG_DIR}/log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
try:
    os.makedirs(LOG_DIR, exist_ok=True)  # 自动创建目录（如果不存在）
except Exception as e:
    print(f"无法创建日志目录 {LOG_DIR}: {e}")
    LOG_DIR = "."  # 如果失败则使用当前目录
file_handler = logging.FileHandler(LOG_FILE, mode="w", encoding="utf-8")
console_handler = logging.StreamHandler()
logging.basicConfig(
    level=logging.DEBUG,  # 日志级别🎈
    format="%(levelname)s - %(message)s",
    handlers=[file_handler, console_handler],
)


##
class LanguagesHotSaleX(EnumItRc):
    """对LanguagesHotSale枚举类的复刻,但是允许你修改下面的配置来调整和控制热销的返回值

    例如,我希望修改美国(US)产品数据中返回热卖的允许词汇列表,则修改下面US的取值(代替默认取值,默认取值来自于LanguagesHotSale枚举类)

    US = ["Best-Sellers","Featured","Top-Sellers"]

    """

    US = LanguagesHotSale.US.value
    UK = LanguagesHotSale.UK.value
    IT = LanguagesHotSale.IT.value
    DE = LanguagesHotSale.DE.value
    ES = LanguagesHotSale.ES.value
    FR = LanguagesHotSale.FR.value


# 产品价格区间(打折前不在此区间的产品将被过滤掉)
LOWEST_PRICE = 1
HIGHEST_PRICE = 10000
# 🎈
LANGUAGE = LanguagesHotSaleX.UK.name
# 限制产品数量少的分类,将其分配到热销类(或其近义词);设置为0表示不处理分类
CATEGORIES_THRESHOLD = 0
# -----------------------------------------------------------
# 指定db文件来源的方案有多种,这里主推方案1,更加简便,但是方案2更加灵活;如果需要解开注释进行配置

# 方案1:遍历指定范围编号内文件夹,获取db文件(需要配置3个参数)
#   例如获取170-180编号采集文件夹下的db文件

# 根据你的采集器安装目录以及采集存放的db目录来填写🎈(末尾不要有\,前面可以有)
DATA_DIR = Path(r"C:\火车采集器V10.27\Data")
# 🎈
START = 605
END = 605

# 枚举出db文件路径
rng = range(START, END + 1)
dbs = []
for dir_num in rng:
    # 构造db文件路径(不一定存在)
    db_file = DATA_DIR / str(dir_num) / "SpiderResult.db3"
    # 确保文件存在,才加入到列表中
    if db_file.exists():
        dbs.append(str(db_file.as_posix()))

# 方案2:配置文件列表,直接指定文件名

# DBS_STR = r"""
# C:\火车采集器V10.27\Data\a\SpiderResult.db3;
# C:\火车采集器V10.27\Data\b\SpiderResult.db3,
# C:\火车采集器V10.27\Data\c\SpiderResult.db3
# ...
# C:\火车采集器V10.27\Data\z\SpiderResult.db3
# """
# dbs = parse_dbs_from_str(DBS_STR)


# 预览已经获取的字段合法的db文件
if len(dbs) == 0:
    raise ValueError("没有找到有效的db文件")
for file in sorted(dbs):
    info(file)

##


# 使用示例
if __name__ == "__main__":
    print(f"开始执行(日志文件位于{LOG_FILE},绝对路径为:{os.path.abspath(LOG_FILE)})...")
    ## 1. 实例化SQLiteDB对象
    db = SQLiteDB(language=LANGUAGE, category_threshold=CATEGORIES_THRESHOLD, yy=True)
    ## 2. 读取数据库数据(根据count_rows_only参数,可以只统计行数,而不做初步的数据处理;正式使用是要改成False!)🎈
    db.get_data(dbs=dbs, count_rows_only=False)

    ## 3. 对sku进行第一次编号(可选)
    # db.number_sku(dbs=dbs, sku_suffix=LANGUAGE)
    ## 4. 获取产品属性值(包括分析不规范属性值的子集和超集,可以自行通过参数控制)
    db.get_attribute_of_products(
        dbs=dbs,
        check_invalid_attribute_subset=True,
        check_invalid_attribute_supperset=False,
    )
    ## 5. 检查属性值是否存在不规范的子集或超集(主要是子集,新手可能要注意一下超集)
    # check_iterable(db.invalid_attribute_supperset) #新手使用
    if db.invalid_attribute_subset:
        info("产品属性值存在不规范的子集")
        check_iterable(db.invalid_attribute_subset)
        info(f"共有{len(db.invalid_attribute_subset)}个属性值显然不规范的产品")
        # 请观察不规范属性值的数量多不多(如果不多,直接运行置空或者移除这部分属性值操作)
        # (按需执行)是否将不规范的属性值置为空(不一定合适,可能需要你重新采集该网站,尤其是不规范属性值过多的情况下)
        print(
            "选项说明:0.退出,1.仅把属性值置为空,2.移除这些不规范产品,3.*查看潜在可能不规范属性值的产品(新手注意)"
        )
        print(
            "Note:如果在notebook中运行,将会在顶部弹出一个输入框,请输入选项序号并回车;\n如果在终端中运行,请直接输入选项序号并回车"
        )
        TRY_COUNT = 1
        while True:
            choice = input(f"第{TRY_COUNT}次尝试,选择选项(序号值)并继续:")
            print(f"你选择了{choice}")
            TRY_COUNT += 1
            if choice == "0":
                sys.exit()
            elif choice == "1":
                db.empty_invalid_attribute_subset(dbs=dbs, remove=False)
                break
            elif choice == "2":
                db.empty_invalid_attribute_subset(dbs=dbs, remove=True)
                break
            elif choice == "3":
                print("查看可能不规范属性值的产品(如果有统计的话)")
                # check_iterable(db.invalid_attribute_subset)
                check_iterable(db.invalid_attribute_supperset)

            else:
                print("输入非法,请重新输入")
        db.empty_invalid_attribute_subset(dbs=dbs, remove=False)
    else:
        info("未发现不规范的产品属性值,默认继续执行...")
    ## 6.统计并处理产品分类(包括合并小分类,分配热销类);可以用data wragger查看cats统计结果
    cats = db.get_category_statistic(hot_class=LanguagesHotSaleX)  # type: ignore
    ## 7.更新产品数据(描述等)🎈
    db.update_products(dbs=dbs, sku_suffix=LANGUAGE, strict_mode=False)
    ## 8.导出csv文件
    db.export_csv(
        dbs=dbs,
        out_dir="./",
        split_files_size=10000,
        img_mode=ImageMode.NAME_AS_URL,
        limit_sale=169.99,
    )
