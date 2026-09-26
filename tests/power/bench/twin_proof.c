// The C twin of proof.bend and proof_par.bend: the same certificates built the
// same way and read by the same four tests in the same order, so the checksum
// is a claim about what the checker accepts and not about the harness.
//
// The order matters here in a way it does not in most twins. Proof.assign
// keeps the FIRST property that fails -- feasibility over every cell, then the
// matching row by row, then the columns nobody holds -- so this file returns
// at the first fault rather than collecting them. The bench's damage is
// single-fault by construction, so the two would agree either way, but a twin
// that disagreed about precedence would be a twin of a different checker.
//
// Both benches live here because they differ only in how the batch is folded:
// proof is one left fold over B instances, proof_par is a 2^D tree over the
// same B. twin_proof_par.c is one line that includes this file with PAR set.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BIG 0x80000000u

typedef unsigned u32;

// the sizes, kept here so both twins read the same numbers as the two .bend
// files: N x N problems, B certificates, each checked R times, against a
// budget of LIMIT units
#ifndef N
#define N 192
#endif
#ifndef B
#define B 128
#endif
#ifndef R
#define R 16
#endif
#define LIMIT 40000u

static u32 h(u32 p) { return ((p + 1) * 2654435761u) ^ (p >> 3); }
static u32 d6(u32 p) { return h(p) >> 26; }  // a value in 0..63

static u32 rot7(u32 v) { return (v << 7) | (v >> 25); }
static u32 mix(u32 a, u32 x) { return rot7(a * 31u + x); }

// the prices, in assign.bend's non-negative column form, and the matched
// column: 97 and N are coprime so i -> 97i+13 mod N is a bijection
static u32 up(u32 base, u32 i) { return 64u + d6(base + i); }
static u32 wp(u32 base, u32 j) { return d6(base + 4096u + j); }
static u32 g(u32 i) { return (97u * i + 13u) % (u32)N; }
static u32 sk(u32 base, u32 i, u32 j, u32 gi) {
  return j == gi ? 0u : 1u + d6(base + 8192u + i * (u32)N + j);
}

// the four tests, in Proof.assign's own order, first fault wins. The codes are
// proof.bend's Bad tags: 2 Range, 3 Dup, 6 Over, 7 Slack.
static u32 check(const u32 *a, const u32 *u, const u32 *w, const u32 *mt, int nr,
                 int nc, char *seen) {
  for (int i = 0; i < nr; i++)
    for (int j = 0; j < nc; j++) {
      u32 c = a[(size_t)i * nc + j];
      if (c < BIG && u[i] > c + w[j]) return 6;  // dual infeasible at a cell
    }
  memset(seen, 0, nc);
  for (int i = 0; i < nr; i++) {
    u32 j = mt[i];
    if (j >= (u32)nc) return 2;
    if (seen[j]) return 3;  // n claims over a range of n is a bijection
    seen[j] = 1;
    if (u[i] != a[(size_t)i * nc + j] + w[j]) return 7;  // not tight
  }
  for (int j = 0; j < nc; j++)
    if (!seen[j] && w[j] != 0) return 7;  // a free column carrying a discount
  return 0;
}

// Done hands back the budget the check did not need; Fail hands back the
// reason, lifted clear of any budget so the two can never collide
static u32 tag(u32 code) {
  return code ? 0xF0000000u + code : LIMIT - ((u32)N * N + N + N);
}

typedef struct { u32 *a, *u, *w, *mt; char *seen; } Work;

static void work_init(Work *k) {
  k->a = malloc((size_t)N * N * sizeof(u32));
  k->u = malloc(N * sizeof(u32));
  k->w = malloc(N * sizeof(u32));
  k->mt = malloc(N * sizeof(u32));
  k->seen = malloc(N);
}

// instance b draws from the hash run at b << SHIFT, in three disjoint stretches
// -- rows, columns, cells -- and the cells end well inside the next instance's
// start as long as N*N + 8192 <= 1 << SHIFT
#define SHIFT 16

// the reps fold into the running acc, exactly as reps() does in the .bend file,
// so this has to thread acc through rather than fold one value an instance
static u32 run(Work *k, u32 lo, u32 hi, u32 acc) {
  for (u32 b = lo; b < hi; b++) {
    u32 base = b << SHIFT, kind = b & 7u;
    for (u32 i = 0; i < N; i++) {
      u32 ui = up(base, i), gi = g(i);
      for (u32 j = 0; j < N; j++) k->a[i * N + j] = ui - wp(base, j) + sk(base, i, j, gi);
      k->u[i] = ui;
      k->mt[i] = gi;
    }
    for (u32 j = 0; j < N; j++) k->w[j] = wp(base, j);
    if (kind == 5) k->a[0] = up(base, 0) - wp(base, 0) - 1u;
    if (kind == 6) k->u[0] = k->u[0] - 1u;
    if (kind == 7) k->mt[0] = N + 1;
    for (int r = 0; r < R; r++)
      acc = mix(acc, tag(check(k->a, k->u, k->w, k->mt, N, N, k->seen)));
  }
  return acc;
}

#ifdef PAR
// the same 2^D tree proof_par.bend forks, evaluated depth-first: each leaf
// folds its own run of SPAN instances from 0, and the levels mix pairwise
static u32 tree(Work *k, int d, u32 s) {
  if (!d) return run(k, s * SPAN, (s + 1) * SPAN, 0);
  u32 a = tree(k, d - 1, s), b = tree(k, d - 1, s + (1u << (d - 1)));
  return mix(a, b);
}
#endif

int main(void) {
  Work k;
  work_init(&k);
#ifdef PAR
  printf("%u\n", tree(&k, D, 0));
#else
  printf("%u\n", run(&k, 0, B, 0));
#endif
  return 0;
}
