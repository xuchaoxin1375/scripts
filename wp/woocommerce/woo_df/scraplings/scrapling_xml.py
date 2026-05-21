import os
from scrapling.fetchers import StealthySession

url = "https://www.lavoroamaglia.it/product-sitemap1.xml"

# Try with StealthySession
with StealthySession(solve_cloudflare=True, headless=True) as session:
    try:
        print("Fetching sitemap...")
        page = session.fetch(url)
        print(f"Status Code: {page.status_code}")
        print("Response structure:")
        print(f"Type of page: {type(page)}")
        print("Attributes/Methods of page:")
        print(dir(page))
        print("First 500 chars of body:")
        print(page.text[:500] if hasattr(page, 'text') else page.body[:500])
    except Exception as e:
        print(f"Exception: {e}")
