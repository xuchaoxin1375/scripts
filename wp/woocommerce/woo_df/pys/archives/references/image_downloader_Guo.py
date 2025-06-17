import csv
import os
import re
import sqlite3
import threading
import time
from queue import Queue
from urllib.parse import urlparse

import requests

# 设置工作目录
# 这行代码的目的是确定脚本文件所在的文件夹，并将这个文件夹的路径存储在 BASE_DIR 变量中。
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# 下载队列
q = Queue()

# 下载计数器
download_count = 0
failed_count = 0
lock = threading.Lock()

# 全局配置
config = {
    "use_original_path": True,  # 是否使用原始路径
    "target_dir": os.path.join(BASE_DIR, "buimg"),  # 默认目标目录
}


def download_image(url):
    """下载图片并保存到指定路径"""
    global download_count, failed_count

    try:
        if config["use_original_path"]:
            # 按照原始路径保存
            parsed_url = urlparse(url)
            path_parts = parsed_url.path.strip("/").split("/")

            # 获取域名之后的路径部分
            domain_parts = parsed_url.netloc.split(".")
            if len(domain_parts) >= 3:
                # 提取二级域名作为第一级目录
                first_dir = domain_parts[0]
            else:
                first_dir = domain_parts[0]

            # 构建完整的本地路径
            local_dir = os.path.join(config["target_dir"], first_dir, *path_parts[:-1])

            # 构建文件名
            file_name = path_parts[-1]
        else:
            # 直接保存到目标目录
            parsed_url = urlparse(url)
            path_parts = parsed_url.path.strip("/").split("/")

            # 使用完整URL的MD5或最后一部分作为文件名
            file_name = path_parts[-1]

            # 构建本地路径
            local_dir = config["target_dir"]

        # 确保目录存在
        os.makedirs(local_dir, exist_ok=True)

        local_path = os.path.join(local_dir, file_name)

        # 如果文件已存在，跳过下载
        if os.path.exists(local_path):
            print(f"文件已存在：{local_path}")
            return

        # 下载图片
        response = requests.get(url, stream=True, timeout=30)

        # 检查响应状态
        if response.status_code == 200:
            with open(local_path, "wb") as f:
                for chunk in response.iter_content(chunk_size=1024):
                    if chunk:
                        f.write(chunk)

            # 更新计数器
            with lock:
                download_count += 1
                print(f"成功下载 [{download_count}]: {url} -> {local_path}")
        else:
            with lock:
                failed_count += 1
                print(
                    f"下载失败 [{failed_count}]: {url}, 状态码: {response.status_code}"
                )

    except Exception as e:
        with lock:
            failed_count += 1
            print(f"处理出错 [{failed_count}]: {url}, 错误: {str(e)}")


def worker():
    """工作线程函数"""
    while True:
        url = q.get()
        if url is None:
            break
        download_image(url)
        q.task_done()


def get_urls_from_db(db_path):
    """从SQLite数据库获取URL"""
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # 获取表名列表
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()

        # 打印表名列表供用户选择
        print("数据库中的表:")
        for i, table in enumerate(tables):
            print(f"{i + 1}. {table[0]}")

        table_idx = int(input("请选择包含产品图片的表 (输入序号): ")) - 1
        table_name = tables[table_idx][0]

        # 获取所选表的列名
        cursor.execute(f"PRAGMA table_info({table_name})")
        columns = cursor.fetchall()

        # 打印列名列表供用户选择
        print(f"表 {table_name} 中的列:")
        for i, col in enumerate(columns):
            print(f"{i + 1}. {col[1]}")

        col_idx = int(input("请选择包含图片URL的列 (输入序号): ")) - 1
        column_name = columns[col_idx][1]

        # 查询图片URL
        cursor.execute(f"SELECT {column_name} FROM {table_name}")
        urls = cursor.fetchall()

        # 关闭数据库连接
        conn.close()

        # 提取URL列表
        return [url[0] for url in urls if url[0]]

    except Exception as e:
        print(f"读取数据库出错: {str(e)}")
        return []


