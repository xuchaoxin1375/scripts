# 或者获取当前脚本所在目录,配置文件位于同一个目录
import os

# 或者获取当前脚本所在目录,配置文件位于同一个目录
script_path = os.path.abspath(__file__)
script_dir = os.path.dirname(script_path)
CONFIG=os.path.join(script_dir,"image_downloader.json")

print(script_path)
print(f"{CONFIG=}")
