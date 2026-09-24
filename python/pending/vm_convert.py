# missing slice: convert — str() and int() conversions, digit edge cases

print(str(0))
print(str(1))
print(str(42))
print(str(123))
print(str(99999))

print(int("0"))
print(int("1"))
print(int("42"))
print(int("123"))
print(int("00123"))
print(int("000"))
print(int("00000"))
print(int("99999"))

print(str(int("00123")))
print(int(str(123)))
print(str(10) + str(20))
print(int("10") + int("20"))

print(str(123) == "123")
print(int("123") == 123)
print(int("00123") == 123)
print(int("0") == 0)
print(str(0) == "0")
