import asyncio

# 计算阶乘
async def factorial(task_name, number):
    f = 1
    for i in range(2, number + 1):
        print(f"Task {task_name}: Compute factorial({number}), currently i={i}...")
        # 每次乘法计算前睡眠1秒
        await asyncio.sleep(1)
        f *= i
    # 结束并包裹结果:
    print(f"[result:Task {task_name}]: factorial({number}) = {f}")
    return f

async def main():
    # *并发地* 调度这三次调用：
    L = await asyncio.gather(
        factorial("A", 2),
        factorial("B", 3),
        factorial("C", 4),
    )
    print(L)

asyncio.run(main())