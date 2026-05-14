import os
from scrapling.fetchers import StealthySession

# 定义一个本地文件夹路径用于存放浏览器数据
# 这样即便 Python 程序结束，下次运行依然能读取到之前的验证状态
my_browser_data = os.path.abspath("C:/temp/my_scraping_profile")

# 测试链接(至少2条)
# url = "https://www.lascoautoparts.com/oem-parts/ford-oil-filter-4h2z6731aa"
# url = "https://www.lascoautoparts.com/oem-parts/ford-air-filter-pr3z9601b"
url="https://www.lascoautoparts.com/oem-parts/ford-motorcraft-air-filter-indicator-fa1892"
with StealthySession(
    solve_cloudflare=True,
    headless=False,
    user_data_dir=my_browser_data,  # 关键参数：持久化存储路径
) as session:
    page = session.fetch(url)
    # ... 处理逻辑 ...
    print(page.status)
    print(f"Title:{page.css('title::text').get()}")