def get_urls_from_csv(csv_path):
    """从CSV文件获取URL"""
    try:
        with open(csv_path, "r", encoding="utf-8") as file:
            reader = csv.reader(file)

            # 读取表头
            headers = next(reader)

            # 打印列名列表供用户选择
            print("CSV文件中的列:")
            for i, col in enumerate(headers):
                print(f"{i + 1}. {col}")

            col_idx = int(input("请选择包含图片URL的列 (输入序号): ")) - 1

            # 收集所有URL
            urls = []
            for row in reader:
                if len(row) > col_idx and row[col_idx]:
                    # 检查是否有多个URL用逗号分隔
                    url_text = row[col_idx]
                    if "," in url_text:
                        # 分割多个URL
                        for url in url_text.split(","):
                            url = url.strip()
                            if url and (
                                url.startswith("http://") or url.startswith("https://")
                            ):
                                urls.append(url)
                    else:
                        # 单个URL
                        url = url_text.strip()
                        if url and (
                            url.startswith("http://") or url.startswith("https://")
                        ):
                            urls.append(url)

            return urls

    except Exception as e:
        print(f"读取CSV文件出错: {str(e)}")
        return []


def get_urls_from_txt(txt_path):
    """从文本文件获取URL (支持一行多个URL，用逗号分隔)"""
    try:
        urls = []
        with open(txt_path, "r", encoding="utf-8") as file:
            for line in file:
                # 处理每一行
                line = line.strip()
                if not line:
                    continue

                # 分割逗号分隔的多个URL
                line_urls = line.split(",")
                for url in line_urls:
                    url = url.strip()
                    if url and (
                        url.startswith("http://") or url.startswith("https://")
                    ):
                        urls.append(url)

        return urls

    except Exception as e:
        print(f"读取文本文件出错: {str(e)}")
        return []


def configure_download_settings():
    """配置下载设置"""
    print("\n配置下载设置:")
    print("1. 按照原始路径下载 (保持网站目录结构)")
    print("2. 直接下载到指定目录 (不保留原始路径)")

    choice = input("请选择下载方式 (1-2) [默认:1]: ").strip()
    config["use_original_path"] = True if not choice or choice == "1" else False

    target_dir = input(f"请输入保存目录路径 [默认:{config['target_dir']}]: ").strip()
    if target_dir:
        config["target_dir"] = target_dir

    # 确保目标目录存在
    os.makedirs(config["target_dir"], exist_ok=True)

    print(f"\n下载设置已配置:")
    print(
        f"- {'按照原始路径下载' if config['use_original_path'] else '直接下载到指定目录'}"
    )
    print(f"- 保存到: {config['target_dir']}")


def main():
    """主函数"""
    print("多线程图片下载工具")
    print("====================")
    print("1. 从SQLite数据库下载")
    print("2. 从CSV文件下载")
    print("3. 从TXT文件下载 (支持一行多个URL，用逗号分隔)")

    choice = int(input("请选择下载源 (1-3): "))

    # 根据选择获取URL
    valid_urls = []

    if choice == 1:
        # 从数据库获取
        db_path = input("请输入数据库文件路径: ")
        urls = get_urls_from_db(db_path)

    elif choice == 2:
        # 从CSV获取
        csv_path = input("请输入CSV文件路径: ")
        urls = get_urls_from_csv(csv_path)

    elif choice == 3:
        # 从TXT获取
        txt_path = input("请输入TXT文件路径: ")
        urls = get_urls_from_txt(txt_path)

    else:
        print("无效的选择!")
        return

    # 配置下载设置
    configure_download_settings()

    # 设置线程数
    num_threads = int(input(f"请输入下载线程数 [默认:{10}]: ") or "10")

    # 过滤有效的URL
    valid_urls = [
        url
        for url in urls
        if url
        and isinstance(url, str)
        and (url.startswith("http://") or url.startswith("https://"))
    ]

    total_images = len(valid_urls)
    print(f"找到 {total_images} 个有效的图片URL")

    if total_images == 0:
        print("没有找到有效的图片URL，程序退出。")
        return

    # 创建并启动工作线程
    threads = []
    for _ in range(num_threads):
        t = threading.Thread(target=worker)
        t.start()
        threads.append(t)

    # 将URL放入队列
    for url in valid_urls:
        q.put(url)

    # 等待队列处理完成
    q.join()

    # 停止工作线程
    for _ in range(num_threads):
        q.put(None)
    for t in threads:
        t.join()

    print(f"\n处理完成!")
    print(f"成功下载: {download_count} 个图片")
    print(f"失败: {failed_count} 个图片")


if __name__ == "__main__":
    start_time = time.time()
    main()
    elapsed_time = time.time() - start_time
    print(f"总耗时: {elapsed_time:.2f} 秒")
