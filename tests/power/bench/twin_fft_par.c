// The C twin of tests/power/bench/fft_par.bend: 256 independent 16,384-point
// transforms, each folded to a u32, combined a*31 + b up the same balanced
// tree in the same order. Single-threaded, like every other twin here -- the
// row it feeds is "one core of C against n cores of Bend", and the scaling
// question is answered by Bend's own 1T column beside its 16T one.
//
// FP_CONTRACT off for the same reason as twin_fft.c: the checksum is over raw
// IEEE-754 bits, and an FMA would round once where Bend rounds twice.
#pragma STDC FP_CONTRACT OFF

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define D 14
#define N (1u << D)
#define K 8

typedef struct {
  float re, im;
} cf;

static cf cadd(cf a, cf b) { return (cf){a.re + b.re, a.im + b.im}; }
static cf csub(cf a, cf b) { return (cf){a.re - b.re, a.im - b.im}; }

static cf cmul(cf a, cf b) {
  return (cf){a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re};
}

static cf half(int j) {
  cf c = {-1.0f, 0.0f};
  for (int k = 0; k < j; k++) {
    c = (cf){sqrtf((1.0f + c.re) / 2.0f), sqrtf((1.0f - c.re) / 2.0f)};
  }
  return c;
}

static cf kernel(int p) {
  cf h = half(p);
  return (cf){h.re, -h.im};
}

static void table(cf *t, unsigned m, cf b) {
  t[0] = (cf){1.0f, 0.0f};
  for (unsigned k = 1; k < m; k++) {
    if ((k & 1u) == 0u) {
      cf x = t[k >> 1];
      t[k] = cmul(x, x);
    } else {
      t[k] = cmul(t[k - 1], b);
    }
  }
}

static void split(const cf *s, cf *e, cf *o, unsigned m) {
  for (unsigned i = 0; i < m; i++) {
    e[i] = s[2 * i];
    o[i] = s[2 * i + 1];
  }
}

static void comb(const cf *a, const cf *b, cf *out, unsigned m, int p) {
  cf *t = malloc((size_t)m * sizeof(cf));
  table(t, m, kernel(p));
  for (unsigned k = 0; k < m; k++) {
    cf x = cmul(t[k], b[k]);
    out[k] = cadd(a[k], x);
    out[k + m] = csub(a[k], x);
  }
  free(t);
}

static void go(int d, const cf *e, const cf *o, cf *out) {
  if (d == 0) {
    comb(e, o, out, 1u, 0);
    return;
  }
  int p = d - 1;
  unsigned m = 1u << p;
  cf *ee = malloc((size_t)m * sizeof(cf)), *eo = malloc((size_t)m * sizeof(cf));
  cf *oe = malloc((size_t)m * sizeof(cf)), *oo = malloc((size_t)m * sizeof(cf));
  split(e, ee, eo, m);
  split(o, oe, oo, m);
  cf *A = malloc((size_t)(2u * m) * sizeof(cf));
  cf *B = malloc((size_t)(2u * m) * sizeof(cf));
  go(p, ee, eo, A);
  go(p, oe, oo, B);
  comb(A, B, out, 2u * m, p + 1);
  free(ee); free(eo); free(oe); free(oo); free(A); free(B);
}

static void fft(const cf *in, cf *out, int d) {
  if (d == 0) {
    out[0] = in[0];
    return;
  }
  int p = d - 1;
  unsigned m = 1u << p;
  cf *e = malloc((size_t)m * sizeof(cf)), *o = malloc((size_t)m * sizeof(cf));
  split(in, e, o, m);
  go(p, e, o, out);
  free(e); free(o);
}

static uint32_t bits(float f) {
  uint32_t u;
  memcpy(&u, &f, sizeof u);
  return u;
}

static uint32_t leaf(uint32_t s) {
  cf *in = malloc((size_t)N * sizeof(cf));
  cf *out = malloc((size_t)N * sizeof(cf));
  for (unsigned i = 0; i < N; i++) {
    uint32_t h = (i + s + 1u) * 2654435761u ^ (i >> 3);
    in[i].re = (float)(h & 0xFFFFu) / 65536.0f;
    in[i].im = 0.0f;
  }
  fft(in, out, D);
  uint32_t acc = 0;
  for (unsigned i = 0; i < N; i++) {
    acc = acc * 31u + bits(out[i].re);
    acc = acc * 31u + bits(out[i].im);
  }
  free(in);
  free(out);
  return acc;
}

static uint32_t tree(int k, uint32_t lo) {
  if (k == 0) return leaf(lo);
  uint32_t a = tree(k - 1, lo * 2u);
  uint32_t b = tree(k - 1, lo * 2u + 1u);
  return a * 31u + b;
}

int main(void) {
  printf("%u\n", tree(K, 0));
  return 0;
}
