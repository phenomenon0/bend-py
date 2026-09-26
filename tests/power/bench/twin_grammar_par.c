// The twin of bench/grammar_par.bend: 256 shards of 8,192 documents, the 256
// leaf checksums folded up a perfect binary tree. It reproduces the fork's
// shape rather than its threads -- the shards are independent by construction,
// so a serial walk of them must land on the same root, which is what makes the
// row a check on the fork and not only on the state machine.
#define TWIN_GRAMMAR_NO_MAIN
#include "twin_grammar.c"

static uint32_t tmix(uint32_t a, uint32_t b) {
  return ((a + 2654435761u) ^ b) * 16777619u;
}

static uint32_t shard(uint32_t s) {
  uint32_t acc = 0, base = s << 13;
  for (uint32_t i = 0; i < 8192u; i++) acc = one_o(acc, base + i);
  return acc;
}

static uint32_t par(int k, uint32_t s) {
  if (k == 0) return shard(s);
  return tmix(par(k - 1, s), par(k - 1, s + (1u << (k - 1))));
}

int main(void) {
  printf("%u\n", par(8, 0));
  return 0;
}
