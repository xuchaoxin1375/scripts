import sys
import time
import argparse
import requests
import concurrent.futures

CF_API_KEY = " your api key ".strip()
CF_EMAIL = " your email ".strip()
HEADERS = {
    "X-Auth-Email": CF_EMAIL,
    "X-Auth-Key": CF_API_KEY,
    "Content-Type": "application/json",
}
API_URL = "https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules"


def get_fail2ban_rules():
    rules = []
    page = 1
    while True:
        params = {
            "mode": "challenge",
            "notes": "Fail2Ban",
            "page": page,
            "per_page": 100,
        }
        resp = requests.get(API_URL, headers=HEADERS, params=params)
        data = resp.json()
        if not data["success"]:
            print("获取规则失败:", data)
            break
        rules.extend(data["result"])
        if page * 50 >= data["result_info"]["total_count"]:
            break
        page += 1
    return rules


def delete_rule(rule):
    # 进度信息由外部传入
    rule_id = rule["id"]
    ip = rule["configuration"].get("value", "未知IP")
    note = rule.get("notes", "")
    resp = requests.delete(f"{API_URL}/{rule_id}", headers=HEADERS)
    data = resp.json()
    return {
        "ip": ip,
        "rule_id": rule_id,
        "note": note,
        "success": data["success"],
        "error": data if not data["success"] else None,
    }


def main():
    parser = argparse.ArgumentParser(description="Cloudflare Fail2Ban批量解封工具")
    parser.add_argument(
        "-m", "--max-workers", type=int, default=3, help="并发线程数，默认3"
    )
    args = parser.parse_args()

    rules = get_fail2ban_rules()
    fail2ban_rules = [r for r in rules if r.get("notes", "").startswith("Fail2Ban")]
    total = len(fail2ban_rules)
    print(f"共找到 {total} 条Fail2Ban规则，开始解封...\n")
    results = [{}] * total

    def worker(idx_rule):
        idx, rule = idx_rule
        print(
            f"[{idx+1}/{total}] 正在解封: IP={rule['configuration'].get('value', '未知IP')}, 规则ID={rule['id']}"
        )
        res = delete_rule(rule)
        if res["success"]:
            print(
                f"[{idx+1}/{total}] 解封成功: IP={res['ip']}, 规则ID={res['rule_id']}"
            )
        else:
            print(
                f"[{idx+1}/{total}] 解封失败: IP={res['ip']}, 规则ID={res['rule_id']}, 错误信息: {res['error']}"
            )
        results[idx] = res

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=args.max_workers
    ) as executor:
        list(executor.map(worker, enumerate(fail2ban_rules)))
    print(f"\n全部解封任务已完成，共处理 {total} 条规则。")


if __name__ == "__main__":
    main()
