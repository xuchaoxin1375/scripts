import os
import os.path as op
import time
""" 使用说明,重命名文件是高危操作,为了安全起见,您可以将要被处理的文件做一个备份
其次,您可以复制文件中的一部分来测试您的代码的可行性
最后,如果代码中通过保守的预览代码代替实际的重命名操作也是不错的选择(待预览效果符合预期后执行实际的重命名操作是推荐的做法)
本程序只对文件执行重命名(纳入排序计算),文件夹被可以排除,当然,也可以认为修改使得文件夹也一并纳入计算
"""
testDir = "d:/repos/learnDatabase_sql/materials"
if __name__ == "__main__":
    # 测试目录填入一下括号中(字符串)
    os.chdir(testDir)
    itemList = os.listdir(".")
    is_endWithAscii = False
    # 推荐的分割符,如果不喜欢,可以替换(取消的换就将其置为空字符串"")
    separator = "^"
    cleanList = []
    # 给部分去除源文件名的前缀中的ascii码部分(可以改为数字isdigital(这在排错序号重新排序前的清洗操作是横有用的))
    for item in itemList:
        originName = item
        item = op.splitext(item)
        is_continue = item[0][-1].isascii()
        # print(item[0][-1])
        if not is_continue:
            new_name = ""
            new_name = item[0]+separator
            new_name += item[-1]
            # 在执行重命名操作前但应出来预览一下,符合预期后在编写重命名语句(可以之列出将要被修改的部分即可,其余部分必定处于原样)
            print(originName, new_name)
            os.rename(originName, new_name)
