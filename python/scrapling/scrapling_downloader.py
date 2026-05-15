import os
from scrapling.fetchers import StealthySession

SOLVE_CLOUDFLARE = True
image_urls = [
    "https://www.velogear.com.au/media/catalog/product/cache/94ef66d09f7a7e8c63df55350acf28cd/m/a/maxxis_flyweight_26_tube_fv.jpg",
    # ... 其他图片URL ...
]

# 初始化一个隐匿会话
# 它默认开启了底层最高级别的防检测，并模拟真实浏览器环境
with StealthySession(solve_cloudflare=SOLVE_CLOUDFLARE) as session:
    # 你可以为整个会话定制基础 Headers（比如防盗链的 Referer）

    for i, url in enumerate(image_urls):
        try:
            # 复用会话请求图片
            page = session.fetch(url)

            if page.status == 200:
                filename = f"image_{i}_{os.path.basename(url)}"
                with open(filename, "wb") as f:
                    f.write(page.body)
                print(f"成功保存: {filename}")
            else:
                print(f"下载失败 {url}, 状态码: {page.status}")

        except Exception as e:
            print(f"请求发生异常: {e}")
