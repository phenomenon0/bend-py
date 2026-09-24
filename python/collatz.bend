import Base

def even(+n: Nat) -> Bool:
  Nat.is_eq(Nat.mod(n, 2n), 0n)

# one collatz step, then continue. fuel shrinks first; stop = n < 2.
def ch(+fuel: Nat, +stop: Bool, +b: Bool, +n: Nat) -> Nat:
  match fuel stop b:
    case 0n _ _:
      0n
    case 1n+d True{} _:
      1n
    case 1n+d False{} True{}:
      +m = Nat.div(n, 2n)
      Nat.add(ch(d, Nat.is_lt(m, 2n), even(m), m), 1n)
    case 1n+d False{} False{}:
      +m = Nat.add(Nat.mul(3n, n), 1n)
      Nat.add(ch(d, Nat.is_lt(m, 2n), even(m), m), 1n)

def collatz_len(+fuel: Nat, +n: Nat) -> Nat:
  ch(fuel, Nat.is_lt(n, 2n), even(n), n)

# the best chain over [lo..hi]: hi shrinks first, stop when it falls below lo.
def bc(+hi: Nat, +stop: Bool, +lo: Nat, +fuel: Nat) -> Nat:
  match hi stop:
    case 0n _:
      0n
    case 1n++h True{}:
      0n
    case 1n++h False{}:
      Nat.max(bc(h, Nat.is_lt(h, lo), lo, fuel), collatz_len(fuel, Nat.add(h, 1n)))

def best_in(+hi: Nat, +lo: Nat, +fuel: Nat) -> Nat:
  bc(hi, Nat.is_lt(hi, lo), lo, fuel)

# depth-d split; leaves brute small ranges; forks under a bang.
def tree(+d: Nat, +lo: Nat, +hi: Nat, +fuel: Nat) -> Nat:
  match d:
    case 0n:
      best_in(hi, lo, fuel)
    case 1n++p:
      +half = Nat.div(Nat.add(hi, lo), 2n)
      a b = tree(p, lo, half, fuel) tree(p, Nat.add(half, 1n), hi, fuel)
      Nat.max(a, b)

def main() -> IO(Unit):
  IO.print(Nat.show(tree!(10n, 1n, 200000n, 500n)))
