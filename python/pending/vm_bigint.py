# missing slice: bigint — unbounded Python integers (a later lane; needs
# arithmetic above 64 bits). Everything below overflows any 64-bit word.

print(2 ** 100 % 1000)          # 376
print(len(str(2 ** 1000)))      # 302

def fact(n):
    r = 1
    i = 1
    while i <= n:
        r = r * i
        i = i + 1
    return r

print(fact(20))
print(fact(40) // fact(39))     # 40

total = 0
s = str(fact(100))
i = 0
while i < len(s):
    total = total + int(s[i])
    i = i + 1
print(total)                    # 648 — Project Euler 20

a = 1
i = 0
while i < 100:
    a = a * 2
    i = i + 1
print(a)                        # 2^100
