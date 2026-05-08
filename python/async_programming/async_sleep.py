# 根据协程的原理实现asyncio.sleep()

# 定义演示用的协程和任务.
import asyncio
import datetime
import time
import random


# import math
async def other_work(id=None,task_time=None):
    # 添加一些随机延迟模拟不同耗时任务
    task_time = task_time or round(random.random(),3)
    await asyncio.sleep(task_time)
    print(f"[{id}]:I like work. Work work.({task_time})s")


async def main():
    # 向事件循环添加一些其他任务，这样在异步休眠时就可以做一些事情。
    print("Create some other tasks , add them to the event loop...")
    work_tasks = [
        asyncio.create_task(other_work(1)),
        asyncio.create_task(other_work(2)),
        asyncio.create_task(other_work(3)),
    ]
    print(
        "Beginning asynchronous sleep at time: "
        f"{datetime.datetime.now().strftime('%H:%M:%S')}."
    )
    # 通过恰当的实现async_sleep,使得下面的语句和await asyncio.create_task(asyncio.sleep(3))效果相同
    await asyncio.create_task(async_sleep(1))
    # await asyncio.create_task(simpler_async_sleep(1))
    print(
        "Done asynchronous sleep at time: "
        f"{datetime.datetime.now().strftime('%H:%M:%S')}."
    )
    # asyncio.gather 有效地等待集合中的每个任务。
    await asyncio.gather(*work_tasks)

# 此协程函数依赖于辅助协程函数_sleep_watcher
async def async_sleep(seconds: float):
    future = asyncio.Future()
    # 计算要唤醒的时刻
    time_to_wake = time.time() + seconds
    # 将监视任务添加到事件循环。
    _watcher_task = asyncio.create_task(_sleep_watcher(future, time_to_wake))
    # 阻塞直到 future 被标记为已完成。
    await future

# 简单的awaitable类,用于可以用于在协程中通过await 该awaitable对象从而让出控制权.
class YieldToEventLoop:
    def __await__(self):
        yield

# 辅助协程函数async_sleep()实现功能
async def _sleep_watcher(future, time_to_wake):
    # 每个事件循环周期内执行1次检查,直到到达要唤醒的时刻
    # cnt=0
    while True:
        if time.time() >= time_to_wake:
            # 这标记 future 为已完成。
            future.set_result(None)
            break
        else:
            # 暂停当前任务(交还控制权给事件循环)，并等待下一次事件循环周期。
            await YieldToEventLoop()
        # 这里可以打印日志感受循环周期(1秒内可以执行数万次循环周期)
        # cnt+=1
        # print(f"[{cnt}]gap probe:{ datetime.datetime.now().strftime('%H:%M:%S.%f')}.")
# 简单的async_sleep实现(不使用Future),直接用循环实现.(依然用到简单awaitable类的实现YieldToEventLoop)
async def simpler_async_sleep(seconds):
    time_to_wake = time.time() + seconds
    while True:
        if time.time() >= time_to_wake:
            return
        else:
            await YieldToEventLoop() # 参考先前的实现.

if __name__ == "__main__":
    asyncio.run(main())
