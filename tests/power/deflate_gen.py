#!/usr/bin/env python3
# The oracle for deflate.bend and gzip.bend: prints the whole fixture.
#
# Three authorities, each for the direction it can speak to:
#   - CPython's zlib compresses every inflate row's input (raw deflate,
#     levels 0-9) and decides every malformed row: accepted, with the
#     bytes it decodes to, or refused, its error message mapped to
#     deflate.bend's reason (zlib_why). zlib's own malformed streams
#     from its test suite (test/infcover.c) are among them.
#   - CPython's gzip.decompress decides the gzip rows' member structure
#     (several members, zero padding, trailer checks); zlib's gzip
#     decoder (wbits 31), which also refuses a reserved FLG bit and a bad
#     FHCRC as RFC 1952 asks, decides the header rows gzip.decompress
#     lets through.
#   - Twin, below, is deflate.bend's encoder written again in Python
#     from its comments: the same hash, chains, lazy rule, block split,
#     code lengths and header. A deflate row prints the length and CRC-32
#     of the stream the Bend encoder wrote, which must be the twin's,
#     and the generator asserts that zlib inflates the twin's stream
#     back to the input exactly -- so every deflate row is a stream
#     CPython inflates byte for byte, and one the Bend inflater reads
#     back too.
import gzip
import os
import sys
import random
import struct
import zlib

# Inputs
# ======

def text(n, seed=12345):
    words = ("the of and to in a is that for it as was with be by on not he i this are or his from at "
             "which but have an they you were her she there been one all we their has would when if so "
             "no will more can out about who had them some into time only what could new other than then "
             "server request response header gzip deflate stream window buffer length distance literal "
             "compression huffman table code symbol block bytes data input output chunk proof law bend "
             "parallel thread kernel memory cache latency throughput connection socket client proxy nginx").split()
    x = seed
    out = []
    size = 0
    line = 0
    while size < n:
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        r = (x >> 8) % 1000
        w = words[int(len(words) * (r / 1000.0) ** 2.2)]
        if (x >> 4) % 17 == 0:
            w = w.capitalize()
        if (x >> 3) % 23 == 0:
            w = w + ","
        if (x >> 5) % 29 == 0:
            w = w + str((x >> 10) % 1000)
        out.append(w)
        size += len(w) + 1
        line += len(w) + 1
        if line > 70:
            out.append("\n")
            line = 0
    return " ".join(out).replace(" \n ", "\n").encode()[:n]


rng = random.Random(1951)
INPUTS = [
    ("empty", b""),
    ("one", b"Z"),
    ("rep", b"a" * 20000),
    ("rand", bytes(rng.getrandbits(8) for _ in range(4096))),
    ("text", text(40000)),
]

# The twin encoder
# ================

K64 = 65535
LBASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
         131, 163, 195, 227, 258]
LEXT = [0] * 8 + [1] * 4 + [2] * 4 + [3] * 4 + [4] * 4 + [5] * 4 + [0]
DBASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
         2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
DEXT = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
        13, 13]
CLORD = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
FIXED_LL = [8] * 144 + [9] * 112 + [7] * 24 + [8] * 8
FIXED_D = [5] * 32
LEVELS = {1: (4, 4, 8, 4, False), 2: (4, 5, 16, 8, False), 3: (4, 6, 32, 32, False),
          4: (4, 4, 16, 16, True), 5: (8, 16, 32, 32, True), 6: (8, 16, 128, 128, True),
          7: (8, 32, 128, 256, True), 8: (32, 128, 258, 1024, True), 9: (32, 258, 258, 4096, True)}


def lcode(l):
    k = 0
    for i, b in enumerate(LBASE):
        if b <= l:
            k = i
    return k


def dcode(d):
    k = 0
    for i, b in enumerate(DBASE):
        if b <= d:
            k = i
    return k


def canon(lens):
    cnt = [0] * 16
    for l in lens:
        cnt[l] += 1
    nc = [0] * 17
    code = 0
    cnt[0] = 0
    for b in range(1, 17):
        code = (code + cnt[b - 1]) << 1
        nc[b] = code
    out = []
    for l in lens:
        if l == 0:
            out.append((0, 0))
        else:
            out.append((l, nc[l]))
            nc[l] += 1
    return out


