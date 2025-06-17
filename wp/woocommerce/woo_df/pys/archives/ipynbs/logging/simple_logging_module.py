"""
simple_logging_module.py

一个简单的 Python 日志记录模块的例子。
"""

import logging

# 创建日志记录器 logger
logger = logging.getLogger("simple_example")
logger.setLevel(logging.DEBUG)

# 创建控制台处理器 ch (console_handler)并将等级设为 debug
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)

# 创建格式化器 formatter
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")

# 将 formatter 添加到 ch
ch.setFormatter(formatter)

# 将 ch 添加到 logger
logger.addHandler(ch)

# '应用程序' 代码
logger.debug("debug message")
logger.info("info message")
logger.warning("warn message")
logger.error("error message")
logger.critical("critical message")
