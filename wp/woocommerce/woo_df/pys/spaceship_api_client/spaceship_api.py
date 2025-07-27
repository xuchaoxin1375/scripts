"""
spaceship 域名管理API封装客户端程序
支持常用的域名管理功能,详情查看配套的readme文档
最核心的功能是域名列举,域名信息查看和域名服务器(nameservers)的修改(这对于cloudflare配置来说是重要的)

开发参考spaceship API文档:
https://docs.spaceship.dev/

api基础端点路径
https://spaceship.dev/api/

这里APIClient可以作为一个模块单独存放
而main函数可以分离出去
"""

import argparse
import json
import os
import sys
import requests


class APIClient:
    """spaceship 域名管理API封装客户端程序"""

    def __init__(self, api_key, api_secret):
        """初始化API客户端"""
        self.api_key = api_key
        self.api_secret = api_secret
        self.base_url = "https://spaceship.dev/api/v1"

    def _headers(self):
        """生成请求头"""
        return {"X-API-Key": self.api_key, "X-API-Secret": self.api_secret}

    def _request(self, method, endpoint, **kwargs):
        """
        通用请求方法
        :param method: HTTP方法，如'GET', 'POST', 'PUT', 'DELETE'
        :param endpoint: API路径（不含base_url）
        :param kwargs: 其他requests参数
        :return: 响应JSON或文本
        """
        url = f"{self.base_url}{endpoint}"
        try:
            response = requests.request(
                method, url, headers=self._headers(), timeout=10, **kwargs
            )
            response.raise_for_status()
            ct = response.headers.get("Content-Type", "")
            if "application/json" in ct:
                return response.json()
            return response.text
        except Exception as e:
            print(f"API请求失败: {e}", file=sys.stderr)
            return None

    def list_domains(self, take=10, skip=0, order_by="expirationDate"):
        """列出域名列表"""
        params = {"take": take, "skip": skip, "orderBy": order_by}
        return self._request("GET", "/domains", params=params)

    def get_domain(self, domain):
        """查询域名详情"""
        return self._request("GET", f"/domains/{domain}")

    def get_nameservers(self, domain):
        """获取域名的nameservers信息
        返回: nameservers对象（dict或list），未找到时返回None
        """
        domain_info = self._request("GET", f"/domains/{domain}")
        if domain_info and isinstance(domain_info, dict) and "nameservers" in domain_info:
            return domain_info["nameservers"]
        print("未找到nameservers信息")
        return None

    def update_nameservers(self, domain, provider, hosts: list[str] | None = None):
        """更新域名的nameservers信息
        :param domain: 域名
        :param provider: nameservers提供商（basic/custom）
        :param hosts: nameserver主机列表（仅provider为custom时需要）
        """
        payload = {"provider": provider}
        if provider == "custom" and hosts:
            payload["hosts"] = hosts
        return self._request("PUT", f"/domains/{domain}/nameservers", json=payload)

    def register_domain(self, domain, auto_renew=True, privacy_level="high"):
        """注册域名"""
        payload = {
            "name": domain,
            "autoRenew": auto_renew,
            "privacyProtection": {"level": privacy_level},
        }
        return self._request("POST", f"/domains/{domain}", json=payload)

    def delete_domain(self, domain):
        """删除域名"""
        return self._request("DELETE", f"/domains/{domain}")

    def renew_domain(self, domain, years, current_expiration_date):
        """续费域名"""
        payload = {"years": years, "currentExpirationDate": current_expiration_date}
        return self._request("POST", f"/domains/{domain}/renew", json=payload)

    def restore_domain(self, domain):
        """恢复域名"""
        return self._request("POST", f"/domains/{domain}/restore")

    def transfer_domain(self, domain, auth_code):
        """转移域名"""
        payload = {"name": domain, "authCode": auth_code}
        return self._request("POST", f"/domains/{domain}/transfer", json=payload)

    def lock_domain(self, domain, is_locked):
        """设置域名转移锁"""
        payload = {"isLocked": is_locked}
        return self._request("PUT", f"/domains/{domain}/transfer/lock", json=payload)

    def privacy_domain(self, domain, privacy_level, user_consent):
        """设置域名隐私保护"""
        payload = {"privacyLevel": privacy_level, "userConsent": user_consent}
        return self._request(
            "PUT", f"/domains/{domain}/privacy/preference", json=payload
        )

    def email_protect(self, domain, contact_form):
        """设置域名邮箱保护"""
        payload = {"contactForm": contact_form}
        return self._request(
            "PUT",
            f"/domains/{domain}/privacy/email-protection-preference",
            json=payload,
        )

    def list_dns(self, domain, take=100, skip=0, order_by="type"):
        """查询域名DNS记录
        :param domain: 域名
        :param take: 返回条数，默认100
        :param skip: 跳过条数，默认0
        :param order_by: 排序字段，默认"type"
        :return: 响应JSON或文本
        """
        if not isinstance(take, int) or take < 0:
            raise ValueError("take must be a non-negative integer")
        if not isinstance(skip, int) or skip < 0:
            raise ValueError("skip must be a non-negative integer")

        params = {"take": take, "skip": skip, "orderBy": order_by}
        return self._request("GET", f"/dns/records/{domain}", params=params)

    def add_dns(self, domain, type_, name, address, ttl=3600):
        """添加DNS记录"""
        payload = {
            "force": True,
            "items": [{"type": type_, "name": name, "address": address, "ttl": ttl}],
        }
        return self._request("PUT", f"/dns/records/{domain}", json=payload)

    def delete_dns(self, domain, type_, name, address):
        """删除DNS记录"""
        payload = [{"type": type_, "name": name, "address": address}]
        return self._request("DELETE", f"/dns/records/{domain}", json=payload)

    def save_contact(self, **kwargs):
        """创建联系人"""
        return self._request("PUT", "/contacts", json=kwargs)

    def get_contact(self, contact_id):
        """查询联系人"""
        return self._request("GET", f"/contacts/{contact_id}")

    def update_contact(self, contact_id, **kwargs):
        """更新联系人"""
        return self._request("PUT", f"/contacts/{contact_id}", json=kwargs)

    def save_contact_attr(self, type_, euAdrLang=None, is_natural_person=None):
        """保存联系人属性"""
        payload = {"type": type_}
        if euAdrLang is not None:
            payload["euAdrLang"] = euAdrLang
        if is_natural_person is not None:
            payload["isNaturalPerson"] = is_natural_person
        return self._request("PUT", "/contacts/attributes", json=payload)

    def get_contact_attr(self, contact_id):
        """查询联系人属性"""
        return self._request("GET", f"/contacts/attributes/{contact_id}")

    def get_async(self, operation_id):
        """查询异步操作状态"""
        return self._request("GET", f"/async-operations/{operation_id}")


