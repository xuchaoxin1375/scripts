import logging
import sys

logger = logging.getLogger("test_identity")
logger.setLevel(logging.INFO)

# 创建一个 handler 实例
console_handler = logging.StreamHandler(sys.stdout)

# 尝试重复添加同一个实例
logger.addHandler(console_handler)
logger.addHandler(console_handler)

print(f"当前日志处理器列表: {logger.handlers}")
logger.info("这是一条测试日志")
