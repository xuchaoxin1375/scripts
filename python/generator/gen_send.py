# 累加器
def accumulator():
    total = 0
    while True:
        print(f' Total will be yield (return):{total}')
        value = yield total  # yield 左边接收 send() 传入的值
        print(f'\n Continue from last yield. Get value from send:{value}')
        # 判断value 是否为 None
        if value is None:
            break
        total += value


gen = accumulator()
# 必须先用 next() 或 send(None) 启动
init = next(gen)
print(init)  # 输出: 0
print(gen.send(10))  # 输出: 10
print(gen.send(20))  # 输出: 30
print(gen.send(5))  # 输出: 35
