import os
import random
import sys
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor, as_completed

import pandas as pd
import requests
from cloudflare import Cloudflare
from dotenv import load_dotenv

load_dotenv()

CLOUDFLARE_EMAIL = os.environ.get("CLOUDFLARE_EMAIL")
CLOUDFLARE_API_KEY = os.environ.get("CLOUDFLARE_API_KEY")
DEFAULT_FORWARD_EMAIL = os.environ.get("DEFAULT_FORWARD_EMAIL")

DESKTOP = r"C:/Users/Administrator/Desktop"
DOMAINS_FILE = f"{DESKTOP}/cf_domains.csv"  # 域名和IP配置文件，格式: 域名,IP
SITE_TAGS_FILENAME = "cf_site_tags.txt"


THREADS = 5  # 并发线程数
API_TIMEOUT = 30  # API 请求超时时间（秒）


# 全局统计变量
processed_count = 0
success_count = 0
lock = threading.Lock()


def load_domains_from_table(filename):
    """从Excel文件加载域名、IP、邮箱前缀和转发邮件地址"""
    domains_info = []
    try:
        # df = pd.read_excel(filename, keep_default_na=False)
        df = pd.read_csv(filename, keep_default_na=False)
        for _, row in df.iterrows():
            domain = row.get("domain").strip()

            # 检查域名和IP是否为空
            if domain:
                domains_info.append(row)

    except Exception as e:
        print(f"Error reading domains table file: {str(e)}")
        sys.exit(1)

    return domains_info


def log(message):
    """线程安全的日志记录"""
    with lock:
        print(f"[{threading.current_thread().name}] {message}")


def get_or_create_zone(domain):
    """获取或创建Zone"""
    try:
        # 检查Zone是否存在
        zones = client.zones.list(name=domain, timeout=API_TIMEOUT)
        if zones.result:
            # log(f"get zone for {domain}")
            return zones.result[0]

        # 创建新Zone
        # log(f"Creating new zone for {domain}")
        zone = client.zones.create(
            name=domain, account={"id": ACCOUNT_ID}, type="full", timeout=API_TIMEOUT
        )

        # 等待Zone激活
        max_retries = 5
        for _ in range(max_retries):
            try:
                zone_status = client.zones.get(zone_id=zone.id, timeout=API_TIMEOUT)
                if zone_status.status == "active":
                    return zone
                time.sleep(3)
            except Exception as e:
                log(f"Error checking zone status for {domain}: {str(e)}")
                time.sleep(3)

        log(f"Zone {domain} did not activate in time")
        return None

    except Exception as e:
        log(f"Error in get_or_create_zone for {domain}: {str(e)}")
        return None


def deal_ip(zone_id, domain, ip_address):
    log(f"设置域名{domain},IP:{ip_address}")
    records_to_create = [
        {"type": "A", "name": "@", "content": ip_address, "proxied": True},
        {"type": "A", "name": "www", "content": ip_address, "proxied": True},
    ]

    # 先获取现有记录
    try:
        existing_records = client.dns.records.list(zone_id=zone_id, timeout=API_TIMEOUT)
        existing_map = {(r.name, r.type): r.id for r in existing_records.result}
    except Exception as e:
        log(f"Failed to fetch existing DNS records for {domain}: {str(e)}")
        return False

    # 准备批量操作
    deletes = []
    patches = []
    posts = []
    puts = []
    # print("existing_map",existing_map)
    for record in records_to_create:
        record_name = record["name"] + "." + domain
        record_name = record_name.replace("@.", "")
        record_key = (record_name, record["type"])

        if record_key in existing_map:
            # 记录存在，准备更新
            # print("exist",record_key,record)
            puts.append(
                {
                    "id": existing_map[record_key],
                    "type": record["type"],
                    "name": record["name"],
                    "content": record["content"],
                    "proxied": record["proxied"],
                }
            )
        else:
            print("pass", record_key, record)
            # 记录不存在，准备创建
            posts.append(
                {
                    "type": record["type"],
                    "name": record["name"],
                    "content": record["content"],
                    "proxied": record["proxied"],
                }
            )

    # 执行批量操作
    if deletes or patches or posts or puts:
        try:
            result = client.dns.records.batch(
                zone_id=zone_id,
                deletes=deletes,
                patches=patches,
                posts=posts,
                puts=puts,
                timeout=API_TIMEOUT,
            )

            # 检查批量操作是否成功
            if hasattr(result, "errors") and result.errors:
                log(f"Failed to update DNS records for {domain}: {result.errors}")
                return False
            else:
                log(f"Successfully updated DNS records for {domain}")
        except Exception as e:
            log(f"Error during batch operation for {domain}: {str(e)}")
            return False

    return True


