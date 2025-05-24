"""
图片压缩与转换模块
详情查看Readme@ImgCompresser
功能摘要:
支持PNG、JPG压缩和WEBP格式转换
通常将jpg,png转换为webp会有较好的效果，尤其是png->webp的效果最明显
支持命令行参数调用和程序化调用

"""

import argparse
import logging
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Optional, Tuple
from PIL import Image

QUALITY_DEFAULT = 80
QUALITY_DEFAULT_STRONG = 20
COMPRESS_TRHESHOLD_KB = 0  # 只对指定大小以上的图片文件进行压缩(取值为0时全部压缩)

K = 2**10
COMPRESS_TRHESHOLD_B = COMPRESS_TRHESHOLD_KB * K
COMPRESS_TRHESHOLD = COMPRESS_TRHESHOLD_B
DEFAULT_QUALITY_RULE = "0,50,70 ; 50,200,40 ; 200,10000,20"


class ImageCompressor:
    """
    图片压缩与转换工具类

    功能:
    - 压缩PNG图片(支持无损和有损压缩)
    - 压缩JPG图片(调整质量参数)
    - 转换为WEBP格式(支持质量调整)
    - 自动保持EXIF信息
    - 批量处理支持(多线程)
    - 命令行支持

    示例用法:
    >>> compressor = ImageCompressor()
    >>> # 单文件压缩
    >>> compressor.compress_image("input.jpg", "output.webp", quality=85)
    >>> # 批量压缩
    >>> results = compressor.batch_compress("./images", "./compressed", "webp")
    """

    def __init__(
        self,
        compress_threshold=COMPRESS_TRHESHOLD,
        quality_rule="",
        logger=None,
        skip_format="",
    ):
        """
        初始化压缩器

        Args:
            logger: 可选的日志记录器
        """
        self.logger = logger or logging.getLogger(__name__)
        self._compress_threshold = compress_threshold
        # self.compress_threshold = compress_threshold
        self.quality_rule = quality_rule  # 用于不同大小区间的质量规则
        self.skip_format = skip_format.lower().split(",")

    @property
    def compress_threshold(self):
        """返回字节压缩阈值"""
        return self._compress_threshold * K

    def compress_image(
        self,
        input_path: str,
        output_path: str = "",
        output_format: str = "",
        quality: int = QUALITY_DEFAULT,
        quality_for_small_file: int = 70,
        optimize: bool = True,
        keep_exif: bool = True,
        overwrite: bool = False,
    ) -> Tuple[bool, str]:
        """
        压缩或转换图片

        Args:
            input_path: 输入图片路径
            output_path: 输出图片路径(可选)
            output_format: 输出格式(webp/jpg/png, 可选)
            quality: 压缩质量(1-100);如果初始化ImageCompressor时设置了quality_rule或compress_threshold,则此参数会被部分情况或完全被覆盖
            optimize: 是否启用优化
            keep_exif: 是否保留EXIF信息
            overwrite: 是否覆盖已存在文件

        Returns:
            (成功状态, 消息)
        """
        try:
            if not os.path.exists(input_path):
                return False, f"输入文件不存在: {input_path}"
            input_format = os.path.splitext(input_path)[1].lower()
            if input_format.strip(".") in self.skip_format:
                msg = f"跳过格式: {input_format}|file:{input_path}"
                self.logger.info(msg)
                return True, msg

            # 验证是否需要执行压缩(过小不压缩或者用高quality微压)
            original_size = os.path.getsize(input_path)
            ct: int = self.compress_threshold  # 取0则不跳过(全部压缩)
            if self.quality_rule:
                quality = get_quality_from_rule(
                    rule=self.quality_rule,
                    size=original_size,
                    default_quality=QUALITY_DEFAULT_STRONG,
                )
            # debug(f"对比:{original_size} vs {ct}")
            elif ct and original_size < ct:
                msg = f"文件大小({original_size/1024:.2f}KB)过小,微压(quality={quality_for_small_file})"
                self.logger.info(msg)
                quality = quality_for_small_file
                # return True, msg
            # 验证质量参数
            quality = max(1, min(100, quality))

            with Image.open(input_path) as img:
                # 保留EXIF信息
                exif = img.info.get("exif") if keep_exif else None
                save_kwargs = {"quality": quality, "optimize": optimize}

                # 确定输出路径和格式(后续要根据目标格式做针对性处理)
                if not output_path and not output_format:
                    # 只提供输入路径的情况下,解析输入路径
                    output_path = input_path
                    output_format = input_format
                elif not output_path:
                    # 未提供输出路径(但是提供了输出格式)
                    base, _ = os.path.splitext(input_path)
                    output_path = f"{base}.{output_format.lower().lstrip('.')}"
                elif not output_format:
                    # 未提供输出格式(但是提供了输出路径)
                    output_format = os.path.splitext(output_path)[1].lower()
                else:
                    # 同时提供输出路径和格式
                    _, format_from_output_path = os.path.splitext(output_path)
                    ext1 = format_from_output_path.lower().lstrip(".")
                    ext2 = output_format.lower().lstrip(".")
                    if ext1 != ext2:
                        self.logger.error("同时提供输出路径和格式,格式矛盾:")
                        print(f"{ext1} vs {ext2}")
                        raise ValueError("输出路径中的格式和指定格式矛盾")

                # 检查输出文件是否已存在
                if os.path.exists(output_path) and not overwrite:
                    return (
                        False,
                        f"输出文件已存在,默认取消压缩: {output_path} (使用--overwrite覆盖)",
                    )

                # 格式特定参数
                if output_format == ".webp":
                    save_kwargs["method"] = 6  # 最高质量编码方法
                elif output_format == ".png":
                    save_kwargs["compress_level"] = 9  # 最高压缩级别
                elif output_format in (".jpg", ".jpeg"):
                    save_kwargs["progressive"] = True  # 渐进式JPEG

                if exif:
                    save_kwargs["exif"] = exif

                # 转换图像模式为兼容格式
                if output_format in (".jpg", ".jpeg", ".webp") and img.mode != "RGB":
                    img = img.convert("RGB")

                img.save(output_path, **save_kwargs)

            # 计算压缩结果

            new_size = os.path.getsize(output_path)
            ratio = (1 - new_size / original_size) * 100

            msg = (
                f"节省: {ratio:.2f}%"
                f"原始大小: {original_size/1024:.2f}KB, "
                f"压缩后: {new_size/1024:.2f}KB, "
                f"压缩成功: {input_path} -> {output_path}\n"
                f"压缩参数: quality={quality}"
            )

            self.logger.info(msg)
            return True, msg

        except Exception as e:
            error_msg = f"处理图片失败: {str(e)}"
            self.logger.error(error_msg)
            return False, error_msg

    def batch_compress(
        self,
        input_dir: str,
        output_dir: str = "",
        output_format: str = "webp",
        quality: int = QUALITY_DEFAULT,
        skip_existing: bool = True,
        max_workers: int = 10,
        overwrite: bool = False,
    ) -> Dict[str, int | List[str]]:
        """
        批量压缩目录中的图片(多线程版本)

        Args:
            input_dir: 输入目录
            output_dir: 输出目录
            output_format: 输出格式(webp/jpg/png)
            quality: 压缩质量(1-100)
            skip_existing: 是否跳过已存在的输出文件
            max_workers: 最大线程数
            overwrite: 是否覆盖已存在文件

        Returns:
            处理结果统计: {
                "total": 总文件数,
                "success": 成功数,
                "failed": 失败数,
                "skipped": 跳过数,
                "details": 详细结果列表
            }
        """
        results: Dict = {
            "total": 0,
            "success": 0,
            "failed": 0,
            "skipped": 0,
            "details": [],
        }

        if not os.path.exists(input_dir):
            raise FileNotFoundError(f"输入目录不存在: {input_dir}")

        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        supported_formats = (".jpg", ".jpeg", ".png", ".webp")

        def process_file(filename: str) -> Optional[Tuple[str, str]]:
            """内部函数"""
            if filename.lower().endswith(supported_formats):
                input_path = os.path.join(input_dir, filename)
                base_name = os.path.splitext(filename)[0]
                output_filename = f"{base_name}.{output_format.lstrip('.')}"
                output_path = os.path.join(output_dir, output_filename)

                if skip_existing and os.path.exists(output_path) and not overwrite:
                    return "skipped", f"跳过已存在文件: {output_path}"

                success, msg = self.compress_image(
                    input_path,
                    output_path,
                    output_format=output_format,
                    quality=quality,
                    overwrite=overwrite,
                )
                return "success" if success else "failed", msg
            return None

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []
            for filename in os.listdir(input_dir):
                futures.append(executor.submit(process_file, filename))
                results["total"] += 1

            for future in as_completed(futures):
                result = future.result()
                if result:
                    status, msg = result
                    if status == "skipped":
                        results["skipped"] += 1
                    elif status == "success":
                        results["success"] += 1
                    else:
                        results["failed"] += 1
                    results["details"].append(msg)

        return results


