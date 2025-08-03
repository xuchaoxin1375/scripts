import argparse
import json
import os
import sys
import requests

CONFIG_FILE = "spaceship_config.json"
API_URL = "https://spaceship.dev/api/v1/domains"


def call_register_domain(api_key, api_secret, domain, auto_renew, privacy_level):
    url = f"https://spaceship.dev/api/v1/domains/{domain}"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = {
        "name": domain,
        "autoRenew": auto_renew,
        "privacyProtection": {"level": privacy_level},
    }
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"注册域名失败: {e}", file=sys.stderr)
        return None


def call_delete_domain(api_key, api_secret, domain):
    url = f"https://spaceship.dev/api/v1/domains/{domain}"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    try:
        response = requests.delete(url, headers=headers, timeout=10)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"删除域名失败: {e}", file=sys.stderr)
        return None


def call_renew_domain(api_key, api_secret, domain, years, current_expiration_date):
    url = f"https://spaceship.dev/api/v1/domains/{domain}/renew"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = {"years": years, "currentExpirationDate": current_expiration_date}
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"续费域名失败: {e}", file=sys.stderr)
        return None


def call_restore_domain(api_key, api_secret, domain):
    url = f"https://spaceship.dev/api/v1/domains/{domain}/restore"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    try:
        response = requests.post(url, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"恢复域名失败: {e}", file=sys.stderr)
        return None


def call_transfer_domain(api_key, api_secret, domain, auth_code):
    url = f"https://spaceship.dev/api/v1/domains/{domain}/transfer"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = {"name": domain, "authCode": auth_code}
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"转移域名失败: {e}", file=sys.stderr)
        return None


def call_lock_domain(api_key, api_secret, domain, is_locked):
    url = f"https://spaceship.dev/api/v1/domains/{domain}/transfer/lock"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = {"isLocked": is_locked}
    try:
        response = requests.put(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"设置域名转移锁失败: {e}", file=sys.stderr)
        return None


def call_privacy_domain(api_key, api_secret, domain, privacy_level, user_consent):
    url = f"https://spaceship.dev/api/v1/domains/{domain}/privacy/preference"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = {"privacyLevel": privacy_level, "userConsent": user_consent}
    try:
        response = requests.put(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"设置域名隐私保护失败: {e}", file=sys.stderr)
        return None


def call_email_protect(api_key, api_secret, domain, contact_form):
    url = f"https://spaceship.dev/api/v1/domains/{domain}/privacy/email-protection-preference"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = {"contactForm": contact_form}
    try:
        response = requests.put(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"设置域名邮箱保护失败: {e}", file=sys.stderr)
        return None


def call_add_dns(api_key, api_secret, domain, type_, name, address, ttl):
    url = f"https://spaceship.dev/api/v1/dns/records/{domain}"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = {
        "force": True,
        "items": [{"type": type_, "name": name, "address": address, "ttl": ttl}],
    }
    try:
        response = requests.put(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"添加DNS记录失败: {e}", file=sys.stderr)
        return None


def call_delete_dns(api_key, api_secret, domain, type_, name, address):
    url = f"https://spaceship.dev/api/v1/dns/records/{domain}"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = [{"type": type_, "name": name, "address": address}]
    try:
        response = requests.delete(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"删除DNS记录失败: {e}", file=sys.stderr)
        return None


def call_save_contact(api_key, api_secret, **kwargs):
    url = "https://spaceship.dev/api/v1/contacts"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = kwargs
    try:
        response = requests.put(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"创建联系人失败: {e}", file=sys.stderr)
        return None


def call_get_contact(api_key, api_secret, contact_id):
    url = f"https://spaceship.dev/api/v1/contacts/{contact_id}"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"查询联系人失败: {e}", file=sys.stderr)
        return None


def call_update_contact(api_key, api_secret, contact_id, **kwargs):
    url = f"https://spaceship.dev/api/v1/contacts/{contact_id}"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = kwargs
    try:
        response = requests.put(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"更新联系人失败: {e}", file=sys.stderr)
        return None


def call_save_contact_attr(
    api_key, api_secret, type_, euAdrLang=None, is_natural_person=None
):
    url = "https://spaceship.dev/api/v1/contacts/attributes"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    payload = {"type": type_}
    if euAdrLang is not None:
        payload["euAdrLang"] = euAdrLang
    if is_natural_person is not None:
        payload["isNaturalPerson"] = is_natural_person
    try:
        response = requests.put(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"保存联系人属性失败: {e}", file=sys.stderr)
        return None


def call_get_contact_attr(api_key, api_secret, contact_id):
    url = f"https://spaceship.dev/api/v1/contacts/attributes/{contact_id}"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"查询联系人属性失败: {e}", file=sys.stderr)
        return None


