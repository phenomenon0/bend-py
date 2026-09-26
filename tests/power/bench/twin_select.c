// The C twin of select.bend: the same clustered grounds, the same fixed-point
// gain summed in the same order, the same ratio key, the same binary min-heap
// order and the same lazy schedule, so the two sides print the same number or
// one of them is wrong.
//
// The checksum folds `left`, the pops each run spent, so this file cannot pass
// by reaching the right set some other way -- it has to make the same
// accept/reinsert/drop decision at every pop that power/select.bend makes.
//
// The heap here is a plain sift-up/sift-down over two parallel arrays rather
// than heap.bend's hole-carrying pair, which is fine and deliberate: the entry
// order is total ((key, val), and val is the candidate index, so there are no
// ties), and every correct min-heap pops a total order in the same sequence.
#include <stdint.h>
#include <stdio.h>

#define N 1024
#define NC 32
#define BUDGET 6000
#define SHARDS 32
#define LIMIT ((uint32_t)N * N + 2u * N + 4u)

static uint32_t h(uint32_t p) { return ((p + 1u) * 2654435761u) ^ (p >> 3); }
static uint32_t mix2(uint32_t a, uint32_t b) { return h((a * 2654435761u) ^ b); }

static uint32_t cl(uint32_t s, uint32_t nc, uint32_t i) {
  return (mix2(s + 17u, i) >> 8) % nc;
}
static uint32_t wt(uint32_t s, uint32_t i) {
  return 1024u + ((mix2(s + 101u, i) >> 7) % 3073u);
}
static uint32_t ct(uint32_t s, uint32_t i) {
  return 1u + ((mix2(s + 211u, i) >> 9) % 12u);
}
static uint32_t sm(uint32_t s, uint32_t nc, uint32_t j, uint32_t i) {
  if (j == i) return 4096u;
  uint32_t g = mix2(s * 7u + j * 65537u, i) >> 5;
  return cl(s, nc, j) == cl(s, nc, i) ? 2600u + g % 1200u : g % 700u;
}

static uint32_t ratio(uint32_t g, uint32_t c) {
  if (g == 0u) return 0u;
  uint32_t m = g < 16777215u ? g : 16777215u;
  uint32_t d = c < 1u ? 1u : c;
  uint32_t r = (m << 8) / d;
  return r < 1u ? 1u : r;
}
static uint32_t keyf(uint32_t r) { return 4294967295u - r; }
static int less(uint32_t k1, uint32_t x1, uint32_t k2, uint32_t x2) {
  return k1 != k2 ? k1 < k2 : x1 < x2;
}

static uint32_t hk[N + 1], hv[N + 1];
static uint32_t hn;

static void hpush(uint32_t k, uint32_t x) {
  uint32_t i = hn++;
  while (i > 0) {
    uint32_t p = (i - 1) / 2;
    if (!less(k, x, hk[p], hv[p])) break;
    hk[i] = hk[p];
    hv[i] = hv[p];
    i = p;
  }
  hk[i] = k;
  hv[i] = x;
}

static void hpop(void) {
  uint32_t k = hk[--hn], x = hv[hn], i = 0;
  if (hn == 0) return;
  for (;;) {
    uint32_t a = 2 * i + 1, b = a + 1, j = a;
    if (a >= hn) break;
    if (b < hn && less(hk[b], hv[b], hk[a], hv[a])) j = b;
    if (!less(hk[j], hv[j], k, x)) break;
    hk[i] = hk[j];
    hv[i] = hv[j];
    i = j;
  }
  hk[i] = k;
  hv[i] = x;
}

static uint32_t sim[(size_t)N * N], val[N], cost[N], cov[N];

static uint32_t gain(uint32_t j) {
  const uint32_t *row = &sim[(size_t)j * N];
  uint32_t acc = 0;
  for (uint32_t i = 0; i < N; i++) {
    uint32_t si = row[i], ci = cov[i];
    acc += (val[i] * (si > ci ? si - ci : 0u)) >> 12;
  }
  return acc;
}

static void cover(uint32_t j) {
  const uint32_t *row = &sim[(size_t)j * N];
  for (uint32_t i = 0; i < N; i++)
    if (row[i] > cov[i]) cov[i] = row[i];
}

static uint32_t rot7(uint32_t v) { return (v << 7) | (v >> 25); }
static uint32_t mixc(uint32_t a, uint32_t x) { return rot7(a * 31u + x); }

// one shard: build the ground from the seed, then the lazy greedy, then the
// counters and every pick in the order it was taken
static uint32_t shard(uint32_t s) {
  for (uint32_t j = 0; j < N; j++)
    for (uint32_t i = 0; i < N; i++) sim[(size_t)j * N + i] = sm(s, NC, j, i);
  for (uint32_t i = 0; i < N; i++) {
    val[i] = wt(s, i);
    cost[i] = ct(s, i);
    cov[i] = 0;
  }

  uint32_t left = LIMIT, room = BUDGET, total = 0, count = 0;
  static uint32_t pi[N], pg[N], pc[N];
  hn = 0;

  for (uint32_t j = 0; j < N; j++) {
    uint32_t c = cost[j] < 1u ? 1u : cost[j];
    hpush(keyf(ratio(gain(j), c)), j);
  }

  for (;;) {
    if (left == 0u || room == 0u || hn == 0u) break;
    uint32_t j = hv[0];
    hpop();
    uint32_t cj = cost[j] < 1u ? 1u : cost[j];
    if (cj > room) {
      left--;
      continue;
    }
    uint32_t g = gain(j), kt = keyf(ratio(g, cj));
    if (hn > 0u && !less(kt, j, hk[0], hv[0])) {
      left--;
      hpush(kt, j);
      continue;
    }
    left--;
    if (g == 0u) break;
    pi[count] = j;
    pg[count] = g;
    pc[count] = cj;
    count++;
    total += g;
    room -= cj;
    cover(j);
  }

  uint32_t acc = 0;
  acc = mixc(acc, left);
  acc = mixc(acc, room);
  acc = mixc(acc, total);
  acc = mixc(acc, count);
  for (uint32_t t = 0; t < count; t++)
    acc = mixc(acc, (pi[t] * 31u + pc[t]) ^ pg[t]);
  return acc;
}

int main(void) {
  uint32_t acc = 0;
  for (uint32_t s = 0; s < SHARDS; s++) acc = mixc(acc, shard(s));
  printf("%u\n", acc);
  return 0;
}
