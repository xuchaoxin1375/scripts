#include <iostream>
#include <chrono>
#include <thread>

void clearScreen() {
    std::cout << "\033[2J\033[1;1H"; // ANSI escape codes to clear screen and move cursor to (1,1)
}

int main() {
    for (int i = 0; i < 10; ++i) {
        clearScreen();
        std::cout << "Frame " << i + 1 << std::endl;
        std::cout << "  O  " << std::endl;
        std::cout << " /|\\ " << std::endl;
        std::cout << " / \\ " << std::endl;
        std::this_thread::sleep_for(std::chrono::milliseconds(500)); // delay for 500 milliseconds
    }

    return 0;
}
