# scrapling stealthy 模式下载图片,相关文档:https://scrapling.readthedocs.io/
import os
from scrapling.fetchers import StealthySession
SOLVE_CLOUDFLARE = True
HEADLESS = False
proxy="http://localhost:7897"
image_urls = [
    "https://www.gosupps.com/media/catalog/product/cache/25/image/9df78eab33525d08d6e5fb8d27136e95/6/1/61Mfc8jVlQL.jpg",
    "https://www.gosupps.com/media/catalog/product/cache/25/image/9df78eab33525d08d6e5fb8d27136e95/5/1/51Em4E1TwPL.jpg",
    # ... 其他图片URL ...
    # "https://www.velogear.com.au/media/catalog/product/cache/94ef66d09f7a7e8c63df55350acf28cd/m/a/maxxis_flyweight_26_tube_fv.jpg",
]
# 单个测试用例:
url = "https://www.gosupps.com/media/catalog/product/cache/25/image/9df78eab33525d08d6e5fb8d27136e95/6/1/61Mfc8jVlQL.jpg"


# 初始化一个隐匿会话
# 它默认开启了底层最高级别的防检测，并模拟真实浏览器环境
with StealthySession(solve_cloudflare=SOLVE_CLOUDFLARE, headless=HEADLESS,proxy=proxy) as session:
    try:
        # 复用会话请求图片
        page = session.fetch(url)
        filename = f"image_{os.path.basename(url)}"
        with open(filename, "wb") as f:
            f.write(page.body)
        print(f"成功保存: {filename}")

    except Exception as e:
        print(f"下载请求发生异常: {e}")
