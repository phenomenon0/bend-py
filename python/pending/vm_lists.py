# missing slice: lists — create, index, slice, len, iteration, append alias pin

print([])
print([1, 2, 3])
print(["a", "b", "c"])
print([10, "twenty", 30])

xs = [10, 20, 30, 40, 50]
print(xs[0])
print(xs[1])
print(xs[2])
print(xs[3])
print(xs[4])

print(xs[1:3])
print(xs[:2])
print(xs[1:])
print(xs[:])

print(len([]))
print(len(xs))
print(len([1, 2]))

for x in xs:
    print(x)

for s in ["alpha", "beta", "gamma"]:
    print(s)

a = [1, 2]
b = a
b.append(3)
print(a)
print(b)

acc = []
acc.append(100)
acc.append(200)
print(acc)
print(len(acc))
