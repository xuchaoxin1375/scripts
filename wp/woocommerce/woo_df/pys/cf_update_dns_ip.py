#!/usr/bin/env python3
"""
Cloudflare 批量修改 DNS A 记录脚本
功能：
  1. 修改整个账号下所有域名的 DNS A 记录
  2. 通过白名单文件指定要修改的域名
  3. 支持 dry-run 模式预览变更
  4. 支持按旧 IP 过滤（只修改特定旧 IP 的记录）
  5. 支持多线程并发加速
"""

import requests
import argparse
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock, local as thread_local
from dataclasses import dataclass, field
from typing import Optional

# ============ 配置区 ============
# 方式一：使用 API Token（推荐，权限最小化）
# 创建方式：Cloudflare Dashboard -> My Profile -> API Tokens -> Create Token
# 所需权限：Zone:Zone:Read + Zone:DNS:Edit
CF_API_TOKEN = "your_api_token_here"

# 方式二：使用 Global API Key（不推荐，但方便）
# CF_API_EMAIL = "your_email@example.com"
# CF_API_KEY = "your_global_api_key_here"

# 使用哪种认证方式：'token' 或 'key'
AUTH_METHOD = "token"
# ================================


@dataclass
class UpdateResult:
    """单条记录的更新结果"""
    domain: str
    old_ip: str
    new_ip: str
    status: str  # 'updated', 'dry_run', 'skipped', 'error'
    message: str = ""


