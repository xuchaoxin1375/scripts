"""
@last update: 2025-11-17 (Updated for generic file support)
简单使用示例:
推荐使用pwsh作为命令行环境(预设$localhost为当前桌面上的localhost目录)

方案1
ls *.txt|%{python $localhost/get_source.py $_ -o htmls -p $localhost/proxies_nolimit.conf -c 2 -r 1 -t 100 -d 1-3 }

方案2
cd $localhost/demo.com #进入到存放url文本文件的目录下
ls *.txt|%{python $pys/get_source.py $_ -o htmls -p $pys/proxies_nolimit.conf -c 2 -r 1 -t 120 -d 1-3 }
"""

import argparse
import asyncio
import os
import random
import logging
import json
import re
import mimetypes  # 新增：用于猜测文件后缀
from urllib.parse import urlparse
from datetime import datetime
from playwright.async_api import async_playwright
import unicodedata
import time

# 强制设置Python输出编码为utf-8，防止Windows终端乱码
os.environ["PYTHONIOENCODING"] = "utf-8"


class UnicodeSafeStreamHandler(logging.StreamHandler):
    """处理控制台输出的Unicode编码问题"""

    def emit(self, record):
        try:
            msg = self.format(record)
            stream = self.stream
            # 强制用utf-8编码输出，防止Windows终端乱码
            msg = msg.encode("utf-8", errors="replace").decode("utf-8")
            stream.write(msg + self.terminator)
            self.flush()
        except Exception:
            self.handleError(record)


