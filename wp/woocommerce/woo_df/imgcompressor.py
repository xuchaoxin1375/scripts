"""
图片压缩与转换模块
详情查看Readme@Imgcompressor
功能摘要:
支持PNG、JPG压缩和WEBP格式转换
通常将jpg,png转换为webp会有较好的效果，尤其是png->webp的效果最明显
支持命令行参数调用和程序化调用

"""

# %%

import logging
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from io import BytesIO

# from wand.image import Image as WandImage
from PIL import Image, ImageFile

# import pillow_avif  # 启用 AVIF 支持必须导入,太新的python版本可能安装不上库(不需要显式调用,导入即可) # noqa: F401  pylint: disable=unused-import
from comutils import get_paths, SUPPORT_IMAGE_FORMATS_NAME
from operationlogger import OperationLogger
from pathsize import format_size, get_size

# 启用pillow基本的容错开关
ImageFile.LOAD_TRUNCATED_IMAGES = True
Image.MAX_IMAGE_PIXELS = int(
    1e10
)  # 允许处理最大10B=100亿像素的图片(默认只支持1.7亿左右的像素)
QUALITY_DEFAULT = 70
QUALITY_DEFAULT_STRONG = 30

# 只对指定大小以上的图片文件进行压缩(取值为0时全部压缩)
K = 2**10
# 直观的KB单位指定(默认0则处理所有大小的图片)
COMPRESS_TRHESHOLD_KB = 0
# 转换为默认的字节单位
COMPRESS_TRHESHOLD_B = COMPRESS_TRHESHOLD_KB * K
COMPRESS_TRHESHOLD = COMPRESS_TRHESHOLD_B

# 默认的quality规则
DEFAULT_QUALITY_RULE = "0,50,75 ; 50,200,40 ; 200,10000,30"
# image extension / format names

SUPPORT_IMAGE_FORMATS = ["." + f for f in SUPPORT_IMAGE_FORMATS_NAME]
# COMPRESS_FOR_FORMATS = map(lambda f: "." + f, COMPRESS_FOR_FORMATS_NAME)

# logger = logging.getLogger("ImageDownloader.imgcompressor")
logger = logging.getLogger(__name__)
debug = logger.debug
info = logger.info
warning = logger.warning
error = logger.error
critical = logger.critical
##


