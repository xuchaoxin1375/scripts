"""图片下载器"""

import argparse
import csv
import logging
import os
import re
import sys

# from logging import error, exception, info, warning, debug
from comutils import (
    URL_SEP_PATTERN,
    URL_SEPARATORS,
    get_user_choice_csv_fields,
    get_data_from_csv,
    # split_multi,
)
from imgdown import ImageDownloader, USER_AGENTS
from filenamehandler import FilenameHandler as fh
from wooenums import CSVProductFields

RESIZE_THRESHOLD = (1000, 800)
DEAFULT_EXT = ".webp"
csv.field_size_limit(int(1e7))  # 允许csv文件最大为10MB
# 或者根据实际类定义位置调整导入路径
IMG_DIR = "./images"
selected_csv_field_ids: list[str] = []
# 日志配置
logger = logging.getLogger("ImageDownloader")
info = logger.info
debug = logger.debug
warning = logger.warning
error = logger.error
exception = logger.exception

if not logger.handlers:
    console_handler = logging.StreamHandler()
    console_formatter = logging.Formatter(
        fmt="%(asctime)s [%(levelname)s] %(funcName)s: %(message)s"
    )
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)
# 默认 INFO，main() 里根据 -v 再调整
logging.basicConfig(level=logging.INFO)
debug("Logger initialized %s", logging.getLevelName(logger.level))


def parse_image_sources(file, args, lines, selected_ids=None):
    """
    解析输入文件，提取图片下载所需的URL和文件名。

    对于处理多个文件,且多个文件的格式一样(主要针对csv文件),可以选择记住参数,避免后续反复要求填写列号
    (当然也可以DF特定的csv文件格式也可以当做普通csv看待,但是后者有专门的参数会更加直接)

    :param file_path: 输入文件路径
    :param args: 命令行参数对象（包含 from_specific_csv, from_csv 等标志）
    :param lines: 用于存储结果的列表(多次调用将会累加到这个列表中)，格式为 [(name, url), ...] 或 [url, ...]
    :return: 成功返回 True，失败抛出异常或返回 False
    """

    try:
        with open(file=file, mode="r", encoding="utf-8") as f:
            if args.from_specific_csv:
                # DF团队特定csv文件格式
                csv_dict_reader = csv.DictReader(f)
                name_field = CSVProductFields.IMAGES.value
                url_field = CSVProductFields.IMAGES_URL.value

                get_data_from_csv(args, lines, csv_dict_reader, url_field, name_field)

            elif args.from_csv:
                # 针对一般的含有图片链接的csv文件,更加灵活(也能够处理上面的情况,但是上面专用分支会更加快捷)
                csv_dict_reader = csv.DictReader(f)
                reader_headers = csv_dict_reader.fieldnames or []
                fmt_consistent = args.format_consistent
                debug("Use selected_ids: %s", selected_ids)
                debug("Use fmt_consistent: %s", fmt_consistent)
                if fmt_consistent and selected_ids:
                    # 格式一致且指定了列号,直接使用记住的参数(不需要每个文件都询问)
                    pass
                else:
                    # 打印出csv文件中所有字段名,让用户选择🎈
                    selected_ids = get_user_choice_csv_fields(
                        selected_ids, reader_headers
                    )

                selected_ids = selected_ids or []
                if len(selected_ids) == 2:
                    # 分别解析字段索引,然后获取字段名
                    name_field_id, url_field_id = selected_ids
                    name_field = reader_headers[int(name_field_id)]
                    url_field = reader_headers[int(url_field_id)]
                elif len(selected_ids) == 1:
                    url_field = reader_headers[int(selected_ids[0])]
                    name_field = ""
                else:
                    raise ValueError("请按照正确的格式输入列号")

                get_data_from_csv(args, lines, csv_dict_reader, url_field, name_field)

            else:
                for line in f:
                    parts = re.split(pattern=URL_SEP_PATTERN, string=line.strip())
                    if args.name_url_pairs:
                        if len(parts) == 2:
                            name, url = parts
                            lines.append((name.strip(), url.strip()))
                        else:
                            warning("无效的行格式: %s; parts=%s", line, parts)
                    else:
                        lines.append(line.strip())

                if not lines:
                    error("没有有效的文件名和URL对")
                    return False

        return True

    except Exception as e:
        error("读取文件失败: %s", str(e))
        return False


