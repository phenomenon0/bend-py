// The C twin of the sketch bench: 12,800,000 HyperLogLog updates over 64
// registers, then the same digest. A flat u32[64] and one compare-and-store an
// update -- the floor a persistent Bank is measured against. clang -O3, single
// thread.
#include <stdint.h>
#include <stdio.h>
typedef uint32_t u32;

static u32 mix(u32 x) {
  x ^= x >> 16; x *= 0x85EBCA6Bu;
  x ^= x >> 13; x *= 0xC2B2AE35u;
  return x ^ (x >> 16);
}

static u32 hsh(u32 seed, u32 x) {
  return mix((x * 0x9E3779B1u) ^ (seed * 0x85EBCA77u + 0xC2B2AE3Du));
}

// leading zeros the way sketch.bend counts them: smear, then popcount
static u32 nlz(u32 x) {
  x |= x >> 1; x |= x >> 2; x |= x >> 4; x |= x >> 8; x |= x >> 16;
  return 32u - (u32)__builtin_popcount(x);
}

int main(void) {
  u32 r[64] = {0};
  for (u32 i = 0; i < 12800000u; i++) {
    u32 h = hsh(7u, i);
    u32 j = h & 63u, rho = nlz(h & ~63u) + 1u;
    if (rho > r[j]) r[j] = rho;
  }
  u32 d = 0u * 1000003u + 7u * 31u + 64u;  // the Hll fingerprint's tag
  for (int i = 0; i < 64; i++) d = d * 31u + r[i];
  printf("%u\n", d);
  return 0;
}
