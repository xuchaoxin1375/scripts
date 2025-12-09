import asyncio
import logging
import os
import random
import re
import shutil
import unicodedata
from typing import Any, Dict, List, Optional, Tuple, Union
from urllib.parse import urlparse

from playwright.async_api import BrowserContext, Page, async_playwright

# 配置一个基本的logger，避免在外部调用时没有handler
logger = logging.getLogger("browser_downloader")
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

    # 确保有扩展名，如果 URL 中没有，Playwright 下载的默认行为是根据 Content-Type
    # 但此处我们无法提前知道 Content-Type，因此如果 URL 路径中没有点号，则假定为 .html
    if "." not in filename:
        filename = filename + ".html"

    return _sanitize_filename(filename)


class BrowserDownloader:
    """
    基于 Playwright 的网络资源下载器。
    专用于下载那些需要完整浏览器环境才能获取的资源 (如动态加载的图片或受保护的网页内容)。
    支持指定输出路径、代理配置和并发控制。
    """

    def __init__(
        self,
        headless: bool = True,
        timeout: int = 30,
        delay_range: Tuple[float, float] = (1.0, 3.0),
        max_concurrency: int = 3,
        max_retries: int = 2,
    ):
        """
        初始化下载器。

        Args:
            headless: 是否启用无头模式 (不显示浏览器窗口)。
            timeout: 单次请求的超时时间 (秒)。
            delay_range: 每次下载任务之间随机延迟的时间范围 (min, max)。
            max_concurrency: 最大并发工作线程数。
            max_retries: 单个 URL 下载失败后的最大重试次数。
        """
        self.headless = headless
        self.timeout = timeout
        self.delay_range = delay_range
        self.max_concurrency = max_concurrency
        self.max_retries = max_retries

    @staticmethod
    def _read_proxies(proxy_input: Optional[Union[str, List[str]]]) -> List[str]:
        """
        从文件路径或直接的代理字符串中读取代理列表。
        一个 None 或空列表/空字符串表示直连。
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

    # ... (_get_proxy_config 保持不变) ...
    def _get_proxy_config(
        self, proxy_list: List[str], worker_id: int
    ) -> Optional[Dict[str, str]]:
        """根据 worker_id 和代理列表获取 Playwright 代理配置。"""
        if not proxy_list:
            return None

        proxy_url = proxy_list[worker_id % len(proxy_list)]
        return {"server": proxy_url}

    async def _download_single_url(
        self,
        page: Page,  # 接收复用的 page 对象
        url: str,
        output_path: str,
        user_agent: Optional[
            str
        ] = None,  # 新增 user_agent 参数，但实际上 Playwright Context 已经设置了
        retry_count: int = 0,
        proxy_info: str = "直连",
    ) -> bool:
        """核心下载逻辑：下载单个 URL 并保存到指定路径 (复用 Page)。"""
        start_time = asyncio.get_event_loop().time()
        display_url = url

        # 确保输出目录存在
        output_dir = os.path.dirname(output_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir, exist_ok=True)

        # 检查是否已存在 (简单检查，不实现恢复机制)
        if (
            os.path.exists(output_path)
            and os.path.getsize(output_path) > 0
            and retry_count == 0
        ):
            logger.info(f"文件已存在，跳过: {output_path}", extra={"progress": "SKIP"})
            return True

        try:
            logger.info(
                f"开始请求: {display_url} [代理: {proxy_info}] -> {os.path.basename(output_path)}"
            )

            # 使用复用的 page 发起请求
            # wait_until="networkidle" 确保页面完全加载/动态资源加载
            response = await page.goto(
                url, timeout=self.timeout * 1000, wait_until="networkidle"
            )

            if not response:
                raise Exception("未获取到有效响应 (Response is None)")

            if response.status >= 400:
                raise Exception(f"HTTP 状态码错误: {response.status}")

            content_type = (
                response.headers.get("content-type", "").split(";")[0].strip().lower()
            )

            # 获取原始数据流
            data_to_write = await response.body()

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
                f"成功下载: {display_url} [类型: {content_type}] [大小: {size_info}] [耗时: {time_info}]"
            )
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
                # 重试时继续使用同一个 page 对象
                return await self._download_single_url(
                    page, url, output_path, user_agent, retry_count + 1, proxy_info
                )
            else:
                logger.error(
                    f"最终失败: {display_url} (错误: {error_msg})",
                    extra={"progress": "FAIL"},
                )
                return False

    async def _worker(self, page: Page, queue: asyncio.Queue, proxy_info: str) -> None:
        """工作线程，复用 page 对象从队列中获取任务并执行下载。"""
        while True:
            try:
                # 任务数据结构: (url, output_path, user_agent)
                url, output_path, user_agent = await queue.get()
                try:
                    await self._download_single_url(
                        page, url, output_path, user_agent, proxy_info=proxy_info
                    )

                    # 随机延迟
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
        tasks,  # 任务包含 (url, output_path, user_agent)
        proxy_input: Optional[Union[str, List[str]]] = None,
    ) -> None:
        """异步运行并发下载任务，实现 Context 和 Page 复用。"""
        proxy_list = self._read_proxies(proxy_input)
        proxy_configs = proxy_list if proxy_list else [None]

        logger.info(
            f"配置: 并发={self.max_concurrency}, 代理池大小={len(proxy_configs)}"
        )

        async with async_playwright() as p:
            launch_options = {
                "headless": self.headless,
                "args": [
                    "--disable-blink-features=AutomationControlled",
                ],
            }

            browser = await p.chromium.launch(**launch_options)

            queue = asyncio.Queue()
            for task in tasks:
                await queue.put(task)

            actual_workers = min(self.max_concurrency, len(tasks))
            worker_slots: List[Tuple[BrowserContext, Page, str]] = []

            for i in range(actual_workers):
                worker_proxy_url = proxy_configs[i % len(proxy_configs)]

                # 默认 User Agent，如果任务提供了新的 UA，会在 Page.goto 时自动应用
                default_user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

                context_args: Dict[str, Any] = {
                    "user_agent": default_user_agent,  # Context 级别的 UA
                    "viewport": {"width": 1366, "height": 768},
                }

                if worker_proxy_url:
                    context_args["proxy"] = {"server": worker_proxy_url}
                    p_info = worker_proxy_url
                else:
                    p_info = "直连"

                ctx = await browser.new_context(**context_args)
                pg = await ctx.new_page()
                worker_slots.append((ctx, pg, p_info))

            workers = []
            for ctx, pg, p_info in worker_slots:
                workers.append(asyncio.create_task(self._worker(pg, queue, p_info)))

            await queue.join()  # 等待所有任务完成

            # 清理资源
            for w in workers:
                w.cancel()
            await asyncio.gather(*workers, return_exceptions=True)

            for ctx, pg, _ in worker_slots:
                try:
                    await pg.close()
                    await ctx.close()
                except:
                    pass

            await browser.close()
            logger.info("所有下载任务已完成。")


def download_by_browser(
    tasks: List[Tuple[str, str]],
    headless: bool = True,
    timeout: int = 30,
    delay_range: Tuple[float, float] = (1.0, 3.0),
    max_concurrency: int = 3,
    max_retries: int = 2,
    proxy_input = None,
) -> None:
    """
    通过 Playwright 浏览器环境下载网络资源 (批量接口)。

    Args:
        tasks: 任务列表，每个元素是 (url, output_path) 的元组。
        ... (其他参数同上) ...
    """
    if not tasks:
        logger.warning("任务列表为空，无需下载。")
        return

    # 扩展任务列表以包含 user_agent (保持 None)
    full_tasks = [(url, output_path, None) for url, output_path in tasks]

    downloader = BrowserDownloader(
        headless=headless,
        timeout=timeout,
        delay_range=delay_range,
        max_concurrency=max_concurrency,
        max_retries=max_retries,
    )

    try:
        asyncio.run(downloader._run_async(full_tasks, proxy_input))
    except KeyboardInterrupt:
        logger.warning("任务被用户中断。")
    except Exception as e:
        logger.error(f"下载任务发生致命错误: {e}")


def download_by_browser_single(
    url: str,
    output_path: str = "",
    use_remote_name: bool = False,
    output_dir_for_remote_name: str = "./",
    user_agent: Optional[str] = None,
    timeout: int = 30,
    headless: bool = True,
    proxy_input: Optional[Union[str, List[str]]] = None,
    retries: int = 2,
) -> None:
    """
    通过 Playwright 浏览器环境下载单个网络资源。

    Args:
        url: 必须填写的要请求的 URL。
        output_path: 指定保存文件的完整路径。如果提供，它将覆盖 use_remote_name 的逻辑。
        use_remote_name: 是否使用 URL 猜测的文件名作为保存文件名。
        output_dir_for_remote_name: 如果 use_remote_name 为 True，指定保存的目录。
        user_agent: 可选，为此次请求设置 User-Agent 字符串。
        timeout: 请求超时时间 (秒)。
        headless: 是否启用无头模式。
        proxy_input: 代理配置 (同 download_by_browser)。
        retries: 单个 URL 下载失败后的最大重试次数。
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

    logger.info(f"--- 启动单个链接下载任务 ---")

    # 3. 实例化 Downloader (使用 max_concurrency=1，因为只有一个任务)
    downloader = BrowserDownloader(
        headless=headless,
        timeout=timeout,
        # 单个任务时，不进行延迟，或者只使用较短的固定延迟 (0, 0)
        delay_range=(0.0, 0.0),
        max_concurrency=1,
        max_retries=retries,
    )

    try:
        # 4. 运行异步任务
        asyncio.run(downloader._run_async(tasks, proxy_input))
        logger.info(f"单个链接下载完成: {final_output_path}")
    except KeyboardInterrupt:
        logger.warning("任务被用户中断。")
    except Exception as e:
        logger.error(f"下载任务发生致命错误: {e}")


