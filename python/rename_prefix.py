import os
import os.path as op
from sys import argv, setprofile
import time
from venv import   create

""" 使用说明,重命名文件是高危操作,为了安全起见,您可以将要被处理的文件做一个备份
其次,您可以复制文件中的一部分来测试您的代码的可行性
或者,编写一个专门的测试(TDD)
最后,如果代码中通过保守的预览代码代替实际的重命名操作也是不错的选择
(待预览效果符合预期后执行实际的重命名操作是推荐的做法)
本程序只对文件执行重命名(纳入排序计算),文件夹不处理
使用python脚本,跨平台
-----
需求分析
- 首先,能够将非字母&数字开头的文件重命名为以指定格式命名的文件:例如,"00_"+文件名
换句话说,经过函数处理,原先不满足字母|数字开头的文件名改为形如"00_"+文件名的格式
算法:
- 将目录下文件名读入到一个列表保存备用
- 识别并提取出需要做重命名的文件(但是先仅仅做文件名上的变更预览(old->new的格式预览),如果符合预期,则编写相应的IO操作代码)
"""

# testDir = argv[1]


""" 设计为递归函数,不同深度的递归调用之间只有index会有所不同 """


def drop_duplicated(item, index, separator, itemList):
    """用于去重,一般情况下不调用它!"""
    new_prefix = str(index + 1).zfill(2) + separator
    new_name = new_prefix + item
    # 制作初步的new_name
    if new_name in itemList:
        # 重新制作new_name(因为发生重名),以覆盖初步的new_name
        new_prefix = str(index + 1).zfill(2) + separator
        new_name = new_prefix + item
        return drop_duplicated(item, index + 1, separator, itemList)
    # 没后重名,直接返回本次调用的初步制作的new_name
    return new_name


def rename_prefix(testDir="."):
    # 测试目录填入
    os.chdir(testDir)
    itemList = os.listdir(".")
    # clone 当前目录下的文件名列表备用
    currentDirItems = itemList[:]
    # print(currentDirItems)
    cnt = 0
    for item in currentDirItems:
        print(cnt, item)
        cnt += 1

    # 推荐的分割符,如果不喜欢,可以替换(取消的换就将其置为空字符串"")
    separator = "_"

    not_meet = []
    for item in itemList:
        # isalnum无法排除中文
        # is_need_rename = not item[0].isalnum()
        first_char = item[0]
        # 这里将`.`排除在外,是为了避免对.git目录做出修改
        is_english_alpha = first_char.islower() or first_char.isupper()
        is_valid = is_english_alpha or first_char.isdigit() or first_char == "."
        # is_need_rename = not  is_english_alpha and first_char.isdigit()
        # if not valid ,then do some handling!
        if not is_valid:
            not_meet.append(item)

        else:
            ...
    itemList = not_meet
    print("@itemList", itemList)
    # sort with the same format 01~99
    for index, item in enumerate(itemList):
        # 这里使用了字符串的.zfill来前置补零格式化字符串(对数字格式化的话可以用str()将其转为字符类型,然后执行该函数)
        # 通过序数前置补0对其的处理,可以是的排序的时候不会出现错乱,当然,这需要对您的文件数(或者说数量级)做一个估计(如果文件在100个以内,哪个zfill()参数取2较为合适.一次类推)
        # 我还建议在插入序号前缀中的最后一个字符以"_"结尾或者其他合法的字符来分隔
        new_prefix = str(index).zfill(2) + separator
        new_name = new_prefix + item
        # for index, chr in enumerate(item):
        # if op.isfile(item):
        # 在执行重命名操作前但应出来预览一下,符合预期后在编写重命名语句
        originName = item
        preview_variations = f"😎newName:{new_name}<-😁originName:{originNam"}'
        # debug
        # print(itemList)
        while new_name in currentDirItems:
            print(f"already exist the new_name:{new_name}"')
            new_prefix = str(index + 1).zfill(2) + separator
            new_name = new_prefix + item
            # if new_name in itemList:
        # print(originName, new_name)
        print(preview_variations)
        os.rename(originName, new_name)


def create_files(n: int = 2, path: str = "."):
    """这是一个创建测试文件的函数,用以检测脚本的主要逻辑是否可以大致的正确工作"""
    path = "test_rename_dir"
    if not os.path.exists(path):
        os.mkdir(path)
    os.chdir("test_rename_dir")
    # os.chdir(path)
    mode = "w+"
    for i in range(n):
        with open(f"{i}.txt", mode) as f:
            f.write("hello world")
    with open("中文开头文件", mode) as f:
        f.write("中文开头文件")
    with open("(_ascii文件", mode) as f:
        f.write("(_ascii文件")


if __name__ == "__main__":
    # print(f'please close any files and directories you want to rename,if they are used by other program.😁')
    print("😎-----------------------------"')
    # create_files()
    rename_prefix()
