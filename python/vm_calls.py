def add(x, y):
    return x + y

def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)

def fact(n):
    acc = 1
    i = 1
    while i <= n:
        acc = acc * i
        i = i + 1
    return acc

def noret():
    pass

print(add(3, 4))
print(add(add(1, 2), add(3, 4)))
print(fib(10))
print(fact(6))
print(noret())
