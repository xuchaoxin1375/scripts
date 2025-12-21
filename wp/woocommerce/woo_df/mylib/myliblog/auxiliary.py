"""This module contains the Auxiliary class and  module function that logs messages."""

import logging

# 创建日志记录器
# module_logger = logging.getLogger("myliblog.auxiliary")
module_logger = logging.getLogger(__name__)


class Auxiliary:
    """This is a class that does something."""

    def __init__(self):
        # self.logger = logging.getLogger("myliblog.auxiliary.Auxiliary")
        # self.logger = logging.getLogger(__name__+".Auxiliary")
        self.logger = module_logger.getChild("Auxiliary")
        self.logger.debug(
            "Auxiliary instance created with logger: %s", self.logger.name
        )
        self.logger.info("creating an instance of Auxiliary")

    def do_something(self):
        """This method does something and logs the process."""
        a = 1 + 1
        self.logger.info("doing something:1+1=%s", a)
        # self.logger.info("done doing something")
        self.logger.warning("this is a warning from Auxiliary")
        self.logger.error("an error demo in Auxiliary")


def some_function():
    """This function does something and logs the process."""
    module_logger.debug("some_function is running")
    module_logger.info('received a call to "some_function"')
    module_logger.warning("this is a warning from some_function")
    module_logger.error("an error demo in some_function")
