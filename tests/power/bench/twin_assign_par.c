// The twin of assign_par.bend: the same solves twin_assign.c does, folded the
// way the fork folds them -- a 2^D tree whose every leaf is one instance,
// mixed pairwise up the levels. Only the fold shape differs from the
// sequential twin, so this file is the sizes and one include.
#define N 192
#define D 9
#define SPAN 1
#define PAR
#include "twin_assign.c"
