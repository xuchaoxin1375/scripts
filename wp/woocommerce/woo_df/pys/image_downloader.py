"""图片下载器

调用imgdown模块实现多线程图片下载功能
TODO:
改进日志:改造下载日志为便于针对性恢复下载进度的存档型日志(比如使用json记录每个图片的下载结果,尤其注意请求码中404这类没有重试意义的错误,在进度恢复或者重新下载尝试意义不大的图片应该在二次下载中跳过)
下载任务的存档日志设计应该合理,除了日志文件内结构,还有日志存放位置(参考思路:将关键下载参数适当处理拼接到日志输出路径中,每次下载读取指定日志文件,并尝试恢复下载进度)

"""

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

# from woo_df.imgdown import ImageDownloader
from imgdown import ImageDownloader, USER_AGENTS, BROSWER_DOWNLOADER,PLAY_BROWSER_DOWNLOADER
from filenamehandler import FilenameHandler as fh
from wooenums import CSVProductFields

DOWNLOAD_METHODS = (
    ["request", "curl", "cffi", "iwr"] + BROSWER_DOWNLOADER
)

PROXY_HTTP = os.environ.get("HTTP_PROXY")

RESIZE_THRESHOLD = (1000, 800)
DEAFULT_EXT = ".webp"
csv.field_size_limit(int(1e7))
# 或者根据实际类定义位置调整导入路径
IMG_DIR = "./images"
selected_csv_field_ids: list[str] = []
# 日志配置
LOG_LEVEL = logging.INFO
# 此脚本为应用程序入口,适合设置为根日志记录器(root)
logger = logging.getLogger("root")
# logger=logging.getLogger("ImageDownloader") # 如果这里使用的是非root记录器,则可能出现消息被重复打印(不过格式可能不同罢了)

# 接管imgdown模块的日志记录器
# imgdown_logger = logging.getLogger(__name__)
# imgdown_logger = logging.getLogger("ImageDownloader.imgdown")
imgdown_logger = logger.getChild("imgdown")


# 设置日志级别(包括被引用模块的日志记录器日志级别,如果模块支持的话)
def set_loggers_level(level=LOG_LEVEL):
    """设置日志级别"""
    logger.setLevel(level)
    imgdown_logger.setLevel(level)
    # compressor_logger.setLevel(level)


# set_loggers_level(LOG_LEVEL)


def add_log_handler():
    """设置日志记录器的handler定义和绑定操作"""
    console_handler = logging.StreamHandler()
    console_formatter = logging.Formatter(
        fmt="%(asctime)s == %(name)s - %(levelname)s %(funcName)s: %(message)s"
    )
    console_handler.setFormatter(console_formatter)
    # 绑定到日志记录器
    logger.addHandler(console_handler)


add_log_handler()

