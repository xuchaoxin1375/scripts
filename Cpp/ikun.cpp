#include <iostream>
#include <[window](https://geek.csdn.net/educolumn/03e5a5a554174a38fdfeb8376bd685e2?spm=1055.2569.3001.10083)s.h>

using namespace std;

void clear_screen()
{
    COORD upper_left = { 0, 0 };
    DWORD chars_written;
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    DWORD console_size;
    [han](https://geek.csdn.net/educolumn/0d22b54eaf6bcf967d9625e1679d00b4?spm=1055.2569.3001.10083)DLE console = GetStd[han](https://geek.csdn.net/educolumn/0d22b54eaf6bcf967d9625e1679d00b4?spm=1055.2569.3001.10083)dle(STD_OUTPUT_[han](https://geek.csdn.net/educolumn/0d22b54eaf6bcf967d9625e1679d00b4?spm=1055.2569.3001.10083)DLE);

    GetConsoleScreenBufferInfo(console, &amp;csbi);
    console_size = csbi.dwSize.X * csbi.dwSize.Y;

    FillConsoleOutputCharacter(console, ' ', console_size, upper_left, &amp;chars_written);
    FillConsoleOutputAttribute(console, csbi.wAttributes, console_size, upper_left, &amp;chars_written);

    SetConsoleCursor[pos](https://geek.csdn.net/educolumn/0399089ce1ac05d7729a569fd611cf73?spm=1055.2569.3001.10083)ition(console, upper_left);
}

void delay(int milliseconds)
{
    Sleep(milliseconds);
}

int main()
{
    int x = 0;
    int y = 0;
    int ball_x = 0;
    int ball_y = 0;
    int score = 0;
    int direction = 0; // 0: right, 1: left
    bool is_jumping = false;
    bool is_shooting = false;

    while (true)
    {
        clear_screen();

        // draw court
        for (int i = 0; i < 25; i++)
        {
            for (int j = 0; j < 80; j++)
            {
                if (i == 0 || i == 24 || j == 0 || j == 79)
                {
                    cout << "#";
                }
                else if (i == 23 &amp;&amp; j == 15)
                {
                    cout << "SCORE: " << score;
                }
                else if (i == 22 &amp;&amp; j == 63)
                {
                    cout << "Cai Xukun Basketball Game";
                }
                else
                {
                    cout << " ";
                }
            }
            cout << endl;
        }

        // draw player
        if (is_jumping)
        {
            if (y > 10)
            {
                y--;
            }
            else
            {
                is_jumping = false;
            }
        }
        else
        {
            if (y < 22)
            {
                y++;
            }
        }

        if (direction == 0)
        {
            for (int i = 0; i < x; i++)
            {
                cout << " ";
            }
            cout << "O";
            x++;
            if (x == 75)
            {
                direction = 1;
            }
        }
        else
        {
            for (int i = 79; i > x; i--)
            {
                cout << " ";
            }
            cout << "O";
            x--;
            if (x == 5)
            {
                direction = 0;
            }
        }

        // draw ball
        if (is_shooting)
        {
            if (ball_x < 70)
            {
                ball_x++;
                ball_y--;
            }
            else
            {
                is_shooting = false;
                if (ball_y >= y &amp;&amp; ball_y <= y + 2)
                {
                    score++;
                }
            }
        }
        else
        {
            ball_x = x + 1;
            ball_y = y + 1;
        }

        for (int i = 0; i < ball_y; i++)
        {
            cout << endl;
        }
        for (int i = 0; i < ball_x; i++)
        {
            cout << " ";
        }
        cout << "*";

        delay(100);

        if (GetAsyncKeyState(VK_SPACE) &amp; 0x8000)
        {
            if (!is_jumping)
            {
                is_jumping = true;
            }
        }

        if (GetAsyncKeyState(VK_RETURN) &amp; 0x8000)
        {
            if (!is_shooting)
            {
                is_shooting = true;
            }
        }
    }

    return 0;
}
