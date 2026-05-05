import asyncio
import time

import logging

datefmt1 = "%H:%M:%S"  # 仅打印时分秒
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
    datefmt=datefmt1,
)
logger=logging.getLogger(__name__)
print=logger.info

async def say_after(delay, what):
    await asyncio.sleep(delay)
    print(what)


async def main():
    task1 = asyncio.create_task(
        say_after(1, 'hello'))

    task2 = asyncio.create_task(
        say_after(2, 'world'))

    print(f"started at {time.strftime('%X')}")

    # 等待直到两个任务都完成
    # task1,2被asyncio.crate_task函数包装后,可以并发运行,节约时间（会花费约 2 秒钟。）
    await task1
    await task2

    print(f"finished at {time.strftime('%X')}")


asyncio.run(main())
