[toc]

## 图片处理需求描述

> 将多种常见图片格式（包括 `jpg`, `png`, `webp`, `heic`, `tif`, `bmp`, `gif`, `avif` 等）统一转换为 **节省磁盘空间的 WebP 格式**，并：
>
>  **等比例缩放分辨率**，使其不超过 `1000x800`（宽≤1000，高≤800），原图小则不放大  
>
>  **压缩画质以降低文件大小**（即使是原 WebP 也要重新压缩）  
>
>  **统一输出为 `.webp` 格式**

---

### ffmpeg版本检查

```bash
ffmpeg -h
ffmpeg -version

```



##  单文件处理命令行

推荐的默认命令行格式和参数

> 注意输入文件和输出文件更改为具体的路径或名字

```powershell
ffmpeg -i "input.jpg" -vf "scale='min(1000,iw)':'min(800,ih)':force_original_aspect_ratio=decrease" -c:v libwebp -quality 80 -compression_level 6 -preset picture -loop 0 "output.webp"
```

上述单行命令行适用于各种shell

---



在bash这类shell下,可以使用如下可读性更高的方式编写(由于参数很长,使用`\`换行)

对于windows下的cmd,将`\`用`^`代替,对应powershell,将`\`用(`)符号代替

```bash
ffmpeg -i input.jpg \
       -vf "scale='min(1000,iw)':'min(800,ih)':force_original_aspect_ratio=decrease" \
       -c:v libwebp \
       -quality 80 \
       -compression_level 6 \
       -preset picture \
       -loop 0 \
       output.webp
```

---

## 🔍 参数详解

### 🖼️ 视频滤镜（缩放）

基本格式

```bash
-vf "scale=WIDTH:HEIGHT:force_original_aspect_ratio=decrease"
```

**在缩放时强制保持原始图像的宽高比，并且只允许缩小（不允许放大），确保输出图像不会超出指定的宽高限制。** 

`force_original_aspect_ratio` 有三个可选值：

| 选项       | 效果                                                        |
| ---------- | ----------------------------------------------------------- |
| `disable`  | 默认值，不强制保持比例 → 可能拉伸变形                       |
| `decrease` | **保持比例，只缩小，不放大**                                |
| `increase` | 保持比例，只放大，不缩小 → 适合“至少达到某尺寸”，但可能模糊 |

这里采用

```bash
-vf "scale='min(1000,iw)':'min(800,ih)':force_original_aspect_ratio=decrease"
```
- 保持原始宽高比
- 最大宽度 1000，最大高度 800
- 原图小则不放大 

---

### 🎯 编码器：`libwebp`
```bash
-c:v libwebp
```
- 必须使用 `libwebp` 编码器才能输出 WebP
- 确保你的 `ffmpeg` 支持：  
  ```bash
  #windows
  ffmpeg -encoders|sls webp
  #linux
  ffmpeg -encoders | grep webp
  ```
  应输出：`V..... libwebp`

>  绝大多数现代 `ffmpeg`（官网、Homebrew、Snap、Windows 官方构建）都已内置 `libwebp` 支持。

---

### 🖌️ 质量控制（关键！压缩大小靠它）

#### 1. `-quality 80`（推荐 70~85）
- 范围：0~100，数字越大质量越高
- **80 是画质与体积的极佳平衡点**
- 若追求极致压缩 → 用 `70` 或 `65`
- 若需高清 → 用 `85~90`

#### 2. `-compression_level 6`（推荐 4~6）
- 范围：0~6，**数字越大压缩越狠、越慢、文件越小**
- `6` = 最高压缩（推荐用于节省空间）
- `4` = 平衡速度与压缩率

#### 3. `-preset picture`
- 针对“静态图片”优化编码策略
- 可选值：`default`, `picture`, `photo`, `drawing`, `icon`, `text`
- `picture` / `photo` 最适合摄影类图片

> 💡 `-preset` 会自动调整内部参数，优先用它而不是手动调参

---

