"""文件名处理模块
用于对从url下载的文件,生成或补全文件名(扩展名)
"""

import hashlib
import mimetypes
import os
import re
from logging import debug, warning, error
from urllib.parse import unquote, urlparse
import requests
import magic


class FileNameHandler:
    """文件名(扩展名)处理器"""

    def __init__(self):
        # 使用 session 实现连接复用
        self.session = requests.Session()

    # 类属性
    MIME_TO_EXT = {
        # 图片格式（新增和完善部分）
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/gif": ".gif",
        "image/webp": ".webp",
        "image/svg+xml": ".svg",
        "image/tiff": ".tiff",
        "image/bmp": ".bmp",
        "image/x-icon": ".ico",
        "image/vnd.microsoft.icon": ".ico",
        "image/heic": ".heic",
        "image/heif": ".heif",
        "image/avif": ".avif",
        "image/jp2": ".jp2",
        "image/jpx": ".jpx",
        "image/jpm": ".jpm",
        "image/apng": ".apng",
        # 原有其他格式保持不变
        "application/pdf": ".pdf",
        "application/msword": ".doc",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
        "application/vnd.ms-excel": ".xls",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": ".xlsx",
        "text/plain": ".txt",
        "text/csv": ".csv",
        "application/zip": ".zip",
        "application/x-rar-compressed": ".rar",
        "application/x-7z-compressed": ".7z",
        "application/x-tar": ".tar",
        "application/gzip": ".gz",
        "audio/mpeg": ".mp3",
        "video/mp4": ".mp4",
        "application/json": ".json",
        "application/xml": ".xml",
        # 可以继续添加更多映射
    }

    @staticmethod
    def get_file_extension_from_mime(mime, prefix_dot=True):
        """根据MIME类型获取文件扩展名

        只能返回预先配置的类型,不保证能够处理任何类型
        Args:
            mime: MIME类型
            prefix_dot: 是否需要前缀"."
        Returns:
            str: 文件扩展名

        例如: image/jpeg -> jpeg(或.jpeg)
        """
        ext = FileNameHandler.MIME_TO_EXT.get(mime, "")
        if prefix_dot:
            return ext
        else:
            return ext[1:] if ext.startswith(".") else ext

    @staticmethod
    def get_file_extension_from_url(url: str) -> str:
        """从URL中提取文件扩展名

        先解析出url路径部分,然后针对此部分字符串尝试截取扩展名
        如果截取失败,则返回空字符串

        效果:例如:"https://www.example.com/file.txt" -> ".txt"
        :param url: 图片URL
        :return: 文件扩展名
        """
        parsed_url = urlparse(url)
        # 百分号解码url路径字符串为单字符
        path = unquote(parsed_url.path)

        # 尝试从路径中获取扩展名
        # 尽可能有正确的扩展名(利用splitext尝试将文件名拆分(split)为文件名和扩展名(ext));这里我们解包只用到ext,前面的路径部分(root)不用
        _, ext = os.path.splitext(path)
        if ext and ext.startswith("."):
            return ext.lower()

        return ""

    @staticmethod
    def get_file_extension_from_content_type(content_type: str) -> str:
        """从Content-Type中获取文件扩展名

        :param content_type: HTTP响应头中的Content-Type,常见的值比如"image/jpeg"等
        :return: 文件扩展名
        """
        debug(f"Content-Type: [{content_type}]")
        if not content_type:
            return ""
        # 使用mimetypes模块获取扩展名,例如将"image/jpeg"转换为".jpg"
        ext = mimetypes.guess_extension(content_type)
        # 识别成功直接返回
        if ext:
            return ext

        # 若自动识别失败,则手动处理一些常见的MIME类型,从而提高扩展名识别的准确性和兼容性。
        mime_map = {
            "image/jpeg": ".jpg",
            "image/png": ".png",
            "image/gif": ".gif",
            "image/webp": ".webp",
            "image/svg+xml": ".svg",
            "image/bmp": ".bmp",
            "image/tiff": ".tiff",
            "image/x-icon": ".ico",
        }

        return mime_map.get(content_type, "")

    # @staticmethod
    def generate_filename_from_url(
        self,
        url: str,
        response=None,
        default_ext="",  # 修复拼写错误
        invalid_chars_regex=r'[\\/*?:"<>|]',
        default_char="_",
    ) -> str:
        r"""生成文件名,尽可能分配一个合适的后缀名,如果么有则将default_ext作为后缀名

        :param url: 图片URL
        :param response: requests响应对象
        :param default_ext: 默认文件扩展名
        :param invalid_chars_regex: 用于清理文件名中的非法字符的正则表达式
        :param default_char: 用于清理文件名中的非法字符的替换字符
        :return: 文件名

        注意,文件名(windows中不允许:   \/:*?"<>|  这9个基本字符)
        """
        # 尝试从URL中提取文件名
        filename = FileNameHandler.get_filebasename_from_url_or_path(url)

        # 检查上述尝试生成的文件名
        ## 如果URL中没有有效的文件名,并检查是否有后缀名(文件扩展名)，如果没有文件名,使用URL的哈希值作为文件名
        if not filename or filename == "/" or "." not in filename:
            url_hash = hashlib.md5(url.encode()).hexdigest()

            # 尝试获取文件扩展名
            ext = self.get_file_extension(url, response, default_ext)

            filename = f"{url_hash}{ext}"

        # 清理文件名中的非法字符
        filename = re.sub(invalid_chars_regex, default_char, filename)

        return filename

    # @staticmethod
    # @classmethod
    def get_file_extension(self, url, response=None, defualt_ext=""):
        """
        根据响应头、URL或默认值确定资源的文件扩展名。

        Args:
            url (str): 资源的URL。
            response (object): HTTP响应对象，可能包含带有内容类型信息的头部。
            defualt_ext (str): 如果无法确定扩展名，则使用的默认文件扩展名。

        Returns:
            str: 确定的文件扩展名，如果所有方法均失败，则返回默认扩展名。

        Notes:
            - 方法首先尝试从响应头中的"Content-Type"提取扩展名。
            - 如果无法从响应头中确定扩展名，则尝试从URL中提取。
            - 如果仍然无法确定扩展名，则使用备用方法`get_file_extension_from_url_magic`推断扩展名。
            - 如果所有方法均失败，则返回提供的默认扩展名。
        """
        ext = ""
        if response and "Content-Type" in response.headers:
            ext = self.get_file_extension_from_content_type(
                response.headers["Content-Type"]
            )

        if not ext:
            ext = self.get_file_extension_from_url(url)

        if not ext:
            ext = self.get_file_extension_from_url_magic(response=response)

        if not ext:
            ext = defualt_ext

        return ext

    @staticmethod
    def get_filebasename_from_url_or_path(url):
        """从URL中提取文件名(basename without extension)
        Args:
            url: 要被解析的URL或文件路径
        例如: https://www.example.com/file.txt -> file
            "ximage.jpg" -> "ximage"
            "path/to/file.txt" -> "file"
        """
        parsed_url = urlparse(url)
        path = unquote(parsed_url.path)
        filename = os.path.basename(path)
        basename, _ = os.path.splitext(filename)
        return basename

    # @staticmethod
    def get_file_extension_from_url_magic(self, url="", response=None, prefix_dot=True):
        """获取文件类型(基于magic库)

        两个参数至少且通常只选择一个,如果不一致则优先选择response

        Args:
            url (str, optional): 文件URL地址
            response (requests.Response, optional): 预获取的响应对象
            prefix_dot (bool): 是否在扩展名前加点号，默认为True

        Returns:
            str: 检测到的文件扩展名（例如 .pdf）

        Raises:
            ValueError: 当既没有提供url也没有提供response时
            Warning: 当同时提供了url和response时(会优先使用response)
        """
        if url is None and response is None:
            raise ValueError("必须提供url或response参数")

        if url and response is not None:
            warning("同时提供了url和response参数，将优先使用response进行计算")

        chunk = None

        # 优先使用 response
        if response is not None:
            try:
                # 尝试从原始流中读取前2048字节
                response.raw.seek(0)  # 确保从头开始读
                chunk = response.raw.read(2048)
            except (AttributeError, OSError, ValueError) as e:
                # 如果无法读取 raw stream(比如response是有stream=False的get方法获取的情况下
                # 将无法使用seek(0)，则从content中提取前2048字节
                debug(f"get file type from response exception:{e}")
                chunk = response.content[:2048]
        else:
            # 如果没有提供response，则针对url发起请求
            try:
                # 使用 self.session 实现连接复用
                # response = requests.get(
                response = self.session.get(
                    url=url, stream=True, timeout=30
                )  # 移除对 self.session 的依赖
                response.raise_for_status()
                response.raw.seek(0)
                chunk = response.raw.read(2048)
            except requests.RequestException as e:
                # raise ValueError(f"网络请求失败: {e}") from e
                error("网络请求失败: %s", e)

        if not chunk:
            raise ValueError("无法从响应中读取数据")

        # 使用 python-magic 检测类型
        mime = magic.from_buffer(chunk, mime=True)
        extension = FileNameHandler.get_file_extension_from_mime(
            mime, prefix_dot=prefix_dot
        )
        return extension
