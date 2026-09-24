#!/usr/bin/env python3
# The oracle for blake3.bend: prints the whole fixture. BLAKE3 is written here
# from the specification, independently of power/blake3.bend, and held to the
# project's own published test vectors before any row is emitted -- the 35
# lengths of test_vectors.json, whose input is the bytes i % 251.
#
# The two constructions differ on purpose. This one is the recursive tree the
# spec describes: split at the largest power of two chunks, hash both halves,
# join. Bend cannot express that -- a def may not call one defined after it --
# so power/blake3.bend is the reference implementation's chunk stack instead, a
# single left-to-right loop that merges a subtree whenever the chunk count says
# one closed. A row agreeing therefore says the two trees are the same tree,
# not that one copy of an algorithm matches another.
M = 0xFFFFFFFF
IV = [
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
]
PERM = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]
CHUNK_START, CHUNK_END, PARENT, ROOT = 1, 2, 4, 8


def rotr(x, r):
    return ((x >> r) | (x << (32 - r))) & M


def g(s, a, b, c, d, mx, my):
    s[a] = (s[a] + s[b] + mx) & M
    s[d] = rotr(s[d] ^ s[a], 16)
    s[c] = (s[c] + s[d]) & M
    s[b] = rotr(s[b] ^ s[c], 12)
    s[a] = (s[a] + s[b] + my) & M
    s[d] = rotr(s[d] ^ s[a], 8)
    s[c] = (s[c] + s[d]) & M
    s[b] = rotr(s[b] ^ s[c], 7)


def rnd(s, m):
    for a, b, c, d, i in [
        (0, 4, 8, 12, 0),
        (1, 5, 9, 13, 2),
        (2, 6, 10, 14, 4),
        (3, 7, 11, 15, 6),
        (0, 5, 10, 15, 8),
        (1, 6, 11, 12, 10),
        (2, 7, 8, 13, 12),
        (3, 4, 9, 14, 14),
    ]:
        g(s, a, b, c, d, m[i], m[i + 1])


def compress(cv, m, counter, block_len, flags):
    s = list(cv) + IV[:4] + [counter & M, (counter >> 32) & M, block_len, flags]
    m = list(m)
    for _ in range(7):
        rnd(s, m)
        m = [m[i] for i in PERM]
    return [s[i] ^ s[i + 8] for i in range(8)]


def words(block):  # 64 bytes, zero-padded, little end first
    b = block + bytes(64 - len(block))
    return [int.from_bytes(b[i : i + 4], "little") for i in range(0, 64, 4)]


