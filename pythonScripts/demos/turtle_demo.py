import turtle
import time
t = turtle.Turtle()
n = 30
side = 30


def n_shape(t, n, side):
    for i in range(n):
        t.forward(side)
        # 正n边形的外角为360/n度
        # turtle每次移动外角的度数即可
        t.left(360 / n)


# n_shape(t, n, side)


def spiral(t, n, angle):
    for i in range(n):
        t.forward(i)
        t.left(angle)


# spiral(t,n,90)
def star(t, n, length):
    turtle.screensize(130, 130, "red")
    for i in range(n):
        t.forward(length)
        t.left(144)


# star(t,5,30)


def fill_color_star():
    t.shape("turtle")
    t.pencolor("red")

    # 打算填充颜色,调用fillcolor方法传入颜色,表示填充颜色为红色
    t.fillcolor("red")
    # 标记需要填充的图形的起点
    t.begin_fill()
    # 绘制需要填充的图形
    for i in range(5):
        t.forward(100)
        t.left(144)

    # 开始填充,嗲用end_fill表示目标图形绘制完毕,颜色瞬间完成填充
    t.end_fill()


# fill_color_star()
# t.circle(50,180)
def mn_shape(num=5, n=5, length=50):
    """绘制num个n边形"""
    t.speed(0)
    for i in range(num):
        for j in range(n):
            t.forward(length)
            t.left(360 / n)
        # 绘制完一个5变形后换一个方向绘制下一个n边形
        t.left(360 / num)
    t.hideturtle()
mn_shape(n=6)
# turtle.done()
time.sleep(2)

turtle.bye()