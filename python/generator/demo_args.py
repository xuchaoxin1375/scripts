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

print("可迭代对象解包（Iterable Unpacking）的方式传参给*args,把关键字参数放在字典中通过**kwargs进行传递")
args = (5, 6)
kwargs = {"g": 9, "h": 10}
# print("args:", args, "kwargs:", kwargs)
# *kwargs仅解包key,得到('g','h'),而应该使用**kwargs解包字典或的关键字参数
complex_func(1, 2, 3, 4, *args, e=7, f=8,**kwargs)