def parse_args():
    """解析命令行参数

    利用parser.add_argument()方法添加命令行参数，并解析命令行参数
    长选项--开头,例如--workers,指出参数将会绑定到相应的变量上,经过parse_args()解析,将构造对应的参数包
    """
    parser = argparse.ArgumentParser(description="多线程图片下载器")
    parser.add_argument(
        "-i",
        "--test-url",
        help="手动指定若干图片URL进行测试下载,如果有多个URL,用空格分隔",
    )
    parser.add_argument(
        "-f",
        "--file-input",
        nargs="+",
        required=False,
        help="包含图片URL的输入[文件],允许指定多个文件",
    )
    parser.add_argument(
        "-a",
        "--format-consistent",
        action="store_true",
        help="所有输入文件是否为相同的格式(如果是,可以避免多次询问文件格式)",
    )
    parser.add_argument(
        "-d",
        "--dir-input",
        nargs="+",
        required=False,
        help="包含图片URL的文件所在[目录(文件夹)]，允许指定多个目录(todo)",
    )
    parser.add_argument(
        "-c",
        "--from-specific-csv",
        action="store_true",  # 开关式参数
        help="指定的文件是特定csv文件(df团队定制格式),从csv文件中指定的图片名字/链接下载",
    )
    parser.add_argument(
        "-C",
        "--from-csv",
        action="store_true",  # 开关式参数
        help="指定的文件是普通csv文件,从csv文件中下载所有图片",
    )
    parser.add_argument(
        "-n",
        "--name-url-pairs",
        action="store_true",  # 开关式参数
        help=f'输入文件包含文件名和URL对，格式为"文件名 URL"，以[{URL_SEPARATORS}]中指定的符号分隔',
    )
    parser.add_argument(
        "-o", "--output-dir", default=IMG_DIR, help="图片保存目录 (默认: ./images)"
    )
    parser.add_argument(
        "-O", "--override", action="store_true", default=False, help="是否覆盖已有图片"
    )
    parser.add_argument(
        "-U",
        "--use-shutil",
        default="",
        # action="store_true",
        help="使用外部命令行工具下载图片(curl或iwr)",
    )
    parser.add_argument("-w", "--workers", type=int, default=10, help="下载线程数")
    parser.add_argument(
        "-t", "--timeout", type=int, default=30, help="下载超时时间，单位秒"
    )
    parser.add_argument("-r", "--retry", type=int, default=0, help="下载失败重试次数 ")
    parser.add_argument("-R", "--quality-rule", help="压缩图片的质量规则")
    parser.add_argument(
        "-u", "--user-agent", default=USER_AGENTS[0], help="自定义User-Agent"
    )
    parser.add_argument(
        "-s",
        "--verify-ssl",
        action="store_true",
        help="是否验证SSL证书(启用会提高安全性，但可能降低下载速度以及成功率)",
    )
    parser.add_argument("--proxy-file", help="代理IP地址列表文件路径")
    parser.add_argument("--cookie-file", help="包含Cookies的JSON文件路径")

    parser.add_argument("-v", "--verbose", action="store_true", help="显示详细日志")
    parser.add_argument(
        "-x",
        "--compress-quality",
        type=int,
        
        default=0,
        help="压缩图片为webp格式的quality参数(1-100),取0表示不压缩",
    )
    parser.add_argument(
        "-k",
        "--remove-original",
        action="store_true",
        help="保留压缩后的原始图片",
    )
    parser.add_argument(
        "-rs",
        "--resize-threshold",
        type=int,
        nargs=2,
        # default=RESIZE_THRESHOLD,
        help="指定图片等比例缩放后的最大尺寸(宽,高),单位px;放空表示不调整分辨率",
    )

    return parser.parse_args()


