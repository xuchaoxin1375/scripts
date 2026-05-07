# 定义典型的生成器函数(打印指定内容),能够处理next,send和throw,以及close调用
def echo(value=None):
    print("Execution starts when 'next()' is called for the first time.")
    # 将循环放在try-finally中
    try:
        while True:
            # 循环内部逻辑也放置异常处理try-except结构中.
            try:
                value = yield value  # value=yield ... 接收send传入的value
            except Exception as e:
                value = e
    finally:
        print("Don't forget to clean up when 'close()' is called.")


generator = echo(1)
# next() 等同于 send(None)

print(
    next(generator)
)  # Execution starts when 'next()' is called for the first time. (并且输出1)
print(next(generator))  # None

print(generator.send(2))  # 2

generator.throw(TypeError, "spam")  # TypeError('spam',)

generator.close()  # Don't forget to clean up when 'close()' is called.


