import threading
import time


def clock():
    time_string = time.strftime(
        '%Y-%m-%d %H:%M:%S', time.localtime(time.time()))
    # 递归实现

    # strLong=time.time()
    # strLong=str(strLong)
    print(time_string)
    # 递归调用(新的计时时钟函数是通过新线程调用,而不是初次调用调用)
    t = threading.Timer(1.0, clock)
    t.start()
    print("\t",t)

def sayHello_forWhile():
    time_string = time.strftime(
        '%Y-%m-%d %H:%M:%S', time.localtime(time.time()))
    print(time_string)

def testWhile():
    # cond=True
    while(True):
        # sayHello()
        time.sleep(1)
        sayHello_forWhile()
        
        


clock()
# 事件循环
print("test main thread task running.(expected be run before the second clock function invocation.")
print("test task queue...")
#design a time consumer(or a time.sleep())
sum_=sum(range(1,5*10**7))
print(sum_)
# #事件循环:事件执行顺序:
# testWhile()