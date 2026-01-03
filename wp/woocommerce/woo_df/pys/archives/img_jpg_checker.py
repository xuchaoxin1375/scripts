"""图片检查(jpg破图检查)"""

import os
from collections import Counter
import shutil
import numpy as np
from PIL import Image
from tqdm import tqdm

# 设置目标目录
IMG_DIR = r"C:/sharetemp/Checker"  # 请替换为你的图片目录

# 过滤条件：文件大小不超过 MAX_SIZE KB
MAX_SIZE = 60

# 图片文件扩展名
image_extensions = [".jpg", ".jpeg"]

# 列出大小不超过 110 KB 的图片文件
filtered_files = []

# 移除这些文件的列表
remove_files = []

# 第一步：遍历目录，检查文件大小
for root, _, files in os.walk(IMG_DIR):
    for file in files:
        # 获取文件的完整路径
        file_path = os.path.join(root, file)

        # 检查文件扩展名是否为图片格式
        if any(file.lower().endswith(ext) for ext in image_extensions):
            # 获取文件大小（单位：字节）
            file_size = os.path.getsize(file_path)

            # 转换为 KB
            file_size_kb = file_size / 1024

            # 如果文件大小不超过 110 KB
            if file_size_kb <= MAX_SIZE:
                filtered_files.append(file_path)

# 第二步：对符合条件的文件检查图片内容是否符合废图特征
total_files = len(filtered_files)
print(f"开始处理 {total_files} 张图片...")

# 创建 checking 目录（如果不存在）
checking_dir = os.path.join(IMG_DIR, "checking")
os.makedirs(checking_dir, exist_ok=True)

for idx, file_path in enumerate(tqdm(filtered_files, desc="处理进度")):
    try:
        # 加载图片
        with Image.open(file_path) as img:
            # 将图片转换为 RGB 模式（确保颜色信息完整）
            img_rgb = img.convert("RGB")
            pixels = np.array(img_rgb)

            # 获取图片高度
            height = img.height

            # 将图片分成上下两部分
            upper_half = pixels[: height // 2, :, :]
            lower_half = pixels[height // 2 :, :, :]

            # 检查下半部分是否为纯色
            lower_colors = lower_half.reshape(-1, 3)
            lower_colors_tuple = [tuple(color) for color in lower_colors]
            lower_color_counts = Counter(lower_colors_tuple)

            if len(lower_color_counts) <= 1:
                print(f"\n✅ 图片 {file_path} 的下半部分是纯色。")

                upper_colors = upper_half.reshape(-1, 3)
                upper_colors_tuple = [tuple(color) for color in upper_colors]
                upper_color_counts = Counter(upper_colors_tuple)

                if len(upper_color_counts) > 1:
                    print(
                        f"✅ 图片 {file_path} 的上半部分不是纯色，判定为废图。正在移动到 checking 目录..."
                    )
                    new_file_path = os.path.join(
                        checking_dir, os.path.basename(file_path)
                    )
                    shutil.move(file_path, new_file_path)
                    print(f"✅ 已移动文件: {file_path} -> {new_file_path}")
    except Exception as e:
        print(f"\n⚠️ 图片 {file_path} 加载失败，可能是损坏的图片: {str(e)}")
        print("✅ 正在移动损坏的图片到 checking 目录...")
        new_file_path = os.path.join(checking_dir, os.path.basename(file_path))
        shutil.move(file_path, new_file_path)
        print(f"✅ 已移动损坏图片: {file_path} -> {new_file_path}")
