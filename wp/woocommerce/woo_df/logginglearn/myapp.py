"""测试跨模块调用的日志行为"""

# myapp.py
import logging

import mylib  # 导入其他使用logging的模块中的函数

logger = logging.getLogger(__name__)


def main():
    """模拟跨模块调用的日志行为函数"""
    logging.basicConfig(
        filename="myapp.log",
        format="%(asctime)s- %(name)s -%(levelname)s:%(message)s",
        filemode="w",
        level=logging.INFO,
    )
    logger.info("Started")
    mylib.do_something()
    logger.info("Finished")


if __name__ == "__main__":
    main()
    print("日志已记录到 myapp.log")
