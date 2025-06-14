"""将原始的网址列表文件中检测出shopify的网站，并将结果保存到excel文件中"""

# %%
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock

import requests
from openpyxl import Workbook
from openpyxl.styles import Font
import pandas as pd
from config import *

domain_file = rf"{SPIDER_TASKS}/domains.txt"
domain_file_excel = rf"{SPIDER_TASKS}/domains.xlsx"
check_result_file = rf"{SPIDER_TASKS}/shopify_result.xlsx"

# %%


# Shopify 检测函数
def is_shopify_site(html):
    """检测是否为 Shopify 网站"""
    keywords = [
        "cdn.shopify.com",
        "x-shopify-stage",
        "x-shopify",
        "Shopify.theme",
        "/cart.js",
        "window.Shopify",
    ]
    return any(keyword in html for keyword in keywords)


# 检测域名
def check_domain(index, domain):
    """检测shopify网站特征"""
    url = domain if domain.startswith("http") else f"https://{domain}"
    try:
        response = requests.get(url, timeout=60, headers={"User-Agent": "Mozilla/5.0"})
        if is_shopify_site(response.text):
            return (index, domain, "是", "检测到 Shopify 特征")
        else:
            return (index, domain, "否", "未发现 Shopify 特征")
    except Exception as e:
        return (index, domain, "检测失败", str(e))


# def get_domain_list(filename):
#     """从表格文件中获取域名列表"""
    

def check_domains_multithread(filename, max_threads=10):
    """多线程检查"""
    with open(filename, "r", encoding="utf-8") as f:
        domain_list = [line.strip() for line in f if line.strip()]

    results_dict = {}
    lock = Lock()

    print("🚀 开始检测...\n")

    with ThreadPoolExecutor(max_workers=max_threads) as executor:
        futures = {
            executor.submit(check_domain, idx, domain): idx
            for idx, domain in enumerate(domain_list)
        }

        for future in as_completed(futures):
            result = future.result()
            index, domain, status, comment = result

            # 实时控制台输出
            print(f"[{index+1}/{len(domain_list)}] {domain} => {status} ({comment})")

            # 存储结果
            with lock:
                results_dict[index] = result

    # 保证顺序
    ordered_results = [results_dict[i] for i in range(len(domain_list))]

    # 写入 Excel
    wb = Workbook()
    ws = wb.active
    ws.title = "Shopify检测结果"
    ws.append(["域名", "是否为 Shopify 网站", "备注"])

    for cell in ws[1]:
        cell.font = Font(bold=True)

    for _, domain, status, comment in ordered_results:
        ws.append([domain, status, comment])

    wb.save(check_result_file)
    print(f"\n✅ 检测完成，结果已按顺序保存为 {check_result_file}")


if __name__ == "__main__":
    check_domains_multithread(domain_file, max_threads=10)
