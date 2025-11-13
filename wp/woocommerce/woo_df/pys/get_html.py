"""
@last update:20251113-2110
简单使用示例:(更多细节查看相关文档)
推荐使用pwsh作为命令行环境(预设$localhost为当前桌面上的localhost目录)
ls *.txt|%{python $localhost/get_html.py $_ -o htmls -p $localhost/proxies_nolimit.conf -c 2 -r 1 -t 100 -d 1-3 }

"""

import argparse
import asyncio
import os
import random
import logging
import json
import sys
import re
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


class SmartDownloader:
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

        # 初始化日志目录 (始终在输出目录下的 _logs)
        self.log_dir = os.path.join(self.output_dir, "_logs")
        os.makedirs(self.log_dir, exist_ok=True)

        # 初始化日志系统
        self._setup_logging()

        # 状态管理
        self.state = {
            "completed": {},  # 键是 URL，值是 True (或失败信息)
            "failed": {},  # 键是 URL，值是 True (或失败信息)
            "total_count": 0,
            "success_count": 0,
            "fail_count": 0,
        }
        self._load_state()

    def _setup_logging(self):
        """配置日志系统"""
        self.logger = logging.getLogger("SmartDownloader")
        self.logger.setLevel(logging.INFO)

        # 清除已有的handlers，防止重复日志
        if self.logger.hasHandlers():
            self.logger.handlers.clear()

        # 文件日志处理器(UTF-8编码)
        file_handler = logging.FileHandler(
            os.path.join(self.log_dir, "download.log"), encoding="utf-8"
        )
        file_handler.setFormatter(
            logging.Formatter(
                "%(asctime)s [%(levelname)-7s] [%(progress)s] %(message)s",
                datefmt="%Y-%m-%d %H:%M:%S",
            )
        )

        # 控制台日志处理器
        console_handler = UnicodeSafeStreamHandler()
        console_handler.setFormatter(
            logging.Formatter(
                "%(asctime)s [%(levelname)-7s] [%(progress)s] %(message)s",
                datefmt="%H:%M:%S",
            )
        )

        self.logger.addHandler(file_handler)
        self.logger.addHandler(console_handler)

    def _load_state(self):
        """加载下载状态 (精简加载)"""
        state_file = os.path.join(self.log_dir, "download_state.json")
        if os.path.exists(state_file):
            try:
                with open(state_file, "r", encoding="utf-8") as f:
                    loaded_state = json.load(f)

                    # **精简优化: 仅加载 URL 列表，值统一设置为 True**
                    self.state["completed"] = {
                        url: True for url in loaded_state.get("completed", {}).keys()
                    }
                    self.state["failed"] = {
                        url: True for url in loaded_state.get("failed", {}).keys()
                    }

                    self.state["success_count"] = len(self.state["completed"])
                    self.state["fail_count"] = len(self.state["failed"])

                self.logger.info(
                    f"成功加载上次进度: 已完成 {self.state['success_count']} 个, 失败 {self.state['fail_count']} 个。",
                    extra={"progress": "RESUME"},
                )
            except Exception as e:
                self.logger.warning(
                    f"加载状态文件失败或文件格式错误: {str(e)}。将从零开始。",
                    extra={"progress": "INIT"},
                )

    def _save_state(self):
        """保存下载状态 (精简保存: 只记录 URL 键)"""
        state_file = os.path.join(self.log_dir, "download_state.json")
        try:
            # **精简优化: 只保存 URL 键的列表，或以 URL 为键，True 为值的字典**
            state_to_save = {
                # 记录 URL 集合，值设为 True，以保持字典结构，方便 future-proof
                "completed": {url: True for url in self.state["completed"].keys()},
                "failed": {url: True for url in self.state["failed"].keys()},
                "total_count": self.state["total_count"],
            }
            with open(state_file, "w", encoding="utf-8") as f:
                json.dump(state_to_save, f, indent=2, ensure_ascii=False)
        except Exception as e:
            self.logger.error(f"保存状态文件失败: {str(e)}", extra={"progress": "SAVE"})

    def _sanitize_filename(self, filename):
        """清理文件名中的特殊字符"""
        filename = unicodedata.normalize("NFKD", filename)
        filename = filename.encode("ascii", "ignore").decode("ascii")
        filename = re.sub(r"[^\w\-_.]", "_", filename)
        return filename[:200]

    def get_progress(self, index):
        """获取进度信息"""
        return f"{index}/{self.state['total_count']}"

    def _get_proxy_for_worker(self, worker_id=0):
        """为整个worker分配固定代理（用于复用context）。"""
        if not self.proxy_configs:
            return None
        return self.proxy_configs[worker_id % len(self.proxy_configs)]

    async def download_url(
        self, context, page, url, index, retry_count=0, worker_id=0, proxy_info=None
    ):
        """下载单个URL"""

        display_url = url[:100] + "..." if len(url) > 100 else url
        start_time = time.time()

        try:
            # 文件路径生成逻辑不变
            parsed = urlparse(url)
            path = parsed.path[1:] if parsed.path.startswith("/") else parsed.path
            domain_dir = self._sanitize_filename(parsed.netloc)
            base_filename = self._sanitize_filename(path) if path else "index"
            url_hash = str(abs(hash(url)))[:8]
            filename = f"{base_filename}-{url_hash}.html"
            output_path = os.path.join(self.output_dir, domain_dir, filename)

            # 检查是否已下载 (断点续传的关键)
            if url in self.state["completed"]:
                self.logger.info(
                    f"跳过已完成: {display_url}",
                    extra={"progress": self.get_progress(index)},
                )
                return True

            os.makedirs(os.path.dirname(output_path), exist_ok=True)

            if proxy_info is None:
                proxy_info = "直连"

            try:
                # 请求开始日志
                self.logger.info(
                    f"开始请求: {display_url} [代理: {proxy_info}]",
                    extra={"progress": self.get_progress(index)},
                )

                await page.goto(
                    url, timeout=self.timeout * 1000, wait_until="networkidle"
                )

                content = await page.content()
                elapsed_time = time.time() - start_time
                time_info = f"{elapsed_time:.2f}s"

                with open(output_path, "w", encoding="utf-8") as f:
                    f.write(content)

                try:
                    size_bytes = os.path.getsize(output_path)
                    size_kb = size_bytes / 1024.0
                    size_info = f"{size_kb:.2f} KB"
                except Exception:
                    size_info = "未知大小"

                # 更新状态：只记录 URL
                self.state["completed"][url] = True
                self.state["failed"].pop(url, None)

                self.state["success_count"] += 1
                self._save_state()

                # 成功日志
                self.logger.info(
                    f"成功下载: {display_url} -> {output_path} [大小: {size_info}] [耗时: {time_info}] [代理: {proxy_info}] [源文件: {os.path.basename(self.input_file)}]",
                    extra={"progress": self.get_progress(index)},
                )
            except Exception as e:
                self.logger.warning(f"页面出现问题: {str(e)}，重试...")
                raise
            finally:
                pass
            return True

        except Exception as e:
            error_msg = str(e)
            if retry_count < self.max_retries:
                # 重试逻辑不变
                adjust_delay = min(5, self.delay_range[1] * (retry_count + 1))
                self.logger.warning(
                    f"下载失败({retry_count + 1}/{self.max_retries}), {error_msg}. 将在{adjust_delay:.1f}秒后重试...",
                    extra={"progress": self.get_progress(index)},
                )
                await asyncio.sleep(adjust_delay)
                return await self.download_url(
                    context,
                    page,
                    url,
                    index,
                    retry_count + 1,
                    worker_id,
                    proxy_info=proxy_info,
                )
            else:
                # 最终失败：只记录 URL
                self.state["failed"][url] = True
                self.state["completed"].pop(url, None)

                self.state["fail_count"] += 1
                self._save_state()
                self.logger.error(
                    f"最终失败: {display_url} (错误: {error_msg})",
                    extra={"progress": self.get_progress(index)},
                )
                # 自适应降低并发数逻辑不变
                if self.current_concurrency > 1:
                    self.current_concurrency = max(
                        1, int(self.current_concurrency * 0.8)
                    )
                    self.logger.warning(
                        f"降低并发数到 {self.current_concurrency}",
                        extra={"progress": "ADAPTIVE"},
                    )
                return False

    async def worker(self, context, page, queue, worker_id, proxy_info="直连"):
        """工作线程函数"""
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

        # 重新根据状态文件计算成功和失败数 (以防用户手动修改状态文件)
        self.state["success_count"] = len(self.state["completed"])
        self.state["fail_count"] = len(self.state["failed"])
        self._save_state()

        # 过滤已完成和已失败的 URL
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
            self.logger.info(
                "所有URL已下载完成或已尝试处理，无需继续", extra={"progress": "DONE"}
            )
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
                proxy_info = "、".join([p or "直连" for p in self.proxy_configs])
                self.logger.info(
                    f"[CONFIG] 代理配置: {proxy_info}", extra={"progress": "CONFIG"}
                )

            queue = asyncio.Queue()
            for index, url in enumerate(urls, 1):
                if url in pending_urls:
                    await queue.put((index, url))

            actual_workers = min(self.max_concurrency, pending_count)
            if actual_workers != self.max_concurrency:
                self.logger.info(
                    f"请求并发数 {self.max_concurrency} 大于待下载链接数 {pending_count}，将并发数调整为 {actual_workers}",
                    extra={"progress": "CONFIG"},
                )
            self.current_concurrency = actual_workers

            worker_slots = []
            for i in range(self.current_concurrency):
                worker_proxy = self._get_proxy_for_worker(i)
                if worker_proxy:
                    ctx = await browser.new_context(
                        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
                        viewport={"width": 1366, "height": 768},
                        proxy={"server": worker_proxy},
                    )
                    proxy_info = worker_proxy
                else:
                    ctx = await browser.new_context(
                        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
                        viewport={"width": 1366, "height": 768},
                    )
                    proxy_info = "直连"
                pg = await ctx.new_page()
                worker_slots.append((ctx, pg, proxy_info))

            workers = []
            for i, (ctx, pg, proxy_info) in enumerate(worker_slots):
                workers.append(
                    asyncio.create_task(self.worker(ctx, pg, queue, i, proxy_info))
                )

            await queue.join()

            for w in workers:
                w.cancel()
            await asyncio.gather(*workers, return_exceptions=True)

            for ctx, pg, _ in worker_slots:
                try:
                    await pg.close()
                except:
                    pass
                try:
                    await ctx.close()
                except:
                    pass

            self.logger.info(
                f"下载完成: 成功 {self.state['success_count']}/{len(urls)}, 失败 {self.state['fail_count']}",
                extra={"progress": "DONE"},
            )