def main():
    """主函数"""

    # 解析命令行用户传输进来的参数,像字典一样使用它
    args = parse_args()

    # 设置日志级别
    if args.verbose:
        logger.setLevel(logging.INFO)
    # 打印当前的日志级别:
    print(f"当前日志级别: {logging.getLevelName(logger.level)}")
    debug("当前日志级别: %s", logging.getLevelName(logger.level))
    # 读取输入文件
    lines = []
    if args.test_url:
        # 处理测试URL下载
        lines = re.split(URL_SEP_PATTERN, args.test_url)
    elif args.file_input:
        # 处理文件输入
        files = args.file_input
        # files = split_multi(files)
        for file in files:
            parse_image_sources(
                file=file, args=args, lines=lines, selected_ids=selected_csv_field_ids
            )
        if lines:
            print(f"读取行数: {len(lines)}")
        else:
            error("读取行数为0,请检查参数")
            exit(1)
    elif args.dir_input:
        # 处理目录输入(遍历目录下的文件,转换到文件处理的情况)
        dirs = args.dir_input
        # dirs = split_multi(dirs)
        if not dirs:
            error("请指定目录!")
            exit(1)
        else:
            for d in dirs:
                if not os.path.exists(d):
                    error("指定的目录不存在: %s", dirs)
                    sys.exit(1)
                else:
                    print(f"处理目录: [{d}]")
                for file in os.listdir(d):
                    info("处理文件: %s", file)
                    _, ext = os.path.splitext(file)
                    if ext not in [".csv", ".txt"]:
                        debug("忽略非csv或txt文件: %s", file)
                        continue
                    file = os.path.abspath(os.path.join(d, file))
                    parse_image_sources(
                        file=file,
                        args=args,
                        lines=lines,
                        selected_ids=selected_csv_field_ids,
                    )
    debug(f"use shutil:{args.use_shutil}🎈")
    # 创建下载器
    downloader = ImageDownloader(
        max_workers=args.workers,
        timeout=args.timeout,
        retry_times=args.retry,
        user_agent=args.user_agent,
        use_shutil=args.use_shutil,
        compress_quality=args.compress_quality,
        quality_rule=args.quality_rule,
        remove_original=args.remove_original,
        override=args.override,
        resize_threshold=args.resize_threshold,
    )
    # 过滤已有图片,扫描出尚未下载的图片
    # 这里不关心文件名后缀的差异,比较basename
    ## 读取指定目录下的图片(只列出名字)
    if not os.path.exists(args.output_dir):
        warning("指定的输出目录[%s]不存在(将尝试自动创建)", args.output_dir)
    elif not args.override:
        # 如果指定的存放目录存在
        img_names_existed = os.listdir(args.output_dir)
        # 默认情况下,对比重复下载时,我们只关心文件名,不关心后缀
        img_names_existed = [os.path.splitext(name)[0] for name in img_names_existed]
        # 记录过滤前的待下载图片数量
        total_num_raw = len(lines)
        if args.name_url_pairs:
            # 从二元组中解析出名字
            lines = [
                (name, _)
                for name, _ in lines
                if fh.get_filebasename_from_url_or_path(name) not in img_names_existed
            ]
            print(lines)
            # return
        else:
            # 从URL列表中解析出名字
            lines = [
                url
                for url in lines
                if fh.get_filebasename_from_url_or_path(url) not in img_names_existed
            ]
        total_num_filtered = len(lines)
        # 统计多少图片被过滤掉
        num_filtered = total_num_raw - total_num_filtered
        info(
            "过滤掉%d张图片(过滤前后分别有: %d张, %d张)",
            num_filtered,
            total_num_raw,
            total_num_filtered,
        )

    # 下载图片
    if args.name_url_pairs:
        # 解析文件名和URL对(使用自定义文件名)
        try:
            downloader.download_with_names(
                name_url_pairs=lines,
                output_dir=args.output_dir,
                default_ext=DEAFULT_EXT,
            )
        except Exception as e:
            exception("下载过程中发生错误: %s", str(e))
            return 1
    else:
        # 直接下载URL列表中的图片
        try:
            if not lines:
                warning("没有有效的URL")
                return 1

            downloader.download_only_url(
                urls=lines, output_dir=args.output_dir, default_ext=DEAFULT_EXT
            )
        except Exception as e:
            exception("下载过程中发生错误: %s", str(e))
            return 1

    return 0


if __name__ == "__main__":
    info("welcome to use image downloader!")
    sys.exit(main())
