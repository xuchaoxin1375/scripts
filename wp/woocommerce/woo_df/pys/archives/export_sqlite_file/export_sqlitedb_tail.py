import sqlite3

# 原始数据库和目标数据库文件名
# 原始数据库和目标数据库文件名
original_db = r'C:\火车采集器V10.27\Data\177\SpiderResult.db3'
new_db = 'first_100_rows.db3'


# 连接原始数据库
conn_old = sqlite3.connect(original_db)
cursor_old = conn_old.cursor()

# 创建新的数据库
conn_new = sqlite3.connect(new_db)
cursor_new = conn_new.cursor()

# 获取所有用户定义的表名
cursor_old.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
tables = [row[0] for row in cursor_old.fetchall()]

print(f"发现 {len(tables)} 张表：{', '.join(tables)}")

for table_name in tables:
    print(f"\n正在处理表: {table_name}")

    # 获取建表语句
    cursor_old.execute(f"SELECT sql FROM sqlite_master WHERE type='table' AND name='{table_name}'")
    create_sql = cursor_old.fetchone()[0]
    cursor_new.execute(create_sql)

    # 获取最后1000条数据（假设表中有自增主键 'id'）
    try:
        cursor_old.execute(f"SELECT * FROM {table_name} ORDER BY id DESC LIMIT 1000")
        rows = cursor_old.fetchall()
        if not rows:
            print(f"表 {table_name} 没有数据，跳过插入。")
            continue

        rows.reverse()  # 恢复原始顺序（可选）
        placeholders = ', '.join(['?'] * len(rows[0]))
        cursor_new.executemany(f"INSERT INTO {table_name} VALUES ({placeholders})", rows)

    except Exception as e:
        print(f"⚠️ 表 {table_name} 处理失败（可能缺少 'id' 字段）: {e}")

# 提交并关闭连接
conn_new.commit()
conn_old.close()
conn_new.close()

print(f"\n✅ 所有表的最后1000行数据已写入新数据库：{new_db}")