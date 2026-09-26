// The forked bench's twin is the sequential one: it has to print the same
// number, so it had better be the same program. run.sh looks for twin_<bench>.c
// by name, and the three benches that share a twin by a rule in run.sh (rng,
// topk, budget) are a closed list this one is not on -- so the file exists
// rather than the rule growing.
#include "twin_rng_normal.c"
