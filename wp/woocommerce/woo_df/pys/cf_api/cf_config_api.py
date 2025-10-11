"""cf 域名配置器"""

import argparse
import json
import logging
import os
import random
import re
import sys
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor, as_completed

import pandas as pd
import requests
from cloudflare import Cloudflare
from comutils import get_main_domain_name_from_str
from dotenv import load_dotenv

# 配置日志
logger = logging.getLogger(name=__name__)
logger.setLevel(logging.INFO)
# 创建一个handler
ch = logging.StreamHandler()
ch.setLevel(logging.INFO)
# 定义handler的输出格式
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
ch.setFormatter(formatter)


load_dotenv()
# 配置默认的配置组(一个服务器配一个默认的cloudflare账号)
CONFIG_GROUP = "cxxu_df2"

DESKTOP = r"C:/Users/Administrator/Desktop"
# CONFIG_PATH = f"{DESKTOP}/deploy_configs/server_config.json"
DESKTOP = r"C:/Users/Administrator/Desktop"
DEPLOY_CONFIGS = f"{DESKTOP}/deploy_configs"
# 默认配置文件路径
CONFIG_PATH = f"{DEPLOY_CONFIGS}/cf_config.json"
# 通用格式:采用table.conf中的第一列数据作为要配置的域名
CF_DOMAINS_TABLE_CONF = f"{DESKTOP}/table.conf"
# 完整专用格式
CF_DOMAINS_CSV = f"{DESKTOP}/cf_domains.csv"  # 域名和IP配置文件，格式: 域名,IP
# 选择其中一个🎈
CF_DOMAINS_FILE = CF_DOMAINS_TABLE_CONF

# DOMAINS_FILE = "domains.xlsx"  # 域名和IP配置文件，格式: 域名,IP
SITE_TAGS_FILENAME = f"{DESKTOP}/cf_site_tags.conf"


THREADS = 5  # 并发线程数
API_TIMEOUT = 100  # API 请求超时时间（秒）


# 全局统计变量
processed_count = 0
success_count = 0
lock = threading.Lock()


def load_config(config_path) -> dict:
    """加载配置文件(json)
    Args:
        config_path: 配置文件路径
    Returns:
         config: 配置字典

    """
    if not os.path.exists(config_path):
        logger.warning(f"{config_path} 文件不存在")
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f) or {}
    return {}


def parse_args():
    parser = argparse.ArgumentParser(description="Cloudflare域名管理工具")
    parser.add_argument(
        "action",
        nargs="?",
        choices=["add_zone", "configure"],
        help="执行操作: add_zone(只添加域名) 或 configure(配置已添加的域名)",
    )
    parser.add_argument(
        "-c",
        "--cf-config",
        default=CONFIG_PATH,
        help=f"Cloudflare配置信息文件(Default:{CONFIG_PATH})",
    )
    parser.add_argument(
        "-f",
        "-t",
        "--file",
        "--table",
        default=CF_DOMAINS_FILE,
        help="包含要在cf上配置的域名配置文本文件,可以是专用格式csv文件,也可以是简化的普通格式conf文件",
    )
    parser.add_argument(
        "-ip",
        "--ip-address",
        help="指定添加dns时解析到的服务器IP地址",
    )
    parser.add_argument(
        "-a",
        "--account",
        help="Cloudflare账户,例如account1,account2等,具体可用账户名配置在cf_config.json文件中",
    )

    args = parser.parse_args()
    return args


args = parse_args()
config = load_config(config_path=args.cf_config)
accounts = config.get("accounts", {})
account = accounts.get(args.account, {})
# account_name=account.get("account", "")
CF_EMAIL = account.get("cf_api_email")
CF_API_KEY = account.get("cf_api_key")
# 账号优先解析的服务器ip地址🎈
DEFAULT_SERVER_IP = args.ip_address or account.get("default_server_ip")
print(f"默认绑定域名到ip: {DEFAULT_SERVER_IP}")


DEFAULT_FORWARD_EMAIL = config.get("default_forward_email")
DEFAULT_SSL_MODE = config.get("ssl_mode") or "flexible"
DEFAULT_SECURITY_MODE = config.get("security_mode") or 1

# 通用格式

# 普通环境变量,名字就是引号中的,取值根据自己的情况设置🎈
# CLOUDFLARE_EMAIL = os.environ.get("CLOUDFLARE_EMAIL")
# CLOUDFLARE_API_KEY = os.environ.get("CLOUDFLARE_API_KEY")
# DEFAULT_FORWARD_EMAIL = os.environ.get("DEFAULT_FORWARD_EMAIL")
# DEFAULT_SERVER_IP = os.environ.get("DF_SERVER1")
# 另一种综合配置文件中读取cf配置
# servers=config.get("servers", {})
# # config_group
# auth = servers.get(CONFIG_GROUP, {})
# account = auth.get("cf_account", {})
# default = config.get("default", {}).get("cf", {})


