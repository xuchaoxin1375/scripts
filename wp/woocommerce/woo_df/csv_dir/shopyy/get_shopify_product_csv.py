"""PTDF woocommerce csv file to shopify(shopyy) format changer
documents:
https://help.shopify.com/zh-CN/manual/products/import-export/using-csv#csv-file-description
# product template csv file:
https://help.shopify.com/csv/product_template.csv

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

# shopify模板中的大致字段
原始列: ['Handle', 'Title', 'Body (HTML)', 'Vendor', 'Product Category', 'Type', 'Tags', 'Published',
'Option1 Name', 'Option1 Value', 'Option2 Name', 'Option2 Value', 'Option3 Name', 'Option3 Value',
'Variant SKU', 'Variant Grams', 'Variant Inventory Tracker', 'Variant Inventory Qty', 'Variant Inventory Policy', 'Variant Fulfillment Service', 'Variant Price', 'Variant Compare At Price', 'Variant Requires Shipping', 'Variant Taxable', 'Variant Barcode', 'Image Src', 'Image Position', 'Image Alt Text', 'Gift Card', 'Variant Image', 'Variant Tax Code', 'Cost per item', 'Included / International', 'Status']



# 笛卡尔积测试(使用itertools.product可以轻松实现笛卡尔积)
m = [
    ["Watermelon", "Neptune"],
    ["XS", "S", "M", "L", "XL", "2XL"],
    ["big", "little", "medium"],
]

"""

# %%
import itertools
from itertools import zip_longest
import logging
import os
import re
from logging import debug, error, info, warning

import pandas as pd

logging.basicConfig(
    level=logging.INFO, format=" %(name)s - %(levelname)s - %(message)s"
)
print(os.getcwd())
# 将工作目录设置为脚本所在目录
script_path = os.path.abspath(__file__)
d = os.path.dirname(script_path)
os.chdir(d)

# SOURCE = r"./simms-eu.demo.csv"
SOURCE = r"./telescope/p1.csv"
# shopify产品模板可以从:https://help.shopify.com/csv/product_template.csv 下载
TEMPLATE_SHOPIFY = r"C:\repos\scripts\wp\woocommerce\woo_df\csv_dir\shopyy\templates\shopify_product_template_empty.csv"
# df = pd.read_csv(SOURCE)
df = pd.read_csv(SOURCE).fillna("")
dft = pd.read_csv(TEMPLATE_SHOPIFY)
# 获取所有字段名
all_columns = dft.columns.tolist()

# 已有字段的映射🎈(从df_woo格式到shopify csv格式)
exist_fields_map = {
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
##
# 分类处理(可选)
# 部分类shopify模板的分类(categories)可以从url中提取,分类的单词之间使用'-'符号分隔,可以用这类的方法替换为`>`
# def replace_separators(s):
#     """替换字符串中的分隔符
#     将`|`或则`-`替换为`>`
#     """
#     pattern = r"/|-"
#     res = re.sub(pattern, ">", s)
#     return res

##
# df['Categories'].str.replace('/|-','>' )
# s_cat = df["Categories"].apply(replace_separators)
# df["Categories"] = s_cat


##
# 价格
# df["Sale price"] = df["Regular price"] * 0.2
s_sale_price = df["Sale price"]
##
# 属性值
attrs = df["Attribute 1 value(s)"]
# attr_lines = [attr for attr in attrs]


def parse_attrs(s: str):
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


def parse_images(imgs):
    """解析图片
    将多图url构成的字符串根据合适的规则分割或提取出一个个图片url字符串构成的列表
    """
    if imgs:
        # imgs=imgs.replace('"',"")
        # res = re.findall(r'"(.*?)"', imgs)
        res = imgs.split(">")
        debug("images: %s", res)
        return res


# 应用解析函数并展开
rows = []
for idx, row in df.iterrows():
    debug("processing row: %s", idx)
    attr = row["Attribute 1 value(s)"]
    # debug(f"attr: {attr}")
    # continue
    names, values = parse_attrs(attr or "")
    images = parse_images(row["Images"]) or []
    z = zip_longest(values, images, fillvalue="")
    for expand_line_idx, (value_group, img) in enumerate(z, start=1):
        # for i, value_group in enumerate(iterable=values, start=1):
        # 每个属性选项组占用一行(生成一个字典)
        d = {}
        debug(
            "expand_line_idx: %s, value_group: %s, img: %s",
            expand_line_idx,
            value_group,
            img,
        )
        # add_attr_name=True
        # 遍历names构造字典(字典中k:v数量取决于names的长度)
        # 商品首行
        if expand_line_idx == 1:
            d["Title"] = row["Name"]
            # d["Product Category"] = row["Categories"]
            d["Type"] = row["Categories"]
            d["Body (HTML)"] = row["Description"]
            # d["Image Src"] = row["Images"]
            # d["Image Src"] = img
            # d["Image Position"] = "1"
            d["Published"] = "TRUE"
        # 同款商品的每一行都要有的
        d["Handle"] = row["SKU"]
        # d["Variant Compare At Price"] = round(row["Regular price"], 2)
        d["Variant Compare At Price"] = round(float(row["Regular price"]), 2)
        d["Variant Price"] = round(float(row["Sale price"]), 2)
        # 多图情况
        d["Image Src"] = img
        d["Image Position"] = str(expand_line_idx)
        # 在当前行(attr_line_order行内)填充属性相关字段(option1~option3)
        options = zip(names, value_group)
        for option_order, (name, value) in enumerate(options, start=1):
            # if add_attr_name:
            debug(
                "attr_line_order: %s, option_order(in line): %s, name: %s,value: %s",
                expand_line_idx,
                option_order,
                name,  # size,color等
                value,
            )
            if expand_line_idx == 1:
                # 每组数据(一款产品占有一组数据行)的首行才添加属性名称,例如:size,color等
                # debug("Head line of this product[%s],")
                d[f"Option{option_order} Name"] = name
            else:
                d[f"Option{option_order} Name"] = ""
            d[f"Option{option_order} Value"] = value_group[option_order - 1]
        debug("check row(d): %s", d)
        rows.append(d)

variants = pd.DataFrame(rows, columns=all_columns)
# 添加额外的专辑列(可选)
variants['Collection']=variants['Type']
## 
variants
##
variants[["Image Src", "Image Position"]]
##
variants.to_csv("changed_1.csv", index=False)

##
