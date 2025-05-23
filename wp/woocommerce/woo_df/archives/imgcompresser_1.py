"""
图片压缩与转换模块
支持PNG、JPG压缩和WEBP格式转换
通常将jpg,png转换为webp会有较好的效果,尤其是png->webp的效果最明显
但是jpg->png的转换效果不佳,png->jpg,jpg->jpg无法执行
同类型压缩png-png,也是有限的,如果启用optimize选项,如果图像本身不适合进一步优化，也不会有明显变化。
"""

import logging
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional, Tuple

from PIL import Image

# %%


class ImageCompressor:
    """
    图片压缩与转换工具类

    功能:
    - 压缩PNG图片(支持无损和有损压缩)
    - 压缩JPG图片(调整质量参数)
    - 转换为WEBP格式(支持质量调整)
    - 自动保持EXIF信息
    - 批量处理支持

    示例用法:
    >>> compressor = ImageCompressor()
    >>> compressor.compress_image("input.jpg", "output.webp", quality=85)
    """

    def __init__(self, logger: Optional[logging.Logger] = None):
        """
        初始化压缩器

        Args:
            logger: 可选的日志记录器
        """
        self.logger = logger or logging.getLogger(__name__)

    def compress_image(
        self,
        input_path: str,
        output_path: str = "",
        output_format: str = "",
        quality: int = 20,
        optimize: bool = True,
        keep_exif: bool = False,
    ) -> Tuple[bool, str]:
        """
        压缩或转换图片

        Args:
            input_path: 输入图片路径
            output_path: 输出图片路径(会分词此路径扩展名,来决定输出文件的格式)
            quality: 压缩质量(1-100)
            optimize: 是否启用优化
            keep_exif: 是否保留EXIF信息

        Returns:
            (成功状态, 消息)
        """
        try:
            if not os.path.exists(input_path):
                return False, f"输入文件不存在: {input_path}"

            with Image.open(input_path) as img:
                # 保留EXIF信息
                exif = img.info.get("exif") if keep_exif else None
                save_kwargs = {"quality": quality, "optimize": optimize}

                # 确认输出格式
                # 如果用户没有指定输出路径,但是指定了输出格式,则根据输入文件名和格式生成输出路径
                if not output_path and output_format:
                    filebasename, origin_format = os.path.splitext(input_path)
                    output_format = output_format.lower()
                    output_path = filebasename + output_format
                    print(f"output_path: {output_path}")
                    print(f"format change:{origin_format}->{output_format}")

                elif not output_path and not output_format:
                    print(ValueError("未指定输出路径或格式,原地压缩覆盖原文件"))
                    output_path = input_path

                if output_format == ".webp":
                    save_kwargs["method"] = 6  # 默认使用最高质量的编码方法
                elif output_format == ".png":
                    save_kwargs["compress_level"] = 9  # 最高压缩级别
                elif output_format == ".jpg" or output_format == ".jpeg":
                    # 优化JPG压缩效果
                    save_kwargs["progressive"] = True  # 启用渐进式模式
                    save_kwargs["quality"] = max(
                        1, min(quality, 100)
                    )  # 限制quality范围，避免过低或过高

                if exif:
                    save_kwargs["exif"] = exif
                # 根据前面计算(调整)的参数做图片压缩和保存处理
                img.save(output_path, **save_kwargs)

            original_size = os.path.getsize(input_path)
            new_size = os.path.getsize(output_path)
            ratio = (1 - new_size / original_size) * 100

            msg = (
                f"压缩成功: {input_path} -> {output_path}\n"
                f"原始大小: {original_size/1024:.2f}KB, "
                f"压缩后: {new_size/1024:.2f}KB, "
                f"节省: {ratio:.2f}%"
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
        output_dir: str,
        output_format: str = "webp",
        quality: int = 20,
        skip_existing: bool = True,
        max_workers: int = 10,
    ) -> dict:
        """
        批量压缩目录中的图片(多线程版本)

        Args:
            input_dir: 输入目录
            output_dir: 输出目录
            output_format: 输出格式(webp/jpg/png)
            quality: 压缩质量
            skip_existing: 是否跳过已存在的输出文件
            max_workers: 最大线程数

        Returns:
            处理结果统计
        """
        results = {"total": 0, "success": 0, "failed": 0, "skipped": 0, "details": []}

        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        supported_formats = (".jpg", ".jpeg", ".png")

        def process_file(filename, task_id=0):
            print(f"task_id:{task_id} processing {filename}...")
            if filename.lower().endswith(supported_formats):
                input_path = os.path.join(input_dir, filename)
                output_filename = f"{os.path.splitext(filename)[0]}.{output_format}"
                output_path = os.path.join(output_dir, output_filename)

                if skip_existing and os.path.exists(output_path):
                    return "skipped", f"跳过已存在文件: {output_path}"

                success, msg = self.compress_image(
                    input_path, output_path, quality=quality
                )
                return "success" if success else "failed", msg
            return None

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = []
            filenames = os.listdir(input_dir)
            for task_id, filename in enumerate(filenames):
                # print(f"task_id:{idx} start...")
                futures.append(executor.submit(process_file, filename, task_id))
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


def setup_logging():
    """配置日志记录"""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        handlers=[
            logging.FileHandler("image_compression.log"),
            logging.StreamHandler(),
        ],
    )


if __name__ == "__main__":
    # 示例用法
    setup_logging()
    compressor = ImageCompressor()

    # 单文件压缩示例
    # compressor.compress_image('S:/imgs_demo/', 'xoutput.webp', quality=20)

    # 批量压缩示例
    # results = compressor.batch_compress(
    #     # input_dir='./images',
    #     input_dir=r"S:/imgs_demo/",
    #     output_dir="./compressed",
    #     output_format="webp",
    #     skip_existing=False,
    #     quality=20,
    #     max_workers=10,
    # )
    # print(f"批量处理结果: {results}")