def setup_logging(level=logging.INFO, log_file=None, log_format=None):
    """
    设置日志记录器。

    Args:
        level (int): 日志级别，
        例如logging.DEBUG, logging.INFO, logging.WARNING, logging.ERROR, logging.CRITICAL。

        log_file (str): 如果指定，则将日志输出到该文件；否则输出到控制台。

        log_format (str): 自定义日志格式。
    """
    logger = logging.getLogger()
    logger.setLevel(level)

    # 清除之前的处理器
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
        handler.close()

    # 设置默认的日志格式
    if log_format is None:
        log_format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"

    # 创建格式化器
    formatter = logging.Formatter(log_format)

    # 设置处理器
    if log_file is None:
        # 输出到控制台
        handler = logging.StreamHandler()
    else:
        # 输出到文件
        handler = logging.FileHandler(log_file)

    handler.setFormatter(formatter)
    logger.addHandler(handler)


def parse_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        description="图片压缩与转换工具",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("input", help="输入文件或目录路径")
    parser.add_argument("-o", "--output", help="输出文件或目录路径")
    parser.add_argument(
        "-f",
        "--format",
        choices=["webp", "jpg", "png"],
        default="webp",
        help="输出格式(webp/jpg/png)",
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
        "-r",
        "--quality-rule",
        type=str,
        default="",
        help="对不同大小图像区间采用不同的quality值的指定规则"
        "例如'50,200,40' 表示50到200KB区间的图片设置quality=70`,多个区间用分号(;)分隔\n 如果使用 `auto`则使用内部的推荐值 ",
    )
    parser.add_argument(
        "-s",
        "--skip-format",
        default="",
        help="跳过指定格式的图片(jpg/png/webp)压缩,多个格式用逗号分隔",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="显示详细输出")
    return parser.parse_args()