def test_batch_download():
    """测试多个链接批量下载的情况"""
    test_url_1 = (
        "https://images.bike24.com/media/1020/i/mb/fc/0d/06/100048-00-d-163801.jpg"
    )
    test_url_2 = "https://covers-v2.ryefieldbooks.com/in-print-books/9783161491184"
    test_url_3 = "https://playwright.dev/"
    test_url_21 = "https://www.bigw.com.au/medias/sys_master/images/images/h6a/h5f/100887801561118.jpg"

    output_dir = "./browser_downloads_optimized"
    output_path_1 = os.path.join(output_dir, "bike24_image.jpg")
    output_path_2 = os.path.join(output_dir, "ryefieldbooks_cover.webp")
    output_path_3 = os.path.join(output_dir, "playwright_doc.html")
    output_path_21 = os.path.join(output_dir, "SK0000004-U-0.jpg")

    download_tasks = [
        (test_url_1, output_path_1),
        (test_url_2, output_path_2),
        (test_url_3, output_path_3),
        (test_url_21, output_path_21),
        # 添加更多任务以测试并发和复用
        # ("https://example.com/1", os.path.join(output_dir, "example_1.html")),
        # ("https://example.com/2", os.path.join(output_dir, "example_2.html")),
        # ("https://example.com/3", os.path.join(output_dir, "example_3.html")),
    ]

    # 清理旧文件和目录以便测试
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir, ignore_errors=True)
    os.makedirs(output_dir, exist_ok=True)

    print("--- 启动并发下载任务 (无头模式，并发=3，Page 复用) ---")
    download_by_browser(
        tasks=download_tasks,
        headless=False,
        max_concurrency=3,  # 此时只启动 3 个 Page/Context，所有任务将共享这 3 个 Page
        delay_range=(0.5, 1.0),
        proxy_input="http://127.0.0.1:8800",
    )


def test_single_download():
    """测试单个链接下载的情况"""
    test_url_1 = (
        "https://images.bike24.com/media/1020/i/mb/fc/0d/06/100048-00-d-163801.jpg"
    )
    test_url_4 = "https://www.baidu.com"
    output_dir = "./browser_downloads_single_test"

    if os.path.exists(output_dir):

        shutil.rmtree(output_dir, ignore_errors=True)
    os.makedirs(output_dir, exist_ok=True)

    print("\n\n=== 示例 1: 指定完整 output_path (图片) ===")
    output_path_1 = os.path.join(output_dir, "bike24_test_011234.jpg")

    download_by_browser_single(
        url=test_url_1,
        output_path=output_path_1,
        headless=False,
        timeout=60,
    )

    print("\n\n=== 示例 2: 使用 use_remote_name 猜测文件名 (HTML) ===")
    download_by_browser_single(
        url=test_url_4,
        use_remote_name=True,
        output_dir_for_remote_name=output_dir,
        headless=False,
    )


# --- 简单使用示例 ---
if __name__ == "__main__":
    test_single_download()
    # test_batch_download()