class WebSourceDownloader:
    """网络资源下载器 (通用版)
    支持 HTML (动态渲染), XML, JSON, GZ, 图片等任意格式。
    """

    def __init__(
        self,
        output_dir,
        timeout,
        delay_range,
        headless,
        proxy_configs,
        max_concurrency,
        max_retries,
        input_file,
        allow_direct=False,
    ):
        self.output_dir = output_dir
        self.timeout = timeout
        self.delay_range = delay_range
        self.headless = headless
        self.proxy_configs = proxy_configs if proxy_configs else []
        self.allow_direct = allow_direct
        if allow_direct:
            self.proxy_configs.append(None)  # None 表示直连
        self.max_concurrency = max_concurrency
        self.current_concurrency = max_concurrency
        self.max_retries = max_retries
        self.input_file = input_file

        # 确保输出目录存在
        os.makedirs(self.output_dir, exist_ok=True)

        # 初始化日志目录
        self.log_dir = os.path.join(self.output_dir, "_logs")
        os.makedirs(self.log_dir, exist_ok=True)

        # 初始化日志系统
        self._setup_logging()

        # 状态管理
        self.state = {
            "completed": {},  # 键是 URL，值是 True
            "failed": {},     # 键是 URL，值是 True
            "total_count": 0,
            "success_count": 0,
            "fail_count": 0,
        }
        self._load_state()

    def _setup_logging(self):
        """配置日志系统"""
        self.logger = logging.getLogger("__main__")
        self.logger.setLevel(logging.INFO)

        if self.logger.hasHandlers():
            self.logger.handlers.clear()

        file_handler = logging.FileHandler(
            os.path.join(self.log_dir, "download.log"), encoding="utf-8"
        )
        fmt = "%(asctime)s [%(levelname)s] [%(progress)s] %(message)s"
        file_handler.setFormatter(
            logging.Formatter(fmt, datefmt="%Y-%m-%d %H:%M:%S")
        )

        console_handler = UnicodeSafeStreamHandler()
        console_handler.setFormatter(
            logging.Formatter(fmt, datefmt="%H:%M:%S")
        )

        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)

    def _load_state(self):
        """加载下载状态"""
        state_file = os.path.join(self.log_dir, "download_state.json")
        if os.path.exists(state_file):
            try:
                with open(state_file, "r", encoding="utf-8") as f:
                    self.state = json.load(f)
                self.logger.info(
                    f"成功加载上次进度: 已完成 {self.state['success_count']} 个, 失败 {self.state['fail_count']} 个。",
                    extra={"progress": "RESUME"},
                )
            except Exception as e:
                self.logger.warning(
                    f"加载状态文件失败: {str(e)}。将从零开始。",
                    extra={"progress": "INIT"},
                )
        else:
            self.logger.info(
                "未找到上次进度文件,将从零开始。", extra={"progress": "INIT"}
            )

    def _save_state(self):
        """保存下载状态"""
        state_file = os.path.join(self.log_dir, "download_state.json")
        try:
            with open(state_file, "w", encoding="utf-8") as f:
                json.dump(self.state, f, indent=2, ensure_ascii=False)
        except Exception as e:
            self.logger.error(f"保存状态文件失败: {str(e)}", extra={"progress": "SAVE"})

    def _sanitize_filename(self, filename):
        """清理文件名"""
        filename = unicodedata.normalize("NFKD", filename)
        filename = filename.encode("ascii", "ignore").decode("ascii")
        filename = re.sub(r"[^\w\-_.]", "_", filename)
        return filename[:200]

    def get_progress(self, index):
        return f"{index}/{self.state['total_count']}"

    def _get_proxy_for_worker(self, worker_id=0):
        if not self.proxy_configs:
            return None
        return self.proxy_configs[worker_id % len(self.proxy_configs)]

    async def download_url(
        self, context, page, url, index, retry_count=0, worker_id=0, proxy_info=None
    ):
        """下载单个URL (通用文件支持)"""
        display_url = url
        start_time = time.time()

        try:
            # 1. 检查状态
            if url in self.state["completed"]:
                self.logger.info(
                    f"跳过已完成: {display_url}",
                    extra={"progress": self.get_progress(index)},
                )
                return True

            if proxy_info is None:
                proxy_info = "直连"

            self.logger.info(
                f"开始请求: {display_url} [代理: {proxy_info}]",
                extra={"progress": self.get_progress(index)},
            )

            # 2. 发起请求，获取响应对象
            # wait_until="commit" 确保至少收到了响应头，如果是大文件，不用等全下完再处理
            response = await page.goto(
                url, timeout=self.timeout * 1000, wait_until="commit"
            )
            
            # 尝试等待网络空闲 (兼容动态网页加载)，如果是纯文件下载，这里可能会超时，但不影响
            try:
                await page.wait_for_load_state("networkidle", timeout=5000)
            except Exception:
                pass

            if not response:
                raise Exception("未获取到有效响应 (Response is None)")

            if response.status >= 400:
                raise Exception(f"HTTP 状态码错误: {response.status}")

            # 3. 分析文件类型和后缀
            content_type = response.headers.get("content-type", "").split(";")[0].strip().lower()
            parsed = urlparse(url)
            path = parsed.path
            
            # 获取基础文件名
            original_filename = os.path.basename(path) if path and path != "/" else "index"
            base_name_without_ext = os.path.splitext(original_filename)[0]
            if not base_name_without_ext:
                base_name_without_ext = "index"

            # 尝试从URL获取后缀
            file_ext = os.path.splitext(path)[1]
            
            # 如果URL无后缀，从 Content-Type 猜测
            if not file_ext:
                file_ext = mimetypes.guess_extension(content_type) or ""
                # 修正常见类型
                if "text/html" in content_type and not file_ext:
                    file_ext = ".html"
                elif "text/plain" in content_type and not file_ext:
                    file_ext = ".txt"

            # 4. 确定保存路径
            domain_dir = self._sanitize_filename(parsed.netloc)
            safe_base_name = self._sanitize_filename(base_name_without_ext)
            url_hash = str(abs(hash(url)))[:8]
            
            filename = f"{safe_base_name}-{url_hash}{file_ext}"
            output_path = os.path.join(self.output_dir, domain_dir, filename)
            os.makedirs(os.path.dirname(output_path), exist_ok=True)

            # 5. 获取数据 (分流处理 HTML vs 二进制)
            is_renderable_html = "text/html" in content_type
            data_to_write = None
            
            if is_renderable_html:
                # 策略 A: 动态网页，获取渲染后的 DOM
                content = await page.content()
                data_to_write = content.encode("utf-8") # 转为bytes
            else:
                # 策略 B: 图片/压缩包/XML/JSON，获取原始流
                data_to_write = await response.body()

            # 6. 写入文件 (统一使用二进制模式)
            elapsed_time = time.time() - start_time
            time_info = f"{elapsed_time:.2f}s"

            with open(output_path, "wb") as f:
                f.write(data_to_write)

            # 计算大小
            try:
                size_bytes = os.path.getsize(output_path)
                if size_bytes < 1024:
                    size_info = f"{size_bytes} B"
                else:
                    size_info = f"{size_bytes / 1024.0:.2f} KB"
            except Exception:
                size_info = "未知大小"

            # 更新成功状态
            self.state["completed"][url] = True
            self.state["failed"].pop(url, None)
            self.state["success_count"] += 1
            self._save_state()

            self.logger.info(
                f"成功下载: {display_url} -> {output_path} [类型: {content_type}] [大小: {size_info}] [耗时: {time_info}]",
                extra={"progress": self.get_progress(index)},
            )
            return True

        except Exception as e:
            error_msg = str(e)
            if retry_count < self.max_retries:
                adjust_delay = min(5, self.delay_range[1] * (retry_count + 1))
                self.logger.warning(
                    f"下载失败({retry_count + 1}/{self.max_retries}), {error_msg}. 将在{adjust_delay:.1f}秒后重试...",
                    extra={"progress": self.get_progress(index)},
                )
                await asyncio.sleep(adjust_delay)
                return await self.download_url(
                    context, page, url, index, retry_count + 1, worker_id, proxy_info
                )
            else:
                self.state["failed"][url] = True
                self.state["completed"].pop(url, None)
                self.state["fail_count"] += 1
                self._save_state()
                self.logger.error(
                    f"最终失败: {display_url} (错误: {error_msg})",
                    extra={"progress": self.get_progress(index)},
                )
                if self.current_concurrency > 1:
                    self.current_concurrency = max(1, int(self.current_concurrency * 0.8))
                return False

    async def worker(self, context, page, queue, worker_id, proxy_info="直连"):
        """工作线程"""
        try:
            while True:
                index, url = await queue.get()
                try:
                    await self.download_url(
                        context,
                        page,
                        url,
                        index,
                        worker_id=worker_id,
                        proxy_info=proxy_info,
                    )
                    if self.delay_range[0] > 0 or self.delay_range[1] > 0:
                        delay = random.uniform(*self.delay_range)
                        await asyncio.sleep(delay)
                finally:
                    queue.task_done()
        finally:
            pass

    async def run(self, urls):
        """运行下载任务"""
        self.state["total_count"] = len(urls)
        self.state["success_count"] = len(self.state["completed"])
        self.state["fail_count"] = len(self.state["failed"])
        self._save_state()

        pending_urls = [
            url
            for url in urls
            if url not in self.state["completed"] and url not in self.state["failed"]
        ]
        pending_count = len(pending_urls)
        processed_count = self.state["success_count"] + self.state["fail_count"]

        self.logger.info(
            f"总URL数: {len(urls)}, 待下载: {pending_count}, 已处理: {processed_count} (成功 {self.state['success_count']}, 失败 {self.state['fail_count']})",
            extra={"progress": "INIT"},
        )

        if not pending_urls:
            self.logger.info("所有URL已处理完毕", extra={"progress": "DONE"})
            return

        async with async_playwright() as p:
            launch_options = {
                "headless": self.headless,
                "args": [
                    "--disable-blink-features=AutomationControlled",
                    "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
                ],
            }

            browser = await p.chromium.launch(**launch_options)

            if self.proxy_configs:
                proxy_desc = "、".join([p or "直连" for p in self.proxy_configs])
                self.logger.info(f"[CONFIG] 代理池: {proxy_desc}", extra={"progress": "CONFIG"})

            queue = asyncio.Queue()
            for index, url in enumerate(urls, 1):
                if url in pending_urls:
                    await queue.put((index, url))

            actual_workers = min(self.max_concurrency, pending_count)
            if actual_workers != self.max_concurrency:
                self.logger.info(
                    f"调整并发数: {self.max_concurrency} -> {actual_workers}",
                    extra={"progress": "CONFIG"},
                )
            self.current_concurrency = actual_workers

            worker_slots = []
            for i in range(self.current_concurrency):
                worker_proxy = self._get_proxy_for_worker(i)
                context_args = {
                    "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
                    "viewport": {"width": 1366, "height": 768},
                }
                if worker_proxy:
                    context_args["proxy"] = {"server": worker_proxy}
                    p_info = worker_proxy
                else:
                    p_info = "直连"
                
                ctx = await browser.new_context(**context_args)
                pg = await ctx.new_page()
                worker_slots.append((ctx, pg, p_info))

            workers = []
            for i, (ctx, pg, p_info) in enumerate(worker_slots):
                workers.append(
                    asyncio.create_task(self.worker(ctx, pg, queue, i, p_info))
                )

            await queue.join()

            for w in workers:
                w.cancel()
            await asyncio.gather(*workers, return_exceptions=True)

            for ctx, pg, _ in worker_slots:
                try:
                    await pg.close()
                    await ctx.close()
                except:
                    pass

            self.logger.info(
                f"任务结束: 成功 {self.state['success_count']}/{len(urls)}, 失败 {self.state['fail_count']}",
                extra={"progress": "DONE"},
            )


