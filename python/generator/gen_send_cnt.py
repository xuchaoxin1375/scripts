##

# 可变步长的累加器
def accumulator_step():
    cnt = 0
    STEP = 1
    while cnt <= 9:
        val = yield cnt
        print(' val:', val)
        # 错误用法:将yield表达式左侧变量直接使用
        # 标准做法是添加一个判断(是否为None),按需设置分支
        if val is not None:
            # break
            STEP = val
        print(' +STEP:', STEP)
        cnt += STEP


gen = accumulator_step()
print(next(gen))  # 0
print(next(gen))  # 1
print(next(gen))  # 2
print(gen.send(2))# 4
print(next(gen))  # 6
print(next(gen))  # 8

##