class ImageCompressorLogger(OperationLogger):
    """图片压缩日志记录器
    添加了图片路径(目录)压缩前后的大小计算和报告
    """

    def __init__(self):
        super().__init__()
        self.size_before = 0
        self.size_after = 0

    def get_size(self, path):
        """计算规定路径(文件或目录占用的磁盘大小)"""
        self.size_before = os.path.getsize(path)
        return self.size_before

    def get_size_changed(self, path):
        """计算此轮压缩节约的空间大小"""
        self.size_after = os.path.getsize(path)
        return self.size_after - self.size_before

    def init_status(self, path):
        """初始化压缩前后大小记录(对于多个目录压缩分别统计size变换的情况很有用)"""
        super().init_status()
        self.size_before = os.path.getsize(path)
        self.size_after = self.size_before

    def end(self):
        """结束压缩记录"""
        summary = super().end()
        if self.size_before and self.size_after:
            size_changed = self.size_after - self.size_before
            size_changed_percent = (size_changed / self.size_before) * 100
            summary = {
                **summary,
                "size_before": format_size(self.size_before),
                "size_after": format_size(self.size_after),
                "size_changed": size_changed,
                "size_changed_percent": f"{size_changed_percent:.2f}%",
            }
        return summary


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
        fake_format=False,
        fake_format_from_webp=False,
        compress_for_format=SUPPORT_IMAGE_FORMATS_NAME,
        remove_original=False,
        process_when_size_reduced=True,
        recurse=False,
        resize_threshold=None,
        skip_truncated_image=False,
    ):
        """
        初始化压缩器

        Args:
            logger: 可选的日志记录器
            compress_threshold: 压缩阈值(单位:KB)
            quality_rule: 质量规则(格式: "size_range_min1,size_range_max1,
                quality1;size_range_min2,size_range_max2,quality2;...")
            skip_format: 需要跳过处理的图片格式(jpg/png/webp/...)
            fake_format:处理后的图片如果体积不减小,是否丢弃处理结果,直接修改原图后缀
            fake_format_from_webp: 是否将图片压缩成webp,然后将文件后缀名改为指定的格式名(考虑到图片压缩到webp压缩效果好,而且浏览器不会应为图片的格式后缀和真实格式不一致而渲染不出来,可以考虑此选项节约空间)
            remove_original: 是否移除原始文件
            resize_threshold: 分辨率阈值(宽, 高)，超过该阈值的图片将被缩小;放空不做分辨率调整
            skip_truncated_image: 是否跳过截断(破损或不完整)的图片(默认不跳尽可能处理)
        """
        self.logger = logger or logging.getLogger(__name__)
        self._compress_threshold = compress_threshold
        # self.compress_threshold = compress_threshold
        self.quality_rule = quality_rule  # 用于不同大小区间的质量规则
        self.skip_format_names = (skip_format or "").lower().split(",")
        self.remove_original = remove_original  # 是否尽可能移除原始文件
        # 仅压缩列出的格式的图片,如果为空,则压缩可能受支持的图片
        self.compress_for_format = compress_for_format
        self.fake_format = fake_format
        self.fake_format_from_webp = fake_format_from_webp
        self.process_when_size_reduced = process_when_size_reduced
        # self.opl = OperationLogger()
        self.opl = ImageCompressorLogger()
        self.recurse = recurse

        if skip_truncated_image:
            ImageFile.LOAD_TRUNCATED_IMAGES = False
        self.resize_threshold = resize_threshold

        # self.opl.init_status()
        self.opl.start()
        info(f"压缩白名单: {self.compress_for_format}")
        # self.logger.propagate = False
        self.logger.info(f"[{__name__}]当前日志处理器:{logger.handlers}")  # type: ignore

    @property
    def compress_threshold(self):
        """返回字节压缩阈值
        单位是字节数(B)
        例如1KB则返回1024
        """
        return self._compress_threshold * K

    def compress_image(
        self,
        input_path: str,
        output_path: str = "",
        output_format: str = "",
        quality: int = QUALITY_DEFAULT,
        optimize: bool = False,
        keep_exif: bool = True,
        overwrite: bool = False,
        resize_compensate_quality=5,
    ):
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
        opl = self.opl
        try:
            if not os.path.exists(input_path):
                return False, f"输入文件不存在: {input_path}"
            self.logger.info(f"开始压缩: {[input_path]}")
            _, input_format = os.path.splitext(input_path)
            # input_format = os.path.splitext(input_path)[1].lower()
            input_format_name = input_format.lower().strip(".")
            self.logger.debug(f"输入格式:{input_format}")

            if self.compress_for_format:
                if input_format_name not in self.compress_for_format:
                    msg = f"不在白名单的格式,跳过: {input_format}|file:{input_path}"
                    self.logger.debug(msg)
                    opl.log_skip()
                    return True, msg
            if input_format_name in self.skip_format_names:
                msg = f"跳过格式: {input_format}|file:{input_path}"
                self.logger.debug(msg)
                opl.log_skip()
                return True, msg

            original_size = os.path.getsize(input_path)
            self.logger.debug(f"原始文件大小: {original_size}")
            ct: int = self.compress_threshold  # 取0则不跳过(全部压缩)
            if ct and original_size < ct:
                msg = f"文件大小({format_size(original_size)})小于压缩阈值({format_size(ct)}),跳过: {input_path}"
                self.logger.info(msg)
                opl.log_skip()
                return True, msg
            # 计算最终的输出路径字符串
            output_path = self._get_output_path(
                input_path=input_path,
                output_path=output_path,
                output_format=output_format,
            )
            info(f"输出文件: {output_path}")
            # self.logger.info(f"输出文件: {output_path}🎈")
            output_base, output_format = os.path.splitext(output_path)
            output_format_name = output_format.lower().strip(".")
            self.logger.debug(f"输出格式:{output_format}")
            # 检查输出文件是否已存在
            if os.path.exists(output_path):
                # 不要急着在这里删除文件,否则后续文件操作没有文件可用
                if not overwrite:
                    opl.log_skip()
                    msg = f"[⚠️]输出文件已存在,默认取消压缩: {output_path} (使用-O/--overwrite覆盖)"

                    self.logger.warning(msg)
                    return (False, msg)
            # return
            with Image.open(input_path) as img:
                # 保留EXIF信息
                exif = img.info.get("exif") if keep_exif else None

                # 按需调整分辨率
                img, old_wh, new_wh = self.resize_resolution(img)

                # 转换图像模式为兼容格式
                # if output_format in (".jpg", ".jpeg", ".webp") and img.mode != "RGB":
                if output_format in (".jpg", ".jpeg") and img.mode != "RGB":
                    img = img.convert("RGB")
                # 为了检测分辨率调整膨胀变化,先保存到临时文件(后缀要保留)
                if self.fake_format_from_webp:
                    output_format_name = "webp"
                temp_output_path = f"{output_base}.tmp.{output_format_name}"
                self.logger.debug(f"临时文件: {temp_output_path}")

                resized_file_size = 0
                need_resize = old_wh != new_wh
                if need_resize:
                    self.logger.debug(
                        f"分辨率变化:{old_wh}->{new_wh} ; 分辨率限制:{self.resize_threshold}"
                    )
                    # 保存临时图片以便计算调整分辨率后的大小,从而分配quality参数
                    # 硬盘方案:先保存临时文件到硬盘,然后计算大小
                    # img.save(temp_output_path)
                    # resized_file_size = os.path.getsize(temp_output_path)

                    # 内存方案:保存临时文件到内存中,避免重复读写硬盘
                    # 特殊处理JPG格式
                    # if output_format_name.lower() in ("jpg", "jpeg"):
                    #     save_kwargs["subsampling"] = 0  # 无损压缩
                    buffer = BytesIO()
                    # 将img流保存到临时的buffer中,再额外指定format
                    # debug
                    debug(f"格式: {output_format_name}")
                    # 规范jpg名字为jpeg(PIL库的需要)
                    if output_format_name == "jpg":
                        output_format_name = "jpeg"
                    img.save(buffer, format=output_format_name)
                    resized_file_size = buffer.tell()  # 获取内存缓冲区大小

                    # buffer.close()  # 清理内存

                    self.logger.debug(
                        f"降分辨率前后的文件大小变化: {format_size(original_size)}->{format_size(resized_file_size)}"
                    )
                    # self.logger.debug(f"估算文件大小: {original_size} bytes")
                # 确定最终的quality(依赖于最新的文件大小评估,尤其是分辨率变化后)
                # quality = self._get_quality(
                #     quality,
                #     quality_for_small_file=quality_for_small_file,
                #     original_size=resized_file_size or original_size,
                # )
                resized_file_size = resized_file_size or original_size

                if self.quality_rule:
                    quality = get_quality_from_rule(
                        rule=self.quality_rule,
                        # size=original_size,
                        size=resized_file_size,
                        default_quality=QUALITY_DEFAULT_STRONG,
                    )
                # 一般缩小分辨率后,quality需要基于规则适当提高
                if need_resize:
                    new_quality = quality + resize_compensate_quality
                    self.logger.debug(
                        f"补偿quality调整: {quality}+{resize_compensate_quality}={new_quality}"
                    )
                    quality = new_quality
                # 参数设定
                save_kwargs = self._get_compress_args(
                    img=img,
                    output_format=output_format,
                    quality=quality,
                    optimize=optimize,
                    exif=exif,
                )

                # 根据最终确定的参数,保存更改的图片🎈
                # 先尝试pillow库,如果失败尝试Wand库处理
                img.save(temp_output_path, **save_kwargs)

                self.logger.info(f"保存临时文件: {temp_output_path}")

                output_format_name = output_format.strip(".")
                debug(
                    f"存储模式:remove_original:{self.remove_original} \
格式变化: {input_format_name} -> {output_format_name}"
                )

            # 计算压缩结果
            msg = ""
            new_size = os.path.getsize(filename=temp_output_path)
            expand = new_size >= original_size
            size_trend = "+" if expand else "-"
            icon_trend = "🔼" if expand else "✅"
            if self.process_when_size_reduced and expand:
                # 不需要处理图片的情况
                # 移除临时文件🎈
                os.remove(temp_output_path)
                opl.log_skip()
                # 根据需要做图片后缀更改,不覆盖原文件
                fake_format = self.fake_format
                if input_format_name != output_format_name and fake_format:
                    debug("仅更改源文件(input_path)的后缀格式,而不做实际转换")
                    debug(f"格式文件变化:{input_path}->{output_path}")
                    os.rename(input_path, output_path)
                msg = f" 🟰  压缩后文件大小未减少,不覆盖原文件(大小变化:{original_size}->{new_size})"
                debug(msg)
            else:
                # 需要替换源文件的情况
                if not expand:
                    # 理想情况:处理后的文件体积变小
                    debug(f"处理后的文件体积变小,覆盖原文件: {output_path}")
                else:
                    debug("不关心体积变化,执行压缩")
                ratio = (new_size / original_size - 1) * 100
                msg_segs = (
                    icon_trend,
                    f"体积变化({size_trend}): {ratio:.2f}%",
                    f"原始大小: {original_size/1024:.2f}KB, ",
                    f"压缩后: {new_size/1024:.2f}KB, ",
                    f"压缩成功: {input_path} -> {output_path}",
                    f"压缩参数: quality={quality}",
                    f"分辨率变化:{old_wh}->{new_wh} ; 分辨率限制:{self.resize_threshold}",
                )
                msg = " ".join(msg_segs)

                # if self.remove_original and input_format_name != output_format_name:
                self.process_after_compressed(
                    input_path, output_path, overwrite, temp_output_path
                )

                self.logger.info(msg)
                opl.log_success()
            # 检查 tmp 文件是否存在,如果存在,删除(安全语句)
            if os.path.exists(temp_output_path):
                os.remove(temp_output_path)

            return True, msg

        except Exception as e:
            error_msg = f"处理图片失败: {str(e)}"
            self.logger.error(error_msg)
            opl.log_failure(item=input_path, error=error_msg)
            return False, error_msg

    def resize_resolution(self, img: Image.Image):
        """按需调整图像分辨率"""
        old_wh = img.size
        new_wh = old_wh
        if self.resize_threshold:
            # self.logger.debug(f"type of resize_threshold: {type(self.resize_threshold)}")
            max_width, max_height = self.resize_threshold
            width, height = img.size
            if width > max_width or height > max_height:
                # 按比例缩小图片
                # 分别计算宽度和高度需要收缩的比例,然后取较小值作为最终的等比例缩小因子
                ratio = min(max_width / width, max_height / height)
                new_wh = (int(width * ratio), int(height * ratio))
                # 调用resize方法调整图片分辨率
                img = img.resize(new_wh, Image.Resampling.LANCZOS)
                self.logger.debug(f"调整分辨率: {img.size}")
                # 计算缩小分辨率后的图片大小

        return img, old_wh, new_wh

    def process_after_compressed(
        self, input_path, output_path, overwrite, temp_output_path
    ):
        """根据需要移除原始文件等操作🎈"""
        if self.remove_original:
            os.remove(input_path)
            debug(f"删除原始文件: {input_path}")
            # 将临时文件重命名为输出文件🎈
        if overwrite:
            if os.path.exists(output_path):
                os.remove(output_path)
                # 重名名时,参数dst直接使用前面计算好的output_path,而不是再构造output_path

        os.rename(src=temp_output_path, dst=output_path)

    def _get_compress_args(self, img, output_format, quality, optimize, exif):
        save_kwargs = {"quality": quality, "optimize": optimize}

        # output_format = output_format or ""

        # 格式特定参数
        # debug(f"输出格式: {output_format}🎈")
        if output_format == ".webp":
            save_kwargs["method"] = 6  # 最高质量编码方法
        elif output_format == ".png":
            save_kwargs["compress_level"] = 9  # 最高压缩级别
        elif output_format in (".jpg", ".jpeg"):
            save_kwargs["progressive"] = True  # 渐进式JPEG
        if output_format in (".png", ".webp") and img.mode in ("RGBA", "LA"):
            save_kwargs["transparency"] = img.info.get("transparency")

        if exif:
            save_kwargs["exif"] = exif
        return save_kwargs

    def _get_quality(self, quality, quality_for_small_file, original_size):
        """验证是否需要执行压缩(过小不压缩或者用高quality微压)"""
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
            # 验证质量参数
        quality = max(0, min(100, quality))
        return quality

    def _get_output_path(self, input_path: str, output_path: str, output_format):
        """
        确定输出格式和输出路径(后续要根据目标格式做针对性处理)

        注意:直接决定输出文件的格式的是output_path,如果用户传入output_format,最终也会通过拼接路径的方式体现在output_path的后缀上


        如果输出路径指定,则根据此值,解析并返回输出格式和输出路径
        如果输出路径没有指定:根据是否指定输出格式来判断
            1.指定输出格式,则文件名和输入路径同名,后缀改为输出格式
            2.没有指定输出格式,则使用输出路径和输入路径同名,后缀也一样

        """
        if output_path and output_format:
            # 同时提供输出路径和格式,格式一致则继续运行,否则报错
            debug(f"同时提供了输出路径和格式:[{output_path}] ,[{output_format}]")
            _, format_from_output_path = os.path.splitext(output_path)
            debug(f"🎈输出和格式:[{output_path}] ,[{output_format}]")
            ext1 = format_from_output_path.lower().lstrip(".")
            ext2 = output_format.lower().lstrip(".")
            if ext1 != ext2:
                self.logger.error("同时提供输出路径和格式,并且格式不一致(矛盾):")
                self.logger.info(f"{ext1} vs {ext2}")
                raise ValueError("输出路径中的格式和指定格式矛盾")

        elif output_format:
            # 提供了输出格式
            debug(f"仅提供了输出格式:[{output_format}]")
            base, _ = os.path.splitext(input_path)
            output_path = f"{base}.{output_format.lower().lstrip('.')}"
        elif output_path:
            # 提供了输出路径
            debug(f"仅提供了输出路径:[{output_path}]")
        elif not output_path and not output_format:
            info("未提供输出路径和格式")
            output_path = input_path
        else:
            error("输出参数错误")
        return output_path

    def batch_compress(
        self,
        input_dir: str,
        output_dir: str = "",
        output_format: str = "",
        quality: int = QUALITY_DEFAULT,
        overwrite: bool = False,
        # skip_existing: bool = True,
        max_workers: int = 10,
    ):
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

        if not os.path.exists(input_dir):
            raise FileNotFoundError(f"输入目录不存在: {input_dir}")
        # 计算目录初始大小
        self.opl.size_before = get_size(input_dir)

        os.makedirs(output_dir, exist_ok=True)

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []
            files = []

            files = get_paths(input_dir=input_dir, recurse=self.recurse)

            # for filename in os.listdir(input_dir):
            for input_path in files:
                if input_path.lower().endswith(SUPPORT_IMAGE_FORMATS_NAME):

                    output_format_name, output_path = self._get_output_info(
                        output_dir=output_dir,
                        output_format=output_format,
                        input_path=input_path,
                    )
                    futures.append(
                        executor.submit(
                            self.compress_image,
                            input_path=input_path,
                            output_path=output_path,
                            output_format=output_format_name,
                            quality=quality,
                            overwrite=overwrite,
                        )
                    )

            for future in as_completed(futures):
                future.result()
        self.opl.size_after = get_size(input_dir)
        return self.opl

    def _get_output_info(self, output_dir, output_format, input_path):
        """确定输出格式和输出路径(适用于压缩包含图片的目录的情况)

        Args:
            output_dir: 输出目录
            output_format: 输出格式(webp/jpg/png)
            input_path: 输入路径

        Returns:
            output_format_name: 输出格式名称
            output_path: 输出路径
        """
        base_name, input_format = os.path.splitext(input_path)

        # output_format = output_format or input_format
        output_format_now = output_format or input_format
        output_format_name = output_format_now.lower().lstrip(".")

        output_filename = f"{base_name}.{output_format_name}"
        output_path = os.path.join(output_dir, output_filename)
        output_path = os.path.abspath(output_path)
        debug(
            f"格式信息预设: [{input_format} -> {output_format_now}];"
            f"{input_path}->{output_path}"
        )

        return output_format_name, output_path


def setup_logging(level=logging.INFO, log_file=None, log_format=None):
    """
    设置日志记录器。

    Args:
        level (int): 日志级别，
        例如logging.DEBUG, logging.INFO, logging.WARNING, logging.ERROR, logging.CRITICAL。

        log_file (str): 如果指定，则将日志输出到该文件；否则输出到控制台。

        log_format (str): 自定义日志格式。
    """
    # logger = logging.getLogger()
    logger.setLevel(level)

    # 清除之前的处理器
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
        handler.close()

    # 设置默认的日志格式
    if log_format is None:
        log_format = "%(asctime)s ~~ %(name)s - %(levelname)s - %(message)s"

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
                debug(f"规则解析: [{range_min}, {range_max}],size:{size} 质量: {q}")

    except ValueError as e:
        error(f"规则解析错误: {e}")
    return q


if __name__ == "__main__":
    # main()
    print("Welcome to use imgcompressor!")