def read_urls_from_file(file_path):
    """读取URL文件"""
    encodings = ["utf-8", "gbk", "gb2312", "latin1"]
    for enc in encodings:
        try:
            with open(file_path, "r", encoding=enc) as f:
                urls = [
                    line.strip()
                    for line in f
                    if line.strip() and not line.startswith("#")
                ]
            return urls
        except UnicodeDecodeError:
            continue
    raise RuntimeError(f"无法读取文件: {file_path}")


def read_proxies_from_file(file_path):
    """读取代理文件"""
    if not file_path:
        return []
    encodings = ["utf-8", "gbk", "gb2312", "latin1"]
    for enc in encodings:
        try:
            with open(file_path, "r", encoding=enc) as f:
                proxies = [
                    line.strip()
                    for line in f
                    if line.strip() and not line.startswith("#")
                ]
            return proxies
        except UnicodeDecodeError:
            continue
        except Exception:
            return []
    return []


def parse_delay_range(delay_str):
    try:
        min_delay, max_delay = map(float, delay_str.split("-"))
        return (min_delay, max_delay)
    except:
        raise argparse.ArgumentTypeError("格式错误，应为 'min-max' (如 1.0-3.0)")


def parse_args():
    parser = argparse.ArgumentParser(description="通用网页/文件下载工具 (Playwright)")
    parser.add_argument("input_file", help="URL列表文件路径")
    parser.add_argument("-o", "--output", default="downloads", help="输出根目录")
    parser.add_argument("-t", "--timeout", type=int, default=30, help="超时时间(秒)")
    parser.add_argument("-d", "--delay", type=parse_delay_range, default="1.0-3.0", help="随机延迟(秒)")
    parser.add_argument("--headless", action="store_true", help="无头模式 (不显示浏览器)")
    parser.add_argument("-p", "--proxy-file", help="代理列表文件")
    parser.add_argument("--allow-direct", action="store_true", help="允许混合直连模式")
    parser.add_argument("-c", "--concurrency", type=int, default=3, help="并发数")
    parser.add_argument("-r", "--retries", type=int, default=2, help="重试次数")
    return parser.parse_args()


