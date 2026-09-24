// The twin of bench/blake3.bend: the same 16 MiB buffer, the same four offsets,
// the same checksum. BLAKE3 here is the reference construction -- a chunk
// stack, the same one power/blake3.bend runs -- written straight from the spec
// so the two sides share no code, only the algorithm.
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

static const uint32_t IV[8] = {0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
                               0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19};
static const uint8_t MSG[7][16] = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8},
    {3, 4, 10, 12, 13, 2, 7, 14, 6, 5, 9, 0, 11, 15, 8, 1},
    {10, 7, 12, 9, 14, 3, 13, 15, 4, 0, 11, 2, 5, 8, 1, 6},
    {12, 13, 9, 11, 15, 10, 14, 8, 7, 2, 5, 3, 0, 1, 6, 4},
    {9, 14, 11, 5, 8, 12, 15, 1, 13, 3, 0, 10, 2, 6, 4, 7},
    {11, 15, 5, 0, 1, 9, 8, 6, 14, 10, 2, 12, 3, 4, 7, 13}};

static uint32_t rotr(uint32_t x, int r) { return (x >> r) | (x << (32 - r)); }

static void g(uint32_t *v, int a, int b, int c, int d, uint32_t x, uint32_t y) {
  v[a] = v[a] + v[b] + x;
  v[d] = rotr(v[d] ^ v[a], 16);
  v[c] = v[c] + v[d];
  v[b] = rotr(v[b] ^ v[c], 12);
  v[a] = v[a] + v[b] + y;
  v[d] = rotr(v[d] ^ v[a], 8);
  v[c] = v[c] + v[d];
  v[b] = rotr(v[b] ^ v[c], 7);
}

// one compression: cv, a 16-word block, the counter, the block length and the
// flags in; the eight-word chaining value out
static void compress(const uint32_t cv[8], const uint32_t m[16], uint64_t t,
                     uint32_t bl, uint32_t fl, uint32_t out[8]) {
  uint32_t v[16];
  memcpy(v, cv, 32);
  memcpy(v + 8, IV, 16);
  v[12] = (uint32_t)t;
  v[13] = (uint32_t)(t >> 32);
  v[14] = bl;
  v[15] = fl;
  for (int r = 0; r < 7; r++) {
    const uint8_t *s = MSG[r];
    g(v, 0, 4, 8, 12, m[s[0]], m[s[1]]);
    g(v, 1, 5, 9, 13, m[s[2]], m[s[3]]);
    g(v, 2, 6, 10, 14, m[s[4]], m[s[5]]);
    g(v, 3, 7, 11, 15, m[s[6]], m[s[7]]);
    g(v, 0, 5, 10, 15, m[s[8]], m[s[9]]);
    g(v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
    g(v, 2, 7, 8, 13, m[s[12]], m[s[13]]);
    g(v, 3, 4, 9, 14, m[s[14]], m[s[15]]);
  }
  for (int i = 0; i < 8; i++) out[i] = v[i] ^ v[i + 8];
}

static void words(const uint8_t *p, size_t n, uint32_t m[16]) {
  uint8_t buf[64] = {0};
  memcpy(buf, p, n);
  for (int i = 0; i < 16; i++)
    m[i] = (uint32_t)buf[4 * i] | ((uint32_t)buf[4 * i + 1] << 8) |
           ((uint32_t)buf[4 * i + 2] << 16) | ((uint32_t)buf[4 * i + 3] << 24);
}

// a chunk's chaining value: CHUNK_START on the first block, CHUNK_END on the
// last, and whatever the caller adds (ROOT, when this chunk is the message)
// rides the last block alone
static void chunk_cv(const uint8_t *p, size_t n, uint64_t t, uint32_t fl,
                     uint32_t out[8]) {
  uint32_t cv[8], m[16];
  memcpy(cv, IV, 32);
  size_t off = 0;
  int i = 0;
  do {
    size_t bl = n - off < 64 ? n - off : 64;
    words(p + off, bl, m);
    uint32_t f = (i == 0 ? 1u : 0u) | (off + 64 >= n ? (2u | fl) : 0u);
    compress(cv, m, t, (uint32_t)bl, f, cv);
    off += 64;
    i++;
  } while (off < n);
  memcpy(out, cv, 32);
}

static void parent_cv(const uint32_t l[8], const uint32_t r[8], uint32_t fl,
                      uint32_t out[8]) {
  uint32_t m[16];
  memcpy(m, l, 32);
  memcpy(m + 8, r, 32);
  compress(IV, m, 0, 64, 4u | fl, out);
}

// the chunk stack, the same construction the Bend side runs: a chaining value
// is merged into the stack once for every low zero bit of the chunk count
static void b3(const uint8_t *p, size_t n, uint32_t out[8]) {
  if (n <= 1024) { chunk_cv(p, n, 0, 8, out); return; }
  uint32_t st[54][8];
  size_t sp = 0;
  uint64_t t = 0;
  size_t off = 0;
  while (n - off > 1024) {
    uint32_t cv[8];
    chunk_cv(p + off, 1024, t, 0, cv);
    t++;
    for (uint64_t k = t; !(k & 1); k >>= 1) {
      sp--;
      parent_cv(st[sp], cv, 0, cv);
    }
    memcpy(st[sp++], cv, 32);
    off += 1024;
  }
  uint32_t cv[8];
  chunk_cv(p + off, n - off, t, 0, cv);
  while (sp) {
    sp--;
    parent_cv(st[sp], cv, sp ? 0 : 8, cv);
  }
  memcpy(out, cv, 32);
}

static uint32_t key(uint32_t i) { return ((i + 1) * 2654435761u) ^ (i >> 3); }
static uint32_t rot7(uint32_t v) { return (v << 7) | (v >> 25); }
static uint32_t mix(uint32_t a, uint32_t x) { return rot7(a * 31u + x); }

#define N 16777216u

int main(void) {
  uint8_t *b = malloc(N);
  for (uint32_t i = 0; i < N; i++) b[i] = (uint8_t)key(i);
  uint32_t acc = 0, cv[8];
  for (uint32_t i = 0; i < 4; i++) {
    b3(b + i, N - i, cv);
    for (int j = 0; j < 8; j++) acc = mix(acc, cv[j]);
  }
  printf("%u\n", acc);
  free(b);
  return 0;
}
