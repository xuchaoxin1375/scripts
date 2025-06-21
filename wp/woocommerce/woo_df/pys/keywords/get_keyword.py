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

# from comutils import get_main_domain_name_from_str


# 当前时间
now = time.strftime("%Y-%m-%d %H_%M", time.localtime())

warnings.filterwarnings("ignore", category=UserWarning, module="openpyxl")

ORDERS_FILE = r"C:\Users\Administrator\Desktop\keywords\订单总表.xlsx"

DOMAIN_TABLE_PATH = r"C:\Users\Administrator\Desktop\keywords\各组域名-国家表"
MERGED_TABLES = rf"C:/users/Administrator/Desktop/各组[域名-国家]合并结果@{now}.xlsx"
RESULT_FILE = rf"C:/users/Administrator/Desktop/result(产品关键词-国家)@{now}.xlsx"


def normalize_columns(df):
    """
    将语义相同但名称不同的列标准化为统一名称。
    """
    column_mapping = {
        "域名": "域名",
        "网站域名": "域名",
        "国家": "国家",
        "网站语言": "国家",
        "网站国家": "国家",
        "语言": "国家",
    }
    # 只保留包含必要列的文件
    available_columns = [col for col in df.columns if col in column_mapping]
    if len(available_columns) < 2:
        raise ValueError("缺少必要的列（需要包含'域名'或等效列，以及'国家'或等效列）")
    # 映射列名为统一名称
    df.rename(
        columns={col: column_mapping[col] for col in available_columns}, inplace=True
    )
    return df[["域名", "国家"]]


def get_main_domain_name_from_str(url):
    """
    从字符串中提取域名,结构形如 "二级域名.顶级域名",即SLD.TLD;
    仅提取一个域名,适合于对于一个字符串中仅包含一个确定的域名的情况
    例如,对于更长的结构,"子域名.二级域名.顶级域名"则会丢弃子域名,前缀带有http(s)的部分也会被移除
    # 测试URL列表
    urls = ['www.domain.com', 'https://www.dom-ain.com', 'domain-test.com', 'http://domain.com', 'https://domain.com/']
    """
    # 使用正则表达式提取域名
    url = str(url)
    # print(f"原始URL: {url}")
    match = re.search(r"(?:https?://)?(?:www\.)?([^/]+)", url)
    if match:
        res = match.group(1)
        print(f"提取域名: {res}")
        return res
    return None


def merge_excel_files(table_path, add_source=True):
    """
    合并指定目录下所有包含"域名"或"国家"列的.xlsx文件到一个DataFrame中。
    """
    all_data = []
    if os.path.isfile(table_path):
        if table_path.endswith(".xlsx"):
            data = get_data_from_table(table_path, add_source=add_source)
            if not data.empty:
                all_data.append(data)
    else:
        for file in os.listdir(table_path):
            if file.endswith(".xlsx"):
                file_path = os.path.join(table_path, file)
                data = get_data_from_table(file_path, add_source=add_source)
                if not data.empty:
                    all_data.append(data)
                print(f"该文件{file_path}共读取了 {len(data)} 条数据")

    if all_data:
        merged_df = pd.concat(all_data, ignore_index=True)
        total = len(merged_df)
        print(f"读取报告:共读取了 {total} 条数据")

        merged_df.to_excel(MERGED_TABLES, index=False)
        return merged_df
    else:
        print("没有找到符合条件的表格文件。")
        return pd.DataFrame(
            columns=["域名", "国家"] + (["文件来源"] if add_source else [])
        )


# def merge_excel_files(table_path, add_source=True):
#     """
#     合并指定目录下所有包含"域名"和"国家"列的.xlsx文件到一个DataFrame中。

#     参数:
#         directory (str): 包含Excel文件的目录路径。
#         add_source (bool): 是否增加"文件来源"列，默认不增加。

#     返回:
#         pd.DataFrame: 合并后的DataFrame，包含"域名"和"国家"列。
#     """
#     all_data = []
#     if os.path.isfile(table_path):
#         if table_path.endswith(".xlsx"):
#             data = get_data_from_table(table_path, add_source=add_source)
#             all_data.extend(data)
#     else:
#         for file in os.listdir(table_path):
#             if file.endswith(".xlsx"):
#                 file_path = os.path.join(table_path, file)
#                 data = get_data_from_table(file_path=file_path, add_source=add_source)
#                 all_data.extend(data)

#     if all_data:
#         merged_df = pd.concat(all_data, ignore_index=True)
#         merged_df.to_excel(MERGED_TABLES, index=False)
#         return merged_df
#     else:
#         print("没有找到符合条件的表格文件。")
#         return pd.DataFrame(
#             columns=["域名", "国家"] + (["文件来源"] if add_source else [])
#         )


# def get_data_from_table(file_path, add_source):
#     """从单个表格文件中获取数据"""
#     all_data = []
#     try:
#         df = pd.read_excel(file_path)
#         # 检查是否包含所需的列
#         if "域名" in df.columns and "国家" in df.columns:
#             current_df = df[["域名", "国家"]].copy()
#             if add_source:
#                 current_df["文件来源"] = file_path  # 添加来源文件名
#             all_data.append(current_df)

#         else:
#             print(f"警告：文件 {file_path} 缺少必要的列，跳过该文件。")
#     except Exception as e:
#         print(f"读取文件 {file_path} 出错: {e}")
#     return all_data


def get_data_from_table(file_path, add_source=False):
    """从单个表格文件中获取数据，并处理不同命名的列"""
    try:
        df = pd.read_excel(file_path)
        # 标准化列名
        df_standard = normalize_columns(df).copy()
        if add_source:
            df_standard["文件来源"] = file_path
        return df_standard
    except Exception as e:
        print(f"读取文件 {file_path} 出错: {e}")
        return pd.DataFrame(
            columns=["域名", "国家"] + (["文件来源"] if add_source else [])
        )


def main():
    """主函数"""
    df = pd.read_excel(ORDERS_FILE)
    print(f"订单表共读取了 {len(df)} 条数据")
    # p = re.compile(r"([-\w]+\.){1,2}[-\w]+")
    # df.info()
    df1 = df[["产品名称", "域名"]].copy()
    df1["域名"] = df1["域名"].apply(get_main_domain_name_from_str)
    df1.drop_duplicates(subset=["产品名称"], inplace=True)

    # 使用在线表格下载下来的excel表格格式肯能不符标准规范,可以用office excel打开(启用编辑)然后保存(会尝试保存为标准excel格式)
    # df2 = pd.read_excel(domain_table)
    df2 = merge_excel_files(DOMAIN_TABLE_PATH)
    # df2.info()
    df2 = df2[["域名", "国家"]].copy()
    df2["域名"] = df2["域名"].apply(get_main_domain_name_from_str)

    # 连接df1和df2,依据为相同的域名
    df = pd.merge(df1, df2, on="域名", how="inner")
    df.drop_duplicates(subset=["产品名称"], inplace=True)
    # 根据产品名称排序
    df.sort_values(by="产品名称", inplace=True)
    # 保存结果文件🎈
    df.to_excel(RESULT_FILE, index=False)
    print(f"尝试将结果文件已保存到 {RESULT_FILE} 请检查(默认在桌面)")

    print(f"处理报告: 处理后共得到 {len(df)} 条数据。")

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
