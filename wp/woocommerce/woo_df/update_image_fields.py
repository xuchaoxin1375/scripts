""" 更新CSV文件中的图片字段(调整和补全字段:Images,ImagesUrl) """
from woosqlitedb import update_image_fields

CSV_DIR = r"./"  # 修改csv文件所在目录
update_image_fields(CSV_DIR)
