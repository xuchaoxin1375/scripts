import os
import fnmatch


def find_csv_files(directory, recursive=True):
    """
    递归查找指定目录下的所有CSV文件
    
    :param directory: 要搜索的目录
    :param recursive: 是否递归搜索子目录，默认为True
    :return: CSV文件路径列表
    """
    csv_files = []
    
    if recursive:
        # 递归搜索所有子目录
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file.lower().endswith('.csv'):
                    csv_files.append(os.path.join(root, file))
    else:
        # 只搜索当前目录
        for file in os.listdir(directory):
            if file.lower().endswith('.csv') and os.path.isfile(os.path.join(directory, file)):
                csv_files.append(os.path.join(directory, file))
    
    return csv_files


def find_csv_files_with_pattern(directory, pattern="*.csv", recursive=True):
    """
    使用通配符模式递归查找CSV文件
    
    :param directory: 要搜索的目录
    :param pattern: 文件名模式，默认为 "*.csv"
    :param recursive: 是否递归搜索子目录，默认为True
    :return: CSV文件路径列表
    """
    csv_files = []
    
    if recursive:
        for root, dirs, files in os.walk(directory):
            for file in fnmatch.filter(files, pattern):
                csv_files.append(os.path.join(root, file))
    else:
        for file in fnmatch.filter(os.listdir(directory), pattern):
            file_path = os.path.join(directory, file)
            if os.path.isfile(file_path):
                csv_files.append(file_path)
    
    return csv_files


if __name__ == "__main__":
    # 设置要搜索的目录（当前目录）
    search_directory = r"c:\repos\scripts"
    
    print(f"正在递归搜索目录 '{search_directory}' 中的所有CSV文件...")
    print("-" * 60)
    
    # 查找所有CSV文件
    csv_files = find_csv_files(search_directory)
    
    if csv_files:
        print(f"找到 {len(csv_files)} 个CSV文件:")
        print()
        for i, csv_file in enumerate(csv_files, 1):
            print(f"{i:2d}. {csv_file}")
    else:
        print("没有找到任何CSV文件。")
        
    print("-" * 60)
    
    # 也可以使用通配符模式的方式
    csv_files_pattern = find_csv_files_with_pattern(search_directory)
    
    # 验证两种方法的结果是否一致
    if len(csv_files) == len(csv_files_pattern):
        print("两种搜索方法的结果一致。")
    else:
        print("警告：两种搜索方法的结果不一致。")