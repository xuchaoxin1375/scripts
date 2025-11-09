"""文件名处理模块
用于对从url下载的文件,生成或补全文件名(扩展名)
"""

# %%
import hashlib
import mimetypes
import os
import re
import logging

# from logging import debug, warning, error
from urllib.parse import unquote, urlparse
import requests
import magic

logger = logging.getLogger(__name__)
TIMEOUT = 30

# 配置日志格式，包括函数名
handler = logging.StreamHandler()
formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(funcName)s: %(message)s")
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# 让所有日志方法都用本logger
debug = logger.debug
warning = logger.warning
error = logger.error


class FilenameHandler:
    """文件名(扩展名)处理器"""

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

    def __init__(self):
        # 使用 session 实现连接复用
        self.session = requests.Session()
        # python3.13可能不兼容(magic.Magic)(库:python-magic-bin)
        # self.mgc = magic.Magic(mime=True)

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
        ext = FilenameHandler.MIME_TO_EXT.get(mime, "")
        if prefix_dot:
            return ext
        else:
            return ext[1:] if ext.startswith(".") else ext

    @staticmethod
    def get_file_extension_from_url_str(url: str) -> str:
        """从URL中提取文件扩展名

        先解析出url路径部分,然后针对此部分字符串尝试截取扩展名
        如果截取失败,则返回空字符串

        :param url: 文件资源URL
        :return: 文件扩展名

        Examples:
            >>> get_file_extension_from_url_str("https://example.com/path/to/image.jpg")
            '.jpg'
            >>> get_file_extension_from_url_str("https://example.com/path/to/image.keepit")
            '.keepit'
        """
        parsed_url = urlparse(url)
        # 百分号解码url路径字符串为单字符
        path = unquote(parsed_url.path)

        # 尝试从路径中获取扩展名
        # 尽可能有正确的扩展名(利用splitext尝试将文件名拆分(split)为文件名和扩展名(ext));这里我们解包只用到ext,前面的路径部分(root)不用
        _, ext = os.path.splitext(path)
        if ext and ext.startswith("."):
            return ext.lower()
        else:
            debug(
                "URL字符串缺少后缀特征,无法从中提取文件扩展名:[%s],注意检查输入源中此链接",
                url,
            )
        return ""

    def get_image_extension_from_url_str(
        self,
        url: str,
        support_image_formats=("jpg", "jpeg", "png", "webp", "tif", "tiff", "gif"),
    ) -> str:
        """从URL中提取图片扩展名
        依赖于support_image_formats参数的指定

        Examples:
            >>> get_image_extension_from_url_str("https://example.com/path/to/image.jpg")
            '.jpg'

            >>> url=r"https://res.cloudinary.com/8r10.086_01"
            >>> get_image_extension_from_url_str(url)
            ""

        """

        ext_candidate = self.get_file_extension_from_url_str(url)
        if ext_candidate.strip(".") in support_image_formats:
            return ext_candidate
        else:
            return ""

    @staticmethod
    def get_file_extension_from_content_type(content_type: str) -> str:
        """从Content-Type中获取文件扩展名

        :param content_type: HTTP响应头中的Content-Type,常见的值比如"image/jpeg"等
        :return: 文件扩展名
        """
        debug("Content-Type:%s", content_type)
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
    def get_filename_from_url(
        self,
        url: str,
        response=None,
        default_ext="",
        invalid_chars_regex=r'[\\/*?:"<>|]',
        default_char="_",
        limit_length=200,
        req_response=False,
    ) -> str:
        r"""尝试解析url字符串生成文件名(包括后缀名),尽可能分配一个合适的后缀名,如果没有则将default_ext作为后缀名

        :param url: 图片URL
        :param response: requests响应对象
        :param default_ext: 默认文件扩展名
        :param invalid_chars_regex: 用于清理文件名中的非法字符的正则表达式
        :param default_char: 用于清理文件名中的非法字符的替换字符
        :return: 文件名

        注意,文件名(windows中不允许:   \/:*?"<>|  这9个基本字符)
        """
        # 首先尝试从URL中提取文件名
        filename = FilenameHandler.get_filebasename_from_url_or_path(
            url, extension=True
        )

        # 检查上述尝试生成(构造)的文件名
        ## 如果URL中没有有效的文件名,并检查是否有后缀名(文件扩展名)，如果没有文件名,使用URL的哈希值作为文件名
        if not filename or filename == "/" or "." not in filename:
            debug(
                "not valid filename(empty or no extension), use url hash as filename!"
            )
            url_hash = hashlib.md5(
                url.encode()
            ).hexdigest()  # md5哈希不可逆(但是优点是长度比较固定),后续可能会更改成可逆

            # 尝试获取文件扩展名
            ext = self.get_file_extension(
                url, response, default_ext=default_ext, req_response=req_response
            )

            filename = f"{url_hash}{ext}"

        # 清理文件名中的非法字符
        filename = re.sub(invalid_chars_regex, default_char, filename)
        # 部分情况下文件名很长,在windows系统上,默认允许的文件名长度有限,大约250个字符
        if limit_length and len(filename) > 250:
            filename = filename[:250]

        return filename

    # @staticmethod
    # @classmethod
    def get_file_extension(
        self, url, response=None, default_ext="", req_response=False, prefix_dot=True
    ):
        """
        根据响应头、URL或默认值确定资源的文件扩展名。
        一般来说,response参数优先级最高(最准确,如果需要的话),其次是url(最快速),最后是default_ext(兜底)

        Args:
            url (str): 资源的URL。
            response (object): HTTP响应对象，可能包含带有内容类型信息的头部。
            defualt_ext (str): 如果无法确定扩展名，则使用的默认文件扩展名,比如webp(.webp)效果一样。

        Returns:
            str: 确定的文件扩展名，如果所有方法均失败，则返回默认扩展名。

        Notes:
            - 方法首先尝试从响应头中的"Content-Type"提取扩展名。
            - 如果无法从响应头中确定扩展名，则尝试从URL中提取。
            - 如果仍然无法确定扩展名，则使用备用方法`get_file_extension_from_url_magic`推断扩展名。
            - 如果所有方法均失败，则返回提供的默认扩展名。
        Examples:
            >>> get_file_extension("https://example.com/path/to/document.txt")
            '.txt'

        """
        ext = ""
        try:
            if response and "Content-Type" in response.headers:
                ext = self.get_file_extension_from_content_type(
                    content_type=response.headers["Content-Type"]
                )

            if not ext:
                # 尝试从URL中提取文件扩展名🎈
                ext = self.get_file_extension_from_url_str(url=url)

            if not ext and req_response:
                # 发送请求获取响应Content-Type来分析文件类型
                debug("发送 HEAD 请求获取 Content-Type: %s", url)
                response = self.session.head(url=url, stream=True, timeout=30)
                response.raise_for_status()  # 确保请求成功
                ext = self.get_file_extension_from_content_type(
                    content_type=response.headers.get("Content-Type", "")
                )
            if not ext:
                # 二进制文件分析
                ext = self.get_file_extension_from_response_magic(
                    url=url,
                    response=response,
                    req_response=req_response,
                    prefix_dot=prefix_dot,
                )

        except Exception as e:
            error("Error: %s", e)
            error("无法确定文件扩展名,使用默认扩展名: %s ", default_ext)
        if not ext:
            ext = default_ext
        ext = ext.strip(".")
        if prefix_dot:
            ext = f".{ext}"
        return ext

    @staticmethod
    def get_filebasename_from_url_or_path(url, extension=False):
        """从URL中提取文件名(basename without extension)
        Args:
            url: 要被解析的URL或文件路径
        例如: https://www.example.com/file.txt -> file
            "ximage.jpg" -> "ximage"
            "path/to/file.txt" -> "file"
        """
        parsed_url = urlparse(str(url))
        path = unquote(parsed_url.path)
        filename = os.path.basename(path)  # 这里的basename是带扩展名的(如果有的话)
        basename = filename
        if not extension:
            basename, _ = os.path.splitext(filename)

        return basename

    def get_file_mimetype_from_url_by_magic(self, url, chunk_size=2048):
        """
        使用流式下载方式获取 URL 资源的前几个字节，并通过 python-magic 判断文件的 MIME 类型。

        该方法适用于大文件或需要节省内存的场景。仅下载第一个数据块即可完成类型识别，
        不会将整个文件加载到内存中。

        Args:
            url (str): 需要检测的文件资源 URL。
            chunk_size (int, optional): 用于判断类型的初始数据块大小，默认为 2048 字节。

        Returns:
            str: 返回文件的 MIME 类型（如 'image/jpeg', 'application/pdf' 等）。

        Raises:
            Exception: 如果 HTTP 请求失败。
            ValueError: 如果无法从响应中读取任何数据（chunk 为空）。

        Example:
            >>> url = "https://example.com/path/to/image.jpg"
            >>> get_file_type_from_url_streaming(url)
            'image/jpeg'
        """
        with requests.get(url, stream=True, timeout=TIMEOUT) as response:

            response.raise_for_status()

            # 读取第一个 chunk 来检测文件类型
            chunk = next(response.iter_content(chunk_size=chunk_size), None)
            if not chunk:
                raise ValueError("无法从响应中读取数据或响应为空")

            # mime = self.mgc.from_buffer(chunk)
            mime = magic.from_buffer(chunk, mime=True)
            return mime

    def extract_chunk_from_response(self, response, chunk_size=2048):
        """
        从 requests.Response 对象中提取指定大小的数据块（chunk）用于文件类型检测。

        优先尝试从原始响应流 (`response.raw`) 中读取数据并支持重复读取（通过 seek）。
        如果原始流不可用，则回退到从 `response.content` 中提取前 `chunk_size` 字节。

        Args:
            response (requests.Response): HTTP 响应对象。
            chunk_size (int): 要提取的数据块大小，默认为 2048 字节。

        Returns:
            bytes: 提取的二进制数据块。

        Raises:
            ValueError: 如果 response 为 None 或无法从中读取任何数据。

        Example:
            >>> res = requests.get("https://example.com/image.jpg", stream=True)
            >>> chunk = handler.extract_chunk_from_response(res)
            >>> mime = magic.from_buffer(chunk)
        """

        if not isinstance(response, requests.Response):
            raise ValueError("response 参数必须是一个有效的 requests.Response 对象")

        chunk = None

        # 尝试从原始流中读取（适用于流式下载）
        try:
            if hasattr(response, "raw") and hasattr(response.raw, "seek"):
                response.raw.seek(0)  # 可重复读取
                chunk = response.raw.read(chunk_size)
        except Exception as e:
            debug("无法从 response.raw 读取数据：%s", e)

        # 回退：尝试从 content 中提取数据
        if not chunk:
            debug("response.raw 不可用，尝试从 response.content 获取数据")
            chunk = getattr(response, "content", b"")[:chunk_size]

        if not chunk:
            raise ValueError("无法从提供的 response 中读取任何数据")

        return chunk

    def get_file_mimetype_from_response(self, response, chunck_size=2048):
        """获取response中判断资源类型
        Args:
            response (requests.Response): HTTP 响应对象。
        Returns:
            str: 返回文件的 MIME 类型（如 'image/jpeg'等）。

        """
        chunk = self.extract_chunk_from_response(response, chunk_size=chunck_size)
        mime = magic.from_buffer(chunk)
        return mime

    # @staticmethod
    def get_file_extension_from_response_magic(
        self, url="", response=None, req_response=True, prefix_dot=True, chunk_size=2048
    ):
        """获取文件类型(基于magic库)

        两个参数至少且通常只选择一个,如果不一致则优先选择response

        Args:
            url (str, optional): 文件URL地址
            response (requests.Response, optional): 预获取的响应对象
            req_response (bool): 如果直接从response中获取文件类型失败，是否需要针对url发起网络请求获取响应，默认为True
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
            warning(
                "同时提供了url和response参数，将优先使用response进行计算,url参数将被忽略"
            )

        mime = ""
        if response is not None:
            # 优先使用 response (此时url参数不会生效)
            mime = self.get_file_mimetype_from_response(
                response, chunck_size=chunk_size
            )
        elif req_response:
            # 如果没有提供response，则针对url发起请求
            if not url:
                raise ValueError("response为空,则必须提供url参数")

            debug("尝试发送请求获取Response并读取前2KB数据来判断文件类型")
            mime = self.get_file_mimetype_from_url_by_magic(url)

        # 使用 python-magic 检测类型
        # mime = magic.from_buffer(chunk, mime=True)
        extension = FilenameHandler.get_file_extension_from_mime(
            mime=mime, prefix_dot=prefix_dot
        )
        return extension

    def get_file_extension_from_file_by_magic(self, file_path):
        """
        获取文件扩展名,使用magic库
        Args:
            file_path (str): 文件路径

        Returns:
            str: 文件扩展名
        """
        with open(file_path, "rb") as f:
            chunk = f.read(2048)
            mime = magic.from_buffer(chunk, mime=True)
            extension = FilenameHandler.get_file_extension_from_mime(mime=mime)
            return extension


##
