"""
Woocommerce product handler/uploader for wordpress.
Copyright (C) 2025 cxxu1375. All Rights Reserved.

使用文档和注意事项,请查看Readme.md文本文件(必看)
尤其是遇到问题,可以参考文档中的说明
"""

__author__ = "cxxu1375 <827797013@qq.com>"
__status__ = "production"
# The following module attributes are no longer updated.
__version__ = "1.0"
__date__ = "2025-04-07"
# %%

# 请安装必要的库(主要是woocomece库要下载,也可以自行提取,大多是自带无需下载的库)
# from typing import Literal
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
from math import ceil
from datetime import datetime
import queue
import sys
from enum import Enum

# 其他模块
import json
import csv
import html
import os
import copy
import pickle
import requests

from requests import Response
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
# from requests.exceptions import ConnectTimeout, ReadTimeout, Timeout, RequestException

# 核心库(需要安装)
from woocommerce import API
csv.field_size_limit(int(1e7))  # 允许csv文件最大为10MB

##

# 用户要配置的参数🎈(仔细检查下面内容)
protocal = "http"  # 协议,一般是https(适用于正式上传),http(适用于本地脚本调试/开发)
domain = "wp.com"  # 域名
url = f"{protocal}://{domain}"  # http://域名 (不要有多余的路径)
consumer_key = "ck_cea9b0730bbda84628674625dc206495ddf62fc7"
consumer_secret = "cs_ba0185c197dc041ad8ba91915886395404badcb9"

# firebat
# consumer_key = "ck_bd5332370e52be2ee62f63204f75f6acaf796ebb"
# consumer_secret = "cs_f0c215137e0b9db09dfa4691cb080a6273f2f8fd"

# 这里指定目录,不是文件!🎈(指定文件请到备用方案2中指定)
CSV_DIR = r"./csv_dir/"
# CSV_DIR = r"C:/users/cxxu/Desktop"


# 额外可配置参数
# 最大总线程数不超过MAX_WORKERS_FILES * MAX_WORKERS_PER_FILE(两者之积)
#   使用filtered模式(仅上传尚未上传的产品)的情况下,仅MAX_WORKERS_FILES有效,
#   batch模式下,其决定将需要上传的数据(单个集合)用几线程上传
MAX_WORKERS_FILES = 2  # 同时上传的文件数(一般不超过7);
MAX_WORKERS_PER_FILE = 1  # 每份文件上传的线程数
TIME_OUT = 100  # 如果是批上传,可以考虑调大些,防止响应体过大时间不足导致报错
BATCH_SIZE = 10  # 每次上传的产品数量


# 上传模式列举(可供ide补全提示);相关含义可以参考文档


class UploadMode(Enum):
    """产品上传模式枚举

    Attributes:
        JUMP_IF_EXIST: 创建失败时跳过当前产品（默认模式）
        TRY_CREATE_ONLY: 仅尝试创建新产品，如果产品已存在则不更新
        UPDATE_IF_EXIST: 直接创建失败时尝试用PUT方法更新产品
        RESUME_FROM_DB: 从数据库恢复上传进度
        RESUME_FROM_LOG: 从日志文件恢复上传进度

    模式详细说明：
    1. JUMP_IF_EXIST (推荐默认)
       - 跳过已存在的商品
       - 比TRY_CREATE_ONLY有更好的性能表现
       - 适用场景：常规上传
    2. TRY_CREATE_ONLY
       - 仅创建新商品
       - 遇到SKU冲突时直接跳过
       - 适用场景：首次上传或确定无重复SKU时

    3. UPDATE_IF_EXIST (强制更新)
       - 自动更新已存在的商品
       - 适用场景：需要覆盖更新商品信息时

    4. RESUME_FROM_DB (断点续传)
       - 从WooCommerce数据库读取已上传记录
       - 优点：100%准确
       - 缺点：首次查询较慢

    5. RESUME_FROM_LOG (快速恢复)
       - 从本地日志文件恢复进度
       - 优点：恢复速度极快
       - 要求：必须使用此代码生成的日志文件,指定log日志文件路径
    """

    JUMP_IF_EXIST = "jump_if_exist"
    TRY_CREATE_ONLY = "try_create_only"
    UPDATE_IF_EXIST = "update_if_exist"
    RESUME_FROM_DATABASE = "resume_from_database"
    RESUME_FROM_LOG_FILE = "resume_from_log_file"


class FetchMode(Enum):
    """产品获取模式枚举

    Attributes:
        FROM_CACHE: 从缓存中获取产品
        FROM_DATABASE: 从数据库中恢复进度
        FROM_LOG_FILE: 从本地日志文件恢复进度

    """

    FROM_CACHE = "from_cache"
    FROM_DATABASE = "from_database"
    FROM_LOG_FILE = "from_log_file"


class ProgressTracker:
    """
    初始化MyClass类的实例。

    该构造函数初始化了一个名为progress_count的实例变量，用于跟踪进度计数。
    """

    def __init__(self):
        self.progress_count = 0
        self.success_count = 0
        self.fail_count = 0

    def update_progress(self, count_type="success"):
        """更新计数器(自增+1)"""

        # 始终为self.progress_count+1
        self.progress_count += 1

        if count_type == "success":
            self.success_count += 1
        elif count_type == "fail":
            self.fail_count += 1

        # print(f"Progress count: {self.progress_count}")

    def get_updated_progress_str(self, count_type="success"):
        """获取更新后的进度字符串,便于统一格式"""
        self.update_progress(count_type=count_type)
        return f"[{self.progress_count}({self.success_count} success, {self.fail_count} fail)]"


# pt = ProgressTracker()
# 默认选择的上传模式:
UPLOAD_MODE = UploadMode.TRY_CREATE_ONLY

# 日志文件路径,可作为存档,恢复上传断点🎈
TIME_STR = datetime.now().strftime("%Y%m%d-%H-%M-%S")
CSV_DIR = CSV_DIR.strip("/")
LOG_FILE_UPLOAD = f"{CSV_DIR}/log/upload-{domain}-{TIME_STR}.csv"
LOG_FILE_UPLOAD_BAK = f"C:/log/upload-{domain}.csv"
# LOG_FILE_UPLOAD_FAIL=f"{CSV_DIR}/log/upload_fail-{domain}-{time_str}.csv"


# 主推方案:获取指定目录下的csv文件列表
files_from_dir = os.listdir(CSV_DIR)
dir_csv_files = [os.path.join(CSV_DIR, f) for f in files_from_dir if f.endswith(".csv")]


# 备用方案1:自动生成文件名,如果文件名比较规范(可选)
# 比如range(1,7),将编号1,2,...,6(左闭右开整数区间)
# 指定要处理的文件列表
auto_csv_files = [os.path.join(CSV_DIR, f"p{i}.csv") for i in range(1, 7)]

# 备用方案2:手动指定文件列表配置(可选)
manual_csv_files = [
    "  ./p1.csv  ",
    "  C:/path/x.csv  ",
]

# 指定你的文件列表(从上述三种方案中选择一种,推荐使用方案1)

files = dir_csv_files

##
# -----------------------------------------------------------------------------
# 日志消息队列
log_queue = queue.Queue()
# 分类缓存锁categories_cache_lock
cat_lock = threading.Lock()
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
##

# 定义 WooCommerce API 端点常量字符串
# 根据api的规范,rest api(get/post/put/delete)中的路径字符串被形参被称为"endpoint"
CATEGORIES_ENDPOINT = "products/categories"
CATEGORIES_TOTALS_ENDPOINT = "reports/categories/totals"


PRODUCTS_ENDPOINT = "products"
PRODUCTS_TOTALS_ENDPOINT = "reports/products/totals"
PRODUCT_BATCH_ENDPOINT = "products/batch"

