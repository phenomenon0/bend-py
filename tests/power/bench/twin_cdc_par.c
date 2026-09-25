// The twin of bench/cdc_par.bend: 256 shards of 64 KiB, each cut four times,
// the 256 leaf checksums folded up a perfect binary tree. It reproduces the
// fork's shape rather than its threads -- the shards are independent by
// construction, so a serial walk of them must land on the same root, which is
// what makes the row a check on the fork and not only on the chunker.
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

static const int ROT[8] = {13, 15, 26, 6, 17, 29, 16, 24};

static uint32_t rotl(uint32_t x, int r) { return (x << r) | (x >> (32 - r)); }

static uint32_t threefry(uint32_t k0, uint32_t k1, uint32_t c0, uint32_t c1) {
  uint32_t ks[3] = {k0, k1, k0 ^ k1 ^ 0x1BD11BDAu};
  uint32_t a = c0 + ks[0], b = c1 + ks[1];
  for (int r = 0; r < 20; r++) {
    a += b;
    b = rotl(b, ROT[r % 8]) ^ a;
    if (r % 4 == 3) {
      int n = r / 4 + 1;
      a += ks[n % 3];
      b += ks[(n + 1) % 3] + (uint32_t)n;
    }
  }
  return a;
}

static uint32_t GEAR[256];

// the masks read the top bits of the rolling hash: under h = (h << 1) + gear[b]
// bit k has only seen the last k + 1 bytes
static uint32_t topmask(uint32_t k) { return (((1u << k) - 1u) << (32 - k)); }

// one cut: nothing tested below off + avg/4, a two-bits-stricter mask up to
// off + avg, a two-bits-looser one up to off + avg*8, and a forced cut there
static uint32_t cut(const uint8_t *d, uint32_t off, uint32_t end, uint32_t bits) {
  uint32_t a = 1u << bits;
  uint32_t lo = off + a / 4 < end ? off + a / 4 : end;
  uint32_t md = off + a < end ? off + a : end;
  uint32_t hi = off + a * 8 < end ? off + a * 8 : end;
  uint32_t h = 0, i = lo;
  uint32_t stop[2] = {md, hi};
  uint32_t msk[2] = {topmask(bits + 2), topmask(bits - 2)};
  for (int s = 0; s < 2; s++)
    while (i < stop[s]) {
      h = (h << 1) + GEAR[d[i]];
      i++;
      if (!(h & msk[s])) return i - off;
    }
  return hi - off;
}

static uint32_t rot7(uint32_t v) { return (v << 7) | (v >> 25); }
static uint32_t mix(uint32_t a, uint32_t x) { return rot7(a * 31u + x); }
// the join: * 31 loses the low five bits a level, which eight levels of tree
// turn into a word of nothing; an odd multiplier loses none at any depth
static uint32_t tmix(uint32_t a, uint32_t b) { return rot7(a * 2654435761u + b); }

static uint32_t split(const uint8_t *d, uint32_t n, uint32_t bits, uint32_t acc) {
  uint32_t off = 0;
  while (off < n) {
    off += cut(d, off, n, bits);
    acc = mix(acc, off);
  }
  return acc;
}

static uint32_t key(uint32_t i) { return ((i + 1) * 2654435761u) ^ (i >> 3); }

#define SHARDS 256u
#define SHARD 65536u

int main(void) {
  for (int i = 0; i < 256; i++) GEAR[i] = threefry(2654435761u, 0, (uint32_t)i, 0);
  uint32_t n = SHARDS * SHARD;
  uint8_t *b = malloc(n);
  for (uint32_t i = 0; i < n; i++) b[i] = (uint8_t)key(i);
  uint32_t *leaf = malloc(SHARDS * sizeof(uint32_t));
  for (uint32_t s = 0; s < SHARDS; s++) {
    uint32_t acc = 0;
    for (uint32_t bits = 8; bits <= 14; bits += 2)
      acc = split(b + s * SHARD, SHARD, bits, acc);
    leaf[s] = acc;
  }
  // the same perfect binary tree the fork builds, bottom up
  for (uint32_t w = 1; w < SHARDS; w <<= 1)
    for (uint32_t s = 0; s + w < SHARDS; s += 2 * w)
      leaf[s] = tmix(leaf[s], leaf[s + w]);
  printf("%u\n", leaf[0]);
  free(leaf);
  free(b);
  return 0;
}
