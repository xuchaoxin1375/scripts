"""
Shopify JSON下载器
功能：批量下载Shopify网站的产品JSON数据
作者：Claude
"""

import argparse
import os

from config import *
from shopifydown import ShopifyDownloader, log

# ===================================================


def parse_arguments():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(description="Shopify JSON 下载器")
    parser.add_argument(
        "--local-domain",
        type=str,
        default=LOCAL_DOMAIN,
        help="本地域名 (默认: %(default)s)",
    )
    parser.add_argument(
        "--wp-sites-dir",
        type=str,
        default=WP_SITES_DIR,
        help="WordPress 站点目录 (默认: %(default)s)",
    )
    parser.add_argument(
        "--json-dir",
        type=str,
        default=JSON_DIR,
        help="JSON 文件保存目录 (默认: %(default)s)",
    )
    parser.add_argument(
        "-i",
        "-e",
        "--excel-file-path",
        type=str,
        default=EXCEL_FILE_PATH,
        help="Excel 文件路径 (默认: %(default)s)",
    )
    return parser.parse_args()


def main():
    """主函数"""
    args = parse_arguments()

    # 使用命令行或代码中定义的路径和设置
    downloader = ShopifyDownloader(
        output_dir=args.json_dir,
        url_threads=URL_THREADS,
        download_threads=DOWNLOAD_THREADS,
    )

    # 检查Excel文件是否存在
    if os.path.exists(args.excel_file_path):
        downloader.start(excel_file=args.excel_file_path)
    else:
        log(f"错误: Excel文件不存在: {args.excel_file_path}", 0)
        log("请指定正确的Excel文件路径", 0)


if __name__ == "__main__":
    main()
