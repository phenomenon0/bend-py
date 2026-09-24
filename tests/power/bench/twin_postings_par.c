// The C twin of tests/power/bench/postings_par.bend: the same 256 shards of 32
// rounds, the same seed split, the same `mix` combine up the same depth-8
// tree -- walked in one thread, which is the point. This column is the work,
// the Bend columns beside it are whether the work forks.
//
// Everything above main() is twin_postings.c verbatim. It is duplicated rather
// than shared because the harness compiles each twin_*.c on its own and two
// benches sharing a header would make either one's edit silently retime the
// other.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define N 65536u          // the universe
#define W (N / 32u)       // words in a dense set
#define CUT (N / 32u)     // optimize densifies above this many ids

typedef struct {
  int dense;
  uint32_t *ids;  // ascending, unique, when !dense
  uint32_t n;     // ids held, when !dense
  uint32_t *w;    // one bit per id, when dense
} set;

static set sparse_new(uint32_t cap) {
  set s = {0, malloc((size_t)cap * sizeof(uint32_t)), 0, NULL};
  return s;
}

static set dense_new(void) {
  set s = {1, NULL, 0, calloc(W, sizeof(uint32_t))};
  return s;
}

static void set_free(set *s) {
  free(s->ids);
  free(s->w);
  s->ids = NULL;
  s->w = NULL;
}

static void dense_set(set *s, uint32_t x) { s->w[x >> 5] |= 1u << (x & 31u); }

static int dense_get(const set *s, uint32_t x) {
  return (s->w[x >> 5] >> (x & 31u)) & 1u;
}

// optimize: a sparse set costs one word an id, a dense one W words whatever it
// holds, so the cheaper shape flips at N/32 ids. Roaring's rule with its fixed
// 4096 replaced by the universe the set is actually over.
static set optimize(set s) {
  if (s.dense || s.n <= CUT) return s;
  set d = dense_new();
  for (uint32_t i = 0; i < s.n; i++) dense_set(&d, s.ids[i]);
  set_free(&s);
  return d;
}

static uint32_t fold_hi(uint32_t h) { return h ^ (h >> 16); }
static uint32_t hsh(uint32_t s) { return fold_hi((s + 1u) * 2654435761u); }
static uint32_t bg(uint32_t s) { return hsh(s) & 63u; }
static uint32_t st(uint32_t s) { return ((hsh(s) >> 8) & 63u) + 1u; }
static uint32_t st8(uint32_t s) { return ((hsh(s) >> 20) & 7u) + 1u; }

static set mk(uint32_t k, uint32_t x, uint32_t d) {
  set s = sparse_new(k);
  for (uint32_t i = 0; i < k; i++) {
    s.ids[s.n++] = x;
    x += d;
  }
  return optimize(s);
}

static set sp(uint32_t seed) { return mk(512u, bg(seed), st(seed)); }
static set dn(uint32_t seed) { return mk(4096u, bg(seed), st8(seed)); }

// and(sparse, sparse): one left-to-right merge, emitting what both hold
static set and_ss(set a, set b) {
  set o = sparse_new(a.n < b.n ? a.n : b.n);
  uint32_t i = 0, j = 0;
  while (i < a.n && j < b.n) {
    if (a.ids[i] < b.ids[j]) i++;
    else if (a.ids[i] > b.ids[j]) j++;
    else { o.ids[o.n++] = a.ids[i]; i++; j++; }
  }
  set_free(&a);
  set_free(&b);
  return o;
}

// or(dense, dense): the cell loop, 32 ids an iteration, no allocation past the
// answer itself
static set or_dd(set a, set b) {
  set o = dense_new();
  for (uint32_t i = 0; i < W; i++) o.w[i] = a.w[i] | b.w[i];
  set_free(&a);
  set_free(&b);
  return o;
}

// and(sparse, dense): the sparse side bounds the answer, so sieve it through
// the other's bits and stay sparse -- the answer costs that side, not the
// universe
static set and_sd(set a, set b) {
  set o = sparse_new(a.n);
  for (uint32_t i = 0; i < a.n; i++) {
    if (dense_get(&b, a.ids[i])) o.ids[o.n++] = a.ids[i];
  }
  set_free(&a);
  set_free(&b);
  return o;
}

// or(sparse, dense): the dense side absorbs the answer, so paint the sparse
// ids in and stay dense
static set or_sd(set a, set b) {
  set o = dense_new();
  memcpy(o.w, b.w, (size_t)W * sizeof(uint32_t));
  for (uint32_t i = 0; i < a.n; i++) dense_set(&o, a.ids[i]);
  set_free(&a);
  set_free(&b);
  return o;
}

// the answer's ids in order, whatever shape held them
static uint32_t fold(uint32_t acc, set s) {
  if (s.dense) {
    for (uint32_t i = 0; i < W; i++) {
      uint32_t w = s.w[i];
      while (w) {
        uint32_t b = w & (uint32_t)(-(int32_t)w);  // lowest set bit
        uint32_t k = __builtin_ctz(w);
        acc = acc * 31u + (i * 32u + k);
        w ^= b;
      }
    }
  } else {
    for (uint32_t i = 0; i < s.n; i++) acc = acc * 31u + s.ids[i];
  }
  set_free(&s);
  return acc;
}

static uint32_t rnd(uint32_t b, uint32_t acc) {
  acc = fold(acc, and_ss(sp(b), sp(b + 1)));
  acc = fold(acc, or_dd(dn(b + 2), dn(b + 3)));
  acc = fold(acc, and_sd(sp(b + 4), dn(b + 5)));
  acc = fold(acc, or_sd(sp(b + 6), dn(b + 7)));
  return acc;
}

static uint32_t rot7(uint32_t v) { return (v << 7) | (v >> 25); }
static uint32_t mix(uint32_t a, uint32_t x) { return rot7(a * 31u + x); }

static uint32_t leaf(uint32_t lo) {
  uint32_t acc = 0;
  for (uint32_t j = 0; j < 32u; j++) acc = rnd(lo * 256u + j * 8u, acc);
  return acc;
}

static uint32_t tree(uint32_t k, uint32_t lo) {
  if (k == 0u) return leaf(lo);
  uint32_t a = tree(k - 1u, lo * 2u);
  uint32_t b = tree(k - 1u, lo * 2u + 1u);
  return mix(a, b);
}

int main(void) {
  printf("%u\n", tree(8u, 0u));
  return 0;
}
