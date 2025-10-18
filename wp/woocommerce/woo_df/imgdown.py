#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
多线程图片下载器
Todo: 允许忽略证书过期的下载

这个模块提供了一个高效的多线程图片下载器，可以同时下载多张图片，
支持各种图片链接格式，并提供下载统计和日志功能。

用法示例:
    # 作为模块导入使用
    from img_downloader import ImageDownloader

    downloader = ImageDownloader(max_workers=10)
    urls = ['http://example.com/image1.jpg', 'https://example.com/image2.png']
    downloader.download(urls, output_dir='./images')

    # 指定文件名下载
    name_url_pairs = [('custom_name1.jpg', 'http://example.com/image1.jpg'),
                      ('custom_name2.png', 'https://example.com/image2.png')]
    downloader.download_with_names(name_url_pairs, output_dir='./images')

    # 命令行使用
    # python img_downloader.py -i urls.txt -o ./images -w 10
"""
import concurrent.futures
import logging
import os
import random
import re

import subprocess
import shutil
import threading
import time

# from logging import exception
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from filenamehandler import FilenameHandler
from imgcompresser import ImageCompressor

TIMEOUT = 120

IMG_DIR = "./images"
RESIZE_THRESHOLD = 1000, 800  # 图片尺寸小于这个阈值则不调整分辨率(宽*高)
# 自定义日志格式
LOG_FORMAT = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
# ...existing code...
# 创建当前模块专属的日志记录器
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)  # 设置默认日志级别
fnh = FilenameHandler()
info = logger.info
debug = logger.debug
warning = logger.warning
error = logger.error
exception = logger.exception
# 防止重复添加 handler
if not logger.handlers:
    # 控制台日志处理器
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.NOTSET)  # 改为 NOTSET，跟随logger级别
    console_formatter = logging.Formatter(LOG_FORMAT)
    console_handler.setFormatter(console_formatter)
    logger.addHandler(console_handler)

    # 文件日志处理器
    try:
        file_handler = logging.FileHandler("img_downloader.log", encoding="utf-8")
        file_handler.setLevel(logging.NOTSET)  # 改为 NOTSET，跟随logger级别
        file_formatter = logging.Formatter(LOG_FORMAT)
        file_handler.setFormatter(file_formatter)
        logger.addHandler(file_handler)
    except Exception as e:
        logger.warning("无法创建文件日志处理器: %s", e)
# ...existing code...
# 文件名处理器
fnh = FilenameHandler()
# 配置使用的User-Agent(过长可以用括号包裹配合+号分隔字符串)

# 预设多个常见浏览器的 User-Agent🎈
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
    #
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/535.11 "
    "(KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36",
    #
    "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/41.0.2227.0 Safari/537.36",
    #
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/41.0.2227.1 Safari/537.36",
]

# 要注意很多常用的普通分割符号都不要用于分割url,例如分号,逗号,甚至空格;
# 比如url的协议名比如https://就带有冒号,而逗号也有风险,部分链接包含逗号!
# 如果需要,可以考虑在调用此下载之前将separator进行配置
# 或者,如果你已经使用逗号做url分割(虽然这不是推荐方式,而且有些url本身包含逗号就容易造成混淆),可以事先将`,`替换为`>`
URL_SEPARATORS = [
    ">",
    # r"\s+",
    # ";",
    # ",",
]
COMMON_SEPARATORS = [",", ";", r"\s+"]
URL_SEP_PATTERN = "|".join(URL_SEPARATORS)
COMMON_SEP_PATTERN = "|".join(COMMON_SEPARATORS)

URL_SEP_REGEXP = re.compile(URL_SEP_PATTERN)
COMMON_SEP_REGEXP = re.compile(COMMON_SEP_PATTERN)
logger.info("SEP_PATTERN: %s", URL_SEP_PATTERN)
# 有些网站需要登录才能访问资源。你可以手动获取登录后的 Cookie，并在每次请求中携带。
COOKIES = {"sessionid": "abc123xyz", "csrftoken": "csrf_token_here"}


def download_by_iwr(
    url, output_path, user_agent=None, timeout=TIMEOUT, verify_ssl=True
):
    """
    使用 PowerShell 的 Invoke-WebRequest 下载指定 URL 到本地文件。

    :param url: 下载链接
    :param output_path: 保存到的本地文件路径
    :param user_agent: 可选，自定义 User-Agent
    :param timeout: 超时时间（秒）
    :param verify_ssl: 是否校验证书
    :return: True/False

    """
    # 构造 PowerShell 命令
    cmd = [
        # "pwsh",
        "powershell.exe",
        "-NoProfile",
        "-Command",
        '"',
        "Invoke-WebRequest",
        f"-Uri '{url}'",
        f"-OutFile '{output_path}'",
        f"-TimeoutSec {timeout}",
        '"',
    ]
    if user_agent:
        cmd.append(f"-Headers @{{'User-Agent'='{user_agent}'}}")
    if not verify_ssl:
        cmd.append("-SkipCertificateCheck")
    # 合并为单行字符串
    ps_command = " ".join(cmd)
    logger.debug("PowerShell 命令: %s", ps_command)
    msg = f"🎈PowerShell 命令:  {ps_command}"
    print(msg)
    try:
        result = subprocess.run(
            ps_command, shell=True, capture_output=True, text=True, check=False
        )
        if result.returncode == 0:
            return True
        else:
            error("Invoke-WebRequest 下载失败: %s", result.stderr.strip())
            return False
    except Exception as e:
        error("调用 Invoke-WebRequest 失败: %s", e)
        return False


def download_by_curl(
    url: str,
    output_path="",
    output_dir="./",
    use_remote_name: bool = False,  # 新增参数：是否使用远程文件名
    user_agent: str = USER_AGENTS[0],
    timeout: int = TIMEOUT,
    silent: bool = False,
    extra_args: Optional[list] = None,
    reset_cwd=False,  # 发生工作目录转换下载后,是否回到原目录
) -> bool:
    """
        使用系统 curl 命令下载图片（或其他文件）。
        (使用-k来强制忽略证书验证https证书过期)

        Args:
            url (str): 要下载的文件 URL。
            output_path (str): 本地保存路径。如果 use_remote_name 为 True，则应为保存目录。
            output_dir (str): 本地保存目录。如果 use_remote_name 为 True时有用
            user_agent (str): 请求头中的 User-Agent 字符串。
            timeout (int): 请求超时时间（秒）。
            silent (bool): 是否静默执行（不输出进度信息）。
            use_remote_name (bool): 是否使用远程文件名保存（即添加 -O 参数）。
            extra_args (Optional[list]): 其他要传给 curl 的额外参数列表。


        Returns:
            bool: 下载成功返回 True，失败返回 False。

        Raises:
            FileNotFoundError: 如果 curl 不在系统 PATH 中。
            PermissionError: 如果没有写入目标路径的权限。
        Examples:
        # 使用服务器返回的文件名字
        download_with_curl(
            url=r"https://brigade-hocare.com/5944-large_default/lot-de-2-glissieres-inox-cambro-pour-dw585.jpg",
            use_remote_name=True,
            )
        # 指定保存路径
        download_with_curl(
        url=r"https://brigade-hocare.com/5944-large_default/lot-de-2-glissieres-inox-cambro-pour-dw585.jpg",
        output_file=r"C:/Users/Administrator/Pictures/xyz123.jpg"
    )
    """

    cwd = os.getcwd()  # 记录当前工作目录
    print(f"当前工作目录(curl): {cwd}")
    # 检查 curl 是否可用
    if not shutil.which("curl"):
        raise FileNotFoundError("curl 命令未找到，请确保已安装并添加到系统 PATH")

    # 如果不使用远程文件名，则确保输出目录存在，并拼接文件名
    if not use_remote_name:
        # 确保输出目录存在
        output_dir = os.path.dirname(output_path)
        os.makedirs(output_dir, exist_ok=True)
    else:
        # 使用远程文件名,确认输出目录存在
        os.makedirs(output_dir, exist_ok=True)
        # 将工作目录转换到输出目录
        os.chdir(output_dir)
        parsed_url = urlparse(url)
        # 这里计算的文件名仅供参考
        output_path = os.path.basename(parsed_url.path)
        output_path = os.path.abspath(os.path.join(output_dir, output_path))
        print(f"使用远程文件名, 计算的文件名(basename供参考): {output_path}")
        # output_file = os.path.basename(url)

    # 构建 curl 命令参数(基础参数,建议移动到函数默认参数中)

    cmd = [
        "curl",
        "-f",
        #    , "--retry", "1", "--retry-delay", "2"
    ]
    # 忽略证书安全检查
    cmd += ["-k", "--ssl-no-revoke"]

    # 添加 User-Agent
    cmd += ["-A", user_agent]

    # 添加超时
    cmd += ["--max-time", str(timeout)]

    # 静默模式
    if silent:
        cmd += ["--silent"]
    else:
        cmd += ["--progress-bar"]

    # 添加 -O 参数（使用远程文件名）
    if use_remote_name:
        cmd += ["-O"]
    else:
        if not output_path:
            raise ValueError("output_path 不能为空")

        cmd += ["-o", output_path]

    # 添加额外参数
    if extra_args:
        cmd += extra_args

    # 添加 URL 最后
    cmd += [url]

    try:
        debug(f"正在下载: {url}")
        subprocess.run(cmd, check=True)
        if use_remote_name:
            info(f"文件已保存至(仅供参考): {output_path}")
        else:
            info(f"文件已保存至: {output_path}")
        return True
    except subprocess.CalledProcessError as e:
        error(f"curl 执行失败，错误码: {e.returncode}")
        return False
    except PermissionError as pe:
        raise PermissionError(f"无权写入路径: {output_path}") from pe
    finally:
        # 下载完成后,是否回到原目录
        if reset_cwd:
            os.chdir(cwd)  # 回到原目录
            print(f"已回到原目录: {cwd}")


class DownloadStatistics:
    """下载统计类，用于记录和展示下载统计信息"""

    def __init__(self):
        self.total = 0
        self.success = 0

        # self.progress = 0
        self.task_index = 0
        self.index_lock = threading.Lock()

        self.failed = 0
        self.skipped = 0
        self.start_time = time.time()
        self.end_time = None
        self.failed_urls = []

    def add_success(self):
        """记录一次成功下载"""
        self.success += 1

    def add_failed(self, url, name=""):
        """记录一次下载失败

        这里如果用户的下载链接同时指定了保存名字,则连同保存的名字一起记录到失败列表中
        一般来说,图片链接中提取出来的文件名不会带有空格
        """
        self.failed += 1
        line = f"{name} {url}".strip()
        self.failed_urls.append(line)

    def add_skipped(self):
        """记录一次跳过下载"""
        self.skipped += 1

    def set_total(self, total: int):
        """设置总下载数量"""
        self.total = total

    def finish(self):
        """完成下载，记录结束时间"""
        self.end_time = time.time()
        self.save_failed_urls()

    def save_failed_urls(self, file_path="failed_urls.txt"):
        """保存失败的URL到文件,供后续此重试"""
        logger.info("Saving failed URLs to %s", file_path)
        logger.info("Failed URLs: [%s]", self.failed_urls)
        with open(file=file_path, mode="w", encoding="utf-8") as f:
            for url in self.failed_urls:
                f.write(url + "\n")

    def get_elapsed_time(self) -> float:
        """获取下载耗时（秒）"""
        if self.end_time:
            return self.end_time - self.start_time
        return time.time() - self.start_time

    def get_summary(self) -> Dict[str, Any]:
        """获取下载统计摘要"""
        return {
            "total": self.total,
            "success": self.success,
            "failed": self.failed,
            "skipped": self.skipped,
            "elapsed_time": self.get_elapsed_time(),
            "failed_urls": self.failed_urls,
        }

    def print_summary(self):
        """打印下载统计摘要"""
        summary = self.get_summary()
        logger.info("=" * 50)
        logger.info("下载统计摘要:")
        logger.info("总计: %d 张图片", summary["total"])
        logger.info("成功: %d 张图片", summary["success"])
        logger.info("下载时跳过: %d 张图片", summary["skipped"])
        logger.info("失败: %d 张图片", summary["failed"])
        logger.info("耗时: %.2f 秒", summary["elapsed_time"])

        if summary["failed"] > 0:
            logger.info("失败的URL:")
            for url in summary["failed_urls"]:
                logger.info("  - %s", url)
        logger.info("=" * 50)


class ImageDownloader:
    """多线程图片下载器"""

    def __init__(
        self,
        max_workers: int = 10,
        timeout: int = TIMEOUT,
        retry_times: int = 1,
        user_agent: Optional[str] = None,
        cookies: Optional[Dict[str, str]] = None,
        verify_ssl: bool = True,
        proxies=None,
        proxy_strategy="round_robin",
        override=False,
        compress_quality=20,
        quality_rule="",
        output_format="webp",
        remove_original=False,
        use_shutil=False,
        resize_threshold=RESIZE_THRESHOLD,
    ):
        """
        初始化图片下载器

        Args:
            max_workers: 最大工作线程数
            timeout: 下载超时时间（秒）
            retry_times: 下载失败重试次数
            user_agent: 自定义User-Agent
            cookies: 自定义Cookie
            verify_ssl: 是否验证SSL证书(启用会提高安全性，但会降低下载速度)
            proxies: 代理设置,格式为{'http': 'http://proxy.example.com:8080',
                'https': 'https://proxy.example.com:8080'}
            proxy_strategy: 代理选择策略,可选值为'round_robin'（轮询）和'random'（随机）
            compress_quality: 压缩图片质量(1-100),取0表示不压缩
            quality_rule: 压缩图片规则(默认使用ic.compress_image的默认规则)
            output_format: 压缩图片格式(默认使用webp)
        """
        self.max_workers = max_workers
        self.timeout = timeout
        self.retry_times = retry_times
        self.verify_ssl = verify_ssl
        self.cookies = cookies
        self.use_shutil = use_shutil
        self.stats = DownloadStatistics()
        self.compress_quality = compress_quality
        self.quality_rule = quality_rule
        self.output_format = output_format
        self.remove_original = remove_original
        self.override = override

        self.ic = ImageCompressor(
            quality_rule=quality_rule,
            remove_original=remove_original,
            resize_threshold=resize_threshold,
        )

        # if retry_times < 1:
        #     warning("retry_times smaller than 1, no retry will be performed.")
        # 初始化会话
        self.session = requests.Session()
        # 创建具有重试策略的适配器
        adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1))
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

        if cookies:
            self.session.cookies.update(cookies)
        # 设置User-Agent
        self.headers = {
            "User-Agent": user_agent or random.choice(USER_AGENTS),
            "Referer": f"https://{random.choice(['google.com', 'bing.com'])}/",
            "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7",
            "Accept-Encoding": "gzip, deflate, br",
            "Accept": "text/html,application/xhtml+xml,application/xml;\
                q=0.9,image/avif,image/webp,*/*;q=0.8",
        }
        self.proxies = proxies or []
        self.proxy_strategy = proxy_strategy
        self.proxy_index = 0

    def get_proxy(self):
        """
        获取代理配置策略
        """
        if not self.proxies:
            return None
        if self.proxy_strategy == "round_robin":
            # 轮询代理(更新索引)
            proxy = self.proxies[self.proxy_index % len(self.proxies)]
            self.proxy_index += 1
            return proxy
        elif self.proxy_strategy == "random":
            # 简单的随机代理
            return random.choice(self.proxies)
        return None

    def _download_single_image(
        self,
        url: str,
        output_dir: str,
        filename="",
        try_get_ext=True,
        default_ext="",
        retry_gap=1,
        # override=False,
        # compress_quality=20,
        # use_shutil=False,
    ):
        """
        下载单张图片

        for chunk in response.iter_content(chunk_size=8*2**10):
        从 HTTP 响应中按块读取内容，每块大小为 8192 字节（8KB）。
        这样做可以防止一次性加载整个文件到内存，适合大文件下载。

        Args:
            url: 图片URL
            output_dir: 输出目录
            filename: 自定义文件名，如果为None则自动生成
            try_get_ext: 如果filename缺少扩展名,是否尝获取文件扩展名(不保证一定返回扩展名)
            override: 是否覆盖已存在文件(如果不覆盖则跳过)
            retry_gap: 失败重试间隔(秒)
            compress_quality: 压缩图片质量(1-100)

        Returns:
            bool: 下载是否成功
        """
        # 更新/修改当前下载的进度
        with self.stats.index_lock:
            self.stats.task_index += 1
            # 在释放锁之前,获取当前下载的进度(退出后用self.stats.task_index获取的进度往往是不正确的)
            current_index = self.stats.task_index
        logger.info(
            "⛏ downloading(%d/%d): [%s] -> (%s) ",
            current_index,
            self.stats.total,
            url,
            filename,
        )
        # 如果传入的文件名没有扩展名,且在try_get_ext为True时,则[尝试]补全扩展名
        filename = filename.rstrip(".")
        filename = self.prepare_filename(url, filename, try_get_ext, default_ext)
        # debug("filename: [%s]", filename)
        override = self.override
        # 配置下载中如果出现失败的重试循环(次数由retry_times指定)
        for attempt in range(self.retry_times + 1):
            # 如果某次尝试下载成功,则直接返回True(结束此下载任务)
            try:
                # # 模拟用户行为：每次请求前添加随机等待,在失败后指数退避
                # time.sleep(random.uniform(0.5, 2))

                # 检查response是否是图片类型
                # if not self._is_image_response(response=response):
                #     return False

                debug("下载图片: %s (尝试 %d/%d)", url, attempt + 1, self.retry_times)
                # 如果用户没有指定文件名,则按照默认策略生成文件名
                if not filename:
                    filename = fnh.get_filename_from_url(
                        url=url,
                        # response=response,
                        default_ext=default_ext,
                    )
                debug("获得文件名🎈: [%s]", filename)

                # 确保输出目录存在(如果路径尚不存在则逐级创建,否则略过,也不报错)
                os.makedirs(output_dir, exist_ok=True)

                # 保存图片(写入二进制文件)🎈

                file_path = os.path.join(output_dir, filename)
                if os.path.exists(file_path) and not override:
                    logger.info("文件已存在,跳过: %s", file_path)
                    self.stats.add_skipped()
                    return True
                elif self.use_shutil:
                    res = False
                    if self.use_shutil == "curl":
                        # print("使用shutil(curl)下载图片")
                        # 目前使用curl下载图片(将来可能扩展)
                        res = download_by_curl(
                            url=url,
                            output_path=file_path,
                            output_dir=output_dir,
                            timeout=self.timeout,
                            user_agent=self.headers["User-Agent"],
                        )
                    elif self.use_shutil == "iwr":
                        # print("使用shutil(iwr)下载图片")
                        res = download_by_iwr(
                            url=url,
                            output_path=file_path,
                            timeout=self.timeout,
                        )
                    if res:
                        self.stats.add_success()
                else:
                    # 通过python发送get请求获取包含文件(图片)的响应
                    # (酌情启用stream参数可以实现流式下载,减少内存占用,配合后面的iter_content方法使用)
                    response = self.session.get(
                        url=url,
                        timeout=self.timeout,
                        verify=self.verify_ssl,
                        stream=True,
                        # proxies={"https": self.get_proxy()},  # 使用代理
                    )
                    response.raise_for_status()

                    self.download_by_py(url, response=response, file_path=file_path)
                    self.stats.add_success()
                # 执行压缩任务
                quality = self.compress_quality
                if quality or self.quality_rule:
                    # 判断下载的图片大小是否高于100KB,如果是则压缩图片
                    # if os.path.getsize(file_path) < 100 * 2**10:
                    #     debug("图片小于100KB,使用高quality压缩")
                    #     quality = 70

                    # else:
                    print("尝试压缩图片")
                    self.ic.compress_image(
                        input_path=file_path,
                        # output_path=file_path,
                        output_format=self.output_format,
                        quality=quality,
                        overwrite=True,
                    )
                # return True
                return file_path

            except requests.exceptions.RequestException as e:
                # 如果是应为请求异常导致的下载失败,这在这里捕获;
                warning(
                    "下载失败 (尝试 %d/%d): %s, 错误: %s",
                    attempt + 1,
                    self.retry_times,
                    url,
                    str(e),
                )
                # 如果还有重试的机会,则等待一段时间后回到循环再重试
                if attempt < self.retry_times - 1:
                    wait_time = retry_gap * (2**attempt) + random.uniform(0, 1)
                    time.sleep(wait_time)
                else:
                    # 尝试次机会用完,直接报错并返回False
                    wait_time = retry_gap * (2**attempt) + random.uniform(0, 1)
                    time.sleep(wait_time)
                    error("下载失败: %s, 错误: %s", url, str(e))
                    self.stats.add_failed(url, name=filename or "")
                    return False

        return False

    def prepare_filename(self, url, filename, try_get_ext, default_ext):
        """准备文件名,用于指定下载保存文件"""
        if filename:
            _, ext = os.path.splitext(filename)
            # ext = ext.strip(".")
            if not ext:
                debug("指定文件名缺少扩展名")
                if try_get_ext:
                    raw_name = filename
                    filename = self.complete_extension(
                        filename=filename, url=url, default_ext=default_ext
                    )
                    debug(
                        "已尝试补全文件扩展名: %s -> %s",
                        raw_name,
                        filename,
                    )
            else:
                debug("文件名包含扩展名:%s", ext)
        else:
            debug("未指定文件名,尝试从URL中获取")
        return filename

    def download_by_py(self, url, response, file_path):
        """使用python的库下载图片(操作比较原始和底层)"""
        with open(file_path, "wb") as f:
            # 分块写入响应内容
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)

        file_size = os.path.getsize(file_path)
        logger.info("成功下载: %s -> %s (%d 字节)", url, file_path, file_size)

    def _is_image_response(self, response):
        """检查response是否是图片类型"""
        content_type = response.headers.get("Content-Type", "")
        if not content_type.startswith("image/"):
            # error("响应不是图片类型: %s -> Content-Type=%s", url, content_type)
            # self.stats.add_failed(url=url, name=filename or "")
            return False

    def complete_extension(self, filename, url, default_ext=""):
        """补全文件扩展名

        Args:
            url:文件资源的url(当filename缺少扩展名时,尝试从对应文件的url中获取)

        如果输入的filename没有扩展名,则尝试补全扩展名
        如果已经有扩展名,则返回原本地filename
        如果文件名为空,则返回空字符串

        """
        _, ext = os.path.splitext(p=filename or "")
        debug("filename: [%s], ext:[ %s]", filename, ext)
        if not ext:
            # 文件名非空但是扩展名为空时尝试获取扩展名
            if filename:
                ext = fnh.get_file_extension(url=url, default_ext=default_ext)
                filename = f"{filename}{ext}"
            else:
                debug("缺少文件名和扩展名")
        return filename

    def download_only_url(
        self, urls: List[Any], output_dir: str = IMG_DIR, default_ext=""
    ) -> Dict[str, Any]:
        """
        仅根据给定的url下载图片

        另一个函数download_with_names()可以指定自定义文件名下载图片

        Args:
            urls: 图片URL列表
            output_dir: 输出目录

        Returns:
            Dict: 下载统计信息
        """
        logger.info("开始下载 %d 张图片到 %s", len(urls), output_dir)

        # 初始化统计信息
        self.stats = DownloadStatistics()
        self.stats.set_total(len(urls))

        # 创建输出目录
        os.makedirs(output_dir, exist_ok=True)

        # 使用线程池多线程下载图片
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=self.max_workers
        ) as executor:
            future_to_url = {
                executor.submit(
                    self._download_single_image,
                    url,
                    output_dir,
                    default_ext=default_ext,
                ): url
                for url in urls
            }

            for future in concurrent.futures.as_completed(future_to_url):
                url = future_to_url[future]
                try:
                    future.result()

                except Exception as e:
                    exception("处理下载时发生异常: %s, 错误: %s", url, str(e))
                    self.stats.add_failed(url)

        # 完成下载，打印统计信息
        self.stats.finish()
        self.stats.print_summary()

        return self.stats.get_summary()

    def download_with_names(
        self,
        name_url_pairs: List[Any],
        output_dir: str = IMG_DIR,
        default_ext="",
    ) -> Dict[str, Any]:
        """
        使用自定义文件名下载多张图片
        另一个函数：download_only_url()仅根据url下载图片

        Args:
            name_url_pairs: (文件名, URL)元组列表
            output_dir: 输出目录

        Returns:
            Dict: 下载统计信息
        """
        logger.info("开始下载 %d 张图片到 %s", len(name_url_pairs), output_dir)

        # 初始化统计信息
        self.stats = DownloadStatistics()
        self.stats.set_total(len(name_url_pairs))

        # 创建输出目录
        os.makedirs(name=output_dir, exist_ok=True)

        # 使用线程池下载图片
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=self.max_workers
        ) as executor:
            # 使用字典解析式创建和存储任务{future: (filename, url)}
            future_to_pair = {
                executor.submit(
                    self._download_single_image,
                    url=url,
                    output_dir=output_dir,
                    filename=filename,  # 此参数取值来自对可迭代对象name_url_pairs解析出来的filename,url元组中的第一个分量
                    default_ext=default_ext,
                ): (filename, url)
                for filename, url in name_url_pairs
            }

            for future in concurrent.futures.as_completed(fs=future_to_pair):
                filename, url = future_to_pair[future]
                try:
                    future.result()
                    # success = future.result()
                    # if success:
                    #     self.stats.add_success()
                    # else:
                    #     self.stats.add_failed(url)
                except Exception as e:
                    failed_dict = {filename: url}
                    exception("处理%s下载时发生异常, 错误:%s", failed_dict, str(e))
                    self.stats.add_failed(url=url, name=filename)

        # 完成下载，打印统计信息
        self.stats.finish()
        self.stats.print_summary()

        return self.stats.get_summary()


##
if __name__ == "__main__":
    logger.info("Welcome to use this image downloader module!")
