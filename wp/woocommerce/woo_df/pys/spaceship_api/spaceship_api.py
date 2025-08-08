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
此外,APIClient内的请求不做重试处理,外部调用api对象的时候自行添加配置重试代码

"""

import argparse

from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
import sys
import time

import requests

DESKTOP = r"C:/Users/Administrator/Desktop"
# 默认配置文件路径
DEFAULT_CONFIG_PATH = os.path.join(DESKTOP, "spaceship_config.json")
class APIClient:
    """spaceship 域名管理API封装客户端程序"""

    def __init__(self, api_key, api_secret):
        """初始化API客户端"""
        self.api_key = api_key
        self.api_secret = api_secret
        self.base_url = "https://spaceship.dev/api/v1"
        self.domains_in_all_accounts = []
        self.suspended_domains = []

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

    def _list_domains(self, take=10, skip=0, order_by="expirationDate"):
        """列出域名列表
        调用默认的api一次请求只能列出一部分,并且返回的数据形式是json风格
        这里增加一些代码让其能够以更灵活的方式获取数据,满足更多需求

        """
        params = {"take": take, "skip": skip, "orderBy": order_by}
        return self._request("GET", "/domains", params=params)

    def list_domains(self, take=0, skip=0, order_by="expirationDate"):
        """列出域名列表
        调用默认的api一次请求只能列出一部分,并且返回的数据形式是json风格
        这里增加一些代码让其能够以更灵活的方式获取数据,满足更多需求
        此方法将take的大小扩展到尽可能大(而不仅限于100),主要用于获取全部域名中的前take个域名

        Args:
            take (int, optional): 表示最多获取的域名数量.此值为0时表示尽可能多获取
            skip (int, optional): 跳过数量.
            order_by (str, optional): 排序字段. Defaults to "expirationDate".
            # get_all (bool, optional): 是否返回尽可能多的数据. Defaults to False.

        Returns:
            { "items": [...],"total": ...}
            返回的json包含两个子对象
        """
        all_domains = []
        # if get_all:
        # 获取全部域名
        # 配置单次请求默认参数
        skip_in_fetch = 0
        take_per_fetch = 100
        # 循环调用list_domains直到所有域名被获取
        while True:
            resp = self._list_domains(take_per_fetch, skip_in_fetch, order_by)

            if not resp or "items" not in resp:
                break
            if isinstance(resp, dict):
                items = resp.get("items", [])
            else:
                items = []

            # 如果本轮获取的域名数组(items)非空,则添加到总的items中
            all_domains.extend(items)

            # print(len(items), "🎈", items)
            # 确定下一轮要请求要跳过多少个(已经请求过的)域名(或者从第几个域名后开始新一轮的请求)
            skip_in_fetch += len(items)

            # 如果累计获取的户名的总数已经不少于需要的数量(take),也可以离开循环
            if take and (len(all_domains) >= take + skip):
                break
            # 如果本轮获取的域名数量小于指定数量,则说明本轮是最后一轮请求,可以离开并结束循环;
            if len(items) < take_per_fetch:
                break
        # 截取需要的数量(跳过前skip个)
        all_domains = all_domains[-take:]
        # 将获取的数据构造成规定的格式
        result = {"items": all_domains, "total": len(all_domains)}
        # else:
        #     result = self._list_domains(take, skip, order_by)

        return result

    def list_domains_names_only(self, take=10, skip=0, order_by="expirationDate"):
        """列出域名列表，只输出域名
        Args:
            take (int, optional): 获取的域名数量. Defaults to 10.
            skip (int, optional): 跳过数量. Defaults to 0.
        Returns:
            list: 域名列表
        """
        domains = self.list_domains(take=take, skip=skip, order_by=order_by)
        names = []
        if "items" in domains:
            if isinstance(domains, dict):
                domains_info = domains.get("items", [])
                for domain in domains_info:
                    # print(name)
                    names.append(domain.get("name", ""))
            else:
                print(type(names))
        return names

    # def list_suspended_domains(self, config=None, output=""):
    #     """检查当前账号中的域名哪些被停用,比如被怀疑滥用(abuse)

    #     如果要检查全部配置文件中有配置的账号的域名是否被停用
    #     首先调用list_domains_from_all_accounts获取所有账号的域名列表,然后遍历查找

    #     """
    #     if not config:  # 如果没有配置,则默认检查当前账号
    #         domains = self.list_domains(take=0)
    #         if "items" in domains:
    #             for domain in domains["items"]:
    #                 if domain.get("suspensions", ""):
    #                     self.suspended_domains.append(domain)
    #     else:  # 如果有配置,则检查配置文件中所有账号的域名是否被停用
    #         domains_in_all_accounts = self.list_domains_from_all_accounts(
    #             config, "", names_only=False
    #         )
    #         for account in domains_in_all_accounts:
    #             for domain in account["domains"]["items"]:
    #                 if domain.get("suspensions", ""):
    #                     self.suspended_domains.append(domain)
    #     # 处理计算结果:self.suspended_domains
    #     if output:
    #         with open(output, "w", encoding="utf-8") as f:
    #             json.dump(self.suspended_domains, f, ensure_ascii=False, indent=2)
    #     return self.suspended_domains
    def list_suspended_domains(self, mode="current", config=None, output=""):
        """检查域名被停用情况
        Args:
            mode (str): 'current' 检查当前账号, 'all' 检查所有账号
            config (dict): 配置,仅'all'时需要
            output (str): 输出文件路径,为空则仅输出到屏幕
        """
        self.suspended_domains = []
        if mode == "current":
            domains = self.list_domains(take=0)
            if "items" in domains:
                for domain in domains["items"]:
                    if domain.get("suspensions", ""):
                        self.suspended_domains.append(domain)
        elif mode == "all":
            if config:
                domains_in_all_accounts = self.list_domains_from_all_accounts(
                    config, "", names_only=False
                )
                for account in domains_in_all_accounts:
                    for domain in account["domains"]["items"]:
                        if domain.get("suspensions", ""):
                            item = {"account": account["account"], "domain": domain}
                            self.suspended_domains.append(item)
            else:
                print("未提供 config，无法检查所有账号", file=sys.stderr)
        else:
            print("mode 参数必须为 'current' 或 'all'", file=sys.stderr)
            return []

        if output:
            print(f"被停用的域名信息文件将被保存到{output}")
            with open(output, "w", encoding="utf-8") as f:
                json.dump(self.suspended_domains, f, ensure_ascii=False, indent=2)
        return self.suspended_domains

    def list_domains_from_all_accounts(self, config, output, names_only=False):
        """从配置文件中读取所有账号信息,并发获取各个账号中的全部域名列表(只获取域名名字)"""
        if output:
            print(f"文件将被保存到{output}")

        accounts = config.get("accounts", [])
        results = []

        def fetch_domains(account):
            """获取指定账号的域名列表
            内部会创建临时的APIClient对象,防止线程间覆盖self.api_key/secret
            Args:
                account (dict): 账号信息
            Returns:
                dict: 包含账号名称和域名列表统计信息的字典
            """
            account_name = account.get("account", "")
            api_key = account.get("api_key", "")
            api_secret = account.get("api_secret", "")
            print(
                f"正在获取{account_name},信息{api_key, api_secret}账号中的域名列表..."
            )
            # 创建临时client防止线程间覆盖self.api_key/secret
            client = APIClient(api_key, api_secret)
            if names_only:
                domains = client.list_domains_names_only(take=0, skip=0)
            else:
                domains = client.list_domains(take=0, skip=0)
            print(f"\t完成{account_name}账号域名列表的获取")
            # 返回指定格式的字典
            return {"account": account_name, "domains": domains, "total": len(domains)}

        with ThreadPoolExecutor(max_workers=min(8, len(accounts))) as executor:
            futures = [executor.submit(fetch_domains, account) for account in accounts]
            for future in as_completed(futures):
                results.append(future.result())

        self.domains_in_all_accounts = results
        # 根据需要尝试写入结果到文件
        if output:
            with open(output, "w", encoding="utf-8") as f:
                json.dump(self.domains_in_all_accounts, f, ensure_ascii=False, indent=2)
        return self.domains_in_all_accounts

    def get_domain(self, domain):
        """查询域名详情"""
        return self._request("GET", f"/domains/{domain}")

    def get_nameservers(self, domain):
        """获取域名的nameservers信息
        返回: nameservers对象（dict或list），未找到时返回None
        """
        domain_info = self._request("GET", f"/domains/{domain}")
        if (
            domain_info
            and isinstance(domain_info, dict)
            and "nameservers" in domain_info
        ):
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
    """加载配置文件
    注意,使用get_auth获取更加完整的逻辑
    """
    if not os.path.exists(config_path):
        return {}
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


