"""
从LocoySpider数据库中获取产品数据并保存为woocommerce能够接受的csv文件

setx LOCOY_SPIDER_DATA C:/火车采集器V10.27/Data

"""

# %%
import argparse  # 用于处理命令行参数
import logging

# from logging import info
import os
from datetime import datetime
from pathlib import Path
import sys

# from random import random
from comutils import check_iterable  # , parse_dbs_from_str
from wooenums import ImageMode, EnumItRc, LanguagesHotSale
from woosqlitedb import SQLiteDB


WOOSQLITEDB_LOGGER = "woosqlitedb"
DEFAULT_CSV_LINES = 5000
MAX_IMG_NAME_LENGTH = 100


LOCOY_SPIDER_DATA = os.environ.get("LOCOY_SPIDER_DATA")
if LOCOY_SPIDER_DATA is None:
    raise ValueError(
        r"请设置环境变量Locoy_Spider_Data为你的采集器数据目录路径,例如运行命令行: setx LOCOY_SPIDER_DATA C:\火车采集器V10.27\Data "
    )


def parse_args():
    """解析命令行参数，提供灵活配置选项"""
    parser = argparse.ArgumentParser(
        description="导出LocoySpider数据库中的产品数据为Woocommerce兼容的CSV文件"
    )

    # 数据库相关参数
    parser.add_argument(
        "-d",
        "--data-dir",
        type=str,
        default=LOCOY_SPIDER_DATA,
        help="采集器数据目录路径",
    )
    parser.add_argument(
        "-C",
        "--language-country",
        type=str,
        # default="US",
        required=True,
        # choices=[language.name for language in LanguagesHotSale],
        help=f"大写的C选项,表示[国家/语言]代码{LanguagesHotSale.get_all_fields_name()}",
    )
    parser.add_argument(
        "-s",
        "--start-id",
        type=int,
        required=True,
        help="起始采集任务ID（必填项）",
    )
    parser.add_argument(
        "-e",
        "--end-id",
        type=int,
        default=None,
        help="结束采集任务ID（默认与start-id相同）",
    )
    parser.add_argument(
        "-E",
        "--exclude-ids",
        # type=
        type=str,
        help="排除的采集任务ID，多个ID用逗号分隔",
    )
    parser.add_argument(
        "-f",
        "-fmt",
        "--default-extension",
        type=str,
        # default=DEFAULT_EXTENSION
        help="配置默认图片文件扩展名",
    )

    # 分类与价格过滤参数
    parser.add_argument(
        "-c",
        "--category-threshold",
        type=int,
        default=30,
        help="小分类阈值，低于此值的分类将被归入热销类（默认：30）",
    )
    parser.add_argument(
        "-L",
        "--lowest-price",
        type=float,
        default=0.5,
        help="最低价格过滤标准（默认：0.5）",
    )
    parser.add_argument(
        "-H",
        "--highest-price",
        type=float,
        default=20000,
        help="最高价格过滤标准（默认：20000）",
    )
    parser.add_argument(
        "--limit-sale",
        type=float,
        default=298.98,
        help="限制最高售价",
    )
    # 图片导出模式
    parser.add_argument(
        "-m",
        "--image-mode",
        type=str,
        choices=[mode.name for mode in ImageMode],
        default=ImageMode.NAME_FROM_SKU.name,
        help=f'图片字段导出模式，可选值: {", ".join(ImageMode.__members__.keys())}',
    )
    parser.add_argument(
        "-ml",
        "--max-image-name-length",
        type=int,
        default=MAX_IMG_NAME_LENGTH,
        help=f"图片文件名最大长度(default: {MAX_IMG_NAME_LENGTH})",
    )

    # 日志配置
    parser.add_argument(
        "--log-level",
        type=str,
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="日志输出级别(输出到日志文件中的级别);为了减少性能损耗,输出到控制台的级别为WARNING",
    )
    parser.add_argument(
        "-l",
        "-lf",
        "--log-file",
        type=str,
        help="日志文件路径（默认：./log/log_YYYYMMDD_HHMMSS.log）",
    )

    # 输出目录
    parser.add_argument(
        "-o",
        "--output-dir",
        type=str,
        default="./",
        help="导出CSV文件的输出目录（默认：当前目录）",
    )
    parser.add_argument(
        "-S",
        "--split-size",
        type=int,
        default=DEFAULT_CSV_LINES,
        help=f"分割输出CSV文件的大小(default: {DEFAULT_CSV_LINES})",
    )
    parser.add_argument(
        "-R",
        "--strict-mode",
        "--remove-duplicates-on-name",
        action="store_true",
        help="去除名称重复的产品(即便图片链接不同)",
    )
    parser.add_argument(
        "-count",
        "--count-rows-only",
        action="store_true",
        help="仅统计行数,不导出csv文件",
    )

    parser.add_argument(
        "-k",
        "--sku-suffix",
        type=str,
        help="自定义SKU后缀(可以通过指定LANGUAGE+NOW_STR)结构的后缀来强制让两批不同时间导出的csv数据中的sku时间部分相同,例如图片下好了,但是发现采集规则错误重新采集了一遍(注意数量是否不变),图片已经下好了,就可以用这个方法指定后缀匹配图片名)",
    )
    parser.add_argument(
        "-dl",
        "--desc-min-len",
        type=int,
        default=0,
        help="最小描述长度(默认:0,不限制)",
    )
    parser.add_argument(
        "-nad",
        "--name-as-desc",
        action="store_true",
        help="将产品名称作为产品描述(仅当原始的描述短于最小描述长度标准时才会生效)",
    )

    return parser.parse_args()


