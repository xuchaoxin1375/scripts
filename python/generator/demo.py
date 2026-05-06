# 从start 到 end 的数字生成器函数
def count_up(start, end):
    current = start
    while current <= end:
        yield current        # 产出值并暂停(yield语句(返回值后)导致函数暂停执行)
        current += 1         # 下次 next() 时从这里继续
# 获取生成器对象,然后消费生成器
gen = count_up(1, 5)         # 函数体此刻一行都没执行,但是得到一个生成器对象gen
print("手动用next()消费迭代器:")
print(next(gen))             # 输出: 1
print(next(gen))             # 输出: 2
print("使用for 循环消费:")
# 用 for 循环消费（最常见的方式）
for num in count_up(1, 5):
    print(num)