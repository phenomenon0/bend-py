// The C twin of assign.bend and assign_par.bend: the same Jonker-Volgenant
// shortest-augmenting-path solve over the same hashed cost matrices, so the
// checksum is a claim about the answer and not about the harness.
//
// Both benches live here because they differ only in how the batch is folded:
// assign is one left fold over B instances, assign_par is a 2^D tree over the
// same B, each leaf folding its own contiguous run. twin_assign_par.c is one
// line that includes this file with PAR set.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define INF 0xFFFFFFFFu
#define BIG 0x80000000u

typedef unsigned u32;

// the sizes, kept here so both twins read the same numbers as the two .bend
// files: N x N cost matrices, B of them, and for the forked one a 2^D tree of
// leaves each folding SPAN instances (D and SPAN come from twin_assign_par.c)
#ifndef N
#define N 192
#endif
#ifndef B
#define B 512
#endif

static u32 h(u32 p) { return ((p + 1) * 2654435761u) ^ (p >> 3); }
static u32 cell(u32 p) { return h(p) >> 26; }  // a cost in 0..63

static u32 rot7(u32 v) { return (v << 7) | (v >> 25); }
static u32 mix(u32 a, u32 x) { return rot7(a * 31u + x); }

// e-maxx's residual form, the one power/assign.bend is a port of: minv holds
// distances less the running potential, so the dual update is one +delta on
// every used column and one -delta on every other.
static u32 solve(const u32 *a, int n, int m, u32 *u, u32 *w, int *p, int *way,
                 u32 *minv, char *used) {
  memset(u, 0, (n + 1) * sizeof *u);
  memset(w, 0, (m + 1) * sizeof *w);
  memset(p, 0, (m + 1) * sizeof *p);
  for (int i = 1; i <= n; i++) {
    p[0] = i;
    int j0 = 0;
    for (int j = 0; j <= m; j++) { minv[j] = INF; used[j] = 0; }
    do {
      used[j0] = 1;
      int i0 = p[j0], j1 = 0;
      u32 delta = INF;
      for (int j = 1; j <= m; j++) {
        if (used[j]) continue;
        u32 cij = a[(size_t)(i0 - 1) * m + (j - 1)];
        u32 cur = cij >= BIG ? INF : cij + w[j] - u[i0];
        if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
        if (minv[j] < delta) { delta = minv[j]; j1 = j; }
      }
      if (delta >= BIG) return INF;  // no augmenting path: infeasible
      for (int j = 0; j <= m; j++) {
        if (used[j]) { u[p[j]] += delta; w[j] += delta; }
        else minv[j] -= delta;
      }
      j0 = j1;
    } while (p[j0] != 0);
    do { int j1 = way[j0]; p[j0] = p[j1]; j0 = j1; } while (j0);
  }
  u32 sum = 0;
  for (int j = 1; j <= m; j++)
    if (p[j]) sum += a[(size_t)(p[j] - 1) * m + (j - 1)];
  return sum;
}

typedef struct { u32 *a, *u, *w, *minv; int *p, *way; char *used; int n; } Work;

static void work_init(Work *k, int n) {
  k->n = n;
  k->a = malloc((size_t)n * n * sizeof(u32));
  k->u = malloc((n + 1) * sizeof(u32));
  k->w = malloc((n + 1) * sizeof(u32));
  k->minv = malloc((n + 1) * sizeof(u32));
  k->p = malloc((n + 1) * sizeof(int));
  k->way = malloc((n + 1) * sizeof(int));
  k->used = malloc(n + 1);
}

// instance b draws its n*n cells from the hash run starting at b << SHIFT, so
// no two instances share a cell as long as n*n <= 1 << SHIFT (n <= 256)
#define SHIFT 16

static u32 one(Work *k, u32 b) {
  int n = k->n;
  u32 base = b << SHIFT;
  for (int t = 0; t < n * n; t++) k->a[t] = cell(base + t);
  return solve(k->a, n, n, k->u, k->w, k->p, k->way, k->minv, k->used);
}

static u32 run(Work *k, u32 lo, u32 hi, u32 acc) {  // a left fold over [lo, hi)
  for (u32 b = lo; b < hi; b++) acc = mix(acc, one(k, b));
  return acc;
}

#ifdef PAR
// the same 2^D tree assign_par.bend forks, evaluated depth-first: each leaf
// folds its own run of SPAN instances from 0, and the levels mix pairwise
static u32 tree(Work *k, int d, u32 s) {
  if (!d) return run(k, s * SPAN, (s + 1) * SPAN, 0);
  u32 a = tree(k, d - 1, s), b = tree(k, d - 1, s + (1u << (d - 1)));
  return mix(a, b);
}
#endif

int main(void) {
  Work k;
  work_init(&k, N);
#ifdef PAR
  printf("%u\n", tree(&k, D, 0));
#else
  printf("%u\n", run(&k, 0, B, 0));
#endif
  return 0;
}