# CF_EMAIL = account.get("cf_api_email")
# CF_API_KEY = account.get("cf_api_key")
# DEFAULT_FORWARD_EMAIL = default.get("default_forward_email")
# DEFAULT_SERVER_IP = auth.get("ip")

# 其他
# DEFAULT_SSL_MODE = default.get("ssl_mode") or "flexible"

# DEFAULT_SECURITY_MODE = default.get("security_mode") or 1


def load_domains_from_file(file):
    """从文件加载域名、IP、邮箱前缀和转发邮件地址
    Excel,csv,conf
    """
    domains_info = []
    df = pd.DataFrame()
    try:
        # 读取表格文件
        # csv情况:
        if file.endswith(".csv"):
            df = pd.read_csv(file, keep_default_na=False)
        elif file.endswith(".xlsx"):
            df = pd.read_excel(file, keep_default_na=False)
        elif file.endswith(".conf") or file.endswith(".txt"):
            with open(file, "r", encoding="utf-8") as f:
                lines = f.readlines()
                domains = []
                for line in lines:
                    # line.split(" ")
                    # 数量不定的空白作为分隔符
                    parts = re.split(r"\s+", line.strip())
                    domain = parts[0].strip()
                    if not re.match(r"\s*\w+", domain):
                        print(f"忽略行: {line}")
                        continue
                    domain = get_main_domain_name_from_str(domain)
                    domains.append(domain)
                    # print(parts)
                    # print(domain)
                all_columns = ["domain", "ip", "forward", "security", "ssl", "Note"]
                df = pd.DataFrame({"domain": domains}, columns=all_columns)
                df.fillna("", inplace=True)
        else:
            raise ValueError("文件格式错误")
        # debug
        # print(df)
        # exit(0)
        # df = df.dropna(subset=["domain"])
        df = df[df["domain"].notna() & (df["domain"] != "")]

        for _, row in df.iterrows():
            domain = row.get("domain", "").strip()
            # 检查域名和IP是否为空
            if domain:
                domains_info.append(row)
        # print(domains_info)
        print(df)
    except Exception as e:
        print(f"读取域名表格文件出错: {str(e)}")
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
            # log(f"获取域名 {domain} 的zone信息")
            return zones.result[0]

        # 创建新Zone
        log(f"为 {domain} 创建新zone")
        try:
            zone = client.zones.create(
                name=domain,
                account={"id": ACCOUNT_ID},
                type="full",
                timeout=API_TIMEOUT,
            )
        except Exception as e:
            # 检查是否是因为域名已存在的错误
            if "already exists and is owned by another user" in str(e):
                log(f"域名 {domain} 已经被其他账户添加")
                return None
            else:
                raise  # 重新抛出其他类型的错误

        # 等待Zone激活，增加等待时间和重试次数
        max_retries = 10  # 增加重试次数
        retry_delay = 5  # 每次等待5秒
        activated = False

        log(f"等待域名 {domain} 激活 (最多尝试 {max_retries*retry_delay} 秒)...")

        # 首先等待一小段时间让系统处理
        time.sleep(3)

        for attempt in range(max_retries):
            try:
                zone_status = client.zones.get(zone_id=zone.id, timeout=API_TIMEOUT)
                log(
                    f"域名 {domain} 状态: {zone_status.status} (尝试 {attempt+1}/{max_retries})"
                )

                if zone_status.status == "active":
                    activated = True
                    break
                elif zone_status.status == "pending":
                    # 域名处于待处理状态，继续等待
                    log(f"域名 {domain} 处于待处理状态，继续等待...")

                # 尝试一个变通方法：检查是否可以获取DNS记录
                try:
                    client.dns.records.list(zone_id=zone.id, timeout=API_TIMEOUT)
                    log(f"域名 {domain} 可以管理DNS记录，视为已激活")
                    activated = True
                    break
                except:
                    # 如果无法获取DNS记录，继续等待
                    pass

            except Exception as e:
                log(f"检查 {domain} 的zone状态时出错: {str(e)}")

            time.sleep(retry_delay)

        if activated:
            log(f"域名 {domain} 已成功激活")
            return zone
        else:
            log(f"域名 {domain} 未在规定时间内激活，但仍返回zone对象")
            # 即使未显示激活也返回zone对象，有些域名虽然状态未更新但仍可使用
            return zone

    except Exception as e:
        log(f"获取或创建 {domain} 的zone时出错: {str(e)}")
        return None


