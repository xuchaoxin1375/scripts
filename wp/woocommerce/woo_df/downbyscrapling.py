"""
调用scrapling的stealthy浏览器下载资源
使用scrapling框架的AsyncStealthySession实现，具有更好的反检测能力
"""

import asyncio
import logging
import os
import random
import re
import unicodedata
from typing import Any, Dict, List, Optional, Tuple, Union
from imgcompressor import ImageCompressor
from urllib.parse import urlparse
from scrapling.fetchers import AsyncStealthySession

PROXY = "http://127.0.0.1:8800"  # 代理设置是可选的,根据实际情况修改
# 配置一个基本的logger，避免在外部调用时没有handler
logger = logging.getLogger("scrapling_downloader")
if not logger.handlers:
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler()
    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S"
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)

# --- 辅助函数 ---


def _sanitize_filename(filename: str) -> str:
    """清理文件名，移除非法字符，保证跨平台兼容性。"""
    filename = unicodedata.normalize("NFKD", filename)
    filename = filename.encode("ascii", "ignore").decode("ascii")
    # 允许的字符是字母数字, 下划线, 连字符, 点号
    filename = re.sub(r"[^\w\-_.]", "_", filename)
    return filename[:200].strip()


def _guess_filename_from_url(url: str, default_name: str = "index") -> str:
    """从 URL 中猜测文件名。"""
    parsed = urlparse(url)
    path = parsed.path

    # 尝试从路径中获取文件名
    filename = os.path.basename(path)
    if not filename or filename == "/":
        filename = default_name

    # 确保有扩展名，如果 URL 中没有，默认假定为 .html
    if "." not in filename:
        filename = filename + ".html"

    return _sanitize_filename(filename)


