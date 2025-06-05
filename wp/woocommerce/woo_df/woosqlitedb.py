"""
读取火车头采集器中的数据,并将其写入到sqlite数据库中
"""

import csv
import os
import re
import sqlite3
import sys
import threading
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from logging import debug, error, info, warning
from pathlib import Path
import shutil

import pandas as pd

from comutils import (
    get_filebasename_from_url,
    remove_sensitive_info,
    split_urls,
    count_lines_csv,
)
from filenamehandler import FilenameHandler
from wooenums import CSVProductFields, DBProductFields, ImageMode, LanguagesHotSale

IMAGES = CSVProductFields.IMAGES.value
IMAGE_URL = CSVProductFields.IMAGES_URL.value

fh = FilenameHandler()
csv.field_size_limit(int(1e7))  # 设置为 10MB 或更高（单位：字节）

# 小分类阈值,小于该阈值的分类将被视为小分类
SMALL_CATEGORY_THRESHOLD = 30
# 配置切割不同url的分隔符(小心选择分隔符,例如逗号和分号是有可能出现在url中的),这里选择">"作为分隔符
SEPARATOR = ">"
LOWEST_PRICE = 1
HIGHEST_PRICE = 10000
cnt_lock = threading.Lock()


def update_image_fields_from_legacy(csv_file):
    """更新图片字段
    针对只有Images字段但是缺失ImagesUrl字段的产品图片字段更新/补全完整(主要为兼容老csv格式准备的)
    这种里针对Images包含了图片url的情况，然后ImagesUrl字段取代Images字段，Images字段会更新为图片名

    """
    df = pd.read_csv(csv_file)
    # fh = FilenameHandler()
    if IMAGE_URL in df.columns and df[IMAGE_URL].notnull().any():
        print("ImagesUrl field already exists, no need to update.")
        return  # 相关字段已经存在,不需要更新
    df[IMAGE_URL] = df[IMAGES]
    df[IMAGES] = df[IMAGES].apply(fh.get_filename_from_url)
    df.to_csv(csv_file, index=False)


def update_image_fields(csv_dir):
    """将指定文件夹中的csv文件中的图片字段更新
    循环调用 `update_image_fields_from_legacy` 函数更新指定文件夹中的csv文件中的图片字段

    """
    print(csv_dir)
    for file in os.listdir(csv_dir):
        file = os.path.abspath(os.path.join(csv_dir, file))

        # print(file)
        # update_image_fields(file)
        if file.endswith(".csv"):
            print(f"Updating image fields for:{file} ")
            update_image_fields_from_legacy(file)


def update_image_fields_extension(csv_dir, extension="webp"):
    """将指定文件夹中的csv文件中的图片字段的值的后缀名改为指定格式"""
    print(csv_dir)
    for file in os.listdir(csv_dir):
        file = os.path.abspath(os.path.join(csv_dir, file))
        if file.endswith(".csv"):
            print(f"Updating image fields extension for:{file} ")
            df = pd.read_csv(file)
            df[IMAGES] = df[IMAGES].str.rsplit(".", n=1).str[0] + f".{extension}"
            df.to_csv(file, index=False)


def remove_items_without_img(csv_dir, img_dir, backup_dir="backup_csvs"):
    """删除csv文件中没有图片的产品

    Args:
        csv_dir (str): csv文件所在目录
        backup_dir (str, optional): 备份目录,如果为空串,则不备份. Defaults to "".

    """
    print(csv_dir)
    for file in os.listdir(csv_dir):
        file = os.path.abspath(os.path.join(csv_dir, file))
        if file.endswith(".csv"):
            print(f"Removing items without image for:{file} ")
            df = pd.read_csv(file)
            # 根据需要备份文件
            if backup_dir:
                # 复制文件file到backup_dir目录下备用

                os.makedirs(backup_dir, exist_ok=True)  # 确保备份目录存在
                backup_file_path = os.path.join(backup_dir, os.path.basename(file))
                shutil.copy(file, backup_file_path)  # 复制文件到备份目录
            # 判断每个IMAGE字段中的图片在指定目录下是否存在,不存在的过滤移除
            df = df[
                df[IMAGES].apply(
                    lambda x: os.path.exists(os.path.join(img_dir, str(x)))
                )
            ]

            # 将过滤后的数据保存回原文件
            df.to_csv(file, index=False)


