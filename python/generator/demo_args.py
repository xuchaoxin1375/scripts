def complex_func(a, b, /, c, d, *args, e, f, **kwargs):
    print(f"a, b (pos-only): {a, b}")
    print(f"c, d (pos-or-key): {c, d}")
    print(f"args: {args}")
    print(f"e, f (key-only): e={e}, f={f}")
    print(f"kwargs: {kwargs}")


print(
    "全部按规则传递(尽可能不使用关键字参数(c,d使用位置参数)和扩展参数*args,**kwargs):"
)
complex_func(1, 2, 3, 4, e=5, f=6)
print()

print("c,d使用关键字参数传参:")
complex_func(1, 2, d=4, c=3, e=5, f=6)
print()

print("包含所有扩展参数 (args 和 kwargs):")
complex_func(1, 2, 3, 4, 100, 200, e=5, f=6, g=7, h=8)
print()

print(
    "可迭代对象解包（Iterable Unpacking）的方式传参给*args,把关键字参数放在字典中通过**kwargs进行传递"
)
args = (5, 6)
kwargs = {"g": 9, "h": 10}
# print("args:", args, "kwargs:", kwargs)
# *kwargs仅解包key,得到('g','h'),而应该使用**kwargs解包字典或的关键字参数
complex_func(1, 2, 3, 4, *args, e=7, f=8, **kwargs)

# print("*args非空时,前面的参数不能以关键字参数传入(仅位置参数).混用位置参数和关键字参数导致错误")
# 如果用到可变位置参数*args,那么其之前就不能关键字参数(pos_or_key类型的参数都只能以position参数的形式传入)
# 否则会导致错误
# complex_func(1, 2, 3,d=4, *args, e=7, f=8,**kwargs) # got multiple values for argument 'd'
# complex_func(1, 2, c=3, d=4, *args, e=7, f=8, **kwargs) # got multiple values for argument 'c'
# complex_func(1, 2, c=3, d=4, e=7, f=8, **kwargs) # 合法调用
complex_func(1, 2, 3, d=4, e=7, f=8, **kwargs) # 合法调用
