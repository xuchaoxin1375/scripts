#include <stdio.h>

// 检查是否是闰年
int isLeapYear(int year)
{
    if (year % 4 == 0)
    {
        if (year % 100 == 0)
        {
            if (year % 400 == 0)
            {
                return 1; // 是闰年
            }
            else
            {
                return 0; // 不是闰年
            }
        }
        else
        {
            return 1; // 是闰年
        }
    }
    else
    {
        return 0; // 不是闰年
    }
}

// 计算给定年月日是当年的第几天
int dayOfYear(int year, int month, int day)
{
    int days = 0;
    int leap = isLeapYear(year);

    // 根据月份累加天数
    switch (month - 1)
    {
    case 11:
        days += 30; // November
    case 10:
        days += 31; // October
    case 9:
        days += 30; // September
    case 8:
        days += 31; // August
    case 7:
        days += 31; // July
    case 6:
        days += 30; // June
    case 5:
        days += 31; // May
    case 4:
        days += 30; // April
    case 3:
        days += 31; // March
    case 2:
        days += (leap ? 29 : 28); // February
    case 1:
        days += 31; // January
    case 0:
        days += 0; // No need to add anything for the first month
    }

    // 加上当前月份的天数
    days += day;

    return days;
}

int main()
{
    int year, month, day;

    // 输入年月日
    printf("Enter year: ");
    scanf("%d", &year);
    printf("Enter month: ");
    scanf("%d", &month);
    printf("Enter day: ");
    scanf("%d", &day);

    int result = dayOfYear(year, month, day);
    printf("The given date is the %dth day of the year %d\n", result, year);

    return 0;
}