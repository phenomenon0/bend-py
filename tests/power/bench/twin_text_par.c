// The twin of bench/text_par.bend: the same 64 chunks of the same corpus, each
// one given the same backward-scanned anchor and the same four-byte tail
// over-read, walked one after another instead of in a tree. It reproduces the
// cut rather than the threads -- the chunks are independent only because of the
// anchor, so a serial walk of them landing on twin_text.c's single-pass number
// is what says the cut is sound.
#define TWIN_TEXT_NO_MAIN
#include "twin_text.c"

#define K 64u
#define CH (N / K)

// the largest offset at or before lo that starts a cluster whatever precedes
// it: 0, or the byte after an LF, which GB4 breaks after unconditionally
static unsigned anchor(unsigned lo) {
  unsigned q = lo;
  for (unsigned n = 0; n < 256u; n++) {
    if (q == 0u) return 0u;
    if (UNIT[(q - 1u) % UL] == 10u) return q;
    q--;
  }
  return 0u;
}

int main(void) {
  unsigned char *b = malloc(CH + 512u);
  if (!b) return 1;
  unsigned sum = 0u, cnt = 0u;
  for (unsigned k = 0; k < K; k++) {
    unsigned lo = k * CH, hi = lo + CH, q = anchor(lo);
    corpus(b, q, hi + 12u);
    scan(b, q, hi + 4u, lo, hi, &sum, &cnt);
  }
  free(b);
  printf("%u\n", mix(sum, cnt));
  return 0;
}
