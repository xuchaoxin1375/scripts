"""
快速统计指定文件或目录的磁盘占用大小（Python 3.6+）

功能说明：
- 输入可以是单个文件或目录
- 快速计算总大小（使用 os.scandir + ThreadPoolExecutor 提升效率）
- 自动格式化输出单位（B, KB, MB, GB...）
- 支持跨平台（Windows/Linux/macOS）
"""

import os
import sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor



def format_size(size_in_bytes):
    """
    将字节大小转换为易读的单位（KB、MB、GB 等）

    参数:
        size_in_bytes (int): 文件大小（以字节为单位）

    返回:
        str: 友好格式的大小字符串
    """
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size_in_bytes < 1024:
            return f"{size_in_bytes:.2f} {unit}"
        size_in_bytes /= 1024
    return f"{size_in_bytes:.2f} PB"


def get_file_size(file_path):
    """获取单个文件的大小，失败时返回 0"""
    try:
        return file_path.stat().st_size
    except Exception as e:
        print(f"⚠️ 跳过文件 '{file_path}': {e}")
        return 0


def get_directory_size(path):
    """
    使用多线程快速统计目录大小

    参数:
        path (str or Path): 目录路径

    返回:
        int: 总大小（以字节为单位）
    """
    total_size = 0
    file_paths = []

    for root, dirs, files in os.walk(path):
        for file in files:
            file_path = Path(root) / file
            file_paths.append(file_path)

    with ThreadPoolExecutor() as executor:
        results = executor.map(get_file_size, file_paths)
        total_size = sum(results)

    return total_size


def get_size(path):
    """
    获取指定路径的磁盘占用大小（支持文件和目录）

    参数:
        path (str or Path): 文件或目录路径

    返回:
        int: 总大小（以字节为单位）
    """
    path = Path(path)

    if not path.exists():
        raise FileNotFoundError(f"路径不存在: {path}")

    if path.is_file():
        return path.stat().st_size

    return get_directory_size(path)


def main():
    """
    主函数：解析命令行参数并执行统计任务
    """

    if len(sys.argv) != 2:
        print("❌ 错误：请提供一个文件或目录路径作为参数。")
        print("用法示例：python disk_usage.py /path/to/file_or_dir")
        sys.exit(1)

    input_path = sys.argv[1]

    try:
        total_bytes = get_size(input_path)
        formatted_size = format_size(total_bytes)
        print(f"📦 '{input_path}' 的总磁盘占用大小为：{formatted_size}")
    except Exception as e:
        print(f"❌ 错误：{e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
