# demo_coroutine_send.py
import logging

datefmt1 = "%H:%M:%S"  # 仅打印时分秒
logging.basicConfig(
    level=logging.INFO,
    format="%(funcName)s - %(message)s",
    datefmt=datefmt1,
)
logger = logging.getLogger(__name__)
print = logger.info


# 定义一个简单的可等待对象(awaitable)
class Rock:
    def __await__(self):  # 一个普通的生成器
        value_sent_in = yield 7 # 本函数被调用后,向调用者返回7(但不是将value_sent_in赋值为7),然后暂停(如果协程恢复,则继续下面到代码,返回value_sent_in)
        # 通过send(None)启动生成器
        print(f"Rock.__await__ resuming with value: {value_sent_in}.")
        return value_sent_in  # 可以配合await 表达式来接收返回值.


# 主协程
async def main():
    print("Beginning coroutine main().")
    # 实例化可等待对象,得到rock
    rock = Rock()
    print("Awaiting rock...")
    value_from_rock = await rock  # 触发rock.__await__()方法的调用,执行到内部的field后暂停,main协程也会暂停(等待send来恢复协程.)
    # 注意这里接收到的只是return的值,而不是yield的返回值(yield表达式返回的值是返回给协程启动(恢复)调用者的,同时也意味着协程的执行又被暂停了,例如后面的语句coroutine.send(42)返回值就是yield的返回值7).
    print(f"Coroutine received value: {value_from_rock} from rock.")

    # 设置主协程的返回值,外部检测coroutine.send()抛出的StopIteration异常中获取main协程的返回值
    # 当一个 generator 或 coroutine 函数返回时，将引发一个新的 StopIteration 实例，函数返回的值将被用作异常构造器的 value 形参。
    return 23


if __name__ == "__main__":
    # 创建主协程(对象)
    coroutine = main()

    # 通过协程的send()方法手动启动协程,而非asyncio.run
    print("Starting main coroutine by send(None)...")
    intermediate_result = coroutine.send(None) # main协程运行到await rock(内部的yield后暂停执行,并获得yield返回值7),直到下面到send(value)调用恢复被挂起的协程(内的其余代码的执行).
    # 虽然协程被挂起,但这不会阻塞主线程其他代码的执行.下面到语句会继续执行.

    print(f"[I]:Coroutine paused and returned intermediate value: {intermediate_result}.")

    print("[I]:Resuming coroutine and sending in value: 42.")

    try:
        coroutine.send(42) # 恢复主协程的执行.
    except StopIteration as e:
        returned_value = e.value
    print(f"[I]:Coroutine main() finished and provided value: {returned_value}.")
