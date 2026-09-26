// The C twin of the budget bench (and of budget_par, which prints the same
// checksum because the accounting does not depend on the schedule). Three u32
// meters in an array and a bounds test a charge -- the thing a Budget has to
// cost no more than. clang -O3, single thread.
#include <stdint.h>
#include <stdio.h>
typedef uint32_t u32;

int main(void) {
  u32 m[3] = {0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu};
  int dry = 0;
  for (u32 i = 0; i < 204800000u; i++) {
    u32 k = i % 3, n = (i & 7) + 1;
    // fold keeps the first refusal and still walks the rest of the chain
    if (dry) continue;
    if (n > m[k]) { dry = 1; continue; }
    m[k] -= n;
  }
  printf("%u\n", dry ? 0u : (u32)(m[0] * 31u + m[1] * 7u + m[2]));
  return 0;
}
