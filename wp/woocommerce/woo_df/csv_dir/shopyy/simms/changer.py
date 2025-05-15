"""PTDF woocommerce csv file to shopify(shopyy) format changer"""

import itertools
import logging
import os
import re
from logging import debug, error, info, warning

import pandas as pd

logging.basicConfig(
    level=logging.DEBUG, format=" %(name)s - %(levelname)s - %(message)s"
)
print(os.getcwd())
# 将工作目录设置为脚本所在目录
script_path = os.path.abspath(__file__)
d = os.path.dirname(script_path)
os.chdir(d)

SOURCE = r"./simms-eu.demo.csv"
df = pd.read_csv(SOURCE)

# 字段映射🎈(从df_woo格式到shopify csv格式)
fiels_map = {
    "Categories": "Product Category",
    "Name": "Title",
    "Sale price": "Variant Price",
    "Regular price": "Variant Compare At Price",
}

# df.rename(columns=fiels_map, inplace=True)


# df.info()
def replace_separators(s):
    """替换字符串中的分隔符"""
    pattern = r"/|-"
    res = re.sub(pattern, ">", s)
    return res


##
# 分类
# df['Categories'].str.replace('/|-','>' )
s_cat = df["Categories"].apply(replace_separators)
df["Categories"] = s_cat


##
# 价格
df["Sale price"] = df["Regular price"] * 0.2
s_sale_price = df["Sale price"]
##
# 属性值
attrs = df["Attribute 1 value(s)"]
# attr_lines = [attr for attr in attrs]


def parse_attrs(s):
    """解析属性值"""
    if s:
        attrs_lines = s.split("~")
        # attr_names=[name for ]
        matrix = [group.split("#") for group in attrs_lines]
        attr_names = [pair[0].strip() for pair in matrix]
        debug(attr_names)
        attr_values = [pair[1].strip() for pair in matrix]
        # debug(attr_values)
        attr_values = [value.split("|") for value in attr_values]
        debug(attr_values)
        # 将属性值排列组合展开

        return attr_names


test_attr = attrs[0]
names = parse_attrs(test_attr)

# for attr in attrs:
#     names = parse_attrs(attr)
##
# 计算列表间的笛卡尔积(Cartesian Product或CROSS JOIN;)


m = [
    ["Watermelon", "Neptune"],
    ["XS", "S", "M", "L", "XL", "2XL"],
    ["big", "little", "medium"],
]

# 计算笛卡尔积
result = list(itertools.product(*m))

# 如果需要二级列表（每个元素为一个列表而非元组）：
result_as_lists = [list(item) for item in result]

print(result_as_lists)
##
