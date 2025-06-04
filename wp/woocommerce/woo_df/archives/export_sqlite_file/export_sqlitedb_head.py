import sqlite3

# 原始数据库和目标数据库文件名
original_db = r'C:\火车采集器V10.27\Data\177\SpiderResult.db3'
new_db = 'first_100_rows.db3'

# 表名（如果你有多个表，请列出所有表名）
# table_name = 'Contents'
 

 
# 连接原始数据库
conn_old = sqlite3.connect(original_db)
cursor_old = conn_old.cursor()

# 创建新的数据库
conn_new = sqlite3.connect(new_db)
cursor_new = conn_new.cursor()

# 获取所有用户定义的表名（排除 sqlite_sequence 等系统表）
cursor_old.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
tables = [row[0] for row in cursor_old.fetchall()]

print(f"发现 {len(tables)} 张表：{', '.join(tables)}")

for table_name in tables:
    print(f"\n正在处理表: {table_name}")

    # 获取原表的创建语句（包括列定义）
    cursor_old.execute(f"SELECT sql FROM sqlite_master WHERE type='table' AND name='{table_name}'")
    create_sql = cursor_old.fetchone()[0]

    # 在新数据库中创建相同的表结构
    cursor_new.execute(create_sql)

    # 提取前100条记录
    cursor_old.execute(f"SELECT * FROM {table_name} LIMIT 100")
    rows = cursor_old.fetchall()

    if not rows:
        print(f"表 {table_name} 没有数据，跳过插入。")
        continue

    # 插入数据
    placeholders = ', '.join(['?'] * len(rows[0]))
    cursor_new.executemany(f"INSERT INTO {table_name} VALUES ({placeholders})", rows)

# 提交并关闭连接
conn_new.commit()
conn_old.close()
conn_new.close()

print(f"\n✅ 所有表的前100行数据已成功写入新数据库：{new_db}")