def deal_ssl(zone_id, domain, ssl_type):
    log(f"设置SSL{domain}:{ssl_type}")

    allowed_ssl_values = ["strict", "full", "flexible", "off"]

    if ssl_type not in allowed_ssl_values:
        log(
            f"错误的SSL类型 '{ssl_type}'. 必须是这几个值之一: {', '.join(allowed_ssl_values)}"
        )
        return False

    response = client.zones.settings.edit(
        setting_id="ssl",
        # id="ssl",
        value=ssl_type,
        zone_id=zone_id,
    )
    if response.value == ssl_type:
        return True

    return False


def deal_forward(zone_id, domain, forward_email):
    log(f"设置{domain}转发邮箱:{forward_email}")

    try:
        # 启用Email Routing

        result = client.email_routing.get(zone_id=zone_id)
        # print("1result", result)
        if hasattr(result, "errors") and result.errors:
            batchadd = []
            print("Error getting email routing settings:", result.errors)
            for error in result.errors:
                # print(error)
                if error["code"] in ["mx.missing", "spf.missing", "dkim.missing"]:
                    batchadd.append(error["missing"])
            # sys.exit(1)
            # print("batchadd", batchadd)

            result2 = client.dns.records.batch(
                zone_id=zone_id, posts=batchadd, timeout=API_TIMEOUT
            )
            print("result2", result2)
            time.sleep(3)

        catch_all = client.email_routing.rules.catch_alls.update(
            zone_id=zone_id,
            actions=[{"type": "forward", "value": [forward_email]}],
            matchers=[{"type": "all"}],
            enabled=True,
            name=f"catch-all-{domain}-" + str(random.randint(1000000, 9999999)),
        )
        # print(catch_all)
        if catch_all.enabled != True:
            return False

        result = client.email_routing.get(zone_id=zone_id)
        # print("1result", result)
        if hasattr(result, "enabled") and result.enabled == False:

            url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/email/routing/enable"

            # print(url)
            data = {}
            response = requests.post(url, headers=curl_headers, data=data)
            result = response.json()
            # print(result['result'])
            # print("Email Routing enabled successfully:", )

            # print("result3", result3)

        # print("Email Routing enabled successfully:", result)
    except Exception as e:
        # print("xxxxxx")
        traceback.print_exc()
        print("Error enabling Email Routing:", e)
        return False

    return True


def deal_domain_security(zone_id, domain):
    log(f"初始化域名安全{domain}状态...")

    site_tag = existing_domains.get(domain, "")
    if site_tag == "":
        site_info_create = client.rum.site_info.create(
            account_id=ACCOUNT_ID, zone_tag=zone_id
        )
        site_tag = site_info_create.site_tag

    site_info_udpate = client.rum.site_info.update(
        account_id=ACCOUNT_ID,
        site_id=site_tag,
        auto_install=True,
        enabled=True,
    )

    if site_info_udpate.auto_install != True:
        print("site_info_udpate", site_info_udpate)
        return False

    settings = ["speed_brain", "0rtt", "always_use_https", "early_hints"]

    success_count = 0
    for setting in settings:
        response = client.zones.settings.edit(
            setting_id=setting,
            value="on",
            zone_id=zone_id,
        )
        if response.value == "on":
            success_count += 1

    if success_count != len(settings):
        return False

    return True


def deal_addresses(domains):
    pass
    forward_emails = [
        domain.get("forward", "").strip().lower()
        for domain in domains
        if isinstance(domain, str)
    ]
    remote_results = client.email_routing.addresses.list(account_id=ACCOUNT_ID).result
    existing_addresses = [
        item.email.strip().lower() for item in remote_results if item.verified
    ]

    # [address for address in remote_result if address.status=="active"]
    # print(remote_results)
    # sys.exit(2)
    # existing_addresses = [address.email for address in existing_addresses]
    result = []
    for email in forward_emails:
        if email not in existing_addresses:
            print("创建邮件地址", email)
            result.append(email)
            client.email_routing.addresses.create(account_id=ACCOUNT_ID, email=email)
    return result

    # address = client.email_routing.addresses.create(
    #     account_id="dbfbadccc57e8c396315b50e449b5d91",
    #     email="r9164521@gmail.com",
    # )
    # print(address.id)

    # page = client.email_routing.addresses.list(
    #     account_id="dbfbadccc57e8c396315b50e449b5d91",
    # )
    # print(page)
    # page = page.result[0]
    # print(page.id)