def process_image_csv(img_dir, csv_dir, backup_dir="backup_csvs"):
    """更新CSV文件中的图片字段,设置格式为webp,并移除无图片的条目
    请务必图片下载完毕后再执行本处理,否则csv文件内容将因为图片找不到而全部被移除

    默认情况下执行此函数会进行备份,因此如果清空太多图片,则可以恢复备份文件

    """
    csv_dir = os.path.abspath(csv_dir)  # 计算绝对路径
    print(csv_dir)

    total_before = count_lines_csv(csv_dir)

    update_image_fields(csv_dir)
    update_image_fields_extension(csv_dir, extension="webp")
    remove_items_without_img(csv_dir, img_dir=img_dir, backup_dir=backup_dir)

    if backup_dir:
        cwd = os.getcwd()
        backup_dir = os.path.abspath(os.path.join(cwd, backup_dir))  # 计算绝对路径
        print(f"csv文件备份到{backup_dir}")
    total_after = count_lines_csv(csv_dir)
    print(f"处理后剩余{total_after}条数据,减少了{total_before-total_after}条数据")


class SQLiteDB:
    """sqlite数据库操作类
    根据业务需要,这里主要以读取操作为主,其他操作可以后期按需扩展

    """

    def __init__(
        self,
        language="US",
        category_threshold=SMALL_CATEGORY_THRESHOLD,
        lowest_price=LOWEST_PRICE,
        highest_price=HIGHEST_PRICE,
    ):
        self.language = language
        # 默认缓存变量(从DB文件中读取)
        self.field_names_full = DBProductFields.get_all_fields_name(
            exclude_field=DBProductFields.SKU.name
        )
        self.field_values_full = DBProductFields.get_all_fields_value(
            exclude_field=DBProductFields.SKU.value
        )
        self.lowest_price = lowest_price
        self.highest_price = highest_price
        self.category_threshold = category_threshold
        # 缓存从数据库中读出来的数据行(记录),默认情况下仅存储业务需要的行以及字段
        self.db_rows = []
        # self.data_dict_rows = []
        # 统计各个数据库读入的可用数据行数
        self.db_reports = {}
        # 具有属性值的产品缓存(db row对象)
        self.products_with_attribute = []
        # 保存简化字段的字典(name,sku,attribute_values,page_url)
        self.attribute_checker = []
        # 记录显然不规范的属性值产品(db_rows的子集)
        self.invalid_attribute_subset = []
        # 速查属性值不规范的产品列表索引
        self.invalid_index_dict = {}
        # 记录可能不规范的属性值的产品
        self.invalid_attribute_supperset = []
        # 分类统计
        self.category_statistic = {}
        self.attr_subset_pattern = re.compile(r".*#.*")
        self.attr_superset_pattern = re.compile(r".*#.*\|.*")
        # 处理进度(产品数据条数)
        self.progress = 0

    def get_selected_fields(
        self,
        connection,
        table="Content",
        empty_check=True,
        fields="",
        where=None,
        params=None,
    ):
        """
        获取表中指定字段
        :param connection: 数据库连接
        :param table: 表名
        :param fields: 字段列表或字符串
        :param where: WHERE条件语句（不含WHERE关键字）
        :param params: 条件参数
        :param empty_check: 是否过滤掉数据库中空行(比如没有产品名称为空的行)
        :return: 结果列表
        """
        # 构造查询语句
        if not fields:
            fields = self.field_values_full
        if isinstance(fields, (list, tuple)):
            fields_str = ", ".join(fields)
            fields_str = fields_str.replace("", "")
        else:
            fields_str = fields
        sql = f"SELECT {fields_str} FROM {table}"
        if where:
            sql += f" WHERE {where}"
        # 获取查询指针
        cursor = connection.cursor()
        cursor.execute(sql, params or ())
        rows = cursor.fetchall()  # sqlite3.Row对象的列表

        if empty_check:
            # 检查行的名字字段是否为空(需要过滤掉)
            rows = [row for row in rows if row[DBProductFields.NAME.value]]
        # self.data_rows += rows
        return rows

    def get_data_init(self, db_path, fields="", count_rows_only=False):
        """从单个数据库获取数据的辅助函数"""
        info("read data from %s...", db_path)
        rows = []
        unique_rows = []
        try:
            rows = self.get_data_from_db(db_path, fields)
            if count_rows_only:
                self.db_reports[db_path] = {
                    "total_raw": len(rows),
                    "total_unique": None,
                }
                return []

        except sqlite3.Error as e:
            error(
                "Jump process:[%s] file is not a valid db file. Error: %s", db_path, e
            )
            return []
        else:
            # 数据处理操作
            # 去重:产品名和图片同时重复的记录只保留一条(仅排除两者都重复的情况)
            handler_dict = defaultdict(
                dict
            )  # 存储单元结构: {product_img: {name: count}}的结构
            name_field = DBProductFields.NAME.value
            img_field = DBProductFields.IMAGES.value
            # sku_field = DBProductFields.SKU.value
            # sku=DBProductFields.SKU.value
            # 访问内存中的数据行
            for i, row in enumerate(rows):
                # product_name = row[name_field]
                # product_img=row[img_field]
                # product_sku = row[sku_field]
                product_name = row[name_field]
                product_img = row[img_field]
                # product_info = f"{{name:{product_name};sku:{product_sku}}}"
                names = handler_dict.get(product_img, {})
                # 进度计数器
                with cnt_lock:
                    self.progress += 1
                    # info("progress: {{%s}}", self.progress)
                    print(f"progress: {self.progress}")
                # 检查重复

                dbp = Path(db_path)
                # 获取父目录的名称
                db_id = dbp.parent.name  # 输出: 'c'
                if product_name in names:
                    warning(
                        "Jump:product:[%s] of [%s db]: duplicated name & image, skip this record!",
                        i,
                        db_id,
                    )
                    continue
                else:
                    # 当前产品尚未统计过,更新统计计数器
                    unique_rows.append(row)
                    info(
                        "keep:product:[%s] of [%s db]: duplicated image, \
but different name, keep records",
                        i,
                        db_id,
                    )

                handler_dict[product_img][product_name] = (
                    handler_dict[product_img].get(product_name, 0) + 1
                )

            # print(handler_dict)
        self.db_reports[db_path] = {
            "total_raw": len(rows),
            "total_unique": len(unique_rows),
        }
        return unique_rows

    def get_data_from_db(self, db_path, fields):
        """从单个数据库获取数据
        :param db_path: sqlite文件路径
        :param fields: 字段列表或字符串
        """
        with sqlite3.connect(str(db_path)) as conn:
            # 设置SQLite性能优化参数
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA synchronous=OFF")
            conn.execute("PRAGMA cache_size=-10000")  # 10MB缓存
            conn.row_factory = sqlite3.Row
            rows = self.get_selected_fields(
                connection=conn, fields=fields, empty_check=True
            )

        return rows

    def get_data_from_dbs(self, dbs, max_workers=8, fields="", count_rows_only=False):
        """
        使用多线程从多个SQLite数据库并行读取数据

        参数:
            dbs: SQLite文件路径列表
            query: SQL查询语句
            max_workers: 最大线程数

        返回:
            list: 合并后的数据列表
        """

        all_data = self.db_rows
        info("read data from %s files using %s threads...", len(dbs), max_workers)
        batch_size = 10  # 每批处理10个文件
        for i in range(0, len(dbs), batch_size):
            batch = dbs[i : i + batch_size]
            with ThreadPoolExecutor(max_workers=max_workers) as executor:
                futures = [
                    executor.submit(
                        self.get_data_init,
                        db_file,
                        fields=fields,
                        count_rows_only=count_rows_only,
                    )
                    for db_file in batch
                ]
            # 收集结果
            for future in as_completed(futures):
                result = future.result()
                if result:
                    all_data.extend(result)

        return all_data

    def remove_sensitive_info_from_description(self, dbs):
        """
        移除描述中的敏感信息
        """
        rows = self.get_data(dbs=dbs)
        for row in rows:
            description = row[DBProductFields.DESCRIPTION.value]
            row[DBProductFields.DESCRIPTION.value] = remove_sensitive_info(description)

        return rows

    def update_products(
        self, dbs, process_attribute=False, sku_suffix=None, strict_mode=False
    ):
        """
        更新产品数据,让数据更加规范

        在从sqlite(db3)文件读取数据,调用get_data()的过程中已经做了初步的数据处理
        (比如价格处理,去除重复产品等,这些是团队业务必须的)

        而下面的步骤是让数据更加规范(如果不处理,不一定会出现问题)
        - 统一编号(number)数据库中产品型号
        - (尽量)清理描述中不需要的内容,如邮箱地址、网址、电话号码等,
            并且，对于库存这类消息,需要采集员采集时避免采集到或者及时替换为空翻译后阅读检查
        - 处理不规范的属性值(建议采集员在采集时就认真抽查,毕竟事后查出问题再补救可能更浪费时间)

        :param process_attribute: 是否处理属性值,默认为False(建议手动调用相关方法检查属性值后,
            如果没有太多不规范或者无关紧要才设置为True)
        :param strict_mode: 是否严格模式(检查产品描述中的敏感信息),默认为False(可以加速导出,效果不好估计,但是数据可能包含邮箱或者url)


        """

        self.number_sku(dbs=dbs, sku_suffix=sku_suffix)
        if process_attribute:
            self.empty_invalid_attribute_subset(dbs=dbs)
        info("Jump process: remove sensitive info from description.")
        if strict_mode:
            # warning("Warning: strict mode is on, remove sensitive info from description.")
            self.remove_sensitive_info_from_description(dbs=dbs)
        return self.db_rows

    def number_sku(self, dbs, sku_suffix=None):
        """
        统一编号(number)数据库中产品型号
        经过必要数据筛选(去重和超低价过滤后),编制统一的产品价格
        """
        if sku_suffix is None:
            sku_suffix = self.language

        rows = self.get_data(dbs=dbs)
        sku = DBProductFields.SKU.value
        for idx, _ in enumerate(iterable=rows):
            new_sku = f"SK{idx+1:07d}-{sku_suffix}"
            debug("SKU: %s-> %s", rows[idx].get(sku, ""), new_sku)
            rows[idx][sku] = new_sku

    def get_data(self, dbs, get_dict_row=True, count_rows_only=False):
        """从缓存或数据库中获取数据
        如果缓存中上不存在数据,则从数据库中读取数据并缓存到self.data_rows中

        """

        if not self.db_rows:
            self.db_rows = self.get_data_from_dbs(
                dbs=dbs, count_rows_only=count_rows_only
            )
        if get_dict_row:
            self.db_rows = [dict(db_row) for db_row in self.db_rows]
        if count_rows_only:
            reports = self.db_reports
            cnt = 0
            for v in reports.values():
                cnt += v["total_raw"]
            info("total rows: %s", cnt)
            info(str(self.db_reports))
            sys.exit(0)  # 只统计行数,不做数据处理,立即退出程序(0表示正常退出)
        return self.db_rows

    def get_products_with_attribute_values(self, dbs):
        """
        获取所有产品的属性值
        """
        rows = self.get_data(dbs=dbs)
        for row in rows:
            if row[DBProductFields.ATTRIBUTE_VALUES.value]:
                self.products_with_attribute.append(row)

        return self.products_with_attribute

    def get_attribute_of_products(
        self,
        dbs,
        check_invalid_attribute_subset=True,
        check_invalid_attribute_supperset=False,
    ):
        """
        获取所有具有属性值的产品的字段简化的字典列表
        1. name
        2. sku
        3. attribute_values
        4. page_url
        支持通过开关参数执行不规范属性值数据分类
        后面两个参数在大量不规范的属性值数据时,可能会导致导出缓慢,占用cpu资源
        (虽然设置了开关,主要用于测试和确认导出速度的瓶颈,提醒读者检查采集数据是否有重大问题)


        :param dbs: SQLite文件路径列表
        :param check_invalid_attribute_subset: 是否检查不规范的属性值子集(属性值中包含#号);
            对于包含大量不规范属性值的数据可能导致导出缓慢,占用cpu资源
        :param check_invalid_attribute_supperset: 是否检查不规范的属性值超集(属性值中包含#号和|号)
            对于包含大量不规范属性值的数据可能导致导出缓慢,占用cpu资源


        """
        rows_with_attribute = self.get_products_with_attribute_values(dbs=dbs)
        for row in rows_with_attribute:
            name = row[DBProductFields.NAME.value]
            # sku: str = row[DBProductFields.SKU.value]
            sku = row.get(DBProductFields.SKU.value, "")
            attribute_values = row[DBProductFields.ATTRIBUTE_VALUES.value]
            page_url = row[DBProductFields.PAGE_URL.value]
            item = {
                DBProductFields.NAME.value: name,
                DBProductFields.SKU.value: sku,
                DBProductFields.ATTRIBUTE_VALUES.value: attribute_values,
                DBProductFields.PAGE_URL.value: page_url,
            }
            self.attribute_checker.append(item)
            # 可选的,根据参数开关是否执行下面的分类统计代码
            # 下面的两个插入语句有两种选择:插入item或者row
            row = item
            if check_invalid_attribute_subset:
                self._check_invalid_attribute_subset(row)
            if check_invalid_attribute_supperset:
                self._check_invalid_attribute_supperset(row)
        return self.attribute_checker

    def empty_invalid_attribute_subset(self, dbs, remove=False):
        """移除显然不合规范的属性值

        :param remove: 是否移除产品,而不仅仅是将属性值置空,默认为False,仅置空

        :return: 处理后的数据库行列表

        采用合适的方式批量置空或移除列表中的元素
        """
        # for row in self.invalid_attribute_subset:
        #     self.db_rows.remove(row)
        self.get_attribute_of_products(dbs=dbs)
        # 构造以产品sku_i:name_i为key-value的字典,便于速查
        sku_field = DBProductFields.SKU.value
        name_field = DBProductFields.NAME.value
        attribute_field = DBProductFields.ATTRIBUTE_VALUES.value
        # 基于self.invalid_attribute_subset构造字典
        invalid_dict = self.invalid_index_dict
        for item in self.invalid_attribute_subset:
            invalid_dict[item[sku_field]] = f"[{item[name_field]}]"

        # 遍历数据库行,处理显然不合规范的属性值
        if remove:
            # 移除不规范属性值的产品
            # 方案1:使用列表推导式创建新列表
            self.db_rows = [
                row for row in self.db_rows if row[sku_field] not in invalid_dict
            ]

            # 方案2:使用列表的remove方法(原地替换)
            # to_remove = [row for row in self.db_rows if row[sku] in invalid_dict]
            # for row in to_remove:
            #     self.db_rows.remove(row)
        else:
            # 仅将不规范属性值的产品置空
            # 方案1:直接操作self.db_rows中的元素(更稳,但是速度更慢)
            # for row in self.db_rows:
            #     sku=row[sku_field]
            #     if invalid_dict[sku]:
            #         row[attribute_field] = ""
            # 方案2:通过self.invalid_attribute_subset的遍历修改(速度快)
            for item in self.invalid_attribute_subset:
                # sku = item[sku_field]
                item[attribute_field] = ""

        return self.db_rows

    def _check_invalid_attribute_subset(self, row):
        """判断属性值是否有效

        合法的属性值的一般格式:attr1#value1|value2|...~attr2#value1|value2|...
        其中attr1,attr2为属性名称,value1,value2为属性值,~为各组属性值分隔符

        简单期间,这里仅检查属性值是否满足正则: .*#.*

        :param row: 要被检查的数据库行

        """
        value = row[DBProductFields.ATTRIBUTE_VALUES.value]
        p = re.compile(r".*#.*")
        if value and not p.match(value):
            debug("Invalid attribute value: %s", value)
            self.invalid_attribute_subset.append(row)
        return self.invalid_attribute_subset

    def _check_invalid_attribute_supperset(self, row):
        """严格的方式判断属性值是否有效
        检查结果列出的数据行不一定是无效的,只是供参考,检查可疑的带有属性值的行,尤其是新手,老手可以跳过检查

        这里检查属性值是否同时具有#和|

        :param row: 要被检查的数据库行

        """
        value = row[DBProductFields.ATTRIBUTE_VALUES.value]
        name = row[DBProductFields.NAME.value]
        sku = row[DBProductFields.SKU.value]
        p = re.compile(r".*#.*\|.*")
        if value and not p.match(value):
            warning(
                "atypical or non-standard  attribute value: {name=%s;sku=%s;value=%s}",
                name,
                sku,
                value,
            )
            self.invalid_attribute_supperset.append(row)
        return self.invalid_attribute_supperset

    def update_hotsale(
        self,
        row,
        cat_field=CSVProductFields.CATEGORIES.name,
        # hot_sale_category="",
        hot_class=LanguagesHotSale,
        language="",
    ):
        """设置"热销"这里产品分类名称

        :param row: 数据库行
        :param lang: 语言代码,默认为US
        :return: 设置后的分类名称
        """
        language = language or self.language
        # if not hot_sale_category:
        hot_sale_category = hot_class.get_one_hot_sale_names(language=language)
        row[cat_field] = hot_sale_category

        debug("change:category [%s]->[%s]  ", row[cat_field], hot_sale_category)

        return hot_sale_category

    def get_lines_lst(self, dbs):
        """
        将读取到的数据库行转换为列表返回
        """
        res = self.get_data(dbs=dbs)
        lines = []
        for r in res:
            lst = [r[v] for v in self.field_values_full]
            lines.append(lst)
        return lines

    def _get_lines_dict_raw(self, dbs, extra_fields=None) -> list[dict]:
        """
        获取所有产品数据，每行作为字典返回,一般不直接调用
        键使用ProductField枚举成员,字段仅包含核心的字段,可以供另一个方法调用:get_lines_dict_full
        它允许你自定义添加字典,便于后期导出为woocommerce要求的csv文件

        此方法允许你可选地加入额外的键值对

        :param extra_fields: 可选参数，包含额外键值对的字典(还可以是其他形式的键值对,比如元组等)
        :return: 字典列表，每个字典键是ProductField枚举成员和extra_fields中的键，
                值是对应的数据库值和extra_fields中的值
        返回的列表中的元素例子
        {
            'NAME': 'Stabilimento balneare "VICTORIA" Piccolo',
            'CATEGORIES': 'Miglior valore',
            'REGULAR_PRICE': '7.50',
            'IMAGES': 'http://birdshopchristina.com/cdn/shop/files/bagnetto-dipinto.jpg',
            'ATTRIBUTE_VALUES': '',
            'TAGS': 'STA',
            'SKU': 'SK0000002-IT',
            'DESCRIPTION': "<p>...</p>",
            'PAGE_URL': 'https://it.birdshopchristina.com/de/products/naamloos-10sep-_21-36'
        }
        """
        # results = self.get_selected_fields(connection)
        rows = self.get_data(dbs=dbs)
        lines = []
        for row in rows:
            line_dict = {}
            for field in DBProductFields:
                line_dict[field.name] = row[field.value]  # 使用枚举成员作为键
            if extra_fields is not None:
                line_dict.update(extra_fields)  # 合并额外的键值对
            lines.append(line_dict)
        return lines

    def get_sale_price(self, price):
        """获取产品折扣价格
        1.价格小于100的打3折
        2.价格100到300的打0.25折
        3.价格大于300的先打0.2折
        4.价格大于300的打完0.2折后。价格还大于300的价格设置为299.99
        :param row: 数据库行
        :return: 折扣价格(如果返回0,表示这个产品初始价格过于低或过高,这个产品要过滤掉,由调用者处理)
        """
        lowest_price = self.lowest_price
        highest_price = self.highest_price
        try:
            price = float(price)
        except ValueError:
            return 0
        # 移除过低或过高价产品
        if price > highest_price:
            return 0
        if price < lowest_price:
            return 0
        # 普通情况
        sale_price = 0
        if price < 100:
            sale_price = price * 0.3
        elif price >= 100 and price < 300:
            sale_price = price * 0.25
        elif price >= 300:
            sale_price = price * 0.2
            if sale_price > 300:
                sale_price = 299.99

        # 保留2位小数
        sale_price = round(sale_price, 2)
        return sale_price

    def get_lines_dict_for_csv(
        self,
        dbs,
        img_mode=ImageMode.NAME_AS_URL,
        extra_fields=None,
        hot_class=LanguagesHotSale,
        language="",
        req_response=False,
    ):
        """
        获取产品数据行的字段补充和修改后的字典形式数据，每行数据作为字典返回,服务于导出到csv的阶段预备
        (字段数量足够,但是字段名字还不是woocommerce要求的,比如暂时产品名字,还是NAME,而不是Name,后面统一转换)

        操作的对象(字典)的key是枚举值中的成员name名字(大写英文),而不是value(处于DB->CSV的中间状态)
        此方法会基于原始采集的数据库中的字段的基础上增加一些字段,利用字典的左值的方式添加字段和赋值,例如
        row[CSVProductFields.SALE_PRICE.name] = sale_price
        row[CSVProductFields.ATTRIBUTE_NAME.name] = ""

        包含业务所需要的所有字段,或者额外需要的字段,但是表头名还不是woocommerce要求的
        需要调用其他方法,此方法辅助export_csv方法导出woocommerce要求的csv文件

        :param extra_fields: 可选参数，包含额外键值对的字典(还可以是其他形式的键值对,比如元组等)
        :param lang: 语言代码，默认为"US"
        :param img_mode: 图片处理模式,默认为ImageMode.NAME_AS_URL,即图片链接直接作为图片名
        :param hot_class: 热销分类类,默认为LanguagesHotSale,即语言热销词
        :param req_response: 如果直接从response中获取文件类型失败，是否需要针对url发起网络请求获取响应来计算文件类型

        :return: list[dict] 返回字段扩充后的数据行的列表
        """
        language = language or self.language
        rows = self._get_lines_dict_raw(dbs=dbs, extra_fields=extra_fields)
        expanded_rows = []
        for row in rows:
            # 数据处理:特价
            price = row[DBProductFields.REGULAR_PRICE.name]
            sale_price = self.get_sale_price(price)
            if sale_price == 0:
                continue
            # 数据处理:产品分类(将分类取值为非常规值做一个恰当的转换,比如热销这类的此)
            category = row[CSVProductFields.CATEGORIES.name]
            if self.is_need_update_category(category):
                self.update_hotsale(row=row, hot_class=hot_class, language=language)
            # 将计算到的价格数据写入到对应的字典(不存在指定字段时会创建,即数据行row字典对象中写入对应key:value)
            row[CSVProductFields.SALE_PRICE.name] = sale_price
            # 扩充一个空值属性值字段,用于后期属性值处理
            row[CSVProductFields.ATTRIBUTE_NAME.name] = ""

            # 为属性值非空的产品添加默认属性名(mycustom)
            if row[CSVProductFields.ATTRIBUTE_VALUES.name]:
                # if row.get(CSVProductFields.ATTRIBUTE_VALUES.value):
                row[CSVProductFields.ATTRIBUTE_NAME.name] = "mycustom"
            # 处理图片(图片链接)字段
            img_field = CSVProductFields.IMAGES.name
            img_url_field = CSVProductFields.IMAGES_URL.name
            sku_field = CSVProductFields.SKU.name
            # 根据图片模式执行对应的字段扩充和修改
            if img_mode == ImageMode.NAME_AS_URL:
                # 默认模式,不需要修改
                pass
            else:
                # 需要进行图片相关字段的迁移
                # 1.设置图链字段(直接引用原图片字段)
                ## 由于采集器暂时仅采集图片链接,存放产品图片存放的取值赋值给图片链接字段,所以直接引用原图片字段即可
                img_urls = row[img_field]
                row[img_url_field] = img_urls

                # 2.处理图名字段(考虑多图,从图片链接解析入手判断图片数量以及图片名取名和编号)
                ## 考虑到可能会采集多个图片,这里预设图片链接之间的分隔符可能是">"," ",为了便于统一处理,将">"替换为空格,然后利用split分割
                # img_url_lst = img_urls.replace(">", " ").split()
                img_url_lst = split_urls(img_urls)
                img_names = []
                # 以sku命名图片🎈
                if img_mode == ImageMode.NAME_FROM_SKU:
                    sku = row[sku_field]
                    # 基于sku,编号命名该产品的多个图片(如果有多图的话)
                    img_names = [
                        f"{sku}-{i}"
                        + self._get_img_extension(
                            img_url=img_url, req_response=req_response, prefix_dot=True
                        )
                        for i, img_url in enumerate(img_url_lst)
                    ]
                elif img_mode == ImageMode.NAME_FROM_URL:
                    img_names = [get_filebasename_from_url(url) for url in img_url_lst]

                row[img_field] = ",".join(img_names)
            # 扩充数据行字典
            expanded_rows.append(row)
        return expanded_rows

    def _get_img_extension(self, img_url, req_response=False, prefix_dot=False):
        """
        尝试获取图片文件的后缀名
        (处理单个图片链接,可以配合循环批量处理)
        :param img_url: 图片链接
        :return: 图片后缀名
        """
        # if not img_url:
        #     return ""
        # return img_url.split(".")[-1]
        res = fh.get_file_extension(
            url=img_url, req_response=req_response, prefix_dot=prefix_dot
        )
        return res

    def split_list_average(self, lst, n):
        """尽可能均匀的将lst切分为n份
        这里使用专门的算法将切割代码写得紧凑
        算法需要找规律总结出来,相对不容易看出来,也可以考虑使用更加通俗的算法来均匀划分
        """
        q, r = divmod(len(lst), n)
        return [lst[i * q + min(i, r) : (i + 1) * q + min(i + 1, r)] for i in range(n)]

    def get_category_statistic(
        self, change_small_to_hotsale=True, hot_class=LanguagesHotSale
    ):
        """统计分类信息报告"""
        category_statistic = self.category_statistic
        product_dict_lst = self.db_rows
        for idx, row in enumerate(product_dict_lst):
            category = row[DBProductFields.CATEGORIES.value]
            debug("processsing:category: %s of row...", category)

            if self.is_need_update_category(category):
                # debug("warn:category: [%s] of row to a best-saler category  ...", category)
                self.update_hotsale(
                    row=row,
                    hot_class=hot_class,
                    cat_field=DBProductFields.CATEGORIES.value,
                    language=self.language,
                )

            if category_statistic.get(category):
                category_statistic[category]["count"] += 1
                category_statistic[category]["product_lst"].append(
                    {"row_data": row, "row_index": idx}
                )
            else:
                category_statistic[category] = {
                    "count": 1,
                    "product_lst": [{"row_data": row, "row_index": idx}],
                }
        if change_small_to_hotsale:
            # cat_static_bakview=list(category_statistic.items())
            for category, cat_set in category_statistic.items():
                # cat_set = category_statistic[category]
                info("Info:category: %s, count: %s", category, cat_set["count"])
                if cat_set["count"] < self.category_threshold:
                    product_dict_lst = cat_set["product_lst"]
                    # 事先为小类分配生成一个类似热销的分类
                    new_cat = hot_class.get_one_hot_sale_names(language=self.language)
                    cat = DBProductFields.CATEGORIES.value
                    # 遍历所有产品数据字典
                    for row in product_dict_lst:
                        # 修改数据行的分类字段
                        # A1:直接影响self.db_rows中的行
                        # row[cat] = new_cat
                        row["row_data"][cat] = new_cat  # 修改row_data而不是row本身
                        # A2:更改灵活的独立控制
                        # row_index = row["row_index"]
                        # self.db_rows[row_index][cat] = new_cat
                        info(
                            "Info:change small category to hotsale: %s->%s",
                            category,
                            new_cat,
                        )
            # 方案1:手动逐步处理
            # 将此类中的产品数据行移动(并入)到热销类别的产品集中
            #         self.category_statistic[new_cat]["product_lst"].extend(rows_lst)
            #         # 更新对应热卖词下的产品数量
            #         self.category_statistic[new_cat]["count"] += cat_set["count"]
            #         # 将对应的分类从缓存中移除(具体的做法又有多种,可以最后统一过滤掉小类,用字典推导式;或者在循环中删除,迭代对象是列表的副本)
            #         # del self.category_statistic[category]
            # self.category_statistic = {
            #     k: v
            #     for k, v in self.category_statistic.items()
            #     if v["count"] >= self.category_threshold
            # }

            # 方案2: 重新统计转换/合并小类别后的情况(先清空原来的统计数据,防止干扰)
            self.category_statistic = {}
            self.get_category_statistic(change_small_to_hotsale=False)
        return self.category_statistic

    def is_need_update_category(self, category):
        """判断是否需要更新分类
        当分类为空,或者是"!",或者是"热卖"时,需要更新分类

        :param category: 分类名称
        :return: True/False
        """
        return not category or category == "!" or category == "热卖"

    def export_csv(
        self,
        dbs,
        out_dir="./",
        img_mode=ImageMode.NAME_AS_URL,
        split_files_size=10000,
        average_split_files=0,
    ):
        """
        导出csv文件
        :param file_path: 文件路径
        :split_files: 单个csv文件最大行数,默认为10000,如果不能整除,则余数行数保存到最后一份;
        :average_split_files: 平均切割文件数,默认为0,表示不切割;
        :img_mode: 是否仅保存图片名作为"图片字段"(一般可以指定产品图片名字为产品sku),
            而图片链接字段单独一列(图片url字段),下载的时候保存为sku同名
            这样图片字段可以省略掉,然后在上传代码中将sku赋值给图片字段,
            但是如果考虑掉其他团队代码的兼容性,则单独保留,而且还可以进一步自定图片名字为"sku+产品名");
        :return: None
        """
        header = CSVProductFields.get_all_fields_name(img_mode=img_mode)
        header_for_woo = CSVProductFields.get_all_fields_value(img_mode=img_mode)
        warning("Info:csv header: %s", header_for_woo)
        # 准备好数据🎈
        lines = self.get_lines_dict_for_csv(dbs=dbs, img_mode=img_mode)

        # self._export_csv(file_path, header, lines)
        # self.update_csv_header_inplace(file_path, header_for_woo)

        file_rows_lst = [lines]
        # 将数据行分割成每份split_files_size个数据,或者尽可能均匀的分成average_split_files份数据
        if split_files_size:
            file_rows_lst = [
                lines[i : i + split_files_size]
                for i in range(0, len(lines), split_files_size)
            ]
        elif average_split_files:
            file_rows_lst = self.split_list_average(lines, average_split_files)
        # if(file_rows_lst):

        for i, file_rows in enumerate(file_rows_lst):
            file_path = os.path.join(out_dir, f"p{i+1}.csv")
            self._export_csv(file_path=file_path, header=header, rows=file_rows)

            self._update_csv_header_inplace(
                file_path=file_path, new_headers=header_for_woo
            )

    def _export_csv(self, file_path, header, rows):
        """根据所给的rows导出单个csv文件

        param:file_path: csv文件路径
        param:header: 表头列表
        param:rows: 数据行列表
        """
        with open(file_path, "w", newline="", encoding="utf-8") as f:
            # writer = csv.writer(f)
            # writer.writerow(header)
            # writer.writerows(lines)
            writer = csv.DictWriter(f, fieldnames=header)
            writer.writeheader()
            writer.writerows(rows)
            # # 将csv的表头字段名字调整为符合woocommerce的要求
            # writer_woo=csv.DictWriter(f, fieldnames=header_for_woo)
            # writer_woo.writeheader()

    def _update_csv_header_inplace(self, file_path, new_headers):
        """
        直接修改原CSV文件的表头
        参数:
            file_path: CSV文件路径
            new_headers: 新表头列表
        """
        temp_file = file_path + ".tmp"
        with open(file_path, "r", newline="", encoding="utf-8") as infile, open(
            temp_file, "w", newline="", encoding="utf-8"
        ) as outfile:
            reader = csv.reader(infile)
            writer = csv.writer(outfile)
            # 跳过旧表头
            next(reader)
            # 写入新表头
            writer.writerow(new_headers)
            # 写入剩余数据
            writer.writerows(reader)
        # 替换原文件
        os.replace(temp_file, file_path)
