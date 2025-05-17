"""
Woocommerce product handler/uploader for wordpress.
Copyright (C) 2025 cxxu1375. All Rights Reserved.

使用文档和注意事项,请查看Readme.md文本文件(必看)
尤其是遇到问题,可以参考文档中的说明

下面是一些基础参数的简要说明:
最大总线程数不超过MAX_WORKERS_FILES * MAX_WORKERS_PER_FILE(两者之积)
  使用filtered模式(仅上传尚未上传的产品)的情况下,仅MAX_WORKERS_FILES有效,
  batch模式下,其决定将需要上传的数据(单个集合)用几线程上传
"""

# %%

# 请安装必要的库(主要是woocomece库要下载,也可以自行提取,大多是自带无需下载的库)
# from typing import Literal
import logging
import os
import threading
from datetime import datetime

from comutils import log_worker
from woodf import WC

# from woodf_dev import WC
from wooenums import UploadMode

# from requests.exceptions import ConnectTimeout, ReadTimeout, Timeout, RequestException

# 用户要配置的参数🎈(仔细检查下面内容)
# 本地开发和测试域名:http://wp.com
protocal = "http"  # 协议,一般是https(适用于正式上传),http(适用于本地脚本调试/开发)
domain = "wp.com"  # 域名
url = f"{protocal}://{domain}"  # 不要有多余的路径
consumer_key = "ck_cea9b0730bbda84628674625dc206495ddf62fc7"
consumer_secret = "cs_ba0185c197dc041ad8ba91915886395404badcb9"

# 这里指定目录,不是文件!🎈(指定文件请到备用方案2中指定)

CSV_DIR = r"S:\csv_demo\current"

MAX_WORKERS_FILES = 1  # 同时上传的文件数(一般不超过7);
MAX_WORKERS_PER_FILE = 1  # 每份文件上传的线程数
TIME_OUT = 500  # 如果是批上传,可以考虑调大些,防止响应体过大时间不足导致报错
BATCH_SIZE = 7  # 每批上传的产品数量(如果上传不顺利,可以适当调小些,反之可以调大些,美国产品数据反爬普遍比较严,一般考虑调小,避免过多的524错误)


# 默认选择的上传模式🎈:
UPLOAD_MODE = UploadMode.FLEXIBLE

# 日志文件路径,可作为存档,恢复上传断点🎈
CSV_DIR = CSV_DIR.strip("/")
TIME_STR = datetime.now().strftime("%Y%m")  # 日期精度自己控制(%Y%m%d-%H-%M-%S)
LOG_FILE_UPLOAD = f"{CSV_DIR}/log/upload-{domain}-{TIME_STR}.csv"
# LOG_FILE_UPLOAD_BAK = f"C:/log/upload-{domain}.csv"
# LOG_FILE_UPLOAD_FAIL=f"{CSV_DIR}/log/upload_fail-{domain}-{time_str}.csv"


# 主推方案:获取指定目录下的csv文件列表
files_from_dir = os.listdir(CSV_DIR)
dir_csv_files = [os.path.join(CSV_DIR, f) for f in files_from_dir if f.endswith(".csv")]


# 备用方案1:自动生成文件名,如果文件名比较规范(可选)
#   比如range(1,7),将编号1,2,...,6(左闭右开整数区间)
#   指定要处理的文件列表
auto_csv_files = [os.path.join(CSV_DIR, f"p{i}.csv") for i in range(1, 7)]

# 备用方案2:手动指定文件列表配置(可选)
manual_csv_files = [
    "  ./p1.csv  ",
    "  C:/path/x.csv  ",
]

# 指定你的文件列表(从上述三种方案中选择一种,推荐使用方案1)

files = dir_csv_files

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)


# 主函数
if __name__ == "__main__":

    # 启动后台日志线程
    log_thread = threading.Thread(
        target=log_worker, args=(LOG_FILE_UPLOAD,), daemon=True
    )
    log_thread.start()

    wc = WC(
        api_consumer_key=consumer_key,
        api_consumer_secret=consumer_secret,
        api_url=url,
        timeout=TIME_OUT,
    )
    # 检查woo鉴权和链接(返回-1表示链接失败)
    wc.get_product_count()

    # 拉取缓存数据(产品数据/分类),对于非纯净上传(尤其是之前不是用此脚本上传的情况下)

    # 清空所有产品(对于干净上传,可以清除模板中自带的商品)
    # wc.delete_all_products()

    ## 普通执行
    wc.process_csvs(
        csv_files=files,
        max_workers=MAX_WORKERS_FILES,
        upload_mode=UPLOAD_MODE,
        prepare_categories=True,
        batch_mode=True,
        batch_size=BATCH_SIZE,
        # 如果是RESUME_FROM_LOG_FILE模式,请填写正确的日志[文件(.log)]路径!
        log_file=LOG_FILE_UPLOAD,
    )



    ## 结尾清理log_thread(适合于从命令行中执行时使用)
    # cleanup_log_thread(log_thread)
