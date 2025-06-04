"""
导出产品名称和产品所属的国家(附带来源的网站域名)
对比两份表格文件:一份是带有产品名+域名的订单表,另一份是带有域名+国家的站点记录表
通过去重等处理,截取我们关心的表格的列,通过域名联表查询(inner),获取产品名称(关键词)所属的国家(语言)

细节的地方是域名规范处理,比如www.domain.com和domain.com都可以匹配到domain.com,使用专门的正则处理了这些细节
"""

import re
import warnings

import pandas as pd

from comutils import get_domain_name_from_str

warnings.filterwarnings("ignore", category=UserWarning, module="openpyxl")

orders_file = r"C:/users/Administrator/Downloads/2025-06-03 08_49_52-order数据.xlsx"
domain_table = r"C:/users/Administrator/Downloads/site_records_cxxu.xlsx"
result_file = r"C:/users/Administrator/Desktop/result.xlsx"
df = pd.read_excel(orders_file)
p = re.compile(r"([-\w]+\.){1,2}[-\w]+")
# df.info()





df1 = df[["产品名称", "域名"]].copy()
df1["域名"] = df1["域名"].apply(get_domain_name_from_str)
df1.drop_duplicates(subset=["产品名称"], inplace=True)
# 使用在线表格下载下来的excel表格格式肯能不符标准规范,可以用office excel打开(启用编辑)然后保存(会尝试保存为标准excel格式)
df2 = pd.read_excel(domain_table)
# df2.info()
df2 = df2[["域名", "国家"]].copy()
df2["域名"] = df2["域名"].apply(get_domain_name_from_str)


# 连接df1和df2,依据为相同的域名
df = pd.merge(df1, df2, on="域名", how="inner")
df.to_excel(result_file, index=False)
