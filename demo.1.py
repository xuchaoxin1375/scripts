import logging

datefmt1 = "%H:%M:%S"  # 仅打印时分秒
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
    datefmt=datefmt1,
)
logger=logging.getLogger(__name__)
print=logger.info
