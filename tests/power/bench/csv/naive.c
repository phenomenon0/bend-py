// The csv bench's C twin: the obvious byte-at-a-time RFC 4180 reader over
// 64 KiB freads, with CPython's line ends (CRLF, CR or LF) and doubled
// quotes, and no budgets or error positions. Prints records, fields and
// content bytes, as read.bend does.
//   cc -O3 -o naive tests/power/bench/csv/naive.c && ./naive FILE
#include <stdio.h>
#include <stdlib.h>

enum { START, PLAIN, QUOTED, QQ, AFTER_CR };

int main(int argc, char **argv) {
  FILE *f = fopen(argc > 1 ? argv[1] : "/tmp/bend-csv-bench.csv", "rb");
  if (!f) { puts("no file"); return 1; }
  static unsigned char buf[65536];
  unsigned long recs = 0, fields = 0, bytes = 0;
  int st = START, open = 0;  // open: a record has begun
  size_t n;
  while ((n = fread(buf, 1, sizeof buf, f)) > 0) {
    for (size_t i = 0; i < n; i++) {
      unsigned char c = buf[i];
      if (st == AFTER_CR) {
        st = START;
        if (c == '\n') continue;
      }
      switch (st) {
      case START:
      case PLAIN:
        if (c == ',') { fields++; open = 1; st = START; }
        else if (c == '\r' || c == '\n') { fields++; recs++; open = 0; st = c == '\r' ? AFTER_CR : START; }
        else if (c == '"' && st == START) { open = 1; st = QUOTED; }
        else { bytes++; open = 1; st = PLAIN; }
        break;
      case QUOTED:
        if (c == '"') st = QQ; else bytes++;
        break;
      case QQ:
        if (c == '"') { bytes++; st = QUOTED; }
        else if (c == ',') { fields++; st = START; }
        else if (c == '\r' || c == '\n') { fields++; recs++; open = 0; st = c == '\r' ? AFTER_CR : START; }
        else { puts("refused"); return 1; }
        break;
      }
    }
  }
  if (st == QUOTED) { puts("refused"); return 1; }
  if (open || st == PLAIN || st == QQ) { fields++; recs++; }
  printf("%lu %lu %lu\n", recs, fields, bytes);
  fclose(f);
  return 0;
}
