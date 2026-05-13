from scrapling.fetchers import StealthySession
from comutils
urls = [
    "https://www.lascoautoparts.com/oem-parts/ford-oil-filter-4h2z6731aa",
    "https://www.lascoautoparts.com/oem-parts/ford-air-filter-pr3z9601b",
    "https://www.lascoautoparts.com/oem-parts/ford-motorcraft-air-filter-indicator-fa1892",
]

# 使用 session 模式，浏览器和 cookie 会被复用
with StealthySession(solve_cloudflare=True, headless=False) as session:
    for url in urls:
        # 第一次请求可能会触发 CF 验证
        # 第二次及以后的请求会携带第一次获取的 Cookie，通常能秒过
        page = session.fetch(url)
        print(f"URL: {url}, Title: {page.css('title::text').get()}")
