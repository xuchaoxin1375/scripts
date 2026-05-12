import asyncio
async def hello():
    print("hello")
    


async def main():
    await hello()
    print("world")


if __name__ == "__main__":
    asyncio.run(main())