args = parse_args()  # 解析命令行参数
DEFAULT_IMAGE_EXTENSION = args.default_extension or ""
# 配置图片字段导出模式
# IMAGE_MODE = ImageMode.NAME_FROM_URL
IMAGE_MODE = ImageMode[args.image_mode] or ImageMode.NAME_FROM_SKU

# 产品价格区间(打折前不在此区间的产品将被过滤掉)
LOWEST_PRICE = args.lowest_price
HIGHEST_PRICE = args.highest_price
# 国家和语言🎈
# LANGUAGE = LanguagesHotSale.US.name
LANGUAGE = args.language_country or LanguagesHotSale.US.name

LIMIT_SALE = args.limit_sale or 298.98

# 获取当前的日期时间字符串(开放可以指定NOW_STR的参数,这样允许用户控制某个时间点导出的数据sku后缀为指定值,可以用来修复数据而不改变其他,比如现有的图片对应关系)
NOW_STR = datetime.now().strftime("%Y%m%d-%H%M%S")
LANGUAGE = LANGUAGE.upper()
DEFAULT_SUFFIX = LANGUAGE + NOW_STR
# sku后缀自定义
SKU_SUFFIX = args.sku_suffix or DEFAULT_SUFFIX


# 小分类阈值,小于该阈值的分类将被视为小分类,将其分配到热销类(或其近义词);设置为0表示不处理分类
# 限制产品数量少的分类,将其分配到热销类(或其近义词)
CATEGORIES_THRESHOLD = 30

# 确保日志目录存在
LOG_DIR = "./log"
LOG_FILE = (
    args.log_file or f"{LOG_DIR}/log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
)


# -----------------------------------------------------------
# 指定db文件来源的方案有多种,这里主推方案1,更加简便,但是方案2更加灵活;如果需要解开注释进行配置

# 方案1:遍历指定范围编号内文件夹,获取db文件(需要配置3个参数)
#   例如获取170-180编号采集文件夹下的db文件

# 根据你的采集器安装目录以及采集存放的db目录来填写🎈(末尾不要有\,前面可以有)


DATA_DIR = Path(args.data_dir.strip())
START = -1  # 用于开发测试,通常使用命令行的参数传参
END = START

# 综合确定参数
START = args.start_id or START
END = args.end_id or START

# 枚举出db文件路径
rng = range(START, END + 1)
dbs = []
exclude_ids = []
if args.exclude_ids:
    exclude_ids = [int(i) for i in args.exclude_ids.split(",")]

for dir_num in rng:
    if dir_num in exclude_ids:
        print(f"跳过 ID: {dir_num}任务")
        continue
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
    logging.info(file)

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


