# mylib.py
import logging

logger = logging.getLogger(__name__)


def do_something():
    """模拟跨模块调用的日志行为函数(被调用函数)"""
    logger.info("Doing something")