SYSTEM_STATUS_ENDPOINT = "system_status"

# -----------------------------------------------------------------------------------

##


def download_img_to_local(img_url, product_sku):
    """
    下载远程图片并保存到本地
    :param url: 图片的URL
    :param product_sku: 产品的SKU，用于命名本地图片
    :return: 本地图片路径
    """
    local_filename = f"{product_sku}.jpg"
    with requests.get(img_url, stream=True, timeout=10) as r:
        r.raise_for_status()
        with open(local_filename, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)
    return local_filename


def split_list(lst, n):
    """将可迭代容器(例如列表)平均分为n份,返回分割后的列表
    尽可能的平均分配比较好,如果前n-1份数量相同,且
    将余数元素都放到最后一份可能会导致最后一份元素过多(最坏情况下是平均份的近两倍)
    方案1:推荐
    设你要均分为n份,每份的基本大小为size=len(lst)//n,余数为r=len(lst)%n,且一定有(r<n)
    那么前r份每份含有size+1个元素，后n-r份每份含有size个元素
    此方案可以保证,任意两份所分得的元素数量差不会超过1
    如果n大于lst的元素数量,那么前len(lst)份每份含有1个元素,后n-len(lst)份每份含有0个元素(空列表)

    方案2:不推荐
    如果容器中元素长度为L=len(lst),k为L/n的余数,则将最后k个元素归入最后一份

    Parameters
    ----------
    lst : list
        需要被分割的容器列表
    n : int
        需要被分割的份数(平均)

    Returns
    -------
    list
        分割后的列表的列表
    Examples
    --------
    split_list(list(range(1,11)), 4)


    """
    result = []
    size, r = divmod(len(lst), n)
    print(f"size: {size}, r: {r}")

    size_r = size + 1
    for i in range(r):
        start = i * size_r
        end = (i + 1) * size_r
        result.append(lst[start:end])
    start = (size + 1) * r

    for i in range(r, n):
        end = start + size
        result.append(lst[start:end])
        start = end

    return result


LOG_HEADER = ["SKU", "Name", "id", "Status", "message", "datetime"]


def log_worker(log_file=LOG_FILE_UPLOAD):
    """后台日志记录线程
    利用循环不断尝试从全局日志队列中获取日志条目,然后写入到日志文件中
    log_header 参考:["Timestamp", "RecordID", "Status", "Details", "ProcessingTime"]

    """
    print(f"Log worker started.logs will be written to: {log_file}🎈")
    while True:
        log_entry = log_queue.get()
        # print(f"Log worker got log entry: {log_entry}")
        if log_entry is None:  # 终止信号
            break
        try:
            # 检查路径(目录)存在,若不存在则创建
            log_dir = os.path.dirname(log_file)
            if not os.path.exists(log_dir):
                os.makedirs(log_dir)
            # 写入日志文件
            with open(log_file, "a", newline="", encoding="utf-8") as f:

                writer = csv.writer(f)
                # 如果文件为空，写入标题行
                if f.tell() == 0:
                    writer.writerow(LOG_HEADER)
                writer.writerow(log_entry)
        except Exception as e:
            print(f"Error:Log write failed: {e}")
        finally:
            log_queue.task_done()


def log_upload(sku, name, product_id, status, msg=""):
    """将日志加入到日志消息队列中
    表头结构由常量LOG_HEADER定义,元素顺序与LOG_HEADER一致,或者使用关键字参数传参
    """
    log_entry = [
        sku,
        name,
        product_id,
        status,
        msg,
        datetime.now().isoformat(),
    ]
    log_queue.put(log_entry)
    # print(f"Log preview:{log_entry}")
    return log_entry


def cleanup_log_thread(q_thread):
    """清理函数，等待队列处理完成并停止工作线程"""
    log_queue.join()  # 等待所有日志项处理完成
    log_queue.put(None)  # 发送终止信号
    q_thread.join()  # 等待线程结束
    print("log_thread(daemon) end.")


##


