"""
维护站点建站日期日志记录文件
"""

import os
import re
from datetime import datetime

import pandas as pd

# 建站日期配置文件格式选择csv的好处是简单,且便于表格软件批量编辑,读写方便
SITE_BIRTH_CSV = "/www/site_birth.csv"
SITE_TABLE_CONF = "/www/site_table.conf"
# 本批次建站列表备份文件
SITE_TABLE_BAK = "/www/site_table.conf.bak"

# 网站创建日期记录表(csv)是记录累加的(各个批次的总和),而conf文件是覆盖的
# SITE_BIRTH_CSV = "./site_birth.csv"
# SITE_TABLE_CONF = "./site_table.conf"

NGINX_VHOST_ROOT = "/www/server/panel/vhost/nginx"

# csv表头
TABLE_HEADER = ["domain", "birth_time", "status", "update_time"]
INIT_STATUS = "young"
now = datetime.now()

# 标准日期-时间格式 YYYY-MM-DD HH:MM:SS (时间(时分秒对于此任务不重要,可以仅仅保留日期(年月日)))
dt = now.strftime("%Y-%m-%d %H:%M:%S")

# 检查网站创建日期日志文件(csv)是否存在,如果不存在,则创建此文件,表头为domain,birth_time
if os.path.exists(SITE_BIRTH_CSV) == False:
    print("日志文件不存在,创建模板日志文件(csv)...")
    df = pd.DataFrame(columns=TABLE_HEADER)
    df.to_csv(SITE_BIRTH_CSV, index=False)
else:
    print("日志文件存在,读取站点创建日期...")
    df = pd.read_csv(SITE_BIRTH_CSV)


site_birth_lines = []
# 维护csv文件
with open(SITE_TABLE_CONF, mode="r", encoding="utf-8") as f:
    lines = f.readlines()
    # print(lines)
    for line in lines:
        # skip comments or empty lines
        if re.match(r"^\s*(#|$)", line):
            print(f"skip line:{line.strip()}")
            continue

        # try to extract domain; ensure match is found before using groups()
        domain_match = re.match(r"^\s*(?:https?://\w*\.)?(?P<domain>[\w.-]+)", line)
        if not domain_match:
            print(f"no domain found in line, skip: {line.strip()}")
            continue

        domain = domain_match.group("domain").strip()
        # 构造用于插入csv的字典
        site_dict = {
            "domain": domain,
            "birth_time": dt,
            "status": INIT_STATUS,
            "update_time": dt,
        }
        site_birth_lines.append(site_dict)

print(f"site_birth_lines:{site_birth_lines}")
df = pd.concat([df, pd.DataFrame(site_birth_lines)], ignore_index=True)
df.to_csv(SITE_BIRTH_CSV, index=False)
print(f"{df}")

# 将表格文件备份(重命名的方式)
# 移除旧备份文件(如果存在的话)
if os.path.exists(SITE_TABLE_BAK):
    os.remove(SITE_TABLE_BAK)

os.rename(SITE_TABLE_CONF, SITE_TABLE_BAK)
# os.system(f"cp {SITE_TABLE_CONF} {SITE_TABLE_BAK}")
