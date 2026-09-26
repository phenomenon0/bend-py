print(None == None, None != None, None == 0, 0 == False, "a" == None)
print(0xbeef, 0xE, 0o17, 0b101, 1_000)
def f():
    return 1
print(f())
def f():
    return 2
print(f())
def g(n):
    return n + 1
def h(g):
    return g * 2
print(h(5), g(5))
x = 281474976710655
print(x, x - 1, x // 2 + x // 2)
def uses_global():
    return y + 1
y = 41
print(uses_global())
