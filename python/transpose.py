##

import numpy as np
rng = np.random.default_rng()
##
nrow=3
ncol=5
c=rng.random(size=(nrow,ncol))
# 保留三位小数(可以确保打印的时候每个元素的小数位数不超过3位)
d=c.round(3)
 
for i in d:
    # print(i)
    for j in i:
        print(j,end="\t")
    print()
print("transposing...","-"*10)

#转置后的矩阵规格为(ncol,nrow)
# 采用逐列读取的方式打印原矩阵,打印结果就是原矩阵的转置(第i列被打印为第i行)
#假设转置后的矩阵记为B
for i in range(ncol):
    # 则i用来表示B中元素的列号
    for j in range(nrow):
        # j用来表示B中元素的行号
        print(d[j,i],end="\t")
    print()
