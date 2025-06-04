"""更新CSV文件中的图片字段(调整和补全字段:Images,ImagesUrl)"""

# import pandas as pd
from woosqlitedb import process_image_csv


IMG_DIR = r"      ".strip()  # 修改图片文件所在目录
CSV_DIR = r"      ".strip()  # 修改csv文件所在目录


if __name__ == "__main__":
    process_image_csv(IMG_DIR, CSV_DIR)
