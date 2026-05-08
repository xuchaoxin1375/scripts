import asyncio
import time

import logging

datefmt1 = "%H:%M:%S"  # 仅打印时分秒
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(funcName)s - %(message)s",
    datefmt=datefmt1,
)
logger=logging.getLogger(__name__)
print=logger.info

async def say_after(delay, what):
    print(f"start say_after...[{what}]")
    await asyncio.sleep(delay)
    print(what)


async def main():
    print("create tasks...")
    task1 = asyncio.create_task(
        say_after(1, 'hello'))

    task2 = asyncio.create_task(
        say_after(2, 'world'))
    # task1,2被asyncio.crate_task函数包装后,可以并发运行,节约时间（会花费约 2 秒钟。）

    # 如果等待足够的时间,可以看到,即便后面没有使用await相关task,上述两个任务依然会执行.
    # await asyncio.sleep(3) # 可以注释此行查看效果
    print(f"Try await at {time.strftime('%X')}")

    # 等待直到两个任务都完成;注意await task并不是为了启动task,而是等待异步任务的结果
    await task1
    await task2
    print(f"finished at {time.strftime('%X')}")


asyncio.run(main())
