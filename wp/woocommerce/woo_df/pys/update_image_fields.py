"""更新CSV文件中的图片字段(调整和补全字段:Images,ImagesUrl)"""

import os

# import pandas as pd
from woosqlitedb import (
    update_image_fields,
    update_image_fields_extension,
    remove_items_without_img,
)
from wooenums import CSVProductFields
from comutils import count_lines_csv

IMAGE = CSVProductFields.IMAGES.value

IMG_DIR = r"   S:/grandwagonsupply/images/   ".strip()  # 修改图片文件所在目录
CSV_DIR = r"     S:\grandwagonsupply\csvs      ".strip()  # 修改csv文件所在目录

CSV_DIR = os.path.abspath(CSV_DIR)  # 计算绝对路径
print(CSV_DIR)

TOTAL_BEFAORE = count_lines_csv(CSV_DIR)

update_image_fields(CSV_DIR)
update_image_fields_extension(CSV_DIR, extension="webp")
remove_items_without_img(CSV_DIR, img_dir=IMG_DIR, backup_dir="backup_csvs")


TOTAL_AFTER = count_lines_csv(CSV_DIR)
print(f"处理后剩余{TOTAL_AFTER}条数据,减少了{TOTAL_BEFAORE-TOTAL_AFTER}条数据")
