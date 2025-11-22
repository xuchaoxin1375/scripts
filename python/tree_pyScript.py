""" 
设定一个递归函数travers_dir(dirName,depthStop,...);
该函数支持指定递归的深度;
同时要求能够体现目录间的层次（通过制表符缩进来表达 🅱 )
具体规则如下：当指定深度depth_stop<=0时，尽可能的递归当前目录下的子目录（否则递归的深度就是depth_stop,或者不超过depth_stop);
默认尽可能递归.
该函数接收一个目录字符串参数，函数进入改目录打印出所有文件名以及目录名此外，如果被打印的对象时目录时，需要以该目录为参数在调用一次traverse_dir
在以下实现中，您不应当传入第三个参数，如果为了安全起见，您可以为其在做一次浅封装，使得函数只有两个参数，而函数内部则调用traverse_dir()
"""
from sys import argv
import os
import os.path as op


# 定义一个空函数，来控制日志打印与否（免注释）
def empyt(obj):
    ...


d = print
# 控制是否打印调试日志
d = empyt
pathOut = "fileOutByTreePyScript"


""" 本函数主要用到：os.listdir（）以及os.path.isdir()以及一些判断技巧和debug过程中的控制技巧，去掉日志语句后，代码量较少 """


def border_generator(num=50, separator='>'):
    return num*separator


def separate_line_printer(num=50, separator='>'):
    print(f'😎🎶:{border_generator(num,separator)}')


def traverse_dir(dirName=".", stop_depth=0, depth=0):
    if depth == 0:
        separate_line_printer(separator='~')
        print(
            f'😁executing the traverse_dir with the paramters: \n@dirName={dirName},\n@stop_depth={stop_depth},\n@depth={depth}')
        separate_line_printer(separator='^')

    if stop_depth > 0:
        if stop_depth > depth:
            pass
        else:
            return
    d("\t new invoke of traverse_dir()")
    items = os.listdir(dirName)
    # print(items)
    # for item in items:
    #     newPath = op.join(dirName, item)
    #     print(newPath)
    #     print(op.isfile(newPath))
    items.sort(key=lambda item: op.isdir(op.join(dirName, item)))
    # separate_line()
    # print(items)

    d(items)
    if (items):
        for item in items:
            # newPath = dirName+"/"+item
            # newPath的存在性可以保证，但是是否为目录需做进一步判断
            newPath = op.join(dirName, item)
            d(newPath)
            # notice the paramter of isdir()
            isdir = op.isdir(newPath)
            depthStr = str(depth+1)
            if isdir:
                # print(isdir)
                if item == ".git":
                    continue
                d("dirName:"+item+"\twill be enter by new invoke of traverse_dir")
                # leftEmoji = "-------😇-------"
                # rightEmoji = "-------🙂-------"
                fileLogo = "☪ "
                folder_Logo = "📁"+depthStr+"->"
                # dir_logo="->"
                indent = depth*"\t"

                # depthStr = folder_Logo+depthStr

                # dirStr = newPath
                #
                dirStr = indent+folder_Logo + newPath
                print(dirStr)
                # borderStr=indent+"\t"+"Depth:"+depthStr+border_generator(separator=".")
                # print(borderStr)
                # out(dirStr)f
                traverse_dir(newPath, stop_depth, depth+1)
            else:
                fileStr = depth*"\t"+0*" "+"⭐"+depthStr+"⭐️:"+item
                print(fileStr)
                # out(fileStr)


def append(content, fileName=pathOut):
    with open(fileName, 'a') as fout:
        # 注意换行
        fout.write(content+"\n")


def generate_defaultParams():
    # dirName = "d:/repos/learnPython/ppt_source_code"
    # dirName = "./../algorithm/"
    dirPrefix = "d:/repos/scripts/"
    # dirPost = "algorithm"
    dirPost = ""
    # dirName = op.join(dirPrefix, dirPost)
    return dirPrefix+dirPost


# 当反复调试的时候可以预处理将之前的文件删除
# 如果有必要，可以采用将原来的文件重名名的方式（以输出时间为名字后缀是一种选择）
if op.exists(pathOut):
    # 或者用rename()
    os.remove(pathOut)


if __name__ == "__main__":

    # test
    os.chdir(os.getcwd())
    # print(os.getcwd(), "😁😁😁")
    # traverse_dir(".",2)
    separate_line_printer(separator="-")
    print("😊info:there is in the tree_pyScript.py;\n try to offer the tree server...💕")

    # if the CLI didn't offer the parameter for the script,then run the statement:
    dirName = "."  # default direcotry(current work directory)
    dirName = generate_defaultParams()
    depth = 2

    # modify the dirName according the parameter(parameter judging&correcting...)
    # case0:more than 1 parameter.
    if len(argv) > 1:
        # scriptName=argv[0]
        # case1: more than 2 parameters
        dirName = argv[1]
        if len(argv) > 2:
            # print(f"get the argv from commandLine:{argv[1]}😊{argv[2]}")
            # the 2nd parameter will be regarded as stopDepth(as default);
            depth = argv[2]
            if(argv[2].isdigit()):
                depth = int(depth)
            # judge if user input the name parameter(keyword parameter.)
            # todo complete this implement
            if(argv[1].startswith("depth=")):
                depth = int(argv[1][6:])
                print(argv[1][6:])
            else:
                ...  # keep the argv[1] as raw input.（as dirName)
            if(argv[2].startswith("dirName=")):
                dirName = argv[2][len("dirName="):]
        if(argv[1] in ["-?", "?", "/?", "\\?"]):
            print("function usage:traverse_dir([dirName],[depth]💕")
    else:
        print("you do not offer any parameter,now try execute the default behaviour💕")

    traverse_dir(dirName, depth)
    tip = '😘work dir tips for user:'
    separate_line_printer()
    print(tip, "\n", os.getcwd(), f'😘')
