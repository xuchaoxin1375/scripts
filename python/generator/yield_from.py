##


# 使用 yield from（简洁）
def chain_v2(*iterables):
    for it in iterables:
        yield from it

result = list(chain_v2([1, 2], [3, 4], [5, 6]))
print(result)   # [1, 2, 3, 4, 5, 6]
##
