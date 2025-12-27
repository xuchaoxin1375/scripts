"""进度记录管理器

用于记录和恢复图片下载任务的进度，支持多线程环境下的线程安全操作。
"""

import json
import os
import threading
import time
from typing import Dict, Optional, Set
from urllib.parse import urlparse


class ProgressRecorder:
    """进度记录管理器，用于记录每个URL的下载状态"""

    # 不可重试的状态码（如404表示资源不存在，无需重试）
    NON_RETRYABLE_STATUS_CODES = {404}

    def __init__(self, record_file: str):
        """
        初始化进度记录器

        Args:
            record_file: 记录文件路径（JSON格式）
        """
        self.record_file = record_file
        self.lock = threading.Lock()  # 用于多线程环境下的文件操作
        self.records: Dict[str, Dict] = {}
        self._load_records()

    def _load_records(self):
        """从文件加载记录"""
        if os.path.exists(self.record_file):
            try:
                with open(self.record_file, "r", encoding="utf-8") as f:
                    self.records = json.load(f)
                info("已加载 %d 条下载记录", len(self.records))
            except Exception as e:
                warning("加载记录文件失败: %s，将创建新记录", e)
                self.records = {}
        else:
            self.records = {}
            info("记录文件不存在，将创建新记录: %s", self.record_file)

    def _save_records(self):
        """保存记录到文件（线程安全）"""
        try:
            # 确保目录存在
            os.makedirs(os.path.dirname(self.record_file) or ".", exist_ok=True)
            # 使用临时文件+原子重命名确保写入安全
            temp_file = self.record_file + ".tmp"
            with open(temp_file, "w", encoding="utf-8") as f:
                json.dump(self.records, f, ensure_ascii=False, indent=2)
            # 原子替换
            if os.path.exists(self.record_file):
                os.replace(temp_file, self.record_file)
            else:
                os.rename(temp_file, self.record_file)
        except Exception as e:
            error(f"保存记录文件失败: {e}")

    def record_success(self, url: str, filename: str = "", http_code: int = 200):
        """
        记录成功下载

        Args:
            url: 图片URL
            filename: 保存的文件名
            http_code: HTTP状态码
        """
        with self.lock:
            self.records[url] = {
                "status": "success",
                "http_code": http_code,
                "filename": filename,
                "timestamp": time.time(),
            }
            self._save_records()

    def record_failure(
        self, url: str, status: str, http_code: Optional[int] = None, filename: str = ""
    ):
        """
        记录下载失败

        Args:
            url: 图片URL
            status: 失败状态（如 "failed", "404", "429", "403"）
            http_code: HTTP状态码（如果有）
            filename: 文件名（如果有）
        """
        with self.lock:
            self.records[url] = {
                "status": status,
                "http_code": http_code,
                "filename": filename,
                "timestamp": time.time(),
            }
            self._save_records()

    def is_completed(self, url: str) -> bool:
        """
        检查URL是否已完成（成功或不可重试的失败）

        Args:
            url: 图片URL

        Returns:
            True表示已完成（成功或404等不可重试），False表示需要重试
        """
        if url not in self.records:
            return False

        record = self.records[url]
        status = record.get("status", "")

        # 成功下载
        if status == "success":
            return True

        # 不可重试的状态码（如404）
        http_code = record.get("http_code")
        if http_code in self.NON_RETRYABLE_STATUS_CODES:
            return True

        # 其他失败状态需要重试
        return False

    def filter_urls(self, urls: list) -> list:
        """
        过滤URL列表，移除已完成的URL

        Args:
            urls: 原始URL列表

        Returns:
            过滤后的URL列表（仅包含需要下载的URL）
        """
        filtered = [url for url in urls if not self.is_completed(url)]
        skipped_count = len(urls) - len(filtered)
        if skipped_count > 0:
            info("从进度记录中跳过 %d 个已完成的URL", skipped_count)
        return filtered

    def filter_name_url_pairs(self, name_url_pairs: list) -> list:
        """
        过滤(文件名, URL)对列表，移除已完成的URL

        Args:
            name_url_pairs: (文件名, URL)元组列表

        Returns:
            过滤后的(文件名, URL)对列表
        """
        filtered = [
            (name, url) for name, url in name_url_pairs if not self.is_completed(url)
        ]
        skipped_count = len(name_url_pairs) - len(filtered)
        if skipped_count > 0:
            info("从进度记录中跳过 %d 个已完成的URL", skipped_count)
        return filtered

    def get_statistics(self) -> Dict:
        """
        获取记录统计信息

        Returns:
            包含统计信息的字典
        """
        stats = {
            "total": len(self.records),
            "success": 0,
            "failed": 0,
            "non_retryable": 0,
        }

        for record in self.records.values():
            status = record.get("status", "")
            http_code = record.get("http_code")

            if status == "success":
                stats["success"] += 1
            elif http_code in self.NON_RETRYABLE_STATUS_CODES:
                stats["non_retryable"] += 1
            else:
                stats["failed"] += 1

        return stats

    def print_statistics(self):
        """打印记录统计信息"""
        stats = self.get_statistics()
        info("=" * 50)
        info("进度记录统计:")
        info("总记录数: %d", stats["total"])
        info("成功: %d", stats["success"])
        info("失败（可重试）: %d", stats["failed"])
        info("失败（不可重试，如404）: %d", stats["non_retryable"])
        info("=" * 50)


def generate_record_file_path(
    output_dir: str, workers: int = 10, download_method: str = "request"
) -> str:
    """
    根据下载参数生成记录文件路径

    Args:
        output_dir: 输出目录
        workers: 线程数
        download_method: 下载方法

    Returns:
        记录文件路径
    """
    # 使用输出目录和关键参数生成唯一的记录文件名
    # 例如: ./images/progress_w10_request.json
    record_dir = output_dir
    # record_filename = f"progress_w{workers}_{download_method}.json"
    record_filename = f"progress.json"
    return os.path.join(record_dir, record_filename)


# 导入日志函数（延迟导入避免循环依赖）
def _get_logger():
    import logging

    logger = logging.getLogger("ImageDownloader.progress_recorder")
    return logger


def info(msg, *args):
    logger = _get_logger()
    logger.info(msg, *args)


def warning(msg, *args):
    logger = _get_logger()
    logger.warning(msg, *args)


def error(msg, *args):
    logger = _get_logger()
    logger.error(msg, *args)

