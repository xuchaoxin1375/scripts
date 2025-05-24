import os
from PIL import Image
import argparse

def compress_jpg(input_path, output_path, quality=85, optimize=True, progressive=False):
    """
    压缩JPG/JPEG图片
    :param input_path: 输入文件路径
    :param output_path: 输出文件路径
    :param quality: 质量(1-100)，值越小压缩率越高
    :param optimize: 是否优化
    :param progressive: 是否使用渐进式JPEG
    """
    try:
        with Image.open(input_path) as img:
            # 转换为RGB模式(如果是RGBA等模式)
            if img.mode != 'RGB':
                img = img.convert('RGB')
            
            # 保存时应用压缩设置
            img.save(
                output_path, 
                'JPEG', 
                quality=quality, 
                optimize=optimize, 
                progressive=progressive
            )
        
        original_size = os.path.getsize(input_path) / 1024  # KB
        compressed_size = os.path.getsize(output_path) / 1024
        reduction = (original_size - compressed_size) / original_size * 100
        
        print(f"压缩完成: {input_path} -> {output_path}")
        print(f"原始大小: {original_size:.2f} KB")
        print(f"压缩后大小: {compressed_size:.2f} KB")
        print(f"减少: {reduction:.1f}%")
        
        return compressed_size
    except Exception as e:
        print(f"压缩 {input_path} 时出错: {e}")
        return None

def compress_directory(input_dir, output_dir, quality=85, optimize=True, progressive=False):
    """
    压缩目录中的所有JPG/JPEG图片
    :param input_dir: 输入目录
    :param output_dir: 输出目录
    :param quality: 压缩质量(1-100)
    :param optimize: 是否优化
    :param progressive: 是否使用渐进式JPEG
    """
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    total_original = 0
    total_compressed = 0
    processed_files = 0
    
    supported_extensions = ('.jpg', '.jpeg', '.JPG', '.JPEG')
    
    for filename in os.listdir(input_dir):
        if filename.lower().endswith(supported_extensions):
            input_path = os.path.join(input_dir, filename)
            output_path = os.path.join(output_dir, filename)
            
            original_size = os.path.getsize(input_path) / 1024
            total_original += original_size
            
            print(f"\n处理文件: {filename} (原始大小: {original_size:.2f} KB)")
            
            compressed_size = compress_jpg(
                input_path, 
                output_path, 
                quality=quality, 
                optimize=optimize, 
                progressive=progressive
            )
            
            if compressed_size is not None:
                total_compressed += compressed_size
                processed_files += 1
    
    if processed_files > 0:
        print(f"\n总结:")
        print(f"处理文件数: {processed_files}")
        print(f"原始总大小: {total_original:.2f} KB")
        print(f"压缩后总大小: {total_compressed:.2f} KB")
        print(f"总减少: {total_original - total_compressed:.2f} KB ({((total_original - total_compressed) / total_original * 100):.1f}%)")
    else:
        print("没有找到可处理的JPG/JPEG文件")

def main():
    parser = argparse.ArgumentParser(description='JPG/JPEG图片压缩工具')
    parser.add_argument('input', help='输入文件或目录路径')
    parser.add_argument('-o', '--output', help='输出文件或目录路径(目录时必需)')
    parser.add_argument('-q', '--quality', type=int, default=85, 
                        help='压缩质量(1-100)，默认85')
    parser.add_argument('--no-optimize', action='store_false', dest='optimize',
                        help='禁用优化(可能减少压缩时间但增大文件)')
    parser.add_argument('-p', '--progressive', action='store_true',
                        help='生成渐进式JPEG(适合网页使用)')
    
    args = parser.parse_args()
    
    if os.path.isfile(args.input):
        if not args.output:
            # 如果没有指定输出路径，添加'_compressed'后缀
            base, ext = os.path.splitext(args.input)
            args.output = f"{base}_compressed{ext}"
        
        compress_jpg(
            args.input, 
            args.output, 
            quality=args.quality, 
            optimize=args.optimize, 
            progressive=args.progressive
        )
    elif os.path.isdir(args.input):
        if not args.output:
            print("错误: 压缩目录时必须指定输出目录")
            return
        
        compress_directory(
            args.input, 
            args.output, 
            quality=args.quality, 
            optimize=args.optimize, 
            progressive=args.progressive
        )
    else:
        print(f"错误: 输入路径 '{args.input}' 不存在")

if __name__ == '__main__':
    main()