def chunk_cv(data, counter, flags):
    cv, n = IV[:], max(1, (len(data) + 63) // 64)
    for i in range(n):
        block = data[i * 64 : (i + 1) * 64]
        f = (CHUNK_START if i == 0 else 0) | ((CHUNK_END | flags) if i == n - 1 else 0)
        cv = compress(cv, words(block), counter, len(block), f)
    return cv


def parent_cv(l, r, flags):
    return compress(IV[:], l + r, 0, 64, PARENT | flags)


def tree(data, counter, root):
    if len(data) <= 1024:
        return chunk_cv(data, counter, ROOT if root else 0)
    nc, left = (len(data) + 1023) // 1024, 1
    while left * 2 < nc:
        left *= 2
    return parent_cv(
        tree(data[: left * 1024], counter, False),
        tree(data[left * 1024 :], counter + left, False),
        ROOT if root else 0,
    )


def hexcv(cv):
    return b"".join(w.to_bytes(4, "little") for w in cv).hex()


def b3(data):
    return hexcv(tree(data, 0, True))


def src(n):  # the official input: the bytes i % 251
    return bytes(i % 251 for i in range(n))


# the published vectors, verbatim from BLAKE3-team/BLAKE3 test_vectors.json.
# Nothing below runs unless every one of them comes back out of the code above.
VEC = {
    0: "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262",
    1: "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213",
    2: "7b7015bb92cf0b318037702a6cdd81dee41224f734684c2c122cd6359cb1ee63",
    3: "e1be4d7a8ab5560aa4199eea339849ba8e293d55ca0a81006726d184519e647f",
    4: "f30f5ab28fe047904037f77b6da4fea1e27241c5d132638d8bedce9d40494f32",
    5: "b40b44dfd97e7a84a996a91af8b85188c66c126940ba7aad2e7ae6b385402aa2",
    6: "06c4e8ffb6872fad96f9aaca5eee1553eb62aed0ad7198cef42e87f6a616c844",
    7: "3f8770f387faad08faa9d8414e9f449ac68e6ff0417f673f602a646a891419fe",
    8: "2351207d04fc16ade43ccab08600939c7c1fa70a5c0aaca76063d04c3228eaeb",
    63: "e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b",
    64: "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98",
    65: "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee",
    127: "d81293fda863f008c09e92fc382a81f5a0b4a1251cba1634016a0f86a6bd640d",
    128: "f17e570564b26578c33bb7f44643f539624b05df1a76c81f30acd548c44b45ef",
    129: "683aaae9f3c5ba37eaaf072aed0f9e30bac0865137bae68b1fde4ca2aebdcb12",
    1023: "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11",
    1024: "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
    1025: "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444",
    2048: "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a",
    2049: "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030",
    3072: "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2",
    3073: "7124b49501012f81cc7f11ca069ec9226cecb8a2c850cfe644e327d22d3e1cd3",
    4096: "015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e969",
    4097: "9b4052b38f1c5fc8b1f9ff7ac7b27cd242487b3d890d15c96a1c25b8aa0fb995",
    5120: "9cadc15fed8b5d854562b26a9536d9707cadeda9b143978f319ab34230535833",
    5121: "628bd2cb2004694adaab7bbd778a25df25c47b9d4155a55f8fbd79f2fe154cff",
    6144: "3e2e5b74e048f3add6d21faab3f83aa44d3b2278afb83b80b3c35164ebeca205",
    6145: "f1323a8631446cc50536a9f705ee5cb619424d46887f3c376c695b70e0f0507f",
    7168: "61da957ec2499a95d6b8023e2b0e604ec7f6b50e80a9678b89d2628e99ada77a",
    7169: "a003fc7a51754a9b3c7fae0367ab3d782dccf28855a03d435f8cfe74605e7817",
    8192: "aae792484c8efe4f19e2ca7d371d8c467ffb10748d8a5a1ae579948f718a2a63",
    8193: "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b",
    16384: "f875d6646de28985646f34ee13be9a576fd515f76b5b0a26bb324735041ddde4",
    31744: "62b6960e1a44bcc1eb1a611a8d6235b6b4b78f32e7abc4fb4c6cdcce94895c47",
    102400: "bc3e3d41a1146b069abffad3c0d44860cf664390afce4d9661f7902e7943e085",
}


def guard():
    bad = [(n, h, b3(src(n))) for n, h in sorted(VEC.items()) if b3(src(n)) != h]
    if bad:
        raise SystemExit(
            "blake3_gen: %d published vectors refused: %r" % (len(bad), bad[:2])
        )


guard()

rows, want = [], []


def row(call, answer):
    rows.append(call)
    want.append(answer)


# 1. the 35 published vectors, whole
for n in sorted(VEC):
    row("one(%dn)" % n, VEC[n])

# 2. a range that is not the whole buffer: off shifts which bytes are hashed,
# and the answer has to be the hash of the slice and nothing about the rest
for tot, off, n in [
    (64, 0, 0),
    (64, 7, 0),
    (64, 1, 63),
    (64, 8, 8),
    (64, 32, 32),
    (300, 1, 255),
    (300, 44, 256),
    (300, 0, 300),
    (300, 299, 1),
    (3000, 100, 1024),
    (3000, 1000, 2000),
    (3000, 5, 2048),
]:
    row(
        "at(%dn, %d, %d)" % (tot, off, n), hexcv(tree(src(tot)[off : off + n], 0, True))
    )

# 3. the chunk counter is in the hash: the same 1,024 bytes at a different
# chunk number is a different chaining value, which is what stops a tree from
# being reordered
for n, t in [
    (0, 0),
    (1, 0),
    (64, 0),
    (1024, 0),
    (1024, 1),
    (1024, 7),
    (1024, 1000),
    (700, 3),
    (65, 9),
]:
    row("leaf(%dn, %d)" % (n, t), hexcv(chunk_cv(src(n), t, 0)))

# 4. the composition the parallel path stands on: two leaves hashed apart and
# joined by parent is the root a single pass prints. If this row and its
# one(...) twin ever disagree, forking the hash is unsound.
for n in [1025, 1500, 2048]:
    row("two(%dn, %d)" % (n, n - 1024), VEC[n] if n in VEC else b3(src(n)))
row("four()", VEC[4096])

print("""# BLAKE3 against the project's own published test vectors (blake3_gen.py prints
# this file). The first 35 rows are test_vectors.json entire -- the same input,
# the bytes i % 251, and the same 64 hex digits the b3sum command prints. The
# rest pin the pieces: a range that is not the whole buffer, a leaf at a chunk
# counter, and a root built by hand out of two and four leaves, which is the
# law a forked hash needs and the only reason blake3_par can fork at all.
import Base
import ../../power/vec.bend as Vec
import ../../power/bytes.bend as Bytes
import ../../power/blake3.bend as B3

# the official input: the bytes i % 251, repeating
def fill(fuel: Nat, +i: U32, b: Bytes.Bytes) -> Bytes.Bytes:
  match fuel:
    case 0n:
      b
    case 1n++p:
      fill(p, U32.inc(i), Bytes.push(b, U32.mod(i, 251)))

def buf(n: Nat) -> Bytes.Bytes:
  fill(n, 0, Bytes.new())

def out(r: Bytes.Bytes & B3.Cv) -> String:
  (b, c) = r
  B3.hex(c)

def one(n: Nat) -> String:
  out(B3.hash_all(buf(n)))

def at(tot: Nat, +off: U32, +n: U32) -> String:
  out(B3.hash(buf(tot), off, n))

def leaf(+n: Nat, t: U32) -> String:
  out(B3.chunk(buf(n), 0, U32.from_nat(n), t, 0))

# two leaves, joined: chunk 0 is the first 1,024 bytes, chunk 1 the rest, and
# the root is their parent with ROOT set
def two.join(c0: B3.Cv, r: Bytes.Bytes & B3.Cv) -> String:
  (b, c1) = r
  B3.hex(B3.parent(c0, c1, 8))

def two.right(+nr: U32, r: Bytes.Bytes & B3.Cv) -> String:
  (b, c0) = r
  two.join(c0, B3.chunk(b, 1024, nr, 1, 0))

def two(n: Nat, +nr: U32) -> String:
  two.right(nr, B3.chunk(buf(n), 0, 1024, 0, 0))

# four leaves: the same law one level deeper, which is the shape a fork tree of
# any depth is made of
def four.d(c0: B3.Cv, c1: B3.Cv, c2: B3.Cv, r: Bytes.Bytes & B3.Cv) -> String:
  (b, c3) = r
  B3.hex(B3.parent(B3.parent(c0, c1, 0), B3.parent(c2, c3, 0), 8))

def four.c(c0: B3.Cv, c1: B3.Cv, r: Bytes.Bytes & B3.Cv) -> String:
  (b, c2) = r
  four.d(c0, c1, c2, B3.chunk(b, 3072, 1024, 3, 0))

def four.b(c0: B3.Cv, r: Bytes.Bytes & B3.Cv) -> String:
  (b, c1) = r
  four.c(c0, c1, B3.chunk(b, 2048, 1024, 2, 0))

def four.a(r: Bytes.Bytes & B3.Cv) -> String:
  (b, c0) = r
  four.b(c0, B3.chunk(b, 1024, 1024, 1, 0))

def four() -> String:
  four.a(B3.chunk(buf(4096n), 0, 1024, 0, 0))

def main() -> IO(Unit):
  do IO<Unit>:""")
for r in rows:
    print("    IO.print(%s)" % r)
for w in want:
    print("#|" + w)
