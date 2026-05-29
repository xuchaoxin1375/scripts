#!/usr/bin/env python3
"""
Cloudflare DNS 批量修改/查询工具

能力：
1. 批量更新账号下 DNS 记录（支持白名单、old-ip 过滤、dry-run）
2. 多账号并发处理（账号级并发）
3. 快速查询某个域名存在于哪些账号（--find-domain）
"""

import argparse
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from threading import Event, Lock, local as thread_local
from typing import Optional

import requests

VERSION="20260529"
# ============ 配置区 ============
# 方式一：使用 API Token（推荐）
CF_API_TOKEN = "your_api_token_here"

# 使用哪种认证方式：'token' 或 'key'
AUTH_METHOD = "token"
# ================================

DESKTOP = r"C:/Users/Administrator/Desktop"
DEPLOY_CONFIGS = f"{DESKTOP}/deploy_configs"
CF_CONFIG_PATH = f"{DEPLOY_CONFIGS}/cf_config.json"


@dataclass
class UpdateResult:
    domain: str
    old_ip: str
    new_ip: str
    status: str  # updated / dry_run / skipped / error
    message: str = ""


@dataclass
class UpdateStats:
    updated: int = 0
    skipped: int = 0
    errors: int = 0
    _lock: Lock = field(default_factory=Lock, repr=False)

    def inc_updated(self) -> None:
        with self._lock:
            self.updated += 1

    def inc_skipped(self) -> None:
        with self._lock:
            self.skipped += 1

    def inc_errors(self) -> None:
        with self._lock:
            self.errors += 1


