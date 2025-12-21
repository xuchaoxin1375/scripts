"""
# logging0.py
logging模块基础用例
"""

import logging

# 1. 创建 Logger
logger = logging.getLogger("logging0")
logger.setLevel(logging.DEBUG)  # 设置总门槛级别

# 2. 创建 Handler (控制台输出+日志文件输出)
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)

file_handler = logging.FileHandler("logging0.log")
file_handler.setLevel(logging.DEBUG)  # 输出到日志文件中的消息为详细级别

# 3. 创建 Formatter 并绑定到 Handler
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
console_handler.setFormatter(formatter)
file_handler.setFormatter(formatter)
# 4. 将 Handler 添加到 Logger
logger.addHandler(console_handler)
logger.addHandler(file_handler)

# 查看logger中已经配置好的handler
print(logger.handlers)

# 使用logger的日志调用
# 由于console_handler的级别为INFO, 此信息不会输出到控制台,但是file_handler的级别为DEBUG, 此信息会输出到文件
# logger.debug("这是一条模拟的调试信息")
# logger.info("这是一条模拟的info信息")
# logger.error("这是一条模拟的错误信息")

# 衍生操作 (增加或移除Handler)

# # 移除控制台处理器
# logger.removeHandler(console_handler)
# print(f"当前日志处理器:{logger.handlers}")
# logger.info("移除console_handler后, 此信息不会输出到控制台,file_handler会记录")
# # 添加回控制台处理器
# logger.addHandler(console_handler)
# print(f"当前日志处理器:{logger.handlers}")
# logger.info("添加回console_handler后, 此信息会输出到控制台,file_handler会记录")


# 循环移除所有 handler
while logger.handlers:
    handler = logger.handlers[0]
    handler.close()  # 释放文件句柄等资源
    logger.removeHandler(handler)

print("请观察控制台输出")
# logger.addHandler(console_handler)
# logger.addHandler(console_handler)
# print(f"当前日志处理器:{logger.handlers}")
# logger.info("添加了两个console_handler,查看打印次数(添加相同的handler不会报错,但是仅会保留1份)")
# 添加多个不同的控制台handler导致控制台输出内容重复(格式可能不同)的记录
console_handler2 = logging.StreamHandler()  # 使用默认日志格式

# formatter = logging.Formatter(
#     "%(asctime)s [hdlr2]- %(name)s - %(levelname)s - %(message)s"
# )
# console_handler2.setFormatter(formatter)

logger.addHandler(console_handler)
logger.addHandler(console_handler)
print(f"当前日志处理器:{logger.handlers}")
logger.info("添加了两个不同的控制台handler,查看打印次数")
