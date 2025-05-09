#include <iostream>
#include "starts_printer_function.h"

int main()
{
    int n;
    std::cout << "Enter the number of rows for the star pattern: ";
    std::cin >> n;

    arrange_stars(n);

    return 0;
}

void arrange_stars(int n)
{
    for (int i = 1; i <= n; ++i)
    {
        for (int j = 1; j <= i; ++j)
        {
            std::cout << "* ";
        }
        std::cout << std::endl;
    }
}
