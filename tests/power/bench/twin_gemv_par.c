// The C twin of gemv_par.bend: the same 64 row blocks, the same broadcast
// activations, the same row dot product in the same order and the same tree
// fold over the leaf checksums, computed serially. The Bend side's threads are
// the only difference between them, which is the point.
//
// The dot product is left strictly ordered, and the product is its own
// statement, for the reasons twin_gemv.c states.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define M 128
#define K 512
#define STEPS 128

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

static float w[(size_t)M * K];
static float xv[K];
static float y[M];

static float dot(const float *a, const float *b) {
  float s = 0.0f;
  for (int c = 0; c < K; c++) {
    float p = a[c] * b[c];
    s = s + p;
  }
  return s;
}

// shard s owns rows [s * M, (s + 1) * M): its weight hashes start at s << 16
static uint32_t shard(uint32_t s) {
  uint32_t wbase = s << 16;
  for (uint32_t p = 0; p < (uint32_t)(M * K); p++) w[p] = v(wbase + p);
  uint32_t acc = 0;
  for (int t = 0; t < STEPS; t++) {
    uint32_t base = 1073741824u + (uint32_t)(t * K);
    for (int c = 0; c < K; c++) xv[c] = v(base + (uint32_t)c);
    for (int i = 0; i < M; i++) y[i] = dot(&w[(size_t)i * K], xv);
    for (int i = 0; i < M; i++) acc = mix(acc, bits(y[i]));
  }
  return acc;
}

static uint32_t par(int d, uint32_t s) {
  if (d == 0) return shard(s);
  return mix(par(d - 1, s), par(d - 1, s + (1u << (d - 1))));
}

int main(void) {
  printf("%u\n", par(6, 0));
  return 0;
}
