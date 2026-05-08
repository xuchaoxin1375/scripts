import asyncio
from datetime import datetime
import random
def printd(message=""):
    print(f"[{datetime.now()}] {message}")

# 在睡眠前后各打印一条消息.支持指定任务ID便于区分不同睡眠任务
async def sleepm(delay=None,id_msg=""):
    delay=delay or round(random.random(),2)
    prefix_msg=f"[{id_msg}]:(sleep {delay}s)"
    printd(f"{prefix_msg}:start sleep...")
    await asyncio.sleep(delay=delay)
    printd(f"[{id_msg}]::end sleep.")

# 主协程(验证await coroutine的执行效果:不会交还控制权给事件循环.)
async def sequential():
    printd("任务开始执行...")
    await sleepm(1,id_msg="1")
    await sleepm(1,id_msg="2")
    await sleepm(1,id_msg="3")
    printd("任务执行完毕.")

# 包装为task实现并发
async def concurrent():
    printd("任务开始执行...")
    printd("创建若干个协程对象...")
    c1= sleepm(1,id_msg="1")
    c2= sleepm(1,id_msg="2")
    c3= sleepm(1,id_msg="3")
    printd("将几个协程包装成task并行运行...")
    tasks=[ asyncio.create_task(c) for c in [c1,c2,c3]]
    printd("所有协程已完成task包装,逐个await等待所有任务完成...")
    # await asyncio.gather(*tasks)
    _res=[await t for t in tasks]
    printd("任务执行完毕.")

async def concurrent2():
    printd("任务开始执行...")
    printd("创建若干个协程对象...")
    c1= sleepm(1,id_msg="1")
    c2= sleepm(2,id_msg="2")
    c3= sleepm(2,id_msg="3")
    printd("将几个协程包装成task并行运行...")
    # tasks=[ asyncio.create_task(c) for c in [c1,c2,c3]]
    # 向事件循环注册任务t1(此时控制权仍在当前协程中,尚未交还给事件循环.意味着不会立即执行t1)
    t1= asyncio.create_task(c1)

    printd("所有协程已完成task包装,逐个await等待所有任务完成...")
    
    # 使用await task 类型语句会交还控制权给事件循环.而不仅仅是挂起当前协程的执行.
    
    t2= asyncio.create_task(c2)
    await t2
    t3= asyncio.create_task(c3)
    await t3

    await t1
    # await asyncio.gather(*tasks)
    # _res=[await t for t in tasks]
    printd("任务执行完毕.")
# async def sequential():
#     printd("任务开始执行...")
#     await asyncio.sleep(1)
#     printd()
#     await asyncio.sleep(1)
#     printd()
#     await asyncio.sleep(1)
#     printd("任务执行完毕.")


if __name__ == "__main__":
    # asyncio.run(sequential())
    # asyncio.run(concurrent())
    asyncio.run(concurrent2())