def read_urls_from_file(file_path):
    """从文件读取URL列表，自动检测编码"""
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
    raise RuntimeError(f"无法用常见编码读取文件: {file_path}")


def read_proxies_from_file(file_path):
    """从文件读取代理列表，自动检测编码"""
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
        except Exception as e:
            print(f"读取代理文件出错: {str(e)}")
            return []
    print(f"无法用常见编码读取代理文件: {file_path}")
    return []


def parse_delay_range(delay_str):
    """解析延迟范围字符串"""
    try:
        min_delay, max_delay = map(float, delay_str.split("-"))
        return (min_delay, max_delay)
    except:
        raise argparse.ArgumentTypeError("延迟范围格式应为'min-max'，如'1.0-3.0'")


def main():
    parser = argparse.ArgumentParser(
        description="智能网页下载工具(支持断点续传和自适应策略)"
    )
    parser.add_argument("input_file", help="包含URL列表的文件路径")
    parser.add_argument(
        "-o",
        "--output",
        default="downloads",
        help="输出根目录 (默认: downloads)。每个输入文件将在其下创建子目录。",
    )
    parser.add_argument(
        "-t", "--timeout", type=int, default=30, help="每个请求超时时间(秒) (默认: 30)"
    )
    parser.add_argument(
        "-d",
        "--delay",
        type=parse_delay_range,
        default="1.0-3.0",
        help="请求之间的随机延迟范围(秒) (默认: 1.0-3.0)",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        dest="headless",
        help="隐藏浏览器窗口,即无头模式(默认显示)",
    )
    parser.add_argument(
        "-p",
        "--proxy-file",
        help="包含代理列表的文件路径(每行一个代理地址，格式: [protocol://]host:port)",
    )
    parser.add_argument(
        "--allow-direct",
        action="store_true",
        help="允许直接连接（不使用代理）作为代理列表的一个选项",
    )
    parser.add_argument(
        "-c", "--concurrency", type=int, default=3, help="最大并发工作线程数 (默认: 3)"
    )
    parser.add_argument(
        "-r", "--retries", type=int, default=3, help="失败重试次数 (默认: 3)"
    )

    args = parser.parse_args()

    # 基于输入文件确定输出目录，实现断点续传
    input_basename = os.path.basename(args.input_file)
    # 使用文件名（不含扩展名）作为子目录名
    input_name_safe = (
        input_basename.split(".")[0] if "." in input_basename else input_basename
    )
    # 最终的输出目录是 output_root / input_name_safe
    output_dir = os.path.join(args.output, input_name_safe)

    # 读取URL
    urls = read_urls_from_file(args.input_file)
    if not urls:
        print("错误: 输入文件中没有找到有效的URL")
        return

    print(f"开始下载 {len(urls)} 个URL到目录: {output_dir}")
    print(f"设置: 超时={args.timeout}s, 延迟={args.delay[0]}-{args.delay[1]}s")
    print(
        f"并发数={args.concurrency}, 重试次数={args.retries}, 浏览器窗口模式={'显示' if not args.headless else '隐藏'}"
    )
    if args.proxy_file:
        print(f"代理配置文件: {args.proxy_file}")

    # 读取代理列表
    proxy_list = []
    if args.proxy_file:
        proxy_list = read_proxies_from_file(args.proxy_file)
        if not proxy_list:
            print("警告: 代理文件为空或读取失败")
        else:
            print(f"已加载 {len(proxy_list)} 个代理:")
            for proxy in proxy_list:
                print(f"  - {proxy}")

    # 创建下载器实例
    downloader = SmartDownloader(
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

    # 运行下载任务
    asyncio.run(downloader.run(urls))


if __name__ == "__main__":
    try:
        import re
        from playwright.async_api import async_playwright
    except ImportError:
        print("请先安装Playwright,运行: pip install playwright && playwright install")
        exit(1)

    main()
