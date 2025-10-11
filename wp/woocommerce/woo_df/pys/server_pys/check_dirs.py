import os

# 填写域名列表的文件名
DOMAINS_LIST_FILE = r"   ".strip()
# 需要扫描的路径
SITE_ROOT = r"  /www/wwwroot/  ".strip()
FILE_DIR_PATTERN = r"  /wordpress/wp-content/uploads/2025  ".strip()
# 处理结果输出的文件名
RES_FILE = r"to_be_compress_dirs.txt"


def walk_with_depth(root_dir, depth=None):
    """
    递归遍历目录，支持指定递归深度和过滤目录/文件。

    Args:
        root_dir (str): 根目录路径。
        depth (int, optional): 遍历的最大深度，默认为 None（无限制）。

    Example:
        >>> test_dir=r"C:/ShareTemp/imgs_demo"
        >>> walk_with_depth(test_dir,depth=1 )
    """

    dirs = []
    files = []

    def walker(path, current_depth):
        if depth is not None and current_depth > depth:
            return

        try:
            entries = os.listdir(path)
        except PermissionError:
            # 忽略无法访问的目录
            return

        for entry in entries:
            full_path = os.path.join(path, entry)

            if os.path.isdir(full_path):
                dirs.append(full_path)
                walker(full_path, current_depth + 1)
            else:
                files.append(full_path)

    walker(root_dir, 1)
    return dirs, files


dirs, files = walk_with_depth(root_dir=SITE_ROOT, depth=2)

to_be_compress_site_domains = []
with open(
    file=DOMAINS_LIST_FILE,
    mode="r",
    encoding="utf-8",
) as f:
    lines = f.readlines()
    for line in lines:
        line = line.strip()
        to_be_compress_site_domains.append(line.lower())

sites = []
for site_dir_path in dirs:
    # print(domain)
    # print(site_dir_path,"(dir_path)")
    if site_dir_path.lower().endswith(tuple(to_be_compress_site_domains)):
        print(site_dir_path)
        sites.append(site_dir_path + FILE_DIR_PATTERN)
# print(sites)
print(f"sites count:{len(sites)}")

# 将列表sites中的内容写入到文件🎈
with open(file=RES_FILE, mode="w", encoding="utf-8") as f:
    f.writelines([f"{line}\n" for line in sites])
