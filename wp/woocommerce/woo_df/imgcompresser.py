"""
图片压缩与转换模块
详情查看Readme@ImgCompresser
功能摘要:
支持PNG、JPG压缩和WEBP格式转换
通常将jpg,png转换为webp会有较好的效果，尤其是png->webp的效果最明显
支持命令行参数调用和程序化调用

"""

import argparse
import sys
import logging
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Optional, Tuple
from PIL import Image

QUALITY_DEFAULT = 70
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
        remove_original=False,
    ):
        """
        初始化压缩器

        Args:
            logger: 可选的日志记录器
            compress_threshold: 压缩阈值(单位:KB)
            quality_rule: 质量规则(格式: "size_range_min1,size_range_max1,
                quality1;size_range_min2,size_range_max2,quality2;...")
            skip_format: 跳过格式(jpg/png/webp)
            remove_original: 是否移除原始文件
        """
        self.logger = logger or logging.getLogger(__name__)
        self._compress_threshold = compress_threshold
        # self.compress_threshold = compress_threshold
        self.quality_rule = quality_rule  # 用于不同大小区间的质量规则
        self.skip_format_name = (skip_format or "").lower().split(",")
        self.remove_original = remove_original  # 是否尽可能移除原始文件

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
            quality: 压缩质量(1-100);
                如果初始化ImageCompressor时设置了quality_rule或compress_threshold,则此参数会被部分情况或完全被覆盖
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
            input_format_name = input_format.strip(".")
            if input_format_name in self.skip_format_name:
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

                # output_format = output_format or ""

                # 确定输出格式和输出路径(后续要根据目标格式做针对性处理),如果传入的参数缺失值的话
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
                    # 同时提供输出路径和格式,格式一致则继续运行,否则报错
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
                output_format_name = output_format.strip(".")
                print(
                    f"存储模式:remove_original:{self.remove_original} \
格式变化: {input_format_name} -> {output_format_name}"
                )
                if self.remove_original and input_format_name != output_format_name:
                    os.remove(input_path)
                    print(f"删除原始文件: {input_path}")

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
        overwrite: bool = False,
        # skip_existing: bool = True,
        max_workers: int = 10,
    ) -> Dict[str, int | List[str]]:
        """
        批量压缩目录中的图片(多线程版本)

        Args:
            input_dir: 输入目录
            output_dir: 输出目录
            output_format: 输出格式(webp/jpg/png)
            quality: 压缩质量(1-100)
            overwrite: 是否覆盖已存在文件
            max_workers: 最大线程数

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

                if os.path.exists(output_path) and not overwrite:
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


if __name__ == "__main__":
    # main()
    print("Welcome to use imgcompresser!")
