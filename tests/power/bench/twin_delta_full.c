// The C twin of delta_full.bend: the same 128 updates, answered the way a system
// with no delta operators has to answer them. Rebuild both relations, join them
// whole, join the changed ones whole, subtract. Every helper above main is
// twin_delta.c's verbatim, because the two twins have to start from identical
// data or the C ratio measures the data instead of the algorithm.
//
// This is the honest reference for the recompute side: same language, same
// compiler, same probe join, same consolidation. Whatever the Bend pair's ratio
// turns out to be, this pair says how much of it is DBSP and how much is Bend.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define NA 1024
#define NB 8192
#define ND 8
#define BB 1000000000u
#define BD 2000000000u
#define STEPS 128
#define OUT (1 << 17)
#define DIF (1 << 18)

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

static Row a[NA + ND], b[NB + ND], out0[OUT], out1[OUT], dif[DIF];

int main(void) {
  uint32_t acc = 0, p = BD;
  for (int s = 0; s < STEPS; s++, p += 16u) {
    // the join as it stood: both relations rebuilt, both indexed, joined whole
    mk(a, 0, NA);
    mk(b, BB, NB);
    qsort(a, NA, sizeof(Row), cmp_k);
    qsort(b, NB, sizeof(Row), cmp_k);
    int n0 = cons(out0, probe(a, NA, b, NB, 0, out0, 0));
    // the join as it now stands: the change folded in, then the same whole join
    mk(a, 0, NA);
    dk(a + NA, p, ND);
    int na = cons(a, NA + ND);
    qsort(a, na, sizeof(Row), cmp_k);
    mk(b, BB, NB);
    dk(b + NB, p + ND, ND);
    int nb = cons(b, NB + ND);
    qsort(b, nb, sizeof(Row), cmp_k);
    int n1 = cons(out1, probe(a, na, b, nb, 0, out1, 0));
    // and the delta, recovered by subtraction instead of computed
    for (int i = 0; i < n1; i++) dif[i] = out1[i];
    for (int i = 0; i < n0; i++) {
      dif[n1 + i].e = out0[i].e;
      dif[n1 + i].w = -out0[i].w;
    }
    acc = sum(acc, dif, cons(dif, n1 + n0));
  }
  printf("%u\n", acc);
  return 0;
}
