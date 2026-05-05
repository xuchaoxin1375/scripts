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
    print(f"started at {time.strftime('%X')}")
    # 函数内使用 await 语法启动协程(两个协程虽然都是通过await成功调用,但是串行执行的,因此并没节约时间)
    await say_after(1, "hello")
    await say_after(2, "world")
    # 最终耗时3秒
    print(f"finished at {time.strftime('%X')}")


asyncio.run(main())
