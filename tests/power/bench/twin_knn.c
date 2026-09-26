// The C twin of knn.bend: the same hash, the same floats, the same squared L2
// in the same order, the same K-greatest rule and the same mixer, so the two
// sides print the same number or one of them is wrong.
//
// The distance loop is left strictly ordered on purpose. Without -ffast-math
// clang will not reassociate a float reduction, so this stays scalar -- which
// is the honest twin of a Bend fold, and a vectorized C would be measuring a
// transform Bend was never asked to make.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define N 65536
#define D 64
#define NQ 64
#define K 10

static uint32_t h(uint32_t p) { return ((p + 1u) * 2654435761u) ^ (p >> 3); }

static float v(uint32_t p) {
  return ((float)(h(p) >> 19) - 4096.0f) / 128.0f;
}

static uint32_t fkey(float x) {
  float y = x + 0.0f;
  uint32_t b;
  memcpy(&b, &y, 4);
  return (b >= 0x80000000u) ? ~b : (b | 0x80000000u);
}

static uint32_t fnear(float x) { return 0xFFFFFFFFu - fkey(x); }

static uint32_t mix(uint32_t a, uint32_t x) {
  uint32_t t = a * 31u + x;
  return (t << 7) | (t >> 25);
}

typedef struct {
  uint32_t k, v;
} ent;

static int less(ent a, ent b) { return a.k != b.k ? a.k < b.k : a.v < b.v; }

// TopK's rule, in a K-entry array kept ascending: an arrival that does not beat
// the worst kept costs one compare and no write
static void offer(ent *hp, int *n, ent e) {
  int i;
  if (*n < K) {
    for (i = *n; i > 0 && less(e, hp[i - 1]); i--) hp[i] = hp[i - 1];
    hp[i] = e;
    (*n)++;
    return;
  }
  if (!less(hp[0], e)) return;
  for (i = 0; i + 1 < K && less(hp[i + 1], e); i++) hp[i] = hp[i + 1];
  hp[i] = e;
}

static float l2(const float *a, const float *b) {
  float s = 0.0f;
  for (int c = 0; c < D; c++) {
    float t = a[c] - b[c];
    s = s + t * t;
  }
  return s;
}

static float st[(size_t)N * D];
static float qs[(size_t)NQ * D];

int main(void) {
  for (uint32_t p = 0; p < (uint32_t)N * D; p++) st[p] = v(p);
  for (uint32_t p = 0; p < (uint32_t)NQ * D; p++) qs[p] = v(1073741824u + p);
  uint32_t acc = 0;
  for (int j = 0; j < NQ; j++) {
    ent hp[K];
    int n = 0;
    for (int i = 0; i < N; i++) {
      ent e = {fnear(l2(&st[(size_t)i * D], &qs[(size_t)j * D])), (uint32_t)i};
      offer(hp, &n, e);
    }
    for (int t = n - 1; t >= 0; t--) acc = mix(acc, hp[t].k ^ hp[t].v);
  }
  printf("%u\n", acc);
  return 0;
}
