import os
import os.path as op
from sys import argv
import time
""" 使用说明,重命名文件是高危操作,为了安全起见,您可以将要被处理的文件做一个备份
其次,您可以复制文件中的一部分来测试您的代码的可行性
最后,如果代码中通过保守的预览代码代替实际的重命名操作也是不错的选择(待预览效果符合预期后执行实际的重命名操作是推荐的做法)
本程序只对文件执行重命名(纳入排序计算),文件夹被可以排除,当然,也可以认为修改使得文件夹也一并纳入计算
"""
testDir = "d:/repos/learnDatabase_sql/materials"
testDir = "D:/org/Ecloud/myMusic/hitomiShimatani"
testDir="D:/org/recently/NEEP/408/CN/theroy/cnBooks/furtherReading"
# testDir = argv[1]


def rename_prefix(testDir="."):
    # 测试目录填入一下括号中(字符串)
    os.chdir(testDir)
    itemList = os.listdir(".")
    is_beginAscii = False
    # 推荐的分割符,如果不喜欢,可以替换(取消的换就将其置为空字符串"")
    separator = "_"
    cleanList = []
    # 给部分去除源文件名的前缀中的ascii码部分(可以改为数字isdigital(这在排错序号重新排序前的清洗操作是横有用的))
    for item in itemList:
        is_continue = item[0].isdigit() or item[0] == separator
        if is_continue:
            new_name = ""
            # 文件名预处理与清理
            for index, chr in enumerate(item):
                if chr.isdigit() or chr == separator:
                    continue
                else:
                    new_name = item[index:]
                    # print(new_name)
                    break
            # 文件判断与重命名
            if op.isfile(item):
                print(new_name)
                # 由于这里还是字符串处理阶段,可以只是预览,不必执行重命名操作
                # os.rename(item, new_name)
                cleanList.append(new_name)
        else:
            ...
    # 得到中文名开头的文件名
    needNumberList=[]
    for item in itemList:
        isNeedNumber = not item[0].isascii()
        if isNeedNumber:
            needNumberList.append(item)

        else:
            ...
    itemList = needNumberList
    # sort with the same format 01~99
    for index, item in enumerate(itemList):
        # 这里使用了字符串的.zfill来前置补零格式化字符串(对数字格式化的话可以用str()将其转为字符类型,然后执行该函数)
        # 通过序数前置补0对其的处理,可以是的排序的时候不会出现错乱,当然,这需要对您的文件数(或者说数量级)做一个估计(如果文件在100个以内,哪个zfill()参数取2较为合适.一次类推)
        # 我还建议在插入序号前缀中的最后一个字符以"_"结尾或者其他合法的字符来分隔
        new_prefix = str(index).zfill(2)
        new_prefix = new_prefix+separator
        new_name = new_prefix+item
        # for index, chr in enumerate(item):
        if op.isfile(item):
            # 在执行重命名操作前但应出来预览一下,符合预期后在编写重命名语句
            originName = item
            print(originName, new_name)
            os.rename(originName, new_name)


if __name__ == "__main__":
    rename_prefix(testDir)
