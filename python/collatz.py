def collatz_len(n):
    if n < 2:
        return 1
    if n % 2 == 0:
        return 1 + collatz_len(n // 2)
    return 1 + collatz_len(3 * n + 1)

def best_len(limit):
    best = 0
    i = 1
    while i < limit:
        c = collatz_len(i)
        if c > best:
            best = c
        i = i + 1
    return best

print(best_len(200000))
