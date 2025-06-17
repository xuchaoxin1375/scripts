"""多模块日志示例"""

import logging

# 测试日志行为的模块myliblog
from myliblog import auxiliary, core, utils

LOG_FILE = "main_cu.log"
# 配置pythonpath环境变量(将myliblog目录添加到PYTHONPATH环境变量中)后可以直接导入模块
# import auxiliary
# import core
# import utils


def setup_logging(level=logging.DEBUG):
    """设置日志级别"""

    # 创建不同名称的日志记录器查看效果上差异

    # 1.普通的日志记录器名:myapp
    # lgr = logging.getLogger("myapp")
    # 或
    lgr = logging.getLogger(__name__)

    # 2.引用自模块myliblog的日志记录器名:myliblog
    # lgr = logging.getLogger("myliblog")

    # 3.根日志记录器名:root
    lgr = logging.getLogger()

    # 设置日志级别
    lgr.setLevel(logging.DEBUG)

    # 创建两个 handler：控制台 + 文件
    # 控制台的日志级别为 INFO
    console_handler = logging.StreamHandler()
    console_handler.setLevel(level=level)

    # 文件的日志级别为 DEBUG
    file_handler = logging.FileHandler(LOG_FILE, mode="w", encoding="utf-8")
    file_handler.setLevel(logging.DEBUG)

    # 定义格式器
    formatter = logging.Formatter(
        fmt="%(asctime)s - %(name)s -[main_cu fmt:%(funcName)s - %(lineno)d]- %(levelname)s - %(message)s"
    )
    console_handler.setFormatter(formatter)
    file_handler.setFormatter(formatter)

    # 添加 handler 到根 logger
    lgr.addHandler(console_handler)
    lgr.addHandler(file_handler)

    # 可选：关闭 propagate，防止重复输出
    lgr.propagate = False
    return lgr


if __name__ == "__main__":
    logger = setup_logging()

    # 获取子模块的 logger
    logger_core = logging.getLogger("myliblog.core")
    logger_utils = logging.getLogger("myliblog.utils")
    logger_auxiliary = logging.getLogger("myliblog.auxiliary")

    # 获取被调用模块的logger对象后,可以通过该对象设置模块代码中的日志行为,比如级别
    logger_core.setLevel(logging.ERROR)  # 设置 core 模块的日志级别为 ERROR
    logger_utils.setLevel(logging.INFO)
    logger_auxiliary.setLevel(logging.WARNING)

    logger.debug("This is a debug message!")
    logger.info("This is an info message!")

    logger.info("(1) Running Module core")
    core.do_core()  # 输出 ERROR 日志
    logger.info("(2) Running Module utils")
    utils.helper()  # 输出 Info 日志
    logger.info("(3) Running Module auxiliary")
    auxiliary.some_function()  # 输出 Warning 日志
