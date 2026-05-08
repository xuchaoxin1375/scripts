import asyncio
from datetime import datetime
def printd(message=""):
    print(f"[{datetime.now()}] {message}")
async def sequential():
    printd("任务开始执行...")
    await asyncio.sleep(1)
    printd()
    await asyncio.sleep(1)
    printd()
    await asyncio.sleep(1)
    printd("任务执行完毕.")


if __name__ == "__main__":
    asyncio.run(sequential())
