#include <iostream>
#include <chrono>
#include <thread>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

void clearScreen() {
    std::cout << "\033[2J\033[1;1H"; // ANSI escape codes to clear screen and move cursor to (1,1)
}

void setTextColor(int color) {
#ifdef _WIN32
    SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), color);
#else
    std::string color_code = "\033[" + std::to_string(color) + "m";
    std::cout << color_code;
#endif
}

int main() {
    const int width = 20; // 控制台宽度
    const int delay = 100; // 延迟时间（毫秒）

    while (true) {
        // 球从左到右
        for (int i = 0; i < width; ++i) {
            clearScreen();
            setTextColor(34); // 设置为蓝色
            for (int j = 0; j < i; ++j) std::cout << " "; // 空格
            std::cout << "O" << std::endl; // 球
            std::this_thread::sleep_for(std::chrono::milliseconds(delay));
        }

        // 球从右到左
        for (int i = width; i >= 0; --i) {
            clearScreen();
            setTextColor(31); // 设置为红色
            for (int j = 0; j < i; ++j) std::cout << " "; // 空格
            std::cout << "O" << std::endl; // 球
            std::this_thread::sleep_for(std::chrono::milliseconds(delay));
        }
    }

    return 0;
}
