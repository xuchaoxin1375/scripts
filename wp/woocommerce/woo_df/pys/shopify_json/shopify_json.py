

"""
Shopify JSON下载器
功能：批量下载Shopify网站的产品JSON数据
作者：Claude
"""

import os
from config import *
from shopifydown import ShopifyDownloader, log

# ===================================================


def main():
    """主函数"""
    # 使用代码中定义的路径和设置，无需命令行参数
    downloader = ShopifyDownloader(
        output_dir=DEFAULT_SAVE_PATH,
        url_threads=URL_THREADS,
        download_threads=DOWNLOAD_THREADS,
    )

    # 检查Excel文件是否存在
    if os.path.exists(EXCEL_FILE_PATH):
        downloader.start(excel_file=EXCEL_FILE_PATH)
    else:
        log(f"错误: Excel文件不存在: {EXCEL_FILE_PATH}", 0)
        log("请修改代码顶部的EXCEL_FILE_PATH变量指向正确的Excel文件路径", 0)


if __name__ == "__main__":
    main()
