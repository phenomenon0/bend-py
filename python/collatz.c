#include <stdio.h>
#include <stdint.h>

static uint64_t collatz_len(uint64_t n) {
    if (n < 2) return 1;
    if (n % 2 == 0) return 1 + collatz_len(n / 2);
    return 1 + collatz_len(3 * n + 1);
}

int main(void) {
    uint64_t best = 0;
    for (uint64_t i = 1; i < 200000; i++) {
        uint64_t c = collatz_len(i);
        if (c > best) best = c;
    }
    printf("%llu\n", (unsigned long long)best);
    return 0;
}
