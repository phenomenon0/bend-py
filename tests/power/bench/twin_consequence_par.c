// The twin of bench/consequence_par.bend: the same 256 blocks of 8,000
// readings, each collapsed against itself alone, combined up the same balanced
// tree with a * 31 + b. Sequential here -- the twin measures what one core has
// to do, which is what the 1T/C column compares against.
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#define BLOCK 8000u
#define DEPTH 8
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

static int cmp(const void *a, const void *b) {
  const Pair *x = a, *y = b;
  if (x->key != y->key) return x->key < y->key ? -1 : 1;
  return x->idx < y->idx ? -1 : x->idx > y->idx;
}

static Pair *p;
static uint32_t *keys, *reps, *cnts;

static uint32_t block(uint32_t lo) {
  for (uint32_t t = 0; t < BLOCK; t++) {
    uint32_t j = lo + t, acc = SEED, n = tlen(j), q = pat(j);
    for (uint32_t i = 0; i < n; i++) acc = hash(acc, act(q, i));
    p[t].key = acc;
    p[t].idx = t;
  }
  qsort(p, BLOCK, sizeof(Pair), cmp);
  uint32_t k = 0, run = 1, key = p[0].key, rep = p[0].idx;
  for (uint32_t i = 1; i < BLOCK; i++) {
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
  return acc;
}

static uint32_t par(int d, uint32_t lo, uint32_t n) {
  if (d == 0) return block(lo);
  uint32_t h = n >> 1;
  uint32_t a = par(d - 1, lo, h), b = par(d - 1, lo + h, h);
  return a * 31u + b;
}

int main(void) {
  p = malloc(sizeof(Pair) * BLOCK);
  keys = malloc(sizeof(uint32_t) * BLOCK);
  reps = malloc(sizeof(uint32_t) * BLOCK);
  cnts = malloc(sizeof(uint32_t) * BLOCK);
  printf("%u\n", par(DEPTH, 0, BLOCK << DEPTH));
  free(p), free(keys), free(reps), free(cnts);
  return 0;
}
