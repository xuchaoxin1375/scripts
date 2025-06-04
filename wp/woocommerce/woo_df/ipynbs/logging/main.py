"""多模块日志示例"""

import logging
from myliblog import core
from myliblog import utils
from myliblog import auxiliary


def setup_logging(level=logging.DEBUG):
    """设置日志级别"""

    # 创建一个顶级 logger
    # logger = logging.getLogger("myapp")
    logger = logging.getLogger(
        "myliblog"
    )  # 使用库的顶级 logger 名称,这样能够接收到子模块的日志信息(从而可以不必为每个子模块都创建 logger并配置handler)
    logger.setLevel(logging.DEBUG)  # 根 logger 级别为 DEBUG

    # 创建两个 handler：控制台 + 文件
    # 控制台的日志级别为 INFO
    console_handler = logging.StreamHandler()
    console_handler.setLevel(level=level)

    # 文件的日志级别为 DEBUG
    file_handler = logging.FileHandler("app.log", mode="w", encoding="utf-8")
    file_handler.setLevel(logging.DEBUG)

    # 定义格式器
    formatter = logging.Formatter(
        fmt="%(asctime)s - %(name)s - %(funcName)s - %(levelname)s - %(message)s"
    )
    console_handler.setFormatter(formatter)
    file_handler.setFormatter(formatter)

    # 添加 handler 到根 logger
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)

    # 可选：关闭 propagate，防止重复输出
    logger.propagate = False
    return logger


if __name__ == "__main__":
    logger = setup_logging()

    # 获取子模块的 logger
    logger_core = logging.getLogger("myliblog.core")
    logger_utils = logging.getLogger("myliblog.utils")
    logger_auxiliary = logging.getLogger("myliblog.auxiliary")
    # logger.propagate = False
    # logger.propagate = False

    # 获取被调用模块的logger对象后,可以通过该对象设置模块代码中的日志行为,比如级别
    logger_core.setLevel(logging.ERROR)  # 设置 core 模块的日志级别为 ERROR
    logger_utils.setLevel(logging.INFO)
    # logger_auxiliary.setLevel(logging.INFO)

    logger.debug("This is a debug message!")
    logger.info("This is an info message!")

    logger.info("(1) Running Module core")
    core.do_core()  # 输出 ERROR 日志
    logger.info("(2) Running Module utils")
    utils.helper()  # 输出 Info 日志
    logger.info("(3) Running Module auxiliary")
    auxiliary.some_function()  # ?控制台没有输出日志