try:
    os.makedirs(LOG_DIR, exist_ok=True)  # 自动创建目录（如果不存在）
except Exception as e:
    print(f"无法创建日志目录 {LOG_DIR}: {e}")
    LOG_DIR = "."  # 如果失败则使用当前目录


def set_log():
    """配置日志记录器

    可以考虑到日志输出到控制台对程序性能的影响,可以考虑分开设置:
    让输出到控制台的级别为WARNING,而输出到文件的级别为INFO或DEBUG

    """

    # 作为主调用脚本(应用程序),使用root级别的默认logger
    logger = logging.getLogger()
    # 定义handler
    ch = logging.StreamHandler()
    fh = logging.FileHandler(LOG_FILE, mode="w", encoding="utf-8")
    # 定义日志格式
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s -%(funcName)s- %(levelname)s - %(message)s"
    )
    ch.setFormatter(formatter)
    fh.setFormatter(formatter)
    # 日志级别设置
    # 解析用户提供的日志级别
    level_str = args.log_level.upper()  # 用户指定的日志文件中的日志级别
    level = getattr(logging, level_str, None)
    if not isinstance(level, int):
        raise ValueError(f"Invalid log level: {level_str}")

    logger.setLevel(logging.DEBUG)
    ch.setLevel(logging.WARNING)  # 输出控制台的级别设置为WARNING

    fh.setLevel(level)

    print("Handlers before adding:")
    for h in logging.getLogger().handlers:
        print(h, h.level)
    # logger = logging.getLogger()
    for h in logger.handlers[:]:  # 使用切片复制列表避免修改时迭代出错
        logger.removeHandler(h)

    logger.addHandler(ch)
    logger.addHandler(fh)
    # logging.basicConfig(
    #     level=level,
    #     format="%(levelname)s - %(funcName)s - %(message)s",
    #     handlers=[fh, ch],
    # )
    # 对调用的woosqlitedb的日志级别进行设置(通常保持默认级别(WARNING即可))
    # db_logger = logging.getLogger(WOOSQLITEDB_LOGGER)
    # db_logger.setLevel(level=level)
    # db_logger.addFilter()

    return logger


# 使用示例
if __name__ == "__main__":
    lgr = set_log()
    lgr.info(
        f"开始执行(日志文件位于{LOG_FILE},绝对路径为:{os.path.abspath(LOG_FILE)})..."
    )
    ## 1. 实例化SQLiteDB对象
    db = SQLiteDB(
        language=LANGUAGE,
        category_threshold=CATEGORIES_THRESHOLD,
        lowest_price=LOWEST_PRICE,
        highest_price=HIGHEST_PRICE,
        max_img_name_length=args.max_image_name_length,
        desc_min_len=args.desc_min_len,
        name_as_desc=args.name_as_desc,
    )
    ## 2. 读取数据库数据(根据count_rows_only参数,可以只统计行数,而不做初步的数据处理;正式使用是要改成False!)🎈
    db.get_data(
        dbs=dbs, strict_mode=args.strict_mode, count_rows_only=args.count_rows_only
    )

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
        print("产品属性值存在不规范的子集")
        check_iterable(db.invalid_attribute_subset)
        print(f"共有{len(db.invalid_attribute_subset)}个属性值显然不规范的产品")
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
        logging.info("未发现不规范的产品属性值,默认继续执行...")
    ## 6.统计并处理产品分类(包括合并小分类,分配热销类);可以用data wragger查看cats统计结果
    cats = db.get_category_statistic(hot_class=LanguagesHotSaleX)  # type: ignore
    ## 7.更新产品数据(描述等)🎈
    db.update_products(dbs=dbs, sku_suffix=SKU_SUFFIX, strict_mode=False)
    ## 8.导出csv文件
    db.export_csv(
        dbs=dbs,
        out_dir=args.output_dir,
        split_files_size=args.split_size,
        img_mode=IMAGE_MODE,
        default_extension=DEFAULT_IMAGE_EXTENSION,
        limit_sale=LIMIT_SALE,
    )
