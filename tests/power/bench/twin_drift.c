// The C twin of the drift bench: one Page-Hinkley detector over 33,554,432
// samples of a square wave, Welford underneath it, clang -O3, single thread.
//
// Contraction is off because bend2/comp.ts:3716 turns it off for the emitted C.
// An FMA folds a multiply and an add into one rounding instead of two, which is
// a BETTER answer and a different one; the checksum below mixes quantized means
// at 2^-20, so one fused step in the wrong place is enough to disagree.
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

// [-2, 2) in steps of 1/2048, exact in f64 on both sides
static double nz(u32 p) { return ((double)(hsh(p) >> 19) - 4096.0) / 2048.0; }

static double sq(u32 p) { return 3.0 * (double)((p >> 16) & 1u) + nz(p); }

static u32 mix(u32 a, u32 x) {
  u32 v = a * 31u + x;
  return (v << 7) | (v >> 25);
}

// F64.round is floor(x + 0.5) in base.bend, not C's round (half away from
// zero). They differ on exact halves, and a quantum boundary is exactly where
// a mean can land, so this has to be floor.
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

// the inverse of Chan's merge: what the suffix saw, given the whole and its
// prefix. The "after" window of a report is this, never a buffer of samples.
static Stat tail(Stat w, Stat h) {
  Stat z = { 0u, 0.0, 0.0 };
  if (w.n <= h.n) return z;
  u32 nb = w.n - h.n;
  double fn = (double)w.n, fa = (double)h.n, fb = (double)nb;
  double mb = (fn * w.mu - fa * h.mu) / fb;
  double d = mb - h.mu;
  double ww = (fa * fb) / fn;
  Stat r = { nb, mb, (w.m2 - h.m2) - (d * d) * ww };
  return r;
}

int main(void) {
  const double delta = 0.5, lam = 16.0;
  const u32 warm = 30u;
  Stat w = { 0u, 0.0, 0.0 }, mark = { 0u, 0.0, 0.0 };
  double cum = 0.0, ext = 0.0;
  u32 s = 0u;
  for (u32 p = 0; p < 33554432u; p++) {
    double x = sq(p);
    Stat w1 = push(w, x);
    double c = cum + ((x - w1.mu) - delta);
    Stat mk = mark;
    double e = ext;
    if (c < ext) { e = c; mk = w1; }
    if (w1.n >= warm && (c - e) > lam) {
      Stat after = tail(w1, mk);
      s = mix(s, w1.n);
      s = mix(s, mk.n);
      s = mix(s, qu(mk.mu));
      s = mix(s, qu(after.mu));
      w.n = 0u; w.mu = 0.0; w.m2 = 0.0;
      mark = w; cum = 0.0; ext = 0.0;
    } else {
      w = w1; cum = c; ext = e; mark = mk;
    }
  }
  printf("%u\n", mix(s, w.n));
  return 0;
}
