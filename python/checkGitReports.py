""" 

设定一个递归函数travers_dir(dirName,depthStop,...);
该函数支持指定递归的深度;
同时要求能够体现目录间的层次（通过制表符缩进来表达 🅱 )
具体规则如下：当指定深度depth_stop<=0时，尽可能的递归当前目录下的子目录（否则递归的深度就是depth_stop,或者不超过depth_stop);
默认尽可能递归.

该函数接收一个目录字符串参数，函数进入改目录打印出所有文件名以及目录名此外，如果被打印的对象时目录时，需要以该目录为参数在调用一次traverse_dir

在以下实现中，您不应当传入第三个参数，如果为了安全起见，您可以为其在做一次浅封装，使得函数只有两个参数，而函数内部则调用traverse_dir()
"""
import os
import os.path as op
from os import system as py_shell

""" 本函数主要用到：os.listdir（）以及os.path.isdir()以及一些判断技巧和debug过程中的控制技巧，去掉日志语句后，代码量较少 """
# dirName = "C:/repos/learnPython/ppt_source_code"
# dirName = "./../algorithm/"

dirPrefix = "C:/repos/learnPython"
dirPost = "algorithm"
dirName = op.join(dirPrefix, dirPost)
dirName = "C:\\repos"
pathOut = "C:/repos/learnPython/pythonOS_files/file_dir_out"

# 定义一个空函数，来控制日志打印与否（免注释）


def empyt(obj):
    ...


d = print
# 控制是否打印调试日志
d = empyt
# 当反复调试的时候可以预处理将之前的文件删除
# 如果有必要，可以采用将原来的文件重名名的方式（以输出时间为名字后缀是一种选择）
if op.exists(pathOut):
    # 或者用rename()
    os.remove(pathOut)

# 将中途的输出结果输出到文件中（采用append模式）


def append(content, fileName=pathOut):
    with open(fileName, 'a') as fout:
        # 注意换行
        fout.write(content+"\n")


out = append
depth = 0
reportOut=".\\gitReport"
# test

def traverse_dir(dirName, stop_depth=1, depth=0):
    # depth=0
    if stop_depth > 0:
        if stop_depth > depth:
            pass
        else:
            return

    d("\t new invoke of traverse_dir()")
    items = os.listdir(dirName)
    d(items)
    if (items):
        # cwd1=os.getcwd()
        # d('\t'+cwd1)
        # d("now chdir()...")
        # os.chdir(dirName)
        # cwd2=os.getcwd()
        # d("\t"+cwd2)

        for item in items:
            # newPath = dirName+"/"+item
            # newPath的存在性可以保证，但是是否为目录需做进一步判断
            newPath = op.join(dirName, item)
            d(newPath)
            # notice the paramter of isdir()
            if op.isdir(newPath):
                d("dirName:"+item+"\twill be enter by new invoke of traverse_dir")
                dirStr_indent = depth*"\t"+newPath
                out(dirStr_indent)
                print("\n---😁-----",dirStr_indent,"---------😇 --------\n")
                
                os.chdir(newPath)
                # 向外输出报告：而当前中断只查看遍历进度和重要错误
                py_shell("git status >> "+reportOut)
                # 直接在当前终端上查看查询结果
                # py_shell("git status")

                traverse_dir(newPath, stop_depth, depth+1)
            else:
                ...
                # fileStr=depth*"\t"+item
                # print(fileStr)
                # out(fileStr)


if __name__ == "__main__":
    traverse_dir(dirName, 1)
