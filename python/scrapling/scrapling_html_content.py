from scrapling.fetchers import StealthySession

url = "https://wiki.python.org/python/BeginnersGuide.html"
url = "https://www.boatid.com/t-h-marine/48-l-snap-flex-all-round-stern-pole-led-light-mpn-led-navsfsl-48-dp.html"

proxy="http://localhost:7897"
# 使用 session 模式，浏览器和 cookie 会被复用
with StealthySession(solve_cloudflare=True, headless=False,proxy=proxy) as session:
    page = session.fetch(url)
    print(page.html_content)
