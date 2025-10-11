"""

请先准备好shopify网址列表
"""

# 配置区域 - 直接在这里修改路径和设置
# ===================================================
# Excel文件路径 - 包含shopify的网站URL和保存路径的Excel文件
LOCAL_DOMAIN = r"wp.test"
WP_SITES_DIR = rf"C:/sites/wp_sites/{LOCAL_DOMAIN}"
JSON_DIR = rf"{WP_SITES_DIR}/json"
# 域名文件路径 - 包含所有shopify域名的Excel文件
SPIDER_TASKS = r"C:\Users\Administrator\Desktop\spider_tasks"
# EXCEL_FILE_PATH = rf"{WP_SITES_DIR}/domains_shopify.xlsx"
EXCEL_FILE_PATH = rf"{SPIDER_TASKS}/domains.xlsx"

# 默认保存路径 - 当Excel中没有指定保存路径时使用
DEFAULT_SAVE_PATH = JSON_DIR

# 文件列表保存路径 - 所有文件列表TXT文件的保存目录
FILES_LIST_PATH = JSON_DIR

# 状态文件目录 - 每个站点一个status文件
STATUS_DIR = rf"{JSON_DIR}/status"


# 线程设置
URL_THREADS = 1  # URL采集线程数
DOWNLOAD_THREADS = 30  # JSON下载线程数

# 日志级别设置
# 0: 只显示错误和关键信息
# 1: 显示基本进度信息（默认）
# 2: 显示详细进度和调试信息
LOG_LEVEL = 1
# 默认正则表达式设置
DEFAULT_INCLUDE_REGEX = r'\.[a-z]{2,}\/sitemap_products_'  # 默认包含的正则表达式
DEFAULT_EXCLUDE_REGEX = r'\.[a-z]{2,}\/[a-z\-]{2,}\/sitemap_products_'  # 默认排除的正则表达式