def call_get_async(api_key, api_secret, operation_id):
    url = f"https://spaceship.dev/api/v1/async-operations/{operation_id}"
    headers = {"X-API-Key": api_key, "X-API-Secret": api_secret}
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"查询异步操作失败: {e}", file=sys.stderr)
        return None


def load_config(config_path):
    if not os.path.exists(config_path):
        return {}
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Spaceship API Client: 多子命令支持，域名/DNS/联系人管理"
    )
    parser.add_argument("--api_key", type=str, help="Spaceship API Key (可全局指定)")
    parser.add_argument(
        "--api_secret", type=str, help="Spaceship API Secret (可全局指定)"
    )
    parser.add_argument(
        "--config",
        type=str,
        default=CONFIG_FILE,
        help="配置文件路径，默认spaceship_config.json",
    )

    subparsers = parser.add_subparsers(dest="command", required=True, help="功能命令")

    # 域名相关
    parser_list_domains = subparsers.add_parser("list-domains", help="列出域名列表")
    parser_list_domains.add_argument("--take", type=int, default=10, help="返回条数")
    parser_list_domains.add_argument("--skip", type=int, default=0, help="跳过条数")
    parser_list_domains.add_argument(
        "--order_by", type=str, default="expirationDate", help="排序字段"
    )

    parser_get_domain = subparsers.add_parser("get-domain", help="查询域名详情")
    parser_get_domain.add_argument("--domain", type=str, required=True, help="域名")

    parser_register_domain = subparsers.add_parser("register-domain", help="注册域名")
    parser_register_domain.add_argument(
        "--domain", type=str, required=True, help="域名"
    )
    parser_register_domain.add_argument(
        "--auto_renew", type=bool, default=True, help="自动续费"
    )
    parser_register_domain.add_argument(
        "--privacy_level",
        type=str,
        choices=["public", "high"],
        default="high",
        help="隐私保护等级",
    )

    parser_delete_domain = subparsers.add_parser("delete-domain", help="删除域名")
    parser_delete_domain.add_argument("--domain", type=str, required=True, help="域名")

    parser_renew_domain = subparsers.add_parser("renew-domain", help="续费域名")
    parser_renew_domain.add_argument("--domain", type=str, required=True, help="域名")
    parser_renew_domain.add_argument(
        "--years", type=int, required=True, help="续费年数"
    )
    parser_renew_domain.add_argument(
        "--current_expiration_date",
        type=str,
        required=True,
        help="当前到期时间(ISO格式)",
    )

    parser_restore_domain = subparsers.add_parser("restore-domain", help="恢复域名")
    parser_restore_domain.add_argument("--domain", type=str, required=True, help="域名")

    parser_transfer_domain = subparsers.add_parser("transfer-domain", help="转移域名")
    parser_transfer_domain.add_argument(
        "--domain", type=str, required=True, help="域名"
    )
    parser_transfer_domain.add_argument(
        "--auth_code", type=str, required=True, help="转移授权码"
    )

    parser_lock_domain = subparsers.add_parser("lock-domain", help="设置域名转移锁")
    parser_lock_domain.add_argument("--domain", type=str, required=True, help="域名")
    parser_lock_domain.add_argument(
        "--is_locked", type=bool, required=True, help="是否锁定"
    )

    parser_privacy_domain = subparsers.add_parser(
        "privacy-domain", help="设置域名隐私保护"
    )
    parser_privacy_domain.add_argument("--domain", type=str, required=True, help="域名")
    parser_privacy_domain.add_argument(
        "--privacy_level",
        type=str,
        choices=["public", "high"],
        required=True,
        help="隐私保护等级",
    )
    parser_privacy_domain.add_argument(
        "--user_consent", type=bool, required=True, help="用户同意变更"
    )

    parser_email_protect = subparsers.add_parser(
        "email-protect", help="设置域名邮箱保护"
    )
    parser_email_protect.add_argument("--domain", type=str, required=True, help="域名")
    parser_email_protect.add_argument(
        "--contact_form", type=bool, required=True, help="是否显示联系表单"
    )

    # DNS相关
    parser_list_dns = subparsers.add_parser("list-dns", help="查询域名 DNS 记录")
    parser_list_dns.add_argument(
        "--domain", type=str, required=True, help="要查询的域名"
    )
    parser_list_dns.add_argument("--take", type=int, default=100, help="返回条数")
    parser_list_dns.add_argument("--skip", type=int, default=0, help="跳过条数")
    parser_list_dns.add_argument(
        "--order_by", type=str, default="type", help="排序字段"
    )

    parser_add_dns = subparsers.add_parser("add-dns", help="添加 DNS 记录")
    parser_add_dns.add_argument("--domain", type=str, required=True, help="域名")
    parser_add_dns.add_argument(
        "--type", type=str, required=True, help="记录类型(A, AAAA, CNAME, MX, TXT等)"
    )
    parser_add_dns.add_argument("--name", type=str, required=True, help="主机名")
    parser_add_dns.add_argument("--address", type=str, required=True, help="记录值")
    parser_add_dns.add_argument("--ttl", type=int, default=3600, help="TTL")

    parser_delete_dns = subparsers.add_parser("delete-dns", help="删除 DNS 记录")
    parser_delete_dns.add_argument("--domain", type=str, required=True, help="域名")
    parser_delete_dns.add_argument("--type", type=str, required=True, help="记录类型")
    parser_delete_dns.add_argument("--name", type=str, required=True, help="主机名")
    parser_delete_dns.add_argument("--address", type=str, required=True, help="记录值")

    # 联系人相关
    parser_save_contact = subparsers.add_parser("save-contact", help="创建联系人")
    parser_save_contact.add_argument("--first_name", type=str, required=True, help="名")
    parser_save_contact.add_argument("--last_name", type=str, required=True, help="姓")
    parser_save_contact.add_argument("--email", type=str, required=True, help="邮箱")
    parser_save_contact.add_argument(
        "--country", type=str, required=True, help="国家代码"
    )
    parser_save_contact.add_argument("--phone", type=str, required=True, help="电话")
    parser_save_contact.add_argument("--organization", type=str, help="公司")
    parser_save_contact.add_argument("--address1", type=str, help="地址1")
    parser_save_contact.add_argument("--address2", type=str, help="地址2")
    parser_save_contact.add_argument("--city", type=str, help="城市")
    parser_save_contact.add_argument("--state_province", type=str, help="省/州")
    parser_save_contact.add_argument("--postal_code", type=str, help="邮编")
    parser_save_contact.add_argument("--phone_ext", type=str, help="电话分机")
    parser_save_contact.add_argument("--fax", type=str, help="传真")
    parser_save_contact.add_argument("--fax_ext", type=str, help="传真分机")
    parser_save_contact.add_argument("--tax_number", type=str, help="税号")

    parser_get_contact = subparsers.add_parser("get-contact", help="查询联系人")
    parser_get_contact.add_argument(
        "--contact_id", type=str, required=True, help="联系人ID"
    )

    parser_update_contact = subparsers.add_parser("update-contact", help="更新联系人")
    parser_update_contact.add_argument(
        "--contact_id", type=str, required=True, help="联系人ID"
    )
    parser_update_contact.add_argument("--first_name", type=str, help="名")
    parser_update_contact.add_argument("--last_name", type=str, help="姓")
    parser_update_contact.add_argument("--email", type=str, help="邮箱")
    parser_update_contact.add_argument("--country", type=str, help="国家代码")
    parser_update_contact.add_argument("--phone", type=str, help="电话")
    parser_update_contact.add_argument("--organization", type=str, help="公司")
    parser_update_contact.add_argument("--address1", type=str, help="地址1")
    parser_update_contact.add_argument("--address2", type=str, help="地址2")
    parser_update_contact.add_argument("--city", type=str, help="城市")
    parser_update_contact.add_argument("--state_province", type=str, help="省/州")
    parser_update_contact.add_argument("--postal_code", type=str, help="邮编")
    parser_update_contact.add_argument("--phone_ext", type=str, help="电话分机")
    parser_update_contact.add_argument("--fax", type=str, help="传真")
    parser_update_contact.add_argument("--fax_ext", type=str, help="传真分机")
    parser_update_contact.add_argument("--tax_number", type=str, help="税号")

    # 联系人属性相关
    parser_save_contact_attr = subparsers.add_parser(
        "save-contact-attr", help="保存联系人属性"
    )
    parser_save_contact_attr.add_argument(
        "--type", type=str, required=True, help="属性类型"
    )
    parser_save_contact_attr.add_argument("--euAdrLang", type=str, help="语言")
    parser_save_contact_attr.add_argument(
        "--is_natural_person", type=bool, help="是否自然人"
    )

    parser_get_contact_attr = subparsers.add_parser(
        "get-contact-attr", help="查询联系人属性"
    )
    parser_get_contact_attr.add_argument(
        "--contact_id", type=str, required=True, help="联系人ID"
    )

    # 异步操作相关
    parser_get_async = subparsers.add_parser("get-async", help="查询异步操作状态")
    parser_get_async.add_argument(
        "--operation_id", type=str, required=True, help="异步操作ID"
    )

    return parser.parse_args()