def process_domain(info):
    """处理单个域名 功能配置开关"""
    global processed_count, success_count

    try:
        domain = info.get("domain").strip().lower()
        ip = info.get("ip").strip()
        ssl = info.get("ssl").strip().lower()
        forward = info.get("forward").strip().lower() or DEFAULT_FORWARD_EMAIL
        need_security = info.get("security") or 1
        log(f"Processing {domain}....")

        with lock:
            processed_count += 1

        # 1. 检查或创建Zone
        zone = get_or_create_zone(domain)
        if not zone:
            log(f"Failed to get or create zone for {domain}")
            return False

        zone_id = zone.id

        # 2. 批量处理DNS记录
        # if ip:
        #     # pass
        #     deal_ip(zone_id, domain, ip)

        # # 3. 设置SSL证书(加密模式改为灵活,早期的模板可能有问题,要慎用)
        # if ssl:
        #     deal_ssl(zone_id, domain, ssl)
        #     pass

        # 4. 设置转发邮件地址
        if forward:
            deal_forward(zone_id, domain, forward)
        # 5. 设置初始状态🎈
        if need_security == 1:
            deal_domain_security(zone_id, domain)

        return True

    except Exception as e:
        # print(traceback.format_exc())
        traceback.print_exc()
        log(f"Error processing {domain}: {str(e)}")
        return False


def get_account_id():
    """获取账户ID"""
    accounts = client.accounts.list(timeout=API_TIMEOUT)
    if not accounts.result:
        log("No Cloudflare accounts found")
        return None

    account_id = accounts.result[0].id
    return account_id


def get_existing_domains():
    """获取已存在的域名和站点标签"""
    existing_domains = dict()

    with open(SITE_TAGS_FILENAME, "a+") as file:
        file.seek(0)  # 将指针移动到文件开头以便读取内容
        # content = file.read()
        # print(content)

        for line in file.readlines():
            data = line.strip().split("|")
            if len(data) != 2:
                continue

            existing_domains[data[0]] = data[1]

    pagenum = 0
    while 1:
        pagenum += 1
        # print(pagenum, "="*10)

        site_info_list = client.rum.site_info.list(
            account_id=ACCOUNT_ID,
            page=pagenum,
            # per_page=2
        )
        if site_info_list.result:
            # result = site_info_list.result[0]
            for result in site_info_list.result:
                zone_name = result.ruleset.zone_name
                site_tag = result.site_tag

                if zone_name not in existing_domains:
                    with open(SITE_TAGS_FILENAME, "a+") as file:
                        with lock:
                            file.write(f"{zone_name}|{site_tag}\n")
                    print("*" * 10, zone_name, site_tag)
                    existing_domains[zone_name] = site_tag

        else:
            break

    return existing_domains


if __name__ == "__main__":

    client = Cloudflare(
        api_email=CLOUDFLARE_EMAIL,
        api_key=CLOUDFLARE_API_KEY,
    )

    curl_headers = {
        "Content-Type": "application/json",
        "X-Auth-Email": CLOUDFLARE_EMAIL,
        "X-Auth-Key": CLOUDFLARE_API_KEY,
    }

    ACCOUNT_ID = get_account_id()

    # 加载域名列表
    domains = load_domains_from_table(DOMAINS_FILE)
    if not domains:
        print("No domains found in the input file")
        sys.exit(1)

    print(f"待处理域名 {len(domains)} 个")

    address_result = deal_addresses(domains)
    if len(address_result) > 0:
        print("待激活邮件:", address_result)
        sys.exit(1)

    existing_domains = get_existing_domains()

    # 使用 ThreadPoolExecutor 执行多线程
    with ThreadPoolExecutor(max_workers=THREADS) as executor:
        futures = [executor.submit(process_domain, record) for record in domains]

        for future in as_completed(futures):
            try:
                result = future.result()
                if result:
                    success_count += 1

            except Exception as e:
                log(f"Error in future: {str(e)}")

    # 输出统计信息
    print("\nProcessing complete!")
    print(f"Total domains processed: {processed_count}")
    print(f"Successfully processed: {success_count}")
    print(f"Failed: {processed_count - success_count}")
