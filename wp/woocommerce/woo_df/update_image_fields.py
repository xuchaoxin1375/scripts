"""更新CSV文件中的图片字段(调整和补全字段:Images,ImagesUrl)"""

import os
import pandas as pd
from woosqlitedb import update_image_fields, update_image_fields_extension
from wooenums import ImageMode, CSVProductFields, DBProductFields, LanguagesHotSale

IMAGE = CSVProductFields.IMAGES.value

CSV_DIR = r"S:/grandwagonsupply/"  # 修改csv文件所在目录
CSV_DIR = os.path.abspath(CSV_DIR)
# print(CSV_DIR)
update_image_fields(CSV_DIR)
update_image_fields_extension(CSV_DIR, extension="webp")