### 🌀 `-loop 0`（防止动图循环）
- 如果输入是 GIF 或动图，WebP 默认可能循环播放
- `-loop 0` 表示“不循环”，对静态图无影响，但加上更安全

---

##  批量转换脚本（Linux/macOS Bash）

```bash
#!/bin/bash

mkdir -p compressed_webp

for file in *.{jpg,jpeg,png,webp,heic,tif,tiff,bmp,gif,avif,JPG,JPEG,PNG,WEBP,HEIC,TIF,TIFF,BMP,GIF,AVIF}; do
    [[ ! -f "$file" ]] && continue
    output="compressed_webp/${file%.*}.webp"
    ffmpeg -i "$file" \
           -vf "scale='min(1000,iw)':'min(800,ih)':force_original_aspect_ratio=decrease" \
           -c:v libwebp \
           -quality 80 \
           -compression_level 6 \
           -preset picture \
           -loop 0 \
           "$output"
done
```

> 💡 保存为 `convert_to_webp.sh`，然后：
> ```bash
> chmod +x convert_to_webp.sh
> ./convert_to_webp.sh
> ```

---

##  Windows 批量命令（CMD）

```cmd
mkdir compressed_webp 2>nul

for %%f in (*.jpg *.jpeg *.png *.webp *.heic *.tif *.tiff *.bmp *.gif *.avif) do (
    ffmpeg -i "%%f" -vf "scale='min(1000,iw)':'min(800,ih)':force_original_aspect_ratio=decrease" -c:v libwebp -quality 80 -compression_level 6 -preset picture -loop 0 "compressed_webp\%%~nf.webp"
)
```

> 保存为 `convert.bat`，双击运行即可

---

## 📊 质量/压缩级别推荐表

| 用途              | `-quality` | `-compression_level` | 说明                   |
| ----------------- | ---------- | -------------------- | ---------------------- |
| 高清展示/印刷预览 | 90         | 4                    | 文件稍大，画质极佳     |
| 网页/社交媒体     | 80~85      | 5~6                  | 推荐默认值             |
| 移动端/快速加载   | 70~75      | 6                    | 体积小，肉眼难辨差异   |
| 缩略图/预览图     | 60~65      | 6                    | 极致压缩，接受轻微模糊 |

---

## ⚠️ 特别注意事项

### 1. HEIC / AVIF 支持
- 需要 `ffmpeg` 编译时启用 `libheif` / `libaom` / `libdav1d`
- 大多数现代 `ffmpeg` 已支持（如 [https://ffmpeg.org](https://ffmpeg.org) 官方构建）
- 检查支持：
  ```bash
  ffmpeg -codecs | grep -E "(heic|av1)"
  ```

### 2. 动图（GIF）→ WebP
- 上述命令会自动将 GIF 转为 **静态首帧 WebP**
- 如果你希望保留动画，请添加 `-loop 0` 并确认是否需要 `-an`（无音频）等，但你目标是“节省空间”，静态图更优

### 3. 保留元数据（EXIF / ICC）
- WebP 默认不保留 EXIF，如需保留，需额外处理（较复杂，通常不推荐，因 WebP 本身设计为轻量网络格式）
- 如有需要可后续扩展

---

##  最终推荐命令（再次强调）

```bash
ffmpeg -i input.any \
       -vf "scale='min(1000,iw)':'min(800,ih)':force_original_aspect_ratio=decrease" \
       -c:v libwebp \
       -quality 80 \
       -compression_level 6 \
       -preset picture \
       -loop 0 \
       output.webp
```

 支持几乎所有输入格式  
 自动缩放不超 1000x800  
 画质压缩可控，节省空间  
 原 WebP 也会被重新压缩优化  
 输出统一为 `.webp`

---

## 💡 附加建议：进一步优化体积

如果对压缩率要求极高，可尝试：

```bash
-quality 75 -compression_level 6 -preset photo
```

或使用外部工具二次压缩（如 `cwebp` 命令行工具）：

```bash
cwebp -q 75 -m 6 -preset photo input.png -o output.webp
```

但 `ffmpeg` 已经非常强大，一般无需额外步骤。

