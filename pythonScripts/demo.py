def quick_sort(arr):
    """
    快速排序函数，使用递归方法对给定列表进行排序。

    参数:
        arr (list): 待排序的列表。

    返回:
        list: 排序后的列表。
    """
    if len(arr) <= 1:
        return arr  # 基础情况：长度小于等于1的列表已经是有序的

    pivot = arr[0]  # 选择第一个元素作为枢轴
    left, right = [], []

    for element in arr[1:]:
        if element <= pivot:
            left.append(element)  # 小于等于枢轴的元素放入左子列表
        else:
            right.append(element)  # 大于枢轴的元素放入右子列表

    return (
        quick_sort(left) + [pivot] + quick_sort(right)
    )  # 递归排序并合并左右子列表及枢轴


# 示例：对一个示例列表进行快速排序
unsorted_list = [5, 8, 14, 1, 3, 9, 2, 7]
sorted_list = quick_sort(unsorted_list)
print(sorted_list)
