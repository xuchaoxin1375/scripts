import time
def fetch_data():
    print("开始获取数据...")
    time.sleep(2)  # 模拟网络延迟
    print("数据获取完成")
    return "data"


def process_data(data):
    print(f"获取到数据:{data}")
    data += " processed"
    time.sleep(1)
    print(f"数据处理完成:{data}")


# 同步执行：总耗时约 3 秒
start = time.time()
data = fetch_data()
# process_data依赖于fetch_data，因此需要等待fetch_data完成后才能执行(不能使用异步来节约时间!)
process_data(data)
print(f"总耗时: {time.time() - start:.2f} 秒")
