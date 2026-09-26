# missing slice: str methods — strip, lstrip, rstrip, upper, lower, split, join, replace, find, startswith, endswith, count

s = "  padded text  "
print(s.strip())
print(s.lstrip())
print(s.rstrip())
print("   ".strip())
print("abc".strip())
print("---trimmed---".strip("-"))
print("---trimmed---".lstrip("-"))
print("---trimmed---".rstrip("-"))

print("Hello, World!".upper())
print("Hello, World!".lower())
print("abc".upper())
print("XYZ".lower())
print("".upper())
print("".lower())

print("apple,banana,cherry".split(","))
print("one two three".split())
print("a:b:c".split(":"))
print("nodiff".split(","))
print(",".join(["a", "b", "c"]))
print(" ".join(["one", "two", "three"]))
print("-".join(["2026", "09", "21"]))
print("".join(["x", "y", "z"]))

print("hello world".replace("world", "there"))
print("banana".replace("a", "o"))
print("aaaa".replace("a", "b", 2))
print("unchanged".replace("x", "y"))

text = "the quick brown fox"
print(text.find("the"))
print(text.find("quick"))
print(text.find("brown"))
print(text.find("fox"))
print("banana".find("na"))
print("abcde".find("e"))

name = "fixture_test.py"
print(name.startswith("fixture"))
print(name.startswith("other"))
print(name.endswith(".py"))
print(name.endswith(".c"))
print("hello".startswith(""))
print("hello".endswith(""))

print("banana".count("a"))
print("banana".count("na"))
print("banana".count("z"))
print("mississippi".count("ss"))
print("mississippi".count("i"))
