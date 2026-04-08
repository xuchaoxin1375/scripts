import asyncio
import time


# 定义简单的log函数打印包含时间:
def log(event):
    print(time.strftime("%H:%M:%S", time.localtime()), event)


async def task():
    log("task:任务开始")
    await asyncio.sleep(1)
    log("task:任务结束")


async def main():
    log("main:create async task")
    at = asyncio.create_task(task())
    log("main:继续执行")
    log("main:await 等待异步任务结束,程序终止")
    await at
    log("main:全部任务结束")


asyncio.run(main())
