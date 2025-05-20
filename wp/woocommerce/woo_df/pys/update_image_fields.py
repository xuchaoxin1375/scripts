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
CSV_DIR = r"S:/grandwagonsupply/"  # 修改csv文件所在目录
CSV_DIR = os.path.abspath(CSV_DIR)
# print(CSV_DIR)
update_image_fields(CSV_DIR)
update_image_fields_extension(CSV_DIR, extension="webp")
remove_items_without_img(CSV_DIR, img_dir=IMG_DIR, backup_dir="backup_csvs")
