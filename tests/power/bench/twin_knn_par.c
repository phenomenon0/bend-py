// The C twin of knn_par.bend: the same 64 shards, run one after another, and
// folded in the same binary tree, so the checksum pins the fork's shape as well
// as its arithmetic -- a shard computed in the wrong place changes the answer.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define SHARDS 64
#define N 2048
#define D 64
#define NQ 128
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

static uint32_t shard(uint32_t s) {
  uint32_t b = s << 20;
  for (uint32_t p = 0; p < (uint32_t)N * D; p++) st[p] = v(b + p);
  for (uint32_t p = 0; p < (uint32_t)NQ * D; p++) qs[p] = v(1073741824u + b + p);
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