def deal_ip(zone_id, domain, ip_address):
    log(f"设置域名 {domain}, IP: {ip_address}")
    records_to_create = [
        {"type": "A", "name": "@", "content": ip_address, "proxied": True},
        {"type": "A", "name": "www", "content": ip_address, "proxied": True},
    ]

    # 先获取现有记录
    try:
        existing_records = client.dns.records.list(zone_id=zone_id, timeout=API_TIMEOUT)
        existing_map = {(r.name, r.type): r.id for r in existing_records.result}
    except Exception as e:
        log(f"获取 {domain} 现有DNS记录失败: {str(e)}")
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
            print("创建", record_key, record)
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
                log(f"更新 {domain} 的DNS记录失败: {result.errors}")
                return False
            else:
                log(f"成功更新 {domain} 的DNS记录")
        except Exception as e:
            log(f"{domain} 批量DNS操作时出错: {str(e)}")
            return False

    return True


def deal_ssl(zone_id, domain, ssl_type):
    log(f"设置 {domain} 的SSL: {ssl_type}")

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
    log(f"设置 {domain} 转发邮箱: {forward_email}")

    try:
        # 启用Email Routing

        result = client.email_routing.get(zone_id=zone_id)
        # print("1result", result)
        if hasattr(result, "errors") and result.errors:
            batchadd = []
            print("注意路由设置:", result.errors)
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
        print("启用邮件路由时出错:", e)
        return False

    return True


def deal_domain_security(zone_id, domain):
    log(f"初始化域名{zone_id}, {domain} 的安全状态...")

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

    bot_management = client.bot_management.update(
        zone_id=zone_id,
        ai_bots_protection="block",
        # crawler_protection="enabled",
        enable_js=True,
        fight_mode=True,
    )
    if bot_management.fight_mode != True:
        print("bot_management", bot_management)
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
    forward_emails = [
        domain.get("forward", DEFAULT_FORWARD_EMAIL).strip().lower()
        for domain in domains
        if domain.get("forward")
    ]

    # 过滤空字符串
    forward_emails = [email for email in forward_emails if email]

    if not forward_emails:
        return []

    remote_results = client.email_routing.addresses.list(account_id=ACCOUNT_ID).result
    existing_addresses = [
        item.email.strip().lower() for item in remote_results if item.verified
    ]

    result = []
    for email in forward_emails:
        if email and email not in existing_addresses:
            print("创建邮件地址", email)
            result.append(email)
            client.email_routing.addresses.create(account_id=ACCOUNT_ID, email=email)
    return result


def add_zone_only(info):
    """只添加域名（Zone），不做其他设置"""
    global processed_count, success_count

    try:
        domain = info.get("domain").strip().lower()

        log(f"添加域名 {domain}...")

        with lock:
            processed_count += 1

        zone = get_or_create_zone(domain)
        if not zone:
            log(f"获取或创建 {domain} 的zone失败")
            return False

        log(f"成功添加域名 {domain}, zone ID: {zone.id}")

        with lock:
            success_count += 1

        return True

    except Exception as e:
        traceback.print_exc()
        log(f"处理 {domain} 时出错: {str(e)}")
        return False


def configure_zone(info):
    """对已添加的域名进行配置
    总配置函数,第二个环节的组织者,功能开关配置入口

    """
    global processed_count, success_count
    # 随机延时3秒以上,防止过于密集访问api
    time.sleep(random.randint(3, 7))
    try:
        # 读取数据字段🎈
        domain = info.get("domain").strip().lower()
        ip = info.get("ip", DEFAULT_SERVER_IP).strip() or DEFAULT_SERVER_IP
        ssl = info.get("ssl", "").strip().lower() or DEFAULT_SSL_MODE
        forward = (
            info.get("forward", DEFAULT_FORWARD_EMAIL).strip().lower()
            or DEFAULT_FORWARD_EMAIL
        )
        need_security = (
            info.get("security", DEFAULT_SECURITY_MODE) or DEFAULT_SECURITY_MODE
        )

        log(f"配置域名 {domain}...")

        with lock:
            processed_count += 1

        # 检查Zone是否存在
        zones = client.zones.list(name=domain, timeout=API_TIMEOUT)
        if not zones.result:
            log(f"域名 {domain} 未找到，请先添加域名")
            return False

        zone_id = zones.result[0].id

        success = True
        # 🎈
        # 配置DNS
        if ip:
            if not deal_ip(zone_id, domain, ip):
                log(f"设置 {domain} 的DNS失败")
                success = False

        # 配置SSL加密模式
        if ssl:
            if not deal_ssl(zone_id, domain, ssl_type=ssl):
                log(f"设置 {domain} 的SSL失败")
                success = False

        # 配置邮件转发
        if forward:
            if not deal_forward(zone_id, domain, forward):
                log(f"设置 {domain} 的邮件转发失败")
                success = False

        # 配置安全设置
        if need_security == 1:
            if not deal_domain_security(zone_id, domain):
                log(f"设置 {domain} 的安全配置失败")
                success = False

        if success:
            with lock:
                success_count += 1

            log(f"成功配置域名 {domain}")

        return success

    except Exception as e:
        traceback.print_exc()
        log(f"配置 {domain} 时出错: {str(e)}")
        return False