class CloudflareDNSUpdater:
    BASE_URL = "https://api.cloudflare.com/client/v4"

    def __init__(
        self,
        auth_method: str,
        api_token: Optional[str] = None,
        api_email: Optional[str] = None,
        api_key: Optional[str] = None,
        max_workers: int = 5,
        print_lock: Optional[Lock] = None,
        stop_event: Optional[Event] = None,
    ):
        self.max_workers = max_workers
        self._print_lock = print_lock or Lock()
        self._stop_event = stop_event or Event()
        self._thread_local = thread_local()

        if auth_method == "token":
            if not api_token:
                raise ValueError("API Token 不能为空")
            self._headers = {
                "Authorization": f"Bearer {api_token}",
                "Content-Type": "application/json",
            }
        elif auth_method == "key":
            if not api_email or not api_key:
                raise ValueError("API Email 和 API Key 不能为空")
            self._headers = {
                "X-Auth-Email": api_email,
                "X-Auth-Key": api_key,
                "Content-Type": "application/json",
            }
        else:
            raise ValueError("auth_method 仅支持 token 或 key")

    def _get_session(self) -> requests.Session:
        session = getattr(self._thread_local, "session", None)
        if session is None:
            session = requests.Session()
            session.headers.update(self._headers)
            self._thread_local.session = session
        return session

    def _safe_print(self, *args, **kwargs) -> None:
        with self._print_lock:
            print(*args, **kwargs)

    def _should_stop(self) -> bool:
        return self._stop_event.is_set()

    def _check_stop(self) -> None:
        if self._should_stop():
            raise KeyboardInterrupt

    def _request(self, method: str, endpoint: str, **kwargs):
        self._check_stop()
        url = f"{self.BASE_URL}{endpoint}"
        resp = self._get_session().request(method, url, timeout=30, **kwargs)
        data = resp.json()
        if not data.get("success"):
            raise Exception(f"API 请求失败: {data.get('errors', [])}")
        return data

    def zone_exists(self, domain: str) -> bool:
        """快速检查某域名是否存在于当前账号。"""
        target = domain.strip().lower()
        data = self._request(
            "GET",
            "/zones",
            params={"name": target, "page": 1, "per_page": 1, "status": "active"},
        )
        for z in data.get("result", []):
            if z.get("name", "").lower() == target:
                return True
        return False

    def get_all_zones(self) -> list:
        zones = []
        page = 1
        while True:
            self._check_stop()
            data = self._request("GET", "/zones", params={"page": page, "per_page": 50})
            zones.extend(data["result"])
            total_pages = data["result_info"]["total_pages"]
            if page >= total_pages:
                break
            page += 1
            time.sleep(0.2)
        return zones

    def get_dns_records(self, zone_id: str, record_type: str = "A") -> list:
        records = []
        page = 1
        while True:
            self._check_stop()
            data = self._request(
                "GET",
                f"/zones/{zone_id}/dns_records",
                params={"type": record_type, "page": page, "per_page": 100},
            )
            records.extend(data["result"])
            total_pages = data["result_info"]["total_pages"]
            if page >= total_pages:
                break
            page += 1
            time.sleep(0.1)
        return records

    def update_dns_record(
        self,
        zone_id: str,
        record_id: str,
        record_name: str,
        new_ip: str,
        proxied: bool,
        ttl: int,
        record_type: str = "A",
    ) -> dict:
        payload = {
            "type": record_type,
            "name": record_name,
            "content": new_ip,
            "proxied": proxied,
            "ttl": ttl,
        }
        return self._request("PUT", f"/zones/{zone_id}/dns_records/{record_id}", json=payload)

    def _process_zone(
        self,
        zone: dict,
        new_ip: str,
        old_ip: Optional[str],
        record_type: str,
        dry_run: bool,
        include_subdomains: bool,
        whitelist: Optional[set],
        stats: UpdateStats,
    ) -> list[UpdateResult]:
        zone_name = zone["name"]
        zone_id = zone["id"]
        results: list[UpdateResult] = []

        self._safe_print(f"\n[zone] 开始处理: {zone_name}")

        try:
            records = self.get_dns_records(zone_id, record_type)
        except KeyboardInterrupt:
            return results
        except Exception as e:
            self._safe_print(f"  [zone] 获取记录失败: {e}")
            stats.inc_errors()
            return results

        if not records:
            return results

        for record in records:
            if self._should_stop():
                return results
            r_name = record["name"]
            r_content = record["content"]
            r_id = record["id"]
            r_proxied = record["proxied"]
            r_ttl = record["ttl"]

            if whitelist and not include_subdomains and r_name.lower() != zone_name.lower():
                continue

            if old_ip and r_content != old_ip:
                stats.inc_skipped()
                continue

            if r_content == new_ip:
                stats.inc_skipped()
                continue

            if dry_run:
                self._safe_print(f"  [DRY] {r_name}: {r_content} -> {new_ip}")
                stats.inc_updated()
                results.append(UpdateResult(r_name, r_content, new_ip, "dry_run"))
            else:
                try:
                    self.update_dns_record(zone_id, r_id, r_name, new_ip, r_proxied, r_ttl, record_type)
                    self._safe_print(f"  [OK] {r_name}: {r_content} -> {new_ip}")
                    stats.inc_updated()
                    results.append(UpdateResult(r_name, r_content, new_ip, "updated"))
                    time.sleep(0.1)
                except Exception as e:
                    self._safe_print(f"  [ERR] {r_name}: {e}")
                    stats.inc_errors()
                    results.append(UpdateResult(r_name, r_content, new_ip, "error", str(e)))

        return results

    def batch_update(
        self,
        new_ip: str,
        old_ip: Optional[str] = None,
        whitelist: Optional[list[str]] = None,
        record_type: str = "A",
        dry_run: bool = False,
        include_subdomains: bool = True,
    ) -> list[UpdateResult]:
        self._check_stop()
        self._safe_print("=" * 60)
        self._safe_print("Cloudflare DNS 批量更新")
        self._safe_print(f"new_ip={new_ip}, type={record_type}, workers={self.max_workers}, dry_run={dry_run}")
        self._safe_print("=" * 60)

        all_zones = self.get_all_zones()
        self._safe_print(f"账号下共 {len(all_zones)} 个域名")

        whitelist_set: Optional[set[str]] = None
        if whitelist:
            whitelist_set = {d.lower().strip() for d in whitelist}
            zones = [z for z in all_zones if z["name"].lower() in whitelist_set]
            self._safe_print(f"白名单匹配到 {len(zones)} 个域名")
        else:
            zones = all_zones

        if not zones:
            self._safe_print("没有需要处理的域名")
            return []

        stats = UpdateStats()
        all_results: list[UpdateResult] = []

        executor = ThreadPoolExecutor(max_workers=self.max_workers)
        try:
            future_to_zone = {
                executor.submit(
                    self._process_zone,
                    zone,
                    new_ip,
                    old_ip,
                    record_type,
                    dry_run,
                    include_subdomains,
                    whitelist_set,
                    stats,
                ): zone
                for zone in zones
            }

            for future in as_completed(future_to_zone):
                if self._should_stop():
                    break
                zone = future_to_zone[future]
                try:
                    all_results.extend(future.result())
                except KeyboardInterrupt:
                    self._stop_event.set()
                    break
                except Exception as e:
                    self._safe_print(f"[zone-error] {zone['name']}: {e}")
                    stats.inc_errors()
        except KeyboardInterrupt:
            self._stop_event.set()
            self._safe_print("\n[INTERRUPT] 收到 Ctrl+C，正在停止当前账号任务...")
        finally:
            executor.shutdown(wait=False, cancel_futures=True)

        self._safe_print("\n" + "=" * 60)
        self._safe_print(f"完成: success={stats.updated}, skipped={stats.skipped}, errors={stats.errors}")
        self._safe_print("=" * 60)
        return all_results