class ScraplingDownloader:
    """
    基于 Scrapling StealthySession 的网络资源下载器。
    专用于下载那些需要完整浏览器环境才能获取的资源 (如动态加载的图片或受保护的网页内容)。
    支持指定输出路径、代理配置和并发控制。
    使用 AsyncStealthySession 实现更好的反检测能力。
    """

    def __init__(
        self,
        headless: bool = True,
        timeout: int = 30,
        delay_range: Tuple[float, float] = (0, 0),
        max_concurrency: int = 3,
        max_retries: int = 1,
        # 图片压缩相关参数
        ic: ImageCompressor | None = None,
        compress_quality: int = 0,
        output_format: str = "webp",
        # Scrapling 特定参数
        solve_cloudflare: bool = True,
        block_webrtc: bool = True,
        hide_canvas: bool = True,
        real_chrome: bool = True,
    ):
        """
        初始化下载器。

        Args:
            headless: 是否启用无头模式 (不显示浏览器窗口)。
            timeout: 单次请求的超时时间 (秒)。
            delay_range: 每次下载任务之间随机延迟的时间范围 (min, max)。
            max_concurrency: 最大并发工作线程数。
            max_retries: 单个 URL 下载失败后的最大重试次数。
            ic: 图片压缩器实例。
            compress_quality: 图片压缩质量 (0-100)。0 表示不压缩。
            output_format: 图片压缩后的输出格式 (如 'webp', 'jpeg')。
            solve_cloudflare: 是否自动解决 Cloudflare 验证。
            block_webrtc: 是否阻止 WebRTC 泄露。
            hide_canvas: 是否隐藏 canvas 指纹。
            real_chrome: 是否使用真实 Chrome 浏览器。
        """
        self.headless = headless
        self.timeout = timeout
        self.delay_range = delay_range
        self.max_concurrency = max_concurrency
        self.max_retries = max_retries
        # 图片压缩相关参数
        self.ic = ic
        self.compress_quality = compress_quality
        self.output_format = output_format
        # Scrapling 特定参数
        self.solve_cloudflare = solve_cloudflare
        self.block_webrtc = block_webrtc
        self.hide_canvas = hide_canvas
        self.real_chrome = real_chrome

    @staticmethod
    def _read_proxies(proxy_input: Optional[Union[str, List[str]]]) -> List[str]:
        """
        从文件路径或直接的代理字符串中读取代理列表。
        一个 None 或空列表/空字符串表示直连(取决于环境代理)。
        """
        if not proxy_input:
            return []

        if isinstance(proxy_input, str):
            if os.path.exists(proxy_input):
                # 认为是文件路径
                proxies = []
                try:
                    with open(proxy_input, "r", encoding="utf-8") as f:
                        for line in f:
                            stripped = line.strip()
                            if stripped and not stripped.startswith("#"):
                                proxies.append(stripped)
                    return proxies
                except Exception as e:
                    logger.error(f"读取代理文件失败: {proxy_input}, 错误: {e}")
                    return []
            else:
                # 认为是单个代理字符串
                return [proxy_input]

        # 认为已经是代理列表
        return [p for p in proxy_input if p]

    def _get_proxy_config(self, proxy_list: List[str], worker_id: int) -> Optional[str]:
        """根据 worker_id 和代理列表获取代理配置。"""
        if not proxy_list:
            return None

        return proxy_list[worker_id % len(proxy_list)]

    async def _download_single_url(
        self,
        session: AsyncStealthySession,
        url: str,
        output_path: str,
        user_agent: Optional[str] = None,
        retry_count: int = 0,
        proxy_info: str = "直连",
        progress_info: Optional[str] = None,
        proxy_url: Optional[str] = None,
    ) -> bool:
        """
        核心下载逻辑：下载单个 URL 并保存到指定路径 (复用 Session)。
        下载完成后自动进行图片压缩处理（如启用）。
        """
        start_time = asyncio.get_event_loop().time()
        display_url = url

        # 确保输出目录存在
        output_dir = os.path.dirname(output_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir, exist_ok=True)

        # 检查是否已存在
        if (
            os.path.exists(output_path)
            and os.path.getsize(output_path) > 0
            and retry_count == 0
        ):
            logger.info(f"文件已存在，跳过: {output_path}", extra={"progress": "SKIP"})
            return True

        try:
            logger.info(
                f"🚀{progress_info if progress_info else ''} 开始请求: {display_url} [代理: {proxy_info}] -> {output_path} ".strip()
            )

            # 准备 fetch 参数
            fetch_kwargs = {
                "timeout": self.timeout * 1000,  # 转换为毫秒
                "network_idle": True,  # 等待网络空闲
            }
            # ty 比 pylance严格,这里可能会警告类型
            
            # 如果指定了 user_agent，添加到 extra_headers
            if user_agent:
                fetch_kwargs["extra_headers"] = {"User-Agent": user_agent}

            # 如果指定了代理，添加到 fetch 参数
            if proxy_url:
                fetch_kwargs["proxy"] = proxy_url

            # 使用复用的 session 发起请求
            response = await session.fetch(url, **fetch_kwargs)

            if not response:
                raise Exception("未获取到有效响应 (Response is None)")

            # 获取 content-type
            content_type = (
                response.headers.get("content-type", "").split(";")[0].strip().lower()
            )

            # 获取原始数据流
            data_to_write = response.body

            # 写入文件
            with open(output_path, "wb") as f:
                f.write(data_to_write)

            # 计算大小和耗时
            elapsed_time = asyncio.get_event_loop().time() - start_time
            size_bytes = os.path.getsize(output_path)
            size_info = (
                f"{size_bytes / 1024.0:.2f} KB"
                if size_bytes >= 1024
                else f"{size_bytes} B"
            )
            time_info = f"{elapsed_time:.2f}s"

            logger.info(
                f"{progress_info if progress_info else ''} 成功下载: {display_url} [类型: {content_type}] [大小: {size_info}] [耗时: {time_info}] ".strip()
            )

            # --- 图片压缩处理（如启用）---
            # 仅对图片类型进行压缩
            if self.ic and content_type.startswith("image/"):
                try:
                    logger.info(f"尝试压缩图片: {output_path}")
                    self.ic.compress_image(
                        input_path=output_path,
                        output_format=self.output_format,
                        quality=self.compress_quality,
                        overwrite=True,
                    )
                    logger.info(f"图片压缩完成: {output_path}")
                except Exception as e:
                    logger.warning(f"图片压缩失败: {output_path}, 错误: {e}")

            return True

        except Exception as e:
            error_msg = str(e)
            if retry_count < self.max_retries:
                adjust_delay = self.delay_range[1] * (retry_count + 1)
                logger.warning(
                    f"下载失败({retry_count + 1}/{self.max_retries}), {error_msg}. 将在{adjust_delay:.1f}秒后重试...",
                    extra={"progress": f"RETRY {retry_count + 1}"},
                )
                await asyncio.sleep(adjust_delay)
                # 重试时继续使用同一个 session 对象
                return await self._download_single_url(
                    session,
                    url,
                    output_path,
                    user_agent,
                    retry_count + 1,
                    proxy_info,
                    proxy_url,
                )
            else:
                logger.error(
                    f"最终失败: {display_url} (错误: {error_msg})",
                    extra={"progress": "FAIL"},
                )
                return False

    async def _worker(
        self,
        session: AsyncStealthySession,
        queue: asyncio.Queue,
        proxy_info: str,
        proxy_url: Optional[str],
        completed_count: List[int],
        total_tasks: int,
        lock: asyncio.Lock,
    ) -> None:
        """工作线程，复用 session 对象从队列中获取任务并执行下载。进度信息融合到请求提示语句。"""
        while True:
            try:
                url, output_path, user_agent = await queue.get()
                progress_info = None
                async with lock:
                    completed_count[0] += 1
                    progress_info = f"[{completed_count[0]}/{total_tasks}]"
                try:
                    await self._download_single_url(
                        session,
                        url,
                        output_path,
                        user_agent,
                        proxy_info=proxy_info,
                        progress_info=progress_info,
                        proxy_url=proxy_url,
                    )
                    if self.delay_range[0] > 0 or self.delay_range[1] > 0:
                        delay = random.uniform(*self.delay_range)
                        await asyncio.sleep(delay)
                finally:
                    queue.task_done()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"工作线程异常: {e}")

    async def _run_async(
        self,
        tasks: List[Tuple[str, str, Optional[str]]],
        proxy_input: Optional[Union[str, List[str]]] = None,
    ):
        """异步运行并发下载任务，实现 Session 复用。"""
        proxy_list = self._read_proxies(proxy_input)
        proxy_configs = proxy_list if proxy_list else [""]

        logger.info(
            f"配置: 并发={self.max_concurrency}, 代理池大小={len(proxy_configs)}"
        )

        # 使用 AsyncStealthySession，max_pages 用于控制并发标签页数量
        async with AsyncStealthySession(
            headless=self.headless,
            solve_cloudflare=self.solve_cloudflare,
            block_webrtc=self.block_webrtc,
            hide_canvas=self.hide_canvas,
            real_chrome=self.real_chrome,
            timeout=self.timeout * 1000,
            max_pages=self.max_concurrency,
        ) as session:
            queue: asyncio.Queue[Tuple[str, str, Optional[str]]] = asyncio.Queue()
            for task in tasks:
                await queue.put(task)

            actual_workers = min(self.max_concurrency, len(tasks))
            worker_sessions: List[Tuple[AsyncStealthySession, str]] = []

            # 由于 AsyncStealthySession 本身支持并发请求（通过 max_pages），
            # 我们不需要创建多个 session，而是使用同一个 session 并发请求
            # 但为了支持代理轮换，我们需要为每个 worker 分配不同的代理配置
            # 这里我们简化处理：如果需要代理轮换，在 fetch 时动态设置 proxy 参数
            # 由于 scrapling 的 session 级别 proxy 配置限制，我们采用以下策略：
            # - 如果有代理列表，我们在每个请求时动态设置 proxy
            # - 如果没有代理，使用默认配置

            # 进度计数器和锁
            completed_count = [0]  # 用列表包裹以便可变
            total_tasks = len(tasks)
            lock = asyncio.Lock()

            workers = []
            for i in range(actual_workers):
                worker_proxy_url = (
                    proxy_configs[i % len(proxy_configs)] if proxy_configs else None
                )
                p_info = worker_proxy_url if worker_proxy_url else "环境代理"
                workers.append(
                    asyncio.create_task(
                        self._worker(
                            session,
                            queue,
                            p_info,
                            worker_proxy_url,
                            completed_count,
                            total_tasks,
                            lock,
                        )
                    )
                )

            await queue.join()

            for w in workers:
                w.cancel()
            await asyncio.gather(*workers, return_exceptions=True)

            logger.info("所有下载任务已完成。")

    def batch_download(
        self,
        tasks: List[Tuple[str, str]],
        proxy_input: Optional[Union[str, List[str]]] = None,
        output_dir: Optional[str] = None,
    ):
        """
        [公共方法] 通过 Scrapling StealthySession 批量下载网络资源。

        所有下载参数 (headless, timeout, concurrency, retries, delay) 继承自 Downloader 实例。

        Args:
            tasks: 任务列表，每个元素是 (url, output_path) 的元组。
            proxy_input: 代理输入，可以是单个代理字符串、代理列表或代理文件路径。
            output_dir: 可选，如果指定，将所有 output_path 仅为文件名的任务补全为 output_dir/filename。
        Returns:
            True 表示下载过程完成 (不代表所有任务成功)。
        """
        if not tasks:
            logger.warning("任务列表为空，无需下载。")
            return True

        # 如果指定了 output_dir，则将所有 output_path 仅为文件名的任务补全为 output_dir/filename
        processed_tasks: List[Tuple[str, str, Optional[str]]] = []
        for url, output_path in tasks:
            # 判断 output_path 是否为简单的文件名（没有目录分隔符且非绝对路径）
            if (
                output_dir
                and (not os.path.isabs(output_path))
                and (os.path.dirname(output_path) == "")
            ):
                # 仅为文件名，补全为 output_dir/filename
                output_path = os.path.join(output_dir, output_path)
            processed_tasks.append((url, output_path, None))  # None for user_agent

        logger.info(f"--- 启动批量链接下载任务 (总数: {len(processed_tasks)}) ---")

        try:
            # 使用 self._run_async 启动异步下载
            asyncio.run(self._run_async(processed_tasks, proxy_input))
        except KeyboardInterrupt:
            logger.warning("任务被用户中断。")
        except Exception as e:
            logger.error(f"下载任务发生致命错误: {e}")
        return True

    def single_download(
        self,
        url: str,
        output_path: str = "",
        use_remote_name: bool = False,
        output_dir_for_remote_name: str = "./",
        user_agent: Optional[str] = None,
        proxy_input: Optional[Union[str, List[str]]] = None,
        # 单个下载时，可以临时覆盖重试次数
        retries: Optional[int] = None,
    ) -> None:
        """
        [公共方法] 通过 Scrapling StealthySession 下载单个网络资源。

        注意: 此方法将临时设置 max_concurrency=1 且 delay_range=(0.0, 0.0) 执行下载。

        Args:
            url: 必须填写的要请求的 URL。
            output_path: 指定保存文件的完整路径。如果提供，它将覆盖 use_remote_name 的逻辑。
            use_remote_name: 是否使用 URL 猜测的文件名作为保存文件名。
            output_dir_for_remote_name: 如果 use_remote_name 为 True，指定保存的目录。
            user_agent: 可选，为此次请求设置 User-Agent 字符串。
            proxy_input: 代理配置 (同 batch_download)。
            retries: 可选，覆盖 Downloader 实例的 max_retries 设置。
        """

        # 1. 确定最终的保存路径 (output_path 优先)
        final_output_path = output_path
        if not final_output_path:
            if use_remote_name:
                # 猜测文件名
                guessed_filename = _guess_filename_from_url(url)
                final_output_path = os.path.join(
                    output_dir_for_remote_name, guessed_filename
                )
            else:
                # 如果两者都没有指定，默认保存到当前目录，文件名根据 URL 猜测
                guessed_filename = _guess_filename_from_url(url)
                final_output_path = os.path.join("./", guessed_filename)

        # 2. 准备任务列表 (单个任务)
        tasks = [
            (url, final_output_path, user_agent)
        ]  # 任务结构 (url, output_path, user_agent)

        logger.info(f"--- 启动单个链接下载任务: {url} -> {final_output_path} ---")

        # 3. 临时覆盖并发和延迟，创建临时 Downloader 实例来执行
        # 使用 self 的配置，但固定并发=1，延迟=(0.0, 0.0)
        temp_downloader = ScraplingDownloader(
            headless=self.headless,
            timeout=self.timeout,
            delay_range=(0.0, 0.0),  # 单个任务不需要延迟
            max_concurrency=1,  # 单个任务固定并发为 1
            max_retries=retries if retries is not None else self.max_retries,
            # 继承图片压缩配置
            compress_quality=self.compress_quality,
            # 继承 Scrapling 特定配置
            solve_cloudflare=self.solve_cloudflare,
            block_webrtc=self.block_webrtc,
            hide_canvas=self.hide_canvas,
            real_chrome=self.real_chrome,
        )

        try:
            # 4. 运行异步任务
            asyncio.run(temp_downloader._run_async(tasks, proxy_input))
            logger.info(f"单个链接下载完成: {final_output_path}")
        except KeyboardInterrupt:
            logger.warning("任务被用户中断。")
        except Exception as e:
            logger.error(f"下载任务发生致命错误: {e}")


