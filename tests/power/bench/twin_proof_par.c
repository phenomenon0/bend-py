// The twin of proof_par.bend: the same checks twin_proof.c does, folded the
// way the fork folds them -- a 2^D tree whose every leaf is one certificate,
// mixed pairwise up the levels. Only the fold shape differs from the
// sequential twin, so this file is the sizes and one include.
#define N 192
#define R 16
#define D 7
#define SPAN 1
#define PAR
#include "twin_proof.c"
