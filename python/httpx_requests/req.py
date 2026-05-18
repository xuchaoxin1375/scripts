## 
import httpx
# 两个库用法相同
params = {"q": "python", "page": 2}
resp = httpx.get("https://example.com/search", params=params)
# 检查最终访问链接:
url=resp.url
##
resp.status_code          # 200
resp.headers              # 响应头（不区分大小写的字典）
resp.headers["content-type"]
resp.text                 # 文本内容（自动解码）
resp.content              # 原始字节
resp.json()              # 解析为 Python 对象
resp.encoding            # 检测到的编码
resp.url                 # 最终 URL（可能经过重定向）
resp.elapsed             # 请求耗时（timedelta）