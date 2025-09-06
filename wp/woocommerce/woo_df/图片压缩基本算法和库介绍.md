[toc]





## PIL库的简单介绍

在 Python 的 PIL（Pillow）库中，`Image.save()` 方法用于将图像保存到文件,可以根据指定保存的文件名将图片文件转换为指定的格式。

## 📚 官方文档参考

- Pillow 文档：https://pillow.readthedocs.io/en/stable/reference/Image.html#PIL.Image.Image.save

---

### 基本语法：

```python
img.save(fp, format=None, **params)
```

---

###  参数说明：

| 参数名     | 类型                                        | 说明                                                         |
| ---------- | ------------------------------------------- | ------------------------------------------------------------ |
| `fp`       | 文件路径（字符串）或文件对象（file object） | 指定要保存的文件路径或已经打开的文件对象。例如 `'image.jpg'` 或 `open('image.png', 'wb')` |
| `format`   | 字符串（可选）                              | 强制指定保存的图像格式（如 `'PNG'`, `'JPEG'` 等）。如果不指定，会根据文件扩展名自动判断；如果没有扩展名或无法识别，则抛出异常。 |
| `**params` | 关键字参数                                  | 不同格式支持的额外参数，比如 JPEG 支持 `quality`、PNG 支配 `optimize` 和 `compress_level` 等 |

---

### 常见格式及其参数

### 1. **JPEG / JPG**

```python
img.save('output.jpg', 'JPEG', quality=85, optimize=True, progressive=True)
```

- `quality`: 图像质量，范围从 1（最差）到 95（最好），默认是 75。
- `optimize`: 是否优化颜色数，通常设为 `True` 可减小文件体积。
- `progressive`: 是否保存为渐进式 JPEG（网页加载更平滑）。

---

### 2. **PNG**

```python
img.save('output.png', 'PNG', optimize=True, compress_level=9)
```

- `optimize`: 是否尝试优化压缩（默认 `False`），设为 `True` 可能会增加处理时间但减小体积。
- `compress_level`: 压缩级别，0（无压缩）~9（最大压缩），默认是 6。

---

### 3. **GIF**

```python
img.save('output.gif', save_all=True, append_images=images[1:], loop=0, duration=100, disposal=2)
```

- `save_all`: 保存所有帧（用于多帧图像，如动图）
- `append_images`: 要追加保存的图像帧列表（必须是 Image 对象组成的列表）
- `loop`: 动画循环次数，0 表示无限循环
- `duration`: 每帧显示时间（毫秒）
- `disposal`: 如何处理帧之间的清除方式（0-3）

---

### 4. **TIFF**

```python
img.save('output.tiff', compression="tiff_deflate")
```

- `compression`: 压缩方式，可以是 `"none"`, `"tiff_lzw"`, `"tiff_deflate"` 等。

---

### 5. **WebP**

```python
img.save('output.webp', 'WEBP', quality=80, lossless=False)
```

- `quality`: 质量值（有损压缩时使用）
- `lossless`: 是否使用无损压缩（布尔值）

---

### 示例代码

```python
from PIL import Image

# 打开图像
img = Image.open('input.jpg')

# 保存为 JPEG，设置质量为 90
img.save('output.jpg', 'JPEG', quality=90)

# 保存为 PNG，并启用压缩优化
img.save('output.png', 'PNG', optimize=True, compress_level=9)

# 保存为 GIF 动图
frames = [frame.convert('P') for frame in ImageSequence.Iterator(img)]
frames[0].save('animation.gif', save_all=True, append_images=frames[1:], duration=200, loop=0)
```

---