@dataclass
class UpdateStats:
    """线程安全的统计计数器"""
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
        auth_method: str = "token",
        api_token: Optional[str] = None,
        api_email: Optional[str] = None,
        api_key: Optional[str] = None,
        max_workers: int = 5,
    ):
        self.max_workers = max_workers
        self._print_lock = Lock()
        self._thread_local = thread_local()

        # 构建通用 headers
        if auth_method == "token":
            if not api_token:
                raise ValueError("API Token 不能为空")
            self._headers = {
                "Authorization": f"Bearer {api_token}",
                "Content-Type": "application/json",
            }
        else:
            if not api_email or not api_key:
                raise ValueError("API Email 和 API Key 不能为空")
            self._headers = {
                "X-Auth-Email": api_email,
                "X-Auth-Key": api_key,
                "Content-Type": "application/json",
            }

    def _get_session(self) -> requests.Session:
        """每个线程使用独立的 Session（连接池隔离）"""
        session = getattr(self._thread_local, "session", None)
        if session is None:
            session = requests.Session()
            session.headers.update(self._headers)
            self._thread_local.session = session
        return session

    def _safe_print(self, *args, **kwargs) -> None:
        """线程安全的打印"""
        with self._print_lock:
            print(*args, **kwargs)

    def _request(self, method: str, endpoint: str, **kwargs):
        """发送请求并处理错误"""
        url = f"{self.BASE_URL}{endpoint}"
        session = self._get_session()
        resp = session.request(method, url, **kwargs)
        data = resp.json()
        if not data.get("success"):
            errors = data.get("errors", [])
            raise Exception(f"API 请求失败: {errors}")
        return data

    def get_all_zones(self) -> list:
        """获取账号下所有域名（zone），自动分页"""
        zones = []
        page = 1
        while True:
            data = self._request("GET", "/zones", params={"page": page, "per_page": 50})
            zones.extend(data["result"])
            total_pages = data["result_info"]["total_pages"]
            if page >= total_pages:
                break
            page += 1
            time.sleep(0.2)
        return zones

    def get_dns_records(self, zone_id: str, record_type: str = "A") -> list:
        """获取指定 zone 的所有 DNS 记录"""
        records = []
        page = 1
        while True:
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
        """更新单条 DNS 记录"""
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
        """处理单个 zone 的所有记录（在线程中运行）"""
        zone_name = zone["name"]
        zone_id = zone["id"]
        results: list[UpdateResult] = []

        self._safe_print(f"\n🌐 处理域名: {zone_name}")

        try:
            records = self.get_dns_records(zone_id, record_type)
        except Exception as e:
            self._safe_print(f"   ❌ 获取记录失败: {e}")
            stats.inc_errors()
            return results

        if not records:
            self._safe_print(f"   (无 {record_type} 记录)")
            return results

        for record in records:
            r_name = record["name"]
            r_content = record["content"]
            r_id = record["id"]
            r_proxied = record["proxied"]
            r_ttl = record["ttl"]

            # 白名单 + 不包含子域名时，只修改根域名记录
            if whitelist and not include_subdomains:
                if r_name.lower() != zone_name.lower():
                    continue

            # 旧 IP 过滤
            if old_ip and r_content != old_ip:
                stats.inc_skipped()
                continue

            # 新旧 IP 相同则跳过
            if r_content == new_ip:
                self._safe_print(f"   ⏭️  {r_name} -> 已经是 {new_ip}，跳过")
                stats.inc_skipped()
                continue

            # 执行更新
            if dry_run:
                self._safe_print(
                    f"   🔍 [DRY RUN] {r_name}: {r_content} -> {new_ip} "
                    f"(proxied={r_proxied})"
                )
                stats.inc_updated()
                results.append(UpdateResult(r_name, r_content, new_ip, "dry_run"))
            else:
                try:
                    self.update_dns_record(
                        zone_id, r_id, r_name, new_ip, r_proxied, r_ttl, record_type
                    )
                    self._safe_print(f"   ✅ {r_name}: {r_content} -> {new_ip}")
                    stats.inc_updated()
                    results.append(UpdateResult(r_name, r_content, new_ip, "updated"))
                    time.sleep(0.1)
                except Exception as e:
                    self._safe_print(f"   ❌ {r_name}: 更新失败 - {e}")
                    stats.inc_errors()
                    results.append(
                        UpdateResult(r_name, r_content, new_ip, "error", str(e))
                    )

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
        """
        批量更新 DNS 记录

        参数：
            new_ip: 新的目标 IP
            old_ip: 可选，只修改指向该旧 IP 的记录
            whitelist: 可选，域名白名单列表
            record_type: 记录类型，默认 A
            dry_run: 预览模式，不实际修改
            include_subdomains: 白名单模式下是否包含子域名
        """
        print("=" * 70)
        print("🚀 Cloudflare DNS 批量更新工具")
        print(f"   新 IP: {new_ip}")
        if old_ip:
            print(f"   旧 IP 过滤: {old_ip}")
        if whitelist:
            print(f"   白名单域名数: {len(whitelist)}")
        print(f"   记录类型: {record_type}")
        print(f"   并发线程数: {self.max_workers}")
        print(f"   模式: {'🔍 预览 (DRY RUN)' if dry_run else '⚡ 实际执行'}")
        print("=" * 70)

        # 获取所有 zone
        print("\n📋 获取域名列表...")
        all_zones = self.get_all_zones()
        print(f"   账号下共 {len(all_zones)} 个域名")

        # 白名单过滤
        whitelist_set: Optional[set[str]] = None
        if whitelist:
            whitelist_set = {d.lower().strip() for d in whitelist}
            zones = [z for z in all_zones if z["name"].lower() in whitelist_set]
            print(f"   白名单匹配到 {len(zones)} 个域名")

            matched = {z["name"].lower() for z in zones}
            unmatched = whitelist_set - matched
            if unmatched:
                print("   ⚠️  以下白名单域名未在账号中找到:")
                for d in sorted(unmatched):
                    print(f"      - {d}")
        else:
            zones = all_zones

        if not zones:
            print("\n❌ 没有需要处理的域名")
            return []

        stats = UpdateStats()
        all_results: list[UpdateResult] = []

        # 多线程处理各 zone
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
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
                zone = future_to_zone[future]
                try:
                    results = future.result()
                    all_results.extend(results)
                except Exception as e:
                    self._safe_print(f"   ❌ 域名 {zone['name']} 处理异常: {e}")
                    stats.inc_errors()

        # 汇总报告
        print("\n" + "=" * 70)
        print("📊 执行报告")
        print(f"   {'预览' if dry_run else '更新'}成功: {stats.updated}")
        print(f"   跳过: {stats.skipped}")
        print(f"   失败: {stats.errors}")
        print("=" * 70)

        if dry_run and stats.updated > 0:
            print("\n💡 这是预览模式。确认无误后，去掉 --dry-run 参数再次执行。")

        return all_results


