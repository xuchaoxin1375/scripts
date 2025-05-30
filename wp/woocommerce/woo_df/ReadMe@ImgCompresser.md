[toc]

## 图片压缩模块

摘要:

- 支持PNG、JPG压缩和WEBP格式转换

- 通常将jpg,png转换为webp会有较好的效果，尤其是png->webp的效果最明显

- 支持命令行参数调用和程序化调用

  

## 功能特点

1. 命令行支持:
   - 添加了完整的命令行参数解析
   - 支持单文件处理和批量处理
   - 添加了详细的帮助信息
   - 支持多种输出格式选择(webp/jpg/png)
   - 添加了覆盖选项(--overwrite)

2. 代码规范:
   - 类型提示
   - 错误处理
   - 日志记录
   - 改进的性能(多线程处理)

3. 其他
   - EXIF信息保留控制
   - 详细输出模式(-v/--verbose)
   - 线程数控制(--max-workers)
   - 优化选项控制(--no-optimize)

## 典型用例

下面用的参数和选项针对我们的业务配置的

### 压缩服务器上的图片

主要针对老方法(api上传的图片未经过处理的情况)

参数序列`-R auto -p -F  -O`

此外主要关心

```python

py C:\repos\scripts\wp\woocommerce\woo_df\pys\image_compresser.py   -R auto -p -F  -O -i C:\Users\Administrator\Pictures\imgs_demo
```

### 本地方法

```bash
-R auto -p -F  -O -k -f webp -i
```



## 使用示例

1. **单文件转换**:
   ```bash
   python image_compressor.py input.jpg -o output.webp -q 85
   ```

2. **批量转换目录**:
   ```bash
   python image_compressor.py ./images -o ./compressed -f webp --overwrite
   ```

3. **高质量JPEG压缩**:
   ```bash
   python image_compressor.py input.png -o output.jpg -q 90 --no-exif
   ```

4. **详细输出模式**:
   ```bash
   python image_compressor.py input.jpg -o output.webp -v
   ```

