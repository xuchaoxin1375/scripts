import asyncio
import time
import aiohttp
import logging

datefmt1 = "%H:%M:%S"  # 仅打印时分秒
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
    datefmt=datefmt1,
)
logger=logging.getLogger(__name__)
print=logger.info

# 模拟需要并发访问的网站列表
URLS = [
    "https://httpbin.org/delay/2",
    "https://httpbin.org/delay/1",
    "https://httpbin.org/delay/3",
    "https://example.com",
    "https://www.python.org",
]


async def fetch_site(session, url):
    """
    一个协程任务：负责访问单个网站并返回状态码
    """
    print(head_tag := f"[开始请求] -> {url}")
    try:
        # 使用 session.get 发送异步网络请求
        async with session.get(url, timeout=5) as response:
            # 异步读取响应内容（这里只读取状态码作为演示）
            status = response.status
            print(f"[请求成功] <- {url} | 状态码: {status}")
            return url, status
    except Exception as e:
        print(f"[请求失败] x {url} | 原因: {e}")
        return url, None


async def main():
    """
    主协程：管理连接池并并发调度所有任务
    """
    # 创建一个异步 HTTP 客户端会话（连接池）
    async with aiohttp.ClientSession() as session:
        # 创建任务列表
        tasks = []
        for url in URLS:
            # 创建协程任务并加入列表
            task = asyncio.create_task(fetch_site(session, url))
            tasks.append(task)

        # 核心：使用 asyncio.gather 并发执行所有任务，并等待它们全部结束
        print("--- 开始并发访问 ---")
        results = await asyncio.gather(*tasks)
        print("--- 所有请求完成 ---\n")

        # 打印最终结果
        print("最终执行结果统计:")
        for url, status in results:
            print(f"URL: {url} -> 状态码: {status}")


if __name__ == "__main__":
    start_time = time.time()

    # 启动异步事件循环
    asyncio.run(main())

    end_time = time.time()
    print(f"\n总共耗时: {end_time - start_time:.2f} 秒")