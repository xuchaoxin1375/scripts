def print_stars_odd(lines):

    n = lines * 2 - 1
    tabs = (n) // 2
    for i in range(1, n + 1, 2):
        # 只打印奇数行(对称),偶数行不打印(不对称)
        print(" " * tabs, end="")
        print("*" * i, end="")
        # print("|")
        print()
        tabs -= 1


# print_stars_odd(3)


def print_stars(lines):
    tabs = lines - 1
    for i in range(lines):
        res = " " * tabs + "* " * (i + 1)
        # res=res.rstrip()
        print(res)
        tabs -= 1


print_stars(5)