def get_account_id():
    # 获取账户ID
    accounts = client.accounts.list(timeout=API_TIMEOUT)
    if not accounts.result:
        log("未找到Cloudflare账户")
        return None

    account_id = accounts.result[0].id
    return account_id


def get_existing_domains():
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


def main():
    """主函数入口"""
    args = parse_args()
    file = args.file  # or CF_DOMAINS_FILE

    global CF_EMAIL, CF_API_KEY, client, curl_headers, ACCOUNT_ID, existing_domains, processed_count, success_count

    if not CF_EMAIL or not CF_API_KEY:
        print("请设置环境变量 CLOUDFLARE_EMAIL 和 CLOUDFLARE_API_KEY")
        sys.exit(1)
    else:
        print(f"已设置环境变量CF_EMAIL:{CF_EMAIL};CF_API_KEY:{CF_API_KEY}")

    client = Cloudflare(
        api_email=CF_EMAIL,
        api_key=CF_API_KEY,
    )

    curl_headers = {
        "Content-Type": "application/json",
        "X-Auth-Email": CF_EMAIL,
        "X-Auth-Key": CF_API_KEY,
    }

    ACCOUNT_ID = get_account_id()
    if not ACCOUNT_ID:
        print("未找到有效的Cloudflare账户")
        sys.exit(1)

    # 如果没有通过命令行参数指定动作，显示菜单让用户选择
    if not args.action:
        print("\n" + "=" * 50)
        print("Cloudflare 域名管理工具")
        print("=" * 50)
        print("请选择要执行的操作：")
        print("  1. 添加域名 - 仅创建Cloudflare Zone")
        print("  2. 配置域名 - 对已添加域名设置DNS/SSL/邮箱转发/安全设置")
        print("  0. 退出程序")
        print("-" * 50)

        while True:
            try:
                choice = input("请输入选项 [0-2]: ").strip()
                if choice == "0":
                    print("程序已退出")
                    sys.exit(0)
                elif choice == "1":
                    args.action = "add_zone"
                    break
                elif choice == "2":
                    args.action = "configure"
                    break
                else:
                    print("无效选项，请重新输入")
            except KeyboardInterrupt:
                print("\n程序已被用户中断")
                sys.exit(0)

    # 加载域名列表🎈
    domains = load_domains_from_file(file)
    if not domains:
        print("输入文件中未找到域名")
        sys.exit(1)

    print(f"待处理域名 {len(domains)} 个")

    # 重置计数器
    processed_count = 0
    success_count = 0

    if args.action == "add_zone":
        # 步骤1: 只添加域名
        print("=" * 50)
        print("步骤1: 添加域名")
        print("=" * 50)

        # 使用ThreadPoolExecutor执行多线程添加域名🎈
        with ThreadPoolExecutor(max_workers=THREADS) as executor:
            futures = [executor.submit(add_zone_only, record) for record in domains]

            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    log(f"添加域名时出错: {str(e)}")

    elif args.action == "configure":
        # 步骤2: 配置已添加的域名
        print("=" * 50)
        print("步骤2: 配置域名")
        print("=" * 50)

        # 处理邮件地址
        address_result = deal_addresses(domains)
        if len(address_result) > 0:
            print("待激活邮件:", address_result)
            print("请先验证这些邮件地址，然后再运行配置")
            sys.exit(1)

        # 加载已有域名信息
        existing_domains = get_existing_domains()

        # 使用ThreadPoolExecutor执行多线程配置域名
        w = 3
        # (不宜过多,容易429,而且可能导致网站证书请求频率过高使得访问https链接提示ssl证书错误)
        print(f"使用{w}个线程配置域名...")
        with ThreadPoolExecutor(w) as executor:
            futures = [executor.submit(configure_zone, record) for record in domains]

            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    log(f"配置域名时出错: {str(e)}")

    # 输出统计信息
    print("\n" + "=" * 50)
    print("处理完成!")
    print(f"总共处理域名: {processed_count}")
    print(f"成功处理: {success_count}")
    print(f"失败: {processed_count - success_count}")
    print("=" * 50)


if __name__ == "__main__":
    main()
