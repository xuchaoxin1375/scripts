
#include <iostream>
using namespace std;
// 声明自定义函数
void arrange_stars(int n);
// 细节函数
void printStart();
void printStars(int n);
void printSpaces(int n);
void printEnd();

int main()
{
    int n;
    cout << "Enter the number of rows for the star pattern: ";
    cin >> n;
    if (n > 0 && n < 100)
    {

        arrange_stars(n);
    }
    else
    {
        cout<<"!n alid input! the number your input is too big to display! "<<endl;
    }

    return 0;
}
void arrange_stars(int n)
{
    for (int i = 1; i <= n; i++)
    {
        printStart();
        printSpaces(n - i);
        printStars(i);
        printSpaces(n - i);
        printEnd();
        cout << endl;
    }
}
void printStart()
{
    cout << "[";
}

void printSpaces(int n)
{
    for (int i = 0; i < n; i++)
    {
        cout << ' ';
    }
}

void printStars(int n)
{
    for (int i = 1; i < n; i++)
    {
        cout << "* ";
    }
    cout << "*";
}

void printEnd()
{
    cout << "]";
}
