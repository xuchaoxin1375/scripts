#include <iostream>
#include "starts_printer_function.h"
using namespace std;

void pyramid(int n);

int main()
{
    int n;
    std::cout << "Enter the number of rows for the star pattern: ";
    std::cin >> n;

    pyramid(n);

    return 0;
}

void pyramid(int n)
{
    // 总共要打印n行内容
    for (int i = 1; i <= n; ++i)
    {

        // 处理每一行要打印的内容
        // 经过分析,当n=m时,第一行要打印m-1个空格,然后打印一个星号
        // 第二行要打印m-2个空格,然后打印星号和空格的交替串,并且最后一个符号为星号(虽然结尾是空格,肉眼也看不出来)
        // 以此类推,我们为每一行的内容分为两个部分
        // 打印n-1-i个空格
        // 行的开始以一个"["开头
        cout << '[';
        for (int k = 1; k <= n - i; k++)
        {
            cout << ' ';
        }
        // 如果不关心行末的空格，可以使用如下版本
        // for (int j = 1; j <= i; ++j)
        // {
        //     std::cout << "* ";
        // }
        // 如果要避免结尾的空格,使用如下版本
        for (int t = 1; t <= i - 1; t++)
        {
            cout << "* ";
        }

        cout << '*';

        // 如果要两边空格数量相同,可以追加下面的代码(和行内第一段一致,因此可以考虑抽象为函数)
        for (int k = 1; k <= n - i; k++)
        {
            cout << ' ';
        }
        cout << "]";
        // 打印完一行后换行
        std::cout << std::endl;
    }
}
