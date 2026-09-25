// The C twin of delta.bend: the same hash, the same element encoding, the same
// three bilinear terms in the same order, the same consolidation rule and the
// same mixer, so the two sides print the same number or one of them is wrong.
//
// The shapes here are the ones the Bend file uses and not the ones C would
// reach for. A Z-set is two columns' worth of (element, weight) rows;
// consolidate is a sort on the element plus a run sum that DROPS every
// total-zero row, which is the rule the whole lane turns on; and the join is a
// probe -- binary search the kept side's key column, walk the run -- because a
// hash join would measure a different algorithm. qsort stands in for
// power/radix.bend's LSD radix: within one key the two orders differ, and they
// are allowed to, because the output is consolidated before it is ever read.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define NA 1024
#define NB 8192
#define ND 8
#define BB 1000000000u
#define BD 2000000000u
#define STEPS 128
#define OUT (1 << 14)

static uint32_t h(uint32_t p) { return ((p + 1u) * 2654435761u) ^ (p >> 3); }

static uint32_t emk(uint32_t x) { return ((x & 127u) << 8) + ((x >> 8) & 255u); }

static uint32_t el(uint32_t p) { return emk(h(p)); }

static uint32_t wt(uint32_t p) { return 1u + (h(p + 7777u) & 1u); }

static uint32_t dwt(uint32_t p) { return 1u - 2u * (h(p + 31337u) & 1u); }

static uint32_t kf(uint32_t x) { return x >> 8; }

static uint32_t jf(uint32_t x, uint32_t y) { return (x << 8) + (y & 255u); }

static uint32_t rot7(uint32_t v) { return (v << 7) | (v >> 25); }

static uint32_t mix(uint32_t a, uint32_t x) { return rot7(a * 31u + x); }

typedef struct {
  uint32_t e, w;
} Row;

static int cmp_e(const void *a, const void *b) {
  uint32_t x = ((const Row *)a)->e, y = ((const Row *)b)->e;
  return x < y ? -1 : x > y ? 1 : 0;
}

static int cmp_k(const void *a, const void *b) {
  uint32_t x = kf(((const Row *)a)->e), y = kf(((const Row *)b)->e);
  return x < y ? -1 : x > y ? 1 : 0;
}

// consolidate: one row an element, elements ascending, and no zero weight
// anywhere -- a retraction that cancelled an insert leaves NO ROW
static int cons(Row *r, int n) {
  qsort(r, n, sizeof(Row), cmp_e);
  int o = 0;
  for (int i = 0; i < n;) {
    uint32_t e = r[i].e, s = 0;
    int j = i;
    while (j < n && r[j].e == e) s += r[j++].w;
    if (s) {
      r[o].e = e;
      r[o].w = s;
      o++;
    }
    i = j;
  }
  return o;
}

static int probe(const Row *xs, int nx, const Row *ys, int ny, int flip, Row *out,
                 int o) {
  for (int i = 0; i < nx; i++) {
    uint32_t k = kf(xs[i].e);
    int lo = 0, hi = ny;
    while (lo < hi) {
      int m = lo + ((hi - lo) >> 1);
      if (kf(ys[m].e) < k) lo = m + 1; else hi = m;
    }
    for (int j = lo; j < ny && kf(ys[j].e) == k; j++) {
      out[o].e = flip ? jf(ys[j].e, xs[i].e) : jf(xs[i].e, ys[j].e);
      out[o].w = xs[i].w * ys[j].w;
      o++;
    }
  }
  return o;
}

// the row count first, then every (element, weight) ascending. The count is
// meant to catch a consolidation that kept a zero-weight row; measured, it does
// not -- at these sizes the terms never cancel to zero. The fixture pins it.
static uint32_t sum(uint32_t acc, const Row *r, int n) {
  acc = mix(acc, (uint32_t)n);
  for (int i = 0; i < n; i++) acc = mix(mix(acc, r[i].e), r[i].w);
  return acc;
}

static void mk(Row *r, uint32_t base, int n) {
  for (int i = 0; i < n; i++) {
    r[i].e = el(base + (uint32_t)i);
    r[i].w = wt(base + (uint32_t)i);
  }
}

static void dk(Row *r, uint32_t base, int n) {
  for (int i = 0; i < n; i++) {
    r[i].e = el(base + (uint32_t)i);
    r[i].w = dwt(base + (uint32_t)i);
  }
}

static Row a[NA], b[NB], da[ND], db[ND], out[OUT];

int main(void) {
  mk(a, 0, NA);
  mk(b, BB, NB);
  qsort(a, NA, sizeof(Row), cmp_k);
  qsort(b, NB, sizeof(Row), cmp_k);
  uint32_t acc = 0, p = BD;
  for (int s = 0; s < STEPS; s++, p += 16u) {
    dk(da, p, ND);
    dk(db, p + ND, ND);
    qsort(da, ND, sizeof(Row), cmp_k);
    qsort(db, ND, sizeof(Row), cmp_k);
    int o = 0;
    o = probe(da, ND, b, NB, 0, out, o);   // da join b
    o = probe(db, ND, a, NA, 1, out, o);   // a join db, the sides kept straight
    o = probe(da, ND, db, ND, 0, out, o);  // da join db, the second-order term
    o = cons(out, o);
    acc = sum(acc, out, o);
  }
  printf("%u\n", acc);
  return 0;
}
