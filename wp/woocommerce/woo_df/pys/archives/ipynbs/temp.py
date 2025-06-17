##
import sqlite3

size = 10
idx = 1
db_path = r"c:\火车采集器V10.27\Data\233\SpiderResult.db3"
table = "Content"
with sqlite3.connect(db_path) as conn:
    cursor = conn.cursor()

    # 每次读取前重新执行查询，确保游标位于结果集开头

    while True:
        rows = cursor.fetchmany(size)
        if not rows:
            print("所有数据已读取完毕。")
            break

        print(f"读取第 {idx} 批次数据:")
        print(f"Batch : {idx}")
        for row in rows:
            print(row)
        idx += 1
cursor.close()
conn.close()
