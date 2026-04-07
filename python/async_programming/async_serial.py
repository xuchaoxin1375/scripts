import asyncio
import time

# 定义2个有顺序依赖的协程函数
async def step_1_async():
    await asyncio.sleep(1)  # 异步等待，释放 CPU
    print("【异步】验证成功，得到用户ID: 123")
    return 123


async def step_2_async(user_id):
    await asyncio.sleep(1)
    print(f"【异步】获取权限成功，用户 {user_id} 是管理员")

# 支线任务
async def other_task():
    """模拟在等待登录时，程序还能处理其他事情（如界面动画或接收消息）"""
    for i in range(4):
        print(f"  [后台] 正在处理其他小任务... {i}")
        await asyncio.sleep(0.5)


async def main_async():
    print("--- 异步流程开始 ---")
    start = time.perf_counter()

    # 我们通过 create_task 让直线任务 other_task 并发跑起来(而不是主线任务的登录验证)
    background_job = asyncio.create_task(other_task())

    # 关键点：这里的代码依然是串行的，必须等 1 完再跑 2
    uid = await step_1_async()
    await step_2_async(uid)

    await background_job  # 等待后台任务收尾
    print(f"--- 异步流程结束，总耗时: {time.perf_counter() - start:.2f}s ---")


asyncio.run(main_async())
