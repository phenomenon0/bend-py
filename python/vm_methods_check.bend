# Verification program for pure string methods against CPython.
import Base
import ./vm_methods.bend as M

def quote(s: String) -> String:
  String.append("'", String.append(s, "'"))

def show_list.go(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      "]"
    case h <> t:
      String.append(", ", String.append(quote(h), show_list.go(t)))

def show_list(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      "[]"
    case h <> t:
      String.append("[", String.append(quote(h), show_list.go(t)))

def fmt_str(tag: String, s: String) -> String:
  String.append(tag, String.append(": ", quote(s)))

def fmt_bool(tag: String, b: Bool) -> String:
  String.append(tag, String.append(": ", Bool.show(b)))

def fmt_nat(tag: String, n: Nat) -> String:
  String.append(tag, String.append(": ", Nat.show(n)))

def fmt_list(tag: String, xs: List<&2, String>) -> String:
  String.append(tag, String.append(": ", show_list(xs)))

def lines_strip() -> List<&2, String>:
  [fmt_str("strip 1", M.strip("  hello  ")),
   fmt_str("strip 2", M.strip("   ")),
   fmt_str("strip 3", M.strip("")),
   fmt_str("strip 4", M.strip("hello")),
   fmt_str("strip 5", M.strip("\t\r\n abc \n\t ")),
   fmt_str("strip 6", M.strip("  a b c  "))]

def lines_lstrip() -> List<&2, String>:
  [fmt_str("lstrip 1", M.lstrip("  hello  ")),
   fmt_str("lstrip 2", M.lstrip("   ")),
   fmt_str("lstrip 3", M.lstrip("")),
   fmt_str("lstrip 4", M.lstrip("hello")),
   fmt_str("lstrip 5", M.lstrip("\t\n abc"))]

def lines_rstrip() -> List<&2, String>:
  [fmt_str("rstrip 1", M.rstrip("  hello  ")),
   fmt_str("rstrip 2", M.rstrip("   ")),
   fmt_str("rstrip 3", M.rstrip("")),
   fmt_str("rstrip 4", M.rstrip("hello")),
   fmt_str("rstrip 5", M.rstrip("abc \r\n\t"))]

def lines_upper() -> List<&2, String>:
  [fmt_str("upper 1", M.upper("hello")),
   fmt_str("upper 2", M.upper("Hello, World! 123")),
   fmt_str("upper 3", M.upper("")),
   fmt_str("upper 4", M.upper("ALREADY UPPER"))]

def lines_lower() -> List<&2, String>:
  [fmt_str("lower 1", M.lower("HELLO")),
   fmt_str("lower 2", M.lower("Hello, World! 123")),
   fmt_str("lower 3", M.lower("")),
   fmt_str("lower 4", M.lower("already lower"))]

def lines_split() -> List<&2, String>:
  [fmt_list("split 1", M.split("a,b,c", ",")),
   fmt_list("split 2", M.split("a,,b", ",")),
   fmt_list("split 3", M.split(",a,", ",")),
   fmt_list("split 4", M.split(",", ",")),
   fmt_list("split 5", M.split("", ",")),
   fmt_list("split 6", M.split("foo::bar::baz", "::")),
   fmt_list("split 7", M.split("hello", ",")),
   fmt_list("split 8", M.split("mississippi", "ss")),
   fmt_list("split 9", M.split("aaaaa", "aa"))]

def lines_join() -> List<&2, String>:
  [fmt_str("join 1", M.join(["a", "b", "c"], ",")),
   fmt_str("join 2", M.join(["foo", "bar"], "::")),
   fmt_str("join 3", M.join(["single"], ",")),
   fmt_str("join 4", M.join([], ",")),
   fmt_str("join 5", M.join(["", ""], ",")),
   fmt_str("join 6", M.join(["a", "", "b"], "-"))]

def lines_replace() -> List<&2, String>:
  [fmt_str("replace 1", M.replace("hello world", "world", "there")),
   fmt_str("replace 2", M.replace("banana", "an", "X")),
   fmt_str("replace 3", M.replace("aaaa", "aa", "b")),
   fmt_str("replace 4", M.replace("abc", "xyz", "123")),
   fmt_str("replace 5", M.replace("abc", "", "-")),
   fmt_str("replace 6", M.replace("", "a", "b")),
   fmt_str("replace 7", M.replace("", "", "x"))]

def lines_find() -> List<&2, String>:
  [fmt_nat("find 1", M.find("banana", "ana")),
   fmt_nat("find 2", M.find("banana", "na")),
   fmt_nat("find 3", M.find("banana", "ban")),
   fmt_nat("find 4", M.find("banana", "nab")),
   fmt_nat("find 5", M.find("banana", "")),
   fmt_nat("find 6", M.find("", "")),
   fmt_nat("find 7", M.find("", "a")),
   fmt_nat("find 8", M.find("mississippi", "iss"))]

def lines_has() -> List<&2, String>:
  [fmt_bool("has 1", M.has("banana", "ana")),
   fmt_bool("has 2", M.has("banana", "nab")),
   fmt_bool("has 3", M.has("banana", "")),
   fmt_bool("has 4", M.has("", "")),
   fmt_bool("has 5", M.has("", "a")),
   fmt_bool("has 6", M.has("mississippi", "ssip"))]

def lines_startswith() -> List<&2, String>:
  [fmt_bool("startswith 1", M.startswith("banana", "ban")),
   fmt_bool("startswith 2", M.startswith("banana", "ana")),
   fmt_bool("startswith 3", M.startswith("banana", "")),
   fmt_bool("startswith 4", M.startswith("", "")),
   fmt_bool("startswith 5", M.startswith("", "a")),
   fmt_bool("startswith 6", M.startswith("hello", "hello")),
   fmt_bool("startswith 7", M.startswith("hello", "helloworld"))]

def lines_endswith() -> List<&2, String>:
  [fmt_bool("endswith 1", M.endswith("banana", "ana")),
   fmt_bool("endswith 2", M.endswith("banana", "ban")),
   fmt_bool("endswith 3", M.endswith("banana", "")),
   fmt_bool("endswith 4", M.endswith("", "")),
   fmt_bool("endswith 5", M.endswith("", "a")),
   fmt_bool("endswith 6", M.endswith("hello", "hello")),
   fmt_bool("endswith 7", M.endswith("hello", "bighello"))]

def lines_count() -> List<&2, String>:
  [fmt_nat("count 1", M.count("banana", "ana")),
   fmt_nat("count 2", M.count("banana", "an")),
   fmt_nat("count 3", M.count("aaaaa", "aa")),
   fmt_nat("count 4", M.count("banana", "z")),
   fmt_nat("count 5", M.count("banana", "")),
   fmt_nat("count 6", M.count("", "")),
   fmt_nat("count 7", M.count("", "a")),
   fmt_nat("count 8", M.count("mississippi", "s"))]

def all_lines() -> List<&2, String>:
  List.concat(&2, String, [lines_strip(), lines_lstrip(), lines_rstrip(), lines_upper(), lines_lower(), lines_split(), lines_join(), lines_replace(), lines_find(), lines_has(), lines_startswith(), lines_endswith(), lines_count()])

def main() -> IO(Unit):
  IO.print(String.join(all_lines(), "\n"))

#|strip 1: 'hello'
#|strip 2: ''
#|strip 3: ''
#|strip 4: 'hello'
#|strip 5: 'abc'
#|strip 6: 'a b c'
#|lstrip 1: 'hello  '
#|lstrip 2: ''
#|lstrip 3: ''
#|lstrip 4: 'hello'
#|lstrip 5: 'abc'
#|rstrip 1: '  hello'
#|rstrip 2: ''
#|rstrip 3: ''
#|rstrip 4: 'hello'
#|rstrip 5: 'abc'
#|upper 1: 'HELLO'
#|upper 2: 'HELLO, WORLD! 123'
#|upper 3: ''
#|upper 4: 'ALREADY UPPER'
#|lower 1: 'hello'
#|lower 2: 'hello, world! 123'
#|lower 3: ''
#|lower 4: 'already lower'
#|split 1: ['a', 'b', 'c']
#|split 2: ['a', '', 'b']
#|split 3: ['', 'a', '']
#|split 4: ['', '']
#|split 5: ['']
#|split 6: ['foo', 'bar', 'baz']
#|split 7: ['hello']
#|split 8: ['mi', 'i', 'ippi']
#|split 9: ['', '', 'a']
#|join 1: 'a,b,c'
#|join 2: 'foo::bar'
#|join 3: 'single'
#|join 4: ''
#|join 5: ','
#|join 6: 'a--b'
#|replace 1: 'hello there'
#|replace 2: 'bXXa'
#|replace 3: 'bb'
#|replace 4: 'abc'
#|replace 5: '-a-b-c-'
#|replace 6: ''
#|replace 7: 'x'
#|find 1: 1
#|find 2: 2
#|find 3: 0
#|find 4: 6
#|find 5: 0
#|find 6: 0
#|find 7: 0
#|find 8: 1
#|has 1: True
#|has 2: False
#|has 3: True
#|has 4: True
#|has 5: False
#|has 6: True
#|startswith 1: True
#|startswith 2: False
#|startswith 3: True
#|startswith 4: True
#|startswith 5: False
#|startswith 6: True
#|startswith 7: False
#|endswith 1: True
#|endswith 2: False
#|endswith 3: True
#|endswith 4: True
#|endswith 5: False
#|endswith 6: True
#|endswith 7: False
#|count 1: 1
#|count 2: 2
#|count 3: 2
#|count 4: 0
#|count 5: 7
#|count 6: 1
#|count 7: 0
#|count 8: 4