class Bits:
    def __init__(self):
        self.out = bytearray()
        self.acc = 0
        self.n = 0

    def put(self, b):
        self.acc |= (b & 1) << self.n
        self.n += 1
        if self.n == 8:
            self.out.append(self.acc)
            self.acc = 0
            self.n = 0

    def putx(self, n, v):
        for i in range(n):
            self.put((v >> i) & 1)

    def putm(self, n, c):
        for i in range(n - 1, -1, -1):
            self.put((c >> i) & 1)

    def align(self):
        while self.n:
            self.put(0)


def hlens(fs, lim, nsym):
    syms = [(f, s) for s, f in enumerate(fs) if f != 0]
    if len(syms) == 0:
        syms = [(0, 0), (0, 1)]
    elif len(syms) == 1:
        syms = [syms[0], (0, 1 if syms[0][1] == 0 else 0)]
    syms.sort()
    xs = [(f, ("L", s)) for f, s in syms]
    n = len(syms)
    while n > 0 and len(xs) >= 2:
        (wa, ta), (wb, tb) = xs[0], xs[1]
        rest = xs[2:]
        w = wa + wb
        i = 0
        while i < len(rest) and not (w < rest[i][0]):
            i += 1
        xs = rest[:i] + [(w, ("N", ta, tb))] + rest[i:]
        n -= 1
    t = xs[0][1]
    cnt = [0] * (lim + 1)

    def walk(t, d):
        if t[0] == "L":
            cnt[min(d, lim)] += 1
        else:
            walk(t[1], d + 1)
            walk(t[2], d + 1)
    walk(t, 0)
    tot = sum(cnt[i] << (lim - i) for i in range(1, lim + 1))
    while (1 << lim) < tot:
        cnt[lim] -= 1
        i = 0
        for j in range(lim - 1, 0, -1):
            if cnt[j] != 0:
                i = j
                break
        cnt[i] = max(0, cnt[i] - 1)
        cnt[i + 1] += 2
        tot -= 1
    seq = []
    for l in range(lim, 0, -1):
        seq += [l] * cnt[l]
    out = [0] * nsym
    for (f, s), l in zip(syms, seq):
        out[s] = l
    return out


def rle(xs):
    items = []
    i = 0
    while i < len(xs):
        v = xs[i]
        mx = 137 if v == 0 else 6
        r = 1
        while r - 1 < mx and i + r < len(xs) and xs[i + r] == v:
            r += 1
        if v == 0:
            if r < 3:
                items.append((0, 0, 0)); i += 1
            elif r <= 10:
                items.append((17, 3, r - 3)); i += r
            else:
                items.append((18, 7, r - 11)); i += r
        else:
            if r < 4:
                items.append((v, 0, 0)); i += 1
            else:
                items += [(v, 0, 0), (16, 2, r - 4)]; i += r
    return items


def last_used(xs):
    last = 0
    for i, x in enumerate(xs):
        if x != 0:
            last = i + 1
    return last


def dplan(ll, d):
    nlit = max(257, last_used(ll))
    ndist = max(1, last_used(d))
    items = rle(ll[:nlit] + d[:ndist])
    cf = [0] * 19
    for s, x, v in items:
        cf[s] += 1
    cll = hlens(cf, 7, 19)
    pl = [cll[k] for k in CLORD]
    n = max(4, last_used(pl))
    bits = 17 + 3 * n + sum(cll[s] + x for s, x, v in items)
    return nlit, ndist, items, cll, pl, n, bits


def put_body(w, toks, ll, d):
    llc, dc = canon(ll), canon(d)
    for t in toks:
        if t[0] == "L":
            l, c = llc[t[1]]
            w.putm(l, c)
        else:
            _, ln, ds = t
            k = lcode(ln)
            l, c = llc[257 + k]
            w.putm(l, c)
            w.putx(LEXT[k], ln - LBASE[k])
            q = dcode(ds)
            l, c = dc[q]
            w.putm(l, c)
            w.putx(DEXT[q], ds - DBASE[q])
    l, c = llc[256]
    w.putm(l, c)


