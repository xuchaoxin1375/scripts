
import os
import sys
import math
from datetime import datetime


def split_file_by_lines(input_file_path, lines_per_file=5000):
    """
    将大文件按指定行数分割成多个小文件
    
    :param input_file_path: 输入文件路径
    :param lines_per_file: 每个分割文件包含的行数，默认为5000
    """
    # 获取当前时间戳
    timestamp = str(int(datetime.now().timestamp()))
    
    # 获取输入文件的基本信息
    base_name = os.path.splitext(os.path.basename(input_file_path))[0]
    file_ext = os.path.splitext(os.path.basename(input_file_path))[1]
    
    # 打开输入文件并读取所有行
    with open(input_file_path, 'r', encoding='utf-8') as input_file:
        lines = input_file.readlines()
    
    total_lines = len(lines)
    total_files = math.ceil(total_lines / lines_per_file)
    
    print(f"总共有 {total_lines} 行，将被分割成 {total_files} 个文件，每个文件最多 {lines_per_file} 行")
    
    # 分割文件
    for i in range(total_files):
        start_idx = i * lines_per_file
        end_idx = min((i + 1) * lines_per_file, total_lines)
        
        # 生成输出文件名：时间戳+序号
        output_filename = f"{timestamp}_{i+1:03d}_{base_name}{file_ext}"
        output_filepath = os.path.join(os.path.dirname(input_file_path), output_filename)
        
        # 写入分割后的文件
        with open(output_filepath, 'w', encoding='utf-8') as output_file:
            output_file.writelines(lines[start_idx:end_idx])
        
        print(f"已创建文件: {output_filepath}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python split_file_by_lines.py <input_file_path> [lines_per_file]")
        print("  input_file_path: 要分割的源文件路径")
        print("  lines_per_file: 每个分割文件的行数 (默认为5000)")
        sys.exit(1)
    
    input_file = sys.argv[1]
    
    if not os.path.exists(input_file):
        print(f"错误: 文件 '{input_file}' 不存在")
        sys.exit(1)
    
    lines_per_file = 5000  # 默认值
    if len(sys.argv) > 2:
        try:
            lines_per_file = int(sys.argv[2])
        except ValueError:
            print("错误: 行数必须是一个整数")
            sys.exit(1)
    
    split_file_by_lines(input_file, lines_per_file)