def load_config(config_path):
    """加载配置文件"""
    if not os.path.exists(config_path):
        return {}
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_args():
    """ 解析命令行参数 """
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
        default="spaceship_config.json",
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
    parser_list_domains.add_argument(
        "--names_only", action="store_true", help="只输出域名，每行一个"
    )
    parser_list_domains.add_argument(
        "--all", action="store_true", help="列出全部域名（忽略take/skip参数）"
    )
    # Nameservers相关
    parser_get_nameservers = subparsers.add_parser(
        "get-nameservers", help="查看域名nameservers"
    )
    parser_get_nameservers.add_argument(
        "--domain", type=str, required=True, help="域名"
    )

    parser_update_nameservers = subparsers.add_parser(
        "update-nameservers", help="更新域名nameservers"
    )
    parser_update_nameservers.add_argument(
        "--domain", type=str, required=True, help="域名"
    )
    parser_update_nameservers.add_argument(
        "--provider",
        type=str,
        choices=["basic", "custom"],
        required=True,
        help="nameservers提供商",
    )
    parser_update_nameservers.add_argument(
        "--hosts",
        type=str,
        nargs="*",
        help="nameserver主机列表(仅provider为custom时必填)",
    )
    parser_get_domain = subparsers.add_parser("get-domain", help="查询域名详情")
    parser_get_domain.add_argument("--domain", type=str, required=True, help="域名")
    parser_register_domain = subparsers.add_parser("register-domain", help="注册域名")
    parser_register_domain.add_argument(
        "--domain", type=str, required=True, help="域名"
    )
    parser_register_domain.add_argument(
        "--auto_renew", action="store_true", help="自动续费(默认开启)", default=True
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
        "--is_locked", action="store_true", help="是否锁定(加锁)"
    )
    parser_lock_domain.add_argument(
        "--no_lock", action="store_true", help="是否解锁(解锁)"
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
        "--user_consent", action="store_true", help="用户同意变更"
    )
    parser_email_protect = subparsers.add_parser(
        "email-protect", help="设置域名邮箱保护"
    )
    parser_email_protect.add_argument("--domain", type=str, required=True, help="域名")
    parser_email_protect.add_argument(
        "--contact_form", action="store_true", help="显示联系表单"
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
        "--is_natural_person", action="store_true", help="是否自然人"
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
    """获取API认证信息"""
    return {
        "api_key": args.api_key or config.get("api_key"),
        "api_secret": args.api_secret or config.get("api_secret"),
    }


def main():
    """ 主函数,主要负责命令行参数解析和API客户端初始化和调用 """
    args = parse_args()
    config = load_config(args.config)
    auth = get_auth(args, config)
    if not auth["api_key"] or not auth["api_secret"]:
        print("API Key 和 Secret 必须指定 (命令行或配置文件)", file=sys.stderr)
        sys.exit(1)
    client = APIClient(auth["api_key"], auth["api_secret"])
    if args.command == "list-domains":
        if getattr(args, "all", False):
            # 获取全部域名
            all_domains = []
            # 配置单次请求默认参数
            skip = 0
            take = 100
            # 循环调用list_domains直到所有域名
            while True:
                resp = client.list_domains(take, skip, args.order_by)
                if not resp or "items" not in resp:
                    break
                if isinstance(resp, dict):
                    items = resp.get("items", [])
                else:
                    items = []
                if not items:
                    break
                all_domains.extend(items)
                skip += len(items)
                if len(items) < take:
                    break
            result = {"items": all_domains, "total": len(all_domains)}
        else:
            result = client.list_domains(args.take, args.skip, args.order_by)
        if getattr(args, "names_only", False):
            # 只输出域名，每行一个
            if result and "items" in result:
                if isinstance(result, dict):
                    items_list = result.get("items", [])
                else:
                    items_list = []
                for item in items_list:
                    if isinstance(item, dict):
                        print(item.get("name", ""))
                    elif isinstance(item, str):
                        print(item)
                    else:
                        print(str(item))
            else:
                print("")
            return
        else:
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return
    elif args.command == "get-domain":
        result = client.get_domain(args.domain)
    elif args.command == "get-nameservers":
        result = client.get_nameservers(args.domain)
        # 只输出nameservers部分
        print(result)
        return
    elif args.command == "update-nameservers":
        result = client.update_nameservers(args.domain, args.provider, args.hosts)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return
    elif args.command == "register-domain":
        result = client.register_domain(
            args.domain, args.auto_renew, args.privacy_level
        )
    elif args.command == "delete-domain":
        result = client.delete_domain(args.domain)
    elif args.command == "renew-domain":
        result = client.renew_domain(
            args.domain, args.years, args.current_expiration_date
        )
    elif args.command == "restore-domain":
        result = client.restore_domain(args.domain)
    elif args.command == "transfer-domain":
        result = client.transfer_domain(args.domain, args.auth_code)
    elif args.command == "lock-domain":
        # 兼容加锁/解锁
        is_locked = True if getattr(args, "is_locked", False) else False
        if getattr(args, "no_lock", False):
            is_locked = False
        result = client.lock_domain(args.domain, is_locked)
    elif args.command == "privacy-domain":
        result = client.privacy_domain(
            args.domain, args.privacy_level, args.user_consent
        )
    elif args.command == "email-protect":
        result = client.email_protect(args.domain, args.contact_form)
    elif args.command == "list-dns":
        result = client.list_dns(args.domain, args.take, args.skip, args.order_by)
    elif args.command == "add-dns":
        result = client.add_dns(
            args.domain, args.type, args.name, args.address, args.ttl
        )
    elif args.command == "delete-dns":
        result = client.delete_dns(args.domain, args.type, args.name, args.address)
    elif args.command == "save-contact":
        contact_args = vars(args)
        for k in ["command", "api_key", "api_secret", "config"]:
            contact_args.pop(k, None)
        result = client.save_contact(**contact_args)
    elif args.command == "get-contact":
        result = client.get_contact(args.contact_id)
    elif args.command == "update-contact":
        update_args = vars(args)
        contact_id = update_args.pop("contact_id")
        for k in ["command", "api_key", "api_secret", "config"]:
            update_args.pop(k, None)
        result = client.update_contact(contact_id, **update_args)
    elif args.command == "save-contact-attr":
        result = client.save_contact_attr(
            args.type, args.euAdrLang, args.is_natural_person
        )
    elif args.command == "get-contact-attr":
        result = client.get_contact_attr(args.contact_id)
    elif args.command == "get-async":
        result = client.get_async(args.operation_id)
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
