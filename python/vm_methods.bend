# Pure string-methods implementations over house String and List APIs.
# These functions become the VM's method table when the wire-in slice lands.
import Base

# Whitespace trim: strip leading and trailing ASCII whitespace.
def strip(s: String) -> String:
  String.trim(s)

# Whitespace trim: strip leading ASCII whitespace.
def lstrip(s: String) -> String:
  String.trim_start(s)

# Whitespace trim: strip trailing ASCII whitespace.
def rstrip(s: String) -> String:
  String.trim_end(s)

# Case: convert ASCII lowercase characters to uppercase.
def upper(s: String) -> String:
  String.to_upper(s)

# Case: convert ASCII uppercase characters to lowercase.
def lower(s: String) -> String:
  String.to_lower(s)

# Split s by delimiter sep into fields. Consecutive seps yield empty fields.
# Note: CPython raises ValueError on empty sep; here empty sep is unhandled.
def split(s: String, +sep: String) -> List<&2, String>:
  String.split_on(s, sep)

# Join parts with delimiter sep.
def join(parts: List<&2, String>, +sep: String) -> String:
  String.join(parts, sep)

# Replace all occurrences of substring a with b in s.
def replace(+s: String, +a: String, +b: String) -> String:
  String.replace(s, a, b)

# Index of the first occurrence of sub in s, or the length of s when absent.
# Note on -1 gap: CPython str.find returns -1 when absent. The VM operates on
# unsigned Nat values, so absence yields String.length(s) instead.
def find(+s: String, +sub: String) -> Nat:
  Maybe.default(&2, Nat, String.find(s, sub), String.length(s))

# Return True if sub is a substring of s (CPython: sub in s).
def has(+s: String, +sub: String) -> Bool:
  String.contains(s, sub)

# Return True if s starts with prefix p.
def startswith(+s: String, +p: String) -> Bool:
  String.starts_with(s, p)

# Return True if s ends with suffix p.
def endswith(+s: String, +p: String) -> Bool:
  String.ends_with(s, p)

# Return the number of non-overlapping occurrences of sub in s.
def count(+s: String, +sub: String) -> Nat:
  String.count(s, sub)
