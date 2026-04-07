import asyncio
import random

async def fetch(url):
    print(f"开始请求: {url}")
    
    # 模拟网络延迟
    delay = random.randint(1, 3)
    await asyncio.sleep(delay)
    
    print(f"请求完成: {url}, 耗时 {delay}s")
    return f"{url} 的内容"

async def main():
    urls = ["https://a.com", "https://b.com", "https://c.com"]

    # 创建任务
    tasks = [asyncio.create_task(fetch(url)) for url in urls]

    print("所有请求已发出，等待结果...")

    # 并发等待所有任务完成
    results = await asyncio.gather(*tasks)

    print("\n最终结果:")
    for result in results:
        print(result)

asyncio.run(main())