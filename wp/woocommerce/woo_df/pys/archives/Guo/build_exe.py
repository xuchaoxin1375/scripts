import os
import PyInstaller.__main__

# 确保当前目录是脚本所在目录
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# 定义PyInstaller参数
pyinstaller_args = [
    'woocommerce_importer_gui.py',  # 主脚本
    '--name=WooCommerceImporter',   # 生成的EXE名称
    '--onefile',                    # 生成单个EXE文件
    '--windowed',                   # 不显示控制台窗口
    '--clean',                      # 清理临时文件
    '--add-data=csvinserttowoocommercebak3.py;.',  # 添加依赖文件
    '--add-data=mysql_connection_manager.py;.',    # 添加连接管理器
    # 确保包含所有必要的库
    '--hidden-import=PIL',
    '--hidden-import=PIL._imagingtk',
    '--hidden-import=PIL._tkinter_finder',
    '--hidden-import=phpserialize',
    '--hidden-import=pymysql.constants',
    '--hidden-import=pymysql.converters',
    '--hidden-import=pymysql.charset',
    '--hidden-import=threading',
    '--hidden-import=queue',
]

# 运行PyInstaller
PyInstaller.__main__.run(pyinstaller_args)

print("打包完成！EXE文件位于 dist 目录中。")