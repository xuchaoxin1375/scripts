"""
# logging_comprehensive_demo.py
单模块或脚本文件内使用日志模块
"""

import logging

# 创建一个顶级 Logger
logger = logging.getLogger("main")

# 配置 Logger 的级别
logger.setLevel(logging.DEBUG)

# 创建 Handler(这里创建两个独立的handler)
# console handler 将日志输出到控制台
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)  # Handler 的级别设置为 INFO
# file handler 用户将日志输出到文件中
file_handler = logging.FileHandler(
    "main_comprehensive_demo.log"
)  # 创建一个 FileHandler，将日志输出到文件
file_handler.setLevel(logging.DEBUG)  # Handler 的级别设置为 DEBUG

# 创建一个 Formatter，定义日志格式
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
# 为两个handler指定formatter(也可以创建不同的formatter,不同handler可以绑定不同formatter.)
console_handler.setFormatter(formatter)
file_handler.setFormatter(formatter)

# 将定义好的各个 Handler 添加到 Logger(handler不能单独使用,只有被正确添加到logger对象的handler才会生效)
logger.addHandler(console_handler)
logger.addHandler(file_handler)

# ============================

# 创建一个子 Logger (注意父级logger的名字是"main",其子级的logger名字以main.<subname>的格式构造)
# 子logger继承父logger的配置,除非额外单独指定子logger的配置
child_logger = logging.getLogger("main.child")
child_logger.setLevel(logging.DEBUG)


def filter_record(record):
    """配置子 Logger 的过滤器(条件测试函数,返回bool值)
    # 例如只允许包含 "important" 的日志通过,通过判断logger中的msg属性返回布尔值

    """
    return "important" in record.msg


# 将过滤器添加到logger对象,例如为子级logger配置定义好的过滤器(函数对象)
child_logger.addFilter(filter_record)

# ======== 测试日志记录 ===========
logger.debug(
    "This is a debug message from main logger"
)  # 此debug级别的日志不会被控制台console_handler记录，因为 console_handler 级别是 INFO;但是会被file_handler记录,因为file_handler级别是DEBUG
logger.info(
    "This is an info message from main logger"
)  # 会被记录,console_hander,file_handler都输出此日志

child_logger.debug(
    "This is a debug message from child logger"
)  # 不会被记录，因为本例的过滤器filter_record要求日志有'important'才被传递,这里的消息中没有,所以被拒绝
child_logger.info(
    "This is an important info message from child logger"
)  # 会被记录,通过过滤器的要求
