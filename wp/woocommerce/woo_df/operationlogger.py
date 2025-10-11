# operation_logger/logger.py

import json
import time
from datetime import datetime
import threading

# 线程局部变量存储每个线程的 logger 实例
local_data = threading.local()


class OperationLogger:
    """
    操作日志记录器类，用于记录一组操作的开始时间、结束时间以及成功、失败、跳过的操作数量，
    同时记录失败操作的详细信息。
    """

    def __init__(self):
        self.start_time = time.time()
        self.end_time = self.start_time
        self.total = 0
        self.success = 0
        self.failure = 0
        self.skipped = 0
        self.failures_log = []

    def start(self):
        """开始记录时间"""
        self.start_time = time.time()
        return f"[{datetime.now()}] 操作开始"

    def end(self):
        """结束记录并返回摘要"""
        self.end_time = time.time()
        duration = self.end_time - self.start_time  # type: ignore

        # 使用 __dict__ 获取对象的所有实例变量
        summary = {
            "start_time": datetime.fromtimestamp(self.start_time).isoformat(),
            "end_time": datetime.fromtimestamp(self.end_time).isoformat(),
            "duration": round(duration, 2),
            **self.__dict__,  # 将 OperationLogger 的所有属性合并到 summary 中
        }

        return summary

    def log_success(self):
        """
        记录成功的操作。
        更新总操作数和成功操作数。
        """
        self.total += 1
        self.success += 1

    def log_failure(self, item, error=None):
        """记录失败的操作并更新总操作数"""
        self.total += 1
        self.failure += 1
        self.failures_log.append(
            {
                "item": item,
                "error": str(error) if error else None,
                "timestamp": datetime.now().isoformat(),
            }
        )

    def log_skip(self):
        """记录跳过的操作并更新总操作数"""
        self.total += 1
        self.skipped += 1

    def save_failures(self, filename=None):
        """保存失败项到 JSON 文件"""
        filename = filename or f"failures_{int(time.time())}.json"
        with open(filename, "w", encoding="utf-8") as f:
            json.dump(self.failures_log, f, indent=2, ensure_ascii=False)
        return filename

    def end_and_report(self):
        """打印操作日志的摘要"""
        res = self.end()
        # 使用字典的风格打印摘要
        print(res)
        # 打印操作日志的摘要
        print(f"操作结束，共耗时 {self.end_time - self.start_time} 秒")
        print(f"总操作数：{self.total}")
        print(f"成功操作数：{self.success}")
        print(f"失败操作数：{self.failure}")
        print(f"跳过操作数：{self.skipped}")

    def init_status(self):
        """将记录器状态初始化"""
        self.start_time = time.time()
        self.end_time = self.start_time
        self.total = 0
        self.success = 0
        self.failure = 0
        self.skipped = 0
        self.failures_log = []


def get_thread_logger():
    """
    获取当前线程专属的 logger 实例
    """
    if not hasattr(local_data, "logger"):
        local_data.logger = OperationLogger()
    return local_data.logger
