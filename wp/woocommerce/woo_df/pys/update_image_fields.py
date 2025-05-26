"""更新CSV文件中的图片字段(调整和补全字段:Images,ImagesUrl)"""

import os
import pandas as pd
from woosqlitedb import (
    update_image_fields,
    update_image_fields_extension,
    remove_items_without_img,
)
from wooenums import ImageMode, CSVProductFields, DBProductFields, LanguagesHotSale

IMAGE = CSVProductFields.IMAGES.value

IMG_DIR = r"S:/grandwagonsupply/images/"  # 修改图片文件所在目录
CSV_DIR = r"S:\grandwagonsupply\csvs"  # 修改csv文件所在目录

CSV_DIR = os.path.abspath(CSV_DIR)  # 计算绝对路径
# print(CSV_DIR)
# update_image_fields(CSV_DIR)
# update_image_fields_extension(CSV_DIR, extension="webp")
# remove_items_without_img(CSV_DIR, img_dir=IMG_DIR, backup_dir="backup_csvs")

# 统计处理后的各个csv文件分别有多少条数据
TOTAL = 0
for file in os.listdir(CSV_DIR):
    if not file.endswith(".csv"):
        continue
    file = os.path.join(CSV_DIR, file)
    df = pd.read_csv(file)
    TOTAL += len(df)
    print(file, len(df))