def main():
    args = parse_args()
    input_basename = os.path.basename(args.input_file)
    input_name_safe = (
        input_basename.split(".")[0] if "." in input_basename else input_basename
    )
    output_dir = os.path.join(args.output, input_name_safe)

    urls = read_urls_from_file(args.input_file)
    if not urls:
        print("没有找到有效的URL")
        return

    print(f"=== 下载任务启动 ===")
    print(f"目标目录: {output_dir}")
    print(f"URL数量: {len(urls)}")
    print(f"配置: 并发={args.concurrency}, 超时={args.timeout}s")

    proxy_list = []
    if args.proxy_file:
        proxy_list = read_proxies_from_file(args.proxy_file)
        print(f"加载代理: {len(proxy_list)} 个")

    downloader = WebSourceDownloader(
        output_dir=output_dir,
        timeout=args.timeout,
        delay_range=args.delay,
        headless=args.headless,
        proxy_configs=proxy_list,
        max_concurrency=args.concurrency,
        max_retries=args.retries,
        input_file=args.input_file,
        allow_direct=args.allow_direct,
    )

    asyncio.run(downloader.run(urls))


if __name__ == "__main__":
    try:
        import playwright
    except ImportError:
        print("错误: 请安装 playwright (pip install playwright)")
        exit(1)
    main()