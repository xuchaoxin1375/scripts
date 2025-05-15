"""PTDF woocommerce csv file to shopify(shopyy) format changer
# DF woocommerce fields
['SKU',
 'Name',
 'Categories',
 'Regular price',
 'Sale price',
 'Attribute 1 value(s)',
 'Attribute 1 name',
 'Images',
 'ImagesUrl',
 'Tags',
 'PageUrl',
 'Description']

# 模板
原始列: ['Handle', 'Title', 'Body (HTML)', 'Vendor', 'Product Category', 'Type', 'Tags', 'Published',
'Option1 Name', 'Option1 Value', 'Option2 Name', 'Option2 Value', 'Option3 Name', 'Option3 Value',
'Variant SKU', 'Variant Grams', 'Variant Inventory Tracker', 'Variant Inventory Qty', 'Variant Inventory Policy', 'Variant Fulfillment Service', 'Variant Price', 'Variant Compare At Price', 'Variant Requires Shipping', 'Variant Taxable', 'Variant Barcode', 'Image Src', 'Image Position', 'Image Alt Text', 'Gift Card', 'Variant Image', 'Variant Tax Code', 'Cost per item', 'Included / International', 'Status']

可能要填写的列:
['Handle', 'Title', 'Body (HTML)', 'Product Category', 'Tags', 'Published',
'Option1 Name', 'Option1 Value', 'Option2 Name', 'Option2 Value', 'Option3 Name', 'Option3 Value',
'Variant Grams', 'Variant Inventory Tracker', 'Variant Inventory Qty', 'Variant Inventory Policy', 'Variant Fulfillment Service',
'Variant Price',
'Variant Requires Shipping', 'Variant Taxable', 'Image Src', 'Image Position',
'Gift Card', 'Variant Image', 'Included / International', 'Status'
]
精选的列:
[
'Handle',
'Vendor',
'Published',
# 'Option1 Name',
# 'Option1 Value',
'Published',
'Variant Grams',

]
# 笛卡尔积测试
m = [
    ["Watermelon", "Neptune"],
    ["XS", "S", "M", "L", "XL", "2XL"],
    ["big", "little", "medium"],
]
"""

# %%
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
TEMPLATE_SHOPIFY = r"C:\repos\scripts\wp\woocommerce\woo_df\csv_dir\shopyy\templates\product_template_shopify_empty.csv"
df = pd.read_csv(SOURCE)
dft = pd.read_csv(TEMPLATE_SHOPIFY)
# 获取所有字段名
all_columns = dft.columns.tolist()

# 已有字段的映射🎈(从df_woo格式到shopify csv格式)
exist_fiels_map = {
    "SKU": "Handle",
    "Name": "Title",
    "Categories": "Product Category",
    "Regular price": "Variant Compare At Price",
    "Sale price": "Variant Price",
    "Images": "Image Src",
    # "ImagesUrl": "Image Src",
    "Description": "Body (HTML)",
}
# 需要shopify 属性值字段
attr_fields_shopify = [
    "Option1 Name",
    "Option1 Value",
    "Option2 Name",
    "Option2 Value",
    "Option3 Name",
    "Option3 Value",
]
# 批量创建新列
df[attr_fields_shopify] = ""


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
    """解析属性值

    Examples:

    parse_attrs('Color#Watermelon|Neptune~Size#XS|S|M')

    root - DEBUG - ['Color', 'Size']
    root - DEBUG - [['Watermelon', 'Neptune'], ['XS', 'S', 'M']]
    (['Color', 'Size'],
        [('Watermelon', 'XS'),
        ('Watermelon', 'S'),
        ('Watermelon', 'M'),
        ('Neptune', 'XS'),
        ('Neptune', 'S'),
        ('Neptune', 'M')])

    """
    if s:
        attrs_lines = s.split("~")
        # attr_names=[name for ]
        matrix = [group.split("#") for group in attrs_lines]
        attr_names = [pair[0].strip() for pair in matrix]
        # 例如:['Color', 'Size']

        # for i, name in enumerate(attr_names):
        #     df.loc[i, "Option{i} Name"] = name
        debug(attr_names)
        attr_values = [pair[1].strip() for pair in matrix]
        # debug(attr_values)
        attr_values = [value.split("|") for value in attr_values]
        debug(attr_values)
        # 将属性值排列组合展开

        combinations = list(itertools.product(*attr_values))

        # for name, value in zip(attr_names, result):
        #     df
        return attr_names, combinations
    else:
        return ([], [])


# 应用解析函数并展开
rows = []
for idx, row in df.iterrows():
    debug("processing row: %s", (idx + 1))
    attr = row["Attribute 1 value(s)"]
    names, values = parse_attrs(attr)
    for i, value_group in enumerate(iterable=values, start=1):
        # 每个属性选项组占用一行(生成一个字典)
        d = {}
        # add_attr_name=True
        # 遍历names构造字典(字典中k:v数量取决于names的长度)
        # 商品首行
        if i == 1:
            d["Title"] = row["Name"]
            d["Product Category"] = row["Categories"]
            d["Body (HTML)"] = row["Description"]
            d["Image Src"] = row["Images"]
        # 同款商品的每一行都要有的
        d["Handle"] = row["SKU"]
        d["Variant Compare At Price"] = row["Regular price"]
        d["Variant Price"] = row["Sale price"]
        # 填充属性相关字段
        for j, name in enumerate(names, start=1):
            # if add_attr_name:
            if i==1:
                d[f"Option{j} Name"] = name
                add_attr_name=False
            else:
                d[f"Option{j} Name"] = ""
            d[f"Option{j} Value"] = value_group[j - 1]
        debug("check row(d): %s", d)
        rows.append(d)
variants = pd.DataFrame(rows, columns=all_columns)
variants

##

# df.rename(columns=exist_fiels_map, inplace=True)
# # 移除不需要的列
# df.drop(columns=["Attribute 1 name", "Attribute 1 value(s)","ImagesUrl","PageUrl", "Tags"], inplace=True)
##