# def get_auth(args, config):
#     """获取API认证信息"""
#     return {
#         "api_key": args.api_key or config.get("api_key"),
#         "api_secret": args.api_secret or config.get("api_secret"),
#     }
def get_auth(config_path, args=None):
    """加载配置
    读取配置文件和环境变量中相关值

    Args:
        config_path (str): 配置文件路径
    Returns:
        dict: 配置信息

    key,secret优先级按照以下顺序(高优先级的值会覆盖低优先级的配置中对应的字段值):

    0. 命令行参数 - 最高优先级
    1. 环境变量 - 优先级
    2. 配置文件 - 默认值
    3. 程序默认值（如果有）

    """

    key, secret = "", ""
    # 从json配置文件中读取鉴权配置
    with open(config_path, "r", encoding="utf-8") as f:
        config = json.load(f)
    if args and getattr(args, "list_accounts", None):
        # 列出配置文件中的账号信息
        accounts = config.get("accounts", {})
        for i, account in enumerate(accounts, start=1):
            name = account.get("account")
            print(f"{i}. {name}")
        exit(0)
    # 根据arg.account参数来决定是否进入选择模式
    if args and args.account:
        # 读取配置文件中的账号信息
        # 列出配置文件中的账号

        accounts = config.get("accounts", {})
        names = []
        for i, account in enumerate(accounts, start=1):
            name = account.get("account")
            names.append(name)
            print(f"{i}. {name}")
            # account.
        # 选择账号
        if args.account in names:
            account_name_idx = names.index(args.account) + 1
        else:
            account_name_idx = input(f"请输入选择的账号(1-{len(accounts)}): ")
            account_name_idx = int(account_name_idx)
        if account_name_idx < 1 or account_name_idx > len(accounts):
            print("无效的账号选择")
            sys.exit(1)
        else:
            account = accounts[account_name_idx - 1]
            key = account.get("api_key")
            secret = account.get("api_secret")
            print(f"选择的账号: {account_name_idx} - {account['account']} 🎈")
    # 如果环境变量中配置了SP_KEY和SP_SECRET,则使用环境变量的值,否则使用配置文件中的值
    key_env = os.environ.get("SP_KEY")
    secret_env = os.environ.get("SP_SECRET")
    if key_env and secret_env:
        key = key_env
        secret = secret_env

    # 最高优先级的命令行参数
    if args:
        if hasattr(args, "api_key") and hasattr(args, "api_secret"):
            if args.api_key and args.api_secret:
                key = args.api_key
                secret = args.api_secret

    # 确定最终使用的key和secret
    if key and secret:
        config["api_key"] = key
        config["api_secret"] = secret
    # print(f"API Key: {key},API Secret: {secret}")

    return config or {}


