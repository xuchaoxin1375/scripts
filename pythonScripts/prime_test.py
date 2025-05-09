""" 说明若干素数的乘积+1不一定是素数 """


def is_prime(n):
    if n <= 1:
        return False
    if n == 2:
        return True
    if n % 2 == 0:
        return False
    max_divisor = int(n**0.5) + 1
    for d in range(3, max_divisor, 2):
        if n % d == 0:
            return False
    return True


def prime_factors(n):
    """
    Returns a list of prime factors of the given integer n.

    Args:
        n (int): The number to factorize.

    Returns:
        list: A list of prime factors of n.

    Raises:
        ValueError: If n is less than 1.

    Example:
        >>> prime_factors(315)
        [3, 3, 5, 7]
    """
    if n < 1:
        raise ValueError("n must be a positive integer")

    factors = []
    i = 2
    while i * i <= n:
        if n % i:
            i += 1
        else:
            n //= i
            factors.append(i)
    if n > 1:
        factors.append(n)
    return factors


i = 2
s = 1
line = []
examples = 5 #可以举更多的例子,这里设置例子的个数,比如给出5个例子
cnt = 0
while True:
    if is_prime(i):
        line.append(i)
        s *= i
        if is_prime(s + 1):
            # print(f"{i} is prime")
            pass
        else:
            ps = "x".join(map(str, line))
            print(f"{ps}+1={s+1}={str('x').join(map(str,prime_factors(s+1)))}")
            # print("is not prime")
            # print("prime factors of", s + 1, "are", prime_factors(s + 1))
            cnt += 1
            if cnt == examples:
                break
        #    break

    i += 1
