# scrapling_xml_cookie.py
from scrapling.fetchers import StealthySession
from playwright.sync_api import Page
import time

BASE_URL = "https://www.lavoroamaglia.it/"
XML_URL  = "https://www.lavoroamaglia.it/product-sitemap1.xml"
proxy    = "http://localhost:8800"

def wait_idle(page: Page) -> Page:
    try:
        page.wait_for_load_state("networkidle", timeout=30_000)
    except Exception:
        pass
    time.sleep(3)
    return page

with StealthySession(
    solve_cloudflare=True,
    headless=False,
    proxy=proxy,
) as session:

    # ① 先访问主站触发并通过 Cloudflare 验证
    print("正在通过 Cloudflare 验证（访问主站）…")
    session.fetch(
        BASE_URL,
        network_idle=True,
        page_action=wait_idle,
        timeout=60_000,
    )
    print("✅ 主站验证完成，cf_clearance 已缓存")

    # ② 用同一 session（携带 cookie）请求 XML
    print("正在请求 XML…")
    xml_page = session.fetch(
        XML_URL,
        network_idle=True,
        page_action=wait_idle,
        timeout=60_000,
        solve_cloudflare=False,  # cookie 已有，不需要再次解题
    )

    print(f"状态码: {xml_page.status}")
    with open("product-sitemap1.xml", "w", encoding="utf-8") as f:
        f.write(xml_page.html_content)
    print("✅ 已保存到 product-sitemap1.xml")