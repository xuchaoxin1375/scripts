import cv2


def extract_edges(image_path, threshold1, threshold2):
    # 加载图像
    image = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)

    # 1. 高斯模糊（降噪）
    blurred = cv2.GaussianBlur(image, (5, 5), 0)

    # 2. 计算梯度（使用Sobel算子）
    # OpenCV的Canny函数内部已经包含了梯度计算，此处不再单独计算
    # grad_x = cv2.Sobel(blurred, cv2.CV_64F, 1, 0)
    # grad_y = cv2.Sobel(blurred, cv2.CV_64F, 0, 1)

    # 3. 直接使用Canny函数，它会自动完成梯度计算和后续步骤
    edges = cv2.Canny(blurred, threshold1, threshold2)

    return edges


# 示例调用
image_path = "C:\\share\\MK\\img.jpg"  # 替换成你要处理的图像路径
threshold1 = 50  # 第一个阈值，低阈值
threshold2 = 150  # 第二个阈值，高阈值

edges = extract_edges(image_path, threshold1, threshold2)

# 显示边缘图像
cv2.imshow("Edges using Canny", edges)
cv2.waitKey(0)
cv2.destroyAllWindows()

# 如果需要保存提取出的边缘图像
cv2.imwrite("output_edges.jpg", edges)
