/*
计算两个n阶矩阵的乘积函数
给出几组测试输入数据
 */

#include <iostream>
#include <vector>
#include <bits/stdc++.h>


using namespace std;

// Function to multiply two matrices
vector<vector<int>> multiplyMatrices(const vector<vector<int>> &matrixA, const vector<vector<int>> &matrixB)
{
    int n = matrixA.size();
    vector<vector<int>> result(n, vector<int>(n, 0));

    for (int i = 0; i < n; ++i)
    {
        for (int j = 0; j < n; ++j)
        {
            for (int k = 0; k < n; ++k)
            {
                result[i][j] += matrixA[i][k] * matrixB[k][j];
            }
        }
    }

    return result;
}

// Function to print a matrix
void printMatrix(const vector<vector<int>> &matrix)
{
    for (const auto &row : matrix)
    {
        for (int val : row)
        {
            cout << val << " ";
        }
        cout << endl;
    }
}

int main()
{
    // Test data
    vector<vector<int>> matrixA = {
        {1, 2, 3},
        {4, 5, 6},
        {7, 8, 9}};

    vector<vector<int>> matrixB = {
        {9, 8, 7},
        {6, 5, 4},
        {3, 2, 1}};

    cout << "Matrix A:" << endl;
    printMatrix(matrixA);

    cout << "Matrix B:" << endl;
    printMatrix(matrixB);

    vector<vector<int>> result = multiplyMatrices(matrixA, matrixB);

    cout << "Result of multiplication:" << endl;
    printMatrix(result);

    // Add more test cases as needed

    return 0;
}