# 默认 INFO，main() 里根据 -v 再调整
info = logger.info
debug = logger.debug
warning = logger.warning
error = logger.error
exception = logger.exception

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
    # 使用说明(用于打印给用户)
    desc = """

    多方案集成的强力图片下载器
    
    Examples:
        # 假设当前shell中配置了$var所需的环境变量: 
        python $pys/image_downloader.py -c -n -R auto -k  -rs 1000 800  --output-dir $Desktop/test_img_down -f  $downloads/p4.csv -F  -w 2  -U bro
    
    """
    parser = argparse.ArgumentParser(description=desc)
    # 关于输入的参数(图片链接)的若干形式
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
        "-d",
        "--dir-input",
        nargs="+",
        required=False,
        help="包含图片URL的文件所在[目录(文件夹)]，允许指定多个目录(todo)",
    )
    # 关于输入的额外属性描述相关参数
    parser.add_argument(
        "-a",
        "--format-consistent",
        action="store_true",
        help="所有输入文件是否为相同的格式(如果是,可以避免多次询问文件格式)",
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
    # 输出参数和控制
    parser.add_argument(
        "-o",
        "--output-dir",
        default=IMG_DIR,
        help="图片保存目录 (默认: ./images)"
        "此下载器设计为批量下载,如果要指定文件的保存名字,需要在批量输入(比如表格文件)中指定每个图片的保存名"
        "对于单个下载图片链接的测试行为,此选项应该将理解为输出目录而不是单个输出文件路径"
        "可以考虑增加-op选项,用来针对下载单个图片链接时指定保存文件名(todo)",
    )
    parser.add_argument(
        "-O", "--override", action="store_true", default=False, help="是否覆盖已有图片"
    )
    # 下载方案控制
    parser.add_argument(
        "-U",
        "--download-method",
        default="request",
        choices=DOWNLOAD_METHODS,
        # action="store_true",
        help=f"使用python 请求或外部工具下载图片(request,curl,iwr,browser,scrapling)以及浏览器方案playwright,同义词{PLAY_BROWSER_DOWNLOADER},scrapling是更强劲的浏览器方案",
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
        "-F",
        "--fake-format",
        action="store_true",
        help="在体积没有缩小的情况下,将原图片的后缀更改为指定的输出格式相同",
    )
    parser.add_argument(
        # 默认情况下，argparse.ArgumentParser会自动为帮助信息（help message）添加一个-h/--help选项，这导致了与这里不能新-h选项,否则发生冲突
        "-H",
        "--headless",
        action="store_true",
        help="是否使用无头模式(不显示浏览器窗口)下载图片(当指定浏览器下载是有效)",
    )
    parser.add_argument(
        "-ps",
        "--ps-version",
        default="powershell",
        choices=["powershell", "pwsh"],
        help="PowerShell版本,可选值:powershell,pwsh",
    )
    parser.add_argument(
        "-ci",
        "--curl-insecure",
        action="store_true",
        help="忽略curl证书验证和检查(为curl启用-k,--ssl-no-revoke)",
    )
    parser.add_argument(
        "-s",
        "--verify-ssl",
        action="store_true",
        help="是否验证SSL证书(启用会提高安全性，但可能降低下载速度以及成功率)",
    )
    parser.add_argument("--proxy-file", help="代理url列表文件路径")
    parser.add_argument("--proxy", help="代理url")
    parser.add_argument("--cookie-file", help="包含Cookies的JSON文件路径")
    parser.add_argument(
        "-Z",
        "--user-data-dir",
        "--profile-dir",
        help="指定持久化浏览器配置/Cookies的主目录(适用于scrapling等浏览器方案)",
    )
    parser.add_argument(
        "-W",
        "--warmup",
        action="store_true",
        default=False,
        help="启用单任务顺序预热模式，先使用单页面通过可能的人机验证(如Cloudflare)，之后再并发下载剩余链接",
    )

    parser.add_argument("-v", "--verbose", action="store_true", help="显示详细日志")
    parser.add_argument(
        "--loglevel",
        help="日志级别,可选值:DEBUG,INFO,WARNING,ERROR,CRITICAL,不区分大小写",
    )
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
    parser.add_argument(
        "-S",
        "--config",
        help="从指定的 JSON 配置文件中读取参数。如果命令行中也指定了参数，命令行优先级更高。",
    )

    # 1. 正常解析所有命令行参数
    args = parser.parse_args()

    # 2. 如果指定了配置文件且存在，则进行合并处理
    if args.config:
        import json
        if os.path.exists(args.config):
            try:
                with open(args.config, "r", encoding="utf-8") as f:
                    config_data = json.load(f)
                
                # 提取原始默认值
                original_defaults = {
                    action.dest: action.default 
                    for action in parser._actions 
                    if action.dest != "help"
                }

                # 抑制解析器中的所有默认值，以提取用户显式指定的命令行参数
                for action in parser._actions:
                    if action.dest != "help":
                        action.default = argparse.SUPPRESS

                # 重新解析，得到仅包含用户显式指定参数的 Namespace
                explicit_args = parser.parse_args()

                # 合并优先级：默认值 < 配置文件值 < 命令行显式指定值
                merged_dict = {}
                
                # a. 填充默认值
                for k, v in original_defaults.items():
                    if v != argparse.SUPPRESS:
                        merged_dict[k] = v

                # b. 覆盖配置文件中的值
                for k, v in config_data.items():
                    merged_dict[k] = v

                # c. 覆盖命令行中显式指定的值
                for k, v in vars(explicit_args).items():
                    merged_dict[k] = v

                args = argparse.Namespace(**merged_dict)
                logger.info(f"成功加载并合并了配置文件: {args.config}")
            except Exception as e:
                logger.error(f"加载配置文件 {args.config} 失败: {e}")
        else:
            logger.warning(f"指定的配置文件不存在: {args.config}")

    return args


def main():
    """主函数"""
    # 注册 Ctrl+C 信号处理器，确保不管处于何种异步事件循环或并发状态下，均能一次 Ctrl+C 瞬间强退程序
    import signal
    def signal_handler(sig, frame):
        logger.warning("\n🛑 接收到 Ctrl+C 信号！正在强行退出并终止所有底层下载进程/线程...")
        os._exit(1)
    signal.signal(signal.SIGINT, signal_handler)
    try:
        signal.signal(signal.SIGTERM, signal_handler)
    except AttributeError:
        pass

    # 解析命令行用户传输进来的参数,像字典一样使用它
    args = parse_args()

    # 设置日志级别
    if args.verbose:
        logger.setLevel(logging.DEBUG)
        # set_loggers_level(level=logging.DEBUG)
    if args.loglevel:
        # 校验用户输入的日志级别是否是可用的合法值(转换为数字级别)
        numeric_level = getattr(logging, args.loglevel.upper(), None)
        if not isinstance(numeric_level, int):
            raise ValueError(f"Invalid log level: {args.loglevel}")
        logger.setLevel(numeric_level)
        # logging.basicConfig(level=numeric_level)
        # set_loggers_level(level=numeric_level)

    # 打印当前的日志级别:
    info("当前日志级别: %s", logging.getLevelName(logger.level))
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
            # 解析所有需要被处理的文件,将结果保存在lines变量中
            parse_image_sources(
                file=file, args=args, lines=lines, selected_ids=selected_csv_field_ids
            )

        if lines:
            print(f"读取行数: {len(lines)}")

        else:
            error("读取行数为0,请检查参数")
            exit(1)
    elif args.dir_input:
        # 处理目录输入(遍历目录下的文件,转换到文件处理的情况)🎈
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
                    info(f"处理目录: [{d}]")
                for file in os.listdir(d):
                    info("处理文件: %s", file)
                    _, ext = os.path.splitext(file)
                    if ext not in [".csv", ".txt"]:
                        debug("忽略非csv或txt文件: %s", file)
                        continue
                    file = os.path.abspath(os.path.join(d, file))
                    # 解析所有需要被处理文件,将结果保存在lines变量中🎈
                    parse_image_sources(
                        file=file,
                        args=args,
                        lines=lines,
                        selected_ids=selected_csv_field_ids,
                    )
                    # print(lines,"🎈🎈")
    debug(f"use shutil:{args.download_method}")
    # 创建下载器实例,控制下载器基本行为

    # 计算最终要使用的代理.
    proxy = PROXY_HTTP if not args.proxy and PROXY_HTTP else args.proxy
    info("当前设置的代理: %s", [proxy])

    downloader = ImageDownloader(
        max_workers=args.workers,
        timeout=args.timeout,
        retry_times=args.retry,
        proxies=proxy,
        user_agent=args.user_agent,
        download_method=args.download_method,
        compress_quality=args.compress_quality,
        quality_rule=args.quality_rule,
        remove_original=args.remove_original,
        override=args.override,
        resize_threshold=args.resize_threshold,
        ps_version=args.ps_version,
        curl_insecure=args.curl_insecure,
        fake_format=args.fake_format,
        headless=args.headless,
        user_data_dir=args.user_data_dir,
        warmup=args.warmup,
    )
    # 过滤已有图片,扫描出尚未下载的图片
    # 这里不关心文件名后缀的差异,比较basename
    ## 读取指定目录下的图片(只列出名字)
    if not os.path.exists(args.output_dir):
        warning("指定的输出目录[%s]不存在(将尝试自动创建)", args.output_dir)
    elif not args.override:
        # 查询指定目录下的已有图片以及去重处理
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
                if fh.get_filebasename_from_url_or_path(name)
                not in img_names_existed  # 这里进行查重,仅比较图片名字(不包括后缀,使用对应的函数截取图片基名)
            ]
            # print(lines,"🎈🎈")
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
    try:
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
    except KeyboardInterrupt:
        logger.warning("\n🛑 接收到 Ctrl+C 信号！正在强行退出并终止所有底层下载进程/线程...")
        os._exit(1)

    return 0


if __name__ == "__main__":
    info("welcome to use image downloader!")
    sys.exit(main())