def stored_all(w, x, at, ln, last):
    while True:
        k = min(ln, K64)
        fin = ln <= K64
        w.put(1 if (fin and last) else 0); w.put(0); w.put(0)
        w.align()
        w.putx(16, k)
        w.putx(16, K64 - k)
        w.out += x[at:at + k]
        at += k
        ln -= k
        if fin:
            break


def block(w, toks, x, at, ln, last, fixed=False):
    fa = [0] * 286
    da = [0] * 30
    xt = 0
    for t in toks:
        if t[0] == "L":
            fa[t[1]] += 1
        else:
            k, q = lcode(t[1]), dcode(t[2])
            fa[257 + k] += 1
            da[q] += 1
            xt += LEXT[k] + DEXT[q]
    fa[256] += 1
    ll, d = hlens(fa, 15, 286), hlens(da, 15, 30)
    nlit, ndist, items, cll, pl, n, hbits = dplan(ll, d)
    st = 8 * ln + 48 * (1 + ln // K64)
    fx = 3 + xt + sum(f * l for f, l in zip(fa, FIXED_LL)) + 5 * sum(da)
    dy = hbits + xt + sum(f * l for f, l in zip(fa, ll)) + sum(f * l for f, l in zip(da, d))
    if fixed:
        w.put(last); w.put(1); w.put(0)
        put_body(w, toks, FIXED_LL, FIXED_D)
    elif st < min(fx, dy):
        stored_all(w, x, at, ln, last)
    elif fx <= dy:
        w.put(last); w.put(1); w.put(0)
        put_body(w, toks, FIXED_LL, FIXED_D)
    else:
        w.put(last); w.put(0); w.put(1)
        w.putx(5, nlit - 257); w.putx(5, ndist - 1); w.putx(4, n - 4)
        for v in pl[:n]:
            w.putx(3, v)
        clc = canon(cll)
        for s, xb, v in items:
            l, c = clc[s]
            w.putm(l, c)
            w.putx(xb, v)
        put_body(w, toks, ll, d)


def twin(x, lvl, fixed=False):
    w = Bits()
    n = len(x)
    if lvl == 0:
        stored_all(w, x, 0, n, True)
        return bytes(w.out)
    good, lazy, nice, chain, slow = LEVELS[min(lvl, 9)]
    head = [0] * 32768
    prev = [0] * 32768

    def h3(i):
        v = 0
        for k in range(3):
            v |= (x[i + k] if i + k < n else 0) << (8 * k)
        return ((v * 2654435761) & 0xFFFFFFFF) >> 17

    def hins(i):
        hh = h3(i)
        old = head[hh]
        head[hh] = i + 1
        prev[i & 32767] = old
        return old

    def ins_run(k, i):
        for p in range(i, i + k):
            if p + 3 <= n:
                hins(p)

    def find(i, k):
        maxl = min(258, n - i)
        cand = hins(i)
        blen = bdist = 0
        go = True
        while k > 0 and go:
            k -= 1
            j = max(0, cand - 1)
            if not (cand != 0 and j < i and i - j <= 32768):
                go = False
                continue
            ml = 0
            while ml < maxl and x[j + ml] == x[i + ml]:
                ml += 1
            nx = prev[j & 32767]
            if blen < ml:
                blen, bdist = ml, i - j
            go = nx < cand and ml < nice
            cand = nx
        if blen == 3 and bdist > 4096:
            return 0, bdist
        return blen, bdist

    i = 0
    toks = []
    tpos = bs = 0
    plen = pdist = 0
    avail = False
    while i < n:
        if len(toks) >= 16383 and not fixed:
            block(w, toks, x, bs, tpos - bs, 0, fixed)
            toks = []
            bs = tpos
        ok = i + 3 <= n
        if not slow:
            ln, ds = find(i, chain) if ok else (0, 0)
            if ln >= 3:
                toks.append(("R", ln, ds))
                ins_run(ln - 1 if ln <= lazy else 0, i + 1)
                i += ln
                tpos += ln
            else:
                toks.append(("L", x[i]))
                i += 1
                tpos += 1
        else:
            k = ((chain // 4 if good <= plen else chain) if plen < lazy else 0)
            ln, ds = find(i, k) if ok else (0, 0)
            if plen >= 3 and ln <= plen:
                toks.append(("R", plen, pdist))
                ins_run(plen - 2, i + 1)
                tpos += plen
                i = i - 1 + plen
                plen = pdist = 0
                avail = False
            elif avail:
                toks.append(("L", x[i - 1]))
                tpos += 1
                i += 1
                plen, pdist = ln, ds
            else:
                i += 1
                plen, pdist = ln, ds
                avail = True
    if avail:
        toks.append(("L", x[n - 1]))
        tpos += 1
    block(w, toks, x, bs, tpos - bs, 1, fixed)
    w.align()
    return bytes(w.out)


def twin_gzip(x, lvl):
    xfl = 2 if lvl == 9 else 4 if lvl == 1 else 0
    return (b"\x1f\x8b\x08\x00\x00\x00\x00\x00" + bytes([xfl, 255]) + twin(x, lvl) +
            struct.pack("<II", zlib.crc32(x), len(x) & 0xFFFFFFFF))

# Authorities
# ===========

def raw(data, lvl):
    c = zlib.compressobj(lvl, zlib.DEFLATED, -15)
    return c.compress(data) + c.flush()


WHY = [
    ("invalid block type", "BadBlock"),
    ("invalid stored block lengths", "BadStored"),
    ("too many length or distance symbols", "BadCounts"),
    ("invalid code lengths set", "BadCl"),
    ("invalid bit length repeat", "BadRepeat"),
    ("missing end-of-block", "NoEnd"),
    ("invalid literal/lengths set", "BadLit"),
    ("invalid distances set", "BadDist"),
    ("invalid literal/length code", "BadCode"),
    ("invalid distance code", "BadCode"),
    ("invalid distance too far back", "FarBack"),
    ("incomplete or truncated stream", "Truncated"),
]


def zlib_inflate(z, cap):
    """what zlib makes of a raw stream: ('ok', bytes) or ('bad', reason)"""
    d = zlib.decompressobj(-15)
    try:
        out = d.decompress(z, cap + 1)
    except zlib.error as e:
        for m, why in WHY:
            if m in str(e):
                return ("bad", why)
        raise
    if len(out) > cap:
        return ("bad", "TooBig")
    if not d.eof:
        return ("bad", "Truncated")
    return ("ok", out)


def show(r):
    if r[0] == "ok":
        return "ok %d %d" % (len(r[1]), zlib.crc32(r[1]))
    return "bad " + r[1]


def gz_ref(z, cap):
    """gzip.decompress, with zlib's gzip decoder refusing what it lets through"""
    try:
        out = gzip.decompress(z)
    except (gzip.BadGzipFile, EOFError, zlib.error, OSError) as e:
        m = str(e)
        if isinstance(e, EOFError):
            return ("bad", "Truncated")
        if "CRC check failed" in m:
            return ("bad", "BadCrc")
        if "Incorrect length" in m:
            return ("bad", "BadSize")
        if "Not a gzipped file" in m:
            return ("bad", "NotGzip")
        if "Unknown compression method" in m:
            return ("bad", "BadMethod")
        for mm, why in WHY:
            if mm in m:
                return ("bad", "Inflate:" + why)
        raise
    # the header checks gzip.decompress skips, member by member
    rest = z
    while rest:
        rest = rest.lstrip(b"\0")
        if not rest:
            break
        d = zlib.decompressobj(31)
        try:
            d.decompress(rest)
        except zlib.error as e:
            if "unknown header flags set" in str(e):
                return ("bad", "BadFlags")
            if "header crc mismatch" in str(e):
                return ("bad", "BadHcrc")
            raise
        rest = d.unused_data
    if len(out) > cap:
        return ("bad", "Inflate:TooBig")
    return ("ok", out)


def member(data, flg=0, extra=b"", name=b"", comment=b"", hcrc=False, lvl=6, crc=None,
           size=None, cm=8, magic=b"\x1f\x8b"):
    f = flg | (4 if extra else 0) | (8 if name else 0) | (16 if comment else 0) | (2 if hcrc else 0)
    h = magic + bytes([cm, f]) + b"\0\0\0\0\x00\xff"
    if extra:
        h += struct.pack("<H", len(extra)) + extra
    if name:
        h += name + b"\0"
    if comment:
        h += comment + b"\0"
    if hcrc:
        h += struct.pack("<H", zlib.crc32(h) & 0xFFFF)
    return h + raw(data, lvl) + struct.pack("<II", zlib.crc32(data) if crc is None else crc,
                                           len(data) if size is None else size)

# Malformed and edge streams
# ==========================

def bits(fields):
    """a raw stream from (n, value) fields, low bit first; ('m', n, code) for a Huffman code"""
    w = Bits()
    for f in fields:
        if f[0] == "m":
            w.putm(f[1], f[2])
        else:
            w.putx(f[0], f[1])
    w.align()
    return bytes(w.out)


def fixed_code(s):
    l, c = canon(FIXED_LL)[s]
    return ("m", l, c)


EOB = fixed_code(256)
FIX = [(1, 1), (2, 1)]  # BFINAL, BTYPE 1
MALFORMED = [
    # zlib's test/infcover.c
    ("zlib stored lengths", "00 00 00 00 00"),
    ("zlib fixed", "03 00"),
    ("zlib block type", "06"),
    ("zlib stored", "01 01 00 fe ff 00"),
    ("zlib too many symbols", "fc 00 00"),
    ("zlib code lengths set", "04 00 fe ff"),
    ("zlib bit length repeat", "04 00 24 49 00"),
    ("zlib bit length repeat 2", "04 00 24 e9 ff ff"),
    ("zlib missing eob", "04 00 24 e9 ff 6d"),
    ("zlib literal set", "04 80 49 92 24 49 92 24 71 ff ff 93 11 00"),
    ("zlib distances set", "04 80 49 92 24 49 92 24 0f b4 ff ff c3 84"),
    ("zlib literal code", "04 c0 81 08 00 00 00 00 20 7f eb 0b 00 00"),
    ("zlib distance code", "02 7e ff ff"),
    ("zlib too far back", "0c c0 81 00 00 00 00 00 90 ff 6b 04 00"),
    ("zlib long code", "05 e0 81 91 24 cb b2 2c 49 e2 0f 2e 8b 9a 47 56 9f fb fe ec d2 ff 1f"),
    ("zlib length extra", "ed c0 01 01 00 00 00 40 20 ff 57 1b 42 2c 4f"),
    ("zlib distance extra", "ed cf c1 b1 2c 47 10 c4 30 fa 6f 35 1d 01 82 59 3d fb be 2e 2a fc 0f 0c"),
    # crafted: the fixed code's symbols no stream may use, a distance
    # before the start, truncations, a block after the last
    ("sym 286", bits(FIX + [fixed_code(286)]).hex()),
    ("sym 287", bits(FIX + [fixed_code(287)]).hex()),
    ("dist 30", bits(FIX + [fixed_code(ord("a")), fixed_code(257), ("m", 5, 30)]).hex()),
    ("dist 31", bits(FIX + [fixed_code(ord("a")), fixed_code(257), ("m", 5, 31)]).hex()),
    ("far by 1", bits(FIX + [fixed_code(ord("a")), fixed_code(257), ("m", 5, 1), EOB]).hex()),
    ("near ok", bits(FIX + [fixed_code(ord("a")), fixed_code(257), ("m", 5, 0), EOB]).hex()),
    ("overlap", bits(FIX + [fixed_code(ord("a")), fixed_code(ord("b")), fixed_code(284), (5, 30),
                            ("m", 5, 1), EOB]).hex()),
    ("len 258", bits(FIX + [fixed_code(ord("q")), fixed_code(285), ("m", 5, 0), EOB]).hex()),
    ("no final", bits([(1, 0), (2, 1), EOB]).hex()),
    ("empty input", ""),
    ("cut header", "05"),
    ("stored cut", "01 05 00 fa ff 61 62"),
    ("two blocks", bits([(1, 0), (2, 1), fixed_code(ord("x")), EOB, (1, 1), (2, 1), fixed_code(ord("y")),
                         EOB]).hex()),
    ("trailing", "03 00 ff ff"),
]

# The fixture
# ===========

# The streams the rows read live in tests/power/deflate.dat, each at
# the offset its row names: a String literal of their size is past what
# the compiler takes. The file is this generator's too: it is checked
# byte for byte against what the generator makes (--write rewrites it).
DAT = bytearray()
AT = {}


def bstr(h):
    z = bytes.fromhex(h)
    if z not in AT:
        AT[z] = len(DAT)
        DAT.extend(z)
    return "blob(dat, U32.to_nat(%d), U32.to_nat(%d))" % (AT[z], len(z))


def main():
    L = []
    rows = []

    def row(line, expect):
        rows.append((line, expect))

    # inflate what CPython compressed, every level
    for name, x in INPUTS:
        for lvl in range(10):
            z = raw(x, lvl)
            assert zlib.decompress(z, -15) == x
            row('IO.print("inflate %s L%d " ++ inf(%s, U32.to_nat(100000000)))' % (name, lvl, bstr(z.hex())),
                "inflate %s L%d ok %d %d" % (name, lvl, len(x), zlib.crc32(x)))
    # deflate: each input got back from its level-9 stream, then written at
    # every level; what the Bend encoder writes must be the twin's, which
    # zlib inflates back to the input
    for name, x in INPUTS:
        z9 = raw(x, 9)
        for lvl in range(10):
            t = twin(x, lvl)
            assert zlib.decompress(t, -15) == x, (name, lvl)
            row('IO.print("deflate %s L%d " ++ enc(%s, %dn))' % (name, lvl, bstr(z9.hex()), lvl),
                "deflate %s L%d %d %d back ok %d %d" % (name, lvl, len(t), zlib.crc32(t), len(x), zlib.crc32(x)))
    # deflate_fixed: the same matches, one block with the fixed code
    for name, x in INPUTS:
        z9 = raw(x, 9)
        for lvl in (1, 4, 9):
            t = twin(x, lvl, True)
            assert zlib.decompress(t, -15) == x, (name, lvl)
            row('IO.print("fixed %s L%d " ++ fix(%s, %dn))' % (name, lvl, bstr(z9.hex()), lvl),
                "fixed %s L%d %d %d back ok %d %d" % (name, lvl, len(t), zlib.crc32(t), len(x), zlib.crc32(x)))
    # malformed and edge streams: as zlib reads them
    for name, h in MALFORMED:
        z = bytes.fromhex(h.replace(" ", ""))
        r = zlib_inflate(z, 100000000)
        row('IO.print("stream %s " ++ inf(%s, U32.to_nat(100000000)))' % (name, bstr(z.hex())),
            "stream %s %s" % (name, show(r)))
    # the cap: a bomb, 64 KiB of zeros in a hundred bytes
    bomb = raw(b"\0" * 65536, 9)
    for cap in (65536, 65535, 1000, 0):
        r = zlib_inflate(bomb, cap)
        row('IO.print("cap %d " ++ inf(%s, U32.to_nat(%d)))' % (cap, bstr(bomb.hex()), cap),
            "cap %d %s" % (cap, show(r)))
    # reads: the text's level-6 stream fed in reads of 1, 7 and 4096
    # bytes, each read's output taken as it comes, is the stream whole
    z = raw(INPUTS[4][1], 6)
    for k in (1, 7, 4096):
        row('IO.print("reads %d " ++ reads(%s, %dn))' % (k, bstr(z.hex()), k),
            "reads %d ok %d %d" % (k, len(INPUTS[4][1]), zlib.crc32(INPUTS[4][1])))
    # CRC-32
    for name, x in INPUTS:
        row('IO.print("crc32 %s " ++ crc(%s))' % (name, bstr(raw(x, 9).hex())),
            "crc32 %s %d" % (name, zlib.crc32(x)))
    # gzip: what gzip.decompress (and zlib's gzip decoder) make of members
    hello = b"hello world " * 20
    GZ = [
        ("plain", member(hello)),
        ("empty file", b""),
        ("empty member", member(b"")),
        ("fname", member(b"abc" * 100, name=b"file.txt")),
        ("all fields", member(b"xyz" * 50, extra=b"\x01\x02\x00\x00", name=b"n", comment=b"a comment",
                              hcrc=True)),
        ("two members", member(b"first ") + member(b"second", lvl=0)),
        ("zero pad", member(b"data") + b"\0\0\0"),
        ("pad between", member(b"a") + b"\0\0" + member(b"b")),
        ("long extra", member(b"q", extra=b"e" * 1000)),
        ("bad crc", member(b"hello", crc=1)),
        ("bad size", member(b"hello", size=7)),
        ("bad magic", member(b"hello", magic=b"\x1f\x8c")),
        ("bad method", member(b"hello", cm=7)),
        ("reserved flag", member(b"hello", flg=0x20)),
        ("bad hcrc", member(b"hello", hcrc=True)[:10] + b"\0\0" + member(b"hello")[10:]),
        ("truncated", member(b"hello world")[:-3]),
        ("garbage after", member(b"hello") + b"xx"),
        ("zero first", b"\0" + member(b"hello")),
        ("bad stream", b"\x1f\x8b\x08\x00\0\0\0\0\x00\xff\x06" + b"\0" * 8),
    ]
    for name, z in GZ:
        row('IO.print("gunzip %s " ++ gun(%s, U32.to_nat(100000000)))' % (name, bstr(z.hex())),
            "gunzip %s %s" % (name, show(gz_ref(z, 100000000))))
    two = member(b"x" * 3000) + member(b"y" * 3000)
    for cap in (6000, 5999, 3000):
        row('IO.print("gunzip cap %d " ++ gun(%s, U32.to_nat(%d)))' % (cap, bstr(two.hex()), cap),
            "gunzip cap %d %s" % (cap, show(gz_ref(two, cap))))
    # gzip: our member for each input, as gzip.decompress reads it back
    for name, x in INPUTS:
        for lvl in (0, 1, 6, 9):
            g = twin_gzip(x, lvl)
            assert gzip.decompress(g) == x
            row('IO.print("gzip %s L%d " ++ gz(%s, %dn))' % (name, lvl, bstr(raw(x, 9).hex()), lvl),
                "gzip %s L%d %d %d back ok %d %d" % (name, lvl, len(g), zlib.crc32(g), len(x), zlib.crc32(x)))

    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "deflate.dat")
    if "--write" in sys.argv:
        open(path, "wb").write(bytes(DAT))
    if not os.path.exists(path) or open(path, "rb").read() != bytes(DAT):
        sys.exit("tests/power/deflate.dat is not what the generator makes: run it with --write")
    print(HEAD, end="")
    print("def main() -> IO(Unit):")
    print("  do IO<Unit>:")
    print('    +dat : Bytes() <- read_all("tests/power/deflate.dat")')
    for line, _ in rows:
        print("    " + line)
    for _, expect in rows:
        print("#|" + expect)


HEAD = '''# Deflate and gzip against CPython (deflate_gen.py prints this file).
# inflate: CPython's zlib streams of five inputs at levels 0-9, read by
# D.inflate. deflate: each input (got back from its level-9 stream)
# written by D.deflate at every level: the stream's length and CRC-32,
# which must be deflate_gen.py's twin encoder's, a stream CPython
# inflates to the input, and what D.inflate reads back. stream: zlib's
# malformed streams and some crafted ones, accepted or refused as zlib
# does. cap: a bomb against the output cap. reads: a stream fed in
# small reads, taken as it goes. gzip and gunzip: members as CPython's
# gzip module and zlib's gzip decoder read them.
import Base
import ../../power/deflate.bend as D
import ../../power/gzip.bend as Z

# The data file, read whole
type Pl is Data:
  More{acc: Bytes()}
  Stop{acc: Bytes()}

def plan.at(acc: Bytes(), +b: Bytes(), empty: Bool) -> Pl:
  match empty:
    case True{}:
      Stop{acc}
    case False{}:
      More{Bytes.append(acc, b)}

def plan(acc: Bytes(), res: Result<&1, &1, U32 & String, Bytes()>) -> Pl:
  match res:
    case Fail{e}:
      Stop{acc}
    case Done{+b}:
      plan.at(acc, b, Nat.is_eq(Bytes.len(b), 0n))

def plan2(acc: Bytes(), r: File & Result<&1, &1, U32 & String, Bytes()>) -> File & Pl:
  (f, res) = r
  (f, plan(acc, res))

def loop(n: Nat, fp: File & Pl) -> IO(Bytes()):
  match n:
    case 0n:
      (f, pl) = fp
      match pl:
        case More{acc}:
          do IO<Bytes()>:
            File.close(f)
            return acc
        case Stop{acc}:
          do IO<Bytes()>:
            File.close(f)
            return acc
    case 1n+p:
      (f, pl) = fp
      match pl:
        case Stop{acc}:
          do IO<Bytes()>:
            File.close(f)
            return acc
        case More{acc}:
          IO.bind(File & Result<&1, &1, U32 & String, Bytes()>, Bytes(), File.read_buf(f, 1048576),
            r => loop(p, plan2(acc, r)))

def read_all(path: String) -> IO(Bytes()):
  do IO<Bytes()>:
    f : File <- IO.try(File, File.open(path, "r"))
    loop(64n, (f, More{""}))

def res(r: Result<&2, &2, D.Why, Bytes()>) -> String:
  match r:
    case Done{+b}:
      "ok " ++ Nat.show(Bytes.len(b)) ++ " " ++ U32.show(D.crc32(b, 0))
    case Fail{why}:
      "bad " ++ D.why.show(why)

def gres(r: Result<&2, &2, Z.Err, Bytes()>) -> String:
  match r:
    case Done{+b}:
      "ok " ++ Nat.show(Bytes.len(b)) ++ " " ++ U32.show(D.crc32(b, 0))
    case Fail{Z.Err{at, why}}:
      "bad " ++ Z.why.show(why)

def blob(+dat: Bytes(), +off: Nat, +len: Nat) -> Bytes():
  Bytes.slice(dat, off, len)

def inf(+b: Bytes(), cap: Nat) -> String:
  res(D.inflate(cap, b))

def gun(+b: Bytes(), cap: Nat) -> String:
  gres(Z.gunzip(cap, b))

def got(r: Result<&2, &2, D.Why, Bytes()>) -> Bytes():
  match r:
    case Done{b}:
      b
    case Fail{e}:
      ""

# x written at lvl: the stream's length and CRC-32, then what reads back
def enc.at(+z: Bytes()) -> String:
  Nat.show(Bytes.len(z)) ++ " " ++ U32.show(D.crc32(z, 0)) ++ " back " ++
    res(D.inflate(U32.to_nat(100000000), z))

def fix(+b: Bytes(), lvl: Nat) -> String:
  enc.at(D.deflate_fixed(got(D.inflate(U32.to_nat(100000000), b)), lvl))

def enc(+b: Bytes(), lvl: Nat) -> String:
  enc.at(D.deflate(got(D.inflate(U32.to_nat(100000000), b)), lvl))

def gz.at(+z: Bytes()) -> String:
  Nat.show(Bytes.len(z)) ++ " " ++ U32.show(D.crc32(z, 0)) ++ " back " ++
    gres(Z.gunzip(U32.to_nat(100000000), z))

def gz(+b: Bytes(), lvl: Nat) -> String:
  gz.at(Z.gzip(got(D.inflate(U32.to_nat(100000000), b)), lvl))

def crc(+b: Bytes()) -> String:
  U32.show(D.crc32(got(D.inflate(U32.to_nat(100000000), b)), 0))

def reads.fin(r: Result<&2, &2, D.Why, Bytes()>, acc: Bytes()) -> Result<&2, &2, D.Why, Bytes()>:
  match r:
    case Done{b}:
      Done{Bytes.append(acc, b)}
    case Fail{e}:
      Fail{e}

# the stream in reads of k bytes, each read's output taken as it comes
def reads.go(n: Nat, +s: Bytes(), +k: Nat, r: Bytes() & D.St, acc: Bytes()) ->
  Result<&2, &2, D.Why, Bytes()>:
  match n:
    case 0n:
      (b, st) = r
      reads.fin(D.finish(st), Bytes.append(acc, b))
    case 1n+p:
      (b, st) = r
      reads.go(p, Bytes.drop(s, k), k, D.take(D.feed(Bytes.slice(s, 0n, k), st)),
        Bytes.append(acc, b))

def reads(+s: Bytes(), +k: Nat) -> String:
  res(reads.go(1n+Nat.div(Bytes.len(s), k), s, k, ("", D.new(U32.to_nat(100000000))), ""))

'''

if __name__ == "__main__":
    main()
