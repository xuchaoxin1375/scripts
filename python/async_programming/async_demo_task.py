import asyncio


async def coro_a(cid):
    print(f"[{cid}]:I am coro_a(). Hi!")


async def coro_b():
    print("I am coro_b(). I sure hope no one hogs the event loop...")


async def main():
    task_b = asyncio.create_task(coro_b())
    # 执行多次await coro_a()
    num_repeats = 3
    for cid in range(num_repeats):
        #   await coro_a()
        await asyncio.create_task(coro_a(cid))
    await task_b


asyncio.run(main())
