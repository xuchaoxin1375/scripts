##


# 使用 yield from（简洁,少写一层循环）
def chain_v2(*iterables):
    for it in iterables:
        yield from it

result = list(chain_v2([1, 2], [3, 4], [5, 6]))
print(result)   # [1, 2, 3, 4, 5, 6]
##
# 不使用 yield from（繁琐）
def chain_v1(*iterables):
    for it in iterables:
        for item in it:
            yield item
result = list(chain_v1([1, 2], [3, 4], [5, 6]))
print(result)   # [1, 2, 3, 4, 5, 6]
##
