// The C twin of gemv.bend: the same hash, the same floats, the same row dot
// product in the same order, the same result vector read back in the same
// order and the same mixer, so the two sides print the same number or one of
// them is wrong. `twin_gemv small` runs the size the interpreter can reach,
// which is how the interpret lane is held against this same code.
//
// The dot product is left strictly ordered on purpose. Without -ffast-math
// clang will not reassociate a float reduction, so this stays scalar -- which
// is the honest twin of a Bend fold, and a vectorized C would be measuring a
// transform Bend was never asked to make. The product is its own statement so
// that -ffp-contract, whose default is per-statement, cannot fuse it into an
// FMA and round once where Bend rounds twice.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define MAXM 512
#define MAXK 512

static uint32_t h(uint32_t p) { return ((p + 1u) * 2654435761u) ^ (p >> 3); }

static float v(uint32_t p) {
  return ((float)(h(p) >> 19) - 4096.0f) / 128.0f;
}

static uint32_t bits(float x) {
  uint32_t b;
  memcpy(&b, &x, 4);
  return b;
}

static uint32_t mix(uint32_t a, uint32_t x) {
  uint32_t t = a * 31u + x;
  return (t << 7) | (t >> 25);
}

static float w[(size_t)MAXM * MAXK];
static float xv[MAXK];
static float y[MAXM];

static float dot(const float *a, const float *b, int k) {
  float s = 0.0f;
  for (int c = 0; c < k; c++) {
    float p = a[c] * b[c];
    s = s + p;
  }
  return s;
}

static uint32_t run(int m, int k, int steps) {
  for (uint32_t p = 0; p < (uint32_t)(m * k); p++) w[p] = v(p);
  uint32_t acc = 0;
  for (int t = 0; t < steps; t++) {
    uint32_t base = 1073741824u + (uint32_t)(t * k);
    for (int c = 0; c < k; c++) xv[c] = v(base + (uint32_t)c);
    for (int i = 0; i < m; i++) y[i] = dot(&w[(size_t)i * k], xv, k);
    for (int i = 0; i < m; i++) acc = mix(acc, bits(y[i]));
  }
  return acc;
}

int main(int argc, char **argv) {
  int small = argc > 1 && strcmp(argv[1], "small") == 0;
  printf("%u\n", small ? run(8, 8, 4) : run(512, 512, 512));
  return 0;
}
