"""
导出产品名称和产品所属的国家(附带来源的网站域名)

此脚本会对比两份表格文件:
1. 一份是带有产品名+域名的订单表
2. 另一份是带有域名+国家的站点记录表

通过去重等处理,截取我们关心的表格的列,通过域名联表查询(inner),获取产品名称(关键词)所属的国家(语言)

- 细节的地方是域名规范处理,比如www.domain.com和domain.com都可以匹配到domain.com,使用专门的正则处理了这些细节
"""

import argparse
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

# 默认常量（可被命令行覆盖）
DEFAULT_ORDERS_FILE = (
    r"C:/users/Administrator/Downloads/2025-06-03 08_49_52-order数据.xlsx"
)
DEFAULT_DOMAIN_TABLE_PATH = r"C:/users/Administrator/Desktop/me"
DEFAULT_MERGED_TABLES = (
    rf"C:/users/Administrator/Desktop/各组[域名-国家]合并结果_{now}.xlsx"
)
DEFAULT_RESULT_FILE = (
    rf"C:/users/Administrator/Desktop/result(产品关键词-国家)@{now}.xlsx"
)


def parse_args():
    """ 解析命令行参数 """
    parser = argparse.ArgumentParser(description="导出产品关键词及其所属国家")
    parser.add_argument(
        "--orders-file",
        "-of",
        type=str,
        default=DEFAULT_ORDERS_FILE,
        help="订单文件路径（包含产品名称和域名）",
    )
    parser.add_argument(
        "--domain-table-path",
        "-dp",
        type=str,
        default=DEFAULT_DOMAIN_TABLE_PATH,
        help="域名-国家表格目录或单个文件路径",
    )
    parser.add_argument(
        "--output-result",
        "-or",
        type=str,
        default=DEFAULT_RESULT_FILE,
        help="输出结果文件路径",
    )
    parser.add_argument(
        "--output-merged",
        "-om",
        type=str,
        default=DEFAULT_MERGED_TABLES,
        help="合并后的域名-国家表输出路径",
    )
    parser.add_argument(
        "--add-source", "-as", action="store_true", help="是否添加'文件来源'列"
    )
    parser.add_argument(
        "--no-add-source",
        "-nas",
        dest="add_source",
        action="store_false",
        help="不添加'文件来源'列",
    )
    parser.set_defaults(add_source=True)
    parser.add_argument(
        "--open",
        "-op",
        dest="auto_open",
        action="store_true",
        help="是否自动打开生成的Excel文件",
    )
    parser.set_defaults(auto_open=True)

    return parser.parse_args()


def merge_excel_files(table_path, add_source=True):
    """
    合并指定目录下所有包含"域名"和"国家"列的.xlsx文件到一个DataFrame中。
    支持传入一个目录或一个单独的 .xlsx 文件。
    """
    all_data = []

    if os.path.isfile(table_path) and table_path.endswith(".xlsx"):
        data = get_data_from_table(table_path, add_source=add_source)
        all_data.extend(data)
    elif os.path.isdir(table_path):
        for file in os.listdir(table_path):
            if file.endswith(".xlsx"):
                file_path = os.path.join(table_path, file)
                data = get_data_from_table(file_path, add_source=add_source)
                all_data.extend(data)
    else:
        print(f"无效路径: {table_path}")
        return pd.DataFrame(
            columns=["域名", "国家"] + (["文件来源"] if add_source else [])
        )

    if all_data:
        merged_df = pd.concat(all_data, ignore_index=True)
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
        if "域名" in df.columns and "国家" in df.columns:
            current_df = df[["域名", "国家"]].copy()
            if add_source:
                current_df["文件来源"] = file_path
            all_data.append(current_df)
        else:
            print(f"警告：文件 {file_path} 缺少必要列，跳过该文件。")
    except Exception as e:
        print(f"读取文件 {file_path} 出错: {e}")
    return all_data


def main():
    args = parse_args()

    # 全局变量赋值
    orders_file = args.orders_file
    domain_table_path = args.domain_table_path
    result_file = args.output_result
    merged_tables = args.output_merged
    add_source = args.add_source
    auto_open = args.auto_open

    # 处理订单文件
    df = pd.read_excel(orders_file)
    df1 = df[["产品名称", "域名"]].copy()
    df1["域名"] = df1["域名"].apply(get_domain_name_from_str)
    df1.drop_duplicates(subset=["产品名称"], inplace=True)

    # 获取域名-国家映射
    df2 = merge_excel_files(domain_table_path, add_source=add_source)
    df2["域名"] = df2["域名"].apply(get_domain_name_from_str)

    # 联表查询
    df_final = pd.merge(df1, df2, on="域名", how="inner")
    df_final.to_excel(result_file, index=False)
    print(f"✅ 结果已保存至: {result_file}")

    # 可选：保存合并后的域名-国家表
    if add_source:
        df2.to_excel(merged_tables, index=False)
        print(f"📁 合并后的域名-国家表已保存至: {merged_tables}")

    # 自动打开
    if auto_open and os.path.exists(result_file):
        if os.name == "nt":
            os.startfile(result_file)
        elif os.name == "posix":
            subprocess.call(["open", result_file])
        else:
            subprocess.call(["xdg-open", result_file])


if __name__ == "__main__":
    import argparse

    main()
