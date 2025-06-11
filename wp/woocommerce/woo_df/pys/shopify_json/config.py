# 配置区域 - 直接在这里修改路径和设置
# ===================================================
# Excel文件路径 - 包含网站URL和保存路径的Excel文件

WP_SITES = r"C:/sites/wp_sites/shopify.com"
JSON_PATH = rf"{WP_SITES}/json"
EXCEL_FILE_PATH = rf"{WP_SITES}/domains.xlsx"

# 默认保存路径 - 当Excel中没有指定保存路径时使用
DEFAULT_SAVE_PATH = JSON_PATH

# 文件列表保存路径 - 所有文件列表TXT文件的保存目录
FILES_LIST_PATH = JSON_PATH

# 状态文件目录 - 每个站点一个status文件
STATUS_DIR = rf"{JSON_PATH}/status"


# 线程设置
URL_THREADS = 1  # URL采集线程数
DOWNLOAD_THREADS = 30  # JSON下载线程数

# 日志级别设置
# 0: 只显示错误和关键信息
# 1: 显示基本进度信息（默认）
# 2: 显示详细进度和调试信息
LOG_LEVEL = 1
