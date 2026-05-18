import asyncio
import time
import httpx
import logging

datefmt1 = "%H:%M:%S"  # 仅打印时分秒
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
    datefmt=datefmt1,
)
logger=logging.getLogger()
print=logger.info

# 模拟需要并发访问的网站列表
URLS = [
    "https://httpbin.org/delay/2",
    "https://httpbin.org/delay/1",
    "https://httpbin.org/delay/3",
    "https://example.com",
    "https://www.python.org",
]


async def fetch_site(client, url):
    """
    一个协程任务：负责访问单个网站并返回状态码
    """
    print(f"[开始请求] -> {url}")
    try:
        # 使用 client.get 发送异步网络请求，注意这里需要 await
        response = await client.get(url, timeout=5.0)
        
        # 注意：在 httpx 中，response.status_code 是一个属性
        status = response.status_code
        print(f"[请求成功] <- {url} | 状态码: {status}")
        return url, status
    except Exception as e:
        print(f"[请求失败] x {url} | 原因: {e}")
        return url, None


async def main():
    """
    主协程：管理 httpx 的异步客户端并并发调度所有任务
    """
    # 创建一个异步客户端实例（相当于 aiohttp 的 Session，用于复用连接池）
    # 如果想开启 HTTP/2 支持，可以设置 httpx.AsyncClient(http2=True)
    async with httpx.AsyncClient() as client:
        tasks = []
        for url in URLS:
            # 创建协程任务
            task = asyncio.create_task(fetch_site(client, url))
            tasks.append(task)

        print("--- 开始并发访问 (使用 httpx) ---")
        # 并发执行所有任务
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