def load_whitelist(filepath: str) -> list[str]:
    domains: list[str] = []
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    domains.append(line.lower())
    except FileNotFoundError:
        print(f"白名单文件不存在: {filepath}")
        sys.exit(1)
    return domains


def load_config(config_path: str) -> dict:
    if not os.path.exists(config_path):
        print(f"{config_path} 文件不存在")
        sys.exit(1)
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f) or {}


def get_cf_accounts(config_path: str) -> list[dict]:
    """
    从约定配置读取账号。
    支持字段：
      - cf_api_email + cf_api_key
      - cf_api_token
    """
    cf_config = load_config(config_path)
    accs = cf_config.get("accounts", {})
    accounts: list[dict] = []
    for name, acc_obj in accs.items():
        token = acc_obj.get("cf_api_token")
        email = acc_obj.get("cf_api_email")
        key = acc_obj.get("cf_api_key")
        if token:
            accounts.append({"name": name, "auth_method": "token", "token": token, "email": None, "key": None})
        elif email and key:
            accounts.append({"name": name, "auth_method": "key", "token": None, "email": email, "key": key})
    return accounts


def parse_args():
    parser = argparse.ArgumentParser(
        description="Cloudflare DNS 批量修改工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--new-ip", help="新的目标 IP 地址（更新模式必填）")
    parser.add_argument("--old-ip", default=None, help="旧 IP 地址（只修改匹配记录）")
    parser.add_argument("--whitelist", default=None, help="域名白名单文件路径（每行一个）")
    parser.add_argument("--record-type", default="A", choices=["A", "AAAA", "CNAME"], help="DNS 记录类型")
    parser.add_argument("--dry-run", action="store_true", help="预览模式")
    parser.add_argument("--no-subdomains", action="store_true", help="白名单模式下只修改根域名")
    parser.add_argument("--workers", type=int, default=5, metavar="N", help="单账号内 zone 并发数（默认 5）")

    # 新增：账号级并发
    parser.add_argument("--account-workers", type=int, default=3, metavar="N", help="多账号并发数（默认 3）")

    parser.add_argument("--token", default=None, help="Cloudflare API Token")
    parser.add_argument("--email", default=None, help="Cloudflare 账号邮箱（配合 --api-key）")
    parser.add_argument("--api-key", default=None, help="Cloudflare Global API Key")
    parser.add_argument("--config", default=None, help="账号配置文件路径（多账号）")

    # 新增：快速查域名模式
    parser.add_argument("--find-domain", default=None, help="快速查找某个域名是否存在于账号中")
    return parser.parse_args()


def build_accounts(args) -> list[dict]:
    if args.config:
        accounts = get_cf_accounts(args.config)
        if not accounts:
            print("配置文件中没有可用账号")
            sys.exit(1)
        return accounts

    if args.token:
        return [{"name": "cli-account", "auth_method": "token", "token": args.token, "email": None, "key": None}]

    if args.email and args.api_key:
        return [{"name": args.email, "auth_method": "key", "token": None, "email": args.email, "key": args.api_key}]

    if AUTH_METHOD == "token" and CF_API_TOKEN != "your_api_token_here":
        return [{"name": "default-token-account", "auth_method": "token", "token": CF_API_TOKEN, "email": None, "key": None}]

    print("请提供认证信息：--token 或 --email + --api-key，或 --config")
    sys.exit(1)


