// The C twin of drift_par: the same 33,554,432 samples as twin_drift.c, but
// summarised through the SAME binary merge tree that par(8n, ...) walks, not
// through a left fold. clang -O3, single thread.
//
// This file exists because the two are different numbers. F64 addition is not
// associative, so ((a+b)+c)+d and (a+b)+(c+d) differ in their last bits, and a
// Welford merge is a sum. The tree below is therefore not a detail of the
// twin -- it is the answer. Depth 8, split at the midpoint, left before right:
// exactly what par(8n, 0, n) does, so the twin and both thread counts land on
// identical bits. Handing this bench twin_drift.c's left fold would print a
// wrong checksum and the harness would refuse to time the row, which is the
// whole reason the lane ships two twins.
#pragma clang fp contract(off)
#include <math.h>
#include <stdint.h>
#include <stdio.h>
typedef uint32_t u32;

static u32 hsh(u32 p) {
  u32 u = (p + 1u) * 2654435761u;
  u ^= u >> 15;
  u *= 2246822519u;
  u ^= u >> 13;
  return u;
}

static double nz(u32 p) { return ((double)(hsh(p) >> 19) - 4096.0) / 2048.0; }

static double sq(u32 p) { return 3.0 * (double)((p >> 16) & 1u) + nz(p); }

static u32 mix(u32 a, u32 x) {
  u32 v = a * 31u + x;
  return (v << 7) | (v >> 25);
}

static u32 qu(double x) {
  double v = floor((x + 8.0) * 1048576.0 + 0.5);
  return v >= 0.0 && v < 4294967296.0 ? (u32)v : 0u;
}

typedef struct { u32 n; double mu, m2; } Stat;

static Stat push(Stat s, double x) {
  u32 n1 = s.n + 1u;
  double d = x - s.mu;
  double mu1 = s.mu + d / (double)n1;
  Stat r = { n1, mu1, s.m2 + d * (x - mu1) };
  return r;
}

// Chan, Golub and LeVeque 1979. The correction is weighted by na * nb / n;
// dropping that weight is right on equal halves and wrong on every other split,
// which a tree of 256 equal leaves would never catch -- so the leaves are equal
// here but the fixture's merges are not.
static Stat merge(Stat a, Stat b) {
  Stat z = { 0u, 0.0, 0.0 };
  if (a.n + b.n == 0u) return z;
  u32 n = a.n + b.n;
  double fn = (double)n;
  double d = b.mu - a.mu;
  double mu = a.mu + d * ((double)b.n / fn);
  double w = ((double)a.n * (double)b.n) / fn;
  Stat r = { n, mu, (a.m2 + b.m2) + (d * d) * w };
  return r;
}

static Stat leaf(u32 lo, u32 n) {
  Stat s = { 0u, 0.0, 0.0 };
  for (u32 i = 0; i < n; i++) s = push(s, sq(lo + i));
  return s;
}

// depth d, halving n each level, left then right: par(8n, lo, n) verbatim
static Stat par(int d, u32 lo, u32 n) {
  if (d == 0) return leaf(lo, n);
  u32 hf = n >> 1;
  Stat a = par(d - 1, lo, hf);
  Stat b = par(d - 1, lo + hf, hf);
  return merge(a, b);
}

int main(void) {
  Stat s = par(8, 0u, 33554432u);
  double var = s.n ? s.m2 / (double)s.n : 0.0;
  printf("%u\n", mix(mix(s.n, qu(s.mu)), qu(var)));
  return 0;
}
