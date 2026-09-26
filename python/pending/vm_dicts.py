# missing slice: dicts — literal create, lookup, len, insertion order iteration, get with default

print({})
print({"a": 1})
print({"a": 1, "b": 2, "c": 3})
print({"x": 10, "y": "hello", "z": 30})

d = {"alpha": 1, "beta": 2, "gamma": 3}
print(d["alpha"])
print(d["beta"])
print(d["gamma"])

print(len({}))
print(len(d))

ordered = {"first": 10, "second": 20, "third": 30, "fourth": 40}
for k in ordered:
    print(k)
    print(ordered[k])

keys = {"zeta": 1, "alpha": 2, "mu": 3, "beta": 4}
for k in keys:
    print(k)

print(d.get("alpha", 999))
print(d.get("not_there", 999))
print(d.get("not_there"))
print(d.get("beta"))
