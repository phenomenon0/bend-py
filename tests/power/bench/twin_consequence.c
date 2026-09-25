// The twin of bench/consequence.bend: the same 2,000,000 readings drawn from the
// same 977 patterns, the same 1..8 trace lengths, the same seeded Murmur3
// finalizer folded left over each trace, the same stable order (digest, then
// reading number) and the same three-column checksum.
//
// This is a C port of the algorithm, not the fixture's oracle -- the oracle is
// consequence_gen.py, which groups with CPython's own dict and never computes
// a digest. Here the digests are reproduced on purpose, so a checksum match
// pins the hash as well as the partition.
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#define N 2000000u
#define SEED 2166136261u

static uint32_t mix(uint32_t x) {
  x ^= x >> 16;
  x *= 2246822507u;
  x ^= x >> 13;
  x *= 3266489909u;
  x ^= x >> 16;
  return x;
}

static uint32_t hash(uint32_t seed, uint32_t x) {
  return mix((x * 2654435761u) ^ (seed * 2246822519u + 3266489917u));
}

static uint32_t pat(uint32_t j) { return j % 977u; }
static uint32_t tlen(uint32_t j) { return (pat(j) & 7u) + 1u; }
static uint32_t act(uint32_t p, uint32_t i) {
  return ((p + 1u) * 2654435761u) ^ (i * 40503u);
}

typedef struct {
  uint32_t key, idx;
} Pair;

// stable by construction: ties fall back on the reading number, which is what
// the Bend side gets from a stable LSD radix sort carrying the index along
static int cmp(const void *a, const void *b) {
  const Pair *x = a, *y = b;
  if (x->key != y->key) return x->key < y->key ? -1 : 1;
  return x->idx < y->idx ? -1 : x->idx > y->idx;
}

int main(void) {
  Pair *p = malloc(sizeof(Pair) * N);
  for (uint32_t j = 0; j < N; j++) {
    uint32_t acc = SEED, n = tlen(j), q = pat(j);
    for (uint32_t i = 0; i < n; i++) acc = hash(acc, act(q, i));
    p[j].key = acc;
    p[j].idx = j;
  }
  qsort(p, N, sizeof(Pair), cmp);

  uint32_t *keys = malloc(sizeof(uint32_t) * N);
  uint32_t *reps = malloc(sizeof(uint32_t) * N);
  uint32_t *cnts = malloc(sizeof(uint32_t) * N);
  uint32_t k = 0, run = 1, key = p[0].key, rep = p[0].idx;
  for (uint32_t i = 1; i < N; i++) {
    if (p[i].key == key) {
      run++;
    } else {
      keys[k] = key, reps[k] = rep, cnts[k] = run, k++;
      key = p[i].key, rep = p[i].idx, run = 1;
    }
  }
  keys[k] = key, reps[k] = rep, cnts[k] = run, k++;

  uint32_t acc = 0;
  for (uint32_t i = 0; i < k; i++) acc = acc * 31u + keys[i];
  for (uint32_t i = 0; i < k; i++) acc = acc * 31u + reps[i];
  for (uint32_t i = 0; i < k; i++) acc = acc * 31u + cnts[i];
  printf("%u\n", acc);

  free(p), free(keys), free(reps), free(cnts);
  return 0;
}
