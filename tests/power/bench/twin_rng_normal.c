// The C twin of the rng_normal bench (and, through twin_rng_normal_par.c, of
// the forked one): Threefry2x32-20, Box-Muller on the two words of one block,
// quantised to millionths and summed with u32 wrap. Written from the Random123
// paper's round structure, not from power/rng.bend. clang -O3, single thread.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
typedef uint32_t u32;

static const int ROT[8] = {13, 15, 26, 6, 17, 29, 16, 24};

static void block(u32 k0, u32 k1, u32 c0, u32 c1, u32 *oa, u32 *ob) {
  u32 ks[3] = {k0, k1, k0 ^ k1 ^ 0x1BD11BDAu};
  u32 a = c0 + ks[0], b = c1 + ks[1];
  for (int r = 0; r < 20; r++) {
    a += b;
    int s = ROT[r % 8];
    b = ((b << s) | (b >> (32 - s))) ^ a;
    if (r % 4 == 3) {
      int n = r / 4 + 1;
      a += ks[n % 3];
      b += ks[(n + 1) % 3] + (u32)n;
    }
  }
  *oa = a;
  *ob = b;
}

int main(void) {
  u32 acc = 0;
  for (u32 i = 0; i < 25600000u; i++) {
    u32 a, b;
    block(1, 0, i, 0, &a, &b);
    // (a + 0.5) / 2^32 is never 0, so the log is finite for every counter
    double z = sqrt(-2.0 * log(((double)a + 0.5) / 4294967296.0)) *
               cos(6.283185307179586 * ((double)b / 4294967296.0));
    acc += (u32)((z + 8.0) * 1000000.0 + 0.5);
  }
  printf("%u\n", acc);
  return 0;
}
