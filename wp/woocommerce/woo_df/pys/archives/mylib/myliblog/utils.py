"""mylib package utils module."""

import logging

logger = logging.getLogger(__name__)  # __name__ == 'myliblog.utils'
FMT = "%(asctime)s - %(levelname)s - [utils fmt:%(name)s -%(funcName)s - %(lineno)d] - %(message)s"
formatter = logging.Formatter(fmt=FMT)
ch = logging.StreamHandler()
ch.setFormatter(formatter)
logger.addHandler(ch)


def helper():
    """Helper function."""
    logger.debug("Helper function is running")
    logger.info("Some useful info from utils")
    logger.warning("This is a warning from utils")
    logger.error("An error demo occurred in utils")
