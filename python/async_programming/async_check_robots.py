import asyncio
import httpx
import time

# 定义robots.txt 检查协程函数
async def check_robots_txt(client, site_url):
    """
    检查单个网站的 robots.txt 是否存在
    """
    # 确保 URL 格式正确
    base_url = site_url.rstrip('/')
    robots_url = f"{base_url}/robots.txt"
    
    try:
        # 使用 head 请求可以节省流量，只获取响应头
        # 使用await挂起网络IO耗时任务
        response = await client.get(robots_url, timeout=5.0, follow_redirects=True)
        
        if response.status_code == 200:
            print(f"[✓] 存在: {robots_url} (Status: {response.status_code})")
            return (site_url, True)
        else:
            print(f"[X] 不存在: {robots_url} (Status: {response.status_code})")
            return (site_url, False)
            
    except Exception as e:
        print(f"[!] 错误: {robots_url} - {str(e)}")
        return (site_url, None)

async def main():
    websites = [
        "https://www.baidu.com",
        "https://www.gitee.com",
        "https://www.python.org",
        "https://github.com",
        "https://www.example.invalid" # 模拟错误地址
    ]

    print(f"开始检查 {len(websites)} 个网站...\n")
    start_time = time.perf_counter()

    # 使用 Limits 控制并发频率，防止被目标服务器封禁
    limits = httpx.Limits(max_connections=10, max_keepalive_connections=5)
    
    async with httpx.AsyncClient(limits=limits, verify=False) as client:
        tasks = [check_robots_txt(client, url) for url in websites]
        # 并发执行所有检查任务
        results = await asyncio.gather(*tasks)

    end_time = time.perf_counter()
    
    print(f"\n检查完成，耗时: {end_time - start_time:.2f}s")
    
    # 统计结果
    exists_count = sum(1 for r in results if r[1] is True)
    print(f"统计：{exists_count} 个存在，{len(websites) - exists_count} 个失败或不存在。")

if __name__ == "__main__":
    asyncio.run(main())