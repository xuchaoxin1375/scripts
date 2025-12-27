import queue
from queue import Queue
q = queue.Queue()
q.put(1)
q.put(2)
print(q.get())  # 输出: 1 (最先放入的最先取出)
print(q.get())  # 输出: 2 (其次放入的其次取出)