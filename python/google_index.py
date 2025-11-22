
import requests
from bs4 import BeautifulSoup

def get_google_index_count(domain):
    query = f"site:{domain}"
    google_url = f"https://www.google.com/search?q={query}"
    headers = {"User-Agent": "Mozilla/5.0"}

    response = requests.get(google_url, headers=headers)
    soup = BeautifulSoup(response.text, "html.parser")

    result_stats = soup.find("div", {"id": "result-stats"})
    if result_stats:
        return result_stats.text
    return "未找到结果"


domains = ["autotoros.com", "iberiangear.com", "mecanicatop.com"]
for domain in domains:
    print(f"{domain} 收录数量: {get_google_index_count(domain)}")