def parse_args():
    """解析命令行参数"""
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
        default=DEFAULT_CONFIG_PATH,
        # default="spaceship_config.json",
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
        "--all", action="store_true", help="列出全部域名（不与take参数同时使用）"
    )
    parser_list_domains.add_argument(
        "--from_all_accounts",
        # action="store_true",
        required=False,
        default="",
        help="列出所有账号中的域名,指定值作为输出文件名,缺省则输出到屏幕,内容过长可能会显示不全!",
    )
    parser_list_domains.add_argument(
        "--list_suspended_domains",
        nargs="+",
        default=[],
        help="列出被停用的域名: current|all [输出文件路径]",
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
    # 多账户管理
    parser.add_argument(
        "-a",
        "--account",
        type=str,
        default="",
        help="指定SpaceShip账号(用户名),默认置空时则读取默认密钥组",
    )
    parser.add_argument(
        "--list-accounts",
        action="store_true",
        help="列出配置文件中的账号,并退出",
    )
    return parser.parse_args()


def main():
    """主函数,主要负责命令行参数解析和API客户端初始化和调用"""
    args = parse_args()
    # config = load_config(args.config)
    # auth = get_auth(args, config)
    auth = get_auth(args.config, args)
    if not auth["api_key"] or not auth["api_secret"]:
        print("API Key 和 Secret 必须指定 (命令行或配置文件)", file=sys.stderr)
        sys.exit(1)
    client = APIClient(auth["api_key"], auth["api_secret"])
    if args.command == "list-domains":
        if getattr(args, "all", False):
            # 获取当前账号下的尽可能多的域名
            result = client.list_domains(take=0, skip=args.skip, order_by=args.order_by)
            # print(result,'🎈')

        if getattr(args, "names_only", False):
            # 只输出域名，每行一个(与上一步相关联)
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
        if getattr(args, "from_all_accounts", False):
            # 列出所有账号中的域名
            result = client.list_domains_from_all_accounts(auth, args.from_all_accounts)
            print(result)
            return
            # 将导出的字典数据存储成json文件
        if (
            getattr(args, "list_suspended_domains", None)
            and len(args.list_suspended_domains) > 0
        ):
            mode = (
                args.list_suspended_domains[0]
                if args.list_suspended_domains[0] in ["current", "all"]
                else "current"
            )
            output = (
                args.list_suspended_domains[1]
                if len(args.list_suspended_domains) > 1
                else ""
            )
            if mode == "all":
                result = client.list_suspended_domains(
                    mode="all", config=auth, output=output
                )
            else:
                result = client.list_suspended_domains(mode="current", output=output)
            if not output:
                print(json.dumps(result, ensure_ascii=False, indent=2))
            return
        else:
            # 所有选项分支都没有命中时,执行默认操作
            result = client.list_domains(args.take, args.skip, args.order_by)
            # print(json.dumps(result, ensure_ascii=False, indent=2))
            print(result)  # 打印未格式还的json
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
