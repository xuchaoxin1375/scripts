import asyncio

async def fetch(url: str) -> str:
    print(f"开始请求 {url}")
    await asyncio.sleep(1)  # 模拟网络请求
    return f"{url} 的内容"

async def main():
    results = await asyncio.gather(
        fetch("https://api.example.com/a"),
        fetch("https://api.example.com/b"),
        fetch("https://api.example.com/c"),
    )
    # 逐个输出结果
    for r in results:
        print(r)
    
# 运行协程
asyncio.run(main())