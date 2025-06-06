"""
导出产品名称和产品所属的国家(附带来源的网站域名)

此脚本会对比两份表格文件:
1. 一份是带有产品名+域名的订单表
2. 另一份是带有域名+国家的站点记录表

通过去重等处理,截取我们关心的表格的列,通过域名联表查询(inner),获取产品名称(关键词)所属的国家(语言)

- 细节的地方是域名规范处理,比如www.domain.com和domain.com都可以匹配到domain.com,使用专门的正则处理了这些细节
"""

import os
import re
import subprocess
import time
import warnings

import pandas as pd
from comutils import get_domain_name_from_str

# 当前时间
now = time.strftime("%Y-%m-%d %H_%M", time.localtime())

warnings.filterwarnings("ignore", category=UserWarning, module="openpyxl")

ORDERS_FILE = r"C:/users/Administrator/Downloads/2025-06-03 08_49_52-order数据.xlsx"

DOMAIN_TABLE_PATH = r"C:/users/Administrator/Desktop/me"
MERGED_TABLES = rf"C:/users/Administrator/Desktop/各组[域名-国家]合并结果@{now}.xlsx"
RESULT_FILE = rf"C:/users/Administrator/Desktop/result(产品关键词-国家)@{now}.xlsx"


def merge_excel_files(table_path, add_source=True):
    """
    合并指定目录下所有包含"域名"和"国家"列的.xlsx文件到一个DataFrame中。

    参数:
        directory (str): 包含Excel文件的目录路径。
        add_source (bool): 是否增加"文件来源"列，默认不增加。

    返回:
        pd.DataFrame: 合并后的DataFrame，包含"域名"和"国家"列。
    """
    all_data = []
    if os.path.isfile(table_path):
        if table_path.endswith(".xlsx"):
            data = get_data_from_table(table_path, add_source=add_source)
            all_data.extend(data)
    else:
        for file in os.listdir(table_path):
            if file.endswith(".xlsx"):
                file_path = os.path.join(table_path, file)
                data = get_data_from_table(file_path=file_path, add_source=add_source)
                all_data.extend(data)

    if all_data:
        merged_df = pd.concat(all_data, ignore_index=True)
        merged_df.to_excel(MERGED_TABLES, index=False)
        return merged_df
    else:
        print("没有找到符合条件的表格文件。")
        return pd.DataFrame(
            columns=["域名", "国家"] + (["文件来源"] if add_source else [])
        )


def get_data_from_table(file_path, add_source):
    """从单个表格文件中获取数据"""
    all_data = []
    try:
        df = pd.read_excel(file_path)
        # 检查是否包含所需的列
        if "域名" in df.columns and "国家" in df.columns:
            current_df = df[["域名", "国家"]].copy()
            if add_source:
                current_df["文件来源"] = file_path  # 添加来源文件名
            all_data.append(current_df)

        else:
            print(f"警告：文件 {file_path} 缺少必要的列，跳过该文件。")
    except Exception as e:
        print(f"读取文件 {file_path} 出错: {e}")
    return all_data


def main():
    df = pd.read_excel(ORDERS_FILE)
    p = re.compile(r"([-\w]+\.){1,2}[-\w]+")
    # df.info()
    df1 = df[["产品名称", "域名"]].copy()
    df1["域名"] = df1["域名"].apply(get_domain_name_from_str)
    df1.drop_duplicates(subset=["产品名称"], inplace=True)

    # 使用在线表格下载下来的excel表格格式肯能不符标准规范,可以用office excel打开(启用编辑)然后保存(会尝试保存为标准excel格式)
    # df2 = pd.read_excel(domain_table)
    df2 = merge_excel_files(DOMAIN_TABLE_PATH)
    # df2.info()
    df2 = df2[["域名", "国家"]].copy()
    df2["域名"] = df2["域名"].apply(get_domain_name_from_str)

    # 连接df1和df2,依据为相同的域名
    df = pd.merge(df1, df2, on="域名", how="inner")
    df.to_excel(RESULT_FILE, index=False)
    print(f"尝试将结果文件已保存到 {RESULT_FILE} 请检查(默认在桌面)")

    if os.path.exists(RESULT_FILE):
        if os.name == "nt":  # Windows
            os.startfile(RESULT_FILE)
        elif os.name == "posix":
            subprocess.call(["open", RESULT_FILE])  # macOS
        else:
            subprocess.call(["xdg-open", RESULT_FILE])  # Linux
    else:
        print("文件不存在")


if __name__ == "__main__":
    main()
