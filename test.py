"""

用例
 python .\test.py
正在启动异步下载测试...
--- 准备下载 (非静默模式) ---
🚀 [Playwright] 任务开始: https://www.bigw.com.au/medias/sys_master/images/images/h23/h39/100487658078238.jpg
Navigating to https://www.bigw.com.au/medias/sys_master/images/images/h23/h39/100487658078238.jpg...
✅ [Playwright] 导航成功 (状态码: 200). 正在读取响应体...
✅ [Playwright] 文件保存成功: downloaded_image.jpg
Browser closed.

🎉 测试成功！图片已保存到 downloaded_image.jpg
"""

import asyncio
import os
from playwright.async_api import async_playwright, Playwright
from typing import Optional

# --- 为示例定义常量 ---
# 定义一个默认的 User-Agent
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36"
]
# 默认超时时间（秒）
TIMEOUT = 30
# -------------------------


async def download_by_playwright(
    url: str,
    output_path: str,
    user_agent: str = USER_AGENTS[0],
    timeout: int = TIMEOUT,
    silent: bool = False,
    extra_args: Optional[list] = None,
) -> bool:
    """
    使用 Playwright 框架异步下载图片（或其他文件）。

    Args:
        url (str): 要下载的文件 URL。
        output_path (str): 本地保存路径。
        user_agent (str): 浏览器 User-Agent 字符串。
        timeout (int): 请求超时时间（秒）。
        silent (bool): 是否静默执行。
                       True:  运行无头浏览器，不打印日志。
                       False: 运行有头浏览器，打印详细日志。
        extra_args (Optional[list]): 传给浏览器启动项的额外参数列表。

    Returns:
        bool: 下载成功返回 True，失败返回 False。
    """

    # --- 1. 参数处理 ---

    # Playwright 的超时时间以毫秒为单位，我们将其从秒转换
    playwright_timeout_ms = timeout * 1000

    # 'silent' 参数控制是否使用 'headless' 模式以及是否打印日志
    # silent=True -> headless=True (无头模式)
    # silent=False -> headless=False (有头模式，会弹窗)
    is_headless = silent

    if not silent:
        print(f"🚀 [Playwright] 任务开始: {url}")

    # --- 2. 确保输出目录存在 ---
    try:
        output_dir = os.path.dirname(output_path)
        # 如果 output_dir 为空字符串 (即保存在当前目录)，os.makedirs 会报错
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
    except Exception as e:
        if not silent:
            print(f"❌ [Playwright] 创建目录失败: {e}")
        return False

    # --- 3. 执行 Playwright 核心逻辑 ---

    # 使用 async with 语句来自动管理 Playwright 实例的生命周期
    async with async_playwright() as p:
        browser = None  # 在 try 块之外定义，确保 finally 中可以访问
        try:
            # 启动浏览器 (我们默认使用 chromium)
            # 添加一些参数来解决可能的HTTP/2协议错误和其他网络问题
            launch_args = [
                "--disable-http2",  # 禁用HTTP/2
                "--disable-web-security",  # 禁用网络安全限制
                "--ignore-certificate-errors",  # 忽略证书错误
                "--allow-running-insecure-content",  # 允许不安全内容
                "--disable-features=VizDisplayCompositor"  # 禁用Viz显示合成器
            ]
            
            if extra_args:
                launch_args.extend(extra_args)
                
            browser = await p.chromium.launch(headless=is_headless, args=launch_args)

            # 创建一个新的浏览器上下文 (Context)
            # 可以在这里设置 User-Agent, Cookies, Viewport 等
            context = await browser.new_context(
                user_agent=user_agent,
                ignore_https_errors=True  # 忽略HTTPS错误
            )

            # 在上下文中打开一个新页面
            page = await context.new_page()

            if not silent:
                print(f"Navigating to {url}...")

            # 核心步骤：导航到目标 URL
            # page.goto() 会返回一个 Response 对象
            response = await page.goto(
                url,
                timeout=playwright_timeout_ms,
                wait_until="load",  # 等待资源完全加载
            )

            # 检查响应是否成功
            if response is None or not response.ok:
                status = response.status if response else "N/A"
                if not silent:
                    print(f"❌ [Playwright] 导航失败。状态码: {status}")
                return False

            if not silent:
                print(
                    f"✅ [Playwright] 导航成功 (状态码: {response.status}). 正在读取响应体..."
                )

            # 从响应中获取原始的二进制数据
            file_bytes = await response.body()

            # --- 4. 保存文件 ---
            with open(output_path, "wb") as f:
                f.write(file_bytes)

            if not silent:
                print(f"✅ [Playwright] 文件保存成功: {output_path}")

            return True

        except Exception as e:
            # 捕获所有可能的异常 (如超时、SSL错误、导航错误等)
            if not silent:
                print(f"❌ [Playwright] 发生意外错误: {e}")
            return False

        finally:
            # 无论成功还是失败，最后都确保关闭浏览器
            if browser:
                await browser.close()
                if not silent:
                    print("Browser closed.")


# --- 如何运行这个异步函数 ---


async def main():
    """
    一个主函数，用于演示如何调用 download_by_playwright
    """
    test_url = "https://www.bigw.com.au/medias/sys_master/images/images/h23/h39/100487658078238.jpg"
    test_output = "downloaded_image.jpg"

    print("--- 准备下载 (非静默模式) ---")

    # 第一次运行，设置 silent=False 来看清所有步骤
    success = await download_by_playwright(
        url=test_url, output_path=test_output, silent=False, timeout=30  # 30秒超时
    )

    if success:
        print(f"\n🎉 测试成功！图片已保存到 {test_output}")
    else:
        print(f"\n🔥 测试失败。请检查错误日志。")


if __name__ == "__main__":
    # --- 重要提示 ---
    # 第一次运行此脚本前，你需要在终端执行:
    # 1. pip install playwright
    # 2. playwright install
    # (第2步会自动下载 chromium, firefox, webkit 浏览器内核)
    # ------------------

    print("正在启动异步下载测试...")
    asyncio.run(main())