# --- 测试函数 ---


def test_batch_download():
    """测试多个链接批量下载的情况"""
    image_urls = [
        "https://www.gosupps.com/media/catalog/product/cache/25/image/9df78eab33525d08d6e5fb8d27136e95/6/1/61Mfc8jVlQL.jpg",
        "https://www.gosupps.com/media/catalog/product/cache/25/image/9df78eab33525d08d6e5fb8d27136e95/5/1/51Em4E1TwPL.jpg",
        # ... 其他图片URL ...
        # "https://www.velogear.com.au/media/catalog/product/cache/94ef66d09f7a7e8c63df55350acf28cd/m/a/maxxis_flyweight_26_tube_fv.jpg",
    ]
    # 输出目录
    output_dir = "./scrapling_downloads"

    # test_url_1 = (
    #     "https://images.bike24.com/media/1020/i/mb/fc/0d/06/100048-00-d-163801.jpg"
    # )
    # test_url_2 = "https://covers-v2.ryefieldbooks.com/in-print-books/9783161491184"
    # test_url_3 = "https://playwright.dev/"
    # test_url_21 = "https://www.bigw.com.au/medias/sys_master/images/images/h6a/h5f/100887801561118.jpg"

    # output_path_1 = os.path.join(output_dir, "bike24_image.jpg")
    # output_path_2 = os.path.join(output_dir, "ryefieldbooks_cover.webp")
    # output_path_3 = os.path.join(output_dir, "playwright_doc.html")
    # output_path_21 = os.path.join(output_dir, "SK0000004-U-0.jpg")

    # download_tasks: list[tuple[str, str]] = [
    #     (test_url_1, output_path_1),
    #     (test_url_2, output_path_2),
    #     (test_url_3, output_path_3),
    #     (test_url_21, output_path_21),
    # ]
    download_tasks: list[tuple[str, str]] = [
        (url, os.path.join(output_dir, _sanitize_filename(url))) for url in image_urls
    ]

    # 清理旧文件和目录以便测试
    if os.path.exists(output_dir):
        import shutil

        shutil.rmtree(output_dir, ignore_errors=True)
    os.makedirs(output_dir, exist_ok=True)

    # 1. 实例化 Downloader，设置公共配置
    downloader = ScraplingDownloader(
        headless=False,
        max_concurrency=3,
        delay_range=(0.5, 1.0),
        max_retries=1,
        solve_cloudflare=True,
        block_webrtc=True,
    )

    print("--- 启动并发下载任务 (无头模式，并发=3，Session 复用) ---")

    # 2. 调用实例方法进行下载
    downloader.batch_download(
        tasks=download_tasks,
        proxy_input=PROXY,
        output_dir=output_dir,
    )


