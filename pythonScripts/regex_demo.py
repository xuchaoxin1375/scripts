import re

text = "这是一个测试字符串，test testing tested @@@test"
pattern = r'\btest\b'
matches = re.finditer(pattern, text)

for match in matches:
    start = match.start()
    end = match.end()
    print(f"匹配位置: {start}-{end-1}")  # 输出匹配开始和结束的位置
""" 
匹配位置: 10-13
匹配位置: 33-36
 """