class WC(API):
    """WooCommerce 产品上传器
    query_string_auth=True
    # Force Basic Authentication as query string true and using under HTTPS Authentication over HTTP
    """

    def __init__(
        self,
        api_url=url,
        api_consumer_key=consumer_key,
        api_consumer_secret=consumer_secret,
        timeout=TIME_OUT,
        version="wc/v3",
        wp_api=True,
        query_string_auth=False,  # 使用查询字符串认证，而不是基本认证
    ):
        """WC生成器
        此类型设置了两个成员变量,wcapi和existing_products,分别表示WooCommerce API客户端和缓存的现有产品信息
        如果不考虑重复,可以不使用existing_products缓存,直接使用API上传产品

        Parameters
        ----------
        url : str, optional
            WooCommerce 站点 URL(可以是本地站点http链接,也可以是https链接), by default "http..."
        consumer_key : str, optional
            WooCommerce 站点的 Consumer Key, by default "ck_..."
        consumer_secret : str, optional
            WooCommerce 站点的 Consumer Secret, by default "cs_..."
        version : str, optional
            woo api版本目前使用v3版本, by default "wc/v3"
        """

        super().__init__(
            url=api_url,
            consumer_key=api_consumer_key,
            consumer_secret=api_consumer_secret,
            version=version,
            wp_api=wp_api,
            query_string_auth=query_string_auth,
            timeout=timeout,
        )

        # 初始化连接池
        self._init_session()
        # 缓存成员变量

        # 已存在的具有sku的产品信息，键为 SKU(使用字典存储,查询性能极高)
        self.existing_products_sku = {}
        # 考虑到一个产品一定有(非空)的字段是id,这里要收集id,取值可以是name,sku 等
        self.existing_products = {}
        # 缓存查询的页面,可以自行转换到existing_products中
        self.product_pages = []
        # 缓存已存在的分类信息，键为分类名称
        self.existing_categories = {}
        # 记录上传失败的产品信息(比如超时)
        self.upload_failed_products = []

        # 缓存从本地文件读取到的产品数据(列表元素可以是每一行csv数据构成的字典)
        self.product_from_file = []
        # 尚未上传的产品数据(列表元素可以是每一行csv数据构成的字典)
        self.products_need_to_upload = []
        # 上传进度跟踪器
        self.progress_tracker = ProgressTracker()

    def _init_session(self):
        """初始化带连接池的session"""
        self.session = requests.Session()

        # 配置重试策略
        retry_strategy = Retry(
            total=3, backoff_factor=1, status_forcelist=[408, 429, 500, 502, 503, 504]
        )

        # 配置连接池
        adapter = HTTPAdapter(
            pool_connections=20,
            pool_maxsize=20,
            pool_block=False,
            max_retries=retry_strategy,
        )

        # 为HTTP和HTTPS挂载适配器
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

    def _request(self, method, endpoint, data, params=None, **kwargs):
        """重写请求方法以使用我们的连接池session"""
        # 确保使用我们自定义的session
        kwargs["session"] = self.session

        # 调用父类的_request方法
        return super().__request(
            method=method, endpoint=endpoint, data=data, params=params, **kwargs
        )

    def get_system_status(self):
        """获取wordPress站点的系统状态/信息"""
        response = self.get(SYSTEM_STATUS_ENDPOINT)
        return response

    def dump_existing_products_sku_pkl(
        self, mode="existing_products_sku", path=f"{domain}-existing_products_sku.pkl"
    ):
        """导出现有产品的对象(pickle文件)
        根据团队的业务方便,这里仅导出有sku的products
        业务变更可以把更完整的existing_products也导出来,或者代替掉
        Parameters
        ----------
        mode : str, optional
            导出模式
            "existing_products_sku"导出有sku的products
            "existing_products"导出所有products
            by default "existing_products_sku"
        path : str, optional

            pkl文件的保存路径, by default f"{domain}-existing_products.pkl"
        """
        products_to_export = {}
        if mode == "existing_products_sku":

            products_to_export = self.existing_products_sku
        elif mode == "existing_products":
            products_to_export = self.existing_products
        else:
            print(f"export mode {mode} not supported!")
        with open(path, "wb") as f:
            pickle.dump(products_to_export, f)

    def load_existing_products_sku_pkl(
        self, mode="existing_products_sku", path=f"{domain}-existing_products.pkl"
    ):
        """导入现有产品的对象(pickle文件)
        :param path: pickle文件路径, by default f"{domain}-existing_products.pkl"
        :param mode: 导入模式,默认为"existing_products_sku",表示导入有sku的products,
            如果选择"existing_products",则导入所有products, by default "existing_products_sku"
        :return: 导入的products对象
        """
        products_to_import = {}

        with open(path, "rb") as f:
            products_to_import = self.existing_products = pickle.load(f)
            if mode == "existing_products_sku":
                self.existing_products_sku = products_to_import
            elif mode == "existing_products":
                self.existing_products = products_to_import
            else:
                print(f"import mode {mode} not supported!")
        return products_to_import

    def get_category(self, category_name, use_lock=True):
        """
        根据指定的分类名字,检查是否已经存在此分类,如果已存在,获取分类的 ID，如果分类不存在则创建该分类。
        此方法每次仅处理一个分类名字
        对于从csv中读取的分类值,可以用get_categories方法解析并处理多个分类值(也兼容单个分类名字)
        ---
        此方法使用双重检查锁定模式,避免多线程同时创建同一分类并尽可能降低不必要阻塞的出现


        :param category_name: 分类名称
        :param no_lock: 是否使用锁定模式,默认不使用,如果使用,则可能导致多线程同时创建同一分类,
            导致资源浪费,在你确定没有分类或者无所谓重建的情况下可以设置True
        :return: 分类 ID

        查询分类是否存在(目前api正式开放的参数只有id,slug或许也行,但是对于字符复杂的分类,我们利用python将难以转换为slug)
        可以考虑先获取所有分类构成的可迭代对象,然后再通过查询名字获取id
        response = self.wcapi.get(
            categories_endpoint,
            params={
                # "name": category_name
                # "id": category_id
                "slug": category_name.lower()
            }
        )
        """
        if category_name in self.existing_categories:
            return self.existing_categories[category_name]

        # 如果存在,则返回ID
        cat_res = self.existing_categories.get(category_name)
        if cat_res:
            print(f"category: {category_name} exist! The id is {cat_res}")
            return cat_res
        else:
            # 如果分类不存在，则创建
            if use_lock:
                with cat_lock:
                    # 双重检查锁定模式(防止其他进程已经创建好了同一分类),这里重复创建就会出错且浪费资源
                    self._create_category(category_name)
            else:
                self._create_category(category_name)

    def _create_category(self, category_name):
        if category_name in self.existing_categories:
            return self.existing_categories[category_name]
        # 加锁,避免多线程同时创建同一分类
        print(f"Creating new category: {category_name}")
        # 创建新分类(只有分类名字)
        response = self.post(CATEGORIES_ENDPOINT, {"name": category_name})
        if response.ok:
            category_id = response.json()["id"]
            self.existing_categories[category_name] = category_id
            print("\tOK:Create new category")
            return category_id
        else:
            print(
                f"\tFailed:Create new category \
                    {category_name}: {self.get_code_message(response)}"
            )
        return None

    def get_categories(self, categories_str, mandatory=True):
        """
        处理产品分类字符串，返回分类 ID 列表。
        产品将被添加到分类ID列表中所指的分类

        这里允许产品有多个分类,分类之间用逗号分割;
        如果分类是单一的,也可以处理,但是注意逗号被作为分隔符
        或者不使用此方法,直接用get_or_create_category 简化处理

        :param categories_str: 分类字符串（多个分类以逗号分隔）。
        :param mandatory: 是否必须存在分类,默认为True,如果为False,则允许返回空列表
        :return: 包含分类 ID 的列表。
        """
        category_ids = []
        if not categories_str:
            if mandatory:
                raise ValueError("Product must have at least one category.")
        # 如果你的产品的所属分类字符串按逗号分隔,那么通过split方法解析拆分处理
        # 但是目前我们的业务就是单分类字符串,可以考虑不需要split
        category_names = [cat.strip() for cat in categories_str.split(",")]
        category_ids = []

        for category_name in category_names:
            category_id = self.get_category(category_name)
            if category_id:
                category_ids.append({"id": category_id})

        return category_ids

    def get_all_categories_from_file(self, csv_files):
        """从文件列表中读取分类信息,得到分类集合

        Parameters
        ----------
        csv_files : list[str]
            woocommerce csv文件列表
        """
        if isinstance(csv_files, str):
            csv_files = [csv_files]
        categories = set()
        for file in csv_files:
            with open(file, mode="r", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    # set.add(categories, row["Categories"])
                    categories.add(row["Categories"])
        return categories

    def get_worker_number(self, tasks, max_workers):
        """返回需要创建的worker数(最大线程数)
        比较任务总数和最大线程数中较小的一个
        线程数至少为1

        Parameters
        ----------
        tasks : int
            任务总数
        max_workers : int
            最大线程数
        """
        return max(min(tasks, max_workers), 1)

    def prepare_categories(self, csv_files, max_workers=50):
        """从文件创建分类

        Parameters
        ----------
        csv_files : str
            woocommerce csv文件列表
        max_workers : int, optional
            并发线程数
        """
        # 准备分类前要先检查站点是否存在某些分类,防止冲突发生
        self.fetch_existing_categories(mode=FetchMode.FROM_DATABASE)

        categories = self.get_all_categories_from_file(csv_files)

        workers = self.get_worker_number(len(categories), max_workers)
        print(f"with {workers} workers(threads) create categories...")

        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [
                executor.submit(self.get_category, category) for category in categories
            ]
            for future in as_completed(futures):
                future.result()

        # for category in categories:
        #     self.get_categories(category)

    def delete_categories(self, category_id="", category_name="", mode="specified"):
        """删除分类
        支持删除指定分类或全部分类
        如果要删除指定分类,可以利用循环调用此方法间接实现
        如果要删除全部分类,可以调用此方法,mode参数设置为"all"

        Parameters
        ----------
        category_id : str, optional
            分类id, by default ""
        mode : str, optional
            删除模式, "specified"表示删除指定分类,
              "all"表示删除所有分类, by default "specified"

        Returns
        -------
        Response List
            返回被删除的分类的响应
        """
        res = []
        if mode == "specified":
            if category_name:
                # 先获取分类id
                category_id = self.existing_categories.get(category_name)
                if not category_id:
                    print(f"category: {category_name} not exist!")
                    return res
                else:
                    print(f"Deleting category: {category_name} (ID: {category_id})")
            # 同一得到分类id后,根据id删除分类
            response = self.delete(
                f"{CATEGORIES_ENDPOINT}/{category_id}", params={"force": True}
            )
            res.append(response)

        elif mode == "all":
            response = self.get(CATEGORIES_ENDPOINT)
            if response.ok:
                for category in response.json():
                    response = self.delete_categories(
                        category_id=category["id"], mode="specified"
                    )
                    res.append(response)

            else:
                print(f"Failed to fetch categories: {self.get_code_message(response)}")
        else:
            print(f"Invalid mode: {mode}")
        return res

    def fetch_existing_products(
        self,
        page=1,
        page_size=100,
        max_workers=10,
        fetch_mode=FetchMode.FROM_CACHE,
        log_file="",
    ):
        """获取所有现有产品的 SKU 和 ID

        Parameters
        ----------
        max_workers : int, optional
            最大并发线程数, by default 10
            设置过大可能会导致ConnectionError
        mode : str, optional

            1.FetchMode.FROM_CACHE,则从缓存中获取(速度快,但是未必是最新情况,不一定包含全部产品);

            2.FetchMode.FROM_DATABASE,则调用api查询数据库获取(速度慢,尽量不用), by default FetchMode.FROM_CACHE

            3.FetchMode.FROM_LOG_FILE,从日志中恢复商品上传进度(读档),速度最快,优先考虑
        log_file : str, optional
            日志文件路径, by default ""


        示例输出:
        {'SK0003245-U': 122578, 'SK0003244-U': 122576, 'SK0003243-U': 122574, 'SK0003242-U': 122572}
        """
        print(f"Fetch {{Mode: {fetch_mode}}}")
        # 循环查询所有产品,每次获取一定数量的产品(每次最多100个产品)
        if fetch_mode == FetchMode.FROM_CACHE:
            if not self.existing_products_sku:
                print(
                    "Fetch Mode Changed!:Fetching products from database...\
                            (There is no cached products.)"
                )
                self.fetch_existing_products(
                    page=1,
                    page_size=page_size,
                    max_workers=max_workers,
                    fetch_mode=FetchMode.FROM_DATABASE,
                )
            else:
                print("Using existing products cache.")

        elif fetch_mode == FetchMode.FROM_DATABASE:

            pages = self.get_product_pages_count()
            # 选择一个合理的线程数(超过页数就没有必要了,但是也不能小于1)
            workers = self.get_worker_number(pages, max_workers)

            print(f"Fetching products with {workers} workers...")

            with ThreadPoolExecutor(max_workers=workers) as executor:
                futures = []
                for page in range(1, pages + 1):
                    futures.append(
                        executor.submit(self.get_product_page, page, page_size)
                    )
                for future in as_completed(futures):
                    response = future.result()
                    if not response.ok:
                        print(
                            f"Error fetching products: {self.get_code_message(response)}"
                        )
                        break
                    print(f"Parsing fetched products page {page}...")
                    products = response.json()
                    for product in products:
                        product_id = product.get("id")
                        name = product.get("name")
                        sku = product.get("sku")
                        if sku:
                            self.existing_products_sku[sku] = product_id
                        self.existing_products[product_id] = [name, sku]
                        print(
                            f"OK:Get product:{{id:{product_id};name:{name};sku:[{sku}]}}"
                        )
        elif fetch_mode == FetchMode.FROM_LOG_FILE:
            self.load_upload_log_data(log_file)
        else:
            print(f"Invalid mode: {fetch_mode}")
        # 返回值还可以选择:self.existing_products_sku,self.existing_products
        # 或者干脆不返回值,后面要用直接访问两个对象的缓存容器属性
        return self.existing_products

    def get_categories_page(self, page=1, page_size=100):
        """获取第page页的分类"""
        print(f"Fetching categories (page:{page})...")
        response = self.get(
            CATEGORIES_ENDPOINT, params={"per_page": page_size, "page": page}
        )
        if response.ok:
            print(f"OK:Get categories page {page}...")
        else:
            print(
                f"Failed:Fetch categories page {page}: {self.get_code_message(response)}"
            )
        return response

    def fetch_existing_categories(
        self, page=1, page_size=100, max_workers=5, mode=FetchMode.FROM_CACHE
    ):
        """获取所有现有分类的名称和ID

        内部有一个细节,是编码实体字符

        :param mode: 获取模式,默认为FetchMode.FROM_CACHE,表示从缓存中获取,
        如果选择FetchMode.FROM_DATABASE,则调用API从数据库查询获取, by default FetchMode.FROM_CACHE
        :param max_workers: 最大线程数, by default 5(如果设置为0,表示不使用多线程模式(逐页获取))

        :return: 包含分类名称和ID的字典

        """
        if mode == FetchMode.FROM_CACHE:
            if not self.existing_categories:
                self.fetch_existing_categories(mode=FetchMode.FROM_DATABASE)
            # return self.existing_categories
        elif mode == FetchMode.FROM_DATABASE:
            categories_count = self.get_categories_page_count()
            workers = self.get_worker_number(categories_count, max_workers=max_workers)
            # 分类的页数统计
            page = 1
            # 多线程方案:获取分类
            print(f"Fetching categories with {workers} workers...")
            with ThreadPoolExecutor(max_workers=workers) as executor:
                futures = [
                    executor.submit(self.get_categories_page, page, page_size)
                    for page in range(1, categories_count + 1)
                ]
                for future in as_completed(futures):
                    response = future.result()
                    # categories = response.json()
                    self.cache_categories_names(response)
            # 普通方案: 逐页获取分类
            if max_workers == 0:
                while True:

                    response = self.get_categories_page(page=page, page_size=page_size)
                    if not response.ok:
                        # api调用失败退出循环
                        print(
                            f"Failed to fetch categories: {self.get_code_message(response)}"
                        )
                        break
                    # 返回分类为空时退出循环
                    categories = response.json()
                    if not categories:
                        break

                    self.cache_categories_names(response)
                    page += 1
        return self.existing_categories

    def cache_categories_names(self, categories_page_response):
        """缓存分类名称和ID
        处理分类名称编码
        """
        if not categories_page_response.ok:
            print(
                f"Failed to fetch categories: {self.get_code_message(categories_page_response)}"
            )

            # return None
        else:
            categories = categories_page_response.json()
            for category in categories:
                # 分类名称解码为unicode(部分字符会被编码存储,解码后方便比较)
                category_name_encoded = category["name"]
                category_name = html.unescape(category_name_encoded)
                self.existing_categories[category_name] = category["id"]

    def get_categories_count(self):
        """获取产品分类数量"""
        # 获取产品分类的第一页(包含总数信息)
        response = self.get(CATEGORIES_ENDPOINT, params={"per_page": 1})
        # 从 response.headers 中读取总数（total number of categories）
        total_categories = response.headers.get("X-WP-Total")
        if total_categories:
            total_categories = int(total_categories)
        else:
            total_categories = -1
        return total_categories

    def get_categories_page_count(self, page_size=100):
        """获取产品分类页数"""
        total_categories = self.get_categories_count()
        pages = ceil(total_categories / page_size)
        return pages

    def get_product_page(self, page=1, page_size=100):
        """获取第page页的产品

        主要配合fetch_existing_products方法使用

        Parameters
        ----------
        page : int, optional
            页码, by default 1
        page_size : int, optional
            每页产品数量, by default 100
        return
            返回产品列表的response对象,调用返回值的.json方法获得列表数据
        """
        # res = None
        print(f"Fetching products page {page}...")
        response = self.get(
            PRODUCTS_ENDPOINT, params={"per_page": page_size, "page": page}
        )
        if response.ok:
            print(f"OK:Get products page {page}...")
            # self.product_pages.append(response)
            # print(f"current products:{len(self.existing_products)}") #需要加锁才能准确读取
        else:
            print(
                f"Failed:Fetch products page {page}: {self.get_code_message(response)}"
            )
        return response

    def get_product_count_report(self):
        """获取产品统计报告
        统计报告包含了产品总数,不同类型产品的数量,不同状态的产品数量等
        """
        res = self.get(PRODUCTS_TOTALS_ENDPOINT)
        if not res.ok:
            print(f"Failed to fetch products count: {self.get_code_message(res)}")
        return res

    def get_product_count(self, product_type="simple"):
        """获取产品总数

        :param product_type: 产品类型,默认为"simple",可以指定"all"获取所有产品类型,也可以指定具体类型,比如"variable"获取变量产品类型
        :return:
            如果是具体类型,则返回产品总数
            否则返回全部类型的统计报告response对象,调用返回值的.json方法获得列表数据

        输出示例:(一般我们看的是simple类型的产品)
        [{'slug': 'external', 'name': 'Prodotto Esterno/Affiliate', 'total': 0},
        {'slug': 'grouped', 'name': 'Grouped product', 'total': 0},
        {'slug': 'simple', 'name': 'Prodotto semplice', 'total': 143},
        {'slug': 'variable', 'name': 'Prodotto variabile', 'total': 0}]

        返回值是一个统计报告列表的response
        通过res[2]["total"]hun获取simple类型的产品总数
        或者通过指定product_type="simple"获取指定类型的产品总数
        """

        print("Try get woocommerce prouducts count...")

        res = self.get_product_count_report()
        report = res.json()
        totoal = -1
        if res.ok:
            for d in report:
                if d.get("slug") == product_type:
                    totoal = d.get("total")
                    break
                    # print(totoal)
        else:
            print(f"Failed to fetch products count: {self.get_code_message(res)}")
        print(f"Total product count: {totoal}")
        return totoal

    def get_product_pages_count(self, page_size=100):
        """获取所有产品的页数"""
        pages = ceil(self.get_product_count(product_type="simple") / page_size)
        return pages

    def load_upload_log_data(self, log_file):
        """从日志文件中恢复商品上传进度(读档)
        日志文件被设计为csv格式,主要包含SKU,Name,status等列
        主要筛选出sku,name这两列,同时仅筛选上传成功的记录(OK)

        Note:
        如果发现导入的数据量(行数)和log文件中的记录数不一致(OK行的行数)不一致,可能是由于调试期间产生的具有重复sku的记录,字典(key)会自动去重(顶替掉)
        """
        print(f"Loading upload log data from {log_file}...")
        with open(log_file, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                sku = row.get("SKU")
                name = row.get("Name")
                status = row.get("Status")
                product_id = row.get("id")
                # 从日志中读入操作(上传/更新)成功的记录
                if status == "OK":
                    self.existing_products_sku[sku] = product_id
                    self.existing_products[product_id] = [name, sku]
                # print(f"loading product: {sku};\tid:{product_id}; \tStatus: {status}")

    def get_custom_attribute(self, product_data, name="mycustom"):
        """获取(构造)自定属性数据

        Parameters
        ----------
        product_data : dict
            一条产品数据(一般来自csv的一条数据)
        name : str, optional
            自定义的产品属性名(对于DF团队魔改的情况下,不是很重要), by default "mycustom"

        Returns
        -------
        dcit
            构造的符合woocommerce api要求的自定义属性数据
        """
        # 创建自定义属性的函数
        name = product_data.get("Attribute 1 name")
        value = product_data.get("Attribute 1 value(s)", "")
        data = {
            "name": name,
            "slug": name,
            "visible": False,
            "options": [value],
        }
        # "type": "text",  # 使用文本类型存储完整值
        # "order_by": "menu_order",
        # "has_archives": False,
        if value:
            print(f"Creating custom attribute: {name}={value}")
        # 返回属性数据(列表)
        return [data]

    def process_tags(self, tags_str):
        """获取产品标签列表
        团队目前只有一个标签

        Parameters
        ----------
        tags_str : str
            csv中的数据行中的标签字段字符串
        """
        if tags_str:
            tags_list = tags_str.split(",")  # 根据逗号分隔标签
            tags = [{"name": tag.strip()} for tag in tags_list]
            return tags
        else:
            return []

    def get_product_data(self, product_data) -> dict:
        """根据产品数据构造产品对象"""
        data = {}

        sku = product_data["SKU"]
        name = product_data["Name"]

        regular_price = product_data["Regular price"]
        sale_price = product_data["Sale price"]

        description = product_data["Description"]

        tags_str = product_data["Tags"]
        tags = self.process_tags(tags_str)

        # 分类(目前的api需要得到对应的id,比较特殊)
        # 团队业务要求分类必须要有
        categories_str = product_data["Categories"]
        categories = self.get_categories(categories_str)

        # print(f"categories: {categories}")

        img_url = product_data["Images"]

        # 属性值要小心处理
        attributes = self.get_custom_attribute(product_data)

        # attributes = product_data.get("Attributes", "")
        # attributes = self.parse_attributes(product_data)

        data = {
            "sku": sku,
            "type": "simple",
            "name": name,
            "regular_price": regular_price,
            "sale_price": sale_price,
            "description": description,
            "categories": categories,
            "Tags": tags,
            "images": [{"src": img_url}],
            "attributes": attributes,
        }
        if not data:
            raise ValueError("Product data is invalid.")
        return data

    def create_product(self, product_data):
        """创建新产品

        这里的product_data将传递给get_product_data构造产品字典,包含了必要的产品的信息
        """
        data = self.get_product_data(product_data)
        response = self.post("products", data)
        # try:
        # except TimeoutError:
        #     print(f"Timeout when creating product: {data.get('name')}")

        name = data["name"]
        sku = data["sku"]
        res_json = response.json()
        product_id = res_json.get("id")
        if response.ok:

            print(
                f"\tOK({self.progress_tracker.get_updated_progress_str()}):\
                    Product created:{{ Name:{name};sku:[{sku}] }}"
            )

            self.existing_products_sku[sku] = product_id
            self.existing_products[product_id] = [name, sku]
        else:
            print(f"Failed to create product: {self.get_code_message(response)}")

        return response

        # if sku not in self.existing_products_sku:
        #     # 产品上不存在,则上传新产品
        #     print(f"Uploading product: {name}")
        #     # print(f"\tCreating new product : {name}")

        #     # post创建产品🎈

    def update_product(self, product_data, update_mode="update_db_only"):
        """更新现有产品

        :param product_data: 产品数据字典
        :param update_mode: 更新模式

            - 默认为"update_db_only",表示仅更新数据库中的产品信息,不更新WC对象缓存;
            - 如果模式为"refresh_product_cache",则还更新对应的缓存(self.existing_products)
        """
        data = self.get_product_data(product_data)
        sku = data["sku"]
        name = data["name"]
        if update_mode == "refresh_product_cache":
            # 获取/更新已有产品缓存
            self.fetch_existing_products()
        # id = self.existing_products_sku[sku]
        products = self.get_product(sku=sku)
        if products:
            product_id = products[0]["id"]
        else:
            raise ValueError("The id of the updating product not found.")

        response = self.put(f"{PRODUCTS_ENDPOINT}/{product_id}", data)

        if response.ok:
            print(f"\tOK:Product updated: {{Name:{name};SKU:{{{sku}}}}}")
        else:
            print(f"\tFailed to update product: {self.get_code_message(response)}")
        return response

    def get_batch_data(self, product_data_batch):
        """获取批量操作数据
        目前仅提供创建产品的操作所需要的数据格式
        后续有需要的话可以提供其他格式(删除/更新)
        """
        products_to_create = [
            self.get_product_data(product_data) for product_data in product_data_batch
        ]
        data = {
            "create": products_to_create,
            "update": [],
            "delete": [],
        }
        return data

        # for product_data in batch_data:

    def batch_update_products(self, batch, task_id=-1):
        """批量操作产品
        更新含义为变更,包括创建/更新/删除
        一个请求体中可以包含三种操作(对应于三个数组)
        api限制最大batch为100

        目前仅批量创建产品,后续可以扩展到批量更新/删除

        详情查看api:https://woocommerce.github.io/woocommerce-rest-api-docs/#batch-update-products
        https://woocommerce.github.io/woocommerce-rest-api-docs/#batch-update-products

        Parameters
        ----------
        batch : dict
            批量操作的字典,格式参考文档
        task_id : int, optional
            任务id,默认为-1(-1表示没有设置)
        Returns
        -------
        responses : Response
            批量操作的响应对象
            batch中包含的每一种操作的各个名称各有一个列表
            Response.json()和batch结构相对应
        """
        print(f"batch update products task_id: {task_id} ...")
        batch_dict = self.get_batch_data(batch)
        response = Response()
        response.status_code = 504  # 默认值(认为服务器错误)
        try:
            response = self.post(PRODUCT_BATCH_ENDPOINT, batch_dict)
            # 这里获取json的过程中可能会出错,需要捕获异常或放在try中
            res_json = self.get_response_json(response)
            # 检查响应体中的信息
            # 将每个产品的上传情况按照约定的日志格式添加到日志文件中
            # 目前仅处理create操作
            res_creation_lst = res_json.get("create", [])
            # to verification
            for idx, info in enumerate(res_creation_lst):
                sku = batch[idx]["SKU"]
                name = batch[idx]["Name"]
                product_id = info.get("id")
                if product_id:
                    # 对于批上传模式,不能像单上传模式那样直接根据响应response.ok判断是否上传成功,需要检查响应体中的信息,比如判断id字段是否存在
                    print(
                        f"OK{self.progress_tracker.get_updated_progress_str()}:\
                            create product:{{Name:{info.get('name')};SKU:[{info.get('sku')}]}}"
                    )
                    if not info.get("price"):
                        print(
                            f"Warning: product:{{Name:{info.get('name')};SKU:[{info.get('sku')}]}} has no price."
                        )
                        self.update_product(
                            batch[idx], update_mode="refresh_product_cache"
                        )
                    # 添加到已有产品缓存中
                    self.existing_products_sku[sku] = product_id
                    self.existing_products[product_id] = [name, sku]
                    # 写入日志
                    log_upload(
                        sku,
                        name,
                        product_id=product_id,
                        status="OK",
                        msg="Product created.",
                    )
                else:
                    print(f"Failed: create product: {info.get('error')}")
                    log_upload(
                        sku,
                        name,
                        product_id=None,
                        status="Failed",
                        msg=info.get("error", ""),
                    )
        except Exception as e:
            print(f"Exception:Failed to batch update products🧨: {e}")
            # 其他操作...
        return response

    def get_response_json(self, response):
        """安全地尝试解析 JSON"""
        try:
            # 打印状态码和文本内容，辅助调试
            print("Status code:", response.status_code)
            res_json = response.json()
        except json.JSONDecodeError:
            print(
                "Failed to parse JSON. Response might be empty or not in JSON format."
            )
        return res_json

    def report_error_of_upload(self, name, sku, exception_message):
        """打印上传失败的信息"""
        print(exception_message)
        print(f"Failed to create product:{{Name:{name};SKU:[{sku}];}}")

    def get_code_message(self, response, return_str=False):
        """读取response对象中的code和message
        直接从response.text读取的值可能包含\\u编码,不便于阅读
        通过调用json()方法可以获得人类可读的unicode字符
        """
        res_json = response.json()
        code = res_json.get("code")
        msg = res_json.get("message")
        if return_str:
            return f"{code}:{msg}"
        return msg, code

    def upload_product(
        self,
        product_data,
        upload_mode=UPLOAD_MODE,
    ) -> Response:
        """上传产品
        这里处理的是单个产品的上传,调用try_create_product来上传
        其他批上传另见其他相关函数

        :param product_data: 产品数据字典
        :param upload_mode: 上传模式,使用UploadMode的枚举值



        """

        # 当前上传的产品的基本信息
        sku = product_data["SKU"]
        name = product_data["Name"]
        # categories_str = product_data["Categories"]
        # print(f"processing product:{sku} {name}")
        res = Response()
        if upload_mode != "update_if_exist":
            # 上传失败时不尝试更新产品
            if self.existing_products_sku.get(product_data["SKU"]):
                # 如果已经存在该产品,则跳过

                print(
                    f"Jump({self.progress_tracker.get_updated_progress_str()}):\
                        Product already exists: {{SKU:[{sku}]}}"
                )
                product_id = self.existing_products_sku.get(sku)
                res.status_code = 208
                # 把跳过的情况(说明站点已经存在该产品,予以跳过)
                # 将跳过的产品写入日志(采用日志队列写入可能会造成效率问题,比如堵塞)
                log_upload(
                    sku=sku,
                    name=name,
                    product_id=product_id,
                    status="OK",
                    msg="Jump:Product already exist.",
                )
                # return res
            else:
                # 已上传产品的缓存中产品不存在该产品,尝试创建产品(注意异常处理)
                # print("🎈try create/upload product")
                self.try_create_product(product_data, upload_mode=upload_mode)
        elif upload_mode == "update_if_exist":
            # 直接尝试创建产品,不管是否已经有相同sku的产品存在,没有的话更新已有产品
            self.try_create_product(product_data, upload_mode=upload_mode)
        # else:
        #     print(f"invalid upload_mode: {upload_mode}")
        return res

    def try_create_product(self, product_data, upload_mode=UPLOAD_MODE):
        """尝试创建产品
        对create_product方法进行了封装,增加了异常处理,并增加了上传失败的产品记录
        """
        sku = product_data["SKU"]
        name = product_data["Name"]
        try:
            res = self.create_product(product_data)
            # 数据库被污染或者缓存不准确的情况下，可以选择以更新的方式创建产品
            if upload_mode == "update_if_exist":
                # 产品存在时,res将会返回错误代码,尝试检查错误代码,如果有则尝试更新产品
                if not res.ok:
                    print(f"Update:Product:{{Name:{name};SKU:[{sku}]}}")
                    # 更新产品
                    res = self.update_product(product_data)
            # 写入日志文件(针对上传/更新成功的产品)
            # if res.ok:
        except Exception as e:
            self.report_error_of_upload(
                name, sku, f"Exception (upload/update error🧨): {e}"
            )
            # logging.error(f"Failed to create product: {name} (SKU: {sku}). Error: {e}")
            log_upload(sku, name, product_id=None, status="Failed", msg=str(e))
        else:
            # message=res.text
            # message = res_json.get("message")
            msg = str(self.get_code_message(res))

            if res.ok:
                # 上传成功,写入日志文件
                product_id = res.json().get("id")
                log_upload(
                    sku,
                    name,
                    product_id=product_id,
                    status="OK",
                    msg=msg,
                )
            else:
                # 上传失败,写入日志文件
                log_upload(sku, name, product_id=None, status="Failed", msg=msg)
                # self.upload_failed_products.append((name, sku))

    def get_product(
        self,
        name=None,
        sku=None,
        product_id=None,
        category=None,
    ):
        """获取指定产品的信息

            woo api中可用的参数不少,这里仅接入最常用的几种情况,详细列表参考文档
            list-all-products:
            https://woocommerce.github.io/woocommerce-rest-api-docs/?python#list-all-products
            假设k是合法参数名,而v是对应的预期值,则WC实例(设为wc)的调用方法为
            wc.get(PRODUCTS_ENDPOINT,params={"k":v})

            针对于查找指定id的产品,采用另一个专用api
            retrieve-a-product:
            https://woocommerce.github.io/woocommerce-rest-api-docs/?python#retrieve-a-product

        Parameters
        ----------
        product_name : str, optional
            产品名称, by default None
        sku : str, optional
            产品sku, by default None
        id : str, optional
            产品id, by default None
        category : str, optional
            产品分类,内部会尝试获取id,然后调用api查询, by default None
        Return
        -------
        list[dict]
            包含产品信息的列表,如果没有找到则返回空列表
        """
        res = []
        if name:
            # 利用search参数搜索产品(返回列表)
            res = self.get(PRODUCTS_ENDPOINT, params={"search": name})
        elif sku:
            # 根据sku获取产品信息
            res = self.get(PRODUCTS_ENDPOINT, params={"sku": sku})
        elif category:
            cat_id = self.fetch_existing_categories(mode=FetchMode.FROM_CACHE).get(
                category
            )
            print(f"Get category id: {cat_id}")
            if not cat_id:
                print(f"Category: {category} not exist!")
            else:
                res = self.get(PRODUCTS_ENDPOINT, params={"category": cat_id})
        elif product_id:
            # 根据id获取产品信息
            # 这个api是id检索专用,返回的是单个产品信息,response.json()返回的是字典
            res = self.get(f"{PRODUCTS_ENDPOINT}/{product_id}")
            if res.ok:
                res = [res.json()]
            else:
                print(f"Failed to get product: {product_id}")
        else:
            print("No valid parameters provided.")
        # 从response中解析出字典列表
        if isinstance(res, Response):
            # res = list(res)
            res = res.json()
        return res

    def delete_product(
        self, category=None, name=None, product_id=None, sku=None, force=True
    ):
        """
        删除指定的产品。
        这些参数仅能选择其中一个,否则会报错。


        :param category: 产品的分类（可选）。如果提供，则根据分类删除产品。
        :param name: 产品的名称（可选）。如果提供，则根据名称搜索产品并删除。
        :param id: 产品的 ID（可选）。如果提供，则直接删除该产品。
        :param sku: 产品的 SKU（可选）。如果提供，则根据 SKU 查找产品 ID 并删除。
        :param force: 是否彻底删除产品(True),若设置为False,则仅移入回收站(团队业务一般要删除就是彻底删除)

        :return: list[response]   如果想要查看被删除的产品的名字,可以将此返回值(列表)遍历,调用.json()方法,然后访问"name"字段即可
        """
        products = self.get_product(
            category=category, name=name, product_id=product_id, sku=sku
        )
        # 如果用户提供的是sku,那么根据api的要求,我们要先找到对应的产品id;最终都是通过id来删除指定产品
        # if sku:

        #     self.get_product(sku=sku)

        # if not self.existing_products:
        #     self.fetch_existing_products()
        # product_id = self.existing_products.get(sku)
        # if not product_id:
        #     print(f"Product with SKU '{sku}' not found.")
        #     return None
        # 调用api删除产品
        deleted_products = []
        if products:
            # print(type(products))
            # print(products[0])
            for product in products:
                # product=product.json()

                product_id = product["id"]
                name = product["name"]
                print(f"Try to delete product with ID: {product_id}")
                response = self.delete(
                    f"products/{product_id}", params={"force": force}
                )
                if response.ok:
                    print(
                        f"Delete:product [ID:{product_id};SKU:[{sku}]];\
                            Name:{name} deleted successfully."
                    )
                    # 将删除成功的响应值加入到已删除列表
                    deleted_products.append(response)
                    # 从现有产品缓存中删除该产品
                    self.existing_products.pop(product_id, None)
                    if not sku:
                        sku = product.get("sku")
                    self.existing_products_sku.pop(sku, None)

                else:
                    print(
                        f"Failed to delete product with ID \
                            {product_id}: {self.get_code_message(response)}"
                    )

        return deleted_products

    def delete_batch_products(self, ids):
        """
        批量删除产品。
        传入一个id列表,批量删除对应的产品
        """
        for product_id in ids:
            self.delete_product(product_id=product_id)

    def delete_all_products(self, max_workers=50):
        """
        删除所有产品。
        通过遍历所有产品,然后逐个删除(调用delete_product方法)
        """

        self.fetch_existing_products(fetch_mode=FetchMode.FROM_DATABASE)
        if not self.existing_products:
            print("No products found.")
        # 遍历字典(这里遍历keys即可)
        products_count = self.get_product_count()
        products = copy.deepcopy(self.existing_products)
        workers = self.get_worker_number(products_count, max_workers)
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [
                executor.submit(self.delete_product, product_id=id)
                for id in products.keys()
            ]
            for future in as_completed(futures):
                future.result()

    def upload_rows(
        self,
        rows,
        upload_mode=UPLOAD_MODE,
    ):
        """上传若干行数据

        :param rows:要上传的产品数据列表
        """
        for row in rows:
            self.upload_product(row, upload_mode=upload_mode)

    def get_products_need_to_uploaded(
        self, csv_files=files, fetch_mode=FetchMode.FROM_DATABASE
    ):
        """获取还未上传的产品"""
        # to verify
        if not self.product_from_file:
            self.product_from_file = self.get_rows_from_csvs(csv_files)
        if not self.existing_products_sku:
            self.fetch_existing_products(fetch_mode=fetch_mode)
        # 以接近O(n)的时间复杂度计算还未上传的产品(利用哈希表的快速查找特性,把O(nxm)降低到O(n))
        for product_data in self.product_from_file:
            sku = product_data.get("SKU")
            if not self.existing_products_sku.get(sku, None):
                self.products_need_to_upload.append(product_data)
                print(f"Found:Product with SKU '{sku}' need to upload")
            else:
                print(f"Jump:Product with SKU '{sku}' already exist.")
        return self.products_need_to_upload

    def get_rows_from_csv(self, csv_file):
        """从 CSV 文件读取数据

        返回一个列表,列表中的每个元素是一个字典,字典的键是CSV文件中的列名,值是该列的值。"""
        print(f"process_csv: {csv_file}...")
        rows = []
        with open(csv_file, mode="r", encoding="utf-8") as file:
            reader = csv.DictReader(file)
            rows = list(reader)
            # 将读取到的csv文件缓存到wc示例中,便于后续使用
            # self.product_data_from_file += rows
        return rows

    def get_rows_from_csvs(self, csv_files):
        """从 CSV 文件列表读取数据"""
        for file in csv_files:
            self.product_from_file += self.get_rows_from_csv(file)
        return self.product_from_file

    def orderd_concurrent_execute(self, max_workers, upload_mode, rows):
        """普通的多线程模式,有序发射
        该模式下,所有线程的并发执行顺序是按照csv文件的顺序执行的,即:先上传第一行,再上传第二行,依次类推。(但是先上传的不一定先完成,这是多线程异步执行的特点)

        该模式代码简单,而且容易发现卡住的地方
        不足就是容易集中请求被采集站的服务器,更有可能被封(ban)
        更好的方法是在上传前进行随机化排序,(甚至可以利用pandas重新排列sku编号)

        Parameters
        ----------
        max_workers : int
            线程池内的线程数
        upload_mode : str
            上传模式:
        rows : list[dict]
            从文件读取的要上传的产品数据
        """
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [
                executor.submit(self.upload_product, row, upload_mode=upload_mode)
                for row in rows
            ]
            for future in as_completed(futures):
                future.result()

    def partition_concurrent_execute(self, max_workers, upload_mode, rows):
        """分区并发执行,可以更加直观的看到并发的运行过程,相比于普通的并发模式,更有利于(更有可能)减轻对同一个采集站的并发请求压力(主要是图片请求,但主要还是要控制池内线程数)

        此模式的缺点主要是如果中断的话相对普通的有序发射,较难定位上传卡住的数据位于那一份文件第几条

        Parameters
        ----------
        max_workers : int
            线程池内的线程数
        upload_mode : str
            上传模式:参考调用者函数的文档
        rows : list[dict]
            从文件读取的要上传的产品数据
        """
        batches = split_list(rows, max_workers)
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [
                executor.submit(self.upload_rows, batch, upload_mode=upload_mode)
                for batch in batches
            ]
            # for future in as_completed(futures):
            for future in as_completed(futures):
                future.result()

            # for row in reader:
            #     self.upload_product(product_data=row, upload_mode=upload_mode)

    def batch_concurrent_execute(self, max_workers, rows):
        """按批构造数据发送,节约请求次数和网络连接数压力(服务器端压力可能比较大)

        Parameters
        ----------
        max_workers : int
            线程池内的线程数
        upload_mode : str
            上传模式:(待将来扩展)
        rows : list[dict]
            要上传的产品数据
        """
        # batch_number=ceil(len(rows)/BATCH_SIZE)
        print(
            f"Batch Mode:upload {len(rows)} products in batches with  {max_workers} threads..."
        )
        batches = [rows[i : i + BATCH_SIZE] for i in range(0, len(rows), BATCH_SIZE)]
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [
                executor.submit(self.batch_update_products, batch, idx)
                for idx, batch in enumerate(batches)
            ]
            for future in as_completed(futures):
                future.result()

    def process_csv(
        self,
        csv_file=r"",
        filtered_rows=(),
        max_workers=5,
        upload_mode=UPLOAD_MODE,
        batch_mode=True,
    ):
        """从 CSV 文件读取数据并上传产品
        处理单个csv文件

        :param csv_file csv文件路径,请使用r""字符串,这样兼容正反斜杠
        :param filtered_rows: 过滤后的产品数据列表,用于跳过已存在的产品的方案
        :param max_workers: 并发线程数
        :param upload_mode: 上传模式
        :param batch_mode: 是否使用分批构造数据发送的模式

        :return: None

        方案1:分区并发
        将csv文件平均分为max_workers份,每个线程处理一份
        self.partition_concurrent_execute(max_workers, upload_mode, rows)

        方案2:有序发射模式
        self.orderd_concurrent_execute(max_workers, upload_mode, rows)

        方案3:分批构造数据发送
        self.batch_concurrent_execute(max_workers, rows)

        """
        # 读取所有csv文件,将所有分类整理出来,然后在上传数据前提前创建好分类,可以免去后面的分类检查工作,也有利于降低多线程的处理复杂度
        rows = []
        if csv_file:
            rows = self.get_rows_from_csv(csv_file)
        elif filtered_rows:
            rows = filtered_rows
        else:
            print("No data need to upload Or empty parameters provided.")
        # 根据需要选择上面的方案
        if batch_mode:
            self.batch_concurrent_execute(max_workers, rows)
        else:
            self.orderd_concurrent_execute(max_workers, upload_mode, rows)

    def process_csvs(self, *args, **kwargs):
        """
        安全的csv处理函数,用于防止因为异常导致程序中断
        """
        try:
            self._process_csvs(*args, **kwargs)
        except Exception as e:
            logging.error(f"Error occurred in {e}")

    def _process_csvs(
        self,
        csv_files: list[str] = files,
        max_workers=MAX_WORKERS_FILES,
        upload_mode=UPLOAD_MODE,
        batch_mode=True,
        filtered_mode=True,
        prepare_categories=True,
        log_file="",
    ):
        """从 CSV 文件列表读取数据并上传产品
        处理多个csv文件
        使用self.products_need_to_upload来直接跳过已存在的产品的方案时,
        可以用适当的参数自行分被调用self.get_products_need_to_uploaded()和self.process_csv()

        :param csv_files  csv文件列表,使用r""字符串,这样兼容正反斜杠
        :param max_workers: 并发线程数
        :param upload_mode: 上传模式,使用UploadMode中的枚举值
        :param batch_mode: 是否使用分批构造数据发送的模式(默认使用,可以降低请求压力,降低发生:
            - [WinError 10055] 由于系统缓冲区空间不足或队列已满，不能执行套接字上的操作的错误)
        :param filtered_mode: 是否预先过滤/计算出还未被上传的产品数据(跳过已存在的产品,减少不必要的请求次数)
            这是推荐使用的,样批上传模式也可以轻松跳过已上传的数据
            如果设置为False,将分文件上传
        :param prepare_categories: 是否预先准备分类

            根据需要灵活选择,例如你要检查分类上传后会不会被错误编码,则使用True;
            如果你希望上传第一条产品后能够尽早看到产品列表中的产品,则使用False

            - 如果设置为False
            不会预先检查产品分类,在上传数据时检查该条产品数据,如果分类不存在,则创建,否则直接返回分类id
            - 如果设置为True
            会在上传产品之前,先将分类整理并创建好(调用prepare_categories方法);
        :param log_file: 日志文件路径,用于记录已上传的产品数据,当upload_mode为UploadMode.RESUME_FROM_LOG_FILE时,需要指定该参数

        """

        # 检查路径参数(如果有的话)
        if log_file and not os.path.exists(log_file):
            logging.error(f"Log file '{log_file}' not found.")
            sys.exit(-1)
        # 是否事先准备好分类
        if prepare_categories:
            self.prepare_categories(csv_files)
        else:
            print(
                "Mutex Lock Mode:check and create categories when data row was uploading..."
            )
        # 上传模式/策略:读档(恢复上传进度方案)
        if upload_mode == UploadMode.RESUME_FROM_DATABASE:
            # 尝试从wp站数据库中读取已上传的数据,并写入缓存容器
            self.fetch_existing_categories()  # mode=FetchMode.FROM_DATABASE
            self.fetch_existing_products()
        elif upload_mode == UploadMode.RESUME_FROM_LOG_FILE:
            # 从日志文件中读取已上传的数据,并写入缓存容器
            # to verify
            self.fetch_existing_products(
                fetch_mode=FetchMode.FROM_LOG_FILE, log_file=log_file
            )

        # 数据文件处理和上传策略(并发方式)
        ## 方案1:计算出尚未上传的产品(集中处理)
        if filtered_mode:
            self.get_products_need_to_uploaded(csv_files)
            self.process_csv(
                filtered_rows=self.products_need_to_upload,
                max_workers=max_workers,
                upload_mode=upload_mode,
                batch_mode=batch_mode,
            )
        else:
            # 方案2:逐个文件处理(分散处理)
            with ThreadPoolExecutor(max_workers=max_workers) as executor:
                futures = [
                    executor.submit(
                        self.process_csv,
                        file,
                        max_workers=MAX_WORKERS_PER_FILE,
                        upload_mode=upload_mode,
                        batch_mode=batch_mode,
                    )
                    for file in csv_files
                ]
                for future in as_completed(futures):
                    future.result()


##

# 主函数
if __name__ == "__main__":

    # 启动后台日志线程
    log_thread = threading.Thread(target=log_worker, daemon=True)
    log_thread.start()

    wc = WC()
    # 检查woo鉴权和链接(返回-1表示链接失败)
    wc.get_product_count()

    # 拉取缓存数据(产品数据/分类),对于非纯净上传模式建议执行下面语句
    # wc.fetch_existing_products(max_workers=15,mode=FetchMode.FROM_DATABASE)
    # wc.fetch_existing_categories()

    # 清空所有产品(对于干净上传,可以清除模板中自带的商品)
    # wc.delete_all_products()

    # 普通执行(干净上传)
    # wc.process_csvs(
    #     files,
    #     max_workers=MAX_WORKERS_FILES,
    #     upload_mode=UPLOAD_MODE,
    #     prepare_categories=True,
    #     batch_mode=True,
    # )

    # 从日志文件中恢复上传进度
    # wc.process_csvs(
    #     files,
    #     max_workers=MAX_WORKERS_FILES,
    #     upload_mode=UploadMode.RESUME_FROM_LOG_FILE,#如果要从数据库中恢复,则使用UploadMode.RESUME_FROM_DATABASE
    #     prepare_categories=True,
    #     batch_mode=True,
    #     log_file=r"" #填写正确的日志文件路径
    # )

    # 结尾清理log_thread(适合于从命令行中执行时使用)
    # cleanup_log_thread(log_thread)
