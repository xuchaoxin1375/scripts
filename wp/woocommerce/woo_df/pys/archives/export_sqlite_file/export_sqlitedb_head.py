"""从指定sqlite数据库中导出前若干条记录到新的sqlite数据库"""

import sqlite3
import argparse

# 原始数据库和目标数据库文件名
original_db = r"C:\火车采集器V10.27\Data\177\SpiderResult.db3"
new_db = "first_100_rows.db3"

# 增加命令行支持
parser = argparse.ArgumentParser(
    description="从指定sqlite数据库中导出前若干条记录到新的sqlite数据库"
)
parser.add_argument(
    "-i", "--input", type=str, default=original_db, help="原始数据库文件路径"
)
parser.add_argument("-o", "--output", type=str, default=new_db, help="新数据库文件路径")
parser.add_argument("-r", "--limit", type=int, default=100, help="每张表导出的行数")
parser.add_argument(
    "-p", "--preview", action="store_true", help="仅预览数据库内容，不导出数据"
)

args = parser.parse_args()

original_db = args.input
new_db = args.output
limit = args.limit
preview = args.preview

# 如果是预览模式，不创建新数据库
if not preview:
    # 创建新的数据库
    conn_new = sqlite3.connect(new_db)
    cursor_new = conn_new.cursor()

# 连接原始数据库
conn_old = sqlite3.connect(original_db)
cursor_old = conn_old.cursor()

# 获取所有用户定义的表名（排除 sqlite_sequence 等系统表）
cursor_old.execute(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
)
tables = [row[0] for row in cursor_old.fetchall()]

print(f"发现 {len(tables)} 张表：{', '.join(tables)}")

for table_name in tables:
    print(f"\n正在处理表: {table_name}")

    # 获取原表的创建语句（包括列定义）
    cursor_old.execute(
        f"SELECT sql FROM sqlite_master WHERE type='table' AND name='{table_name}'"
    )
    create_sql = cursor_old.fetchone()[0]

    if not preview:
        # 在新数据库中创建相同的表结构
        cursor_new.execute(create_sql)

    # 提取前limit条记录
    cursor_old.execute(f"SELECT * FROM {table_name} LIMIT {limit}")
    rows = cursor_old.fetchall()

    if not rows:
        print(f"表 {table_name} 没有数据，跳过。")
        continue

    if preview:
        # 预览模式下打印表结构和前若干行数据
        print(f"表结构: {create_sql}")
        print("前若干行数据:")
        for row in rows:
            print(row)
    else:
        # 插入数据
        placeholders = ", ".join(["?"] * len(rows[0]))
        cursor_new.executemany(
            f"INSERT INTO {table_name} VALUES ({placeholders})", rows
        )

# 提交并关闭连接
if not preview:
    conn_new.commit()
    conn_new.close()

conn_old.close()

if preview:
    print("\n✅ 预览完成，未导出任何数据")
else:
    print(f"\n✅ 所有表的前{limit}行数据已成功写入新数据库：{new_db}")
