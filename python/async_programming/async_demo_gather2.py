import asyncio

async def download_file(name, duration):
    print(f"任务 {name}: 开始下载...")
    await asyncio.sleep(duration)
    print(f"任务 {name}: 下载完成 (耗时 {duration}s)")
    return f"{name}_data"

async def main():
    # 同时启动多个协程，并等待它们全部完成
    # gather 会自动将协程包装成 Task
    print("--- 并发开始 ---")
    results = await asyncio.gather(
        download_file("A", 2),
        download_file("B", 1),
        download_file("C", 1.5)
    )
    
    # results 是一个列表，顺序与传入参数的顺序一致
    print(f"所有任务结果: {results}")
    print("--- 全部处理完毕 ---")

asyncio.run(main())