def test_single_download():
    """测试单个链接下载的情况"""
    # 图片
    test_url_1 = (
        "https://www.velogear.com.au/media/catalog/product/cache/94ef66d09f7a7e8c63df55350acf28cd/m/a/maxxis_flyweight_26_tube_fv.jpg"
        # "https://images.bike24.com/media/1020/i/mb/fc/0d/06/100048-00-d-163801.jpg"
        # "https://www.gosupps.com/media/catalog/product/cache/25/image/9df78eab33525d08d6e5fb8d27136e95/6/1/61Mfc8jVlQL.jpg"
    )
    # 网页(html)
    # test_url_html = "https://www.baidu.com"

    output_dir = "./scrapling_downloads"

    if os.path.exists(output_dir):
        import shutil

        shutil.rmtree(output_dir, ignore_errors=True)
    os.makedirs(output_dir, exist_ok=True)

    # 1. 实例化 Downloader，设置公共配置
    downloader = ScraplingDownloader(
        headless=False,
        timeout=60,
        solve_cloudflare=True,
    )

    print("\n\n=== 示例 1: 指定完整 output_path (图片) ===")
    output_path_1 = os.path.join(output_dir, "img_by_scrapling.jpg")

    # 2. 调用实例方法进行下载
    downloader.single_download(
        url=test_url_1,
        output_path=output_path_1,
        proxy_input=PROXY,
    )

    # print("\n\n=== 示例 2: 使用 use_remote_name 猜测文件名 (HTML) ===")
    # downloader.single_download(
    #     url=test_url_html,
    #     use_remote_name=True,
    #     output_dir_for_remote_name=output_dir,
    # )


# --- 简单使用示例 ---
if __name__ == "__main__":
    test_single_download()
    # test_batch_download()
