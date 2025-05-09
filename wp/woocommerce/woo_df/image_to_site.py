"""批量地将图片移动或复制到指定的目录中
比如从csv文件中读取图片字段(比如图片名字),然后将指定目录中的图片遍历,命中的图片被移动或复制到指定目录中
目标目录通常是网站存放图片的目录(如果指定的目录不存在,会发出警告并尝试创建)

对于没有后缀的图片,会尝试类型推断并添加后缀
"""

import csv
import os
from comutils import get_user_choice_csv_fields
from wooenums import CSVProductFields

img_field=CSVProductFields.IMAGES.value

def image_to_site(csv_file ,source_dir, target_dir,field=None):
    """
    读取csv文件(带有图片字段,比如图片名字或路径),根据此字段将指定目录中的这些图片移动或复制到目标目录中

    """
    with open(csv_file, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            image_name = row[img_field]
            if not image_name:
                continue
            if field:
                image_name = row[field]
            # if not image_name.startswith("http"):
            #     image_path = source_dir + "/" + image_name
            #     if not os.path.exists(image_path):
            #         print(f"图片{image_path}不存在")
            #         continue
            #     target_path = target_dir + "/" + image_name
            #     if not os.path.exists(target_dir):
            #         os.makedirs(target_dir)
            #     if os.path.exists(target_path):
            #         print(f"图片{target_path}已存在,跳过")
            #         continue
            #     if "." not in image_name:
            #         # 尝试推断图片类型并添加后缀
            #         ext = imghdr.what(image_path)
            #         if ext:
            #             target_path += "." + ext
            #     shutil.copy(image_path, target_path)
