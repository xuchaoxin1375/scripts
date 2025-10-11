"""测试跨模块日志"""

import logging

import myliblog.auxiliary as auxiliary_module
LOG_FILE="main_aux.log"
# 创建 本脚本的 日志记录器(分别试验三种方案)
# 1.取名为严格的模块名,从而作为父级日志记录器接受子模块的日志记录
# (下面的两个日志记录器会因为名字不同而有不同的效果,体现了日志记录器的命名和消息传递层级关系的绑定)
# 1.1为日志记录器起一个和所调用的库myliblog同名的名字(这是这个库的顶级名字,其子模块中的日志会被传递到这个记录器,当然root记录器也可以收到)
logger = logging.getLogger("myliblog")
# 1.2为日志记录器起一个普通的名字
logger = logging.getLogger("myliblogAUX")


# 2.对于库/模块是合适的,但是主调代码中使用相当于'__main__'的名称的记录器
# logger=logging.getLogger(__name__)
# 3.根日志器,接受可能的任何日志记录
# logger = logging.getLogger()

logger.setLevel(logging.DEBUG)
# 创建可记录调试消息的文件处理器(将文件保存到文件中)
fh = logging.FileHandler(LOG_FILE, mode="w", encoding="utf-8")
fh.setLevel(logging.DEBUG)
# 创建具有更高日志层级的控制台处理器🎈
ch = logging.StreamHandler()
ch.setLevel(logging.INFO)
# ch.setLevel(logging.ERROR)

# 创建格式化器并将其添加到处理器
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fh.setFormatter(formatter)
ch.setFormatter(formatter)
# 将处理器添加到日志记录器
logger.addHandler(fh)
logger.addHandler(ch)

# 模块中的Auxiliary类的日志记录
logger.info("creating an instance of auxiliary_module.Auxiliary")
a = auxiliary_module.Auxiliary()
logger.info("created an instance of auxiliary_module.Auxiliary")


logger.info("calling auxiliary_module.Auxiliary.do_something")
a.do_something()
logger.info("finished auxiliary_module.Auxiliary.do_something")

# 模块级的函数的日志记录
logger.info("calling auxiliary_module.some_function()")
auxiliary_module.some_function()
logger.info("done with auxiliary_module.some_function()")