def get_quality_from_rule(rule, size, default_quality=20):
    """
    解析规则字符串，返回对应尺寸的质量参数。

    参数:
        rule (str): 规则字符串，如 "50,100,40;100,200,30"
            其中每个区间用分号分隔，每个区间由三个整数组成，分别表示区间最小值，区间最大值，和对应的质量值。
            如 "50,100,40;100,200,30" 表示 50KB~100KB 区间的图片质量为40，100KB~200KB 区间的图片质量为30。
        size (int): 要查询的尺寸
        default_quality (int): 默认质量值，若未匹配到任何规则则返回此值

    返回:
        int: 对应的质量值
    """
    if not rule or not isinstance(rule, str):
        return default_quality
    if rule.lower() == "auto":
        rule = DEFAULT_QUALITY_RULE
    q = default_quality
    try:
        for segment in rule.split(";"):
            segment = segment.strip()
            if not segment:
                continue
            parts = segment.split(",")
            if len(parts) != 3:
                continue
            range_min, range_max, quality = map(int, parts)
            range_min, range_max = range_min * K, range_max * K
            # range_min <= size and size < range_max
            if range_min <= size < range_max:
                q = quality
                print(f"规则解析: [{range_min}, {range_max}],size:{size} 质量: {q}")

    except ValueError as e:
        print(f"规则解析错误: {e}")
    return q


def main():
    """命令行入口"""
    args = parse_args()
    setup_logging(args.verbose)
    compressor = ImageCompressor(
        compress_threshold=args.compress_threshold,
        quality_rule=args.quality_rule,
        skip_format=args.skip_format,
    )

    try:
        # 分两种情况处理input(文件或目录),以决定调用单处理还是批处理
        if os.path.isfile(args.input):
            # 单文件处理
            output_path = (
                args.output or os.path.splitext(args.input)[0] + f".{args.format}"
            )
            success, msg = compressor.compress_image(
                args.input,
                output_path,
                output_format=args.format,
                quality=args.quality,
                optimize=args.optimize,
                keep_exif=args.keep_exif,
                overwrite=args.overwrite,
            )
            print(msg)
            sys.exit(0 if success else 1)
        elif os.path.isdir(args.input):
            # 批量处理
            out_dir = args.output or os.path.join(args.input, "compressed")
            if not args.output:
                # print("!批量处理时必须指定输出目录", file=sys.stderr)
                # sys.exit(1)
                print(f"批量处理没有指定输出目录,使用默认目录{out_dir}")

            results = compressor.batch_compress(
                args.input,
                out_dir,
                output_format=args.format,
                quality=args.quality,
                skip_existing=not args.overwrite,
                max_workers=args.max_workers,
                overwrite=args.overwrite,
            )
            print("\n批量处理结果:")
            print(f"总文件数: {results['total']}")
            print(f"成功: {results['success']}")
            print(f"失败: {results['failed']}")
            print(f"跳过: {results['skipped']}")
            sys.exit(0 if results["failed"] == 0 else 1)
        else:
            print(f"错误: 输入路径不存在 {args.input}", file=sys.stderr)
            sys.exit(1)
    except Exception as e:
        print(f"发生错误: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