def run_find_mode(
    accounts: list[dict],
    domain: str,
    account_workers: int,
    zone_workers: int,
    stop_event: Event,
) -> int:
    print_lock = Lock()

    def _find_one(account: dict) -> tuple[str, bool, str]:
        name = account.get("name") or account.get("email") or "unknown"
        try:
            updater = CloudflareDNSUpdater(
                auth_method=account["auth_method"],
                api_token=account.get("token"),
                api_email=account.get("email"),
                api_key=account.get("key"),
                max_workers=zone_workers,
                print_lock=print_lock,
                stop_event=stop_event,
            )
            exists = updater.zone_exists(domain)
            return name, exists, ""
        except KeyboardInterrupt:
            return name, False, "interrupted"
        except Exception as e:
            return name, False, str(e)

    print(f"快速查找域名: {domain}")
    found_accounts: list[str] = []

    executor = ThreadPoolExecutor(max_workers=max(1, account_workers))
    try:
        futures = [executor.submit(_find_one, account) for account in accounts]
        for future in as_completed(futures):
            if stop_event.is_set():
                break
            name, exists, err = future.result()
            if err:
                if err == "interrupted":
                    continue
                print(f"[ERR] {name}: {err}")
                continue
            if exists:
                found_accounts.append(name)
                print(f"[FOUND] {name}")
            else:
                print(f"[MISS]  {name}")
    except KeyboardInterrupt:
        stop_event.set()
        print("\n[INTERRUPT] 收到 Ctrl+C，正在停止查询...")
    finally:
        executor.shutdown(wait=False, cancel_futures=True)

    if stop_event.is_set():
        return 130

    print("\n查询结果:")
    if found_accounts:
        for name in found_accounts:
            print(f"- {name}")
        return 0
    print("- 未在任何账号中找到")
    return 2


def run_update_for_account(
    account: dict,
    args,
    whitelist: Optional[list[str]],
    print_lock: Lock,
    stop_event: Event,
) -> tuple[str, bool, str]:
    name = account.get("name") or account.get("email") or "unknown"
    try:
        updater = CloudflareDNSUpdater(
            auth_method=account["auth_method"],
            api_token=account.get("token"),
            api_email=account.get("email"),
            api_key=account.get("key"),
            max_workers=args.workers,
            print_lock=print_lock,
            stop_event=stop_event,
        )
        updater._safe_print(f"\n=== 开始处理账号: {name} ===")
        updater.batch_update(
            new_ip=args.new_ip,
            old_ip=args.old_ip,
            whitelist=whitelist,
            record_type=args.record_type,
            dry_run=args.dry_run,
            include_subdomains=not args.no_subdomains,
        )
        if stop_event.is_set():
            return name, False, "interrupted"
        return name, True, ""
    except KeyboardInterrupt:
        return name, False, "interrupted"
    except Exception as e:
        return name, False, str(e)


def main() -> None:
    args = parse_args()
    stop_event = Event()

    if args.workers < 1:
        print("--workers 至少为 1")
        sys.exit(1)
    if args.workers > 20:
        print("线程数过高，已自动调整为 20")
        args.workers = 20

    if args.account_workers < 1:
        print("--account-workers 至少为 1")
        sys.exit(1)
    if args.account_workers > 20:
        print("账号并发数过高，已自动调整为 20")
        args.account_workers = 20

    accounts = build_accounts(args)

    # 模式1：快速查域名
    if args.find_domain:
        code = run_find_mode(accounts, args.find_domain, args.account_workers, args.workers, stop_event)
        sys.exit(code)

    # 模式2：批量更新
    if not args.new_ip:
        print("更新模式下必须提供 --new-ip")
        sys.exit(1)

    whitelist: Optional[list[str]] = None
    if args.whitelist:
        whitelist = load_whitelist(args.whitelist)
        if not whitelist:
            print("白名单文件为空")
            sys.exit(1)
        print(f"已加载白名单: {len(whitelist)}")

    print_lock = Lock()
    success = 0
    failed = 0
    executor = ThreadPoolExecutor(max_workers=args.account_workers)
    try:
        futures = [
            executor.submit(run_update_for_account, account, args, whitelist, print_lock, stop_event)
            for account in accounts
        ]
        for future in as_completed(futures):
            if stop_event.is_set():
                break
            name, ok, err = future.result()
            if ok:
                success += 1
                print(f"[ACCOUNT-OK] {name}")
            else:
                if err == "interrupted":
                    continue
                failed += 1
                print(f"[ACCOUNT-ERR] {name}: {err}")
    except KeyboardInterrupt:
        stop_event.set()
        print("\n[INTERRUPT] 收到 Ctrl+C，正在终止所有线程...")
    finally:
        executor.shutdown(wait=False, cancel_futures=True)

    if stop_event.is_set():
        print("任务已被用户中断")
        sys.exit(130)

    print("\n账号汇总:")
    print(f"- 成功: {success}")
    print(f"- 失败: {failed}")
    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()