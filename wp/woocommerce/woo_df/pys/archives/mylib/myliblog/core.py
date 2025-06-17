"""mylib package core module."""

import logging

# 创建库的顶级 logger
logger = logging.getLogger(
    __name__
)  # 从外部调用此模块时,预计有 __name__ == 'myliblog.core'
# logger.setLevel(logging.DEBUG)  # 设置日志级别为 DEBUG
# 创建格式化器
FMT1 = "%(asctime)s - %(levelname)s - %(name)s -%(module)s -%(funcName)s - %(lineno)d - %(message)s"
FMT2 = "%(asctime)s - %(levelname)s - [core fmt:%(name)s -%(funcName)s - %(lineno)d] - %(message)s"
formatter = logging.Formatter(fmt=FMT2)
# 创建控制台处理器
ch = logging.StreamHandler()
# ch.setLevel(logging.DEBUG)
ch.setFormatter(formatter)
# 添加控制台处理器到 logger
logger.addHandler(ch)


def do_core():
    """Do something in core module."""
    logger.debug("Doing something in core module")
    logger.info("Core module is working")
    logger.warning("This is a warning from core module")
    logger.error("An error demo in core module")


if __name__ == "__main__":
    # 如果直接运行此模块,则执行以下代码
    logger.setLevel(logging.INFO)
    logger.info("Running myliblog.core as a script")
    do_core()
