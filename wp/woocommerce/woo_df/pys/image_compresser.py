"""
图片压缩与转换工具的命令行工具
"""

import argparse
import logging
import os
import sys

from imgcompresser import ImageCompressor, setup_logging

QUALITY_DEFAULT = 70
QUALITY_DEFAULT_STRONG = 20
COMPRESS_TRHESHOLD_KB = 0  # 只对指定大小以上的图片文件进行压缩(取值为0时全部压缩)

K = 2**10
COMPRESS_TRHESHOLD_B = COMPRESS_TRHESHOLD_KB * K
COMPRESS_TRHESHOLD = COMPRESS_TRHESHOLD_B
DEFAULT_QUALITY_RULE = "0,50,70 ; 50,200,40 ; 200,10000,30"


def parse_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        description="图片压缩与转换工具",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    # parser.add_argument(
    #     "input",
    #     nargs="?",  # 可选
    #     default=None,
    #     help="输入文件或目录路径"
    # )
    parser.add_argument(
        "-i",
        "--input",
        dest="input",  # 映射到 args.input
        help="输入文件或目录路径 (可选参数形式)",
    )
    parser.add_argument(
        "-o",
        "--output",
        # default="./",
        help="输出文件或目录路径(如果放空,且input是目录,则默认输出目录为input目录)",
    )
    parser.add_argument(
        "-f",
        "--format",
        choices=["webp", "jpg", "png"],
        # default="",
        help="输出格式(webp/jpg/png),默认为原格式,不做格式转换",
    )
    parser.add_argument(
        "-q",
        "--quality",
        type=int,
        default=QUALITY_DEFAULT,
        help="压缩质量(1-100)",
    )
    parser.add_argument(
        "--no-optimize",
        action="store_false",
        dest="optimize",
        help="禁用优化",
    )
    parser.add_argument(
        "--no-exif",
        action="store_false",
        dest="keep_exif",
        help="不保留EXIF信息",
    )
    parser.add_argument(
        "-O",
        "--overwrite",
        action="store_true",
        help="覆盖已存在的输出文件",
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=10,
        help="批量处理时的最大线程数",
    )
    parser.add_argument(
        "-T",
        "--compress-threshold",
        type=int,
        default=COMPRESS_TRHESHOLD_KB,
        help="压缩阈值(KB), 小于该阈值的图片微压(quality=70)"
        "(取值为0表示不设置压缩门槛全部压缩),取值越大,压缩力度越轻,反之越高"
        "(此选项是quality-rule的简化版,更多需求可以通过quality-rule更灵活地调整)",
    )
    parser.add_argument(
        "-R",
        "--quality-rule",
        type=str,
        # default="auto",
        help="对不同大小图像区间采用不同的quality值的指定规则"
        "例如'50,200,40' 表示50到200KB区间的图片设置quality=70`,多个区间用分号(;)分隔\n 如果使用 `auto`则使用内部的推荐值 ",
    )
    parser.add_argument(
        "-s",
        "--skip-format",
        help="跳过指定格式的图片(jpg/png/webp)压缩,多个格式用逗号分隔",
    )
    parser.add_argument(
        "-k",
        "--remove-original",
        action="store_true",
        help="移除原始文件(如果压缩后的格式和原格式不同时,保留源文件,但如果压缩前后格式相同且在同一目录下,则源文件会被覆盖)",
    )
    parser.add_argument(
        "-F",
        "--fake-format",
        action="store_true",  # 默认不启用,指定此参数启用fake-format
        help="假装输出格式与输入格式相同,但实际上输出的是空白图片,用于测试压缩效果",
    )
    parser.add_argument(
        "-W",
        "--fake-format-from-webp",
        action="store_true",  # 默认不启用,指定此参数启用fake-format-from-webp
    )
    parser.add_argument(
        "-p",
        "--process-when-size-reduced",
        action="store_true",
        help="当图片大小减少时才保留压缩结果",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="显示详细输出")
    return parser.parse_args()


def main():
    """命令行入口"""
    args = parse_args()
    setup_logging(args.verbose)
    skip_format = args.skip_format or ""
    print(f"type:{type(skip_format)};value:[{skip_format}]")
    compressor = ImageCompressor(
        compress_threshold=args.compress_threshold,
        quality_rule=args.quality_rule,
        skip_format=skip_format,
        remove_original=args.remove_original,
        fake_format=args.fake_format,
        fake_format_from_webp=args.fake_format_from_webp,
        process_when_size_reduced=args.process_when_size_reduced,
    )
    fmt = args.format or ""
    print(f"type:{type(fmt)};value:[{fmt}]")
    try:
        # 分两种情况处理input(文件或目录),以决定调用单处理还是批处理
        if os.path.isfile(args.input):
            # 单文件处理(压缩完一个图片后就退出程序exit)
            # output_path = (
            #     args.output or os.path.splitext(args.input)[0] + f".{args.format}"
            # )
            output_path = ""
            if os.path.isfile(args.output or ""):
                output_path = args.output

            success, _ = compressor.compress_image(
                args.input,
                output_path,
                output_format=fmt,
                quality=args.quality,
                optimize=args.optimize,
                keep_exif=args.keep_exif,
                overwrite=args.overwrite,
            )
            # print(_)
            sys.exit(0 if success else 1)
        elif os.path.isdir(args.input):
            # 批量处理
            # output = args.output.strip(".").rstrip("/")
            output = args.output
            out_dir = output or args.input
            if not output:
                # print("!批量处理时必须指定输出目录", file=sys.stderr)
                # sys.exit(1)
                print(f"批量处理没有指定输出目录🎈,使用默认目录{out_dir}")

            results = compressor.batch_compress(
                input_dir=args.input,
                output_dir=out_dir,
                output_format=fmt,
                quality=args.quality,
                max_workers=args.max_workers,
                overwrite=args.overwrite,
            )
            print("\n批量处理结果:")
            results.get_report()

        else:
            print(f"错误: 输入路径不存在 {args.input}", file=sys.stderr)
            sys.exit(1)
    except Exception as e:
        print(f"发生错误: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