def get_auth(args, config):
    return {
        "api_key": args.api_key or config.get("api_key"),
        "api_secret": args.api_secret or config.get("api_secret"),
    }


def call_list_domains(api_key, api_secret, take, skip, order_by):
    url = f"{API_URL}?take={take}&skip={skip}&orderBy={order_by}"
    headers = {
        "X-API-Key": api_key,
        "X-API-Secret": api_secret,
    }
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"API请求失败: {e}", file=sys.stderr)
        return None


def call_list_dns(api_key, api_secret, domain, take, skip, order_by):
    url = f"https://spaceship.dev/api/v1/dns/records/{domain}?take={take}&skip={skip}&orderBy={order_by}"
    headers = {
        "X-API-Key": api_key,
        "X-API-Secret": api_secret,
    }
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"DNS记录查询失败: {e}", file=sys.stderr)
        return None


def call_get_domain(api_key, api_secret, domain):
    url = f"https://spaceship.dev/api/v1/domains/{domain}"
    headers = {
        "X-API-Key": api_key,
        "X-API-Secret": api_secret,
    }
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        print(f"域名详情查询失败: {e}", file=sys.stderr)
        return None


def main():
    args = parse_args()
    config = load_config(args.config)
    auth = get_auth(args, config)
    if not auth["api_key"] or not auth["api_secret"]:
        print("API Key 和 Secret 必须指定 (命令行或配置文件)", file=sys.stderr)
        sys.exit(1)

    if args.command == "list-domains":
        result = call_list_domains(
            auth["api_key"], auth["api_secret"], args.take, args.skip, args.order_by
        )
    elif args.command == "get-domain":
        result = call_get_domain(auth["api_key"], auth["api_secret"], args.domain)
    elif args.command == "register-domain":
        result = call_register_domain(
            auth["api_key"],
            auth["api_secret"],
            args.domain,
            args.auto_renew,
            args.privacy_level,
        )
    elif args.command == "delete-domain":
        result = call_delete_domain(auth["api_key"], auth["api_secret"], args.domain)
    elif args.command == "renew-domain":
        result = call_renew_domain(
            auth["api_key"],
            auth["api_secret"],
            args.domain,
            args.years,
            args.current_expiration_date,
        )
    elif args.command == "restore-domain":
        result = call_restore_domain(auth["api_key"], auth["api_secret"], args.domain)
    elif args.command == "transfer-domain":
        result = call_transfer_domain(
            auth["api_key"], auth["api_secret"], args.domain, args.auth_code
        )
    elif args.command == "lock-domain":
        result = call_lock_domain(
            auth["api_key"], auth["api_secret"], args.domain, args.is_locked
        )
    elif args.command == "privacy-domain":
        result = call_privacy_domain(
            auth["api_key"],
            auth["api_secret"],
            args.domain,
            args.privacy_level,
            args.user_consent,
        )
    elif args.command == "email-protect":
        result = call_email_protect(
            auth["api_key"], auth["api_secret"], args.domain, args.contact_form
        )
    elif args.command == "list-dns":
        result = call_list_dns(
            auth["api_key"],
            auth["api_secret"],
            args.domain,
            args.take,
            args.skip,
            args.order_by,
        )
    elif args.command == "add-dns":
        result = call_add_dns(
            auth["api_key"],
            auth["api_secret"],
            args.domain,
            args.type,
            args.name,
            args.address,
            args.ttl,
        )
    elif args.command == "delete-dns":
        result = call_delete_dns(
            auth["api_key"],
            auth["api_secret"],
            args.domain,
            args.type,
            args.name,
            args.address,
        )
    elif args.command == "save-contact":
        contact_args = vars(args)
        contact_args.pop("command")
        contact_args.pop("api_key", None)
        contact_args.pop("api_secret", None)
        contact_args.pop("config", None)
        result = call_save_contact(auth["api_key"], auth["api_secret"], **contact_args)
    elif args.command == "get-contact":
        result = call_get_contact(auth["api_key"], auth["api_secret"], args.contact_id)
    elif args.command == "update-contact":
        update_args = vars(args)
        contact_id = update_args.pop("contact_id")
        update_args.pop("command")
        update_args.pop("api_key", None)
        update_args.pop("api_secret", None)
        update_args.pop("config", None)
        result = call_update_contact(
            auth["api_key"], auth["api_secret"], contact_id, **update_args
        )
    elif args.command == "save-contact-attr":
        result = call_save_contact_attr(
            auth["api_key"],
            auth["api_secret"],
            args.type,
            args.euAdrLang,
            args.is_natural_person,
        )
    elif args.command == "get-contact-attr":
        result = call_get_contact_attr(
            auth["api_key"], auth["api_secret"], args.contact_id
        )
    elif args.command == "get-async":
        result = call_get_async(auth["api_key"], auth["api_secret"], args.operation_id)
    else:
        print(f"未知命令: {args.command}", file=sys.stderr)
        sys.exit(3)

    if result is not None:
        if isinstance(result, (dict, list)):
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(result)
    else:
        sys.exit(2)


if __name__ == "__main__":
    main()
