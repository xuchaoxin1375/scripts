from scrapling import StealthyFetcher, Fetcher
import json

url_home = "https://www.lavoroamaglia.it/"
url_sitemap = "https://www.lavoroamaglia.it/product-sitemap1.xml"
proxy = "http://localhost:7897"

print("1. Fetching homepage to solve Cloudflare Turnstile...")
page = StealthyFetcher.fetch(url_home, solve_cloudflare=True, headless=True, proxy=proxy)
print(f"Homepage fetch status: {page.status}")

# Extracted cookies
cookies_list = page.cookies
cookie_dict = {c['name']: c['value'] for c in cookies_list}
print(f"Extracted cookies keys: {list(cookie_dict.keys())}")

# Extracted headers
headers = page.request_headers
print(f"Using User-Agent: {headers.get('user-agent')}")

print("\n2. Fetching sitemap XML via Fetcher.get with solved cookies...")
# Let's request the sitemap using Fetcher.get
sitemap_res = Fetcher.get(
    url_sitemap,
    headers=headers,
    cookies=cookie_dict,
    proxy=proxy
)

print(f"Sitemap fetch status: {sitemap_res.status}")
print(f"Sitemap content type: {sitemap_res.headers.get('content-type')}")
print(f"Sitemap response body length: {len(sitemap_res.body)}")
print("First 500 characters of sitemap content:")
print(sitemap_res.text[:500])
