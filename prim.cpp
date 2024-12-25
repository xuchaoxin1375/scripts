#include <iostream>
#include <vector>
using namespace std;

const int MAX_NUM = 1e3;
vector<int> primes;         // 存储素数
bool isNotPrime[MAX_NUM + 1]; // 标记非素数

int main() {
    for (int i = 2; i <= MAX_NUM; ++i) {
        if (!isNotPrime[i]) primes.push_back(i); // 如果 i 是素数，加入素数列表
        for (int p : primes) {
            if (i * p > MAX_NUM) break;          // 超出范围，退出
            isNotPrime[i * p] = true;            // 标记 i * p 为非素数
            if (i % p == 0) break;               // 如果 i 被 p 整除，停止继续筛
        }
    }

    for (int prime : primes) cout << prime << endl; // 输出素数
    cout << "prime number count in [2," << MAX_NUM << "]:" << primes.size() << endl;

    return 0;
}