def load_whitelist(filepath: str) -> list[str]:
    """从文件加载域名白名单"""
    domains: list[str] = []
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    domains.append(line.lower())
    except FileNotFoundError:
        print(f"❌ 白名单文件不存在: {filepath}")
        sys.exit(1)
    return domains


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Cloudflare DNS 批量修改工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  # 预览：修改账号下所有域名的 A 记录到新 IP
  python cf_dns_batch.py --new-ip 1.2.3.4 --dry-run

  # 执行：只修改旧 IP 为 5.6.7.8 的记录
  python cf_dns_batch.py --new-ip 1.2.3.4 --old-ip 5.6.7.8

  # 使用白名单文件
  python cf_dns_batch.py --new-ip 1.2.3.4 --whitelist domains.txt --dry-run

  # 指定 8 个线程并发
  python cf_dns_batch.py --new-ip 1.2.3.4 --old-ip 5.6.7.8 --workers 8

  # 通过命令行传入 token
  python cf_dns_batch.py --new-ip 1.2.3.4 --token YOUR_API_TOKEN
  
  # 通过命令行传入 api key 和 email组合
   python cf_update_dns_ip.py --api-key key_string --email your_email  --new-ip new_ip --whitelist whitelist.txt 
        """,
    )
    parser.add_argument("--new-ip", required=True, help="新的目标 IP 地址")
    parser.add_argument("--old-ip", default=None, help="旧 IP 地址（只修改匹配的记录）")
    parser.add_argument("--whitelist", default=None, help="域名白名单文件路径（每行一个域名）")
    parser.add_argument(
        "--record-type",
        default="A",
        choices=["A", "AAAA", "CNAME"],
        help="DNS 记录类型（默认 A）",
    )
    parser.add_argument("--dry-run", action="store_true", help="预览模式，不实际修改")
    parser.add_argument(
        "--no-subdomains",
        action="store_true",
        help="白名单模式下只修改根域名，不包含子域名",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=5,
        metavar="N",
        help="并发线程数（默认 5，建议不超过 10 以避免 API 限流）",
    )
    parser.add_argument("--token", default=None, help="Cloudflare API Token")
    parser.add_argument("--email", default=None, help="Cloudflare 账号邮箱（配合 --api-key 使用）")
    parser.add_argument("--api-key", default=None, help="Cloudflare Global API Key")

    args = parser.parse_args()

    # 线程数校验
    if args.workers < 1:
        print("❌ --workers 至少为 1")
        sys.exit(1)
    if args.workers > 20:
        print("⚠️  线程数过高可能触发 Cloudflare API 限流，已自动调整为 20")
        args.workers = 20

    # 确定认证方式
    api_token: Optional[str] = None
    api_email: Optional[str] = None
    api_key: Optional[str] = None

    if args.token:
        auth_method = "token"
        api_token = args.token
    elif args.email and args.api_key:
        auth_method = "key"
        api_email = args.email
        api_key = args.api_key
    elif AUTH_METHOD == "token" and CF_API_TOKEN != "your_api_token_here":
        auth_method = "token"
        api_token = CF_API_TOKEN
    else:
        print("❌ 请提供认证信息！")
        print("   方式一：--token YOUR_API_TOKEN")
        print("   方式二：--email YOUR_EMAIL --api-key YOUR_API_KEY")
        print("   方式三：在脚本顶部配置区填写")
        sys.exit(1)

    # 加载白名单
    whitelist: Optional[list[str]] = None
    if args.whitelist:
        whitelist = load_whitelist(args.whitelist)
        if not whitelist:
            print("❌ 白名单文件为空")
            sys.exit(1)
        print(f"📄 已加载白名单: {len(whitelist)} 个域名")

    # 创建更新器并执行
    updater = CloudflareDNSUpdater(
        auth_method=auth_method,
        api_token=api_token,
        api_email=api_email,
        api_key=api_key,
        max_workers=args.workers,
    )

    updater.batch_update(
        new_ip=args.new_ip,
        old_ip=args.old_ip,
        whitelist=whitelist,
        record_type=args.record_type,
        dry_run=args.dry_run,
        include_subdomains=not args.no_subdomains,
    )


if __name__ == "__main__":
    main()