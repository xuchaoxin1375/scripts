import os
import requests
import json

# --- 配置 ---
# 优先从环境变量读取，如果环境变量不存在，则使用下面的默认值
# 建议将敏感信息存储在环境变量中
CLOUDFLARE_API_TOKEN = os.environ.get("CF_API_TOKEN_DNS_EDIT")
# 或者使用 API Key 和 Email (如果使用 API Token，请将下面两行注释掉或留空)
CLOUDFLARE_API_KEY = os.environ.get("CLOUDFLARE_API_KEY")
CLOUDFLARE_EMAIL = os.environ.get("CLOUDFLARE_EMAIL")

DOMAIN_NAME = "modernmufflershop.com"  # <-- 将这里替换为您的域名

# Cloudflare API 端点
API_BASE_URL = "https://api.cloudflare.com/client/v4"

def get_zone_id(domain_name, headers):
    """获取指定域名的 Zone ID"""
    url = f"{API_BASE_URL}/zones"
    params = {"name": domain_name}
    try:
        response = requests.get(url, headers=headers, params=params)
        response.raise_for_status()  # 如果请求失败则抛出 HTTPError 错误
        data = response.json()
        if data["result"] and len(data["result"]) > 0:
            return data["result"][0]["id"]
        else:
            print(f"错误：找不到域名 {domain_name} 的 Zone ID。")
            return None
    except requests.exceptions.RequestException as e:
        print(f"请求 Zone ID 时发生错误: {e}")
        if response is not None:
            print(f"响应内容: {response.text}")
        return None
    except json.JSONDecodeError:
        print(f"解析 Zone ID 响应时发生错误。响应内容: {response.text}")
        return None

def set_ssl_flexible(zone_id, headers):
    """将指定 Zone ID 的 SSL/TLS 模式设置为 flexible"""
    url = f"{API_BASE_URL}/zones/{zone_id}/settings/ssl"
    payload = {"value": "flexible"}
    try:
        response = requests.patch(url, headers=headers, json=payload)
        response.raise_for_status()
        data = response.json()
        if data.get("success"):
            print(f"成功将域名 (Zone ID: {zone_id}) 的 SSL/TLS 模式设置为 'flexible'。")
            return True
        else:
            print(f"设置 SSL/TLS 模式失败。响应: {data.get('errors') or data.get('messages')}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"设置 SSL/TLS 模式时发生错误: {e}")
        if response is not None:
            print(f"响应内容: {response.text}")
        return False
    except json.JSONDecodeError:
        print(f"解析设置 SSL/TLS 响应时发生错误。响应内容: {response.text}")
        return False

def main():
    """主函数"""
    headers = {}
    auth_method_used = ""

    if CLOUDFLARE_API_TOKEN:
        headers["Authorization"] = f"Bearer {CLOUDFLARE_API_TOKEN}"
        auth_method_used = "API Token"
    # elif CLOUDFLARE_API_KEY and CLOUDFLARE_EMAIL: # 取消注释以启用 API Key/Email 认证
    #     headers["X-Auth-Email"] = CLOUDFLARE_EMAIL
    #     headers["X-Auth-Key"] = CLOUDFLARE_API_KEY
    #     auth_method_used = "API Key and Email"
    else:
        print("错误：请设置 CLOUDFLARE_API_TOKEN 或 CLOUDFLARE_API_KEY 和 CLOUDFLARE_EMAIL 环境变量或在脚本中直接配置。")
        print("建议使用 API Token。")
        return

    if DOMAIN_NAME == "your-domain.com":
        print("错误：请在脚本中将 DOMAIN_NAME 替换为您的实际域名。")
        return

    print(f"正在使用 {auth_method_used} 进行认证...")
    print(f"目标域名: {DOMAIN_NAME}")

    zone_id = get_zone_id(DOMAIN_NAME, headers)

    if zone_id:
        print(f"获取到 Zone ID: {zone_id}")
        set_ssl_flexible(zone_id, headers)

if __name__ == "__main__":
    main()