import time
if __name__ == "__main__":
    time_string = time.strftime(
        '%Y-%m-%d %H:%M:%S', time.localtime(time.time()))
    print(time_string)