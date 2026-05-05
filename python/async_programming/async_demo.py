import asyncio
import logging

datefmt1 = "%H:%M:%S"  # 仅打印时分秒
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
    datefmt=datefmt1,
)
logger=logging.getLogger(__name__)
# 是否使用info代替print
print = logger.info

# info("开始执行...")
# warning("开始执行...")
async def fetch_data():
    print("开始获取数据...")
    await asyncio.sleep(2)  # 非阻塞等待
    print("数据获取完成")
    return "data"


async def process_data():
    print("开始处理数据...")
    await asyncio.sleep(1)
    print("数据处理完成")


async def main():
    # 异步并发执行：总耗时约 2 秒（因为两个任务重叠执行）
    start = asyncio.get_event_loop().time()
    #
    await asyncio.gather(fetch_data(), process_data())
    print(f"总耗时: {asyncio.get_event_loop().time() - start:.2f} 秒")


asyncio.run(main())
