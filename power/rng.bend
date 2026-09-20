# Counter RNG: Threefry2x32-20 (Salmon et al., Random123). A pure function of
# (key, counter): no state to thread, so any draw of any rollout is addressable
# and the answer is the same on every lane and under every schedule.
#
# Written for the compiled lanes: every op is one native u32 row, the twenty
# rounds are unrolled into straight-line lets (no rotation table, no loop, no
# match on a U32), and a rotation carries both shift counts as literals.
import Base

def rot(+x: U32, l: Nat, r: Nat) -> U32:
  U32.or(U32.shln(x, l), U32.shrn(x, r))

# four rounds (rotations 13 15 26 6), then the n-th key injection
def mix_a(+a: U32, +b: U32, ka: U32, kb: U32, n: U32) -> U32 & U32:
  +a1 = U32.add(a, b)
  +b1 = U32.xor(rot(b, 13n, 19n), a1)
  +a2 = U32.add(a1, b1)
  +b2 = U32.xor(rot(b1, 15n, 17n), a2)
  +a3 = U32.add(a2, b2)
  +b3 = U32.xor(rot(b2, 26n, 6n), a3)
  +a4 = U32.add(a3, b3)
  (U32.add(a4, ka), U32.add(U32.add(U32.xor(rot(b3, 6n, 26n), a4), kb), n))

# four rounds (rotations 17 29 16 24), then the n-th key injection
def mix_b(+a: U32, +b: U32, ka: U32, kb: U32, n: U32) -> U32 & U32:
  +a1 = U32.add(a, b)
  +b1 = U32.xor(rot(b, 17n, 15n), a1)
  +a2 = U32.add(a1, b1)
  +b2 = U32.xor(rot(b1, 29n, 3n), a2)
  +a3 = U32.add(a2, b2)
  +b3 = U32.xor(rot(b2, 16n, 16n), a3)
  +a4 = U32.add(a3, b3)
  (U32.add(a4, ka), U32.add(U32.add(U32.xor(rot(b3, 24n, 8n), a4), kb), n))

# a let cannot open a computed pair, so each group takes the last one's as a parameter
def go_a(ab: U32 & U32, ka: U32, kb: U32, n: U32) -> U32 & U32:
  (a, b) = ab
  mix_a(a, b, ka, kb, n)

def go_b(ab: U32 & U32, ka: U32, kb: U32, n: U32) -> U32 & U32:
  (a, b) = ab
  mix_b(a, b, ka, kb, n)

def keyed(+k0: U32, +k1: U32, +k2: U32, c0: U32, c1: U32) -> U32 & U32:
  go_a(go_b(go_a(go_b(mix_a(U32.add(c0, k0), U32.add(c1, k1),
    k1, k2, 1), k2, k0, 2), k0, k1, 3), k1, k2, 4), k2, k0, 5)

# one block: key (k0, k1), counter (c0, c1), two fresh words
def block(+k0: U32, +k1: U32, c0: U32, c1: U32) -> U32 & U32:
  keyed(k0, k1, U32.xor(U32.xor(k0, k1), 466688986), c0, c1)

def fst(xy: U32 & U32) -> U32:
  (x, _) = xy
  x

# the draw at (seed, stream, step): stream names the rollout, step the draw
def u32(seed: U32, stream: U32, step: U32) -> U32:
  fst(block(seed, stream, step, 0))

# uniform in [0, 1): the top 24 bits over 2^24, exact in an F32 on every lane
def f32(seed: U32, stream: U32, step: U32) -> F32:
  F32.div(U32.to_f32(U32.shrn(u32(seed, stream, step), 8n)), 16777216.0)

# ponytail: modulo bias of n / 2^32; Lemire's reject loop when a caller needs it
def below(seed: U32, stream: U32, step: U32, n: U32) -> U32:
  U32.mod(u32(seed, stream, step), n)
